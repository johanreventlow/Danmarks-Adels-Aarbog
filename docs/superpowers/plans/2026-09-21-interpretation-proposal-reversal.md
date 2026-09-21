# Interpretation Proposal Reversal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use the projection delivery's exact result receipts to add append-only proposal reversal, controlled re-run, and commit-unknown result reading for finalized `interpretation_proposal` batches.

**Architecture:** The prerequisite receipt binds each proposal event to its exact interpretations, links, run, and dispositions. New operation-specific RPCs bind reversal authorization to a locked batch-state hash, supersede current proposal versions, restore prior clause dispositions by appending new versions, mark the batch reversed, and expose a read-only `not_started|reversed|drift` result; the existing generic `red_reverse_reimport` remains unchanged.

**Tech Stack:** PostgreSQL 17 PL/pgSQL, Supabase Auth/RLS conventions, R/DBI/RPostgres/jsonlite, testthat, dblink race tests, Python projection comparator.

**Spec:** `docs/superpowers/specs/2026-09-20-interpretation-proposal-prod-gate-design.md`

## Global Constraints

- This is roadmap step 4 and issue #196; it does not implement 4.5 decisions or promotion reversal.
- Prerequisite: the projection plan's `interpretation-proposal-result-v1` receipt and apply comparator are merged and green.
- The operation is edition-neutral and uses existing interpretation, observation-link, disposition, authorization, batch, and event tables.
- No proposal/link/disposition/run/event/authorization/batch row is deleted.
- `red_reverse_reimport(uuid,uuid)` and its activation/name-completion semantics remain unchanged.
- A reversal is allowed only for a pure, finalized proposal batch with exact receipts and no human decision, promotion, later interpretation version, later disposition, or foreign drift.
- Apply and reversal both fail closed if an affected pre-apply disposition is human; this workflow never overwrites or machine-copies editorial judgment.
- Reversal writes one `superseded` interpretation version per active proposal and copies its links.
- Reversal restores each affected clause by appending the pre-apply disposition as a new machine version.
- Re-run is allowed only when the current version is `superseded` by this operation and its originating batch is `reversed`.
- Errors contain stable codes plus ids, field names, hashes, and counts only; never source text or claim values.
- No production connection or production mutation is part of this plan.

## Review Focus

- A receipt with reordered arrays remains canonical, but a missing, duplicated, extra, or foreign claim/link/disposition fails.
- A human decision, direct later version, promotion, or later clause disposition racing reversal makes exactly one transaction win.
- A second reversal call after a verified success performs zero writes and returns the existing receipt.
- A consumed authorization with partial or mismatched state returns `drift`, never `reversed`.
- Controlled re-run accepts only the precise reversed lineage; any unrelated `superseded` version still fails with `REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`.

---

## File Structure

| File | Responsibility |
|---|---|
| `schema.sql` | Reversal state/auth/apply/result, controlled re-run, and grants. |
| `db-migrations.sql` | Idempotent migration to the same final catalog. |
| `db-rls.sql` | Explicit ACL inventory for new public/private functions. |
| `db-verify.sql` | Catalog, append-only, idempotence, denial, and dblink race verification. |
| `tests/sql/test-interpretation-proposal.sql` | Focused proposal receipt/reversal/re-run contract. |
| `tests/sql/run-db-verify-disposable.sql` | Require the three new dblink race anchors. |
| `tests/integration/test-reimport-interpretation-proposal.R` | End-to-end apply, reversal, recovery comparison, corrected re-run. |
| `tests/testthat/test-apply-reimport.R` | Client receipt and re-run result expectations. |
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | Preserve and validate per-element receipt metadata. |
| `.claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py` | Recovery-mode comparison. |
| `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py` | Synthetic recovery mutation matrix. |

### Task 1: Add closed reversal state and authorization

**Files:**
- Modify: `tests/sql/test-interpretation-proposal.sql`
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`

**Interfaces:**
- Produces:
  - `private.interpretation_proposal_reversal_state(uuid,boolean) -> jsonb`
  - `public.red_preflight_interpretation_proposal_reversal(uuid) -> jsonb`
  - `public.red_authorize_interpretation_proposal_reversal(uuid,text,jsonb,uuid,timestamptz) -> uuid`
- Authorization `operation` is `interpretation_proposal_reversal`.
- `expected_counts` keys are exactly `elements`, `claims`, `links`, and `dispositions`.
- `authorized_elements` keys are exactly `batch_id`, `proposal_state_sha256`, and `upstream_binding_sha256`.

- [ ] **Step 1: Write red state and authorization tests**

Assert the state result has exactly:

```json
{
  "schema_version": "interpretation-proposal-reversal-state-v1",
  "batch_id": "uuid",
  "manifest_sha256": "sha256",
  "source_id": 1,
  "profile_id": "profile",
  "profile_sha256": "sha256",
  "database_identity": "json text",
  "counts": {"elements": 1, "claims": 2, "links": 3, "dispositions": 2},
  "upstream_binding_sha256": "sha256",
  "proposal_state_sha256": "sha256"
}
```

Tests call the public authorizer with that exact state/counts and assert issued binding, actor, nonce, expiry, database identity, source/profile, and manifest. Mutate each argument separately and expect `REIMPORT_INTERPRETATION_REVERSAL_AUTHORIZATION_INVALID`.

- [ ] **Step 2: Run and verify missing functions fail**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
```

Expected: missing-function or authorization-invalid failure.

- [ ] **Step 3: Implement locked state derivation**

The private helper must acquire the generic writer lock and, in locking mode, lock the batch, receipt-addressed interpretations/dispositions, and every upstream row named below in deterministic id order. Verify a pure finalized proposal batch, recompute every receipt row hash, reject reversal/activation/canonical events, and reject all decision/promotion/later-version/later-disposition drift.

Build `upstream_binding_sha256` from the exact resolution graph used by the live writer: source record; its accepted anchor event and occurrence; the unique root observation; every cited clause and its current row hash; the root's source mention and unique primary persona link; the resolved source persona plus current identity and record/persona placement rows consulted by the writer; and the exact extraction-run row referenced by every receipt. Use the projection plan's closed row-receipt helpers where applicable. Build `proposal_state_sha256` over batch identity, this upstream binding, sorted event receipt hashes, sorted current interpretation ids/versions/statuses, sorted current clause disposition ids/versions/statuses/evidence hashes, target database identity, and zero decision/promotion counts. Both hashes use `private.interpretation_proposal_canonical_json_sha256`, never the legacy/general helper.

Tests mutate each dependency independently—including accepted anchor event/occurrence, root observation, cited clause, mention, primary persona link, persona identity, record/persona placement, extraction run, source/profile, and database target—and require the state or authorization to fail before a write. Add a two-session test that changes one upstream row after unlocked preflight but before apply; locked recomputation must reject it.

- [ ] **Step 4: Implement authorization and enum/check changes**

Extend `reimport_authorization.operation` to admit `interpretation_proposal_reversal`. The authorizer requires service-role execution, editor actor, expiry in the future, exact supplied state hash/upstream binding/counts, and current database identity. Store the exact state hash, upstream binding, and batch id in `authorized_elements`.

Add `red_preflight_interpretation_proposal_reversal(batch_id)` as the authenticated, read-only route to the same unlocked state helper. It returns the closed state object above, has no authorization side effect, and is the only metadata the operator copies into the service-role authorization call.

- [ ] **Step 5: Apply ACLs and catalog checks**

Revoke the private state helper from all client roles. Grant preflight only to `authenticated` and the authorizer only to `service_role`. Verify `anon` and PUBLIC cannot execute either, `authenticated` cannot execute the authorizer, and `service_role` cannot execute preflight. Add idempotent migration-side `DROP CONSTRAINT/ADD CONSTRAINT` logic for the operation check.

- [ ] **Step 6: Run and commit**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
git diff --check
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql   tests/sql/test-interpretation-proposal.sql
git commit -m "feat: authorize exact proposal reversals"
```

### Task 2: Implement append-only reversal and result reading

**Files:**
- Modify: `tests/sql/test-interpretation-proposal.sql`
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`

**Interfaces:**
- Produces:
  - `public.red_reverse_reimport_interpretation_proposal(uuid,uuid) -> jsonb`
  - `public.red_reimport_interpretation_proposal_reversal_result(uuid,uuid) -> jsonb`
  - `public.red_reimport_interpretation_proposal_result(uuid) -> jsonb`
- Result keys: `batch_id`, `authorization_id`, `status`, `proposal_state_sha256`, `reversal_event_id`, `counts`.
- Status is exactly `not_started`, `reversed`, or `drift`.
- Proposal-result keys are exactly `authorization_id`, `batch_id`, `status`, `source_id`, `profile_id`, `manifest_sha256`, `preview_sha256`, and `counts`; status is exactly `not_started`, `committed`, or `drift`.

- [ ] **Step 1: Write the red success, append-only, and idempotence tests**

Snapshot row counts and current semantic state. Reverse once and assert:
- one new `superseded` version per proposal;
- copied observation links;
- one new disposition version per affected clause restoring the version immediately before apply;
- unchanged counts of extraction runs and proposal events;
- one reversal event;
- consumed authorization;
- original batch `reversed`;
- no deletes from any involved table.

Call result and reversal again. Both return `reversed` and all counts remain unchanged.

- [ ] **Step 2: Write red denial tests**

For independent fixtures, add a later accepted/rejected/unresolved/superseded decision, a promotion, a direct later proposed version, a later clause disposition, a changed link, a changed run, an altered receipt, a mixed batch event, a human pre-apply disposition, an expired/wrong-actor/reused authorization, and a different database identity. Mutate each upstream binding component from Task 1 separately. Each must raise `REIMPORT_INTERPRETATION_REVERSAL_INVALID` and leave all row counts and current states unchanged.

- [ ] **Step 3: Run and verify the missing RPCs fail**

Run the focused SQL file. Expected: missing-function failures.

- [ ] **Step 4: Implement reversal in one transaction**

Lock in this order: generic writer advisory lock; original batch `FOR UPDATE`; authorization `FOR UPDATE`; receipt-addressed interpretations ordered by id; clauses ordered by observation id. Recompute the authorized state.

For every claim receipt, insert a copied interpretation with:
- version + 1;
- status `superseded`;
- `supersedes_id` = current proposal id;
- copied source, persona, kind, predicate, value, schema, derivation, confidence, method, model, prompt, and run;
- decision evidence keys exactly `reversal_kind`, `original_batch_id`, `original_event_id`, `manifest_sha256`, `authorization_id`, and `proposal_state_sha256`;
- current actor/name/time.

Copy links from the proposal to its superseding row. For each clause, read the maximum disposition version strictly below the proposal-written version, require `decided_by_kind='machine'`, and append its disposition as a new machine version. Evidence keys are exactly `manifest_sha256`, `batch_id`, `reversal_kind`, `original_disposition_version`, `restored_evidence_sha256`, `authorization_id`, and `proposal_state_sha256`: `manifest_sha256` and `batch_id` are the original proposal batch's trigger-valid values, while `restored_evidence_sha256` binds the closed prior evidence without copying an open object. Tests must execute the live `trg_clause_disposition_validate` success path and prove invalid/missing manifest and UUID provenance fail.

Insert one reversal event whose closed receipt contains sorted old/new interpretation ids and old/restored disposition ids/versions plus counts. Hash only that receipt. Consume authorization and set batch status `reversed`.

- [ ] **Step 5: Implement fail-closed result reading**

The result function authenticates the same actor and binds batch/auth/database/source/profile/manifest. Return `not_started` only when authorization is still issued and no reversal event exists. Return `reversed` only when authorization is consumed, batch reversed, one exact reversal event exists, all current versions/dispositions match its receipt, and no decision/promotion exists. Return `drift` for every partial or conflicting state; never repair it.

At the top of the reversal RPC, call the result helper. If it says `reversed`, return it without writes; if `drift`, raise; only `not_started` may continue.

Implement the proposal-result RPC by authorization id so recovery does not depend on a batch id held only in a crashed process. It authenticates the editor actor, recomputes current database identity and requires it to equal the authorization binding, requires `operation='reimport'`, and requires every `authorized_elements` key to match `^interpretation-proposal:.+$` with the exact closed proposal payload shape. Return `not_started` only for one issued authorization with zero batches/events. Return `committed` only for one consumed authorization, exactly one finalized batch, exact source/profile/manifest/preview/count binding, one exact event per authorized element, and receipt hashes/current rows that all validate. Every open, duplicate, partial, wrong-target, wrong-actor, mixed-operation, or inconsistent state returns `drift`; it performs no repair and emits no raw payload. Add catalog/ACL and state-matrix tests for all three statuses.

- [ ] **Step 6: Apply ACLs, run, and commit**

Grant apply and both result functions only to `authenticated`; revoke from `anon`, `service_role`, and PUBLIC. Run:

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
git diff --check
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql   tests/sql/test-interpretation-proposal.sql
git commit -m "feat: reverse proposal batches append only"
```

### Task 3: Permit only controlled re-run after reversal

**Files:**
- Modify: `tests/sql/test-interpretation-proposal.sql`
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `tests/testthat/test-apply-reimport.R`
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`

**Interfaces:**
- Existing `red_apply_reimport_interpretation_proposal` signature is unchanged.
- Writer result adds `interpretation_versions_written`, keyed by claim id, while retaining `interpretations_written`, `clauses_dispositioned`, `run_id`, and `result_receipt_sha256`.

- [ ] **Step 1: Write red re-run acceptance and rejection tests**

Apply and reverse a batch. A corrected manifest with one unchanged claim and one changed claim must create:
- version 3 for the unchanged deterministic key, superseding the reversal's version 2;
- version 1 for the changed key;
- only the new manifest's links;
- a new extraction run if runner hash changed;
- exact new receipts and dispositions.

Separately prove rejection for current statuses `proposed`, `accepted`, `rejected`, `unresolved`, unrelated `superseded`, a superseded row missing reversal evidence, a non-reversed originating batch, a promoted lineage, and a newer version.

- [ ] **Step 2: Run and verify existing writer rejects the valid re-run**

Expected: `REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS` for the valid reversed lineage.

- [ ] **Step 3: Replace the unconditional exists check**

When the deterministic key exists, lock its current row. Accept only if all are true:
- current status `superseded`;
- current row is the newest version;
- decision evidence has `reversal_kind = interpretation_proposal`;
- its `original_batch_id` exists with status `reversed`;
- the cited reversal event and authorization match that batch;
- no promotion references any row in the interpretation-key lineage.

Insert the new proposal with `version=current.version+1` and `supersedes_id=current.id`. Otherwise raise the existing `REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS` code.

- [ ] **Step 4: Validate the richer writer result in R**

Update the fake gateway and assertions so each returned claim id maps to the expected version and the receipt hash is a lowercase SHA-256. Keep other dependency classes and the general CLI unchanged.

- [ ] **Step 5: Run and commit**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
git add schema.sql db-migrations.sql   tests/sql/test-interpretation-proposal.sql   tests/testthat/test-apply-reimport.R   .claude/skills/daa-extract/scripts/apply_reimport_helpers.R
git commit -m "feat: rerun reversed interpretation proposals"
```

### Task 4: Prove race safety

**Files:**
- Modify: `db-verify.sql`
- Modify: `tests/sql/run-db-verify-disposable.sql`
- Modify: `tests/sql/test-interpretation-proposal.sql`

**Interfaces:**
- Produces three dblink anchors: `daa.verify_dblink_proposal_reversal_decision`, `daa.verify_dblink_proposal_reversal_promotion`, and `daa.verify_dblink_proposal_reversal_disposition`, each set to `executed`.

- [ ] **Step 1: Add dblink tests for both lock orderings of all three conflicts**

For each decision, promotion, and disposition case, create fresh fixtures for both schedules:

1. competitor A locks first, asynchronous reversal B blocks, A commits, then B resumes and rejects with zero writes;
2. reversal A locks first, asynchronous competitor B blocks, A commits, then B resumes and rejects with zero writes.

Use `dblink_send_query`, prove the waiting connection is actually busy before releasing A, and set bounded `lock_timeout`/`statement_timeout`. Assert no timeout or deadlock token is treated as success. After both sessions finish, assert:
- exactly one operation committed;
- reversal either fully committed or wrote zero rows;
- no partial superseded/link/disposition/event state;
- result is `reversed` for a reversal win or `drift`/the exact coded rejection for a competitor win;
- the winner's receipt and all loser row-count deltas are exact.

- [ ] **Step 2: Require all anchors in the disposable runner**

Extend the current seven-gate table to ten gates and keep the final missing-gate assertion.

- [ ] **Step 3: Run full disposable db-verify**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
```

Expected: all ten dblink gates report `executed`.

- [ ] **Step 4: Commit**

```bash
git add db-verify.sql tests/sql/run-db-verify-disposable.sql   tests/sql/test-interpretation-proposal.sql
git commit -m "test: prove proposal reversal races"
```

### Task 5: Extend the projection to recovery and prove the full local cycle

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py`
- Modify: `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py`
- Modify: `tests/integration/test-reimport-interpretation-proposal.R`
- Create: `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-reversal-rehearsal.md`

**Interfaces:**
- Produces `compare_recovery(manifest, before, applied, reversed, expected_target_sha256) -> dict` with scope `interpretation-proposal-recovery-v1`.
- Produces `compare_rerun(manifest, reversed, after, expected_target_sha256) -> dict` with scope `interpretation-proposal-rerun-v1`; the fresh `compare_apply` contract remains strict and unchanged.

- [ ] **Step 1: Write red recovery mutation tests**

A valid recovery keeps append-only history but restores active semantics. Mutate separately: batch status, auth status, reversal event receipt/hash, superseded version, copied links, current disposition, decision/promotion count, upstream/canonical/anon hashes, and any foreign row. Each mutation must fail with a specific code.

- [ ] **Step 2: Implement semantic recovery comparison**

Require:
- same source and target through all three projections;
- unchanged five neutral lists and upstream/canonical/anon/promotion surfaces;
- applied projection still proves the original apply;
- original batch is reversed with one exact reversal event;
- no current proposed/accepted target interpretation or promotion;
- current target key versions are the expected superseded rows with copied links;
- current clause dispositions equal the before projection's current dispositions;
- all expected proposal, superseded, disposition, auth, batch, and event history remains append-only.

Return counts for superseded claims, copied links, restored dispositions, and reversal events.

- [ ] **Step 3: Implement the separate corrected-rerun comparison**

`compare_rerun` first validates that `reversed` is a complete recovery state. For an unchanged deterministic interpretation key, it accepts a new proposal only when the immediately prior current row is the exact reversal-created `superseded` row, whose evidence names the expected original batch, reversal event, reversal authorization, state hash, and manifest; the new proposal must then be version `prior+1` and supersede that row. For a changed claim id/key, the key must be absent from the reversed projection and the new proposal must be version 1. Reject unrelated superseded rows, wrong batch/event/authorization/evidence, a newer version, decision, promotion, foreign history, or use of a key not justified by the corrected manifest.

Expose this only through a closed CLI mode `--mode rerun --manifest PATH --reversed PATH --after PATH --expect-target-sha256 HASH --report PATH`. Fresh comparison remains `--mode fresh --before PATH --after PATH ...` and retains its preexisting-target rejection. Missing or cross-mode arguments fail schema validation.

- [ ] **Step 4: Extend the integration sequence**

After apply match:
1. derive state and issue exact reversal authorization;
2. call result and require `not_started`;
3. reverse and require `reversed`;
4. call reverse again and assert zero count change;
5. project and require recovery `match`;
6. build a corrected manifest, re-run with unchanged and changed keys;
7. project and require rerun `match` from `compare_rerun`, never from the fresh comparator.

- [ ] **Step 5: Run all relevant suites**

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   .claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py -q
Rscript run-tests.R
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
Rscript tests/integration/test-reimport-interpretation-proposal.R
git diff --check
```

Expected: Python PASS, R `FAIL 0`, SQL gates PASS, integration success marker, and no whitespace errors.

- [ ] **Step 6: Record evidence and commit**

Record exact commands, catalog ordering, ids/hashes/counts, apply result, reversal result, recovery comparison, and corrected re-run comparison. Do not include values, text, names, DSNs, or credentials. End with `Produktions-GO: IKKE GIVET`.

```bash
git add .claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   tests/integration/test-reimport-interpretation-proposal.R   docs/evidensbaseret-genimport/proposal-ingest-147-4-4-reversal-rehearsal.md
git commit -m "test: prove proposal reversal and rerun"
```
