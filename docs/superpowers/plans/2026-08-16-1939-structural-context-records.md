# 1939 Structural Context Records Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve five approved generation references as separate, non-person 1939 source records and rebuild reconciliation against the corrected geometry.

**Architecture:** Extend the existing boundary materializer with an optional, exact-span `strukturelle_henvisninger` contract. Generate a derived boundary export from the immutable reviewed export, retain historical ledger entries while requiring every active acceptance, and rebuild/review reconciliation without name-based carryover.

**Tech Stack:** Python 3.9, pytest, deterministic JSON and SHA-256.

## Global Constraints

- Calamari SHA-256 remains `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37`.
- The original boundary export SHA-256 is `5fca128211319594cef4b0a3d9d91376486474d79dbb1cac602af6641e0e11da` and is never overwritten.
- Structural records use `record_kind: structural_context` and may not create people.
- Unknown, partial, overlapping, omitted, or non-cut-bounded structural spans fail closed.
- Historical ledger entries remain stored but cannot own current materialized records.
- No database or identity-register writes.

---

### Task 1: Materialize exact structural records

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_materialize_graenseflade_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/materialize_graenseflade_1939.py`

**Interfaces:**
- Consumes: optional export field `strukturelle_henvisninger: list[{char_from, char_to, record_kind, person_creation}]`.
- Produces: matching records with `record_kind == "structural_context"` and report field `structural_record_candidates`.

- [ ] Add a failing test with cuts `[0, 8, 18]`, structural span `8..18`, and literal assertions that the second record is structural and the report count is one.
- [ ] Run `/usr/bin/python3 -m pytest -q test_materialize_graenseflade_1939.py -k structural` and verify failure because the field is ignored.
- [ ] Parse and validate structural spans in `_validated_geometry`; require exact keys and literal values `structural_context`/`forbidden`.
- [ ] Assign record kind by exact `record_span`; after the interval loop require every declared structural span to have matched exactly once.
- [ ] Add parameterized failing-then-passing tests for overlap with omission, partial cut interval, duplicate span, overlap between structural spans, and legacy export without the field.
- [ ] Run the complete materializer test module and commit:

```bash
git add .claude/skills/daa-extract/scripts/materialize_graenseflade_1939.py .claude/skills/daa-extract/scripts/test_materialize_graenseflade_1939.py
git commit -m "feat: materialize 1939 structural context records"
```

### Task 2: Permit inactive append-only ledger history in reconciliation

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/test_reconcile_source_records_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/reconcile_source_records_1939.py`

**Interfaces:**
- Consumes: ledger whose acceptance IDs are a superset of the active materialization.
- Produces: new records only for active acceptance IDs; missing active IDs remain an error.

- [ ] Add a failing test that appends one valid historical ledger entry absent from materialization and expects reconciliation to remain identical.
- [ ] Verify RED: current `_new_records` rejects unequal acceptance sets.
- [ ] Replace equality with `acceptance_ids <= set(ledger_by_acceptance)`; retain duplicate identity and missing-active checks.
- [ ] Add a test proving a missing active acceptance still fails.
- [ ] Run the reconciliation tests and commit:

```bash
git add .claude/skills/daa-extract/scripts/reconcile_source_records_1939.py .claude/skills/daa-extract/scripts/test_reconcile_source_records_1939.py
git commit -m "fix: allow inactive 1939 ledger history"
```

### Task 3: Derive geometry and rebuild artifacts

**Files:**
- Create: `.claude/skills/daa-extract/scripts/amend_structural_context_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_amend_structural_context_1939.py`
- Create ignored outputs under `work/task20-1939-full/` for amended export, materialization, ledger, bundle, reconciliation, decisions, and report.

**Interfaces:**
- Consumes: exact original-export bytes and a fixed decision document containing the five approved source spans and cut/omission replacements.
- Produces: a new exclusive JSON export with `derived_from` provenance and deterministic geometry.

- [ ] Write a failing artifact-level test proving original-hash drift, missing expected cut/omission, or overlapping approved spans rejects without output.
- [ ] Implement a generic `amend_export(data, decisions, *, export_sha256)` that removes only declared cuts/omissions, adds only declared cuts, and emits sorted structural references plus `derived_from`.
- [ ] Test success with literal before/after geometry and verify the input object remains unchanged.
- [ ] Generate the amended export with spans `11945..11955`, `38259..38284`, `38949..38977`, `39498..39526`, and `67129..67153`.
- [ ] Run `materialize_graenseflade_1939.py` with the prior ledger as `--ledger-in`, producing new exclusive artifacts.
- [ ] Rebuild raw reconciliation from the original baseline/evidence and inspect every prior human-approved key against exact targets.
- [ ] Create one new hash-bound decision batch that revalidates all prior choices and marks each structural target `person_creation: forbidden_without_separate_evidence`; do not guess if any target changed unexpectedly.
- [ ] Apply the decisions, audit exact geometry/record kinds/owner graph/counts, then run `/usr/bin/python3 -m pytest -q` from the scripts directory.
- [ ] Commit only reusable scripts/tests; keep work artifacts ignored, and present the next five unresolved cases.
