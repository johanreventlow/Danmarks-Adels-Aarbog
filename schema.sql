-- =====================================================================
--  Datamodel — konkret skema (PoC: Reventlow / DAA-følgesvend)
--  Mål: PostgreSQL/Supabase og DuckDB (standard SQL).  Evidensbaseret kerne + generisk relation.
--
--  Konventioner:
--   * Surrogat-PK (BIGINT). Bogens (linje, nr.) lever i person_external_id.
--   * Fuzzy dato = (date_min, date_max) interval + kvalifikator + rå tekst.
--       exact:      min = max
--       før/efter:  kun max / kun min sat
--       interval:   min < max ("1353/1356")
--       floruit:    dokumenteret-aktiv span, distinkt fra levetid
--       åben:       max IS NULL (igangværende / til død)
--   * Polymorfe referencer = (type, id)-par (ingen hård FK), så samme
--     mekanisme kan pege på enhver entitet.
-- =====================================================================

-- ---------- KONTROLLERET VOKABULAR ----------
CREATE TABLE vocab (              -- roller, faktatyper, dekorationer, forkortelser
  scheme TEXT NOT NULL,           -- 'rolle' | 'faktatype' | 'dekoration' | 'forkortelse'
  code   TEXT NOT NULL,
  label  TEXT NOT NULL,
  PRIMARY KEY (scheme, code)
);

-- ---------- KILDE-/EVIDENS-INFRASTRUKTUR ----------
CREATE TABLE repository (
  id      BIGINT PRIMARY KEY,
  navn    TEXT NOT NULL,
  adresse TEXT                    -- fysisk placering af arkivet (TNG: tng_addresses)
);

CREATE TABLE source (             -- = kilde/værk; også DAA-udgaver og eksterne værker
  id            BIGINT PRIMARY KEY,
  slags         TEXT,             -- 'kirkebog','DAA-udgave','diplomsamling','bog','artikel','segl'
  titel         TEXT,
  udgave        TEXT,             -- fx 'DAA 2018-20', 'DAA 1982-84'
  ekstern       BOOLEAN DEFAULT FALSE,   -- eksternt referenceværk (Gotha, ES, DBL ...)
  repository_id BIGINT REFERENCES repository(id)
);

-- ---------- KONTEKST-ENTITETER ----------
CREATE TABLE place (
  id        BIGINT PRIMARY KEY,
  navn      TEXT,
  type      TEXT,                 -- 'sogn','herred','amt','kreds','land'
  parent_id BIGINT,               -- hierarki (self-ref, ingen hård FK)
  lat DOUBLE PRECISION, lon DOUBLE PRECISION
);

CREATE TABLE organisation (
  id    BIGINT PRIMARY KEY,
  navn  TEXT,
  slags TEXT                      -- 'amt','regiment','hof','institution','ridderorden'
);

CREATE TABLE estate (             -- EJENDOM: gods/len/stamhus/lensgrevskab
  id      BIGINT PRIMARY KEY,
  navn    TEXT,
  slags   TEXT,
  sted_id BIGINT REFERENCES place(id)
);

CREATE TABLE media (
  id       BIGINT PRIMARY KEY,
  slags    TEXT,                  -- 'foto','maleri','segl','scanning'
  titel    TEXT,
  kunstner TEXT,                  -- ekstern skaber (intern skaber = relation)
  datering TEXT
);

CREATE TABLE historical_event (
  id   BIGINT PRIMARY KEY,
  navn TEXT
);

CREATE TABLE coat_of_arms (       -- VÅBEN
  id          BIGINT PRIMARY KEY,
  blasonering TEXT,               -- skjold / hjelmklæde / hjelmtegn
  note        TEXT
);

-- ---------- KERNE: PERSON & FAMILIE ----------
CREATE TABLE person (
  id            BIGINT PRIMARY KEY,
  levende       BOOLEAN DEFAULT FALSE,   -- GDPR: AFLEDT synlighed (levende vs. afdød)
  privat        BOOLEAN DEFAULT FALSE,   -- GDPR: MANUEL skjulning, uafhængig af levende (TNG: living vs. private)
  status        TEXT,                    -- fx 'kendt hul / ikke undersøgt'
  koen          TEXT CHECK (koen IN ('mand','kvinde','ukendt')),  -- vocab 'koen'; NULL = ikke registreret. Arbejdsværdi; afledes af konklusion hvis omstridt.
  -- afledt visnings-cache (envejs-projektion af konklusioner; redigeres ALDRIG direkte):
  visning_navn  TEXT,
  visning_foedt TEXT,
  visning_doed  TEXT,
  visning_titel TEXT
);

CREATE TABLE person_external_id (        -- bogens (linje, nr.) som eksternt ID
  person_id BIGINT REFERENCES person(id),
  source_id BIGINT REFERENCES source(id),
  linje     TEXT,                        -- 'I','V', ... — rå bog-token (proveniens); join til lineage.kode
  nr        INTEGER,
  PRIMARY KEY (person_id, source_id)
);

CREATE TABLE lineage (                   -- SLÆGTSLINJE / GREN (fx Reventlows fem linjer)
  id        BIGINT PRIMARY KEY,
  source_id BIGINT REFERENCES source(id),  -- hvilken udgaves linje-inddeling
  kode      TEXT,                          -- 'I'..'V' — matcher person_external_id.linje
  navn      TEXT NOT NULL,                 -- 'Den holstenske linje', ...
  -- (b) PROMOVERING (2026-06-30): forgrening + status. Tilføjet additivt; ældre rækker har NULL.
  parent_lineage_id BIGINT REFERENCES lineage(id),  -- forgrening: gren udgår af gren (NULL = rod)
  status    TEXT,                          -- fri tekst, fx 'uddød', 'kendt hul / ikke undersøgt'
  UNIQUE (source_id, kode)
  -- Resten af (b) kræver INGEN skema-ændring — den rider på de polymorfe evidens-tabeller:
  --   * fact     subjekt_type='lineage'  → adling, floruit, alternative navne m. evidens
  --   * relation lineage→coat_of_arms / →source / person→lineage (konfidens på medlemskab)
  -- En linje der adles → ny lineage-række + relation rolle='gren_af' til moderlinjen
  --   (parent_lineage_id er den hurtige FK; 'gren_af'-relationen bærer evidens/konfidens).
  -- Jf. datamodel-oversigt §5/§9.
);

-- ---------- AUTH / REDAKTION ----------
CREATE TABLE profiles (              -- 1:1 med auth.users; bærer rolle + binding til træet
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  rolle               TEXT NOT NULL DEFAULT 'medlem'
                        CHECK (rolle IN ('redaktion','medlem')),
  reventlow_person_id BIGINT REFERENCES person(id),
  email               TEXT
);

CREATE TABLE suggestion (            -- staging: ikke-redaktion-forslag (manuelt re-anvendt)
  id              BIGINT PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  forslagsstiller UUID REFERENCES auth.users(id),
  status          TEXT NOT NULL DEFAULT 'afventer',  -- PoC: kun 'afventer'
  art             TEXT,
  subjekt_type    TEXT, subjekt_id BIGINT,
  felt            TEXT, vaerdi TEXT,
  kilde_source_id BIGINT REFERENCES source(id),
  kilde_fritekst  TEXT,
  payload         JSONB DEFAULT '{}'::jsonb,
  note            TEXT
);
-- RLS slås til ved oprettelse (deny-all indtil politikker + grants lander i db-rls.sql).
ALTER TABLE profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE suggestion ENABLE ROW LEVEL SECURITY;

CREATE TABLE family (                    -- union/partnerskab
  id   BIGINT PRIMARY KEY,
  type TEXT                              -- 'vielse','partnerskab','ugift union'
);

CREATE TABLE family_member (             -- FAMC/FAMS: person i familie med rolle
  family_id BIGINT REFERENCES family(id),
  person_id BIGINT REFERENCES person(id),
  rolle     TEXT NOT NULL,               -- 'partner' | 'barn' | 'adopteret_barn' | 'plejebarn' | 'stedbarn'
                                         --   (barn-subtyper afgør blodslægtskab: kun 'barn' tæller genetisk i finderen; jf. TNG frel/mrel)
  ordinal   INTEGER,                     -- ægteskab 1°/2° for partner
  konfidens TEXT,                        -- 'sikker'|'sandsynlig'|'formodet'|'omstridt' (NULL = uangivet). Omstridte hypoteser med kilder ligger i evidenslaget.
  PRIMARY KEY (family_id, person_id, rolle)
);

-- ---------- FAKTA (events/attributter) ----------
CREATE TABLE fact (                      -- "slot": ét forhold om en person/familie
  id           BIGINT PRIMARY KEY,
  subjekt_type TEXT NOT NULL,            -- enhver entitet: 'person','family','place','estate','coat_of_arms' ...
  subjekt_id   BIGINT NOT NULL,
  faktatype    TEXT NOT NULL,            -- 'navn','tilnavn','fødsel','død','floruit','erhverv','titel','dødsårsag'...
  sted_id      BIGINT REFERENCES place(id)
);
-- BEVIDST INGEN ekstra kolonner her (jf. invariant #2 — genbrug mekanismer):
--   * dødsårsag  = eget fact ('dødsårsag') hvor det bærer vægt; ellers narrative/note.
--   * alder-ved-hændelse = udledes af datoer, gemmes ikke separat.
--   * "hvem udførte" (præst v. dåb, monark v. tildeling) = relation (person/org -> fact, rolle 'udførte').
--   * media-ejer / nuværende placering = relation ('ejer' / 'placeret_på' -> ejendom/sted), ikke kolonne på media.

-- ---------- GENERISK RELATION ----------
CREATE TABLE relation (
  id            BIGINT PRIMARY KEY,
  subjekt_type  TEXT NOT NULL,           -- polymorf
  subjekt_id    BIGINT NOT NULL,
  objekt_type   TEXT NOT NULL,           -- polymorf (estate, organisation, media, event, coa, person ...)
  objekt_id     BIGINT NOT NULL,
  rolle         TEXT NOT NULL,           -- 'ejer','afbildet','skabt_af','forfatter','m.a.','deltager'...
  erhvervelsesmaade TEXT,                -- 'født/arvet','tildelt','knyttet_til_ejendom'
  start_min DATE, start_max DATE,        -- fuzzy periode
  end_min   DATE, end_max   DATE,
  period_type TEXT,                      -- 'closed','open_start','open_end','ongoing','floruit','until_event'
  periode_raw TEXT,
  konfidens   TEXT
);

-- ---------- EVIDENS: PÅSTAND / KONKLUSION / CITATION ----------
CREATE TABLE assertion (                 -- én kildes udsagn om et FACT ELLER en RELATION
  id             BIGINT PRIMARY KEY,
  target_type    TEXT NOT NULL,          -- 'fact' | 'relation'
  target_id      BIGINT NOT NULL,
  vaerdi_tekst   TEXT,                   -- navn, erhverv, titel, stednavn ...
  date_min DATE, date_max DATE,          -- hvis dato-værdi (fuzzy)
  date_qualifier TEXT,                   -- 'exact','before','after','between','floruit','about'
  date_raw       TEXT,                   -- oprindelig tekst, fx '† før 1261 (22. aug.)'
  calendar       TEXT DEFAULT 'gregoriansk',
  uforanderlig   BOOLEAN DEFAULT TRUE
);

CREATE TABLE conclusion (                -- den blåstemplede vurdering ovenpå påstandene
  id                BIGINT PRIMARY KEY,
  target_type       TEXT NOT NULL,       -- 'fact' | 'relation'
  target_id         BIGINT NOT NULL,
  valgt_assertion_id BIGINT REFERENCES assertion(id),
  status            TEXT,                -- 'afklaret','omstridt','forældet'
  blaastemplet_af   TEXT,                -- udgave eller beslutning (proveniens)
  blaastemplet_naar DATE,
  UNIQUE (target_type, target_id)
);

CREATE TABLE citation (
  id           BIGINT PRIMARY KEY,
  assertion_id BIGINT REFERENCES assertion(id),
  source_id    BIGINT REFERENCES source(id),
  side         TEXT,
  citat_tekst  TEXT,                     -- ordret transskriberet kildeuddrag (TNG: citetext) — bevarer det kilden faktisk skriver
  citat_dato   TEXT,                     -- rå dato for citatet/optegnelsen (TNG: citedate)
  kvalitet     TEXT                      -- 'primær','sekundær','tvivlsom' (TNG QUAY 0-3 mapper hertil)
);

-- ---------- TVÆRGÅENDE ----------
CREATE TABLE note (
  id          BIGINT PRIMARY KEY,
  target_type TEXT NOT NULL,             -- polymorf: 'person','family','fact','relation',... (en note kan hænge på ét faktum, jf. TNG notelinks.eventID)
  target_id   BIGINT NOT NULL,
  indhold     TEXT,
  privat      BOOLEAN DEFAULT FALSE      -- GDPR: skjult note (TNG: notelinks.secret)
);

CREATE TABLE narrative (          -- bevaret biografisk prosa (substrat); fakta udtrækkes selektivt ovenpå
  id           BIGINT PRIMARY KEY,
  subjekt_type TEXT NOT NULL,     -- 'person' | 'family' | 'line' ...
  subjekt_id   BIGINT NOT NULL,
  source_id    BIGINT REFERENCES source(id),
  side         TEXT,              -- fx '209-211'
  tekst        TEXT NOT NULL,
  privat       BOOLEAN DEFAULT FALSE   -- GDPR: skjult narrativ (levende-biografi); jf. TNG secret-flag
);

-- ---------- CACHE-REGENERERING & TRIGGERS ----------
-- Recompute cache-felter fra personens konklusioner. Læser den VALGTE assertions værdi
-- pr. faktatype. Dato-fakta (fødsel/død) bruger coalesce(date_raw, vaerdi_tekst).
CREATE OR REPLACE FUNCTION regen_person_visning(pid BIGINT)
RETURNS void LANGUAGE sql AS $$
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
RETURNS trigger LANGUAGE plpgsql AS $$
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
RETURNS trigger LANGUAGE plpgsql AS $$
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

-- ---------- REDAKTIONS-RPC'ER (Task 3) ----------

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

-- Operation A: tilføj en OPLYSNING (assertion + citation) til et EKSISTERENDE fact.
-- Rører IKKE conclusion — den nye oplysning er en kandidat; vælg den med red_set_konklusion.
-- (fact-kardinalitet: per-kort "+ tilføj oplysning" målretter dette specifikke fact.)
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

-- Operation B: opret et NYT distinkt fact (+ assertion + citation + conclusion). ALTID nyt
-- (modsat red_upsert_fakta's find-or-create) → tillader flere facts pr. faktatype (fx ny titel).
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
-- Append-baseret edit: bevarer den gamle påstand (invariant #1), opretter ny + re-peger
-- konklusion via INTERN logik (ikke red_set_konklusion-RPC → undgår nested change_set, B7).
-- void → jsonb: kræver DROP FUNCTION før CREATE i db-migrations.sql.
CREATE OR REPLACE FUNCTION red_edit_oplysning(
  p_assertion_id bigint, p_vaerdi text, p_date_raw text DEFAULT NULL, p_kilde_fritekst text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_tt text; v_tid bigint; v_old assertion; v_new bigint; v_cit bigint;
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

-- ---------- INDEKSER (relations-/evidens-opslag; UI + traversal) ----------
CREATE INDEX IF NOT EXISTS ix_fammember_person   ON family_member(person_id);
CREATE INDEX IF NOT EXISTS ix_fammember_family   ON family_member(family_id);
CREATE INDEX IF NOT EXISTS ix_extid_linje_nr     ON person_external_id(linje, nr);
CREATE INDEX IF NOT EXISTS ix_extid_person       ON person_external_id(person_id);
CREATE INDEX IF NOT EXISTS ix_lineage_src_kode   ON lineage(source_id, kode);
CREATE INDEX IF NOT EXISTS ix_fact_subjekt       ON fact(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_assertion_target   ON assertion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_conclusion_target  ON conclusion(target_type, target_id);
CREATE INDEX IF NOT EXISTS ix_citation_assertion ON citation(assertion_id);
CREATE INDEX IF NOT EXISTS ix_relation_subjekt   ON relation(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_relation_objekt    ON relation(objekt_type, objekt_id);
CREATE INDEX IF NOT EXISTS ix_narrative_subjekt  ON narrative(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_person_visningnavn ON person(visning_navn);

-- --- KUN PostgreSQL/Supabase: fuldtekstindeks på narrativ (kør separat; DuckDB understøtter ikke tsvector) ---
-- ALTER TABLE narrative ADD COLUMN fts tsvector
--   GENERATED ALWAYS AS (to_tsvector('danish', coalesce(tekst,''))) STORED;
-- CREATE INDEX narrative_fts_idx ON narrative USING GIN (fts);

-- ---------- REDAKTIONS-RPC'ER (Task 5) ----------

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
-- Cycle 02 H2: FK-sikker cascade. Tidligere slettede den kun family_member+person → fejlede med
-- foreign_key_violation for enhver loadet person (non-cascade FK'er fra person_external_id/profiles/
-- family_member → person). Slet evidens/relationer/notes/narrativ FØR person, i FK-rigtig orden
-- (citation+conclusion FØR assertion, da conclusion.valgt_assertion_id → assertion).
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
  PERFORM begin_change_set('red_relation', format('Relation %s: %s/%s → %s/%s', p_rolle, p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id), p_subjekt_type, p_subjekt_id);
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
            p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- FK-ORDNET slet af en relation + dens evidens (relationer har 955 assertion+conclusion med
-- target_type='relation' UDEN FK → flad DELETE forældreløser dem). Spejler red_slet_person.
CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_slet_relation', format('Slettede relation %s', p_relation_id), NULL, NULL);
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
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

-- 2C-2b familie-redigering -------------------------------------------------
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
-- REDAKTIONS-DASHBOARD: konflikt-view + slet-preview
-- =====================================================================

-- Konflikt-kø til redaktions-dashboard: ægte kilde-uenighed = >1 DISTINKT værdi
-- INDEN FOR ÉT fact (to kilder uenige om SAMME forhold). Grain er PR. FACT, ikke
-- pr. (person,faktatype): en person kan have FLERE facts af samme type (fx 6 titler
-- gennem livet) — det er legitime distinkte facts, ikke en konflikt (bruger-feedback
-- 2026-06-28, fact-kardinalitet — se decisions.md).
-- security_invoker=true er KRITISK: ellers kører viewet med ejer-rettigheder og omgår RLS
-- på fact/assertion → ville lække private personers konflikter (spec §5, Codex-review høj).
-- v1: kun 'navn'/'titel' (dato-fakta har typisk tom vaerdi_tekst → udeladt, spec §5).
CREATE OR REPLACE VIEW red_konflikt
  WITH (security_invoker = true) AS
-- fact_id sidst: CREATE OR REPLACE VIEW kan kun APPEND kolonner (ikke indsætte midt i).
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

-- ============ OPRET-NY-ENTITET (2026-06-29) ============
-- Komposite SECURITY DEFINER opret-RPC'er. id=max+1 (husstil). privat=true default (privatliv).
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

-- =====================================================================
--  VERSIONERING + HYPERLINKS (2026-06-30)
--  Additive features: fortryd-bar redaktionel ændringshistorik + hyperlinks.
--  Spec: docs/superpowers/specs/2026-06-30-versionering-og-hyperlinks-design.md
-- =====================================================================

-- ---------- VERSIONERING: PK/skip-kolonne-registry ----------
-- Styrer den generiske log_change-trigger: hvilke kolonner udgør PK (→ row_pk)
-- og hvilke kolonner springes over i snapshot (afledt cache; spec-B8/B11).
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
  ('profiles',           ARRAY['id'], ARRAY['email','rolle'])  -- versionér kun reventlow_person_id-binding (spec §4.3.1)
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;
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
  SELECT coalesce(p.email, v_uid::text), p.rolle INTO v_navn, v_rolle
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
-- ---------- VERSIONERING: generisk log_change ----------
-- Byg kanonisk row_pk fra registry'ets pk_cols.
CREATE OR REPLACE FUNCTION _row_pk(p_tabel text, p_row jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_object_agg(k, p_row->k), '{}'::jsonb)
  FROM version_pk_registry r, unnest(r.pk_cols) k
  WHERE r.tabel = p_tabel;
$$;

CREATE OR REPLACE FUNCTION log_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_cs text; v_seq int; v_skip text[];
  v_foer jsonb; v_efter jsonb;
BEGIN
  v_cs := current_setting('app.change_set_id', true);
  IF v_cs IS NULL OR v_cs = '' THEN RETURN NULL; END IF;  -- bulk-load-sti: ingen logning

  SELECT skip_cols INTO v_skip FROM version_pk_registry WHERE tabel = TG_TABLE_NAME;
  v_skip := coalesce(v_skip, '{}');

  -- projektion: fjern skip-kolonner (afledt cache; B8)
  v_foer  := CASE WHEN TG_OP='INSERT' THEN NULL ELSE (to_jsonb(OLD) - v_skip) END;
  v_efter := CASE WHEN TG_OP='DELETE' THEN NULL ELSE (to_jsonb(NEW) - v_skip) END;

  -- no-op-skip: hvis kun skip-kolonner ændrede sig (fx ren cache-regen), log intet
  IF TG_OP='UPDATE' AND v_foer = v_efter THEN RETURN NULL; END IF;

  v_seq := coalesce(nullif(current_setting('app.change_seq', true),''),'0')::int + 1;
  PERFORM set_config('app.change_seq', v_seq::text, true);

  INSERT INTO change_event(id, change_set_id, seq, tabel, row_pk, op, foer, efter)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM change_event),
          v_cs::bigint, v_seq, TG_TABLE_NAME,
          _row_pk(TG_TABLE_NAME, coalesce(to_jsonb(NEW), to_jsonb(OLD))),
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
-- ---------- VERSIONERING: restore-hjælpere ----------
-- WHERE-klausul fra pk-jsonb med korrekt type-cast pr. kolonne (via udt_name).
CREATE OR REPLACE FUNCTION _version_pk_where(p_tabel text, p_pk jsonb)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT string_agg(format('%I = (%L)::%s', c.column_name, p_pk->>c.column_name, c.udt_name), ' AND ')
  FROM version_pk_registry r, unnest(r.pk_cols) k
  JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name=p_tabel AND c.column_name=k
  WHERE r.tabel=p_tabel;
$$;

CREATE OR REPLACE FUNCTION _version_current_row(p_tabel text, p_pk jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_skip text[]; v_row jsonb;
BEGIN
  SELECT coalesce(skip_cols,'{}') INTO v_skip FROM version_pk_registry WHERE tabel=p_tabel;
  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk))
    INTO v_row;
  IF v_row IS NULL THEN RETURN NULL; END IF;
  RETURN v_row - v_skip;  -- samme projektion som log_change
END $$;

-- Upsert til nøjagtig snapshot-tilstand. Manglende (skip-)kolonner → NULL (cache regenereres efter).
CREATE OR REPLACE FUNCTION _version_upsert_row(p_tabel text, p_row jsonb)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_pk_cols text; v_set text;
BEGIN
  SELECT string_agg(quote_ident(k),',') INTO v_pk_cols
    FROM version_pk_registry r, unnest(r.pk_cols) k WHERE r.tabel=p_tabel;
  SELECT string_agg(format('%I = excluded.%I', column_name, column_name), ',') INTO v_set
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name=p_tabel;
  EXECUTE format(
    'INSERT INTO %1$I SELECT (jsonb_populate_record(null::%1$I, $1)).* ON CONFLICT (%2$s) DO UPDATE SET %3$s',
    p_tabel, v_pk_cols, v_set) USING p_row;
END $$;

CREATE OR REPLACE FUNCTION _version_delete_row(p_tabel text, p_pk jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('DELETE FROM %I WHERE %s', p_tabel, _version_pk_where(p_tabel, p_pk));
END $$;
-- ---------- VERSIONERING: restore ----------
CREATE OR REPLACE FUNCTION red_fortryd_change_set(p_change_set_id bigint, p_force boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  ev change_event; v_new_cs bigint; v_orig change_set;
  v_cur jsonb; v_pids bigint[] := '{}'; v_narr bigint[] := '{}'; v_notes bigint[] := '{}';
  v_div int := 0; pid bigint;
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
            coalesce((SELECT email FROM profiles WHERE id=auth.uid()), 'ukendt'),
            current_rolle(), 'fortryd',
            format('Fortrød: %s', coalesce(v_orig.summary,'(uden tekst)')),
            v_orig.subjekt_type, v_orig.subjekt_id, v_orig.subjekt_synlighed, p_change_set_id);

  -- inverse-apply i OMVENDT seq-orden, alt i denne ene transaktion
  FOR ev IN SELECT * FROM change_event WHERE change_set_id=p_change_set_id ORDER BY seq DESC LOOP
    -- optimistisk verifikation (B9): nuværende tilstand skal matche hvad sættet efterlod
    v_cur := _version_current_row(ev.tabel, ev.row_pk);
    IF ev.op IN ('INSERT','UPDATE') THEN
      IF v_cur IS DISTINCT FROM ev.efter THEN
        v_div := v_div + 1;
        IF NOT p_force THEN
          RAISE EXCEPTION 'FEJL: nyere ændring rører %/% — afvist (brug force)', ev.tabel, ev.row_pk;
        END IF;
      END IF;
    END IF;
    -- anvend inverse
    IF ev.op='INSERT' THEN
      PERFORM _version_delete_row(ev.tabel, ev.row_pk);
    ELSIF ev.op='DELETE' THEN
      PERFORM _version_upsert_row(ev.tabel, ev.foer);
    ELSE  -- UPDATE
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
  FOREACH pid IN ARRAY (SELECT array_agg(DISTINCT x) FROM unnest(v_pids) x) LOOP
    PERFORM regen_person_visning(pid);
  END LOOP;
  -- text_mention regenereres af mention-trigger ved narrativ/note-skrivning (Task 10);
  -- ved restore kalder vi den eksplicit (funktion tilføjes i Task 10):
  -- (GENAKTIVERES I TASK 10:)
  -- PERFORM _regen_mentions_for('narrative', n) FROM unnest(v_narr) n;
  -- PERFORM _regen_mentions_for('note', n)      FROM unnest(v_notes) n;

  IF v_div > 0 THEN
    UPDATE change_set SET summary = summary || format(' [%s divergenser tvunget]', v_div) WHERE id=v_new_cs;
  END IF;
  RETURN jsonb_build_object('reversal_change_set', v_new_cs, 'divergenser', v_div);
END $$;
