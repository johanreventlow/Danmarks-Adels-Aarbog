# DAA 1939 Reconciliation Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the remaining DAA 1939 source-record reconciliation queue without weakening source, ownership, or provenance gates.

**Architecture:** Extend the existing hash-bound reconciliation interpreter with one narrow decision for a named record followed by a contiguous extraction fragment. Apply that decision to Hedevig Ida, then review the remaining unmatched baseline and new records together in source order so that the two queues cannot be resolved inconsistently.

**Tech Stack:** Python 3.9, pytest, JSON reconciliation artifacts, Calamari OCR, visual PDF review.

## Global Constraints

- Work only in `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/.claude/worktrees/evidensbaseret-genimport` on `feat/evidensbaseret-genimport`.
- Preserve all existing v30 decisions and provenance; never overwrite an earlier decision, reconciliation, report, OCR ledger, source export, source PDF, or Calamari file.
- Every decision is bound to the exact preceding reconciliation SHA-256 plus the unchanged baseline and Calamari hashes.
- Fail closed on missing keys, unexpected fields, non-unique ownership, non-contiguous spans, changed source bytes, hierarchy ambiguity, or incomplete visual evidence.
- Raw OCR remains raw. OCR corrections are append-only and each `calamari_text` must be a literal substring of its bound Calamari page.
- Do not use `work/task19-1939-pilot/calamari-occurrences-v2-run-f.json`; it is stale.
- Do not modify the database, `load_daa.R`, canonical people, identity decisions, or production import paths.
- Render complete relevant PDF pages under `tmp/pdfs/` and delete renderings after review.
- Generated work artifacts remain uncommitted/ignored; an implementer may commit only the focused tracked interpreter, tests, and this plan for review.

---

### Task 1: Support and resolve a contiguous continuation fragment

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- Create: `work/task20-1939-full/source-record-decisions-merge-v1.json`
- Create: `work/task20-1939-full/source-record-reconciliation-v31.json`
- Create: `work/task20-1939-full/source-record-reconciliation-report-v31.json`
- Create: `work/task20-1939-full/merge-batch-v1-hedevig-ida-report.md`

**Interfaces:**
- Consumes: v30 SHA-256 `62b60890fd1963cb83d1e16ab589781d6193736a3340891bebabd323130faeec`.
- Produces: a fail-closed `retire_continuation_fragment` decision and v31 with the Hedevig Ida target owned only by the canonical named baseline record.

- [x] Add failing unit tests for the exact decision shape, correct canonical/fragment output, target ownership, resolved counts, non-contiguous spans, reversed spans, differing targets, extra owners, unknown keys, stale hashes, and unexpected fields.
- [x] Implement the minimal decision branch. Require two distinct `merge_review` baseline records, one shared `merge_review` target, the canonical span before the fragment span with at most one intervening character, and both spans inside the target. Mark the canonical record `accepted_carryover` with `selected_new_record_key` and basis `human_accepted_contiguous_merge`; clear the fragment matches and mark it `retired_fragment` with its canonical key, reason `continuation_extraction_fragment`, reviewer, and batch. Treat `retired_fragment` as resolved.
- [x] Run `pytest -q test_apply_reconciliation_decisions_1939.py` and then the complete scripts suite.
- [x] Render and inspect the complete PDF page containing Hedevig Ida; compare both baseline spans and the target with the literal Calamari text.
- [x] Create and apply the v1 merge decision to v30 without overwriting prior artifacts.
- [x] Audit exact changed baseline/new sets, unique target ownership, deep preservation of all unrelated objects, embedded/standalone report identity, hashes, counts, and `git diff --check`.
- [x] Commit only the interpreter, tests, and this plan after implementation self-review; later review fixes use separate focused commits.

### Task 2: Build the paired unresolved/unmatched review order

**Files:**
- Create: `work/task20-1939-full/reconciliation-paired-review-v1.json`
- Create: `work/task20-1939-full/reconciliation-paired-review-v1-report.md`

**Interfaces:**
- Consumes: v31 after Task 1.
- Produces: a source-ordered, hash-bound review manifest pairing every one of the 49 unresolved baseline entries with zero or more plausible unmatched-new entries, while also listing every unmatched-new entry not proposed for a baseline.

- [ ] Sort baseline entries with spans by `char_from`, followed by spanless baseline entries in stable input order; sort unmatched-new entries by `char_from`.
- [ ] Generate candidates only from exact source overlap, bounded source proximity, or literal/name evidence derived from the hash-bound Calamari and baseline record. Do not manufacture names or identities.
- [ ] Record candidate evidence, competing ownership, full source spans, source pages, and a fail-closed proposed class: `same_record_review`, `baseline_missing_span_review`, `genuinely_new_review`, `structural_review`, or `unresolved`.
- [ ] Prove coverage: all 49 unresolved baseline keys and all remaining unmatched-new keys occur exactly once as subjects; candidate references may repeat only as explicit alternatives.
- [ ] Run deterministic schema, source-hash, injectivity, coverage, and `git diff --check` audits.

### Task 3: Repair two contaminated legacy anchors

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/apply_reconciliation_decisions_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_apply_reconciliation_decisions_1939.py`
- Modify: `docs/superpowers/plans/2026-08-16-1939-reconciliation-finish.md`
- Create: `work/task20-1939-full/source-record-decisions-legacy-anchor-repair-v1.json`
- Create: `work/task20-1939-full/source-record-reconciliation-v32.json`
- Create: `work/task20-1939-full/source-record-reconciliation-report-v32.json`
- Create: `work/task20-1939-full/legacy-anchor-repair-v1-report.md`

**Interfaces:**
- Consumes: approved design `docs/superpowers/specs/2026-08-17-1939-legacy-anchor-repair-design.md` and v31 SHA-256 `ee37434d78057088f0b20f16a642dee82e24875c02ff9d8dc1b1b538cb6ee725`.
- Produces: a fail-closed `repair_legacy_anchor` decision and v32 where Margrethe and Iwen own their existing correct targets, while their stale baseline spans remain visible as historical provenance.

- [x] Add failing tests for the exact closed decision shape and a successful batch containing both geometries: disjoint Margrethe and overlapping Iwen. Assert accepted baseline/target output, synthesized `human_repaired_legacy_anchor` match, complete repair metadata, exact changed sets and report counts.
- [x] Add failing rejection tests for wrong source disposition/reason, non-empty baseline matches, target not `unmatched_new_review`, ghost/duplicate/malformed owners, stale or mismatched spans, empty/unsorted/overlapping/incomplete discarded spans, wrong reason, unknown fields, reused target, stale hashes and later-batch metadata loss.
- [x] Implement `repair_legacy_anchor` exactly as specified. Compute the half-open interval difference `stale_source_span - selected_new_source_span` internally and require exact equality with the declared non-empty sorted `discarded_source_spans`; never infer a target from name, proximity or overlap.
- [x] Create one v1 decision batch with Margrethe `c52df82f-0cd9-4c66-ab76-8a429df0124f` → `record-9bd09532-097b-49e1-aa99-14bef66588d6`, discarded `[50370,50568)`, and Iwen `6bfbce43-740d-49b1-9b4b-1aa2e9b17266` → `record-07204254-7bc5-4754-bcd2-68a1c79408c5`, discarded `[183021,183074)`.
- [x] Apply the decision directly to v31 with new exclusive v32/report paths. Audit exactly two changed baseline and two changed new objects, unique ownership, deep preservation of all others, embedded/standalone report identity, unchanged v31/OCR/source artifacts and counts `145 accepted`, `47 unresolved baseline`, `90 unmatched new`, one retired duplicate, one retired fragment, `NO-GO`.
- [x] Run focused interpreter tests, the full scripts suite, the artifact audit and `git diff --check`.
- [x] Commit only interpreter, tests and this plan after implementation self-review; never commit work artifacts.

### Task 4: Resolve paired reconciliation reviews in source-ordered batches

**Files:**
- Create: sequential `work/task20-1939-full/source-record-decisions-paired-vN.json`
- Create: sequential reconciliation/report artifacts after v32
- Create: sequential `work/task20-1939-full/paired-review-batch-vN-report.md`

**Interfaces:**
- Consumes: a regenerated, v32-bound paired manifest and the latest reconciliation hash.
- Produces: reviewed decisions for every clear pair or genuinely new/structural record; genuinely ambiguous hierarchy or identity remains explicitly unresolved for user review.

- [ ] Review subjects in batches of at most 12, preserving manifest source order and using complete relevant PDF pages plus literal Calamari.
- [ ] Apply only decision kinds already supported and tested. If a reviewed case requires a new semantic decision, stop that case, add a separately reviewed interpreter task, and continue the other subjects.
- [ ] After each batch, audit exact decision/hash binding, changed sets, ownership, deep preservation, report identity, OCR literal substrings, focused tests, and `git diff --check`.
- [ ] Continue without routine user confirmation. Ask only about genuine hierarchy, ownership, identity, or source-boundary ambiguity that cannot be resolved from PDF and Calamari.
- [ ] Finish with a zero-queue audit or an explicit ambiguity ledger naming every remaining key and exact blocker.
