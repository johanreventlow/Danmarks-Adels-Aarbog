# Interpretation Proposal Production Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide the only documented 4.4 production entry point, a fail-closed runbook, and a fresh production-derived restore rehearsal covering apply, reversal, recovery, and corrected re-run.

**Architecture:** One edition-neutral R CLI validates immutable files and expected identities before opening a connection, then reuses the generic reimport executor and the proposal-specific result/reversal RPCs without ever issuing authorization. It exposes explicit subcommands for dry-run, apply, proposal result, reversal preflight, reversal, and reversal result recovery; connection loss is resolved through a fully revalidated fresh connection, never automatic retry. The runbook binds an immutable pre-GO package, then a separate immutable post-GO execution envelope containing the externally issued authorization.

**Tech Stack:** R/DBI/RPostgres/jsonlite/digest/testthat, PostgreSQL 17, psql/pg_dump/pg_restore, Python projection comparator, POSIX file permissions.

**Spec:** `docs/superpowers/specs/2026-09-20-interpretation-proposal-prod-gate-design.md`

## Global Constraints

- This delivery makes 4.4 production-GO-ready; it neither gives GO nor runs proposal apply against production.
- The wrapper is edition-neutral and accepts only `interpretation_proposal` operations.
- Every mode requires the literal guard `DAA-4.4-INTERPRETATION-PROPOSAL-PROD-V1`.
- Manifest byte hash, recomputed content hash, preview byte hash, source, profile, database target, immutable pre-GO package, post-GO execution envelope, and pre-issued authorization are bound before writes.
- The wrapper never calls either authorization RPC.
- Dry-run and apply use the same externally issued authorization; dry-run rolls back its consumption.
- A client error at commit yields `commit_unknown` and invokes only the appropriate result RPC on a new connection.
- Every initial or recovery connection independently clears inherited libpq state, verifies target identity, establishes and verifies the expected editor actor, and only then calls an RPC.
- Output contains ids, hashes, counts, and statuses only; never source text, claim values, names, DSNs, or credentials.
- No raw `conditionMessage()`, DBI error, subprocess stderr, connection field, or filesystem path may cross the CLI boundary.
- The existing `apply_reimport.R` CLI contract remains unchanged.
- No production apply or production reversal is authorized by implementing this plan.

## Review Focus

- A manifest containing one non-proposal operation fails before connect, even when counts and hashes are otherwise valid.
- Inherited `PGHOSTADDR` or a target mismatch cannot redirect R to a different database after psql preflight.
- Missing production guard, changed file byte, changed content hash, stale authorization, or preexisting active proposal stops before write.
- A dropped connection after commit returns a verified result or `drift`; it never starts another batch or reversal.
- The fresh restore must be from the exact recorded dump SHA and must run migrations in the same order intended for production.

---

## File Structure

| File | Responsibility |
|---|---|
| `.claude/skills/daa-extract/scripts/interpretation_proposal_prod_helpers.R` | CLI validation, artifact/target checks, sanitized output, apply/reversal orchestration. |
| `.claude/skills/daa-extract/scripts/interpretation_proposal_prod.R` | Thin command entry point. |
| `.claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R` | Script-local testthat contract. |
| `tests/testthat/test-interpretation-proposal-prod.R` | Repository test runner coverage. |
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | Consume the projection delivery's external-authorization and transaction-entry hooks; add connection-discard, commit-unknown, and sanitizer hooks with backward-compatible defaults. |
| `tests/testthat/test-apply-reimport.R` | Generic executor regression tests. |
| `schema.sql` / `db-migrations.sql` / `db-rls.sql` / `db-verify.sql` | Proposal-result RPC used when apply commit outcome is unknown (implemented by the reversal plan prerequisite). |
| `docs/runbooks/interpretation-proposal-prod-apply.md` | Operator procedure, GO package, recovery matrix, prohibited actions. |
| `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-prod-gate-rehearsal.md` | Fresh-restore evidence receipt. |
| `docs/evidensbaseret-genimport/status.md` | Update only after every gate has evidence; otherwise leave 4.4 partial. |

### Task 1: Add safe commit-unknown resolution to the generic executor

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
- Modify: `tests/testthat/test-apply-reimport.R`

**Interfaces:**
- Consumes the projection delivery's already-tested `authorization_policy = c("auto_dry_run", "external")` and `transaction_entry = NULL`; do not redefine or defer either hook to this delivery.
- Extend `execute_reimport` with:
  - `result_after_commit = NULL`, invoked after every apply commit attempt, whether `dbCommit` returned normally or raised a connection error, but only after the original gateway connection has been discarded successfully.
- Add an idempotent gateway `disconnect` operation that performs no rollback. Refactor apply commit handling so the executor always calls `commit`, then `disconnect`, then—when supplied—the fresh resolver; a commit exception never enters the ordinary rollback handler.
- Structured commit-unknown condition fields: `code`, `authorization_id`, `batch_id`.
- Produces one closed `sanitize_reimport_error(condition) -> list(code,details)` mapper used by executor and production wrapper.
- Existing callers and `apply_reimport.R` behavior remain unchanged.

- [ ] **Step 1: Write failing executor tests**

Cover:
1. the prerequisite external policy still requires an authorization for both modes and never calls gateway `authorize`;
2. the prerequisite transaction-entry callback still runs exactly once after `begin` and before `advisory_lock`, `preflight`, `preflight_authorization`, or `begin_batch`;
3. a transaction-entry failure rolls back and no later gateway operation runs;
4. dry-run uses the supplied id, then rolls back;
5. neither a normal commit nor a commit error calls rollback or reapply after the commit attempt;
6. exact normal order is `commit -> disconnect -> resolver`;
7. exact connection-error order is attempted `commit -> disconnect -> resolver`, and the old connection is absent before the resolver opens its fresh one;
8. a disconnect error is sanitized, suppresses automatic resolver invocation, performs no rollback/reapply, and directs recovery to the explicit result command;
9. the supplied resolver is called exactly once after both normal and commit-error returns when discard succeeded and receives authorization id and batch id;
10. the executor never exposes its local `finalized` as production success before resolver verification;
11. resolver `committed` becomes `commit_verified`, while `not_started` and `drift` remain distinct closed results.

Inject a password, DSN, source value, private path, and arbitrary SQL/DBI message into separate failures. Assert none occurs in returned conditions, JSON, stdout, or stderr. Known allowlisted reimport codes may retain only closed ids/field/count/hash details; every unknown connect/DBI/subprocess/commit exception becomes `INTERPRETATION_PROD_INTERNAL_ERROR` with no original message.

Use a gateway with an ordered call log and make `commit` raise `synthetic connection lost`.

- [ ] **Step 2: Run and verify tests fail**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
```

Expected: failures for unknown arguments and commit behavior.

- [ ] **Step 3: Implement backward-compatible transaction and commit handling**

Preserve the projection delivery's authorization-policy and transaction-entry implementations byte-for-byte except where tests require a compatible call-signature extension.

Move `batch_id` outside the transaction closure while preserving the projection delivery's exact transaction-entry location immediately after `call("begin")` and before `advisory_lock`; do not move, duplicate, or retry that callback. Around only `call("commit")`, capture whether it returned or raised, and mark the transaction outcome unknown once the attempt begins. From that point, never call rollback. Invoke the idempotent `call("disconnect")` without rollback and require it to return before `result_after_commit(authorization$id,batch_id)` may run. Refactor the DBI gateway so `commit` no longer owns disconnect; every executor apply path performs the explicit disconnect, preserving existing successful-call cleanup while also covering a throwing `dbCommit`. If disconnect itself fails, drop the process-local connection reference, emit only `INTERPRETATION_PROD_INTERNAL_ERROR` with a closed `recovery_command='proposal-result'` detail, and do not start the resolver in that process; never include the DBI/disconnect message.

When discard succeeds, invoke `result_after_commit` exactly once after both normal and failed commit attempts. Production proposal apply requires the callback; existing callers retain `NULL` and their current verified-local behavior after disconnect. The callback opens a fresh validated connection and may ignore the process-local batch id because authorization id is the recovery key. Accept exactly its fully validated three-way state: map `committed` to `commit_verified`, preserve `not_started`, and preserve `drift`; never expose the executor's local `finalized` as production success, collapse states, or retry. The wrapper emits all three as closed results, with success exit only for `commit_verified`; tests cover normal commit, commit error, disconnect error, and explicit result paths for every state.

Replace every pass-through of `conditionMessage(error)` with the closed error mapper. It extracts only an anchored, allowlisted repository error code and separately validated UUID/hash/field/count details; it never copies arbitrary message tails. Unknown conditions map to the generic internal code. Preserve original conditions only inside tests, never in operator output.

- [ ] **Step 4: Run regression tests and commit**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
Rscript run-tests.R
git add .claude/skills/daa-extract/scripts/apply_reimport_helpers.R   tests/testthat/test-apply-reimport.R
git commit -m "feat: resolve reimport commit unknown safely"
```

Expected: focused PASS and full R suite `FAIL 0`.

### Task 2: Lock the production CLI and artifact gates

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_proposal_prod_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/interpretation_proposal_prod.R`
- Create: `.claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R`
- Create: `tests/testthat/test-interpretation-proposal-prod.R`

**Interfaces:**
- Subcommands:
  - `proposal-dry-run`
  - `proposal-apply`
  - `proposal-result`
  - `reversal-preflight`
  - `proposal-reverse-dry-run`
  - `proposal-reverse-apply`
  - `reversal-result`
- All require `--production-guard DAA-4.4-INTERPRETATION-PROPOSAL-PROD-V1`, `--expected-target-sha256 HASH`, and `--expected-actor-id UUID`.
- Proposal dry-run/apply modes additionally require manifest path, manifest byte hash, manifest content hash, preview path/hash, expected source/profile/profile hash, authorization id, pre-GO package path/hash, execution-envelope path/hash, deployment-receipt path/hash, and expected deployment-contract hash.
- `proposal-result` requires authorization id plus the same pre-GO package, execution-envelope, deployment-receipt paths/hashes, and expected deployment-contract hash; it deliberately does not require a process-local batch id.
- Reversal apply/result modes require batch and authorization ids plus their separate approval-envelope path/hash and the same deployment receipt/contract; reversal preflight requires batch id and the deployment receipt/contract.

- [ ] **Step 1: Write table-driven red CLI tests**

For each subcommand, test missing, duplicated, unknown, positional, malformed UUID/hash/integer, and wrong guard arguments. Test proposal manifests with mixed dependencies, extra keys, wrong counts, wrong source/profile, mismatched byte hash, mismatched recomputed content hash, and preview byte drift. Mutate every deployment-receipt/pre-GO/envelope key, every SQL or input file byte hash, the embedded receipt/pre-GO hash, deployment-contract hash, GO receipt, immutable authorization binding, issued-state receipt, actor, target, expiry value, and outer envelope hash. Assert the fake gateway call log remains empty. Separately prove an expired or consumed live authorization is rejected for write modes but still reaches the result RPC for recovery.

The valid proposal contract is:

```text
interpretation_proposal_prod.R proposal-apply
  --manifest PATH
  --manifest-byte-sha256 HASH
  --manifest-content-sha256 HASH
  --preview PATH
  --preview-sha256 HASH
  --expected-source-id INTEGER
  --expected-profile-id TEXT
  --expected-profile-sha256 HASH
  --expected-target-sha256 HASH
  --authorization-id UUID
  --expected-actor-id UUID
  --pre-go-package PATH
  --pre-go-package-sha256 HASH
  --execution-envelope PATH
  --execution-envelope-sha256 HASH
  --deployment-receipt PATH
  --deployment-receipt-sha256 HASH
  --expected-deployment-contract-sha256 HASH
  --production-guard DAA-4.4-INTERPRETATION-PROPOSAL-PROD-V1
```

- [ ] **Step 2: Run and verify missing helpers fail**

```bash
Rscript .claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R
Rscript -e 'testthat::test_file("tests/testthat/test-interpretation-proposal-prod.R")'
```

Expected: source/file-not-found failures.

- [ ] **Step 3: Implement pure parsing and artifact validation**

Implement `parse_interpretation_proposal_prod_cli(args)` and `validate_interpretation_proposal_prod_artifacts(cli)` without DB access. Read files as raw bytes, compare `digest::digest(raw, "sha256", serialize=FALSE)`, parse JSON without simplification, call `validate_reimport_manifest`, and require every dependency class to equal `interpretation_proposal`. Recompute the content hash by invoking the repository-relative `compare_interpretation_proposal_projection.py --print-manifest-sha256 <manifest>` with `/usr/bin/python3`; capture stdout and stderr separately, require exit 0 and exactly one lowercase 64-character stdout line, discard raw stderr, and map all other outcomes to the closed internal error code.

Validate the deployment receipt as a closed JSON object containing exactly schema version, reviewed commit, database target hash, the exact byte hashes of `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, and `tests/sql/test-interpretation-proposal.sql`, narrative contract version, deployment contract SHA-256, deployment timestamp, and its own content hash. Validate the pre-GO package as a closed JSON object containing exactly schema version, commit, script/profile/manifest/preview/SQL byte-hash map, deployment-receipt byte/content hashes, deployment-contract hash, target, source/profile binding, manifest/preview hashes, backup/freeze/counts/rehearsal receipts, and before-projection hash.

Validate the execution envelope as a closed JSON object containing exactly schema version, `pre_go_package_sha256`, deployment-receipt hash, deployment-contract hash, GO receipt id/hash, authorization id, immutable authorization-binding hash, authorization issue-receipt hash, authorization expiry value, expected actor id, target hash, and `execution_envelope_sha256`. The immutable binding contains authorization id, operation, actor, source/profile/profile SHA, manifest/preview/target, counts, authorized elements, nonce, issued timestamp, and expiry timestamp; it excludes mutable `status` and `consumed_at`. The DB-produced issue receipt additionally proves that envelope creation observed `status='issued'` and `consumed_at IS NULL`, but result modes retain its hash-bound value as history and do not require the live row still to have that state. Recompute all file/content hashes excluding their self-hash fields. Require every duplicated artifact/catalog/target/actor/authorization-binding field to equal the CLI and pre-GO values before connect.

Expiry and mutable-state checks are mode-specific: proposal/reversal dry-run or apply requires live `issued`, null `consumed_at`, and expiry in the future; `proposal-result` and `reversal-result` accept the same immutable binding after `issued→consumed` and after wall-clock expiry, and delegate state classification to the locked result RPC. Reversal uses an analogous closed approval envelope bound to its approved reversal-state hash/counts, immutable reversal-authorization binding/issue receipt, deployment contract, and original execution-envelope hash.

Return a closed list containing parsed manifest, hashes, expected source/profile/target/actor, authorization id, validated pre-GO/envelope hashes and fields, subcommand, and file paths. Do not include manifest operations in printed output.

- [ ] **Step 4: Implement the thin entry point**

The entry point defines a tiny constant-code bootstrap error emitter before sourcing any helper, then wraps **all** setup, sourcing, parsing, subprocess validation, connection creation, execution, and serialization in one top-level `tryCatch`. Source/bootstrap failures use only the constant fallback; after helpers load, the handler calls only `sanitize_reimport_error`. Both paths write one closed JSON object to stdout, write nothing to stderr, exit non-zero, and never call `conditionMessage` for display. Add black-box `Rscript` tests that inject secret-bearing source, parse, missing-file, Python stderr, connect, query, and commit failures and assert the actual process stdout/stderr contains none of the injected bytes.

- [ ] **Step 5: Run tests and commit**

```bash
Rscript .claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R
Rscript -e 'testthat::test_file("tests/testthat/test-interpretation-proposal-prod.R")'
git diff --check
git add .claude/skills/daa-extract/scripts/interpretation_proposal_prod_helpers.R   .claude/skills/daa-extract/scripts/interpretation_proposal_prod.R   .claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R   tests/testthat/test-interpretation-proposal-prod.R
git commit -m "feat: validate proposal production artifacts"
```

### Task 3: Bind the wrapper to its own connection and result RPCs

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/interpretation_proposal_prod_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R`
- Modify: `tests/testthat/test-interpretation-proposal-prod.R`

**Interfaces:**
- Produces `new_interpretation_proposal_prod_gateway(connection_factory)` and `execute_interpretation_proposal_prod(cli,gateway)`.
- Produces a production decorator over the generic gateway. Its generic `call` surface remains `connect`, `begin`, `advisory_lock`, `preflight`, `preflight_authorization`, `begin_batch`, operation writers, `batch_result`, `finalize`, `commit`, `rollback`, and `disconnect`; the decorator adds `target_identity`, `role_capability`, `deployment_receipt`, `proposal_contract_lock`, `authorization_binding`, `proposal_result`, `reversal_preflight`, `reverse`, and `reversal_result` without inventing a second transaction owner.

- [ ] **Step 1: Write red target and no-self-authorization tests**

Use a fake gateway to prove:
- target identity is checked before proposal preflight;
- the session login's role-switch capability is checked before `BEGIN`, and a superuser or login without explicit `authenticated` membership is rejected;
- target mismatch stops;
- the one exact apply call sequence is `connect(target, capability) → begin(DBI::dbBegin, SET LOCAL ROLE, transaction-local claims, actor verification) → transaction_entry(exclusive contract lock plus live deployment receipt) → advisory_lock → preflight → preflight_authorization → begin_batch`; no outer or second `BEGIN` exists;
- actor is established inside the decorated generic `begin` only after the target matches and is verified before transaction-entry or any result/preflight/apply RPC;
- missing/wrong actor and wrong role stop before the operation RPC;
- preflight returns exact source/profile/auth/manifest/preview binding;
- immutable authorization binding exactly matches the validated execution envelope inside the operation transaction: after exclusive entry lock and before apply writes, or inside the result RPC's own shared/domain locks; write modes additionally require live issued/unconsumed/unexpired state, while result modes explicitly accept consumed and expired rows and classify them;
- active preexisting proposal stops dry-run and apply;
- no SQL string contains `red_authorize_reimport` or `red_authorize_interpretation_proposal_reversal`;
- proposal modes pass `authorization_policy="external"`;
- proposal dry-run/apply pass a transaction-entry callback that calls `red_lock_interpretation_proposal_contract(expected_deployment_contract_sha256)` before the generic executor's first shared-locking RPC, and a wrong returned contract hash stops before generic preflight;
- before apply/dry-run `BEGIN`, only local artifact checks plus direct target/capability SQL may run; the transaction-entry contract-lock RPC returns and validates the authoritative live deployment receipt under exclusive lock;
- result RPCs receive expected deployment-contract and immutable authorization-binding hashes and recompute both server-side under their shared/domain locks; the public deployment-receipt/binding RPCs are for envelope construction and standalone read-only inspection, not pre-lock calls on the operation transaction;
- reversal modes call only preflight/apply/result RPCs;
- commit loss calls result on a fresh connection and never repeats apply/reverse;
- proposal and reversal result recovery after both a successful `issued→consumed` commit and wall-clock expiry still reaches the result RPC; a changed immutable binding stops;
- fresh proposal-result and reversal-result connections repeat environment clearing, direct connection, target recomputation/comparison, actor setup/verification, and only then the lock-taking result RPC;
- wrong target, missing actor, wrong actor, or RPC-before-revalidation on a resolver connection fails closed.

- [ ] **Step 2: Run and verify orchestration tests fail**

Run the two test commands from Task 2. Expected: failures for missing gateway operations.

- [ ] **Step 3: Implement connection hygiene and target binding**

Read the trusted connection fields from `SUPABASE_HOST`, `SUPABASE_PORT`, `SUPABASE_DB`, `SUPABASE_USER`, and `SUPABASE_PASSWORD`, which R loads from the operator's private `~/.Renviron`. Require all five to be non-empty. Then clear these inherited libpq variables before connecting:

```r
c("PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
  "PGPASSWORD", "PGSSLMODE", "PGOPTIONS", "PGSERVICE",
  "PGSERVICEFILE", "PGPASSFILE", "PGCONNECT_TIMEOUT")
```

The default connection factory passes the captured `SUPABASE_*` values directly as DBI arguments and never reconstructs connection settings from `PG*`. On every initial and resolver R connection, query database name and `pg_control_system().system_identifier`, compute the target formula, and compare with `--expected-target-sha256` before any RPC. Before `BEGIN`, require `session_user` to be a non-superuser LOGIN role, `pg_has_role(session_user,'authenticated','MEMBER')`, and `has_function_privilege(session_user,'pg_control_system()','EXECUTE')`; otherwise stop with a closed capability code. The production credential contract is explicit: `SUPABASE_USER` names a dedicated `NOINHERIT LOGIN` role granted membership in `authenticated` and the minimum target-identity capability, never `postgres` or another superuser.

The production decorator's implementation of the generic `call("begin")` is the sole transaction owner. On the already validated connection it performs, in order, exactly one `DBI::dbBegin`, the literal `SET LOCAL ROLE authenticated`, transaction-local `request.jwt.claim.sub=--expected-actor-id` and `request.jwt.claim.role=authenticated`, then verifies `session_user` is the already checked operator login, `current_user='authenticated'`, `auth.uid()` equals that UUID, and `public.current_rolle()='redaktion'`. It returns only after all checks pass. The decorated `call("preflight")` must not repeat or mutate role/claims; it delegates only to the generic data/authorization preflight. Existing non-production gateways retain their current preflight behavior.

`execute_reimport` then immediately invokes its `transaction_entry`: the wrapper calls `red_lock_interpretation_proposal_contract(expected_deployment_contract_sha256)`. The RPC authenticates the already established actor without taking a narrative shared lock, then takes the exclusive contract lock before any shared/row lock or contract-state read; its closed return is the authoritative in-transaction live deployment receipt. Only after that callback succeeds may the existing generic `advisory_lock`, `preflight`, authorization preflight, or `begin_batch` RPC run. There is no outer transaction and no second `BEGIN`. Ordinary standalone preflight may use a separate `READ ONLY` transaction. Result RPCs are semantically read-only but intentionally use one normal transaction because their race-safe contract takes advisory locks and `FOR UPDATE`; they use the same begin/role/claim lifecycle but no generic executor. Disconnect and discard the connection on any pre-commit failure after rollback. Once an apply commit has been attempted, never rollback: invoke the Task 1 no-rollback `disconnect` and require it to finish before opening the result connection. A discard failure is sanitized and suppresses the automatic resolver so the possibly live connection cannot self-block a fresh resolver.

Unit and spawned-process tests record every gateway/SQL action and require the complete order above, including actor verification before `proposal_contract_lock`. A real non-superuser PostgreSQL integration test asserts the exclusive advisory lock is held before `red_preflight_reimport_authorization` is invoked. For both success and injected failure, test `BEGIN; SET LOCAL ROLE authenticated; ...; COMMIT/ROLLBACK;` and then assert outside the transaction that `current_user=session_user` and transaction-local JWT claims are absent. Reject any session-scoped `SET ROLE authenticated` spelling in source/black-box SQL capture.

Do not print connection fields.

- [ ] **Step 4: Implement proposal and reversal orchestration**

Before proposal dry-run/apply `BEGIN`, perform only local file/envelope validation and direct target/capability SQL. Then call `execute_reimport` with external authorization. Its transaction-entry invokes `red_lock_interpretation_proposal_contract(expected_deployment_contract_sha256)` as the first operation RPC and validates the returned live receipt. Only afterward may the decorated generic preflight inspect proposal existence/source/profile; that inspection performs no DML, `FOR UPDATE`, or additional advisory lock and is never authorization authority. Its `preflight_authorization` first calls the proposal-aware issued-only generic preflight, which follows provisional authorization discovery → writer lock → sorted anchor locks → locked authorization recheck; only while that row lock is held may it call the non-locking closed authorization-binding RPC and compare the expected immutable hash, principal, source/profile/manifest/preview/target, live `issued`, null `consumed_at`, and future expiry. Reversing those two calls is a test failure. No deployment-receipt, binding, or proposal-existence RPC precedes transaction-entry.

The commit resolver opens a new connection, repeats only capability/target/actor setup, and directly invokes `red_reimport_interpretation_proposal_result(authorization_id, expected_authorization_binding_sha256, expected_deployment_contract_sha256)`. That result RPC validates both hashes server-side under its shared and domain-row locks; the client does not attempt the issued-only preflight first.

`proposal-result` performs the same fresh-connection target/actor sequence and invokes only that proposal-specific result RPC with both expected hashes. It does not require live `issued` status or future expiry. It maps `committed` after a lost connection to CLI status `commit_verified`; it reports `not_started` or `drift` verbatim and never retries apply. Reversal-result supplies the analogous expected hashes and follows the same rule after consumed status or expiry.

Reversal preflight calls `red_preflight_interpretation_proposal_reversal`. Reverse dry-run/apply first validates the reversal approval envelope against that state and then calls `red_reverse_reimport_interpretation_proposal(batch_id, authorization_id, expected_authorization_binding_sha256, expected_deployment_contract_sha256)` in one transaction, rolling back or committing. After every apply commit attempt—normal return or connection error—open one new validated connection and call `red_reimport_interpretation_proposal_reversal_result` exactly once with the same expected hashes; never expose the local reverse return as verified success. Preserve `reversed`, `not_started`, and `drift` as three distinct outcomes through the automatic resolver and explicit command; never map `not_started` to drift. Both result subcommands perform no data writes, although their transactions permit row/advisory locks.

- [ ] **Step 5: Sanitize every result**

Validate each internal RPC result against its own exact DB schema before transformation; never apply the external CLI allowlist directly to a DB row. In particular:

- proposal-result accepts exactly `schema_version`, `authorization_id`, `batch_id`, `status`, `source_id`, `profile_id`, `manifest_sha256`, `preview_sha256`, and `counts`;
- reversal-preflight accepts exactly the reversal plan's `schema_version`, `batch_id`, `manifest_sha256`, `source_id`, `profile_id`, `profile_sha256`, `database_identity`, `counts`, `upstream_binding_sha256`, and `proposal_state_sha256`;
- reversal-result accepts exactly `schema_version`, `batch_id`, `authorization_id`, `status`, `proposal_state_sha256`, `reversal_event_id`, and `counts`.

Reject any extra/missing internal key. Validate the exact schema-version constant, status-specific nullability, and nested counts keys from the reversal plan. Then perform one named, tested transformation: validate `database_identity` against the expected target and emit only its target SHA; rename internal `manifest_sha256` to external `manifest_content_sha256`; omit the validated internal `schema_version`; preserve `profile_sha256` and `upstream_binding_sha256` only where present; enrich only with already validated envelope fields such as operation and deployment hash. Shared fixtures produced from the SQL test feed the R validator so either side changing alone turns tests red.

Pin the proposal-result matrix in the R validator as well: `not_started` has null batch but non-null source/profile/manifest/preview binding; `committed` has a UUID batch and the same non-null binding; `drift` has null batch, source, profile, manifest, preview, and counts. Pin reversal `reversal_event_id` as null for `not_started|drift` and as a canonical positive decimal string within signed-bigint range for `reversed`; reject UUIDs, JSON numbers, leading zeroes, signs, exponent notation, and out-of-range values.

The union of permitted external keys is:

```r
c("operation", "status", "source_id", "profile_id",
  "profile_sha256", "upstream_binding_sha256",
  "database_target_sha256", "deployment_contract_sha256",
  "manifest_content_sha256",
  "preview_sha256", "authorization_id", "batch_id",
  "proposal_state_sha256", "reversal_event_id", "counts",
  "committed")
```

Pin an exact external subset per subcommand: proposal-result/apply may emit proposal binding fields but never reversal-state fields; proposal/reversal dry-run emits its applicable binding fields with exactly `status='dry_run_validated'` and `committed=false`; reversal-preflight emits `operation`, `status='ready'`, batch/source/profile/profile SHA/target/deployment/manifest/counts/upstream/state; reversal-result/apply emits operation/status/authorization/batch/target/deployment/state/event/counts. Reject an external object with any other or missing key instead of filtering it silently. Proposal apply/result status is exactly `commit_verified|not_started|drift`; reversal apply/result status is exactly `reversed|not_started|drift`. Catch all top-level conditions through the Task 1 mapper; unit tests and spawned-process tests capture stdout and stderr and require that injected DSNs, passwords, manifest values, subprocess output, and paths are absent.

- [ ] **Step 6: Run tests and commit**

```bash
Rscript .claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R
Rscript -e 'testthat::test_file("tests/testthat/test-interpretation-proposal-prod.R")'
Rscript run-tests.R
git add .claude/skills/daa-extract/scripts/interpretation_proposal_prod_helpers.R   .claude/skills/daa-extract/scripts/test_interpretation_proposal_prod.R   tests/testthat/test-interpretation-proposal-prod.R
git commit -m "feat: execute guarded proposal production workflow"
```

### Task 4: Write the fail-closed production runbook

**Files:**
- Create: `docs/runbooks/interpretation-proposal-prod-apply.md`

**Interfaces:**
- Consumes: the tracked wrapper, projection, comparator, manifest, preview, backup receipt, immutable pre-GO package, and post-GO execution envelope.
- Produces: an operator sequence with explicit STOP/GO boundaries; it does not contain credentials.

- [ ] **Step 1: Write the roadmap and authority boundary**

Open with the six roadmap access requirements. State that issue #196, reversal, wrapper, and fresh restore make the operation GO-ready only. State in a boxed stop rule:

```text
Denne runbook giver ikke produktions-GO.
Kun en ny, eksplicit GO-kvittering mod den fulde §4-pakke
må autorisere proposal-apply i produktion.
```

- [ ] **Step 2: Specify the exact preflight and freeze order**

The runbook requires:
1. resolve the 4.1c restore window;
2. begin an enforced editorial writer freeze;
3. record non-own active sessions;
4. run read-only schema/ACL/profile/absence preflight;
5. take before projection;
6. take a fresh `pg_dump -Fc --no-owner` without `--no-privileges`;
7. hash dump and record start time before the command;
8. restore that exact SHA to a new disposable database;
9. run the full rehearsal before any GO package exists.

List `PGHOSTADDR` among variables that must be cleared. Require per-command `PGOPTIONS='-c default_transaction_read_only=on'` for read-only psql calls outside the projection transaction.

- [ ] **Step 3: Specify the immutable pre-GO package and post-GO execution envelope**

The immutable pre-GO package binds:
- clean commit and exact byte SHA-256 set for wrapper, helpers, profile, four projection files, comparator, manifest, preview, `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`, and `tests/sql/test-interpretation-proposal.sql`;
- an immutable deployment receipt whose reviewed commit and SQL hashes equal that set, whose target equals the expected database, and whose catalog contract SHA is freshly reproduced by `red_interpretation_proposal_deployment_receipt()` after the reviewed migration/ACL order;
- database name plus target SHA;
- source/profile/profile hash;
- manifest byte and content hashes;
- preview byte hash;
- backup path/start/size/SHA;
- freeze start/responsible/session count;
- exact operation/claim/link/disposition counts;
- fresh-restore report SHA;
- before projection SHA.

It contains no authorization because authorization is issued only after an explicit human GO against that exact package hash. Any changed pre-GO value invalidates GO.

After GO, a separate immutable execution envelope binds the pre-GO package SHA-256, deployment-receipt hash, deployment-contract hash, GO receipt id/hash, apply authorization id, immutable authorization-binding hash, DB-produced issued-state receipt, expiry value, expected actor id, and its own envelope SHA-256. The immutable hash excludes `status`/`consumed_at`; the issued-state receipt proves they were `issued`/NULL when the envelope was made. The pre-GO package is never edited or replaced. Any file, live catalog, target, or immutable authorization mismatch invalidates every mode. A non-issued/consumed or expired authorization invalidates only dry-run/apply and requires a new explicit decision; it must not block result recovery. The wrapper never performs authorization. It requires all three files and their expected byte hashes on dry-run, apply, proposal-result, and corresponding reversal commands. Apply compares live deployment/binding after its exclusive entry lock; result RPCs compare the expected hashes under their own locks and classify mutable authorization state.

- [ ] **Step 4: Specify apply, commit-unknown, and reversal matrices**

Apply sequence is dry-run with external auth, assert no durable delta, apply once, then always resolve on a fresh connection with the same target/actor/auth envelope. The same locked result call runs after normal commit return and after client error; only `commit_verified` continues to after-projection and comparator `match`, `not_started` requires a new human decision, and `drift` is STOP.

Reversal sequence is fresh preflight, separate human approval of state hash/counts, separate service-role authorization, reverse once, then result on a fresh connection after every commit attempt, after-reversal projection, recovery comparator `match`. Never automatically retry. Never reverse after human decisions or promotion.

- [ ] **Step 5: Specify prohibited actions and report schema**

Explicitly prohibit production schema migration, self-authorization, manual deletes/updates, receipt editing, `--allow-empty`, automatic reapply, and full restore while the append-only reversal is valid. Define sanitized report keys and permissions `0600`/directory `0700`.

- [ ] **Step 6: Review against the spec and commit**

```bash
rg -n "GO|STOP|commit_unknown|reversal|PGHOSTADDR|allow-empty|0600|0700"   docs/runbooks/interpretation-proposal-prod-apply.md
git diff --check
git add docs/runbooks/interpretation-proposal-prod-apply.md
git commit -m "docs: add proposal production runbook"
```

### Task 5: Run the fresh production-derived restore rehearsal

**Files:**
- Create: `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-prod-gate-rehearsal.md`
- Modify: `docs/evidensbaseret-genimport/status.md` only if every gate below is evidenced.

**Interfaces:**
- Consumes: one fresh production-derived dump taken after the 4.1c window is resolved.
- Produces: a sanitized, hash-bound rehearsal receipt; no production proposal write.

- [ ] **Step 1: Create an isolated private rehearsal directory**

Use `mktemp -d` under a private parent, set directory mode `0700` and files `0600`. Record dump SHA and target identity. Restore to a newly created local database; apply no data fixes.

- [ ] **Step 2: Verify catalog order and baseline**

Run `schema.sql → db-rls.sql → db-migrations.sql` and the alternate migration ordering on separate disposable databases. On the production-derived restore, apply only the reviewed migrations needed for the feature, then `db-rls.sql` and `db-verify.sql`. From each final catalog, call `red_interpretation_proposal_deployment_receipt()` as the non-superuser integration login, require identical deployment-contract hashes for both disposable orderings, and create the production-derived deployment receipt from the reviewed file hashes plus the live target/catalog result. Re-read it on a fresh connection and require exact equality before building the pre-GO package. Record exact commands and sanitized outputs. Any unexpected restore, migration, ACL, receipt, or catalog-hash difference is BLOCKED.

- [ ] **Step 3: Execute the full required dataflow**

Create a dedicated non-superuser `NOINHERIT LOGIN` integration role, grant it membership in `authenticated` and the minimum target-identity capability, connect the R integration as that role, and assert `pg_has_role` plus the literal role switch before running the workflow. The owner/superuser connection may bootstrap and load SQL only; it may not execute wrapper tests. On the fresh restore, with new short-lived authorizations, execute exactly:

```text
before projection
→ proposal-dry-run, no durable rows
→ proposal-apply
→ apply projection = match
→ reversal-preflight
→ proposal-reverse-apply
→ reversal-result = reversed
→ recovery projection = match
→ corrected proposal-apply
→ rerun projection = match
```

Prove unchanged deterministic keys advance version and changed claims get new keys. Preserve all output artifacts and their SHA-256 values.

- [ ] **Step 4: Run full repository verification**

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
Rscript run-tests.R
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
Rscript tests/integration/test-reimport-interpretation-proposal.R
git diff --check
```

Also run the wrapper's script-local tests. Record PASS counts and exact known warnings; a missing runner or dependency is BLOCKED, not PASS.

- [ ] **Step 5: Write the evidence receipt**

Record:
- commit and clean-tree proof;
- dump path alias, start, size, SHA, and restore database target SHA;
- manifest/preview/profile/script hashes;
- authorization and batch ids;
- exact element/claim/link/disposition/version counts;
- apply, recovery, and corrected re-run comparator receipts;
- all commands and exit results;
- explicit statement that no production proposal apply/reversal occurred.

End with:

```text
4.4 prod-gate rehearsal: PASS/PARTIAL/BLOCKED
Issue #196 implementation gate: PASS/PARTIAL/BLOCKED
Produktions-GO: IKKE GIVET
Produktionsmutation: INGEN
```

- [ ] **Step 6: Update status only on complete evidence and commit**

If any gate is missing, leave `status.md` unchanged and mark the report partial/blocked. If all gates pass, update only 4.4's factual line to say the technical gate is ready and production GO remains outstanding.

```bash
git add docs/evidensbaseret-genimport/proposal-ingest-147-4-4-prod-gate-rehearsal.md
git add docs/evidensbaseret-genimport/status.md
git commit -m "docs: record proposal prod gate rehearsal"
```

Omit the `status.md` `git add` when it was correctly left unchanged.
