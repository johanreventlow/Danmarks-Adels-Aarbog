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
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | External-authorization and commit-unknown hooks with backward-compatible defaults. |
| `tests/testthat/test-apply-reimport.R` | Generic executor regression tests. |
| `schema.sql` / `db-migrations.sql` / `db-rls.sql` / `db-verify.sql` | Proposal-result RPC used when apply commit outcome is unknown (implemented by the reversal plan prerequisite). |
| `docs/runbooks/interpretation-proposal-prod-apply.md` | Operator procedure, GO package, recovery matrix, prohibited actions. |
| `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-prod-gate-rehearsal.md` | Fresh-restore evidence receipt. |
| `docs/evidensbaseret-genimport/status.md` | Update only after every gate has evidence; otherwise leave 4.4 partial. |

### Task 1: Make external authorization and commit-unknown explicit in the generic executor

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
- Modify: `tests/testthat/test-apply-reimport.R`

**Interfaces:**
- Extend `execute_reimport` with:
  - `authorization_policy = c("auto_dry_run", "external")`, default `auto_dry_run`;
  - `result_after_commit_error = NULL`.
- Structured commit-unknown condition fields: `code`, `authorization_id`, `batch_id`.
- Produces one closed `sanitize_reimport_error(condition) -> list(code,details)` mapper used by executor and production wrapper.
- Existing callers and `apply_reimport.R` behavior remain unchanged.

- [ ] **Step 1: Write failing executor tests**

Cover:
1. `external` requires an authorization for dry-run and apply;
2. `external` never calls gateway `authorize`;
3. dry-run uses the supplied id, then rolls back;
4. a commit error after finalize does not call rollback or reapply;
5. the supplied resolver receives authorization id and batch id;
6. resolver `committed` becomes `commit_verified`;
7. resolver mismatch becomes `REIMPORT_COMMIT_UNKNOWN_DRIFT`.

Inject a password, DSN, source value, private path, and arbitrary SQL/DBI message into separate failures. Assert none occurs in returned conditions, JSON, stdout, or stderr. Known allowlisted reimport codes may retain only closed ids/field/count/hash details; every unknown connect/DBI/subprocess/commit exception becomes `INTERPRETATION_PROD_INTERNAL_ERROR` with no original message.

Use a gateway with an ordered call log and make `commit` raise `synthetic connection lost`.

- [ ] **Step 2: Run and verify tests fail**

```bash
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
```

Expected: failures for unknown arguments and commit behavior.

- [ ] **Step 3: Implement backward-compatible policy selection**

Resolve authorization as:

```r
authorization_policy <- match.arg(authorization_policy)
if (identical(authorization_policy, "external")) {
  validate_reimport_authorization(authorization)
  resolved_authorization <- authorization
} else {
  if (identical(mode, "apply")) validate_reimport_authorization(authorization)
  resolved_authorization <- call(
    "authorize", manifest, preview_sha256, mode, authorization)
}
```

Move `batch_id` outside the transaction closure. Around only `call("commit")`, catch connection errors, do not call rollback, and call `result_after_commit_error(authorization$id,batch_id)` once. The callback may ignore the process-local batch id and resolve by authorization id. Accept only the proposal-result RPC's fully validated `committed` state; `not_started` or `drift` becomes the drift code with ids only.

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
- Proposal dry-run/apply modes additionally require manifest path, manifest byte hash, manifest content hash, preview path/hash, expected source/profile/profile hash, authorization id, pre-GO package path/hash, and execution-envelope path/hash.
- `proposal-result` requires authorization id plus the same pre-GO package and execution-envelope paths/hashes; it deliberately does not require a process-local batch id.
- Reversal apply/result modes require batch and authorization ids plus their separate approval-envelope path/hash; reversal preflight needs batch id only.

- [ ] **Step 1: Write table-driven red CLI tests**

For each subcommand, test missing, duplicated, unknown, positional, malformed UUID/hash/integer, and wrong guard arguments. Test proposal manifests with mixed dependencies, extra keys, wrong counts, wrong source/profile, mismatched byte hash, mismatched recomputed content hash, and preview byte drift. Mutate every pre-GO/envelope key, either file byte hash, the embedded pre-GO hash, GO receipt, authorization readback, actor, target, expiry, and outer envelope hash. Assert the fake gateway call log remains empty.

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

Validate the pre-GO package as a closed JSON object containing exactly schema version, commit, script/profile/manifest/preview byte-hash map, target, source/profile binding, manifest/preview hashes, backup/freeze/counts/rehearsal receipts, and before-projection hash. Validate the execution envelope as a closed JSON object containing exactly schema version, `pre_go_package_sha256`, GO receipt id/hash, authorization id/expiry/readback hash, expected actor id, target hash, and `execution_envelope_sha256`. Recompute both content hashes excluding their self-hash fields. Require every duplicated artifact/target/actor/authorization field to equal the CLI and pre-GO values before connect; expiry must still be in the future. Reversal uses an analogous closed approval envelope bound to its approved reversal-state hash/counts and original execution-envelope hash.

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
- Gateway calls: `connect`, `target_identity`, `establish_actor`, `proposal_preflight`, `execute_proposal`, `proposal_result`, `reversal_preflight`, `reverse`, `reversal_result`, `disconnect`.

- [ ] **Step 1: Write red target and no-self-authorization tests**

Use a fake gateway to prove:
- target identity is checked before proposal preflight;
- target mismatch stops;
- actor is established only after the target matches and is verified before any result/preflight/apply RPC;
- missing/wrong actor and wrong role stop before the operation RPC;
- preflight returns exact source/profile/auth/manifest/preview binding;
- authorization readback exactly matches the validated execution envelope before any apply/result RPC;
- active preexisting proposal stops dry-run and apply;
- no SQL string contains `red_authorize_reimport` or `red_authorize_interpretation_proposal_reversal`;
- proposal modes pass `authorization_policy="external"`;
- reversal modes call only preflight/apply/result RPCs;
- commit loss calls result on a fresh connection and never repeats apply/reverse;
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

The default connection factory passes the captured `SUPABASE_*` values directly as DBI arguments and never reconstructs connection settings from `PG*`. On every initial and resolver R connection, query database name and `pg_control_system().system_identifier`, compute the target formula, and compare with `--expected-target-sha256` before any RPC.

After target match, begin a transaction, execute `SET LOCAL ROLE authenticated`, and set transaction-local `request.jwt.claim.sub` to `--expected-actor-id` and `request.jwt.claim.role` to `authenticated`. Verify `current_user='authenticated'`, `auth.uid()` equals that UUID, and `public.current_rolle()='redaktion'`; then and only then invoke the RPC. Ordinary preflight may use `READ ONLY`. Result RPCs are semantically read-only but intentionally use a normal transaction because their race-safe contract takes advisory locks and `FOR UPDATE`; assert they execute no DML. Apply/reverse transaction setup performs the same role/claim checks before write calls. Disconnect and discard the connection on any failure.

Do not print connection fields.

- [ ] **Step 4: Implement proposal and reversal orchestration**

Proposal preflight reads authorization binding and current proposal existence without mutation, requires its principal id to equal `--expected-actor-id`, validates source/profile/manifest/preview/target, computes the closed authorization-readback hash, and requires it to equal the execution envelope. Dry-run/apply call `execute_reimport` with external authorization and a resolver that opens a new connection and invokes `red_reimport_interpretation_proposal_result(authorization_id)`.

`proposal-result` performs the same fresh-connection target/actor sequence and invokes only that proposal-specific result RPC. It maps `committed` after a lost connection to CLI status `commit_verified`; it reports `not_started` or `drift` verbatim and never retries apply.

Reversal preflight calls `red_preflight_interpretation_proposal_reversal`. Reverse dry-run/apply first validates the reversal approval envelope against that state and then wraps `red_reverse_reimport_interpretation_proposal` in a transaction, rolling back or committing. If commit raises, open a new connection, repeat target/actor/envelope validation, and call `red_reimport_interpretation_proposal_reversal_result` exactly once. Both result subcommands perform no data writes, although their transactions permit row/advisory locks.

- [ ] **Step 5: Sanitize every result**

Allow only these output keys:

```r
c("operation", "status", "source_id", "profile_id",
  "database_target_sha256", "manifest_content_sha256",
  "preview_sha256", "authorization_id", "batch_id",
  "proposal_state_sha256", "reversal_event_id", "counts",
  "committed")
```

Reject a gateway result with any other key instead of filtering it silently. Catch all top-level conditions through the Task 1 mapper; unit tests and spawned-process tests capture stdout and stderr and require that injected DSNs, passwords, manifest values, subprocess output, and paths are absent.

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
- clean commit and exact byte SHA-256 set for wrapper, helpers, profile, four projection files, comparator, manifest, and preview;
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

After GO, a separate immutable execution envelope binds the pre-GO package SHA-256, GO receipt id/hash, apply authorization id and expiry, authorization readback hash (actor/source/profile/manifest/preview/target/counts/authorized-elements/status), expected actor id, and its own envelope SHA-256. The pre-GO package is never edited or replaced. Any mismatch or expiry invalidates the execution envelope and requires a new explicit decision; the wrapper never performs authorization. The wrapper requires both files and both expected byte hashes on dry-run, apply, and proposal-result and compares live authorization readback to the envelope before any operation RPC.

- [ ] **Step 4: Specify apply, commit-unknown, and reversal matrices**

Apply sequence is dry-run with external auth, assert no durable delta, apply once, after projection, comparator `match`. On client error, run `proposal-result` with the same target/actor/auth envelope; `commit_verified` continues to projection, `not_started` requires a new human decision, and `drift` is STOP.

Reversal sequence is fresh preflight, separate human approval of state hash/counts, separate service-role authorization, reverse once, result if connection fails, after-reversal projection, recovery comparator `match`. Never automatically retry. Never reverse after human decisions or promotion.

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

Run `schema.sql → db-rls.sql → db-migrations.sql` and the alternate migration ordering on separate disposable databases. On the production-derived restore, apply only the reviewed migrations needed for the feature, then `db-rls.sql` and `db-verify.sql`. Record exact commands and outputs. Any unexpected restore or migration error is BLOCKED.

- [ ] **Step 3: Execute the full required dataflow**

On the fresh restore, with new short-lived authorizations, execute exactly:

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
