# Personers OCR-kvalitetsark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give web editors a spreadsheet-like view of every raw imported person, with deterministic QA filters and a source-control side panel where name, birth date, death date, and gender can be corrected without turning OCR cleanup into new historical assertions.

**Architecture:** Add reload-stable import identity and a durable correction journal in PostgreSQL; expose one redaction-only set-based grid RPC, one narrow atomic correction RPC, and one lazy per-field history RPC; apply matching corrections as an overlay during `load_daa.R`; build a web-only table and source panel on top of focused TypeScript data adapters. Corrections update the one unambiguous imported assertion in place, retain its evidence identity, write normal `change_set`/`change_event` history, and fail closed on missing identity, ambiguity, or changed source fingerprints.

**Tech Stack:** PostgreSQL 17 / Supabase PostgREST and RLS, R 4.1+ with DBI/RPostgres/digest/testthat, TypeScript, React 18, Vite/Vitest, `@daa/core`.

**Authoritative design:** `docs/superpowers/specs/2026-07-26-person-ocr-kvalitetsark-design.md`

**Current Supabase constraints:** New exposed tables and RPCs receive explicit grants rather than relying on dashboard defaults; every exposed table has RLS enabled; every `SECURITY DEFINER` RPC has an explicit redaction-role guard, fixed `search_path`, and revokes for `PUBLIC` and `anon`. See [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security), [Securing your API](https://supabase.com/docs/guides/api/securing-your-api), and the [April 2026 API exposure change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).

## Global Constraints

- Work only in the isolated worktree
  `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/person-spreadsheet`
  on `feat/person-spreadsheet-design`.
- This plan does not authorize production DDL, production DML, deployment, push, or
  PR creation. Database work is verified against a local disposable PostgreSQL database
  or a separately approved non-production copy.
- One grid row is one physical `person.id`. Never run the rows through
  `collapseSameAs`; `samme_som` is read-only context.
- “Alle personer” is a permanent first-class view. The QA queue is a filter preset,
  never the only way into the data.
- V1 writes only `navn`, `foedsel`, `doed`, and `koen`, one cell at a time. Titles,
  families, and relations are counts/links only. No bulk paste, fill-down, multi-row
  save, title editing, family editing, relation editing, or mobile UI.
- `person.visning_*` remains a cache. Name and date corrections target the selected
  imported assertion; gender targets `person.koen`. Never write a `visning_*` column.
- An OCR correction is a correction of the same imported source statement. Preserve
  `fact.id`, `assertion.id`, `citation`, `source_id`, `conclusion`, and
  `assertion.uforanderlig`; do not create a competing assertion or conclusion.
- The correction RPC must fail closed unless the person has exactly one stable
  `(import_key, record_key)` anchor and the chosen field resolves to exactly one selected,
  cited assertion from that source. Ambiguous rows remain readable but link to the
  existing editor.
- `citation.citat_tekst` is extraction/OCR context (`kilde_span`), not a facsimile of the
  printed page. The UI must say “OCR-kontekst” and must not claim it shows the original.
- The correction journal is outside `load_daa.R`'s reset list and has no FK to
  regenerable IDs. A changed fingerprint marks the decision `stale` and prevents replay.
- A correction never becomes its own import input. Before the first decision, the
  fingerprint is calculated from the selected assertion/person value. After a journal
  row exists, both grid and correction RPC calculate it from
  `import_korrektion.importeret` plus the current OCR context. This keeps repeated
  corrections possible while still detecting a changed extraction on the next reload.
- `source.import_key` follows the existing fail-closed import-key direction: never infer
  it from a display title and never silently replace another artifact using the same key.
  Artifact checksum/idempotency itself remains out of scope for this feature.
- Date normalization must remain in parity with the extraction pipeline's
  `.claude/skills/daa-extract/scripts/validate.py::derive_date_info`. A shared fixture
  covers exact dates/years, before/after, circa, intervals, floruit, Danish/German month
  names, Roman years, and OCR uncertainty. An unsupported corrected raw date is still
  saved as `date_raw`, with bounds and qualifier set to `NULL` and QA code
  `dato_ufortolkelig`; the editor is warned before save.
- All SQL changes must exist in both `schema.sql` (fresh install) and an idempotent,
  named block in `db-migrations.sql` (upgrade path). RLS/grants live in `db-rls.sql`.
- Tests precede production changes. Capture the intended RED, implement the smallest
  GREEN, then refactor. Do not weaken a failing test to obtain green.
- Keep commits small and Danish, using the prefix shown under each task. Leave the branch
  local unless the user later asks to publish it.

## Planned File Map

| File | Responsibility |
|---|---|
| `schema.sql` | Stable import identity, correction journal, private helpers, grid/correction RPCs |
| `db-migrations.sql` | Idempotent upgrade path for the same objects |
| `db-rls.sql` | Journal RLS, least-privilege grants, RPC execute allowlist |
| `db-verify.sql` | Identity, ambiguity, fingerprint, atomic correction, undo, and RLS assertions |
| `.claude/skills/daa-extract/scripts/load_helpers.R` | Pure record-key, fingerprint, and correction-overlay helpers |
| `.claude/skills/daa-extract/scripts/load_daa.R` | Explicit import key, stable record key, journal preload/replay |
| `tests/testthat/test-load-daa.R` | Loader unit and reset/replay fixture tests |
| `packages/core/src/ocrKvalitet.ts` | Grid types, extraction-parity date normalization, QA/filter/sort pure functions |
| `packages/core/src/index.ts` | Export seam |
| `packages/core/src/__tests__/ocrKvalitet.test.ts` | Pure contract tests |
| `web/src/data/personKvalitetsark.ts` | Supabase grid/write/history RPC adapters and error mapping |
| `web/src/data/__tests__/personKvalitetsark.test.ts` | Adapter tests |
| `web/src/components/PersonKvalitetsark.tsx` | Table, presets, filters, sorting, selection |
| `web/src/components/OcrKildepanel.tsx` | Single-field correction and review panel |
| `web/src/components/__tests__/PersonKvalitetsark.test.tsx` | Grid behavior tests |
| `web/src/components/__tests__/OcrKildepanel.test.tsx` | Save/warning/blocked-state tests |
| `web/src/Redaktion.tsx` | Person “Liste / Kvalitetsark” mode integration |
| `web/src/__tests__/Redaktion.kvalitetsark.test.tsx` | Integration/regression tests |

## Dependency Order

1. Task 1 establishes stable identity and the durable journal.
2. Task 2 establishes the loader-side stable-key and fingerprint contract.
3. Task 3 can then build the read projection on stable anchors.
4. Task 4 adds the atomic correction/review RPC against the same contract.
5. Task 5 makes corrections survive a loader reset.
6. Tasks 6–9 build and integrate the web UI.
7. Task 10 runs the complete verification gate and prepares, but does not perform,
   deployment.

---

## Task 1: Stable Import Identity and Durable Journal

**Files:**
- Modify: `schema.sql` (`source`, `person_external_id`, version registry section)
- Modify: `db-migrations.sql` (new named block `person_ocr_kvalitetsark_identitet`)
- Modify: `db-rls.sql` (journal policy and grants)
- Modify: `db-verify.sql` (new self-contained section “Person OCR kvalitetsark — identitet”)

**Interfaces:**

```sql
ALTER TABLE source ADD COLUMN import_key text;
CREATE UNIQUE INDEX source_import_key_uidx
  ON source (import_key) WHERE import_key IS NOT NULL;

ALTER TABLE person_external_id ADD COLUMN record_key text;
CREATE UNIQUE INDEX person_external_id_source_record_key_uidx
  ON person_external_id (source_id, record_key)
  WHERE record_key IS NOT NULL;

CREATE TABLE import_korrektion (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  import_key text NOT NULL,
  record_key text NOT NULL,
  felt text NOT NULL CHECK (felt IN ('navn','foedsel','doed','koen','post')),
  input_fingerprint text NOT NULL CHECK (input_fingerprint ~ '^[0-9a-f]{32}$'),
  importeret jsonb NOT NULL,
  korrigeret jsonb,
  status text NOT NULL CHECK (status IN ('aaben','rettet','godkendt','udskudt','stale')),
  actor_id uuid,
  actor_navn text,
  oprettet_at timestamptz NOT NULL DEFAULT now(),
  opdateret_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (import_key, record_key, felt)
);

CREATE INDEX import_korrektion_status_import_idx
  ON import_korrektion (status, import_key);
```

The idempotent migration must use catalog checks/`CREATE ... IF NOT EXISTS` where
PostgreSQL supports them. For constraints, use a guarded `DO $$` block because
`ADD CONSTRAINT IF NOT EXISTS` is not valid PostgreSQL.

**Steps:**

- [ ] Add failing catalog and behavior assertions to `db-verify.sql`:
  columns exist with the exact types/nullability, the two partial unique indexes reject
  duplicate non-null keys but permit legacy `NULL`, the journal constraints reject an
  unknown field/status/hash, and no FK from `import_korrektion` points at regenerable IDs.
- [ ] Add a failing RLS assertion: `anon` cannot select or mutate journal rows;
  a normal authenticated member cannot select them; an impersonated redactor can select
  but cannot perform direct insert/update/delete.
- [ ] Run the scoped new verify section against the local database and retain the
  first expected error as RED:

```bash
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 5432 -U postgres -d daa_person_grid_test \
  -v ON_ERROR_STOP=1 -f db-verify.sql
```

- [ ] Add the columns/table/indexes to `schema.sql`.
- [ ] Add the equivalent idempotent migration block to `db-migrations.sql`. The block
  must be safely runnable twice.
- [ ] Add `ALTER TABLE import_korrektion ENABLE ROW LEVEL SECURITY`.
- [ ] Add a `redaktion_read` policy using
  `(select public.current_rolle()) = 'redaktion'`.
- [ ] Explicitly grant `SELECT` on `import_korrektion` to `authenticated`, revoke every
  table privilege from `anon`, and revoke `INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES,
  TRIGGER` from `authenticated`. Writes will arrive only through Task 4's RPC.
- [ ] Register `import_korrektion` in `version_pk_registry` with `ARRAY['id']`, install
  `trg_log_import_korrektion` through the repository's existing trigger installer, and
  assert that an upsert produces a normal `change_event`. The table's actor/timestamps are
  the current decision summary; `change_event` is the immutable correction history.
- [ ] Rebuild a fresh local database from `schema.sql`, then test the upgrade path twice:

```bash
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/createdb daa_person_grid_test
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 5432 -U postgres -d daa_person_grid_test \
  -v ON_ERROR_STOP=1 -f schema.sql
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 5432 -U postgres -d daa_person_grid_test \
  -v ON_ERROR_STOP=1 -f db-migrations.sql
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 5432 -U postgres -d daa_person_grid_test \
  -v ON_ERROR_STOP=1 -f db-migrations.sql
LC_ALL=C /opt/homebrew/opt/postgresql@17/bin/psql \
  -h 127.0.0.1 -p 5432 -U postgres -d daa_person_grid_test \
  -v ON_ERROR_STOP=1 -f db-rls.sql
```

- [ ] Run the scoped verify section again and confirm GREEN.
- [ ] Run `git diff --check`.
- [ ] Commit:

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): tilføj stabile importnøgler og korrektionsjournal"
```

---

## Task 2: Pure Loader Contract for Record Keys and Fingerprints

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_helpers.R`
- Modify: `tests/testthat/test-load-daa.R`

**Interfaces:**

```r
record_key_of <- function(rec) {
  paste0(as.character(rec$linje), "-", as.character(
    rec$nr_label %||% rec$nr
  ))
}

canonical_import_value <- function(felt, value)
ocr_input_fingerprint <- function(import_key, record_key, felt, importeret, ocr_context)
apply_import_correction <- function(import_key, record_key, felt, importeret,
                                    ocr_context, corrections)
```

Canonical JSON shapes:

```json
{"value":"Conrad Detlev Reventlow"}
{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}
{"value":"mand"}
```

Fingerprint input is UTF-8 bytes of these five values separated by ASCII unit separator
`0x1f`, then MD5 hex:

```text
import_key ␟ record_key ␟ felt ␟ canonical_json(importeret) ␟ ocr_context
```

MD5 is used only as a deterministic change detector, not for security. JSON keys must be
emitted in the fixed order shown above, with compact encoding and explicit `null`.

`apply_import_correction()` returns:

```r
list(
  value = importeret,
  status = "ingen",       # ingen | anvendt | stale
  fingerprint = "<32 hex>",
  correction_id = NA
)
```

**Steps:**

- [ ] Add failing tests for `record_key_of()` preserving `nr_label` exactly:
  `I + 15a -> I-15a`, `III + 79 -> III-79`, and numeric fallback when `nr_label`
  is absent.
- [ ] Add table-driven failing tests for canonical name/date/gender JSON, including
  Danish characters and explicit JSON `null`.
- [ ] Add a fixed-vector fingerprint test. Compute the reference once with R's
  `digest(..., algo = "md5", serialize = FALSE)` and hard-code the expected 32-char
  hex so later SQL parity tests cannot “agree by sharing the same bug”.
- [ ] Add failing overlay tests:
  exact fingerprint + `status="rettet"` applies `korrigeret`; exact fingerprint +
  `godkendt` leaves the imported value; changed context yields `stale` and leaves the
  import untouched; `udskudt` never changes the value.
- [ ] Run the focused test file and capture RED:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-load-daa.R")'
```

- [ ] Implement only the pure functions in `load_helpers.R`. Use `jsonlite::toJSON`
  with `auto_unbox=TRUE`, `null="null"`, `na="null"`, and fixed list key order.
- [ ] Keep missing `record_key` fail-closed: return `NA_character_`; never synthesize a
  key from the person's database ID or name.
- [ ] Run the focused R test, then the full R suite:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-load-daa.R")'
Rscript run-tests.R
```

- [ ] Run `git diff --check`.
- [ ] Commit:

```bash
git add .claude/skills/daa-extract/scripts/load_helpers.R tests/testthat/test-load-daa.R
git commit -m "feat(loader): fastlæg stabile OCR-korrektionsnøgler"
```

---

## Task 3: Set-Based Redaction Grid RPC

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`

**Interfaces:**

```sql
CREATE OR REPLACE FUNCTION red_person_grid()
RETURNS TABLE (
  person_id bigint,
  import_key text,
  record_key text,
  source_id bigint,
  source_titel text,
  source_udgave text,
  linje text,
  nr integer,
  slaegtled integer,
  navn text,
  navn_assertion_id bigint,
  foedsel_raw text,
  foedsel_min date,
  foedsel_max date,
  foedsel_qualifier text,
  foedsel_assertion_id bigint,
  doed_raw text,
  doed_min date,
  doed_max date,
  doed_qualifier text,
  doed_assertion_id bigint,
  input_fingerprint jsonb,
  importeret jsonb,
  korrigeret jsonb,
  ocr_context jsonb,
  kilde_side jsonb,
  koen text,
  levende boolean,
  privat boolean,
  staged boolean,
  person_status text,
  kanonisk_person_id bigint,
  samme_som_status text,
  antal_titler integer,
  antal_familier integer,
  antal_relationer integer,
  antal_kilde_assertions integer,
  qa_koder text[],
  qa_alvor text,
  review_status jsonb,
  kan_rettes jsonb,
  blokarsager jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp;
```

`kan_rettes` and `blokarsager` are keyed by the four editable field names. Example:

```json
{"navn":true,"foedsel":false,"doed":true,"koen":true}
{"foedsel":"flere_importerede_facts"}
```

The function must use CTEs grouped by person/source/field. It must not call a SQL
function once per output row when the same result can be aggregated in a set.

**Steps:**

- [ ] Add a self-contained fixture to `db-verify.sql` with:
  one normal imported person, one person with two birth facts, one legacy person without
  `record_key`, one staged person, and two raw persons connected by `samme_som`.
- [ ] Add failing assertions that the RPC:
  returns exactly one row per physical `person.id`; does not collapse `samme_som`;
  includes all persons regardless of QA status; returns title/family/relation counts;
  labels ambiguity/missing key as non-editable; and returns OCR context from the selected
  assertion's citation.
- [ ] Add failing QA assertions for:
  `mistænkeligt_ocr_tegn`, `dato_ufortolkelig`, `foedt_efter_doed`,
  `struktureret_afviger_fra_ocr`, `navn_mangler`, `record_key_mangler`,
  `ocr_kontekst_mangler`, and `flere_importerede_facts`.
  Verify that merely missing birth/death dates does not create an error.
- [ ] Add failing permission assertions:
  `anon` cannot execute, authenticated member cannot execute, redactor can execute.
- [ ] Capture RED using the Task 1 local `psql` command.
- [ ] Implement the function in `schema.sql` with these set-based CTE layers:
  `external_anchor`, `selected_assertions`, `field_candidates`, `field_rollup`,
  `counts`, `same_as_context`, `journal`, `qa`, final projection.
- [ ] For a person with multiple external IDs, return a row but set every editable
  field to `false` with `blokarsag="flere_importankre"`.
- [ ] For name/date fields, accept only exactly one selected assertion cited by the
  anchored source. If there are zero or multiple candidates, set the field non-editable.
- [ ] For gender, require exactly one import anchor but no assertion.
- [ ] Use the journal row only when its stored fingerprint equals the current source
  fingerprint. When a journal row exists, derive the source input from its immutable
  `importeret` snapshot rather than the already corrected assertion/person value.
  Surface a mismatch as `status="stale"` and add `kilde_aendret`.
- [ ] Add the exact function body to the idempotent migration.
- [ ] Harden execution in `db-rls.sql`:

```sql
REVOKE EXECUTE ON FUNCTION red_person_grid() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION red_person_grid() TO authenticated;
```

  Keep the internal `current_rolle()='redaktion'` exception guard even though the
  execute grant is authenticated-wide.
- [ ] Run `EXPLAIN (ANALYZE, BUFFERS)` against a representative local load. Confirm there
  is no query count proportional to the number of persons and no accidental Cartesian
  multiplication. Add a supporting composite index only if the plan shows a real need.
- [ ] Run the scoped verify section and `git diff --check`.
- [ ] Commit:

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): tilføj samlet personprojektion til kvalitetsark"
```

---

## Task 4: Atomic OCR Correction and Review RPC

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`

**Interfaces:**

```sql
CREATE OR REPLACE FUNCTION red_ret_ocr_felt(
  p_person_id bigint,
  p_import_key text,
  p_record_key text,
  p_felt text,
  p_input_fingerprint text,
  p_korrigeret jsonb,
  p_status text DEFAULT 'rettet',
  p_actor_navn text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION red_ocr_historik(
  p_import_key text,
  p_record_key text,
  p_felt text
) RETURNS TABLE (
  change_set_id bigint,
  changed_at timestamptz,
  actor_navn text,
  operation text,
  foer jsonb,
  efter jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp;
```

Accepted commands:

- `p_status='rettet'`: `p_korrigeret` is required.
- `p_status='godkendt'`: `p_korrigeret` must be `NULL`; no model value changes.
- `p_status='udskudt'`: `p_korrigeret` must be `NULL`; no model value changes.

Date JSON:

```json
{
  "raw":"1644-06-12",
  "min":"1644-06-12",
  "max":"1644-06-12",
  "qualifier":null,
  "calendar":"gregoriansk",
  "certainty":null
}
```

The result is the newly projected single grid row as JSON. Errors use stable codes in
the message prefix:

```text
OCR_ROLE_FORBIDDEN
OCR_FIELD_INVALID
OCR_PERSON_NOT_FOUND
OCR_IMPORT_ANCHOR_AMBIGUOUS
OCR_ASSERTION_AMBIGUOUS
OCR_FINGERPRINT_STALE
OCR_VALUE_INVALID
```

**Steps:**

- [ ] Add failing transaction tests for each field:
  name changes only `assertion.vaerdi_tekst`; date changes only the selected assertion's
  date columns; gender changes only `person.koen`.
- [ ] Assert that the original `fact.id`, `assertion.id`, citation row/source, conclusion,
  and `uforanderlig` value remain unchanged.
- [ ] Assert that one `change_set` and the expected `change_event` snapshots are written,
  and that the existing undo mechanism restores the prior model value.
- [ ] Assert journal upsert semantics:
  first correction inserts; later correction updates the same logical row; approve/defer
  do not mutate the model; actor is taken from `auth.uid()`/profile where available and
  `p_actor_navn` is only a display fallback.
- [ ] Add a failing history test: after two corrections,
  `red_ocr_historik(import_key,record_key,felt)` returns both journal events in newest-first
  order with frozen actor, timestamp, before, and after snapshots; another field/person is
  absent.
- [ ] Add negative tests for role, stale fingerprint, unknown field, invalid gender,
  missing corrected value, multiple import anchors, multiple candidate facts, and a
  source mismatch. Assert every failure leaves model, journal, and history unchanged.
- [ ] Add a repeated-correction test: after correcting the same field twice, the journal's
  `importeret` snapshot and source fingerprint remain the original import, while only
  `korrigeret` and the model value advance. This distinguishes source drift from an
  intentional later editor correction.
- [ ] Capture RED using the scoped local verify command.
- [ ] Implement a private SQL helper for the canonical import JSON/fingerprint. If a
  `private` schema does not already exist, add:

```sql
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
```

  Put the helper in `private`, keep its JSON key order identical to Task 2, and add the
  fixed-vector SQL assertion matching the R test.
- [ ] Implement the RPC in this lock order:
  source/external anchor by `p_import_key + p_record_key`; verify it resolves uniquely to
  `p_person_id`; person row `FOR UPDATE`; selected assertion `FOR UPDATE`; journal row
  `FOR UPDATE`; current fingerprint comparison; `begin_change_set`; model update; journal
  upsert; return refreshed row. Never hold locks during client interaction.
- [ ] Implement `red_ocr_historik` by resolving the journal row's stable logical key,
  joining `change_event` on `tabel='import_korrektion'` and that row's JSON PK, then joining
  `change_set`. Apply the same redaction guard and never expose unrelated event rows.
- [ ] Call `regen_person_visning(p_person_id)` only if existing triggers do not already
  regenerate for the changed table. Verify once; do not double-regenerate.
- [ ] Use `INSERT ... ON CONFLICT (import_key,record_key,felt) DO UPDATE` for the journal.
- [ ] Add the identical function/helper definitions to the migration block.
- [ ] Add explicit function ACLs:

```sql
REVOKE EXECUTE ON FUNCTION red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION red_ret_ocr_felt(bigint,text,text,text,text,jsonb,text,text)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION red_ocr_historik(text,text,text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION red_ocr_historik(text,text,text)
  TO authenticated;
```

- [ ] Run the scoped DB tests, the existing undo/history blocks, and `git diff --check`.
- [ ] Commit:

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat(db): ret OCR-felter atomisk med auditspor"
```

---

## Task 5: Replay Durable Corrections During Loader Reset

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R`
- Modify: `.claude/skills/daa-extract/scripts/load_helpers.R`
- Modify: `.claude/skills/daa-extract/SKILL.md` (loader invocation)
- Modify: `tests/testthat/test-load-daa.R`
- Create: `tests/fixtures/person-ocr-kvalitetsark-clean.json`
- Modify: `db-verify.sql` only if a DB-backed reload fixture is kept there

**Interfaces (CLI):**

```text
Rscript .claude/skills/daa-extract/scripts/load_daa.R \
  tests/fixtures/person-ocr-kvalitetsark-clean.json \
  "DAA OCR-fixture" \
  --import-key=daa:test:ocr-kvalitetsark \
  [--reset]
```

`--import-key` is mandatory for a correction-capable import. Existing invocations without
it may continue only in explicitly marked legacy mode, which writes `NULL` keys and cannot
be corrected in the quality grid.

**Steps:**

- [ ] Add failing argument-parser tests for a valid explicit import key, blank key,
  and missing key. If argument parsing is currently inline, extract only the smallest
  pure parser helper needed for testing.
- [ ] Add a failing buffer test showing that `add_extid()` carries `record_key` and that
  `record_key_of(rec)` uses `nr_label`, not integer `nr`.
- [ ] Add failing correction preload/replay tests:
  exact fingerprint applies corrected name/date/gender before buffer rows are built;
  stale fingerprint leaves import untouched and schedules journal status `stale`;
  approved/deferred rows leave values untouched.
- [ ] Add a reset-list test proving `import_korrektion` is absent from `model_tables`.
- [ ] Capture RED with:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-load-daa.R")'
```

- [ ] Extend the source insert to write the explicit `import_key`.
- [ ] Change `add_extid(pid, sid, linje, nr)` to
  `add_extid(pid, sid, linje, nr, record_key)` and pass `k <- record_key_of(rec)`.
- [ ] Load all correction rows for the selected import key once before the person loop.
  Index them in an in-memory environment by `record_key + felt`; do not query once per
  person or once per fact.
- [ ] Apply name and gender overlays before `split_title()`/`add_person()`.
- [ ] Apply birth/death overlays before `fact_value()` receives raw/bounds. Keep the
  printed/OCR context unmodified; the journal preserves both imported and corrected JSON.
- [ ] Collect stale correction IDs during the loop and update them in one statement after
  the model buffer flush succeeds. A failed load must not mark corrections stale.
- [ ] Keep `import_korrektion` out of both `TRUNCATE ... CASCADE` and any sequence-reset
  list. Verify that no FK causes it to be cascaded indirectly.
- [ ] Create `tests/fixtures/person-ocr-kvalitetsark-clean.json` with two persons,
  including `I-15a`, name/birth/death/gender facts, and OCR context. Load it, insert one
  correction through the RPC, rerun with `--reset`, and
  assert the new `person.id` still has the corrected value while journal ID is unchanged.
- [ ] Update `.claude/skills/daa-extract/SKILL.md` so every documented correction-capable
  invocation includes an explicit `--import-key=...`; explain that legacy imports without
  it remain visible but non-editable in the quality grid.
- [ ] Run focused and full R tests. If the DB-backed RPostgres smoke encounters the known
  local cross-connection persistence mismatch, do not “fix” loader transactions in this
  task: report it separately, keep the pure replay tests, and verify the SQL side in the
  same connection.
- [ ] Run `git diff --check`.
- [ ] Commit:

```bash
git add .claude/skills/daa-extract/scripts/load_daa.R \
  .claude/skills/daa-extract/scripts/load_helpers.R \
  .claude/skills/daa-extract/SKILL.md tests/testthat/test-load-daa.R \
  tests/fixtures/person-ocr-kvalitetsark-clean.json
git commit -m "feat(loader): genanvend OCR-rettelser efter reset"
```

---

## Task 6: Shared Grid Types, Date Normalization, QA Filters, and Sorting

**Files:**
- Create: `packages/core/src/ocrKvalitet.ts`
- Create: `packages/core/src/__tests__/ocrKvalitet.test.ts`
- Create: `tests/fixtures/ocr-date-normalization.json`
- Modify: `.claude/skills/daa-extract/scripts/test_validate.py`
- Modify: `packages/core/src/index.ts`

**Interfaces:**

```ts
export type OcrFelt = 'navn' | 'foedsel' | 'doed' | 'koen';
export type OcrReviewStatus = 'aaben' | 'rettet' | 'godkendt' | 'udskudt' | 'stale';
export type KvalitetsarkPreset =
  | 'alle' | 'aabne' | 'rettede' | 'godkendte' | 'udskudte' | 'stale';
export type KvalitetsarkSortKey =
  | 'navn' | 'foedsel' | 'doed' | 'koen' | 'linje' | 'qa_alvor';
export type OcrDateQualifier =
  | 'exact' | 'before' | 'after' | 'about' | 'between' | 'floruit'
  | 'until_event' | 'open_end' | 'ongoing';

export type PersonKvalitetsarkRow = {
  personId: string;
  importKey: string | null;
  recordKey: string | null;
  sourceTitel: string | null;
  sourceUdgave: string | null;
  linje: string | null;
  nr: number | null;
  personStatus: string | null;
  navn: string;
  foedselRaw: string | null;
  foedselMin: string | null;
  foedselMax: string | null;
  doedRaw: string | null;
  doedMin: string | null;
  doedMax: string | null;
  koen: string | null;
  levende: boolean;
  privat: boolean;
  staged: boolean;
  kanoniskPersonId: string | null;
  sammeSomStatus: string | null;
  antalTitler: number;
  antalFamilier: number;
  antalRelationer: number;
  qaKoder: string[];
  qaAlvor: 'fejl' | 'advarsel' | 'info' | null;
  reviewStatus: Partial<Record<OcrFelt, OcrReviewStatus>>;
  kanRettes: Record<OcrFelt, boolean>;
  blokarsager: Partial<Record<OcrFelt, string>>;
  ocrContext: Partial<Record<OcrFelt, string | null>>;
  kildeSide: Partial<Record<OcrFelt, string | null>>;
  importeret: Partial<Record<OcrFelt, Record<string, unknown>>>;
  korrigeret: Partial<Record<OcrFelt, Record<string, unknown> | null>>;
  inputFingerprint: Partial<Record<OcrFelt, string>>;
};

export function normaliserOcrDato(raw: string): {
  raw: string;
  min: string | null;
  max: string | null;
  qualifier: OcrDateQualifier | null;
  calendar: 'gregoriansk';
  certainty: 'certain' | 'uncertain' | 'ambiguous' | null;
  understood: boolean;
};

export type KvalitetsarkFilter = {
  preset: KvalitetsarkPreset;
  query: string;
  source: string | null;
  linje: string | null;
  felt: OcrFelt | null;
  reviewStatus: OcrReviewStatus | null;
  staged: boolean | null;
  sammeSom: boolean | null;
};

export function filterKvalitetsark(
  rows: PersonKvalitetsarkRow[],
  filter: KvalitetsarkFilter,
): PersonKvalitetsarkRow[];

export function sortKvalitetsark(
  rows: PersonKvalitetsarkRow[],
  key: KvalitetsarkSortKey,
  direction: 'asc' | 'desc',
): PersonKvalitetsarkRow[];
```

The JSON fixture has explicit input/output records and is the cross-language contract:

```json
[
  {
    "raw": "26. juli 1975",
    "min": "1975-07-26",
    "max": "1975-07-26",
    "qualifier": "exact",
    "certainty": null
  },
  {
    "raw": "ukendt",
    "min": null,
    "max": null,
    "qualifier": null,
    "certainty": null
  }
]
```

**Steps:**

- [ ] Extract representative cases from the existing Python validator tests into the
  shared JSON fixture: exact year/date, leap day, invalid date, Danish and German month
  names, Roman year, `ca.`, before, after, interval, floruit, OCR uncertainty, and
  unparseable text.
- [ ] Add a failing Python parameterized test proving `derive_date_info()` matches every
  fixture record. This protects current extraction behavior before the TypeScript port.
- [ ] Write failing TypeScript tests against the same fixture. Confirm unsupported raw
  text is preserved and returns null structured fields.
- [ ] Write failing filter tests proving:
  preset `alle` always contains every input row; `aabne` uses active QA codes without a
  completed review; search covers
  name, record key, source, line, and person ID; field/status/staged/same-as filters combine
  with AND semantics.
- [ ] Write failing stable-sort tests for text, dates with null last, QA severity, reverse
  direction, and deterministic `personId` tie-break.
- [ ] Run focused tests and capture RED:

```bash
npm test -w @daa/core -- ocrKvalitet.test.ts
```

- [ ] Port the relevant pure normalization rules from `validate.py::derive_date_info`
  into the core module, retaining the source function name/version in a header comment.
  Do not broaden or “clean up” parsing rules without adding the case to the shared fixture
  and both language tests. Use `Intl.Collator('da')` for grid text ordering and no
  React/Supabase imports.
- [ ] Export functions and types through `packages/core/src/index.ts`.
- [ ] Run:

```bash
npm test -w @daa/core -- ocrKvalitet.test.ts
npm test -w @daa/core
npm run typecheck -w @daa/core
python3 .claude/skills/daa-extract/scripts/test_validate.py
```

- [ ] Run `git diff --check`.
- [ ] Commit:

```bash
git add packages/core/src/ocrKvalitet.ts \
  packages/core/src/__tests__/ocrKvalitet.test.ts packages/core/src/index.ts \
  tests/fixtures/ocr-date-normalization.json \
  .claude/skills/daa-extract/scripts/test_validate.py
git commit -m "feat(core): tilføj kvalitetsarkets rene datalogik"
```

---

## Task 7: Web RPC Adapters and Stable Error Mapping

**Files:**
- Create: `web/src/data/personKvalitetsark.ts`
- Create: `web/src/data/__tests__/personKvalitetsark.test.ts`

**Interfaces:**

```ts
export async function fetchPersonKvalitetsark(): Promise<PersonKvalitetsarkRow[]>;

export type OcrHistorikEntry = {
  changeSetId: string;
  changedAt: string;
  actorNavn: string | null;
  operation: string | null;
  foer: Record<string, unknown> | null;
  efter: Record<string, unknown> | null;
};

export async function fetchOcrHistorik(
  importKey: string,
  recordKey: string,
  felt: OcrFelt,
): Promise<OcrHistorikEntry[]>;

export async function retOcrFelt(input: {
  personId: string;
  importKey: string;
  recordKey: string;
  felt: OcrFelt;
  inputFingerprint: string;
  korrigeret: Record<string, unknown> | null;
  status: 'rettet' | 'godkendt' | 'udskudt';
  actorNavn?: string;
}): Promise<PersonKvalitetsarkRow>;

export function oversaetOcrFejl(error: unknown): string;
```

**Steps:**

- [ ] Write a failing mapping test with a complete snake_case RPC row and assert the exact
  camelCase `PersonKvalitetsarkRow`, including `person_id` as a string to avoid unsafe
  JavaScript bigint coercion.
- [ ] Write a failing pagination test with more than one 1,000-row page. The adapter may
  use the repository's `getAll` helper around `supabase.rpc('red_person_grid')`; assert
  no per-person query is made.
- [ ] Write failing mutation tests for the exact `red_ret_ocr_felt` payload and returned
  row replacement.
- [ ] Write a failing lazy-history test for the exact `red_ocr_historik` parameters and
  newest-first result mapping.
- [ ] Write table-driven error tests for every `OCR_*` code and an unknown fallback.
- [ ] Capture RED with non-secret test environment values:

```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web -- personKvalitetsark.test.ts
```

- [ ] Implement the adapter as a focused module. Do not add the special correction shape
  to the generic `Change` union in `redaktionWrite.ts`.
- [ ] Validate essential row fields at the boundary and fail with a clear contract error
  if `person_id`, `qa_koder`, or editability maps have the wrong shape.
- [ ] Run the focused tests and web typecheck:

```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web -- personKvalitetsark.test.ts
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm run build -w web
```

- [ ] Run `git diff --check`.
- [ ] Commit:

```bash
git add web/src/data/personKvalitetsark.ts \
  web/src/data/__tests__/personKvalitetsark.test.ts
git commit -m "feat(web): tilføj dataadapter til OCR-kvalitetsark"
```

---

## Task 8: Spreadsheet Grid Component

**Files:**
- Create: `web/src/components/PersonKvalitetsark.tsx`
- Create: `web/src/components/__tests__/PersonKvalitetsark.test.tsx`

**Interfaces (component props):**

```ts
type PersonKvalitetsarkProps = {
  rows: PersonKvalitetsarkRow[];
  loading: boolean;
  error: string | null;
  selected: { personId: string; felt: OcrFelt } | null;
  onSelect: (selection: { personId: string; felt: OcrFelt }) => void;
  onOpenPerson: (personId: string) => void;
};
```

**Required columns in the default desktop layout:**

```text
QA | Navn | Født | Død | Køn | Kilde/udgave | Linje/post |
Titler | Familier | Relationer | levende | privat | staged | status | samme_som
```

**Steps:**

- [ ] Write a failing jsdom test that renders two physical rows with the same canonical
  person and proves both are visible.
- [ ] Write a failing interaction test for the permanent presets:
  `Alle personer`, `Åbne OCR-fejl`, `Rettede`, `Godkendte`, `Udskudte`, `Stale`.
  Switching back to `Alle personer` must restore every row without refetching.
- [ ] Write failing tests for search, combined filters, ascending/descending sort,
  null-last dates, hide/show columns, reset-to-default columns, and a visible result count.
- [ ] Write failing accessibility tests:
  semantic `<table>`, column-header buttons with `aria-sort`, selected cell state,
  keyboard focus, and descriptive labels for QA-only icons.
- [ ] Write a failing selection test:
  editable cell calls `onSelect`; blocked cell remains focusable, exposes its block reason,
  and offers `onOpenPerson`; count columns open the existing person editor.
- [ ] Add a failing wide-layout test asserting the table has horizontal overflow inside
  its own region and does not force the entire redaction app wider.
- [ ] Capture RED:

```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web -- PersonKvalitetsark.test.tsx
```

- [ ] Implement with a native semantic HTML table and sticky header/identity columns.
  Do not add a grid dependency for the current data size.
- [ ] Use existing `Redaktion.tsx` theme tokens (`T`) by passing a narrow token object or
  extracting only the already-shared tokens; do not introduce a second visual system.
- [ ] Keep each cell display-only. All writing belongs to Task 9's side panel.
- [ ] Run focused tests and `git diff --check`.
- [ ] Commit:

```bash
git add web/src/components/PersonKvalitetsark.tsx \
  web/src/components/__tests__/PersonKvalitetsark.test.tsx
git commit -m "feat(web): byg spreadsheet-grid til personkontrol"
```

---

## Task 9: OCR Source Panel and Redaktion Integration

**Files:**
- Create: `web/src/components/OcrKildepanel.tsx`
- Create: `web/src/components/__tests__/OcrKildepanel.test.tsx`
- Modify: `web/src/Redaktion.tsx`
- Create: `web/src/__tests__/Redaktion.kvalitetsark.test.tsx`

**Interfaces (panel and integration):**

```ts
type OcrKildepanelProps = {
  row: PersonKvalitetsarkRow;
  felt: OcrFelt;
  historik: OcrHistorikEntry[];
  historikLoading: boolean;
  busy: boolean;
  error: string | null;
  onSave: (input: RetOcrFeltInput) => Promise<void>;
  onClose: () => void;
  onOpenPerson: (personId: string) => void;
};
```

**Integration state:**

```ts
type PersonVisning = 'liste' | 'kvalitetsark';
```

The `Liste / Kvalitetsark` control is shown only for `entity === 'person'` and only for a
signed-in `session.role === 'redaktion'`. The existing list/editor remains the default
and unchanged for every other entity and role.

**Steps:**

- [ ] Write failing panel tests for name, date, and gender forms. Confirm the save payload
  includes the row's current fingerprint and exactly one field.
- [ ] Write a failing copy test that the evidence box is titled “OCR-kontekst” and includes
  the explicit note: “Konteksten er fra OCR-udtrækket, ikke en gengivelse af den trykte side.”
- [ ] Write failing date-warning tests:
  valid year/ISO shows derived bounds; unsupported text is preserved but requires a second
  explicit confirmation and sends null bounds.
- [ ] Write failing review-action tests:
  “Godkend som korrekt” and “Udskyd” send no corrected value and never optimistically
  change the field.
- [ ] Write a failing history test showing the selected field's newest-first correction
  history with actor and time; loading and empty states must be explicit.
- [ ] Write failing blocked/stale tests:
  no save button when `kanRettes[felt]` is false; stale fingerprint error keeps the panel
  open, refreshes the row, and asks the editor to review the new source input.
- [ ] Write integration tests in `Redaktion.kvalitetsark.test.tsx`:
  redactor sees the toggle; member/anonymous do not; entering quality mode fetches once;
  `Alle personer` is selected initially; a successful save replaces only the returned row;
  exiting returns to the existing person list without losing the currently selected person.
- [ ] Add a regression test proving media, lineage, and generic entity rendering do not
  mount the quality grid.
- [ ] Capture RED:

```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web -- OcrKildepanel.test.tsx Redaktion.kvalitetsark.test.tsx
```

- [ ] Implement `OcrKildepanel` with explicit Save/Cancel and no autosave.
- [ ] Fetch correction history lazily when a cell is selected. Refresh only that history
  after a successful save; never fetch history once per grid row.
- [ ] Integrate a person-mode toggle near the existing person list header. Persist the
  chosen mode in `localStorage` only after validating the stored value; always keep
  “Alle personer” available inside quality mode.
- [ ] Lazy-load grid rows on first entry into quality mode. Cache them for the session;
  expose an explicit “Genindlæs” action; do not refresh the full grid after each save.
- [ ] On successful save, replace the single returned row by `personId` and keep current
  filters/sort/selection. On failure, leave local data unchanged.
- [ ] Use a wide desktop workspace: grid consumes the former list+editor area and panel
  occupies a fixed right side. Leave the left entity sidebar and top bar intact.
- [ ] Do not add mobile styles or responsive promises. At narrow widths, show the existing
  web app's overflow behavior rather than silently collapsing fields.
- [ ] Run focused tests, the complete web suite, and build:

```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web -- OcrKildepanel.test.tsx Redaktion.kvalitetsark.test.tsx
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm run build -w web
```

- [ ] Run `git diff --check`.
- [ ] Commit:

```bash
git add web/src/components/OcrKildepanel.tsx \
  web/src/components/__tests__/OcrKildepanel.test.tsx \
  web/src/Redaktion.tsx web/src/__tests__/Redaktion.kvalitetsark.test.tsx
git commit -m "feat(web): integrer kildekontrol i personkvalitetsarket"
```

---

## Task 10: End-to-End Verification and Deployment Handoff

**Files:**
- Modify: `docs/changelog.md`
- Modify: `docs/database-current-state.md`
- Create: `docs/runbooks/person-ocr-kvalitetsark.md`

**Interfaces (handoff contract):**

The runbook must distinguish these states explicitly:

```text
code_ready | local_db_verified | production_db_migrated | web_deployed | smoke_verified
```

Completing this task may set only `code_ready` and `local_db_verified`. The other three
states require later explicit user authorization and fresh evidence.

**Steps:**

- [ ] On a fresh disposable PostgreSQL database, run:
  `schema.sql`, `db-migrations.sql` twice, `db-rls.sql`, and the new scoped
  `db-verify.sql` blocks. Record database version and exact results in the runbook.
- [ ] On an upgrade-shaped disposable database, apply only the migration/RLS path and
  confirm legacy rows with null keys remain readable but non-editable.
- [ ] Load the minimal fixture, correct all four fields through the RPC, run a reset load,
  and verify:
  correction values survive; journal IDs survive; stable keys survive; a deliberately
  changed OCR context yields `stale`; no stale correction is replayed.
- [ ] Verify `anon`, member, and redactor permissions using impersonated JWT claims, not
  only function-owner calls.
- [ ] Run all local automated gates from repository root:

```bash
Rscript run-tests.R
npm test -w @daa/core
npm run typecheck -w @daa/core
npm test -w @daa/feed
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm test -w web
VITE_SUPABASE_URL=http://127.0.0.1:54321 \
VITE_SUPABASE_ANON_KEY=test-anon-key \
npm run build -w web
npm test -w mobile
git diff --check
```

- [ ] Manually smoke-test at desktop width:
  switch List/Kvalitetsark; select “Alle personer”; combine QA/search/source filters;
  sort each editable column; open a blocked row in the existing editor; correct one field;
  approve one; defer one; reload the browser; verify the source panel wording.
- [ ] Inspect the grid with at least the expected production-scale row count and record:
  initial RPC duration, response size, browser render time, and whether native-table
  rendering remains responsive. If it does not, stop and design row virtualization or
  server-side cursor paging as a separate follow-up rather than silently changing v1.
- [ ] Update `docs/changelog.md` with code/artifact readiness only. Update
  `docs/database-current-state.md` only after a later approved production migration;
  until then, mark the feature “kodeklar, ikke deployet”.
- [ ] Write the deployment runbook with this gated order:
  backup/restore check → scoped migration → `db-rls.sql` → DB verification →
  loader import-key rollout/reload decision → web deployment → redactor smoke test.
  Each production mutation requires a fresh explicit user approval.
- [ ] Review the final diff against every Global Constraint and the authoritative design.
  Search for placeholders:

```bash
git diff --unified=0 HEAD^ -- \
  schema.sql db-migrations.sql db-rls.sql db-verify.sql \
  .claude/skills/daa-extract/scripts packages/core/src web/src \
  docs/runbooks/person-ocr-kvalitetsark.md |
  rg "^\\+.*([T]ODO|[F]IXME|[T]BD|[P]LACEHOLDER)"
```

- [ ] Confirm type consistency across SQL snake_case → adapter mapping → core type →
  component props, especially bigint IDs and nullable date fields.
- [ ] Commit documentation:

```bash
git add docs/changelog.md docs/database-current-state.md \
  docs/runbooks/person-ocr-kvalitetsark.md
git commit -m "docs(redaktion): beskriv drift af OCR-kvalitetsark"
```

- [ ] Run the complete gate one final time on the committed HEAD. Report exact passing
  counts, any environment-only blockers, changed files, commit list, and the explicit
  statement that production, push, and PR were not touched.

## Definition of Done

- A redactor can switch from the existing person list to a web-only quality grid and
  always choose “Alle personer”.
- Every physical person row is visible independently of `samme_som`.
- Filters, search, sorting, selection, QA presets, and count links work without N+1 reads.
- Name, birth, death, and gender can be corrected one field at a time only when the
  import anchor and target assertion are unambiguous.
- The source panel truthfully distinguishes OCR context from printed source imagery.
- Corrections preserve evidence identity, produce change history, are undoable, and
  atomically update the durable journal.
- Corrections survive a loader reset by stable import/record key and do not replay when
  their source fingerprint changes.
- Anonymous/member access is denied server-side; redaction access is explicitly granted
  and RLS-protected.
- Core, R, feed, web, mobile regression, database verification, build, and diff checks
  pass, or any pre-existing/environment blocker is documented precisely without being
  presented as feature success.
- No production database, deployment, push, or pull request has been changed without a
  later explicit user instruction.
