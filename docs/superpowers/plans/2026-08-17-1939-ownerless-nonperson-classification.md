# DAA 1939 Ownerless Non-Person Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve one structural narrative and two annotated cross-references without creating owners or people, then materialize v46.

**Architecture:** Add two closed new-entry-only decisions before baseline-key parsing. Preserve existing cross-reference annotation provenance, add explicit resolution metadata, validate both human classification forms on later batches, and keep machine-derived structural context backward compatible.

**Tech Stack:** Python 3.9, pytest, JSON reconciliation artifacts, source-bound PDF/Calamari evidence.

## Global Constraints

- Work only in `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport` on `feat/evidensbaseret-genimport`.
- Implement `docs/superpowers/specs/2026-08-17-1939-ownerless-nonperson-classification-design.md` exactly.
- Bind to v45 SHA `249d7e3ed158ee831845d0faac361366c60db9d2b9e08312886b99654fc6a342`, baseline SHA `eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0`, and Calamari SHA `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.
- Preserve prior artifacts and write exclusive v46 paths. Fail closed on owner, span, annotation, provenance, reuse, shape or hash drift.
- No baseline, person, identity, database, OCR, PDF or production-import mutation.
- Commit only interpreter and tests; work artifacts remain ignored.

---

### Task 1: Implement and apply the two non-person decisions

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- Create: `work/task20-1939-full/source-record-decisions-nonperson-classification-v1.json`
- Create: `work/task20-1939-full/source-record-reconciliation-v46.json`
- Create: `work/task20-1939-full/source-record-reconciliation-report-v46.json`
- Create: `work/task20-1939-full/nonperson-classification-v1-report.md`

**Interfaces:**
- Consumes: exact v45 and the three visually reviewed records in Task 4 checkpoints 4–5.
- Produces: two `accepted_cross_reference` and one human-classified `accepted_structural_context`, all ownerless.

- [ ] **Step 1: Add test fixtures only**

Add one ownerless unmatched unclassified record with no human metadata for the
structural path. Add another with this exact pre-existing annotation:

```python
{
    "new_record_key": "new-crossref",
    "record_kind": "cross_reference",
    "person_creation": "forbidden_without_separate_evidence",
}
```

and old `reviewed_by`/`decision_batch`. Do not alter production code.

- [ ] **Step 2: Write success tests and observe RED**

Use exact decisions:

```python
{"decision_kind": "accept_structural_context",
 "new_record_key": "new-structural",
 "new_source_span": {"char_from": 10, "char_to": 20},
 "reason": "human_verified_structural_narrative"}

{"decision_kind": "resolve_annotated_cross_reference",
 "new_record_key": "new-crossref",
 "new_source_span": {"char_from": 30, "char_to": 40},
 "reason": "human_verified_cross_reference"}
```

Assert exact record kinds, dispositions, classification bases, original
cross-reference annotation/reviewer/batch, new resolution fields, zero owners,
unchanged baselines and resolved counts. Add a mixed two-decision batch test.
Run:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k nonperson_classification
```

Expected: RED because both decisions are unsupported.

- [ ] **Step 3: Add negative and later-history tests, then observe RED**

For both kinds cover unknown/reused keys, extra/missing fields, wrong reason,
stale/invalid span and three stale hashes, wrong disposition/kind, declared or
hidden owner, and existing conflicting metadata. For cross-reference cover
every annotation field, key mismatch and missing/empty/wrong-type old
reviewer/batch. For structural cover any annotation/reviewer/batch/basis.

After a valid classification, apply an unrelated valid decision and assert
deep preservation. Parameterize malformed later history: wrong disposition,
kind, owner, basis, annotation, original reviewer/batch, resolution fields for
cross-reference; wrong disposition/kind/owner/basis/reviewer/batch or added
annotation for human structural context. Machine structural records without
classification basis must remain compatible.

Run the focused command again and record the additional RED failures.

- [ ] **Step 4: Implement minimal closed branches and historical validation**

Add `accepted_cross_reference` to resolved dispositions. Process both decision
kinds before extracting `baseline_record_key`. Require exact four-field shapes,
exact reasons, exact target spans, ownerlessness and metadata preconditions;
reserve targets in the common selected-target set.

Materialize only the fields in the design. In a pre-decision history pass,
validate every `accepted_cross_reference` and every structural record with
`classification_basis == "human_verified_structural_context"`. Do not impose
new requirements on existing machine-derived structural records.

- [ ] **Step 5: Verify focused and complete interpreter GREEN**

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k nonperson_classification
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py
```

- [ ] **Step 6: Create and apply the exact v1 decision file**

Use the Global Constraint hashes, `reviewed_by: "codex-assisted:johan-reventlow"`,
a unique batch and exactly:

```python
("accept_structural_context", "record-c2eff948-485c-421f-9f41-1a7c8650d8c0", 32503, 33941, "human_verified_structural_narrative")
("resolve_annotated_cross_reference", "record-0df24f62-3f1d-42f1-b863-4f0e443c1ad4", 75906, 75953, "human_verified_cross_reference")
("resolve_annotated_cross_reference", "record-d6346df9-b841-4504-826c-b018ef7da558", 92073, 92121, "human_verified_cross_reference")
```

Apply directly to v45 with exclusive v46/report paths.

- [ ] **Step 7: Audit, full suite and commit**

Independently assert zero baseline changes and exactly three new changes; zero
owners; annotation preservation; exact classification/resolution fields; deep
preservation of 589 other new records; report identity; protected hashes; old
artifacts unchanged; counts `6` baseline unresolved, `5` unmatched new,
`6` structural, `2` cross-reference and `NO-GO`.

Run:

```bash
/usr/bin/python3 -m pytest -q
git diff --check
```

Write full evidence to the work report. Commit only interpreter/tests:

```bash
git add .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "feat(1939): classify ownerless non-person records"
```
