# DAA 1939 v50 Name Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a separately authorized, append-only eight-name completion batch that creates source-bound canonical name facts for the staged DAA 1939 persons while keeping cutover disabled.

**Architecture:** Preserve the committed v1 production batch byte-for-byte. A closed Python manifest compiler and dedicated R orchestrator drive narrow PostgreSQL functions that create eight fact/assertion/citation/conclusion chains in a child batch, journal the generated IDs, regenerate display caches through the existing conclusion trigger, and make reversal/cutover child-aware.

**Tech Stack:** Python 3 standard library and pytest; R with DBI, RPostgres, jsonlite and digest; PostgreSQL 17 PL/pgSQL, RLS and SECURITY DEFINER functions; GitHub Actions PostgreSQL service.

**Spec:** `docs/superpowers/specs/2026-08-18-1939-v50-name-completion-design.md`

## Global Constraints

- The original batch `560c39f8-5c87-4c0d-a768-025d97fa2974`, its authorization and its 313 events remain immutable.
- The production database identity is `postgres` / cluster system identifier `7642734024280108049`; local fixtures use explicit non-production identities.
- Exactly eight names may be completed; no sex, date, relation, family, person-create, external-ID or activation mutation is allowed.
- Each name value, person ID, record key, source persona, source span, page, verbatim text and payload hash is closed and source-bound.
- `person.visning_*` remains derived. Only selected canonical facts may regenerate it.
- The eight persons remain `staged=true`; this plan does not authorize production apply or cutover.
- Unknown keys, changed counts, changed order, duplicate targets, missing provenance or ambiguous ownership fail closed.
- The existing v1 production-manifest compiler and applied artifacts must retain their current bytes and hashes.
- Production SQL is developed test-first. Observe the intended RED before every behavior change.
- No credentials, Vault content or living-person data may enter tracked files, reports or test output.

---

### Task 1: Closed name-completion manifest compiler

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_name_completion_manifest_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_name_completion_manifest_1939_v50.py`

**Interfaces:**
- Consumes: original production manifest JSON, production apply JSON, post-apply audit JSON, and their exact SHA-256 values.
- Produces: `build_manifest(production_manifest, production_apply, post_apply_audit, *, input_hashes) -> dict` with schema `1939-v50-name-completion-manifest-v1` and `artifact_sha(value) -> str`.

- [ ] **Step 1: Write failing compiler tests**

Create literal fixtures for the eight locked bindings and tests that name the breaks they catch:

```python
def test_builds_exact_eight_source_bound_name_operations():
    out = build_manifest(*production_inputs(), input_hashes=production_hashes())
    assert out["schema_version"] == "1939-v50-name-completion-manifest-v1"
    assert out["counts"] == {"name_completions": 8, "operations": 8}
    assert [x["person_id"] for x in out["operations"]] == list(range(1846, 1854))
    assert out["operations"][0]["name"] == "Ditlev"
    assert out["operations"][-1]["name"] == "Margrethe"
    assert out["expected_changes"] == {
        "facts_created": 8, "assertions_created": 8,
        "citations_created": 8, "conclusions_created": 8,
        "persons_created": 0, "persons_activated": 0,
        "relations_changed": 0, "families_changed": 0,
    }

@pytest.mark.parametrize("mutation", [
    "wrong_batch", "wrong_person", "wrong_record", "wrong_name",
    "wrong_page", "wrong_text", "wrong_persona", "duplicate_person",
    "missing_operation", "unknown_field", "reordered_apply_map",
])
def test_rejects_locked_universe_drift(mutation):
    inputs = mutate_production_inputs(mutation)
    with pytest.raises(ManifestError):
        build_manifest(*inputs, input_hashes=hash_inputs(inputs))
```

Also assert two independent subprocess builds with different
`PYTHONHASHSEED` values are byte-identical, and that the CLI refuses an
existing output path.

- [ ] **Step 2: Run the compiler tests and verify RED**

Run:

```bash
cd .claude/skills/daa-extract/scripts
/usr/bin/python3 -m pytest -q test_build_name_completion_manifest_1939_v50.py
```

Expected: collection fails with `ModuleNotFoundError: No module named 'build_name_completion_manifest_1939_v50'`.

- [ ] **Step 3: Implement the minimal closed compiler**

Implement these production constants and entry points:

```python
SCHEMA_VERSION = "1939-v50-name-completion-manifest-v1"
SOURCE_BATCH_ID = "560c39f8-5c87-4c0d-a768-025d97fa2974"
SOURCE_MANIFEST_BYTES_SHA256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
SOURCE_MANIFEST_CONTENT_SHA256 = "8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03"
PRODUCTION_BINDINGS = {
    "record-3766faae-ae21-412a-8cfb-745a19ac77f0": (1846, "Ditlev", 503),
    "record-43d4974a-0532-421d-a3fb-8e7c575a67e7": (1847, "Gerhard (Gherardus de Reventlow)", 506),
    "record-80180a6e-2cc6-4968-81ca-004b6662d8ce": (1848, "Henning", 506),
    "record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422": (1849, "Henning Reventlow", 508),
    "record-8f346104-cf3c-465f-bfa3-efb78be436b2": (1850, "Iven (Ywanus de Reuentlo)", 506),
    "record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58": (1851, "Henning", 508),
    "record-b626f5ff-f2fb-4061-bfce-988dbddec846": (1852, "Henrik", 506),
    "record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d": (1853, "Margrethe", 517),
}

def artifact_sha(value: object) -> str: ...
def canonical_sha(value: object) -> str: ...
def build_manifest(production_manifest, production_apply, post_apply_audit,
                   *, input_hashes: list[str]) -> dict[str, object]: ...
```

Each operation copies source evidence only from the matching original
`person_creates` row, computes the original authorized payload SHA-256 using
canonical JSON, and emits a stable `name-completion:<record_key>` element.
The CLI requires three inputs, three bytehash flags and exclusive `--output`.
There are no production count or binding overrides.

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run the command from Step 2. Expected: all tests pass with no warnings.

- [ ] **Step 5: Prove the old production manifest remains byte-identical**

Re-run the existing production builder test and compare the checked-in ignored
artifact hash:

```bash
/usr/bin/python3 -m pytest -q test_build_production_write_manifest_1939_v50.py
shasum -a 256 ../../../../work/task25-1939-v50-production-writer/production-write-manifest-v1.json
```

Expected artifact hash:
`8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f`.

- [ ] **Step 6: Commit Task 1**

```bash
git add .claude/skills/daa-extract/scripts/build_name_completion_manifest_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_build_name_completion_manifest_1939_v50.py
git commit -m "feat(1939): build staged name completion manifest"
```

---

### Task 2: Dedicated R validator and transaction orchestrator

**Files:**
- Create: `.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_name_completion_1939_v50.R`
- Create: `tests/testthat/test-apply-name-completion-1939-v50.R`

**Interfaces:**
- Consumes: schema-v1 completion manifest, expected manifest bytehash and optional authorization JSON.
- Produces: `validate_name_completion_manifest(x)`, `authorized_name_payloads(x)`, `execute_name_completion(manifest, manifest_sha256, mode, gateway, authorization=NULL)`, and `new_name_completion_dbi_gateway(connection_factory)`.

- [ ] **Step 1: Write the failing R tests**

Use a complete eight-row literal fixture. Test success plus rejection of schema,
hash, order, duplicate person/record, count, expected-change, unknown-field,
`production_authorized`, source-batch and database-identity drift. Test the
transaction call order and rollback after every stage:

```r
result <- execute_name_completion(manifest, manifest_sha, "dry-run", gateway())
stopifnot(identical(result$status, "finalized"), identical(result$committed, FALSE))
stopifnot(identical(log, c("connect", "begin", "advisory_lock", "preflight",
  "begin_batch", rep("name_completion", 8L), "finalize", "rollback")))

for (stage in c("preflight", "begin_batch", "name_completion", "finalize")) {
  g <- failing_gateway(stage)
  stopifnot(inherits(try(execute_name_completion(manifest, manifest_sha,
    "dry-run", g), silent=TRUE), "try-error"))
  stopifnot(tail(g$log(), 1L) == "rollback")
}
```

The public production API must expose no expected-count, binding or database
override parameters.

- [ ] **Step 2: Run the R tests and verify RED**

Run:

```bash
Rscript .claude/skills/daa-extract/scripts/test_apply_name_completion_1939_v50.R
```

Expected: source/import failure because the helpers file does not exist.

- [ ] **Step 3: Implement validator, gateway and CLI**

Implement a closed validator with literal 8/8 counts and the exact production
source batch/content hashes. The transaction sequence is:

```r
call("connect")
call("begin")
call("advisory_lock")
call("preflight", manifest, manifest_sha256)
batch <- call("begin_batch", authorization, manifest, manifest_sha256, mode)
for (op in manifest$operations) call("name_completion", batch, op$element_id, strip_transport(op))
final <- call("finalize", batch)
if (mode == "dry-run") call("rollback") else call("commit")
```

The DBI gateway uses only parameterized calls to the dedicated RPCs. The CLI
requires `--manifest`, `--manifest-sha256`, `--mode`, `--output`, and
`--authorization` only for apply. It rejects an existing output file and emits
no credentials.

- [ ] **Step 4: Run direct and wrapper tests**

```bash
Rscript .claude/skills/daa-extract/scripts/test_apply_name_completion_1939_v50.R
Rscript -e 'testthat::test_file("tests/testthat/test-apply-name-completion-1939-v50.R")'
```

Expected: both commands pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add .claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R \
  .claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R \
  .claude/skills/daa-extract/scripts/test_apply_name_completion_1939_v50.R \
  tests/testthat/test-apply-name-completion-1939-v50.R
git commit -m "feat(1939): orchestrate staged name completion"
```

---

### Task 3: PostgreSQL name-completion contract

**Files:**
- Modify: `schema.sql` immediately after the existing DAA 1939 writer functions.
- Modify: `db-migrations.sql` append-only migration section.
- Modify: `db-rls.sql` beside the existing reimport writer grants/revokes.
- Create: `tests/sql/test-1939-v50-name-completion.sql`

**Interfaces:**
- Consumes: one exact completion manifest authorization and eight closed element payloads.
- Produces: `public.red_lock_1939_v50_name_completion(text)`, `public.red_authorize_1939_v50_name_completion(...)`, `public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)`, `public.red_begin_1939_v50_name_completion(...)`, `public.red_apply_1939_v50_name_completion(...)`, and `public.red_finalize_1939_v50_name_completion(...)`.
- The preflight RPC consumes the authorization id, source-batch id, manifest
  hash and complete element-payload map. It returns the closed nested object
  `{authorization,preflight}`, where `authorization` is read from database
  state as exactly `{authorization_id,database_name,system_identifier}` and
  `preflight` is exactly
  `{valid,database_name,system_identifier,source_batch_id,manifest_sha256}`.

- [ ] **Step 1: Write the failing PostgreSQL behavior test**

Build one complete source production batch/person fixture, then assert that a
completion element creates the four canonical rows and regenerates the cache:

```sql
v_completion_batch := public.red_begin_1939_v50_name_completion(
  v_auth, repeat('1',64), v_source_batch);
PERFORM public.red_apply_1939_v50_name_completion(
  v_completion_batch, 'name-completion:record-fixture', v_payload);
v_result := public.red_finalize_1939_v50_name_completion(v_completion_batch);

ASSERT v_result->>'status' = 'finalized';
ASSERT (SELECT visning_navn FROM public.person WHERE id=v_person) = 'Fixture';
ASSERT (SELECT count(*) FROM public.fact
  WHERE subjekt_type='person' AND subjekt_id=v_person AND faktatype='navn') = 1;
ASSERT (SELECT count(*) FROM public.citation c
  JOIN public.assertion a ON a.id=c.assertion_id
  JOIN public.fact f ON f.id=a.target_id
  WHERE f.subjekt_id=v_person AND c.source_id=3 AND c.side='506'
    AND c.citat_tekst='Fixture source text') = 1;
ASSERT (SELECT count(*) FROM private.reimport_1939_name_completion_result
  WHERE batch_id=v_completion_batch) = 1;
```

Before begin, call the dedicated lock and four-argument preflight RPC and assert
that the returned database-issued authorization envelope and preflight identity
match the disposable database. Add negative blocks for unknown or mismatched
authorization id, database/system identity drift, extra/missing nested return
fields, tampered name/text/page/person/persona/event hash,
non-staged person, existing name fact, missing source link, reused authorization,
wrong actor, expired authorization, ninth element and partial finalize.

- [ ] **Step 2: Run against a disposable PostgreSQL 17 database and verify RED**

```bash
createdb name_completion_1939
psql -X -v ON_ERROR_STOP=1 -d name_completion_1939 -f schema.sql
psql -X -v ON_ERROR_STOP=1 -d name_completion_1939 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -X -v ON_ERROR_STOP=1 -d name_completion_1939 -f tests/sql/test-1939-v50-name-completion.sql
```

Expected: the final command fails because the completion table/functions do
not exist. Drop only this explicitly named disposable database after the test.

- [ ] **Step 3: Add the private result table and authorization state**

Add `name_completion` to the authorization operation constraint and create:

```sql
CREATE TABLE private.reimport_1939_name_completion_result (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES private.reimport_1939_write_batch(id),
  element_id text NOT NULL,
  source_batch_id uuid NOT NULL REFERENCES private.reimport_1939_write_batch(id),
  person_id bigint NOT NULL,
  source_record_id uuid NOT NULL,
  source_persona_id uuid NOT NULL,
  fact_id bigint NOT NULL,
  assertion_id bigint NOT NULL,
  citation_id bigint NOT NULL,
  conclusion_id bigint NOT NULL,
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  result_sha256 text NOT NULL CHECK(result_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(batch_id,element_id),
  UNIQUE(source_batch_id,person_id,source_record_id)
);
```

Enable RLS, add the existing append-only mutation rejection trigger, and revoke
all table privileges from `PUBLIC`, `anon` and `authenticated`.

- [ ] **Step 4: Implement the six narrow functions**

The authorize function verifies current database plus
`(pg_control_system()).system_identifier`, source batch status/hashes, exact
8-counts and exact element object, stores that database identity with the
authorization, and returns the closed authorization envelope. The lock function
acquires the name-completion advisory transaction lock. Preflight accepts the
authorization id and re-derives the complete payload evidence from database
state; it returns the exact nested `{authorization,preflight}` object and cannot
echo caller-supplied database identity. Begin consumes the authorization and
creates one open child batch. Apply:

```sql
PERFORM pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0));
LOCK TABLE public.fact, public.assertion, public.citation, public.conclusion
  IN SHARE ROW EXCLUSIVE MODE;
```

It then validates the closed payload and original event, allocates each legacy
BIGINT id under those locks, inserts fact/assertion/citation/conclusion, records
the generated IDs, appends one `canonical_delta` event, and asserts the derived
cache. Finalize requires exactly eight distinct result links/events and complete
row chains before setting the child batch to `finalized`.

- [ ] **Step 5: Add RLS and function grants**

Revoke all new SECURITY DEFINER functions from `PUBLIC`, `anon` and
`authenticated`. Grant only lock/preflight/begin/apply/finalize to
`authenticated`; keep authorization unavailable to self-service roles,
matching the original writer contract. Preflight must validate the stored
authorization actor and identity before returning its envelope. Use fixed
`search_path=pg_catalog,public,private,extensions` only where `digest()` is
needed.

- [ ] **Step 6: Rebuild and run the SQL test GREEN**

Repeat Step 2 from a newly created empty disposable database. Expected: all SQL
blocks pass. Also run:

```bash
psql -X -v ON_ERROR_STOP=1 -d name_completion_1939 -f tests/sql/test-1939-v50-production-writer.sql
```

Expected: the original writer contract remains green.

- [ ] **Step 7: Commit Task 3**

```bash
git add schema.sql db-migrations.sql db-rls.sql tests/sql/test-1939-v50-name-completion.sql
git commit -m "feat(1939): add source-bound name completion writer"
```

---

### Task 4: Child-aware reversal and fail-closed cutover

**Files:**
- Modify: `schema.sql` existing `red_reverse_1939_v50_reimport` and `red_activate_1939_v50_batch`.
- Modify: `db-migrations.sql` append-only replacements for the same functions.
- Modify: `tests/sql/test-1939-v50-name-completion.sql`

**Interfaces:**
- Consumes: finalized original batch plus zero or one finalized completion child.
- Produces: atomic child cleanup during reversal and mandatory exact completion verification during activation.

- [ ] **Step 1: Add failing reversal and cutover tests**

Test these observable outcomes:

```sql
-- Before completion, activation must fail and leave the person staged.
BEGIN
  PERFORM public.red_activate_1939_v50_batch(v_source_batch,v_cutover_auth);
  RAISE EXCEPTION 'NAMELESS_CUTOVER_ACCEPTED';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='NAMELESS_CUTOVER_ACCEPTED' THEN RAISE; END IF;
END;
ASSERT (SELECT staged FROM public.person WHERE id=v_person);

-- After completion, a rolled-back activation probe reaches the valid branch.
PERFORM public.red_activate_1939_v50_batch(v_source_batch,v_cutover_auth);
ASSERT NOT (SELECT staged FROM public.person WHERE id=v_person);
RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='ROLLBACK_ACTIVATION_PROBE';
```

In separate transactions, mutate citation source/text, conclusion selection,
fact target, cache value and result IDs; each must fail with
`REIMPORT_1939_NAME_COMPLETION_INVALID` and activate zero persons.

For reversal, assert all four canonical rows are removed, source persons become
`reimport_1939_reversed`, the child batch becomes `reversed`, and append-only
events/results remain. Drift in any owned row must reject reversal without
deleting anything.

- [ ] **Step 2: Run the SQL test and verify RED**

Run the Task 3 disposable-database sequence. Expected: the pre-completion
cutover test is erroneously accepted or the child canonical rows survive
reversal.

- [ ] **Step 3: Implement exact cutover verification**

Before the activation update, lock the original batch, eight persons and child
results. Require one finalized child result per original `person_create` event,
then compare all generated rows, authorized names, citations, conclusions and
`visning_navn`. Raise `REIMPORT_1939_NAME_COMPLETION_INVALID` on any mismatch.

- [ ] **Step 4: Implement atomic child-aware reversal**

Before the existing person reversal, validate every completion-owned row. If
all match, delete conclusions, citations, assertions and facts in dependency
order, set child status to `reversed`, then continue the existing reversal.
Keep result links and writer events. Any mismatch raises before the first
delete.

- [ ] **Step 5: Run focused SQL suites GREEN**

Run both SQL files from Task 3 in a fresh disposable database. Expected: pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add schema.sql db-migrations.sql tests/sql/test-1939-v50-name-completion.sql
git commit -m "fix(1939): require completed names before cutover"
```

---

### Task 5: Real PostgreSQL orchestration, rollback, concurrency and CI

**Files:**
- Create: `tests/integration/test-1939-v50-name-completion.R`
- Modify: `.github/workflows/ci.yml` PostgreSQL 17 writer job.

**Interfaces:**
- Consumes: Tasks 1-4 public builder/orchestrator/RPC interfaces.
- Produces: end-to-end proof that dry-run, apply, replay rejection, rollback, RLS, reversal and concurrency work in PostgreSQL 17.

- [ ] **Step 1: Write the failing integration test**

Create one realistic source-batch fixture with eight persons and exact source
provenance. Use the real DBI gateway. Assert:

```r
before <- protected_counts(con)
dry <- execute_name_completion(manifest, sha, "dry-run", gateway())
stopifnot(!dry$committed, identical(protected_counts(con), before))

applied <- execute_name_completion(manifest, sha, "apply", gateway(), auth)
stopifnot(applied$committed, length(applied$result_map) == 8L)
stopifnot(all(fetch_names(con, person_ids) == expected_names))
stopifnot(all(fetch_staged(con, person_ids)))
stopifnot(fetch_completion_counts(con)$events == 8L)
```

Inject failure after elements 1 through 8 and at finalize; each transaction must
leave zero completion rows. Hold a competing fact-table insert transaction and
prove completion waits for the lock or times out without collision. Verify anon
and authenticated cannot read private result rows or self-authorize.

- [ ] **Step 2: Run the integration test and verify RED**

Run it against the Task 3 disposable database. Expected: failure at the first
unimplemented or incorrect orchestration boundary.

- [ ] **Step 3: Make only integration-required corrections**

Correct parameter types, returned result-map shape, lock ordering or rollback
handling exposed by the real test. Do not weaken manifest, authorization,
ownership or count checks.

- [ ] **Step 4: Extend CI**

After the existing writer SQL test, add:

```yaml
- name: Test DAA 1939 name completion SQL
  run: psql -h localhost -U postgres -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-1939-v50-name-completion.sql
- name: Test DAA 1939 name completion integration
  env:
    PGHOST: localhost
    PGPORT: 5432
    PGUSER: postgres
    PGPASSWORD: postgres
    PGDATABASE: writer_1939
  run: Rscript tests/integration/test-1939-v50-name-completion.R
```

- [ ] **Step 5: Run focused SQL/R tests GREEN**

Run the SQL and R commands from Tasks 2-5. Expected: all pass, with the
concurrency test observing blocking/timeout rather than duplicate IDs.

- [ ] **Step 6: Commit Task 5**

```bash
git add tests/integration/test-1939-v50-name-completion.R .github/workflows/ci.yml
git commit -m "test(1939): verify staged name completion in postgres"
```

---

### Task 6: Build the locked real artifact and run restore rehearsals

**Files:**
- Generate ignored: `work/task25-1939-v50-production-writer/production-post-apply-audit.json`
- Generate ignored: `work/task25-1939-v50-production-writer/name-completion-manifest-v1.json`
- Generate ignored: `work/task25-1939-v50-production-writer/name-completion-dry-run-a.json`
- Generate ignored: `work/task25-1939-v50-production-writer/name-completion-dry-run-b.json`
- Generate ignored: `work/task25-1939-v50-production-writer/name-completion-rehearsal-report.md`

**Interfaces:**
- Consumes: the permanent pre-apply backup plus a fresh read-only snapshot of the current staged production state.
- Produces: byte-locked completion manifest, two semantically identical rollback rehearsals and exact protected-state comparison.

- [ ] **Step 1: Materialize a closed post-apply audit artifact read-only**

Query production in `BEGIN READ ONLY`, bind the database/system ID, original
batch/auth/event hashes, eight person rows, external IDs, source records,
personas, narratives, current null name facts/caches and zero cutover auth.
Write only non-secret results to the ignored JSON and hash it.

- [ ] **Step 2: Build the production completion manifest exclusively**

Run the new compiler with the three exact input bytehashes and an absent output
path. Reload it independently and assert schema, content hash, stable order,
8/8 coverage, unique people/records/personas and exact expected changes.

- [ ] **Step 3: Restore disposable rehearsal databases**

Create two explicitly named local databases from fresh copies of the same
staged-state snapshot. Apply the tracked migration/RLS files with
`ON_ERROR_STOP=1`. Verify both have non-production database identities and the
same protected-state hashes before rehearsal.

- [ ] **Step 4: Run two complete rollback/apply/reversal rehearsals**

For A and B: authorize the exact completion payload, execute dry-run and prove
zero persistence; execute apply and audit exact 8x4 canonical rows/caches;
exercise reversal and prove return to the staged pre-completion state. Normalize
only timestamps, authorization UUIDs and batch UUIDs. Person IDs, source keys,
names, canonical row content and counts may not be normalized away.

- [ ] **Step 5: Compare semantics and protected state**

Require A/B semantic equality, complete provenance links, `staged=true`, no
activation, and equality of every pre-existing row outside the exact generated
name fact/assertion/citation/conclusion/result/event sets.

- [ ] **Step 6: Write the ignored rehearsal report**

Record input/output hashes, exact commands, database identities, counts,
rollback/reversal outcomes, credential audit and any concern. Verdict is GO only
for preparing a production review package, never for applying it.

---

### Task 7: Full verification and production review stop

**Files:**
- Create: `docs/superpowers/reviews/1939-v50-name-completion-readiness.md`
- Generate ignored: `work/task25-1939-v50-production-writer/name-completion-production-review.md`

**Interfaces:**
- Consumes: all implementation commits and Task 6 real artifacts.
- Produces: auditable readiness verdict and an exact production authorization request; performs no production write.

- [ ] **Step 1: Run fresh full suites**

```bash
cd .claude/skills/daa-extract/scripts
/usr/bin/python3 -m pytest -q
cd ../../../..
Rscript run-tests.R
```

Then run the PostgreSQL 17 SQL and integration sequences from Tasks 3-5 on a
fresh disposable database. Report focused and full results separately.

- [ ] **Step 2: Run security and artifact audits**

Verify fixed SECURITY DEFINER search paths, explicit revokes, deny-all private
RLS, no caller count overrides, no credential literals, exact git scope,
byte-identical old v1 manifest, completion-manifest hashes and no cutover
authorization artifact.

- [ ] **Step 3: Independently review spec compliance**

Review exact 8/8 coverage, source-binding, authorization reuse/expiry,
rollback points, concurrency, child reversal, cutover drift rejection and the
absence of unrelated canonical mutations. Any P0/P1 or unresolved mismatch is
`NO-GO` and returns to the responsible task's RED→GREEN cycle.

- [ ] **Step 4: Write readiness and production-review reports**

The tracked review records code/test/rehearsal evidence and an honest GO/NO-GO.
The ignored production package records current read-only database identity,
new backup requirement, migration/RLS hashes, completion manifest hash, exact
eight names and exact expected delta.

- [ ] **Step 5: Commit the tracked readiness review**

```bash
git add docs/superpowers/reviews/1939-v50-name-completion-readiness.md
git commit -m "docs(1939): report name completion readiness"
```

- [ ] **Step 6: Stop before production**

Do not create a production authorization and do not invoke the completion
writer. Present the review package and require new approval that explicitly
names database identity, new backup, migration/RLS hashes, completion manifest
hash and exactly one name-completion apply. Cutover remains a later, separate
authorization.

## Final verification checklist

- [ ] Original production manifest SHA-256 remains `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f`.
- [ ] Original batch remains finalized with exactly 305 source-evidence and 8 person-create events.
- [ ] Completion manifest contains exactly eight distinct, source-bound operations.
- [ ] Dry-run and every injected failure leave zero persistent completion rows.
- [ ] Apply rehearsal creates exactly 8 facts, 8 assertions, 8 citations, 8 conclusions and 8 result links.
- [ ] All eight `visning_navn` values match the authorized names; all eight persons remain staged.
- [ ] No relation, family, external-ID, person-create or activation row changes.
- [ ] Reversal is complete when owned rows match and fails before deletion on drift.
- [ ] Cutover rejects missing, incomplete or modified name completion.
- [ ] Full Python/R suites and focused PostgreSQL 17 suites are reported accurately.
- [ ] Production apply and cutover have not been performed.
