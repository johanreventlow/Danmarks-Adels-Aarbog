# 1939 rå-brointegritet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Gør hver accepteret 1939 rå-OCR-bro eksakt verificerbar med ordret
udsnit og SHA-256, før privat coverage materialiseres.

**Architecture:** Review-inputtet bærer koordinater, ordret råtekst og
udsnitshash. Kandidatbygningen bekræfter dem mod den rå OCR og lægger kun
koordinater, type og hash i den canonical coverage-fil. Coverage-validatoren
kræver hashen, så et senere konsumled ikke kan droppe udsnitsbeviset.

**Tech Stack:** Python 3 standardbibliotek, hashlib og pytest.

## Global Constraints

- Ingen tekstsøgning, normalisering, matchning eller gæt.
- Ingen database-, Supabase-, Vercel- eller loaderændringer.
- Eksisterende private review-ark overskrives aldrig.
- Enhver fejl i råtekst, interval eller hash skal afvise materialisering.
- Kør git branch --show-current før hver mutation og commit.

---

### Task 1: Kræv og verificér råtekstbevis i kandidatbygningen

**Files:**

- Modify: .claude/skills/daa-extract/scripts/prepare_coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py

**Interfaces:**

- Changes build_candidates to:
  build_candidates(calamari_text: str, raw_text: str, posts: list[dict],
  raw_bridges: list[dict]) -> list[dict].
- Every accepted raw bridge consumes raw_verbatim_text and
  raw_excerpt_sha256 and produces raw_structure_bridge with kind,
  raw_char_from, raw_char_to and raw_excerpt_sha256.

- [ ] **Step 1: Write failing exact-raw tests**

Add a literal raw string to the existing bridge fixture and test each branch.
The positive case passes raw_text "rå Alfa", raw_char_from 0,
raw_char_to 2, raw_verbatim_text "rå", and the hexadecimal SHA-256 of the
UTF-8 bytes for "rå". Assert that raw_structure_bridge includes that digest.
Add separate cases for an out-of-range raw interval, a nonidentical
raw_verbatim_text and a wrong raw_excerpt_sha256.

- [ ] **Step 2: Run test to verify it fails**

Run: /usr/bin/python3 -m pytest
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py -q -k
raw_excerpt

Expected: FAIL because the current function cannot accept raw_text or the
candidate output lacks raw_excerpt_sha256.

- [ ] **Step 3: Write minimal raw-proof implementation**

Require raw_text to be a string. For every bridge, require an interval within
raw_text, exact equality between the indexed slice and raw_verbatim_text, and
a raw_excerpt_sha256 equal to hashlib.sha256(raw_verbatim_text encoded as
UTF-8).hexdigest(). Raise "ikke eksakt rå-bro" for an interval or text
mismatch, and "rå-bro SHA-256 matcher ikke" for a digest mismatch. Emit the
digest in raw_structure_bridge and pass raw_text from materialize_coverage.

- [ ] **Step 4: Run candidate and materialization tests green**

Run: /usr/bin/python3 -m pytest
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py -q

Expected: PASS; existing output protection still raises FileExistsError.

- [ ] **Step 5: Commit**

Run git add .claude/skills/daa-extract/scripts/prepare_coverage_1939.py
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py, then
git commit -m "feat: verify exact 1939 raw bridges".

### Task 2: Bær rå-udsnitshashen gennem review og coverage

**Files:**

- Modify: .claude/skills/daa-extract/scripts/prepare_coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/test_coverage_1939.py

**Interfaces:**

- Adds raw_verbatim_text and raw_excerpt_sha256 to the accepted review-field
  set.
- Requires raw_excerpt_sha256 in a canonical candidate raw_structure_bridge.

- [ ] **Step 1: Write failing review and coverage tests**

Add a review entry with every older accepted field but no raw_verbatim_text;
validate_review_template must raise a message containing raw_verbatim_text.
Add a canonical accepted coverage candidate whose raw_structure_bridge lacks
raw_excerpt_sha256; validate_coverage must reject it.

- [ ] **Step 2: Run tests to verify they fail**

Run: /usr/bin/python3 -m pytest
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
.claude/skills/daa-extract/scripts/test_coverage_1939.py -q -k
"raw_verbatim_text or raw_excerpt_sha256"

Expected: FAIL because the review and coverage validators accept the
incomplete data.

- [ ] **Step 3: Implement the contract fields**

Add both fields to _REVIEW_ACCEPTED_FIELDS and the review allowlist. In
_review_entry_errors, require a nonempty raw_verbatim_text and a
64-character lowercase hexadecimal raw_excerpt_sha256. In coverage_1939.py
use the source-hash regular expression to require raw_excerpt_sha256 in
raw_structure_bridge.

- [ ] **Step 4: Run focused tests green**

Run: /usr/bin/python3 -m pytest
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
.claude/skills/daa-extract/scripts/test_coverage_1939.py -q

Expected: PASS.

- [ ] **Step 5: Commit**

Run git add .claude/skills/daa-extract/scripts/prepare_coverage_1939.py
.claude/skills/daa-extract/scripts/coverage_1939.py
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
.claude/skills/daa-extract/scripts/test_coverage_1939.py, then git commit -m
"feat: require 1939 raw excerpt hashes".

### Task 3: Regressions- og compatibility-gate

**Files:**

- Modify: docs/superpowers/reviews/1939-evidence-pilot.md

- [ ] **Step 1: Run full script suite**

Run: /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q

Record exact pass and skip counts.

- [ ] **Step 2: Verify current private review is unaffected**

Run prepare_coverage_1939.py with --check-review,
work/task19-1939-pilot/coverage-review.json and the frozen
clean_1939_v2.json baseline.

Expected: 546 entries, because every current entry is unreviewed.

- [ ] **Step 3: Document the gate**

Add one pilot-report paragraph: accepted bridges require exact Calamari text,
exact raw OCR text and both source-level/hash proofs; unreviewed records
remain nonmaterializable.

- [ ] **Step 4: Commit**

Run git add docs/superpowers/reviews/1939-evidence-pilot.md, then
git commit -m "docs: record 1939 raw bridge gate".

## Plan self-review

- Spec coverage: Task 1 covers exact raw bounds, text and digest; Task 2
  makes the review and canonical output contracts enforce that proof; Task 3
  proves no impact on the current all-unreviewed ledger.
- Placeholder scan: no TBD, TODO or implicit error paths remain.
- Type consistency: raw_verbatim_text remains only in the private decision
  path; raw_excerpt_sha256 reaches the canonical raw_structure_bridge.
