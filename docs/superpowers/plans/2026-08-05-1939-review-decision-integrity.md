# 1939 review- og beslutningsintegritet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Afvis falske rå-udsnitshashes og ugyldige direkte
dubletbeslutninger før output.

**Architecture:** Den eksisterende review-entry-kontrol sammenligner hash med
råtekst. Konverteringen opbygger en unik key-mængde og anvender den delte
globale dubletmålskontrol før den skriver beslutninger.

**Tech Stack:** Python 3 standardbibliotek og pytest.

## Global Constraints

- Ingen ændring af review-arbejdsartefakter, database eller deployment.
- Ingen automatisk matching eller tekstnormalisering.

### Task 1: Fail-closed review og direkte konvertering

**Files:**

- Modify: .claude/skills/daa-extract/scripts/prepare_coverage_1939.py
- Modify: .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py

- [ ] Add a test whose raw hash has correct syntax but wrong content; review
  validation must raise raw_excerpt_sha256.
- [ ] Add direct review_to_decisions tests for duplicate baseline keys and
  invalid duplicate targets.
- [ ] Run the selected tests red.
- [ ] Compare hashlib.sha256(raw_verbatim_text encoded as UTF-8) with the
  supplied digest in _review_entry_errors. In review_to_decisions, reject
  duplicate keys and call duplicate_target_errors with review_status before
  conversion.
- [ ] Run the focused tests, the full scriptsuite and --check-review against
  the 546-entry private review.
- [ ] Commit scripts and tests with message feat: harden 1939 review decisions.
