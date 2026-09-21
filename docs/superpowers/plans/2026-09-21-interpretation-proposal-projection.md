# Interpretation Proposal Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build issue #196's edition-neutral, read-only projection and database-free comparator for one `interpretation_proposal` batch.

**Architecture:** Four focused SQL files take owner and `anon` views in one repeatable-read, read-only snapshot and emit one closed JSON document containing only identifiers, hashes, counts, statuses, and booleans. The existing writer gains one closed, value-free result receipt per event, and a standalone Python comparator binds that receipt to the manifest and actual rows before returning `match`.

**Tech Stack:** PostgreSQL 17 SQL/psql, Python 3 standard library, pytest, R/DBI/RPostgres/jsonlite, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-20-interpretation-proposal-prod-gate-design.md`

## Global Constraints

- Roadmap mapping: step 4, issues #147/#148, with #196 as the production-gate deliverable.
- Value-chain stage: machine-proposed interpretations immediately before human decision.
- Delivery type: general and edition-neutral; no new permanent `2018-20`- or `1939`-named surface.
- Editorial value: prove the exact proposal delta without exporting source text or claim values.
- Completion proof: synthetic mutation tests plus a disposable-database apply projection that returns `match`.
- Replaced workflow: count-only inspection and the private `44-apply.R` package without reconciliation.
- Do not change or generalize the existing `clause_evidence_projection*` files.
- Output may contain ids, record keys, predicates, hashes, counts, statuses, and booleans; never source text, claim values, names, or narrative bytes.
- Every JSON object has a closed key set. Extra and missing keys fail closed.
- Aggregation uses `COLLATE "C"`; session settings are UTC, `ISO, YMD`, `postgres`, and `extra_float_digits=1`.
- Receipt row hashes use a dedicated operation-specific canonical JSON function and closed JSON projections, never composite-row text or implicit session formatting. Every timestamp and numeric/decimal row field is rendered as a normalized string, JSON structural counts/versions are signed 64-bit integers, and every key/list order is fixed with `COLLATE "C"`.
- Proposal apply refuses to replace an affected clause's current human disposition; only a current machine disposition with trigger-valid machine evidence may be versioned by this workflow.
- The comparator opens no database connection and writes reports mode `0600`.
- No production connection or production mutation is part of this plan.

## Review Focus

- An unknown top-level, operation, claim, citation, projection, or row key fails before comparison.
- Canonical value hashes are comparable without placing values or source text in output or errors.
- A changed foreign interpretation, link, run, disposition, authorization, batch, event, promotion, or canonical/anon row produces a named drift code.
- Multiple claims on one clause create one expected disposition, with `afventer_identitet` taking precedence.
- Owner and `anon` hashes come from the same snapshot; separate-session or writable execution fails in SQL.

---

## File Structure

| File | Responsibility |
|---|---|
| `.claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql` | Owner projection with closed, text-free rows and hashes. |
| `.claude/skills/daa-extract/scripts/interpretation_proposal_anon_projection.sql` | `anon` whole-row hashes in the same snapshot. |
| `.claude/skills/daa-extract/scripts/interpretation_proposal_projection.psql` | Same-snapshot psql driver. |
| `.claude/skills/daa-extract/scripts/interpretation_proposal_target_identity.sql` | Target SHA-256 formula. |
| `.claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py` | Closed validation, derivation, comparison, CLI, private report. |
| `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py` | Synthetic mutation matrix. |
| `schema.sql` / `db-migrations.sql` | Operation-specific canonical JSON/hash and row-receipt helpers plus exact value-free result receipt and receipt hash in proposal events. |
| `db-rls.sql` | No-client-execute ACLs for the private receipt helpers. |
| `db-verify.sql` / `tests/sql/test-interpretation-proposal.sql` | Receipt catalog and row-level contract. |
| `tests/integration/test-reimport-interpretation-proposal.R` | Disposable PostgreSQL dry-run/apply/replay/projection proof. |
| `.github/workflows/ci.yml` | New Python and disposable-database gates. |
| `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-projection-rehearsal.md` | Sanitized evidence receipt. |

### Task 1: Lock the closed projection and manifest schemas

**Files:**
- Create: `.claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py`
- Create: `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py`

**Interfaces:**
- Consumes: 4.4 manifest schema from `build_43b_proposal_manifest.py`.
- Produces: `compute_manifest_sha256(manifest: dict[str, Any]) -> str` using the already-shipped manifest JSON convention; `proposal_canonical_bytes(value: Any) -> bytes` and `proposal_canonical_sha256(value: Any) -> str` for the new SQL-shared restricted byte contract; `target_sha256(identity: dict[str, Any]) -> str`; `compare_apply(manifest: Any, before: Any, after: Any, expected_target_sha256: str) -> dict[str, Any]`; `compare_replay(after: Any, replayed: Any, replay_authorization_id: str, expected_target_sha256: str) -> dict[str, Any]`; and `ProjectionError(code, details)`.

- [ ] **Step 1: Write failing tests for exact schemas**

Create one-record fixtures with two claims, two cited clauses, one run, and one finalized batch. Pin these constants:

```python
PROJECTION_SCHEMA = "daa-interpretation-proposal-projection-v1"
RESULT_SCOPE = "interpretation-proposal-delta-v1"
PROJECTION_KEYS = frozenset({
    "schema_version", "source_id", "database_target_identity",
    "source_records", "source_anchors", "narrative_bindings",
    "narrative_sha256", "persons", "upstream_sha256", "neutral_sha256",
    "anon_sha256", "clauses", "interpretations", "interpretation_links",
    "extraction_runs", "proposal_events", "reversal_events",
    "authorizations", "batches", "promotion_sha256",
})
MANIFEST_TOP_KEYS = frozenset({
    "manifest_content_sha256", "source", "expected_counts",
    "operations", "provenance",
})
OPERATION_KEYS = frozenset({
    "element_id", "dependency_class", "source_record_key",
    "runner_manifest_sha256", "model_version", "prompt_version", "claims",
})
CLAIM_KEYS = frozenset({
    "claim_id", "predicate", "interpretation_kind", "value",
    "confidence", "cited_clauses", "persona_role",
})
CITATION_KEYS = frozenset({"ordinal", "verbatim_sha256"})
```

Mutate one key at every manifest and projection level. Assert `INTERPRETATION_PROJECTION_MANIFEST_INVALID` or `INTERPRETATION_PROJECTION_SHAPE_INVALID` and assert the rejected value is absent from error details.

- [ ] **Step 2: Run tests and verify the missing module fails**

Run:

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   -k 'shape or manifest' -q
```

Expected: collection fails because the comparator module does not exist.

- [ ] **Step 3: Implement canonical hashing and closed validation**

```python
def _canon(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"))

def _manifest_canonical_sha256(value: Any) -> str:
    return hashlib.sha256(_canon(value).encode("utf-8")).hexdigest()

def compute_manifest_sha256(manifest: dict[str, Any]) -> str:
    body = {key: value for key, value in manifest.items()
            if key != "manifest_content_sha256"}
    return _manifest_canonical_sha256(body)

class ProjectionError(ValueError):
    def __init__(self, code: str,
                 details: dict[str, Any] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.details = details or {}
```

Validate positive integer source id, lowercase 64-character hashes, unique operation and claim ids, `interpretation_proposals == len(operations)`, zeros for the other count keys, and closed nested keys. Claim values may contain strings, objects, arrays, booleans, null, and signed 64-bit integers only; reject parsed non-integers, while lexical negative zero normalizes to integer `0` in the JSON data model. Derive expected claim rows keyed by `(element_id, claim_id)` and links keyed by `(element_id, claim_id, link_ordinal)`; keep only `value_sha256` after validation.

- [ ] **Step 4: Run the schema tests**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py
git commit -m "test: lock interpretation proposal projection contract"
```

### Task 2: Implement the same-snapshot SQL projection

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql`
- Create: `.claude/skills/daa-extract/scripts/interpretation_proposal_anon_projection.sql`
- Create: `.claude/skills/daa-extract/scripts/interpretation_proposal_projection.psql`
- Create: `.claude/skills/daa-extract/scripts/interpretation_proposal_target_identity.sql`
- Modify: `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py`

**Interfaces:**
- Consumes: `-v source_id=<positive bigint>` and the live schema.
- Produces: one JSON line matching `PROJECTION_SCHEMA`; target SQL produces one `database_target_sha256` cell.

- [ ] **Step 1: Add failing static SQL contract tests**

Assert these literals and reject raw-value output:

```python
assert "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY" in driver
assert "SET LOCAL ROLE anon" in driver
assert "RESET ROLE" in driver
assert "current_setting('transaction_read_only') <> 'on'" in owner
assert "current_setting('transaction_isolation') <> 'repeatable read'" in owner
assert "current_user <> 'anon'" in anon
for relation in (
    "private.interpretation", "private.interpretation_observation",
    "private.extraction_run", "private.clause_disposition",
    "private.reimport_authorization", "private.reimport_batch",
    "private.reimport_event", "private.interpretation_promotion",
):
    assert relation in owner
for forbidden in ("verbatim_text", "narrative.tekst", "'value', i.value"):
    assert forbidden not in owner
```

Also assert all four deterministic session settings precede both SQL inclusions.

- [ ] **Step 2: Run and verify missing SQL files fail**

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   -k sql_contract -q
```

Expected: `FileNotFoundError` for the new SQL files.

- [ ] **Step 3: Implement owner output groups**

Use CTEs `guard`, `records`, `accepted`, `bound`, `clause_rows`, `interpretation_rows`, `link_rows`, `run_rows`, `proposal_event_rows`, `reversal_event_rows`, `authorization_rows`, `batch_rows`, `upstream`, `neutral`, and `promotion`. Build exactly the keys in `PROJECTION_KEYS`.

Every detailed row exports ids and a SHA-256 produced by the dedicated receipt helper for that relation. It must not hash `row::text`, `to_jsonb(row)` with an open column set, or any session-formatted composite value. Export `private.interpretation_proposal_canonical_json_sha256(i.value) AS value_sha256`, never `i.value`. Event rows expose event metadata plus `payload->'result_receipt'` and its hash; they do not expose the rest of `payload`.

`upstream_sha256` hashes whole rows from `source_record`, `source_record_occurrence`, `source_record_anchor_event`, `source_observation`, `source_mention`, `source_persona`, `source_persona_mention`, `source_persona_identity`, `source_persona_identity_event`, `source_record_placement`, `source_record_placement_decision`, `source_persona_placement`, and `source_persona_placement_decision`. `neutral_sha256` includes the clause projection's canonical/public set and other-source interpretation/link/run/disposition rows. `promotion_sha256` hashes all promotion rule, batch, and promotion rows.

- [ ] **Step 4: Implement anon, driver, and target SQL**

Use the clause projection's eight anon-visible whole-row hashes with `INTERPRETATION_PROJECTION_*` guards. The driver loads both SQL files from `DAA_PROJECTION_SQL_DIR` in one transaction and combines `anon_sha256`. Use this exact target formula:

```sql
SELECT encode(pg_catalog.sha256(convert_to(
  current_database() || E'\n' ||
  encode(pg_catalog.sha256(convert_to(
    (pg_control_system()).system_identifier::text,'UTF8')),'hex'),
  'UTF8')),'hex') AS database_target_sha256;
```

- [ ] **Step 5: Run static tests and commit**

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   -k sql_contract -q
git diff --check
git add .claude/skills/daa-extract/scripts/interpretation_proposal_projection.sql \
  .claude/skills/daa-extract/scripts/interpretation_proposal_anon_projection.sql \
  .claude/skills/daa-extract/scripts/interpretation_proposal_projection.psql \
  .claude/skills/daa-extract/scripts/interpretation_proposal_target_identity.sql \
  .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py
git commit -m "feat: add interpretation proposal projection"
```

Expected: tests PASS and `git diff --check` is empty.

### Task 3: Bind every proposal event to an exact result receipt

**Files:**
- Modify: `tests/sql/test-interpretation-proposal.sql`
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`

**Interfaces:**
- Consumes: one authorized proposal element and rows inserted by `private.write_interpretation_proposal`.
- Produces `private.interpretation_proposal_canonical_json_text(jsonb) -> text` and `private.interpretation_proposal_canonical_json_sha256(jsonb) -> text`. The recursive object-key query uses `ORDER BY key COLLATE "C"`; arrays preserve caller order; scalars use JSONB's JSON representation.
- Produces `private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb) -> uuid`, the sole SQL authority for the existing key algorithm. It deliberately preserves the live `key_version=1`/JSONB-text algorithm; the distinct manifest `claim_id` remains a transport id and is never asserted equal to the DB key.
- Produces `private.interpretation_proposal_interpretation_receipt(private.interpretation) -> jsonb`, `private.interpretation_proposal_link_receipt(private.interpretation_observation) -> jsonb`, and `private.interpretation_proposal_disposition_receipt(private.clause_disposition) -> jsonb` with closed, versioned fields.
- Produces: `payload.result_receipt` schema `interpretation-proposal-result-v1` and `after_sha256 = private.interpretation_proposal_canonical_json_sha256(result_receipt)`.

- [ ] **Step 1: Write failing SQL assertions for the receipt**

After the existing fixture applies one element, select its event and assert this exact shape:

```sql
IF jsonb_typeof(v_event.payload->'result_receipt') <> 'object'
   OR ARRAY(
        SELECT key FROM jsonb_object_keys(v_event.payload->'result_receipt') key
        ORDER BY key COLLATE "C"
      ) IS DISTINCT FROM ARRAY[
        'claims','clause_dispositions','schema_version'
      ]
   OR v_event.payload #>> '{result_receipt,schema_version}'
      <> 'interpretation-proposal-result-v1'
   OR v_event.after_sha256 IS DISTINCT FROM
      private.interpretation_proposal_canonical_json_sha256(
        v_event.payload->'result_receipt') THEN
  RAISE EXCEPTION 'PROPOSAL_RESULT_RECEIPT_INVALID';
END IF;
```

Each claim has exactly `claim_id`, `interpretation_id`, `interpretation_key`, `version`, `value_sha256`, `key_material_sha256`, `row_sha256`, `extraction_run_id`, and `observations`. Each observation has `observation_id`, `clause_ordinal`, `verbatim_sha256`, `evidence_role`, `link_ordinal`, and `row_sha256`. Each clause disposition has exactly `observation_id`, `before`, and `written`; both nested objects contain `version`, `disposition`, and `row_sha256`. Assert sorted unique arrays and exact row hashes.

First lock each helper's exact JSON keys and values. The interpretation helper includes only the immutable identity/version/status/source/persona/kind/predicate/value-hash/schema/derivation/confidence/method/model/prompt/run/supersedes/decision-evidence/actor/time fields used by this operation; the link helper contains only the two row ids, role, ordinal, and UTC created timestamp; the disposition helper contains only observation id, version, disposition, kind, closed evidence, actor, and UTC created timestamp. Timestamp strings use `to_char(value AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`; nullable fields remain JSON null. Hash only these helper results with `private.interpretation_proposal_canonical_json_sha256`.

Pin the canonical bytes, not just the hash: UTF-8; object keys ordered by Unicode scalar value, which is byte-equivalent to UTF-8 `COLLATE "C"` for valid scalar sequences; no Unicode normalization; minimal JSON escaping of quote, backslash, and U+0000–U+001F with lowercase hex; raw non-ASCII; literals `true`, `false`, and `null`; arrays preserve order. Hashed JSON may contain only signed 64-bit integers as numeric tokens. Reject parsed fractions/exponents and canonicalize lexical negative zero as `0`; row helpers serialize confidence and other decimals as normalized strings.

Run the same fixtures under at least two session time zones and available collations and require byte-identical receipt JSON and hashes. Add SQL-to-Python golden vectors for composed/decomposed Danish text, astral Unicode, quotes, backslashes, control characters, nulls, booleans, signed 64-bit integer boundaries, nested keys, rejected `1.0`/`1e0`, and `-0 → 0`. Require exact SQL canonical text bytes to equal Python `proposal_canonical_bytes` and exact SHA equality. Do not modify the existing manifest hashing, generic SQL canonical helper, or any historical profile hash contract.

- [ ] **Step 2: Run the focused SQL and verify it fails**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
```

Expected: `PROPOSAL_RESULT_RECEIPT_INVALID`.

- [ ] **Step 3: Implement the closed receipt projections and build the receipt inside the writer transaction**

Move the current interpretation-key calculation byte-for-byte into `private.interpretation_proposal_key` and call that helper from the writer. Add golden SQL fixtures proving it returns the same UUID as the pre-change inline expression for string and object values; projection/state recompute the key with the same helper. Compute receipt value hashes separately:

```sql
v_receipt_value_sha :=
  private.interpretation_proposal_canonical_json_sha256(v_claim->'value');
```

Accumulate claims in a temp table keyed by `claim_id` and observations keyed by interpretation/link ordinal. For each affected clause, lock and require exactly one current trigger-valid machine disposition before the first write. Record that exact `before` receipt and the newly inserted `written` receipt. If another element in the same batch touches the clause, require a contiguous chain where its `before` equals the preceding event's `written`; never replace the original baseline. After inserting dispositions, construct:

```sql
v_result_receipt := jsonb_build_object(
  'schema_version','interpretation-proposal-result-v1',
  'claims',coalesce((
    SELECT jsonb_agg(receipt ORDER BY claim_id COLLATE "C")
    FROM pg_temp.proposal_claim_receipt
  ),'[]'::jsonb),
  'clause_dispositions',coalesce((
    SELECT jsonb_agg(receipt ORDER BY observation_id::text COLLATE "C")
    FROM pg_temp.proposal_disposition_receipt
  ),'[]'::jsonb)
);
```

Store `result_receipt` alongside the already-authorized payload and run id. Set `after_sha256` only from the receipt. Return `result_receipt_sha256` with the existing counts and run id.

Before appending a proposal disposition, read and lock the current disposition. Reject absence, a human `decided_by_kind`, and machine evidence that does not satisfy the live trigger vocabulary (`manifest_sha256` plus a UUID `batch_id` or `extraction_run_id`). This makes the later reversal able to deduplicate shared clauses and restore the one exact pre-batch state without inventing absence or overwriting editorial judgment. Add a two-element/shared-clause fixture and prove both event receipts form one contiguous chain from the same original baseline.

- [ ] **Step 4: Mirror the function in migrations and verification**

Use `CREATE OR REPLACE FUNCTION` in `db-migrations.sql`. Revoke helper execution from PUBLIC, `anon`, `authenticated`, and `service_role` in both catalog paths. In `db-verify.sql`, verify function existence, exact helper signatures and ACLs, receipt schema, row hashes, cross-time-zone stability, and `after_sha256` equality.

- [ ] **Step 5: Run and commit**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
git diff --check
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-interpretation-proposal.sql
git commit -m "feat: bind proposal events to result receipts"
```

Expected: focused SQL and R tests pass.

### Task 4: Implement apply comparison and mutation coverage

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py`
- Modify: `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py`

**Interfaces:**
- Consumes: manifest, before/after projections, expected target SHA-256.
- Produces: sanitized `match` receipt or stable `INTERPRETATION_PROJECTION_*` error.

- [ ] **Step 1: Write red tests for every drift class**

Parameterize target, source, five neutral lists, every upstream/canonical/anon/promotion hash, and each interpretation, link, run, disposition, event, authorization, and batch field. Include:

```python
def test_two_claims_on_one_clause_write_one_identity_priority_disposition():
    result = compare_apply(manifest(), before(), correctly_applied(), TARGET)
    assert result["counts"]["claims"] == 2
    assert result["counts"]["links"] == 3
    assert result["counts"]["dispositions"] == {
        "afventer_identitet": 2,
    }

def test_error_details_never_echo_value():
    m = manifest()
    secret = m["operations"][0]["claims"][0]["value"]
    after = correctly_applied()
    after["interpretations"][0]["value_sha256"] = H("f")
    with pytest.raises(ProjectionError) as caught:
        compare_apply(m, before(), after, TARGET)
    assert secret not in json.dumps(caught.value.details, ensure_ascii=False)
```

Pin distinct codes for shape, manifest hash, target, source, neutral list, upstream, canonical, anon, promotion, preexisting target, foreign drift, batch binding, receipt, claim, link, run, disposition, and event-history drift.

- [ ] **Step 2: Run and verify apply tests fail**

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   -k 'apply or drift or priority or secret' -q
```

Expected: FAIL because `compare_apply` is incomplete.

- [ ] **Step 3: Implement comparison in fixed order**

```python
def compare_apply(manifest, before, after, expected_target_sha256):
    expected = _validate_manifest(manifest)
    _validate_projection(before)
    _validate_projection(after)
    _compare_source_and_target(
        manifest, before, after, expected_target_sha256)
    _compare_neutral_surfaces(before, after)
    batch = _compare_batch_authorization_and_events(
        manifest, before, after)
    _compare_claims_links_and_run(expected, before, after, batch)
    dispositions = _compare_clause_dispositions(
        expected, before, after, batch)
    return {
        "status": "match",
        "scope": RESULT_SCOPE,
        "source_id": after["source_id"],
        "database_target_sha256": target_sha256(
            after["database_target_identity"]),
        "manifest_content_sha256": manifest["manifest_content_sha256"],
        "batch_id": batch["batch_id"],
        "counts": {
            "elements": len(manifest["operations"]),
            "claims": len(expected.claims),
            "links": len(expected.links),
            "dispositions": dict(sorted(dispositions.items())),
        },
    }
```

Require exactly one new finalized batch, one consumed matching authorization, one proposal event per operation, one run for all events, exact receipt-to-row/hash linkage, and no changed foreign row. Disposition priority is `afventer_identitet` if any claim on the clause has role `other`; otherwise `fortolkning_foreslaaet`.

For each claim, require a one-to-one manifest `claim_id` → event receipt → recomputed SQL-authoritative `interpretation_key` → current row chain. The comparator does not equate `claim_id` with `interpretation_key`; `key_material_sha256` and the projection's database-verified key guard make the mapping explicit.

Implement `compare_replay` separately. It accepts only the exact prior after-projection plus one new consumed replay authorization bound to the same actor/source/profile/manifest/preview/expected counts/authorized payload hash and pointing to the already-finalized batch. It requires zero new batches, events, interpretations, links, runs, dispositions, or any other hash/list change. Any extra authorization or non-authorization delta fails.

- [ ] **Step 4: Add the closed CLI**

Support only:

```text
--mode fresh --manifest PATH --before PATH --after PATH
  --expect-target-sha256 HASH --report PATH
--mode replay --after PATH --replayed PATH --replay-authorization-id UUID
  --expect-target-sha256 HASH --report PATH
--print-manifest-sha256 PATH
```

Refuse an existing report path, write mode `0600`, print only sanitized JSON, and exit 1 with `{status:"no-go",code,details}` for `ProjectionError`.

- [ ] **Step 5: Run all tests and commit**

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py -q
git add .claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py
git commit -m "feat: compare interpretation proposal deltas"
```

Expected: all tests PASS.

### Task 5: Prove dry-run, apply, match, and replay in PostgreSQL

**Files:**
- Create: `tests/integration/test-reimport-interpretation-proposal.R`

**Interfaces:**
- Consumes: disposable database with current schema/RLS/migrations and Tasks 1-3.
- Produces: terminal marker `interpretation_proposal integration OK`.

- [ ] **Step 1: Build the synthetic fixture and red stop**

Reuse source record, accepted anchor, parent observation, clauses, primary mention, persona, profile, actor, and authorization patterns from `test-reimport-clause-evidence.R`. Use a nonce for source id, record key, hashes, and profile. Create two claims; both cite clause 1, and the `other` claim also cites clause 2. Assert both SQL read-only/role guards, then stop with `RED: apply flow not implemented`.

- [ ] **Step 2: Run and verify the red stop**

```bash
Rscript tests/integration/test-reimport-interpretation-proposal.R
```

Expected: FAIL at the explicit red marker.

- [ ] **Step 3: Implement the complete sequence**

```r
before_counts <- proposal_counts(con, source_id)
dry <- execute_reimport(manifest, preview_sha, "dry-run", gateway(), NULL)
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
          identical(proposal_counts(con, source_id), before_counts))
before_path <- write_private("before.json", projection())
applied <- execute_reimport(
  manifest, preview_sha, "apply", gateway(),
  list(id = authorize(manifest, preview_sha)))
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))
after_text <- projection()
after_path <- write_private("after.json", after_text)
matched <- run_comparator(before_path, after_path, "apply-match.json")
stopifnot(matched$status == 0L,
          grepl('"status": "match"', matched$out, fixed = TRUE))
replay <- execute_reimport(
  manifest, preview_sha, "apply", gateway(),
  list(id = replay_authorization <- authorize(manifest, preview_sha)))
stopifnot(identical(replay$status, "already_applied"))
replayed_path <- write_private("replayed.json", projection())
replay_match <- run_replay_comparator(
  after_path, replayed_path, replay_authorization,
  "replay-match.json")
stopifnot(replay_match$status == 0L,
          grepl('"status": "match"', replay_match$out, fixed = TRUE))
```

Mutate one receipt hash in a copied projection and require `INTERPRETATION_PROJECTION_RECEIPT_INVALID`.

- [ ] **Step 4: Run and commit**

```bash
Rscript tests/integration/test-reimport-interpretation-proposal.R
git add tests/integration/test-reimport-interpretation-proposal.R
git commit -m "test: prove interpretation proposal projection"
```

Expected final line: `interpretation_proposal integration OK`.

### Task 6: Wire CI and record evidence

**Files:**
- Modify: `.github/workflows/ci.yml`
- Create: `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-projection-rehearsal.md`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: reproducible CI gates and a sanitized PASS/PARTIAL/BLOCKED ledger.

- [ ] **Step 1: Add CI gates**

Add the Python test beside `test_compare_clause_evidence_projection.py` in the existing `evidence-contract` job.

Add a dedicated `interpretation-proposal-db` job with PostgreSQL 17 and a two-value `catalog_order` matrix (`schema-rls-migrations`, `schema-migrations-rls`). The job installs R through `r-lib/actions/setup-r@v2`, uses `r-lib/actions/setup-r-dependencies@v2` with `extra-packages: any::DBI, any::RPostgres, any::jsonlite, any::digest, any::testthat`, and sets the five explicit `PG*` variables used by the existing DB jobs.

For each matrix leg, create a fresh database and run `tests/sql/evidence-promotion-bootstrap.sql` first so `anon`, `authenticated`, `service_role`, `auth.uid()`, Storage shims, `pgcrypto`, and schemas exist. Load `schema.sql`, `db-rls.sql`, and two idempotent `db-migrations.sql` passes in the selected ordering, finish with `db-rls.sql`, run `tests/sql/test-interpretation-proposal.sql`, and then run `tests/sql/run-db-verify-disposable.sql`, which installs `extensions.dblink` and its required fixtures. Set `DAA_REIMPORT_TEST_ROLE=authenticated` for the R integration so its connection exercises the granted client surface rather than owner bypass. Finally invoke:

```yaml
- run: Rscript tests/integration/test-reimport-interpretation-proposal.R
```

Do not rely on the neighboring `evidence-promotion-db` job's environment: it currently has PostgreSQL order coverage but no R toolchain or packages. Both matrix legs must upload only sanitized logs and must fail if the success marker is absent.

- [ ] **Step 2: Run focused and full verification**

```bash
/usr/bin/python3 -m pytest   .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py   .claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py -q
Rscript run-tests.R
git diff --check
```

Run the integration against both CI database orderings. Expected: Python PASS, R `FAIL 0`, both database runs print the success marker, and no whitespace errors.

- [ ] **Step 3: Write the sanitized receipt**

Record exact commit, catalog ordering, commands, target hashes, manifest hash, batch/authorization ids, counts, and comparator result. Mark unrun gates `BLOCKED`. End with:

```text
Leverance #196-projektion: PASS/PARTIAL/BLOCKED
Produktions-GO: IKKE GIVET
Produktionsmutation: INGEN
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml   docs/evidensbaseret-genimport/proposal-ingest-147-4-4-projection-rehearsal.md
git commit -m "ci: gate interpretation proposal projection"
```
