# Trin 4 · dagsværk 4.1a: klausullagets skema — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør databasen og Python-kontrakten i stand til at rumme klausul-observationer under en helpost, med lukket vokabular, dækningsregler i trigger, en append-only dispositionsledger og en hærdet legacy-writer — uden at skrive én klausul endnu.

**Architecture:** Additive DDL på `private.source_observation` (fire nullable kolonner + trigger), ny `private.vocab` som privat pendant til `public.vocab`, ny tabel `private.clause_disposition` + view, én ændret linje i `private.migrate_legacy_narrative_record`, og bundle-skema 1.2 i `evidence_contract.py`. Alt spejles idempotent i `db-migrations.sql`, verificeres i `db-verify.sql` og testes i CI's PostgreSQL-jobs.

**Tech Stack:** PostgreSQL 17 (plpgsql, triggere), psql-baserede SQL-tests i `tests/sql/`, Python 3 + pytest for kontrakten, GitHub Actions (`.github/workflows/ci.yml`).

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §4.1.1-4.1.2 og §3 (rækken 4.1a).

## Global Constraints

- `schema.sql` er source of truth; `db-migrations.sql` er idempotent og skal kunne køres to gange i træk (CI kører den to gange). Enhver DDL skrives begge steder.
- Ingen prod-mutation. Den rigtige kørsel sker i en lokal restore af prod-dumpet (`umask 077`, `PGTZ=UTC` i alle sessioner).
- Ingen persondata i repo, chat, commits eller testfixtures. Syntetiske fixtures bruger opdigtede navne som `Alfa`, `Bravo`.
- Commits: Conventional Commits med dansk beskrivelse, ét commit pr. task, ingen Claude-attribution, ingen push. Kør `git branch --show-current` før hvert commit; arbejd på en gren `feat/148-klausullag-skema` fra `origin/main`.
- Appendix-only: ingen `UPDATE`/`DELETE` på evidenstabeller i produktionskode. Cache-kolonner (`person.visning_*`) røres aldrig.
- Kontrolleret vokabular: nye koder lever i `private.vocab`, aldrig som frie strenge.
- `SECURITY DEFINER`-funktioner har altid `SET search_path=pg_catalog,...`; nye private funktioner får `REVOKE ALL ... FROM PUBLIC,anon,authenticated,service_role` i `db-rls.sql`.
- Klassifikatoren i auto-mode kan blokere skrivning mod prod; det er irrelevant her, fordi alt sker lokalt.

## Roadmappens seks adgangskrav (for dette dagsværk)

1. **Roadmapmål:** trin 4, #148.
2. **Værdikædeled:** forudsætningen for `klausulobservationer og mentions`: skemaet, der kan bære dem.
3. **Generel/profil/legacy:** generel motor (DDL + kontrakt). Ingen profil, ingen legacy-afvikling.
4. **Redaktionel værdi:** ingen direkte; muliggør klausulbelæg i 4.1b-4.1c.
5. **Bevis:** migration + `db-verify.sql` + CI-tests på en frisk restore af prod; 591 `person_post`-observationer uændrede, 0 klausuler, alle 7 eksisterende `observation_kind`-værdier seedet; legacy-writerens regressionstest grøn med en klausul-mention til stede.
6. **Erstatter:** intet endnu; `clause_ledger.py` forbliver Python-kontrakten, som databasen nu kan projicere.

## Målt udgangspunkt (lokal prod-kopi 2026-09-06, kun tal)

| Måling | Værdi |
| --- | --- |
| `observation_kind` i prod | `person_post` (source 1: 591), `person` 584, `fact` 130, `marriage` 94, `relationship` 81, `structural_context` 6, `cross_reference` 2 (alle source 3) |
| `mention_kind` | samme syv koder, samme antal |
| `private.interpretation` | 0 rækker |
| Occurrences pr. record | 2018-20: altid 1; 1939: 1-5 (1939's fact/marriage-observationer har egne occurrences) |
| 2018-20: observation-span = occurrence-span | 591 af 591 |
| Mentions pr. occurrence > 1 | 0 |

Konsekvens: "helposten" for 2018-20 er entydigt observationen med `parent_observation_id IS NULL` under recordens eneste occurrence. 1939's flerforekomst-struktur røres ikke i trin 4.

## Filoversigt

- Modify: `schema.sql` (efter `private.source_observation_text`, dvs. efter linje 583; og i `private.migrate_legacy_narrative_record`, linje 2830)
- Modify: `db-migrations.sql` (ny blok i slutningen, før `$public_red_revoke$`-blokken, dvs. før linje 17383)
- Modify: `db-rls.sql` (efter REVOKE-blokken for private reimport-funktioner, linje ~1178)
- Modify: `db-verify.sql` (efter `$reimport_event_operation_check_verify$`, linje ~2704)
- Create: `tests/sql/test-clause-evidence-schema.sql`
- Modify: `tests/sql/test-reimport-legacy-migration.sql` (ny task efter `task3_happy_path`)
- Modify: `.github/workflows/ci.yml` (writer_1939-jobbet, efter trinnet "Legacy migration writer SQL (149b)")
- Modify: `.claude/skills/daa-extract/scripts/evidence_contract.py`
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_contract.py`
- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py` (accepter bundle 1.2)
- Create: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`
- Modify: `docs/changelog.md`

---

### Task 1: SQL-kontrakttest for klausul-skemaet (fejler først)

**Files:**
- Create: `tests/sql/test-clause-evidence-schema.sql`

**Interfaces:**
- Consumes: `private.source_observation`, `private.source_record_occurrence`, `private.source_rendition`, `private.extraction_run` (eksisterende), `public.profiles` med `rolle='redaktion'` (findes efter `tests/sql/reimport-writer-v2-bootstrap.sql`).
- Produces: fejltokens, som Task 2 skal implementere: `EVIDENCE_OBSERVATION_KIND_UNKNOWN`, `EVIDENCE_CLAUSE_PARENT_REQUIRED`, `EVIDENCE_CLAUSE_PARENT_FORBIDDEN`, `EVIDENCE_CLAUSE_PARENT_NOT_TOP_LEVEL`, `EVIDENCE_CLAUSE_OCCURRENCE_MISMATCH`, `EVIDENCE_CLAUSE_SPAN_OUTSIDE_PARENT`, `EVIDENCE_CLAUSE_PAGE_OUTSIDE_PARENT`, `EVIDENCE_CLAUSE_TEXT_MISMATCH`, `EVIDENCE_CLAUSE_CLASSIFICATION_UNKNOWN`, `EVIDENCE_CLAUSE_DISPOSITION_UNKNOWN`, `EVIDENCE_CLAUSE_DISPOSITION_KIND_MISMATCH`, `EVIDENCE_CLAUSE_DISPOSITION_TARGET_INVALID`, `EVIDENCE_CLAUSE_DISPOSITION_VERSION_INVALID`.

- [ ] **Step 1: Skriv testfilen**

```sql
-- #148 4.1a: klausul-skema — kolonner, vokabular, triggere og dispositionsledger.
-- Alt syntetisk. Filen kører i én transaktion og ruller altid tilbage.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'CLAUSE_SCHEMA_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'CLAUSE_SCHEMA_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Fixture: source, run, rendition, occurrence og helpost (kind person_post).
CREATE FUNCTION pg_temp.fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint := -148001; v_run uuid := gen_random_uuid(); v_rend uuid; v_occ uuid; v_parent uuid;
  v_text text := 'Alfa Bravo, f. 1801 i Charlie. Gift 1830 m. Delta Echo. Død 1860.';
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES(v_source,'DAA-udgave','Clause fixture','synthetic',1900) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,v_source,'clause-schema-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(v_source,'clause-r-'||v_run::text,'pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rend,'occ-1',10,10,100,100+char_length(v_text),v_text,repeat('3',64),repeat('4',64),v_run) RETURNING id INTO v_occ;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occ,'person_post',10,10,100,100+char_length(v_text),v_text,'clear','fixture',v_run) RETURNING id INTO v_parent;
  RETURN jsonb_build_object('run',v_run,'occ',v_occ,'parent',v_parent,'text',v_text);
END $$;

DO $t1_columns_and_vocab$
DECLARE fx jsonb; v_kind text;
BEGIN
  FOREACH v_kind IN ARRAY ARRAY['parent_observation_id','clause_ordinal','clause_classification','clause_flags'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private' AND table_name='source_observation' AND column_name=v_kind) THEN
      RAISE EXCEPTION 'CLAUSE_SCHEMA_COLUMN_MISSING: %', v_kind;
    END IF;
  END LOOP;
  IF to_regclass('private.vocab') IS NULL THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_PRIVATE_VOCAB_MISSING'; END IF;
  FOREACH v_kind IN ARRAY ARRAY['person_post','person','fact','marriage','relationship','structural_context','cross_reference','clause'] LOOP
    IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='observation_kind' AND code=v_kind) THEN
      RAISE EXCEPTION 'CLAUSE_SCHEMA_OBSERVATION_KIND_NOT_SEEDED: %', v_kind;
    END IF;
  END LOOP;
  fx := pg_temp.fixture();
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
       VALUES(%L,'ukendt_slags',10,10,100,101,'A','clear','fixture',%L)$q$, fx->>'occ', fx->>'run'),
    'EVIDENCE_OBSERVATION_KIND_UNKNOWN');
  RAISE NOTICE 't1 columns and vocab OK';
END $t1_columns_and_vocab$;

DO $t2_clause_trigger$
DECLARE fx jsonb; v_clause uuid; v_text text; v_len integer;
BEGIN
  fx := pg_temp.fixture(); v_text := fx->>'text'; v_len := char_length(v_text);
  -- Gyldig klausul: første sætning, helpost-relativ [0,30) → absolut [100,130).
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
    parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES((fx->>'occ')::uuid,'clause',10,10,100,130,substr(v_text,1,30),'clear','clause_segment_v1',(fx->>'run')::uuid,
    (fx->>'parent')::uuid,1,'record_text','[]'::jsonb) RETURNING id INTO v_clause;
  -- Klausul uden forælder.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,%L,'clear','x',%L,2,'record_text','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run'),
    'EVIDENCE_CLAUSE_PARENT_REQUIRED');
  -- Ikke-klausul med forælder.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id)
       VALUES(%L,'person_post',10,10,100,101,'A','clear','x',%L,%L)$q$, fx->>'occ', fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_PARENT_FORBIDDEN');
  -- Forælder er selv en klausul.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,100,105,%L,'clear','x',%L,%L,1,'record_text','[]')$q$, fx->>'occ', substr(v_text,1,5), fx->>'run', v_clause),
    'EVIDENCE_CLAUSE_PARENT_NOT_TOP_LEVEL');
  -- Span uden for forælderen.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,%s,%s,'x','clear','x',%L,%L,2,'record_text','[]')$q$, fx->>'occ', 100+v_len, 100+v_len+1, fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_SPAN_OUTSIDE_PARENT');
  -- Sideinterval uden for forælderen (spec 4.1.2: klausulen arver forælderens grænser).
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',9,10,130,140,%L,'clear','x',%L,%L,2,'record_text','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_PAGE_OUTSIDE_PARENT');
  -- Tekst ≠ udsnit af forælderen.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,'FORKERT TEKST','clear','x',%L,%L,2,'record_text','[]')$q$, fx->>'occ', fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_TEXT_MISMATCH');
  -- Ukendt klassifikation.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,%L,'clear','x',%L,%L,2,'layout','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run', fx->>'parent'),
    'EVIDENCE_CLAUSE_CLASSIFICATION_UNKNOWN');
  -- Dublet-ordinal under samme forælder.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
       VALUES(%L,'clause',10,10,130,140,%L,'clear','x',%L,%L,1,'record_text','[]')$q$, fx->>'occ', substr(v_text,31,10), fx->>'run', fx->>'parent'),
    'duplicate key value');
  RAISE NOTICE 't2 clause trigger OK';
END $t2_clause_trigger$;

DO $t3_disposition_ledger$
DECLARE fx jsonb; v_clause uuid; v_actor uuid; v_current text;
BEGIN
  fx := pg_temp.fixture();
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES((fx->>'occ')::uuid,'clause',10,10,100,130,substr(fx->>'text',1,30),'clear','x',(fx->>'run')::uuid,(fx->>'parent')::uuid,1,'record_text','["unknown_abbreviation"]'::jsonb) RETURNING id INTO v_clause;
  -- Maskinel version 1.
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
  VALUES(v_clause,1,'maskinelt_flagget','machine','{"manifest_sha256":"fixture"}');
  -- Version skal være fortløbende.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,3,'afventer_fortolkning','machine','{"x":1}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_VERSION_INVALID');
  -- Maskine må ikke skrive en endelig (menneskelig) disposition.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'struktureret','machine','{"x":1}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_KIND_MISMATCH');
  -- Ukendt disposition.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'noget_andet','machine','{"x":1}')$q$, v_clause),
    'EVIDENCE_CLAUSE_DISPOSITION_UNKNOWN');
  -- Menneske uden aktørfelter → CHECK.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,2,'struktureret','human','{"basis":"test"}')$q$, v_clause),
    'new row for relation "clause_disposition" violates check constraint');
  -- Disposition på en ikke-klausul afvises.
  PERFORM pg_temp.expect_error(format(
    $q$INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence) VALUES(%L,1,'afventer_fortolkning','machine','{"x":1}')$q$, fx->>'parent'),
    'EVIDENCE_CLAUSE_DISPOSITION_TARGET_INVALID');
  -- Menneskelig version 2 og view.
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,decided_by,decided_by_name,decided_at,evidence)
  VALUES(v_clause,2,'struktureret','human',v_actor,'Fixture redaktør',clock_timestamp(),'{"basis":"test"}');
  SELECT disposition INTO v_current FROM private.clause_disposition_current WHERE observation_id=v_clause;
  IF v_current<>'struktureret' THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_CURRENT_VIEW_WRONG: %', v_current; END IF;
  RAISE NOTICE 't3 disposition ledger OK';
END $t3_disposition_ledger$;

ROLLBACK;
```

- [ ] **Step 2: Kør testen og bekræft, at den fejler**

Forudsætning: en lokal PostgreSQL 17 med en disponerbar base bygget som CI's `writer_1939`:

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=clause_schema_test
createdb clause_schema_test
psql -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-schema.sql
```

Forventet: FAIL med `CLAUSE_SCHEMA_COLUMN_MISSING: parent_observation_id`.

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add tests/sql/test-clause-evidence-schema.sql
git commit -m "test(db): kontrakttest for klausul-skema (#148 4.1a) — fejler før DDL"
```

---

### Task 2: DDL i `schema.sql`

**Files:**
- Modify: `schema.sql` — indsæt blokken umiddelbart efter `CREATE TABLE private.source_observation_text (...);` (slutter linje 583) og før `CREATE TABLE private.source_mention` (linje 584).

**Interfaces:**
- Produces: `private.vocab(scheme,code,label)`, kolonnerne `parent_observation_id`, `clause_ordinal`, `clause_classification`, `clause_flags` på `private.source_observation`, funktionerne `private.validate_clause_observation()` og `private.validate_clause_disposition()`, tabellen `private.clause_disposition`, view `private.clause_disposition_current`. Task 3 (migration), 4.1b (segmenter-kontrakt) og 4.1c (writer) bygger på præcis disse navne.

- [ ] **Step 1: Indsæt DDL'en**

```sql
-- ---------- #148 4.1a: KLAUSULLAG ----------
-- Privat vokabular for interne workflow-koder. public.vocab er anon-læsbar og
-- må ikke bære interne tilstande (spec 4.1.2).
CREATE TABLE private.vocab (
  scheme text NOT NULL CHECK (btrim(scheme)<>''),
  code   text NOT NULL CHECK (btrim(code)<>''),
  label  text NOT NULL CHECK (btrim(label)<>''),
  PRIMARY KEY (scheme, code)
);

INSERT INTO private.vocab(scheme,code,label) VALUES
  ('observation_kind','person_post','Helpost (2018-20, source_evidence-writer)'),
  ('observation_kind','person','Personobservation (1939 fase A)'),
  ('observation_kind','fact','Faktumobservation (1939 fase A)'),
  ('observation_kind','marriage','Ægteskabsobservation (1939 fase A)'),
  ('observation_kind','relationship','Relationsobservation (1939 fase A)'),
  ('observation_kind','structural_context','Strukturel kontekst (1939 fase A)'),
  ('observation_kind','cross_reference','Krydshenvisning (1939 fase A)'),
  ('observation_kind','clause','Klausul under helpost (#148)'),
  ('clause_classification','record_text','Meningsbærende tekstklausul'),
  ('clause_classification','structural_header','Strukturel overskrift inde i posten'),
  ('clause_disposition_machine','afventer_fortolkning','Maskinel: afventer fortolkning'),
  ('clause_disposition_machine','fortolkning_foreslaaet','Maskinel: mindst ét forslag citerer klausulen'),
  ('clause_disposition_machine','afventer_identitet','Maskinel: forslag om anden aktør end hovedpersonen'),
  ('clause_disposition_machine','maskinelt_flagget','Maskinel: segmenteringen var i tvivl'),
  ('clause_disposition_machine','strukturel','Maskinel: strukturel overskrift'),
  ('clause_disposition_human','struktureret','§15.1: struktureret'),
  ('clause_disposition_human','relevant_uklassificeret','§15.1: relevant, men uklassificeret'),
  ('clause_disposition_human','ikke_biografisk','§15.1: ikke-biografisk'),
  ('clause_disposition_human','layout_stoej','§15.1: layout-/bibliografisk støj'),
  ('clause_disposition_human','ulaeselig_ocr','§15.1: ulæselig OCR'),
  ('clause_disposition_human','kraever_menneske','§15.1: kræver menneskelig vurdering');

ALTER TABLE private.source_observation
  ADD COLUMN parent_observation_id uuid REFERENCES private.source_observation(id),
  ADD COLUMN clause_ordinal        integer CHECK (clause_ordinal IS NULL OR clause_ordinal >= 1),
  ADD COLUMN clause_classification text,
  ADD COLUMN clause_flags          jsonb CHECK (clause_flags IS NULL OR jsonb_typeof(clause_flags)='array');

CREATE UNIQUE INDEX ux_source_observation_clause_ordinal
  ON private.source_observation(parent_observation_id, clause_ordinal)
  WHERE parent_observation_id IS NOT NULL;

-- Klausul-invarianter (spec 4.1.2): ét niveau, samme occurrence, span inde i
-- forælderen, ordret udsnit, lukket vokabular. Offsets er rendition-absolutte.
CREATE FUNCTION private.validate_clause_observation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE v_parent private.source_observation%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='observation_kind' AND code=NEW.observation_kind) THEN
    RAISE EXCEPTION 'EVIDENCE_OBSERVATION_KIND_UNKNOWN: %', NEW.observation_kind;
  END IF;
  IF NEW.observation_kind<>'clause' THEN
    IF NEW.parent_observation_id IS NOT NULL OR NEW.clause_ordinal IS NOT NULL
       OR NEW.clause_classification IS NOT NULL OR NEW.clause_flags IS NOT NULL THEN
      RAISE EXCEPTION 'EVIDENCE_CLAUSE_PARENT_FORBIDDEN';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.parent_observation_id IS NULL OR NEW.clause_ordinal IS NULL
     OR NEW.clause_classification IS NULL OR NEW.clause_flags IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_PARENT_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme='clause_classification' AND code=NEW.clause_classification) THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_CLASSIFICATION_UNKNOWN: %', NEW.clause_classification;
  END IF;
  SELECT * INTO v_parent FROM private.source_observation WHERE id=NEW.parent_observation_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EVIDENCE_CLAUSE_PARENT_REQUIRED'; END IF;
  IF v_parent.parent_observation_id IS NOT NULL THEN RAISE EXCEPTION 'EVIDENCE_CLAUSE_PARENT_NOT_TOP_LEVEL'; END IF;
  IF v_parent.occurrence_id<>NEW.occurrence_id THEN RAISE EXCEPTION 'EVIDENCE_CLAUSE_OCCURRENCE_MISMATCH'; END IF;
  IF NEW.char_from<v_parent.char_from OR NEW.char_to>v_parent.char_to THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_SPAN_OUTSIDE_PARENT';
  END IF;
  -- Sider er grænser, ikke en påstand om præcis side (spec 4.1.2).
  IF NEW.page_from<v_parent.page_from OR NEW.page_to>v_parent.page_to THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_PAGE_OUTSIDE_PARENT';
  END IF;
  IF substr(v_parent.verbatim_text, NEW.char_from-v_parent.char_from+1, NEW.char_to-NEW.char_from)<>NEW.verbatim_text THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_TEXT_MISMATCH';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_source_observation_clause
  BEFORE INSERT ON private.source_observation
  FOR EACH ROW EXECUTE FUNCTION private.validate_clause_observation();

-- Append-only dispositionsledger pr. klausul (spec 4.1.2, §15.1).
CREATE TABLE private.clause_disposition (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  observation_id   uuid NOT NULL REFERENCES private.source_observation(id),
  version          integer NOT NULL CHECK (version >= 1),
  disposition      text NOT NULL CHECK (btrim(disposition)<>''),
  decided_by_kind  text NOT NULL CHECK (decided_by_kind IN ('machine','human')),
  decided_by       uuid,
  decided_by_name  text,
  decided_at       timestamptz,
  evidence         jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(evidence)='object'),
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (observation_id, version),
  CONSTRAINT clause_disposition_actor_check CHECK (
    (decided_by_kind='human' AND decided_by IS NOT NULL
      AND nullif(btrim(decided_by_name),'') IS NOT NULL AND decided_at IS NOT NULL
      AND evidence<>'{}'::jsonb)
    OR
    (decided_by_kind='machine' AND decided_by IS NULL AND decided_by_name IS NULL
      AND decided_at IS NULL AND evidence<>'{}'::jsonb)
  )
);

CREATE FUNCTION private.validate_clause_disposition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE v_kind text; v_scheme text; v_next integer;
BEGIN
  SELECT observation_kind INTO v_kind FROM private.source_observation WHERE id=NEW.observation_id FOR UPDATE;
  IF NOT FOUND OR v_kind<>'clause' THEN RAISE EXCEPTION 'EVIDENCE_CLAUSE_DISPOSITION_TARGET_INVALID'; END IF;
  v_scheme := CASE NEW.decided_by_kind WHEN 'machine' THEN 'clause_disposition_machine' ELSE 'clause_disposition_human' END;
  IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE code=NEW.disposition AND scheme IN ('clause_disposition_machine','clause_disposition_human')) THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_DISPOSITION_UNKNOWN: %', NEW.disposition;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.vocab WHERE scheme=v_scheme AND code=NEW.disposition) THEN
    RAISE EXCEPTION 'EVIDENCE_CLAUSE_DISPOSITION_KIND_MISMATCH: % er ikke %', NEW.disposition, NEW.decided_by_kind;
  END IF;
  SELECT coalesce(max(version),0)+1 INTO v_next FROM private.clause_disposition WHERE observation_id=NEW.observation_id;
  IF NEW.version<>v_next THEN RAISE EXCEPTION 'EVIDENCE_CLAUSE_DISPOSITION_VERSION_INVALID: forventede %', v_next; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_clause_disposition_validate
  BEFORE INSERT ON private.clause_disposition
  FOR EACH ROW EXECUTE FUNCTION private.validate_clause_disposition();

CREATE VIEW private.clause_disposition_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (observation_id) *
  FROM private.clause_disposition
 ORDER BY observation_id, version DESC;
```

- [ ] **Step 2: Byg en frisk base og kør Task 1's test**

```bash
dropdb clause_schema_test && createdb clause_schema_test
psql -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-schema.sql
```

Forventet: tre `NOTICE`-linjer (`t1 … OK`, `t2 … OK`, `t3 … OK`) og `ROLLBACK`. Fejler den på den eksisterende `validate_evidence_scope`-trigger (`EVIDENCE_OBSERVATION_SPAN_INVALID`), er fixturens occurrence-span forkert; klausulens `page_from/page_to` og `char_from/char_to` skal ligge inde i occurrence-spannet, hvilket fixturen sikrer med `[100, 100+len)`.

- [ ] **Step 3: Kør de eksisterende SQL-suiter, der rører observationer, for at fange regressioner**

```bash
psql -v ON_ERROR_STOP=1 -f tests/sql/test-evidence-promotion.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
```

Forventet: alle grønne. `test-evidence-promotion.sql` indsætter observationer med `observation_kind`-værdier; findes en værdi, der ikke er seedet, fejler den med `EVIDENCE_OBSERVATION_KIND_UNKNOWN` — tilføj så koden til seed-listen i både `schema.sql` og Task 3, aldrig ved at slække triggeren.

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add schema.sql
git commit -m "feat(db): klausul-kolonner, privat vokabular og dispositionsledger (#148 4.1a)"
```

---

### Task 3: Idempotent migration i `db-migrations.sql`

**Files:**
- Modify: `db-migrations.sql` — indsæt før linjen `-- #154: close every inherited/default EXECUTE grant and classify the complete` (linje 17383), så #154's ACL-blok fortsat er sidst.

**Interfaces:**
- Consumes: Task 2's DDL (samme funktionskroppe, kopieret ordret).
- Produces: en base migreret fra ethvert tidligere prod-skema når samme tilstand som frisk `schema.sql`.

- [ ] **Step 1: Skriv migrationsblokken**

```sql
-- ===== #148 4.1a: klausullag (kolonner, privat vokabular, dispositionsledger) =====
CREATE TABLE IF NOT EXISTS private.vocab (
  scheme text NOT NULL CHECK (btrim(scheme)<>''),
  code   text NOT NULL CHECK (btrim(code)<>''),
  label  text NOT NULL CHECK (btrim(label)<>''),
  PRIMARY KEY (scheme, code)
);
INSERT INTO private.vocab(scheme,code,label) VALUES
  ('observation_kind','person_post','Helpost (2018-20, source_evidence-writer)'),
  ('observation_kind','person','Personobservation (1939 fase A)'),
  ('observation_kind','fact','Faktumobservation (1939 fase A)'),
  ('observation_kind','marriage','Ægteskabsobservation (1939 fase A)'),
  ('observation_kind','relationship','Relationsobservation (1939 fase A)'),
  ('observation_kind','structural_context','Strukturel kontekst (1939 fase A)'),
  ('observation_kind','cross_reference','Krydshenvisning (1939 fase A)'),
  ('observation_kind','clause','Klausul under helpost (#148)'),
  ('clause_classification','record_text','Meningsbærende tekstklausul'),
  ('clause_classification','structural_header','Strukturel overskrift inde i posten'),
  ('clause_disposition_machine','afventer_fortolkning','Maskinel: afventer fortolkning'),
  ('clause_disposition_machine','fortolkning_foreslaaet','Maskinel: mindst ét forslag citerer klausulen'),
  ('clause_disposition_machine','afventer_identitet','Maskinel: forslag om anden aktør end hovedpersonen'),
  ('clause_disposition_machine','maskinelt_flagget','Maskinel: segmenteringen var i tvivl'),
  ('clause_disposition_machine','strukturel','Maskinel: strukturel overskrift'),
  ('clause_disposition_human','struktureret','§15.1: struktureret'),
  ('clause_disposition_human','relevant_uklassificeret','§15.1: relevant, men uklassificeret'),
  ('clause_disposition_human','ikke_biografisk','§15.1: ikke-biografisk'),
  ('clause_disposition_human','layout_stoej','§15.1: layout-/bibliografisk støj'),
  ('clause_disposition_human','ulaeselig_ocr','§15.1: ulæselig OCR'),
  ('clause_disposition_human','kraever_menneske','§15.1: kræver menneskelig vurdering')
ON CONFLICT (scheme,code) DO NOTHING;

-- Inventering (spec 4.1.2): en eksisterende observation_kind, der ikke er seedet,
-- er en stopport — ikke noget, der stiltiende slækkes.
DO $clause_kind_inventory$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(DISTINCT observation_kind, ', ') INTO v_missing
    FROM private.source_observation ob
   WHERE NOT EXISTS (SELECT 1 FROM private.vocab v WHERE v.scheme='observation_kind' AND v.code=ob.observation_kind);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'CLAUSE_MIGRATION_OBSERVATION_KIND_UNSEEDED: %', v_missing;
  END IF;
END $clause_kind_inventory$;

ALTER TABLE private.source_observation
  ADD COLUMN IF NOT EXISTS parent_observation_id uuid REFERENCES private.source_observation(id),
  ADD COLUMN IF NOT EXISTS clause_ordinal        integer,
  ADD COLUMN IF NOT EXISTS clause_classification text,
  ADD COLUMN IF NOT EXISTS clause_flags          jsonb;
DO $clause_column_checks$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.source_observation'::regclass AND conname='source_observation_clause_ordinal_check') THEN
    ALTER TABLE private.source_observation ADD CONSTRAINT source_observation_clause_ordinal_check CHECK (clause_ordinal IS NULL OR clause_ordinal >= 1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.source_observation'::regclass AND conname='source_observation_clause_flags_check') THEN
    ALTER TABLE private.source_observation ADD CONSTRAINT source_observation_clause_flags_check CHECK (clause_flags IS NULL OR jsonb_typeof(clause_flags)='array');
  END IF;
END $clause_column_checks$;
CREATE UNIQUE INDEX IF NOT EXISTS ux_source_observation_clause_ordinal
  ON private.source_observation(parent_observation_id, clause_ordinal)
  WHERE parent_observation_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.validate_clause_observation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
-- (kopiér funktionskroppen ordret fra schema.sql, Task 2)
$$;
DROP TRIGGER IF EXISTS trg_source_observation_clause ON private.source_observation;
CREATE TRIGGER trg_source_observation_clause
  BEFORE INSERT ON private.source_observation
  FOR EACH ROW EXECUTE FUNCTION private.validate_clause_observation();

CREATE TABLE IF NOT EXISTS private.clause_disposition (
  -- (kopiér tabeldefinitionen ordret fra schema.sql, Task 2)
);
CREATE OR REPLACE FUNCTION private.validate_clause_disposition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
-- (kopiér funktionskroppen ordret fra schema.sql, Task 2)
$$;
DROP TRIGGER IF EXISTS trg_clause_disposition_validate ON private.clause_disposition;
CREATE TRIGGER trg_clause_disposition_validate
  BEFORE INSERT ON private.clause_disposition
  FOR EACH ROW EXECUTE FUNCTION private.validate_clause_disposition();
CREATE OR REPLACE VIEW private.clause_disposition_current
WITH (security_invoker=true) AS
SELECT DISTINCT ON (observation_id) *
  FROM private.clause_disposition
 ORDER BY observation_id, version DESC;
```

De tre "(kopiér … ordret)"-markeringer er instruktion til dig: sæt den fulde tekst fra Task 2 ind. Migrationen må ikke afvige fra `schema.sql` med ét tegn i funktionskroppene, ellers giver `db-verify` drift.

- [ ] **Step 2: Test migrationsstien som CI gør (to gange i træk)**

```bash
dropdb clause_schema_test && createdb clause_schema_test
psql -v ON_ERROR_STOP=1 -f tests/sql/evidence-hardening-pre-migration.sql
psql -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-evidence-promotion.sql
```

Forventet: exit 0 begge gange; anden kørsel må ikke fejle på `ADD COLUMN` eller `CREATE TRIGGER`.

- [ ] **Step 3: Test "frisk schema + migration"-stien**

```bash
dropdb clause_schema_test && createdb clause_schema_test
psql -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-evidence-promotion.sql
```

Forventet: exit 0.

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add db-migrations.sql
git commit -m "feat(db): idempotent migration for klausullaget (#148 4.1a)"
```

---

### Task 4: Hærd legacy-writeren (tæl kun helpostens mentions)

**Files:**
- Modify: `schema.sql:2830` (i `private.migrate_legacy_narrative_record`)
- Modify: `db-migrations.sql` — tilføj `CREATE OR REPLACE FUNCTION private.migrate_legacy_narrative_record(...)` med hele den nye funktionskrop i 4.1a-blokken fra Task 3 (efter view'et).
- Modify: `tests/sql/test-reimport-legacy-migration.sql` — ny task efter `$task3_happy_path$`-blokken.

**Interfaces:**
- Consumes: `pg_temp.task3_fixture(p_key, p_levende)` og `pg_temp.task3_migrate(p_fx, p_disposition, p_manifest_nonce)` fra den eksisterende testfil (linje 97-215).
- Produces: legacy-migration afvises ikke længere af klausul-mentions.

- [ ] **Step 1: Skriv den fejlende test**

Indsæt efter `END $task3_happy_path$;`:

```sql
-- 4.1a (#148 fund 3b): klausul-mentions under helposten må ikke gøre legacy-migration
-- tvetydig. Tællingen skal kun se helpost-observationer (parent_observation_id IS NULL).
DO $task3_clause_mentions$
DECLARE fx jsonb; r jsonb; v_occ uuid; v_parent uuid; v_run uuid; v_clause uuid; v_text text;
BEGIN
  fx := pg_temp.task3_fixture('T3CL1', false);
  SELECT ob.id, ob.occurrence_id, ob.extraction_run_id, ob.verbatim_text INTO v_parent, v_occ, v_run, v_text
    FROM private.source_observation ob
    JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id
    JOIN private.source_rendition rd ON rd.id=o.rendition_id
   WHERE rd.source_id=(fx->>'source_id')::bigint AND ob.parent_observation_id IS NULL;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,
    parent_observation_id,clause_ordinal,clause_classification,clause_flags)
  VALUES(v_occ,'clause',10,10,0,10,substr(v_text,1,10),'clear','fixture',v_run,v_parent,1,'record_text','[]') RETURNING id INTO v_clause;
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  VALUES(v_clause,'person',0,4,substr(v_text,1,4),v_run);
  r := pg_temp.task3_migrate(fx,'bound_published','T3CL1-nonce');
  IF (r->>'legacy_event_id') IS NULL THEN RAISE EXCEPTION 'TASK3_CLAUSE_MENTION_BLOCKED_MIGRATION: %', r; END IF;
  RAISE NOTICE 'task3 clause mentions OK';
END $task3_clause_mentions$;
```

- [ ] **Step 2: Kør testen og bekræft, at den fejler**

```bash
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
```

Forventet: FAIL med `LEGACY_MIGRATION_MENTION_AMBIGUOUS`.

- [ ] **Step 3: Ret tællingen i `schema.sql`**

Linje 2830, erstat

```sql
  SELECT count(*),(array_agg(m.id ORDER BY m.id))[1] INTO v_mention_count,v_mention_id FROM private.source_observation ob JOIN private.source_mention m ON m.observation_id=ob.id WHERE ob.occurrence_id=v_occurrence.id;
```

med

```sql
  -- #148 4.1a: kun helpostens mentions tæller; klausul-mentions er under-niveau.
  SELECT count(*),(array_agg(m.id ORDER BY m.id))[1] INTO v_mention_count,v_mention_id FROM private.source_observation ob JOIN private.source_mention m ON m.observation_id=ob.id WHERE ob.occurrence_id=v_occurrence.id AND ob.parent_observation_id IS NULL;
```

Gentag ændringen i `db-migrations.sql` ved at kopiere hele den nu ændrede funktion fra `schema.sql` (linje 2773-2955) ind som `CREATE OR REPLACE FUNCTION` i 4.1a-blokken.

- [ ] **Step 4: Kør testen igen på begge stier**

```bash
# frisk schema
dropdb clause_schema_test && createdb clause_schema_test
psql -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
# migreret
psql -v ON_ERROR_STOP=1 -f db-migrations.sql
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
```

Forventet: `task3 clause mentions OK` begge gange, og alle eksisterende tasks i filen fortsat grønne (herunder den, der forventer `LEGACY_MIGRATION_MENTION_AMBIGUOUS` for to helpost-mentions, hvis den findes: den skal stadig bestå, fordi to *helpost*-mentions fortsat er tvetydige).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add schema.sql db-migrations.sql tests/sql/test-reimport-legacy-migration.sql
git commit -m "fix(db): legacy-migration tæller kun helpostens mentions (#148 4.1a)"
```

---

### Task 5: ACL, db-verify og CI-wiring

**Files:**
- Modify: `db-rls.sql` (efter den eksisterende `REVOKE ALL ON FUNCTION private.lock_reimport_writer(...)…FROM PUBLIC,anon,authenticated,service_role;`-sætning, som slutter linje ~1178)
- Modify: `db-verify.sql` (efter `$reimport_event_operation_check_verify$`, linje ~2704)
- Modify: `.github/workflows/ci.yml` (writer_1939-jobbet)

- [ ] **Step 1: Tilføj REVOKE i `db-rls.sql`**

```sql
-- #148 4.1a: trigger-funktioner og privat vokabular er interne.
REVOKE ALL ON FUNCTION private.validate_clause_observation(), private.validate_clause_disposition()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE private.vocab, private.clause_disposition FROM PUBLIC,anon,authenticated;
```

- [ ] **Step 2: Tilføj verify-blok i `db-verify.sql`**

```sql
-- #148 4.1a: klausullagets skema er til stede, vokabularet er lukket, og
-- legacy-writeren tæller kun helpostens mentions.
DO $clause_schema_verify$
DECLARE v_def text; v_count integer;
BEGIN
  IF to_regclass('private.vocab') IS NULL OR to_regclass('private.clause_disposition') IS NULL
     OR to_regclass('private.clause_disposition_current') IS NULL THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_OBJECTS_MISSING';
  END IF;
  SELECT count(*) INTO v_count FROM information_schema.columns
   WHERE table_schema='private' AND table_name='source_observation'
     AND column_name IN ('parent_observation_id','clause_ordinal','clause_classification','clause_flags');
  IF v_count<>4 THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_COLUMNS_MISSING: %', v_count; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.source_observation'::regclass AND tgname='trg_source_observation_clause')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.clause_disposition'::regclass AND tgname='trg_clause_disposition_validate') THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_TRIGGER_MISSING';
  END IF;
  SELECT count(*) INTO v_count FROM private.source_observation ob
   WHERE NOT EXISTS (SELECT 1 FROM private.vocab v WHERE v.scheme='observation_kind' AND v.code=ob.observation_kind);
  IF v_count<>0 THEN RAISE EXCEPTION 'CLAUSE_SCHEMA_OBSERVATION_KIND_UNSEEDED: %', v_count; END IF;
  SELECT pg_get_functiondef('private.migrate_legacy_narrative_record(uuid,text,jsonb)'::regprocedure) INTO v_def;
  IF v_def NOT LIKE '%ob.occurrence_id=v_occurrence.id AND ob.parent_observation_id IS NULL%' THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_LEGACY_WRITER_NOT_HARDENED';
  END IF;
  IF has_function_privilege('authenticated','private.validate_clause_observation()','EXECUTE')
     OR has_table_privilege('anon','private.vocab','SELECT') THEN
    RAISE EXCEPTION 'CLAUSE_SCHEMA_ACL_INVALID';
  END IF;
  RAISE NOTICE 'OK: #148 klausullagets skema, vokabular, triggere, ACL og hærdet legacy-writer';
END $clause_schema_verify$;
```

- [ ] **Step 3: Kør db-verify disponerbart**

```bash
psql -v ON_ERROR_STOP=1 -f db-rls.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
```

Forventet: `OK: #148 klausullagets skema …` i outputtet og exit 0.

- [ ] **Step 4: Tilføj CI-trin**

I `.github/workflows/ci.yml`, i jobbet `DAA 1939 v50 writer · PostgreSQL 17`, umiddelbart efter trinnet `Legacy migration writer SQL (149b)`:

```yaml
      - name: Klausul-skema SQL (#148 4.1a)
        env:
          PGPASSWORD: postgres
        run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-clause-evidence-schema.sql
```

Kopiér `env:`-blokken præcis som det foregående trin bruger den (samme nøgler), så jobbet ikke mister forbindelsesoplysninger.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add db-rls.sql db-verify.sql .github/workflows/ci.yml
git commit -m "chore(db): ACL, db-verify og CI for klausullagets skema (#148 4.1a)"
```

---

### Task 6: Bundle-skema 1.2 i Python-kontrakten

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/evidence_contract.py` (klassen `Observation`, `_as_observation`, `validate_bundle`)
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_contract.py`
- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py:150` (`validate_output`)

**Interfaces:**
- Produces: `Observation` får valgfrie felter `parent_observation_id: Optional[str] = None`, `clause_ordinal: Optional[int] = None`, `clause_classification: Optional[str] = None`, `clause_flags: tuple[str, ...] = ()`; `validate_bundle` accepterer `schema_version` `"1.2"` (strict som 1.1) og håndhæver klausul-invarianterne; `evidence_extract.validate_output` accepterer bundle 1.1 og 1.2.

- [ ] **Step 1: Skriv de fejlende tests**

Tilføj til `test_evidence_contract.py` (brug den eksisterende hjælpe-fixture i filen til at bygge et gyldigt 1.1-bundle; navnet står i filen som den funktion, der returnerer et gyldigt strict bundle — genbrug den, og sæt `schema_version` til `"1.2"`):

```python
def _clause(parent, ordinal, char_from, char_to, text, classification="record_text", flags=()):
    return {
        "observation_id": f"{parent['observation_id']}-c{ordinal}",
        "occurrence_id": parent["occurrence_id"],
        "kind": "clause",
        "verbatim_text": text,
        "span": {**parent["span"], "char_from": char_from, "char_to": char_to},
        "extraction_method": "clause_segment_v1",
        "extraction_run_id": parent["extraction_run_id"],
        "parent_observation_id": parent["observation_id"],
        "clause_ordinal": ordinal,
        "clause_classification": classification,
        "clause_flags": list(flags),
    }


def test_bundle_1_2_accepts_clause_under_parent(strict_bundle):
    bundle = json.loads(json.dumps(strict_bundle))
    bundle["schema_version"] = "1.2"
    parent = bundle["observations"][0]
    text = parent["verbatim_text"]
    bundle["observations"].append(_clause(parent, 1, parent["span"]["char_from"], parent["span"]["char_from"] + 5, text[:5]))
    validate_bundle(bundle)


def test_bundle_1_1_rejects_clause_fields():
    # 1.1 er strict og kender ikke klausulfelterne.
    bundle = json.loads(json.dumps(strict_bundle_factory()))
    parent = bundle["observations"][0]
    bundle["observations"].append(_clause(parent, 1, parent["span"]["char_from"], parent["span"]["char_from"] + 5, parent["verbatim_text"][:5]))
    with pytest.raises(ContractError):
        validate_bundle(bundle)


@pytest.mark.parametrize("mutate,expected", [
    (lambda c, p: c.update(parent_observation_id=None), "clause requires parent"),
    (lambda c, p: c["span"].update(char_to=p["span"]["char_to"] + 1), "clause span outside parent"),
    (lambda c, p: c.update(verbatim_text="X" * 5), "clause verbatim_text must equal the parent slice"),
    (lambda c, p: c.update(clause_classification="layout"), "unknown clause classification"),
    (lambda c, p: p.update(parent_observation_id="other"), "parent observation must be top level"),
])
def test_bundle_1_2_rejects_invalid_clause(strict_bundle, mutate, expected):
    bundle = json.loads(json.dumps(strict_bundle))
    bundle["schema_version"] = "1.2"
    parent = bundle["observations"][0]
    clause = _clause(parent, 1, parent["span"]["char_from"], parent["span"]["char_from"] + 5, parent["verbatim_text"][:5])
    bundle["observations"].append(clause)
    mutate(clause, parent)
    with pytest.raises(ContractError, match=expected):
        validate_bundle(bundle)
```

Tilpas `strict_bundle`/`strict_bundle_factory` til det navn, filen faktisk bruger for sin gyldige strict-fixture (søg efter `"schema_version": "1.1"` i testfilen). Findes der ingen genbrugelig fixture, byg én i en `@pytest.fixture` ud fra den eksisterende `tests/fixtures/evidence-observation.synthetic.json` med `schema_version` sat til `"1.1"` og de felter, `_strict_renditions` kræver (`source_rendition[].verbatim_text` med matchende sha256).

- [ ] **Step 2: Kør og se dem fejle**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -q -k "clause or 1_2"
```

Forventet: FAIL (`unsupported schema version` / `unknown observation fields`).

- [ ] **Step 3: Implementér**

I `Observation` (dataclass, frozen): tilføj efter `extraction_run_id`:

```python
    parent_observation_id: Optional[str] = None
    clause_ordinal: Optional[int] = None
    clause_classification: Optional[str] = None
    clause_flags: Tuple[str, ...] = ()
```

og i `Observation.validate()` efter substring-checket:

```python
        is_clause = self.kind == "clause"
        has_clause_fields = any([self.parent_observation_id, self.clause_ordinal is not None,
                                 self.clause_classification, self.clause_flags])
        if is_clause and not (self.parent_observation_id and self.clause_ordinal and self.clause_classification is not None):
            raise ContractError("clause requires parent, ordinal and classification")
        if not is_clause and has_clause_fields:
            raise ContractError("clause fields are only allowed on kind clause")
        if is_clause and self.clause_classification not in ("record_text", "structural_header"):
            raise ContractError("unknown clause classification")
        if is_clause and self.clause_ordinal < 1:
            raise ContractError("clause ordinal must be positive")
```

I `_as_observation`: gør feltmængden versionsafhængig. Signaturen udvides med `schema_version: str = "1.1"`; i strict mode:

```python
    allowed = {"observation_id", "occurrence_id", "kind", "verbatim_text", "span",
               "extraction_method", "extraction_run_id"}
    if schema_version == "1.2":
        allowed |= {"parent_observation_id", "clause_ordinal", "clause_classification", "clause_flags"}
    if strict:
        _exact_fields_subset(value, allowed, {"observation_id", "occurrence_id", "kind", "verbatim_text",
                                              "span", "extraction_method", "extraction_run_id"}, "observation")
```

hvor `_exact_fields_subset(value, allowed, required, label)` er en ny lille hjælper ved siden af `_exact_fields`, der kræver `required ⊆ keys ⊆ allowed`. Konstruktionen af `Observation` får de fire felter med `value.get(...)` og `tuple(value.get("clause_flags") or ())`.

I `validate_bundle`:

```python
    if schema_version not in ("1.0", "1.1", "1.2"):
        raise ContractError("unsupported schema version")
    strict = schema_version in ("1.1", "1.2")
```

og send `schema_version` med til `_as_observation`. Efter observations-loopet (hvor `observation_by_id` findes eller bygges) tilføj:

```python
    if schema_version == "1.2":
        observation_by_id = {item.observation_id: item for item in observations}
        for item in observations:
            if item.kind != "clause":
                continue
            parent = observation_by_id.get(item.parent_observation_id or "")
            if parent is None:
                raise ContractError("clause requires parent")
            if parent.kind == "clause" or parent.parent_observation_id:
                raise ContractError("parent observation must be top level")
            if parent.occurrence_id != item.occurrence_id:
                raise ContractError("clause occurrence differs from parent")
            if item.span.char_from < parent.span.char_from or item.span.char_to > parent.span.char_to:
                raise ContractError("clause span outside parent")
            start = item.span.char_from - parent.span.char_from
            if parent.verbatim_text[start:start + (item.span.char_to - item.span.char_from)] != item.verbatim_text:
                raise ContractError("clause verbatim_text must equal the parent slice")
    elif any(getattr(item, "parent_observation_id", None) for item in observations):
        raise ContractError("clause fields require schema version 1.2")
```

I `evidence_extract.validate_output` (linje 150): erstat `if bundle.get("schema_version") != "1.1":` med `if bundle.get("schema_version") not in ("1.1", "1.2"):`.

- [ ] **Step 4: Kør hele Python-suiten**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
```

Forventet: alle grønne (samme antal skips som før: 3).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/evidence_contract.py .claude/skills/daa-extract/scripts/test_evidence_contract.py .claude/skills/daa-extract/scripts/evidence_extract.py
git commit -m "feat(evidens): bundle-skema 1.2 med klausul-observationer under helpost (#148 4.1a)"
```

---

### Task 7: Rigtig kørsel på restore + rapport

**Files:**
- Create: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`
- Modify: `docs/changelog.md` (ny dateret post øverst)

Forudsætning: et prod-dump (`$DUMP_PATH`, 0600) og Homebrew PostgreSQL 17 som i `docs/runbooks/source-evidence-reimport-rehearsal.md` §2. Rollerne `anon`, `authenticated`, `service_role` skal findes i clusteret.

- [ ] **Step 1: Restore og migrér**

```bash
set -euo pipefail; umask 077; export PGTZ=UTC
PG=/opt/homebrew/opt/postgresql@17/bin
DB="daa148a_rehearsal_$(date +%Y%m%d%H%M%S)"
ART="$HOME/.private/148a-$DB"; mkdir -p "$ART"; chmod 700 "$ART"
$PG/createdb "$DB"
PGDATABASE="$DB" $PG/pg_restore --clean --if-exists --no-owner --dbname="$DB" "$DUMP_PATH" 2>"$ART/restore.err" || true
grep -c '^pg_restore: error' "$ART/restore.err"   # kun supabase_vault-fejl er tilladt
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -Atc "SELECT count(*) FROM private.source_observation WHERE observation_kind='person_post'"   # forventet 591
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql
```

Forventet: begge migrationer exit 0; inventeringsblokken må ikke kaste `CLAUSE_MIGRATION_OBSERVATION_KIND_UNSEEDED`.

- [ ] **Step 2: Verificér**

```bash
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql 2>&1 | grep -E 'OK: #148|ERROR' 
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -Atc "
SELECT (SELECT count(*) FROM private.source_observation WHERE observation_kind='person_post'),
       (SELECT count(*) FROM private.source_observation WHERE observation_kind='clause'),
       (SELECT count(*) FROM private.source_observation WHERE parent_observation_id IS NOT NULL),
       (SELECT count(*) FROM private.vocab WHERE scheme='observation_kind'),
       (SELECT count(*) FROM private.clause_disposition)"
```

Forventet: `591|0|0|8|0` og `OK: #148 …`.

- [ ] **Step 3: Kør 149b's SQL-suite mod restoren for regressionsbeviset (fixtures er syntetiske og ruller tilbage)**

```bash
PGDATABASE="$DB" $PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql 2>&1 | grep -E 'NOTICE|ERROR'
```

Forventet: alle `… OK`-notices inkl. `task3 clause mentions OK`; ingen `ERROR`. Basen er stadig prod-ækvivalent bagefter, fordi filen ruller tilbage.

- [ ] **Step 4: Skriv rapporten (kun tal og hashes)**

`docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`:

```markdown
# #148 klausullag: rehearsal-rapport

**Dagsværk 4.1a (skema)** — dato, base `<DB>`, dump-SHA `<sha256 af $DUMP_PATH>`.

| Måling | Før | Efter |
| --- | --- | --- |
| `person_post`-observationer (source 1) | 591 | 591 |
| `clause`-observationer | 0 | 0 |
| `private.vocab` `observation_kind`-koder | – | 8 |
| `db-migrations.sql` kørt to gange | – | exit 0 / exit 0 |
| `run-db-verify-disposable.sql` | – | `OK: #148 …` |
| `test-reimport-legacy-migration.sql` mod restoren | – | alle notices OK |

Ingen persondata i denne rapport. Basen droppes efter 4.1c, ikke før.
```

- [ ] **Step 5: Changelog og commit**

Tilføj øverst i `docs/changelog.md` en dateret post "#148 4.1a: klausullagets skema — migreret og verificeret på restore; ingen prod-mutation".

```bash
git branch --show-current
git add docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md docs/changelog.md
git commit -m "docs(genimport): 4.1a klausul-skema kørt på restore af prod-dump (#148)"
```

---

## Selvreview-checkliste før aflevering

- [ ] `schema.sql` og `db-migrations.sql` giver byte-identiske funktionskroppe (`pg_get_functiondef` på begge stier).
- [ ] CI's PostgreSQL-jobs grønne på grenen; Python-suiten grøn.
- [ ] Ingen fixture i repo indeholder rigtige navne.
- [ ] Rapporten indeholder tal og hashes, ikke tekst.
