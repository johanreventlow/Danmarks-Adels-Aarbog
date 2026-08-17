# DAA 1939 Spanless-Baseline Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt twelve visually recovered ownerless 1939 source records to their spanless baseline records while preserving the earlier genuinely-new decisions as embedded provenance.

**Architecture:** Add one closed `adopt_genuinely_new_target` decision to the hash-bound reconciliation interpreter. The decision synthesizes one baseline match, transfers the target from genuinely-new to carryover, embeds its prior acceptance metadata, and validates the full two-sided adoption graph on every later batch.

**Tech Stack:** Python 3.9, pytest, JSON reconciliation artifacts, Calamari OCR, source-bound PDF evidence from Task 4 checkpoint 10.

## Global Constraints

- Work only in `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport` on `feat/evidensbaseret-genimport`.
- Implement `docs/superpowers/specs/2026-08-17-1939-spanless-baseline-adoption-design.md` exactly.
- Preserve all v41 decisions and prior artifacts; write only new exclusive decision/v42/report paths.
- Bind decisions to v41 SHA-256 `59398f7a7f2fe615c83243ce3209ba3d74d11e3a88001fd2edabf142beefe4ae`, baseline SHA-256 `eb52ee25c02866ce4b095a3c53610fea49913c3c87941fed58d984d0bab9f8f0`, and Calamari SHA-256 `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.
- Fail closed on any baseline span, wrong unresolved reason, stale target span/hash, hidden/declared owner, malformed prior genuinely-new acceptance, reused key, inconsistent later-batch adoption graph, or unexpected field.
- Preserve the absence of baseline `source_span`; never infer or write a baseline span.
- Do not create or identify people and do not modify database paths, `load_daa.R`, canonical people, identity decisions, raw OCR, source PDFs, or production import paths.
- Generated `work/` artifacts and SDD reports remain ignored/uncommitted. Commit only focused interpreter and tests.

---

### Task 1: Implement and apply `adopt_genuinely_new_target`

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- Create: `work/task20-1939-full/source-record-decisions-spanless-adoption-v1.json`
- Create: `work/task20-1939-full/source-record-reconciliation-v42.json`
- Create: `work/task20-1939-full/source-record-reconciliation-report-v42.json`
- Create: `work/task20-1939-full/spanless-adoption-batch-v1-report.md`

**Interfaces:**
- Consumes: exact v41 bytes and the twelve source-bound mappings in `.superpowers/sdd/2026-08-16-1939-reconciliation-finish/task-4-report.md` checkpoint 10.
- Produces: one `human_recovered_spanless_baseline` match per baseline, one owner per target, `human_adopted_spanless_baseline` bases, and a lossless `prior_genuinely_new_acceptance` object on each target.

- [ ] **Step 1: Add test fixtures only**

Create a fixture with one spanless baseline:

```python
{
    "baseline_record_key": "old-spanless",
    "name": "Recovered Person",
    "matches": [],
    "unresolved_reason": "narrative_not_exact",
    "disposition": "unresolved",
}
```

and one ownerless target:

```python
{
    "new_record_key": "new-genuine",
    "record_kind": "unclassified",
    "source_span": {"char_from": 10, "char_to": 20},
    "baseline_record_keys": [],
    "disposition": "accepted_genuinely_new_source_record",
    "acceptance_basis": "human_verified_genuinely_new_source_record",
    "reviewed_by": "old-reviewer",
    "decision_batch": "old-batch",
}
```

Do not change production code in this step.

- [ ] **Step 2: Write failing success tests**

Use the exact decision shape:

```python
{
    "baseline_record_key": "old-spanless",
    "decision_kind": "adopt_genuinely_new_target",
    "selected_new_record_key": "new-genuine",
    "selected_new_source_span": {"char_from": 10, "char_to": 20},
    "reason": "spanless_baseline_exact_source_recovery",
}
```

Assert the baseline has no `source_span`, has exactly this match:

```python
[{"new_record_key": "new-genuine",
  "geometry_relation": "human_recovered_spanless_baseline"}]
```

and has selected target, `accepted_carryover`, basis
`human_adopted_spanless_baseline`, new reviewer/batch, and exact
`spanless_baseline_recovery`. Assert the target has one owner,
`accepted_carryover`, the same new basis/reviewer/batch, no top-level
`acceptance_basis`, and:

```python
{
    "acceptance_basis": "human_verified_genuinely_new_source_record",
    "reviewed_by": "old-reviewer",
    "decision_batch": "old-batch",
}
```

under `prior_genuinely_new_acceptance`. Add a two-pair success test proving
independent batch adoption and resolved report counts.

- [ ] **Step 3: Run success tests and observe RED**

From `.claude/skills/daa-extract/scripts`, run:

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k spanless_adoption
```

Expected: failure because the decision kind is unsupported.

- [ ] **Step 4: Write failing rejection and history tests**

Add negative tests for:

- baseline with a `source_span`, wrong/missing `unresolved_reason`, nonempty
  matches, prior selected key/basis/reviewer/batch/annotation/adoption data;
- target with wrong disposition/kind/span, declared owner, hidden forward
  owner, annotation, existing reconciliation basis/prior adoption, or missing,
  empty, wrong-type, or wrong-value genuine-new acceptance fields;
- missing/extra decision fields, unknown baseline/target, duplicate baseline,
  two baselines adopting one target, wrong reason, stale reconciliation,
  baseline or Calamari hash.

Add a later-batch success test: apply one adoption, then an unrelated valid
decision, and assert both sides of the adoption graph and all prior provenance
are deep-preserved. Add parameterized later-batch failures for removing or
changing every load-bearing field on the adopted baseline and target,
including match geometry/key, selected key, basis, recovery span/reason,
owners, disposition, reviewer/batch, target basis, top-level acceptance basis,
and each `prior_genuinely_new_acceptance` field.

- [ ] **Step 5: Run rejection/history tests and observe RED**

Run the same focused command. Expected: new tests fail because neither the
decision nor historical adoption validator exists.

- [ ] **Step 6: Implement the minimal decision and historical validator**

Add an adoption map keyed by baseline and a reverse map keyed by target. In
the decision loop, require the exact five-field decision shape and all spec
preconditions before reserving both keys in the existing affected/selected
sets.

During baseline materialization, synthesize only the one match and fields
required by the spec; leave `source_span` absent. During new-entry
materialization, first copy the three old genuine-new fields into
`prior_genuinely_new_acceptance`, remove top-level `acceptance_basis`, then set
the new owner/disposition/basis/reviewer/batch.

Before decision parsing on every invocation, validate any historical
`human_adopted_spanless_baseline` graph in both directions. Require one
baseline, one target and exact mutual metadata; reject orphan targets,
duplicate adopters, extra owners, malformed prior acceptance, a reintroduced
top-level `acceptance_basis`, or any partial/mismatched adoption.

- [ ] **Step 7: Run focused and interpreter GREEN verification**

```bash
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py -k spanless_adoption
/usr/bin/python3 -m pytest -q test_apply_reconciliation_decisions_1939.py
```

Expected: all adoption tests and the complete interpreter test file pass.

- [ ] **Step 8: Create the exact v1 decision batch**

Create a schema `1.0` decision document using the three hashes in Global
Constraints, `reviewed_by: "codex-assisted:johan-reventlow"`, a unique batch,
and these tuples in checkpoint order:

```python
(
    ("865eb154-0c1d-42f1-a381-7924ccb83e22", "record-3e58c76d-129b-4960-94d3-221a89339aab", 183862, 183987),
    ("9355e9d5-c821-416e-b58f-4cfb7b829646", "record-779eb4c3-dbfd-4eb1-a315-bcceaf25d19f", 185447, 185495),
    ("2f3e2489-4710-4bef-b753-684da5ef18dc", "record-4a45b83d-6d14-449c-8d38-b679691b0a61", 66386, 66727),
    ("35daa2fd-1e16-4a70-9cae-cac187bc4009", "record-bce01922-5e9e-44ee-a55f-03a895df489d", 18819, 20769),
    ("9ce0947f-7d9a-491b-b6ff-29e56134a8cf", "record-e3fe11ca-7736-4a91-af11-6a2f20acb54a", 29134, 29181),
    ("ca405aec-ee70-42fe-9ddb-e3dac8659ee0", "record-ecf76183-aeab-468c-8430-57cc02434baf", 73908, 73923),
    ("33737547-9893-4fef-aa31-a9a8d0052357", "record-5ecbbc9c-2aff-470f-ad0e-f3f3839a13ac", 71979, 72002),
    ("17bb49a4-b79e-4190-ad36-238c13350f39", "record-7501cb45-5006-481e-9330-be89ec076a2d", 80596, 80650),
    ("ded63308-9e41-4ff9-af38-3917ace2d777", "record-45f4488d-6056-42e3-b605-01fe1766a5de", 114536, 116540),
    ("59bea4a2-01eb-4412-9f00-47fe29f259b8", "record-6c9f1d48-f93d-4d98-a59b-d069e372b878", 117931, 118714),
    ("5e09c377-3eb7-4d9b-bd29-77f9b162ce10", "record-77396a28-2464-458c-a977-086ec7f48984", 129853, 130100),
    ("7016dc5a-a6c2-4a3c-a770-5200d9708c66", "record-1965bc70-dc15-4199-90b4-3561cf91962d", 133979, 134838),
)
```

Every decision uses reason `spanless_baseline_exact_source_recovery`.

- [ ] **Step 9: Apply v1 to v41 and audit v42**

Use exclusive output paths and independently assert:

```python
assert changed_baseline_keys == set(EXACT_TWELVE_BASELINE_KEYS)
assert changed_new_keys == set(EXACT_TWELVE_NEW_KEYS)
assert report["accepted_carryovers"] == 168
assert report["remaining_baseline_review"] == 24
assert report["remaining_new_review"] == 9
assert report["new_dispositions"]["accepted_genuinely_new_source_record"] == 58
assert report["retired_duplicates"] == 1
assert report["retired_fragments"] == 1
assert report["reconciliation_gate"] == "NO-GO"
```

Prove one owner per target, no baseline source spans, exact match/recovery
metadata, lossless prior acceptance, deep preservation of the other 534
baseline and 580 new objects, embedded/standalone report identity, unchanged
v41/protected hashes and literal evidence from checkpoint 10.

- [ ] **Step 10: Run full verification and commit**

Run from the scripts directory:

```bash
/usr/bin/python3 -m pytest -q
git diff --check
```

Write hashes, counts, commands/output and exact audits to
`work/task20-1939-full/spanless-adoption-batch-v1-report.md`. Self-review the
tracked diff for closed schema, bidirectional history validation and absence
of person/database behavior. Commit only:

```bash
git add .claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py .claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py
git commit -m "feat(1939): adopt recovered spanless baselines"
```
