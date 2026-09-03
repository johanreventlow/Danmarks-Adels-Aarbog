# 149b legacy-migration af 2018-20-narrativer — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Én generel elementoperation `legacy_migration` i #153's writer, som for hvert af 2018-20's 591 narrativer indlæser identitet fra `person_external_id`, afslutter den grandfathered legacy-stream med `legacy_migrated` og binder det eksisterende narrativ til dets source record gennem #152's eventkontrakt — bevist mod en restore af prod-dumpet.

**Architecture:** DB-laget får en ny RPC `public.red_apply_reimport_legacy_migration` (privat krop `private.migrate_legacy_narrative_record`) i den eksisterende batch-livscyklus (autorisér → begin → apply pr. element → finalize), en `legacy_migrated`-gren i den dedikerede reversal og et statusfilter i #152's tre læsefunktioner. Uden for DB: en læse-kun R-eksport af kandidater, en Python-manifestbygger (kun hashes) og udvidelser af R-validator/gateway/preview. Alt er editionsneutralt; 2018-20 bor i én profil-JSON.

**Tech Stack:** PostgreSQL 17 (plpgsql), R (DBI/RPostgres/jsonlite/digest), Python 3 (stdlib + pytest), psql-baserede SQL-tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-2018-20-fase-b-legacy-migration-design.md` (læs den først; §-henvisninger nedenfor peger dertil).

## Global Constraints

- Ingen nye tabeller; ingen DB-objekter, scripts eller tests med `2018` i navnet (editionskatalog-gaten `private.assert_reimport_edition_catalog()` har tom `_2018`-allowlist). Udgaven bor i `references/reimport-profiles/daa-2018-20-legacy-migration-v1.json`.
- Alle nye `public.red_*`-funktioner SKAL klassificeres i præcis ét af #154's arrays i `db-migrations.sql` (blokken `$public_red_revoke$`) OG i `db-verify.sql` (`$public_red_acl_verify$`), ellers fejler migrationen fail-closed (`EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED`).
- `schema.sql` er source of truth; `db-migrations.sql` er idempotent og SKAL give samme katalog. Hver DB-task ændrer begge.
- Ingen tekst i manifest, preview, tests, rapporter eller commits. Fixtures bruger opdigtede navne. `work/`-stier afvises af eksporten.
- Kontraktversion 2 er forudsætning for alle writer-RPC'er (`REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED`).
- Fejlkoder er stabile UPPER_SNAKE-tokens; nye tokens i denne plan begynder med `LEGACY_MIGRATION_` eller `NARRATIVE_LEGACY_MIGRATION_`.
- Commit-politik: parent-sessionen committer. Subagenter committer IKKE. Conventional Commits, dansk, ingen attribution.
- Codex-subagenter kan ikke nå lokal PostgreSQL (127.0.0.1:55441). SQL-tests og rehearsal køres af Claude-subagenter eller parent.
- Lokal PostgreSQL: `PG=/opt/homebrew/opt/postgresql@17/bin`, port 55441. Prod-dump: `.claude/worktrees/evidensbaseret-genimport/work/task30-1939-v50-c0-efterkoersel/pre-c0f-20260821-112005.dump` (SHA `fcfeb225…`).

## Målte kontraktfakta (verificér selv med grep før du koder — linjetal kan drive)

| Fakta | Sted |
|---|---|
| `reimport_event.operation` CHECK (`source_evidence`,`person_create`,`canonical_delta`,`reversal`,`activation`) | `schema.sql:2442` |
| `validate_reimport_authorization_payload` kræver præcis nøglerne `person_creates`+`source_evidence` og præfikser `person-create:`/`source-evidence:` | `schema.sql:2582-2607` |
| `ensure_reimport_source_evidence` (skabelon for run/persona-kæden; skriver 1 observation + 1 mention pr. record) | `schema.sql:2608-2645` |
| `red_apply_reimport_person_create` (skabelon: persona, mention, `red_decide_source_persona_identity`, `narrative_record_state`-efterkontrol, `reimport_event`) | `schema.sql:2735-2766` |
| `red_finalize_reimport` tæller kun to nøgler | `schema.sql:2767-2779` |
| `red_reimport_batch_result` kræver præcis 2 nøgler og to præfikser | `schema.sql:2780-2880` |
| ACL for den generelle writer (REVOKE/GRANT) | `schema.sql:3177-3182`, `db-rls.sql:1176-1192` |
| `red_decide_source_persona_identity` (GRANT authenticated) | `schema.sql:6773-6851`, `6972-6986` |
| `narrative_legacy_publication` + `narrative_publication_event` (CHECKs, target-check) | `schema.sql:9190-9320` |
| Triggere: event-validering / ledger-baseline-immutabilitet (ingen status-whitelist) | `schema.sql:9320-9450` |
| `narrative_record_labels(record_id)` → `{record_label, citation_label, side, record_order}` | `schema.sql:10099` |
| `narrative_publication_state(person_id,source_id,record_key)` / `narrative_record_state(person_id,source_id,record_key,lock)` | `schema.sql:10150-10484`, `10484-10733` |
| `narrative_legacy_publication_state(ref)` / `narrative_legacy_state(ref,lock)` (`ledger_status`, `baseline_matches`, `publication_status`) | `schema.sql:10733-10935` |
| `red_person_narrative_records` legacy-forespørgsel (`'grandfathered_legacy'`) | `schema.sql:11055-11110` |
| `mutate_person_narrative_record` (skabelon for event-append + efterkontrol) | `schema.sql:11219-11518` |
| `withdraw_legacy_narrative` (skabelon for legacy-stream-event) | `schema.sql:11604-11745` |
| `reverse_narrative_publication_event` (reversibel mængde, `v_would_publish`, `legacy_withdrawn`-gren) | `schema.sql:11745-12073` |
| `person_daa_narrative_publication_allowed` (returnerer fra binding-grenen; legacy kræver `grandfathered_publication`) | `schema.sql` grep `FUNCTION public.person_daa_narrative_publication_allowed` (sidste def) |
| `public_person_bio_source_versions_v2` legacy-gren uden statusfilter | `schema.sql:12345-12375` |
| `public_person_bio_source_versions` (v1-navn) v2-gren, legacy-del uden statusfilter | `schema.sql:12451-12500` |
| #154 ACL-klassifikation (arrays `v_authenticated`, `v_service_only`, `v_disabled`) | `db-migrations.sql:15932-16086`, `db-verify.sql:2680-2760` |
| SQL-test-inventarer der lister writer-RPC'er | `tests/sql/test-reimport-writer.sql:15-25,100-130`, `tests/sql/inspect-reimport-writer-catalog.sql:15-30`, `tests/sql/test-1939-v50-production-writer.sql:29,66` |
| R-validator/gateway | `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R:19-66,120-260` |
| R-preview | `.claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R` |
| Python-profilindlæser (lukket nøglemængde, kanonisk hash) | `.claude/skills/daa-extract/scripts/reimport_profile.py` |
| `normalize_narrative_v1(raw, corpus) -> {text, flags, applied}` | `.claude/skills/daa-extract/scripts/normalize_narrative_1939_v50.py:235` |
| CI-jobbet der bygger `writer_1939` v2-basen og kører R-integrationstests | `.github/workflows/ci.yml:300-334` |
| 149a's R-integrationstest (skabelon: aktør, profil, manifest, dry-run/apply/replay, aggregat-hashes) | `tests/integration/test-reimport-source-evidence.R` |
| Rehearsal-runbook for 149a (restore, migrations, #152-cutover §3b, profil, kørsel) | `docs/runbooks/source-evidence-reimport-rehearsal.md` |

## Forventede tal (spec §3-§4, dump 2026-08-21)

591 records/narrativer → 541 `bound_published`, 46 `bound_draft`, 4 `unresolved_text` (`I-133`, `II-35`, `III-129`, `IV-94`), 0 `unresolved_identity`. Elementer: 587. Events: 587 `draft_created`, 541 `published`, 541 `legacy_migrated`. Ledger source 1 efter apply: 541 `migrated`, 3 `grandfathered_publication`.

## File Structure

| Fil | Ansvar |
|---|---|
| `schema.sql`, `db-migrations.sql` | CHECK-udvidelse, tre udvidede writer-funktioner, ny RPC + privat krop, reversal-gren, tre læsefunktions-filtre, ACL. |
| `db-rls.sql`, `db-verify.sql` | REVOKE/GRANT for den nye RPC; ACL-klassifikation. |
| `tests/sql/test-reimport-legacy-migration.sql` (ny) | Hele DB-kontrakten for elementet, læsefunktionerne og reversal, mod `writer_1939`-v2-basen. |
| `tests/sql/test-reimport-writer.sql`, `inspect-reimport-writer-catalog.sql`, `test-1939-v50-production-writer.sql` | Inventarer udvidet med den nye RPC/private funktion. |
| `.github/workflows/ci.yml` | Nyt trin i writer-jobbet + pytest-fil + R-integrationstest. |
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | Validator (valgfri `legacy_migrations`, `dependency_class='legacy_migration'`, valgfri `dispositions`), expected_counts, dispatch, gateway. |
| `.claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R` | Legacy-før-billede når manifestet har `legacy_migrations > 0`. |
| `.claude/skills/daa-extract/scripts/export_legacy_migration_candidates.R` (ny) | Læse-kun eksport af kandidater (JSON uden tekst) + tekster (0600). |
| `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py` (ny) + `test_build_legacy_migration_manifest.py` (ny) | Dispositioner, stopgrænse, inkonsistens, manifest uden tekst. |
| `.claude/skills/daa-extract/scripts/reimport_profile.py` + `test_reimport_profile.py` | Andet profilskema `reimport-legacy-migration-profile-v1`. |
| `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-legacy-migration-v1.json` (ny) | Udgaveprofilen. |
| `tests/testthat/test-reimport-writer-legacy-migration.R` (ny) | Enhedstests for validator/expected_counts/dispatch (mock-gateway). |
| `tests/integration/test-reimport-legacy-migration.R` (ny) | Syntetisk v2-integration: dry-run, apply, replay, reversal-kæde. |
| `docs/runbooks/legacy-migration-reimport-rehearsal.md` (ny), `docs/evidensbaseret-genimport/legacy-migration-149b-rehearsal.md` (ny), `…-149b-phase-package-contribution.md` (ny), `status.md`, `changelog.md`, `decisions.md` | Rehearsal og dokumentation. |

---

# Leverance 1 — databasekontrakten (én dag; »én rigtig kørsel« = SQL-testen grøn mod `writer_1939`-v2-basen bygget som CI gør det)

### Task 1: Statusfilter i #152's tre læsefunktioner (fejlende test først)

**Files:**
- Modify: `schema.sql:12345-12375` (v2-legacy-gren), `schema.sql:12451-12500` (v1-navnets v2-legacy-gren), `schema.sql:11055-11110` (`red_person_narrative_records` legacy-forespørgsel)
- Modify: `db-migrations.sql` (append en ny blok »2026-09-03: #166 149b« med `CREATE OR REPLACE` af de tre funktioner — kopiér funktionskroppene ordret fra `schema.sql` efter rettelsen)
- Create: `tests/sql/test-reimport-legacy-migration.sql`

**Interfaces:**
- Produces: uændrede signaturer; ny adfærd: en `narrative_legacy_publication`-række med `status<>'grandfathered_publication'` producerer aldrig en `legacy_narrative`-række i de to offentlige funktioner, og `migrated` producerer ingen `grandfathered_legacy`-række i redaktørlisten.

- [ ] **Step 1: Skriv den fejlende test**

Opret `tests/sql/test-reimport-legacy-migration.sql` med denne ramme (alle senere tasks føjer `DO`-blokke til samme fil; filen kører i én transaktion og ruller altid tilbage):

```sql
\set ON_ERROR_STOP on
BEGIN;
-- Forudsætning: basen er writer_1939 efter tests/sql/reimport-writer-v2-bootstrap.sql
-- (kontraktversion 2, syntetiske personer/records/bindinger, aktør med rolle redaktion).
DO $precondition$ BEGIN
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'TEST_REQUIRES_CONTRACT_V2'; END IF;
END $precondition$;

-- Task 1: en migreret ledger-række må aldrig vises som legacy.
DO $task1_read_filter$
DECLARE
  v_person bigint; v_narrative bigint; v_source bigint; v_ref uuid := gen_random_uuid();
  v_state jsonb; v_rows integer;
BEGIN
  -- Vælg et syntetisk person/DAA-narrativ uden binding og uden ledger-række.
  SELECT n.subjekt_id,n.id,n.source_id INTO v_person,v_narrative,v_source
    FROM public.narrative n JOIN public.source s ON s.id=n.source_id AND s.slags='DAA-udgave'
    JOIN public.person p ON p.id=n.subjekt_id
   WHERE n.subjekt_type='person' AND p.levende IS FALSE AND coalesce(p.privat,false)=false
     AND coalesce(p.staged,false)=false AND coalesce(n.privat,false)=false
     AND NOT EXISTS (SELECT 1 FROM private.narrative_record_publication b WHERE b.narrative_id=n.id)
     AND NOT EXISTS (SELECT 1 FROM private.narrative_legacy_publication l WHERE l.narrative_id=n.id)
   ORDER BY n.id LIMIT 1;
  IF v_narrative IS NULL THEN RAISE EXCEPTION 'TEST_FIXTURE_NARRATIVE_MISSING'; END IF;
  v_state:=private.narrative_legacy_candidate_publication_state(v_narrative,v_source,v_ref);
  INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
  VALUES(v_ref,v_narrative,v_source,v_state,encode(extensions.digest(v_state::text,'sha256'),'hex'),'grandfathered_publication');
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name)
  VALUES((SELECT max(id) FROM public.change_set),v_ref,1,'baseline',v_narrative,v_source,v_ref,'test',v_state,v_state,encode(extensions.digest(v_state::text,'sha256'),'hex'),encode(extensions.digest(v_state::text,'sha256'),'hex'),'test');
  UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=v_ref) WHERE legacy_publication_ref=v_ref;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative' AND r.source_id=v_source;
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK1_GRANDFATHERED_ROW_EXPECTED: %',v_rows; END IF;
  -- Sæt status til migrated uden at ændre baseline (triggeren tillader det).
  UPDATE private.narrative_legacy_publication SET status='migrated' WHERE legacy_publication_ref=v_ref;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative' AND r.source_id=v_source;
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_MIGRATED_ROW_LEAKED_V2: %',v_rows; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions(ARRAY[v_person]) r WHERE r.provenance_kind='legacy_narrative';
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_MIGRATED_ROW_LEAKED_V1: %',v_rows; END IF;
  PERFORM set_config('request.jwt.claim.sub',(SELECT id::text FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1),true);
  SELECT count(*) INTO v_rows FROM public.red_person_narrative_records(v_person) r WHERE r.provenance_kind='grandfathered_legacy' AND r.legacy_publication_ref=v_ref;
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK1_MIGRATED_ROW_LEAKED_EDITOR: %',v_rows; END IF;
  -- withdrawn skal fortsat vises i redaktørlisten (historik), men ikke offentligt.
  UPDATE private.narrative_legacy_publication SET status='withdrawn' WHERE legacy_publication_ref=v_ref;
  SELECT count(*) INTO v_rows FROM public.red_person_narrative_records(v_person) r WHERE r.provenance_kind='grandfathered_legacy' AND r.legacy_publication_ref=v_ref;
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK1_WITHDRAWN_ROW_HIDDEN_EDITOR: %',v_rows; END IF;
  RAISE NOTICE 'task1 read filter OK';
END $task1_read_filter$;

ROLLBACK;
```

Bemærk: `person_daa_narrative_publication_allowed` afviser allerede `migrated` for den rene legacy-vej; lækagen opstår først, når der OGSÅ findes en `published` binding (Task 3 tester den kombination). Task 1's test fanger derfor kun redaktørlisten som rød i første omgang — det er tilsigtet: filtret i de to offentlige funktioner er forsvar i dybden og verificeres endeligt i Task 3.

- [ ] **Step 2: Byg testbasen som CI og kør testen (forventet: FEJL `TASK1_MIGRATED_ROW_LEAKED_EDITOR`)**

```bash
PG=/opt/homebrew/opt/postgresql@17/bin; export PGPORT=55441 PGHOST=127.0.0.1 PGDATABASE=daa149b_writer_ci
$PG/dropdb --if-exists $PGDATABASE; $PG/createdb $PGDATABASE
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do
  $PG/psql -X -v ON_ERROR_STOP=1 -f "$f" > /dev/null || { echo "FAIL $f"; break; }; done
$PG/psql -X -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' > /dev/null
$PG/psql -X -v ON_ERROR_STOP=1 -f db-rls.sql > /dev/null
$PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
```

- [ ] **Step 3: Ret de tre funktioner i `schema.sql`**

I `public_person_bio_source_versions_v2` (v2-grenen, `schema.sql:~12367`) og i `public_person_bio_source_versions` (v2-grenen, `~12483`), tilføj til legacy-`JOIN`:

```sql
      JOIN private.narrative_legacy_publication legacy
        ON legacy.narrative_id=narrative.id
       AND legacy.status='grandfathered_publication'
```

I `red_person_narrative_records` (anden `RETURN QUERY`, `WITH measured AS (... FROM private.narrative_legacy_publication legacy JOIN public.narrative ... WHERE ...)`), tilføj `AND legacy.status<>'migrated'` til `WHERE`.

- [ ] **Step 4: Spejl i `db-migrations.sql`**

Append efter #154-blokken (før filens slutning) en ny sektion:

```sql
-- =====================================================================
-- 2026-09-03: #166 149b legacy-migration — læsefunktioner, elementoperation,
-- writer, reversal-gren og ACL. Idempotent: CREATE OR REPLACE / IF NOT EXISTS.
-- =====================================================================
```

og `CREATE OR REPLACE FUNCTION` for de tre funktioner med kroppene kopieret ordret fra `schema.sql`. Kør derefter `diff <(sed -n '/FUNCTION public.red_person_narrative_records/,/^\$\$;/p' schema.sql) <(sed -n '/FUNCTION public.red_person_narrative_records/,/^\$\$;/p' db-migrations.sql | tail -n +1)` — forventet tom for hver af de tre.

- [ ] **Step 5: Kør testen grøn (Step 2's kommandoer igen) og kør migrationsparitet**

```bash
# frisk base via schema.sql (Step 2) + samme base via db-migrations.sql oveni skal give identiske funktionskroppe
$PG/psql -X -v ON_ERROR_STOP=1 -f db-migrations.sql > /dev/null && $PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
$PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-narrative-record-contract.sql   # #152's egen kontrakt stadig grøn
```

Forventet: `task1 read filter OK`, ingen fejl.

- [ ] **Step 6: Commit** (parent): `fix(db): legacy-læsefunktioner filtrerer på grandfathered status (149b)`

### Task 2: Elementoperation `legacy_migration` i de lukkede mængder

**Files:**
- Modify: `schema.sql:2442` (CHECK), `2582-2607` (`validate_reimport_authorization_payload`), `2767-2779` (`red_finalize_reimport`), `2780-2880` (`red_reimport_batch_result`)
- Modify: `db-migrations.sql` (samme blok som Task 1: `ALTER TABLE … DROP CONSTRAINT IF EXISTS reimport_event_operation_check; ALTER TABLE … ADD CONSTRAINT reimport_event_operation_check CHECK (…)` + `CREATE OR REPLACE` af de tre funktioner)
- Modify: `tests/sql/test-reimport-legacy-migration.sql` (ny `DO`-blok)

**Interfaces:**
- Produces: `expected_counts` accepterer nøglemængden `{person_creates, source_evidence}` ELLER `{person_creates, source_evidence, legacy_migrations}`; element-præfiks `legacy-migration:`; `reimport_event.operation='legacy_migration'`.

- [ ] **Step 1: Fejlende test**

```sql
DO $task2_counts$
DECLARE v_err text; v_ok boolean:=false; v_source bigint; v_profile text; v_sha text;
BEGIN
  SELECT source_id,profile_id,profile_sha256 INTO v_source,v_profile,v_sha FROM private.reimport_writer_profile ORDER BY created_at LIMIT 1;
  -- (a) to-nøgle-manifest skal stadig valideres (149a-kompatibilitet)
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":1}'::jsonb,
    jsonb_build_object('source-evidence:x','{}'::jsonb));
  -- (b) tre nøgler med legacy-migration-præfiks skal valideres
  BEGIN
    PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
      jsonb_build_object('legacy-migration:x','{}'::jsonb));
    v_ok:=true;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK2_THREE_KEY_REJECTED: %',v_err; END IF;
  -- (c) forkert nøgle afvises fortsat
  v_ok:=false;
  BEGIN
    PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"canonical_delta":0}'::jsonb,'{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK2_UNKNOWN_KEY_ACCEPTED'; END IF;
  -- (d) præfiks/antal-mismatch afvises
  v_ok:=false;
  BEGIN
    PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
      jsonb_build_object('source-evidence:x','{}'::jsonb));
  EXCEPTION WHEN OTHERS THEN v_ok:=true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK2_PREFIX_MISMATCH_ACCEPTED'; END IF;
  -- (e) CHECK-constraint accepterer den nye operation
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='private.reimport_event'::regclass AND contype='c'
                 AND pg_get_constraintdef(oid) LIKE '%legacy_migration%') THEN
    RAISE EXCEPTION 'TASK2_OPERATION_CHECK_MISSING';
  END IF;
  RAISE NOTICE 'task2 counts OK';
END $task2_counts$;
```

- [ ] **Step 2: Kør (forventet FEJL `TASK2_THREE_KEY_REJECTED`)** — Step 2-kommandoerne fra Task 1.

- [ ] **Step 3: Implementér i `schema.sql`**

`schema.sql:2442`:

```sql
  operation text NOT NULL CHECK(operation IN ('source_evidence','person_create','legacy_migration','canonical_delta','reversal','activation')),
```

`validate_reimport_authorization_payload` — erstat kroppen:

```sql
DECLARE v_person_creates bigint; v_source_evidence bigint; v_legacy_migrations bigint; v_authorized_count bigint;
BEGIN
  IF jsonb_typeof(p_expected_counts)<>'object' OR jsonb_typeof(p_authorized_elements)<>'object'
     OR jsonb_typeof(p_expected_counts->'person_creates')<>'number'
     OR jsonb_typeof(p_expected_counts->'source_evidence')<>'number'
     OR coalesce(p_expected_counts->>'person_creates','') !~ '^[0-9]+$'
     OR coalesce(p_expected_counts->>'source_evidence','') !~ '^[0-9]+$'
     OR (p_expected_counts ? 'legacy_migrations' AND (jsonb_typeof(p_expected_counts->'legacy_migrations')<>'number' OR coalesce(p_expected_counts->>'legacy_migrations','') !~ '^[0-9]+$'))
     OR (SELECT count(*) FROM jsonb_object_keys(p_expected_counts)) NOT IN (2,3)
     OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_expected_counts) key WHERE key NOT IN ('person_creates','source_evidence','legacy_migrations')) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID';
  END IF;
  v_person_creates:=(p_expected_counts->>'person_creates')::bigint;
  v_source_evidence:=(p_expected_counts->>'source_evidence')::bigint;
  v_legacy_migrations:=coalesce((p_expected_counts->>'legacy_migrations')::bigint,0);
  SELECT count(*) INTO v_authorized_count FROM jsonb_object_keys(p_authorized_elements);
  IF v_authorized_count<>(v_person_creates+v_source_evidence+v_legacy_migrations)
     OR EXISTS(SELECT 1 FROM jsonb_each(p_authorized_elements) element
                WHERE jsonb_typeof(element.value)<>'object'
                   OR (element.key !~ '^person-create:.+$' AND element.key !~ '^source-evidence:.+$' AND element.key !~ '^legacy-migration:.+$'))
     OR (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements) key WHERE key ~ '^person-create:.+$')<>v_person_creates
     OR (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements) key WHERE key ~ '^source-evidence:.+$')<>v_source_evidence
     OR (SELECT count(*) FROM jsonb_object_keys(p_authorized_elements) key WHERE key ~ '^legacy-migration:.+$')<>v_legacy_migrations THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_AUTHORIZATION_INVALID';
  END IF;
END $$;
```

`red_finalize_reimport` — erstat count-linjen:

```sql
  SELECT jsonb_build_object('person_creates',count(*) FILTER(WHERE operation='person_create'),'source_evidence',count(*) FILTER(WHERE operation='source_evidence'))
         || CASE WHEN v_batch.expected_counts ? 'legacy_migrations'
                 THEN jsonb_build_object('legacy_migrations',count(*) FILTER(WHERE operation='legacy_migration')) ELSE '{}'::jsonb END
    INTO v_counts FROM private.reimport_event WHERE batch_id=p_batch_id;
```

`red_reimport_batch_result` — (i) nøgletjek: `(SELECT count(*) FROM jsonb_object_keys(v_batch.expected_counts)) NOT IN (2,3)` og `key NOT IN ('person_creates','source_evidence','legacy_migrations')`, plus samme typetjek for `legacy_migrations` som ovenfor; (ii) ny variabel `v_expected_legacy_migrations bigint := coalesce((v_batch.expected_counts->>'legacy_migrations')::bigint,0)`; (iii) `v_authorized_element_count<>(v_expected_person_creates+v_expected_source_evidence+v_expected_legacy_migrations)`; (iv) præfiks-tjekket udvides med `AND item.key !~ '^legacy-migration:'`; (v) `event.operation IN ('person_create','source_evidence','legacy_migration')`.

- [ ] **Step 4: Spejl i `db-migrations.sql`** (CHECK via `DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT`; tre `CREATE OR REPLACE`). Kør migrations-paritet som i Task 1 Step 5.

- [ ] **Step 5: Kør Task 1-2 grønne + regressioner**

```bash
$PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
$PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql
$PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-name-completion.sql
PGDATABASE=daa149b_writer_ci Rscript tests/integration/test-reimport-source-evidence.R   # 149a-kompatibilitet
```

- [ ] **Step 6: Commit**: `feat(db): elementoperation legacy_migration i den generelle reimport-writers tællinger`

### Task 3: Writeren `private.migrate_legacy_narrative_record` + `public.red_apply_reimport_legacy_migration`

**Files:**
- Modify: `schema.sql` (indsæt begge funktioner umiddelbart efter `red_apply_reimport_person_create`, dvs. før `red_finalize_reimport` ~`2767`; ACL-linjer ved `3177-3182`)
- Modify: `db-migrations.sql` (samme 149b-blok), `db-rls.sql:1176-1192` (REVOKE/GRANT-lister)
- Modify: `tests/sql/test-reimport-legacy-migration.sql`

**Interfaces:**
- Consumes: `private.require_reimport_open_batch(uuid)`, `private.require_reimport_writer_editor()`, `private.lock_reimport_writer(bigint,text)`, `private.reimport_canonical_json_sha256(jsonb)`, `public.red_decide_source_persona_identity(uuid,bigint,integer,text,jsonb)`, `private.narrative_publication_state(bigint,bigint,text)`, `private.narrative_record_state(bigint,bigint,text,boolean)`, `private.narrative_legacy_state(uuid,boolean)`, `private.narrative_legacy_publication_state(uuid)`, `public.begin_change_set(text,text,text,bigint)`, `public.person_daa_narrative_publication_allowed(bigint)`.
- Produces: `public.red_apply_reimport_legacy_migration(p_batch_id uuid,p_element_id text,p_payload jsonb) RETURNS jsonb` — returnerer `{persona_id, identity_version, legacy_event_id, binding_id, draft_event_id, published_event_id, publication_state_sha256, state_sha256}`. Payloadens lukkede nøglemængde (spec §6.2): `disposition, legacy_baseline_sha256, legacy_publication_ref, narrative_id, narrative_text_sha256, normalized_text_sha256, occurrence_verbatim_sha256, person_id, persona_key, source_id, source_record_key`.

- [ ] **Step 1: Fejlende test — den fulde lykkelige vej + de vigtigste afvisninger**

Tilføj til `tests/sql/test-reimport-legacy-migration.sql` (efter Task 2-blokken) en fixture-hjælper og testblok. Fixturen bygger på `writer_1939`-basens syntetiske profil og opretter selv: ét ubundet person/DAA-narrativ med `person_external_id`, ét source record med accepteret anker via `private.ensure_reimport_source_evidence`-vejen (dvs. en 149a-lignende `source_evidence`-batch), og en ledger-række via samme mønster som Task 1.

```sql
-- Hjælper: opret en fuld 149b-fixture og returnér nøglerne. Alt syntetisk.
CREATE FUNCTION pg_temp.task3_fixture(p_key text, p_levende boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_source bigint; v_profile text; v_sha text; v_actor uuid; v_person bigint; v_narrative bigint;
  v_text text := 'Alfa '||p_key||' Bravo, f. 1801, d. 1860.';
  v_auth uuid; v_batch uuid; v_payload jsonb; v_ref uuid := gen_random_uuid(); v_state jsonb;
  v_occ_sha text; v_baseline text; v_verbatim text;
BEGIN
  SELECT p.source_id,p.profile_id,p.profile_sha256 INTO v_source,v_profile,v_sha
    FROM private.reimport_writer_profile p ORDER BY p.created_at LIMIT 1;
  SELECT id INTO v_actor FROM public.profiles WHERE rolle='redaktion' ORDER BY id LIMIT 1;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO public.person(levende,privat,staged,visning_navn) VALUES(p_levende,false,false,'Fixture '||p_key) RETURNING id INTO v_person;
  INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES(v_person,v_source,p_key);
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst,privat) VALUES('person',v_person,v_source,v_text,false) RETURNING id INTO v_narrative;
  -- 149a-ækvivalent: source record + forekomst + anker + observation + mention
  v_payload:=jsonb_build_object('source_record_key',p_key,'source_id',v_source,'category','person_post',
    'disposition','retain_source_only','rendition_content_sha256',repeat('c',64),
    'source_span',jsonb_build_object('char_from',0,'char_to',length(v_text)),
    'page_evidence',jsonb_build_object('page_from',10,'page_to',10),
    'verbatim_text',v_text,'verbatim_sha256',encode(extensions.digest(v_text,'sha256'),'hex'),
    'anchor_method','deterministic-segment','segment_version','fixture');
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(repeat('1',64),repeat('2',64),
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_source,v_profile,v_sha,'{"person_creates":0,"source_evidence":1}'::jsonb,
    jsonb_build_object('source-evidence:'||p_key,v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,repeat('1',64),repeat('2',64));
  PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:'||p_key,v_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  IF NOT p_levende THEN
    v_state:=private.narrative_legacy_candidate_publication_state(v_narrative,v_source,v_ref);
    v_baseline:=encode(extensions.digest(v_state::text,'sha256'),'hex');
    INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
    VALUES(v_ref,v_narrative,v_source,v_state,v_baseline,'grandfathered_publication');
    INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name)
    VALUES((SELECT max(id) FROM public.change_set),v_ref,1,'baseline',v_narrative,v_source,v_ref,'fixture',v_state,v_state,v_baseline,v_baseline,'fixture');
    UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=v_ref) WHERE legacy_publication_ref=v_ref;
  END IF;
  RETURN jsonb_build_object('source_id',v_source,'profile_id',v_profile,'profile_sha256',v_sha,'actor',v_actor,
    'person_id',v_person,'narrative_id',v_narrative,'record_key',p_key,
    'narrative_text_sha256',encode(extensions.digest(v_text,'sha256'),'hex'),
    'occurrence_verbatim_sha256',encode(extensions.digest(v_text,'sha256'),'hex'),
    'legacy_publication_ref',CASE WHEN p_levende THEN NULL ELSE v_ref END,
    'legacy_baseline_sha256',CASE WHEN p_levende THEN NULL ELSE v_baseline END);
END $$;

-- Hjælper: kør én legacy-migration-batch med præcis ét element og returnér RPC-resultatet.
CREATE FUNCTION pg_temp.task3_migrate(p_fx jsonb, p_disposition text, p_manifest_nonce text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_payload jsonb; v_auth uuid; v_batch uuid; v_result jsonb; v_msha text := encode(extensions.digest(p_manifest_nonce,'sha256'),'hex');
BEGIN
  v_payload:=jsonb_build_object(
    'source_record_key',p_fx->>'record_key','source_id',(p_fx->>'source_id')::bigint,
    'person_id',(p_fx->>'person_id')::bigint,'narrative_id',(p_fx->>'narrative_id')::bigint,
    'disposition',p_disposition,
    'narrative_text_sha256',p_fx->>'narrative_text_sha256',
    'occurrence_verbatim_sha256',p_fx->>'occurrence_verbatim_sha256',
    'normalized_text_sha256',p_fx->>'narrative_text_sha256',
    'legacy_publication_ref',p_fx->'legacy_publication_ref',
    'legacy_baseline_sha256',p_fx->'legacy_baseline_sha256',
    'persona_key',p_fx->>'record_key');
  PERFORM set_config('request.jwt.claim.sub',p_fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,repeat('9',64),
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (p_fx->>'source_id')::bigint,p_fx->>'profile_id',p_fx->>'profile_sha256',
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":1}'::jsonb,
    jsonb_build_object('legacy-migration:'||(p_fx->>'record_key'),v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,repeat('9',64));
  v_result:=public.red_apply_reimport_legacy_migration(v_batch,'legacy-migration:'||(p_fx->>'record_key'),v_payload);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_result||jsonb_build_object('batch_id',v_batch,'authorization_id',v_auth);
END $$;

DO $task3_happy_path$
DECLARE fx jsonb; r jsonb; v_rows integer; v_status text; v_kind text;
BEGIN
  -- bound_published
  fx:=pg_temp.task3_fixture('T3P',false);
  r:=pg_temp.task3_migrate(fx,'bound_published','t3p');
  SELECT status INTO v_status FROM private.narrative_legacy_publication WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  IF v_status<>'migrated' THEN RAISE EXCEPTION 'TASK3_LEDGER_NOT_MIGRATED: %',v_status; END IF;
  SELECT status INTO v_status FROM private.narrative_record_publication WHERE id=(r->>'binding_id')::uuid;
  IF v_status<>'published' THEN RAISE EXCEPTION 'TASK3_BINDING_NOT_PUBLISHED: %',v_status; END IF;
  SELECT count(*) INTO v_rows FROM private.narrative_publication_event WHERE narrative_id=(fx->>'narrative_id')::bigint AND event_type IN ('legacy_migrated','draft_created','published');
  IF v_rows<>3 THEN RAISE EXCEPTION 'TASK3_EVENT_COUNT: %',v_rows; END IF;
  IF NOT public.person_daa_narrative_publication_allowed((fx->>'narrative_id')::bigint) THEN RAISE EXCEPTION 'TASK3_GATE_CLOSED'; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]);
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3_PUBLIC_ROWS: % (forventet præcis 1, ingen dublet)',v_rows; END IF;
  SELECT provenance_kind INTO v_kind FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]);
  IF v_kind<>'source_record' THEN RAISE EXCEPTION 'TASK3_PUBLIC_KIND: %',v_kind; END IF;
  SELECT count(*) INTO v_rows FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
   WHERE p.persona_key='T3P' AND i.decision_status='accepted' AND i.canonical_person_id=(fx->>'person_id')::bigint AND i.evidence->>'authority'='person_external_id';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3_IDENTITY_LEDGER: %',v_rows; END IF;
  SELECT count(*) INTO v_rows FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid AND operation='legacy_migration';
  IF v_rows<>1 THEN RAISE EXCEPTION 'TASK3_REIMPORT_EVENT: %',v_rows; END IF;
  -- narrativrækken er urørt
  IF (SELECT encode(extensions.digest(tekst,'sha256'),'hex') FROM public.narrative WHERE id=(fx->>'narrative_id')::bigint)<>fx->>'narrative_text_sha256' THEN RAISE EXCEPTION 'TASK3_TEXT_CHANGED'; END IF;
  -- bound_draft (levende)
  fx:=pg_temp.task3_fixture('T3D',true);
  r:=pg_temp.task3_migrate(fx,'bound_draft','t3d');
  SELECT status INTO v_status FROM private.narrative_record_publication WHERE id=(r->>'binding_id')::uuid;
  IF v_status<>'draft' THEN RAISE EXCEPTION 'TASK3_DRAFT_STATUS: %',v_status; END IF;
  IF (r->'published_event_id') IS DISTINCT FROM 'null'::jsonb OR (r->'legacy_event_id') IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'TASK3_DRAFT_EXTRA_EVENTS'; END IF;
  IF public.person_daa_narrative_publication_allowed((fx->>'narrative_id')::bigint) THEN RAISE EXCEPTION 'TASK3_DRAFT_PUBLIC'; END IF;
  SELECT count(*) INTO v_rows FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]);
  IF v_rows<>0 THEN RAISE EXCEPTION 'TASK3_DRAFT_PUBLIC_ROWS: %',v_rows; END IF;
  RAISE NOTICE 'task3 happy path OK';
END $task3_happy_path$;

-- Hjælper: forvent en bestemt fejlkode fra én migration (subtransaktion ruller tilbage).
CREATE FUNCTION pg_temp.task3_expect(p_code text, p_fx jsonb, p_disposition text, p_nonce text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM pg_temp.task3_migrate(p_fx,p_disposition,p_nonce);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE p_code||'%' THEN RETURN; END IF;
    RAISE EXCEPTION 'TASK3_EXPECTED_% GOT %',p_code,SQLERRM;
  END;
  RAISE EXCEPTION 'TASK3_EXPECTED_%_BUT_SUCCEEDED',p_code;
END $$;

DO $task3_rejections$
DECLARE fx jsonb; v_ok boolean;
BEGIN
  -- (1) publicerbar person uden ledger-række → LEDGER_INCONSISTENT
  fx:=pg_temp.task3_fixture('T3R1',true);
  UPDATE public.person SET levende=false WHERE id=(fx->>'person_id')::bigint;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_LEDGER_INCONSISTENT',fx,'bound_draft','t3r1');
  -- (2) bound_published med ledger-status withdrawn
  fx:=pg_temp.task3_fixture('T3R2',false);
  UPDATE private.narrative_legacy_publication SET status='withdrawn' WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_LEDGER_INCONSISTENT',fx,'bound_published','t3r2');
  -- (3) tekstdrift i narrativet
  fx:=pg_temp.task3_fixture('T3R3',false);
  UPDATE public.narrative SET tekst=tekst||' x' WHERE id=(fx->>'narrative_id')::bigint;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_NARRATIVE_TEXT_DRIFT',fx,'bound_published','t3r3');
  -- (4) identitet: external_id fjernet → tvetydig
  fx:=pg_temp.task3_fixture('T3R4',false);
  DELETE FROM public.person_external_id WHERE person_id=(fx->>'person_id')::bigint;
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_IDENTITY_AMBIGUOUS',fx,'bound_published','t3r4');
  -- (5) allerede bundet: anden batch (nyt manifest-nonce) mod samme narrativ
  fx:=pg_temp.task3_fixture('T3R5',false);
  PERFORM pg_temp.task3_migrate(fx,'bound_published','t3r5');
  PERFORM pg_temp.task3_expect('LEGACY_MIGRATION_ALREADY_BOUND',fx,'bound_published','t3r5b');
  -- (6) ikke-autoriseret element/ukendt batch afvises af writer-gaten
  v_ok:=false;
  BEGIN
    PERFORM public.red_apply_reimport_legacy_migration(gen_random_uuid(),'legacy-migration:T3R6','{"x":1}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'REIMPORT_WRITER_%'; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK3_EXPECTED_WRITER_GATE'; END IF;
  RAISE NOTICE 'task3 rejections OK';
END $task3_rejections$;
```

Bemærk til (5): `task3_migrate` afvises i (5b) allerede før writeren, hvis `red_begin_reimport` finder en finaliseret batch med samme manifest — derfor det nye nonce. Bemærk også, at `SET ROLE` i `pg_temp.task3_migrate` kræver, at testens session-rolle må skifte til `service_role`/`authenticated` (superuser i CI/lokalt).

- [ ] **Step 2: Kør (forventet FEJL: `function public.red_apply_reimport_legacy_migration(...) does not exist`)**

- [ ] **Step 3: Implementér writeren i `schema.sql`**

Indsæt efter `red_apply_reimport_person_create`:

```sql
-- #166 149b: bind ét eksisterende legacy-narrativ til sin source record gennem #152's
-- eventkontrakt og luk den grandfathered stream. Editionsneutral; identitetsevidensen er
-- person_external_id (spec §5, valg A: ingen placements).
CREATE FUNCTION private.migrate_legacy_narrative_record(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,private,extensions AS $$
DECLARE
  v_batch private.reimport_batch%ROWTYPE; v_auth private.reimport_authorization%ROWTYPE; v_profile private.reimport_writer_profile%ROWTYPE;
  v_actor uuid; v_actor_name text; v_run uuid; v_payload_sha text;
  v_record private.source_record%ROWTYPE; v_occurrence private.source_record_occurrence%ROWTYPE;
  v_anchor_count bigint; v_mention_count bigint; v_mention_id uuid;
  v_person_id bigint; v_narrative_id bigint; v_disposition text; v_narrative public.narrative%ROWTYPE;
  v_person_levende boolean; v_person_private boolean; v_person_staged boolean; v_publishable boolean;
  v_legacy private.narrative_legacy_publication%ROWTYPE; v_legacy_editor jsonb;
  v_legacy_before jsonb; v_legacy_before_sha text; v_legacy_after jsonb; v_legacy_after_sha text; v_legacy_event_id uuid;
  v_persona uuid; v_identity_version integer;
  v_initial jsonb; v_initial_sha text; v_before jsonb; v_before_sha text; v_after jsonb; v_after_sha text;
  v_labels jsonb; v_binding_id uuid; v_change_set_id bigint; v_stream_version integer;
  v_draft_event_id uuid; v_published_event_id uuid; v_editor jsonb; v_expected_status text;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  IF public.narrative_record_contract_version()<>2 THEN RAISE EXCEPTION 'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED'; END IF;
  v_batch:=private.require_reimport_open_batch(p_batch_id);
  v_actor:=private.require_reimport_writer_editor();
  PERFORM private.lock_reimport_writer(v_batch.source_id,v_batch.profile_id);
  SELECT * INTO v_auth FROM private.reimport_authorization WHERE id=v_batch.authorization_id;
  SELECT * INTO v_profile FROM private.reimport_writer_profile WHERE source_id=v_batch.source_id AND profile_id=v_batch.profile_id AND profile_sha256=v_batch.profile_sha256;
  IF NOT FOUND OR v_auth.source_id<>v_batch.source_id OR v_auth.profile_id<>v_batch.profile_id OR v_auth.profile_sha256<>v_batch.profile_sha256
     OR NOT v_auth.authorized_elements ? p_element_id OR v_auth.authorized_elements->p_element_id IS DISTINCT FROM p_payload THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED';
  END IF;
  IF jsonb_typeof(p_payload)<>'object'
     OR ARRAY(SELECT key FROM jsonb_object_keys(p_payload) key ORDER BY key)
        <> ARRAY['disposition','legacy_baseline_sha256','legacy_publication_ref','narrative_id','narrative_text_sha256','normalized_text_sha256','occurrence_verbatim_sha256','person_id','persona_key','source_id','source_record_key']
     OR p_element_id<>'legacy-migration:'||coalesce(p_payload->>'source_record_key','')
     OR (p_payload->>'source_id')::bigint IS DISTINCT FROM v_batch.source_id
     OR coalesce(p_payload->>'disposition','') NOT IN ('bound_published','bound_draft')
     OR jsonb_typeof(p_payload->'person_id')<>'number' OR jsonb_typeof(p_payload->'narrative_id')<>'number'
     OR coalesce(p_payload->>'narrative_text_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(p_payload->>'occurrence_verbatim_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(p_payload->>'normalized_text_sha256','') !~ '^[0-9a-f]{64}$'
     OR nullif(btrim(coalesce(p_payload->>'persona_key','')),'') IS NULL
     OR (p_payload->>'disposition'='bound_published') <> (jsonb_typeof(p_payload->'legacy_publication_ref')='string')
     OR (p_payload->>'disposition'='bound_published') <> (jsonb_typeof(p_payload->'legacy_baseline_sha256')='string') THEN
    RAISE EXCEPTION 'LEGACY_MIGRATION_PAYLOAD_INVALID';
  END IF;
  v_disposition:=p_payload->>'disposition'; v_person_id:=(p_payload->>'person_id')::bigint; v_narrative_id:=(p_payload->>'narrative_id')::bigint;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'NARRATIVE_RECORD_FOREIGN_CHANGE_SET'; END IF;

  -- Låserække (spec §6.4): change_set → source_record → narrativ → ledger/events.
  LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;
  SELECT * INTO v_record FROM private.source_record WHERE source_id=v_batch.source_id AND record_key=p_payload->>'source_record_key' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_MIGRATION_RECORD_MISSING'; END IF;
  SELECT count(*) INTO v_anchor_count FROM private.source_record_anchor_current a WHERE a.source_record_id=v_record.id AND a.decision_status='accepted';
  IF v_anchor_count<>1 THEN RAISE EXCEPTION 'LEGACY_MIGRATION_ANCHOR_AMBIGUOUS'; END IF;
  SELECT o.* INTO v_occurrence FROM private.source_record_anchor_current a JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
   WHERE a.source_record_id=v_record.id AND a.decision_status='accepted';
  IF encode(digest(v_occurrence.verbatim_text,'sha256'),'hex')<>p_payload->>'occurrence_verbatim_sha256' THEN RAISE EXCEPTION 'LEGACY_MIGRATION_OCCURRENCE_TEXT_DRIFT'; END IF;
  SELECT count(*),min(m.id) INTO v_mention_count,v_mention_id FROM private.source_observation ob JOIN private.source_mention m ON m.observation_id=ob.id WHERE ob.occurrence_id=v_occurrence.id;
  IF v_mention_count<>1 THEN RAISE EXCEPTION 'LEGACY_MIGRATION_MENTION_AMBIGUOUS'; END IF;
  IF (SELECT count(*) FROM public.person_external_id x WHERE x.source_id=v_batch.source_id AND x.record_key=v_record.record_key)<>1
     OR NOT EXISTS (SELECT 1 FROM public.person_external_id x WHERE x.source_id=v_batch.source_id AND x.record_key=v_record.record_key AND x.person_id=v_person_id)
     OR (SELECT count(*) FROM public.person_external_id x WHERE x.source_id=v_batch.source_id AND x.person_id=v_person_id)<>1 THEN
    RAISE EXCEPTION 'LEGACY_MIGRATION_IDENTITY_AMBIGUOUS';
  END IF;
  IF (SELECT count(*) FROM public.narrative n WHERE n.subjekt_type='person' AND n.subjekt_id=v_person_id AND n.source_id=v_batch.source_id)<>1 THEN
    RAISE EXCEPTION 'LEGACY_MIGRATION_NARRATIVE_AMBIGUOUS';
  END IF;
  SELECT * INTO v_narrative FROM public.narrative WHERE id=v_narrative_id AND subjekt_type='person' AND subjekt_id=v_person_id AND source_id=v_batch.source_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_MIGRATION_NARRATIVE_AMBIGUOUS'; END IF;
  IF EXISTS (SELECT 1 FROM private.narrative_record_publication b WHERE b.narrative_id=v_narrative_id) THEN RAISE EXCEPTION 'LEGACY_MIGRATION_ALREADY_BOUND'; END IF;
  IF encode(digest(v_narrative.tekst,'sha256'),'hex')<>p_payload->>'narrative_text_sha256' THEN RAISE EXCEPTION 'LEGACY_MIGRATION_NARRATIVE_TEXT_DRIFT'; END IF;
  SELECT levende,coalesce(privat,false),coalesce(staged,false) INTO v_person_levende,v_person_private,v_person_staged FROM public.person WHERE id=v_person_id;
  v_publishable:=v_person_levende IS FALSE AND NOT v_person_private AND NOT v_person_staged AND NOT coalesce(v_narrative.privat,false);
  SELECT * INTO v_legacy FROM private.narrative_legacy_publication WHERE narrative_id=v_narrative_id;
  IF v_disposition='bound_published' THEN
    IF NOT FOUND OR NOT v_publishable OR v_legacy.legacy_publication_ref<>(p_payload->>'legacy_publication_ref')::uuid
       OR v_legacy.status<>'grandfathered_publication' OR v_legacy.baseline_sha256<>p_payload->>'legacy_baseline_sha256' THEN
      RAISE EXCEPTION 'LEGACY_MIGRATION_LEDGER_INCONSISTENT';
    END IF;
    v_legacy_editor:=private.narrative_legacy_state(v_legacy.legacy_publication_ref,true);
    IF NOT coalesce((v_legacy_editor->>'baseline_matches')::boolean,false) OR v_legacy_editor->>'publication_status'<>'published' THEN
      RAISE EXCEPTION 'NARRATIVE_LEGACY_BASELINE_DRIFT';
    END IF;
  ELSE
    IF FOUND OR v_publishable THEN RAISE EXCEPTION 'LEGACY_MIGRATION_LEDGER_INCONSISTENT'; END IF;
  END IF;

  -- Identitetsledger (spec §5): run, persona, mention, accepteret identitet.
  v_payload_sha:=private.reimport_canonical_json_sha256(p_payload);
  INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_batch.source_id,(v_profile.writer_config->>'run_key_prefix')||v_batch.manifest_sha256,v_profile.writer_config->>'schema_version',v_profile.writer_config->>'extractor_version',v_profile.profile_version,v_batch.manifest_sha256,jsonb_build_object('batch_id',p_batch_id,'profile_sha256',v_batch.profile_sha256))
  ON CONFLICT(source_id,run_key) DO NOTHING;
  SELECT id INTO v_run FROM private.extraction_run WHERE source_id=v_batch.source_id AND run_key=(v_profile.writer_config->>'run_key_prefix')||v_batch.manifest_sha256;
  IF EXISTS (SELECT 1 FROM private.source_persona WHERE source_id=v_batch.source_id AND persona_key=p_payload->>'persona_key') THEN RAISE EXCEPTION 'LEGACY_MIGRATION_PERSONA_EXISTS'; END IF;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id) VALUES(v_batch.source_id,p_payload->>'persona_key',v_run) RETURNING id INTO v_persona;
  INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES(v_persona,v_mention_id,'primary',1);
  v_identity_version:=public.red_decide_source_persona_identity(v_persona,v_person_id,0,'accepted',jsonb_build_object(
    'authority','person_external_id',
    'person_external_id',jsonb_build_object('person_id',v_person_id,'source_id',v_batch.source_id,'record_key',v_record.record_key),
    'batch_id',p_batch_id,'element_id',p_element_id,'profile_sha256',v_batch.profile_sha256,'authorized_payload_sha256',v_payload_sha));

  v_initial:=private.narrative_publication_state(v_person_id,v_batch.source_id,v_record.record_key);
  v_initial_sha:=encode(digest(v_initial::text,'sha256'),'hex');
  -- Førtilstanden accepteres, når den enten er eligible (fremtidige placements) eller
  -- blokeret ALENE af manglende identitet (valg A). Manglende anker eller konflikt er stop.
  IF v_initial->>'publication_status'<>'none' OR jsonb_typeof(v_initial->'binding')<>'null'
     OR NOT ((v_initial #>> '{authority,eligibility_status}')='eligible'
             OR (v_initial #>> '{authority,blocking_reason}')='NARRATIVE_RECORD_IDENTITY_REQUIRED') THEN
    RAISE EXCEPTION 'LEGACY_MIGRATION_PRESTATE_INVALID';
  END IF;
  v_labels:=v_initial->'labels';
  SELECT coalesce(nullif(btrim(navn),''),nullif(btrim(email),''),v_actor::text) INTO v_actor_name FROM public.profiles WHERE id=v_actor;
  v_actor_name:=coalesce(v_actor_name,v_actor::text);
  v_change_set_id:=public.begin_change_set('narrative_record_legacy_migrated',
    format('Legacy-migration: person %s, source %s, record %s, batch %s',v_person_id,v_batch.source_id,v_record.record_key,p_batch_id),'person',v_person_id);

  -- Legacy-stream lukkes først (kun bound_published).
  IF v_disposition='bound_published' THEN
    v_legacy_before:=v_legacy_editor->'publication_state'; v_legacy_before_sha:=v_legacy_editor->>'publication_state_sha256';
    UPDATE private.narrative_legacy_publication SET status='migrated' WHERE legacy_publication_ref=v_legacy.legacy_publication_ref AND status='grandfathered_publication';
    IF NOT FOUND THEN RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_PROJECTION_MISMATCH'; END IF;
    v_legacy_after:=private.narrative_legacy_publication_state(v_legacy.legacy_publication_ref);
    v_legacy_after_sha:=encode(digest(v_legacy_after::text,'sha256'),'hex');
    SELECT coalesce(max(stream_version),0)+1 INTO v_stream_version FROM private.narrative_publication_event WHERE stream_ref=v_legacy.legacy_publication_ref;
    INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,decided_by_name)
    VALUES(v_change_set_id,v_legacy.legacy_publication_ref,v_stream_version,'legacy_migrated',v_narrative_id,v_batch.source_id,v_legacy.legacy_publication_ref,
      format('Legacy-migration til source record %s (batch %s)',v_record.record_key,p_batch_id),v_legacy_before,v_legacy_after,v_legacy_before_sha,v_legacy_after_sha,v_actor,v_actor_name)
    RETURNING id INTO v_legacy_event_id;
    UPDATE private.narrative_legacy_publication SET latest_event_id=v_legacy_event_id WHERE legacy_publication_ref=v_legacy.legacy_publication_ref;
    v_legacy_editor:=private.narrative_legacy_state(v_legacy.legacy_publication_ref,false);
    IF v_legacy_editor->>'latest_event_id' IS DISTINCT FROM v_legacy_event_id::text OR v_legacy_editor->>'ledger_status' IS DISTINCT FROM 'migrated' THEN
      RAISE EXCEPTION 'LEGACY_MIGRATION_EVENT_APPEND_MISMATCH';
    END IF;
  END IF;

  -- Record-stream: draft_created, derefter published ved bound_published.
  v_before:=v_initial; v_before_sha:=v_initial_sha;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
  VALUES(v_narrative_id,v_record.id,v_labels->>'record_label',v_labels->>'citation_label','draft') RETURNING id INTO v_binding_id;
  v_after:=private.narrative_publication_state(v_person_id,v_batch.source_id,v_record.record_key);
  v_after_sha:=encode(digest(v_after::text,'sha256'),'hex');
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,source_id,source_record_id,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,decided_by_name)
  VALUES(v_change_set_id,v_binding_id,1,'draft_created',v_binding_id,v_narrative_id,v_batch.source_id,v_record.id,
    format('Legacy-migration: record-binding fra person_external_id (batch %s)',p_batch_id),v_before,v_after,v_before_sha,v_after_sha,v_actor,v_actor_name)
  RETURNING id INTO v_draft_event_id;
  v_expected_status:='draft';
  IF v_disposition='bound_published' THEN
    v_before:=v_after; v_before_sha:=v_after_sha;
    UPDATE private.narrative_record_publication SET status='published' WHERE id=v_binding_id AND status='draft';
    IF NOT FOUND THEN RAISE EXCEPTION 'NARRATIVE_RECORD_PROJECTION_MISMATCH'; END IF;
    v_after:=private.narrative_publication_state(v_person_id,v_batch.source_id,v_record.record_key);
    v_after_sha:=encode(digest(v_after::text,'sha256'),'hex');
    INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,source_id,source_record_id,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,decided_by_name)
    VALUES(v_change_set_id,v_binding_id,2,'published',v_binding_id,v_narrative_id,v_batch.source_id,v_record.id,
      format('Legacy-migration: publiceret record-bundet narrativ (batch %s)',p_batch_id),v_before,v_after,v_before_sha,v_after_sha,v_actor,v_actor_name)
    RETURNING id INTO v_published_event_id;
    v_expected_status:='published';
  END IF;

  v_editor:=private.narrative_record_state(v_person_id,v_batch.source_id,v_record.record_key,false);
  IF v_editor->>'latest_event_id' IS DISTINCT FROM coalesce(v_published_event_id,v_draft_event_id)::text
     OR v_editor->>'publication_state_sha256' IS DISTINCT FROM v_after_sha
     OR v_editor->'publication_state' IS DISTINCT FROM v_after
     OR v_editor->>'publication_status' IS DISTINCT FROM v_expected_status
     OR v_editor->>'eligibility_status' IS DISTINCT FROM 'eligible'
     OR v_after #>> '{authority,kind}' IS DISTINCT FROM 'existing_exact_binding' THEN
    RAISE EXCEPTION 'LEGACY_MIGRATION_EVENT_APPEND_MISMATCH';
  END IF;
  IF (v_disposition='bound_published')<>public.person_daa_narrative_publication_allowed(v_narrative_id) THEN
    RAISE EXCEPTION 'LEGACY_MIGRATION_PUBLICATION_GATE_MISMATCH';
  END IF;

  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,before_sha256,after_sha256)
  VALUES(p_batch_id,p_element_id,'legacy_migration',v_record.record_key,v_person_id,
    p_payload||jsonb_build_object('authorized_payload_sha256',v_payload_sha,'persona_id',v_persona,'identity_version',v_identity_version,
      'legacy_event_id',v_legacy_event_id,'binding_id',v_binding_id,'draft_event_id',v_draft_event_id,'published_event_id',v_published_event_id,
      'publication_state_sha256',v_after_sha,'state_sha256',v_editor->>'state_sha256'),
    v_initial_sha,v_after_sha);
  RETURN jsonb_build_object('persona_id',v_persona,'identity_version',v_identity_version,'legacy_event_id',v_legacy_event_id,
    'binding_id',v_binding_id,'draft_event_id',v_draft_event_id,'published_event_id',v_published_event_id,
    'publication_state_sha256',v_after_sha,'state_sha256',v_editor->>'state_sha256');
END $$;

CREATE FUNCTION public.red_apply_reimport_legacy_migration(p_batch_id uuid,p_element_id text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  RETURN private.migrate_legacy_narrative_record(p_batch_id,p_element_id,p_payload);
END $$;
```

ACL i `schema.sql:3177-3182`: tilføj `private.migrate_legacy_narrative_record(uuid,text,jsonb)` til REVOKE-listen (3177), `public.red_apply_reimport_legacy_migration(uuid,text,jsonb)` til REVOKE-listen (3178) og til GRANT `authenticated` (3180). Samme i `db-rls.sql:1176-1192`.

- [ ] **Step 4: Spejl i `db-migrations.sql`** (`CREATE OR REPLACE FUNCTION` for begge + REVOKE/GRANT-linjer i 149b-blokken). Bemærk: #154-blokkens `$public_red_revoke$` løber over ALLE `public.red_*` og fejler på den nye RPC, indtil Task 5 klassificerer den — kør derfor Task 5's array-ændringer sammen med denne task, hvis migrationen skal køres før Task 5 er færdig.

- [ ] **Step 5: Kør testen grøn** (Task 1 Step 2-kommandoer). Forventet: `task3 happy path OK`, `task3 rejections OK`.

- [ ] **Step 6: Commit**: `feat(db): legacy-migration-writer binder eksisterende narrativ og lukker grandfathered stream (149b)`

### Task 4: `legacy_migrated`-gren i den dedikerede reversal

**Files:**
- Modify: `schema.sql:11745-12073` (`private.reverse_narrative_publication_event`), `db-migrations.sql` (149b-blok, `CREATE OR REPLACE`)
- Modify: `tests/sql/test-reimport-legacy-migration.sql`

**Interfaces:**
- Produces: `public.red_fortryd_person_narrative_publication_event(p_event_id uuid,p_expected_state_sha256 text)` accepterer nu et `legacy_migrated`-event som target; ny fejlkode `NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE`.

- [ ] **Step 1: Fejlende test — tre-trins reversal**

```sql
DO $task4_reversal$
DECLARE fx jsonb; r jsonb; v_state jsonb; v_res jsonb; v_status text; v_err text; v_ok boolean;
BEGIN
  fx:=pg_temp.task3_fixture('T4',false);
  r:=pg_temp.task3_migrate(fx,'bound_published','t4');
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','authenticated',true);
  -- (a) legacy_migrated kan ikke fortrydes, mens bindingen er aktiv
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  v_ok:=false;
  BEGIN
    PERFORM public.red_fortryd_person_narrative_publication_event((r->>'legacy_event_id')::uuid,v_state->>'state_sha256');
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE%'; v_err:=SQLERRM; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK4_EXPECTED_BINDING_ACTIVE got %',v_err; END IF;
  -- (b) published → draft
  v_state:=private.narrative_record_state((fx->>'person_id')::bigint,(fx->>'source_id')::bigint,fx->>'record_key',false);
  v_res:=public.red_fortryd_person_narrative_publication_event((r->>'published_event_id')::uuid,v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  IF v_res->>'status'<>'draft' THEN RAISE EXCEPTION 'TASK4_STEP_B: %',v_res->>'status'; END IF;
  -- (c) draft_created → withdrawn
  v_state:=private.narrative_record_state((fx->>'person_id')::bigint,(fx->>'source_id')::bigint,fx->>'record_key',false);
  v_res:=public.red_fortryd_person_narrative_publication_event((r->>'draft_event_id')::uuid,v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  IF v_res->>'status'<>'withdrawn' THEN RAISE EXCEPTION 'TASK4_STEP_C: %',v_res->>'status'; END IF;
  -- (d) legacy_migrated → ledger tilbage til grandfathered_publication
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  v_res:=public.red_fortryd_person_narrative_publication_event((r->>'legacy_event_id')::uuid,v_state->>'state_sha256');
  PERFORM set_config('app.change_set_id','',true);
  SELECT status INTO v_status FROM private.narrative_legacy_publication WHERE legacy_publication_ref=(fx->>'legacy_publication_ref')::uuid;
  IF v_status<>'grandfathered_publication' THEN RAISE EXCEPTION 'TASK4_STEP_D: %',v_status; END IF;
  IF NOT public.person_daa_narrative_publication_allowed((fx->>'narrative_id')::bigint) THEN RAISE EXCEPTION 'TASK4_LEGACY_NOT_PUBLIC_AGAIN'; END IF;
  IF (SELECT count(*) FROM public.public_person_bio_source_versions_v2(ARRAY[(fx->>'person_id')::bigint]) WHERE provenance_kind='legacy_narrative')<>1 THEN RAISE EXCEPTION 'TASK4_LEGACY_ROW_MISSING'; END IF;
  -- (e) red_tilbagetraek_legacy_narrative på en migreret række afvises
  fx:=pg_temp.task3_fixture('T4E',false); r:=pg_temp.task3_migrate(fx,'bound_published','t4e');
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_state:=private.narrative_legacy_state((fx->>'legacy_publication_ref')::uuid,false);
  v_ok:=false;
  BEGIN
    PERFORM public.red_tilbagetraek_legacy_narrative((fx->>'legacy_publication_ref')::uuid,v_state->>'state_sha256','test');
  EXCEPTION WHEN OTHERS THEN v_ok:=SQLERRM LIKE 'NARRATIVE_LEGACY_PUBLICATION_TRANSITION_INVALID%'; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'TASK4_WITHDRAW_MIGRATED_ACCEPTED'; END IF;
  RESET role;
  RAISE NOTICE 'task4 reversal OK';
END $task4_reversal$;
```

- [ ] **Step 2: Kør (forventet FEJL: `NARRATIVE_PUBLICATION_EVENT_NOT_REVERSIBLE` i (a))**

- [ ] **Step 3: Implementér grenen i `reverse_narrative_publication_event`**

1. Den reversible mængde (linjen `ELSIF v_target.event_type NOT IN ('draft_created', … ,'legacy_withdrawn')`): tilføj `'legacy_migrated'`.
2. `v_would_publish := v_target.event_type IN ('published_revision','revalidated','withdrawn','legacy_withdrawn','legacy_migrated')`.
3. Efter `legacy_withdrawn`-baseline-tjekket, tilføj:

```sql
  IF v_target.event_type='legacy_migrated' THEN
    IF v_before_editor->>'ledger_status' IS DISTINCT FROM 'migrated'
       OR NOT coalesce((v_before_editor->>'baseline_matches')::boolean,false) THEN
      RAISE EXCEPTION 'NARRATIVE_LEGACY_BASELINE_DRIFT';
    END IF;
    IF EXISTS (
      SELECT 1 FROM private.narrative_record_publication binding
       WHERE binding.narrative_id=v_target.narrative_id
         AND binding.status IN ('draft','published')
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE';
    END IF;
  END IF;
```

4. Projektionsgrenen: udvid `IF v_target.event_type='legacy_withdrawn' THEN UPDATE … SET status='grandfathered_publication' WHERE … AND status='withdrawn'` til:

```sql
  IF v_target.event_type IN ('legacy_withdrawn','legacy_migrated') THEN
    UPDATE private.narrative_legacy_publication legacy
       SET status='grandfathered_publication'
     WHERE legacy.legacy_publication_ref=v_target.legacy_publication_ref
       AND legacy.status=CASE v_target.event_type WHEN 'legacy_withdrawn' THEN 'withdrawn' ELSE 'migrated' END;
    IF NOT FOUND THEN RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_PROJECTION_MISMATCH'; END IF;
```

Restore-mismatch-tjekket (`v_target.event_type NOT IN ('draft_created','revalidated') AND after IS DISTINCT FROM before_state`) gælder uændret: `narrative_legacy_publication_state` indeholder ikke ledgerstatus, så after = before, når narrativ/policy er uændret.

- [ ] **Step 4: Spejl i `db-migrations.sql`.** Kør migrations-paritet.

- [ ] **Step 5: Kør testen grøn + `tests/sql/test-narrative-record-contract.sql` (#152's reversal-tests stadig grønne).**

- [ ] **Step 6: Commit**: `feat(db): dedikeret reversal kan fortryde legacy_migrated når record-bindingen er trukket tilbage`

### Task 5: ACL-klassifikation, inventarer, editionskatalog og CI

**Files:**
- Modify: `db-migrations.sql` (#154-arrays: `v_authenticated` += `'public.red_apply_reimport_legacy_migration(uuid,text,jsonb)'::regprocedure`), `db-verify.sql` (samme array i `$public_red_acl_verify$`)
- Modify: `tests/sql/test-reimport-writer.sql:15-25` (RPC-inventar) og `:100-130` (ACL-paritet: `private.migrate_legacy_narrative_record(uuid,text,jsonb)` forventet hverken authenticated eller service_role; `public.red_apply_reimport_legacy_migration(uuid,text,jsonb)` forventet authenticated=true, service_role=false), `tests/sql/inspect-reimport-writer-catalog.sql:15-30` (begge navne), `tests/sql/test-1939-v50-production-writer.sql:29,66` (hvis inventaret er en lukket liste — læs testen; tilføj kun hvis den assert'er fuld lighed)
- Modify: `.github/workflows/ci.yml` (i jobbet »DAA 1939 v50 writer«, efter trinnet »Source evidence writer integration«, tilføj)

```yaml
      - name: Legacy migration writer SQL (149b)
        env: {PGPASSWORD: postgres}
        run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-legacy-migration.sql
```

- [ ] **Step 1: Kør hele gaten lokalt (forventet: `EVIDENCE_PUBLIC_RED_ACL_UNCLASSIFIED` fra `db-migrations.sql`, indtil arrays er rettet)**

```bash
$PG/dropdb --if-exists daa149b_mig; $PG/createdb daa149b_mig
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-migrations.sql db-rls.sql db-verify.sql; do
  PGDATABASE=daa149b_mig $PG/psql -X -v ON_ERROR_STOP=1 -f "$f" > /dev/null || { echo "FAIL $f"; break; }; done
PGDATABASE=daa149b_mig $PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-edition-catalog.sql
PGDATABASE=daa149b_mig $PG/psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
```

- [ ] **Step 2: Ret arrays og inventarer; kør Step 1 igen (forventet exit 0, ingen `REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT`)**

- [ ] **Step 3: Kør writer-jobbets fulde lokale ækvivalent** (Task 1 Step 2-basen + `test-reimport-writer.sql`, `test-reimport-legacy-migration.sql`, `test-reimport-name-completion.sql`, `Rscript tests/integration/test-reimport-source-evidence.R`, `Rscript tests/integration/test-reimport-writer-locking.R`) og `Rscript run-tests.R`.

- [ ] **Step 4: `get_advisors`** — Supabase-MCP peger på et andet projekt i denne opsætning (memory); kør i stedet `tests/sql/run-db-verify-disposable.sql` (Step 1) og notér i commit-beskeden, at advisors skal køres ved prod-deploy.

- [ ] **Step 5: Commit**: `chore(db): klassificér legacy-migration-RPC i ACL, inventarer og CI (149b)`

---

# Leverance 2 — manifest, gateway og preview (én dag; »én rigtig kørsel« = R-integrationstesten grøn mod `writer_1939`-v2-basen + byggeren kørt på den rigtige eksport fra `daa149b_inv_20260903`-restore migreret til v2)

### Task 6: R-validator, expected_counts, dispatch og gateway

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R:19-66` (validator, payloads, expected_counts), `:158-170` (dispatch), `:238-246` (gateway)
- Modify: `.claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R:14-23` (`preview_authorization_request`), `:99-120` (`build_reimport_preview`)
- Create: `tests/testthat/test-reimport-writer-legacy-migration.R`

**Interfaces:**
- Consumes: `public.red_apply_reimport_legacy_migration(uuid,text,jsonb)` (Task 3).
- Produces: `validate_reimport_manifest(manifest)` accepterer `expected_counts` med nøglerne `source_evidence, person_creates, canonical_delta` **eller** samme plus `legacy_migrations`; top-niveau-nøglen `dispositions` er valgfri (liste); `dependency_class %in% c("source_evidence","person_create","legacy_migration")`. `reimport_writer_expected_counts(manifest)` returnerer to eller tre nøgler. Gateway-operation `legacy_migration`. Preview får feltet `legacy_before_counts` når `legacy_migrations > 0`.

- [ ] **Step 1: Fejlende enhedstests**

```r
# tests/testthat/test-reimport-writer-legacy-migration.R
root <- normalizePath(file.path(testthat::test_path(), "../.."))
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"))
sha <- function(ch) paste(rep(ch, 64L), collapse = "")
op <- function(key) list(
  element_id = paste0("legacy-migration:", key), dependency_class = "legacy_migration",
  source_record_key = key, source_id = 7L, person_id = 11L, narrative_id = 21L,
  disposition = "bound_published", narrative_text_sha256 = sha("1"),
  occurrence_verbatim_sha256 = sha("1"), normalized_text_sha256 = sha("2"),
  legacy_publication_ref = "11111111-1111-4111-8111-111111111111",
  legacy_baseline_sha256 = sha("3"), persona_key = key)
manifest <- function(...) list(
  manifest_content_sha256 = sha("a"),
  source = list(id = 7L, profile_id = "fixture-legacy-migration-v1", profile_sha256 = sha("b")),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L, legacy_migrations = 1L),
  dispositions = list(list(record_key = "K1", disposition = "bound_published")),
  operations = list(op("K1")), ...)

test_that("tre-nøgle-manifest med legacy_migration valideres", {
  expect_silent(validate_reimport_manifest(manifest()))
  expect_identical(reimport_writer_expected_counts(manifest()),
    list(person_creates = 0L, source_evidence = 0L, legacy_migrations = 1L))
})
test_that("to-nøgle-manifest (149a) valideres stadig", {
  m <- manifest(); m$expected_counts$legacy_migrations <- NULL; m$dispositions <- NULL
  m$operations <- list(); m$expected_counts$source_evidence <- 0L
  expect_silent(validate_reimport_manifest(m))
  expect_identical(names(reimport_writer_expected_counts(m)), c("person_creates", "source_evidence"))
})
test_that("legacy_migrations skal matche antallet af elementer", {
  m <- manifest(); m$expected_counts$legacy_migrations <- 2L
  expect_error(validate_reimport_manifest(m), "REIMPORT_MANIFEST_COUNTS_INVALID")
})
test_that("ukendt dependency_class afvises", {
  m <- manifest(); m$operations[[1]]$dependency_class <- "legacy_migrate"
  expect_error(validate_reimport_manifest(m), "REIMPORT_MANIFEST_OPERATIONS_INVALID")
})
test_that("gateway dispatcher legacy_migration og nulstiller change set", {
  calls <- list()
  gateway <- list(call = function(name, ...) {
    calls[[length(calls) + 1L]] <<- name
    switch(name,
      preflight = list(database_identity = "db", actor_id = "11111111-1111-4111-8111-111111111111",
        transaction_read_only = "off", source = manifest()$source, locked_payload_count = 1L),
      authorize = list(id = "22222222-2222-4222-8222-222222222222"),
      preflight_authorization = list(authorization_id = "22222222-2222-4222-8222-222222222222",
        database_identity = "db", source = manifest()$source, manifest_sha256 = sha("a"), preview_sha256 = sha("e")),
      begin_batch = "33333333-3333-4333-8333-333333333333",
      batch_result = list(batch_id = "33333333-3333-4333-8333-333333333333", status = "open", replayed = FALSE, person_id_map = list()),
      legacy_migration = list(binding_id = "x"),
      finalize = list(status = "finalized"),
      invisible(NULL))
  })
  result <- execute_reimport(manifest(), sha("e"), "dry-run", gateway)
  expect_identical(result$status, "finalized")
  expect_true("legacy_migration" %in% calls)
})
```

- [ ] **Step 2: Kør (forventet FAIL)**: `Rscript -e 'testthat::test_file("tests/testthat/test-reimport-writer-legacy-migration.R")'`

- [ ] **Step 3: Implementér i `apply_reimport_helpers.R`**

`validate_reimport_manifest`:

```r
  required <- c("manifest_content_sha256", "source", "expected_counts", "operations")
  optional <- "dispositions"
  if (!is.list(manifest) || !all(required %in% names(manifest)) ||
      !all(names(manifest) %in% c(required, optional)) || anyDuplicated(names(manifest)) || ...
  count_names <- names(manifest$expected_counts)
  base_counts <- c("source_evidence", "person_creates", "canonical_delta")
  if (!is.list(manifest$expected_counts) ||
      !(identical(sort(count_names), sort(base_counts)) ||
        identical(sort(count_names), sort(c(base_counts, "legacy_migrations")))) || ...
  ... dependency_class %in% c("source_evidence", "person_create", "legacy_migration") ...
  counts <- c(source_evidence = ..., person_creates = ..., canonical_delta = 0L)
  if ("legacy_migrations" %in% count_names)
    counts[["legacy_migrations"]] <- sum(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "legacy_migration"), logical(1)))
  else if (any(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "legacy_migration"), logical(1))))
    stop_reimport("REIMPORT_MANIFEST_COUNTS_INVALID")
  if (!is.null(manifest$dispositions) && !is.list(manifest$dispositions))
    stop_reimport("REIMPORT_MANIFEST_DISPOSITIONS_INVALID")
```

`reimport_writer_expected_counts`: `manifest$expected_counts[intersect(c("person_creates", "source_evidence", "legacy_migrations"), names(manifest$expected_counts))]`.

`execute_reimport`-løkken:

```r
      if (identical(operation$dependency_class, "source_evidence")) {
        call("source_evidence", batch_id, operation$element_id, payload)
      } else if (identical(operation$dependency_class, "legacy_migration")) {
        call("legacy_migration", batch_id, operation$element_id, payload)
      } else {
        person_id_map[[operation$source_record_key]] <- call("person_create", batch_id, operation$element_id, payload)
      }
```

Gateway (`new_reimport_dbi_gateway`), ny gren efter `person_create`:

```r
      legacy_migration = {
        result <- query("SELECT public.red_apply_reimport_legacy_migration($1,$2,$3::jsonb)::text AS value", list(
          args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))$value[[1L]]
        query("SELECT set_config('app.change_set_id','',true)")
        jsonlite::fromJSON(result, simplifyVector = FALSE)
      },
```

Preview: `preview_authorization_request` beholder `person_creates == 0` og `canonical_delta == 0`. `build_reimport_preview` tilføjer, når `isTRUE(manifest$expected_counts$legacy_migrations > 0L)`, feltet:

```r
    legacy_before_counts = preview_legacy_before_counts(query, manifest),
```

med

```r
preview_legacy_before_counts <- function(query, manifest) {
  counts <- query(paste(
    "SELECT (SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.source_id=$1 AND l.status='grandfathered_publication') AS grandfathered,",
    "(SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.source_id=$1 AND l.status='migrated') AS migrated,",
    "(SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.source_id=$1 AND l.status='withdrawn') AS withdrawn,",
    "(SELECT count(*) FROM private.narrative_record_publication b JOIN private.source_record r ON r.id=b.source_record_id WHERE r.source_id=$1 AND b.status='published') AS bound_published,",
    "(SELECT count(*) FROM private.narrative_record_publication b JOIN private.source_record r ON r.id=b.source_record_id WHERE r.source_id=$1 AND b.status='draft') AS bound_draft,",
    "(SELECT count(*) FROM private.source_persona p WHERE p.source_id=$1) AS personas,",
    "(SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id WHERE p.source_id=$1 AND i.decision_status='accepted') AS identities,",
    "(SELECT count(*) FROM public.narrative n WHERE n.source_id=$1 AND n.subjekt_type='person') AS narratives"),
    list(manifest$source$id))
  lapply(as.list(counts[1L, ]), as.integer)
}
```

samt en ledger-dækning: for hvert `bound_published`-element skal `legacy_publication_ref` findes med status `grandfathered_publication` og samme `baseline_sha256`; for hvert `bound_draft`-element må der ikke findes en ledger-række. Afvigelse → `PREVIEW_LEGACY_LEDGER_INCONSISTENT` (preview stopper; manifestet er forældet).

- [ ] **Step 4: Kør enhedstests grønne + `Rscript run-tests.R` (hele suiten).**

- [ ] **Step 5: Commit**: `feat(genimport): R-gateway og preview for legacy_migration-elementer`

### Task 7: Læse-kun kandidateksport (R)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_legacy_migration_candidates.R`
- Create: `.claude/skills/daa-extract/scripts/export_legacy_migration_candidates_helpers.R`
- Create: `tests/testthat/test-export-legacy-migration-candidates.R` (SQL-tekst og stiafvisning; ingen DB)

**Interfaces:**
- Produces: `Rscript export_legacy_migration_candidates.R --source-id N --output-dir <abs 0700-mappe>` skriver `legacy-migration-candidates-v1.json` (uden tekst) og `legacy-migration-texts-v1.json` (0600; `{record_key: {narrative_text, occurrence_text}}`). Kandidat-post: `record_key, person_id, narrative_id, person_levende (bool|null), person_privat, person_staged, narrative_privat, narrative_text_sha256, occurrence_verbatim_sha256, legacy_publication_ref (uuid|null), legacy_status (text|null), legacy_baseline_sha256 (text|null), persons_for_record_key (int), external_ids_for_person (int), narratives_for_person (int), already_bound (bool)`. Kørt i `REPEATABLE READ READ ONLY`; afviser `--output-dir` med en `work`-stikomponent (`OUTPUT_WORK_PATH`), relativ sti, eller mappe der ikke er 0700.

- [ ] **Step 1: Fejlende tests** (stiafvisning + at SQL-teksten indeholder `READ ONLY`, `narrative_legacy_publication`, `source_record_anchor_current`, og ikke `tekst` i kandidat-forespørgslen).

```r
root <- normalizePath(file.path(testthat::test_path(), "../.."))
source(file.path(root, ".claude/skills/daa-extract/scripts/export_legacy_migration_candidates_helpers.R"))
test_that("work-stier afvises", {
  expect_error(lmc_validate_output_dir("/tmp/work/x"), "OUTPUT_WORK_PATH")
  expect_error(lmc_validate_output_dir("relative/dir"), "OUTPUT_DIR_NOT_ABSOLUTE")
})
test_that("kandidat-SQL bærer ingen tekstkolonne", {
  expect_false(grepl("\\btekst\\b", lmc_sql$candidates))
  expect_true(grepl("verbatim_text", lmc_sql$texts))
  expect_true(grepl("narrative_legacy_publication", lmc_sql$candidates))
})
```

- [ ] **Step 2: Implementér** — `lmc_sql$candidates` (én forespørgsel pr. `person_external_id`-række for source): join `person`, `narrative` (aggregat: `count(*)`, `min(id)`), `private.source_record` → `source_record_anchor_current` (accepted) → `source_record_occurrence` (`encode(digest(verbatim_text,'sha256'),'hex')`), `LEFT JOIN private.narrative_legacy_publication`, `EXISTS narrative_record_publication`, tællere som vinduesfunktioner. `lmc_sql$texts`: samme join, men `narrative.tekst` og `occurrence.verbatim_text`. Skriv med `jsonlite::write_json(..., auto_unbox = TRUE, null = "null", digits = NA)`, `Sys.chmod(path, "600")`. Følg `export_narrative_record_cutover.R` for CLI-mønster (`--output-dir` eneste flag).

- [ ] **Step 3: Kør tests + en rigtig kørsel mod `daa149b_inv_20260903`** (basen er pre-#152, så `legacy_*` er `null` for alle — det er forventet her; den rigtige kørsel med ledger sker i Task 11). Forventet: 591 kandidater, 0 `already_bound`, `persons_for_record_key = 1` og `external_ids_for_person = 1` for alle.

- [ ] **Step 4: Commit**: `feat(genimport): læse-kun eksport af legacy-migration-kandidater`

### Task 8: Manifestbygger (Python) og profilskema

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_legacy_migration_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_legacy_migration_manifest.py`
- Modify: `.claude/skills/daa-extract/scripts/reimport_profile.py` (andet skema), `test_reimport_profile.py`
- Create: `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-legacy-migration-v1.json`
- Modify: `.github/workflows/ci.yml:103` (pytest-listen += de to nye/ændrede testfiler)

**Interfaces:**
- Consumes: `normalize_narrative_v1(raw, corpus)["text"]` fra `normalize_narrative_1939_v50.py`; Task 7's to JSON-filer; renditionsteksten (149a's `rendition.txt`, SHA `2dd5cf84…`) som corpus.
- Produces: `python3 build_legacy_migration_manifest.py --profile P --candidates C --texts T --rendition-text R --output M` → manifest `{source, expected_counts:{person_creates:0, source_evidence:0, canonical_delta:0, legacy_migrations:N}, dispositions:[{record_key, person_id, narrative_id, disposition, reason}], operations:[…], manifest_content_sha256}` — ingen tekst; operationer sorteret på `record_key`; deterministisk. Profilskema `reimport-legacy-migration-profile-v1` med lukket nøglemængde `{profile_schema_version, source_id, profile_id, profile_version, writer_config, raw_text_sha256, expected_counts:{person_creates, source_evidence, legacy_migrations}, expected_dispositions:{bound_published, bound_draft, unresolved_text, unresolved_identity}, stop_threshold:{unresolved_max_share_percent:int}}`; `load_profile()` returnerer profilen med `profile_sha256 = canonical_json_sha256(writer_config)`.

- [ ] **Step 1: Fejlende tests** (syntetiske navne):

```python
"""Syntetiske fixtures — legacy-migration-byggerens dispositioner og gates."""
import hashlib, json, pytest
import build_legacy_migration_manifest as builder

CORPUS = "### PAGE 0010 ###\nAlfa Bravo, f. 1801,\nd. 1860.\n"
def sha(s): return hashlib.sha256(s.encode("utf-8")).hexdigest()
def profile(**o):
    p = {"source_id": 7, "profile_id": "fixture-legacy-migration-v1", "profile_sha256": "b"*64,
         "raw_text_sha256": sha(CORPUS),
         "expected_counts": {"person_creates": 0, "source_evidence": 0, "legacy_migrations": 2},
         "expected_dispositions": {"bound_published": 1, "bound_draft": 1, "unresolved_text": 0, "unresolved_identity": 0},
         "stop_threshold": {"unresolved_max_share_percent": 10}}
    p.update(o); return p
def cand(key, **o):
    c = {"record_key": key, "person_id": 1, "narrative_id": 2, "person_levende": False, "person_privat": False,
         "person_staged": False, "narrative_privat": False, "narrative_text_sha256": sha("Alfa Bravo, f. 1801, d. 1860."),
         "occurrence_verbatim_sha256": sha("Alfa Bravo, f. 1801, d. 1860."), "legacy_publication_ref": "11111111-1111-4111-8111-111111111111",
         "legacy_status": "grandfathered_publication", "legacy_baseline_sha256": "3"*64, "persons_for_record_key": 1,
         "external_ids_for_person": 1, "narratives_for_person": 1, "already_bound": False}
    c.update(o); return c
def texts(key, n="Alfa Bravo, f. 1801, d. 1860.", o="Alfa Bravo, f. 1801, d. 1860."):
    return {key: {"narrative_text": n, "occurrence_text": o}}

def test_bound_published_and_draft():
    living = cand("K2", person_levende=True, legacy_publication_ref=None, legacy_status=None, legacy_baseline_sha256=None)
    m = builder.build_manifest(profile(), [cand("K1"), living], {**texts("K1"), **texts("K2")}, CORPUS)
    kinds = {d["record_key"]: d["disposition"] for d in m["dispositions"]}
    assert kinds == {"K1": "bound_published", "K2": "bound_draft"}
    assert m["expected_counts"]["legacy_migrations"] == 2
    assert [op["element_id"] for op in m["operations"]] == ["legacy-migration:K1", "legacy-migration:K2"]
    assert "narrative_text" not in json.dumps(m) and "Alfa" not in json.dumps(m)

def test_unresolved_text_is_not_an_element():
    p = profile(expected_counts={"person_creates": 0, "source_evidence": 0, "legacy_migrations": 0},
                expected_dispositions={"bound_published": 0, "bound_draft": 0, "unresolved_text": 1, "unresolved_identity": 0})
    m = builder.build_manifest(p, [cand("K1")], texts("K1", n="Alfa Bravo, f. 1801, d. 1861."), CORPUS)
    assert m["dispositions"][0]["disposition"] == "unresolved_text" and m["operations"] == []

def test_unresolved_identity():
    p = profile(expected_counts={"person_creates": 0, "source_evidence": 0, "legacy_migrations": 0},
                expected_dispositions={"bound_published": 0, "bound_draft": 0, "unresolved_text": 0, "unresolved_identity": 1})
    m = builder.build_manifest(p, [cand("K1", external_ids_for_person=2)], texts("K1"), CORPUS)
    assert m["dispositions"][0]["disposition"] == "unresolved_identity"

def test_ledger_inconsistent_stops():
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_LEDGER_INCONSISTENT"):
        builder.build_manifest(profile(), [cand("K1", legacy_status=None, legacy_publication_ref=None, legacy_baseline_sha256=None)], texts("K1"), CORPUS)

def test_stop_threshold():
    p = profile(stop_threshold={"unresolved_max_share_percent": 0})
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_STOP_THRESHOLD"):
        builder.build_manifest(p, [cand("K1")], texts("K1", n="x"), CORPUS)

def test_expected_dispositions_mismatch_stops():
    p = profile(expected_dispositions={"bound_published": 2, "bound_draft": 0, "unresolved_text": 0, "unresolved_identity": 0})
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_EXPECTED_DISPOSITIONS_MISMATCH"):
        builder.build_manifest(p, [cand("K1")], texts("K1"), CORPUS)

def test_text_hash_consistency_between_files():
    with pytest.raises(builder.BuildError, match="LEGACY_MIGRATION_TEXT_HASH_MISMATCH"):
        builder.build_manifest(profile(), [cand("K1", narrative_text_sha256="0"*64)], texts("K1"), CORPUS)

def test_deterministic():
    a = builder.build_manifest(profile(), [cand("K1"), cand("K2", person_levende=True, legacy_publication_ref=None, legacy_status=None, legacy_baseline_sha256=None)], {**texts("K1"), **texts("K2")}, CORPUS)
    b = builder.build_manifest(profile(), [cand("K2", person_levende=True, legacy_publication_ref=None, legacy_status=None, legacy_baseline_sha256=None), cand("K1")], {**texts("K2"), **texts("K1")}, CORPUS)
    assert a["manifest_content_sha256"] == b["manifest_content_sha256"]
```

- [ ] **Step 2: Kør (forventet: ImportError)**: `cd .claude/skills/daa-extract/scripts && python3 -m pytest test_build_legacy_migration_manifest.py -q`

- [ ] **Step 3: Implementér byggeren**

```python
#!/usr/bin/env python3
"""Byg et hash-låst legacy-migration-manifest (spec §4, §6.2, §7). Ingen tekst i output."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from typing import Any
from normalize_narrative_1939_v50 import normalize_narrative_v1

DISPOSITIONS = ("bound_published", "bound_draft", "unresolved_text", "unresolved_identity")

class BuildError(ValueError):
    pass

def _fail(code: str) -> None:
    raise BuildError(code)

def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def _publishable(c: dict[str, Any]) -> bool:
    return c["person_levende"] is False and not c["person_privat"] and not c["person_staged"] and not c["narrative_privat"]

def dispose(c: dict[str, Any], t: dict[str, str], corpus: str) -> tuple[str, str, str]:
    """Returnér (disposition, reason, normalized_sha256)."""
    if _sha(t["narrative_text"]) != c["narrative_text_sha256"] or _sha(t["occurrence_text"]) != c["occurrence_verbatim_sha256"]:
        _fail("LEGACY_MIGRATION_TEXT_HASH_MISMATCH")
    if c["persons_for_record_key"] != 1 or c["external_ids_for_person"] != 1 or c["narratives_for_person"] != 1 or c["already_bound"]:
        return "unresolved_identity", "identity_not_injective_or_bound", ""
    n_norm = normalize_narrative_v1(t["narrative_text"], corpus)["text"]
    o_norm = normalize_narrative_v1(t["occurrence_text"], corpus)["text"]
    if n_norm != o_norm:
        return "unresolved_text", "normalized_text_differs", ""
    publishable = _publishable(c)
    if publishable:
        if c["legacy_status"] != "grandfathered_publication" or not c["legacy_publication_ref"] or not c["legacy_baseline_sha256"]:
            _fail("LEGACY_MIGRATION_LEDGER_INCONSISTENT")
        return "bound_published", "publishable_grandfathered", _sha(n_norm)
    if c["legacy_status"] is not None:
        _fail("LEGACY_MIGRATION_LEDGER_INCONSISTENT")
    return "bound_draft", "not_publishable", _sha(n_norm)

def build_manifest(profile: dict[str, Any], candidates: list[dict[str, Any]], texts: dict[str, dict[str, str]], corpus: str) -> dict[str, Any]:
    if _sha(corpus) != profile["raw_text_sha256"]:
        _fail("LEGACY_MIGRATION_CORPUS_SHA_MISMATCH")
    seen: set[str] = set()
    dispositions: list[dict[str, Any]] = []
    operations: list[dict[str, Any]] = []
    for c in sorted(candidates, key=lambda x: x["record_key"]):
        key = c["record_key"]
        if key in seen:
            _fail("LEGACY_MIGRATION_RECORD_KEY_DUPLICATE")
        seen.add(key)
        if key not in texts:
            _fail("LEGACY_MIGRATION_TEXT_MISSING")
        disposition, reason, norm_sha = dispose(c, texts[key], corpus)
        dispositions.append({"record_key": key, "person_id": c["person_id"], "narrative_id": c["narrative_id"],
                             "disposition": disposition, "reason": reason})
        if disposition.startswith("bound_"):
            operations.append({
                "element_id": f"legacy-migration:{key}", "dependency_class": "legacy_migration",
                "source_record_key": key, "source_id": profile["source_id"],
                "person_id": c["person_id"], "narrative_id": c["narrative_id"], "disposition": disposition,
                "narrative_text_sha256": c["narrative_text_sha256"],
                "occurrence_verbatim_sha256": c["occurrence_verbatim_sha256"],
                "normalized_text_sha256": norm_sha,
                "legacy_publication_ref": c["legacy_publication_ref"] if disposition == "bound_published" else None,
                "legacy_baseline_sha256": c["legacy_baseline_sha256"] if disposition == "bound_published" else None,
                "persona_key": key})
    tally = {d: sum(1 for x in dispositions if x["disposition"] == d) for d in DISPOSITIONS}
    unresolved = tally["unresolved_text"] + tally["unresolved_identity"]
    if dispositions and unresolved * 100 > profile["stop_threshold"]["unresolved_max_share_percent"] * len(dispositions):
        _fail("LEGACY_MIGRATION_STOP_THRESHOLD")
    if tally != profile["expected_dispositions"]:
        _fail("LEGACY_MIGRATION_EXPECTED_DISPOSITIONS_MISMATCH")
    if len(operations) != profile["expected_counts"]["legacy_migrations"]:
        _fail("LEGACY_MIGRATION_COUNT_MISMATCH")
    manifest = {
        "source": {"id": profile["source_id"], "profile_id": profile["profile_id"], "profile_sha256": profile["profile_sha256"]},
        "expected_counts": {"source_evidence": 0, "person_creates": 0, "canonical_delta": 0, "legacy_migrations": len(operations)},
        "dispositions": dispositions,
        "operations": operations,
    }
    manifest["manifest_content_sha256"] = hashlib.sha256(json.dumps(
        manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return manifest

def main() -> None:
    parser = argparse.ArgumentParser()
    for flag in ("--profile", "--candidates", "--texts", "--rendition-text", "--output"):
        parser.add_argument(flag, required=True)
    args = parser.parse_args()
    from reimport_profile import load_profile  # samme mappe
    profile = load_profile(Path(args.profile))
    candidates = json.loads(Path(args.candidates).read_text(encoding="utf-8"))
    texts = json.loads(Path(args.texts).read_text(encoding="utf-8"))
    corpus = Path(args.rendition_text).read_text(encoding="utf-8")
    out = Path(args.output)
    if out.exists():
        _fail("LEGACY_MIGRATION_OUTPUT_EXISTS")
    out.write_text(json.dumps(build_manifest(profile, candidates, texts, corpus), ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
```

`reimport_profile.py`: tilføj `LEGACY_PROFILE_SCHEMA_VERSION = "reimport-legacy-migration-profile-v1"`, nøglemængderne ovenfor, og lad `load_profile` dispatche på `profile_schema_version` (samme `_validate_writer_config`, samme kanoniske hash, samme placeholder-/kollations-tjek). Tests i `test_reimport_profile.py`: gyldig legacy-profil indlæses; ekstra nøgle afvises (`PROFILE_KEYS_INVALID`); `expected_dispositions` skal have præcis de fire nøgler med ikke-negative heltal.

Profilen `daa-2018-20-legacy-migration-v1.json`:

```json
{
  "profile_schema_version": "reimport-legacy-migration-profile-v1",
  "source_id": 1,
  "profile_id": "daa-2018-20-legacy-migration-v1",
  "profile_version": "legacy-migration-v1",
  "writer_config": {
    "citation_label_template": "DAA 2018-20 side {page_from}",
    "extractor_version": "legacy-migration-v1",
    "observation_extraction_method": "none",
    "rendition_key": "daa-2018-20-pdftotext-r1",
    "rendition_kind": "pdf_text_layer",
    "rendition_metadata": {
      "edition": "2018-20",
      "pdf_sha256": "3beadfc15e3fa1a4090589af56cd4e95599a9231e8f979dfb60c4e27bbd8252a",
      "pdftotext_version": "26.07.0"
    },
    "run_key_prefix": "reimport-legacy-migration:",
    "schema_version": "legacy-migration-manifest-v1"
  },
  "raw_text_sha256": "2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563",
  "expected_counts": {"person_creates": 0, "source_evidence": 0, "legacy_migrations": 587},
  "expected_dispositions": {"bound_published": 541, "bound_draft": 46, "unresolved_text": 4, "unresolved_identity": 0},
  "stop_threshold": {"unresolved_max_share_percent": 10}
}
```

- [ ] **Step 4: Kør pytest grøn** (alle fire pytest-filer i CI-listen).

- [ ] **Step 5: Commit**: `feat(genimport): legacy-migration-manifestbygger, profilskema og 2018-20-profil`

### Task 9: R-integrationstest mod syntetisk v2-base + CI

**Files:**
- Create: `tests/integration/test-reimport-legacy-migration.R`
- Modify: `.github/workflows/ci.yml` (writer-jobbet, efter Task 5's SQL-trin):

```yaml
      - name: Legacy migration writer integration (149b)
        env: {PGHOST: localhost, PGPORT: 5432, PGUSER: postgres, PGPASSWORD: postgres, PGDATABASE: writer_1939}
        run: Rscript tests/integration/test-reimport-legacy-migration.R
```

**Interfaces:**
- Consumes: Task 3's RPC, Task 6's gateway, `execute_reimport(manifest, preview_sha256, mode, gateway, authorization)`.

- [ ] **Step 1: Skriv testen** efter skabelonen `tests/integration/test-reimport-source-evidence.R` (nonce pr. kørsel, aktør, syntetisk source + to profiler). Forløb: (1) opret syntetisk person (død) + narrativ + external_id + ledger-række (som Task 3's SQL-fixture, men via DBI) og en levende ditto; (2) kør en `source_evidence`-batch med 149a-profilen for de to record_keys (genbrug `operation()` fra skabelonen); (3) byg legacy-manifestet i R (samme felter som Task 8's operationer; `normalized_text_sha256 = digest(tekst)` da fixturen er byte-lig); (4) dry-run → `finalized`, committed FALSE, ledger uændret; (5) apply → ledger `migrated` for den døde, binding `published`/`draft`, `public_person_bio_source_versions_v2` giver præcis 1 række for den døde og 0 for den levende; `anon`-hashes for de otte tabeller uændrede; (6) replay → `already_applied`; (7) tre-trins reversal for den døde gennem `red_fortryd_person_narrative_publication_event` med `state_sha256` fra `red_person_narrative_records`/`narrative_legacy_state`, slut: ledger `grandfathered_publication`, binding `withdrawn`; (8) `cat("PASS legacy migration integration\n")`.

- [ ] **Step 2: Kør mod basen fra Task 1 Step 2** (`PGDATABASE=daa149b_writer_ci Rscript tests/integration/test-reimport-legacy-migration.R`), to gange i træk (idempotens pr. nonce).

- [ ] **Step 3: Commit**: `test(genimport): integrationstest og CI-trin for legacy-migration-writeren`

---

# Leverance 3 — rehearsal, rapport og dokumentation (én dag; »én rigtig kørsel« = Del B-kæden mod restore af prod-dumpet)

### Task 10: Rehearsal-runbook og rehearsal mod restore af prod-dumpet

**Files:**
- Create: `docs/runbooks/legacy-migration-reimport-rehearsal.md` (kopiér strukturen fra `docs/runbooks/source-evidence-reimport-rehearsal.md` §1-§6 og tilføj §7 »149b«)
- Create: `docs/evidensbaseret-genimport/legacy-migration-149b-rehearsal.md`

**Interfaces:**
- Consumes: alle tidligere tasks; 149a's manifest (`c7d19c01…`) og profil; #152's cutover-kæde (runbook §3b).

- [ ] **Step 1: Restore + migrations + cutover + 149a** — følg `source-evidence-reimport-rehearsal.md` §2-§5 ordret på en ny base `daa149b_rehearsal_<dato>` (`createdb -T daa149b_inv_20260903` sparer restore). Verificér: kontraktversion 2; ledger source 1 = 544 `grandfathered_publication`; 149a-apply giver 1/591/591/591. Notér alle hashes i rapporten. `PGTZ=UTC` i alle sessioner.

- [ ] **Step 2: Eksport, byg, preview, dry-run, autorisation, apply** — Task 7's eksport til en 0700-mappe under `$CLAUDE_JOB_DIR/tmp` (ikke `work/`), Task 8's bygger med 149a's `rendition.txt` som corpus, Task 6's preview (`export_reimport_preview.R --profile <legacy-profil>`), `apply_reimport.R --dry-run`, autorisation som `service_role` + `request.jwt.claim.sub` (runbook §5), `apply_reimport.R --apply`.

  Forventet efter apply (spec §10): 587 personas, 587 accepterede identiteter, 587 `draft_created`, 541 `published`, 541 `legacy_migrated`; ledger source 1 = 541 `migrated` + 3 `grandfathered_publication`; bindinger 541 `published` + 46 `draft`; `public_person_bio_source_versions_v2` for de 591 personer: 541 `source_record`, 0 `legacy_narrative` for source 1; `anon`-hashes for de otte tabeller identiske med før; `person`/`fact`/`family_member`/`narrative`-aggregat-hash uændrede (kun `narrative_record_publication` og private tabeller ændres); replay `already_applied`; tre-trins reversal for ét narrativ (`I-1` eller det første i manifestet) gendanner ledger + `withdrawn` binding; `red_reverse_reimport` afviser med `REIMPORT_WRITER_REVERSAL_INVALID`.

- [ ] **Step 3: Skriv rapporten** (`legacy-migration-149b-rehearsal.md`) med præcis: afgrænsning (»lokalt bevis, ikke produktionsautorisation«), basetabel, låste inputhashes (profil, manifest indhold/bytes, preview), tal pr. disposition og eventtype, de 4 `unresolved_text`-nøgler, hash-tabel før/efter, replay, reversal, restpunkter (de 13 mulige `NOISE_RE`-prosalinjer; valg A/B afventer kvittering).

- [ ] **Step 4: Commit**: `docs(genimport): rehearsal-runbook og rehearsal-rapport for 149b legacy-migration`

### Task 11: Fase-pakke-bidrag, status, changelog, beslutninger

**Files:**
- Create: `docs/evidensbaseret-genimport/legacy-migration-149b-phase-package-contribution.md` (samme felter som `source-evidence-149a-phase-package-contribution.md`, plus `dispositions`, `events`, `ledger_after`)
- Modify: `docs/evidensbaseret-genimport/status.md` (ny række »2018-20 narrativ-binding (149b)« = `integreret ende-til-ende` med bevis; opdatér 149a-rækkens »Bindinger er 149b (#166)«), `docs/changelog.md` (dateret afsnit), `docs/decisions.md` (tilføj »149b: rehearsal gennemført; valg A/B afventer kvittering« under 149b-posten)

- [ ] **Step 1: Skriv de fire dokumenter** fra rapportens tal og hashes (ingen tekst, ingen navne).
- [ ] **Step 2: `git diff --check`, `Rscript run-tests.R`, pytest (fire filer), SQL-gaten (Task 5 Step 1-3).**
- [ ] **Step 3: Commit**: `docs(genimport): 149b integreret ende-til-ende — fase-pakke-bidrag, status og changelog`

---

## Selv-review

### Spec-dækning pr. paragraf

| Spec | Krav | Task |
|---|---|---|
| §1 række 5 | eksakte tal, én offentlig række pr. biografi, anon uændret, replay, reversal | Task 3 (SQL), 9 (R), 10 (rehearsal) |
| §2 | generel elementoperation, identitetsledger, dispositioner, reversal-gren, bygger/preview | Task 2-4, 6-8 |
| §4 | fire dispositioner, 10 %-stopgrænse, inkonsistens = stop | Task 8 (bygger), Task 3 (`LEDGER_INCONSISTENT` i DB) |
| §5 | persona + mention + accepteret identitet, evidens `person_external_id`, ingen placements | Task 3 |
| §6.1 | CHECK, expected_counts valgfri tredje nøgle, præfiks, RPC, ACL, profil, læsefunktioner | Task 1, 2, 3, 5, 8 |
| §6.2 | lukket payload | Task 3 (ARRAY-tjek), Task 8 |
| §6.3 | preconditions i rækkefølge | Task 3 |
| §6.4 | låserække, events, efterkontrol, gate-tjek | Task 3 |
| §6.5 | narrativrækken urørt | Task 3-test `TASK3_TEXT_CHANGED` |
| §7 | eksport, bygger, validator, preview, gate | Task 6, 7, 8, 10 |
| §8 | reversal-gren, batch-reversal = per-narrativ i omvendt rækkefølge, `red_reverse_reimport` afviser | Task 4, Task 10 Step 2 |
| §9 | ingen tekst i artefakter, 0600/0700, `work` afvises | Task 7, 8, 10 |
| §10 | SQL/R/Python-tests, CI, rehearsal med eksakte tal | Task 1-5, 6, 8, 9, 10 |

### Kendte forbehold, som udføreren skal afgøre ved læsning

- Hvis `tests/sql/test-1939-v50-production-writer.sql:29,66` assert'er en *lukket* liste af RPC'er, tilføjes den nye RPC dér; ellers ikke.
- Task 3-testens `SET ROLE service_role`/`authenticated` forudsætter, at rollerne findes i testbasen (de oprettes af `tests/sql/evidence-promotion-bootstrap.sql`); verificér med `\du` før første kørsel.

### Typekonsistens

`red_apply_reimport_legacy_migration(uuid,text,jsonb) RETURNS jsonb` (Task 3, 5, 6, 9); payload-nøgler identiske i Task 3 (ARRAY), Task 6 (R-test), Task 8 (bygger). `expected_counts.legacy_migrations` (Task 2, 6, 8). Fejlkoder: `LEGACY_MIGRATION_PAYLOAD_INVALID`, `_RECORD_MISSING`, `_ANCHOR_AMBIGUOUS`, `_OCCURRENCE_TEXT_DRIFT`, `_MENTION_AMBIGUOUS`, `_IDENTITY_AMBIGUOUS`, `_NARRATIVE_AMBIGUOUS`, `_ALREADY_BOUND`, `_NARRATIVE_TEXT_DRIFT`, `_LEDGER_INCONSISTENT`, `_PERSONA_EXISTS`, `_PRESTATE_INVALID`, `_EVENT_APPEND_MISMATCH`, `_PUBLICATION_GATE_MISMATCH` (DB); `NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE` (reversal); `LEGACY_MIGRATION_TEXT_HASH_MISMATCH`, `_CORPUS_SHA_MISMATCH`, `_RECORD_KEY_DUPLICATE`, `_TEXT_MISSING`, `_STOP_THRESHOLD`, `_EXPECTED_DISPOSITIONS_MISMATCH`, `_COUNT_MISMATCH`, `_OUTPUT_EXISTS` (bygger); `PREVIEW_LEGACY_LEDGER_INCONSISTENT` (preview); `OUTPUT_WORK_PATH`, `OUTPUT_DIR_NOT_ABSOLUTE` (eksport).
