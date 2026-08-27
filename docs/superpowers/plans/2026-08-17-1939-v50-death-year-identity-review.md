# DAA 1939 v50 Death-Year Identity Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Byg en deterministisk, review-only pakke med de 11 entydige navn-og-dødsår-kandidater blandt de 30 resterende v50 source records.

**Architecture:** Ét fokuseret Python-modul validerer de hashbundne v50-input, fjerner allerede besluttede subjects og matcher kun et ordret hovednavn plus et firecifret dødsår før første slægtskabs-overgang. Modulet emitterer et lukket JSON-manifest og en afledt Markdown-rapport; det har ingen databaseforbindelse og ingen writer.

**Tech Stack:** Python 3, standardbiblioteket (`argparse`, `hashlib`, `json`, `pathlib`, `re`), pytest og eksisterende v50 JSON-artefakter.

## Global Constraints

- Dæk præcis 30 resterende subjects, 11 kandidatlinks og 19 subjects uden link.
- Kandidaten skal være blandt præcis 543 allerede kortlagte 1939-profiler.
- Accepteret evidens er ordrette source-substrings for navn og dødsår; normalisering må ikke stå alene.
- Navn og dødsår skal ligge før første overgang til børn eller efterkommere.
- Christian Ditlev død 1738 skal forblive uden automatisk kandidat, fordi personen introduceres efter `havde Sønnen`.
- Alle subjects og links forbliver `pending`/`unresolved` og review-only.
- `canonical_mutations_authorized`, `database_write_authorized` og alle writer-/reimport-gates forbliver falske eller `NO-GO`.
- Ingen databaseadgang eller ændring af `load_daa.R`.
- Private artefakter under `work/` må ikke commits.

---

### Task 1: Lås hovedperson- og kandidatreglen test-first

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_death_year_identity_review_1939_v50.py`
- Create: `.claude/skills/daa-extract/scripts/test_build_death_year_identity_review_1939_v50.py`

**Interfaces:**
- Produces: `principal_end(source: str) -> int`
- Produces: `literal_name_signal(source: str, name: str, limit: int, record_key: str) -> dict[str, Any] | None`
- Produces: `death_year_signals(source: str, limit: int, profile: dict[str, Any]) -> list[dict[str, Any]]`
- Produces: `qualifying_candidate(source: str, profile: dict[str, Any]) -> dict[str, Any] | None`

- [ ] **Step 1: Skriv den første fej­lende test for direkte navn og dødsår**

```python
def test_qualifies_literal_principal_name_and_death_year():
    profile = profile_row("old-detlev", 1137, "Detlev", "4 Nov. 1701")
    candidate = subject.qualifying_candidate(
        "Detlev til Hemmelmark († 1701), der havde Sønnerne Heinrich ...",
        profile,
    )
    assert candidate["candidate_record_key"] == "old-detlev"
    assert [(row["kind"], row["text"]) for row in candidate["signals"]] == [
        ("literal_name", "Detlev"),
        ("literal_death_year", "1701"),
    ]
```

- [ ] **Step 2: Kør testen og observer forventet RED**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py::test_qualifies_literal_principal_name_and_death_year -q`

Expected: FAIL under import eller manglende `qualifying_candidate`.

- [ ] **Step 3: Implementér den minimale direkte regel**

```python
YEAR_RE = re.compile(r"\b1[2-9]\d{2}\b")
KINSHIP_RE = re.compile(
    r"\b(?:fader\s+til|moder\s+til|hvis\s+søn|hvis\s+datter|"
    r"der\s+havde\s+søn(?:nen|nerne)?|havde\s+søn(?:nen|nerne)?|"
    r"havde\s+datter(?:en|døtrene)?)\b",
    re.IGNORECASE,
)

def principal_end(source: str) -> int:
    match = KINSHIP_RE.search(source)
    return match.start() if match else len(source)
```

`qualifying_candidate` skal bruge `_best_literal_name` fra
`build_identity_review_1939_v50.py`, kræve at hele navnesignalet slutter før
`principal_end`, udtrække år fra profile facts med `faktatype == "død"` og
returnere eksakte offsets for det fælles år i hovedpersondelen.

- [ ] **Step 4: Kør den fokuserede test og observer GREEN**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py::test_qualifies_literal_principal_name_and_death_year -q`

Expected: `1 passed`.

- [ ] **Step 5: Tilføj negative tests for hierarki og utilstrækkelig evidens**

```python
@pytest.mark.parametrize("source_text", [
    "Detlev til Hemmelmark, der havde Sønnen Heinrich † 1701.",
    "Detlev til Hemmelmark uden dødsår.",
])
def test_rejects_year_after_transition_or_missing_year(source_text):
    profile = profile_row("old-detlev", 1137, "Detlev", "4 Nov. 1701")
    assert subject.qualifying_candidate(source_text, profile) is None

def test_rejects_name_introduced_after_parent_transition():
    profile = profile_row("old-christian", 1201, "Christian Ditlev", "1 Okt. 1738")
    source_text = "Storkansler Conrad Reventlow havde Sønnen: Christian Ditlev † 1738."
    assert subject.qualifying_candidate(source_text, profile) is None
```

- [ ] **Step 6: Kør hele den nye testfil og observer GREEN**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py -q`

Expected: alle Task 1-tests passer.

---

### Task 2: Byg og valider det lukkede reviewmanifest

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/build_death_year_identity_review_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_build_death_year_identity_review_1939_v50.py`

**Interfaces:**
- Consumes: Task 1-funktionerne og de fire hashbundne inputtyper.
- Produces: `build_death_year_review(*, mapped_review: dict[str, Any], database_preview: dict[str, Any], clean_records: list[dict[str, Any]], identity_decision_batches: list[dict[str, Any]], input_hashes: dict[str, Any], expected_subjects: int = 30, expected_links: int = 11) -> dict[str, Any]`
- Produces schema: `1939-v50-death-year-identity-review-v1`

- [ ] **Step 1: Skriv en fej­lende integrationstest med literals afledt uafhængigt**

```python
def test_builds_closed_review_with_exact_coverage_and_no_authority():
    result = subject.build_death_year_review(**fixture_inputs(), expected_subjects=2,
                                             expected_links=1)
    assert result["schema_version"] == "1939-v50-death-year-identity-review-v1"
    assert result["counts"] == {
        "subjects": 2, "profiles": 3, "candidate_links": 1,
        "linked_subjects": 1, "unlinked_subjects": 1,
    }
    assert result["review_only"] is True
    assert result["canonical_mutations_authorized"] is False
    assert result["database_write_authorized"] is False
    assert result["identity_decision_gate"] == "NO-GO"
    assert result["database_gate"] == "NO-GO"
    assert result["reimport_gate"] == "NO-GO"
```

- [ ] **Step 2: Kør integrationstesten og observer forventet RED**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py::test_builds_closed_review_with_exact_coverage_and_no_authority -q`

Expected: FAIL fordi `build_death_year_review` mangler.

- [ ] **Step 3: Implementér streng inputvalidering og manifestbygning**

Implementeringen skal:

```python
def build_death_year_review(...):
    validate_mapped_review(mapped_review)
    decided_sources, decided_person_ids = validate_decision_batches(
        identity_decision_batches)
    profiles = validate_profiles(database_preview, clean_records,
                                 expected_profiles=543)
    remaining = [row for row in mapped_review["subjects"]
                 if row["new_record_key"] not in decided_sources]
    # Kvalificér mod alle profiler; behold kun præcis ét match per subject.
    # Afvis global genbrug af candidate_record_key eller candidate_person_id.
    # Kontrollér expected_subjects og expected_links før returnering.
```

Valider `schema_version`, alle eksisterende `GO`/`NO-GO`-gates, 64-tegns
SHA-256-værdier, eksakt 543 matched profiler, entydige record-key/person-ID-par,
præcis én clean record per profil og unique source/candidate ownership.

- [ ] **Step 4: Kør integrationstesten og observer GREEN**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py::test_builds_closed_review_with_exact_coverage_and_no_authority -q`

Expected: `1 passed`.

- [ ] **Step 5: Tilføj fail-closed mutationstests**

```python
@pytest.mark.parametrize("mutation", [
    "mapped_schema", "mapped_gate", "decision_write_authority",
    "duplicate_decision_source", "profile_count", "duplicate_person_id",
    "missing_clean_profile", "subject_count", "link_count",
    "ambiguous_candidate",
])
def test_fails_closed_on_input_drift_or_ambiguity(mutation):
    inputs = fixture_inputs()
    mutate(inputs, mutation)
    with pytest.raises(subject.DeathYearIdentityReviewError):
        subject.build_death_year_review(**inputs, expected_subjects=2,
                                        expected_links=1)
```

- [ ] **Step 6: Kør hele testfilen og observer GREEN**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py -q`

Expected: alle Task 1-2-tests passer.

- [ ] **Step 7: Commit den testede builder**

```bash
git add .claude/skills/daa-extract/scripts/build_death_year_identity_review_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_build_death_year_identity_review_1939_v50.py
git commit -m "feat(1939): build death-year identity review"
```

---

### Task 3: Tilføj eksklusiv CLI-output og materialisér den virkelige reviewpakke

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/build_death_year_identity_review_1939_v50.py`
- Modify: `.claude/skills/daa-extract/scripts/test_build_death_year_identity_review_1939_v50.py`
- Generate ignored: `work/task22-1939-v50-identity-review/death-year-identity-review-v1.json`
- Generate ignored: `work/task22-1939-v50-identity-review/death-year-identity-review-v1-report.md`

**Interfaces:**
- Produces: `render_markdown(result: dict[str, Any]) -> str`
- Produces: `write_outputs(result: dict[str, Any], output_path: Path, report_path: Path) -> None`
- CLI consumes: `--mapped-review`, `--database-preview`, `--clean`, to gentagne `--identity-decisions`, `--output`, `--report`, `--expected-subjects 30`, `--expected-links 11`.

- [ ] **Step 1: Skriv fej­lende tests for eksklusiv og deterministisk output**

```python
def test_outputs_are_exclusive_and_byte_deterministic(tmp_path):
    result = subject.build_death_year_review(**fixture_inputs(), expected_subjects=2,
                                             expected_links=1)
    output, report = tmp_path / "review.json", tmp_path / "review.md"
    subject.write_outputs(result, output, report)
    first = output.read_bytes(), report.read_bytes()
    with pytest.raises(FileExistsError):
        subject.write_outputs(result, output, report)
    output.unlink(); report.unlink()
    subject.write_outputs(result, output, report)
    assert (output.read_bytes(), report.read_bytes()) == first
```

- [ ] **Step 2: Kør testen og observer forventet RED**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py::test_outputs_are_exclusive_and_byte_deterministic -q`

Expected: FAIL fordi outputfunktionerne mangler.

- [ ] **Step 3: Implementér minimal CLI, rapport og eksklusiv skrivning**

Brug `Path.open("x", encoding="utf-8", newline="\n")`, sortér hashfelter og
subjects stabilt, og slet kun den fil, som samme fejlede kald netop har oprettet.
Rapporten skal vise 30/11/19-counts, de 11 kandidatpar og alle `NO-GO`-gates.

- [ ] **Step 4: Kør hele den fokuserede testfil**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest test_build_death_year_identity_review_1939_v50.py -q`

Expected: alle tests passer.

- [ ] **Step 5: Materialisér den virkelige private pakke**

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/build_death_year_identity_review_1939_v50.py \
  --mapped-review work/task22-1939-v50-identity-review/mapped-identity-review-v1.json \
  --database-preview work/task21-1939-v50-import-preview/database-preview-v1.json \
  --clean work/task19-1939-pilot/clean_1939_v3.json \
  --identity-decisions work/task22-1939-v50-identity-review/identity-decisions-v1.json \
  --identity-decisions work/task22-1939-v50-identity-review/identity-decisions-v2.json \
  --output work/task22-1939-v50-identity-review/death-year-identity-review-v1.json \
  --report work/task22-1939-v50-identity-review/death-year-identity-review-v1-report.md \
  --expected-subjects 30 --expected-links 11
```

Expected: JSON-status med `subjects: 30`, `candidate_links: 11`,
`database_write_authorized: false`.

- [ ] **Step 6: Genbyg til en frisk tempmappe og sammenlign bytes**

Run samme CLI med output under `mktemp -d`, efterfulgt af `cmp` for både JSON
og Markdown.

Expected: begge `cmp` afslutter med exit 0.

- [ ] **Step 7: Kør fuld scriptsuite og Git-kontroller**

Run: `cd .claude/skills/daa-extract/scripts && /usr/bin/python3 -m pytest -q`

Expected: 0 failures.

Run: `git diff --check && git status --short`

Expected: kun de to tilsigtede tracked Python-filer er ændret; private
`work/`-artefakter vises ikke.

- [ ] **Step 8: Commit CLI og tests**

```bash
git add .claude/skills/daa-extract/scripts/build_death_year_identity_review_1939_v50.py \
  .claude/skills/daa-extract/scripts/test_build_death_year_identity_review_1939_v50.py
git commit -m "feat(1939): materialize death-year identity review"
```

- [ ] **Step 9: Forelæg de 11 kandidater uden at materialisere identitetsbeslutninger**

Rapportér kandidatens navn, dødsår, source record key og eksisterende person-ID.
Bed om én eksplicit samlet bekræftelse. Bevar Christian Ditlev og de øvrige 18
som synligt uafklarede.

