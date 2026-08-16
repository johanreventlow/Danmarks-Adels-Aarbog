# 1939 Duplicate Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the hash-bound 1939 reconciliation decision layer so a reviewed extraction duplicate remains auditable but cannot own or import a new source record, then apply the five approved decisions.

**Architecture:** Keep `apply_reconciliation_decisions_1939.py` as the only decision interpreter. Add one explicit `retire_duplicate_record` branch beside the existing split-target branch, validate the shared source geometry before mutating the in-memory graph, and recompute ownership from the resulting edges. Persist the human batch as an ignored work artifact and generate a new immutable reconciliation output rather than modifying v4.

**Tech Stack:** Python 3.9, stdlib `json`/`hashlib`/`collections`, pytest, deterministic JSON work artifacts.

## Global Constraints

- The retained and retired baseline keys must exist, differ, share the exact non-empty `source_span`, and match the same declared new record.
- The retired baseline entry remains visible as `retired_duplicate` with its canonical key, reviewer, batch, and reason.
- A `retired_duplicate` owns no new record and must not be importable.
- Decisions remain bound to exact reconciliation, baseline, and Calamari hashes; any drift rejects the whole batch without partial output.
- Names, ordering, and page numbers are not identity evidence.
- No database, canonical-person, or identity-register mutation is in scope.

---

### Task 1: Add fail-closed duplicate retirement

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py`

**Interfaces:**
- Consumes: `apply_decisions(reconciliation: Mapping[str, Any], decisions: Mapping[str, Any], *, reconciliation_sha256: str) -> dict[str, Any]`.
- Produces: support for `decision_kind == "retire_duplicate_record"` with `canonical_baseline_record_key`, `new_record_key`, and `reason == "duplicate_extraction_record"`; output baseline disposition `retired_duplicate`; report field `retired_duplicates`.

- [ ] **Step 1: Write the failing success test**

Add a real fixture-level test whose production mutation is “the decision interpreter has no duplicate-retirement branch”:

```python
def test_retires_duplicate_but_preserves_audit_and_single_owner():
    source = reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = duplicate_decision_document(digest)

    result = apply_decisions(source, document, reconciliation_sha256=digest)

    canonical, retired = result["baseline_entries"]
    assert canonical["disposition"] == "accepted_carryover"
    assert retired["disposition"] == "retired_duplicate"
    assert retired["matches"] == []
    assert retired["canonical_baseline_record_key"] == "old-a"
    assert retired["retirement_reason"] == "duplicate_extraction_record"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-a"]
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"
    assert result["report"]["retired_duplicates"] == 1
```

Use a literal fixture where `old-a` and `old-b` both have source span `0..10`, both match `new-a`, and both initially have `merge_review`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd .claude/skills/daa-extract/scripts
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py::test_retires_duplicate_but_preserves_audit_and_single_owner
```

Expected: FAIL because `retire_duplicate_record` is rejected as an unknown/unsafe decision.

- [ ] **Step 3: Implement the minimal retirement branch**

In `apply_decisions`:

1. Parse split choices and retirement choices into separate validated structures.
2. For a retirement, require literal fields:

```json
{
  "baseline_record_key": "old-b",
  "decision_kind": "retire_duplicate_record",
  "canonical_baseline_record_key": "old-a",
  "new_record_key": "new-a",
  "reason": "duplicate_extraction_record"
}
```

3. Require both entries to have disposition `merge_review`, identical non-empty `source_span`, and exactly one match to `new-a`.
4. Reject reuse of any affected old or new key by a conflicting choice in the same batch.
5. Transform the canonical entry to one `accepted_carryover` edge and the retired entry to no edges plus:

```python
{
    "disposition": "retired_duplicate",
    "canonical_baseline_record_key": canonical_key,
    "retirement_reason": "duplicate_extraction_record",
    "reviewed_by": reviewed_by,
    "decision_batch": decision_batch,
}
```

6. Add `retired_duplicate` to resolved baseline dispositions, never to valid new-record ownership, and add `retired_duplicates` to the report.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2. Expected: `1 passed`.

- [ ] **Step 5: Write failing validation tests**

Add parameterized tests whose named breaks are accepting unsafe geometry or conflicting decisions:

```python
@pytest.mark.parametrize("mutation", [
    "different_source_span",
    "wrong_shared_target",
    "unknown_canonical_key",
    "same_canonical_and_retired_key",
    "conflicting_split_choice",
])
def test_rejects_unproven_or_conflicting_duplicate_retirement(mutation):
    source, document, digest = duplicate_case(mutation)
    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)
```

Each mutation must alter one literal fixture field and recompute the reconciliation digest when the source fixture changes, so the test reaches the intended validation rather than merely tripping hash drift.

- [ ] **Step 6: Run the validation tests and verify RED**

Run:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k 'unproven_or_conflicting'
```

Expected: at least one FAIL showing the missing validation.

- [ ] **Step 7: Add the minimal conflict and geometry validation**

Track all affected baseline keys and selected/retired new targets before transforming entries. Reject duplicates or cross-kind reuse, enforce exact key sets for the retirement action, and validate the literal reason. Do not add name-based or page-based fallback.

- [ ] **Step 8: Run the focused module**

Run:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py
```

Expected: all tests in the module pass with no warnings.

- [ ] **Step 9: Commit the decision-engine change**

```bash
git add .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "feat: retire duplicate 1939 source records"
```

### Task 2: Apply the five approved decisions and audit the new queue

**Files:**
- Create ignored artifact: `work/task20-1939-full/source-record-decisions-hierarchical-v2.json`
- Create ignored artifact: `work/task20-1939-full/source-record-reconciliation-v5.json`
- Create ignored artifact: `work/task20-1939-full/source-record-reconciliation-report-v5.json`

**Interfaces:**
- Consumes: v4 reconciliation bytes and the extended decision schema from Task 1.
- Produces: v5 reconciliation with four accepted split carryovers and one retired duplicate, plus exact report counts and the remaining human-review queue.

- [ ] **Step 1: Confirm exact v4 source and target keys**

Read v4 and assert the approved selections are current candidates:

```python
approved = {
    "a66902ba-5ca2-49a9-b615-96541b381dff": "record-2a1115a8-c0b1-4bb7-a6f7-5d6d29a93c3c",
    "76605302-f2b2-4dac-aadc-ccb5af6e9dc5": "record-97f5179d-6b52-4520-8f28-8bc9f8d4367c",
    "29e1eb62-a709-4cbf-b241-6cff056cd025": "record-02181744-91c0-4e6d-9ae1-347b4314dcb8",
    "33094d44-8619-4dbc-8f02-c0f352255790": "record-c9c5736c-aee7-4578-ac3e-89e8b515bc63",
}
```

Also assert the canonical and retired Ditlev keys both match
`record-3d4ef02c-de19-47e0-b629-2fcc202e9dfb` with identical spans.

- [ ] **Step 2: Create the hash-bound decision document**

Use four `select_carryover_target` decisions and one
`retire_duplicate_record` decision. Annotate Benedicte Margrethe’s rejected
Ditlev target `record-d6346df9-b841-4504-826c-b018ef7da558` as:

```json
{
  "record_kind": "cross_reference",
  "person_creation": "forbidden_without_separate_evidence"
}
```

Bind the document to the exact SHA-256 of v4 and copy its baseline and
Calamari hashes without modification.

- [ ] **Step 3: Generate v5 exclusively**

Run:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py \
  work/task20-1939-full/source-record-reconciliation-v4.json \
  --decisions work/task20-1939-full/source-record-decisions-hierarchical-v2.json \
  --out work/task20-1939-full/source-record-reconciliation-v5.json \
  --report-out work/task20-1939-full/source-record-reconciliation-report-v5.json
```

Expected: exit 0; `applied_decisions` increases by five for this batch;
`retired_duplicates` is one; gate remains `NO-GO` while unrelated reviews
remain.

- [ ] **Step 4: Audit all five outcomes independently**

Load v5 in a short read-only assertion script and verify:

- each selected split baseline owns only its approved new key;
- the four selected entries are `accepted_carryover`;
- the Benedicte-rejected Ditlev line carries the cross-reference annotation;
- canonical Ditlev alone owns the shared new key;
- the duplicate Ditlev has no matches and is `retired_duplicate` with the
  canonical key and reason;
- totals remain 546 baseline and 587 new records.

- [ ] **Step 5: Run the full DAA script suite**

Run:

```bash
cd .claude/skills/daa-extract/scripts
/usr/bin/python3 -m pytest -q
```

Expected: all non-skipped tests pass, including the new retirement tests.

- [ ] **Step 6: Check repository state and report the next batch**

Run:

```bash
git diff --check
git status --short
git log -3 --oneline
```

Inspect the remaining `merge_review`, `boundary_change_review`, and
`text_anchor_review` entries using exact source spans and PDF context. Present
the next five genuinely ambiguous decisions with book-page numbers and a
specific recommendation; do not bulk-approve unresolved entries.
