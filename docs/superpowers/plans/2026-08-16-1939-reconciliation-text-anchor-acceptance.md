# 1939 Text-Anchor Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the hash-bound 1939 reconciliation decision layer with an explicit, fail-closed `accept_text_anchor` action for individually PDF-reviewed `text_anchor_review` records.

**Architecture:** Keep `apply_reconciliation_decisions_1939.py` as the only decision interpreter. Route the new action into the existing `decision_by_old` ownership and output pipeline, but admit it only for one current `text_anchor_review` record with `evidence_method == "unique_exact_narrative"` and exactly one existing target. Reuse the common global injectivity check and report recomputation; do not alter candidate discovery or auto-create decisions.

**Tech Stack:** Python 3.9, stdlib `json`/`hashlib`/`collections`, pytest, deterministic hash-bound JSON artifacts.

## Global Constraints

- The decision object has exactly `baseline_record_key`, `decision_kind`, and `selected_new_record_key`.
- The source baseline record must currently be `text_anchor_review` with literal evidence method `unique_exact_narrative` and exactly one match.
- The selected new key must equal that match, exist in `new_entries`, be selected at most once in the batch, and have no unresolved competing baseline owner.
- Every mismatch, extra field, missing record, ownership collision, or hash drift raises `DecisionError`; there is no fallback by name, page, normalized text, or geometry.
- A valid result preserves the old `record_key`, records `selected_new_record_key`, and uses `reconciliation_basis == "human_accepted_text_anchor"` with the existing reviewer and batch provenance.
- Previously accepted boundary changes, structural-context records, and duplicate retirements remain resolved and retain their audit fields.
- Candidate generation, database writes, loaders, identity matching, OCR correction, and automatic approval of the current 50 records are out of scope.

---

### Task 1: Add the explicit text-anchor decision path

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py:15-175`
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py:235-285`
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py:108-181`
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py:228-263`

**Interfaces:**
- Consumes: `apply_decisions(reconciliation: Mapping[str, Any], decisions: Mapping[str, Any], *, reconciliation_sha256: str) -> dict[str, Any]`.
- Adds: `decision_kind == "accept_text_anchor"` with exactly one `selected_new_record_key`.
- Produces: baseline and new dispositions `accepted_carryover`, basis `human_accepted_text_anchor`, explicit selected target, reviewer, and decision batch.

- [ ] **Step 1: Add focused fixture builders**

After `decision_document`, add a fixture that is intrinsically a valid text-anchor review rather than mutating an unrelated split fixture inside every test:

```python
def text_anchor_reconciliation():
    source = reconciliation()
    source["baseline_entries"] = [source["baseline_entries"][0]]
    old = source["baseline_entries"][0]
    old["matches"] = [old["matches"][0]]
    old["disposition"] = "text_anchor_review"
    old["evidence_method"] = "unique_exact_narrative"
    source["new_entries"] = [source["new_entries"][0]]
    source["new_entries"][0]["baseline_record_keys"] = ["old-a"]
    source["new_entries"][0]["disposition"] = "text_anchor_review"
    return source


def text_anchor_decision_document(reconciliation_sha256):
    document = decision_document(reconciliation_sha256)
    document["decisions"] = [{
        "baseline_record_key": "old-a",
        "decision_kind": "accept_text_anchor",
        "selected_new_record_key": "new-a",
    }]
    return document
```

- [ ] **Step 2: Write the failing success test**

Add beside the boundary-acceptance tests:

```python
def test_accepts_exactly_one_human_reviewed_text_anchor():
    source = text_anchor_reconciliation()
    digest = hashlib.sha256(encoded(source)).hexdigest()

    result = apply_decisions(
        source,
        text_anchor_decision_document(digest),
        reconciliation_sha256=digest,
    )

    old = result["baseline_entries"][0]
    assert old["matches"] == [{
        "new_record_key": "new-a",
        "geometry_relation": "new_inside_old",
    }]
    assert old["selected_new_record_key"] == "new-a"
    assert old["disposition"] == "accepted_carryover"
    assert old["reconciliation_basis"] == "human_accepted_text_anchor"
    assert old["reviewed_by"] == "johan-reventlow"
    assert old["decision_batch"] == "batch-1"
    assert result["new_entries"][0]["baseline_record_keys"] == ["old-a"]
    assert result["new_entries"][0]["disposition"] == "accepted_carryover"
```

- [ ] **Step 3: Run the focused test and verify RED**

Run from `.claude/skills/daa-extract/scripts`:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py::test_accepts_exactly_one_human_reviewed_text_anchor
```

Expected: one failure with `DecisionError`, because `accept_text_anchor` currently falls through to the split-review branch.

- [ ] **Step 4: Implement the minimal validated branch**

Insert this branch immediately after the existing `accept_boundary_change` branch so the two actions remain adjacent while their distinct decision kinds keep them independent:

```python
if decision.get("decision_kind") == "accept_text_anchor":
    if set(decision) != {
        "baseline_record_key", "decision_kind", "selected_new_record_key",
    } or old is None or old.get("disposition") != "text_anchor_review":
        raise DecisionError(
            "text-anchor acceptance kræver én eksisterende text-anchor review"
        )
    if old.get("evidence_method") != "unique_exact_narrative":
        raise DecisionError(
            "text-anchor acceptance kræver unique_exact_narrative"
        )
    matches = old.get("matches")
    selected = _text(
        decision.get("selected_new_record_key"), "selected_new_record_key"
    )
    if (not isinstance(matches, list) or len(matches) != 1
            or not isinstance(matches[0], Mapping)
            or matches[0].get("new_record_key") != selected
            or selected not in new_by_key):
        raise DecisionError(
            "text-anchor acceptance kræver præcis ét eksisterende mål"
        )
    if selected in selected_targets:
        raise DecisionError("flere beslutninger vælger samme new_record_key")
    affected_old_keys.add(old_key)
    selected_targets.add(selected)
    decision_by_old[old_key] = (
        decision, selected, "human_accepted_text_anchor",
    )
    continue
```

In the common `choice is not None` output branch, persist the already validated target for every human carryover choice:

```python
output["selected_new_record_key"] = selected
```

Place it after filtering `output["matches"]` and before setting the disposition. This makes the new contract explicit without introducing a second transformation path.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run the command from Step 3. Expected: `1 passed`.

- [ ] **Step 6: Run existing decision tests for immediate regression coverage**

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k 'boundary_change or selected_split_target'
```

Expected: all selected tests pass; the boundary action still rejects `text_anchor_review`, and split selection still uses its existing reconciliation basis.

- [ ] **Step 7: Commit the minimal decision path**

```bash
git add .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "feat: accept reviewed 1939 text anchors"
```

### Task 2: Prove fail-closed drift and global injectivity

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py:235-325`

**Interfaces:**
- Exercises the Task 1 action through public `apply_decisions`; no new production interface.
- Proves the existing `selected_targets` and `original_owners` checks cover the new action.

- [ ] **Step 1: Add a one-variable-at-a-time drift matrix**

Add this parameterized test after the success test:

```python
@pytest.mark.parametrize("mutation", [
    "wrong_disposition",
    "wrong_evidence_method",
    "zero_matches",
    "extra_match",
    "wrong_target",
    "unknown_target",
    "extra_field",
])
def test_text_anchor_acceptance_fails_closed_on_drift(mutation):
    source = text_anchor_reconciliation()
    decision = {
        "baseline_record_key": "old-a",
        "decision_kind": "accept_text_anchor",
        "selected_new_record_key": "new-a",
    }
    if mutation == "wrong_disposition":
        source["baseline_entries"][0]["disposition"] = "boundary_change_review"
    elif mutation == "wrong_evidence_method":
        source["baseline_entries"][0]["evidence_method"] = "geometry_only"
    elif mutation == "zero_matches":
        source["baseline_entries"][0]["matches"] = []
    elif mutation == "extra_match":
        source["baseline_entries"][0]["matches"].append({
            "new_record_key": "new-b", "geometry_relation": "partial_overlap",
        })
    elif mutation == "wrong_target":
        source["new_entries"].append({
            "new_record_key": "new-b",
            "record_kind": "unclassified",
            "source_span": {"char_from": 10, "char_to": 20},
            "baseline_record_keys": [],
            "disposition": "unmatched_new_review",
        })
        decision["selected_new_record_key"] = "new-b"
    elif mutation == "unknown_target":
        decision["selected_new_record_key"] = "missing"
    elif mutation == "extra_field":
        decision["note"] = "looks exact"
    digest = hashlib.sha256(encoded(source)).hexdigest()
    document = text_anchor_decision_document(digest)
    document["decisions"] = [decision]

    with pytest.raises(DecisionError):
        apply_decisions(source, document, reconciliation_sha256=digest)
```

The source digest is recomputed after each source mutation, ensuring every case reaches the intended validation instead of failing only on hash drift.

- [ ] **Step 2: Add same-batch target-reuse coverage**

Create two independent text-anchor baseline records that each have one match to different targets, then make both decisions select `new-a` by changing the second source match and decision target to `new-a`. Call `apply_decisions` and assert `DecisionError`. This reaches `selected_targets` and proves two new decisions cannot claim the same target in one batch.

- [ ] **Step 3: Add unresolved competing-owner coverage**

Start from `text_anchor_reconciliation()`, append a second baseline entry whose sole match is also `new-a` and whose disposition is `merge_review`, update the new entry's input owner list to both keys, and submit only the `old-a` text-anchor decision. Assert `DecisionError` from the post-parse `original_owners` check because the other owner has no resolving decision.

- [ ] **Step 4: Add an explicit hash-drift test for this action**

Build a valid text-anchor decision document from the source digest, mutate one source field afterward, and call `apply_decisions` with the mutated bytes' digest. Assert `DecisionError` because the decision document remains bound to the original reconciliation hash.

- [ ] **Step 5: Run the new safety tests**

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k 'text_anchor'
```

Expected: all text-anchor tests pass. If any case passes unexpectedly, tighten the decision branch rather than weakening the fixture.

- [ ] **Step 6: Run the entire focused module**

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py
```

Expected: the previous 22 tests plus all new tests pass without warnings.

- [ ] **Step 7: Commit the safety proofs**

```bash
git add .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "test: enforce 1939 text-anchor decision integrity"
```

### Task 3: Preserve prior decisions and recompute reports

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py:307-391`

**Interfaces:**
- Exercises sequential calls to `apply_decisions` with a newly computed hash for each immutable reconciliation generation.
- Verifies that common output and report logic preserves resolved history and removes only the accepted text anchor from review counts.

- [ ] **Step 1: Add exact report assertions to the success case**

Extend `test_accepts_exactly_one_human_reviewed_text_anchor`:

```python
assert result["report"]["accepted_carryovers"] == 1
assert result["report"]["baseline_dispositions"] == {
    "accepted_carryover": 1,
}
assert result["report"]["new_dispositions"] == {
    "accepted_carryover": 1,
}
assert result["report"]["remaining_baseline_review"] == 0
assert result["report"]["remaining_new_review"] == 0
assert result["report"]["reconciliation_gate"] == "GO"
```

- [ ] **Step 2: Add a sequential-batch preservation test**

Construct a source containing four disjoint histories:

1. an already `accepted_carryover` boundary record with `reconciliation_basis == "human_accepted_boundary_change"`, `reviewed_by`, and its original `decision_batch`;
2. an `accepted_structural_context` new record with no baseline owner;
3. the canonical and `retired_duplicate` baseline records from `duplicate_reconciliation()`, including canonical key, retirement reason, reviewer, and original batch;
4. one fresh valid text anchor owning a distinct `new-text` target.

Hash this combined source, apply only the new text-anchor decision, and assert all prior disposition and audit fields are unchanged while the fresh record becomes `accepted_carryover`. Also assert the structural record remains ownerless and `accepted_structural_context`, and the duplicate target still has exactly one canonical owner.

- [ ] **Step 3: Verify report counts for the mixed history**

In the same test, derive expected counts from the literal combined fixture and assert the complete `baseline_dispositions`, `new_dispositions`, `accepted_carryovers`, `retired_duplicates`, `remaining_baseline_review`, and `remaining_new_review` values. Do not assert only a decrement: exact dictionaries catch accidental reclassification of prior records.

- [ ] **Step 4: Run the preservation and report tests**

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k 'text_anchor or later_decision_batch or report_recounts'
```

Expected: all selected tests pass, including the pre-existing duplicate-retirement preservation test.

- [ ] **Step 5: Run the full DAA script suite**

From `.claude/skills/daa-extract/scripts`:

```bash
/usr/bin/python3 -m pytest -q
```

Expected: all non-skipped tests pass with no new warnings or failures.

- [ ] **Step 6: Check the exact diff and repository state**

```bash
git diff --check
git status --short
git log -3 --oneline
```

Expected: `git diff --check` is silent; only intentional plan or implementation changes are present; the two implementation commits are visible.

- [ ] **Step 7: Commit any final test-only adjustment**

Run only if Task 3 changed the test file after Task 2's commit:

```bash
git add .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "test: preserve 1939 reconciliation history"
```

### Task 4: Hand off to the source-review batch

**Files:**
- Read: `work/task20-1939-full/source-record-reconciliation-v22.json`
- Future ignored artifact: `work/task20-1939-full/source-record-decisions-text-anchor-v1.json`
- Future ignored artifact: `work/task20-1939-full/source-record-reconciliation-v23.json`
- Future ignored artifact: `work/task20-1939-full/source-record-reconciliation-report-v23.json`

**Interfaces:**
- Consumes only the verified decision capability from Tasks 1-3.
- Does not create a decision until each source record has been checked against its exact Calamari span and PDF context.

- [ ] **Step 1: Confirm the current queue without changing it**

Read v22 and assert its SHA-256, source hashes, unique keys, and exact count of 50 baseline `text_anchor_review` entries. Confirm each candidate still has `evidence_method == "unique_exact_narrative"` and exactly one current match. Any drift stops the batch and requires a refreshed queue inventory.

- [ ] **Step 2: Start the first bounded PDF-review batch**

Select a small contiguous source-page batch from the 50 records, inspect both Calamari text and the rendered PDF, and record OCR discrepancies separately. Clear cases may be self-confirmed under the user's standing instruction; actual hierarchy, ownership, or identity ambiguity remains unresolved and is presented to the user.

- [ ] **Step 3: Create decisions only for verified clear cases**

Write `source-record-decisions-text-anchor-v1.json` with one exact `accept_text_anchor` object per verified clear case and bind it to the exact v22 SHA-256 plus its baseline and Calamari hashes. Do not include uncertain or unreviewed records.

- [ ] **Step 4: Apply the bounded batch to a new generation**

Run:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py \
  work/task20-1939-full/source-record-reconciliation-v22.json \
  --decisions work/task20-1939-full/source-record-decisions-text-anchor-v1.json \
  --out work/task20-1939-full/source-record-reconciliation-v23.json \
  --report-out work/task20-1939-full/source-record-reconciliation-report-v23.json
```

Expected: exit 0; accepted carryovers increase by exactly the number of decisions; text-anchor reviews decrease by the same number; unrelated dispositions and totals remain unchanged; the gate remains `NO-GO` while other reviews remain.

- [ ] **Step 5: Audit before continuing**

Independently verify decision hash binding, selected-target equality, unique ownership, preserved prior decision metadata, exact report deltas, and no disappearance of unreviewed records. Report the reviewed source pages, accepted count, remaining text anchors, OCR notes, and genuine ambiguities before selecting the next batch.
