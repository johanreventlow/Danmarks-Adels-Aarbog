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
- `service_role` may issue only the named authorization through its SECURITY DEFINER RPC; it has no direct DML on any #196 write-set or upstream-binding table. Database owner/admin access is outside the application-role trust boundary and is held by the runbook's schema/write freeze.
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
| `tests/sql/run-db-verify-disposable.sql` | Require every newly named reversal/result/generic-lock dblink race anchor in addition to the existing exact set. |
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
- Create: `tests/sql/interpretation-proposal-service-role-grants.sql`

**Interfaces:**
- Produces:
  - `private.interpretation_proposal_reversal_state(uuid,boolean) -> jsonb`
  - `private.interpretation_proposal_deployment_contract() -> jsonb`
  - `public.red_interpretation_proposal_deployment_receipt() -> jsonb`
  - `public.red_lock_interpretation_proposal_contract(text) -> jsonb`
  - `private.interpretation_proposal_authorization_binding(private.reimport_authorization) -> jsonb`
  - `public.red_interpretation_proposal_authorization_binding(uuid) -> jsonb`
  - `public.red_preflight_interpretation_proposal_reversal(uuid) -> jsonb`
  - `public.red_authorize_interpretation_proposal_reversal(uuid,text,jsonb,uuid,timestamptz) -> uuid`
- Authorization `operation` is `interpretation_proposal_reversal`.
- `expected_counts` keys are exactly `elements`, `claims`, `links`, and `dispositions`.
- `authorized_elements` keys are exactly `batch_id`, `proposal_authorization_id`, `proposal_authorization_binding_sha256`, `proposal_state_sha256`, and `upstream_binding_sha256`.

- [ ] **Step 1: Write red state and authorization tests**

Assert the state result has exactly:

```json
{
  "schema_version": "interpretation-proposal-reversal-state-v1",
  "batch_id": "uuid",
  "proposal_authorization_id": "uuid",
  "proposal_authorization_binding_sha256": "sha256",
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

`proposal_authorization_id` is exactly the locked original batch row's `authorization_id`; its binding hash is recomputed from that locked proposal authorization with the same private immutable helper used by proposal-result. Tests call the public reversal authorizer with that exact state/counts and assert both original proposal fields are copied into the reversal authorization's five-key `authorized_elements`. Separately assert that the authorization row and its immutable binding carry actor, nonce, expiry, database identity, source/profile, manifest, and expected counts in their documented fields. Mutate each argument separately—including replacing the original proposal authorization with a replay authorization for the same manifest—and expect `REIMPORT_INTERPRETATION_REVERSAL_AUTHORIZATION_INVALID`.

Assert the authorization-binding RPC returns exactly `schema_version`, `authorization_id`, `authorization_binding_sha256`, `state_receipt_sha256`, `status`, `consumed_at`, and `expires_at`. The private closed binding hashes id, operation, principal, source/profile/profile SHA, manifest/preview/database identity, expected counts, authorized elements, nonce, created/issued timestamp, and expiry; it excludes mutable status and consumed-at. The DB-produced state receipt hashes the binding hash plus the **current** status/consumed-at. While issuing the execution or reversal envelope, require live `issued`, consumed-at NULL, and future expiry, and retain that returned state-receipt hash as `authorization_issue_receipt_sha256`. After consumption or expiry, the RPC returns the same immutable binding hash, current mutable fields, and a correspondingly changed state-receipt hash; result recovery compares only the immutable binding and retains the original issue receipt as envelope history.

- [ ] **Step 2: Run and verify missing functions fail**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
```

Expected: missing-function or authorization-invalid failure.

- [ ] **Step 3: Implement locked state derivation**

The end-to-end production path follows one enforceable global order that includes both client and SQL locks: first the existing gateway `hashtextextended('daa-reimport:'||source_id||':'||profile_id,0)` advisory lock owned by the wrapper/executor, then the **exclusive** `hashtextextended('daa-narrative-record-contract',0)` advisory lock, then the private generic `daa-reimport-writer:*` source/profile lock, then the accepted-anchor advisory keys `hashtextextended(source_record_id::text,154155)` in record-id order, and only then authorization/batch/upstream/receipt rows in deterministic id order. SQL helpers begin at the narrative lock and never request the client gateway lock; a direct RPC caller therefore cannot acquire that lock in the inverse order. Add `red_lock_interpretation_proposal_contract(expected_deployment_contract_sha256)` as the proposal-apply transaction-entry RPC. It authenticates the already established editor without taking a narrative shared lock, takes the exclusive contract lock, recomputes the closed deployment contract, requires its SHA to equal the envelope value, and returns exactly the same schema version, narrative contract version, database target hash, and deployment-contract SHA as the public deployment receipt. The production gateway must call it through the projection delivery's existing post-advisory transaction-entry hook as the first operation RPC after `begin` and the gateway lock; no generic preflight or SQL shared-locking RPC may precede it.

Make that order true in every SQL path that can participate. For pure proposal authorizations, change both `public.red_preflight_reimport_authorization` and `public.red_begin_reimport`: provisionally read source/profile and the complete closed `authorized_elements` without a row lock; validate that every element is a proposal payload; resolve every distinct record key to exactly one `source_record.id`; take the writer lock and all distinct anchor keys sorted by id; only then lock and re-read the complete authorization row, require the provisional source/profile/elements/map to be unchanged, and proceed with issued-state validation or replay/batch row locks. This is essential because the executor calls preflight-authorization before begin-batch; neither function may hold the authorization row while waiting for an anchor. Change `private.write_interpretation_proposal` to perform the same unlocked batch/source/key discovery, writer lock, sorted anchor lock, and locked recheck **before** `private.require_reimport_open_batch` or any source/occurrence/observation row lock. Re-acquiring keys already held by preflight/begin is intentional and nonblocking. Missing, duplicate, or changed mappings fail closed with zero writes. Non-proposal preflight/begin paths retain their existing behavior.

The standalone `red_interpretation_proposal_authorization_binding` remains a closed, non-authoritative envelope-construction reader and takes no `FOR UPDATE` row lock; inside a write transaction it is called only after the proposal-aware generic preflight has acquired anchors and locked/revalidated the authorization. Also move the accepted-case anchor lock in `private.validate_source_record_anchor_event` before its occurrence `FOR UPDATE`, and the accepted-case anchor lock in `private.validate_source_record_revision_event` before its ordered source-record `FOR UPDATE`. Mirror all five changed bodies—preflight, begin, writer, and both triggers—in `schema.sql` and `db-migrations.sql`. Source-order tests inspect effective function bodies, and mutation/race tests must turn red if either early proposal preflight/begin lock, the writer lock, either trigger lock, sorted ordering, or any post-lock recheck is removed.

Make the premise "all competing writers take the shared side" true in live code: `red_decide_interpretation` and `red_promote_interpretations_batch` acquire the shared narrative-contract lock before any row lock or mutation, and `private.validate_clause_disposition()` acquires it before validating every direct or indirect disposition insert. Existing reimport writers already acquire the shared side. Reversal may invoke the trigger while already holding exclusive; it never attempts shared-to-exclusive upgrade. Tests assert the first lock operation on each path and prove no relevant decision, promotion, or disposition writer bypasses the guard. The ACL contract separately denies direct client DML, so the guarded RPC/trigger paths are exhaustive for application roles. Then verify a pure finalized proposal batch, recompute every receipt row hash after all locks, reject reversal/activation/canonical events, and reject all decision/promotion/later-version/later-disposition drift.

Build `upstream_binding_sha256` from the exact resolution graph used by the live writer: source record; accepted anchor event and occurrence; unique root observation; every cited clause; root source mentions and the unique primary `source_persona_mention`; resolved source persona; each referenced active `interpretation_predicate` row; and the exact extraction-run row referenced by every receipt. Do not claim identity or placement rows are writer inputs: they remain in the broad projection drift hash, not this operation-state graph. Use the projection plan's closed row-receipt helpers where applicable. Build `proposal_state_sha256` over batch identity including its original `authorization_id` and recomputed immutable proposal-authorization binding hash, this upstream binding, sorted event receipt hashes, sorted current interpretation ids/versions/statuses, sorted current clause disposition ids/versions/statuses/evidence hashes, target database identity, and zero decision/promotion counts. Both hashes use `private.interpretation_proposal_canonical_json_sha256`, never the legacy/general helper.

Tests mutate each actual dependency independently—including accepted anchor event/occurrence, root observation, cited clause, mention, primary persona link, source persona, predicate row, extraction run, source/profile, and database target—and require the state or authorization to fail before a write. Add two-session tests for an anchor change and a primary-persona-link change after unlocked preflight: proposal/reversal must either acquire the gateway/contract/writer/anchor locks in the common order and win completely, or wait and then reject the changed binding with zero writes. Add proposal-preflight-versus-reversal and proposal-begin-versus-reversal schedules in both startordener; require observed waiting, no deadlock-as-success, and prove the proposal cannot hold an authorization/batch row while waiting for an anchor held by reversal. Add a real unchanged generic reimport flow versus production proposal flow on the same source/profile in both startordener; assert the second session waits, both eventually terminate without deadlock/timeout-as-success, and the captured order is gateway lock before shared/exclusive narrative lock on both sides.

- [ ] **Step 4: Implement authorization and enum/check changes**

Extend `reimport_authorization.operation` to admit `interpretation_proposal_reversal`. The authorizer requires service-role execution, editor actor, expiry in the future, exact supplied state hash/upstream binding/counts, current database identity, and the locked batch's exact original proposal authorization id/binding hash. Store the state hash, upstream binding, batch id, proposal authorization id, and proposal authorization binding hash in `authorized_elements`.

Add `red_preflight_interpretation_proposal_reversal(batch_id)` as the authenticated, read-only route to the same unlocked state helper. It returns the closed state object above, including the original proposal authorization id and immutable binding hash, has no authorization side effect, and is the only metadata the operator copies into the service-role authorization call.

Add `red_interpretation_proposal_authorization_binding(authorization_id)` as authenticated, actor-bound **non-locking metadata access** for envelope construction and inspection. It is valid for issued or consumed and before or after expiry. It performs one plain row read with no narrative/writer advisory lock and no `FOR UPDATE`, validates proposal/reversal operation shape and actor, and returns only the closed point-in-time fields above. It is never operation authority: inside write mode the proposal-aware issued-only preflight first owns the authoritative anchor/authorization locks, and only then may the same transaction call this reader; proposal/reversal result RPCs recompute the private binding from their own already locked row. Result RPCs receive the expected authorization-binding SHA and expected deployment-contract SHA and compare both under their own locks; recovery never relies on the standalone reader, direct table access, or the issued-only generic preflight RPC. Tests reject any advisory or row-lock clause in the public reader's effective body and prove a concurrent state transition is classified only by preflight/result, not by the reader.

`private.interpretation_proposal_deployment_contract()` builds a closed, versioned catalog object from an exact inventory of every #196 function definition/signature, trigger definition, altered constraint/index, and effective function **and table** ACL, including the changed decision/promotion/disposition writers. The table inventory includes `reimport_writer_profile`, `extraction_run`, `source_record`, `source_record_occurrence`, `source_record_anchor_event`, `source_observation`, `source_mention`, `source_persona`, `source_persona_mention`, `interpretation_predicate`, `interpretation`, `interpretation_observation`, `interpretation_promotion_rule_line`, `interpretation_promotion_rule`, `interpretation_promotion_batch`, `interpretation_promotion`, `clause_disposition`, `reimport_authorization`, `reimport_batch`, and `reimport_event`. It uses `pg_get_functiondef`, fixed `COLLATE "C"` ordering, both expected-minus-actual and actual-minus-expected inventory checks, and the operation-specific canonical hash. The public receipt exposes only schema version, narrative contract version, database target hash, and `deployment_contract_sha256`; it performs no DML. Golden catalog tests change or omit one inventoried object/ACL at a time and require a changed hash or a closed inventory error.

- [ ] **Step 5: Apply ACLs and catalog checks**

Revoke the private state/deployment/binding helpers from all client roles. Grant preflight, deployment receipt, proposal contract-lock, and authorization-binding readback only to `authenticated`, and the authorizer only to `service_role`. Verify `anon` and PUBLIC cannot execute any of them, `authenticated` cannot execute the authorizer, and `service_role` cannot execute the client RPCs. Explicitly `REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` from `service_role` on every table in the deployment inventory above; do not rely on the local bootstrap's absence of grants. Assert every table/privilege pair with both catalog ACL expansion and `has_table_privilege`, and add negative `SET LOCAL ROLE service_role` attempts for insert/update/delete through the repository savepoint-based expected-error helper. The only allowed service-role mutation in this workflow is the named SECURITY DEFINER authorizer.

Add a production-like grant fixture that grants `service_role` the relevant private-schema/table defaults **after all tables exist and immediately before the final `db-rls.sql` pass** in both catalog orderings. The final ACL layer must remove every simulated direct DML grant, so CI turns red if any explicit revoke disappears. Owner/admin DML is not modeled as an application path and remains prohibited by the rehearsal/production freeze. Add idempotent migration-side `DROP CONSTRAINT/ADD CONSTRAINT` logic for the operation check. Add every exact function signature and table denial to the corresponding allow/deny inventories in `db-rls.sql`; add expected-minus-actual and actual-minus-expected assertions to `db-verify.sql` for fresh and migration catalogs. The contract-lock and deployment receipt signatures plus the table-denial set are part of the catalog contract, and tests prove no overload or DML privilege is accidentally available.

- [ ] **Step 6: Run and commit**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
git diff --check
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql   tests/sql/test-interpretation-proposal.sql   tests/sql/interpretation-proposal-service-role-grants.sql
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
  - `public.red_reverse_reimport_interpretation_proposal(uuid,uuid,text,text) -> jsonb`
  - `public.red_reimport_interpretation_proposal_reversal_result(uuid,uuid,text,text) -> jsonb`
  - `public.red_reimport_interpretation_proposal_result(uuid,text,text) -> jsonb`
- The two trailing text parameters are expected immutable authorization-binding SHA and expected deployment-contract SHA; each RPC recomputes and compares them after its contract lock.
- Result keys: `schema_version`, `batch_id`, `authorization_id`, `status`, `proposal_state_sha256`, `reversal_event_id`, `counts`.
- Status is exactly `not_started`, `reversed`, or `drift`.
- Proposal-result keys are exactly `schema_version`, `authorization_id`, `batch_id`, `status`, `source_id`, `profile_id`, `manifest_sha256`, `preview_sha256`, and `counts`; status is exactly `not_started`, `committed`, or `drift`.
- Schema versions are respectively `interpretation-proposal-reversal-result-v1` and `interpretation-proposal-result-v1`. Both `counts` objects have exactly `elements`, `claims`, `links`, and `dispositions`: zeroes for `not_started`, exact nonnegative counts for success, and JSON null for `drift`. Proposal status matrix: `not_started` has null `batch_id`, non-null positive bigint `source_id`, non-empty `profile_id`, and lowercase 64-hex manifest/preview hashes from the locked authorization; `committed` has a UUID batch plus the same four non-null binding fields; `drift` has JSON null for batch, source, profile, manifest, preview, and counts. Missing or ambiguous authorization discovery returns that exact `drift` shape; malformed arguments, caller/capability failure, and deployment-contract mismatch are named exceptions. Reversal `batch_id` is always its input UUID. `reversal_event_id` is null for `not_started|drift` and for `reversed` is the existing `private.reimport_event.id` bigint encoded as a canonical positive base-10 JSON string matching `^[1-9][0-9]{0,18}$` and not exceeding signed bigint max; it is never a UUID or JSON number. `proposal_state_sha256` is a hash for `not_started|reversed` and JSON null for `drift`. Tests pin every status-specific type, nullability rule, numeric bound, and nested key set.

- [ ] **Step 1: Write the red success, append-only, and idempotence tests**

Snapshot row counts and current semantic state. Reverse once and assert:
- one new `superseded` version per proposal;
- copied observation links;
- one new disposition version per distinct affected clause restoring the exact `before` receipt at the start of the batch, even when multiple proposal events touched that clause;
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

The documented wrapper takes the existing gateway source/profile advisory lock before calling reversal. Inside the RPC use Task 1's exact SQL order: exclusive narrative-contract advisory lock; recompute/compare expected deployment-contract hash; provisional source/profile/record-key discovery; private generic writer lock; sorted anchor advisory keys; original batch, its original proposal authorization, and reversal authorization `FOR UPDATE` in the one documented deterministic order; recompute/compare the provisional map, the batch's proposal authorization id/binding against reversal `authorized_elements`, and the expected reversal immutable authorization-binding hash; actual upstream rows; receipt-addressed interpretations ordered by id; clauses and their complete disposition chains ordered by observation id/version. A direct server call never requests the client gateway lock after taking exclusive, so it cannot form the inverse cycle. Recompute the authorized state after locks and immediately before the first insert.

After the final locked state check and before any insert, allocate `reversal_event_id bigint` once with `nextval(pg_get_serial_sequence('private.reimport_event','id'))`. A rolled-back attempt may leave an identity-sequence gap; gaps carry no semantics. Encode the allocated bigint as its canonical positive decimal **string** in every JSON evidence/result object, while inserting the bigint itself explicitly into `private.reimport_event.id`. Require the value to be positive and within signed-bigint range. Never insert dependent rows first and patch their evidence later.

For every claim receipt, insert a copied interpretation with:
- version + 1;
- status `superseded`;
- `supersedes_id` = current proposal id;
- copied source, persona, kind, predicate, value, schema, derivation, confidence, method, model, prompt, and run;
- decision evidence keys exactly `reversal_kind`, `original_batch_id`, `original_event_id`, `reversal_event_id`, `manifest_sha256`, `authorization_id`, and `proposal_state_sha256`;
- current actor/name/time.

Copy links from the proposal to its superseding row. Require exactly one receipt-addressed proposal event per source record and at most one `before → written` clause receipt per observation in that event; multiple claims in the event are already folded to that one disposition. A duplicate/forked clause receipt or any cross-event reuse of an observation is `REIMPORT_INTERPRETATION_REVERSAL_INVALID`, not a chain that reversal may repair. Its single trigger-valid machine `before`, not `max(version)`, is the restoration authority. Append that original disposition exactly once per clause. Evidence keys are exactly `manifest_sha256`, `batch_id`, `reversal_kind`, `reversal_event_id`, `original_disposition_version`, `restored_evidence_sha256`, `authorization_id`, and `proposal_state_sha256`: `manifest_sha256` and `batch_id` are the original proposal batch's trigger-valid values, while `restored_evidence_sha256` binds the closed prior evidence without copying an open object. Tests must execute the live `trg_clause_disposition_validate` success path and cover no-prestate, human-prestate, several claims in one event sharing a clause, a duplicate cross-event clause receipt, invalid/missing manifest, invalid UUID batch provenance, and UUID/numeric/zero/out-of-range reversal-event representations.

Insert the preallocated bigint reversal event id once; its closed receipt contains sorted old/new interpretation ids and old/restored disposition ids/versions plus counts and proves every written evidence object carries the same canonical decimal-string representation. Hash only that receipt. Consume authorization and set batch status `reversed`.

- [ ] **Step 5: Implement fail-closed result reading**

Both result helpers authenticate the same actor and use a no-data-write but lock-taking transaction. Before classifying, acquire the shared narrative-contract lock; recompute and compare the expected deployment-contract hash; discover source/profile and the complete proposal record-key map provisionally from the authorization; acquire the same generic writer lock as apply; acquire every resolved anchor key in sorted record-id order; then lock and re-read the authorization row, recompute/compare the provisional map and immutable binding, and lock batch/events in deterministic id order. From the locked receipts, lock every addressed current interpretation in id order, every affected `source_observation` in id order, every complete disposition chain in observation-id/version order, and every matching promotion batch/promotion row in id order before reading decision/status/promotion/disposition state. This mirrors the row domains locked by live proposal, anchor, decision, promotion, and disposition writers and makes the resolver wait for both the apply/reversal transaction and any in-flight downstream writer. It may not observe an unlocked `issued`/zero-batch or half-decided intermediate state. If provisional discovery changes on locked re-read, is missing, or has ambiguous multiplicity, return the exact all-null-binding `drift` shape, not `not_started`.

Add two-start-order dblink tests for result-vs-decision, result-vs-promotion, and result-vs-disposition: competitor first makes result wait then classify the committed competitor state; result first makes the competitor wait until classification completes. Require observed wait state, bounded timeouts, no deadlock-as-success, exact result status, and zero writes from the result function. Mutation tests that remove any domain-row lock must turn at least one schedule red.

The reversal result then binds batch/reversal-auth/database/source/profile/manifest and also requires the locked batch's original proposal authorization id and recomputed immutable binding to equal the two values stored in reversal `authorized_elements`. Result lookup matches the envelope's reversal immutable authorization binding but deliberately does not require future expiry. Return `not_started` only after those locks when reversal authorization is still issued and no reversal event exists, even if its wall-clock expiry has passed. Return `reversed` only when reversal authorization is consumed, batch reversed, one exact reversal event exists, all current versions/dispositions match its receipt, the original proposal authorization binding still matches, and no decision/promotion exists. Return `drift` for every partial or conflicting state; never repair it.

The reversal RPC acquires Task 1's exclusive narrative-contract lock **before** calling a private result helper with `contract_lock_already_held=true`; it must never acquire shared and then upgrade to exclusive. The standalone public result RPC calls the same helper with `false` and acquires the shared side itself. If the locked result says `reversed`, return it without writes; if `drift`, raise; only `not_started` may continue.

Implement the proposal-result RPC by authorization id so recovery does not depend on a batch id held only in a crashed process. After the common lock protocol above, it recomputes current database identity and requires it to equal the immutable authorization binding, requires `operation='reimport'`, and requires every `authorized_elements` key to match `^interpretation-proposal:.+$` with the exact closed proposal payload shape. It never requires future expiry. Return `not_started` only for one locked issued authorization with zero batches/events after any concurrent writer has completed, including after expiry, using the four non-null binding fields from that authorization. Return `committed` only for one consumed authorization, exactly one finalized batch, exact source/profile/manifest/preview/count binding, one exact event per authorized element, and receipt hashes/current rows that all validate. Missing/ambiguous authorization and every open, duplicate, partial, wrong-target, wrong-actor, mixed-operation, or inconsistent state return the exact all-null-binding `drift` object; malformed input, caller/capability failure, and deployment-contract mismatch raise their named closed errors. It performs no repair and emits no raw payload. Add catalog/ACL/state-matrix tests plus async commit/rollback races proving the result call waits and then returns `committed`/`not_started` respectively, both before and after authorization expiry.

- [ ] **Step 6: Apply ACLs, run, and commit**

Grant apply and both result functions only to `authenticated`; revoke from `anon`, `service_role`, and PUBLIC. Together with Task 1, add the exact seven authenticated signatures (deployment receipt, contract lock, authorization binding, preflight, reverse, reversal-result, proposal-result) and the one service-role authorizer signature to `db-rls.sql`'s positive allowlists, and assert both missing and excess entries in `db-verify.sql` under both catalog orderings. Pin the new result signatures including both expected-hash arguments and reject executable overloads. Run:

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

Compute the key only through `private.interpretation_proposal_key` from the projection plan. The writer recomputes it from the authorized payload, returns the manifest `claim_id` and SQL key in the same receipt entry, and the SQL tests pin that mapping. `claim_id` is not a truncated representation of the UUID and must never be substituted for it.

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
- Modify: `.github/workflows/ci.yml`
- Use: `tests/sql/interpretation-proposal-service-role-grants.sql` created in Task 1.

**Interfaces:**
- Produces the three reversal conflict anchors `daa.verify_dblink_proposal_reversal_decision`, `daa.verify_dblink_proposal_reversal_promotion`, and `daa.verify_dblink_proposal_reversal_disposition`; the six result/competitor anchors `daa.verify_dblink_proposal_result_decision_competitor_first`, `daa.verify_dblink_proposal_result_decision_result_first`, `daa.verify_dblink_proposal_result_promotion_competitor_first`, `daa.verify_dblink_proposal_result_promotion_result_first`, `daa.verify_dblink_proposal_result_disposition_competitor_first`, and `daa.verify_dblink_proposal_result_disposition_result_first`; plus `daa.verify_dblink_proposal_generic_first` and `daa.verify_dblink_proposal_first` for the live generic-flow lock order. Set each to `executed` only after its full assertions.

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

Before the concurrency schedules, add focused catalog/source tests that remove the shared lock from each of `red_decide_interpretation`, `red_promote_interpretations_batch`, and `private.validate_clause_disposition` and show the corresponding test turns red. For the disposition schedule, perform the competing insert through the real trigger; direct table access is test setup only, not a new client API. Separately seed production-like `service_role` table grants, run the final ACL script, and prove direct writer-profile, interpretation, link, promotion, disposition, authorization, batch, event, and upstream-binding mutations all fail while the service-role authorizer still succeeds.

Add the two named generic/proposal schedules on one source/profile using the real unchanged generic executor/RPC path and the production proposal sequence. In generic-first, prove proposal waits on the gateway lock before it can hold exclusive narrative lock. In proposal-first, prove generic waits on the gateway lock and never holds it while waiting for shared narrative lock. Capture the actual advisory keys/order, require both sessions eventually complete after release, and reject timeout/deadlock as success. A mutant that moves transaction-entry before gateway `advisory_lock` must turn at least one schedule red.

- [ ] **Step 2: Require all anchors in the disposable runner**

Extend the current seven-gate table for every new race/ACL anchor and keep the final missing-gate assertion derived from the exact expected set rather than a stale count. In both CI catalog-order matrix legs, after all relevant tables exist and immediately before the final `db-rls.sql`, run `tests/sql/interpretation-proposal-service-role-grants.sql`; then run the focused SQL and disposable verifier. This production-like grant/final-revoke gate belongs to the reversal delivery and is not a prerequisite of the earlier projection delivery.

- [ ] **Step 3: Run full disposable db-verify**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
```

Expected: every name in the runner's exact derived expected set reports `executed`, including all pre-existing gates and every new result/reversal/generic-lock gate listed by this task; no numeric count is used as the assertion authority.

- [ ] **Step 4: Commit**

```bash
git add db-verify.sql tests/sql/run-db-verify-disposable.sql   tests/sql/test-interpretation-proposal.sql .github/workflows/ci.yml
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

`compare_rerun` first validates that `reversed` is a complete recovery state. It uses the receipt's explicit manifest `claim_id` → SQL-authoritative key mapping. For an unchanged claim/key, it accepts a new proposal only when the immediately prior current row is the exact reversal-created `superseded` row, whose evidence names the expected original batch, reversal event, reversal authorization, state hash, and manifest; the new proposal must then be version `prior+1` and supersede that row. For a changed claim id/key, the key must be absent from the reversed projection and the new proposal must be version 1. Reject a changed claim id that reuses an old key, an unchanged claim id that changes key, unrelated superseded rows, wrong batch/event/authorization/evidence, a newer version, decision, promotion, foreign history, or use of a key not justified by the corrected receipt.

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
