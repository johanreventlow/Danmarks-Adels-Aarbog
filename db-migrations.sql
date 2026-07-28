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

/* Deferred until the Task 1 journal/table block below has created its dependencies.
-- 2026-07-26: person_ocr_kvalitetsark_rettelse
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION private.ocr_importeret(p_felt text,p_vaerdi text,p_raw text,p_min date,p_max date,p_qualifier text,p_calendar text,p_certainty text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT CASE WHEN p_felt IN ('foedsel','doed') THEN jsonb_build_object('raw',p_raw,'min',p_min::text,'max',p_max::text,'qualifier',p_qualifier,'calendar',coalesce(p_calendar,'gregoriansk'),'certainty',p_certainty) ELSE jsonb_build_object('value',p_vaerdi) END
$$;
CREATE OR REPLACE FUNCTION private.ocr_fingerprint(p_import_key text,p_record_key text,p_felt text,p_importeret jsonb,p_ocr_context text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT public.ocr_input_fingerprint(p_import_key,p_record_key,p_felt,p_importeret,p_ocr_context)
$$;
REVOKE ALL ON FUNCTION private.ocr_importeret(text,text,text,date,date,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.ocr_fingerprint(text,text,text,jsonb,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION red_ret_ocr_felt(p_person_id bigint,p_import_key text,p_record_key text,p_felt text,p_input_fingerprint text,p_korrigeret jsonb,p_status text DEFAULT 'rettet',p_actor_navn text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_source_id bigint; v_anchor_person bigint; v_anchor_count integer; v_person_anchor_count integer;
  v_assertion_id bigint; v_candidate_count integer; v_context text; v_observed jsonb;
  v_journal import_korrektion%ROWTYPE; v_importeret jsonb; v_fingerprint text;
  v_actor_id uuid := auth.uid(); v_actor_navn text; v_result jsonb; v_min date; v_max date;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'OCR_ROLE_FORBIDDEN'; END IF;
  IF p_felt NOT IN ('navn','foedsel','doed','koen') THEN RAISE EXCEPTION 'OCR_FIELD_INVALID'; END IF;
  IF p_status NOT IN ('rettet','godkendt','udskudt') OR (p_status='rettet' AND p_korrigeret IS NULL) OR (p_status<>'rettet' AND p_korrigeret IS NOT NULL) THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
  SELECT count(*),min(pei.person_id),min(s.id) INTO v_anchor_count,v_anchor_person,v_source_id FROM source s JOIN person_external_id pei ON pei.source_id=s.id WHERE s.import_key=p_import_key AND pei.record_key=p_record_key;
  IF v_anchor_count <> 1 THEN RAISE EXCEPTION 'OCR_IMPORT_ANCHOR_AMBIGUOUS'; END IF;
  IF v_anchor_person <> p_person_id THEN RAISE EXCEPTION 'OCR_PERSON_NOT_FOUND'; END IF;
  SELECT count(*) INTO v_person_anchor_count FROM person_external_id pei JOIN source s ON s.id=pei.source_id WHERE pei.person_id=p_person_id AND s.import_key IS NOT NULL AND pei.record_key IS NOT NULL;
  IF v_person_anchor_count <> 1 THEN RAISE EXCEPTION 'OCR_IMPORT_ANCHOR_AMBIGUOUS'; END IF;
  PERFORM 1 FROM person WHERE id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'OCR_PERSON_NOT_FOUND'; END IF;
  IF p_felt='koen' THEN
    SELECT private.ocr_importeret('koen',koen,NULL,NULL,NULL,NULL,NULL,NULL) INTO v_observed FROM person WHERE id=p_person_id; v_context := NULL;
  ELSE
    WITH candidates AS (SELECT DISTINCT a.id FROM fact f JOIN conclusion cn ON cn.target_type='fact' AND cn.target_id=f.id JOIN assertion a ON a.id=cn.valgt_assertion_id JOIN citation c ON c.assertion_id=a.id AND c.source_id=v_source_id WHERE f.subjekt_type='person' AND f.subjekt_id=p_person_id AND cn.status='afklaret' AND f.faktatype=CASE p_felt WHEN 'navn' THEN 'navn' WHEN 'foedsel' THEN 'fødsel' ELSE 'død' END) SELECT count(*),min(id) INTO v_candidate_count,v_assertion_id FROM candidates;
    IF v_candidate_count <> 1 THEN RAISE EXCEPTION 'OCR_ASSERTION_AMBIGUOUS'; END IF;
    SELECT private.ocr_importeret(p_felt,a.vaerdi_tekst,a.date_raw,a.date_min,a.date_max,a.date_qualifier,a.calendar,a.date_certainty),c.citat_tekst INTO v_observed,v_context FROM assertion a JOIN citation c ON c.assertion_id=a.id AND c.source_id=v_source_id WHERE a.id=v_assertion_id ORDER BY c.id LIMIT 1 FOR UPDATE OF a;
    IF NOT FOUND THEN RAISE EXCEPTION 'OCR_ASSERTION_AMBIGUOUS'; END IF;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws(chr(31),p_import_key,p_record_key,p_felt),0));
  SELECT * INTO v_journal FROM import_korrektion WHERE import_key=p_import_key AND record_key=p_record_key AND felt=p_felt FOR UPDATE;
  v_importeret := coalesce(v_journal.importeret,v_observed); v_fingerprint := private.ocr_fingerprint(p_import_key,p_record_key,p_felt,v_importeret,v_context);
  IF p_input_fingerprint IS DISTINCT FROM v_fingerprint THEN RAISE EXCEPTION 'OCR_FINGERPRINT_STALE'; END IF;
  IF p_status='rettet' THEN
    IF jsonb_typeof(p_korrigeret) <> 'object' THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
    IF p_felt='navn' AND (jsonb_typeof(p_korrigeret->'value') <> 'string' OR nullif(btrim(p_korrigeret->>'value'),'') IS NULL) THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
    IF p_felt='koen' AND p_korrigeret->>'value' NOT IN ('mand','kvinde','ukendt') THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
    IF p_felt IN ('foedsel','doed') THEN
      IF jsonb_typeof(p_korrigeret->'raw') <> 'string' OR nullif(btrim(p_korrigeret->>'raw'),'') IS NULL THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
      BEGIN v_min := NULLIF(p_korrigeret->>'min','')::date; v_max := NULLIF(p_korrigeret->>'max','')::date; EXCEPTION WHEN others THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END;
    END IF;
  END IF;
  SELECT coalesce(pr.navn,pr.email,p_actor_navn,v_actor_id::text,'ukendt') INTO v_actor_navn FROM profiles pr WHERE pr.id=v_actor_id;
  v_actor_navn := coalesce(v_actor_navn,p_actor_navn,'ukendt');
  PERFORM begin_change_set('red_ret_ocr_felt',format('OCR-%s: %s/%s',p_felt,p_import_key,p_record_key),'person',p_person_id);
  IF p_status='rettet' THEN
    IF p_felt='navn' THEN UPDATE assertion SET vaerdi_tekst=p_korrigeret->>'value' WHERE id=v_assertion_id;
    ELSIF p_felt='koen' THEN UPDATE person SET koen=p_korrigeret->>'value' WHERE id=p_person_id;
    ELSE UPDATE assertion SET date_raw=p_korrigeret->>'raw',date_min=v_min,date_max=v_max,date_qualifier=p_korrigeret->>'qualifier',calendar=coalesce(p_korrigeret->>'calendar','gregoriansk'),date_certainty=p_korrigeret->>'certainty' WHERE id=v_assertion_id; END IF;
  END IF;
  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,korrigeret,status,actor_id,actor_navn) VALUES (p_import_key,p_record_key,p_felt,v_fingerprint,v_importeret,CASE WHEN p_status='rettet' THEN p_korrigeret ELSE NULL END,p_status,v_actor_id,v_actor_navn)
  ON CONFLICT (import_key,record_key,felt) DO UPDATE SET input_fingerprint=excluded.input_fingerprint,korrigeret=excluded.korrigeret,status=excluded.status,actor_id=excluded.actor_id,actor_navn=excluded.actor_navn,opdateret_at=now();
  SELECT to_jsonb(g) INTO v_result FROM red_person_grid() g WHERE g.person_id=p_person_id; RETURN v_result;
END $$;
*/

/* Deferred with the Task 4 block below.
CREATE OR REPLACE FUNCTION red_ocr_historik(p_import_key text,p_record_key text,p_felt text)
RETURNS TABLE(change_set_id bigint,changed_at timestamptz,actor_navn text,operation text,foer jsonb,efter jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_journal_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'OCR_ROLE_FORBIDDEN'; END IF;
  SELECT id INTO v_journal_id FROM import_korrektion WHERE import_key=p_import_key AND record_key=p_record_key AND felt=p_felt;
  IF v_journal_id IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT cs.id,cs.created_at,cs.actor_navn,cs.operation,ce.foer,ce.efter FROM change_event ce JOIN change_set cs ON cs.id=ce.change_set_id WHERE ce.tabel='import_korrektion' AND ce.row_pk->>'id'=v_journal_id::text ORDER BY cs.created_at DESC,cs.id DESC,ce.seq DESC;
END $$;
*/

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
  IF (SELECT f.faktatype FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact' WHERE a.id=p_assertion_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Forældrefamilie-slottets konklusion vælges kun via red_vaelg_foraeldre (bevarer projektion/invariant P1)';
  END IF;
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
  IF (SELECT f.faktatype FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact' WHERE a.id=p_assertion_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Forældrefamilie-slottets påstande redigeres ikke (uforanderlige) — brug red_tilfoej_foraeldre_paastand';
  END IF;
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
  IF (SELECT f.faktatype FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact' WHERE a.id=p_assertion_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Forældrefamilie-slottets påstande slettes ikke (uforanderlige) — skift kanonisk valg med red_vaelg_foraeldre';
  END IF;
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

  -- Fælles skriveorden med OCR-rettelsen: source/external-id → person → evidens.
  PERFORM 1 FROM source s JOIN person_external_id pei ON pei.source_id=s.id
    WHERE pei.person_id=p_person_id ORDER BY s.id,pei.source_id FOR UPDATE OF s,pei;
  PERFORM 1 FROM person WHERE id=p_person_id FOR UPDATE;

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
  -- Gate (sikkerheds-hærdning): SECURITY DEFINER-helper kaldes kun fra gatede red_*-funktioner, men
  -- Supabases default-grants ville ellers eksponere den for anon via PostgREST → uatoriseret sletning
  -- af relations-evidens (kører som ejer, omgår RLS). Gratis her (kalderne er allerede redaktion).
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion (intern relations-slet-helper)'; END IF;
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

-- Genskab snapshot-tilstand: opdatér eksisterende række uden at røre skip-kolonner;
-- ved en slettet række bruges INSERT, hvor manglende kolonner får deres DEFAULT.
CREATE OR REPLACE FUNCTION _version_upsert_row(p_tabel text, p_row jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_pk_cols text; v_set text; v_cols text; v_exists boolean;
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
  -- En UPDATE-fortrydelse har stadig målrækken. Gå direkte til UPDATE, så Postgres ikke
  -- validerer en kunstig, ufuldstændig INSERT-række mod NOT NULL før ON CONFLICT (haendelse
  -- logger bevidst kun id+feed_status; alle regenererbare kolonner er skip_cols).
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE %s)',
                 p_tabel, _version_pk_where(p_tabel, _row_pk(p_tabel, p_row))) INTO v_exists;
  IF v_exists THEN
    EXECUTE format(
      'UPDATE %1$I SET (%2$s) = (SELECT %2$s FROM jsonb_populate_record(null::%1$I, $1)) WHERE %3$s',
      p_tabel, v_cols, _version_pk_where(p_tabel, _row_pk(p_tabel, p_row))) USING p_row;
    RETURN;
  END IF;
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

-- 2026-07-24: batchet historik-API til flere subjekter
CREATE OR REPLACE FUNCTION hist_for_subjekter(p_type text, p_ids bigint[])
RETURNS SETOF change_set LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY SELECT * FROM change_set
    WHERE subjekt_type=p_type AND subjekt_id = ANY(p_ids) ORDER BY created_at DESC;
END $$;

-- 2026-07-24: ét batchet kald til tværudgave-match-datasættet
CREATE OR REPLACE FUNCTION red_match_personer()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE result jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT jsonb_build_object(
    'persons', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'visning_navn', visning_navn, 'visning_fuldt_navn', visning_fuldt_navn,
      'koen', koen, 'staged', staged
    )) FROM person), '[]'::jsonb),
    'facts', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'subjekt_id', subjekt_id, 'faktatype', faktatype
    )) FROM fact
      WHERE subjekt_type='person' AND faktatype IN ('fødsel','død','titel')), '[]'::jsonb),
    'concs', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'target_id', target_id, 'valgt_assertion_id', valgt_assertion_id
    )) FROM conclusion
      WHERE target_type='fact' AND status='afklaret'), '[]'::jsonb),
    'assertions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', id, 'date_min', date_min, 'date_max', date_max, 'vaerdi_tekst', vaerdi_tekst
    )) FROM assertion WHERE target_type='fact'), '[]'::jsonb),
    'extIds', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'person_id', person_id, 'source_id', source_id, 'linje', linje, 'nr', nr,
      'slaegtled_lokal', slaegtled_lokal, 'slaegtled_gennem', slaegtled_gennem, 'kuld', kuld
    )) FROM person_external_id), '[]'::jsonb)
  ) INTO result;
  RETURN result;
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

  -- Fælles skriveorden med OCR-rettelsen: source/external-id → person → evidens.
  PERFORM 1 FROM source s JOIN person_external_id pei ON pei.source_id=s.id
    WHERE pei.person_id=p_person_id ORDER BY s.id,pei.source_id FOR UPDATE OF s,pei;
  PERFORM 1 FROM person WHERE id=p_person_id FOR UPDATE;

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

-- =====================================================================
-- 2026-07-05: billedstørrelser/lightbox Slice B1 — media_variant (spejl af schema.sql)
-- =====================================================================
CREATE TABLE IF NOT EXISTS media_variant (
  id           BIGINT PRIMARY KEY,
  media_id     BIGINT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  tier         TEXT NOT NULL CHECK (tier IN ('thumb','medium')),
  storage_path TEXT NOT NULL,
  mime_type    TEXT,
  byte_size    BIGINT,
  bredde       INT,
  hoejde       INT
);
CREATE UNIQUE INDEX IF NOT EXISTS media_variant_media_tier_uidx    ON media_variant (media_id, tier);
CREATE UNIQUE INDEX IF NOT EXISTS media_variant_storage_path_uidx ON media_variant (storage_path);

CREATE OR REPLACE FUNCTION red_registrer_media_variant(
  p_media_id bigint, p_tier text, p_storage_path text,
  p_mime text DEFAULT NULL, p_byte_size bigint DEFAULT NULL,
  p_bredde int DEFAULT NULL, p_hoejde int DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tier NOT IN ('thumb','medium') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig variant-tier. ''large'' er media-rækkens egen storage_path, ikke en variant-række.', p_tier;
  END IF;
  INSERT INTO media_variant(id, media_id, tier, storage_path, mime_type, byte_size, bredde, hoejde)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM media_variant), p_media_id, p_tier, p_storage_path, p_mime, p_byte_size, p_bredde, p_hoejde)
    ON CONFLICT (media_id, tier) DO UPDATE
      SET storage_path = excluded.storage_path, mime_type = excluded.mime_type,
          byte_size = excluded.byte_size, bredde = excluded.bredde, hoejde = excluded.hoejde
    RETURNING id INTO v_id;
  RETURN v_id;
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

-- 2026-07-06: konto-bogmærker — login-eksklusiv bookmark-tabel (design-spec 2026-07-06).
CREATE TABLE IF NOT EXISTS bookmark (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  oprettet  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, person_id)
);
ALTER TABLE bookmark ENABLE ROW LEVEL SECURITY;

-- 2026-07-16: source.aar-konvention harmoniseret til SIDSTE dækkede år (flere-daa-udgaver,
-- Problem 1 §3.2). Den tidligere backfill (ovf.: 'aar=2018 WHERE id=1') satte DAA 2018-20 til
-- FØRSTE år; tidsserie-diff ("forrige udgave" via source.aar) kræver ensartet konvention på
-- tværs af udgaver. Loaderne (load_presens.R/load_daa.R parse_aar) bruger sidste dækkede år
-- fremadrettet (2012-2014→2014, 2018-20→2020, 1939→1939). Idempotent korrektion af den ene
-- allerede-loadede prod-source (rører kun rækken hvis den stadig står på det gamle 2018):
UPDATE source SET aar = 2020 WHERE udgave = 'DAA 2018-20' AND aar = 2018;

-- 2026-07-16: ikke_samme_som — persisteret identitets-afvisning (tværudgave-spec §4).
-- Ny rolle + red_ikke_samme_som/red_fjern_ikke_samme_som; kontradiktions-guard tilføjet i
-- red_samme_som; red_relation afviser rolle='ikke_samme_som'. Alt idempotent (CREATE OR
-- REPLACE / ON CONFLICT). Integrationstestet mod lokal prod-kopi (daa_test2).
-- ikke_samme_som-migration (tværudgave-spec §4) — idempotent
INSERT INTO vocab (scheme, code, label) VALUES ('rolle','ikke_samme_som','bekræftet forskellig person fra') ON CONFLICT (scheme, code) DO NOTHING;

CREATE OR REPLACE FUNCTION red_relation(
  p_subjekt_type text, p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint,
  p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_rolle = 'samme_som' THEN RAISE EXCEPTION 'Brug red_samme_som til identitets-links'; END IF;
  IF p_rolle = 'ikke_samme_som' THEN RAISE EXCEPTION 'Brug red_ikke_samme_som til identitets-afvisning'; END IF;
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

CREATE OR REPLACE FUNCTION red_samme_som(p_alias_id bigint, p_objekt_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_alias_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_alias_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_objekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_objekt_id; END IF;
  -- G2 idempotens (præcis retning) FØR begin_change_set.
  SELECT id INTO v_rel FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=p_alias_id AND objekt_id=p_objekt_id LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  -- Kontradiktions-guard (tværudgave-spec §4): parret må ikke samtidig være markeret
  -- ikke_samme_som. At skifte mening er to versionerede trin (fjern afvisningen først).
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='ikke_samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND subjekt_id=least(p_alias_id,p_objekt_id) AND objekt_id=greatest(p_alias_id,p_objekt_id)) THEN
    RAISE EXCEPTION 'samme_som: parret (%,%) er markeret ikke_samme_som — fjern afvisningen først', p_alias_id, p_objekt_id;
  END IF;
  PERFORM begin_change_set('red_samme_som',
    format('Markerede person %s som samme som %s', p_alias_id, p_objekt_id), 'person', p_objekt_id);
  -- Triggeren validerer G0/G3/G4/G5 på denne INSERT.
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

CREATE OR REPLACE FUNCTION red_ikke_samme_som(p_a bigint, p_b bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_lo bigint; v_hi bigint; v_rel bigint; v_ass bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- Samme advisory-lock som red_samme_som: serialisér de to kontradiktions-guards mod hinanden
  -- (uden den kan concurrent red_samme_som(a,b)+red_ikke_samme_som(a,b) begge passere → dobbelt-rolle).
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF p_a = p_b THEN RAISE EXCEPTION 'ikke_samme_som: kan ikke afvise en person mod sig selv'; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_a) THEN RAISE EXCEPTION 'Person % findes ikke', p_a; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_b) THEN RAISE EXCEPTION 'Person % findes ikke', p_b; END IF;
  v_lo := least(p_a, p_b); v_hi := greatest(p_a, p_b);
  -- Idempotens FØR change_set (ingen tom audit ved gentagelse; begge kald-retninger normaliseres).
  SELECT id INTO v_rel FROM relation WHERE rolle='ikke_samme_som' AND subjekt_type='person' AND objekt_type='person'
    AND subjekt_id=v_lo AND objekt_id=v_hi LIMIT 1;
  IF v_rel IS NOT NULL THEN RETURN v_rel; END IF;
  -- Kontradiktions-guard: findes et samme_som-link mellem parret (begge retninger) → afvis.
  IF EXISTS (SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
             AND ((subjekt_id=p_a AND objekt_id=p_b) OR (subjekt_id=p_b AND objekt_id=p_a))) THEN
    RAISE EXCEPTION 'ikke_samme_som: parret (%,%) er allerede linket som samme_som — fjern linket først', p_a, p_b;
  END IF;
  PERFORM begin_change_set('red_ikke_samme_som',
    format('Markerede person %s og %s som forskellige', v_lo, v_hi), 'person', v_lo);
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', v_lo, 'person', v_hi, 'ikke_samme_som')
    RETURNING id INTO v_rel;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'relation', v_rel, 'ikke_samme_som')
    RETURNING id INTO v_ass;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'relation', v_rel, v_ass, 'afklaret',
            'redaktionel identitets-afvisning');
  RETURN v_rel;
END $$;

CREATE OR REPLACE FUNCTION red_fjern_ikke_samme_som(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=p_relation_id AND rolle='ikke_samme_som'
                AND subjekt_type='person' AND objekt_type='person') THEN
    RAISE EXCEPTION 'Relation % er ikke et person→person ikke_samme_som-spor', p_relation_id;
  END IF;
  PERFORM begin_change_set('red_fjern_ikke_samme_som', format('Fjernede ikke_samme_som-spor %s', p_relation_id), NULL, NULL);
  PERFORM _delete_relation_evidence(p_relation_id);
END $$;

-- =====================================================================
-- 2026-07-16: Problem 2 — konkurrerende forældrefamilie-påstande (Fase 1: DB-lag)
-- Spec: docs/superpowers/specs/2026-07-15-family-member-konkurrerende-relationer-design.md
-- Giver 'barn'-slægtskabet det evidenslag fact/relation allerede har: hver udgaves
-- forældre-påstand bevares som assertion (objekt=familie), redaktøren vælger den kanoniske
-- via conclusion, family_member forbliver den kanoniske projektion (nul ændring i læse-laget).
-- Alt idempotent. Backfill af eksisterende barn-rækker køres separat (kræver ren single-edition
-- kilde-kontekst — se docs/reviews/29-problem2). BEVIDST AFVIGELSE fra spec §4.4/§4.5:
-- red_flyt_barn er delete-før-insert (ikke insert-før-delete) — så red_tilfoej_barns nye
-- fødselsfamilie-prætjek komponerer uden bypass-param, og barnet har aldrig momentant to
-- fødselsfamilier. EXCLUDE forbliver DEFERRABLE (fremtidssikret, harmløs med begge rækkefølger).
-- =====================================================================

-- 4.1 assertion.objekt_type/objekt_id — en påstands VÆRDI kan være en entitet (her: forældrefamilien).
-- Polymorf (type,id)-par uden hård FK (husets konvention); NULL for alle eksisterende påstande.
ALTER TABLE assertion ADD COLUMN IF NOT EXISTS objekt_type TEXT;
ALTER TABLE assertion ADD COLUMN IF NOT EXISTS objekt_id   BIGINT;
CREATE INDEX IF NOT EXISTS ix_assertion_objekt ON assertion(objekt_type, objekt_id)
  WHERE objekt_id IS NOT NULL;

-- 4.2 vokabular
INSERT INTO vocab (scheme, code, label)
  VALUES ('faktatype','forældrefamilie','Forældrefamilie (fødselsfamilie)')
  ON CONFLICT (scheme, code) DO NOTHING;

-- 4.4 Grafinvariant: højst én fødselsfamilie ('barn'-række) pr. person. Fail-closed prætjek:
-- constrainten må ikke tilføjes ovenpå eksisterende dubletter.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM family_member WHERE rolle='barn'
             GROUP BY person_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'family_member: person(er) med >1 fødselsfamilie — afklar manuelt før constraint';
  END IF;
END $$;
ALTER TABLE family_member DROP CONSTRAINT IF EXISTS family_member_en_foedselsfamilie;
ALTER TABLE family_member ADD CONSTRAINT family_member_en_foedselsfamilie
  EXCLUDE USING btree (person_id WITH =) WHERE (rolle = 'barn')
  DEFERRABLE INITIALLY DEFERRED;

-- 4.5 RPC: registrér en kildes forældrefamilie-påstand UDEN at ændre det kanoniske valg (Operation A-analog).
CREATE OR REPLACE FUNCTION red_tilfoej_foraeldre_paastand(
  p_barn_id bigint, p_family_id bigint,
  p_source_id bigint DEFAULT NULL, p_side text DEFAULT NULL,
  p_citat text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_fact bigint; v_assert bigint; v_cit bigint;
  v_valgt_family bigint; v_barn_family bigint; v_konflikt boolean := false; v_concl_exists boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion må skrive forældre-påstande (din rolle: %)', current_rolle(); END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_barn_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_barn_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM family WHERE id=p_family_id) THEN RAISE EXCEPTION 'Familie % findes ikke', p_family_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND rolle='partner') THEN
    RAISE EXCEPTION 'Familie % har ingen forælder (partner-medlem) — kan ikke være forældrefamilie', p_family_id; END IF;

  -- Idempotens FØR change_set: samme slot + samme objekt_id + samme citation-source → returnér eksisterende (intet change_set).
  SELECT f.id, a.id, c.id INTO v_fact, v_assert, v_cit
    FROM fact f
    JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id AND a.objekt_type='family' AND a.objekt_id=p_family_id
    JOIN citation c ON c.assertion_id=a.id AND c.source_id IS NOT DISTINCT FROM p_source_id
    WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie'
    LIMIT 1;
  IF v_assert IS NOT NULL THEN
    RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,'citation_id',v_cit,'konflikt',false,'idempotent',true);
  END IF;

  PERFORM begin_change_set('red_tilfoej_foraeldre_paastand',
    format('Forældrefamilie-påstand: barn %s → familie %s', p_barn_id, p_family_id), 'person', p_barn_id);

  -- find-or-create slot (højst ét 'forældrefamilie'-fact pr. person)
  SELECT id INTO v_fact FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_barn_id AND faktatype='forældrefamilie' LIMIT 1;
  IF v_fact IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), 'person', p_barn_id, 'forældrefamilie')
      RETURNING id INTO v_fact;
  END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, 'barn', 'family', p_family_id, true)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, side, citat_tekst, kvalitet)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, p_source_id, p_side,
            coalesce(p_citat, p_kilde_fritekst, '(kilde mangler)'),
            CASE WHEN p_source_id IS NOT NULL THEN 'primær' ELSE 'sekundær' END)  -- kildeløs redaktionel påstand er ikke primærkilde
    RETURNING id INTO v_cit;

  -- Adjudikations-tilstand: hvad peger konklusionen (om nogen) på, og hvor er barnet projiceret?
  SELECT a.objekt_id INTO v_valgt_family
    FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_fact;
  v_concl_exists := EXISTS(SELECT 1 FROM conclusion WHERE target_type='fact' AND target_id=v_fact);
  SELECT family_id INTO v_barn_family FROM family_member WHERE person_id=p_barn_id AND rolle='barn' LIMIT 1;

  IF v_concl_exists THEN
    IF v_valgt_family IS DISTINCT FROM p_family_id THEN
      -- Konflikt: rival peger på anden familie end den valgte. Vores konklusion URØRT (TNG-præcedens);
      -- markér omstridt + eskalér projektions-rækkens konfidens (invariant 7: vis usikkerhed).
      v_konflikt := true;
      UPDATE conclusion SET status='omstridt', blaastemplet_naar=current_date
        WHERE target_type='fact' AND target_id=v_fact;
      -- EXCLUDE garanterer højst én 'barn'-række pr. person → intet familie-prædikat/NULL-guard nødvendigt.
      UPDATE family_member SET konfidens='omstridt'
        WHERE person_id=p_barn_id AND rolle='barn';
    END IF;
    -- v_valgt_family = p_family_id: korroboration af det valgte — ingen ændring.
  ELSE
    -- Ingen conclusion endnu: selv-helende afklaret KUN når påstanden matcher barnets projicerede række.
    IF v_barn_family IS NOT DISTINCT FROM p_family_id THEN
      INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
        VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert, 'afklaret',
                'Redaktør (korroboration)', current_date);
    END IF;
    -- ellers: påstanden står som ren kandidat; adjudicér med red_vaelg_foraeldre.
  END IF;

  RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,'citation_id',v_cit,'konflikt',v_konflikt);
END $$;

-- 4.5 RPC: adjudikationen — ét bevidst valg + synkron projektion, i ÉT change_set.
CREATE OR REPLACE FUNCTION red_vaelg_foraeldre(p_assertion_id bigint, p_konfidens text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fact bigint; v_barn bigint; v_faktatype text; v_objekt_type text; v_til_family bigint; v_old_family bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  SELECT a.target_id, a.objekt_type, a.objekt_id, f.subjekt_id, f.faktatype
    INTO v_fact, v_objekt_type, v_til_family, v_barn, v_faktatype
    FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact'
    WHERE a.id=p_assertion_id;
  IF v_fact IS NULL THEN RAISE EXCEPTION 'Assertion % findes ikke el. targeter ikke et fact', p_assertion_id; END IF;
  IF v_faktatype <> 'forældrefamilie' OR v_objekt_type IS DISTINCT FROM 'family' THEN
    RAISE EXCEPTION 'Assertion % er ikke en forældrefamilie-påstand', p_assertion_id; END IF;
  -- Kontradiktions-guard: aktivt forældre_ukendt → at skifte mening er to versionerede trin.
  IF EXISTS(SELECT 1 FROM fact ff JOIN conclusion cc ON cc.target_type='fact' AND cc.target_id=ff.id AND cc.status='afklaret'
            WHERE ff.subjekt_type='person' AND ff.subjekt_id=v_barn AND ff.faktatype='forældre_ukendt') THEN
    RAISE EXCEPTION 'Barn % er markeret forældre_ukendt — tilbagetræk markeringen først (red_tilbagetraek_fakta)', v_barn; END IF;

  PERFORM begin_change_set('red_vaelg_foraeldre',
    format('Valgte forældrefamilie %s for barn %s', v_til_family, v_barn), 'person', v_barn);

  -- Ét bevidst valg: re-peg conclusion FØR projektionen (så red_flyt_barns slot-vedligehold ser
  -- slottet allerede peger på til-familien og ikke dobbelt-nedskriver).
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, p_assertion_id, 'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret', blaastemplet_naar=current_date;

  -- Projektion: family_member følger valget (genbruger cyklus-/partner-guards). EXCLUDE = sidste værn.
  SELECT family_id INTO v_old_family FROM family_member WHERE person_id=v_barn AND rolle='barn' LIMIT 1;
  IF v_old_family IS NULL THEN
    PERFORM red_tilfoej_barn(v_til_family, v_barn);
  ELSIF v_old_family <> v_til_family THEN
    PERFORM red_flyt_barn(v_old_family, v_til_family, v_barn);
  END IF;

  -- Konfidens: kun manuelt (aldrig auto-beroligelse) — en 'omstridt' fra konflikten står til redaktøren erklærer tillid.
  IF p_konfidens IS NOT NULL THEN
    PERFORM red_set_familie_konfidens(v_til_family, v_barn, 'barn', p_konfidens);
  END IF;
END $$;

-- 4.5 Guards: tving den evidens-komplette vej for forældrefamilie-slottet.
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
  IF p_faktatype = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Brug red_tilfoej_foraeldre_paastand / red_vaelg_foraeldre til forældrefamilie';
  END IF;
  PERFORM begin_change_set('red_upsert_fakta', format('Opdaterede %s på %s/%s', p_faktatype, p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  SELECT id INTO v_fact FROM fact
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND faktatype=p_faktatype LIMIT 1;
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
  RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,'citation_id',v_cit,'conclusion_id',v_concl);
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
  IF p_faktatype = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Brug red_tilfoej_foraeldre_paastand / red_vaelg_foraeldre til forældrefamilie';
  END IF;
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

CREATE OR REPLACE FUNCTION red_tilfoej_oplysning(
  p_fact_id bigint, p_vaerdi text,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_kilde_fritekst text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF (SELECT faktatype FROM fact WHERE id=p_fact_id) = 'forældrefamilie' THEN
    RAISE EXCEPTION 'Brug red_tilfoej_foraeldre_paastand til forældrefamilie-slottet';
  END IF;
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

-- red_tilfoej_barn: venligt prætjek ved eksisterende fødselsfamilie (i stedet for rå exclusion_violation).
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
  -- Fødselsfamilie-prætjek (invariant P1/EXCLUDE): kun én 'barn'-række pr. person. Venlig fejl frem
  -- for rå exclusion_violation. red_flyt_barn er delete-før-insert, så den passerer her (gammel række væk).
  IF p_rolle = 'barn' AND EXISTS(SELECT 1 FROM family_member
       WHERE person_id=p_barn_id AND rolle='barn' AND family_id <> p_family_id) THEN
    RAISE EXCEPTION 'Person % har allerede en fødselsfamilie — brug red_flyt_barn eller forældre-påstands-flowet', p_barn_id;
  END IF;
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
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle=p_rolle) THEN RETURN; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_barn_id, p_rolle, NULL, p_konfidens);
END $$;

-- red_flyt_barn: delete-før-insert (se blok-header) + slot-vedligehold (invariant P1) for direkte
-- strukturelle flytninger der ikke kom via red_vaelg_foraeldre.
CREATE OR REPLACE FUNCTION red_flyt_barn(p_fra_family_id bigint, p_til_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_konfidens text; v_slot_fact bigint; v_slot_family bigint; v_new_assert bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_flyt_barn', format('Flyttede barn %s fra familie %s til familie %s', p_barn_id, p_fra_family_id, p_til_family_id), 'person', p_barn_id);
  IF p_fra_family_id = p_til_family_id THEN RAISE EXCEPTION 'Fra- og til-familie er ens'; END IF;
  SELECT konfidens INTO v_konfidens FROM family_member
    WHERE family_id=p_fra_family_id AND person_id=p_barn_id AND rolle=p_rolle;
  IF NOT FOUND THEN RAISE EXCEPTION 'Barn-link findes ikke (family %, person %, rolle %)', p_fra_family_id, p_barn_id, p_rolle; END IF;
  PERFORM red_slet_familie_link(p_fra_family_id, p_barn_id, p_rolle);
  PERFORM red_tilfoej_barn(p_til_family_id, p_barn_id, p_rolle, v_konfidens);
  -- Slot-vedligehold: har barnet et afklaret forældrefamilie-slot der STADIG peger på fra-familien
  -- (dvs. flytningen kom ikke via red_vaelg_foraeldre, der re-peger slottet på forhånd), nedskriv en
  -- redaktionel påstand (objekt=til) + re-peg — så slot og projektion ikke divergerer (invariant P1).
  IF p_rolle = 'barn' THEN
    SELECT f.id INTO v_slot_fact FROM fact f
      WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie' LIMIT 1;
    IF v_slot_fact IS NOT NULL THEN
      SELECT a.objekt_id INTO v_slot_family FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
        WHERE c.target_type='fact' AND c.target_id=v_slot_fact AND c.status='afklaret';
      IF v_slot_family = p_fra_family_id THEN
        INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
          VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_slot_fact, 'barn', 'family', p_til_family_id, true)
          RETURNING id INTO v_new_assert;
        INSERT INTO citation(id, assertion_id, source_id, citat_tekst, kvalitet)
          VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_new_assert, NULL,
                  '(kilde mangler: strukturel flytning via red_flyt_barn)', 'sekundær');
        UPDATE conclusion SET valgt_assertion_id=v_new_assert, blaastemplet_naar=current_date
          WHERE target_type='fact' AND target_id=v_slot_fact;
      END IF;
    END IF;
  END IF;
END $$;

-- 4.6 Konflikt-view til redaktions-dashboardet (security_invoker som red_konflikt).
CREATE OR REPLACE VIEW red_foraeldre_konflikt WITH (security_invoker = true) AS
SELECT f.subjekt_id AS person_id, f.id AS fact_id,
       count(DISTINCT a.objekt_id) AS antal_familier,
       count(*)                    AS antal_paastande,
       max(c.status)               AS status
FROM fact f
JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id AND a.objekt_type='family'
LEFT JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
WHERE f.subjekt_type='person' AND f.faktatype='forældrefamilie'
GROUP BY f.subjekt_id, f.id
HAVING count(DISTINCT a.objekt_id) > 1;

-- 5. Backfill af forældre-evidens: FLYTTET til db-backfill-foraeldrefamilie.sql (review 30/Fase 4).
-- Backfillen er en DELIBERAT engangs-datahandling med fail-open-risiko mod multi-edition-baser og
-- hører derfor IKKE i den idempotente skema-afstemning (der ellers auto-kørte den ved hver anvendelse).
-- Kør db-backfill-foraeldrefamilie.sql separat EFTER denne migration + EFTER single-edition er bekræftet
-- (filen har nu en external_id-baseret multi-edition-abort ud over STRICT-kildeopslaget). Se docs/fase4-runbook.md.

-- =====================================================================
-- 2026-07-16: review 30 (dual-review Problem 2) — slot-vedligehold på ALLE strukturelle
-- family_member-skrive-veje (B1+B2). De tre mutatorer var opdateret asymmetrisk: kun
-- red_flyt_barn vedligeholdt forældrefamilie-slottet. red_tilfoej_barn (nyt barn) efterlod en
-- slotløs barn-række (backfill-komplethed-brud); red_slet_familie_link (fjern barn) efterlod et
-- forældreløst afklaret slot (P1-drift). Delt helper _ensure_foraeldrefamilie_redaktionel + retraktion.
-- =====================================================================

-- Helper: sikr at barnets forældrefamilie-slot findes og peger afklaret på p_family (via en
-- find-or-created redaktionel assertion). Idempotent. Intern (kaldes kun fra gated red_*-funktioner).
CREATE OR REPLACE FUNCTION _ensure_foraeldrefamilie_redaktionel(p_barn bigint, p_family bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_slot bigint; v_assert bigint;
BEGIN
  -- Gate (review 30/fable): SECURITY DEFINER-helper kaldes kun fra gated red_*-funktioner, men
  -- Supabases default-grants ville ellers eksponere den for anon via PostgREST (uatoriseret
  -- slot-re-peg). Guarden er gratis her (kalderen er allerede redaktion).
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion (intern forældrefamilie-helper)'; END IF;
  SELECT id INTO v_slot FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_barn AND faktatype='forældrefamilie' LIMIT 1;
  IF v_slot IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), 'person', p_barn, 'forældrefamilie') RETURNING id INTO v_slot;
  END IF;
  -- Find KUN en redaktionel (source-løs) assertion for familien — kapr aldrig en source-bunden
  -- rival-/adjudikeret påstand (review 30/Codex #5). Ordnet for determinisme.
  SELECT a.id INTO v_assert FROM assertion a
    WHERE a.target_type='fact' AND a.target_id=v_slot AND a.objekt_type='family' AND a.objekt_id=p_family
      AND NOT EXISTS(SELECT 1 FROM citation c WHERE c.assertion_id=a.id AND c.source_id IS NOT NULL)
    ORDER BY a.id LIMIT 1;
  IF v_assert IS NULL THEN
    INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst, objekt_type, objekt_id, uforanderlig)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_slot, 'barn', 'family', p_family, true) RETURNING id INTO v_assert;
    INSERT INTO citation(id, assertion_id, source_id, citat_tekst, kvalitet)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL, '(kilde mangler: strukturel projektion)', 'sekundær');
  END IF;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_slot, v_assert, 'afklaret', 'Redaktør (strukturel)', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret', blaastemplet_naar=current_date;
END $$;

-- red_slet_familie_link: retraktér slottet når en 'barn'-række fjernes (B1). Kun hvis det afklarede
-- slot faktisk peger på DEN fjernede familie → red_flyt_barns interne slet (slot peger allerede på
-- til efter red_vaelg_foraeldres re-peg) rører den ikke.
CREATE OR REPLACE FUNCTION red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_familie_link', format('Slettede familie-link %s/%s/%s', p_family_id, p_person_id, p_rolle), 'person', p_person_id);
  DELETE FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  IF p_rolle = 'barn' THEN
    UPDATE conclusion c SET status='tilbagetrukket', blaastemplet_naar=current_date
    FROM fact f, assertion a
    WHERE f.subjekt_type='person' AND f.subjekt_id=p_person_id AND f.faktatype='forældrefamilie'
      AND c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
      AND a.id=c.valgt_assertion_id AND a.objekt_id=p_family_id;
  END IF;
END $$;

-- red_tilfoej_barn: find-or-create slot når et GENUINT nyt barn tilføjes (B2). Kun når personen
-- ikke allerede har et slot (red_flyt_barn/red_vaelg_foraeldre håndterer slottet selv → skip).
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
  IF p_rolle = 'barn' AND EXISTS(SELECT 1 FROM family_member
       WHERE person_id=p_barn_id AND rolle='barn' AND family_id <> p_family_id) THEN
    RAISE EXCEPTION 'Person % har allerede en fødselsfamilie — brug red_flyt_barn eller forældre-påstands-flowet', p_barn_id;
  END IF;
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
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle=p_rolle) THEN RETURN; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_barn_id, p_rolle, NULL, p_konfidens);
  -- Slot-komplethed (review 30/Codex #1): sikr et AFKLARET slot mod p_family. Dækker nyt barn (intet
  -- slot), delete→re-add (retrakteret slot) og slot der peger forkert. No-op når red_vaelg/red_flyt
  -- allerede pegede slottet på p_family (bevar deres valgte, source-bundne assertion).
  IF p_rolle = 'barn' AND NOT EXISTS(
       SELECT 1 FROM fact f
       JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
       JOIN assertion a ON a.id=c.valgt_assertion_id
       WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie'
         AND a.objekt_id=p_family_id) THEN
    PERFORM _ensure_foraeldrefamilie_redaktionel(p_barn_id, p_family_id);
  END IF;
END $$;

-- red_flyt_barn: slot-vedligehold gennem den delte helper. Re-etablér slottet til til-familien
-- MEDMINDRE det allerede peger dertil (red_vaelg_foraeldre re-pegede FØR flyt → bevar dens valgte,
-- source-bundne assertion). Håndterer også retraktion fra det interne red_slet_familie_link + omstridt.
CREATE OR REPLACE FUNCTION red_flyt_barn(p_fra_family_id bigint, p_til_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_konfidens text; v_slot_fact bigint; v_slot_family bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_flyt_barn', format('Flyttede barn %s fra familie %s til familie %s', p_barn_id, p_fra_family_id, p_til_family_id), 'person', p_barn_id);
  IF p_fra_family_id = p_til_family_id THEN RAISE EXCEPTION 'Fra- og til-familie er ens'; END IF;
  SELECT konfidens INTO v_konfidens FROM family_member
    WHERE family_id=p_fra_family_id AND person_id=p_barn_id AND rolle=p_rolle;
  IF NOT FOUND THEN RAISE EXCEPTION 'Barn-link findes ikke (family %, person %, rolle %)', p_fra_family_id, p_barn_id, p_rolle; END IF;
  PERFORM red_slet_familie_link(p_fra_family_id, p_barn_id, p_rolle);
  PERFORM red_tilfoej_barn(p_til_family_id, p_barn_id, p_rolle, v_konfidens);
  IF p_rolle = 'barn' THEN
    SELECT f.id INTO v_slot_fact FROM fact f
      WHERE f.subjekt_type='person' AND f.subjekt_id=p_barn_id AND f.faktatype='forældrefamilie' LIMIT 1;
    IF v_slot_fact IS NOT NULL THEN
      SELECT a.objekt_id INTO v_slot_family FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
        WHERE c.target_type='fact' AND c.target_id=v_slot_fact AND c.status='afklaret';
      IF v_slot_family IS DISTINCT FROM p_til_family_id THEN  -- peger ikke (længere) på til → re-etablér redaktionelt
        PERFORM _ensure_foraeldrefamilie_redaktionel(p_barn_id, p_til_family_id);
      END IF;
    END IF;
  END IF;
END $$;

-- =====================================================================
-- 2026-07-17: Dato-hærdning A1 — additive felter til qualifier-aware parsing
-- Plan: docs/plan-1939-produktionsklar.md (Spor A). Understøtter A2-parseren
-- (validate.py) der fremadrettet emit'er læse-sikkerhed + konverteret kalender.
-- Modellen var allerede rig (date_raw/min/max/qualifier/calendar); dette tilføjer
-- KUN den ægte manglende ortogonale dimension (date_certainty) + kontrollerer
-- faktavokabularet. date_precision UDLEDES af date_min/date_max ved læsning (ikke
-- persisteret — plan A1b). Alt idempotent, additivt, ingen backfill/data-mutation.
-- =====================================================================

-- A1b: date_certainty — LÆSE-sikkerhed, ortogonal til date_qualifier (RELATION).
-- Ny kolonne → CHECK er sikker (alle eksisterende påstande får NULL = 'ikke vurderet').
ALTER TABLE assertion ADD COLUMN IF NOT EXISTS date_certainty TEXT;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'assertion_date_certainty_chk') THEN
    ALTER TABLE assertion ADD CONSTRAINT assertion_date_certainty_chk
      CHECK (date_certainty IN ('certain','uncertain','ambiguous'));
  END IF;
END $$;

-- A1a/A1c: faktavokabular. faktatype er fri TEXT (ingen FK), men vocab er den
-- autoritative reference for 'samme slags'-forespørgsler (invariant #9). Seed de
-- kerne-dato-/event-typer der de facto bruges som literaler + de nye event-typer.
-- 'begravelse' er kanonisk (bisættelse normaliseres hertil i parseren). Idempotent.
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','fødsel','Fødsel'),
  ('faktatype','dåb','Dåb'),
  ('faktatype','død','Død'),
  ('faktatype','begravelse','Begravelse (kanonisk — bisættelse normaliseres hertil)'),
  ('faktatype','floruit','Floruit (dokumenteret-aktiv span; ≠ levetid)'),
  ('faktatype','adling','Adling/standsophøjelse'),
  ('faktatype','naturalisering','Naturalisation'),
  ('faktatype','introduktion_ridderhus','Introduktion på ridderhus')
  ON CONFLICT (scheme, code) DO NOTHING;

-- =====================================================================
-- 2026-07-17: K2 — staging-gate for ny-udgave-import (plan Konvergens/K2)
-- Problem: en ny udgaves poster (fx 1939) er anon-synlige STRAKS ved load —
-- før en redaktør har matchet dem mod eksisterende udgaver (samme_som) — så
-- dublette Conrad'er (1939 + 2018-20) er begge offentlige indtil matchet.
-- Løsning: person.staged (KURATERING, uafhængig af GDPR-levende/privat). Loaderen
-- sætter TRUE ved --staged; person_offentlig (db-rls.sql) skjuler staged → cascader
-- til fact/relation/narrative via entitet_offentlig. red_publicer_udgave rydder
-- samlet når match-gennemgangen er færdig. Additiv, bagud-kompatibel (default FALSE).
-- NB: RLS-ændringen bor i db-rls.sql (gen-anvendes af cutover Trin 1b).
-- =====================================================================
ALTER TABLE person ADD COLUMN IF NOT EXISTS staged BOOLEAN DEFAULT FALSE;

-- Publicér en udgave: ryd staged for dens egne poster (person_external_id→source)
-- + dens partner-stubs (staged personer i en familie m. et source-scopet medlem;
-- stubs har ingen external_id). Redaktion-gated, revisions-tal returneres.
CREATE OR REPLACE FUNCTION red_publicer_udgave(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n integer;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må publicere en udgave (din rolle: %)', current_rolle();
  END IF;
  UPDATE person p SET staged = false
  WHERE p.staged = true
    AND (EXISTS (SELECT 1 FROM person_external_id pei
                 WHERE pei.person_id = p.id AND pei.source_id = p_source_id)
      OR EXISTS (SELECT 1 FROM family_member fm1
                 JOIN family_member fm2 ON fm2.family_id = fm1.family_id
                 JOIN person_external_id pei ON pei.person_id = fm2.person_id
                   AND pei.source_id = p_source_id
                 WHERE fm1.person_id = p.id));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('publiceret_source', p_source_id, 'personer_afstaget', v_n);
END $$;
REVOKE ALL ON FUNCTION red_publicer_udgave(bigint) FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- 2026-07-18: levende feed fase 2 — haendelse (formidlingslag)
-- Additiv regenererbar projektion af narrative; kun feed_status er varig.
-- RLS-politikkerne bor i db-rls.sql og skal gen-anvendes efter migrationen.
-- =====================================================================
CREATE TABLE IF NOT EXISTS haendelse (
  id             BIGINT PRIMARY KEY,
  subjekt_type   TEXT NOT NULL,
  subjekt_id     BIGINT NOT NULL,
  narrative_id   BIGINT NOT NULL REFERENCES narrative(id) ON DELETE CASCADE,
  noegle         TEXT NOT NULL,
  span_start     INTEGER,
  span_laengde   INTEGER,
  klausul        TEXT NOT NULL,
  kategori       TEXT,
  date_min       DATE,
  date_max       DATE,
  date_qualifier TEXT,
  date_raw       TEXT,
  feed_status    TEXT NOT NULL DEFAULT 'kandidat'
                   CHECK (feed_status IN ('kandidat','interessant','skjult')),
  fact_id        BIGINT REFERENCES fact(id),
  relation_id    BIGINT REFERENCES relation(id),
  pass_version   TEXT,
  UNIQUE (narrative_id, noegle)
);
CREATE INDEX IF NOT EXISTS ix_haendelse_subjekt   ON haendelse(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_haendelse_narrative ON haendelse(narrative_id);

INSERT INTO vocab (scheme, code, label) VALUES
  ('haendelse_feed_status','kandidat',   'Umarkeret — må vises som arkiv-kort'),
  ('haendelse_feed_status','interessant','Redaktørens dom: godt feed-stof (boostes)'),
  ('haendelse_feed_status','skjult',     'Aldrig i feed'),
  ('haendelse_kategori','embede',       'Embede/udnævnelse'),
  ('haendelse_kategori','uddannelse',   'Uddannelse/immatrikulation'),
  ('haendelse_kategori','rejse',        'Rejse/udlandsophold'),
  ('haendelse_kategori','krig',         'Krig/militær tjeneste'),
  ('haendelse_kategori','ejendom',      'Ejendom/køb/salg/arv'),
  ('haendelse_kategori','kirke',        'Kirke/kloster/gejstligt'),
  ('haendelse_kategori','hof',          'Hof/ceremoni/hyldning'),
  ('haendelse_kategori','familie',      'Familiebegivenhed'),
  ('haendelse_kategori','personligt',   'Personligt/øvrigt dateret'),
  ('haendelse_kategori','andet',        'Andet')
ON CONFLICT (scheme, code) DO NOTHING;

CREATE OR REPLACE FUNCTION red_set_haendelse_status(p_haendelse_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kandidat','interessant','skjult') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig feed-status (kandidat|interessant|skjult)', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM haendelse WHERE id=p_haendelse_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Hændelse % findes ikke', p_haendelse_id; END IF;
  PERFORM begin_change_set('red_set_haendelse_status',
    format('Satte feed-status %s på hændelse %s', p_status, p_haendelse_id), v_stype, v_sid);
  UPDATE haendelse SET feed_status=p_status WHERE id=p_haendelse_id;
END $$;
REVOKE ALL ON FUNCTION red_set_haendelse_status(bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION red_set_haendelse_status(bigint,text) TO authenticated;

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('haendelse', ARRAY['id'],
   ARRAY['subjekt_type','subjekt_id','narrative_id','noegle','span_start','span_laengde',
         'klausul','kategori','date_min','date_max','date_qualifier','date_raw',
         'fact_id','relation_id','pass_version'])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;

DROP TRIGGER IF EXISTS trg_log_haendelse ON haendelse;
CREATE TRIGGER trg_log_haendelse AFTER INSERT OR UPDATE OR DELETE ON haendelse
  FOR EACH ROW EXECUTE FUNCTION log_change();

-- =====================================================================
-- 2026-07-19: Mediehåndtering fase 1 — filside og fuld CRUD
-- Nye metadata-/genopret-RPC'er og kunstner/datering i upload-signaturen.
-- =====================================================================

CREATE OR REPLACE FUNCTION red_opdater_media(
  p_media_id bigint,
  p_titel text DEFAULT NULL,
  p_slags text DEFAULT NULL,
  p_kunstner text DEFAULT NULL,
  p_datering text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opdater_media', format('Opdaterede media %s', p_media_id), 'media', p_media_id);
  IF p_slags IS NOT NULL AND nullif(btrim(p_slags),'') IS NULL THEN
    RAISE EXCEPTION 'Slags kan ikke ryddes';
  END IF;
  UPDATE media SET
    titel = CASE WHEN p_titel IS NULL THEN titel ELSE nullif(btrim(p_titel),'') END,
    slags = CASE WHEN p_slags IS NULL THEN slags ELSE btrim(p_slags) END,
    kunstner = CASE WHEN p_kunstner IS NULL THEN kunstner ELSE nullif(btrim(p_kunstner),'') END,
    datering = CASE WHEN p_datering IS NULL THEN datering ELSE nullif(btrim(p_datering),'') END
  WHERE id = p_media_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
END $$;

CREATE OR REPLACE FUNCTION red_genopret_media(p_media_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_genopret_media', format('Genoprettede media %s', p_media_id), 'media', p_media_id);
  UPDATE media SET upload_status='klar'
   WHERE id=p_media_id AND upload_status='fjernet';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Kan kun genoprette et fjernet medie'; END IF;
END $$;

-- Parametertilføjelser ændrer PostgreSQL-signaturen. Fjern den gamle overload først,
-- ellers bliver PostgREST-kald og det navnebaserede grant-loop tvetydige.
DROP FUNCTION IF EXISTS red_upload_media(
  text, text, text, text,
  bigint, text, bigint,
  bigint, integer, integer,
  text, text, text, boolean
);

CREATE OR REPLACE FUNCTION red_upload_media(
  p_slags text, p_titel text, p_storage_path text, p_mime text,
  p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL,
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
  v_media := red_opret_media(p_slags, p_titel, p_kunstner, p_datering, 'media', p_storage_path,
                             p_mime, p_byte_size, p_bredde, p_hoejde, p_sha256,
                             p_original_filnavn, p_rettigheder_status, p_maa_publiceres);
  IF p_afbildet_person_id IS NOT NULL THEN
    PERFORM red_relation('person', p_afbildet_person_id, 'media', v_media, 'afbildet');
  END IF;
  IF p_objekt_type IS NOT NULL AND p_objekt_id IS NOT NULL THEN
    IF p_objekt_type = 'person' THEN
      RAISE EXCEPTION 'Brug p_afbildet_person_id til personer (GDPR-gating kræver person→media-retning)';
    END IF;
    PERFORM red_relation('media', v_media, p_objekt_type, p_objekt_id, 'afbildet');
  END IF;
  RETURN v_media;
END $$;

-- =====================================================================
-- 2026-07-19: mediehaandtering_fase2_doede_links
-- Døde media-mentions er kun dem, hvis media-række ikke findes. Et blødt
-- fjernet medie findes fortsat og kan genoprettes, så det er ikke et dødt link.
-- =====================================================================
CREATE OR REPLACE VIEW red_doede_links WITH (security_invoker = true) AS
SELECT m.* FROM text_mention m
WHERE (m.maal_type='person' AND NOT EXISTS (SELECT 1 FROM person  p WHERE p.id=m.maal_id))
   OR (m.maal_type='estate' AND NOT EXISTS (SELECT 1 FROM estate  e WHERE e.id=m.maal_id))
   OR (m.maal_type='lineage' AND NOT EXISTS (SELECT 1 FROM lineage l WHERE l.id=m.maal_id))
   OR (m.maal_type='media' AND NOT EXISTS (SELECT 1 FROM media md WHERE md.id=m.maal_id));

-- =====================================================================
-- 2026-07-20: mediehaandtering_fase3_hygiejne
-- To-trins created_at bevarer NULL (= ukendt alder) på præ-fase-3-rækker.
-- Evidensfri afbildet-dubletter ryddes før partial-indexet; evidens-bærende
-- dubletter overlever med vilje og får index-oprettelsen til at fejle højlydt.
-- =====================================================================
ALTER TABLE media ADD COLUMN IF NOT EXISTS created_at timestamptz;
ALTER TABLE media ALTER COLUMN created_at SET DEFAULT now();

-- Evidens omfatter assertion/conclusion/note. haendelse.relation_id er strukturelt
-- udelukket via conclusion-tjekket (den eneste skrivevej kræver en afklaret conclusion),
-- ikke ved en tilfældighed; en haendelse-båret dublet kan derfor ikke nå DELETE'en.
DELETE FROM relation r USING relation r2
 WHERE r.rolle='afbildet' AND r2.rolle='afbildet' AND r.id > r2.id
   AND r.subjekt_type=r2.subjekt_type AND r.subjekt_id=r2.subjekt_id
   AND r.objekt_type=r2.objekt_type   AND r.objekt_id=r2.objekt_id
   AND NOT EXISTS (SELECT 1 FROM assertion  a WHERE a.target_type='relation' AND a.target_id=r.id)
   AND NOT EXISTS (SELECT 1 FROM conclusion c WHERE c.target_type='relation' AND c.target_id=r.id)
   AND NOT EXISTS (SELECT 1 FROM note       n WHERE n.target_type='relation' AND n.target_id=r.id);

CREATE UNIQUE INDEX IF NOT EXISTS relation_afbildet_uidx
  ON relation (subjekt_type, subjekt_id, objekt_type, objekt_id)
  WHERE rolle='afbildet';
CREATE INDEX IF NOT EXISTS ix_note_target ON note(target_type, target_id);

-- Samme signatur og funktionskrop som schema.sql: ingen overload-/grant-ændring.
CREATE OR REPLACE FUNCTION red_relation(
  p_subjekt_type text, p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint,
  p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_rolle = 'samme_som' THEN RAISE EXCEPTION 'Brug red_samme_som til identitets-links'; END IF;
  IF p_rolle = 'ikke_samme_som' THEN RAISE EXCEPTION 'Brug red_ikke_samme_som til identitets-afvisning'; END IF;
  -- GDPR-invariant ved fødslen (ikke kun i red_upload_media): en 'afbildet'-relation skal gå
  -- person→media, fordi media_afbilder_skjult/privat KUN scanner (subjekt=person, objekt=media).
  -- En person på objekt-siden ville være usynlig for gatingen → fail-open. Luk det for ALLE kaldere.
  IF p_rolle = 'afbildet' AND p_objekt_type = 'person' THEN
    RAISE EXCEPTION 'afbildet skal gå person→media (person kan ikke stå på objekt-siden — GDPR-gating)';
  END IF;
  PERFORM begin_change_set('red_relation', format('Relation %s: %s/%s → %s/%s', p_rolle, p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id), p_subjekt_type, p_subjekt_id);
  BEGIN
    INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
              p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
      RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    DECLARE v_constraint_name text;
    BEGIN
      GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
      IF v_constraint_name = 'relation_afbildet_uidx' THEN
        RAISE EXCEPTION 'Mediet er allerede tilknyttet dette subjekt';
      END IF;
      RAISE;
    END;
  END;
  RETURN v_id;
END $$;

-- Polymorf relationsevidens har ingen deklarativ FK. Fælles trigger giver den
-- samme rækkelåssemantik: writer-før-delete holder KEY SHARE; delete-før-writer
-- holder UPDATE/DELETE-lock, hvorefter writeren fejler, hvis relationen er væk.
CREATE OR REPLACE FUNCTION enforce_relation_evidence_target()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.target_type='relation' THEN
    PERFORM 1 FROM relation WHERE id=NEW.target_id FOR KEY SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Relations-evidens kræver eksisterende relation %', NEW.target_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.enforce_relation_evidence_target() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_assertion_relation_target
  BEFORE INSERT OR UPDATE OF target_type, target_id ON assertion
  FOR EACH ROW EXECUTE FUNCTION enforce_relation_evidence_target();
CREATE OR REPLACE TRIGGER trg_conclusion_relation_target
  BEFORE INSERT OR UPDATE OF target_type, target_id ON conclusion
  FOR EACH ROW EXECUTE FUNCTION enforce_relation_evidence_target();
CREATE OR REPLACE TRIGGER trg_note_relation_target
  BEFORE INSERT OR UPDATE OF target_type, target_id ON note
  FOR EACH ROW EXECUTE FUNCTION enforce_relation_evidence_target();

-- Direkte relation-DELETE eller PK-ændring må ikke omgå invarianten. Evidensfri
-- id-update forbliver tilladt til import/undo; slette-RPC'erne rydder evidensen først.
CREATE OR REPLACE FUNCTION guard_relation_evidence_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  -- Generisk undo SET'er også PK-kolonnen til dens nuværende værdi.
  IF TG_OP='UPDATE' AND NEW.id IS NOT DISTINCT FROM OLD.id THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM conclusion WHERE target_type='relation' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='relation' AND target_id=OLD.id) THEN
    IF TG_OP='UPDATE' THEN
      RAISE EXCEPTION 'Relation % har evidens og id kan ikke ændres', OLD.id;
    END IF;
    RAISE EXCEPTION 'Relation % har evidens og kan ikke slettes direkte', OLD.id;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.guard_relation_evidence_delete() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_relation_evidence_delete
  BEFORE DELETE OR UPDATE OF id ON relation
  FOR EACH ROW EXECUTE FUNCTION guard_relation_evidence_delete();

-- Atomisk evidensværn til den bløde medieflets specifikke unlink. Separat RPC bevarer
-- red_slet_relation's eksisterende, tilsigtede "relation + evidens"-sletning.
CREATE OR REPLACE FUNCTION red_slet_medierelation_uden_evidens(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_relation relation%ROWTYPE;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  -- FOR UPDATE konflikter med evidens-triggerens FOR KEY SHARE på præcis denne relation.
  SELECT * INTO v_relation FROM relation WHERE id=p_relation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Relation % findes ikke', p_relation_id; END IF;
  IF NOT (
    (v_relation.rolle='afbildet' AND v_relation.subjekt_type='person'
      AND v_relation.objekt_type='media')
    OR
    (v_relation.rolle='afbildet' AND v_relation.subjekt_type='media'
      AND v_relation.objekt_type IN ('estate','coat_of_arms','lineage'))
  ) THEN
    RAISE EXCEPTION 'Relation % er ikke en kanonisk medie-afbildning', p_relation_id;
  END IF;
  IF EXISTS (SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=p_relation_id)
     OR EXISTS (SELECT 1 FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='relation' AND target_id=p_relation_id) THEN
    RAISE EXCEPTION 'Medierelationen % har evidens og kan ikke fjernes ved blød flet', p_relation_id;
  END IF;
  PERFORM begin_change_set(
    'red_slet_medierelation_uden_evidens',
    format('Fjernede evidensfri medierelation %s ved blød flet', p_relation_id), NULL, NULL
  );
  DELETE FROM relation WHERE id=p_relation_id;
END $$;

REVOKE ALL ON FUNCTION public.red_slet_medierelation_uden_evidens(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.red_slet_medierelation_uden_evidens(bigint) TO authenticated;

-- 2026-07-19: levende feed fase 3 — story/story_kilde/feed_pin
-- Kurateret formidlingslag (fase3-spec §3); additiv oven på fase 2.
-- RLS-politikkerne bor i db-rls.sql og skal gen-anvendes efter migrationen.
-- =====================================================================
CREATE TABLE IF NOT EXISTS story (
  id                  BIGINT PRIMARY KEY,
  subjekt_type        TEXT NOT NULL,
  subjekt_id          BIGINT NOT NULL,
  haendelse_id        BIGINT REFERENCES haendelse(id) ON DELETE SET NULL,
  fact_id             BIGINT REFERENCES fact(id) ON DELETE SET NULL,
  relation_id         BIGINT REFERENCES relation(id) ON DELETE SET NULL,
  historical_event_id BIGINT REFERENCES historical_event(id) ON DELETE SET NULL,
  titel               TEXT,
  tekst               TEXT NOT NULL,
  date_min            DATE,
  date_max            DATE,
  date_qualifier      TEXT,
  date_raw            TEXT,
  status              TEXT NOT NULL DEFAULT 'kladde'
                        CHECK (status IN ('kladde','klar','publiceret','arkiveret')),
  publiceret_dato     DATE,
  oprindelse          TEXT NOT NULL DEFAULT 'redaktoer'
                        CHECK (oprindelse IN ('redaktoer','llm_assisteret')),
  llm_model           TEXT,
  llm_promptversion   TEXT,
  llm_naar            TIMESTAMPTZ,
  skabt_af            UUID NOT NULL DEFAULT auth.uid(),
  godkendt_af         UUID,
  godkendt_naar       TIMESTAMPTZ,
  privat              BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS ix_story_subjekt   ON story(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_story_haendelse ON story(haendelse_id);
CREATE INDEX IF NOT EXISTS ix_story_status    ON story(status);

CREATE TABLE IF NOT EXISTS story_kilde (
  id        BIGINT PRIMARY KEY,
  story_id  BIGINT NOT NULL REFERENCES story(id) ON DELETE CASCADE,
  source_id BIGINT NOT NULL REFERENCES source(id),
  side      TEXT
);
CREATE INDEX IF NOT EXISTS ix_story_kilde_story ON story_kilde(story_id);

CREATE TABLE IF NOT EXISTS feed_pin (
  id            BIGINT PRIMARY KEY,
  kort_noegle   TEXT NOT NULL UNIQUE,
  handling      TEXT NOT NULL CHECK (handling IN ('pin','skjul')),
  oprettet_af   UUID NOT NULL DEFAULT auth.uid(),
  oprettet_naar TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO vocab (scheme, code, label) VALUES
  ('story_status','kladde',     'Under udarbejdelse — kun redaktion'),
  ('story_status','klar',       'Færdigskrevet, ikke publiceret'),
  ('story_status','publiceret', 'Synlig i feed for publikum'),
  ('story_status','arkiveret',  'Trukket tilbage — den normale slette-vej'),
  ('story_oprindelse','redaktoer',      'Redaktørskrevet'),
  ('story_oprindelse','llm_assisteret', 'LLM-kladde, menneskeligt godkendt (fase 4)')
ON CONFLICT (scheme, code) DO NOTHING;

-- Redaktionelle minihistorier + feed-kurering: eneste skrivevej.
CREATE OR REPLACE FUNCTION red_opret_story(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text,
  p_titel text DEFAULT NULL, p_haendelse_id bigint DEFAULT NULL,
  p_fact_id bigint DEFAULT NULL, p_relation_id bigint DEFAULT NULL,
  p_historical_event_id bigint DEFAULT NULL,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_privat boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tekst IS NULL OR btrim(p_tekst) = '' THEN RAISE EXCEPTION 'Story-tekst må ikke være tom'; END IF;
  PERFORM begin_change_set('red_opret_story',
    format('Oprettede story om %s %s', p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  INSERT INTO story (id, subjekt_type, subjekt_id, haendelse_id, fact_id, relation_id,
                     historical_event_id, titel, tekst, date_min, date_max, date_qualifier,
                     date_raw, privat)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM story), p_subjekt_type, p_subjekt_id,
          p_haendelse_id, p_fact_id, p_relation_id, p_historical_event_id,
          p_titel, p_tekst, p_date_min, p_date_max, p_date_qualifier, p_date_raw, p_privat)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_rediger_story(
  p_story_id bigint, p_tekst text,
  p_titel text DEFAULT NULL, p_haendelse_id bigint DEFAULT NULL,
  p_fact_id bigint DEFAULT NULL, p_relation_id bigint DEFAULT NULL,
  p_historical_event_id bigint DEFAULT NULL,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_privat boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tekst IS NULL OR btrim(p_tekst) = '' THEN RAISE EXCEPTION 'Story-tekst må ikke være tom'; END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_rediger_story',
    format('Redigerede story %s', p_story_id), v_stype, v_sid);
  UPDATE story SET titel=p_titel, tekst=p_tekst, haendelse_id=p_haendelse_id,
    fact_id=p_fact_id, relation_id=p_relation_id, historical_event_id=p_historical_event_id,
    date_min=p_date_min, date_max=p_date_max, date_qualifier=p_date_qualifier,
    date_raw=p_date_raw, privat=p_privat
  WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_set_story_status(p_story_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kladde','klar','publiceret','arkiveret') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig story-status (kladde|klar|publiceret|arkiveret)', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  IF p_status='publiceret'
     AND NOT EXISTS (SELECT 1 FROM story_kilde WHERE story_id=p_story_id) THEN
    RAISE EXCEPTION 'Story % kan ikke publiceres uden mindst én kilde', p_story_id;
  END IF;
  PERFORM begin_change_set('red_set_story_status',
    format('Satte status %s på story %s', p_status, p_story_id), v_stype, v_sid);
  UPDATE story SET status=p_status,
    publiceret_dato=CASE WHEN p_status='publiceret' THEN current_date ELSE publiceret_dato END
  WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_slet_story(p_story_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_slet_story',
    format('Slettede story %s (hård slet — fejloprettelse)', p_story_id), v_stype, v_sid);
  DELETE FROM story WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_set_story_kilder(p_story_id bigint, p_kilder jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint; v_k jsonb; v_next bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_kilder IS NULL OR jsonb_typeof(p_kilder) <> 'array' THEN
    RAISE EXCEPTION 'p_kilder skal være et jsonb-array af {source_id, side?}';
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_set_story_kilder',
    format('Satte kildeliste på story %s', p_story_id), v_stype, v_sid);
  DELETE FROM story_kilde WHERE story_id=p_story_id;
  SELECT coalesce(max(id),0) INTO v_next FROM story_kilde;
  FOR v_k IN SELECT * FROM jsonb_array_elements(p_kilder) LOOP
    IF v_k->>'source_id' IS NULL
       OR NOT EXISTS (SELECT 1 FROM source WHERE id=(v_k->>'source_id')::bigint) THEN
      RAISE EXCEPTION 'Source % findes ikke', v_k->>'source_id';
    END IF;
    v_next := v_next + 1;
    INSERT INTO story_kilde (id, story_id, source_id, side)
    VALUES (v_next, p_story_id, (v_k->>'source_id')::bigint, v_k->>'side');
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION red_set_feed_pin(p_kort_noegle text, p_handling text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_handling NOT IN ('pin','skjul') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig pin-handling (pin|skjul)', p_handling;
  END IF;
  IF p_kort_noegle IS NULL OR btrim(p_kort_noegle)='' THEN
    RAISE EXCEPTION 'kort_noegle må ikke være tom';
  END IF;
  PERFORM begin_change_set('red_set_feed_pin',
    format('Satte %s på kort %s', p_handling, p_kort_noegle), NULL, NULL);
  INSERT INTO feed_pin (id, kort_noegle, handling)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM feed_pin), p_kort_noegle, p_handling)
  ON CONFLICT (kort_noegle) DO UPDATE
    SET handling=excluded.handling, oprettet_af=auth.uid(), oprettet_naar=now();
END $$;

CREATE OR REPLACE FUNCTION red_fjern_feed_pin(p_kort_noegle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM feed_pin WHERE kort_noegle=p_kort_noegle) THEN
    RAISE EXCEPTION 'Ingen pin/skjul på %', p_kort_noegle;
  END IF;
  PERFORM begin_change_set('red_fjern_feed_pin',
    format('Fjernede kurering af kort %s', p_kort_noegle), NULL, NULL);
  DELETE FROM feed_pin WHERE kort_noegle=p_kort_noegle;
END $$;

DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'red_opret_story(text,bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'red_set_story_status(bigint,text)', 'red_slet_story(bigint)',
    'red_set_story_kilder(bigint,jsonb)', 'red_set_feed_pin(text,text)', 'red_fjern_feed_pin(text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon;', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated;', fn);
  END LOOP;
END $$;

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('story',    ARRAY['id'], ARRAY[]::text[]),
  ('feed_pin', ARRAY['id'], ARRAY[]::text[])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;

DROP TRIGGER IF EXISTS trg_log_story ON story;
CREATE TRIGGER trg_log_story AFTER INSERT OR UPDATE OR DELETE ON story
  FOR EACH ROW EXECUTE FUNCTION log_change();
DROP TRIGGER IF EXISTS trg_log_feed_pin ON feed_pin;
CREATE TRIGGER trg_log_feed_pin AFTER INSERT OR UPDATE OR DELETE ON feed_pin
  FOR EACH ROW EXECUTE FUNCTION log_change();

-- =====================================================================
-- 2026-07-20: K2 — selektiv publicering (person_ids)
-- red_publicer_udgave (2026-07-17) er alt-eller-intet pr. kilde. Redaktøren skal kunne
-- publicere KUN de 1939-personer hvor et samme_som-match allerede er bekræftet, mens
-- resten forbliver staged indtil et korrigeret OCR-udtræk er indlæst (R/update-1939-
-- narratives.R er løsnet samtidig til at tolerere blandet staged-status — se dens
-- kommentar ved read_1939_mapping). I MODSÆTNING til red_publicer_udgave (som er
-- REVOKE'et fra alle roller — kun tiltænkt manuel SQL-editor-kørsel) er denne funktion
-- BEVIDST callable fra app-laget som redaktion (samme mønster som red_samme_som): ingen
-- REVOKE her, gates udelukkende via current_rolle() i funktionskroppen — nødvendigt for
-- at kunne wire en "Publicér valgte"-knap ind i Sammenlign udgaver.
-- =====================================================================
CREATE OR REPLACE FUNCTION red_publicer_personer(p_person_ids bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n integer;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må publicere personer (din rolle: %)', current_rolle();
  END IF;
  IF p_person_ids IS NULL OR array_length(p_person_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'p_person_ids må ikke være tom';
  END IF;
  PERFORM begin_change_set('red_publicer_personer',
    format('Publicerede %s valgt(e) person(er)', array_length(p_person_ids, 1)), NULL, NULL);
  -- Rydder staged for de valgte personer + deres familie-partnere (fx en 1939-ægtefælle-stub
  -- uden eget external_id — samme partner-stub-inklusion som red_publicer_udgave, blot scopet
  -- til udvalget i stedet for hele kilden).
  UPDATE person p SET staged = false
  WHERE p.staged = true
    AND (p.id = ANY(p_person_ids)
      OR EXISTS (SELECT 1 FROM family_member fm1
                 JOIN family_member fm2 ON fm2.family_id = fm1.family_id
                 WHERE fm1.person_id = p.id AND fm2.person_id = ANY(p_person_ids)));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('valgte_person_ids', p_person_ids, 'personer_afstaget', v_n);
END $$;

-- ============================================================
-- 2026-07-22: Præsensliste — faktatype 'overhoved' (vokabular-seed)
-- Ingen skemaændring. Se docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md §4.
-- ============================================================
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','overhoved','Linje-/gren-overhoved — anker for præsenslisten')
ON CONFLICT (scheme, code) DO NOTHING;

-- =====================================================================
-- 2026-07-22: mediehaandtering_fase4_identitet
-- Erstat fil (M4), udrensning + preview (M11), portræt-valg (M10).
-- Additiv jsonb-kolonne relation.kvalifikator (fase 4 bruger {"primaer":true};
-- fremtidig region-tagging deler kolonnen uden ny DDL). relation står i
-- version_pk_registry uden skip-cols → jsonb-rækkesnapshottet bærer den nye
-- kolonne automatisk; INGEN registry-/trigger-/RLS-ændring. Funktionerne er
-- verbatim-kopier af schema.sql (samme signaturer). Nye red_*-funktioner er
-- kaldbare af authenticated via Supabases default-grants (frisk install:
-- db-rls.sql's navnebaserede grant-loop); rolle-gaten sidder i kroppen.
-- Udrens blokerer på ALLE polymorfe ankre (relation/mention/fakta m.
-- evidenskæde/story/narrativ/defensiv note) og sletter i ét atomisk
-- statement (review 34 H1/H2/H3).
-- =====================================================================
ALTER TABLE relation ADD COLUMN IF NOT EXISTS kvalifikator jsonb;

-- (1) red_erstat_media_fil — samme signatur og funktionskrop som schema.sql: ingen overload-/grant-ændring.
CREATE OR REPLACE FUNCTION red_erstat_media_fil(
  p_media_id bigint,
  p_storage_path text, p_mime text, p_byte_size bigint,
  p_bredde int, p_hoejde int, p_sha256 text,
  p_original_filnavn text DEFAULT NULL,
  p_varianter jsonb DEFAULT '[]'
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_egen_sha text; v_v record;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_storage_path),'') IS NULL THEN RAISE EXCEPTION 'Storage-sti er påkrævet'; END IF;
  IF nullif(btrim(p_sha256),'') IS NULL THEN RAISE EXCEPTION 'sha256 er påkrævet'; END IF;
  SELECT upload_status, sha256 INTO v_status, v_egen_sha FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  -- 'kladde' færdiggøres via fase 3's genoptag-flow; 'fjernet' genoprettes først.
  IF v_status <> 'klar' THEN RAISE EXCEPTION 'Kan kun erstatte filen på et klart medie'; END IF;
  -- Dedup-guard, to grene (klientens pre-flight fanger begge FØR bytes uploades; dette er race-bagstopperen):
  IF v_egen_sha = p_sha256 THEN RAISE EXCEPTION 'Filen er identisk med den nuværende'; END IF;
  IF EXISTS (SELECT 1 FROM media WHERE sha256 = p_sha256 AND id <> p_media_id) THEN
    RAISE EXCEPTION 'Medie med samme indhold findes allerede (sha256=%). Genbrug den eksisterende media-række via red_relation.', p_sha256;
  END IF;
  PERFORM begin_change_set('red_erstat_media_fil', format('Erstattede filen på media %s', p_media_id), 'media', p_media_id);
  -- Statustjekket er også del af selve UPDATE'ens WHERE (ikke kun den tidlige SELECT
  -- ovenfor): den tidlige SELECT er en billig fast-fail i det almindelige (ikke-race)
  -- tilfælde, men er IKKE i sig selv den autoritative gate — et konkurrerende
  -- red_fjern_media kan committe mellem SELECT og UPDATE (check-then-act race).
  -- Ved at gøre 'klar'-betingelsen atomisk med selve skrivningen lukkes racet.
  UPDATE media SET
    storage_path = p_storage_path, mime_type = p_mime, byte_size = p_byte_size,
    bredde = p_bredde, hoejde = p_hoejde, sha256 = p_sha256,
    original_filnavn = coalesce(nullif(btrim(p_original_filnavn),''), original_filnavn)
  WHERE id = p_media_id AND upload_status = 'klar';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kan kun erstatte filen på et klart medie';
  END IF;
  FOR v_v IN SELECT * FROM jsonb_to_recordset(coalesce(p_varianter,'[]'::jsonb))
      AS x(tier text, storage_path text, mime text, byte_size bigint, bredde int, hoejde int)
  LOOP
    PERFORM red_registrer_media_variant(p_media_id, v_v.tier, v_v.storage_path,
                                        v_v.mime, v_v.byte_size, v_v.bredde, v_v.hoejde);
  END LOOP;
END $$;

-- (2)+(3) red_udrens_media_preview + red_udrens_media — samme signatur og funktionskrop som schema.sql.
CREATE OR REPLACE FUNCTION red_udrens_media_preview(p_media_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_tilknytninger jsonb; v_mentions jsonb; v_fakta jsonb; v_stories jsonb;
        v_narrativer jsonb; v_noter jsonb; v_forslag jsonb; v_stier jsonb; v_blok text[] := '{}';
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT upload_status INTO v_status FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  -- ALLE relationer (enhver rolle, begge retninger) blokerer — ikke kun 'afbildet'.
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_tilknytninger FROM (
    SELECT id AS relation_id,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN objekt_type ELSE subjekt_type END AS modpart_type,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
       OR (objekt_type='media'  AND objekt_id=p_media_id)
    ORDER BY id) r;
  SELECT coalesce(jsonb_agg(m), '[]'::jsonb) INTO v_mentions FROM (
    SELECT kilde_type, kilde_id FROM text_mention
    WHERE maal_type='media' AND maal_id=p_media_id
    ORDER BY kilde_type, kilde_id) m;
  SELECT coalesce(jsonb_agg(f.id ORDER BY f.id), '[]'::jsonb) INTO v_fakta
    FROM fact f WHERE f.subjekt_type='media' AND f.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(s.id ORDER BY s.id), '[]'::jsonb) INTO v_stories
    FROM story s WHERE s.subjekt_type='media' AND s.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(n.id ORDER BY n.id), '[]'::jsonb) INTO v_narrativer
    FROM narrative n WHERE n.subjekt_type='media' AND n.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(t.id ORDER BY t.id), '[]'::jsonb) INTO v_noter
    FROM note t WHERE t.target_type='media' AND t.target_id=p_media_id;
  SELECT coalesce(jsonb_agg(g.id ORDER BY g.id), '[]'::jsonb) INTO v_forslag
    FROM suggestion g WHERE g.subjekt_type='media' AND g.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(s), '[]'::jsonb) INTO v_stier FROM (
    SELECT bucket, storage_path AS sti, 'media' AS kilde FROM media
      WHERE id=p_media_id AND storage_path IS NOT NULL
    UNION ALL
    SELECT m.bucket, v.storage_path, v.tier FROM media_variant v JOIN media m ON m.id=v.media_id
      WHERE v.media_id=p_media_id) s;
  IF v_status <> 'fjernet' THEN
    v_blok := v_blok || 'Kan kun udrense et fjernet medie — fjern det først (papirkurven)';
  END IF;
  IF jsonb_array_length(v_tilknytninger) > 0 THEN
    v_blok := v_blok || format('%s tilknytning(er) skal fjernes først', jsonb_array_length(v_tilknytninger));
  END IF;
  IF jsonb_array_length(v_mentions) > 0 THEN
    v_blok := v_blok || format('%s narrativ-omtale(r) skal redigeres ud først', jsonb_array_length(v_mentions));
  END IF;
  IF jsonb_array_length(v_fakta) > 0 THEN
    v_blok := v_blok || format('Mediet har rettighedsdokumentation (%s faktum/fakta) — fjern den først', jsonb_array_length(v_fakta));
  END IF;
  IF jsonb_array_length(v_stories) > 0 THEN
    v_blok := v_blok || format('Mediet er subjekt for %s story/stories — flyt eller slet dem først', jsonb_array_length(v_stories));
  END IF;
  IF jsonb_array_length(v_narrativer) > 0 THEN
    v_blok := v_blok || format('Mediet har %s tilknyttet narrativ(er) — slet dem først', jsonb_array_length(v_narrativer));
  END IF;
  IF jsonb_array_length(v_noter) > 0 THEN
    v_blok := v_blok || format('%s note(r) peger på mediet — fjern dem først', jsonb_array_length(v_noter));
  END IF;
  IF jsonb_array_length(v_forslag) > 0 THEN
    v_blok := v_blok || format('Mediet har %s forslag i kø — afvis eller godkend dem først', jsonb_array_length(v_forslag));
  END IF;
  RETURN jsonb_build_object(
    'upload_status', v_status,
    'kan_udrenses', coalesce(array_length(v_blok,1),0) = 0,
    'blokeringer', to_jsonb(v_blok),
    'antal_tilknytninger', jsonb_array_length(v_tilknytninger),
    'antal_mentions', jsonb_array_length(v_mentions),
    'antal_fakta', jsonb_array_length(v_fakta),
    'antal_stories', jsonb_array_length(v_stories),
    'antal_narrativer', jsonb_array_length(v_narrativer),
    'antal_noter', jsonb_array_length(v_noter),
    'antal_forslag', jsonb_array_length(v_forslag),
    'tilknytninger', v_tilknytninger,
    'mentions', v_mentions,
    'fakta', v_fakta,
    'stories', v_stories,
    'narrativer', v_narrativer,
    'noter', v_noter,
    'forslag', v_forslag,
    'stier', v_stier);
END $$;

CREATE OR REPLACE FUNCTION red_udrens_media(p_media_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_stier jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT upload_status INTO v_status FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  IF v_status <> 'fjernet' THEN RAISE EXCEPTION 'Kan kun udrense et fjernet medie'; END IF;
  -- Venlige, kategori-præcise domæne-fejl (det atomiske DELETE nedenfor er den autoritative gate):
  IF EXISTS (SELECT 1 FROM relation
             WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
                OR (objekt_type='media' AND objekt_id=p_media_id)) THEN
    RAISE EXCEPTION 'Mediet har tilknytninger og kan ikke udrenses — fjern dem først';
  END IF;
  IF EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet er nævnt i narrativer og kan ikke udrenses — redigér omtalerne ud først';
  END IF;
  IF EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har rettighedsdokumentation (fakta) og kan ikke udrenses — fjern den først';
  END IF;
  IF EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet er subjekt for en story og kan ikke udrenses — flyt eller slet storyen først';
  END IF;
  IF EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har et tilknyttet narrativ og kan ikke udrenses — slet narrativet først';
  END IF;
  IF EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har noter og kan ikke udrenses — fjern dem først';
  END IF;
  IF EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har forslag i kø og kan ikke udrenses — afvis eller godkend dem først';
  END IF;
  SELECT coalesce(jsonb_agg(s), '[]'::jsonb) INTO v_stier FROM (
    SELECT bucket, storage_path AS sti FROM media WHERE id=p_media_id AND storage_path IS NOT NULL
    UNION ALL
    SELECT m.bucket, v.storage_path FROM media_variant v JOIN media m ON m.id=v.media_id
      WHERE v.media_id=p_media_id) s;
  PERFORM begin_change_set('red_udrens_media', format('Udrensede media %s permanent', p_media_id), 'media', p_media_id);
  -- ÉT atomisk statement (H2): check-then-act kan ikke splittes af en samtidig transaktion.
  DELETE FROM media
   WHERE id = p_media_id
     AND upload_status = 'fjernet'
     AND NOT EXISTS (SELECT 1 FROM relation
                     WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
                        OR (objekt_type='media' AND objekt_id=p_media_id))
     AND NOT EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='media' AND subjekt_id=p_media_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mediet kunne ikke udrenses — tilstanden ændrede sig undervejs, prøv igen';
  END IF;
  RETURN jsonb_build_object('stier', v_stier);
END $$;

-- (4) red_saet_portraet — samme signatur og funktionskrop som schema.sql.
CREATE OR REPLACE FUNCTION red_saet_portraet(p_person_id bigint, p_media_id bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_saet_portraet',
    CASE WHEN p_media_id IS NULL THEN format('Ryddede portræt-valg for person %s', p_person_id)
         ELSE format('Satte media %s som portræt for person %s', p_media_id, p_person_id) END,
    'person', p_person_id);
  -- Nulstil søskende først (én UPDATE): fjern nøglen; tom jsonb normaliseres til NULL.
  UPDATE relation SET kvalifikator = nullif(kvalifikator - 'primaer', '{}'::jsonb)
   WHERE subjekt_type='person' AND subjekt_id=p_person_id
     AND objekt_type='media' AND rolle='afbildet'
     AND kvalifikator ? 'primaer';
  IF p_media_id IS NOT NULL THEN
    UPDATE relation SET kvalifikator = coalesce(kvalifikator,'{}'::jsonb) || '{"primaer":true}'::jsonb
     WHERE subjekt_type='person' AND subjekt_id=p_person_id
       AND objekt_type='media' AND objekt_id=p_media_id AND rolle='afbildet';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
      RAISE EXCEPTION 'Mediet er ikke tilknyttet personen — tilknyt først';
    END IF;
  END IF;
END $$;

-- Præsensliste-redesign 2026-07-24: ny rolle-kode til lineage→coat_of_arms-relationen
-- (linjens våben). Selve relations-/media-/coat_of_arms-rækkerne for de faktiske våben
-- indsættes separat via docs/superpowers/plans/2026-07-24-praesensliste-vaaben-data-runbook.md
-- (redaktionelt indhold — blasonering/billeder — ikke noget en migration skal fabrikere).
INSERT INTO vocab (scheme, code, label) VALUES ('rolle','vaaben','våbenskjold for') ON CONFLICT (scheme, code) DO NOTHING;

-- Præsensliste-redesign 2026-07-24 (rettelse efter bruger-verifikation): lineage.kode er IKKE
-- det samme nummer som præsenslistens "I"/"II" — præsenslisten nummererer kun de nulevende
-- linjer sekventielt og springer uddøde linjer over (i dag: kode='IV' vises som "I linje",
-- kode='V' som "II linje" i præsenslisten). presens_kode er redaktørens eksplicitte, løbende
-- tilknytning af dette — NULL = linjen indgår ikke (endnu) i præsenslisten. Slås ALDRIG op med
-- fallback til kode (ville kollidere: kode='I' er allerede den uddøde Holstenske linje).
ALTER TABLE lineage ADD COLUMN IF NOT EXISTS presens_kode TEXT;
-- Fanger dubletter loudly (DB-fejl) i stedet for at lade to linjer stille dele samme
-- præsens-nummer (reviewfund — hvilken af dem der "vinder" ved opslag ville ellers
-- afhænge af rækkefølge, præcis den fejlklasse denne rettelse lukker).
CREATE UNIQUE INDEX IF NOT EXISTS lineage_presens_kode_uidx ON lineage (presens_kode) WHERE presens_kode IS NOT NULL;

-- =====================================================================
-- 2026-07-24: K2 — app-adgang til bulk-publicering af en hel udgave
-- Funktionen har sin egen interne redaktion-gate ligesom de øvrige red_*-RPC'er.
-- =====================================================================
GRANT EXECUTE ON FUNCTION red_publicer_udgave(bigint) TO authenticated;

-- =====================================================================
-- 2026-07-26: person_ocr_kvalitetsark_identitet
-- Stabile importnøgler og journalens aktuelle korrektionsbeslutning.
-- change_event (via triggeren nedenfor) bevarer den uforanderlige historik.
-- =====================================================================
ALTER TABLE source ADD COLUMN IF NOT EXISTS import_key text;
CREATE UNIQUE INDEX IF NOT EXISTS source_import_key_uidx
  ON source (import_key) WHERE import_key IS NOT NULL;

ALTER TABLE person_external_id ADD COLUMN IF NOT EXISTS record_key text;
CREATE UNIQUE INDEX IF NOT EXISTS person_external_id_source_record_key_uidx
  ON person_external_id (source_id, record_key) WHERE record_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS import_korrektion (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  import_key text NOT NULL,
  record_key text NOT NULL,
  felt text NOT NULL,
  input_fingerprint text NOT NULL,
  importeret jsonb NOT NULL,
  korrigeret jsonb,
  status text NOT NULL,
  actor_id uuid,
  actor_navn text,
  oprettet_at timestamptz NOT NULL DEFAULT now(),
  opdateret_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT import_korrektion_felt_check CHECK (felt IN ('navn','foedsel','doed','koen','post')),
  CONSTRAINT import_korrektion_input_fingerprint_check CHECK (input_fingerprint ~ '^[0-9a-f]{32}$'),
  CONSTRAINT import_korrektion_status_check CHECK (status IN ('aaben','rettet','godkendt','udskudt','stale')),
  CONSTRAINT import_korrektion_import_record_felt_key UNIQUE (import_key, record_key, felt)
);

-- ADD CONSTRAINT IF NOT EXISTS findes ikke i PostgreSQL; gamle/halv-anvendte
-- miljøer afstemmes derfor eksplicit mod kataloget.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.import_korrektion'::regclass
                   AND conname='import_korrektion_felt_check') THEN
    ALTER TABLE import_korrektion ADD CONSTRAINT import_korrektion_felt_check
      CHECK (felt IN ('navn','foedsel','doed','koen','post'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.import_korrektion'::regclass
                   AND conname='import_korrektion_input_fingerprint_check') THEN
    ALTER TABLE import_korrektion ADD CONSTRAINT import_korrektion_input_fingerprint_check
      CHECK (input_fingerprint ~ '^[0-9a-f]{32}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.import_korrektion'::regclass
                   AND conname='import_korrektion_status_check') THEN
    ALTER TABLE import_korrektion ADD CONSTRAINT import_korrektion_status_check
      CHECK (status IN ('aaben','rettet','godkendt','udskudt','stale'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.import_korrektion'::regclass
                   AND conname='import_korrektion_import_record_felt_key') THEN
    ALTER TABLE import_korrektion ADD CONSTRAINT import_korrektion_import_record_felt_key
      UNIQUE (import_key, record_key, felt);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS import_korrektion_status_import_idx
  ON import_korrektion (status, import_key);

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('import_korrektion', ARRAY['id'], ARRAY[]::text[])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;

DROP TRIGGER IF EXISTS trg_log_import_korrektion ON import_korrektion;
CREATE TRIGGER trg_log_import_korrektion AFTER INSERT OR UPDATE OR DELETE ON import_korrektion
  FOR EACH ROW EXECUTE FUNCTION log_change();

-- =====================================================================
-- 2026-07-26: person_ocr_kvalitetsark_grid
-- Set-baseret læseprojektion. Fingerprint-helperen er den delte Task 2-byte-kontrakt;
-- Task 4 skal genbruge den og må ikke indføre en parallel canonicaliser.
-- =====================================================================
-- Fast byte-kontrakt delt af kvalitetsarkets læse- og kommende skrivevej.
-- jsonb bevarer ikke indsat nøgleorden, så teksten bygges eksplicit i Task 2's R-orden
-- før UTF-8/0x1f/MD5. Task 4 skal genbruge denne helper, ikke kopiere logikken.
CREATE OR REPLACE FUNCTION ocr_input_fingerprint(
  p_import_key text, p_record_key text, p_felt text, p_importeret jsonb, p_ocr_context text
) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT md5(concat_ws(chr(31),
    coalesce(p_import_key,''), coalesce(p_record_key,''), coalesce(p_felt,''),
    CASE WHEN p_felt IN ('foedsel','doed') THEN format(
      '{"raw":%s,"min":%s,"max":%s,"qualifier":%s,"calendar":%s,"certainty":%s}',
      coalesce(to_jsonb(p_importeret->>'raw')::text,'null'),
      coalesce(to_jsonb(p_importeret->>'min')::text,'null'),
      coalesce(to_jsonb(p_importeret->>'max')::text,'null'),
      coalesce(to_jsonb(p_importeret->>'qualifier')::text,'null'),
      coalesce(to_jsonb(coalesce(p_importeret->>'calendar','gregoriansk'))::text,'null'),
      coalesce(to_jsonb(p_importeret->>'certainty')::text,'null'))
    ELSE format('{"value":%s}',coalesce(to_jsonb(p_importeret->>'value')::text,'null'))
    END,
    coalesce(p_ocr_context,'')))
$$;

-- Én række pr. fysisk person; alle sidegrene aggregeres før slut-projektionen, så
-- relationer/facts aldrig multiplicerer griddens rækker. Samme-som er kontekst, aldrig collapse.
CREATE OR REPLACE FUNCTION red_person_grid()
RETURNS TABLE (
  person_id bigint, import_key text, record_key text, source_id bigint, source_titel text,
  source_udgave text, linje text, nr integer, slaegtled integer, navn text,
  navn_assertion_id bigint, foedsel_raw text, foedsel_min date, foedsel_max date,
  foedsel_qualifier text, foedsel_assertion_id bigint, doed_raw text, doed_min date,
  doed_max date, doed_qualifier text, doed_assertion_id bigint, input_fingerprint jsonb,
  importeret jsonb, korrigeret jsonb, ocr_context jsonb, kilde_side jsonb, koen text,
  levende boolean, privat boolean, staged boolean, person_status text, kanonisk_person_id bigint,
  samme_som_status text, antal_titler integer, antal_familier integer,
  antal_relationer integer, antal_kilde_assertions integer, qa_koder text[], qa_alvor text,
  review_status jsonb, kan_rettes jsonb, blokarsager jsonb
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
#variable_conflict use_column
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  RETURN QUERY
  WITH external_anchor AS (
    SELECT p.id AS grid_person_id, count(pei.person_id)::integer AS anchor_count,
      count(*) FILTER (WHERE s.import_key IS NOT NULL AND pei.record_key IS NOT NULL)::integer AS stable_anchor_count,
      max(s.import_key) AS import_key, max(pei.record_key) AS record_key, max(s.id) AS source_id,
      max(s.titel) AS source_titel, max(s.udgave) AS source_udgave, max(pei.linje) AS linje,
      max(pei.nr) AS nr, max(pei.slaegtled_lokal) AS slaegtled
    FROM person p LEFT JOIN person_external_id pei ON pei.person_id=p.id
      LEFT JOIN source s ON s.id=pei.source_id
    GROUP BY p.id
  ), selected_assertions AS (
    SELECT f.subjekt_id AS grid_person_id,
      CASE f.faktatype WHEN 'navn' THEN 'navn' WHEN 'fødsel' THEN 'foedsel' WHEN 'død' THEN 'doed' END AS felt,
      a.id AS assertion_id, a.vaerdi_tekst, a.date_raw, a.date_min, a.date_max, a.date_qualifier,
      a.calendar, a.date_certainty
    FROM fact f JOIN conclusion cn ON cn.target_type='fact' AND cn.target_id=f.id
      JOIN assertion a ON a.id=cn.valgt_assertion_id
    WHERE f.subjekt_type='person' AND f.faktatype IN ('navn','fødsel','død') AND cn.status='afklaret'
  ), resolved_rollup AS (
    SELECT grid_person_id,felt,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(vaerdi_tekst) END AS vaerdi_tekst,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_raw) END AS date_raw,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_min) END AS date_min,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_max) END AS date_max,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_qualifier) END AS date_qualifier
    FROM selected_assertions GROUP BY grid_person_id,felt
  ), cited_assertions AS (
    SELECT sa.*, c.source_id, count(c.id)::integer AS citation_count,
      (array_agg(c.citat_tekst ORDER BY c.id))[1] AS ocr_context,
      (array_agg(c.side ORDER BY c.id))[1] AS kilde_side
    FROM selected_assertions sa LEFT JOIN citation c ON c.assertion_id=sa.assertion_id
    GROUP BY sa.grid_person_id,sa.felt,sa.assertion_id,sa.vaerdi_tekst,sa.date_raw,sa.date_min,sa.date_max,
      sa.date_qualifier,sa.calendar,sa.date_certainty,c.source_id
  ), field_candidates AS (
    SELECT ca.grid_person_id,ca.felt,ca.assertion_id,ca.vaerdi_tekst,ca.date_raw,ca.date_min,ca.date_max,
      ca.date_qualifier,ca.ocr_context,ca.kilde_side,
      CASE WHEN ca.felt IN ('foedsel','doed') THEN jsonb_build_object(
        'raw',ca.date_raw,'min',ca.date_min::text,'max',ca.date_max::text,
        'qualifier',ca.date_qualifier,'calendar',coalesce(ca.calendar,'gregoriansk'),'certainty',ca.date_certainty)
      ELSE jsonb_build_object('value',ca.vaerdi_tekst) END AS current_importeret
    FROM cited_assertions ca JOIN external_anchor ea ON ea.grid_person_id=ca.grid_person_id
    WHERE ea.anchor_count=1 AND ea.stable_anchor_count=1 AND ca.source_id=ea.source_id
      AND ca.citation_count > 0
  ), field_rollup AS (
    SELECT grid_person_id,felt,count(DISTINCT assertion_id)::integer AS candidate_count,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(assertion_id) END AS assertion_id,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(vaerdi_tekst) END AS vaerdi_tekst,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_raw) END AS date_raw,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_min) END AS date_min,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_max) END AS date_max,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(date_qualifier) END AS date_qualifier,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(ocr_context) END AS ocr_context,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN min(kilde_side) END AS kilde_side,
      CASE WHEN count(DISTINCT assertion_id)=1 THEN (array_agg(current_importeret ORDER BY assertion_id))[1] END AS current_importeret
    FROM field_candidates GROUP BY grid_person_id,felt
  ), title_counts AS (
    SELECT f.subjekt_id AS grid_person_id,count(*)::integer AS antal_titler FROM fact f
    WHERE f.subjekt_type='person' AND f.faktatype='titel' GROUP BY f.subjekt_id
  ), family_counts AS (
    SELECT person_id AS grid_person_id,count(DISTINCT family_id)::integer AS antal_familier FROM family_member GROUP BY person_id
  ), relation_counts AS (
    SELECT grid_person_id,count(DISTINCT relation_id)::integer AS antal_relationer FROM (
      SELECT subjekt_id AS grid_person_id,id AS relation_id FROM relation WHERE subjekt_type='person'
      UNION ALL SELECT objekt_id,id FROM relation WHERE objekt_type='person') r GROUP BY grid_person_id
  ), citation_counts AS (
    SELECT f.subjekt_id AS grid_person_id,count(DISTINCT a.id)::integer AS antal_kilde_assertions
    FROM fact f JOIN assertion a ON a.target_type='fact' AND a.target_id=f.id JOIN citation c ON c.assertion_id=a.id
    WHERE f.subjekt_type='person' GROUP BY f.subjekt_id
  ), counts AS (
    SELECT p.id AS grid_person_id,coalesce(tc.antal_titler,0) AS antal_titler,coalesce(fc.antal_familier,0) AS antal_familier,
      coalesce(rc.antal_relationer,0) AS antal_relationer,coalesce(cc.antal_kilde_assertions,0) AS antal_kilde_assertions
    FROM person p LEFT JOIN title_counts tc ON tc.grid_person_id=p.id LEFT JOIN family_counts fc ON fc.grid_person_id=p.id
      LEFT JOIN relation_counts rc ON rc.grid_person_id=p.id LEFT JOIN citation_counts cc ON cc.grid_person_id=p.id
  ), same_as_context AS (
    -- Højst ÉN række pr. person. En person midt i en samme_som-kæde er både alias og
    -- kanonisk; de to rækker adskiller sig på samme_som_status og overlevede derfor
    -- GROUP BY'et i den afsluttende SELECT, så samme fysiske person kom ud af griddet
    -- to gange. (Kæder er ikke hypotetiske: enforce_samme_som_invariants() er BEFORE
    -- INSERT og G4 tjekker kun NEW.subjekt, så indsættes den inderste kant først,
    -- slipper den ydre igennem — én person i prod står sådan.) Alias vinder over
    -- kanonisk: det er det stærkere udsagn om personens identitet, og redaktøren skal
    -- kunne se hvem rækken peger på. Laveste kanoniske id bryder resten deterministisk.
    SELECT DISTINCT ON (grid_person_id) grid_person_id,kanonisk_grid_person_id,samme_som_status
    FROM (
      SELECT r.subjekt_id AS grid_person_id,r.objekt_id AS kanonisk_grid_person_id,'alias'::text AS samme_som_status,1 AS prio
      FROM relation r WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
      UNION ALL
      SELECT r.objekt_id,r.objekt_id,'kanonisk'::text,2
      FROM relation r WHERE r.rolle='samme_som' AND r.subjekt_type='person' AND r.objekt_type='person'
    ) s
    ORDER BY grid_person_id,prio,kanonisk_grid_person_id
  ), all_fields AS (
    SELECT p.id AS grid_person_id,v.felt FROM person p CROSS JOIN (VALUES ('navn'::text),('foedsel'),('doed'),('koen')) v(felt)
  ), field_data AS (
    SELECT af.grid_person_id,af.felt,ea.anchor_count,ea.stable_anchor_count,ea.import_key,ea.record_key,ea.source_id,
      ea.source_titel,ea.source_udgave,ea.linje,ea.nr,ea.slaegtled,fr.candidate_count,fr.assertion_id,fr.vaerdi_tekst,fr.date_raw,
      fr.date_min,fr.date_max,fr.date_qualifier,fr.ocr_context,fr.kilde_side,fr.current_importeret,
      rr.vaerdi_tekst AS resolved_vaerdi_tekst,rr.date_raw AS resolved_date_raw,rr.date_min AS resolved_date_min,
      rr.date_max AS resolved_date_max,rr.date_qualifier AS resolved_date_qualifier,
      CASE WHEN af.felt='koen' THEN jsonb_build_object('value',p.koen) ELSE fr.current_importeret END AS base_importeret,
      CASE WHEN af.felt='koen' THEN p.koen ELSE fr.vaerdi_tekst END AS felt_vaerdi
    FROM all_fields af JOIN person p ON p.id=af.grid_person_id JOIN external_anchor ea ON ea.grid_person_id=af.grid_person_id
      LEFT JOIN field_rollup fr ON fr.grid_person_id=af.grid_person_id AND fr.felt=af.felt
      LEFT JOIN resolved_rollup rr ON rr.grid_person_id=af.grid_person_id AND rr.felt=af.felt
  ), journal AS (
    SELECT fd.*,ik.importeret AS journal_importeret,ik.korrigeret,ik.status AS journal_status,
      ik.input_fingerprint AS journal_fingerprint,
      CASE WHEN fd.anchor_count=1 AND fd.stable_anchor_count=1
             AND (fd.felt='koen' OR fd.candidate_count=1)
        THEN ocr_input_fingerprint(fd.import_key,fd.record_key,fd.felt,coalesce(ik.importeret,fd.base_importeret),fd.ocr_context)
      END AS fingerprint
    FROM field_data fd LEFT JOIN import_korrektion ik
      ON ik.import_key=fd.import_key AND ik.record_key=fd.record_key AND ik.felt=fd.felt
  ), field_state AS (
    SELECT j.*,coalesce(j.journal_importeret,j.base_importeret) AS effective_importeret,
      CASE WHEN j.journal_status IS NULL THEN 'aaben'
           WHEN j.fingerprint IS DISTINCT FROM j.journal_fingerprint
             THEN 'stale' ELSE j.journal_status END AS effective_status,
      CASE WHEN j.anchor_count=0 THEN 'ingen_importanker'
           WHEN j.anchor_count<>1 THEN 'flere_importankre'
           WHEN j.stable_anchor_count<>1 AND j.import_key IS NULL THEN 'import_key_mangler'
           WHEN j.stable_anchor_count<>1 THEN 'record_key_mangler'
           WHEN j.felt='koen' THEN NULL
           WHEN coalesce(j.candidate_count,0)=0 THEN 'ingen_kildebelagt_assertion'
           WHEN j.candidate_count>1 THEN 'flere_importerede_facts'
      END AS blokarsag
    FROM journal j
  ), missing_context AS (
    SELECT DISTINCT sa.grid_person_id FROM selected_assertions sa JOIN external_anchor ea ON ea.grid_person_id=sa.grid_person_id
    WHERE ea.anchor_count=1 AND ea.stable_anchor_count=1 AND NOT EXISTS (
      SELECT 1 FROM citation c WHERE c.assertion_id=sa.assertion_id AND c.source_id=ea.source_id
        AND nullif(btrim(c.citat_tekst),'') IS NOT NULL)
  ), qa_items AS (
    SELECT fs.grid_person_id,'mistænkeligt_ocr_tegn'::text AS kode,'advarsel'::text AS alvor FROM field_state fs
      WHERE coalesce(fs.ocr_context,'') ~ '[?�]'
    UNION ALL SELECT sa.grid_person_id,'dato_ufortolkelig','fejl' FROM selected_assertions sa
      WHERE sa.felt IN ('foedsel','doed') AND sa.date_raw IS NOT NULL AND sa.date_min IS NULL AND sa.date_max IS NULL
    UNION ALL SELECT b.grid_person_id,'foedt_efter_doed','fejl' FROM field_state b JOIN field_state d
      ON d.grid_person_id=b.grid_person_id AND d.felt='doed'
      WHERE b.felt='foedsel' AND b.date_min IS NOT NULL AND d.date_max IS NOT NULL AND b.date_min>d.date_max
    UNION ALL SELECT fs.grid_person_id,'struktureret_afviger_fra_ocr','advarsel' FROM field_state fs
      WHERE fs.felt='navn' AND fs.felt_vaerdi IS NOT NULL AND fs.ocr_context IS NOT NULL AND btrim(fs.felt_vaerdi)<>btrim(fs.ocr_context)
    -- navn_mangler måler PRÆCIS den værdi griddet viser — ikke om rækken kan rettes.
    -- candidate_count/felt_vaerdi er anker-gatede; visningen falder tilbage til
    -- resolved_vaerdi_tekst. Målte koden på de gatede felter, flagede den hver eneste
    -- ikke-redigerbar række, uanset at navnet stod der. Redigerbarhed hører til
    -- kan_rettes/blokarsager; at blande de to gav 1169 falske flag ud af 1757.
    UNION ALL SELECT fs.grid_person_id,'navn_mangler','fejl' FROM field_state fs
      WHERE fs.felt='navn' AND nullif(btrim(coalesce(fs.felt_vaerdi,fs.resolved_vaerdi_tekst)),'') IS NULL
    UNION ALL SELECT fs.grid_person_id,'record_key_mangler','fejl' FROM field_state fs
      WHERE fs.anchor_count=1 AND fs.stable_anchor_count=0 AND fs.record_key IS NULL
    UNION ALL SELECT grid_person_id,'ocr_kontekst_mangler','advarsel' FROM missing_context
    UNION ALL SELECT fs.grid_person_id,'flere_importerede_facts','fejl' FROM field_state fs
      WHERE fs.felt IN ('navn','foedsel','doed') AND fs.candidate_count>1
    UNION ALL SELECT fs.grid_person_id,'kilde_aendret','advarsel' FROM field_state fs WHERE fs.effective_status='stale'
  ), qa AS (
    SELECT grid_person_id,array_agg(DISTINCT kode ORDER BY kode) AS qa_koder,
      CASE WHEN bool_or(alvor='fejl') THEN 'fejl' WHEN bool_or(alvor='advarsel') THEN 'advarsel' ELSE 'info' END AS qa_alvor
    FROM qa_items GROUP BY grid_person_id
  ), field_json AS (
    SELECT grid_person_id,
      jsonb_object_agg(felt,effective_status) AS review_status,
      jsonb_object_agg(felt,(blokarsag IS NULL)) AS kan_rettes,
      coalesce(jsonb_object_agg(felt,blokarsag) FILTER (WHERE blokarsag IS NOT NULL),'{}'::jsonb) AS blokarsager,
      jsonb_object_agg(felt,to_jsonb(fingerprint)) FILTER (WHERE fingerprint IS NOT NULL) AS input_fingerprint,
      jsonb_object_agg(felt,effective_importeret) FILTER (WHERE effective_importeret IS NOT NULL) AS importeret,
      jsonb_object_agg(felt,korrigeret) FILTER (WHERE korrigeret IS NOT NULL) AS korrigeret,
      jsonb_object_agg(felt,to_jsonb(ocr_context)) FILTER (WHERE ocr_context IS NOT NULL) AS ocr_context,
      jsonb_object_agg(felt,to_jsonb(kilde_side)) FILTER (WHERE kilde_side IS NOT NULL) AS kilde_side
    FROM field_state GROUP BY grid_person_id
  )
  SELECT p.id,ea.import_key,ea.record_key,ea.source_id,ea.source_titel,ea.source_udgave,ea.linje,ea.nr,ea.slaegtled,
    coalesce(max(fs.felt_vaerdi) FILTER (WHERE fs.felt='navn'),max(fs.resolved_vaerdi_tekst) FILTER (WHERE fs.felt='navn')),max(fs.assertion_id) FILTER (WHERE fs.felt='navn'),
    coalesce(max(fs.date_raw) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_raw) FILTER (WHERE fs.felt='foedsel')),
    coalesce(max(fs.date_min) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_min) FILTER (WHERE fs.felt='foedsel')),
    coalesce(max(fs.date_max) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_max) FILTER (WHERE fs.felt='foedsel')),
    coalesce(max(fs.date_qualifier) FILTER (WHERE fs.felt='foedsel'),max(fs.resolved_date_qualifier) FILTER (WHERE fs.felt='foedsel')),
    max(fs.assertion_id) FILTER (WHERE fs.felt='foedsel'),
    coalesce(max(fs.date_raw) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_raw) FILTER (WHERE fs.felt='doed')),
    coalesce(max(fs.date_min) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_min) FILTER (WHERE fs.felt='doed')),
    coalesce(max(fs.date_max) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_max) FILTER (WHERE fs.felt='doed')),
    coalesce(max(fs.date_qualifier) FILTER (WHERE fs.felt='doed'),max(fs.resolved_date_qualifier) FILTER (WHERE fs.felt='doed')),
    max(fs.assertion_id) FILTER (WHERE fs.felt='doed'),
    coalesce(fj.input_fingerprint,'{}'::jsonb),coalesce(fj.importeret,'{}'::jsonb),coalesce(fj.korrigeret,'{}'::jsonb),coalesce(fj.ocr_context,'{}'::jsonb),coalesce(fj.kilde_side,'{}'::jsonb),
    p.koen,p.levende,p.privat,p.staged,p.status,sac.kanonisk_grid_person_id,sac.samme_som_status,
    coalesce(ct.antal_titler,0),coalesce(ct.antal_familier,0),coalesce(ct.antal_relationer,0),coalesce(ct.antal_kilde_assertions,0),
    coalesce(q.qa_koder,ARRAY[]::text[]),q.qa_alvor,coalesce(fj.review_status,'{}'::jsonb),coalesce(fj.kan_rettes,'{}'::jsonb),coalesce(fj.blokarsager,'{}'::jsonb)
  FROM person p JOIN external_anchor ea ON ea.grid_person_id=p.id JOIN field_state fs ON fs.grid_person_id=p.id
    LEFT JOIN counts ct ON ct.grid_person_id=p.id LEFT JOIN same_as_context sac ON sac.grid_person_id=p.id
    LEFT JOIN qa q ON q.grid_person_id=p.id LEFT JOIN field_json fj ON fj.grid_person_id=p.id
  GROUP BY p.id,ea.import_key,ea.record_key,ea.source_id,ea.source_titel,ea.source_udgave,ea.linje,ea.nr,ea.slaegtled,
    p.koen,p.levende,p.privat,p.staged,p.status,sac.kanonisk_grid_person_id,sac.samme_som_status,ct.antal_titler,ct.antal_familier,
    ct.antal_relationer,ct.antal_kilde_assertions,q.qa_koder,q.qa_alvor,fj.input_fingerprint,fj.importeret,fj.korrigeret,
    fj.ocr_context,fj.kilde_side,fj.review_status,fj.kan_rettes,fj.blokarsager;
END $$;

-- 2026-07-26: person_ocr_kvalitetsark_rettelse (efter journal + fingerprint)
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION private.ocr_importeret(p_felt text,p_vaerdi text,p_raw text,p_min date,p_max date,p_qualifier text,p_calendar text,p_certainty text) RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,pg_temp AS $$ SELECT CASE WHEN p_felt IN ('foedsel','doed') THEN jsonb_build_object('raw',p_raw,'min',p_min::text,'max',p_max::text,'qualifier',p_qualifier,'calendar',coalesce(p_calendar,'gregoriansk'),'certainty',p_certainty) ELSE jsonb_build_object('value',p_vaerdi) END $$;
CREATE OR REPLACE FUNCTION private.ocr_fingerprint(p_import_key text,p_record_key text,p_felt text,p_importeret jsonb,p_ocr_context text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,pg_temp AS $$ SELECT public.ocr_input_fingerprint(p_import_key,p_record_key,p_felt,p_importeret,p_ocr_context) $$;
REVOKE ALL ON FUNCTION private.ocr_importeret(text,text,text,date,date,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.ocr_fingerprint(text,text,text,jsonb,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION red_ret_ocr_felt(p_person_id bigint,p_import_key text,p_record_key text,p_felt text,p_input_fingerprint text,p_korrigeret jsonb,p_status text DEFAULT 'rettet',p_actor_navn text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s bigint; ap bigint; ac int; pc int; aid bigint; cc int; ctx text; observed jsonb; j import_korrektion%ROWTYPE; imp jsonb; fp text; actor text; dmin date; dmax date; out jsonb;
BEGIN
 IF current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'OCR_ROLE_FORBIDDEN'; END IF;
 IF p_felt NOT IN ('navn','foedsel','doed','koen') THEN RAISE EXCEPTION 'OCR_FIELD_INVALID'; END IF;
 IF p_status NOT IN ('rettet','godkendt','udskudt') OR (p_status='rettet' AND p_korrigeret IS NULL) OR (p_status<>'rettet' AND p_korrigeret IS NOT NULL) THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF;
 WITH anchor_rows AS (SELECT pei.person_id,src.id AS source_id FROM source src JOIN person_external_id pei ON pei.source_id=src.id WHERE src.import_key=p_import_key AND pei.record_key=p_record_key FOR UPDATE OF src,pei) SELECT count(*),min(person_id),min(source_id) INTO ac,ap,s FROM anchor_rows;
 IF ac<>1 THEN RAISE EXCEPTION 'OCR_IMPORT_ANCHOR_AMBIGUOUS'; END IF; IF ap<>p_person_id THEN RAISE EXCEPTION 'OCR_PERSON_NOT_FOUND'; END IF;
 SELECT count(*) INTO pc FROM person_external_id pei JOIN source src ON src.id=pei.source_id WHERE pei.person_id=p_person_id AND src.import_key IS NOT NULL AND pei.record_key IS NOT NULL;
 IF pc<>1 THEN RAISE EXCEPTION 'OCR_IMPORT_ANCHOR_AMBIGUOUS'; END IF; PERFORM 1 FROM person WHERE id=p_person_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'OCR_PERSON_NOT_FOUND'; END IF;
 IF p_felt='koen' THEN SELECT private.ocr_importeret('koen',koen,NULL,NULL,NULL,NULL,NULL,NULL) INTO observed FROM person WHERE id=p_person_id; ctx:=NULL;
 ELSE WITH c AS (SELECT DISTINCT a.id FROM fact f JOIN conclusion cn ON cn.target_type='fact' AND cn.target_id=f.id JOIN assertion a ON a.id=cn.valgt_assertion_id JOIN citation ci ON ci.assertion_id=a.id AND ci.source_id=s WHERE f.subjekt_type='person' AND f.subjekt_id=p_person_id AND cn.status='afklaret' AND f.faktatype=CASE p_felt WHEN 'navn' THEN 'navn' WHEN 'foedsel' THEN 'fødsel' ELSE 'død' END) SELECT count(*),min(id) INTO cc,aid FROM c; IF cc<>1 THEN RAISE EXCEPTION 'OCR_ASSERTION_AMBIGUOUS'; END IF; SELECT private.ocr_importeret(p_felt,a.vaerdi_tekst,a.date_raw,a.date_min,a.date_max,a.date_qualifier,a.calendar,a.date_certainty),ci.citat_tekst INTO observed,ctx FROM assertion a JOIN citation ci ON ci.assertion_id=a.id AND ci.source_id=s WHERE a.id=aid ORDER BY ci.id LIMIT 1 FOR UPDATE OF a,ci; IF NOT FOUND THEN RAISE EXCEPTION 'OCR_ASSERTION_AMBIGUOUS'; END IF; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws(chr(31),p_import_key,p_record_key,p_felt),0)); SELECT * INTO j FROM import_korrektion WHERE import_key=p_import_key AND record_key=p_record_key AND felt=p_felt FOR UPDATE; imp:=coalesce(j.importeret,observed); fp:=private.ocr_fingerprint(p_import_key,p_record_key,p_felt,imp,ctx); IF j.id IS NOT NULL AND j.input_fingerprint IS DISTINCT FROM fp THEN RAISE EXCEPTION 'OCR_FINGERPRINT_STALE'; END IF; IF p_input_fingerprint IS DISTINCT FROM coalesce(j.input_fingerprint,fp) THEN RAISE EXCEPTION 'OCR_FINGERPRINT_STALE'; END IF;
 IF p_status='rettet' THEN IF jsonb_typeof(p_korrigeret)<>'object' THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF; IF p_felt='navn' AND (jsonb_typeof(p_korrigeret->'value')<>'string' OR nullif(btrim(p_korrigeret->>'value'),'') IS NULL) THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF; IF p_felt='koen' AND p_korrigeret->>'value' NOT IN ('mand','kvinde','ukendt') THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF; IF p_felt IN ('foedsel','doed') THEN IF jsonb_typeof(p_korrigeret->'raw')<>'string' OR nullif(btrim(p_korrigeret->>'raw'),'') IS NULL THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END IF; BEGIN dmin:=nullif(p_korrigeret->>'min','')::date; dmax:=nullif(p_korrigeret->>'max','')::date; EXCEPTION WHEN others THEN RAISE EXCEPTION 'OCR_VALUE_INVALID'; END; END IF; END IF;
 SELECT coalesce(pr.navn,pr.email,p_actor_navn,auth.uid()::text,'ukendt') INTO actor FROM profiles pr WHERE pr.id=auth.uid(); actor:=coalesce(actor,p_actor_navn,'ukendt'); PERFORM begin_change_set('red_ret_ocr_felt',format('OCR-%s: %s/%s',p_felt,p_import_key,p_record_key),'person',p_person_id);
 IF p_status='rettet' THEN IF p_felt='navn' THEN UPDATE assertion SET vaerdi_tekst=p_korrigeret->>'value' WHERE id=aid; ELSIF p_felt='koen' THEN UPDATE person SET koen=p_korrigeret->>'value' WHERE id=p_person_id; ELSE UPDATE assertion SET date_raw=p_korrigeret->>'raw',date_min=dmin,date_max=dmax,date_qualifier=p_korrigeret->>'qualifier',calendar=coalesce(p_korrigeret->>'calendar','gregoriansk'),date_certainty=p_korrigeret->>'certainty' WHERE id=aid; END IF; END IF;
 INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,korrigeret,status,actor_id,actor_navn) VALUES(p_import_key,p_record_key,p_felt,fp,imp,CASE WHEN p_status='rettet' THEN p_korrigeret ELSE NULL END,p_status,auth.uid(),actor) ON CONFLICT(import_key,record_key,felt) DO UPDATE SET input_fingerprint=import_korrektion.input_fingerprint,korrigeret=CASE WHEN excluded.status='rettet' THEN excluded.korrigeret ELSE import_korrektion.korrigeret END,status=excluded.status,actor_id=excluded.actor_id,actor_navn=excluded.actor_navn,opdateret_at=now(); SELECT to_jsonb(g) INTO out FROM red_person_grid() g WHERE g.person_id=p_person_id; RETURN out;
END $$;
CREATE OR REPLACE FUNCTION red_ocr_historik(p_import_key text,p_record_key text,p_felt text) RETURNS TABLE(change_set_id bigint,changed_at timestamptz,actor_navn text,operation text,foer jsonb,efter jsonb) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE jid bigint; BEGIN IF current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'OCR_ROLE_FORBIDDEN'; END IF; SELECT id INTO jid FROM import_korrektion WHERE import_key=p_import_key AND record_key=p_record_key AND felt=p_felt; IF jid IS NULL THEN RETURN; END IF; RETURN QUERY SELECT cs.id,cs.created_at,cs.actor_navn,cs.operation,ce.foer,ce.efter FROM change_event ce JOIN change_set cs ON cs.id=ce.change_set_id WHERE ce.tabel='import_korrektion' AND ce.row_pk->>'id'=jid::text ORDER BY cs.created_at DESC,cs.id DESC,ce.seq DESC; END $$;
