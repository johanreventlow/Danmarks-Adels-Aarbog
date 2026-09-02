# Generalized Reimport Writer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or `superpowers:executing-plans`
> task-by-task. Use `superpowers:test-driven-development` for every code task,
> `superpowers:systematic-debugging` for every failing verification, and
> `superpowers:verification-before-completion` before a completion claim.

**Goal:** Replace the editions-specific 1939 production-writer primaries with
one v2-safe, profile-bound reimport writer while retaining a single, exact 1939
compatibility facade and rejecting new permanent `_1939` catalog debt.

**Architecture:** `private.reimport_writer_profile` binds each immutable
source/profile/configuration hash to a generic authorization, batch and event
ledger. Generic RPCs take the complete source/profile identity, require #152's
narrative-record contract v2 before any mutation, and use its event-backed
record mutation path. 1939 relations become views and its public RPCs become
thin pinned wrappers; no new writer logic remains under a 1939 name.

**Tech Stack:** PostgreSQL 17, Supabase RLS and `SECURITY DEFINER` RPCs, SQL
contract/integration tests, R/testthat, DBI/RPostgres/jsonlite/digest, and
GitHub Actions.

**Spec:**
`docs/superpowers/specs/2026-09-01-generalized-reimport-writer-design.md`

## Global Constraints

- Work only in `feat/generalized-reimport-153` at
  `.claude/worktrees/generalized-reimport-153`; preserve a clean worktree
  before and after every task.
- Read `vision.md`, `roadmap.md`, `teknisk-maalarkitektur.md` and `status.md`
  before changing the plan. #153 is a general permanent writer/batch mechanism
  between #152 and #149; it does not advance #149 or authorize a new import.
- Do not read, print, create or modify `work/` or protected review artifacts.
- No production database connection, production mutation, push, merge, deploy
  or production cutover. All database tests use a local disposable database.
- Do not modify `load_daa.R`, C3's `reimport_case_*` data model, #152 policy,
  its production runbook or browser/mobile code. Do not use Fable.
- Generic writer mutations take the global
  `daa-narrative-record-contract` lock first and require contract version 2.
  They use #152's state-hash/event-backed record API; direct writes to
  `narrative` or `narrative_record_publication` from the writer are forbidden.
- Every generic authorization/batch/manifest identity is exactly
  `(source_id, profile_id, profile_sha256)`. Every replay, reversal, cutover
  and child-batch lookup includes that identity.
- New editions use only generic interfaces. The one transition facade pins
  source 3, `daa-1939-v50-production-write-v1`, and its seeded profile hash.
- The upgrade is a fail-closed writer cutover, not a second writer version:
  historical terminal ledgers are preserved, but an old authorization with
  `status='issued'` or an old batch with `status IN ('open','finalized')`
  blocks the transaction with `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`.
  Operators must finish or explicitly expire/reverse such work before the
  upgrade; after the upgrade every mutation, including a 1939-wrapper call,
  goes through the generic v2 kernel. Do not add `writer_contract_version`,
  a generic v1 activation/reversal path, synthetic v2 anchors, or a fallback
  based on absent legacy payload fields.
- User-approved 2026-09-02 ACL interpretation: the exact 1939 facade
  signatures are v2-compatible adapters, not executable legacy writers. The
  version-aware #152 ACL authority therefore grants only those enumerated
  facade signatures to their historic authenticated/service-role classes when
  the narrative-record contract is version 2; it must still revoke every
  other legacy writer signature. `db-rls.sql`, v2 cutover and `db-verify.sql`
  must converge on that same matrix in either application order.
- Public/private ACLs must be proven per function signature for `PUBLIC`,
  `anon`, `authenticated` and `service_role`; no blanket EXECUTE grant is
  acceptable.
- Each task commits only its declared files and gets a Codex self-review. After
  the complete integrated diff and all relevant tests are green, obtain one
  independent read-only GPT-5.6-Sol review; repeat it only if a valid fix
  materially changes the risk profile.

## File Structure

| File | Responsibility |
| --- | --- |
| `schema.sql` | Fresh-install generic primary tables, generic v2 writer, exact 1939 views/wrappers and ACLs. |
| `db-migrations.sql` | Transactional upgrade from the old 1939 primary objects to the fresh-install contract. |
| `db-rls.sql` | Explicit grants/revokes for generic and legacy public surfaces. |
| `db-verify.sql` | Complete `_1939` catalog allowlist and generic writer/ACL verification. |
| `tests/sql/test-reimport-writer.sql` | Generic profile, writer, lifecycle and v2 integration contract. |
| `tests/sql/test-reimport-name-completion.sql` | Generic name-completion, activation and reversal contract. |
| `tests/sql/test-reimport-writer-migration.sql` | Applied-upgrade parity checks from a pre-#153 schema. |
| `tests/sql/test-reimport-edition-catalog.sql` | Positive and rollback-isolated negative catalog-gate checks. |
| `tests/sql/reimport-writer-v2-bootstrap.sql` | Reusable disposable fixture that reaches #152 contract v2 without production authority. |
| `tests/integration/test-reimport-writer.R` | DBI two-profile transaction, rollback and collision proof. |
| `tests/testthat/test-apply-reimport.R` | Generic reimport manifest/gateway unit contract. |
| `tests/testthat/test-apply-name-completion.R` | Generic name-completion manifest/gateway unit contract. |
| `tests/testthat/test-reimport-writer-source-inventory.R` | Static source inventory, literal classification and forbidden direct-write proof. |
| `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` | Generic reimport manifest validation and DBI gateway. |
| `.claude/skills/daa-extract/scripts/apply_reimport.R` | Generic reimport CLI. |
| `.claude/skills/daa-extract/scripts/apply_name_completion_helpers.R` | Generic name-completion manifest validation and DBI gateway. |
| `.claude/skills/daa-extract/scripts/apply_name_completion.R` | Generic name-completion CLI. |
| Existing `*_1939_v50*.R` files | Thin legacy manifest adapters only; no DBI calls or legacy RPC calls. |
| `.github/workflows/ci.yml` | Fresh, upgraded and full disposable verification paths. |

---

### Task 1: Freeze the live writer inventory and create RED contract tests

**Files:**

- Create: `tests/testthat/test-reimport-writer-source-inventory.R`
- Create: `tests/sql/test-reimport-writer.sql`
- Create: `tests/sql/test-reimport-name-completion.sql`
- Create: `tests/sql/reimport-writer-v2-bootstrap.sql`
- Modify: `tests/sql/test-1939-v50-production-writer.sql`
- Modify: `tests/sql/test-1939-v50-name-completion.sql`

**Interfaces:**

- Consumes the current writer family from `schema.sql:2324-3098`, the v2
  narrative-record API beginning at `schema.sql:10994`, and the current two
  legacy SQL tests.
- Produces a closed literal inventory and RED tests for the generic primary
  catalog, generic RPC signatures, contract-v2 gate, profile identity,
  generic lifecycle, and legacy facade parity.

- [ ] **Step 1: Write the static literal and direct-writer RED test**

  In `test-reimport-writer-source-inventory.R`, parse the 1939 writer segment
  in both `schema.sql` and `db-migrations.sql`. Assert that every occurrence
  of `source_id=3`, `sr.source_id<>3`, `sp.source_id<>3`,
  `=8`, `<>8`, `DAA 1939 side`, `reimport-1939-v50:` and
  `daa-1939-v50-name-completion` is listed in a four-column inventory
  (`literal`, `classification`, `generic_target`, `test_name`). Assert that
  generic functions contain neither those literals nor direct DML on
  `public.narrative`/`private.narrative_record_publication`.

  ```r
  expect_true(all(inventory$classification %in%
    c("generic_invariant", "profile", "manifest", "legacy_wrapper")))
  expect_false(grepl("INSERT INTO public\\.narrative", generic_person_create))
  expect_false(grepl("INSERT INTO private\\.narrative_record_publication", generic_person_create))
  ```

- [ ] **Step 2: Run the RED inventory test**

  Run:

  ```bash
  Rscript -e 'testthat::test_file("tests/testthat/test-reimport-writer-source-inventory.R")'
  ```

  Expected: FAIL because generic functions, a literal inventory and v2-only
  writer guards do not yet exist.

- [ ] **Step 3: Write generic SQL catalog and v2-gate RED assertions**

  In `test-reimport-writer.sql`, require these primary relations:

  ```sql
  private.reimport_writer_profile
  private.reimport_authorization
  private.reimport_batch
  private.reimport_event
  private.reimport_name_completion_result
  ```

  Require `profile_sha256` on profile/authorization/batch, the two composite
  foreign keys, an immutable-profile trigger, append-only events/results, and
  the generic signatures:

  ```sql
  public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)
  public.red_begin_reimport(uuid,text,text)
  public.red_apply_reimport_source_evidence(uuid,text,jsonb)
  public.red_apply_reimport_person_create(uuid,text,jsonb)
  public.red_finalize_reimport(uuid)
  public.red_authorize_reimport_reversal(uuid,uuid,timestamptz)
  public.red_reverse_reimport(uuid,uuid)
  public.red_authorize_reimport_cutover(uuid,uuid,timestamptz)
  public.red_activate_reimport_batch(uuid,uuid)
  ```

  The test must call generic authorization while the v2 bootstrap is absent
  and require `REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED` before any ledger
  row is inserted.

- [ ] **Step 4: Add reusable disposable v2 bootstrap and run RED SQL**

  Extract only the existing synthetic #152 cutover prerequisites into
  `reimport-writer-v2-bootstrap.sql`: create a disposable editor principal,
  source record and exact cutover artifact, invoke the existing contract
  cutover path, and assert `narrative_record_contract_version()=2`. Do not
  alter the #152 production runbook or use production identifiers.

  Run:

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-writer.sql
  ```

  Expected: FAIL at the first missing generic relation or signature.

- [ ] **Step 5: Convert legacy tests into facade-only RED tests**

  Keep the files `test-1939-v50-production-writer.sql` and
  `test-1939-v50-name-completion.sql`, but change their first assertions to
  require old private names to be views and old public names to be wrappers.
  Add assertions that their created authorization/batch rows resolve to the
  generic primaries and the seeded 1939 profile. Preserve tests for existing
  signature, result type, idempotence, role rejection, tamper rejection and
  observed legacy error tokens.

- [ ] **Step 6: Commit the RED suite**

  ```bash
  git add tests/testthat/test-reimport-writer-source-inventory.R \
    tests/sql/test-reimport-writer.sql tests/sql/test-reimport-name-completion.sql \
    tests/sql/reimport-writer-v2-bootstrap.sql \
    tests/sql/test-1939-v50-production-writer.sql \
    tests/sql/test-1939-v50-name-completion.sql
  git commit -m "test: specify generic reimport writer contract"
  ```

### Task 2: Implement the generic profile ledger and main v2 writer

**Files:**

- Modify: `schema.sql:2324-2797`
- Modify: `db-migrations.sql` after the current 1939 writer migration block
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-reimport-writer.sql`
- Modify: `tests/testthat/test-reimport-writer-source-inventory.R`

**Interfaces:**

- Consumes Task 1's generic catalog/v2 RED tests and #152's
  `private.narrative_record_state` plus
  `public.red_upsert_person_narrative_record` interface.
- Produces the primary generic ledger and source-evidence/person-create/finalize
  RPCs, all bound to a sealed profile hash and v2 narrative event path.

- [ ] **Step 1: Add focused profile ledger RED cases**

  Extend `test-reimport-writer.sql` to seed two sources and immutable profiles:

  ```sql
  INSERT INTO private.reimport_writer_profile
    (source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES
    (3,'daa-1939-v50-production-write-v1','production-writer-v1',repeat('a',64),
     '{"run_key_prefix":"fixture-1939:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"fixture-rendition-3","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed","citation_label_template":"Fixture 1939 side {page_from}"}'::jsonb),
    (4,'synthetic-second-profile-v1','synthetic-v1',repeat('b',64),
     '{"run_key_prefix":"fixture-second:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"fixture-rendition-4","rendition_kind":"ocr_text","rendition_metadata":{"edition":"synthetic"},"observation_extraction_method":"human_reviewed","citation_label_template":"Fixture second side {page_from}"}'::jsonb);
  ```

  Verify `UPDATE`/`DELETE` fail, a profile hash mismatch fails before a ledger
  row, and source/profile mismatch fails before a ledger row.

- [ ] **Step 2: Run the focused profile RED cases**

  Run the same SQL file on the disposable v2 database. Expected: failures at
  missing profile table, immutable trigger and generic authorization.

- [ ] **Step 3: Replace fresh-install primaries with generic relations**

  In `schema.sql`, replace the old primary table block with
  `reimport_writer_profile`, `reimport_authorization`, `reimport_batch`,
  `reimport_event` and `reimport_name_completion_result`. Define:

  - `UNIQUE(source_id, profile_id, profile_sha256)` on the profile registry;
  - an append-only `BEFORE UPDATE OR DELETE` trigger on profile/event/result;
  - `(source_id,profile_id,profile_sha256)` foreign keys from authorization
    and batch to profile;
  - `(authorization_id,source_id,profile_id,profile_sha256)` foreign key from
    batch to authorization; and
  - uniqueness/replay indexes that include source/profile/hash together with
    the current manifest/preview/principal or parent identity.

  Seed only the 1939 profile row in fresh DDL. Its `writer_config` must carry
  all inventory fields classified as `profile`; counts and payloads remain in
  the manifest.

- [ ] **Step 4: Implement main generic helpers and RPCs**

  Rename the primary helper implementations to generic names and implement the
  full authorization envelope. `red_authorize_reimport` verifies the supplied
  source/profile/hash against the immutable profile, then stores all three.
  `red_begin_reimport`, source evidence, person create and finalize read the
  exact profile triple from the locked batch. Every mutation begins with:

  ```sql
  PERFORM pg_advisory_xact_lock_shared(
    hashtextextended('daa-narrative-record-contract',0)
  );
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED';
  END IF;
  ```

  `red_apply_reimport_person_create` must obtain the v2 record state hash and
  call `public.red_upsert_person_narrative_record`; it records returned event,
  narrative and state hashes in the generic event payload. It must not directly
  insert/update/delete `narrative` or `narrative_record_publication`.

- [ ] **Step 5: Apply the same transformation to `db-migrations.sql`**

  Append an idempotent transactional upgrade that creates the profile registry,
  seeds the 1939 profile/hash, renames the old three ledger tables, adds and
  backfills profile columns, rebuilds the source/profile-aware FK/index set,
  and creates generic functions. Keep row PKs and batch/event references
  unchanged. A missing/multiple legacy source identity must raise an exception
  before DDL commits.

- [ ] **Step 6: Make generic ACLs explicit and run GREEN**

  In `schema.sql`, `db-migrations.sql` and `db-rls.sql`, revoke all private
  tables/helpers and grant only the specific generic authorizers to
  `service_role` and specific generic write operations to `authenticated`.
  Execute Task 1's inventory and generic SQL tests; require both profiles to
  reach source-evidence/person-create/finalize through v2 events.

- [ ] **Step 7: Self-review and commit**

  Inspect the staged diff for old primary references, direct narrative DML,
  omitted profile-scoped uniqueness and ACL broadening. Rerun the two tests,
  then commit:

  ```bash
  git add schema.sql db-migrations.sql db-rls.sql \
    tests/sql/test-reimport-writer.sql \
    tests/testthat/test-reimport-writer-source-inventory.R
  git commit -m "feat: add profile-bound generic reimport writer"
  ```

### Task 3: Generalize name completion, activation and reversal

**Files:**

- Modify: `schema.sql:2569-3098`
- Modify: `db-migrations.sql` generic writer upgrade section
- Modify: `tests/sql/test-reimport-writer.sql`
- Modify: `tests/sql/test-reimport-name-completion.sql`

**Interfaces:**

- Consumes Task 2's batch triple, generic event ledger and v2 person/narrative
  event receipt.
- Produces generic name-completion, reversal and activation APIs that work for
  both profiles without source-3 or eight-row assumptions.

- [ ] **Step 1: Write full two-profile lifecycle RED cases**

  For each profile, create the same number of staged persons through the
  generic main writer, authorize name completion, apply completion payloads,
  finalize, authorize cutover, activate, authorize reversal and reverse.
  Use exactly equal manifest and preview hashes for both profiles and assert
  different authorization/batch IDs. Include a cross-profile reversal and
  child-batch lookup attempt that must fail.

- [ ] **Step 2: Run lifecycle RED SQL**

  Run:

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-name-completion.sql
  ```

  Expected: FAIL because generic name-completion/lifecycle signatures and
  profile-scoped child lookup do not exist.

- [ ] **Step 3: Implement generic continuation functions**

  Implement `red_lock_reimport_name_completion`,
  `red_authorize_reimport_name_completion`,
  `red_preflight_reimport_name_completion`,
  `red_begin_reimport_name_completion`,
  `red_apply_reimport_name_completion` and
  `red_finalize_reimport_name_completion`. Derive source/profile/hash from the
  locked source batch and authorize them again at each child boundary. Replace
  fixed eight-row checks with equality between authorized expected counts,
  result rows and generic event rows. Put citation/source labels and extraction
  values in profile config or authorized payload according to Task 1 inventory.

- [ ] **Step 4: Implement generic activation and reversal**

  Implement generic reversal/cutover functions that scope all child batches,
  facts, identities, citations and record publication events to the locked
  complete profile identity. Use the #152 event-specific reversal/withdrawal
  path rather than deleting a v2 narrative binding directly. A stale state,
  foreign child batch, mismatched event hash, non-finalized completion or
  profile collision must abort before the first mutation.

- [ ] **Step 5: Preserve C3 boundary and run GREEN**

  Do not rename or alter `reimport_case_*`. Change only shared canonical JSON
  helper callers to the generic helper name and retain an explicit legacy alias
  where the C3 surface still calls it. Run both generic lifecycle SQL tests and
  `tests/sql/test-1939-v50-c3-apply.sql`; the latter must retain its current
  C3 semantics and #152 fail-closed behavior.

- [ ] **Step 6: Self-review and commit**

  Verify every current literal is accounted for by the Task 1 inventory, every
  lock begins with the global v2 contract lock, and no profile-unscoped child
  query remains. Commit:

  ```bash
  git add schema.sql db-migrations.sql tests/sql/test-reimport-writer.sql \
    tests/sql/test-reimport-name-completion.sql
  git commit -m "feat: generalize reimport lifecycle and completion"
  ```

### Task 4: Add the one-version 1939 compatibility facade and upgrade proof

**Files:**

- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `tests/sql/test-1939-v50-production-writer.sql`
- Modify: `tests/sql/test-1939-v50-name-completion.sql`
- Create: `tests/sql/test-reimport-writer-migration.sql`
- Create: `tests/sql/inspect-reimport-writer-catalog.sql`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Consumes generic primaries from Tasks 2-3 and the pre-#153 schema at commit
  `2d6aabf`.
- Produces read-compatible private 1939 views, exact public 1939 wrappers,
  complete error/ACL matrices, byte-comparable fresh/upgraded catalog
  receipts, and a fail-closed pre-upgrade quiescence gate. Terminal legacy
  history is read-compatible; an in-flight legacy write is deliberately not
  executable after upgrade.

- [ ] **Step 1: Write facade and migration-parity RED tests**

  Require `to_regclass('private.reimport_1939_authorization')` and the other
  three old relation names to have `relkind='v'`, not table kind. Require every
  old public signature to exist, return the historic type and delegate to the
  corresponding generic primary with source 3/profile/hash. Build an explicit
  expected error mapping in the SQL test for each legacy
  `REIMPORT_1939_*`, `NAME_COMPLETION_1939_*` and cutover failure exercised by
  the legacy tests. Add two migration fixtures: a terminal chain with only
  consumed/expired authorizations and activated/reversed batches, and an
  in-flight chain containing one `issued` authorization or one `open`/
  `finalized` batch. The former must upgrade with preserved IDs, hashes and
  references; the latter must fail with
  `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED` before any schema conversion.

- [ ] **Step 2: Bootstrap an actual pre-#153 schema and run migration RED**

  In CI and locally, create a disposable `reimport_legacy_153` database,
  install `tests/sql/evidence-promotion-bootstrap.sql`, then feed
  `git show 2d6aabf:schema.sql` to `psql`. In one disposable database insert a
  terminal legacy authorization/batch/event/name-completion chain with source
  3; applying current `db-migrations.sql` and `db-rls.sql` must initially
  fail until it preserves rows and installs the generic/view contract. In a
  separate disposable database insert one otherwise-valid issued
  authorization, then one otherwise-valid `finalized` batch; each migration
  attempt must initially fail only because the quiescence gate is absent.

- [ ] **Step 3: Implement fresh views and pinned public wrappers**

  After generic fresh DDL, create the four 1939 relation views. Define each
  old public function at its exact current signature as a SQL/plpgsql wrapper
  that passes source 3, the seeded profile ID/hash and otherwise delegates once
  to a generic RPC. Wrappers contain no DML, locks or input validation beyond
  converting a generic domain error through the explicit error map.

- [ ] **Step 4: Complete transactional upgrade DDL**

  At the start of the one-transaction migration, lock/check the old ledgers
  and raise `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED` if any authorization
  is `issued` or any batch is `open` or `finalized`. Do not rewrite old payloads
  into synthetic v2 event/record anchors and do not attempt to complete,
  activate or reverse an old chain through a new v1 branch. Once quiescent,
  rename old tables/indexes/triggers to generic names, retain their row IDs,
  create generic replacement constraints and profile foreign keys, then create
  views/wrappers only after all generic functions are defined. Serialize and
  compare relation kind/name, `pg_constraint` type and parent, `pg_policy`,
  owned sequence, index definition, function signature, trigger parent, RLS
  state and grants between a fresh and upgraded database.

- [ ] **Step 5: Materialize the ACL/error matrices and run GREEN**

  Add a catalog-driven SQL matrix covering every generic and wrapper signature:
  owner, security-definer bit, exact `search_path`, each role's EXECUTE state
  and required redaktion principal. Test all legacy error tokens with a
  deliberately invalid generic condition and assert the wrapper emits the
  mapped token, while an unknown error is not silently translated. The
  historic canonical-delta signature must delegate once to a generic
  fail-closed endpoint and return `REIMPORT_1939_CANONICAL_DELTA_UNSUPPORTED`
  with no created fact/assertion/citation/conclusion/result/event. Amend the
  #152 version-aware ACL authority, rather than re-granting afterward: at v2
  it grants exactly the approved facade signatures and their historic role
  split, while unrelated legacy writers remain revoked. Exercise both
  orderings (v2 cutover then `db-rls.sql`; `db-rls.sql` then v2 ACL apply),
  assert the same matrix and run `db-verify.sql` in each. Include the profile
  registry and all four legacy relation views in the migration catalog receipt
  and relkind assertions.

- [ ] **Step 6: Self-review and commit**

  Confirm the migration does not drop or recreate terminal historic ledger
  identities, rejects every in-flight legacy state before conversion, old
  private names are views only, and the CI old-schema bootstrap never contacts
  production. Run the fresh, terminal-upgrade and rejected-in-flight-upgrade
  test paths, then commit:

  ```bash
  git add schema.sql db-migrations.sql db-rls.sql db-verify.sql .github/workflows/ci.yml \
    tests/sql/test-1939-v50-production-writer.sql \
    tests/sql/test-1939-v50-name-completion.sql \
    tests/sql/test-reimport-writer-migration.sql \
    tests/sql/inspect-reimport-writer-catalog.sql
  git commit -m "feat: add 1939 reimport transition facade"
  ```

### Task 5: Replace the R gateways with generic manifest-bound adapters

**Files:**

- Create: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_reimport.R`
- Create: `.claude/skills/daa-extract/scripts/apply_name_completion_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_name_completion.R`
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_1939_v50.R`
- Modify: `.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R`
- Create: `tests/testthat/test-apply-reimport.R`
- Create: `tests/testthat/test-apply-name-completion.R`
- Modify: `tests/testthat/test-apply-reimport-1939-v50.R`
- Modify: `tests/testthat/test-apply-name-completion-1939-v50.R`
- Modify: `tests/integration/test-1939-v50-production-writer.R`
- Modify: `tests/integration/test-1939-v50-name-completion.R`

**Approved 2026-09-02 replay-boundary amendment:**

- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql` and `db-verify.sql`
- Modify: `tests/sql/test-reimport-writer.sql`,
  `tests/sql/test-reimport-writer-migration.sql` and
  `tests/sql/inspect-reimport-writer-catalog.sql`

Add exactly one generic, authenticated-writer-only result surface:
`public.red_reimport_batch_result(p_authorization_id uuid, p_batch_id uuid)
RETURNS jsonb`. It replaces R-side reads of `private.reimport_batch` and
`private.reimport_event`; no private-table grant is permitted. It must bind a
consumed reimport authorization and its current editor to the complete
source/profile/hash and manifest/preview identity of the batch, return only a
deterministic `batch_id`, `status`, `replayed` and finalized `person_id_map`,
and fail closed for every other state or identity. The same definition and
ACL must reach fresh and upgraded catalogs. This narrow addition is required
to preserve the approved finalized-batch replay contract without weakening
the private-ledger boundary.

**Interfaces:**

- Consumes generic SQL signatures and the manifest envelope from Tasks 2-3.
- Produces generic DBI gateways and legacy scripts that adapt only a pinned
  1939 manifest to generic helpers.
- The generic reimport DBI gateway may use only generic public RPCs, including
  the approved result surface above; it may not read `private.reimport_*`.

- [ ] **Step 1: Write generic manifest/gateway RED unit tests**

  In both new testthat files, construct an in-memory manifest with required
  `source$id`, `source$profile_id` and `source$profile_sha256`. Assert failure
  for missing, unknown-format or mismatched profile hash before any gateway
  call. Use an instrumented gateway to assert generic SQL only:

  ```r
  expect_match(calls[["authorize"]], "red_authorize_reimport")
  expect_false(any(grepl("1939_v50|source_id=3", unlist(calls))))
  ```

- [ ] **Step 2: Run R RED tests**

  Run:

  ```bash
  Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
  Rscript -e 'testthat::test_file("tests/testthat/test-apply-name-completion.R")'
  ```

  Expected: FAIL because generic helper files and envelope validation do not
  exist.

- [ ] **Step 3: Implement generic helpers and CLIs**

  Implement shared validation that checks the complete manifest identity,
  profile hash, current database identity, actor, transaction/read-only status
  and locked payload count. The DBI gateway calls generic authorization,
  begin/apply/finalize and generic name-completion/cutover/reversal RPCs using
  DBI parameter binding. Keep `on.exit`/error rollback idempotent and preserve
  dry-run versus apply semantics.

- [ ] **Step 4: Reduce 1939 scripts to adapters**

  Keep their old command-line flags and 1939 manifest validation. Add the
  pinned profile ID/hash, call the generic helper and remove every `DBI::`,
  `red_*_1939_v50_*` and literal database source-ID use from the adapters.
  Existing old testthat files must prove this compatibility contract.

- [ ] **Step 5: Run all R tests and commit**

  Run new and old testthat files, then the existing production-writer and
  name-completion DBI integrations against the disposable v2 database. Self
  review the gateways for credentials/artifact leaks and commit:

  ```bash
  git add .claude/skills/daa-extract/scripts/apply_reimport_helpers.R \
    .claude/skills/daa-extract/scripts/apply_reimport.R \
    .claude/skills/daa-extract/scripts/apply_name_completion_helpers.R \
    .claude/skills/daa-extract/scripts/apply_name_completion.R \
    .claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R \
    .claude/skills/daa-extract/scripts/apply_reimport_1939_v50.R \
    .claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R \
    .claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R \
    tests/testthat/test-apply-reimport.R tests/testthat/test-apply-name-completion.R \
    tests/testthat/test-apply-reimport-1939-v50.R \
    tests/testthat/test-apply-name-completion-1939-v50.R
  git commit -m "refactor: route reimport gateways through generic API"
  ```

### Task 6: Enforce the permanent editions-name catalog gate

**Files:**

- Modify: `db-verify.sql`
- Modify: `tests/sql/run-db-verify-disposable.sql`
- Create: `tests/sql/test-reimport-edition-catalog.sql`
- Modify: `tests/testthat/test-reimport-writer-source-inventory.R`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Consumes the complete fresh/upgraded catalog serialization from Task 4.
- Produces a deterministic allowlist gate for relations/views/indexes/sequences,
  types, function signatures, triggers, constraints and policies named
  `_1939` in `public`/`private`.

- [ ] **Step 1: Write positive and negative catalog RED tests**

  In `test-reimport-edition-catalog.sql`, call the new verifier against the
  clean current catalog, then in savepoints create one extra `_1939` function,
  relation, check constraint, RLS policy, owned sequence/index and trigger.
  Each must raise `REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT`; roll back the
  savepoint and assert the normal catalog remains unchanged.

- [ ] **Step 2: Run catalog RED**

  Run:

  ```bash
  /opt/homebrew/opt/postgresql@17/bin/psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-reimport-edition-catalog.sql
  ```

  Expected: FAIL because `db-verify.sql` has no complete allowlist assertion.

- [ ] **Step 3: Implement canonical catalog serialization and allowlist**

  Add one `db-verify.sql` assertion that emits comparable rows for `pg_class`,
  `pg_type`, `pg_proc`, `pg_trigger`, `pg_constraint` and `pg_policy`, with
  namespace, object kind, name/signature and parent identity. Encode the exact
  baseline allowlist from `2d6aabf`'s existing C3 objects plus Task 4's four
  1939 views, public wrappers and explicit helper aliases. Reject an omitted,
  additional or kind/signature/parent-drifted entry.

- [ ] **Step 4: Run disposable db-verify GREEN and commit**

  Extend `run-db-verify-disposable.sql` only with the generic writer's local
  fixture prerequisites. Run the catalog test, the complete disposable
  `db-verify`, static inventory test and CI fresh/upgraded paths. Self-review
  the allowlist for accidental production assumptions, then commit:

  ```bash
  git add db-verify.sql tests/sql/run-db-verify-disposable.sql \
    tests/sql/test-reimport-edition-catalog.sql \
    tests/testthat/test-reimport-writer-source-inventory.R .github/workflows/ci.yml
  git commit -m "test: reject new edition-specific reimport objects"
  ```

### Task 7: Run complete disposable verification and final evidence audit

**Observed Task 7 status (2026-09-02): GREEN for bounded code-integration
evidence.** Separate named local disposable fresh/upgraded tracks now cover
generic writer, migration parity, catalog, complete `dblink` verifier,
generic/legacy DBI and focused R suites. Full C3 is green on both v1-compatible
tracks; focused v2 probes prove the specified C3 public surface is fail-closed.
The exact two private/revoked C3 aliases are catalog-allowlisted and fresh/
upgraded v2 catalog serialization is byte-identical. The durable evidence is
`docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md`; it is not
production authority. The controller still owns the required independent
read-only Sol review.

**Files:**

- Modify: `docs/superpowers/plans/2026-09-01-generalized-reimport-writer-implementation.md`
- Modify: `docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md`

**Task 7 corrective completion scope (2026-09-02):**

- Modify: `db-migrations.sql`
- Modify: `db-verify.sql`
- Modify: `tests/sql/test-1939-v50-c3-apply.sql`
- Create: `tests/integration/test-reimport-writer.R`

The Task 7 rehearsal found an upgrade-only C3 regression: the #153 migration
drops `private.require_reimport_1939_editor()` and
`private.reimport_1939_canonical_json_sha256(jsonb)` although the unaffected
C3 case-ledger RPCs still call them. Retain exactly these private, revoked C3
helper aliases in the upgrade catalog, matching fresh install; do not restore
any legacy 1939 writer table, public writer RPC, grant, or generic-writer
dependency. Add an upgraded C3 regression assertion. Add the already-required
generic DBI integration and prove its listed Task 7 invariants using only a
named disposable database. Repeat affected fresh/upgraded and C3 verification
and replace the observed NO-GO rehearsal conclusion only with new observed
evidence.

The exact edition-object catalog must allowlist those two retained private,
revoked helper signatures and no other new edition-specific object.

**Task 7 contract-track ruling (2026-09-02):** The generic writer requires the
v2 bootstrap. C3 remains a separate v1 contract: the existing #152
version-aware ACL authority deliberately fail-closes the C3 public RPCs after
v2 bootstrap. Therefore, run the full C3 regression on separate fresh and
upgraded v1-compatible disposable databases (schema/migration/RLS, without v2
bootstrap), and record a focused v2 assertion that the C3 public surface stays
fail-closed. Do not restore C3 privileges under v2 or change C3's data model.

**Interfaces:**

- Consumes all completed tasks and their clean fresh/upgraded local databases.
- Produces a bounded evidence report for code integration only, not a
  production authorization.

- [x] **Step 1: Run fresh-install verification**

  Build a disposable database with bootstrap → `schema.sql` →
  `db-migrations.sql` → `db-rls.sql` → v2 bootstrap. Run generic SQL writer,
  generic name-completion, legacy facade, catalog and full
  `run-db-verify-disposable.sql` tests. On a separate fresh v1-compatible
  database without v2 bootstrap, run the complete C3 regression; on the v2
  database, assert that C3's public surface fails closed. Record exact
  commands, database name, commit and exit status in the rehearsal report.

- [x] **Step 2: Run upgraded-install verification**

  Build a separate disposable database from `git show 2d6aabf:schema.sql`, then
  current migrations/RLS. Run migration parity serialization, generic and
  legacy SQL tests after its v2 bootstrap, and compare the fresh/upgraded v2
  canonical catalog output byte-for-byte with `cmp`. Separately run the full
  C3 regression on an upgraded v1-compatible database without v2 bootstrap.

- [x] **Step 3: Run R and concurrency verification**

  Run both generic and compatibility testthat suites plus
  `tests/integration/test-reimport-writer.R`. The integration test must prove:
  v2 event-backed person narrative creation, two-profile equal-hash separation,
  rollback leaves no ledger/domain rows, unauthorized caller rejection and
  reversal/activation cannot cross profile identity.

- [ ] **Step 4: Perform final self-review and independent Sol review**

  Review the final diff against every §1 and §6 requirement in the spec.
  Confirm all permanent primaries are generic, all old names are allowlisted
  transition facades, no new source-specific writer remains, C3 is unchanged
  in behavior, and no `work/` or production boundary was crossed. Request one
  independent read-only GPT-5.6-Sol review of the final diff and critically
  resolve valid findings; rerun the affected verification after each fix.

- [ ] **Step 5: Update evidence and commit**

  Document only observed disposable evidence, including any unresolved test or
  environment limitation. State explicitly that #153 is a code-integration
  result and not production authority.

  ```bash
  git add docs/superpowers/plans/2026-09-01-generalized-reimport-writer-implementation.md \
    docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md
  git commit -m "docs: record generalized reimport writer rehearsal"
  ```

### Task 8: Correct final SOL review findings

**Authority:** Owner-approved 2026-09-02 after the required independent
read-only SOL review returned NO-GO. This is a bounded correctness completion
of the existing #153 specification, not a new writer feature, C3 policy
change, production action, or expansion to a new edition.

**Files:**

- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: generic R gateway helpers and their generic/legacy adapters only as
  required to bind server-authorized identity
- Modify: generic SQL, migration, catalog/parity, concurrency and R tests;
  `.github/workflows/ci.yml` only if its disposable fixture must model the
  corrected terminal legacy chain
- Modify: this plan and the bounded #153 rehearsal only with observed evidence

- [x] **Step 1: Seal profile identity and configuration bytes RED/GREEN**

  Enforce the specification's `(source_id, profile_id)` primary identity,
  append-only row and deterministic `profile_sha256` binding to the exact
  canonical `writer_config`. Replace the synthetic 1939 hash with the derived
  value and make fresh/migration/wrapper tests reject a duplicate profile key,
  arbitrary hash or mismatched configuration. Do not add profile mutation or
  a second profile version under one `profile_id`.

- [x] **Step 2: Bind gateway apply paths to server identity RED/GREEN**

  Make generic reimport and name-completion apply validate the supplied
  authorization against server-returned source/profile/hash and manifest
  hashes. The server, not a locally echoed manifest object, is the source of
  this identity. Preserve the restricted public-RPC boundary; do not grant
  private ledger access. Restore name-completion's full
  database-name/system-identifier binding and test profile, hash and cloned
  database-identity mismatch rejection.

- [x] **Step 3: Restore authorization/replay tamper invariants RED/GREEN**

  Reject malformed expected counts/elements and require equivalent
  authorized-element/count state before finalized replay is returned. Cover
  same-hash but changed-element/count authorization attempts and preserve
  idempotent matching replay.

- [x] **Step 4: Correct terminal migration and parity proof RED/GREEN**

  Permit only genuinely terminal historical chains: an activated source with
  one finalized name-completion child, or a reversed source with its reversed
  child. Reject issued authorization, open work, finalized reimport sources,
  orphan/finalized children without exactly one activated parent, finalized
  children beneath reversed parents, and broken/ambiguous parent-result
  references. Repair the CI and disposable fixtures to represent both real
  topologies. Add function-body digests to fresh/upgraded catalog serialization
  so behavioral drift cannot pass byte parity.

  **Owner-approved evidence extension (2026-09-02):** Build the terminal
  historical fixture through the pre-#153 name-completion RPC path (or an
  equivalently complete, RPC-valid fixture) with its actual eight
  `canonical_delta` events and result rows. A status-only synthetic child is
  insufficient. Re-run atomicity, actual migration, preserved-history and
  fresh/upgraded body-digest parity evidence. This remains disposable
  fixture/test work only; it must not modify C3, production data or the
  generic writer contract.

  **Owner-approved two-track ruling (2026-09-02, SOL GO):** Verify both real
  historical forms on a v1-compatible migration track without v2 bootstrap.
  Verify v2 generic writer behavior separately on fresh v2 and a clean
  upgraded baseline using the existing truthful #152 bootstrap. The rehearsal
  must state that this does not prove #152 cutover of the eight-record
  historical fixture. Do not alter #152 inventory/cutover policy or fabricate
  candidate/approval evidence.

  **Observed completion (2026-09-02):** The pre-fix migration rejected a
  source-3 physical ledger with zero authorization rows
  (`REIMPORT_WRITER_LEGACY_SOURCE_IDENTITY_INVALID`). The completed narrow
  correction permits only that zero-row path; every nonempty ledger still must
  identify exactly source 3. Named local disposable tests prove the two
  RPC-created eight-row terminal forms, atomic rollback, exact parent/child/
  result linkage, four malformed-terminal rejections, wrong-source and
  multi-source nonempty rejection, a separate clean historical upgrade through
  the existing v2 bootstrap, and byte-identical fresh/clean-upgraded effective
  catalog output. The terminal history path stays v1-compatible and is not
  bootstrapped to v2; its attempted #152 bootstrap correctly fails closed on
  live cutover inventory drift. No #152 inventory/cutover/C3 policy changed.

- [x] **Step 5: Enforce source/profile writer locking RED/GREEN**

  Take the specified `(source_id, profile_id)` writer lock inside every generic
  SQL mutation/lifecycle path, including name completion, after the shared v2
  contract lock. Prove same-profile serialization and unrelated-profile
  independence through a disposable two-connection test. Do not rely on the
  cooperative R lock or use a global name-completion lock for this property.

- [ ] **Step 6: Full verification, self-review and independent SOL re-review**

  Re-run affected fresh/upgraded v1-C3 and v2 generic suites, DBI integrations,
  catalog byte parity, migration/terminal-chain fixture and concurrency proof.
  Critically self-review every original SOL finding, then request one fresh
  read-only SOL re-review only after the fixes and evidence are complete.
  Update the rehearsal with observed facts and commit; no production GO.

### Task 9: Close the remaining generic contract and integrity gaps

**Authority:** Owner-approved 2026-09-02 after the Task 8 SOL re-review found
six remaining specification gaps. This task is the single bounded correction
round for those findings. It does not reopen C3, #152 cutover policy, terminal
history semantics, production authority, or support for another real edition.

**Files:**

- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`
- Modify: `.claude/skills/daa-extract/scripts/apply_name_completion_helpers.R`
- Modify: `tests/sql/test-reimport-writer.sql`,
  `tests/sql/test-reimport-name-completion.sql`,
  `tests/sql/test-reimport-writer-migration.sql`,
  `tests/sql/reimport-writer-legacy-terminal-fixture.sql`,
  `tests/sql/reimport-writer-legacy-invalid-terminal-fixture.sql`,
  `tests/sql/inspect-reimport-writer-catalog.sql`
- Modify: `tests/integration/test-reimport-writer-locking.R`,
  `tests/integration/test-reimport-writer.R`,
  `tests/testthat/test-apply-name-completion.R`, and only directly affected
  facade/catalog tests
- Modify: this plan and
  `docs/evidensbaseret-genimport/reimport-writer-153-rehearsal.md` only with
  observed evidence

**Interfaces:**

- Consumes Task 8's generic v2 kernel, one-version 1939 facade, two-track
  terminal migration fixture and exact ACL matrix.
- Produces the complete generic RPC surface, server-bound name-completion
  apply gateway, collision-safe name inserts, closed typed profile config,
  complete routine-body parity and exact terminal result/source-record
  integrity.

- [ ] **Step 1: Specify the missing generic RPC contract RED**

  Add behavior-first SQL assertions for these exact generic signatures:

  ```text
  public.red_apply_reimport_canonical_delta(uuid,text,jsonb)
  public.red_lock_reimport_name_completion(text,bigint,text)
  public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)
  ```

  The lock must reject invalid or missing `(source_id, profile_id)` before
  mutation; the authorizer must reject a mismatched complete `(source_id,
  profile_id, profile_sha256)` triple. The dedicated canonical-delta entry point
  must take the shared v2 lock, validate the open batch/profile writer boundary
  and then fail closed with
  `REIMPORT_WRITER_CANONICAL_DELTA_UNSUPPORTED`; it must never call the
  name-completion writer. The exact legacy wrapper must pin the seeded 1939
  identity and translate that error to
  `REIMPORT_1939_CANONICAL_DELTA_UNSUPPORTED` without changing rows. Extend the
  signature-specific ACL tests: the generic canonical-delta and lock are
  authenticated-only, the generic name-completion authorizer is
  service-role-only, and all three remain denied to `PUBLIC`/`anon`.

  Run the focused SQL tests and record the expected missing-signature or wrong-
  behavior failures before changing DDL.

- [ ] **Step 2: Implement the RPCs and server-bind apply-mode name completion**

  Implement the three signatures identically in fresh and migration DDL,
  update exact revokes/grants and all 1939 wrappers, and remove the facade's
  synthetic `{}` call into `red_apply_reimport_name_completion`. In the R DBI
  gateway, return the complete server `authorization` object from
  `red_preflight_reimport_name_completion`; validate its database name, system
  identifier and exact source/profile/hash against both the supplied
  authorization and manifest before `red_begin_reimport_name_completion`.
  Add an apply-mode test in which the supplied object is locally valid but the
  server returns a different source/profile/hash; require rollback and
  `REIMPORT_NAME_COMPLETION_AUTHORIZATION_REQUIRED` or the narrower existing
  database/profile mismatch token before any child batch is created. Run the R
  and SQL tests to GREEN.

- [ ] **Step 3: Close and consume `writer_config` RED/GREEN**

  Add fresh/migration tests proving a profile is rejected unless
  `writer_config` is a JSON object with exactly these eight keys and no others:

  ```text
  run_key_prefix, schema_version, extractor_version, rendition_key,
  rendition_kind, rendition_metadata, observation_extraction_method,
  citation_label_template
  ```

  The seven scalar values must be non-empty strings; `rendition_metadata` must
  be an object; `citation_label_template` must contain the literal
  `{page_from}` exactly once and must not contain another brace placeholder.
  Implement one immutable private validator used by the table constraint in
  fresh and migration DDL. Build the inserted citation label from that template
  by replacing `{page_from}` with the authorized payload's integer page value,
  and assert both profiles get their own literal label. Reject missing, extra,
  null, wrong-typed and malformed-template fixtures before a profile row is
  stored. Re-run profile, name-completion, migration and parity tests.

- [ ] **Step 4: Prove collision-safe cross-profile writes RED/GREEN**

  Extend the disposable two-connection integration test from lock acquisition
  to two real, authorized name-completion writes for different profiles. Hold
  the first transaction across ID allocation, start the second, release the
  first, then require both commits, distinct `fact.id`/`citation.id`, complete
  result/event rows and no duplicate-key error. First observe the current
  `max(id)+1` collision. Then serialize only the shared legacy ID-allocation
  critical section with a dedicated transaction advisory lock, acquired after
  the global contract and source/profile locks and before computing both IDs.
  Record the intentional trade-off: profile lifecycle state remains
  independent, while the two global integer-ID allocations are briefly
  serialized because those public tables do not own safe sequences. Do not
  broaden this task into identity-column conversion or unrelated writer
  changes.

- [ ] **Step 5: Complete routine parity and terminal source-record integrity**

  Replace the hand-selected routine subset in
  `inspect-reimport-writer-catalog.sql` with the complete explicitly versioned
  #153 kernel/facade set, including at least
  `private.lock_reimport_writer`,
  `private.validate_reimport_authorization_payload`,
  `private.validate_reimport_writer_config`,
  `private.reject_reimport_writer_mutation`, and
  `public.red_preflight_reimport_authorization`, plus the new generic RPCs.
  Keep signature, owner, definer, search path, ACL and
  `pg_get_functiondef` SHA-256 in the byte-comparable receipt. Require exact
  fresh/clean-upgraded parity.

  In the terminal migration guard, require each name-completion result's
  `source_record_id` to resolve to the source parent's exact
  `person_create` event `source_record_key` and source. Add a fixture that
  changes only `result.source_record_id` to a different valid record while all
  other references remain valid; the migration must fail and roll back. Run
  both approved historical terminal topologies, every invalid topology,
  atomicity and clean-upgrade parity to GREEN.

- [ ] **Step 6: Review, verify and close Task 8/9**

  Self-review the full Task 9 diff against all six SOL findings and every
  relevant §3-§5 specification clause. Run the complete disposable fresh-v2,
  clean-upgraded-v2, historical-v1 terminal migration, C3 fail-closed, ACL,
  DBI, R/testthat, catalog and build gates with all five PG variables. Obtain a
  fresh task-scoped Codex review, critically fix valid findings and rerun the
  affected evidence. Then obtain one GPT-5.6-Sol xhigh independent read-only
  re-review because this correction materially changes the public RPC,
  concurrency and migration-integrity risk profile. Update only observed
  rehearsal evidence, mark Task 8 Step 6 and this step complete, and commit.
  No production action, push, merge or production GO.

### Task 10: Resolve the final independent review findings

**Authority:** Required bounded correction under Task 9 Step 6 after the
independent 2026-09-02 SOL review returned NO-GO. This task corrects the
generic writer's allocation, provenance, page-validation and immediate ACL
contracts. It does not change C3, #152 policy, production authority or add a
real edition.

**Files:**

- Modify: `schema.sql`, `db-migrations.sql`, `db-rls.sql`
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R` and
  `.claude/skills/daa-extract/scripts/apply_name_completion_helpers.R`
- Modify: focused generic writer, name-completion, concurrency, reversal,
  catalog/parity and R tests only
- Modify: this plan and the #153 rehearsal only with observed evidence

- [ ] **Step 1: Add RED coverage for every valid finding**

  Prove that name completion cannot collide with an ordinary writer, that a
  reversed append-only result's IDs are never reused, that same-source
  profiles cannot reuse incompatible extraction-run or rendition provenance,
  and that missing, null or non-integer `page_evidence.page_from` is rejected
  before writes. Add focused R coverage for JSON object key-order independence
  and SQL coverage for the immediate preflight ACL.

- [ ] **Step 2: Implement the bounded corrections**

  Bring clean-slate `fact.id` and `citation.id` into parity with the already
  migrated `GENERATED BY DEFAULT AS IDENTITY` contract. Allocate all four
  name-completion result IDs through their identity defaults and `RETURNING`,
  so sequences rather than a private advisory lock provide non-reusing global
  identity. Validate every immutable extraction-run/rendition field after
  `ON CONFLICT`; use existing mapped generic drift errors. Validate positive
  integer page evidence in SQL and R. Compare named R objects by field rather
  than incoming JSON order, and apply the exact generic preflight revoke/grant
  in schema and migration DDL immediately.

- [ ] **Step 3: Re-run focused and full disposable verification**

  Run the focused RED/GREEN suites, two-profile and ordinary-writer
  concurrency, reversal non-reuse, same-source profile drift, R gateways,
  fresh-v2, clean-upgraded-v2, historical-v1 terminal/atomicity/C3,
  fresh/upgraded catalog parity, ACL/db-verify, all relevant testthat/core/web
  tests and build. Use all five PG variables for every local disposable DB.

- [ ] **Step 4: Review and close**

  Self-review the fix range, then obtain one scoped read-only GPT-5.6-Sol
  re-review of the valid findings. Critically resolve only regressions caused
  by this fix, update observed evidence, mark the completed plan steps and
  commit. No production action, push, merge, deploy or production GO.
