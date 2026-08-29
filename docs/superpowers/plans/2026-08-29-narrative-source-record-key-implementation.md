# Narrative Source-Record Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement roadmapmål #152 as an editions-neutral, record-keyed and append-only publication contract for person/DAA narratives, prove it end-to-end in disposable infrastructure, and stop before any production mutation.

**Architecture:** PostgreSQL owns record resolution, authority checks, canonical state hashes, immutable publication events, current projections, legacy disposition and the atomic versioned cutover. Shared TypeScript owns only public row mapping and deterministic ordering. Web gets the full record editor; mobile gets a capability-aware, fail-closed minimum. Read-only manifest tooling binds every baseline row and production precondition to exact bytes before a later separately approved cutover.

**Tech Stack:** PostgreSQL 17, PL/pgSQL, Supabase Auth/RLS/PostgREST, `dblink`, R 4.x with DBI/RPostgres/jsonlite/digest/testthat, Python 3 stdlib/pytest for local approval artifacts, TypeScript, React/Vitest, React Native/Jest, Playwright Chromium.

**Spec:** `docs/superpowers/specs/2026-08-29-narrative-source-record-key-design.md`

## Global Constraints

- This plan belongs to roadmapmål #152. It closes the publication-gate and public read-projection link in the shared evidence chain; it is a permanent editions-neutral mechanism plus explicitly temporary legacy retirement.
- The editorial value is independent maintenance and publication of multiple concrete records from the same DAA edition without first-row selection or text concatenation.
- Completion means disposable database, real concurrency, schema/RLS/ACL verification, focused and full client suites, production-shaped restore rehearsal, and real-browser smoke evidence. A green isolated SQL test alone is insufficient.
- No task in this plan mutates production, deploys a client, pushes a branch, or merges to `main`. Task 13 stops at `READY_FOR_PRODUCTION_REVIEW` and requests a new explicit GO.
- Execute tasks in order. Finish each task with its focused tests, spec-conformance review, code-quality review, status checkpoint and separate commit. Do not auto-continue past a failed gate.
- Treat `schema.sql`, `db-migrations.sql`, `db-rls.sql` and executable tests as one contract. Additive objects are present in both schema and migration truth; access rules live explicitly in `db-rls.sql` and are asserted by tests.
- Every privileged function uses a fixed schema-qualified `search_path`, explicit editor/service role checks where applicable, `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, and only the minimum subsequent `GRANT EXECUTE`. RLS and grants are independent gates and both must pass.
- Private UUIDs (`source_record.id`, binding IDs and internal identity rows) never cross public or first-party client contracts. Editors address records only by `(source_id, record_key)`; public clients use `source_record_ref`.
- Every mutation takes `pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0))` first, re-reads contract version under that lock and follows the canonical record-first row-lock order. Cutover alone takes the exclusive form of the same lock.
- Old paths require contract version `1`; new record writers require version `2`. ACL revocation supplements this runtime guard and is never the sole concurrency proof.
- Publication history is append-only. Do not update or delete publication events, synthesize identity decisions, rewrite old C3 bindings, mutate legacy text during withdrawal, or use generic change-set undo for publication events.
- `state_sha256` is computed only from one canonical server-side JSON function. Readers, writers, history and tests must not each invent a state representation.
- A published text has no ordinary save path. Text change requires `published_revision`; text change with `haendelse` rows fails closed.
- Keep 2018-20 legacy text read-only. Only its exact hash-locked ledger row may be withdrawn or safely restored by dedicated event reversal.
- New bindings without exactly one accepted principal/co-principal canonical person remain blocked. The approved temporary freeze is not to be weakened to make a test or UI flow pass.
- `red_slet_person` fails before any writes when publication events exist. This plan does not decide permanent person tombstone/retention.
- Baseline and legacy manifests use exact ordered ID sets and non-optional SHA-256 values. Count equality alone, dynamic production `INSERT ... SELECT`, and an approval surviving any byte drift are forbidden.
- Narrative identity sequence resync happens under the exclusive cutover and narrative table lock, never lowers the sequence, and floors above live narrative IDs, historical `change_event` row IDs, event narrative IDs and the already allocated next sequence value.
- Use all five `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` variables together for database integration, or omit all five. Never infer production credentials from the working directory.
- Do not read, stage or modify `work/` or the untracked external review file while implementing this plan.

## File Map

Database truth and verification:

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Create: `tests/sql/test-narrative-record-contract.sql`
- Create: `tests/sql/test-narrative-record-cutover.sql`
- Create: `tests/integration/test-narrative-record-concurrency.R`
- Modify: `.github/workflows/ci.yml`

Cutover artifacts and rehearsal:

- Create: `.claude/skills/daa-extract/scripts/export_narrative_record_cutover.R`
- Create: `.claude/skills/daa-extract/scripts/export_narrative_record_cutover_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py`
- Create: `.claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py`
- Create: `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R`
- Create: `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover_helpers.R`
- Create: `tests/testthat/test-export-narrative-record-cutover.R`
- Create: `tests/testthat/test-apply-narrative-record-cutover.R`
- Create: `.claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py`

Existing writer gates:

- Modify: `.claude/skills/daa-extract/scripts/load_daa.R`
- Modify: `R/update-1939-narratives.R`
- Modify: `R/update-2018-narratives.R`
- Modify: `tests/testthat/test-load-daa.R`
- Modify: `tests/testthat/test-update-1939-narratives.R`
- Modify: `tests/testthat/test-update-2018-narratives.R`
- Create: `tests/testthat/test-narrative-record-source-inventory.R`

Shared public contract:

- Modify: `packages/core/src/bioVersions.ts`
- Modify: `packages/core/src/__tests__/bioVersions.test.ts`
- Modify: `web/src/data/public.ts`
- Modify: `web/src/data/__tests__/orThrow.test.ts`
- Modify: `web/src/data/feedAux.ts`
- Modify: `web/src/data/__tests__/feedAux.test.ts`
- Modify: `mobile/src/data/publicBioVersions.ts`
- Modify: `mobile/src/data/__tests__/publicBioVersions.test.ts`
- Modify: `mobile/src/data/load.ts`
- Modify: `mobile/src/data/__tests__/load.test.ts`

Web editor and history:

- Modify: `web/src/data/redaktionRead.ts`
- Modify: `web/src/data/redaktionWrite.ts`
- Modify: `web/src/data/historik.ts`
- Create: `web/src/components/PersonNarrativeRecordEditor.tsx`
- Create: `web/src/components/__tests__/PersonNarrativeRecordEditor.test.tsx`
- Modify: `web/src/components/HistorikPanel.tsx`
- Modify: `web/src/components/__tests__/HistorikPanel.test.tsx`
- Modify: `web/src/data/__tests__/redaktionRead.narrativer.test.ts`
- Modify: `web/src/data/__tests__/redaktionWrite.narrativ.test.ts`
- Modify: `web/src/data/__tests__/historik.test.ts`
- Modify: `web/src/Redaktion.tsx`

Minimal mobile migration:

- Modify: `mobile/src/data/redaktionRead.ts`
- Modify: `mobile/src/data/redaktionWrite.ts`
- Modify: `mobile/src/components/redaktion/NarrativEditor.tsx`
- Create: `mobile/src/components/redaktion/__tests__/NarrativEditor.recordContract.test.tsx`
- Modify: `mobile/src/data/__tests__/redaktionRead.test.ts`
- Modify: `mobile/src/data/__tests__/redaktionWrite.test.ts`

Evidence and governance:

- Create: `docs/evidensbaseret-genimport/narrative-record-key-152-rehearsal.md`
- Create: `docs/runbooks/narrative-record-key-cutover.md`
- Modify: `docs/evidensbaseret-genimport/status.md` only after the corresponding evidence exists.
- Modify: `docs/evidensbaseret-genimport/roadmap.md` only when the maturity state is evidence-backed.

---

### Task 1: Add the additive schema, contract version and immutable event foundation

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Create: `tests/sql/test-narrative-record-contract.sql`
- Modify: `db-verify.sql`

**Interfaces:**

```sql
public.narrative_record_contract_version() RETURNS integer

private.source_record.public_ref uuid NOT NULL UNIQUE

private.narrative_publication_event(
  id uuid PRIMARY KEY,
  change_set_id bigint NOT NULL,
  stream_ref uuid NOT NULL,
  stream_version integer NOT NULL,
  event_type text NOT NULL,
  narrative_id bigint,
  source_record_id uuid,
  legacy_publication_ref uuid,
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  before_state_sha256 text,
  after_state_sha256 text NOT NULL,
  reversed_event_id uuid,
  decided_by uuid,
  decided_by_name text NOT NULL,
  created_at timestamptz NOT NULL,
  UNIQUE(stream_ref, stream_version)
)

private.narrative_legacy_publication(
  legacy_publication_ref uuid PRIMARY KEY,
  narrative_id bigint NOT NULL UNIQUE,
  baseline_state jsonb NOT NULL,
  baseline_sha256 text NOT NULL,
  status text NOT NULL,
  latest_event_id uuid,
  created_at timestamptz NOT NULL
)
```

- [ ] **Step 1: Write failing structural tests.** In `tests/sql/test-narrative-record-contract.sql`, assert `public_ref` exists, is `NOT NULL`/unique, cannot be updated, both private tables and their exact CHECK/UNIQUE/FK constraints exist, event update/delete raises `NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY`, private relations have RLS enabled, and contract version returns exactly `1`.

- [ ] **Step 2: Run the focused test against a fresh disposable database and confirm RED.** Apply `tests/sql/evidence-promotion-bootstrap.sql`, `schema.sql`, `db-rls.sql`, then the new test. Expected first failure: missing `private.source_record.public_ref` or `public.narrative_record_contract_version()`.

```bash
PGDATABASE=daa_narrative_152 PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres \
  /opt/homebrew/opt/postgresql@17/bin/psql -v ON_ERROR_STOP=1 -f tests/sql/test-narrative-record-contract.sql
```

- [ ] **Step 3: Implement additive DDL in `schema.sql`.** Backfill `public_ref` with `gen_random_uuid()`, then enforce `NOT NULL`, uniqueness and an immutability trigger. Add event/legacy tables, append-only/shape triggers and private RLS. Include event types `baseline`, `draft_created`, `draft_updated`, `draft_discarded`, `published`, `published_revision`, `revalidated`, `withdrawn`, `legacy_withdrawn`, `reversal`.

- [ ] **Step 4: Mirror the deployable, idempotent block at the end of `db-migrations.sql`.** Existing rows receive stable random refs once; reruns preserve them. Install `narrative_record_contract_version()` returning `1`. Fix `schema.sql`'s current `red_upsert_narrativ` insert to use the narrative identity default instead of `max(id)+1`, matching the effective migration definition.

- [ ] **Step 5: Add integrity assertions to `db-verify.sql`.** Verify public refs are non-null/unique, every event hash has 64 lowercase hex characters, exactly one target kind is present, reversal points backward within the same stream, immutable triggers reject mutations, and no client role can directly access either private table.

- [ ] **Step 6: Run schema/migration parity both ways.** Fresh path: bootstrap → `schema.sql` → `db-rls.sql`. Upgrade path: a pre-Task-1 base → `db-migrations.sql` twice → `db-rls.sql`. Both must pass the focused SQL test; the second migration run must change zero existing public refs.

- [ ] **Step 7: Review and commit.** Confirm no new writer has a grant, version remains `1`, no baseline events are auto-created, and no legacy row becomes public merely from this additive task.

```bash
git add schema.sql db-migrations.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
git commit -m "feat(db): add narrative publication event foundation"
```

### Task 2: Implement one canonical record state, authority resolver and editor read/history RPCs

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-narrative-record-contract.sql`

**Interfaces:**

```sql
private.narrative_record_state(
  p_person_id bigint,
  p_source_id bigint,
  p_record_key text,
  p_lock boolean DEFAULT false
) RETURNS jsonb

private.narrative_legacy_state(
  p_legacy_publication_ref uuid,
  p_lock boolean DEFAULT false
) RETURNS jsonb

public.red_person_narrative_records(p_person_id bigint) RETURNS SETOF jsonb

public.red_person_narrative_publication_history(p_person_id bigint)
RETURNS SETOF jsonb
```

- [ ] **Step 1: Add failing state-contract fixtures.** Seed records covering accepted principal identity, accepted co-principal identity, empty identity, two-person ambiguity, conflicting existing binding, one accepted anchor, missing anchor, active placement, withdrawn-only history, active draft, published, stale projection and active legacy.

- [ ] **Step 2: Assert canonical JSON exactly, not by selected fields.** Expected state includes person/source/record locator, internal record identity only inside the hash input, public ref, ordered anchor/placement/identity/revision snapshots, authority kind, binding/withdrawn history, narrative/text/privacy/side, latest event, labels, policy/provenance hashes and `has_haendelse`. Hash must equal `encode(digest(canonical_json::text,'sha256'),'hex')` in every consumer.

- [ ] **Step 3: Implement record resolution and lock mode.** `p_lock=false` is stable read; `p_lock=true` takes source record first, then bindings ordered by stable key, latest event, narrative, and current evidence rows in the spec order. Absence is protected by the already locked source record. Do not expose internal UUIDs from public RPCs.

- [ ] **Step 4: Implement identity authority exactly.** For a new binding, the set of current accepted `canonical_person_id` values reached through accepted `principal_member`/`co_principal` placements must equal `{p_person_id}`. For an existing exact binding, allow `existing_exact_binding` only if no accepted principal/co-principal identity conflicts.

- [ ] **Step 5: Implement the single label projector.** Preserve existing binding labels. For a new binding use exactly one accepted placement label, otherwise `record_key`; derive citation from source label plus distinct current accepted anchor page intervals in numeric order. Missing current anchor fails with `NARRATIVE_RECORD_ANCHOR_REQUIRED`.

- [ ] **Step 6: Implement editor read and history RPCs.** Record rows return safe locator, public ref, status, editable action set, event-derived text, labels and `state_sha256`. Legacy rows return immutable `legacy_publication_ref`, text, active/withdrawn disposition and no edit action. History rows return `event_id`, `change_set_id`, stream/version, event type, safe target ref, before/after hashes, `can_reverse` and blocking reason.

- [ ] **Step 7: Verify roles and data minimization.** Anonymous/member calls fail; redaction succeeds. Search serialized RPC output for source-record UUIDs, private policy JSON and identity row IDs and require zero matches.

- [ ] **Step 8: Run focused SQL and commit.** Expected notices cover every authority and state fixture, label determinism, lock order and history mapping.

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
git commit -m "feat(db): expose canonical narrative record state"
```

### Task 3: Implement record draft, publish, revision, revalidation, discard and withdrawal writers

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-narrative-record-contract.sql`

**Interfaces:**

```sql
public.red_upsert_person_narrative_record(
  p_person_id bigint, p_source_id bigint, p_record_key text,
  p_tekst text, p_privat boolean, p_expected_state_sha256 text
) RETURNS jsonb

public.red_publicer_person_narrative_record(
  p_person_id bigint, p_source_id bigint, p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb

public.red_revider_publiceret_person_narrative_record(
  p_person_id bigint, p_source_id bigint, p_record_key text,
  p_tekst text, p_expected_state_sha256 text
) RETURNS jsonb

public.red_revalider_person_narrative_record(
  p_person_id bigint, p_source_id bigint, p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb

public.red_kasser_person_narrative_record(
  p_person_id bigint, p_source_id bigint, p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb

public.red_tilbagetraek_person_narrative_record(
  p_person_id bigint, p_source_id bigint, p_record_key text,
  p_expected_state_sha256 text
) RETURNS jsonb
```

- [ ] **Step 1: Write transition-table tests before functions.** Cover every row in spec §6.2/§6.3, including missing/two identities, conflict, legacy, no anchor, stale state, published ordinary save, stale publication, derived `haendelse`, private/staged/alive publication and withdrawn-only new draft.

- [ ] **Step 2: Confirm RED.** Each call currently fails with missing function. Record the exact expected stable code for every negative case; tests must snapshot the complete pre/post write set and prove no side effect after rejection. After the functions exist, run transition cases inside a rollback-scoped fixture that replaces only `narrative_record_contract_version()` with constant `2`; never weaken the production version check.

- [ ] **Step 3: Add one private mutation kernel used by all six RPCs.** It takes the shared cutover lock first, requires version `2`, checks editor role, delegates canonical state/locks to Task 2, opens exactly one change set, performs exactly one legal projection transition and appends exactly one event whose `after_state_sha256` equals the post-write canonical state.

- [ ] **Step 4: Keep public writers ungranted in additive phase.** Define functions and explicit revokes in schema/migration; do not grant `authenticated` until Task 7 cutover. Replace `db-rls.sql`'s broad `red_*` grant loop with signature-aware grants plus an explicit deny-list for these eight mutation RPCs and the private cutover kernel. Editor read/history RPCs may be granted. Tests invoke mutation functions as owner only inside the version-2 fixture and assert an authenticated editor still receives permission denied while contract version is `1`.

- [ ] **Step 5: Implement narrative allocation and preservation.** New narrative uses identity default. Draft discard/withdraw marks projection withdrawn; it never deletes narrative, binding or events. A fresh draft after withdrawn history creates a new narrative/binding stream and preserves old text byte-for-byte.

- [ ] **Step 6: Implement publication snapshots.** `published` and `published_revision` carry complete old/new text plus occurrence/rendition/identity/policy/provenance inputs. Ordinary upsert cannot alter published text. Revision with any `haendelse` fails `NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`.

- [ ] **Step 7: Assert exact write sets.** A successful call adds one change set and one event and changes only the expected narrative/binding rows. A rejected call adds none. Returned JSON includes safe locator, `event_id`, `narrative_id`, current status and new `state_sha256`, but no binding/source-record UUID.

- [ ] **Step 8: Run focused SQL and commit.** Also rerun existing C3 SQL tests to show the additive definitions have not changed C3 behavior while version is `1`.

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
git commit -m "feat(db): add record keyed narrative writers"
```

### Task 4: Implement legacy withdrawal, dedicated reversal, undo routing and person-delete block

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-narrative-record-contract.sql`

**Interfaces:**

```sql
public.red_tilbagetraek_legacy_narrative(
  p_legacy_publication_ref uuid,
  p_expected_state_sha256 text,
  p_begrundelse text
) RETURNS jsonb

public.red_fortryd_person_narrative_publication_event(
  p_event_id uuid,
  p_expected_state_sha256 text
) RETURNS jsonb
```

- [ ] **Step 1: Write RED tests for legacy withdrawal.** Active exact baseline becomes withdrawn; only that biography disappears from the publication predicate; text and `narrative.privat` are unchanged; blank reason, stale hash, unknown ref, already withdrawn or baseline drift rejects without writes.

- [ ] **Step 2: Write RED tests for each reversal class.** Cover draft create/update/discard, publish, published revision, revalidate, record withdraw and legacy withdraw. Reject non-latest, already reversed, drifted state, cross-stream target, reversal target and any restoration that fails current privacy/identity/provenance policy.

- [ ] **Step 3: Implement legacy withdrawal and one reversal kernel.** Legacy lock order is ledger → latest event → narrative. Reversal appends a new `reversal` event referencing the target and restores semantic before-state without deleting history. Reversal of draft creation leaves a withdrawn projection.

- [ ] **Step 4: Gate generic undo before it creates a reversal change set.** Add this exact first predicate to `red_fortryd_change_set` in schema and migration:

```sql
IF EXISTS (
  SELECT 1
  FROM private.narrative_publication_event
  WHERE change_set_id = p_change_set_id
) THEN
  RAISE EXCEPTION 'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED';
END IF;
```

- [ ] **Step 5: Block person hard-delete safely.** `red_slet_person` takes the shared contract lock before its existing locks and fails `PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY` before `begin_change_set` if any publication event reaches a narrative for the person. `red_slet_person_preview` returns `antal_publication_events` and `sletning_blokeret=true` without exposing private event payloads.

- [ ] **Step 6: Prove generic history mapping.** The history RPC maps each publication change set to the dedicated event. `can_reverse` is true only for the latest legal event; reversal rows have false plus `NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE`.

- [ ] **Step 7: Run focused SQL, existing generic undo tests and commit.** Require unchanged behavior for change sets with no publication event.

```bash
git add schema.sql db-migrations.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
git commit -m "feat(db): reverse narrative publication events safely"
```

### Task 5: Build the event-gated public v2 contract and exhaustive person/DAA RLS

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-narrative-record-contract.sql`

**Interface:**

```sql
public.public_person_bio_source_versions_v2(p_person_ids bigint[])
RETURNS TABLE(
  person_id bigint,
  source_id bigint,
  source_year integer,
  record_order integer,
  source_record_ref uuid,
  source_label text,
  record_label text,
  narrative_text text,
  citation_label text,
  provenance_kind text
)
```

- [ ] **Step 1: Write a matrix test before the predicate.** As `anon`, ordinary `authenticated` and redaction, test bound published/current, draft, withdrawn, stale text/anchor/rendition/identity/privacy/policy, active legacy, withdrawn legacy, drifted legacy and new unbound row. Repeat through v1 RPC, v2 RPC and direct `SELECT public.narrative`.

- [ ] **Step 2: Include unaffected controls.** A non-person narrative and a person narrative from a non-DAA source preserve existing privacy/person gates. A `haendelse` under an invalid person/DAA publication disappears through the existing `EXISTS narrative` cascade; an unaffected event remains visible.

- [ ] **Step 3: Implement one server publication predicate.** Reduce the latest append-only event state, compare projection/text/provenance/identity/privacy/policy hashes, or validate active legacy baseline. Use it from v1, v2 and RLS rather than copying eligibility rules. Install all three surfaces version-aware: version `1` preserves the current public behavior; version `2` activates the exhaustive event/ledger branch. SQL tests temporarily flip the function to `2` inside a rolled-back transaction to exercise that branch before cutover.

- [ ] **Step 4: Return authoritative event text from v2.** Do not read a potentially drifted `narrative.tekst` as the public text oracle. Return one row per record, stable public ref, structured sort fields and no `record_key`/private UUID/identity payload.

- [ ] **Step 5: Replace anon/auth narrative policies exhaustively for person/DAA only.** At contract version `1`, preserve the current policy. At version `2`, apply the bound-event/active-ledger predicate. Preserve redaction-read access through its existing policy. Keep explicit table and safe boolean-helper execute grants; do not assume the new RLS policy revokes anything.

- [ ] **Step 6: Keep v1 signature but make its active branch explicit.** At version `1`, preserve compatibility before baselines exist. At version `2`, v1 must not publish a row rejected by v2. New unbound legacy never appears merely because it is public/non-private after activation.

- [ ] **Step 7: Verify security metadata.** Assert function owner, `prosecdef`, fixed `search_path`, exact grants, RLS enabled/forced expectations and zero direct private-table grants to `PUBLIC`, `anon`, `authenticated`.

- [ ] **Step 8: Run focused SQL plus full disposable `db-verify.sql` and commit.** Report focused and full results separately.

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
git commit -m "feat(db): gate public biographies by publication events"
```

### Task 6: Instrument every old writer and direct R loader with the shared version gate

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R`
- Modify: `R/update-1939-narratives.R`
- Modify: `R/update-2018-narratives.R`
- Modify: `tests/sql/test-narrative-record-contract.sql`
- Modify: `tests/testthat/test-load-daa.R`
- Modify: `tests/testthat/test-update-1939-narratives.R`
- Modify: `tests/testthat/test-update-2018-narratives.R`
- Create: `tests/testthat/test-narrative-record-source-inventory.R`

- [ ] **Step 1: Enumerate and pin the live writer set in a test.** `tests/testthat/test-narrative-record-source-inventory.R` must require definitions/references for `red_upsert_narrativ`, `red_publicer_narrative_record(bigint,uuid,text,text)`, `red_tilbagetraek_narrative_record(bigint)`, C3's `red_apply_reimport_cases`, `load_daa.R`, both updater scripts and `red_slet_person`. Historical C0/phase-B scripts are classified as one-shot consumers blocked by the DB gate. A new direct person/DAA writer must make the inventory test fail until classified.

- [ ] **Step 2: Write two-session cutover-lock tests.** Session A starts an old writer and waits; session B takes exclusive cutover lock and flips version to `2`; when A proceeds it must re-read version and reject without writes. Reverse the roles to show new writer cannot pass at version `1`.

- [ ] **Step 3: Instrument DB writers.** Shared advisory lock is the first transaction lock, followed by contract-version check and only then existing 1939/identity locks. At version `2`, `red_upsert_narrativ` rejects only person + `source.slags='DAA-udgave'` with `NARRATIVE_RECORD_REQUIRED`; non-person and non-DAA behavior remains green.

- [ ] **Step 4: Instrument loader/updaters before first mutation.** Each script opens one transaction, takes the shared lock, reads contract version, and aborts the entire run at `2` with `NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED`. At `1`, existing dry-run and write call ordering remain byte-for-byte compatible.

- [ ] **Step 5: Assert no hidden fallback.** Testthat fakes return version `2` and assert zero `dbExecute`/writer RPC calls after the gate. Version `1` tests assert the gate precedes every existing writer/loader lock.

- [ ] **Step 6: Run focused R and SQL tests.** Expected PASS:

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-load-daa.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-update-1939-narratives.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-update-2018-narratives.R")'
```

- [ ] **Step 7: Commit the complete writer gate as one atomic batch.** Do not merge only DB or only R protection.

```bash
git add schema.sql db-migrations.sql .claude/skills/daa-extract/scripts/load_daa.R R/update-1939-narratives.R R/update-2018-narratives.R tests/sql/test-narrative-record-contract.sql tests/testthat/test-load-daa.R tests/testthat/test-update-1939-narratives.R tests/testthat/test-update-2018-narratives.R tests/testthat/test-narrative-record-source-inventory.R
git commit -m "fix(import): gate legacy narrative writers at cutover"
```

### Task 7: Build exact manifests, approval conversion and atomic cutover/recovery gateway

**Files:**

- Create: `.claude/skills/daa-extract/scripts/export_narrative_record_cutover.R`
- Create: `.claude/skills/daa-extract/scripts/export_narrative_record_cutover_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py`
- Create: `.claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py`
- Create: `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R`
- Create: `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover_helpers.R`
- Create: `tests/testthat/test-export-narrative-record-cutover.R`
- Create: `tests/testthat/test-apply-narrative-record-cutover.R`
- Create: `.claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py`
- Create: `tests/sql/test-narrative-record-cutover.sql`
- Modify: `schema.sql`
- Modify: `db-migrations.sql`

**Interfaces:**

```sql
private.apply_narrative_record_cutover(
  p_record_manifest_raw text,
  p_legacy_manifest_raw text,
  p_inventory_raw text,
  p_approval_raw text,
  p_nonce uuid,
  p_expected_database_name text,
  p_expected_system_identifier text
) RETURNS jsonb

CREATE TABLE private.narrative_record_cutover_receipt(
  nonce uuid PRIMARY KEY,
  record_manifest_sha256 text NOT NULL,
  legacy_manifest_sha256 text NOT NULL,
  inventory_sha256 text NOT NULL,
  approval_sha256 text NOT NULL,
  database_name text NOT NULL,
  system_identifier text NOT NULL,
  sequence_before bigint NOT NULL,
  sequence_floor bigint NOT NULL,
  sequence_after bigint NOT NULL,
  result jsonb NOT NULL,
  result_sha256 text NOT NULL,
  committed_at timestamptz NOT NULL
)
```

**Artifacts:**

```text
narrative-record-baseline-manifest-v1.json
narrative-legacy-baseline-manifest-v1.json
narrative-record-cutover-inventory-v1.json
narrative-record-cutover-approval-v1.json
narrative-record-cutover-receipt-v1.json
```

- [ ] **Step 1: Write pure exporter tests.** Feed duplicate IDs, null/non-hex hashes, changed row order, extra/missing rows, ambiguous binding, non-DAA row and drifted snapshot. Require stable canonical JSON, exact sorted ID sets, database name/system identifier, schema contract and separate whole-file SHA-256 values. Generate each legacy candidate's random `legacy_publication_ref` once into the candidate manifest; rerunning creates a new manifest that requires new approval rather than silently reusing an unapproved ref.

- [ ] **Step 2: Implement one read-only repeatable-read exporter.** It opens `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`, takes the shared cutover lock, measures binding baselines and eligible legacy independently, and writes only to an explicit mode-`0700` output directory outside the repository with mode-`0600` files. It refuses the repository root and every `work/` path. Inventory includes counts by source, accepted identities, records blocked by identity and classified direct readers.

- [ ] **Step 3: Build a local offline review surface and converter.** The HTML uses safe DOM APIs, embeds exact manifest hashes and asks the concrete question for every candidate: record baseline `godkend baseline`/`uafklaret`; legacy `bevar offentligt som grandfathered`/`skjul ved cutover`/`uafklaret`. No bulk action converts unresolved rows to approval. It exports deterministic text/JSON and never connects to database/network. The converter rejects missing, duplicate, unknown or altered decisions; derives the final exact legacy ID set only from explicit `bevar offentligt` decisions; and binds approval SHA to both final manifest bytes and inventory bytes.

- [ ] **Step 4: Write cutover RED tests.** Assert any missing/extra/drifted baseline row aborts before mutation; approval mismatch aborts; database identity mismatch aborts; dynamic rows outside approved ID sets are never inserted.

- [ ] **Step 5: Implement the private cutover kernel and append-only receipt.** Hash each raw text argument before parsing it, validate the approval's embedded hashes, then under the exclusive shared-gate key and one transaction validate exact manifests, lock narrative, compute monotone sequence floor, create baseline events/legacy ledger, activate the already installed version-aware v1/RLS branch, apply exact grants/revokes, and change contract version to `2` last. A receipt records input hashes, exact event/ledger IDs, sequence before/floor/after and post-state hash. Its update/delete trigger is append-only. No client role gets execute on the private kernel or receipt table.

- [ ] **Step 6: Implement the production-shaped R gateway.** Required modes are `preflight`, `rollback`, `apply`, `recover`; all require explicit artifact paths, nonce, expected DB name/system identifier and all-five PG env. `rollback` runs the real cutover then rolls back and compares exact before-state. `recover` resolves a lost commit only from nonce + all hashes + exact receipt; ambiguity returns `CUTOVER_RECOVERY_REQUIRED`.

- [ ] **Step 7: Prove sequence safety.** Test live high narrative ID, deleted historical ID retained in `change_event`, event-referenced narrative ID above live max, and already allocated sequence value above all three. Next default insert must succeed; rerun never lowers sequence.

- [ ] **Step 8: Prove grant/version atomicity.** Before commit, clients remain v1 and new writer uncallable. After commit, version is `2`, new writer grants exist, old publish/withdraw grants are absent, old person/DAA writer rejects, and v1/v2/RLS all use baselines. No intermediate observer can see a mixed contract.

- [ ] **Step 9: Run Python, testthat and SQL focused suites, then commit.** Do not generate production artifacts in this task.

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py -q
Rscript -e 'testthat::test_file("tests/testthat/test-export-narrative-record-cutover.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-apply-narrative-record-cutover.R")'
PGDATABASE=daa_narrative_152 PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres \
  /opt/homebrew/opt/postgresql@17/bin/psql -v ON_ERROR_STOP=1 -f tests/sql/test-narrative-record-cutover.sql
git add schema.sql db-migrations.sql tests/sql/test-narrative-record-cutover.sql .claude/skills/daa-extract/scripts/export_narrative_record_cutover.R .claude/skills/daa-extract/scripts/export_narrative_record_cutover_helpers.R .claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py .claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py .claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R .claude/skills/daa-extract/scripts/apply_narrative_record_cutover_helpers.R .claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py tests/testthat/test-export-narrative-record-cutover.R tests/testthat/test-apply-narrative-record-cutover.R
git commit -m "feat(db): build atomic narrative contract cutover"
```

### Task 8: Update the shared public TypeScript contract and deterministic ordering

**Files:**

- Modify: `packages/core/src/bioVersions.ts`
- Modify: `packages/core/src/__tests__/bioVersions.test.ts`
- Modify: `web/src/data/public.ts`
- Modify: `web/src/data/__tests__/orThrow.test.ts`
- Modify: `web/src/data/feedAux.ts`
- Modify: `web/src/data/__tests__/feedAux.test.ts`
- Modify: `mobile/src/data/publicBioVersions.ts`
- Modify: `mobile/src/data/__tests__/publicBioVersions.test.ts`
- Modify: `mobile/src/data/load.ts`
- Modify: `mobile/src/data/__tests__/load.test.ts`

**Types:**

```ts
export type PublicBioSourceVersionRowV2 = {
  person_id: number;
  source_id: number;
  source_year: number | null;
  record_order: number | null;
  source_record_ref: string | null;
  source_label: string;
  record_label: string;
  narrative_text: string;
  citation_label: string;
  provenance_kind: 'source_record' | 'legacy_narrative';
};
```

- [ ] **Step 1: Write failing core order tests.** Cover `source_year DESC NULLS LAST`, opaque `source_id ASC`, bound before legacy, numeric page, Danish record label and stable ref. Two records from one source remain two items; no text concatenation occurs.

- [ ] **Step 2: Add shared V2 mapper.** Preserve safe public fields and expose structured sort inputs only where the UI needs them. Do not call `localeCompare` on source labels as a chronology substitute.

- [ ] **Step 3: Make web/mobile public adapters capability-aware.** Call `narrative_record_contract_version`; at `<2`, retain v1 behavior. At `>=2`, call `public_person_bio_source_versions_v2`. A v2 error is an explicit fetch error/`null`, never `buildBioVersions` concatenating fallback. Migrate the person-biography reads in `web/src/data/feedAux.ts` and `mobile/src/data/load.ts` to the same event-text contract; they may not keep a direct `public.narrative.tekst` fallback at version `2`.

- [ ] **Step 4: Share identical contract fixtures and classify every direct reader.** Copy no business logic between adapters: both pass the same fixture through the core mapper and assert byte-equivalent ordered output. Pin these current direct readers in the inventory test: `mobile/src/data/about.ts` and both `presensLinjer.ts` files are non-person controls; both `haendelser.ts` files are RLS-gated metadata consumers; both redaction readers move person/DAA to the editor RPC; `web/src/data/public.ts`, `web/src/data/feedAux.ts` and `mobile/src/data/load.ts` move person text to v2. Any new unclassified `.from('narrative')` hit fails the test.

- [ ] **Step 5: Run focused and complete core suites, then commit.** Expected PASS:

```bash
npm run test -w @daa/core -- bioVersions
npm run typecheck -w @daa/core
```

```bash
git add packages/core/src/bioVersions.ts packages/core/src/__tests__/bioVersions.test.ts web/src/data/public.ts web/src/data/__tests__/orThrow.test.ts web/src/data/feedAux.ts web/src/data/__tests__/feedAux.test.ts mobile/src/data/publicBioVersions.ts mobile/src/data/__tests__/publicBioVersions.test.ts mobile/src/data/load.ts mobile/src/data/__tests__/load.test.ts tests/testthat/test-narrative-record-source-inventory.R
git commit -m "feat(core): map record keyed biography versions"
```

### Task 9: Replace web narrative data adapters and route publication history correctly

**Files:**

- Modify: `web/src/data/redaktionRead.ts`
- Modify: `web/src/data/redaktionWrite.ts`
- Modify: `web/src/data/historik.ts`
- Modify: `web/src/data/__tests__/redaktionRead.narrativer.test.ts`
- Modify: `web/src/data/__tests__/redaktionWrite.narrativ.test.ts`
- Modify: `web/src/data/__tests__/historik.test.ts`

**Client contracts:**

```ts
type PersonNarrativeRecord = {
  sourceId: number;
  recordKey: string;
  sourceRecordRef: string;
  status: 'none' | 'draft' | 'published' | 'stale_published' | 'withdrawn' | 'blocked';
  stateSha256: string;
  text: string;
  recordLabel: string;
  citationLabel: string;
  allowedActions: readonly NarrativeRecordAction[];
};

type LegacyNarrativePublication = {
  legacyPublicationRef: string;
  status: 'legacy_active' | 'legacy_withdrawn';
  stateSha256: string;
  text: string;
};
```

- [ ] **Step 1: Write adapter tests for exact RPC names/args.** Cover read, draft create/update, discard, publish, published revision, revalidate, withdraw, legacy withdraw and event reversal. Assert every record mutation sends `(personId, sourceId, recordKey, expectedStateSha256)` as applicable and never an internal UUID, label or side.

- [ ] **Step 2: Separate person/DAA from generic narrative behavior.** `fetchNarrativer` and old `Change.art='narrativ'` remain for non-person or non-DAA entity editors. Person editor at capability `2` exclusively uses record RPCs; there is no fallback to `red_upsert_narrativ` after a record RPC error.

- [ ] **Step 3: Route history.** Merge generic `hist_for_subjekt` presentation with `red_person_narrative_publication_history`. A publication change set invokes `red_fortryd_person_narrative_publication_event`; other reversible sets keep `red_fortryd_change_set`. Reversal events render with no undo control.

- [ ] **Step 4: Map stable errors to explicit UI states.** At minimum stale state, identity required/conflict, anchor required, derived events, illegal transition, dedicated reversal required, legacy drift and person-delete publication history. No error mapping may silently retry a mutation with refreshed hash.

- [ ] **Step 5: Run focused tests and typecheck.** Expected old assertion that person narrative writes `red_upsert_narrativ` fails before implementation and is removed only after the new exact RPC assertion passes.

```bash
npm run test -w web -- redaktionRead.narrativer redaktionWrite.narrativ historik
npx tsc -p web/tsconfig.json --noEmit
```

- [ ] **Step 6: Commit.**

```bash
git add web/src/data/redaktionRead.ts web/src/data/redaktionWrite.ts web/src/data/historik.ts web/src/data/__tests__/redaktionRead.narrativer.test.ts web/src/data/__tests__/redaktionWrite.narrativ.test.ts web/src/data/__tests__/historik.test.ts
git commit -m "feat(web): use narrative record RPC adapters"
```

### Task 10: Build the full web record editor and dedicated history actions

**Files:**

- Create: `web/src/components/PersonNarrativeRecordEditor.tsx`
- Create: `web/src/components/__tests__/PersonNarrativeRecordEditor.test.tsx`
- Modify: `web/src/components/HistorikPanel.tsx`
- Modify: `web/src/components/__tests__/HistorikPanel.test.tsx`
- Modify: `web/src/Redaktion.tsx`

- [ ] **Step 1: Write component tests from the spec state table.** Render two records in one source, source ordering by year, `none`, `draft`, `published`, `stale_published`, `withdrawn`, blocked and legacy active/withdrawn. Assert no ordinary Save on published text and no edit controls for legacy text.

- [ ] **Step 2: Implement record cards/tabs.** Show source/record/citation labels, explicit status and only server-authorized actions. `none` offers create draft; draft offers save/discard/publish; published offers withdraw and `Publicér ændring`; stale offers revalidate; withdrawn is history plus conditional new draft.

- [ ] **Step 3: Implement stale conflict UX.** On `NARRATIVE_RECORD_STATE_STALE`, retain local text in memory, fetch latest server state, show both states and offer `Kopiér lokal tekst` or `Genindlæs`. Never automatically replay with the new hash.

- [ ] **Step 4: Implement legacy takedown.** Require a non-empty reason and a confirmation that identifies only the selected legacy biography. Send ref/hash/reason; do not toggle `privat` and do not hide the person or sibling biographies.

- [ ] **Step 5: Wire dedicated history reversal.** History panel calls the correct handler from Task 9; `canReverse=false` shows the server blocking reason and reversal rows have no button.

- [ ] **Step 6: Replace only the person editor branch.** `Redaktion.tsx` uses `PersonNarrativeRecordEditor` for `subjekt.type==='person'`; the existing generic editor remains for `slaegt`/`lineage` and non-DAA semantics.

- [ ] **Step 7: Run focused accessibility/interaction tests, full web test and build.** Expected PASS:

```bash
npm run test -w web -- PersonNarrativeRecordEditor HistorikPanel
npm run test -w web
npm run build -w web
```

- [ ] **Step 8: Commit.**

```bash
git add web/src/components/PersonNarrativeRecordEditor.tsx web/src/components/__tests__/PersonNarrativeRecordEditor.test.tsx web/src/components/HistorikPanel.tsx web/src/components/__tests__/HistorikPanel.test.tsx web/src/Redaktion.tsx
git commit -m "feat(web): add person narrative record editor"
```

### Task 11: Apply the minimal fail-closed mobile editor migration

**Files:**

- Modify: `mobile/src/data/redaktionRead.ts`
- Modify: `mobile/src/data/redaktionWrite.ts`
- Modify: `mobile/src/components/redaktion/NarrativEditor.tsx`
- Create: `mobile/src/components/redaktion/__tests__/NarrativEditor.recordContract.test.tsx`
- Modify: `mobile/src/data/__tests__/redaktionRead.test.ts`
- Modify: `mobile/src/data/__tests__/redaktionWrite.test.ts`

- [ ] **Step 1: Write the minimum-scope tests first.** Exactly one active editable person/DAA record permits the appropriate record action with record key/hash. Zero, more than one, stale, legacy-only, withdrawn-history or blocked records are read-only and say `Brug webredaktionen`.

- [ ] **Step 2: Prove the old path is unreachable.** At contract version `2`, a person/DAA edit never builds `red_upsert_narrativ`, even if the record read fails. Generic `slaegt`/`lineage` editor continues to use its current path.

- [ ] **Step 3: Implement capability-aware read and minimal action builder.** Reuse shared statuses/types. Do not add record tabs, withdrawn history, legacy takedown, advanced revalidation/reversal or a second full editor.

- [ ] **Step 4: Make ambiguous state visibly read-only.** Preserve displayed authoritative text and labels; disable text/privacy/page controls and all write previews. Do not pick the first record.

- [ ] **Step 5: Run focused and full mobile verification.** Expected PASS:

```bash
npm run test -w mobile -- NarrativEditor.recordContract redaktionRead redaktionWrite
npm --workspace mobile exec -- tsc --noEmit
npm run test -w mobile
```

- [ ] **Step 6: Commit.**

```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/redaktionWrite.ts mobile/src/components/redaktion/NarrativEditor.tsx mobile/src/components/redaktion/__tests__/NarrativEditor.recordContract.test.tsx mobile/src/data/__tests__/redaktionRead.test.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(mobile): fail closed on narrative record ambiguity"
```

### Task 12: Add CI coverage and run full disposable end-to-end/concurrency/browser proof

**Files:**

- Create: `tests/integration/test-narrative-record-concurrency.R`
- Modify: `.github/workflows/ci.yml`
- Create: `docs/evidensbaseret-genimport/narrative-record-key-152-rehearsal.md`
- Modify: any task-owned test file only to correct a demonstrated defect through RED → GREEN.

- [ ] **Step 1: Write real multi-session integration.** Use separate DBI connections for simultaneous create/update, same-stream version race, old-writer-vs-cutover and new-writer-vs-version-1. Assert both allowed commit orders, no deadlock, exact winner/loser codes and no duplicate active binding/event version.

- [ ] **Step 2: Add a PostgreSQL 17 CI job.** Bootstrap auth shim, apply `schema.sql`, `db-migrations.sql`, `db-rls.sql`, run both new SQL tests, `tests/sql/run-db-verify-disposable.sql`, and the R concurrency test with all five PG variables. Keep focused test output separate from full historical verification.

- [ ] **Step 3: Run all local suites.** Record exact counts and commit IDs in the rehearsal report:

```bash
Rscript run-tests.R
npm run test -w @daa/core
npm run typecheck -w @daa/core
npm run test -w web
npm run build -w web
npm run test -w mobile
npm --workspace mobile exec -- tsc --noEmit
```

- [ ] **Step 4: Create a production-shaped disposable restore.** Use a fresh backup/restore authorized for testing, not production. Export restore-bound manifests, generate synthetic test approval bound to those exact bytes, run gateway `rollback`, committed `apply`, reconnect receipt verification and read-only postverify. Do not reuse a production-bound database identity.

- [ ] **Step 5: Run a real web browser smoke test against that isolated database.** Demonstrate the eleven spec §10.3 scenarios: two same-source records, draft, independent edits, stale conflict, publish/revision, provenance drift/revalidation, reversal, discard/no redo, legacy withdrawal, stable public ref, public ordering and mobile ambiguous read-only behavior. Capture only synthetic/non-sensitive fixture screenshots.

- [ ] **Step 6: Adversarially compare final tree to the spec.** Search for direct person/DAA `narrative` reads/writes, old RPC calls, internal UUID serialization, `max(id)+1`, grants, mutable events, `TODO`/`TBD`, concatenating v2 fallback and missing stable error mappings. Every hit is classified or fixed with a failing test first.

- [ ] **Step 7: Write the rehearsal report.** Include branch/commit, disposable DB identity, backup hash, manifest/approval/receipt hashes, exact ID-set counts, sequence before/floor/after, focused/full suite results, browser steps and explicit `NO_PRODUCTION_MUTATION`.

- [ ] **Step 8: Commit only verified integration corrections, CI and evidence.**

```bash
git add tests/integration/test-narrative-record-concurrency.R .github/workflows/ci.yml docs/evidensbaseret-genimport/narrative-record-key-152-rehearsal.md
git commit -m "test: prove narrative record contract end to end"
```

### Task 13: Prepare the production runbook and stop at a new approval gate

**Files:**

- Create: `docs/runbooks/narrative-record-key-cutover.md`
- Modify: `docs/evidensbaseret-genimport/status.md`
- Modify: `docs/evidensbaseret-genimport/roadmap.md`

- [ ] **Step 1: Write an exact no-placeholder runbook.** Include backup with mode `0600` and SHA-256, restore rehearsal, fresh read-only inventory/manifests, local human review, approval conversion, drift recheck, exclusive cutover, commit-unknown recovery, postverify and rollback/containment decision points.

- [ ] **Step 2: Make the production gates explicit.** Require fresh counts for bindings, grandfathered legacy, accepted identities, blocked new records and direct readers; material drift from the 2026-08-29 approved consequence returns to the project owner. Require separately reviewed hashes and exact database identity.

- [ ] **Step 3: State what rollback means.** Before commit: database rollback. After committed cutover: do not delete append-only events or lower version opportunistically; use the documented containment/recovery path and a new approved migration. Restore from backup only under explicit incident authority.

- [ ] **Step 4: Update governance to evidence-backed maturity only.** If Task 12 passed, set #152 to `integreret ende-til-ende`, not `produktionsverificeret`. Record that new binding/loader freeze remains active by design and that no production GO has been given.

- [ ] **Step 5: Run documentation and repository verification.** Check every referenced path exists, every RPC signature matches schema/migration, no `TODO`/`TBD`/`<placeholder>` remains, and the worktree contains no generated manifest, credential, backup or `work/` artifact.

- [ ] **Step 6: Review and commit the runbook/status batch.**

```bash
git add docs/runbooks/narrative-record-key-cutover.md docs/evidensbaseret-genimport/status.md docs/evidensbaseret-genimport/roadmap.md
git commit -m "docs: prepare narrative record production gate"
```

- [ ] **Step 7: STOP.** Report `READY_FOR_PRODUCTION_REVIEW` only if all preceding evidence is present. Request a fresh explicit production GO. Do not connect the cutover gateway to production, do not generate a production approval on the user's behalf, and do not proceed automatically.

## Plan Completion Review

Before implementation begins, review this plan against the approved spec and require all of the following:

- [ ] Every public/editor RPC in spec §§5.4, 6 and 7 has an implementation task, negative test, ACL test and client consumer or explicit private-only classification.
- [ ] Every old writer/read path named in spec §9 has a gate or migration task, including `load_daa.R`, both updater scripts, C3, generic undo, direct RLS and `red_slet_person`.
- [ ] Every spec §10.1 database/concurrency bullet maps to a named SQL/integration test above.
- [ ] Every spec §10.2 client bullet maps to a core, web or mobile test above.
- [ ] All eleven spec §10.3 smoke scenarios are present in Task 12.
- [ ] Additive phase, client phase, atomic cutover and separate production gate remain distinct.
- [ ] The plan contains no production mutation, no identity backfill, no legacy text editing, no full mobile editor and no #153/#149 implementation.
- [ ] No placeholder, ellipsis-as-implementation, `TODO`, `TBD`, “similar to”, or unbound future choice remains.
