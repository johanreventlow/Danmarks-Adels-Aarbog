# 1939 dubletmålintegritet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Afvis coverage- og review-ledgers, hvor en eksplicit dublet ikke
positivt peger på én accepteret baseline-record.

**Architecture:** Begge validatorer læser først alle entries og udfører deres
lokale kontrol. En efterfølgende global kontrol slår hvert dubletmål op i den
færdige entry-mængde og kræver et andet, accepteret mål.

**Tech Stack:** Python 3 standardbibliotek og pytest.

## Global Constraints

- Ingen automatisk matching eller oprettelse af dubletmål.
- Ingen ændring af private review-ark, database, loader eller deployment.
- Flere dubletter må gerne have samme accepterede mål.
- Kør git branch --show-current før hver mutation og commit.

---

### Task 1: Gør dubletmål globale og positive

**Files:**

- Modify: .claude/skills/daa-extract/scripts/coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/prepare_coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/test_coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py

**Interfaces:**

- validate_coverage rejects an explicit duplicate when its target is absent,
  equals its own baseline key, has status eksplicit_dublet or has status
  menneskeark.
- validate_review_template applies the same relationship rule after all
  review entries are structurally and semantically valid.
- review_summary emits each relationship failure as a blocker.

- [ ] **Step 1: Write failing synthetic relationship tests**

Create a four-entry coverage bundle with rk-1 accepted, rk-2 duplicate of
rk-1, rk-3 menneskeark, and rk-4 as the key under test. Assert that rk-4 is
rejected when it targets "unknown", "rk-4", "rk-2" or "rk-3"; assert it
passes when it targets "rk-1". Create an equivalent complete review ledger
where rk-2 is a duplicate of rk-1 and verify a bad target is reported by
review_summary.

- [ ] **Step 2: Run tests to verify they fail**

Run: /usr/bin/python3 -m pytest
.claude/skills/daa-extract/scripts/test_coverage_1939.py
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py -q -k
duplicate

Expected: FAIL because current validation only requires a nonempty target
string.

- [ ] **Step 3: Implement one global target validator**

After local validation, inspect each explicit duplicate target. Raise
"ukendt dubletmål" when target is absent, "dublet må ikke pege på sig selv"
for self-reference, and "dubletmål skal være accepteret" for a known target
with another status. Reuse this check for review entries by converting
review_status to the same status relation without constructing decisions.

- [ ] **Step 4: Run focused tests green**

Run: /usr/bin/python3 -m pytest
.claude/skills/daa-extract/scripts/test_coverage_1939.py
.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py -q

Expected: PASS.

- [ ] **Step 5: Run full regression and current-review check**

Run: /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q

Then run prepare_coverage_1939.py with --check-review against
work/task19-1939-pilot/coverage-review.json and the frozen
clean_1939_v2.json baseline. Expected: 546 unreviewed review entries still
validate.

- [ ] **Step 6: Commit**

Run git add for the two scripts and two test files, then git commit -m
"feat: validate 1939 duplicate targets".

## Plan self-review

- Spec coverage: target existence, self-reference and accepted-target status
  are all tested and enforced; valid many-to-one duplicate references remain
  allowed.
- Placeholder scan: no deferred behavior or implicit decision path remains.
- Type consistency: coverage status and review_status use the same three
  explicit values.
