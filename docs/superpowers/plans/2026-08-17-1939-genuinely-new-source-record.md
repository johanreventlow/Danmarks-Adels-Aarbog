# DAA 1939 Genuinely-New Source-Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one fail-closed decision that accepts a visually verified, ownerless 1939 source record without creating or identifying a person, then materialize the first 12 reviewed records as v33.

**Architecture:** Extend the existing hash-bound reconciliation interpreter with a new-entry-only `accept_genuinely_new` branch processed before baseline-key parsing. Preserve accepted ownerless records across later batches, record human provenance on the new-entry only, and produce exclusive v33 artifacts from the exact v32 input.

**Tech Stack:** Python 3.9, pytest, JSON reconciliation artifacts, Calamari OCR, visual PDF evidence already recorded in Task 4 checkpoint 1.

## Global Constraints

- Work only in `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport` on `feat/evidensbaseret-genimport`.
- Implement `docs/superpowers/specs/2026-08-17-1939-genuinely-new-source-record-design.md` exactly.
- Preserve every v32 decision and all prior artifacts; write only new exclusive decision/v33/report paths.
- Bind decisions to v32 SHA-256 `cc9aaf4926411b3d11cff6f26de9cafdef26479855765a323091a898c70cbc2d`, baseline SHA-256 `eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0`, and Calamari SHA-256 `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.
- Fail closed on missing or extra fields, unknown or reused keys, stale spans or hashes, any forward/reverse owner, existing human metadata, wrong disposition/kind/reason, and later-batch metadata loss.
- The decision accepts a source record only. Do not create or identify a person; do not modify the database, `load_daa.R`, canonical people, identity decisions, raw OCR, source PDFs, or production import paths.
- Generated `work/` artifacts and SDD reports remain ignored/uncommitted. Commit only the focused interpreter and tests.

---

### Task 1: Implement and apply `accept_genuinely_new`

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- Create: `work/task20-1939-full/source-record-decisions-genuinely-new-v1.json`
- Create: `work/task20-1939-full/source-record-reconciliation-v33.json`
- Create: `work/task20-1939-full/source-record-reconciliation-report-v33.json`
- Create: `work/task20-1939-full/genuinely-new-batch-v1-report.md`

**Interfaces:**
- Consumes: exact v32 bytes and the 12 source records visually verified in `.superpowers/sdd/2026-08-16-1939-reconciliation-finish/task-4-report.md`.
- Produces: `accepted_genuinely_new_source_record` new-entry dispositions with `acceptance_basis: "human_verified_genuinely_new_source_record"`, `reviewed_by`, and `decision_batch`; no baseline changes.

- [ ] **Step 1: Add the resolved disposition and a minimal test fixture**

Add `"accepted_genuinely_new_source_record"` to `RESOLVED_DISPOSITIONS`. In the test file, add a fixture whose only new-entry is:

```python
{
    "new_record_key": "new-genuine",
    "record_kind": "unclassified",
    "source_span": {"char_from": 10, "char_to": 20},
    "baseline_record_keys": [],
    "disposition": "unmatched_new_review",
}
```

The fixture must retain the existing valid schema/source/report shape and have no baseline match to `new-genuine`.

- [ ] **Step 2: Write the failing success tests**

Add tests using this exact decision shape:

```python
{
    "decision_kind": "accept_genuinely_new",
    "new_record_key": "new-genuine",
    "new_source_span": {"char_from": 10, "char_to": 20},
    "record_kind": "unclassified",
    "reason": "visually_verified_distinct_source_record",
}
```

Assert that one decision:

```python
assert result["baseline_entries"] == source["baseline_entries"]
assert accepted["baseline_record_keys"] == []
assert accepted["disposition"] == "accepted_genuinely_new_source_record"
assert accepted["acceptance_basis"] == "human_verified_genuinely_new_source_record"
assert accepted["reviewed_by"] == decisions["reviewed_by"]
assert accepted["decision_batch"] == decisions["decision_batch"]
assert result["report"]["remaining_new_review"] == 0
assert result["report"]["reconciliation_gate"] == "GO"
```

Add a second success test with two distinct ownerless targets to prove that a batch can accept multiple records without a synthetic baseline key.

- [ ] **Step 3: Run the success tests and observe RED**

Run from `.claude/skills/daa-extract/scripts`:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k genuinely_new
```

Expected: failure because the current loop requires `baseline_record_key` and has no genuinely-new output handling.

- [ ] **Step 4: Write the failing rejection and preservation tests**

Parameterize mutations that must raise `DecisionError`:

```python
(
    {"new_record_key": "missing"},
    {"new_source_span": {"char_from": 10, "char_to": 21}},
    {"new_source_span": {"char_from": 20, "char_to": 20}},
    {"record_kind": "structural_context"},
    {"reason": "name_match"},
    {"extra": True},
)
```

Add separate cases for a declared owner, a hidden forward owner, malformed or duplicate reverse owners, `accepted_structural_context`, an existing `human_annotation`, existing `acceptance_basis`, duplicate decisions for one new key, target reuse alongside another decision kind, and stale reconciliation/baseline/Calamari hashes. Add a later-batch test that first accepts `new-genuine`, then applies an unrelated valid decision and asserts the genuinely-new disposition and all three provenance fields are byte-semantically preserved.

- [ ] **Step 5: Run the rejection/preservation tests and observe RED**

Run:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k genuinely_new
```

Expected: the new negative tests fail because the branch and preservation rule do not yet exist.

- [ ] **Step 6: Implement the minimal decision branch**

Before extracting `baseline_record_key` in the decision loop, branch on `decision_kind == "accept_genuinely_new"`. Require the exact field set:

```python
{
    "decision_kind", "new_record_key", "new_source_span",
    "record_kind", "reason",
}
```

Validate `record_kind == "unclassified"`, `reason == "visually_verified_distinct_source_record"`, the exact `_span(...)`, target existence, `disposition == "unmatched_new_review"`, `baseline_record_keys == []`, `original_owners[target] == []`, and absence of `human_annotation`, `acceptance_basis`, `reviewed_by`, and `decision_batch`. Reject a target already present in `selected_targets` or any new-entry decision map. Store the target in `genuinely_new_acceptances` and `selected_targets`, then continue without reading a baseline key.

In new-entry materialization, use this ordering:

```python
if key in genuinely_new_acceptances:
    output["disposition"] = "accepted_genuinely_new_source_record"
    output["acceptance_basis"] = "human_verified_genuinely_new_source_record"
    output["reviewed_by"] = reviewed_by
    output["decision_batch"] = decision_batch
elif entry.get("disposition") == "accepted_genuinely_new_source_record":
    output["disposition"] = "accepted_genuinely_new_source_record"
elif not old_keys:
    output["disposition"] = (
        "accepted_structural_context"
        if entry.get("record_kind") == "structural_context"
        else "unmatched_new_review"
    )
```

Do not create a match, owner, baseline entry, person identifier, or database payload.

- [ ] **Step 7: Run focused RED-to-GREEN verification**

Run:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k genuinely_new
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py
```

Expected: all genuinely-new tests and the complete interpreter test file pass.

- [ ] **Step 8: Create the exact v1 decision batch**

Create a schema `1.0` decision document with the three exact source hashes from Global Constraints, `reviewed_by: "codex-assisted:johan-reventlow"`, a unique `decision_batch`, and one decision per tuple below, in this order:

```python
(
    ("record-341212a9-54ea-45cf-84e8-f2f16b404011", 2463, 2490),
    ("record-e63debca-6fb4-456e-9b11-90a8676d98b8", 6654, 7824),
    ("record-c0e8f5ad-1b06-4b7e-aea5-5aaf7738f968", 7824, 8464),
    ("record-9db9004f-d6a7-4b98-bd0f-f1f90ba770d8", 8542, 9666),
    ("record-6fe0fbac-d360-4f26-a531-3e0aa62fcbdb", 9666, 9877),
    ("record-3766faae-ae21-412a-8cfb-745a19ac77f0", 17706, 17915),
    ("record-bce01922-5e9e-44ee-a55f-03a895df489d", 18819, 20769),
    ("record-4ba8b3b2-a4d4-40e6-b4f9-1a0aaf8b4cfa", 20769, 20944),
    ("record-3c9644c0-ac4f-4e6a-8043-0ff99bbc5554", 20968, 21003),
    ("record-d790ab87-566c-40a5-80c8-079607941d75", 21003, 21036),
    ("record-d5770de3-06e8-4cc2-8802-36bc59e7e862", 21036, 21099),
    ("record-0bde9cda-dc25-465f-b05c-82e1552791bd", 21099, 21207),
)
```

Every decision uses `record_kind: "unclassified"` and `reason: "visually_verified_distinct_source_record"`.

- [ ] **Step 9: Apply v1 directly to v32 and audit v33**

Use the interpreter CLI with exclusive v33 output paths. Audit independently that:

```python
assert changed_baseline_keys == set()
assert changed_new_keys == set(EXACT_TWELVE_KEYS)
assert report["accepted_carryovers"] == 145
assert report["remaining_baseline_review"] == 47
assert report["remaining_new_review"] == 78
assert report["new_dispositions"]["accepted_genuinely_new_source_record"] == 12
assert report["retired_duplicates"] == 1
assert report["retired_fragments"] == 1
assert report["reconciliation_gate"] == "NO-GO"
```

Also prove zero owners for all 12, exact source spans, complete provenance, deep preservation of the other 580 new objects and all 546 baseline objects, embedded/standalone report identity, unchanged protected hashes, unchanged v32 bytes, and literal Calamari substrings recorded in the checkpoint report.

- [ ] **Step 10: Run the full verification suite**

From `.claude/skills/daa-extract/scripts`, run:

```bash
/usr/bin/python3 -m pytest -q
git diff --check
```

Record focused and full counts, v33/report hashes, exact changed sets, and any concern in `work/task20-1939-full/genuinely-new-batch-v1-report.md`.

- [ ] **Step 11: Self-review and commit only tracked implementation**

Confirm `git status --short` lists only the interpreter and its test as tracked changes; all generated work artifacts remain ignored. Review the diff for closed-schema validation, later-batch preservation, absence of person/database behavior, and exact error paths. Then commit:

```bash
git add .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "feat(1939): accept genuinely new source records"
```
