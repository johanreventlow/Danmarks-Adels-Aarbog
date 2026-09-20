# DAA 1939 v50 Identity Review Implementation Plan

> **For Codex:** Følg planen test-first. Alle databasekald er read-only. Ingen
> identitetsafgørelse eller canonical mutation må materialiseres.

**Goal:** Fremstil en hashbundet reviewpakke, der sammenholder de 41 v50
genuinely-new source records med de 23 eksisterende, umappede 1939-personer.

**Architecture:** Et read-only R-profiludtræk genbruger v50-previewets
databasekontrakt. En separat Python-builder validerer profil, importpreview og
historisk linked payload og emitterer et closed-schema, review-only manifest.

**Design:**
`docs/superpowers/specs/2026-08-17-1939-v50-identity-review-design.md`

## Task 1: Lås databaseprofil-kontrakten

**Files:**

- Create: `.claude/skills/daa-extract/scripts/profile_identity_review_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/test_profile_identity_review_1939_v50.R`

1. Skriv dependency-injected tests for eksakt 23-key input, read-only
   queryrækkefølge, lukket outputschema og deterministic sortering.
2. Test narrativ-, fact-, relation- og family-member-provenance samt
   rollback/disconnect på alle fejlveje.
3. Observer RED før implementation.

## Task 2: Implementér read-only profiludtræk

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/profile_identity_review_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/profile_identity_review_1939_v50.R`

1. Genbrug SQL-whitelist og read-only bootstrap fra v50 databasepreviewet.
2. Valider inputhash og præcise record-key/person-ID-par.
3. Læs kun de 23 profiler og deres source-/editorial ownership.
4. Skriv output eksklusivt efter forbindelsen er lukket.
5. Kør fokuserede og fulde R-tests.

## Task 3: Lås manifest-kontrakten

**Files:**

- Create: `.claude/skills/daa-extract/scripts/test_build_identity_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/build_identity_review_1939_v50.py`

1. Skriv fixtures for discriminating literal, common short name, date-only,
   ambiguity, spouse/date kombination og fuzzy-only signal.
2. Test closed schema, SHA-binding, 41/23 coverage, exact offsets, competitor
   symmetry og review-only invariants.
3. Observer RED før implementation.

## Task 4: Implementér manifest-builder og rapport

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/build_identity_review_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_build_identity_review_1939_v50.py`

1. Implementér streng inputvalidering og deterministic ordering.
2. Implementér kun source-bound literal signals; fuzzy finder er
   presentation-only.
3. Afvis common-name-only og date-only links.
4. Emitér alle subjects/profiles, pending states og nul canonical mutations.
5. Implementér eksklusiv CLI-output og Markdown fra samme bundle.

## Task 5: Kør mod live read-only database og virkelige artefakter

**Generated ignored:**

- `work/task22-1939-v50-identity-review/database-profiles-v1.json`
- `work/task22-1939-v50-identity-review/identity-review-v1.json`
- `work/task22-1939-v50-identity-review/identity-review-v1-report.md`

1. Kør profiludtrækket mod direct/session-mode PostgreSQL i read-only
   transaktion; port 6543 er fortsat forbudt.
2. Byg manifestet fra de eksakte task21-input og linked v2-payload.
3. Genbyg til tempstier og sammenlign bytes.
4. Auditér alle links, ambiguity sets og unlinked subjects.

## Task 6: Handoff til menneskelig identitetsreview

1. Dokumentér counts og konkrete reviewspørgsmål uden at godkende identitet.
2. Kør fokuserede Python-/R-tests, fulde suites og `git diff --check`.
3. Bevar alle persondata under ignoreret `work/`; commit kun scripts, tests og
   dokumentation.
4. Efter menneskelige beslutninger udarbejdes en separat writer-/migrationplan.

