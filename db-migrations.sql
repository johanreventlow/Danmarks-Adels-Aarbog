-- =====================================================================
--  Inkrementelle migrationer for den LEVENDE Supabase-base.
--  schema.sql er source of truth; denne fil afstemmer en allerede
--  deployet base op til den. Alt er idempotent (IF NOT EXISTS) — sikkert
--  at køre flere gange. Kør i Supabase -> SQL Editor.
--
--  Baggrund: den levende base kan drifte fra schema.sql (manuelle ALTER'er
--  blev ikke altid anvendt). Se docs/ + memory 'live-base-schema-drift'.
-- =====================================================================

-- ---- 2026-06 (tidligere manuelle tilføjelser, jf. CLAUDE.md §5) ----
ALTER TABLE person        ADD COLUMN IF NOT EXISTS koen      TEXT;
ALTER TABLE family_member ADD COLUMN IF NOT EXISTS konfidens TEXT;
-- (narrative-tabellen: oprettes af schema.sql hvis den mangler)

-- ---- 2026-06-15: gaps fundet ved TNG-analyse (DNA bevidst udeladt) ----

-- #3 Citation: bevar ordret kildeuddrag + citat-dato (TNG citetext/citedate).
ALTER TABLE citation   ADD COLUMN IF NOT EXISTS citat_tekst TEXT;
ALTER TABLE citation   ADD COLUMN IF NOT EXISTS citat_dato  TEXT;

-- #4 Privacy-granularitet: manuel skjulning adskilt fra afledt levende-status.
ALTER TABLE person     ADD COLUMN IF NOT EXISTS privat BOOLEAN DEFAULT FALSE;
ALTER TABLE note       ADD COLUMN IF NOT EXISTS privat BOOLEAN DEFAULT FALSE;
ALTER TABLE narrative  ADD COLUMN IF NOT EXISTS privat BOOLEAN DEFAULT FALSE;

-- #5 (minor) Arkiv-adresse.
ALTER TABLE repository ADD COLUMN IF NOT EXISTS adresse TEXT;

-- 2026-06-15 (normaliserings-pass): koen kontrolleret på DB-niveau (invariant #9).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'person_koen_chk') then
    alter table person add constraint person_koen_chk
      check (koen in ('mand','kvinde','ukendt'));
  end if;
end $$;

-- 2026-06-16: indekser til relations-/evidens-opslag (UI + validering var seq-scan
-- -> statement timeout på self-joins). Idempotent.
CREATE INDEX IF NOT EXISTS ix_fammember_person   ON family_member(person_id);
CREATE INDEX IF NOT EXISTS ix_fammember_family   ON family_member(family_id);
CREATE INDEX IF NOT EXISTS ix_extid_linje_nr     ON person_external_id(linje, nr);
CREATE INDEX IF NOT EXISTS ix_extid_person       ON person_external_id(person_id);
CREATE INDEX IF NOT EXISTS ix_fact_subjekt       ON fact(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_assertion_target   ON assertion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_conclusion_target  ON conclusion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_citation_assertion ON citation(assertion_id);
CREATE INDEX IF NOT EXISTS ix_relation_subjekt   ON relation(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_relation_objekt    ON relation(objekt_type, objekt_id);
CREATE INDEX IF NOT EXISTS ix_narrative_subjekt  ON narrative(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_person_visningnavn ON person(visning_navn);

-- #1 Barn-relationstype: INGEN skemaændring — udvidet vocab på family_member.rolle
--    ('barn' | 'adopteret_barn' | 'plejebarn' | 'stedbarn'). Kun 'barn' tæller
--    som blodslægtskab i finderen.

-- ---- 2026-06-23: SLÆGTSLINJER navngives — trin (a) af lineage-promovering ----
--   Linjer levede kun som bart 'I'..'V'-token på person_external_id.linje.
--   Her får de en entitet med navn. Forward-kompatibel med (b): adling, forgrening,
--   eget våben m.m. tilføjes additivt senere (se schema.sql lineage-kommentar + §5/§9).
CREATE TABLE IF NOT EXISTS lineage (
  id        BIGINT PRIMARY KEY,
  source_id BIGINT REFERENCES source(id),
  kode      TEXT,
  navn      TEXT NOT NULL,
  UNIQUE (source_id, kode)
);
-- RLS slås til ved oprettelse (offentlig anon-read-politik lander i db-rls.sql).
ALTER TABLE lineage ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS ix_lineage_src_kode ON lineage(source_id, kode);

-- Backfill: udled (source_id, kode) fra de faktiske eksterne ID'er (ingen hardcodet
-- source_id). Navn pr. kode fra DAA-stamtavlens linje-overskrifter. Idempotent.
INSERT INTO lineage (id, source_id, kode, navn)
SELECT row_number() OVER (ORDER BY x.source_id, x.kode) AS id,
       x.source_id, x.kode,
       CASE x.kode
         WHEN 'I'   THEN 'Den holstenske linje'
         WHEN 'II'  THEN 'Linjen Gallentin'
         WHEN 'III' THEN 'Den mecklenburgske linje'
         WHEN 'IV'  THEN 'Den lensgrevelige linje af 1767'
         WHEN 'V'   THEN 'Den grevelige linje af 1673'
       END AS navn
FROM (SELECT DISTINCT source_id, linje AS kode
      FROM person_external_id
      WHERE linje IN ('I','II','III','IV','V')) x
ON CONFLICT (source_id, kode) DO NOTHING;

-- ---- 2026-06-26: redaktions-app — auth + staging ----
CREATE TABLE IF NOT EXISTS profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  rolle               TEXT NOT NULL DEFAULT 'medlem' CHECK (rolle IN ('redaktion','medlem')),
  reventlow_person_id BIGINT REFERENCES person(id),
  email               TEXT
);
CREATE TABLE IF NOT EXISTS suggestion (
  id              BIGINT PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  forslagsstiller UUID REFERENCES auth.users(id),
  status          TEXT NOT NULL DEFAULT 'afventer',
  art TEXT, subjekt_type TEXT, subjekt_id BIGINT, felt TEXT, vaerdi TEXT,
  kilde_source_id BIGINT REFERENCES source(id), kilde_fritekst TEXT,
  payload JSONB DEFAULT '{}'::jsonb, note TEXT
);
-- RLS slås til ved oprettelse (deny-all indtil politikker + grants lander i db-rls.sql).
-- Lukker eksponerings-vinduet mellem migration og RLS-kørsel + tilfredsstiller Supabase-linteren.
ALTER TABLE profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE suggestion ENABLE ROW LEVEL SECURITY;

-- ---- 2026-06-26: cache-regenerering af person.visning_* via trigger ----
-- Recompute cache-felter fra personens konklusioner. Læser den VALGTE assertions værdi
-- pr. faktatype. Dato-fakta (fødsel/død) bruger coalesce(date_raw, vaerdi_tekst).
CREATE OR REPLACE FUNCTION regen_person_visning(pid BIGINT)
RETURNS void LANGUAGE sql SET search_path=public AS $$
  UPDATE person p SET
    visning_navn  = sub.navn,
    visning_foedt = sub.foedt,
    visning_doed  = sub.doed,
    visning_titel = sub.titel
  FROM (
    SELECT
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='navn')  AS navn,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='fødsel') AS foedt,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='død')    AS doed,
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='titel') AS titel
    FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    JOIN assertion  a ON a.id = c.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.subjekt_id = pid
  ) sub
  WHERE p.id = pid;
$$;

-- Trigger-wrapper: udled berørt person fra conclusion-rækkens fact-target.
CREATE OR REPLACE FUNCTION trg_regen_from_conclusion()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE pid BIGINT;
BEGIN
  SELECT f.subjekt_id INTO pid FROM fact f
    WHERE f.id = coalesce(NEW.target_id, OLD.target_id)
      AND coalesce(NEW.target_type, OLD.target_type)='fact'
      AND f.subjekt_type='person';
  IF pid IS NOT NULL THEN PERFORM regen_person_visning(pid); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_conclusion_regen ON conclusion;
CREATE TRIGGER trg_conclusion_regen
  AFTER INSERT OR UPDATE OR DELETE ON conclusion
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_conclusion();

-- Edits af den VALGTE assertion ændrer cache-værdien uden at conclusion-rækken røres.
CREATE OR REPLACE FUNCTION trg_regen_from_assertion()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE pid BIGINT;
BEGIN
  SELECT f.subjekt_id INTO pid FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    WHERE c.valgt_assertion_id = NEW.id AND f.subjekt_type='person';
  IF pid IS NOT NULL THEN PERFORM regen_person_visning(pid); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_assertion_regen ON assertion;
CREATE TRIGGER trg_assertion_regen
  AFTER UPDATE ON assertion
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_assertion();

-- ---- 2026-06-26: redaktions-app — rolle-helper + fact-triplet RPC (Task 3) ----

-- Kalderens rolle (default 'medlem' hvis ingen profil). STABLE; bruger auth.uid().
CREATE OR REPLACE FUNCTION current_rolle()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT coalesce((SELECT rolle FROM profiles WHERE id = auth.uid()), 'medlem');
$$;

-- Tilføj/opdater en oplysning på et fact-slot. Find-or-create fact → assertion →
-- citation → upsert conclusion (peg på den nye assertion). Atomisk (én funktion = én txn).
-- PoC: kilde er fritekst (source_id null, teksten i citat_tekst). Proper source-link senere.
-- Note (id-tildeling): basen bruger eksplicitte BIGINT-PK'er (ikke IDENTITY) — derfor `max(id)+1`
-- inde i funktionen. Det er race-følsomt under samtidighed, men acceptabelt i PoC (én redaktør).
-- Migrér til IDENTITY/sekvenser når flerbruger-skrivning aktiveres.
CREATE OR REPLACE FUNCTION red_upsert_fakta(
  p_subjekt_type text, p_subjekt_id bigint, p_faktatype text, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fact bigint; v_assert bigint; v_cit bigint; v_concl bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må skrive fakta (din rolle: %)', current_rolle();
  END IF;
  PERFORM begin_change_set('red_upsert_fakta', format('Opdaterede %s på %s/%s', p_faktatype, p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);

  SELECT id INTO v_fact FROM fact
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND faktatype=p_faktatype
    LIMIT 1;
  IF v_fact IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), p_subjekt_type, p_subjekt_id, p_faktatype)
      RETURNING id INTO v_fact;
  END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;

  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
            'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret',
                  blaastemplet_af='Redaktør', blaastemplet_naar=current_date
    RETURNING id INTO v_concl;

  RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,
                            'citation_id',v_cit,'conclusion_id',v_concl);
END $$;

-- ---- 2026-06-26: Task 4 — redaktions-RPC'er (konklusion-skift + edit/slet) ----

-- "Gør til konklusion": re-peg conclusion for assertionens fact til denne assertion.
CREATE OR REPLACE FUNCTION red_set_konklusion(p_assertion_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_target_type text; v_target_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_konklusion', format('Satte konklusion til oplysning %s', p_assertion_id), NULL, NULL);
  SELECT target_type, target_id INTO v_target_type, v_target_id
    FROM assertion WHERE id = p_assertion_id;
  IF v_target_id IS NULL THEN RAISE EXCEPTION 'Ukendt assertion %', p_assertion_id; END IF;
  -- Cycle 02: upsert frem for UPDATE — et fact m. assertions men ingen conclusion (importeret/
  -- delvist) ville ellers give silent no-op (0 rækker) + falsk success.
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), v_target_type, v_target_id, p_assertion_id,
            'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id = excluded.valgt_assertion_id, blaastemplet_naar = current_date;
END $$;

-- PoC blød redigering: UPDATE assertion direkte (indkapslet — skift til insert-ny senere).
-- 2026-06-30: red_edit_oplysning skifter void -> jsonb (append-baseret, B5/B7)
DROP FUNCTION IF EXISTS red_edit_oplysning(bigint, text, text, text);
CREATE OR REPLACE FUNCTION red_edit_oplysning(
  p_assertion_id bigint, p_vaerdi text, p_date_raw text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_old assertion; v_new bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_edit_oplysning', format('Rettede oplysning %s', p_assertion_id), NULL, NULL);
  SELECT * INTO v_old FROM assertion WHERE id=p_assertion_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Ukendt assertion %', p_assertion_id; END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, date_min, date_max,
                        date_qualifier, date_raw, calendar, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), v_old.target_type, v_old.target_id,
            p_vaerdi, v_old.date_min, v_old.date_max, v_old.date_qualifier,
            coalesce(p_date_raw, v_old.date_raw), v_old.calendar, false)
    RETURNING id INTO v_new;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_new, NULL,
            coalesce(p_kilde_fritekst, '(kilde mangler)'))
    RETURNING id INTO v_cit;

  -- intern re-peg (ikke RPC): kun hvis den gamle påstand var den valgte
  UPDATE conclusion SET valgt_assertion_id=v_new, blaastemplet_naar=current_date
    WHERE target_type=v_old.target_type AND target_id=v_old.target_id
      AND valgt_assertion_id=p_assertion_id;
  IF NOT FOUND THEN
    INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), v_old.target_type, v_old.target_id,
              v_new, 'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id) DO UPDATE SET valgt_assertion_id=v_new, blaastemplet_naar=current_date;
  END IF;

  RETURN jsonb_build_object('ny_assertion_id', v_new, 'citation_id', v_cit);
END $$;

-- PoC blød sletning: DELETE assertion; var den valgt → re-peg konklusion til første
-- tilbageværende oplysning på samme fact (fact-slot bevares).
CREATE OR REPLACE FUNCTION red_slet_oplysning(p_assertion_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_target_type text; v_target_id bigint; v_was_chosen boolean; v_next bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_oplysning', format('Slettede oplysning %s', p_assertion_id), NULL, NULL);
  SELECT target_type, target_id INTO v_target_type, v_target_id
    FROM assertion WHERE id = p_assertion_id;
  IF v_target_id IS NULL THEN RETURN; END IF;
  SELECT (valgt_assertion_id = p_assertion_id) INTO v_was_chosen
    FROM conclusion WHERE target_type=v_target_type AND target_id=v_target_id;
  -- VIGTIGT: slip FK'en (conclusion.valgt_assertion_id -> assertion.id) FØR assertion slettes,
  -- ellers fejler DELETE med conclusion_valgt_assertion_id_fkey. Re-peg til første tilbageværende
  -- oplysning (ekskl. den der slettes); ingen tilbage -> drop conclusion. Fact-slot bevares.
  IF coalesce(v_was_chosen,false) THEN
    SELECT id INTO v_next FROM assertion
      WHERE target_type=v_target_type AND target_id=v_target_id AND id <> p_assertion_id
      ORDER BY id LIMIT 1;
    IF v_next IS NULL THEN
      DELETE FROM conclusion WHERE target_type=v_target_type AND target_id=v_target_id;
    ELSE
      UPDATE conclusion SET valgt_assertion_id=v_next
        WHERE target_type=v_target_type AND target_id=v_target_id;
    END IF;
  END IF;
  DELETE FROM citation  WHERE assertion_id = p_assertion_id;
  DELETE FROM assertion WHERE id = p_assertion_id;
END $$;

-- ---- 2026-06-26: Task 5 — direkte person/narrativ/relation-RPC'er ----

-- Direkte person-koen-sætter
CREATE OR REPLACE FUNCTION red_set_koen(p_person_id bigint, p_koen text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_koen', format('Satte køn på person %s', p_person_id), 'person', p_person_id);
  UPDATE person SET koen = p_koen WHERE id = p_person_id;  -- CHECK håndhæver vokabular
END $$;

-- Direkte person-privat-sætter
CREATE OR REPLACE FUNCTION red_set_privat(p_person_id bigint, p_privat boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_privat', format('Satte privat-flag på person %s', p_person_id), 'person', p_person_id);
  UPDATE person SET privat = p_privat WHERE id = p_person_id;
END $$;

-- Direkte person-sletning (og familje-relationer)
-- Cycle 02 H2: FK-sikker cascade (se schema.sql for begrundelse).
CREATE OR REPLACE FUNCTION red_slet_person(p_person_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_facts bigint[]; v_rels bigint[];
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_person', format('Slettede person %s', p_person_id), 'person', p_person_id);

  SELECT coalesce(array_agg(id),'{}') INTO v_facts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(array_agg(id),'{}') INTO v_rels FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id);

  UPDATE profiles SET reventlow_person_id = NULL WHERE reventlow_person_id = p_person_id;

  DELETE FROM citation WHERE assertion_id IN (
    SELECT id FROM assertion WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                                OR (target_type='relation' AND target_id = ANY(v_rels)));
  DELETE FROM conclusion WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                            OR (target_type='relation' AND target_id = ANY(v_rels));
  DELETE FROM assertion  WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                            OR (target_type='relation' AND target_id = ANY(v_rels));

  DELETE FROM note WHERE (target_type='person'   AND target_id=p_person_id)
                      OR (target_type='fact'     AND target_id = ANY(v_facts))
                      OR (target_type='relation' AND target_id = ANY(v_rels));

  DELETE FROM narrative          WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  DELETE FROM relation           WHERE id = ANY(v_rels);
  DELETE FROM fact               WHERE id = ANY(v_facts);
  DELETE FROM person_external_id WHERE person_id = p_person_id;
  DELETE FROM family_member      WHERE person_id = p_person_id;
  DELETE FROM person             WHERE id = p_person_id;
END $$;

-- Upsert narrativ (find-or-create, opdater tekst)
CREATE OR REPLACE FUNCTION red_upsert_narrativ(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_upsert_narrativ', format('Opdaterede narrativ på %s/%s', p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  SELECT id INTO v_id FROM narrative
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO narrative(id, subjekt_type, subjekt_id, tekst, privat)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM narrative), p_subjekt_type, p_subjekt_id, p_tekst, p_privat)
      RETURNING id INTO v_id;
  ELSE
    UPDATE narrative SET tekst=p_tekst, privat=p_privat WHERE id=v_id;
  END IF;
  RETURN v_id;
END $$;

-- Upsert relation (skaber ny relation direkte)
CREATE OR REPLACE FUNCTION red_relation(
  p_subjekt_type text, p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint,
  p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_rolle = 'samme_som' THEN RAISE EXCEPTION 'Brug red_samme_som til identitets-links'; END IF;
  -- GDPR-invariant ved fødslen (ikke kun i red_upload_media): en 'afbildet'-relation skal gå
  -- person→media, fordi media_afbilder_skjult/privat KUN scanner (subjekt=person, objekt=media).
  -- En person på objekt-siden ville være usynlig for gatingen → fail-open. Luk det for ALLE kaldere.
  IF p_rolle = 'afbildet' AND p_objekt_type = 'person' THEN
    RAISE EXCEPTION 'afbildet skal gå person→media (person kan ikke stå på objekt-siden — GDPR-gating)';
  END IF;
  PERFORM begin_change_set('red_relation', format('Relation %s: %s/%s → %s/%s', p_rolle, p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id), p_subjekt_type, p_subjekt_id);
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
            p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ---- 2026-06-26: Task 6 — medlem-forslag til staging ----

-- Medlem-forslag til staging (all authenticated)
CREATE OR REPLACE FUNCTION red_suggest(
  p_art text, p_subjekt_type text, p_subjekt_id bigint, p_felt text, p_vaerdi text,
  p_kilde_fritekst text DEFAULT NULL, p_payload jsonb DEFAULT '{}'::jsonb, p_note text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Login kræves for forslag'; END IF;
  INSERT INTO suggestion(forslagsstiller, art, subjekt_type, subjekt_id, felt, vaerdi,
                         kilde_fritekst, payload, note)
    VALUES (auth.uid(), p_art, p_subjekt_type, p_subjekt_id, p_felt, p_vaerdi,
            p_kilde_fritekst, coalesce(p_payload,'{}'::jsonb), p_note)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- =====================================================================
-- 2026-06-27: red_konflikt-view, redaktion-read-RLS, slet-preview-RPC
-- =====================================================================

-- Konflikt-kø: ægte kilde-uenighed = >1 DISTINKT værdi INDEN FOR ÉT fact. Grain PR. FACT
-- (ikke pr. person+faktatype): en person kan have flere facts af samme type (fx 6 titler)
-- = legitime distinkte facts, ikke konflikt (bruger-feedback 2026-06-28, fact-kardinalitet).
-- security_invoker=true er KRITISK: ellers kører viewet med ejer-rettigheder og omgår RLS
-- på fact/assertion → ville lække private personers konflikter (spec §5, Codex-review høj).
-- v1: kun 'navn'/'titel' (dato-fakta har typisk tom vaerdi_tekst → udeladt, spec §5).
-- fact_id sidst: CREATE OR REPLACE VIEW kan kun APPEND kolonner (ikke indsætte midt i).
CREATE OR REPLACE VIEW red_konflikt
  WITH (security_invoker = true) AS
SELECT f.subjekt_id AS person_id,
       f.faktatype,
       count(DISTINCT a.vaerdi_tekst) AS antal_vaerdier,
       count(*)                       AS antal_oplysninger,
       f.id         AS fact_id
FROM fact f
JOIN assertion a ON a.target_type = 'fact' AND a.target_id = f.id
WHERE f.subjekt_type = 'person'
  AND f.faktatype IN ('navn','titel')
GROUP BY f.subjekt_id, f.faktatype, f.id
HAVING count(DISTINCT a.vaerdi_tekst) > 1;

-- Read-only forhåndsvisning af hvad red_slet_person ville slette. Spejler RPC'ens
-- relations-logik: personen som subjekt ELLER objekt (spec §7, Codex-review høj).
CREATE OR REPLACE FUNCTION red_slet_person_preview(p_person_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rels jsonb; v_nfacts int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT count(*) INTO v_nfacts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_rels FROM (
    SELECT rolle,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id)
  ) r;
  RETURN jsonb_build_object(
    'antal_relationer', jsonb_array_length(v_rels),
    'antal_facts', v_nfacts,
    'relationer', v_rels);
END $$;

-- 5b) REDAKTION-LAG: rolle=redaktion ser OGSÅ private rækker (ellers skjuler auth_read-laget
-- en netop privat-markeret person for redaktøren selv — spec §8b, Codex-review høj).
-- Additiv: hver tabel har nu (anon_read) + (auth_read ikke-privat) + (redaktion_read alt).
do $$
declare t text;
begin
  foreach t in array array['person','person_external_id','family_member','fact',
                           'relation','narrative','note','assertion','conclusion','citation']
  loop
    execute format('drop policy if exists redaktion_read on public.%I;', t);
    execute format(
      'create policy redaktion_read on public.%I for select to authenticated '
      || 'using ((select public.current_rolle()) = ''redaktion'');', t);
  end loop;
end $$;

-- Konflikt-view: læsbar for authenticated (RLS håndhæves af security_invoker på basistabeller).
grant select on public.red_konflikt to authenticated;
grant select on public.red_konflikt to anon;


-- =====================================================================
-- 2026-06-28: fact-målrettet skrivning (fact-kardinalitet)
--   red_tilfoej_oplysning (operation A: oplysning til eksisterende fact)
--   red_opret_fakta       (operation B: nyt distinkt fact)
-- (Funktionskroppe er source-of-truth i schema.sql; her idempotent gentaget.)
-- =====================================================================

CREATE OR REPLACE FUNCTION red_tilfoej_oplysning(
  p_fact_id bigint, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_tilfoej_oplysning', format('Tilføjede oplysning til fakta %s', p_fact_id), NULL, NULL);
  IF NOT EXISTS (SELECT 1 FROM fact WHERE id = p_fact_id) THEN
    RAISE EXCEPTION 'Fact % findes ikke', p_fact_id;
  END IF;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', p_fact_id, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  RETURN jsonb_build_object('assertion_id', v_assert, 'citation_id', v_cit);
END $$;

CREATE OR REPLACE FUNCTION red_opret_fakta(
  p_subjekt_type text, p_subjekt_id bigint, p_faktatype text, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fact bigint; v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_fakta', format('Oprettede %s på %s/%s', p_faktatype, p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), p_subjekt_type, p_subjekt_id, p_faktatype)
    RETURNING id INTO v_fact;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
            'afklaret', 'Redaktør', current_date);
  RETURN jsonb_build_object('fact_id', v_fact, 'assertion_id', v_assert, 'citation_id', v_cit);
END $$;

grant execute on function public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text) to authenticated;
grant execute on function public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text) to authenticated;

-- 2026-06-28: 2C-2a relation-RPC'er
-- FK-ORDNET slet af en relation + dens evidens (relationer har 955 assertion+conclusion med
-- target_type='relation' UDEN FK → flad DELETE forældreløser dem). Spejler red_slet_person.
-- Delt intern helper (ingen change_set/rolle-gate — kalderen ejer dem, B7). Én kilde til FK-orden
-- for red_slet_relation OG red_fjern_samme_som.
CREATE OR REPLACE FUNCTION _delete_relation_evidence(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $$;

CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_relation', format('Slettede relation %s', p_relation_id), NULL, NULL);
  PERFORM _delete_relation_evidence(p_relation_id);
END $$;

-- Valideret + idempotent tilføj af person↔org/estate-relation (erstatter rå red_relation for UI).
CREATE OR REPLACE FUNCTION red_tilfoej_relation(
  p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint; v_findes boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_tilfoej_relation', format('Relation %s fra person %s', p_rolle, p_subjekt_id), 'person', p_subjekt_id);
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_subjekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_subjekt_id; END IF;
  IF p_objekt_type NOT IN ('organisation','estate') THEN RAISE EXCEPTION 'Ugyldig objekt_type %', p_objekt_type; END IF;
  IF p_objekt_type='organisation' THEN SELECT EXISTS(SELECT 1 FROM organisation WHERE id=p_objekt_id) INTO v_findes;
  ELSE SELECT EXISTS(SELECT 1 FROM estate WHERE id=p_objekt_id) INTO v_findes; END IF;
  IF NOT v_findes THEN RAISE EXCEPTION 'Objekt %/% findes ikke', p_objekt_type, p_objekt_id; END IF;
  SELECT id INTO v_id FROM relation WHERE subjekt_type='person' AND subjekt_id=p_subjekt_id
    AND objekt_type=p_objekt_type AND objekt_id=p_objekt_id AND coalesce(rolle,'')=coalesce(p_rolle,'') LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- 2026-06-29: 2C-2b familie-RPC'er (1/2)
-- Opret partner-union. INGEN auto-dedup (Codex H2): samme par kan gifte sig igen.
-- NB: p_ordinal er UNIONENS sekvensnummer (skrives ens til begge partnere), ikke hver partners
--     individuelle ægteskabstal — per-partner-ordinal er en fremtidig additiv udvidelse (cycle 07 H2).
CREATE OR REPLACE FUNCTION red_opret_union(p_partner_a bigint, p_partner_b bigint, p_type text, p_ordinal int DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fam bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_union', format('Oprettede union (%s) mellem %s og %s', p_type, p_partner_a, p_partner_b), 'person', p_partner_a);
  IF p_partner_a = p_partner_b THEN RAISE EXCEPTION 'Partnere skal være forskellige'; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_partner_a) THEN RAISE EXCEPTION 'Person % findes ikke', p_partner_a; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_partner_b) THEN RAISE EXCEPTION 'Person % findes ikke', p_partner_b; END IF;
  IF p_type NOT IN ('vielse','partnerskab','ugift union') THEN RAISE EXCEPTION 'Ugyldig union-type %', p_type; END IF;
  INSERT INTO family(id, type) VALUES ((SELECT coalesce(max(id),0)+1 FROM family), p_type) RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens) VALUES (v_fam, p_partner_a, 'partner', p_ordinal, NULL);
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens) VALUES (v_fam, p_partner_b, 'partner', p_ordinal, NULL);
  RETURN v_fam;
END $$;

-- Ret konfidens på et eksisterende familie-link.
CREATE OR REPLACE FUNCTION red_set_familie_konfidens(p_family_id bigint, p_person_id bigint, p_rolle text, p_konfidens text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_familie_konfidens', format('Satte konfidens %s på familie-link %s/%s/%s', p_konfidens, p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  UPDATE family_member SET konfidens=p_konfidens
    WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'Familie-link findes ikke (%, %, %)', p_family_id, p_person_id, p_rolle; END IF;
END $$;

-- Slet ÉT familie-link. INGEN family-entitets-sletning (Codex H1): family bærer facts/notes uden FK.
-- Idempotent: no-op (ingen RAISE) hvis triplen ikke findes — tilsigtet, matcher red_slet_relation/red_slet_person
--   (UI sender altid friskt-hentede triples; cycle 07 H4).
CREATE OR REPLACE FUNCTION red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_familie_link', format('Slettede familie-link %s/%s/%s', p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  DELETE FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
END $$;

-- 2026-06-29: 2C-2b familie-RPC'er (2/2)
-- Tilføj barn til en union. Struktur-guards (Codex H3): barn ≠ partner i samme family;
-- ingen ane-cyklus (recursiv CTE: descendants(barn) må ikke indeholde en partner i family).
-- NB: cyklus-tjekket er pre-INSERT uden lås — to samtidige txn'er kan i teorien hver indsætte den anden
--   som barn og tilsammen lukke en cyklus. Accepteret under projektets single-writer-PoC-antagelse
--   (samme klasse som max(id)+1; cycle 07 Codex H1). Advisory-lock = fremtidig hærdning hvis multi-writer.
CREATE OR REPLACE FUNCTION red_tilfoej_barn(p_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn', p_konfidens text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cyklus boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_tilfoej_barn', format('Tilføjede barn %s til familie %s', p_barn_id, p_family_id), 'person', p_barn_id);
  IF NOT EXISTS(SELECT 1 FROM family WHERE id=p_family_id) THEN RAISE EXCEPTION 'Familie % findes ikke', p_family_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_barn_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_barn_id; END IF;
  IF p_rolle NOT IN ('barn','adopteret_barn','plejebarn','stedbarn') THEN RAISE EXCEPTION 'Ugyldig barn-rolle %', p_rolle; END IF;
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle='partner')
    THEN RAISE EXCEPTION 'Person % er partner i familie % — kan ikke også være barn', p_barn_id, p_family_id; END IF;
  -- Cyklus: er en partner i family en efterkommer af barnet?
  WITH RECURSIVE efterkommere(pid) AS (
    SELECT p_barn_id
    UNION
    SELECT b.person_id FROM efterkommere e
      JOIN family_member par ON par.person_id = e.pid AND par.rolle = 'partner'
      JOIN family_member b   ON b.family_id = par.family_id
        AND b.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn')
  )
  SELECT EXISTS(
    SELECT 1 FROM family_member fp
    WHERE fp.family_id = p_family_id AND fp.rolle='partner' AND fp.person_id IN (SELECT pid FROM efterkommere)
  ) INTO v_cyklus;
  IF v_cyklus THEN RAISE EXCEPTION 'Cyklus: barn % er ane til en partner i familie %', p_barn_id, p_family_id; END IF;
  -- Dup-guard (PK): no-op hvis linket allerede findes
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle=p_rolle) THEN RETURN; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_barn_id, p_rolle, NULL, p_konfidens);
END $$;


-- ---- 2026-06-30: lineage trin (b) — forgrening + status (additivt) ----
--   Trin (a) gav linjerne navne. (b) tilføjer to additive kolonner; resten af (b)
--   (adling, medlemskab, eget våben) rider på de polymorfe fact/relation-tabeller og
--   kræver ingen skema-ændring. Ældre rækker får NULL → forward-kompatibelt.
--   Se schema.sql lineage-kommentar + datamodel-oversigt §5/§9.
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS parent_lineage_id BIGINT REFERENCES lineage(id);
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS status TEXT;
CREATE INDEX IF NOT EXISTS ix_lineage_parent ON lineage(parent_lineage_id);

-- ============ OPRET-NY-ENTITET (2026-06-29, hærdet 2026-06-30) ============
-- Komposite SECURITY DEFINER opret-RPC'er. id=max+1 (husstil). privat FORCERET true (cycle-08 GDPR).
-- Gammel 7-arg signatur (m. p_privat) DROPpes; ny 6-arg erstatter.
DROP FUNCTION IF EXISTS public.red_opret_person(text,text,boolean,boolean,text,text,text);
CREATE OR REPLACE FUNCTION red_opret_person(
  p_navn text, p_koen text DEFAULT NULL, p_levende boolean DEFAULT false,
  p_foedt_raw text DEFAULT NULL, p_doed_raw text DEFAULT NULL, p_titel_raw text DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_person', format('Oprettede person %s', p_navn), NULL, NULL);
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  IF p_koen IS NOT NULL AND p_koen NOT IN ('mand','kvinde','ukendt')
    THEN RAISE EXCEPTION 'Ugyldigt køn %', p_koen; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, levende, privat, koen) VALUES (v_id, p_levende, true, p_koen);
  PERFORM red_upsert_fakta('person', v_id, 'navn', p_navn);
  IF nullif(btrim(p_foedt_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'fødsel', p_foedt_raw, p_date_raw => p_foedt_raw);
  END IF;
  IF nullif(btrim(p_doed_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'død', p_doed_raw, p_date_raw => p_doed_raw);
  END IF;
  IF nullif(btrim(p_titel_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'titel', p_titel_raw);
  END IF;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_estate(p_navn text, p_slags text DEFAULT NULL, p_sted_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_estate', format('Oprettede ejendom %s', p_navn), NULL, NULL);
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM estate);
  INSERT INTO estate(id, navn, slags, sted_id) VALUES (v_id, p_navn, p_slags, p_sted_id);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_kilde', format('Oprettede kilde %s', p_titel), NULL, NULL);
  IF nullif(btrim(p_titel),'') IS NULL THEN RAISE EXCEPTION 'Titel er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel, udgave, ekstern) VALUES (v_id, p_slags, p_titel, p_udgave, p_ekstern);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_organisation(p_navn text, p_slags text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_organisation', format('Oprettede organisation %s', p_navn), NULL, NULL);
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM organisation);
  INSERT INTO organisation(id, navn, slags) VALUES (v_id, p_navn, p_slags);
  RETURN v_id;
END $$;

grant execute on function public.red_opret_person(text,text,boolean,text,text,text) to authenticated;
grant execute on function public.red_opret_estate(text,text,bigint) to authenticated;
grant execute on function public.red_opret_kilde(text,text,text,boolean) to authenticated;
grant execute on function public.red_opret_organisation(text,text) to authenticated;


-- =====================================================================
-- 2026-06-30: versionering + hyperlinks (idempotent spejling af schema.sql)
-- =====================================================================

-- 2026-06-30: versionering — PK-registry
CREATE TABLE IF NOT EXISTS version_pk_registry (
  tabel     TEXT PRIMARY KEY,
  pk_cols   TEXT[] NOT NULL,
  skip_cols TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('person',             ARRAY['id'], ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel']),
  ('person_external_id', ARRAY['person_id','source_id'], '{}'),
  ('family',             ARRAY['id'], '{}'),
  ('family_member',      ARRAY['family_id','person_id','rolle'], '{}'),
  ('fact',               ARRAY['id'], '{}'),
  ('relation',           ARRAY['id'], '{}'),
  ('assertion',          ARRAY['id'], '{}'),
  ('conclusion',         ARRAY['id'], '{}'),
  ('citation',           ARRAY['id'], '{}'),
  ('narrative',          ARRAY['id'], '{}'),
  ('note',               ARRAY['id'], '{}'),
  ('source',             ARRAY['id'], '{}'),
  ('repository',         ARRAY['id'], '{}'),
  ('place',              ARRAY['id'], '{}'),
  ('organisation',       ARRAY['id'], '{}'),
  ('estate',             ARRAY['id'], '{}'),
  ('media',              ARRAY['id'], '{}'),
  ('historical_event',   ARRAY['id'], '{}'),
  ('coat_of_arms',       ARRAY['id'], '{}'),
  ('lineage',            ARRAY['id'], '{}'),
  ('vocab',              ARRAY['scheme','code'], '{}'),
  ('profiles',           ARRAY['id'], ARRAY['email','rolle'])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;

-- 2026-06-30: versionering — change_set/change_event
-- ---------- VERSIONERING: change_set / change_event ----------
CREATE TABLE IF NOT EXISTS change_set (
  id                BIGINT PRIMARY KEY,
  actor_id          UUID REFERENCES auth.users(id) ON DELETE SET NULL,  -- frosne felter er autoritative (B3)
  actor_navn        TEXT,
  actor_rolle       TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  operation         TEXT,
  summary           TEXT,
  subjekt_type      TEXT,
  subjekt_id        BIGINT,
  subjekt_synlighed TEXT,                       -- frosset: 'offentlig'|'levende'|'privat' (C1-sti)
  reverterer_id     BIGINT REFERENCES change_set(id)  -- dette saet fortroed hvilket (reversal-kaede; M3)
);

CREATE TABLE IF NOT EXISTS change_event (
  id            BIGINT PRIMARY KEY,
  change_set_id BIGINT NOT NULL REFERENCES change_set(id),
  seq           INT NOT NULL,
  tabel         TEXT NOT NULL,
  row_pk        JSONB NOT NULL,
  op            TEXT NOT NULL CHECK (op IN ('INSERT','UPDATE','DELETE')),
  foer          JSONB,
  efter         JSONB
);

CREATE INDEX IF NOT EXISTS ix_change_event_set  ON change_event(change_set_id, seq);
CREATE INDEX IF NOT EXISTS ix_change_set_subjekt ON change_set(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_change_set_revert  ON change_set(reverterer_id);

-- 2026-06-30: versionering — begin_change_set + _subjekt_synlighed
-- ---------- VERSIONERING: begin_change_set ----------
-- Synligheds-klasse på subjektet, frosset på commit-tid (C1-sti for fremtidig
-- medlems-historik). Kun person har levende/privat; øvrige = 'offentlig'.
CREATE OR REPLACE FUNCTION _subjekt_synlighed(p_type text, p_id bigint)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE
    WHEN p_type='person' THEN (
      SELECT CASE WHEN coalesce(pr.privat,false) THEN 'privat'
                  WHEN coalesce(pr.levende,false) THEN 'levende'
                  ELSE 'offentlig' END
      FROM person pr WHERE pr.id=p_id)
    ELSE 'offentlig' END;
$$;

-- Re-entrant: yderste kald ejer change_set'et; indre kald genbruger det aktive (B7).
CREATE OR REPLACE FUNCTION begin_change_set(
  p_operation text, p_summary text, p_subjekt_type text DEFAULT NULL, p_subjekt_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing text; v_id bigint; v_uid uuid; v_navn text; v_rolle text;
BEGIN
  v_existing := current_setting('app.change_set_id', true);
  IF v_existing IS NOT NULL AND v_existing <> '' THEN
    RETURN v_existing::bigint;  -- genbrug aktivt sæt; opret intet, nulstil intet
  END IF;
  v_uid := auth.uid();
  SELECT coalesce(p.navn, p.email, v_uid::text), p.rolle INTO v_navn, v_rolle
    FROM profiles p WHERE p.id = v_uid;
  v_navn  := coalesce(v_navn, 'ukendt');
  v_rolle := coalesce(v_rolle, 'medlem');
  v_id := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed)
    VALUES (v_id, v_uid, v_navn, v_rolle, p_operation, p_summary,
            p_subjekt_type, p_subjekt_id, _subjekt_synlighed(p_subjekt_type, p_subjekt_id));
  PERFORM set_config('app.change_set_id', v_id::text, true);
  PERFORM set_config('app.change_seq', '0', true);
  RETURN v_id;
END $$;

-- 2026-06-30: versionering — log_change-trigger + tilknytning
-- ---------- VERSIONERING: generisk log_change ----------
-- Byg kanonisk row_pk fra registry'ets pk_cols.
CREATE OR REPLACE FUNCTION _row_pk(p_tabel text, p_row jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT coalesce(jsonb_object_agg(k, p_row->k), '{}'::jsonb)
  FROM version_pk_registry r, unnest(r.pk_cols) k
  WHERE r.tabel = p_tabel;
$$;

CREATE OR REPLACE FUNCTION log_change()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE
  v_cs text; v_seq int; v_skip text[];
  v_foer jsonb; v_efter jsonb; v_old jsonb; v_new jsonb;
BEGIN
  v_cs := current_setting('app.change_set_id', true);
  IF v_cs IS NULL OR v_cs = '' THEN RETURN NULL; END IF;  -- bulk-load-sti: ingen logning

  SELECT skip_cols INTO v_skip FROM version_pk_registry WHERE tabel = TG_TABLE_NAME;
  v_skip := coalesce(v_skip, '{}');

  -- projektion: fjern skip-kolonner (afledt cache; B8)
  v_old := to_jsonb(OLD); v_new := to_jsonb(NEW);  -- serialisér én gang (ingen CSE i PL/pgSQL)
  v_foer  := CASE WHEN TG_OP='INSERT' THEN NULL ELSE (v_old - v_skip) END;
  v_efter := CASE WHEN TG_OP='DELETE' THEN NULL ELSE (v_new - v_skip) END;

  -- no-op-skip: hvis kun skip-kolonner ændrede sig (fx ren cache-regen), log intet
  IF TG_OP='UPDATE' AND v_foer = v_efter THEN RETURN NULL; END IF;

  v_seq := coalesce(nullif(current_setting('app.change_seq', true),''),'0')::int + 1;
  PERFORM set_config('app.change_seq', v_seq::text, true);

  INSERT INTO change_event(id, change_set_id, seq, tabel, row_pk, op, foer, efter)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM change_event),
          v_cs::bigint, v_seq, TG_TABLE_NAME,
          _row_pk(TG_TABLE_NAME, coalesce(v_new, v_old)),
          TG_OP, v_foer, v_efter);
  RETURN NULL;
END $$;

-- Tilknyt log_change-trigger til alle registrerede tabeller (idempotent loop).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tabel FROM version_pk_registry LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_log_%1$s ON %1$I', r.tabel);
    EXECUTE format('CREATE TRIGGER trg_log_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$I '
                || 'FOR EACH ROW EXECUTE FUNCTION log_change()', r.tabel);
  END LOOP;
END $$;

-- 2026-06-30: versionering — restore-hjælpere
-- ---------- VERSIONERING: restore-hjælpere ----------
-- WHERE-klausul fra pk-jsonb med korrekt type-cast pr. kolonne (via udt_name).
CREATE OR REPLACE FUNCTION _version_pk_where(p_tabel text, p_pk jsonb)
RETURNS text LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT string_agg(format('%I = (%L)::%s', c.column_name, p_pk->>c.column_name, c.udt_name), ' AND ')
  FROM version_pk_registry r, unnest(r.pk_cols) k
  JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name=p_tabel AND c.column_name=k
  WHERE r.tabel=p_tabel;
$$;

CREATE OR REPLACE FUNCTION _version_current_row(p_tabel text, p_pk jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE v_skip text[]; v_row jsonb;
BEGIN
  SELECT coalesce(skip_cols,'{}') INTO v_skip FROM version_pk_registry WHERE tabel=p_tabel;
  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk))
    INTO v_row;
  RETURN v_row - v_skip;  -- samme projektion som log_change (NULL - skip = NULL)
END $$;

-- Upsert til nøjagtig snapshot-tilstand. Manglende (skip-)kolonner → NULL (cache regenereres efter).
CREATE OR REPLACE FUNCTION _version_upsert_row(p_tabel text, p_row jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_pk_cols text; v_set text; v_cols text;
BEGIN
  SELECT string_agg(quote_ident(k),',') INTO v_pk_cols
    FROM version_pk_registry r, unnest(r.pk_cols) k WHERE r.tabel=p_tabel;
  -- Kun kolonner i snapshot'et: INSERT lister dem eksplicit (skip_cols får DEFAULT, ikke NULL),
  -- ON CONFLICT opdaterer kun dem (skip_cols bevares). Undgår NOT NULL-crash på fx profiles.rolle
  -- og rul-tilbage af person.visning_*-cache. review09 H2.
  -- Ekskluder desuden GENERATED ALWAYS-kolonner (fx narrative.fts) — Postgres tillader IKKE en
  -- eksplicit værdi for dem i INSERT/UPDATE, uanset skip_cols; de genberegnes automatisk.
  -- Uden dette fejler fortryd hårdt for enhver tabel med en generated-kolonne (fundet ved
  -- manuel Expo-test 2026-07-01, ikke af statisk review).
  SELECT string_agg(quote_ident(key),','), string_agg(format('%I = excluded.%I', key, key), ',')
    INTO v_cols, v_set
    FROM jsonb_object_keys(p_row) AS key
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
      WHERE c.relnamespace = 'public'::regnamespace AND c.relname = p_tabel
        AND a.attname = key AND a.attgenerated = 's'
    );
  EXECUTE format(
    'INSERT INTO %1$I (%2$s) SELECT %2$s FROM jsonb_populate_record(null::%1$I, $1) ON CONFLICT (%3$s) DO UPDATE SET %4$s',
    p_tabel, v_cols, v_pk_cols, v_set) USING p_row;
END $$;

CREATE OR REPLACE FUNCTION _version_delete_row(p_tabel text, p_pk jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  EXECUTE format('DELETE FROM %I WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk));
END $$;

-- 2026-06-30: versionering — red_fortryd_change_set (mention-linjer udkommenteret til T10)
-- ---------- VERSIONERING: restore ----------
CREATE OR REPLACE FUNCTION red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  ev change_event; v_new_cs bigint; v_orig change_set;
  v_cur jsonb; v_pids bigint[] := '{}'; v_narr bigint[] := '{}'; v_notes bigint[] := '{}';
  v_div int := 0; pid bigint; v_forventet jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT * INTO v_orig FROM change_set WHERE id=p_change_set_id;
  IF v_orig.id IS NULL THEN RAISE EXCEPTION 'FEJL: change_set % findes ikke', p_change_set_id; END IF;
  -- allerede reverteret? (reversal-kæde; M3)
  IF EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=p_change_set_id) THEN
    RAISE EXCEPTION 'FEJL: change_set % er allerede fortrudt', p_change_set_id;
  END IF;

  -- åbn reversal-sæt (re-entrant: triggere fanger ikke restore-DML ind under DET, da vi
  -- bevidst NULLER app.change_set_id under selve inverse — se nedenfor). Vi logger restore
  -- som ÉT change_set uden child-events for ikke at dobbelt-logge; reversal-kæden er sporet.
  PERFORM set_config('app.change_set_id','',true);  -- undgå at inverse-DML re-logges
  v_new_cs := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id, actor_id, actor_navn, actor_rolle, operation, summary,
                         subjekt_type, subjekt_id, subjekt_synlighed, reverterer_id)
    VALUES (v_new_cs, auth.uid(),
            coalesce((SELECT coalesce(p.navn, p.email, auth.uid()::text) FROM profiles p WHERE p.id=auth.uid()), 'ukendt'),
            current_rolle(), 'fortryd',
            format('Fortrød: %s', coalesce(v_orig.summary,'(uden tekst)')),
            v_orig.subjekt_type, v_orig.subjekt_id, v_orig.subjekt_synlighed, p_change_set_id);

  -- inverse-apply i OMVENDT seq-orden, alt i denne ene transaktion
  FOR ev IN SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq DESC LOOP
    -- optimistisk verifikation (B9): nuværende tilstand skal matche hvad sættet efterlod
    v_cur := _version_current_row(ev.tabel, ev.row_pk);
    -- B9-divergens for ALLE op-typer (review09 H1): DELETE efterlod række ABSENT (NULL),
    -- INSERT/UPDATE efterlod ev.efter. Lukker blind PK-overskrivning ved DELETE-inverse.
    v_forventet := CASE WHEN ev.op='DELETE' THEN NULL ELSE ev.efter END;
    IF v_cur IS DISTINCT FROM v_forventet THEN
      v_div := v_div + 1;
      IF NOT p_force THEN
        RAISE EXCEPTION 'FEJL: nyere ændring rører %/% — afvist (brug force)', ev.tabel, ev.row_pk;
      END IF;
    END IF;
    -- anvend inverse
    IF ev.op='INSERT' THEN
      PERFORM _version_delete_row(ev.tabel, ev.row_pk);
    ELSE  -- DELETE eller UPDATE: genskab foer-tilstand
      PERFORM _version_upsert_row(ev.tabel, ev.foer);
    END IF;
    -- saml berørte for cache/indeks-regen
    IF ev.tabel='person'    THEN v_pids := v_pids || (ev.row_pk->>'id')::bigint; END IF;
    IF ev.tabel='conclusion' THEN
      SELECT f.subjekt_id INTO pid FROM fact f
        WHERE f.id=(coalesce(ev.foer,ev.efter)->>'target_id')::bigint AND f.subjekt_type='person';
      IF pid IS NOT NULL THEN v_pids := v_pids || pid; END IF;
    END IF;
    IF ev.tabel='narrative' THEN v_narr := v_narr || (ev.row_pk->>'id')::bigint; END IF;
    IF ev.tabel='note'      THEN v_notes := v_notes || (ev.row_pk->>'id')::bigint; END IF;
  END LOOP;

  -- regenerér afledte projektioner ÉN gang (B8 + hyperlinks)
  FOR pid IN SELECT DISTINCT unnest(v_pids) LOOP
    PERFORM regen_person_visning(pid);
  END LOOP;
  -- text_mention regenereres af mention-trigger ved narrativ/note-skrivning (Task 10);
  -- ved restore kalder vi den eksplicit (funktion tilføjes i Task 10):
  PERFORM _regen_mentions_for('narrative', n) FROM unnest(v_narr) n;
  PERFORM _regen_mentions_for('note', n)      FROM unnest(v_notes) n;

  IF v_div > 0 THEN
    UPDATE change_set SET summary = summary || format(' [%s divergenser tvunget]', v_div) WHERE id=v_new_cs;
  END IF;
  RETURN jsonb_build_object('reversal_change_set', v_new_cs, 'divergenser', v_div);
END $$;

-- 2026-06-30: hyperlinks — parse_mentions
-- ---------- HYPERLINKS: token-parser ----------
-- Grammatik (spec §5.1): [[<type>:<id>|<visningstekst>]]
--   type ∈ fast vokabular; id = heltal uden foranstillede nuller; visningstekst vilkårlig
--   (| [ ] escapes som \| \[ \]). Malformet/ukendt type → ignoreres.
CREATE OR REPLACE FUNCTION parse_mentions(p_tekst text)
RETURNS TABLE(maal_type text, maal_id bigint) LANGUAGE sql IMMUTABLE SET search_path=public AS $$
  SELECT m[1] AS maal_type, m[2]::bigint AS maal_id
  FROM regexp_matches(
    coalesce(p_tekst,''),
    -- type-gruppe begrænset til vokabularet; id uden foranstillet nul (0 eller 1-9…)
    '\[\[(person|estate|place|organisation|source|coat_of_arms|family|historical_event|media|lineage):(0|[1-9][0-9]*)\|',
    'g'
  ) AS m;
$$;

-- 2026-06-30: hyperlinks — text_mention + regen-trigger + profiles.navn
-- ---------- HYPERLINKS: text_mention (afledt indeks) ----------
CREATE TABLE IF NOT EXISTS text_mention (
  kilde_type TEXT NOT NULL,            -- 'narrative' | 'note'
  kilde_id   BIGINT NOT NULL,
  maal_type  TEXT NOT NULL,
  maal_id    BIGINT NOT NULL,
  PRIMARY KEY (kilde_type, kilde_id, maal_type, maal_id)
);
CREATE INDEX IF NOT EXISTS ix_text_mention_maal ON text_mention(maal_type, maal_id);

-- Erstat HELE projektionen for én kilde-række (dedup via PK).
CREATE OR REPLACE FUNCTION _regen_mentions_for(p_kilde_type text, p_kilde_id bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_tekst text;
BEGIN
  DELETE FROM text_mention WHERE kilde_type=p_kilde_type AND kilde_id=p_kilde_id;
  IF p_kilde_type='narrative' THEN SELECT tekst INTO v_tekst FROM narrative WHERE id=p_kilde_id;
  ELSIF p_kilde_type='note'   THEN SELECT indhold INTO v_tekst FROM note WHERE id=p_kilde_id; END IF;
  IF v_tekst IS NULL THEN RETURN; END IF;
  INSERT INTO text_mention(kilde_type, kilde_id, maal_type, maal_id)
    SELECT p_kilde_type, p_kilde_id, maal_type, maal_id FROM parse_mentions(v_tekst)
    ON CONFLICT DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION trg_regen_mentions()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_kilde text := TG_TABLE_NAME;  -- 'narrative' | 'note'
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM text_mention WHERE kilde_type=v_kilde AND kilde_id=OLD.id;
  ELSE
    PERFORM _regen_mentions_for(v_kilde, NEW.id);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_mentions_narrative ON narrative;
CREATE TRIGGER trg_mentions_narrative AFTER INSERT OR UPDATE OR DELETE ON narrative
  FOR EACH ROW EXECUTE FUNCTION trg_regen_mentions();
DROP TRIGGER IF EXISTS trg_mentions_note ON note;
CREATE TRIGGER trg_mentions_note AFTER INSERT OR UPDATE OR DELETE ON note
  FOR EACH ROW EXECUTE FUNCTION trg_regen_mentions();

-- profiles.navn (kilde til frosset actor_navn; spec §6)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS navn TEXT;

-- 2026-06-30: versionering — historik-API + døde-links-view
-- ---------- VERSIONERING: redaktion-only historik-API (B10) ----------
CREATE OR REPLACE FUNCTION hist_for_subjekt(p_type text, p_id bigint)
RETURNS SETOF change_set LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_set
    WHERE subjekt_type=p_type AND subjekt_id=p_id ORDER BY created_at DESC;
END $$;

CREATE OR REPLACE FUNCTION hist_events(p_change_set_id bigint)
RETURNS SETOF change_event LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq;
END $$;

-- Døde links: mentions hvis mål ikke længere findes (kun person/estate/lineage vist; udvid efter behov).
CREATE OR REPLACE VIEW red_doede_links WITH (security_invoker = true) AS
SELECT m.* FROM text_mention m
WHERE (m.maal_type='person' AND NOT EXISTS (SELECT 1 FROM person  p WHERE p.id=m.maal_id))
   OR (m.maal_type='estate' AND NOT EXISTS (SELECT 1 FROM estate  e WHERE e.id=m.maal_id))
   OR (m.maal_type='lineage' AND NOT EXISTS (SELECT 1 FROM lineage l WHERE l.id=m.maal_id));

-- 2026-07-02: søskende-rækkefølge (ordinal på familie-links) + flyt barn mellem forhold
-- (brugerfund: forkert mor/far-par tilskrevet et barn kan i dag kun rettes ved en manuel
-- to-trins-omvej på tværs af to profiler). Testet mod prod via BEGIN/ROLLBACK-sandkasse
-- (ordinal-sæt, ugyldigt-link-fejl, atomisk flyt m. bevaret konfidens, samme-fra/til-fejl,
-- ét change_set/to change_events, red_fortryd_change_set gendanner korrekt) før anvendt.
CREATE OR REPLACE FUNCTION red_set_familie_ordinal(p_family_id bigint, p_person_id bigint, p_rolle text, p_ordinal int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_familie_ordinal', format('Satte ordinal %s på familie-link %s/%s/%s', p_ordinal, p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  UPDATE family_member SET ordinal=p_ordinal
    WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'Familie-link findes ikke (%, %, %)', p_family_id, p_person_id, p_rolle; END IF;
END $$;

CREATE OR REPLACE FUNCTION red_flyt_barn(p_fra_family_id bigint, p_til_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_konfidens text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_flyt_barn', format('Flyttede barn %s fra familie %s til familie %s', p_barn_id, p_fra_family_id, p_til_family_id), 'person', p_barn_id);
  IF p_fra_family_id = p_til_family_id THEN RAISE EXCEPTION 'Fra- og til-familie er ens'; END IF;
  SELECT konfidens INTO v_konfidens FROM family_member
    WHERE family_id=p_fra_family_id AND person_id=p_barn_id AND rolle=p_rolle;
  IF NOT FOUND THEN RAISE EXCEPTION 'Barn-link findes ikke (family %, person %, rolle %)', p_fra_family_id, p_barn_id, p_rolle; END IF;
  PERFORM red_tilfoej_barn(p_til_family_id, p_barn_id, p_rolle, v_konfidens);
  PERFORM red_slet_familie_link(p_fra_family_id, p_barn_id, p_rolle);
END $$;

grant execute on function public.red_set_familie_ordinal(bigint, bigint, text, int) to authenticated;
grant execute on function public.red_flyt_barn(bigint, bigint, bigint, text) to authenticated;

-- ============================================================================
-- 2026-07-02: Redaktionel identitets-sammenkædning (samme_som). Spec 2026-07-02.
-- Invariant håndhæves i trigger (gælder ALLE insert-veje). Idempotent.
-- ============================================================================
CREATE OR REPLACE FUNCTION enforce_samme_som_invariants() RETURNS trigger
LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.rolle <> 'samme_som' OR NEW.subjekt_type <> 'person' OR NEW.objekt_type <> 'person' THEN
    RETURN NEW;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NEW.subjekt_id = NEW.objekt_id THEN
    RAISE EXCEPTION 'samme_som: kan ikke linke en person til sig selv';
  END IF;
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND subjekt_id = NEW.subjekt_id AND objekt_id <> NEW.objekt_id) THEN
    RAISE EXCEPTION 'samme_som: person % er allerede alias for en anden (ville give multi-sink)', NEW.subjekt_id;
  END IF;
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND objekt_id = NEW.subjekt_id) THEN
    RAISE EXCEPTION 'samme_som: person % er allerede kanonisk for andre — skift retning via fjern+genopret', NEW.subjekt_id;
  END IF;
  -- G3+G4 håndhæver invarianten fuldt (cyklus umulig: kræver at alias er et objekt, hvilket G4 afviser).
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_enforce_samme_som ON relation;
CREATE TRIGGER trg_enforce_samme_som BEFORE INSERT ON relation
  FOR EACH ROW WHEN (NEW.rolle = 'samme_som') EXECUTE FUNCTION enforce_samme_som_invariants();

CREATE OR REPLACE FUNCTION red_samme_som(p_alias_id bigint, p_objekt_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_alias_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_alias_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_objekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_objekt_id; END IF;
  SELECT id INTO v_rel FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=p_alias_id AND objekt_id=p_objekt_id LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  PERFORM begin_change_set('red_samme_som',
    format('Markerede person %s som samme som %s', p_alias_id, p_objekt_id), 'person', p_objekt_id);
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_alias_id, 'person', p_objekt_id, 'samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'relation', v_rel, 'samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'relation', v_rel, v_ass, 'afklaret',
            'redaktionel identitetssammenkædning');
  RETURN v_rel;
END $$;

CREATE OR REPLACE FUNCTION red_fjern_samme_som(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=p_relation_id AND rolle='samme_som'
                AND subjekt_type='person' AND objekt_type='person') THEN
    RAISE EXCEPTION 'Relation % er ikke et person→person samme_som-link', p_relation_id;
  END IF;
  PERFORM begin_change_set('red_fjern_samme_som', format('Fjernede samme_som-link %s', p_relation_id), NULL, NULL);
  PERFORM _delete_relation_evidence(p_relation_id);
END $$;

GRANT EXECUTE ON FUNCTION public.red_samme_som(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.red_fjern_samme_som(bigint) TO authenticated;

-- ============================================================================
-- FLERE NARRATIVER PR. PERSON (udgave-nøglede narrativer) — 2026-07-03
-- Spec: docs/superpowers/specs/2026-07-03-flere-narrativer-per-person-design.md
-- ============================================================================

-- ---------- source.aar (udgave-kronologi) + red_opret_kilde(p_aar) ----------
ALTER TABLE source ADD COLUMN IF NOT EXISTS aar SMALLINT;
UPDATE source SET aar=2018 WHERE id=1 AND aar IS NULL;   -- backfill eksisterende DAA 2018-20-udgave

DROP FUNCTION IF EXISTS red_opret_kilde(text, text, text, boolean);   -- gammel 4-arg → undgå PostgREST-overload
CREATE OR REPLACE FUNCTION red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false, p_aar smallint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_kilde', format('Oprettede kilde %s', p_titel), NULL, NULL);
  IF nullif(btrim(p_titel),'') IS NULL THEN RAISE EXCEPTION 'Titel er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel, udgave, aar, ekstern) VALUES (v_id, p_slags, p_titel, p_udgave, p_aar, p_ekstern);
  RETURN v_id;
END $$;

-- ---------- red_upsert_narrativ nøglet på (subjekt_type, subjekt_id, source_id) ----------
DROP FUNCTION IF EXISTS red_upsert_narrativ(text, bigint, text, boolean);   -- gammel 4-arg → undgå overload
CREATE OR REPLACE FUNCTION red_upsert_narrativ(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean,
  p_source_id bigint, p_side text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_upsert_narrativ', format('Opdaterede narrativ på %s/%s (kilde %s)', p_subjekt_type, p_subjekt_id, p_source_id), p_subjekt_type, p_subjekt_id);
  SELECT id INTO v_id FROM narrative
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND source_id IS NOT DISTINCT FROM p_source_id
    ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO narrative(id, subjekt_type, subjekt_id, source_id, tekst, side, privat)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM narrative), p_subjekt_type, p_subjekt_id, p_source_id, p_tekst, p_side, p_privat)
      RETURNING id INTO v_id;
  ELSE
    UPDATE narrative SET tekst=p_tekst, privat=p_privat, side=COALESCE(p_side, side) WHERE id=v_id;
  END IF;
  RETURN v_id;
END $$;

-- 2026-07-03: udledt slægtsnavn — nye kolonner (spec docs/superpowers/specs/2026-07-03-udledt-slaegtsnavn-design.md)
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS slaegtsnavn TEXT;
ALTER TABLE person  ADD COLUMN IF NOT EXISTS visning_efternavn  TEXT;
ALTER TABLE person  ADD COLUMN IF NOT EXISTS visning_fuldt_navn TEXT;

UPDATE version_pk_registry
  SET skip_cols = (SELECT array_agg(DISTINCT c) FROM unnest(skip_cols || ARRAY['visning_efternavn','visning_fuldt_navn']) c)
  WHERE tabel = 'person';

-- 2026-07-03: udledt slægtsnavn — cyklus-sikre lineage-graf-walkers + BEFORE-cyklus-vagt
CREATE OR REPLACE FUNCTION lineage_ancestors(p_lineage_id BIGINT)
RETURNS BIGINT[] LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE
  v_path BIGINT[] := ARRAY[]::BIGINT[];
  v_current BIGINT := p_lineage_id;
BEGIN
  WHILE v_current IS NOT NULL LOOP
    IF v_current = ANY(v_path) THEN
      RAISE EXCEPTION 'lineage_ancestors: cyklus detekteret ved lineage-id %', v_current;
    END IF;
    IF array_length(v_path,1) IS NOT NULL AND array_length(v_path,1) > 50 THEN
      RAISE EXCEPTION 'lineage_ancestors: dybde-grænse (50) overskredet fra lineage-id %', p_lineage_id;
    END IF;
    v_path := v_path || v_current;
    SELECT parent_lineage_id INTO v_current FROM lineage WHERE id = v_current;
  END LOOP;
  RETURN v_path;
END $$;

CREATE OR REPLACE FUNCTION lineage_descendants(p_lineage_id BIGINT)
RETURNS SETOF BIGINT LANGUAGE plpgsql STABLE SET search_path=public AS $$
DECLARE
  v_visited BIGINT[] := ARRAY[]::BIGINT[];
  v_queue BIGINT[] := ARRAY[p_lineage_id];
  v_current BIGINT; v_child BIGINT;
BEGIN
  WHILE array_length(v_queue,1) IS NOT NULL LOOP
    v_current := v_queue[1];
    v_queue := v_queue[2:array_length(v_queue,1)];
    IF v_current = ANY(v_visited) THEN
      RAISE EXCEPTION 'lineage_descendants: cyklus/gen-besøg detekteret ved lineage-id %', v_current;
    END IF;
    IF array_length(v_visited,1) IS NOT NULL AND array_length(v_visited,1) > 500 THEN
      RAISE EXCEPTION 'lineage_descendants: dybde-grænse (500) overskredet fra lineage-id %', p_lineage_id;
    END IF;
    v_visited := v_visited || v_current;
    RETURN NEXT v_current;
    FOR v_child IN SELECT id FROM lineage WHERE parent_lineage_id = v_current LOOP
      v_queue := v_queue || v_child;
    END LOOP;
  END LOOP;
  RETURN;
END $$;

CREATE OR REPLACE FUNCTION trg_lineage_prevent_cycle()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.parent_lineage_id IS NOT NULL AND NEW.id = ANY(lineage_ancestors(NEW.parent_lineage_id)) THEN
    RAISE EXCEPTION 'lineage: parent_lineage_id-tildeling ville skabe en cyklus (lineage % → %)', NEW.id, NEW.parent_lineage_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_cycle_guard ON lineage;
CREATE TRIGGER trg_lineage_cycle_guard
  BEFORE INSERT OR UPDATE OF parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_lineage_prevent_cycle();

CREATE OR REPLACE FUNCTION lineage_effective_slaegtsnavn(p_lineage_id BIGINT)
RETURNS TEXT LANGUAGE sql STABLE SET search_path=public AS $$
  SELECT l.slaegtsnavn
  FROM unnest(lineage_ancestors(p_lineage_id)) WITH ORDINALITY AS anc(id, ord)
  JOIN lineage l ON l.id = anc.id
  WHERE l.slaegtsnavn IS NOT NULL
  ORDER BY anc.ord
  LIMIT 1;
$$;

-- 2026-07-03: udledt slægtsnavn — normalisering + suffiks-token-match (spec §4.6)
CREATE OR REPLACE FUNCTION slaegtsnavn_normaliser(s TEXT)
RETURNS TEXT[] LANGUAGE sql IMMUTABLE SET search_path=public AS $$
  SELECT regexp_split_to_array(
    trim(regexp_replace(regexp_replace(lower(s), '[‐‑–]', '-', 'g'), '\s+', ' ', 'g')),
    '\s+'
  );
$$;

CREATE OR REPLACE FUNCTION slaegtsnavn_suffiks_match(navn TEXT, slaegtsnavn TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE n_tokens TEXT[]; s_tokens TEXT[]; n_len INT; s_len INT;
BEGIN
  IF navn IS NULL OR slaegtsnavn IS NULL THEN RETURN FALSE; END IF;
  n_tokens := slaegtsnavn_normaliser(navn);
  s_tokens := slaegtsnavn_normaliser(slaegtsnavn);
  n_len := coalesce(array_length(n_tokens,1),0);
  s_len := coalesce(array_length(s_tokens,1),0);
  IF s_len = 0 OR n_len < s_len THEN RETURN FALSE; END IF;
  RETURN n_tokens[n_len - s_len + 1 : n_len] = s_tokens;
END $$;

CREATE TABLE IF NOT EXISTS slaegtsnavn_karantaene (
  person_id  BIGINT PRIMARY KEY REFERENCES person(id),
  n_distinct INT NOT NULL,
  noteret_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2026-07-03: udledt slægtsnavn — regen_person_visning-udvidelse (§4.5) + invalidation-triggere (§4.7)
CREATE OR REPLACE FUNCTION regen_person_visning(pid BIGINT)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_n_distinct INT;
BEGIN
  WITH navn_agg AS (
    SELECT
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='navn')  AS navn,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='fødsel') AS foedt,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='død')    AS doed,
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='titel') AS titel
    FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    JOIN assertion  a ON a.id = c.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.subjekt_id = pid
  ),
  efternavn_cte AS (
    SELECT pei.person_id,
           count(DISTINCT lineage_effective_slaegtsnavn(l.id)) AS n_distinct,
           min(lineage_effective_slaegtsnavn(l.id))            AS slaegtsnavn
    FROM person_external_id pei
    JOIN lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
    WHERE pei.person_id = pid
    GROUP BY pei.person_id
  ),
  final AS (
    SELECT
      navn_agg.navn, navn_agg.foedt, navn_agg.doed, navn_agg.titel,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(efternavn_cte.n_distinct,0) <> 1 THEN NULL
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, efternavn_cte.slaegtsnavn) THEN NULL
        ELSE efternavn_cte.slaegtsnavn
      END AS efternavn,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(efternavn_cte.n_distinct,0) <> 1 THEN navn_agg.navn
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, efternavn_cte.slaegtsnavn) THEN navn_agg.navn
        ELSE navn_agg.navn || ' ' || efternavn_cte.slaegtsnavn
      END AS fuldt
    FROM navn_agg LEFT JOIN efternavn_cte ON true
  )
  UPDATE person p SET
    visning_navn = final.navn, visning_foedt = final.foedt, visning_doed = final.doed,
    visning_titel = final.titel, visning_efternavn = final.efternavn, visning_fuldt_navn = final.fuldt
  FROM final
  WHERE p.id = pid
    AND (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_efternavn, p.visning_fuldt_navn)
        IS DISTINCT FROM (final.navn, final.foedt, final.doed, final.titel, final.efternavn, final.fuldt);

  SELECT count(DISTINCT lineage_effective_slaegtsnavn(l.id)) INTO v_n_distinct
  FROM person_external_id pei JOIN lineage l ON l.source_id=pei.source_id AND l.kode=pei.linje
  WHERE pei.person_id = pid;

  IF v_n_distinct > 1 THEN
    INSERT INTO slaegtsnavn_karantaene(person_id, n_distinct) VALUES (pid, v_n_distinct)
      ON CONFLICT (person_id) DO UPDATE SET n_distinct=excluded.n_distinct, noteret_at=now();
  ELSE
    DELETE FROM slaegtsnavn_karantaene WHERE person_id = pid;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION trg_regen_from_external_id()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') THEN PERFORM regen_person_visning(NEW.person_id); END IF;
  IF TG_OP IN ('DELETE','UPDATE') THEN PERFORM regen_person_visning(OLD.person_id); END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_external_id_regen ON person_external_id;
CREATE TRIGGER trg_external_id_regen
  AFTER INSERT OR UPDATE OR DELETE ON person_external_id
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_external_id();

CREATE OR REPLACE FUNCTION trg_regen_from_lineage()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_lid BIGINT; v_pid BIGINT;
BEGIN
  IF (NEW.slaegtsnavn IS DISTINCT FROM OLD.slaegtsnavn) OR (NEW.parent_lineage_id IS DISTINCT FROM OLD.parent_lineage_id) THEN
    FOR v_lid IN SELECT * FROM lineage_descendants(NEW.id) LOOP
      FOR v_pid IN
        SELECT DISTINCT pei.person_id FROM person_external_id pei
        JOIN lineage l ON l.source_id=pei.source_id AND l.kode=pei.linje
        WHERE l.id = v_lid
      LOOP
        PERFORM regen_person_visning(v_pid);
      END LOOP;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_regen ON lineage;
CREATE TRIGGER trg_lineage_regen
  AFTER UPDATE OF slaegtsnavn, parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_lineage();

-- 2026-07-03: udledt slægtsnavn — review 19 dual-review-fund (H1 + H2)
-- H1: trg_lineage_regen fyrede kun på UPDATE. En frisk --force-reset-genindlæsning opretter
-- lineage-rækkerne FØRSTE gang via INSERT (post_load_fixup.R) → triggeren fyrede aldrig →
-- alle medlemmers visning_efternavn/visning_fuldt_navn forblev stille NULL. OLD findes ikke ved
-- INSERT — TG_OP tjekkes derfor FØRST.
CREATE OR REPLACE FUNCTION trg_regen_from_lineage()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_lid BIGINT; v_pid BIGINT;
BEGIN
  IF TG_OP = 'INSERT' OR (NEW.slaegtsnavn IS DISTINCT FROM OLD.slaegtsnavn) OR (NEW.parent_lineage_id IS DISTINCT FROM OLD.parent_lineage_id) THEN
    FOR v_lid IN SELECT * FROM lineage_descendants(NEW.id) LOOP
      FOR v_pid IN
        SELECT DISTINCT pei.person_id FROM person_external_id pei
        JOIN lineage l ON l.source_id=pei.source_id AND l.kode=pei.linje
        WHERE l.id = v_lid
      LOOP
        PERFORM regen_person_visning(v_pid);
      END LOOP;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_lineage_regen ON lineage;
CREATE TRIGGER trg_lineage_regen
  AFTER INSERT OR UPDATE OF slaegtsnavn, parent_lineage_id ON lineage
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_lineage();

-- H2: slaegtsnavn_karantaene.person_id har ingen ON DELETE CASCADE (bevidst — deny-all intern
-- log). red_slet_person sletter fra alle andre evidens-/link-tabeller men rørte aldrig karantæne-
-- tabellen → FK-violation ved sletning af en person med >1 distinkt effektivt efternavn (fan-out).
CREATE OR REPLACE FUNCTION red_slet_person(p_person_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_facts bigint[]; v_rels bigint[];
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_person', format('Slettede person %s', p_person_id), 'person', p_person_id);

  SELECT coalesce(array_agg(id),'{}') INTO v_facts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(array_agg(id),'{}') INTO v_rels FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id);

  UPDATE profiles SET reventlow_person_id = NULL WHERE reventlow_person_id = p_person_id;

  DELETE FROM citation WHERE assertion_id IN (
    SELECT id FROM assertion WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                                OR (target_type='relation' AND target_id = ANY(v_rels)));
  DELETE FROM conclusion WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                            OR (target_type='relation' AND target_id = ANY(v_rels));
  DELETE FROM assertion  WHERE (target_type='fact'     AND target_id = ANY(v_facts))
                            OR (target_type='relation' AND target_id = ANY(v_rels));

  DELETE FROM note WHERE (target_type='person'   AND target_id=p_person_id)
                      OR (target_type='fact'     AND target_id = ANY(v_facts))
                      OR (target_type='relation' AND target_id = ANY(v_rels));

  DELETE FROM narrative          WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  DELETE FROM relation           WHERE id = ANY(v_rels);
  DELETE FROM fact               WHERE id = ANY(v_facts);
  DELETE FROM person_external_id WHERE person_id = p_person_id;
  DELETE FROM family_member      WHERE person_id = p_person_id;
  DELETE FROM slaegtsnavn_karantaene WHERE person_id = p_person_id;
  DELETE FROM person             WHERE id = p_person_id;
END $$;

-- 2026-07-03: udledt slægtsnavn — /simplify-fund (review 19): fjern dobbelt beregning af
-- lineage-efternavn-fan-out i regen_person_visning (var 2 kald + 2 join-scans, nu 1 af hver via
-- LATERAL, genbrugt i BÅDE UPDATE'ets CASE-logik og karantæne-tjekket).
CREATE OR REPLACE FUNCTION regen_person_visning(pid BIGINT)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_n_distinct INT; v_slaegtsnavn TEXT;
BEGIN
  SELECT count(DISTINCT sn.v), min(sn.v) INTO v_n_distinct, v_slaegtsnavn
  FROM person_external_id pei
  JOIN lineage l ON l.source_id = pei.source_id AND l.kode = pei.linje
  CROSS JOIN LATERAL (SELECT lineage_effective_slaegtsnavn(l.id) AS v) sn
  WHERE pei.person_id = pid;

  WITH navn_agg AS (
    SELECT
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='navn')  AS navn,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='fødsel') AS foedt,
      max(coalesce(a.date_raw,a.vaerdi_tekst)) FILTER (WHERE f.faktatype='død')    AS doed,
      max(a.vaerdi_tekst) FILTER (WHERE f.faktatype='titel') AS titel
    FROM fact f
    JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
    JOIN assertion  a ON a.id = c.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.subjekt_id = pid
  ),
  final AS (
    SELECT
      navn_agg.navn, navn_agg.foedt, navn_agg.doed, navn_agg.titel,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(v_n_distinct,0) <> 1 THEN NULL
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, v_slaegtsnavn) THEN NULL
        ELSE v_slaegtsnavn
      END AS efternavn,
      CASE
        WHEN navn_agg.navn IS NULL THEN NULL
        WHEN coalesce(v_n_distinct,0) <> 1 THEN navn_agg.navn
        WHEN slaegtsnavn_suffiks_match(navn_agg.navn, v_slaegtsnavn) THEN navn_agg.navn
        ELSE navn_agg.navn || ' ' || v_slaegtsnavn
      END AS fuldt
    FROM navn_agg
  )
  UPDATE person p SET
    visning_navn = final.navn, visning_foedt = final.foedt, visning_doed = final.doed,
    visning_titel = final.titel, visning_efternavn = final.efternavn, visning_fuldt_navn = final.fuldt
  FROM final
  WHERE p.id = pid
    AND (p.visning_navn, p.visning_foedt, p.visning_doed, p.visning_titel, p.visning_efternavn, p.visning_fuldt_navn)
        IS DISTINCT FROM (final.navn, final.foedt, final.doed, final.titel, final.efternavn, final.fuldt);

  IF v_n_distinct > 1 THEN
    INSERT INTO slaegtsnavn_karantaene(person_id, n_distinct) VALUES (pid, v_n_distinct)
      ON CONFLICT (person_id) DO UPDATE SET n_distinct=excluded.n_distinct, noteret_at=now();
  ELSE
    DELETE FROM slaegtsnavn_karantaene WHERE person_id = pid;
  END IF;
END $$;

-- =====================================================================
--  2026-07-04: MEDIEHÅNDTERING Slice 0 — storage-metadata + rettigheds-gating
--  Skema-delta (kolonner + RPC'er). RLS-helpers/-politikker + storage.objects
--  ligger i db-rls.sql (kør den efter denne). Verify: db-verify.sql Task 12.
-- =====================================================================

-- Fysisk byte-metadata (bytes har intet andet hjem; semantik forbliver relation/fact).
ALTER TABLE media ADD COLUMN IF NOT EXISTS bucket           TEXT NOT NULL DEFAULT 'media';
ALTER TABLE media ADD COLUMN IF NOT EXISTS storage_path     TEXT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS mime_type        TEXT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS byte_size        BIGINT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS bredde           INT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS hoejde           INT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS sha256           TEXT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS original_filnavn TEXT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS upload_status    TEXT NOT NULL DEFAULT 'kladde';
-- Publikations-gating (rettigheder, fail-closed kontrol-kolonne som person.privat).
ALTER TABLE media ADD COLUMN IF NOT EXISTS maa_publiceres     BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE media ADD COLUMN IF NOT EXISTS rettigheder_status TEXT NOT NULL DEFAULT 'ukendt';

CREATE UNIQUE INDEX IF NOT EXISTS media_storage_path_uidx ON media (bucket, storage_path) WHERE storage_path IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_sha256_uidx       ON media (sha256)               WHERE sha256 IS NOT NULL;

-- RPC'er (spejl af schema.sql; se dér for kommentarer). CREATE OR REPLACE → idempotent.
CREATE OR REPLACE FUNCTION red_opret_media(
  p_slags text, p_titel text DEFAULT NULL, p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL,
  p_bucket text DEFAULT 'media', p_storage_path text DEFAULT NULL,
  p_mime text DEFAULT NULL, p_byte_size bigint DEFAULT NULL,
  p_bredde int DEFAULT NULL, p_hoejde int DEFAULT NULL,
  p_sha256 text DEFAULT NULL, p_original_filnavn text DEFAULT NULL,
  p_rettigheder_status text DEFAULT 'ukendt', p_maa_publiceres boolean DEFAULT false
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_media', format('Oprettede media %s', coalesce(p_titel,p_original_filnavn,'?')), 'media', NULL);
  IF nullif(btrim(p_slags),'') IS NULL THEN RAISE EXCEPTION 'Slags er påkrævet'; END IF;
  -- sha256-dedup: samme bytes må kun registreres som ÉN media-række (genbrug den frem for at
  -- oprette en dublet). Domæne-fejl frem for rå unique_violation (media_sha256_uidx).
  IF p_sha256 IS NOT NULL AND EXISTS (SELECT 1 FROM media WHERE sha256 = p_sha256) THEN
    RAISE EXCEPTION 'Medie med samme indhold findes allerede (sha256=%). Genbrug den eksisterende media-række via red_relation.', p_sha256;
  END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id, slags, titel, kunstner, datering, bucket, storage_path,
                    mime_type, byte_size, bredde, hoejde, sha256, original_filnavn,
                    upload_status, rettigheder_status, maa_publiceres)
    VALUES (v_id, p_slags, p_titel, p_kunstner, p_datering, coalesce(p_bucket,'media'), p_storage_path,
            p_mime, p_byte_size, p_bredde, p_hoejde, p_sha256, p_original_filnavn,
            'kladde', coalesce(p_rettigheder_status,'ukendt'), coalesce(p_maa_publiceres,false));
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_bekraeft_media_upload(
  p_media_id bigint, p_byte_size bigint DEFAULT NULL, p_sha256 text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_bekraeft_media_upload', format('Bekræftede upload af media %s', p_media_id), 'media', p_media_id);
  -- upload_status<>'fjernet'-guard (Slice 0h /simplify-fund): et forsinket/gentaget bekræft-kald må
  -- aldrig genoplive en blødt-slettet række til 'klar' igen.
  UPDATE media SET upload_status='klar',
                   byte_size=coalesce(p_byte_size, byte_size),
                   sha256=coalesce(p_sha256, sha256)
   WHERE id=p_media_id AND upload_status <> 'fjernet';
END $$;

CREATE OR REPLACE FUNCTION red_upload_media(
  p_slags text, p_titel text, p_storage_path text, p_mime text,
  p_afbildet_person_id bigint DEFAULT NULL,
  p_objekt_type text DEFAULT NULL, p_objekt_id bigint DEFAULT NULL,
  p_byte_size bigint DEFAULT NULL, p_bredde int DEFAULT NULL, p_hoejde int DEFAULT NULL,
  p_sha256 text DEFAULT NULL, p_original_filnavn text DEFAULT NULL,
  p_rettigheder_status text DEFAULT 'ukendt', p_maa_publiceres boolean DEFAULT false
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_media bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_upload_media', format('Uploadede media %s', coalesce(p_titel,p_original_filnavn,'?')), 'media', NULL);
  v_media := red_opret_media(p_slags, p_titel, NULL, NULL, 'media', p_storage_path,
                             p_mime, p_byte_size, p_bredde, p_hoejde, p_sha256,
                             p_original_filnavn, p_rettigheder_status, p_maa_publiceres);
  IF p_afbildet_person_id IS NOT NULL THEN
    PERFORM red_relation('person', p_afbildet_person_id, 'media', v_media, 'afbildet');
  END IF;
  IF p_objekt_type IS NOT NULL AND p_objekt_id IS NOT NULL THEN
    -- GDPR-guard: person-afbildning SKAL gå person→media (den retning media_afbilder_skjult/privat
    -- scanner). Objekt-grenen laver media→objekt og ville ellers omgå gatingen for en person.
    IF p_objekt_type = 'person' THEN
      RAISE EXCEPTION 'Brug p_afbildet_person_id til personer (GDPR-gating kræver person→media-retning)';
    END IF;
    PERFORM red_relation('media', v_media, p_objekt_type, p_objekt_id, 'afbildet');
  END IF;
  RETURN v_media;
END $$;

CREATE OR REPLACE FUNCTION red_set_media_rettigheder(
  p_media_id bigint, p_status text, p_maa_publiceres boolean,
  p_licens text DEFAULT NULL, p_kildehenvisning text DEFAULT NULL,
  p_gengivelsestilladelse text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_set_media_rettigheder', format('Rettigheder for media %s → %s', p_media_id, p_status), 'media', p_media_id);
  UPDATE media SET rettigheder_status=coalesce(p_status, rettigheder_status),
                   maa_publiceres=coalesce(p_maa_publiceres, maa_publiceres)
   WHERE id=p_media_id;
  -- Rig rettigheds-dokumentation som facts (kun de udfyldte). Én løkke frem for tre ens IF-blokke.
  PERFORM red_upsert_fakta('media', p_media_id, r.felt, r.val, p_kilde_fritekst => p_kilde_fritekst)
    FROM (VALUES ('licens', p_licens), ('kildehenvisning', p_kildehenvisning),
                 ('gengivelsestilladelse', p_gengivelsestilladelse)) AS r(felt, val)
    WHERE nullif(btrim(r.val),'') IS NOT NULL;
END $$;

-- Slice 0h: "slet billede" som blødt fjern — upload_status='fjernet' udelukker mediet fra
-- media_rettigheder_ok (kræver 'klar') og dermed al anon/auth-synlighed uden ny RLS-politik.
-- Storage-bytes røres ikke (protect_delete-triggeren kommer aldrig i spil), og media har allerede
-- trg_log_media — ændringen er gratis fortrydbar via den eksisterende redaktionelle historik.
CREATE OR REPLACE FUNCTION red_fjern_media(p_media_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_fjern_media', format('Fjernede media %s', p_media_id), 'media', p_media_id);
  UPDATE media SET upload_status = 'fjernet' WHERE id = p_media_id;
END $$;

-- 2026-07-05: generations-reparation — slægtled + kuld på person_external_id (design-spec 2026-07-05).
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS slaegtled_lokal  INTEGER;
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS slaegtled_gennem INTEGER;
ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS kuld             TEXT;

-- Trigger-hærdning: generations-/kuld-UPDATE må IKKE udløse regen_person_visning (påvirker ikke visning_*).
DROP TRIGGER IF EXISTS trg_external_id_regen ON person_external_id;
CREATE TRIGGER trg_external_id_regen
  AFTER INSERT OR DELETE OR UPDATE OF person_id, source_id, linje, nr ON person_external_id
  FOR EACH ROW EXECUTE FUNCTION trg_regen_from_external_id();

-- =====================================================================
-- 2026-07-09: "forældre ukendt"-markering (docs/reviews/25-generationer-ukendt-forbindelse-analyse.md)
-- INGEN skema-ændring: markeringen er et fact (faktatype 'forældre_ukendt') på personen med
-- assertion (grad = vaerdi_tekst) + citation (proveniens) + afklaret conclusion — skrives via den
-- eksisterende red_opret_fakta-RPC. Her seedes kun det kontrollerede vokabular (invariant 9), så
-- "samme slags"-forespørgsler er pålidelige. Idempotent.
--   Grad-værdier (vaerdi_tekst på assertionen):
--     'forælder ukendt'            — en forælder FINDES, men er ukendt for os (vis mulige forældre)
--     'ingen forbindelse angivet'  — bogen forbinder slet ikke personen opad (vis blot forrige slægtled)
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype', 'forældre_ukendt', 'Forældre ukendt (kilden angiver ingen forbindelse opad)'),
  ('forældre_ukendt_grad', 'forælder ukendt', 'Forælder findes, men er ukendt for os'),
  ('forældre_ukendt_grad', 'ingen forbindelse angivet', 'Bogen forbinder ikke personen opad')
ON CONFLICT (scheme, code) DO NOTHING;

-- =====================================================================
-- 2026-07-11: "Fjern markering" retter fejl (review 26/Codex HIGH 2)
-- Fjern-knappen kaldte tidligere red_slet_oplysning, som re-peger konklusionen til den ældste
-- tilbageværende påstand → efter Markér→Opdatér→Fjern genoplivedes den oprindelige markering i
-- stedet for at forsvinde. Ny retract-RPC sætter konklusionen 'tilbagetrukket' (læse-gates
-- kræver 'afklaret'). Append-sikkert, fortrydbart. Idempotent (CREATE OR REPLACE).
CREATE OR REPLACE FUNCTION red_tilbagetraek_fakta(p_fact_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Fail-closed FØR change_set åbnes (review 27/Codex MEDIUM): intet at tilbagetrække → ærlig fejl
  -- frem for tomt change_set + falsk succes.
  IF NOT EXISTS (SELECT 1 FROM conclusion
                 WHERE target_type='fact' AND target_id=p_fact_id AND status='afklaret') THEN
    RAISE EXCEPTION 'Ingen aktiv markering at tilbagetrække på fakta %', p_fact_id;
  END IF;
  PERFORM begin_change_set('red_tilbagetraek_fakta', format('Tilbagetrak markering på fakta %s', p_fact_id), NULL, NULL);
  UPDATE conclusion SET status='tilbagetrukket', blaastemplet_naar=current_date
    WHERE target_type='fact' AND target_id=p_fact_id AND status='afklaret';
END $$;
