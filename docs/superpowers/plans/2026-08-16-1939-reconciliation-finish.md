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

### Task 3: Resolve paired reconciliation reviews in source-ordered batches

**Files:**
- Create: sequential `work/task20-1939-full/source-record-decisions-paired-vN.json`
- Create: sequential reconciliation/report artifacts after v31
- Create: sequential `work/task20-1939-full/paired-review-batch-vN-report.md`

**Interfaces:**
- Consumes: the Task 2 manifest and the latest reconciliation hash.
- Produces: reviewed decisions for every clear pair or genuinely new/structural record; genuinely ambiguous hierarchy or identity remains explicitly unresolved for user review.

- [ ] Review subjects in batches of at most 12, preserving manifest source order and using complete relevant PDF pages plus literal Calamari.
- [ ] Apply only decision kinds already supported and tested. If a reviewed case requires a new semantic decision, stop that case, add a separately reviewed interpreter task, and continue the other subjects.
- [ ] After each batch, audit exact decision/hash binding, changed sets, ownership, deep preservation, report identity, OCR literal substrings, focused tests, and `git diff --check`.
- [ ] Continue without routine user confirmation. Ask only about genuine hierarchy, ownership, identity, or source-boundary ambiguity that cannot be resolved from PDF and Calamari.
- [ ] Finish with a zero-queue audit or an explicit ambiguity ledger naming every remaining key and exact blocker.
