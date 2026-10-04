# Overførsel af 2018-20 — plan A: pakke, digests og lokal genafspilning

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Byg de repo-filer, overførslen hviler på (fingeraftryk, digests, baseline, pakkebygger, genererede skrive-SQL'er), og bevis lokalt, at pakken genskaber restorens 3.739 forslag, 676 afgørelser og 622 bindinger på en ren restore af dumpet 2026-10-01 (`PACK_REPLAY_OK`).

**Architecture:** Læse-SQL-filer gemmer deres resultat som JSON i en GUC (`set_config('daa.…', …, false)`) og printer den, som `interpretation_control_classification.sql` gør; de kører derfor også under `default_transaction_read_only=on`. Python (`transfer_pack.py`) er databasefri: den læser JSON-filer, bygger og validerer pakken, klassificerer tilstanden og genererer skrive-SQL'en for `07`/`08` — samme mønster som `control_model.py`. Skrive-SQL'en køres fra repo-roden, fordi den `\i`'er repo-filerne relativt.

**Tech Stack:** PostgreSQL 17 (psql), Python 3 (stdlib, pytest), zsh; R kun via den eksisterende `~/.private/2018-20-fuld/44g-apply.R` i Task 6.

**Spec:** `docs/superpowers/specs/2026-10-03-trin4-2018-20-prod-overfoersel-design.md` (godkendt 2026-10-04, inkl. errata `92f8ed9`).

**Opdeling:** Plan A er repo-artefakter og det lokale bevis; den giver fungerende, testet software for sig. **Plan B** (private ceremoni-scripts `00`-`08`, ny lib, runbook, stand-in-rehearsal) skrives først, når Task 6 har givet `PACK_REPLAY_OK`, så dens grænseflader er målte, ikke gættede.

## Global Constraints

- **Ingen prod.** Intet i denne plan forbinder til prod. Lokale baser kun via `-h /tmp` med ryddet miljø: `env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD -u PGDATABASE psql -h /tmp …`.
- **Ingen kildetekst i repo, logs, commits eller chat** — heller ikke claim-værdier eller noter. Kun tal, nøgler og hashes. Private filer 0600, mapper 0700, under `~/.private/2018-20-overfoersel/`.
- **Restoren `daa2018f_20261001133125` er facit og ændres ikke.** Lokale testbaser navngives `daa44_rehearsal_transfer_<UTC-stempel>` (R-filernes basenavnsmønster `^daa44_rehearsal_[a-z0-9_]+$`), så R-filerne forbliver uændrede.
- **Kilden** 2018-20 er `source_id = 1` i restore og prod; SQL-filerne tager den som psql-variablen `src` (`-v src=1`).
- **Hashing:** ordnet med `COLLATE "C"`; rækker som `to_jsonb(…)::text`, aldrig `x::text`. SHA-256 via `extensions.digest(convert_to(…,'UTF8'),'sha256')`.
- **Kanonisk JSON** (Python): `json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))`, UTF-8.
- **Ingen DDL** — ingen `CREATE FUNCTION`/`VIEW` i nogen fil. Midlertidige tabeller kun i skrive-SQL (`ON COMMIT DROP`).
- **pytest:** `/usr/bin/python3 -m pytest` (Homebrews Python har ikke pytest). Kør `env -u NODE_OPTIONS` foran (kendt miljøfejl). Nye testfiler skal på listen i `.github/workflows/ci.yml`, job `python`; nye SQL-tests i jobbet `evidence-promotion-db`'s step-liste. Verificér lokalt før push — CI-minutter er knappe.
- **Lokal SQL-testopskrift = CI's:** `createdb X; psql -f tests/sql/evidence-promotion-bootstrap.sql; psql -f schema.sql; psql -f db-rls.sql; psql -f db-migrations.sql; psql -f db-migrations.sql; psql -f db-rls.sql` (alle med `-v ON_ERROR_STOP=1 -d X`), derefter testfilen.
- **Commits:** én pr. task, Conventional Commits på dansk, `type(147): …`, afsluttet med `Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb`. Ingen push uden projektejerens ja.

## Review Focus

1. **En kanonisk rettelse mellem pakkebygning og genafspilning** (fx én assertion-værdi) skal give `TRANSFER_DRIFT` i baselinen *og* `MACHINE_PREMISE_DRIFT` i `07` — ikke en stille, anderledes binding. Test i Task 3 og Task 5.
2. **En afgørelse, hvis citerede klausultekst er ændret, mens nøglen stadig findes** (nøglen binder ikke teksten), skal give `DECISION_FINGERPRINT_MISMATCH`. Test i Task 1 og Task 5.
3. **`07` køres to gange:** anden gang er tilstanden `DECIDED`, og scriptet melder `already_applied` uden at skrive; evidensen er uændret. Test i Task 4 (tilstand) og Task 5 (SQL'ens tilstandsvagt).
4. **En nøgle med to aktuelle rækker eller en afgjort version, der ikke er pakkens** (skrevet udenom), giver `DECISION_KEY_UNRESOLVED` / `TRANSFER_STATE_NOT_PROPOSED`, ikke en delvis skrivning. Test i Task 5.
5. **Dry-run'ens profilrække og autorisation** må ikke flytte forslags-/afgørelses-/bindings-digesten eller baselinen (de ligger uden for alle tre), men flytter restore-hashen — derfor måles den før dry-run'en. Test i Task 3.

---

## Filoversigt

| Fil | Ansvar |
| --- | --- |
| `.claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql` | **Ny.** Fingeraftryk pr. `interpretation_key` → `daa.fingerprints` |
| `.claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql` | **Ny.** De tre digests + antal → `daa.transfer_digests` |
| `.claude/skills/daa-extract/scripts/transfer_baseline.sql` | **Ny.** Driftsbaseline (indholdshash), `clause_set_sha256`, skema-fingeraftryk → `daa.transfer_baseline` |
| `.claude/skills/daa-extract/scripts/transfer_restore_hash.sql` | **Ny.** Hash over alle tabeller og sekvenser i `private`+`public` → `daa.restore_hash` |
| `.claude/skills/daa-extract/scripts/transfer_untouched_hash.sql` | **Ny.** Som restore-hashen minus kædens tabeller → `daa.untouched_hash` |
| `.claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql` | **Ny.** Forældreløse rækker pr. FK + katalogfingeraftryk → `daa.restore_preconditions` |
| `.claude/skills/daa-extract/scripts/transfer_pack_export.sql` | **Ny.** Restorens afgørelser + id→nøgle-kort → `daa.pack_export` |
| `.claude/skills/daa-extract/scripts/interpretation_promotion_targets_scoped.sql` | **Ny.** Wrapper: den delte målfinding filtreret til pakkens nøgler |
| `.claude/skills/daa-extract/scripts/transfer_pack.py` | **Ny.** `build`, `state`, `decide-sql`, `bind-sql` |
| `.claude/skills/daa-extract/scripts/test_transfer_pack.py` | **Ny.** pytest |
| `tests/sql/transfer-fixture.sql` | **Ny.** Fælles fixture: to kilder med samme logiske indhold og forskellige id'er |
| `tests/sql/test-transfer-fingerprint-digests.sql` | **Ny.** Task 1-2 |
| `tests/sql/test-transfer-baseline.sql` | **Ny.** Task 3 |
| `tests/sql/test-transfer-decide-bind.sql` | **Ny.** Task 5 (kører genereret SQL) |
| `tests/fixtures/transfer-pack/` | **Ny.** Små JSON-fixtures til pytest og Task 5 |
| `.github/workflows/ci.yml` | Nye testfiler på listerne |

---

### Task 0: Forudsætninger målt

**Files:** ingen ændringer; resultatet noteres i plan-ændringsloggen (Task 6, Step 9).

- [ ] **Step 1: Mål restorens grundtal (kun tal)**

```bash
P(){ env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD -u PGDATABASE psql -h /tmp -d daa2018f_20261001133125 -X -A -t "$@"; }
P -c "SELECT count(*), count(DISTINCT interpretation_key) FROM private.interpretation WHERE source_id=1 AND version=1"
P -c "SELECT status, decision_evidence->>'method', count(*) FROM private.interpretation_current WHERE source_id=1 GROUP BY 1,2 ORDER BY 1,2"
P -c "SELECT count(*), count(DISTINCT decided_by) FROM private.interpretation_current WHERE source_id=1 AND status<>'proposed'"
P -c "SELECT count(*) FROM private.interpretation_promotion"
P -c "SELECT profile_id, profile_version FROM private.reimport_writer_profile WHERE source_id=1 AND profile_id LIKE '%interpretation-proposal%'"
shasum -a 256 ~/.private/2018-20-fuld/kontrol/klassifikation.json | cut -c1-16
```

Expected: `3739|3739`; `accepted|human-sheet-kontrol-v1|61`, `accepted|machine-corroboration-v1|602`, `proposed||3063`, `unresolved|human-sheet-kontrol-v1|13`; `676|1`; `622`; `daa-2018-20-interpretation-proposal-v1|1.0.0`; `ded0de566…`. Afviger noget: STOP og spørg.

- [ ] **Step 2: Opret den private mappe**

```bash
mkdir -m 700 -p ~/.private/2018-20-overfoersel/{pack,replay,export}
```

---

### Task 1: Fingeraftryk pr. nøgle

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql`
- Create: `tests/sql/transfer-fixture.sql`
- Create: `tests/sql/test-transfer-fingerprint-digests.sql` (Task 2 udvider den)
- Modify: `.github/workflows/ci.yml` (job `evidence-promotion-db`, efter `test-interpretation-control-classification.sql`)

**Interfaces:**
- Produces: `daa.fingerprints` = JSON-objekt `{"<interpretation_key>": "<sha256 hex>", …}` for alle version 1-rækker i kilden `:src`. Fingeraftrykket = SHA-256 over `private.interpretation_proposal_canonical_json_text({fp_version:1, interpretation_key, record_key, predicate, value_sha256, clauses:[[clause_ordinal, verbatim_sha256], …]})`, `clauses` sorteret efter `interpretation_observation.ordinal`.
- Produces (fixture): to kilder `-4700` og `-4701` med samme logiske indhold og forskellige uuid'er; persona-nøgler, record-nøgler og værdier er ens. Kilde `-4700` har id-præfiks `a4700000-`, kilde `-4701` `a4701000-`.

- [ ] **Step 1: Skriv fixturen**

`tests/sql/transfer-fixture.sql` — kaldes inde i en transaktion af testfilerne. Den følger `tests/sql/test-interpretation-control-classification.sql` (samme tabeller og kolonner) og tilføjer source record + anker, så record-nøglen kan slås op. Afviger en kolonne eller constraint fra `schema.sql`, rettes fixturen efter skemaet — ikke omvendt.

```sql
-- Fælles fixture for overførselstestene (plan A, Task 1). Kaldes inden for BEGIN … ROLLBACK.
-- To kilder (-4700, -4701) med SAMME logiske indhold og FORSKELLIGE uuid'er: digests og
-- fingeraftryk filtreret pr. kilde skal være ens. Tre forslag pr. kilde:
--   k1 principal person.death '1850'  → MATCH mod assertion -4711 (kilde -4700) / -4711 deles
--   k2 principal person.name  'Anna'  → REAL_DIFF (assertion 'Anne')
--   k3 other     mention.place 'Kbh'  → ingen regel
INSERT INTO auth.users(id,email) VALUES ('a4700000-0000-4000-8000-000000000001','transfer47@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4700000-0000-4000-8000-000000000001','redaktion','Transfer 47','transfer47@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES (-4701,false,false,'transfer47');
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-4711,'person',-4701,'død'),(-4712,'person',-4701,'navn');
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES (-4711,'fact',-4711,'1850','gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES (-4712,'fact',-4712,'Anne','gregoriansk',true);
DO $fx$
DECLARE s bigint; pre text;
BEGIN
  FOR s, pre IN SELECT * FROM (VALUES (-4700::bigint,'a4700000'),(-4701::bigint,'a4701000')) v LOOP
    INSERT INTO source(id,titel,import_key) VALUES (s,'Transfer '||s,'verify:transfer'||s);
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES ((pre||'-0000-4000-8000-0000000000e1')::uuid,s,'transfer-run'||s,'1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
      VALUES ((pre||'-0000-4000-8000-0000000000e2')::uuid,s,'transfer-rendition','text_layer',repeat('8',64),'{}');
    INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES ((pre||'-0000-4000-8000-0000000000e3')::uuid,(pre||'-0000-4000-8000-0000000000e2')::uuid,'transfer-occ',1,1,0,20,
              'Anna død 1850 i Kbh','phys-t','struct-t',(pre||'-0000-4000-8000-0000000000e1')::uuid);
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES ((pre||'-0000-4000-8000-0000000000e5')::uuid,s,'T-1','person_entry',(pre||'-0000-4000-8000-0000000000e1')::uuid);
    INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by_name)
      VALUES ((pre||'-0000-4000-8000-0000000000e3')::uuid,(pre||'-0000-4000-8000-0000000000e5')::uuid,'accepted',
              '{"basis":"transfer-fixture"}',1,'fixture');
    -- To klausuler (ordinal 1 og 2).
    INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
      verbatim_text,quality_status,extraction_method,extraction_run_id,clause_ordinal)
      VALUES ((pre||'-0000-4000-8000-0000000000c1')::uuid,(pre||'-0000-4000-8000-0000000000e3')::uuid,'clause',1,1,0,13,
              'Anna død 1850','clear','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid,1),
             ((pre||'-0000-4000-8000-0000000000c2')::uuid,(pre||'-0000-4000-8000-0000000000e3')::uuid,'clause',1,1,14,20,
              'i Kbh','clear','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid,2);
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES ((pre||'-0000-4000-8000-000000000101')::uuid,s,'T-1',(pre||'-0000-4000-8000-0000000000e1')::uuid);
    INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by_name)
      VALUES ((pre||'-0000-4000-8000-000000000101')::uuid,-4701,'accepted',1,'{"basis":"fixture"}','fixture');
    -- Tre forslag; nøglen dannes af writerens egen funktion over (kilde, post, prædikat, ordinaler, værdi)
    -- — her sat direkte, så de to kilder får samme nøgle og testen kan sammenligne på tværs.
    INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
      predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES
      ((pre||'-0000-4000-8000-000000000301')::uuid,'b4700000-0000-4000-8000-000000000001',1,s,(pre||'-0000-4000-8000-000000000101')::uuid,
       'event','person.death',to_jsonb('1850'::text),'1.0','source_statement',1,'proposed','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid),
      ((pre||'-0000-4000-8000-000000000302')::uuid,'b4700000-0000-4000-8000-000000000002',1,s,(pre||'-0000-4000-8000-000000000101')::uuid,
       'property','person.name',to_jsonb('Anna'::text),'1.0','source_statement',1,'proposed','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid),
      ((pre||'-0000-4000-8000-000000000303')::uuid,'b4700000-0000-4000-8000-000000000003',1,s,NULL,
       'mention','mention.place',to_jsonb('Kbh'::text),'1.0','source_statement',1,'proposed','verify',(pre||'-0000-4000-8000-0000000000e1')::uuid);
    INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES
      ((pre||'-0000-4000-8000-000000000301')::uuid,(pre||'-0000-4000-8000-0000000000c1')::uuid,'supporting',1),
      ((pre||'-0000-4000-8000-000000000302')::uuid,(pre||'-0000-4000-8000-0000000000c1')::uuid,'supporting',1),
      ((pre||'-0000-4000-8000-000000000303')::uuid,(pre||'-0000-4000-8000-0000000000c2')::uuid,'supporting',1);
    INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,decided_by_name,evidence)
      VALUES ((pre||'-0000-4000-8000-0000000000c1')::uuid,1,'fortolkning_foreslaaet','machine','fixture',
              jsonb_build_object('batch_id',pre)),
             ((pre||'-0000-4000-8000-0000000000c2')::uuid,1,'fortolkning_foreslaaet','machine','fixture',
              jsonb_build_object('batch_id',pre));
  END LOOP;
END $fx$;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
```

Bemærk: `interpretation_key` er her sat ens i begge kilder med vilje (testen handler om, at *id'erne* er forskellige). `interpretation_kind`-værdierne og `clause_disposition`-kolonnerne skal stemme med skemaets CHECK-constraints og prædikattabellen; ret fixturen, hvis `schema.sql` siger andet.

- [ ] **Step 2: Skriv den fejlende test**

`tests/sql/test-transfer-fingerprint-digests.sql`:

```sql
\set ON_ERROR_STOP on
-- Overførslens fingeraftryk og digests (spec 2026-10-03 §4.2, §5; plan A Task 1-2).
BEGIN;
\i tests/sql/transfer-fixture.sql
-- (F1) Samme indhold, forskellige id'er ⇒ samme fingeraftryk pr. nøgle.
\set src -4700
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
SELECT set_config('t.fp_a', current_setting('daa.fingerprints'), true);
\set src -4701
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ BEGIN
  IF current_setting('t.fp_a')::jsonb IS DISTINCT FROM current_setting('daa.fingerprints')::jsonb THEN
    RAISE EXCEPTION 'F1: fingeraftryk afhænger af id''er';
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(current_setting('t.fp_a')::jsonb)) <> 3 THEN
    RAISE EXCEPTION 'F1: forventede 3 nøgler';
  END IF;
END $$;
-- (F2) Ændret klausultekst ⇒ ændret fingeraftryk (kun for de nøgler, der citerer klausulen).
UPDATE private.source_observation SET verbatim_text='Anna død 1851' WHERE id='a4701000-0000-4000-8000-0000000000c1';
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ DECLARE a jsonb := current_setting('t.fp_a')::jsonb; b jsonb := current_setting('daa.fingerprints')::jsonb; BEGIN
  IF a->>'b4700000-0000-4000-8000-000000000001' = b->>'b4700000-0000-4000-8000-000000000001' THEN RAISE EXCEPTION 'F2: tekst ikke bundet'; END IF;
  IF a->>'b4700000-0000-4000-8000-000000000003' <> b->>'b4700000-0000-4000-8000-000000000003' THEN RAISE EXCEPTION 'F2: urelateret nøgle ændret'; END IF;
END $$;
UPDATE private.source_observation SET verbatim_text='Anna død 1850' WHERE id='a4701000-0000-4000-8000-0000000000c1';
-- (F3) Ændret ordinal ⇒ ændret fingeraftryk.
UPDATE private.source_observation SET clause_ordinal=3 WHERE id='a4701000-0000-4000-8000-0000000000c2';
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ BEGIN
  IF current_setting('t.fp_a')::jsonb->>'b4700000-0000-4000-8000-000000000003'
     = current_setting('daa.fingerprints')::jsonb->>'b4700000-0000-4000-8000-000000000003' THEN
    RAISE EXCEPTION 'F3: ordinal ikke bundet'; END IF;
END $$;
UPDATE private.source_observation SET clause_ordinal=2 WHERE id='a4701000-0000-4000-8000-0000000000c2';
-- (F4) Ændret værdi ⇒ ændret fingeraftryk.
UPDATE private.interpretation SET value=to_jsonb('Anne'::text) WHERE id='a4701000-0000-4000-8000-000000000302';
\i .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql
DO $$ BEGIN
  IF current_setting('t.fp_a')::jsonb->>'b4700000-0000-4000-8000-000000000002'
     = current_setting('daa.fingerprints')::jsonb->>'b4700000-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'F4: værdi ikke bundet'; END IF;
END $$;
UPDATE private.interpretation SET value=to_jsonb('Anna'::text) WHERE id='a4701000-0000-4000-8000-000000000302';
\echo 'OK: transfer fingerprint'
ROLLBACK;
```

Hvis en `UPDATE` på `private.interpretation`/`source_observation` afvises af en uforanderligheds-trigger, så erstat F2-F4 med at indsætte en *tredje* kilde (`-4702`, præfiks `a4702000-`) med den ændrede tekst/ordinal/værdi og sammenlign den med `t.fp_a`.

- [ ] **Step 3: Kør testen og se den fejle**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
DB=daa_transfer_t1_$(date -u +%H%M%S)
PSQL="env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD -u PGDATABASE psql -h /tmp -X -q -v ON_ERROR_STOP=1 -d $DB"
env -u PGHOST createdb -h /tmp "$DB"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do $PSQL -f "$f" >/dev/null; done
$PSQL -f tests/sql/test-transfer-fingerprint-digests.sql
```

Expected: FAIL med `could not open … interpretation_decision_fingerprint.sql`.

- [ ] **Step 4: Skriv fingeraftryksfilen**

`.claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql`:

```sql
-- Fingeraftryk pr. interpretation_key (spec 2026-10-03 §4.2; 24/9-spec §4.2). Læse-kun.
-- Binder afgørelsen til den tekst, mennesket læste: post, prædikat, værdi og de citerede
-- klausulers (ordinal, tekst-hash), sorteret efter linkets ordinal. Id'er indgår ikke.
-- Input: psql-variablen src. Output: daa.fingerprints = {"<nøgle>": "<sha256>", …}.
WITH v1 AS (
  SELECT i.id, i.interpretation_key, i.predicate,
         private.interpretation_proposal_canonical_json_sha256(i.value) AS value_sha256
    FROM private.interpretation i
   WHERE i.source_id = :src AND i.version = 1
), rec AS (
  SELECT DISTINCT ON (v1.id) v1.id, sr.record_key
    FROM v1
    JOIN private.interpretation_observation io ON io.interpretation_id = v1.id
    JOIN private.source_observation so ON so.id = io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id
                                               AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
   ORDER BY v1.id, sr.record_key COLLATE "C"
), cl AS (
  SELECT io.interpretation_id AS id,
         jsonb_agg(jsonb_build_array(so.clause_ordinal,
                     encode(extensions.digest(convert_to(so.verbatim_text,'UTF8'),'sha256'),'hex'))
                   ORDER BY io.ordinal) AS clauses
    FROM private.interpretation_observation io
    JOIN private.source_observation so ON so.id = io.observation_id
   WHERE io.interpretation_id IN (SELECT id FROM v1)
   GROUP BY io.interpretation_id
), fp AS (
  SELECT v1.interpretation_key::text AS k,
         encode(extensions.digest(convert_to(private.interpretation_proposal_canonical_json_text(
           jsonb_build_object('fp_version', 1, 'interpretation_key', v1.interpretation_key,
                              'record_key', rec.record_key, 'predicate', v1.predicate,
                              'value_sha256', v1.value_sha256,
                              'clauses', coalesce(cl.clauses, '[]'::jsonb))),'UTF8'),'sha256'),'hex') AS fp
    FROM v1 LEFT JOIN rec USING (id) LEFT JOIN cl USING (id)
)
SELECT set_config('daa.fingerprints', coalesce((SELECT jsonb_object_agg(k, fp) FROM fp), '{}'::jsonb)::text, false)
       AS fingerprints;
```

- [ ] **Step 5: Kør testen og se den bestå**

Samme kommando som Step 3 (ny base). Expected: `OK: transfer fingerprint`.

- [ ] **Step 6: CI og commit**

I `.github/workflows/ci.yml`, job `evidence-promotion-db`, tilføj efter linjen med `test-interpretation-control-classification.sql`:

```yaml
          psql -v ON_ERROR_STOP=1 -f tests/sql/test-transfer-fingerprint-digests.sql
```

```bash
git add .claude/skills/daa-extract/scripts/interpretation_decision_fingerprint.sql tests/sql/transfer-fixture.sql tests/sql/test-transfer-fingerprint-digests.sql .github/workflows/ci.yml
git commit -m "feat(147): fingeraftryk pr. fortolkningsnøgle til overførslen"
```

---

### Task 2: De tre digests

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql`
- Modify: `tests/sql/test-transfer-fingerprint-digests.sql` (tilføj D1-D6 før `ROLLBACK`)

**Interfaces:**
- Consumes: fixturen fra Task 1.
- Produces: `daa.transfer_digests` = JSON
  `{"n_interpretations", "proposal_digest", "n_decided", "decided_by_method_status": {"<metode>|<status>": n}, "decision_digest", "n_bindings", "binding_digest"}`. Tomme lag giver antal 0 og digest = SHA-256 af tom streng (`e3b0c442…`).

- [ ] **Step 1: Tilføj de fejlende tests** (indsæt før `\echo 'OK: transfer fingerprint'` i testfilen)

```sql
-- (D1) Samme indhold, forskellige id'er ⇒ samme tre digests.
\set src -4700
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
SELECT set_config('t.dg_a', current_setting('daa.transfer_digests'), true);
\set src -4701
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
DO $$ BEGIN
  IF current_setting('t.dg_a')::jsonb IS DISTINCT FROM current_setting('daa.transfer_digests')::jsonb THEN
    RAISE EXCEPTION 'D1: digests afhænger af id''er';
  END IF;
  IF (current_setting('t.dg_a')::jsonb->>'n_interpretations')::int <> 3 THEN RAISE EXCEPTION 'D1: antal'; END IF;
END $$;
-- (D2) Dispositions-evidence (batch_id) er udeladt: den er forskellig i de to kilder, og D1 bestod.
-- (D3) Afgør k1 accepted og k2 rejected i begge kilder ⇒ ens; ombyt status i kilde -4701 ⇒ forskellig.
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation('a4700000-0000-4000-8000-000000000301',1,'accepted','{"method":"m"}');
SELECT red_decide_interpretation('a4700000-0000-4000-8000-000000000302',1,'rejected','{"method":"m"}');
SELECT red_decide_interpretation('a4701000-0000-4000-8000-000000000301',1,'rejected','{"method":"m"}');
SELECT red_decide_interpretation('a4701000-0000-4000-8000-000000000302',1,'accepted','{"method":"m"}');
RESET ROLE;
\set src -4700
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
SELECT set_config('t.dg_a', current_setting('daa.transfer_digests'), true);
\set src -4701
\i .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql
DO $$ DECLARE a jsonb := current_setting('t.dg_a')::jsonb; b jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN
  IF a->>'proposal_digest' <> b->>'proposal_digest' THEN RAISE EXCEPTION 'D3: forslag ændret af afgørelse'; END IF;
  IF a->'decided_by_method_status' IS DISTINCT FROM b->'decided_by_method_status' THEN RAISE EXCEPTION 'D3: fordeling'; END IF;
  IF a->>'decision_digest' = b->>'decision_digest' THEN RAISE EXCEPTION 'D3: ombyttet status ikke fanget'; END IF;
END $$;
-- (D4) pack_sha256 i evidensen tæller ikke med: samme afgørelser med og uden pack_sha256 ⇒ ens digest.
-- Dækkes i Task 5 (genereret SQL tilføjer pack_sha256); her kun at nøglen fjernes:
DO $$ BEGIN
  IF (SELECT ('{"a":1,"pack_sha256":"x"}'::jsonb - 'pack_sha256') <> '{"a":1}'::jsonb) THEN RAISE EXCEPTION 'D4'; END IF;
END $$;
\echo 'OK: transfer digests'
```

Bindingsdelen (to mål pr. nøgle, ændret mål) testes i Task 5, hvor bindinger skrives med RPC'en.

- [ ] **Step 2: Kør testen og se den fejle**

Kommando som Task 1 Step 3. Expected: FAIL med `could not open … interpretation_transfer_digests.sql`.

- [ ] **Step 3: Skriv digest-filen**

`.claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql`:

```sql
-- Overførslens tre nøglede digests (spec 2026-10-03 §5). Læse-kun; samme bytes i restore,
-- rehearsal og prod. Hver hashet række indeholder interpretation_key; ingen id'er, tidsstempler
-- eller batch-/kørsels-id'er. Input: psql-variablen src. Output: daa.transfer_digests.
WITH v1 AS (
  SELECT i.* FROM private.interpretation i WHERE i.source_id = :src AND i.version = 1
), links AS (
  SELECT io.interpretation_id AS id,
         jsonb_agg(jsonb_build_object(
           'ordinal', io.ordinal, 'clause_ordinal', so.clause_ordinal, 'evidence_role', io.evidence_role,
           'verbatim_sha256', encode(extensions.digest(convert_to(so.verbatim_text,'UTF8'),'sha256'),'hex'),
           'disposition', cd.disposition)
           ORDER BY io.ordinal, so.clause_ordinal) AS l
    FROM private.interpretation_observation io
    JOIN private.source_observation so ON so.id = io.observation_id
    LEFT JOIN private.clause_disposition_current cd ON cd.observation_id = so.id
   WHERE io.interpretation_id IN (SELECT id FROM v1)
   GROUP BY io.interpretation_id
), prop_rows AS (
  SELECT v1.interpretation_key::text AS k, to_jsonb(r)::text AS t
    FROM v1 LEFT JOIN links ON links.id = v1.id
    LEFT JOIN private.source_persona sp ON sp.id = v1.source_persona_id
   CROSS JOIN LATERAL (SELECT v1.interpretation_key AS key, v1.predicate, v1.interpretation_kind,
          private.interpretation_proposal_canonical_json_sha256(v1.value) AS value_sha256,
          v1.confidence, sp.persona_key, v1.schema_version, v1.method, v1.model_version,
          v1.prompt_version, v1.derivation_kind, coalesce(links.l, '[]'::jsonb) AS links) r
), cur AS (
  SELECT ic.* FROM private.interpretation_current ic WHERE ic.source_id = :src
), dec_rows AS (
  SELECT cur.interpretation_key::text AS k, to_jsonb(r)::text AS t
    FROM cur CROSS JOIN LATERAL (SELECT cur.interpretation_key AS key, cur.version, cur.status,
          CASE WHEN cur.decision_evidence IS NULL THEN NULL ELSE cur.decision_evidence - 'pack_sha256' END AS evidence,
          CASE WHEN cur.decided_by IS NULL THEN NULL
               ELSE encode(extensions.digest(convert_to(cur.decided_by::text,'UTF8'),'sha256'),'hex') END
            AS decided_by_sha256) r
), bind_rows AS (
  SELECT i.interpretation_key::text AS k, p.target_type, p.target_id::text AS tid,
         to_jsonb(r)::text AS t
    FROM private.interpretation_promotion p
    JOIN private.interpretation i ON i.id = p.interpretation_id
   CROSS JOIN LATERAL (SELECT i.interpretation_key AS key, p.target_type, p.target_id, p.rule_key, p.rule_version) r
   WHERE i.source_id = :src
), h AS (
  SELECT
    (SELECT count(*) FROM prop_rows) AS n_interpretations,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(t, E'\n' ORDER BY k COLLATE "C") FROM prop_rows),''),'UTF8'),'sha256'),'hex') AS proposal_digest,
    (SELECT count(*) FROM cur WHERE status <> 'proposed') AS n_decided,
    coalesce((SELECT jsonb_object_agg(ms, n) FROM (
       SELECT coalesce(decision_evidence->>'method','') || '|' || status AS ms, count(*) AS n
         FROM cur WHERE status <> 'proposed' GROUP BY 1) x), '{}'::jsonb) AS decided_by_method_status,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(t, E'\n' ORDER BY k COLLATE "C") FROM dec_rows),''),'UTF8'),'sha256'),'hex') AS decision_digest,
    (SELECT count(*) FROM bind_rows) AS n_bindings,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(t, E'\n' ORDER BY k COLLATE "C", target_type COLLATE "C", tid COLLATE "C") FROM bind_rows),''),'UTF8'),'sha256'),'hex') AS binding_digest
)
SELECT set_config('daa.transfer_digests', to_jsonb(h)::text, false) AS transfer_digests FROM h;
```

Bemærk: `decided_by_method_status` bruger nøglen `"<metode>|<status>"`. `interpretation_promotion.interpretation_id` peger på den afgjorte version (v2), så joinet går mod `private.interpretation` (alle versioner), ikke `interpretation_current`.

- [ ] **Step 4: Kør testen og se den bestå**

Expected: `OK: transfer fingerprint` og `OK: transfer digests`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/interpretation_transfer_digests.sql tests/sql/test-transfer-fingerprint-digests.sql
git commit -m "feat(147): tre nøglede digests for forslag, afgørelser og bindinger"
```

---

### Task 3: Baseline, restore-hash, uberørt-hash og restore-forudsætninger

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_baseline.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_restore_hash.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_untouched_hash.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql`
- Create: `tests/sql/test-transfer-baseline.sql`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `daa.transfer_baseline` = `{"canonical_sha256", "clause_set_sha256", "n_interpretations_src", "schema_sha256"}`; `daa.restore_hash` = sha256 hex; `daa.untouched_hash` = sha256 hex; `daa.restore_preconditions` = `{"orphans": {"<constraint>": n, …}, "n_orphans_total", "catalog_sha256"}`.

- [ ] **Step 1: Skriv den fejlende test**

`tests/sql/test-transfer-baseline.sql`:

```sql
\set ON_ERROR_STOP on
-- Driftsbaseline, restore-hash, uberørt-hash og restore-forudsætninger (spec §4.3, §5, §6.1; plan A Task 3).
BEGIN;
\i tests/sql/transfer-fixture.sql
\set src -4700
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
SELECT set_config('t.b0', current_setting('daa.transfer_baseline'), true);
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
SELECT set_config('t.r0', current_setting('daa.restore_hash'), true);
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
SELECT set_config('t.u0', current_setting('daa.untouched_hash'), true);
-- (B1) Gentagelse ⇒ samme værdier (deterministisk).
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
DO $$ BEGIN
  IF current_setting('daa.transfer_baseline') <> current_setting('t.b0') THEN RAISE EXCEPTION 'B1 baseline'; END IF;
  IF current_setting('daa.restore_hash') <> current_setting('t.r0') THEN RAISE EXCEPTION 'B1 restore'; END IF;
END $$;
-- (B2) Review Focus 5: en writer-profilrække og en autorisation (dry-run'ens spor) flytter IKKE
-- baselinen eller uberørt-hashen, men flytter restore-hashen.
INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES (-4700,'transfer-probe','1.0.0',repeat('a',64),'{}');
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
\i .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql
DO $$ BEGIN
  IF current_setting('daa.transfer_baseline') <> current_setting('t.b0') THEN RAISE EXCEPTION 'B2: baseline flyttet af profilrække'; END IF;
  IF current_setting('daa.untouched_hash') <> current_setting('t.u0') THEN RAISE EXCEPTION 'B2: uberørt flyttet af profilrække'; END IF;
  IF current_setting('daa.restore_hash') = current_setting('t.r0') THEN RAISE EXCEPTION 'B2: restore-hash fangede ikke profilrækken'; END IF;
END $$;
DELETE FROM private.reimport_writer_profile WHERE profile_id='transfer-probe';
-- (B3) Review Focus 1: én ændret assertion-værdi ⇒ baseline ændres (canonical_sha256).
UPDATE assertion SET date_raw='1851' WHERE id=-4711;
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
DO $$ BEGIN
  IF current_setting('daa.transfer_baseline')::jsonb->>'canonical_sha256'
     = current_setting('t.b0')::jsonb->>'canonical_sha256' THEN RAISE EXCEPTION 'B3: assertion-værdi ikke fanget'; END IF;
END $$;
UPDATE assertion SET date_raw='1850' WHERE id=-4711;
-- (B4) Ændret identitet ⇒ baseline ændres.
UPDATE private.source_persona_identity SET decision_status='rejected' WHERE source_persona_id='a4700000-0000-4000-8000-000000000101';
\i .claude/skills/daa-extract/scripts/transfer_baseline.sql
DO $$ BEGIN
  IF current_setting('daa.transfer_baseline')::jsonb->>'canonical_sha256'
     = current_setting('t.b0')::jsonb->>'canonical_sha256' THEN RAISE EXCEPTION 'B4: identitet ikke fanget'; END IF;
END $$;
UPDATE private.source_persona_identity SET decision_status='accepted' WHERE source_persona_id='a4700000-0000-4000-8000-000000000101';
-- (B5) Restore-hashen fanger en sekvens.
SELECT nextval('reimport_event_id_seq'::regclass);
\i .claude/skills/daa-extract/scripts/transfer_restore_hash.sql
DO $$ BEGIN
  IF current_setting('daa.restore_hash') = current_setting('t.r0') THEN RAISE EXCEPTION 'B5: sekvens ikke fanget'; END IF;
END $$;
-- (B6) Forudsætninger: 0 forældreløse i fixturen; en forældreløs række tælles.
\i .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql
DO $$ BEGIN
  IF (current_setting('daa.restore_preconditions')::jsonb->>'n_orphans_total')::int <> 0 THEN RAISE EXCEPTION 'B6: falsk forældreløs'; END IF;
  IF current_setting('daa.restore_preconditions')::jsonb->>'catalog_sha256' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'B6: katalog'; END IF;
END $$;
\echo 'OK: transfer baseline'
ROLLBACK;
```

Hvis `UPDATE` på `source_persona_identity` eller `assertion` afvises af en trigger (uforanderlighed), så indsæt en ny version/række i stedet, som skemaet foreskriver, og sammenlign. Navnet `reimport_event_id_seq` kontrolleres mod skemaet (`\ds private.*`); brug den sekvens, der findes.

- [ ] **Step 2: Kør testen og se den fejle**

Kommando som Task 1 Step 3 med `tests/sql/test-transfer-baseline.sql`. Expected: FAIL `could not open … transfer_baseline.sql`.

- [ ] **Step 3: Skriv `transfer_baseline.sql`**

```sql
-- Driftsbaseline (spec 2026-10-03 §4.3). Læse-kun. Indholdshash over de data, klassifikationen og
-- målfindingen hviler på, antal i de øvrige kanoniske tabeller, klausulsættet og skemaet.
-- Ingen tællinger af autorisationer, writer-profiler eller fortolkninger: dry-run og ingest
-- ændrer dem lovligt. Input: psql-variablen src. Output: daa.transfer_baseline.
WITH tab AS (
  SELECT 'assertion' AS n, encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(a)::text, E'\n' ORDER BY a.id),''),'UTF8'),'sha256'),'hex') AS h FROM public.assertion a
  UNION ALL SELECT 'fact', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(f)::text, E'\n' ORDER BY f.id),''),'UTF8'),'sha256'),'hex') FROM public.fact f
  UNION ALL SELECT 'person', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(p)::text, E'\n' ORDER BY p.id),''),'UTF8'),'sha256'),'hex') FROM public.person p
  UNION ALL SELECT 'identity', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(s)::text, E'\n' ORDER BY s.source_persona_id, s.version),''),'UTF8'),'sha256'),'hex') FROM private.source_persona_identity s
  UNION ALL SELECT 'placement', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(pl)::text, E'\n' ORDER BY pl.id, pl.version),''),'UTF8'),'sha256'),'hex') FROM private.source_persona_placement_current pl
  UNION ALL SELECT 'promotion_rule', encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(r)::text, E'\n' ORDER BY r.rule_key COLLATE "C", r.rule_version),''),'UTF8'),'sha256'),'hex') FROM private.interpretation_promotion_rule r
  UNION ALL SELECT 'counts', md5(concat_ws('|',
      (SELECT count(*) FROM public.conclusion), (SELECT count(*) FROM public.narrative),
      (SELECT count(*) FROM public.relation), (SELECT count(*) FROM public.family_member)))
), parents AS (
  SELECT sr.record_key, so.parent_observation_id AS parent, max(coalesce(so.clause_set_seq,1)) AS seq
    FROM private.source_observation so
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
   WHERE so.observation_kind = 'clause' AND sr.source_id = :src
   GROUP BY sr.record_key, so.parent_observation_id
), recs AS (
  SELECT sr.record_key, p.seq, coalesce(private.clause_set_sha256(p.parent, p.seq), 'none') AS h
    FROM private.source_record sr LEFT JOIN parents p ON p.record_key = sr.record_key
   WHERE sr.source_id = :src
), sch AS (
  SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' ||
         md5(pg_get_functiondef(p.oid)) AS t
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','private') AND p.prokind IN ('f','p')
  UNION ALL
  SELECT c.table_schema || '.' || c.table_name || '.' || c.column_name || ':' || c.data_type || ':' || c.is_nullable
    FROM information_schema.columns c WHERE c.table_schema IN ('public','private')
), b AS (
  SELECT
    encode(extensions.digest(convert_to((SELECT string_agg(n || '=' || h, E'\n' ORDER BY n COLLATE "C") FROM tab),'UTF8'),'sha256'),'hex') AS canonical_sha256,
    encode(extensions.digest(convert_to(coalesce((SELECT string_agg(record_key || '|' || coalesce(seq::text,'none') || '|' || h, E'\n' ORDER BY record_key COLLATE "C") FROM recs),''),'UTF8'),'sha256'),'hex') AS clause_set_sha256,
    (SELECT count(*) FROM private.interpretation WHERE source_id = :src) AS n_interpretations_src,
    encode(extensions.digest(convert_to((SELECT string_agg(t, E'\n' ORDER BY t COLLATE "C") FROM sch),'UTF8'),'sha256'),'hex') AS schema_sha256
)
SELECT set_config('daa.transfer_baseline', to_jsonb(b)::text, false) AS transfer_baseline FROM b;
```

Bemærk: `private.source_persona_placement_current` er et view over `placement.*` + seneste afgørelse; ordnes på `(id, version)`. Kolonnenavnet `version` i `source_persona_identity` kontrolleres mod skemaet.

- [ ] **Step 4: Skriv `transfer_restore_hash.sql`**

```sql
-- Restore-hash (spec §4.3 »ingen skrivning siden dumpet«; §6.1 trin 4b). Læse-kun.
-- Alle ordinære tabeller og sekvenser i private+public. Ingen PK-antagelse: rækker sorteres på
-- deres egen to_jsonb-tekst. Output: daa.restore_hash.
DO $rh$
DECLARE r record; h text; acc text := '';
BEGIN
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','p')
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT encode(extensions.digest(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"),''''),''UTF8''),''sha256''),''hex'') FROM (SELECT to_jsonb(x)::text AS t FROM %I.%I x) s',
                   r.nspname, r.relname) INTO h;
    acc := acc || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind = 'S'
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT last_value::text || '':'' || is_called::text FROM %I.%I', r.nspname, r.relname) INTO h;
    acc := acc || 'seq:' || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  PERFORM set_config('daa.restore_hash', encode(extensions.digest(convert_to(acc,'UTF8'),'sha256'),'hex'), false);
END $rh$;
SELECT current_setting('daa.restore_hash') AS restore_hash;
```

- [ ] **Step 5: Skriv `transfer_untouched_hash.sql`**

Samme som `transfer_restore_hash.sql`, men begge løkker springer kædens tabeller og deres ejede sekvenser over. Kopiér filen og tilføj eksklusionen i begge `WHERE`'er:

```sql
-- Uberørt-hash (spec §5 »Uberørt«). Som transfer_restore_hash.sql MINUS de tabeller overførslen
-- skriver i (writer, afgørelser, bindinger) og sekvenser ejet af dem. Listen er hardkodet her og
-- dermed bundet af GO-inventaret. Output: daa.untouched_hash.
DO $uh$
DECLARE r record; h text; acc text := '';
        excl text[] := ARRAY['private.reimport_writer_profile','private.reimport_authorization','private.reimport_batch',
                             'private.reimport_event','private.extraction_run','private.interpretation',
                             'private.interpretation_observation','private.clause_disposition',
                             'private.interpretation_promotion_batch','private.interpretation_promotion'];
BEGIN
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','p')
              AND (n.nspname || '.' || c.relname) <> ALL (excl)
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT encode(extensions.digest(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"),''''),''UTF8''),''sha256''),''hex'') FROM (SELECT to_jsonb(x)::text AS t FROM %I.%I x) s',
                   r.nspname, r.relname) INTO h;
    acc := acc || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind = 'S'
              AND NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_class t ON t.oid = d.refobjid
                               JOIN pg_namespace tn ON tn.oid = t.relnamespace
                              WHERE d.objid = c.oid AND d.deptype IN ('a','i')
                                AND (tn.nspname || '.' || t.relname) = ANY (excl))
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT last_value::text || '':'' || is_called::text FROM %I.%I', r.nspname, r.relname) INTO h;
    acc := acc || 'seq:' || r.nspname || '.' || r.relname || '=' || h || E'\n';
  END LOOP;
  PERFORM set_config('daa.untouched_hash', encode(extensions.digest(convert_to(acc,'UTF8'),'sha256'),'hex'), false);
END $uh$;
SELECT current_setting('daa.untouched_hash') AS untouched_hash;
```

- [ ] **Step 6: Skriv `transfer_restore_preconditions.sql`**

```sql
-- Restore-forudsætninger (spec §6.1 trin 2, review runde 2 N2). Læse-kun.
-- (1) Forældreløse rækker pr. enkeltkolonne-FK i private+public: en restore kan ikke genskabe en
--     FK over forældreløse rækker. Flerkolonne-FK'er tælles som antal (skal stå i rapporten).
-- (2) Katalogfingeraftryk: FK-, policy-, funktions- og sekvensdefinitioner — sammenlignes med
--     prods eget efter fortrydelsesøvelsen. Output: daa.restore_preconditions.
DO $pc$
DECLARE r record; n bigint; orphans jsonb := '{}'; multi int := 0; cat text;
BEGIN
  FOR r IN SELECT con.conname, cn.nspname AS sch, c.relname AS tab, a.attname AS col,
                  fn.nspname AS fsch, f.relname AS ftab, fa.attname AS fcol
             FROM pg_constraint con
             JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace cn ON cn.oid = c.relnamespace
             JOIN pg_class f ON f.oid = con.confrelid JOIN pg_namespace fn ON fn.oid = f.relnamespace
             JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = con.conkey[1]
             JOIN pg_attribute fa ON fa.attrelid = f.oid AND fa.attnum = con.confkey[1]
            WHERE con.contype = 'f' AND cn.nspname IN ('private','public') AND array_length(con.conkey,1) = 1
            ORDER BY cn.nspname COLLATE "C", con.conname COLLATE "C" LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I x WHERE x.%I IS NOT NULL AND NOT EXISTS (SELECT 1 FROM %I.%I y WHERE y.%I = x.%I)',
                   r.sch, r.tab, r.col, r.fsch, r.ftab, r.fcol, r.col) INTO n;
    IF n > 0 THEN orphans := orphans || jsonb_build_object(r.sch || '.' || r.conname, n); END IF;
  END LOOP;
  SELECT count(*) INTO multi FROM pg_constraint con JOIN pg_namespace cn ON cn.oid = con.connamespace
   WHERE con.contype = 'f' AND cn.nspname IN ('private','public') AND array_length(con.conkey,1) > 1;
  SELECT string_agg(t, E'\n' ORDER BY t COLLATE "C") INTO cat FROM (
    SELECT 'fk:' || conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid) AS t
      FROM pg_constraint WHERE contype = 'f' AND connamespace IN (SELECT oid FROM pg_namespace WHERE nspname IN ('private','public'))
    UNION ALL SELECT 'policy:' || schemaname || '.' || tablename || ':' || policyname || ':' || coalesce(qual,'') || ':' || coalesce(with_check,'')
      FROM pg_policies WHERE schemaname IN ('private','public')
    UNION ALL SELECT 'fn:' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '):' || md5(pg_get_functiondef(p.oid))
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('private','public') AND p.prokind IN ('f','p')
    UNION ALL SELECT 'seq:' || sequence_schema || '.' || sequence_name FROM information_schema.sequences WHERE sequence_schema IN ('private','public')
  ) s;
  PERFORM set_config('daa.restore_preconditions', jsonb_build_object(
    'orphans', orphans,
    'n_orphans_total', coalesce((SELECT sum(value::bigint) FROM jsonb_each_text(orphans)), 0),
    'n_multi_column_fks', multi,
    'catalog_sha256', encode(extensions.digest(convert_to(coalesce(cat,''),'UTF8'),'sha256'),'hex'))::text, false);
END $pc$;
SELECT current_setting('daa.restore_preconditions') AS restore_preconditions;
```

- [ ] **Step 7: Kør testen og se den bestå**

Expected: `OK: transfer baseline`.

- [ ] **Step 8: Mål på restoren (kun tal) og notér**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
P="env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD -u PGDATABASE psql -h /tmp -X -A -t -q -v ON_ERROR_STOP=1 -v src=1 -d daa2018f_20261001133125"
time $P -c "SET default_transaction_read_only=on" -f .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql | tail -1 | /usr/bin/python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['n_orphans_total'], d['n_multi_column_fks'], len(d['orphans']))"
```

Expected: tre tal; varigheden noteres. `n_orphans_total` > 0 i restoren kan være `db-verify`-residu (memory 2026-09-17) og skal i Task 6 måles på den rene restore af dumpet, ikke her.

- [ ] **Step 9: CI og commit**

Tilføj i `ci.yml` (job `evidence-promotion-db`) efter Task 1's linje:

```yaml
          psql -v ON_ERROR_STOP=1 -f tests/sql/test-transfer-baseline.sql
```

```bash
git add .claude/skills/daa-extract/scripts/transfer_baseline.sql .claude/skills/daa-extract/scripts/transfer_restore_hash.sql .claude/skills/daa-extract/scripts/transfer_untouched_hash.sql .claude/skills/daa-extract/scripts/transfer_restore_preconditions.sql tests/sql/test-transfer-baseline.sql .github/workflows/ci.yml
git commit -m "feat(147): driftsbaseline, restore-hash og restore-forudsætninger til overførslen"
```

---

### Task 4: Pakkebyggeren og tilstandsklassifikationen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_pack_export.sql`
- Create: `.claude/skills/daa-extract/scripts/transfer_pack.py`
- Create: `.claude/skills/daa-extract/scripts/test_transfer_pack.py`
- Create: `tests/fixtures/transfer-pack/` (`export.json`, `fingerprints.json`, `digests.json`, `baseline.json`, `classification.json`, `dump-receipt.json`)
- Modify: `.github/workflows/ci.yml` (job `python`)

**Interfaces:**
- Consumes: `daa.fingerprints` (Task 1), `daa.transfer_digests` (Task 2), `daa.transfer_baseline` (Task 3); kørslens `klassifikation.json` (`{"items":[{"interpretation_id","version","predicate","class","assertion_id"}],"counts":{…}}`).
- Produces (`transfer_pack_export.sql`): `daa.pack_export` = `{"decisions":[{"interpretation_key","restore_interpretation_id","v1_interpretation_id","status","evidence","decided_by"}], "key_by_v1_id": {"<v1-id>": "<key>"}}` — `decided_by` er rå uuid og forlader kun eksporten som hash.
- Produces (`transfer_pack.py`):
  - `build_pack(export, fingerprints, digests, baseline, classification, classification_sha256, receipt, *, manifest_content_sha256, ledger_sha256) -> tuple[list[dict], dict]` — (decisions-keyed, pack-manifest med `pack_sha256`).
  - `classify_state(digests: dict, pack_manifest: dict) -> str` ∈ `{"EMPTY","PROPOSED","DECIDED","COMPLETE","MIXED"}`.
  - `pack_sha256(manifest: dict) -> str`.
  - CLI: `build`, `state` (Task 5 tilføjer `decide-sql`, `bind-sql`).
  - Fejl: `PackError(ValueError)` med koderne `PACK_DUPLICATE_KEY`, `PACK_COUNT_MISMATCH`, `PACK_ACTOR_COUNT`, `PACK_FINGERPRINT_MISSING`, `PACK_CLASSIFICATION_UNMAPPED`.

- [ ] **Step 1: Skriv eksport-SQL'en**

`.claude/skills/daa-extract/scripts/transfer_pack_export.sql`:

```sql
-- Restorens afgørelser til pakken (spec §4.1). Læse-kun. Indeholder evidens med noter:
-- skriv output til en 0600-fil og læs det aldrig — kun tæl. Input: src. Output: daa.pack_export.
WITH cur AS (
  SELECT ic.* FROM private.interpretation_current ic WHERE ic.source_id = :src AND ic.status <> 'proposed'
), v1 AS (
  SELECT i.id, i.interpretation_key FROM private.interpretation i WHERE i.source_id = :src AND i.version = 1
)
SELECT set_config('daa.pack_export', jsonb_build_object(
  'decisions', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'interpretation_key', cur.interpretation_key, 'restore_interpretation_id', cur.id,
      'v1_interpretation_id', v1.id, 'status', cur.status, 'evidence', cur.decision_evidence,
      'decided_by', cur.decided_by) ORDER BY cur.interpretation_key)
    FROM cur JOIN v1 ON v1.interpretation_key = cur.interpretation_key), '[]'::jsonb),
  'key_by_v1_id', coalesce((SELECT jsonb_object_agg(id::text, interpretation_key::text) FROM v1), '{}'::jsonb)
)::text, false) AS pack_export;
```

- [ ] **Step 2: Skriv test-fixtures**

`tests/fixtures/transfer-pack/export.json` (tre afgørelser, fire nøgler; ingen ægte data):

```json
{"decisions": [
  {"interpretation_key": "k-1", "restore_interpretation_id": "r-1", "v1_interpretation_id": "v-1", "status": "accepted",
   "evidence": {"method": "human-sheet-kontrol-v1", "line": 5, "note": "", "rows_sha256": "a", "sheet_sha256": "b"}, "decided_by": "u-1"},
  {"interpretation_key": "k-2", "restore_interpretation_id": "r-2", "v1_interpretation_id": "v-2", "status": "unresolved",
   "evidence": {"method": "human-sheet-kontrol-v1", "line": 9, "note": "titel i navn", "rows_sha256": "a", "sheet_sha256": "b"}, "decided_by": "u-1"},
  {"interpretation_key": "k-3", "restore_interpretation_id": "r-3", "v1_interpretation_id": "v-3", "status": "accepted",
   "evidence": {"method": "machine-corroboration-v1", "assertion_id": 7, "classification_sha256": "c", "decision": "d", "sample_sha256": "e", "sheet_sha256": "b"}, "decided_by": "u-1"}],
 "key_by_v1_id": {"v-1": "k-1", "v-2": "k-2", "v-3": "k-3", "v-4": "k-4"}}
```

`fingerprints.json`: `{"k-1": "f1", "k-2": "f2", "k-3": "f3", "k-4": "f4"}`
`digests.json`: `{"n_interpretations": 4, "proposal_digest": "P", "n_decided": 3, "decided_by_method_status": {"human-sheet-kontrol-v1|accepted": 1, "human-sheet-kontrol-v1|unresolved": 1, "machine-corroboration-v1|accepted": 1}, "decision_digest": "D", "n_bindings": 2, "binding_digest": "B"}`
`baseline.json`: `{"canonical_sha256": "C", "clause_set_sha256": "S", "n_interpretations_src": 0, "schema_sha256": "H"}`
`classification.json`: `{"items": [{"interpretation_id": "v-1", "version": 1, "predicate": "person.death", "class": "MATCH", "assertion_id": 7}, {"interpretation_id": "v-2", "version": 1, "predicate": "person.name", "class": "REAL_DIFF", "assertion_id": null}, {"interpretation_id": "v-3", "version": 1, "predicate": "person.death", "class": "MATCH", "assertion_id": 7}], "counts": {}}`
`dump-receipt.json`: `{"dump_sha256": "DS", "state": "1|2|3", "kanonisk_md5": "KM"}`

- [ ] **Step 3: Skriv de fejlende tests**

`.claude/skills/daa-extract/scripts/test_transfer_pack.py`:

```python
import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import transfer_pack as tp  # noqa: E402

FX = Path(__file__).resolve().parents[4] / "tests" / "fixtures" / "transfer-pack"


def load(name):
    return json.loads((FX / name).read_text(encoding="utf-8"))


def build(**over):
    args = dict(export=load("export.json"), fingerprints=load("fingerprints.json"), digests=load("digests.json"),
                baseline=load("baseline.json"), classification=load("classification.json"),
                classification_sha256="ded0", receipt=load("dump-receipt.json"),
                manifest_content_sha256="80f3", ledger_sha256="e620")
    args.update(over)
    return tp.build_pack(**args)


def test_build_counts_and_fields():
    decisions, manifest = build()
    assert [d["interpretation_key"] for d in decisions] == ["k-1", "k-2", "k-3"]
    assert set(decisions[0]) == {"interpretation_key", "restore_interpretation_id", "expected_version", "status",
                                 "decision_fingerprint", "evidence"}
    assert decisions[0]["expected_version"] == 1
    assert decisions[1]["decision_fingerprint"] == "f2"
    assert manifest["counts_by_method_status"] == {"human-sheet-kontrol-v1|accepted": 1,
                                                   "human-sheet-kontrol-v1|unresolved": 1,
                                                   "machine-corroboration-v1|accepted": 1}
    assert manifest["n_accepted"] == 2 and manifest["accepted_keys"] == ["k-1", "k-3"]
    assert manifest["keyed_classification"] == {"k-1": ["MATCH", 7], "k-2": ["REAL_DIFF", None], "k-3": ["MATCH", 7]}
    assert len(manifest["actor_sha256"]) == 64


def test_pack_sha_is_canonical_and_excludes_itself():
    _, m = build()
    again = dict(m)
    assert tp.pack_sha256(again) == m["pack_sha256"]
    shuffled = dict(reversed(list(m.items())))
    assert tp.pack_sha256(shuffled) == m["pack_sha256"]
    changed = dict(m, ledger_sha256="other")
    assert tp.pack_sha256(changed) != m["pack_sha256"]


def test_duplicate_key_is_error():
    ex = load("export.json")
    ex["decisions"].append(copy.deepcopy(ex["decisions"][0]))
    with pytest.raises(tp.PackError, match="PACK_DUPLICATE_KEY"):
        build(export=ex)


def test_decision_without_fingerprint_is_error():
    fp = load("fingerprints.json")
    del fp["k-3"]
    with pytest.raises(tp.PackError, match="PACK_FINGERPRINT_MISSING"):
        build(fingerprints=fp)


def test_counts_must_match_digests():
    dg = load("digests.json")
    dg["n_decided"] = 4
    with pytest.raises(tp.PackError, match="PACK_COUNT_MISMATCH"):
        build(digests=dg)


def test_exactly_one_actor():
    ex = load("export.json")
    ex["decisions"][2]["decided_by"] = "u-2"
    with pytest.raises(tp.PackError, match="PACK_ACTOR_COUNT"):
        build(export=ex)


def test_classification_must_map_to_keys():
    cl = load("classification.json")
    cl["items"].append({"interpretation_id": "v-9", "version": 1, "predicate": "x", "class": "MATCH", "assertion_id": 1})
    with pytest.raises(tp.PackError, match="PACK_CLASSIFICATION_UNMAPPED"):
        build(classification=cl)


def test_state_classifier_five_states():
    _, m = build()
    full = load("digests.json")
    empty = {"n_interpretations": 0, "proposal_digest": tp.EMPTY_SHA, "n_decided": 0,
             "decided_by_method_status": {}, "decision_digest": tp.EMPTY_SHA, "n_bindings": 0,
             "binding_digest": tp.EMPTY_SHA}
    proposed = dict(full, n_decided=0, decided_by_method_status={}, decision_digest="ANY", n_bindings=0,
                    binding_digest=tp.EMPTY_SHA)
    decided = dict(full, n_bindings=0, binding_digest=tp.EMPTY_SHA)
    assert tp.classify_state(empty, m) == "EMPTY"
    assert tp.classify_state(proposed, m) == "PROPOSED"
    assert tp.classify_state(decided, m) == "DECIDED"
    assert tp.classify_state(full, m) == "COMPLETE"
    assert tp.classify_state(dict(full, proposal_digest="X"), m) == "MIXED"
    assert tp.classify_state(dict(decided, decision_digest="X"), m) == "MIXED"
    assert tp.classify_state(dict(empty, n_bindings=1), m) == "MIXED"


def test_cli_prints_no_notes_or_values(tmp_path):
    out = tmp_path / "pack"
    out.mkdir(mode=0o700)
    cmd = [sys.executable, str(Path(tp.__file__)), "build"]
    for flag, name in (("--export", "export.json"), ("--fingerprints", "fingerprints.json"),
                       ("--digests", "digests.json"), ("--baseline", "baseline.json"),
                       ("--classification", "classification.json"), ("--dump-receipt", "dump-receipt.json")):
        cmd += [flag, str(FX / name)]
    cmd += ["--manifest-content-sha256", "80f3", "--ledger-sha256", "e620", "--out-dir", str(out)]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    assert "titel i navn" not in res.stdout + res.stderr
    assert "PACK_OK" in res.stdout
    for f in ("decisions-keyed.json", "pack-manifest.json"):
        assert (out / f).stat().st_mode & 0o777 == 0o600
```

- [ ] **Step 4: Kør testene og se dem fejle**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_transfer_pack.py -q
```

Expected: FAIL `ModuleNotFoundError: No module named 'transfer_pack'`.

- [ ] **Step 5: Skriv `transfer_pack.py`**

```python
#!/usr/bin/env python3
"""Overførselspakken for 2018-20 (#147; spec 2026-10-03 §4-§6).

Databasefri: SQL-filerne skriver JSON (daa.pack_export, daa.fingerprints, daa.transfer_digests,
daa.transfer_baseline); denne fil bygger og validerer pakken, klassificerer tilstanden og genererer
skrive-SQL'en for 07/08. Printer kun tal og hashes — aldrig noter, værdier eller aktør-id.
Alle skrevne filer er 0600.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from pathlib import Path

EMPTY_SHA = hashlib.sha256(b"").hexdigest()
PACK_VERSION = "transfer-pack-v1"


class PackError(ValueError):
    """Fail-closed: intet skrives."""


def canonical(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def pack_sha256(manifest: dict) -> str:
    return sha256_text(canonical({k: v for k, v in manifest.items() if k != "pack_sha256"}))


def _write_private(path: Path, text: str) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def build_pack(*, export: dict, fingerprints: dict, digests: dict, baseline: dict, classification: dict,
               classification_sha256: str, receipt: dict, manifest_content_sha256: str,
               ledger_sha256: str) -> tuple[list[dict], dict]:
    rows = export["decisions"]
    keys = [r["interpretation_key"] for r in rows]
    if len(keys) != len(set(keys)):
        raise PackError("PACK_DUPLICATE_KEY")
    actors = {r["decided_by"] for r in rows}
    if len(actors) != 1:
        raise PackError(f"PACK_ACTOR_COUNT {len(actors)}")
    missing = [k for k in keys if k not in fingerprints]
    if missing:
        raise PackError(f"PACK_FINGERPRINT_MISSING {len(missing)}")
    by_ms = Counter(f"{r['evidence'].get('method', '')}|{r['status']}" for r in rows)
    if len(rows) != digests["n_decided"] or dict(by_ms) != digests["decided_by_method_status"]:
        raise PackError("PACK_COUNT_MISMATCH")

    key_by_v1 = export["key_by_v1_id"]
    keyed_cls = {}
    for item in classification["items"]:
        key = key_by_v1.get(item["interpretation_id"])
        if key is None:
            raise PackError("PACK_CLASSIFICATION_UNMAPPED")
        keyed_cls[key] = [item["class"], item["assertion_id"]]

    decisions = [{"interpretation_key": r["interpretation_key"],
                  "restore_interpretation_id": r["restore_interpretation_id"],
                  "expected_version": 1, "status": r["status"],
                  "decision_fingerprint": fingerprints[r["interpretation_key"]],
                  "evidence": r["evidence"]} for r in sorted(rows, key=lambda r: r["interpretation_key"])]
    decisions_text = canonical(decisions)
    accepted = sorted(d["interpretation_key"] for d in decisions if d["status"] == "accepted")
    manifest = {
        "pack_version": PACK_VERSION,
        "manifest_content_sha256": manifest_content_sha256,
        "ledger_sha256": ledger_sha256,
        "dump_sha256": receipt["dump_sha256"],
        "dump_state": receipt["state"],
        "dump_kanonisk_md5": receipt["kanonisk_md5"],
        "baseline": baseline,
        "classification_sha256": classification_sha256,
        "keyed_classification": dict(sorted(keyed_cls.items())),
        "actor_sha256": sha256_text(next(iter(actors))),
        "counts_by_method_status": dict(sorted(by_ms.items())),
        "n_decisions": len(decisions),
        "n_accepted": len(accepted),
        "accepted_keys": accepted,
        "digests": digests,
        "decisions_keyed_sha256": sha256_text(decisions_text),
    }
    manifest["pack_sha256"] = pack_sha256(manifest)
    return decisions, manifest


def classify_state(digests: dict, pack: dict) -> str:
    """Spec §5: EMPTY / PROPOSED / DECIDED / COMPLETE, ellers MIXED."""
    want = pack["digests"]
    nothing = (digests["n_interpretations"] == 0 and digests["n_decided"] == 0 and digests["n_bindings"] == 0)
    if nothing:
        return "EMPTY"
    proposals = (digests["n_interpretations"] == want["n_interpretations"]
                 and digests["proposal_digest"] == want["proposal_digest"])
    if not proposals:
        return "MIXED"
    no_bindings = digests["n_bindings"] == 0 and digests["binding_digest"] == EMPTY_SHA
    if digests["n_decided"] == 0 and no_bindings:
        return "PROPOSED"
    decisions = (digests["n_decided"] == want["n_decided"]
                 and digests["decided_by_method_status"] == want["decided_by_method_status"]
                 and digests["decision_digest"] == want["decision_digest"])
    if not decisions:
        return "MIXED"
    if no_bindings:
        return "DECIDED"
    if digests["n_bindings"] == want["n_bindings"] and digests["binding_digest"] == want["binding_digest"]:
        return "COMPLETE"
    return "MIXED"


def _load(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    for flag in ("--export", "--fingerprints", "--digests", "--baseline", "--classification", "--dump-receipt",
                 "--manifest-content-sha256", "--ledger-sha256", "--out-dir"):
        b.add_argument(flag, required=True)
    s = sub.add_parser("state")
    s.add_argument("--digests", required=True)
    s.add_argument("--pack-manifest", required=True)
    args = ap.parse_args(argv)
    try:
        if args.cmd == "build":
            cls_path = Path(args.classification)
            decisions, manifest = build_pack(
                export=_load(args.export), fingerprints=_load(args.fingerprints), digests=_load(args.digests),
                baseline=_load(args.baseline), classification=_load(args.classification),
                classification_sha256=hashlib.sha256(cls_path.read_bytes()).hexdigest(),
                receipt=_load(args.dump_receipt), manifest_content_sha256=args.manifest_content_sha256,
                ledger_sha256=args.ledger_sha256)
            out = Path(args.out_dir)
            _write_private(out / "decisions-keyed.json", canonical(decisions) + "\n")
            _write_private(out / "pack-manifest.json", canonical(manifest) + "\n")
            print(f"PACK_OK afgørelser={manifest['n_decisions']} accepterede={manifest['n_accepted']} "
                  f"klassificerede={len(manifest['keyed_classification'])} pack_sha256={manifest['pack_sha256']}")
        else:
            print(classify_state(_load(args.digests), _load(args.pack_manifest)))
    except PackError as exc:
        print(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Bemærk: `decided_by_method_status` i pakken sammenlignes med digestens nøgle `"<metode>|<status>"` (Task 2). Pakken bærer aldrig rå `decided_by`, kun `actor_sha256`.

- [ ] **Step 6: Kør testene og se dem bestå**

Expected: `9 passed`.

- [ ] **Step 7: CI og commit**

I `ci.yml`, job `python`, tilføj `test_transfer_pack.py` på pytest-linjen ved siden af de øvrige `.claude/skills/daa-extract/scripts/test_*.py`. Kontroller i jobbet, at fixture-stien `tests/fixtures/transfer-pack/` er checket ud (den er i repoet).

```bash
git add .claude/skills/daa-extract/scripts/transfer_pack_export.sql .claude/skills/daa-extract/scripts/transfer_pack.py .claude/skills/daa-extract/scripts/test_transfer_pack.py tests/fixtures/transfer-pack .github/workflows/ci.yml
git commit -m "feat(147): pakkebygger og tilstandsklassifikation for overførslen"
```

---

### Task 5: Skrive-SQL'en for `07` og `08`

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_promotion_targets_scoped.sql`
- Modify: `.claude/skills/daa-extract/scripts/transfer_pack.py` (tilføj `decide_sql`, `bind_sql`, CLI `decide-sql`, `bind-sql`)
- Modify: `.claude/skills/daa-extract/scripts/test_transfer_pack.py`
- Create: `tests/sql/test-transfer-decide-bind.sql`
- Create: `tests/fixtures/transfer-pack/sql/` (pakke for SQL-fixturen, se Step 5)
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `build_pack`, `classify_state` (Task 4); fingeraftryk (Task 1), digests (Task 2), klausulsæt i baselinen (Task 3); den delte `interpretation_control_classification.sql` og `interpretation_promotion_targets.sql` **uændret**.
- Produces: `decide_sql(decisions: list[dict], manifest: dict) -> str`, `bind_sql(manifest: dict) -> str`. Begge forventer psql-variablerne `src` og `actor` og køres fra repo-roden. Fejlkoder i SQL'en: `TRANSFER_STATE_NOT_PROPOSED`, `TRANSFER_STATE_NOT_DECIDED`, `CLAUSE_SET_DRIFT`, `MACHINE_PREMISE_DRIFT`, `DECISION_FINGERPRINT_MISMATCH`, `DECISION_KEY_UNRESOLVED`, `DECISION_DIGEST_MISMATCH`, `BIND_SCOPE_DRIFT`, `BIND_NOT_ELIGIBLE`, `BINDING_DIGEST_MISMATCH`.

- [ ] **Step 1: Skriv den scopede målfinding**

`.claude/skills/daa-extract/scripts/interpretation_promotion_targets_scoped.sql`:

```sql
-- Målfindingen afgrænset til overførselspakkens accepterede nøgler (spec §6.2, review runde 1 m8).
-- Den delte interpretation_promotion_targets.sql er uændret; denne fil filtrerer dens resultat.
-- Obligatorisk input: daa.transfer_scope = JSON-array af interpretation_key. Uden input: STOP.
-- Output: daa.targets_scoped = {"items":[…], "singleton_items":[…], "out_of_scope": n}.
DO $s$ BEGIN
  IF coalesce(current_setting('daa.transfer_scope', true), '') = '' THEN
    RAISE EXCEPTION 'BIND_SCOPE_REQUIRED';
  END IF;
END $s$;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
WITH t AS (SELECT current_setting('daa.targets_result')::jsonb AS j),
scope AS (SELECT jsonb_array_elements_text(current_setting('daa.transfer_scope')::jsonb) AS k),
tagged AS (
  SELECT g.grp, x.item, i.interpretation_key::text AS k
    FROM t CROSS JOIN LATERAL (VALUES ('items'), ('singleton_items')) g(grp)
    CROSS JOIN LATERAL jsonb_array_elements(t.j -> g.grp) x(item)
    JOIN private.interpretation i ON i.id = (x.item->>'interpretation_id')::uuid
)
SELECT set_config('daa.targets_scoped', jsonb_build_object(
  'items', coalesce((SELECT jsonb_agg(item ORDER BY k) FROM tagged WHERE grp = 'items' AND k IN (SELECT k FROM scope)), '[]'::jsonb),
  'singleton_items', coalesce((SELECT jsonb_agg(item ORDER BY k) FROM tagged WHERE grp = 'singleton_items' AND k IN (SELECT k FROM scope)), '[]'::jsonb),
  'out_of_scope', (SELECT count(*) FROM tagged WHERE k NOT IN (SELECT k FROM scope)))::text, false) AS targets_scoped;
```

- [ ] **Step 2: Skriv de fejlende pytest-tests for generatorerne** (tilføj i `test_transfer_pack.py`)

```python
def test_decide_sql_shape():
    decisions, manifest = build()
    sql = tp.decide_sql(decisions, manifest)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;\nSELECT set_config('daa.src', :'src', true);")
    assert ":src" not in sql.replace(":'src'", "")
    assert sql.rstrip().endswith("COMMIT;")
    for code in ("TRANSFER_STATE_NOT_PROPOSED", "CLAUSE_SET_DRIFT", "MACHINE_PREMISE_DRIFT",
                 "DECISION_FINGERPRINT_MISMATCH", "DECISION_KEY_UNRESOLVED", "DECISION_DIGEST_MISMATCH"):
        assert code in sql
    assert sql.index("SET LOCAL ROLE authenticated") < sql.index("red_decide_interpretation")
    assert sql.index("red_decide_interpretation") < sql.index("RESET ROLE")
    assert sql.index("RESET ROLE") < sql.rindex("interpretation_transfer_digests.sql")
    assert manifest["pack_sha256"] in sql


def test_bind_sql_shape():
    _, manifest = build()
    sql = tp.bind_sql(manifest)
    for code in ("TRANSFER_STATE_NOT_DECIDED", "BIND_SCOPE_DRIFT", "BIND_NOT_ELIGIBLE", "BINDING_DIGEST_MISMATCH"):
        assert code in sql
    assert "interpretation_promotion_targets_scoped.sql" in sql
    assert '["k-1","k-3"]' in sql
```

- [ ] **Step 3: Kør og se dem fejle**

Expected: FAIL `AttributeError: module 'transfer_pack' has no attribute 'decide_sql'`.

- [ ] **Step 4: Tilføj generatorerne i `transfer_pack.py`** (før `_load`)

```python
SCRIPTS = ".claude/skills/daa-extract/scripts"


def _lit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def _state_guard(want: dict, state: str, code: str) -> str:
    """SQL-vagt: kør digests og kræv netop indgangstilstanden (spec §5)."""
    w = want["digests"]
    cond = {"PROPOSED": (f"(d->>'n_interpretations')::int = {w['n_interpretations']} "
                         f"AND d->>'proposal_digest' = {_lit(w['proposal_digest'])} "
                         "AND (d->>'n_decided')::int = 0 AND (d->>'n_bindings')::int = 0"),
            "DECIDED": (f"(d->>'n_interpretations')::int = {w['n_interpretations']} "
                        f"AND d->>'proposal_digest' = {_lit(w['proposal_digest'])} "
                        f"AND d->>'decision_digest' = {_lit(w['decision_digest'])} "
                        "AND (d->>'n_bindings')::int = 0")}[state]
    return (f"\\i {SCRIPTS}/interpretation_transfer_digests.sql\n"
            "DO $g$ DECLARE d jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN "
            f"IF NOT ({cond}) THEN RAISE EXCEPTION '{code}'; END IF; END $g$;")


def decide_sql(decisions: list[dict], manifest: dict) -> str:
    """07: én transaktion. Læsning som ejerrolle; kun RPC-kaldene som authenticated (review 2, N4)."""
    pack = manifest["pack_sha256"]
    plan = canonical([{"k": d["interpretation_key"], "s": d["status"], "fp": d["decision_fingerprint"],
                       "e": d["evidence"]} for d in decisions])
    keyed = canonical(manifest["keyed_classification"])
    base = manifest["baseline"]
    return "\n".join([
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        # psql indsætter ikke :src i $-quotede DO-blokke; kilden lægges derfor i en GUC.
        "SELECT set_config('daa.src', :'src', true);",
        _state_guard(manifest, "PROPOSED", "TRANSFER_STATE_NOT_PROPOSED"),
        # (1) Klausulsættet (spec §4.2).
        f"\\i {SCRIPTS}/transfer_baseline.sql",
        "DO $c$ BEGIN IF current_setting('daa.transfer_baseline')::jsonb->>'clause_set_sha256' <> "
        f"{_lit(base['clause_set_sha256'])} THEN RAISE EXCEPTION 'CLAUSE_SET_DRIFT'; END IF; END $c$;",
        # (2) Præmissen: nøglet klassifikation i tilstand PROPOSED = pakkens (spec §4.3).
        f"\\i {SCRIPTS}/interpretation_control_classification.sql",
        "DO $m$ DECLARE r jsonb := current_setting('daa.control_result')::jsonb; f jsonb; "
        f"want jsonb := {_lit(keyed)}::jsonb; BEGIN "
        "SELECT coalesce(jsonb_object_agg(i.interpretation_key::text, jsonb_build_array(x->>'class', "
        "(x->>'assertion_id')::bigint)), '{}'::jsonb) INTO f FROM jsonb_array_elements(r->'items') x "
        "JOIN private.interpretation i ON i.id = (x->>'interpretation_id')::uuid; "
        "IF f IS DISTINCT FROM want THEN RAISE EXCEPTION 'MACHINE_PREMISE_DRIFT'; END IF; END $m$;",
        # (3) Fingeraftryk og id-opslag; planen lægges i en GUC, som authenticated kan læse.
        f"\\i {SCRIPTS}/interpretation_decision_fingerprint.sql",
        "DO $p$ DECLARE fps jsonb := current_setting('daa.fingerprints')::jsonb; "
        f"plan jsonb := {_lit(plan)}::jsonb; out jsonb; n int; BEGIN "
        "IF EXISTS (SELECT 1 FROM jsonb_array_elements(plan) p WHERE fps->>(p->>'k') IS DISTINCT FROM p->>'fp') "
        "THEN RAISE EXCEPTION 'DECISION_FINGERPRINT_MISMATCH'; END IF; "
        "SELECT count(*), jsonb_agg(jsonb_build_object('id', ic.id, 's', p->>'s', 'e', "
        f"(p->'e') || jsonb_build_object('pack_sha256', {_lit(pack)}))) INTO n, out "
        "FROM jsonb_array_elements(plan) p JOIN private.interpretation_current ic "
        "ON ic.interpretation_key = (p->>'k')::uuid AND ic.version = 1 AND ic.status = 'proposed' "
        "AND ic.source_id = current_setting('daa.src')::bigint; "
        "IF n <> jsonb_array_length(plan) THEN RAISE EXCEPTION 'DECISION_KEY_UNRESOLVED % af %', "
        "jsonb_array_length(plan) - n, jsonb_array_length(plan); END IF; "
        "PERFORM set_config('daa.decide_plan', out::text, true); END $p$;",
        # (4) Skrivningen.
        "SET LOCAL ROLE authenticated;",
        "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
        "DO $w$ DECLARE n int; BEGIN "
        "SELECT count(red_decide_interpretation((x->>'id')::uuid, 1, x->>'s', x->'e')) INTO n "
        "FROM jsonb_array_elements(current_setting('daa.decide_plan')::jsonb) x; "
        f"IF n <> {manifest['n_decisions']} THEN RAISE EXCEPTION 'DECISION_COUNT %', n; END IF; END $w$;",
        "RESET ROLE;",
        # (5) Resultatet = pakkens.
        f"\\i {SCRIPTS}/interpretation_transfer_digests.sql",
        "DO $d$ DECLARE d jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN "
        f"IF d->>'decision_digest' <> {_lit(manifest['digests']['decision_digest'])} "
        f"OR (d->>'n_decided')::int <> {manifest['n_decisions']} "
        "THEN RAISE EXCEPTION 'DECISION_DIGEST_MISMATCH'; END IF; END $d$;",
        "COMMIT;",
    ]) + "\n"


def bind_sql(manifest: dict) -> str:
    """08: én transaktion; pakkescope obligatorisk; preview og batch i samme transaktion."""
    scope = canonical(manifest["accepted_keys"])
    n_bind = manifest["digests"]["n_bindings"]
    return "\n".join([
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "SELECT set_config('daa.src', :'src', true);",
        _state_guard(manifest, "DECIDED", "TRANSFER_STATE_NOT_DECIDED"),
        f"SELECT set_config('daa.transfer_scope', {_lit(scope)}, true);",
        # Aktuelle accepterede for kilden = pakkens accepterede nøgler.
        "DO $s$ DECLARE f jsonb; BEGIN "
        "SELECT coalesce(jsonb_agg(interpretation_key::text ORDER BY interpretation_key::text COLLATE \"C\"), '[]') "
        "INTO f FROM private.interpretation_current WHERE source_id = current_setting('daa.src')::bigint AND status = 'accepted'; "
        "IF f IS DISTINCT FROM current_setting('daa.transfer_scope')::jsonb THEN RAISE EXCEPTION 'BIND_SCOPE_DRIFT'; END IF; END $s$;",
        f"\\i {SCRIPTS}/interpretation_promotion_targets_scoped.sql",
        "DO $n$ DECLARE t jsonb := current_setting('daa.targets_scoped')::jsonb; BEGIN "
        f"IF jsonb_array_length(t->'items') <> {n_bind} OR jsonb_array_length(t->'singleton_items') <> 0 "
        "OR (t->>'out_of_scope')::int <> 0 THEN RAISE EXCEPTION 'BIND_SCOPE_DRIFT items=%', "
        "jsonb_array_length(t->'items'); END IF; END $n$;",
        "SET LOCAL ROLE authenticated;",
        "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
        "DO $b$ DECLARE items jsonb := current_setting('daa.targets_scoped')::jsonb->'items'; "
        "p jsonb := red_preview_interpretation_promotions(items); BEGIN "
        "IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) "
        "THEN RAISE EXCEPTION 'BIND_NOT_ELIGIBLE'; END IF; "
        "PERFORM red_promote_interpretations_batch(items, p->>'preview_hash'); END $b$;",
        "RESET ROLE;",
        f"\\i {SCRIPTS}/interpretation_transfer_digests.sql",
        "DO $d$ DECLARE d jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN "
        f"IF d->>'binding_digest' <> {_lit(manifest['digests']['binding_digest'])} "
        f"OR (d->>'n_bindings')::int <> {n_bind} THEN RAISE EXCEPTION 'BINDING_DIGEST_MISMATCH'; END IF; END $d$;",
        "COMMIT;",
    ]) + "\n"
```

og i `main`: tilføj underkommandoerne

```python
    for name in ("decide-sql", "bind-sql"):
        g = sub.add_parser(name)
        g.add_argument("--pack-dir", required=True)
        g.add_argument("--out", required=True)
```

samt i `try`-blokken:

```python
        elif args.cmd in ("decide-sql", "bind-sql"):
            pdir = Path(args.pack_dir)
            manifest = _load(pdir / "pack-manifest.json")
            if pack_sha256(manifest) != manifest["pack_sha256"]:
                raise PackError("PACK_SHA_MISMATCH")
            decisions = _load(pdir / "decisions-keyed.json")
            if sha256_text(canonical(decisions)) != manifest["decisions_keyed_sha256"]:
                raise PackError("PACK_DECISIONS_SHA_MISMATCH")
            sql = decide_sql(decisions, manifest) if args.cmd == "decide-sql" else bind_sql(manifest)
            _write_private(Path(args.out), sql)
            print(f"{args.cmd.upper().replace('-', '_')}_OK pack_sha256={manifest['pack_sha256']}")
```

(`state`-grenen flyttes til `elif args.cmd == "state":`.) Bemærk: `red_promote_interpretations_batch`s returværdi ignoreres som i 4.5-planen; resultatet efterprøves af `binding_digest`.

- [ ] **Step 5: Kør pytest og se dem bestå**

Expected: `11 passed`.

- [ ] **Step 6: Skriv SQL-integrationstesten for den genererede SQL**

Testen bruger fixturen fra Task 1 (kilde `-4700`) som »prod« og en pakke bygget af den samme fixture efter afgørelse og binding i kilde `-4701` som »restore«. Fordi pakken afhænger af fixturens digests, genereres den i CI-steppet:

`tests/sql/test-transfer-decide-bind.sql`:

```sql
\set ON_ERROR_STOP on
-- 07/08's genererede SQL mod fixturen (plan A Task 5). Køres af CI-steppet efter, at
-- tests/sql/transfer-decide-bind.sh har bygget pakken og genereret /tmp/transfer-*.sql.
-- Del 1 (»restore«): kilde -4701 afgøres og bindes direkte; digests eksporteres.
-- Del 2 (»prod«): kilde -4700 er urørt; den genererede 07 og 08 køres og skal give pakkens digests.
\echo 'se tests/sql/transfer-decide-bind.sh'
```

og `tests/sql/transfer-decide-bind.sh` (eksekverbar, kaldes af CI og lokalt med `PGDATABASE` sat):

```zsh
#!/bin/zsh -f
# Plan A Task 5: byg en pakke af fixturen og kør 07/08's genererede SQL. Kræver en base med
# CI-opskriften. Én transaktion pr. trin; fixturen committes i en engangsbase.
emulate -R zsh; set -euo pipefail
cd "${0:A:h}/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
psql -X -q -v ON_ERROR_STOP=1 -c "BEGIN" -f tests/sql/transfer-fixture.sql -c "COMMIT"
# »Restore«: afgør og bind kilde -4701 som kontrolmodellen ville (k1 MATCH accepteret maskinelt, k2 REAL_DIFF afvist af menneske).
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT red_decide_interpretation('a4701000-0000-4000-8000-000000000301',1,'accepted','{"method":"machine-corroboration-v1","assertion_id":-4711}');
SELECT red_decide_interpretation('a4701000-0000-4000-8000-000000000302',1,'rejected','{"method":"human-sheet-kontrol-v1","line":1,"note":""}');
RESET ROLE;
COMMIT;
SQL
# Klassifikationen for pakken: tages i »restore« FØR afgørelserne ville være umuligt her, så den
# tages fra den urørte kilde -4700 (samme indhold) og mappes via kilde -4701's v1-id'er.
for f in interpretation_control_classification; do
  psql -X -A -t -q -v ON_ERROR_STOP=1 -c "BEGIN READ ONLY" -f .claude/skills/daa-extract/scripts/$f.sql -c "ROLLBACK" | tail -1 > "$T/cls-raw.json"
done
python3 - "$T" <<'PY'
import json,sys
t=sys.argv[1]; r=json.load(open(f"{t}/cls-raw.json"))
# kun kilde -4700's forslag (id-præfiks a4700000-), id'erne oversættes til -4701's
items=[dict(i, interpretation_id=i["interpretation_id"].replace("a4700000-","a4701000-")) for i in r["items"] if i["interpretation_id"].startswith("a4700000-")]
json.dump({"items":items,"counts":{}},open(f"{t}/cls.json","w"))
PY
# Binding i »restore« med den scopede målfinding (scope = accepterede i -4701).
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
SELECT set_config('daa.transfer_scope','["b4700000-0000-4000-8000-000000000001"]',true);
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets_scoped.sql
SELECT set_config('request.jwt.claim.sub','a4700000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $b$ DECLARE items jsonb := current_setting('daa.targets_scoped')::jsonb->'items'; p jsonb := red_preview_interpretation_promotions(items);
BEGIN PERFORM red_promote_interpretations_batch(items, p->>'preview_hash'); END $b$;
RESET ROLE;
COMMIT;
SQL
for f in transfer_pack_export interpretation_decision_fingerprint interpretation_transfer_digests transfer_baseline; do
  psql -X -A -t -q -v ON_ERROR_STOP=1 -v src=-4701 -c "BEGIN READ ONLY" -f .claude/skills/daa-extract/scripts/$f.sql -c "ROLLBACK" | tail -1 > "$T/$f.json"
done
print -r -- '{"dump_sha256":"fixture","state":"fixture","kanonisk_md5":"fixture"}' > "$T/receipt.json"
mkdir -m 700 "$T/pack"
python3 .claude/skills/daa-extract/scripts/transfer_pack.py build --export "$T/transfer_pack_export.json" \
  --fingerprints "$T/interpretation_decision_fingerprint.json" --digests "$T/interpretation_transfer_digests.json" \
  --baseline "$T/transfer_baseline.json" --classification "$T/cls.json" --dump-receipt "$T/receipt.json" \
  --manifest-content-sha256 fixture --ledger-sha256 fixture --out-dir "$T/pack"
python3 .claude/skills/daa-extract/scripts/transfer_pack.py decide-sql --pack-dir "$T/pack" --out "$T/07.sql"
python3 .claude/skills/daa-extract/scripts/transfer_pack.py bind-sql --pack-dir "$T/pack" --out "$T/08.sql"
# »Prod«: kilde -4700. Bind-scope og kilde-filter bruger src=-4700.
A="a4700000-0000-4000-8000-000000000001"
psql -X -q -v ON_ERROR_STOP=1 -v src=-4700 -v actor=$A -f "$T/07.sql"
# Review Focus 3: 07 igen ⇒ tilstandsvagten stopper (scriptet melder already_applied ud fra state).
if psql -X -q -v ON_ERROR_STOP=1 -v src=-4700 -v actor=$A -f "$T/07.sql" 2>"$T/e"; then print -u2 "FEJL: 07 kørte to gange"; exit 1; fi
grep -q TRANSFER_STATE_NOT_PROPOSED "$T/e"
psql -X -q -v ON_ERROR_STOP=1 -v src=-4700 -v actor=$A -f "$T/08.sql"
for f in interpretation_transfer_digests; do
  psql -X -A -t -q -v ON_ERROR_STOP=1 -v src=-4700 -c "BEGIN READ ONLY" -f .claude/skills/daa-extract/scripts/$f.sql -c "ROLLBACK" | tail -1 > "$T/prod-digests.json"
done
[[ "$(python3 .claude/skills/daa-extract/scripts/transfer_pack.py state --digests "$T/prod-digests.json" --pack-manifest "$T/pack/pack-manifest.json")" == COMPLETE ]]
print -- "OK: transfer decide/bind"
```

Bemærk: Fixturen deler `interpretation_key` mellem de to kilder; scope-checket i `bind_sql` filtrerer på `source_id = :src`, så kun »prod«-kildens accepterede tæller. Negative tilfælde (`MACHINE_PREMISE_DRIFT` ved ændret assertion, `DECISION_FINGERPRINT_MISMATCH` ved ændret klausul, `DECISION_KEY_UNRESOLVED` ved en ekstra afgjort version, `BIND_SCOPE_DRIFT` ved en accepteret uden for pakken) tilføjes i scriptet efter `07.sql` er genereret: hver i en engangskopi (`createdb -T`) af basen, med én ændring, og forventet fejlkode i stderr:

```zsh
neg() { # neg <kode> <sql-ændring> <trin-fil>
  local db="${PGDATABASE}_neg_$1"; dropdb --if-exists "$db"; createdb -T "$PGDATABASE" "$db"
  PGDATABASE="$db" psql -X -q -v ON_ERROR_STOP=1 -c "$2"
  if PGDATABASE="$db" psql -X -q -v ON_ERROR_STOP=1 -v src=-4700 -v actor=$A -f "$3" 2>"$T/neg"; then print -u2 "FEJL: $1 slap igennem"; exit 1; fi
  grep -q "$1" "$T/neg" || { print -u2 "FEJL: $1 forventet"; exit 1; }
  dropdb "$db"
}
```

Kaldene placeres FØR `07.sql` køres i »prod« (basen er da i tilstand `PROPOSED` for kilde `-4700`):

```zsh
neg MACHINE_PREMISE_DRIFT "UPDATE assertion SET date_raw='1851' WHERE id=-4711" "$T/07.sql"
neg DECISION_FINGERPRINT_MISMATCH "UPDATE private.source_observation SET verbatim_text='Anna død 1849' WHERE id='a4700000-0000-4000-8000-0000000000c1'" "$T/07.sql"
neg TRANSFER_STATE_NOT_PROPOSED "SELECT set_config('request.jwt.claim.sub','$A',false); SET ROLE authenticated; SELECT red_decide_interpretation('a4700000-0000-4000-8000-000000000303',1,'rejected','{\"m\":1}')" "$T/07.sql"
```

(`MACHINE_PREMISE_DRIFT` udløses før fingeraftrykket, fordi den ændrede assertion gør k1 til `REAL_DIFF`; ændringen af klausulteksten ændrer ikke klassifikationen, så fingeraftrykket fanger den. Afvises en `UPDATE` af en trigger, så brug den samme omvej som i Task 1.) `BIND_SCOPE_DRIFT` testes efter `07.sql` med en ekstra accepteret afgørelse på k3 før `08.sql`.

- [ ] **Step 7: Kør integrationstesten lokalt**

```bash
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
DB=daa_transfer_t5_$(date -u +%H%M%S)
export PGHOST=/tmp PGDATABASE=$DB
env -u PGSERVICE createdb "$DB"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do psql -X -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null; done
chmod +x tests/sql/transfer-decide-bind.sh
tests/sql/transfer-decide-bind.sh
```

Expected: `PACK_OK …`, `DECIDE_SQL_OK …`, `BIND_SQL_OK …`, `OK: transfer decide/bind`.

- [ ] **Step 8: CI og commit**

I `ci.yml`, job `evidence-promotion-db`, tilføj efter Task 3's linje:

```yaml
          zsh -f tests/sql/transfer-decide-bind.sh
```

(Kontrollér at `zsh` findes i CI-billedet; ellers tilføj `sudo apt-get install -y zsh` som første linje i steppet.)

```bash
git add .claude/skills/daa-extract/scripts/interpretation_promotion_targets_scoped.sql .claude/skills/daa-extract/scripts/transfer_pack.py .claude/skills/daa-extract/scripts/test_transfer_pack.py tests/sql/test-transfer-decide-bind.sql tests/sql/transfer-decide-bind.sh .github/workflows/ci.yml
git commit -m "feat(147): genereret skrive-SQL for afgørelser og bindinger i overførslen"
```

---

### Task 6: Lokal genafspilning (spec §4.4) — `PACK_REPLAY_OK`

**Files:**
- Create (privat, ikke i git): `~/.private/2018-20-overfoersel/replay.zsh`
- Modify: `docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-a-pakke.md` (ændringslog nederst)

**Interfaces:**
- Consumes: alt fra Task 1-5; restoren; dumpet `~/.private/2018-20-fuld/daa-prod-20261001133017.dump` og kvitteringen; forslagsmanifestet `~/.private/2018-20-fuld/proposal-manifest.json`; `~/.private/2018-20-fuld/44g-dryrun.R` og `44g-apply.R`; klassifikationen `~/.private/2018-20-fuld/kontrol/klassifikation.json`.
- Produces: pakken i `~/.private/2018-20-overfoersel/pack/`; rapport `~/.private/2018-20-overfoersel/replay/replay.json` med `PACK_REPLAY_OK`; tal og hashes til plan B.

- [ ] **Step 1: Byg pakken mod restoren**

```zsh
cd /Users/johanreventlow/TypeScript/danmarksadelsaarbog
O=~/.private/2018-20-overfoersel; S=.claude/skills/daa-extract/scripts; umask 077
q(){ env -u PGHOSTADDR -u PGSERVICE -u PGSERVICEFILE -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD -u PGDATABASE \
     psql -h /tmp -d daa2018f_20261001133125 -X -A -t -q -v ON_ERROR_STOP=1 -v src=1 -c "BEGIN READ ONLY" -f "$S/$1.sql" -c "ROLLBACK" | tail -1 > "$O/export/$1.json"; }
for f in transfer_pack_export interpretation_decision_fingerprint interpretation_transfer_digests transfer_baseline; do q $f; done
MC=$(/usr/bin/python3 -c "import json;print(json.load(open('$HOME/.private/2018-20-fuld/proposal-manifest.json'))['manifest_content_sha256'])")
LS=$(shasum -a 256 ~/.private/2018-20-fuld/ledger/eligibility-ledger-v1.json | cut -d' ' -f1)
/usr/bin/python3 $S/transfer_pack.py build --export $O/export/transfer_pack_export.json \
  --fingerprints $O/export/interpretation_decision_fingerprint.json --digests $O/export/interpretation_transfer_digests.json \
  --baseline $O/export/transfer_baseline.json --classification ~/.private/2018-20-fuld/kontrol/klassifikation.json \
  --dump-receipt ~/.private/2018-20-fuld/daa-prod-20261001133017.dump.receipt.json \
  --manifest-content-sha256 "$MC" --ledger-sha256 "$LS" --out-dir $O/pack
```

Expected: `PACK_OK afgørelser=676 accepterede=663 klassificerede=1276 pack_sha256=…`. `MC` skal være `80f3e5c1…`, `LS` `e620073c…`. Notér `pack_sha256`.

- [ ] **Step 2: Ren restore af dumpet uden migrationer**

```zsh
STAMP=$(/bin/date -u +%Y%m%d%H%M%S); DB=daa44_rehearsal_transfer_$STAMP
export PGHOST=/tmp PGDATABASE=$DB; unset PGHOSTADDR PGSERVICE PGSERVICEFILE PGPORT PGUSER PGPASSWORD
createdb "$DB"
pg_restore --clean --if-exists --no-owner --dbname="$DB" ~/.private/2018-20-fuld/daa-prod-20261001133017.dump 2>"$O/replay/restore.err" || true
grep '^pg_restore: error' "$O/replay/restore.err" | grep -vci vault   # forventet: 0
print -r -- "$DB" > "$O/replay/db.txt"
```

Rollerne (`anon`, `authenticated`, `service_role` m.fl.) findes allerede lokalt fra tidligere restores; mangler de, opret dem som i `~/.private/2018-20-fuld/restore-lokal.zsh`.

- [ ] **Step 3: Baseline på den rene restore = pakkens (N7)**

```zsh
r(){ psql -X -A -t -q -v ON_ERROR_STOP=1 -v src=1 -c "BEGIN READ ONLY" -f "$S/$1.sql" -c "ROLLBACK" | tail -1; }
r transfer_baseline > "$O/replay/baseline-clean.json"
/usr/bin/python3 -c "
import json; a=json.load(open('$O/replay/baseline-clean.json')); b=json.load(open('$O/pack/pack-manifest.json'))['baseline']
for k in ('canonical_sha256','clause_set_sha256','schema_sha256'): print(k, a[k]==b[k])
print('n_interpretations_src', a['n_interpretations_src'])"
r transfer_restore_preconditions | /usr/bin/python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print('orphans', d['n_orphans_total'], 'multi', d['n_multi_column_fks'])"
```

Expected: `canonical_sha256 True`, `clause_set_sha256 True`, `n_interpretations_src 0`, `orphans 0`. `schema_sha256` kan være `False`: det betyder, at `db-migrations.sql`/`db-rls.sql` ændrer skemaet ud over dumpet. **STOP i så fald** og forelæg forskellen (navne på de afvigende funktioner/kolonner, ingen data) — spec §4.3 forudsætter no-op, og plan B skal vide det.

- [ ] **Step 4: Ingest via writeren (dry-run, derefter apply)**

```zsh
env -i PATH=/usr/bin:/bin:/usr/local/bin PGHOST=/tmp PGDATABASE=$DB PGUSER=$USER PGPORT=5432 PGPASSWORD= \
  /usr/local/bin/Rscript --vanilla ~/.private/2018-20-fuld/44g-dryrun.R ~/.private/2018-20-fuld/proposal-manifest.json > "$O/replay/dryrun.out" 2>&1
env -i PATH=/usr/bin:/bin:/usr/local/bin PGHOST=/tmp PGDATABASE=$DB PGUSER=$USER PGPORT=5432 PGPASSWORD= \
  /usr/local/bin/Rscript --vanilla ~/.private/2018-20-fuld/44g-apply.R ~/.private/2018-20-fuld/proposal-manifest.json > "$O/replay/apply.out" 2>&1
grep -c -i "error\|fejl" "$O/replay/apply.out"   # forventet: 0 (læs aldrig filen; tæl)
r interpretation_transfer_digests > "$O/replay/digests-1.json"
/usr/bin/python3 $S/transfer_pack.py state --digests "$O/replay/digests-1.json" --pack-manifest "$O/pack/pack-manifest.json"
```

Expected: `PROPOSED`. (`44g-*.R` læser PG-miljøet; brug samme kald som i den fulde kørsel, hvis argumentformen afviger — se `~/.private/2018-20-fuld/44g-apply.R:7-21`.)

- [ ] **Step 5: `07` — afgørelserne**

```zsh
ACTOR=$(psql -X -A -t -q -c "SELECT id FROM profiles WHERE rolle='redaktion'")   # aldrig til stdout i en rapport
[[ $(print -rn -- "$ACTOR" | shasum -a 256 | cut -d' ' -f1) == $(/usr/bin/python3 -c "import json;print(json.load(open('$O/pack/pack-manifest.json'))['actor_sha256'])") ]] || { print -u2 "aktør afviger"; exit 1; }
/usr/bin/python3 $S/transfer_pack.py decide-sql --pack-dir "$O/pack" --out "$O/replay/07.sql"
psql -X -q -v ON_ERROR_STOP=1 -v src=1 -v actor="$ACTOR" -f "$O/replay/07.sql" > "$O/replay/07.out" 2>&1
r interpretation_transfer_digests > "$O/replay/digests-2.json"
/usr/bin/python3 $S/transfer_pack.py state --digests "$O/replay/digests-2.json" --pack-manifest "$O/pack/pack-manifest.json"
```

Expected: `DECIDED`. Fejler `07` med `MACHINE_PREMISE_DRIFT`: STOP og forelæg — det betyder, at klassifikationen i tilstand `PROPOSED` ikke giver det samme som kørslens fil.

- [ ] **Step 6: `08` — bindingerne**

```zsh
/usr/bin/python3 $S/transfer_pack.py bind-sql --pack-dir "$O/pack" --out "$O/replay/08.sql"
psql -X -q -v ON_ERROR_STOP=1 -v src=1 -v actor="$ACTOR" -f "$O/replay/08.sql" > "$O/replay/08.out" 2>&1
r interpretation_transfer_digests > "$O/replay/digests-3.json"
/usr/bin/python3 $S/transfer_pack.py state --digests "$O/replay/digests-3.json" --pack-manifest "$O/pack/pack-manifest.json"
```

Expected: `COMPLETE`.

- [ ] **Step 7: Kanonisk delta 0 og rapport**

```zsh
r transfer_baseline > "$O/replay/baseline-after.json"
/usr/bin/python3 - <<PY
import json, hashlib
O="$O"
a=json.load(open(f"{O}/replay/baseline-clean.json")); b=json.load(open(f"{O}/replay/baseline-after.json"))
m=json.load(open(f"{O}/pack/pack-manifest.json"))
assert a["canonical_sha256"]==b["canonical_sha256"], "kanonisk delta"
rep={"status":"PACK_REPLAY_OK","db":"$DB","pack_sha256":m["pack_sha256"],"n_decisions":m["n_decisions"],
     "n_bindings":m["digests"]["n_bindings"],"proposal_digest":m["digests"]["proposal_digest"],
     "decision_digest":m["digests"]["decision_digest"],"binding_digest":m["digests"]["binding_digest"]}
import os; fd=os.open(f"{O}/replay/replay.json", os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600); os.write(fd, json.dumps(rep).encode()); os.close(fd)
print(rep["status"], rep["n_decisions"], rep["n_bindings"], rep["pack_sha256"][:16])
PY
```

Expected: `PACK_REPLAY_OK 676 622 <hash>`.

- [ ] **Step 8: Mål varigheden og varianter til plan B**

Notér (kun tal): varighed af `44g-apply.R`, `07.sql`, `08.sql` (`time`); `pg_restore`-fejlantal; antal `orphans`. Disse er input til plan B's transaktionsgrænse (spec §6.1 trin 4c).

- [ ] **Step 9: Ændringslog og commit**

Tilføj nederst i denne plan:

```markdown
## Ændringslog

- 2026-10-04: første udgave.
- <dato>: Task 6 kørt — PACK_REPLAY_OK; pack_sha256 <16 tegn>…; varigheder apply/07/08 = <s>/<s>/<s>; schema_sha256 ren restore = restore: <ja/nej>.
```

```bash
git add docs/superpowers/plans/2026-10-04-trin4-2018-20-overfoersel-a-pakke.md
git commit -m "docs(147): plan A — lokal genafspilning af overførselspakken (PACK_REPLAY_OK)"
```

Engangsbasen `daa44_rehearsal_transfer_<stempel>` bevares, til projektejeren har set rapporten; oprydning kun efter måling og ja.
