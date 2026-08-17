# DAA 1939 v50 Source-persona Materialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Materialisér de 24 godkendte v50-identiteter som et hashbundet source-persona-preview og genkør database-preview v2 helt read-only.

**Architecture:** En ny Python-builder joiner import-preview v1, database-preview v1 og fire identitetsbatches uden databaseadgang. R-komparatoren får source-persona-artefaktet som et ekstra input og producerer et append-only database-preview v2; den eksisterende read-only querygrænse bevares.

**Tech Stack:** Python 3, pytest, R, testthat, DBI/RPostgres/jsonlite, PostgreSQL/Supabase read-only session.

## Global Constraints

- `load_daa.R` må ikke ændres eller kaldes.
- Ingen DDL, DML, temp-tabeller, mutation-RPC'er eller canonical writes.
- Eksisterende preview v1-artefakter må ikke overskrives.
- Alle input er SHA-256-bundne og schemas valideres fail closed.
- Realdataoutput ligger kun i ignoreret `work/`.
- `canonical_mutations_authorized`, `database_write_authorized` og reimport-autorisation forbliver `false`/`NO-GO`.

---

### Task 1: Source-persona-materialisering

**Files:**
- Create: `.claude/skills/daa-extract/scripts/materialize_source_personas_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_materialize_source_personas_1939_v50.py`

**Interfaces:**
- Consumes: import-preview v1, database-preview v1 og en ordnet liste af identity-decisions v1 med deres SHA-256.
- Produces: `build_source_persona_materialization(...) -> dict`, `write_outputs(...)` og CLI-output med schema `1939-v50-source-persona-materialization-v1`.

- [x] **Step 1: Skriv failing tests for 24→17-kontrakten og entydig target-validering**

  Små fixtures skal kontrollere, at kun `genuinely_new_pending` kan materialiseres, at canonical person-id matcher databaseankeret, og at source/candidate/person er globalt entydige.

- [x] **Step 2: Kør fokuseret RED**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_materialize_source_personas_1939_v50.py`

  Expected: FAIL fordi modulet eller builderen ikke findes.

- [x] **Step 3: Implementér minimal lukket builder**

  Builderen validerer schemas/gates/hashes, afleder deterministisk UUIDv5 fra det logiske `source_id` og `new_record_key`, bevarer database-source-id separat, kopierer source span/verbatim og emitterer 24 accepted identities, 17 pending samt nul canonical mutations.

- [x] **Step 4: Tilføj negative drift-tests**

  Afvis mindst ukendt batchschema, ændret inputhash, duplicate source/candidate/person, source uden for pending-sættet, target/person mismatch, ændret source span og enhver write-authority.

- [x] **Step 5: Kør fokuseret GREEN og commit**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_materialize_source_personas_1939_v50.py`

  Commit: `feat(1939): materialize approved source personas`

### Task 2: Database-preview v2-kontrakt

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/preview_reimport_1939_v50_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R`
- Modify: `.claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R`
- Modify: `tests/testthat/test-preview-reimport-1939-v50.R`

**Interfaces:**
- Consumes: import-preview v1 plus source-persona-materialization v1 og dets hash.
- Produces: database-preview schema `1939-v50-database-preview-v2` med `source_personas`, 17 pending og uændrede canonical mutation-gates.

- [x] **Step 1: Skriv failing R-tests for materialiseringsvalidering og 24/17-output**

  Tests skal bruge den eksisterende dependency-injected queryadapter og assertére, at forkert import-preview-hash, source-id, count, target eller gate afvises før domænesammenligning.

- [x] **Step 2: Kør fokuseret RED**

  Run: `Rscript -e 'source(".claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R")'`

  Expected: FAIL fordi v2-inputtet endnu ikke understøttes.

- [x] **Step 3: Implementér v2 som snæver udvidelse**

  Tilføj CLI-argumenterne `--source-personas` og `--source-personas-sha256`; valider materialiseringen og sammenlign private persona-/identitytabeller, når capability-proben viser dem. Ved manglende tabeller emitér null comparisons og stabile capability-blockers.

- [x] **Step 4: Bevar read-only- og SQL-whitelist-testene**

  Assertér fortsat `BEGIN READ ONLY` før første domænequery, rollback/disconnect på alle veje og nul credentialfelter i output.

- [x] **Step 5: Kør fokuseret GREEN og commit**

  Run: `Rscript -e 'source(".claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R")'`

  Commit: `feat(1939): include source personas in database preview`

### Task 3: Realdataartefakter og live dry-run

**Files:**
- Generate ignored: `work/task23-1939-v50-source-personas/source-persona-materialization-v1.json`
- Generate ignored: `work/task23-1939-v50-source-personas/source-persona-materialization-v1-report.md`
- Generate ignored: `work/task23-1939-v50-source-personas/database-preview-v2.json`
- Generate ignored: `work/task23-1939-v50-source-personas/database-preview-v2-report.md`

**Interfaces:**
- Consumes: de låste task21/task22-artefakter og den eksisterende read-only databaseforbindelse.
- Produces: hashbundne realdataresultater uden databasewrites.

- [x] **Step 1: Generér source-persona-materialiseringen eksklusivt**

  Brug import-preview v1, database-preview v1 og identity-decisions v1-v4; forvent 24 accepted, 17 pending og 0 canonical mutations.

- [x] **Step 2: Genbyg til temp og sammenlign bytes**

  JSON og Markdown skal være byteidentiske; alle 24 source-, candidate- og person-id'er skal være entydige.

- [x] **Step 3: Kør den virkelige database-preview v2 read-only**

  Brug direct/session-mode connection, afvis port 6543, verificér `transaction_read_only=on`, og skriv kun lokale outputfiler efter disconnect.

- [x] **Step 4: Auditér resultatet**

  Bekræft 24 materialiserede, 17 pending, 0 canonical person creates/updates/deletes, capability-blockers som stabile og ingen credentials i output.

### Task 4: Dokumentation og slutverifikation

**Files:**
- Modify: `.claude/skills/daa-extract/SKILL.md`
- Create: `docs/superpowers/reviews/1939-v50-source-persona-materialization.md`

**Interfaces:**
- Consumes: alle fokuserede og realdata-resultater.
- Produces: reproducerbar kommando, eksakte counts og ærlig GO/NO-GO-status.

- [x] **Step 1: Dokumentér kommandoer og gates**

  Skeln `source_persona_materialization_gate: GO`, read-only dry-run-status og `reimport_gate: NO-GO`.

- [x] **Step 2: Kør fuld verifikation**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q`

  Run: `cd ../../../.. && Rscript run-tests.R`

  Run: `git diff --check && git status --short`

- [x] **Step 3: Commit dokumentation og eventuelle snævre rettelser**

  Commit: `docs(1939): report source persona dry run`

- [x] **Step 4: Handoff**

  Rapportér artefakthashes, testtal, database-read-only-bevis, resterende blockers og at en egentlig writer fortsat kræver separat autorisation.
