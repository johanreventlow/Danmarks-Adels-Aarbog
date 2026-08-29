# Narrative Source-Record Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement roadmapmål #152 as an editions-neutral, record-keyed and append-only publication contract for person/DAA narratives, prove it end-to-end in disposable infrastructure, and stop before any production mutation.

**Architecture:** PostgreSQL owns record resolution, authority checks, a semantic `publication_state` hash plus a separate editor concurrency-envelope hash, immutable publication events, current projections, legacy disposition and the atomic versioned cutover. Shared TypeScript owns only typed public row mapping and deterministic ordering. Web gets the full record editor; mobile gets a capability-aware, fail-closed minimum. Read-only manifest tooling binds every baseline row, explicit keep/hide disposition and production precondition to exact bytes before a later separately approved cutover.

**Tech Stack:** PostgreSQL 17, PL/pgSQL, Supabase Auth/RLS/PostgREST, `dblink`, R 4.x with DBI/RPostgres/jsonlite/digest/testthat, Python 3 stdlib/pytest for local approval artifacts, TypeScript, React/Vitest, React Native/Jest, Playwright Chromium.

**Spec:** `docs/superpowers/specs/2026-08-29-narrative-source-record-key-design.md`

**Plan review status:** Revideret og self-reviewet `GO`; afventer
projektejerens samlede godkendelse før Task 1.

## Global Constraints

- This plan belongs to roadmapmål #152. It closes the publication-gate and public read-projection link in the shared evidence chain; it is a permanent editions-neutral mechanism plus explicitly temporary legacy retirement.
- The editorial value is independent maintenance and publication of multiple concrete records from the same DAA edition without first-row selection or text concatenation.
- Completion means disposable database, real concurrency, schema/RLS/ACL verification, focused and full client suites, production-shaped restore rehearsal, and real-browser smoke evidence. A green isolated SQL test alone is insufficient.
- No task in this plan mutates production, deploys a client, pushes a branch, or merges to `main`. Task 13 stops at `READY_FOR_PRODUCTION_REVIEW` and requests a new explicit GO.
- Execute tasks in order. Finish each task with its focused tests, spec-conformance review, code-quality review, status checkpoint and separate commit. Stop after every task and wait for explicit user continuation; never auto-continue, whether the gate passed or failed.
- Treat `schema.sql`, `db-migrations.sql`, `db-rls.sql` and executable tests as one contract. Additive objects are present in both schema and migration truth; access rules live explicitly in `db-rls.sql` and are asserted by tests.
- Every privileged function uses a fixed schema-qualified `search_path`, explicit editor/service role checks where applicable, `REVOKE ALL ... FROM PUBLIC, anon, authenticated`, and only the minimum subsequent `GRANT EXECUTE`. RLS and grants are independent gates and both must pass.
- Private UUIDs (`source_record.id`, binding IDs and internal identity rows) never cross public or first-party client contracts. Editors address records only by `(source_id, record_key)`; public clients use `source_record_ref`.
- Every mutation takes `pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0))` first, re-reads contract version under that lock and follows the canonical record-first row-lock order. Cutover alone takes the exclusive form of the same lock.
- Old paths require contract version `1`; new record writers require version `2`. ACL revocation supplements this runtime guard and is never the sole concurrency proof.
- Publication history is append-only. Do not update or delete publication events, synthesize identity decisions, rewrite old C3 bindings, mutate legacy text during withdrawal, or use generic change-set undo for publication events.
- `publication_state_sha256` is computed only from the canonical semantic server-side publication-state projector, which excludes its own event envelope. Client `state_sha256` is computed only from the canonical editor envelope, which embeds the semantic state plus latest event id/version and semantic before/after hashes. Readers, writers, history and tests must not invent parallel representations or equate the two hashes.
- A published text has no ordinary save path. Text change requires `published_revision`; text change with `haendelse` rows fails closed.
- Keep 2018-20 legacy text read-only. Only its exact hash-locked ledger row may be withdrawn or safely restored by dedicated event reversal.
- New bindings without exactly one accepted principal/co-principal canonical person remain blocked. The approved temporary freeze is not to be weakened to make a test or UI flow pass.
- `red_slet_person` fails before any writes when publication events exist. This plan does not decide permanent person tombstone/retention.
- Baseline and legacy manifests use exact ordered ID sets and non-optional SHA-256 values. Count equality alone, dynamic production `INSERT ... SELECT`, and an approval surviving any byte drift are forbidden.
- Candidate review may contain `uafklaret`; approval conversion may not. Every record candidate must be `godkend baseline`, every legacy candidate must be explicitly `bevar` or `skjul`, and `bevar ∪ skjul` must equal the exact candidate ID set without overlap before final manifests exist.
- Every mutating 1939-v50 and C3 authorization/apply/reversal entry point requires contract version `1` under the shared cutover lock. Version `2` returns `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED`, cutover revokes its client grants, and generic undo rejects any historic change set touching a narrative later represented in the event/legacy contract.
- Narrative identity sequence resync happens under the exclusive cutover and narrative table lock, never lowers the sequence, and floors above live narrative IDs, historical `change_event` row IDs, event narrative IDs and the already allocated next sequence value.
- Use all five `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` variables together for database integration, or omit all five. Never infer production credentials from the working directory.
- Do not read, stage or modify `work/` or the untracked external review file while implementing this plan.
- After the final Codex self-review, run one independent read-only Claude Fable 5 review of `f53d965...HEAD`; critically evaluate every finding and rerun tests for each valid RED → GREEN correction.

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
- Modify: `db-rls.sql`
- Create: `tests/sql/test-narrative-record-contract.sql`
- Modify: `db-verify.sql`

**Interfaces:**

```sql
public.narrative_record_contract_version() RETURNS integer

private.source_record.public_ref uuid NOT NULL UNIQUE DEFAULT gen_random_uuid()

private.narrative_publication_event(
  id uuid PRIMARY KEY,
  change_set_id bigint NOT NULL,
  stream_ref uuid NOT NULL,
  stream_version integer NOT NULL,
  event_type text NOT NULL,
  binding_id uuid,
  narrative_id bigint NOT NULL,
  source_id bigint NOT NULL,
  source_record_id uuid,
  legacy_publication_ref uuid,
  decision_basis text NOT NULL,
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  before_state_sha256 text NOT NULL,
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
  source_id bigint NOT NULL,
  baseline_state jsonb NOT NULL,
  baseline_sha256 text NOT NULL,
  status text NOT NULL,
  latest_event_id uuid,
  created_at timestamptz NOT NULL
)
```

- [ ] **Step 1: Write failing structural tests.** In `tests/sql/test-narrative-record-contract.sql`, assert `public_ref` exists with `DEFAULT gen_random_uuid()`, is `NOT NULL`/unique and cannot be updated. Assert both private tables and their exact CHECK/UNIQUE/FK constraints exist: event types are exactly `baseline`, `draft_created`, `draft_updated`, `draft_discarded`, `published`, `published_revision`, `revalidated`, `withdrawn`, `legacy_migrated`, `legacy_withdrawn`, `reversal`; ledger statuses are exactly `grandfathered_publication`, `withdrawn`, `migrated`; before/after states and hashes are non-null; `decision_basis` and `decided_by_name` are non-null and non-blank; and exactly one target kind is present (`binding_id` + `source_record_id`, or `legacy_publication_ref`). Assert event update/delete raises `NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY`, private relations have RLS enabled, and contract version returns exactly `1`.

- [ ] **Step 2: Run the focused test against a fresh disposable database and confirm RED.** Apply `tests/sql/evidence-promotion-bootstrap.sql`, `schema.sql`, `db-rls.sql`, then the new test. Expected first failure: missing `private.source_record.public_ref` or `public.narrative_record_contract_version()`.

```bash
PGDATABASE=daa_narrative_152 PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres \
  /opt/homebrew/opt/postgresql@17/bin/psql -v ON_ERROR_STOP=1 -f tests/sql/test-narrative-record-contract.sql
```

- [ ] **Step 3: Implement additive DDL in `schema.sql`.** Add `public_ref` with `DEFAULT gen_random_uuid()`, backfill null rows once, then enforce `NOT NULL`, uniqueness and an immutability trigger while preserving existing refs on rerun. Add the event/legacy tables with the exact types/statuses and non-null semantic before/after hashes from Step 1, append-only/shape triggers and private RLS. `legacy_migrated`/`migrated` are schema-reserved but receive no #152 writer.

- [ ] **Step 4: Mirror the deployable, idempotent block at the end of `db-migrations.sql`.** Existing rows receive stable random refs once; reruns preserve them. Install `narrative_record_contract_version()` returning `1`. Fix `schema.sql`'s current `red_upsert_narrativ` insert to use the narrative identity default instead of `max(id)+1`, matching the effective migration definition.

- [ ] **Step 5: Make access control explicit in `db-rls.sql`, then add integrity assertions to `db-verify.sql`.** Add both new tables to the private deny-all/RLS inventory and revoke every new private helper from `PUBLIC`, `anon`, `authenticated`, and `service_role`. Verify public refs are non-null/unique/defaulted, every before/after/baseline hash has 64 lowercase hex characters, event identities and target kinds are exact, reversal points backward within the same stream, reserved migration status has no callable #152 writer, immutable triggers reject mutations, and no client role can directly access either private table.

- [ ] **Step 6: Run schema/migration parity both ways.** Fresh path: bootstrap → `schema.sql` → `db-rls.sql`. Upgrade path: a pre-Task-1 base → `db-migrations.sql` twice → `db-rls.sql`. Both must pass the focused SQL test; the second migration run must change zero existing public refs.

- [ ] **Step 7: Review and commit.** Confirm no new writer has a grant, version remains `1`, no baseline events are auto-created, and no legacy row becomes public merely from this additive task.

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
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
private.narrative_publication_state(
  p_person_id bigint,
  p_source_id bigint,
  p_record_key text
) RETURNS jsonb

private.narrative_record_state(
  p_person_id bigint,
  p_source_id bigint,
  p_record_key text,
  p_lock boolean DEFAULT false
) RETURNS jsonb

private.narrative_legacy_publication_state(
  p_legacy_publication_ref uuid
) RETURNS jsonb

private.narrative_legacy_state(
  p_legacy_publication_ref uuid,
  p_lock boolean DEFAULT false
) RETURNS jsonb

public.red_person_narrative_records(p_person_id bigint) RETURNS TABLE(
  person_id bigint,
  source_id bigint,
  source_year integer,
  source_label text,
  provenance_kind text,
  record_key text,
  source_record_ref uuid,
  legacy_publication_ref uuid,
  record_order integer,
  record_label text,
  citation_label text,
  narrative_id bigint,
  narrative_text text,
  narrative_private boolean,
  narrative_side text,
  publication_status text,
  text_editable boolean,
  allowed_actions jsonb,
  withdrawn_history jsonb,
  latest_event_version integer,
  published_text_sha256 text,
  eligibility_status text,
  blocking_reason text,
  state_sha256 text
)

public.red_person_narrative_publication_history(p_person_id bigint)
RETURNS TABLE(
  event_id uuid,
  change_set_id bigint,
  stream_version integer,
  event_type text,
  source_record_ref uuid,
  legacy_publication_ref uuid,
  before_state_sha256 text,
  after_state_sha256 text,
  before_text text,
  after_text text,
  decided_by_name text,
  created_at timestamptz,
  can_reverse boolean,
  blocking_reason text
)
```

`allowed_actions` is a JSON array containing only these exact machine values in
this order when eligible: `create_draft`, `save_draft`, `discard_draft`,
`publish`, `publish_revision`, `revalidate`, `withdraw`, `withdraw_legacy`.
Record and legacy state rules determine the subset; reversal is expressed only
by the history row's typed `can_reverse`, never as a record action.

- [ ] **Step 1: Add failing state-contract fixtures.** Seed records covering accepted principal identity, accepted co-principal identity, empty identity, two-person ambiguity, conflicting existing binding, one accepted anchor, missing anchor, active placement, withdrawn-only history, active draft, published, stale projection, active legacy, withdrawn legacy and legacy baseline drift. Assert editor inclusion through both approved routes (existing active/withdrawn binding; accepted anchor + accepted principal/co-principal placement) and exclusion of every record satisfying neither route. For two records in one source, assert numeric page then `record_key` order.

- [ ] **Step 2: Assert both canonical JSON domains exactly, not by selected fields.** `narrative_publication_state` contains person/source/record locator, internal record identity, public ref, ordered anchor/placement/identity/revision snapshots, authority kind, binding projection, narrative/text/privacy/side, labels, policy/provenance and `has_haendelse`, but no latest event id/version/hash. Its hash is `publication_state_sha256 = encode(digest(publication_state::text,'sha256'),'hex')`. `narrative_record_state` wraps that semantic object with active/withdrawn history plus latest event id/version/before/after hashes and computes the separate client `state_sha256`. Assert neither canonical input contains the hash it produces. Mirror the same two-level contract for legacy.

- [ ] **Step 3: Implement record resolution and one owner of lock mode.** `narrative_record_state(p_lock=false)` is stable read; `p_lock=true` alone owns the full sequence: source record first, bindings ordered by stable key, latest events, narratives, then current evidence rows in the spec order. The semantic `narrative_publication_state` and legacy equivalent are pure canonical projectors with no row-lock statements; the envelope calls them only after its locks are acquired. Absence is protected by the already locked source record. Do not expose internal UUIDs from public RPCs.

- [ ] **Step 4: Implement identity authority exactly.** For a new binding, the set of current accepted `canonical_person_id` values reached through accepted `principal_member`/`co_principal` placements must equal `{p_person_id}`. For an existing exact binding, allow `existing_exact_binding` only if no accepted principal/co-principal identity conflicts.

- [ ] **Step 5: Implement the single label projector.** Preserve existing binding labels. For a new binding use exactly one accepted placement label, otherwise `record_key`; derive citation from source label plus distinct current accepted anchor page intervals in numeric order. Missing current anchor fails with `NARRATIVE_RECORD_ANCHOR_REQUIRED`.

- [ ] **Step 6: Implement the exact typed editor read and history RPC signatures above.** Record rows use `provenance_kind='source_record'` and return safe locator, public ref, status, validated `allowed_actions`, event-derived text, labels and editor-envelope `state_sha256`. Legacy rows use `provenance_kind='grandfathered_legacy'`, return immutable `legacy_publication_ref`, text, active/withdrawn disposition and no text-edit action. History rows return the typed event/change-set/stream fields, safe target ref, semantic before/after hashes and texts, actor/time, `can_reverse` and blocking reason. Only `allowed_actions` and `withdrawn_history` are JSONB.

- [ ] **Step 7: Verify roles, typed metadata and data minimization.** Anonymous/member calls fail; redaction succeeds. Assert `pg_get_function_result` and `information_schema.parameters` match every declared table column and type exactly. Search serialized RPC output for source-record UUIDs, binding UUIDs, private policy JSON and identity row IDs and require zero matches.

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

- [ ] **Step 3: Add one private mutation kernel used by all six RPCs.** It takes the shared cutover lock first, requires version `2`, checks editor role, delegates canonical state/locks to Task 2, compares the pre-write editor-envelope `state_sha256`, opens exactly one change set, performs exactly one legal projection transition and appends exactly one event. The event's before/after hashes must equal the pre/post semantic `publication_state` hashes; after insertion the kernel recomputes and returns the distinct editor-envelope `state_sha256` containing the new event metadata.

- [ ] **Step 4: Keep the six Task 3 writers ungranted in additive phase.** Define them with explicit revokes in schema/migration; do not grant `authenticated` until Task 7 cutover. Replace `db-rls.sql`'s broad `red_*` grant loop with a signature-aware allow-list and an explicit deny-list for the six functions that exist at this task boundary plus their private mutation kernel. Do not name not-yet-created Task 4/7 functions in unconditional SQL; those tasks add their own exact revokes and extend the deny-list after creation. Editor read/history RPCs may be granted. Tests invoke mutation functions as owner only inside the version-2 fixture and assert an authenticated editor still receives permission denied while contract version is `1`.

- [ ] **Step 5: Implement narrative allocation and preservation.** New narrative uses identity default. Draft discard/withdraw marks projection withdrawn; it never deletes narrative, binding or events. A fresh draft after withdrawn history creates a new narrative/binding stream and preserves old text byte-for-byte.

- [ ] **Step 6: Implement publication snapshots.** `published` and `published_revision` carry complete old/new text plus occurrence/rendition/identity/policy/provenance inputs. Ordinary upsert cannot alter published text. Revision with any `haendelse` fails `NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT`.

- [ ] **Step 7: Assert exact write sets and both post-state hashes.** A successful call adds one change set and one event and changes only the expected narrative/binding rows. A rejected call adds none. Event `after_state_sha256` equals the independently recomputed semantic projection hash; returned `state_sha256` equals the independently recomputed editor envelope and differs from the semantic hash because it includes the new event metadata. Returned JSON includes safe locator, `event_id`, `narrative_id`, current status, `publication_state_sha256` and `state_sha256`, but no binding/source-record UUID.

- [ ] **Step 8: Run focused SQL and commit.** Also rerun existing C3 SQL tests to show the additive definitions have not changed C3 behavior while version is `1`.

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
git commit -m "feat(db): add record keyed narrative writers"
```

### Task 4: Implement legacy withdrawal, dedicated reversal, undo routing and person-delete block

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
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

- [ ] **Step 4: Gate generic undo before it creates a reversal change set.** Add this exact first predicate to `red_fortryd_change_set` in schema and migration. The second branch prevents generic undo of a pre-cutover change set whose narrative later received a baseline event or legacy ledger row:

```sql
IF EXISTS (
  SELECT 1
  FROM private.narrative_publication_event
  WHERE change_set_id = p_change_set_id
) OR (
  public.narrative_record_contract_version() >= 2
  AND EXISTS (
    SELECT 1
    FROM public.change_event ce
    WHERE ce.change_set_id = p_change_set_id
      AND ce.tabel = 'narrative'
      AND ce.row_pk ? 'id'
      AND (
        EXISTS (
          SELECT 1
          FROM private.narrative_publication_event npe
          WHERE npe.narrative_id = (ce.row_pk->>'id')::bigint
        )
        OR EXISTS (
          SELECT 1
          FROM private.narrative_legacy_publication nlp
          WHERE nlp.narrative_id = (ce.row_pk->>'id')::bigint
        )
      )
  )
) THEN
  RAISE EXCEPTION 'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED';
END IF;
```

Extend `db-rls.sql`'s exact deny-list only after the two public Task 4 RPCs
exist, revoke their private helpers from every client/service role, and prove
they remain uncallable by `authenticated` while contract version is `1`.

- [ ] **Step 5: Block person hard-delete safely.** `red_slet_person` takes the shared contract lock before its existing locks and fails `PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY` before `begin_change_set` if any publication event reaches a narrative for the person. `red_slet_person_preview` returns `antal_publication_events` and `sletning_blokeret=true` without exposing private event payloads.

- [ ] **Step 6: Prove generic history mapping.** The history RPC maps each publication change set to the dedicated event. `can_reverse` is true only for the latest legal event; reversal rows have false plus `NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE`.

- [ ] **Step 7: Run focused SQL, existing generic undo tests and commit.** Require unchanged behavior for change sets with neither a publication event nor a narrative row that is later baseline-/ledger-bound. Add a pre-cutover C3-shaped narrative change-set fixture, baseline that narrative under the rolled-back version-2 fixture, and prove generic undo rejects without touching narrative, binding, ledger or event.

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-contract.sql
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

- [ ] **Step 3: Implement one server publication predicate over semantic state.** Reduce the latest append-only event, verify its `after_state_sha256` against its canonical `publication_state`, compare that semantic projection's text/provenance/identity/privacy/policy hashes to live state, or validate the active legacy baseline. The predicate never consumes editor-envelope `state_sha256`. Use it from v1, v2 and RLS rather than copying eligibility rules. Install all three surfaces version-aware: version `1` preserves the current public behavior; version `2` activates the exhaustive event/ledger branch. SQL tests temporarily flip the function to `2` inside a rolled-back transaction to exercise that branch before cutover.

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

- [ ] **Step 1: Enumerate and pin the complete live mutation set in a test.** `tests/testthat/test-narrative-record-source-inventory.R` must require definitions, contract-gate references and ACL classification for `red_upsert_narrativ`, `red_publicer_narrative_record(bigint,uuid,text,text)`, `red_tilbagetraek_narrative_record(bigint)`, `red_slet_person`, `red_fortryd_change_set`, `load_daa.R` and both updater scripts. Pin the mutating 1939-v50 family: `red_authorize_1939_v50_reimport`, `red_begin_1939_v50_reimport`, `red_apply_1939_v50_source_evidence`, `red_apply_1939_v50_person_create`, `red_apply_1939_v50_canonical_delta`, `red_finalize_1939_v50_reimport`, `red_authorize_1939_v50_reversal`, `red_reverse_1939_v50_reimport`, `red_authorize_1939_v50_cutover`, `red_activate_1939_v50_batch`. Pin the C3 family: `red_authorize_reimport_cases`, `red_apply_reimport_cases`, `red_authorize_reimport_case_reversal`, `red_reverse_reimport_cases`, plus the private `write_reimport_case_narrative` helper as reachable only through gated public entry points. Classify `public.red_preview_reimport_cases(bigint,text,jsonb)`, `private.reimport_case_receipt(uuid)` and `private.reimport_case_reversal_plan(uuid)` explicitly as read-only/private-only as applicable. Historical C0/phase-B scripts are one-shot consumers blocked by their gated DB RPCs. Any new direct person/DAA mutation or unclassified `.from('narrative')` reader makes the inventory test fail.

- [ ] **Step 2: Write both real two-session lock orders across each old family.** Order A: session B acquires the exclusive cutover gate first; session A then invokes `red_upsert_narrativ`, a 1939-v50 apply entry point, C3 apply and each corresponding reversal family and blocks on its shared gate; B flips to version `2` and commits; every A call wakes, re-reads version and rejects without authorization, journal, projection, event or change-set writes. Order B: A acquires the shared gate first and performs a version-1 in-scope mutation while B blocks on exclusive; after A commits, B must revalidate the approved manifests under exclusive and abort the cutover on exact drift without changing version or grants. Separately prove a new writer rejects immediately at version `1` and succeeds only after an exclusive cutover commits version `2`. Use separate database sessions and assert the first lock in every function definition is the shared narrative-contract gate.

- [ ] **Step 3: Instrument every DB mutation family.** Shared advisory lock is the first transaction lock, followed by contract-version check and only then existing 1939/identity/production-writer locks. At version `2`, `red_upsert_narrativ` rejects only person + `source.slags='DAA-udgave'` with `NARRATIVE_RECORD_REQUIRED`; non-person and non-DAA behavior remains green. Every mutating 1939-v50/C3 authorization, begin, apply, finalize, activation and reversal entry point rejects version `2` with `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED`. Multi-step flows gate before the first authorization/journal mutation and narrative-mutating entry points recheck independently, so a pre-cutover authorization cannot cross the cutover.

- [ ] **Step 4: Instrument loader/updaters before first mutation.** Each script opens one transaction, takes the shared lock, reads contract version, and aborts the entire run at `2` with `NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED`. At `1`, existing dry-run and write call ordering remain byte-for-byte compatible.

- [ ] **Step 5: Assert no hidden fallback or reversal bypass.** Testthat fakes return version `2` and assert zero `dbExecute`/writer RPC calls after the loader/updater gate. SQL tests assert zero old-family authorization, batch, event, change-set, narrative or binding writes after rejection. Version `1` tests assert the gate precedes every existing writer/loader lock. Add the historic narrative-change-set fixture consumed by Task 4's expanded generic-undo guard, proving direct `red_fortryd_change_set` cannot bypass the disabled C3 reversal after baseline.

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
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Modify: `tests/testthat/test-narrative-record-source-inventory.R`

**Interfaces:**

```sql
private.apply_narrative_record_cutover(
  p_record_candidates_raw text,
  p_legacy_candidates_raw text,
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
  record_candidates_sha256 text NOT NULL,
  legacy_candidates_sha256 text NOT NULL,
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
narrative-record-baseline-candidates-v1.json
narrative-legacy-baseline-candidates-v1.json
narrative-record-baseline-manifest-v1.json
narrative-legacy-baseline-manifest-v1.json
narrative-record-cutover-inventory-v1.json
narrative-record-cutover-approval-v1.json
narrative-record-cutover-receipt-v1.json
```

- [ ] **Step 1: Write pure exporter/converter tests for candidate and final artifacts.** Feed duplicate IDs, null/non-hex hashes, changed row order, extra/missing rows, ambiguous binding, non-DAA row and drifted snapshot. Require stable canonical JSON, exact sorted ID sets, database name/system identifier, schema contract and separate whole-file SHA-256 values. Generate each legacy candidate's random `legacy_publication_ref` once into `narrative-legacy-baseline-candidates-v1.json`; rerunning creates new candidate bytes requiring new approval rather than silently reusing an unapproved ref. Assert final manifests do not exist while any record decision is not `godkend baseline` or any legacy decision is `uafklaret`.

- [ ] **Step 2: Implement one read-only repeatable-read exporter.** It opens `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`, takes the shared cutover lock, measures binding baselines and eligible legacy independently, and writes only to an explicit mode-`0700` output directory outside the repository with mode-`0600` files. It refuses the repository root and every `work/` path. Inventory includes counts by source, accepted identities, records blocked by identity and classified direct readers.

- [ ] **Step 3: Build a local offline review surface and fail-closed converter.** The HTML uses safe DOM APIs, embeds exact candidate/inventory hashes and asks the concrete question for every candidate: record baseline `godkend baseline`/`uafklaret`; legacy `bevar offentligt som grandfathered`/`skjul ved cutover`/`uafklaret`. No bulk action converts unresolved rows to approval. It exports deterministic text/JSON and never connects to database/network. The converter rejects missing, duplicate, unknown, altered or `uafklaret` decisions. It emits the final record manifest only when it equals the full approved record-candidate ID set; emits the final legacy manifest from exactly the explicit `bevar` set; stores the exact complementary `skjul` ID/hash set in approval; requires `bevar ∪ skjul` to equal all legacy candidates with empty intersection; and binds approval SHA to both candidate hashes, both final manifest hashes and inventory bytes.

- [ ] **Step 4: Write cutover RED tests.** Assert any missing/extra/drifted baseline row aborts before mutation; any unresolved decision or non-complementary legacy keep/hide set produces no valid approval; candidate/final/inventory/approval hash mismatch aborts; database identity mismatch aborts; and dynamic rows outside approved ID sets are never inserted.

- [ ] **Step 5: Implement the private cutover kernel and append-only receipt.** Hash both candidate, both final-manifest, inventory and approval raw arguments before parsing them; validate the approval's embedded candidate/final/inventory hashes and exact keep/hide partition; then under the exclusive shared-gate key and one transaction validate exact live sets, lock narrative, compute the monotone sequence floor, create baseline events/legacy ledger with semantic before/after hashes, activate the already installed version-aware v1/RLS branch, apply exact grants/revokes, and change contract version to `2` last. A receipt records every input hash, exact event/ledger IDs, sequence before/floor/after, semantic publication-state hashes and post-cutover editor-envelope hashes. Its update/delete trigger is append-only. No client role gets execute on the private kernel or receipt table.

- [ ] **Step 6: Implement the production-shaped R gateway.** Required modes are `preflight`, `rollback`, `apply`, `recover`; all require explicit paths to both candidate manifests, both final manifests, inventory and approval, plus nonce, expected DB name/system identifier and all-five PG env. The gateway verifies every raw-file hash before the DB call. `rollback` runs the real cutover then rolls back and compares exact before-state. `recover` resolves a lost commit only from nonce + all six artifact hashes + exact receipt; ambiguity returns `CUTOVER_RECOVERY_REQUIRED`.

- [ ] **Step 7: Prove sequence safety.** Test live high narrative ID, deleted historical ID retained in `change_event`, event-referenced narrative ID above live max, and already allocated sequence value above all three. Next default insert must succeed; rerun never lowers sequence.

- [ ] **Step 8: Prove grant/version atomicity and source-of-truth ACLs.** Before commit, clients remain v1 and new writers are uncallable. After commit, version is `2`, only the eight new writer grants exist, old publish/withdraw plus every mutating 1939-v50/C3 authorization/apply/reversal grant is absent for `authenticated` and `service_role`, old functions still reject under their runtime gate when invoked as owner, and v1/v2/RLS all use baselines. Extend Task 3's signature-aware `db-rls.sql` block into an exact version-aware ACL block: version `1` grants the classified legacy allow-list and denies all new writers; version `2` grants only the new allow-list and revokes every legacy mutation. Mirror both branches in `db-verify.sql`; no anticipatory reference to nonexistent signatures and no intermediate observer may see a mixed contract.

- [ ] **Step 9: Run Python, testthat and SQL focused suites, then commit.** Do not generate production artifacts in this task.

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py -q
Rscript -e 'testthat::test_file("tests/testthat/test-export-narrative-record-cutover.R")'
Rscript -e 'testthat::test_file("tests/testthat/test-apply-narrative-record-cutover.R")'
PGDATABASE=daa_narrative_152 PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres \
  /opt/homebrew/opt/postgresql@17/bin/psql -v ON_ERROR_STOP=1 -f tests/sql/test-narrative-record-cutover.sql
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-narrative-record-cutover.sql tests/testthat/test-narrative-record-source-inventory.R .claude/skills/daa-extract/scripts/export_narrative_record_cutover.R .claude/skills/daa-extract/scripts/export_narrative_record_cutover_helpers.R .claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py .claude/skills/daa-extract/scripts/convert_narrative_record_cutover_approvals.py .claude/skills/daa-extract/scripts/apply_narrative_record_cutover.R .claude/skills/daa-extract/scripts/apply_narrative_record_cutover_helpers.R .claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py tests/testthat/test-export-narrative-record-cutover.R tests/testthat/test-apply-narrative-record-cutover.R
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

- [ ] **Step 1: Write failing core order and selection tests.** Cover `source_year DESC NULLS LAST`, opaque `source_id ASC`, bound before legacy, numeric page, Danish record label and stable ref. Two records from one source remain two items; no text concatenation occurs. Assert the default is the first eligible bound record in this order and only falls back to the first eligible legacy row when no bound row exists.

- [ ] **Step 2: Add the shared typed V2 mapper and default selector.** Preserve safe public fields, reject missing/wrongly typed required RPC columns fail-closed, and expose structured sort inputs only where the UI needs them. Do not call `localeCompare` on source labels as a chronology substitute.

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
type NarrativeRecordAction =
  | 'create_draft'
  | 'save_draft'
  | 'discard_draft'
  | 'publish'
  | 'publish_revision'
  | 'revalidate'
  | 'withdraw'
  | 'withdraw_legacy';

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
  allowedActions: readonly Extract<NarrativeRecordAction, 'withdraw_legacy'>[];
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

- [ ] **Step 1: Write component tests from the spec state table.** Render two records in one source and assert numeric page then `record_key` order, plus source ordering by year. Render `none`, `draft`, `published`, `stale_published`, `withdrawn`, blocked and legacy active/withdrawn. Assert no ordinary Save on published text and no edit controls for legacy text.

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

- [ ] **Step 1: Write real multi-session integration.** Use separate DBI connections for simultaneous create/update, same-stream version race, both old-writer-vs-cutover lock orders from Task 6 and new-writer-vs-version-1/version-2. Assert no deadlock, exact winner/loser codes, old-writer rejection when cutover owns exclusive first, cutover drift rejection when the old writer owns shared first, and no duplicate active binding/event version.

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

- [ ] **Step 7: Run the required independent Claude Fable 5 review read-only.** From this worktree run exactly:

```bash
claude -p --model claude-fable-5 --permission-mode plan --no-session-persistence --allowedTools "Read,Grep,Glob,Bash(git diff *),Bash(git status *),Bash(git log *),Bash(git show *)" "Review issue #152 read-only. Do not modify files. Review the complete feature diff from f53d965 through HEAD, the current unstaged diff, and every untracked task-owned file listed by git status; inspect relevant surrounding code. Do not read the preserved untracked design-review file under docs/superpowers/reviews. Report severity-sorted findings with file and line evidence for correctness, regressions, edge cases, architecture, maintainability, security, data integrity, unnecessary complexity, and missing or inadequate tests. Explicitly state GO or NO-GO."
```

Critically evaluate every finding; never implement it automatically. For each valid finding, first add a failing regression test, verify RED, apply the minimum fix, verify GREEN, rerun the affected focused suite and then every full suite invalidated by the fix. Record rejected findings with technical reasons. Run a second Fable review only if accepted fixes materially alter design or risk.

- [ ] **Step 8: Write the rehearsal report.** Include branch/commit, disposable DB identity, backup hash, candidate/final manifest, approval and receipt hashes, exact keep/hide and record ID-set counts, sequence before/floor/after, focused/full suite results, browser steps, Codex self-review, Fable command/verdict/finding dispositions and explicit `NO_PRODUCTION_MUTATION`.

- [ ] **Step 9: Commit only verified integration corrections, CI and evidence.**

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

- [x] Every public/editor RPC in spec §§5.4, 6 and 7 has an implementation task, negative test, ACL test and client consumer or explicit private-only classification.
- [x] Editor/history RPCs use the exact typed `RETURNS TABLE` signatures; only validated actions/withdrawn history are JSONB, and metadata tests pin every column/type.
- [x] Semantic `publication_state_sha256` and editor-envelope `state_sha256` have separate canonical builders/tests; no canonical input contains its own output hash.
- [x] Every old writer/read path named in spec §9 has a gate or migration task, including `load_daa.R`, both updater scripts, all mutating 1939-v50/C3 authorization/apply/reversal entry points, generic undo of current and historic baseline-bound change sets, direct RLS and `red_slet_person`.
- [x] Every spec §10.1 database/concurrency bullet maps to a named SQL/integration test above.
- [x] Every spec §10.2 client bullet maps to a core, web or mobile test above.
- [x] All eleven spec §10.3 smoke scenarios are present in Task 12.
- [x] Additive phase, client phase, atomic cutover and separate production gate remain distinct.
- [x] Candidate/final manifest and approval semantics are exact: any `uafklaret` is terminal, all record baselines are approved, and legacy `bevar`/`skjul` is a complete disjoint partition.
- [x] The plan contains no production mutation, no identity backfill, no legacy text editing, no full mobile editor and no #153/#149 implementation.
- [x] Task 12 includes Codex self-review followed by one read-only `claude-fable-5` review of `f53d965...HEAD`, critical finding disposition and rerun rules.
- [x] No placeholder, ellipsis-as-implementation, `TODO`, `TBD`, “similar to”, or unbound future choice remains.
