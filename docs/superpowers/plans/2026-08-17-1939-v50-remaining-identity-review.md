# DAA 1939 v50 Remaining Identity Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Klassificér alle 17 resterende v50-source-records med PDF/Calamari-evidens, materialisér kun sikre eksisterende identiteter og genkør database-preview helt read-only.

**Architecture:** En ny Python-builder laver en hashbundet 17-posters reviewpakke fra den eksisterende v1-materialisering, 543 mapped og 23 database-only 1939-profiler, v50-kontekst og boundary-sidemapping. En særskilt beslutningsvalidator accepterer præcis fire lukkede dispositioner, og en append-only v2-materialisering bevarer de eksisterende 24 personaer samt tilføjer kun sikre `same_existing_person`-links. Den eksisterende R-komparator udvides kompatibelt til database-preview v3 og ændrer aldrig databasen.

**Tech Stack:** Python 3, pytest, R, testthat, DBI/RPostgres/jsonlite, Poppler (`pdfinfo`, `pdftoppm`), PostgreSQL/Supabase read-only session.

## Global Constraints

- `load_daa.R` må ikke ændres eller kaldes.
- Ingen DDL, DML, temp-tabeller, mutation-RPC'er eller canonical writes.
- Eksisterende v1/v2-artefakter må ikke overskrives.
- Rå OCR, source spans og record keys bevares ordret og SHA-256-bindes.
- Alle maskinelle forslag starter `unresolved`; fuzzy signaler kan aldrig autorisere et match.
- Kun `same_existing_person` kan tilføje et source-persona-link.
- `new_person_candidate`, `structural_or_summary` og `unresolved` må aldrig autorisere en canonical mutation.
- Realdataoutput ligger kun under ignoreret `work/task24-1939-v50-remaining-identities/`.
- Midlertidige PDF-renderinger ligger under `tmp/pdfs/` og fjernes efter review.
- `database_write_authorized` og `canonical_mutations_authorized` forbliver `false`; `reimport_gate` forbliver `NO-GO`.

---

### Task 1: Deterministisk 17-posters reviewmanifest

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_remaining_identity_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_remaining_identity_review_1939_v50.py`

**Interfaces:**
- Consumes: source-persona-materialization v1, import-preview v1, database-preview v1, database-only-profiler v1, `clean_1939_v3.json`, boundary-materialization v3 og Calamari-renditionen med eksakte hashes.
- Produces: `build_remaining_review(...) -> dict`, `write_outputs(...)` og schema `1939-v50-remaining-identity-review-v1`.

- [ ] **Step 1: Skriv RED-fixture for eksakt dækning, kildeorden og sidemapping**

  Testen bygger tre små records i usorteret input og kræver sortering efter
  `source_span.char_from`, ordret tekst, foregående/efterfølgende record og
  entydig `page_from/page_to` fra boundary-materialiseringen:

  ```python
  result = build_remaining_review(**fixture_inputs())
  assert [row["new_record_key"] for row in result["subjects"]] == ["new-a", "new-b", "new-c"]
  assert result["subjects"][1]["page_evidence"] == {"page_from": 503, "page_to": 503}
  assert result["counts"]["subjects"] == 3
  assert result["review_gate"] == "GO"
  assert result["identity_decision_gate"] == "NO-GO"
  ```

- [ ] **Step 2: Kør den fokuserede test og observer RED**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_build_remaining_identity_review_1939_v50.py`

  Expected: FAIL fordi modulet ikke findes.

- [ ] **Step 3: Implementér lukket inputvalidering og kontekstbygning**

  Implementér `build_remaining_review` med denne offentlige signatur:

  ```python
  def build_remaining_review(
      *, source_persona_v1: dict[str, Any], import_preview: dict[str, Any],
      database_preview: dict[str, Any], database_only_profiles: dict[str, Any],
      clean_records: list[dict[str, Any]],
      boundary_materialization: dict[str, Any], calamari_text: str,
      input_hashes: dict[str, str], expected_subjects: int = 17,
      expected_mapped_profiles: int = 543,
      expected_database_only_profiles: int = 23,
  ) -> dict[str, Any]: ...
  ```

  Validatoren skal kræve præcis 17 `remaining_genuinely_new_pending`, præcis
  543 entydige matched record-key/person-id-par, 23 entydige database-only-par,
  én clean-record pr. mapped key, eksakte database-only-profiler, én boundary-
  record med identisk global span og verbatimtekst pr. subject og Calamari-
  substring lig verbatimteksten.

- [ ] **Step 4: Skriv RED-tests for kandidat- og later-occurrence-evidens**

  Kræv at literal profilnavn + vitalt år kan blive en `review_candidate`, at en
  OCR-normaliseret lighed kun bliver `presentation_only`, og at senere v50-
  forekomster har record key, span og literal/normaliseret signal. Alle forslag
  skal have `proposed_action == "unresolved"`.

- [ ] **Step 5: Implementér konservativ kandidat- og forekomstsøgning**

  Genbrug `_profile_signals`, `filter_principal_signals` og `_qualifies` for
  positive literal-signaler. Tilføj en lokal OCR-normalisering kun til discovery
  (`lven/Iven`, linjeskift-bindestreg og splittede versaler); emitér altid den
  rå substring og markér signalet `authoritative: false`. Byg `later_occurrences`
  fra andre source records, aldrig fra fri tekst uden record key.

- [ ] **Step 6: Tilføj negative drift-tests**

  Parametriser mindst: forkert source-persona-hash, 16/18 subjects, duplicate
  subject, ændret verbatimtekst, manglende boundary-side, Calamari-mismatch,
  ukendt profil, duplicate canonical person-id, ukendt felt og write-authority.
  Alle skal rejse `RemainingIdentityReviewError` før output skrives.

- [ ] **Step 7: Kør GREEN og commit reviewbuilderen**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_build_remaining_identity_review_1939_v50.py`

  Commit: `feat(1939): build remaining identity review`

---

### Task 2: Realdatareview med PDF og Calamari

**Files:**
- Generate ignored: `work/task24-1939-v50-remaining-identities/remaining-identity-review-v1.json`
- Generate ignored: `work/task24-1939-v50-remaining-identities/remaining-identity-review-v1-report.md`
- Generate ignored: `work/task24-1939-v50-remaining-identities/remaining-identity-proposals-v1.json`
- Temporary only: `tmp/pdfs/1939-remaining-identity-*.png`

**Interfaces:**
- Consumes: Task 1-builderen og de låste realdatafiler.
- Produces: en komplet 17-posters reviewpakke samt et forslag med en af de fire dispositioner pr. post; forslaget giver ingen write-authority.

- [ ] **Step 1: Generér reviewpakken eksklusivt**

  Run:

  ```bash
  /usr/bin/python3 -B .claude/skills/daa-extract/scripts/build_remaining_identity_review_1939_v50.py \
    --source-personas=work/task23-1939-v50-source-personas/source-persona-materialization-v1.json \
    --import-preview=work/task21-1939-v50-import-preview/import-preview-v1.json \
    --database-preview=work/task21-1939-v50-import-preview/database-preview-v1.json \
    --database-profiles=work/task22-1939-v50-identity-review/database-profiles-v1.json \
    --clean=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/clean_1939_v3.json \
    --boundary-materialization=work/task20-1939-full/boundary-materialization-v3-ditlev.json \
    --calamari=/Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
    --output=work/task24-1939-v50-remaining-identities/remaining-identity-review-v1.json \
    --report=work/task24-1939-v50-remaining-identities/remaining-identity-review-v1-report.md \
    --expected-subjects=17 --expected-mapped-profiles=543 \
    --expected-database-only-profiles=23
  ```

- [ ] **Step 2: Genbyg til temp og kræv byteidentitet**

  Kør samme CLI mod en `mktemp -d`-mappe og brug `cmp` på både JSON og
  Markdown. Auditér 17 unikke source keys, 17 unikke spans, stigende offsets og
  hashene for alle syv input.

- [ ] **Step 3: Render komplette kildesider og nødvendige nabosider**

  Brug `pdfinfo` til at kontrollere PDF'en og render kun de sideintervaller, som
  manifestet deklarerer, fra:
  `/Users/johanreventlow/TypeScript/danmarksadelsaarbog/Dansk Adels Aarbog - Reventlow 1939 stamtavle.pdf`.
  Kør `pdftoppm -f <page> -l <page> -png -r 180 ...` og inspicér hver PNG
  visuelt; ved sidebrud renderes begge sider.

- [ ] **Step 4: Klassificér alle 17 i kildeorden**

  For hver post sammenholdes komplet PDF-side, Calamari, naboer, senere
  occurrences og relevante profiler. Skriv et lukket forslag med:

  ```json
  {
    "source_record_key": "record-...",
    "decision": "same_existing_person",
    "target_record_key": "record-...",
    "canonical_person_id": 123,
    "reason": "pdf_calamari_hierarchy_and_profile_agree",
    "evidence_sha256": "<64 hex>"
  }
  ```

  For `new_person_candidate` og `unresolved` udelades alle targetfelter. For
  `structural_or_summary` er kun `context_owner_record_key` tilladt, og kun ved
  én entydig ejer.

- [ ] **Step 5: Indhent kun nødvendige brugerafgørelser**

  Hvis evidensen har to plausible identiteter, usikkert hierarki eller usikker
  personoprettelse, vis PDF-side, ordret tekst og de konkrete alternativer til
  brugeren. Entydige tilfælde kan markeres `codex_verified`; tvivlstilfælde
  forbliver `unresolved`, indtil brugeren svarer.

- [ ] **Step 6: Fjern midlertidige renderinger og auditér 17/17-forslaget**

  Run: `find tmp/pdfs -maxdepth 1 -name '1939-remaining-identity-*.png' -delete`

  Kræv præcis én disposition pr. source key og nul canonical write-authority.

---

### Task 3: Lukket beslutningsmaterialisering

**Files:**
- Create: `.claude/skills/daa-extract/scripts/materialize_remaining_identity_decisions_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_materialize_remaining_identity_decisions_1939_v50.py`
- Generate ignored: `work/task24-1939-v50-remaining-identities/remaining-identity-decisions-v1.json`
- Generate ignored: `work/task24-1939-v50-remaining-identities/remaining-identity-decisions-v1-report.md`

**Interfaces:**
- Consumes: reviewmanifest v1, dets eksakte SHA-256 og det komplette 17-posters forslag/brugersvar.
- Produces: schema `1939-v50-remaining-identity-decisions-v1` med lukkede counts og alle gates på ikke-skrivende værdier.

- [ ] **Step 1: Skriv RED-tests for de fire dispositioner**

  ```python
  result = materialize_remaining_decisions(
      review=review, proposal=proposal, review_sha256=review_sha,
      expected_decisions=4)
  assert result["counts"] == {
      "decisions": 4, "same_existing_person": 1,
      "new_person_candidate": 1, "structural_or_summary": 1,
      "unresolved": 1,
  }
  assert result["canonical_mutations_authorized"] is False
  assert result["database_write_authorized"] is False
  ```

- [ ] **Step 2: Kør fokuseret RED**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_materialize_remaining_identity_decisions_1939_v50.py`

- [ ] **Step 3: Implementér closed-schema-validatoren**

  Kræv præcis ét proposal-row pr. reviewsubject. `same_existing_person` kræver
  kandidat/anker og canonical person-id; `new_person_candidate` og `unresolved`
  forbyder targetfelter; `structural_or_summary` tillader kun en deklareret
  context owner. Bind hver række til source span, verbatim-hash, reviewhash og
  evidenshash.

- [ ] **Step 4: Tilføj mutations- og ejerskabstests**

  Afvis duplicate/missing source, ukendt decision, skjult targetfelt, forkert
  person-id, duplicate target/person, konkurrerende kandidat uden brugerbevis,
  falsk context owner, ændret reviewhash, ændret evidenshash og enhver authority.

- [ ] **Step 5: Kør GREEN, generér realdataoutput og commit**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_materialize_remaining_identity_decisions_1939_v50.py`

  Commit: `feat(1939): materialize remaining identity decisions`

---

### Task 4: Append-only source-persona v2

**Files:**
- Create: `.claude/skills/daa-extract/scripts/materialize_remaining_source_personas_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_materialize_remaining_source_personas_1939_v50.py`
- Generate ignored: `work/task24-1939-v50-remaining-identities/source-persona-materialization-v2.json`
- Generate ignored: `work/task24-1939-v50-remaining-identities/source-persona-materialization-v2-report.md`

**Interfaces:**
- Consumes: source-persona-materialization v1, remaining-decisions v1, database-preview v1 og eksakte hashes.
- Produces: schema `1939-v50-source-persona-materialization-v2`.

- [ ] **Step 1: Skriv RED-test for deep-preservation og selektiv tilføjelse**

  Kræv at alle 24 v1-personaer er deep-equal og i samme orden, at kun
  `same_existing_person` tilføjes, og at de øvrige tre klasser står i separate
  lister uden persona-ID eller canonical mutation.

- [ ] **Step 2: Kør fokuseret RED**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q test_materialize_remaining_source_personas_1939_v50.py`

- [ ] **Step 3: Implementér v2-builderen**

  Afled nye persona-ID'er med samme UUIDv5-regel som v1. Kontrollér target-
  record/person-id mod både `matched` og `database_only`, global injectivity mod
  de eksisterende 24 og komplet disposition af alle 17 beslutninger.

- [ ] **Step 4: Tilføj negative lineage-tests**

  Afvis ændret v1-række, duplicate source/target/person, ukendt target,
  source-span-drift, category-count-drift, source/hash-drift og authority.

- [ ] **Step 5: Kør GREEN, genbyg byteidentisk og commit**

  Commit: `feat(1939): extend source persona materialization`

---

### Task 5: Read-only database-preview v3

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/preview_reimport_1939_v50_helpers.R`
- Modify: `.claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R`
- Modify: `.claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R`
- Modify: `tests/testthat/test-preview-reimport-1939-v50.R`
- Generate ignored: `work/task24-1939-v50-remaining-identities/database-preview-v3.json`
- Generate ignored: `work/task24-1939-v50-remaining-identities/database-preview-v3-report.md`

**Interfaces:**
- Consumes: import-preview v1 og source-persona-materialization v1 eller v2.
- Produces: v2-output uændret for v1-input; schema `1939-v50-database-preview-v3` for v2-input.

- [ ] **Step 1: Skriv RED-tests for kompatibilitet og nye blockers**

  V1-fixturen skal fortsat give database-preview v2. En v2-fixture skal give
  v3 med persona-count, `new_person_candidate`, `structural_or_summary` og
  `unresolved`; den samlede `genuinely_new_identity_pending:17` må ikke overleve.

- [ ] **Step 2: Kør fokuseret RED**

  Run: `Rscript .claude/skills/daa-extract/scripts/test_preview_reimport_1939_v50.R`

- [ ] **Step 3: Implementér kompatibel v1/v2-validering og v3-output**

  Bevar `BEGIN READ ONLY`, SQL-whitelist, capability checks og rollback. For v2
  kontrolleres alle nye same-targets mod den friske anchor-query. Emitér
  `genuinely_new_identity_pending:<unresolved>` og
  `genuinely_new_person_creation_pending:<new>` kun når count er positiv;
  strukturelle records rapporteres separat uden person-create-blocker.

- [ ] **Step 4: Tilføj negative R-tests**

  Afvis target mismatch, category drift, v1-lineage drift, private-table drift,
  write-authority, ukendt schema og credentialserialization.

- [ ] **Step 5: Kør live read-only v3 to gange og sammenlign semantik**

  Brug `--source-personas-sha256=<aktuel hash>`, kræv
  `transaction_read_only=on`, nul target-mismatches og semantisk identitet efter
  fjernelse af `snapshot_at`.

- [ ] **Step 6: Kør GREEN og commit**

  Commit: `feat(1939): compare remaining identities read only`

---

### Task 6: Dokumentation og slutverifikation

**Files:**
- Modify: `.claude/skills/daa-extract/SKILL.md`
- Create: `docs/superpowers/reviews/1939-v50-remaining-identity-review.md`

**Interfaces:**
- Consumes: alle Task 1-5-resultater.
- Produces: reproducerbare kommandoer, hashes, 17-posters dispositionstabel og ærlig GO/NO-GO-status.

- [ ] **Step 1: Dokumentér pipeline og eksakte gates**

  Skill-dokumentet skal vise reviewbuilder, beslutningsmaterialisering,
  source-persona v2 og database-preview v3. Rapporten skal vise hver record key,
  PDF-side, disposition, eventuelt mål, evidensgrundlag og alle hashes.

- [ ] **Step 2: Kør fuld verifikation**

  Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -B -m pytest -q`

  Run: `cd ../../../.. && Rscript run-tests.R`

  Run: `git diff --check && git status --short`

- [ ] **Step 3: Auditér private artefakter**

  Kræv at `work/task24-1939-v50-remaining-identities/` er ignoreret, at ingen
  credentialværdi forekommer i JSON/Markdown, og at canonical create/update/
  delete fortsat er tomme og `authorized: false`.

- [ ] **Step 4: Commit dokumentation og handoff**

  Commit: `docs(1939): report remaining identity review`

  Handoff skal oplyse testtal, artefakthashes, read-only-bevis, dispositions-
  counts og de præcise blockers før en senere person-create/writer-fase.
