# #152 Task 13 Corrective Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Task 13's offline inventory, review, cutover and postverify gates one compatible, fail-closed contract, then stop before any production action.

**Architecture:** The existing export reader inventory remains the single artifact
oracle. The Python review validator and SQL cutover kernel consume the same
ordered classification. The postverify adapter reads its complete state inside
one locked, read-only repeatable-read transaction; it compares receipt-bound
events, exact public projection rows and explicit ACL grants without relying on
the artifact as observed state. The runbook adds the external traffic hold that
cannot be enforced by a read-only database snapshot.

**Tech Stack:** PostgreSQL 17, PL/pgSQL, R/testthat/DBI/RPostgres, Python 3
stdlib/pytest, Markdown.

**Spec:** `docs/superpowers/specs/2026-08-29-narrative-source-record-key-design.md`

## Global Constraints

- This corrective plan expands only the Task 13 gate contract; it makes no
  production database mutation, push, merge, deployment or network request.
- Do not read, stage or modify `work/` or
  `docs/superpowers/reviews/2026-08-29-narrative-source-record-key-design-review.md`.
- `schema.sql`, `db-migrations.sql`, the offline review validator and the
  exporter must agree byte-for-byte on the classified reader list.
- Use exact IDs and hashes, never count-only approval; preserve bigint values
  as decimal strings across JSON/R comparison boundaries.
- A final independent GPT-5.6-Sol review is read-only and its valid findings
  require RED → GREEN evidence before a commit.

---

### Task 1: Repair the classified-reader contract across every gate

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/export_narrative_record_cutover_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/build_narrative_record_cutover_review.py`
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `tests/testthat/test-export-narrative-record-cutover.R`
- Modify: `.claude/skills/daa-extract/scripts/test_build_narrative_record_cutover_review.py`
- Modify: `tests/sql/test-narrative-record-cutover.sql`

- [x] Add RED tests that the 11-item ordered inventory includes
  `mobile/src/data/publicBioVersions.ts` as `v2_public_rpc`, and that a review
  artifact with that list is accepted while any omitted or reordered item is
  rejected.
- [x] Make the exporter, Python validator, schema and migration use exactly the
  same 11 ordered `(path, classification)` values.
- [x] Run the focused R, Python and disposable SQL cutover tests; verify GREEN.

### Task 2: Make postverify a complete, executable database observation

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/verify_narrative_record_cutover_postverify.R`
- Modify: `.claude/skills/daa-extract/scripts/apply_narrative_record_cutover_helpers.R`
- Modify: `tests/testthat/test-verify-narrative-record-cutover-postverify.R`
- Modify: `tests/testthat/test-apply-narrative-record-cutover.R`

- [x] Add RED cases for a bigint artifact ID above JavaScript's safe range,
  extra private event in the receipt change set, a legacy-only/hidden person,
  event UUID order differing from public RPC order, a missing ACL signature,
  a default PUBLIC function ACL and `NA` database NULLs.
- [x] Parse artifact JSON with decimal bigint preservation, query expected
  procedures by `to_regprocedure`, require every expected OID, expand default
  ACLs while ignoring only the owner grant, and compare canonical qualified
  OID identities.
- [x] Query all receipt change-set events under one read-only repeatable-read
  shared cutover lock; reject additional events and validate baseline fields.
  Derive expected v2 rows from those proven events and order them exactly as
  `public_person_bio_source_versions_v2` orders them.
- [x] Scan both `.ts` and `.tsx` production source files for all classified
  reader families and fail when the complete checkout inventory differs.
- [x] Run the affected R suites and parse/diff checks; verify GREEN.

### Task 3: Make the production procedure non-circular and quiescent

**Files:**
- Modify: `docs/runbooks/narrative-record-key-cutover.md`
- Modify: `docs/evidensbaseret-genimport/status.md`
- Modify: `docs/evidensbaseret-genimport/roadmap.md`

- [x] Add an exact preliminary-authorization → backup/restore rehearsal →
  fresh artifact/review → final artifact-bound GO → preflight/apply sequence.
  Generate and bind the nonce before final GO; bind backup SHA only when it
  already exists.
- [x] Require an explicit external writer-traffic hold from apply through
  postverify, and release it only after the verifier passes; a failed
  postverify remains containment, never `recover`.
- [x] State the reviewed release SHA and expiry as final-GO fields checked by
  the operator before preflight/apply.

### Task 4: Final verification and review

- [x] Run all focused R/Python/SQL suites invalidated above, their applicable
  integration test and `git diff --check`; report results separately.
- [x] Conduct Codex self-review against the spec, original Task 13 plan and
  this corrective plan.
- [x] Request one GPT-5.6-Sol xhigh read-only review; critically disposition
  each finding, run RED → GREEN for valid fixes, then rerun invalidated suites.
- [x] Commit only the verified corrective batch. Update Task 13 governance only
  when the evidence is GO; otherwise retain `READY_FOR_PRODUCTION_REVIEW`.
