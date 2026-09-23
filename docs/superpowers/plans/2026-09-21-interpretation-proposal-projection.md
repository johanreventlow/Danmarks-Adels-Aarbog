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
- Receipt row hashes use a dedicated operation-specific canonical JSON function and closed JSON projections, never composite-row text or implicit session formatting. Every timestamp and numeric/decimal row field is rendered as a normalized string, JSON structural counts/versions are signed 64-bit integers, and every key/list order is fixed with `COLLATE "C"`. The receiver's generic proposal-manifest value validator has the stricter JSON-safe integer range `[-9007199254740991,9007199254740991]` because values can cross the R/jsonlite transport boundary.
- The current 4.3b builder is the deliberately narrower producer: `partition_record_claims()` accepts only its live predicate-specific string or `{raw: string, normalized?: string}` value forms, so numeric claim values are rejected before key derivation and manifest emission. The generic manifest/R/SQL canonicalizer nevertheless normalizes accepted numeric JSON tokens: `1`, `1.0`, and `1e0` are one semantic value at that receiver boundary. Do not silently broaden the 4.3b claim-value contract in #196.
- One `interpretation_proposal` element/event is permitted per `(source_id, source_record_key)` in a batch. Multiple claims inside that one event may cite the same clause and are folded to one disposition; a cross-event shared-clause chain is not a supported success path.
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
| `.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py` / `test_build_43b_proposal_manifest.py` | Strictly decode cached raw JSON, retain the existing 4.3b claim-value boundary before key derivation, and prove unsupported numeric claim values never reach manifest emission. |
| `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-projection-rehearsal.md` | Sanitized evidence receipt. |

### Task 1: Lock the closed projection and manifest schemas

**Files:**
- Create: `.claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py`
- Create: `.claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py`
- Modify: `.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py`
- Modify: `.claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py`

**Interfaces:**
- Consumes: 4.4 manifest schema from `build_43b_proposal_manifest.py`.
- Produces: `compute_manifest_sha256(manifest: dict[str, Any]) -> str` using the already-shipped manifest JSON convention; `normalize_interpretation_proposal_claim_value(value: Any) -> Any`, `proposal_canonical_bytes(value: Any) -> bytes`, and `proposal_canonical_sha256(value: Any) -> str` for the new SQL-shared restricted byte contract; `target_sha256(identity: dict[str, Any]) -> str`; `compare_apply(manifest: Any, before: Any, after: Any, expected_target_sha256: str) -> dict[str, Any]`; `compare_replay(after: Any, replayed: Any, replay_authorization_id: str, expected_target_sha256: str) -> dict[str, Any]`; and `ProjectionError(code, details)`. The generic manifest/R/SQL path has no second numeric canonicalizer. The builder retains its narrower, existing value contract.

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

Add pure normalizer/manifest-validator fixtures for `1`, `1.0`, and `1e0`, including nested arrays and objects. Assert that normalization emits base-10 integer JSON values and gives all three spellings identical canonical bytes and value hash; strings such as `"1.0"` remain strings. Pin that fractional, non-finite, `±2^53`, and recursively out-of-range numeric tokens fail before any receiver-side manifest is written. Separately add a builder integration fixture using a legal live predicate value (`string` or `{raw: string, normalized?: string}`): assert its key and emission are unchanged, and assert that numeric scalar/nested value forms are rejected by `partition_record_claims()` before `interpretation_key_input`, deduplication, or manifest emission. This plan adds no accepted nested numeric field to 4.3b.

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

Validate positive integer source id, lowercase 64-character hashes, unique operation and claim ids, `interpretation_proposals == len(operations)`, zeros for the other count keys, and closed nested keys. The receiver-side manifest validator permits strings, objects, arrays, booleans, null, and mathematical integers only in the inclusive JSON-safe range `[-9007199254740991,9007199254740991]`; this is deliberately narrower than signed bigint so R can parse and serialize every accepted token exactly. Load the operation-hash view with a strict JSON decoder using `parse_float=Decimal` and `parse_int=int`; its `parse_constant` rejects NaN/Infinity, its pairs hook rejects duplicate object keys, and it rejects U+0000 and lone surrogates before PostgreSQL `jsonb` parsing. Normalize every accepted integral `Decimal`/integer token—including `1.0`, `1e0`, and `-0`—to the same base-10 integer value and bytes; reject non-integral, `±2^53`, signed-bigint boundary, and other out-of-range claim values. Booleans are not numbers. Make `build_43b_proposal_manifest.py` use the strict decoder for cached raw JSON, then retain `partition_record_claims()` as the authoritative 4.3b value boundary before `interpretation_key_input`, `sete_noegler` deduplication, `claim_id` assignment, and manifest emission; it must reject rather than normalize numeric claim values. The already-shipped manifest-content hash remains on its existing JSON convention and is computed from its own ordinary parse, so this new operation receipt contract cannot change historical manifest hashes. Derive expected claim rows keyed by `(element_id, claim_id)` and links keyed by `(element_id, claim_id, link_ordinal)`; keep only `value_sha256` after validation.

- [ ] **Step 4: Run the schema tests**

Run the Step 2 command and the existing builder test file. Expected: PASS.

```bash
/usr/bin/python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py \
  .claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py -q
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/compare_interpretation_proposal_projection.py \
  .claude/skills/daa-extract/scripts/test_compare_interpretation_proposal_projection.py \
  .claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py \
  .claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py
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
- Produces: one JSON line matching `PROJECTION_SCHEMA`; target SQL produces one `database_target_sha256` cell. Owner and anon partials each carry internal `snapshot_sha256 = encode(extensions.digest(convert_to(txid_current_snapshot()::text,'UTF8'),'sha256'),'hex')`, which the driver requires equal and removes before emitting the external projection.

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

Static assertions are only a source-inventory guard. Task 5 must execute the effective guards against PostgreSQL and must turn red when any asserted guard is removed or moved into a comment/dead branch.

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
- Produces `private.interpretation_proposal_key_material(bigint,text,text,jsonb,jsonb) -> text`, `private.interpretation_proposal_key_material_sha256(bigint,text,text,jsonb,jsonb) -> text`, and `private.interpretation_proposal_key(bigint,text,text,jsonb,jsonb) -> uuid`. The material helper is the sole byte authority for the already-shipped key-version-1 input; the hash helper hashes exactly `convert_to(material,'UTF8')`, and the UUID helper passes exactly that same material to `private.deterministic_uuid`.
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

Pin the canonical bytes, not just the hash: UTF-8; object keys ordered by Unicode scalar value, which is byte-equivalent to UTF-8 `COLLATE "C"` for valid scalar sequences; no Unicode normalization; escape quote and backslash, use the short JSON escapes for U+0008/U+0009/U+000A/U+000C/U+000D, and lowercase `\u00xx` for the other allowed control characters; raw non-ASCII; literals `true`, `false`, and `null`; arrays preserve order. U+0000 is rejected at the raw-file boundary because PostgreSQL `jsonb` cannot carry it. The general receipt canonicalizer may contain mathematical signed-64-bit integers for DB-produced structural fields. SQL requires `trunc(value::numeric)=value::numeric`, checks those bounds, and emits `(value::numeric)::bigint::text`; Python parses numeric tokens with `Decimal`, applies the same checks, and emits the same integer text. The proposal manifest/writer adds the stricter JSON-safe bound for every recursively nested claim-value number before hashing or writing. Thus `1`, `1.0`, and `1e0` all canonicalize to `1`, and every spelling of negative zero canonicalizes to `0`; non-integral values are rejected. Row helpers serialize confidence and all other genuine decimals as normalized strings rather than numeric JSON tokens.

Run the same fixtures under at least two session time zones and available collations and require byte-identical receipt JSON and hashes. Add SQL-to-Python golden vectors for composed/decomposed Danish text, astral Unicode, quotes, backslashes, every allowed control escape, rejected U+0000/lone-surrogate/duplicate-key/non-finite input at the file boundary, nulls, booleans, signed 64-bit integer boundaries for internal canonicalization, nested keys, `1`/`1.0`/`1e0` equivalence, `-0 → 0`, and rejected fractional/out-of-range values. Separately prove the proposal-input validator accepts `±(2^53-1)` and rejects `±2^53`, signed-bigint min/max, and nested occurrences. Require exact SQL canonical text bytes to equal Python `proposal_canonical_bytes` and exact SHA equality. Do not modify the existing manifest hashing, generic SQL canonical helper, or any historical profile hash contract.

- [ ] **Step 2: Run the focused SQL and verify it fails**

```bash
psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
```

Expected: `PROPOSAL_RESULT_RECEIPT_INVALID`.

- [ ] **Step 3: Implement the closed receipt projections and build the receipt inside the writer transaction**

Move the current interpretation-key calculation into `private.interpretation_proposal_key_material`; for strings and already canonical object values it remains byte-for-byte the existing `interpretation-key-1` formula. The generic receiver normalizes accepted numeric `jsonb` values before this formula, and SQL verifies that the received `jsonb` is already normalized before it calls the helper; the narrower 4.3b builder never emits numeric claim values. Make both key-material SHA and UUID helpers call it, and call the UUID helper from the writer. Add golden SQL fixtures proving the material text, its SHA, and UUID equal the pre-change inline expression for string and object values, plus synthetic receiver-boundary cross-language fixtures proving `1`/`1.0`/`1e0` produce one key. Projection/state recompute through the same helpers. The receipt's `key_material_sha256` must equal the SHA helper and must never be synthesized from `claim_id` or from the new receipt canonicalizer. Compute receipt value hashes separately:

Before computing either key material or value hash, recursively validate every numeric token in the authorized claim value as integral and within `[-9007199254740991,9007199254740991]`. This SQL check is independent of the Python/R checks and runs on the exact `jsonb` value received by the writer; any fractional or wider value fails before the first interpretation/link/disposition write.

```sql
v_receipt_value_sha :=
  private.interpretation_proposal_canonical_json_sha256(v_claim->'value');
```

Accumulate claims in a temp table keyed by `claim_id` and observations keyed by interpretation/link ordinal. Enforce one proposal element/event per source record in the authorized payload and reject duplicate record-key/element pairs before `begin_batch`; the live foreign-clause predicate means another record cannot share its clause. Within that one event, collapse multiple claim citations for one observation to one disposition using the documented `afventer_identitet` precedence. For each affected clause, lock and require exactly one current trigger-valid machine disposition before the first write, then record that exact `before` receipt and one `written` receipt. After inserting dispositions, construct:

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

Before appending a proposal disposition, read and lock the current disposition. Reject absence, a human `decided_by_kind`, and machine evidence that does not satisfy the live trigger vocabulary (`manifest_sha256` plus a UUID `batch_id` or `extraction_run_id`). This makes reversal restore one exact pre-batch state without inventing absence or overwriting editorial judgment. Add one-element fixtures with multiple claims citing one clause and prove they create exactly one disposition receipt; separately prove a duplicate source-record element is rejected before a second event and a foreign-record citation is rejected by the live writer.

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
- Modify: `.claude/skills/daa-extract/scripts/apply_reimport_helpers.R`
- Modify: `tests/testthat/test-apply-reimport.R`
- Create: `tests/integration/test-reimport-interpretation-proposal.R`

**Interfaces:**
- Consumes: disposable database with current schema/RLS/migrations and Tasks 1-3.
- Extends `execute_reimport` with `authorization_policy = c("auto_dry_run", "external")`, default `auto_dry_run`; `external` requires a supplied authorization for dry-run and apply and never calls the gateway authorizer.
- Extends `execute_reimport` with `transaction_entry = NULL`, invoked exactly once immediately **after** the existing `gateway$call("advisory_lock", manifest$source)` returns and before preflight, authorization, or batch calls. The default is a no-op, so existing callers are unchanged. This preserves the live generic order `daa-reimport:* gateway lock → SQL shared narrative lock` while letting the following reversal plan insert its exclusive contract-lock between them.
- Extends `new_reimport_dbi_gateway` with an optional transaction-local setup callback invoked once by `begin`, after `DBI::dbBegin` and before returning; the default is `NULL`, so existing callers are unchanged. This is the integration seam for literal `SET LOCAL ROLE authenticated`, local claims, and actor verification, not a session-scoped role switch.
- Extends `validate_reimport_manifest` for proposal claims with the same recursive JSON-safe integer bound and makes the proposal gateway serialize only through one tested helper using `jsonlite::toJSON(..., auto_unbox=TRUE, null="null", digits=17)`. Repository-pinned jsonlite must emit the exact base-10 token for both safe endpoints; scientific or rounded output is a test failure. No already-parsed proposal payload may bypass that validator/serializer pair.
- Produces: terminal marker `interpretation_proposal integration OK`.

- [ ] **Step 1: Build the synthetic fixture and red stop**

Reuse source record, accepted anchor, parent observation, clauses, primary mention, persona, profile, actor, and authorization patterns from `test-reimport-clause-evidence.R`. Use a nonce for source id, record key, hashes, and profile. Create two claims; both cite clause 1, and the `other` claim also cites clause 2. Execute—not merely grep—the owner and anon guards, then stop with `RED: apply flow not implemented`.

First add focused red executor tests: external policy without authorization fails for both modes; supplied external authorization bypasses `gateway$call("authorize")`; default policy preserves every existing call sequence; the gateway transaction-setup callback runs exactly once inside `begin` after `DBI::dbBegin`; the executor transaction-entry runs exactly once after the completed `advisory_lock` and before preflight; either callback failing rolls back and prevents later operations; and SQL capture rejects session-scoped `SET ROLE authenticated`. These tests belong to this first sequential delivery—the later reversal and production-wrapper plans consume, rather than introduce, external authorization and transaction-entry.

Add an actual R→PostgreSQL receiver-boundary matrix, not only Python fixtures: use synthetic manifests that are explicitly outside the 4.3b builder success path, parse them through repository-pinned jsonlite without simplification, pass nested accepted values `±(2^53-1)`, `1.0`, `1e0`, and `-0` through the `digits=17` proposal serializer and bound SQL parameter, and assert the serializer's exact token bytes, received `jsonb`, and SQL/Python value hashes. Explicitly assert that the positive/negative safe endpoints serialize as full base-10 integers and not exponent notation. Require `±2^53`, signed-bigint min/max, fractional, exponent-overflow, and nested variants to fail in R before any gateway call; mutation-removing the R bound, serializer precision, or SQL bound must turn a test red. Separately retain the builder-boundary fixture proving it rejects numeric claim values before serialization.

Add disposable-database negative schedules that invoke the effective SQL bodies with: a READ WRITE transaction; READ COMMITTED READ ONLY; anon SQL as owner; owner SQL after `SET LOCAL ROLE anon`; and owner/anon partials in separate sessions with a committed mutation between them. Require the named read-only/isolation/role/snapshot code and no projection output. Run source mutants with each effective guard predicate removed while leaving its comment/literal intact; at least one runtime case must fail its expected rejection, proving static string presence alone cannot pass the gate.

- [ ] **Step 2: Run and verify the red stop**

```bash
Rscript tests/integration/test-reimport-interpretation-proposal.R
```

Expected: FAIL at the explicit red marker.

- [ ] **Step 3: Implement the complete sequence**

```r
before_counts <- proposal_counts(con, source_id)
dry_authorization <- authorize_as_service_role(manifest, preview_sha)
dry <- execute_reimport(
  manifest, preview_sha, "dry-run", gateway(),
  list(id = dry_authorization), authorization_policy = "external")
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
          identical(proposal_counts(con, source_id), before_counts))
before_path <- write_private("before.json", projection())
apply_authorization <- authorize_as_service_role(manifest, preview_sha)
applied <- execute_reimport(
  manifest, preview_sha, "apply", gateway(),
  list(id = apply_authorization), authorization_policy = "external")
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))
after_text <- projection()
after_path <- write_private("after.json", after_text)
matched <- run_comparator(before_path, after_path, "apply-match.json")
stopifnot(matched$status == 0L,
          grepl('"status": "match"', matched$out, fixed = TRUE))
replay <- execute_reimport(
  manifest, preview_sha, "apply", gateway(),
  list(id = replay_authorization <- authorize_as_service_role(manifest, preview_sha)),
  authorization_policy = "external")
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
Rscript -e 'testthat::test_file("tests/testthat/test-apply-reimport.R")'
git add .claude/skills/daa-extract/scripts/apply_reimport_helpers.R tests/testthat/test-apply-reimport.R tests/integration/test-reimport-interpretation-proposal.R
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

For each matrix leg, create a fresh database and run `tests/sql/evidence-promotion-bootstrap.sql` first so `anon`, `authenticated`, `service_role`, `auth.uid()`, Storage shims, `pgcrypto`, and schemas exist. As owner, create two dedicated non-superuser roles: `daa_proposal_ci NOINHERIT LOGIN` with membership only in `authenticated`, and `daa_proposal_authorizer_ci NOINHERIT LOGIN` with membership only in `service_role`. Grant only `daa_proposal_ci` the minimum `pg_control_system()` target-identity capability if it is not already executable, and assert both logins are non-superuser with their exact explicit memberships. Load `schema.sql`, `db-rls.sql`, and two idempotent `db-migrations.sql` passes in the selected ordering, finish with `db-rls.sql`, then run `tests/sql/test-interpretation-proposal.sql` and `tests/sql/run-db-verify-disposable.sql`, which installs `extensions.dblink` and its required fixtures. The later reversal delivery owns the production-like service-role table-grant fixture and its final-ACL gate; projection completion does not depend on a file from that later plan.

Issue the dry-run, apply, and replay authorizations on short-lived connections as `daa_proposal_authorizer_ci`: `BEGIN; SET LOCAL ROLE service_role;` set transaction-local actor claims, verify the expected actor, call only `red_authorize_reimport`, commit, disconnect, and pass only the resulting UUID into the operation flow. The operation connection must never hold service-role membership. As `daa_proposal_ci`, execute the exact lifecycle `BEGIN; SET LOCAL ROLE authenticated;` plus transaction-local claims and actor verification through the new transaction-setup callback, then test both `COMMIT` and `ROLLBACK`; after each, require `current_user=session_user` and absent transaction-local claims. Source/SQL-capture tests reject session-scoped `SET ROLE authenticated`. Run the R integration through this login, with `DAA_REIMPORT_TEST_ROLE=authenticated`, so neither connection ownership nor superuser bypass can satisfy the client-surface assertions. Add negative integration cases for a nonmember login, a superuser login, an operation login attempting authorization, and an authorizer login attempting proposal DML. Finally invoke:

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
