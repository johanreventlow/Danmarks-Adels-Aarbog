# #153: Varig writer- og batchkontrakt — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementér den editionsneutrale writer-/batchkontrakt for source-scoped replace og evidens-promotion, bevis #152-cutover og C3 som de specificerede kontraktadaptere, og bevar alle produktionsgates fail-closed.

**Architecture:** En lille R-kontraktpakke validerer lukkede operationprofiler og receipts uden en fælles databasejournal. Promotion og source-scoped replace får hver sin domæneejede single-use authorization/batch/receipt-vej i PostgreSQL. Narrative-cutover mappes read-only til sin eksisterende external-GO/nonce/recover-model, mens C3 kun conformance-testes og fortsat afvises som writer efter narrative-contract v2.

**Tech Stack:** R/testthat/DBI/RPostgres/jsonlite/digest, Python 3/pytest, PostgreSQL 17, SQL-kontrakttests og disposable lokale databaser.

**Spec:** `docs/superpowers/specs/2026-08-30-generalized-writer-batch-design.md`

**Planstatus (2026-08-31):** Tasks 1–3 er afsluttede. Tasks 4–7 nedenfor er
V1-udkast og må ikke eksekveres. De er erstattet af
`docs/superpowers/plans/2026-08-31-source-scoped-evidence-visibility-implementation.md`,
som implementerer den godkendte V3-specifikation.

## Global Constraints

- Ingen production-DB, push, merge, deploy eller produktions-callback.
- Aldrig læs, skriv eller send data under `work/` til model-, browser- eller reviewværktøjer.
- Opret ingen global journal, generisk SQL-writer eller editionsnavngivet permanent databaseoverflade.
- C3 apply/reversal forbliver lukket efter narrative-contract version 2 med `NARRATIVE_RECORD_LEGACY_WRITER_DISABLED`.
- Source-scoped replace bruger stabile `record_key`-identiteter, bevarer person-ID'er ved entydigt match og gør aldrig fravær til slettebevis.
- Source-scoped narrative-write må kun oprette/opdatere record-bundne drafts via #152-kernen. Den må aldrig skrive publiceret tekst, `published_revision`, stale eller withdrawal.
- Promotion opretter eller ændrer aldrig genealogiske kerneobjekter og har `reversal_mode=not_supported`.
- Cutover forbliver `external_go_nonce_authorization` med `recover` som eneste replayvej og `reversal_mode=not_supported`.
- Alle databundet tests bruger en frisk disposable PostgreSQL-database; credentials og realdataartefakter serialiseres aldrig.
- Før hver mutation: kontrollér branch og worktree. Hver task committer kun sine erklærede filer.

## Filkort

| Fil | Ansvar |
| --- | --- |
| `.claude/skills/daa-extract/scripts/writer_batch_contract_helpers.R` | Lukkede operationprofiler, canonical JSON, receipt- og current-state-validering. |
| `tests/testthat/test-writer-batch-contract.R` | Rene kontrakt-, determinisme- og negative R-tests. |
| `tests/sql/test-writer-batch-contract.sql` | Tværadapter ACL-, state- og receiptkontrakt på disposable DB. |
| `tests/integration/test-writer-batch-contract.R` | Én rigtig databasevej pr. muterende adapter samt C3/cutover conformance. |
| `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | Domæneejede promotion- og source-replace-kontrakter samt RLS. |
| `tests/sql/test-evidence-promotion.sql` | Promotionens authorization, batch, receipt og rollbackregression. |
| `.claude/skills/daa-extract/scripts/build_source_scoped_replace_manifest.py` | Lukket, content-addressed replace-manifest fra dry-run og validerede input. |
| `.claude/skills/daa-extract/scripts/apply_source_scoped_replace.R` | Read-only preflight, authorise/apply/reconcile mod adapter-RPC'er. |
| `.claude/skills/daa-extract/scripts/{test_build_source_scoped_replace_manifest.py,test_apply_source_scoped_replace.R}` | Enheds- og gatewaytests for source-replace. |
| `tests/sql/test-source-scoped-replace.sql`, `tests/integration/test-source-scoped-replace.R` | Databasekontrakt, ownership, narrativeovergange og lock-order. |
| `.claude/skills/daa-extract/scripts/load_daa.R`, `R/update-1939-narratives.R`, `R/update-2018-narratives.R` | Fjern kun den permanente v2-dead-end ved at delegere til den autoriserede adapter; behold direkte writes blokeret. |
| `docs/runbooks/{source-scoped-replace.md,evidence-promotion.md}` | Redaktionelt præcist før/efter, autorisation, receipt, recovery og reversibilitet. |

---

### Task 1: Kortlæg levende adaptere før enhver ændring

**Files:**
- Create: `docs/superpowers/reviews/2026-08-30-writer-batch-contract-live-map.md`

- [ ] **Step 1: Kortlæg alle fire adaptere read-only**

For hver af C3, promotion, narrative-cutover og source-scoped replace skal kortet angive aktuelle schema-/migrationsobjekter, R/Python-entrypoints, RLS/revokes, receipt/current-state-verifier, lock-order og præcise SQL-/integrationstests. Brug kun `rg`, `git ls-files`, `pg_get_functiondef` på disposable DB og eksisterende testfixtures; aldrig `work/` eller produktion.

- [ ] **Step 2: Skriv et dependency- og lock-kort**

Kortet skal identificere hver delt ressource (`source_record`, `person`, `narrative`, publication binding, interpretation/target assertion), den aktuelle og den ønskede lock-orden, samt alle legacy writers der er lukkede ved narrative-contract v2.

- [ ] **Step 3: Review kortet mod specen**

Afvis planarbejdet med `WRITER_BATCH_LIVE_MAP_INCOMPLETE`, hvis en adapter, RPC, RLS-flade, test eller lock-overlap mangler. Dokumentér beslutningen om at C3 kun er read-only conformance.

- [ ] **Step 4: Commit read-only-kortet**

```bash
git add docs/superpowers/reviews/2026-08-30-writer-batch-contract-live-map.md
git commit -m "docs: map writer batch adapters"
```

### Task 2: Fastlås styringsgrundlag og den rene fælleskontrakt

**Files:**
- Create: `.claude/skills/daa-extract/scripts/writer_batch_contract_helpers.R`
- Create: `tests/testthat/test-writer-batch-contract.R`
- Modify: `docs/evidensbaseret-genimport/{roadmap.md,status.md}`
- Modify: `docs/decisions.md`
- Modify: `docs/superpowers/specs/2026-08-30-generalized-writer-batch-design.md`
- Modify: this plan

**Interfaces:**
- `wb_validate_profile(profile) -> list` accepts exactly `operation_family,contract_version,execution_kind,reversal_mode,authorization_mode,input_identity,database_identity,schema_contract_version,scope,element_ids,expected_counts,adapter_invariants,lock_order,receipt_schema,terminal_statuses,postverify_schema`.
- `wb_canonical_json(value) -> character` and `wb_sha256(value) -> character` are deterministic.
- `wb_validate_receipt(receipt,profile,mode) -> list` distinguishes historical receipt from `wb_validate_current_state(state,receipt)`.

- [ ] **Step 1: Write failing profile tests**

```r
expect_error(wb_validate_profile(list(operation_family = "x")),
             "WRITER_BATCH_PROFILE_KEYS_INVALID")
expect_error(wb_validate_profile(valid_profile(execution_kind = "delete")),
             "WRITER_BATCH_EXECUTION_KIND_INVALID")
expect_equal(wb_sha256(valid_profile(element_ids = c("b", "a"))),
             wb_sha256(valid_profile(element_ids = c("a", "b"))))
```

- [ ] **Step 2: Run the focused RED test**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-writer-batch-contract.R")'`

Expected: FAIL because the helper does not exist.

- [ ] **Step 3: Implement only canonical, closed validation**

Use `jsonlite::toJSON(..., auto_unbox=TRUE, null="null", pretty=FALSE)` after recursive key sorting. Reject unknown keys, duplicate element IDs, non-hex hashes, empty scope, missing database/schema/terminal/postverify declarations, an undeclared reversal mode, and `authorization_mode="none"` for non-read-only execution.

- [ ] **Step 4: Add historical/current-state separation tests**

Require a valid historical receipt to remain valid after a simulated later drift, while `wb_validate_current_state()` returns `WRITER_BATCH_CURRENT_STATE_DRIFT`.

- [ ] **Step 5: Record the activation and spec wording**

Keep the already approved #153 activation, no-production boundary, four adapters and source-scoped narrative transitions in the authoritative docs. Do not change roadmap order or claim production verification.

- [ ] **Step 6: Run focused tests and diff check**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-writer-batch-contract.R")' && git diff --check`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add docs/decisions.md docs/evidensbaseret-genimport/roadmap.md docs/evidensbaseret-genimport/status.md docs/superpowers/specs/2026-08-30-generalized-writer-batch-design.md docs/superpowers/plans/2026-08-30-generalized-writer-batch-implementation.md .claude/skills/daa-extract/scripts/writer_batch_contract_helpers.R tests/testthat/test-writer-batch-contract.R
git commit -m "docs: activate generalized writer contract"
```

### Task 3: Make evidence-promotion a single-use authorized writer

**Files:**
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `tests/sql/evidence-promotion-bootstrap.sql`, `tests/sql/test-evidence-promotion.sql`
- Create: `tests/integration/test-evidence-promotion-writer-contract.R`
- Create: `docs/runbooks/evidence-promotion.md`

**Interfaces:**
- Add private, adapter-owned `interpretation_promotion_authorization` with UUID id, preview/profile hashes, database identity, actor, nonce, issued/consumed/expired state and expiry.
- Extend `interpretation_promotion_batch` with authorization FK, terminal status, observed counts, receipt JSON/SHA and finalized timestamp.
- Add `red_authorize_interpretation_promotions(jsonb,text,uuid,timestamptz) -> uuid` and change `red_promote_interpretations_batch` to accept an authorization id and return a closed receipt JSON.

- [ ] **Step 1: Write failing SQL contract cases**

Require: unknown profile key, cross-database authorization, wrong actor, expired/consumed nonce, preview hash drift, and duplicate scope all fail before rows are inserted. Require exact replay to return the same receipt and one invalid item to leave zero new batch/promotion rows.

- [ ] **Step 2: Run the SQL RED test**

Run bootstrap, schema, RLS and `tests/sql/test-evidence-promotion.sql` against a fresh disposable DB.

Expected: FAIL because the authorization table/RPC and receipt fields are absent.

- [ ] **Step 3: Add the append-only authorization/batch schema**

Use checks and composite foreign keys to bind batch to authorization, preview hash, profile hash and actor. Add append-only triggers after finalization and revoke all direct private access from `PUBLIC, anon, authenticated`.

- [ ] **Step 4: Implement authorize, apply and postverify**

Authorize only a redaktion actor against `current_database()`; lock interpretations in stable UUID order; recompute preview inside apply; consume authorization only in the same transaction as batch insertion; calculate observed counts from inserted rows; reject a receipt unless observed counts and live promotion links match exactly.

- [ ] **Step 5: Add RLS, ACL and integration negatives**

Test `anon` and ordinary `authenticated` cannot query private authorization/batch data or execute private helpers. Inject a privileged target/link drift after promotion rows are written but before receipt finalization and require full transaction rollback with no green receipt. Separately mutate a post-apply link through the privileged fixture and require current-state verification to report later drift without changing the historical receipt. Add two-session same-interpretation and same-target races; one path may finalize and the other must return a stable no-deadlock conflict/replay result.

- [ ] **Step 6: Write the runbook**

State the exact editorial choice, selected interpretations/targets, preview/profile hash, no-reversal rule and receipt/current-state distinction. It must never promise canonical object creation or undo.

- [ ] **Step 7: Run focused verification and commit**

Run the SQL contract, integration test and `git diff --check`; commit only the declared files with `feat: authorize evidence promotion batches`.

### Task 4: Implement the source-scoped replace authorization, manifest and narrative draft adapter

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_source_scoped_replace_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_source_scoped_replace_manifest.py`
- Create: `.claude/skills/daa-extract/scripts/apply_source_scoped_replace.R`
- Create: `.claude/skills/daa-extract/scripts/apply_source_scoped_replace_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_source_scoped_replace.R`
- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Create: `tests/sql/test-source-scoped-replace.sql`
- Create: `tests/integration/test-source-scoped-replace.R`

**Interfaces:**
- Manifest schema `source-scoped-replace-v1` has `source_id, record_keys, input_sha256, dry_run_sha256, ownership_sha256, expected_counts, policy_decisions, narrative_operations, source_operations`; every array is canonically sorted and closed. `policy_decisions.new_records` is an exact allowlist with `mode="create_staged"`; `policy_decisions.discontinued_records` is an exact allowlist with `mode="retain_report_only"`.
- `build_source_scoped_replace_manifest(dry_run, ownership, input_sha256) -> dict` never reads a database or `work/`.
- DB RPCs: `red_authorize_source_scoped_replace(...)->uuid`, `red_apply_source_scoped_replace(uuid,jsonb)->jsonb`, and `red_verify_source_scoped_replace(uuid)->jsonb`.
- The narrative operation object is exactly `{element_id,person_id,source_id,record_key,text,text_sha256,expected_state_sha256}`; `sha256(UTF-8(text))` must equal `text_sha256`. Terminal receipts contain only the hash and element identity, never `text`.

- [ ] **Step 1: Write Python RED tests for the closed manifest**

Test deterministic bytes under two `PYTHONHASHSEED` values; reject reordered/duplicate record keys, missing dry-run or ownership hash, a non-entydig outcome, a `new` or `bortfalden` outcome absent from its exact policy allowlist, a create mode other than `create_staged`, an unauthorized narrative transition, text/hash mismatch and any extra field.

- [ ] **Step 2: Run Python RED**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_build_source_scoped_replace_manifest.py`

Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Implement the manifest compiler**

Compile only an already read-only dry-run report and an ownership report. An entydig source record requires positive ownership and draft-only narrative candidates. A new record may be included only by its exact `create_staged` policy decision; a bortfalden record may only be retained/reported by its exact `retain_report_only` decision and never yields deletion. Keep validated text only in the locked manifest payload; terminal receipts bind its SHA-256 and omit it.

- [ ] **Step 4: Write failing SQL transition tests**

On a disposable DB, require:
  - no binding/withdrawn + accepted identity -> one `draft_created`;
  - active draft -> one `draft_updated`;
  - published, stale-published, legacy-only, identity mismatch, stale anchor and derived `haendelse` -> whole batch rollback;
  - no writer-created `published`, `published_revision` or `withdrawn` event;
  - source-owned fact replacement preserves editorial/fremmed rows and person IDs.

- [ ] **Step 5: Implement the adapter-owned ledger and RPCs**

Add `source_scoped_replace_authorization`, `source_scoped_replace_batch` and `source_scoped_replace_event` under `private`; do not reuse C3 tables. Bind every authorization to current database, actor, nonce, expiry, manifest/dry-run/ownership hashes and exact elements. Lock in documented order: narrative-contract shared gate, source scope, people ascending, source records ascending, narratives/bindings, then adapter ledger. Route narrative mutations exclusively through `private.mutate_person_narrative_record('upsert',...)` and assert its returned event type is draft-only.

- [ ] **Step 6: Implement R preflight/apply/reconcile**

The R gateway must use `BEGIN READ ONLY` for preflight, reject an unverified manifest, set transaction timeouts before write RPCs, authorize once, reconcile ambiguous commit on a new connection, and verify the terminal receipt plus current state. It must not call `dbAppendTable` on model tables.

- [ ] **Step 7: Add ownership, concurrency and compensation tests**

Test wrong database, actor, nonce, expiry, manifest/dry-run/ownership hash and element-scope before every mutation; exact replay returns the same receipt while any semantic drift fails. Use two DB sessions to prove overlapping source scope cannot deadlock or alter absence sets. Prove a compensating replace requires a new authorization and previous manifest hash; prove it cannot delete editor rows or publication events. Fault-inject a privileged state change after source writes but before batch finalization and require rollback/no green receipt. Test ACL denial for non-editors.

- [ ] **Step 8: Run focused verification and commit**

Run Python, R helper, SQL and integration suites in a fresh disposable DB, then `git diff --check`. Commit with `feat: add source scoped replace writer`.

### Task 5: Delegate legacy entrypoints only to the authorized source writer

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/load_daa.R`
- Modify: `R/update-1939-narratives.R`, `R/update-2018-narratives.R`
- Modify: their existing `tests/testthat/test-*.R`
- Create: `tests/integration/test-source-scoped-replace-entrypoints.R`

- [ ] **Step 1: Write failing entrypoint tests**

Require version-2 normal load and both direct updaters still fail before any write with `NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED`. Require only explicit `--replace` with a verified manifest and authorization to delegate to `apply_source_scoped_replace.R`; reject `--force-gate` as authority.

- [ ] **Step 2: Run RED tests**

Run the three existing testthat files plus the new integration fixture. Expected: the authorized delegation path is absent.

- [ ] **Step 3: Implement minimal delegation**

Keep legacy append/reset paths unchanged and blocked at version 2. Parse an explicit manifest/authorization path only for `--replace`; call the adapter gateway as a subprocess-free R function, pass no credentials in arguments, and return its receipt. Remove no legacy gate.

- [ ] **Step 4: Verify no bypass**

Static tests must fail if `load_daa.R` or either updater contains a post-v2 direct `dbAppendTable(...,"narrative"` or direct narrative UPDATE. Runtime test must observe the adapter’s draft event.

- [ ] **Step 5: Run focused tests and commit**

Commit with `refactor: route source replace through writer contract`.

### Task 6: Add cutover and C3 conformance adapters without reopening writers

**Files:**
- Create: `.claude/skills/daa-extract/scripts/verify_writer_batch_conformance.R`
- Create: `.claude/skills/daa-extract/scripts/test_verify_writer_batch_conformance.R`
- Create: `tests/sql/test-writer-batch-contract.sql`
- Create: `tests/integration/test-writer-batch-contract.R`
- Modify: `tests/sql/test-narrative-record-cutover.sql`
- Modify: `tests/sql/test-1939-v50-c3-apply.sql`
- Modify: `tests/integration/test-narrative-record-concurrency.R`
- Create: `docs/runbooks/source-scoped-replace.md`

- [ ] **Step 1: Write failing conformance fixtures**

Define four profiles: C3 `conformance_read_only`, promotion `promotion`, cutover `cutover/recover`, and source replace `apply/reversal=compensating`. Require cutover receipt fields to bind approval hash, nonce and database identity; require C3 RPC apply/reversal to raise the v2 legacy-writer error. Build a synthetic, hash-locked cutover candidate/approval fixture and run the actual private cutover path plus its actual postverify on a fresh disposable database; do not import a receipt as proof.

- [ ] **Step 2: Run RED**

Run `Rscript .claude/skills/daa-extract/scripts/test_verify_writer_batch_conformance.R`. Expected: no shared conformance verifier.

- [ ] **Step 3: Implement read-only verifier**

Inspect existing C3 batches and cutover receipts only. For C3, return `historical_conformant` only when receipt hash/counts are valid and a probe confirms mutation is disabled. For cutover, validate the real disposable apply receipt, full inventory/postverify result, row-and-absence locking behaviour, private-binding invisibility and the existing `recover` protocol; never rerun a committed apply merely to test replay.

- [ ] **Step 4: Add cross-adapter integration test**

Bootstrap once, execute the real promotion and source-replace paths, execute a synthetic cutover candidate through its real database/postverify path, and inspect a C3 history fixture. Assert common fields while preserving each adapter’s declared execution/reversal mode. Add two-session cross-adapter races: promotion versus source replace over the same canonical person/source scope, and cutover versus each narrative-capable adapter over the same source record. Each must finish or fail with its declared stable gate error, never deadlock or leave a partial/absence-state breach.

- [ ] **Step 5: Write source-replace runbook and commit**

The runbook must require read-only dry-run, manifest/authorization identity, editorial before/after summary, expected draft-only narrative effects, receipt/current-state checks and compensating-manifest procedure. Commit with `test: verify writer batch conformance`.

### Task 7: Full verification, self-review and independent review

**Files:**
- Modify: this plan only if commands or evidence paths changed.

- [ ] **Step 1: Run all focused suites**

Run Python manifest tests; all new R helper tests; evidence-promotion SQL/integration; source-replace SQL/integration/entrypoint; narrative-cutover SQL/concurrency; C3 SQL/conformance.

- [ ] **Step 2: Run repository-level relevant checks**

Run the established DB bootstrap/migration/RLS verification sequence and the relevant TypeScript/R build checks that the touched entrypoints require. Report focused and broader results separately.

- [ ] **Step 3: Codex self-review**

Inspect `git diff --check`, migrations versus schema parity, RLS/revokes, every receipt state transition, lock-order compatibility, current-state drift semantics, source ownership and public-narrative prohibition. Record every finding and its disposition.

- [ ] **Step 4: Independent Sol review**

After tests are green, ask GPT-5.6-Sol to read-only review the current diff and relevant surrounding code for correctness, regressions, lock/deadlock hazards, RLS, data integrity, test gaps and unnecessary complexity. Critically evaluate each finding; fix only valid findings and rerun affected tests. Obtain a second Sol review only if fixes materially change the design/risk profile.

- [ ] **Step 5: Final checkpoint**

Confirm no production action, push, merge or deployment occurred; report branch, HEAD, untracked files, commits, exact commands and results. Only then request integration disposition.
