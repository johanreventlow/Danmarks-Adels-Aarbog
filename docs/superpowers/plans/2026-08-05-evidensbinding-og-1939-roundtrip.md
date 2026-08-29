# Evidensbinding og 1939-roundtrip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Historisk status (2026-08-29):** Checkbokse er ikke en aktuel statuskilde.
> Den efterfølgende v50-kæde erstattede dele af roundtrip-sporet; se
> afvigelsesvurderingen 2026-08-22 §§4 og 7.1 for dokumenteret leverance og
> rester.

**Goal:** Gør hvert promotionsklart claim mekanisk sporbar til den korrekte persona, record og frosne rendition, og bind 1939-beslutninger til de baseline-bytes, de blev truffet imod.

**Architecture:** Evidence bundle-kontrakten bumpes til `1.1` og validerer alle nested objekter samt absolutte spans mod renditionens ordrette tekst. Source-record-ledgeren producerer 1.1 fra entydige absolutte ankre, claimvalideringen kræver samme persona/observation/record-kæde, og 1939-decisions bevarer baseline-hash til materialisering.

**Tech Stack:** Python 3 standardbibliotek, dataclasses, hashlib, JSON og pytest.

## Global Constraints

- Ukendt eller manglende provenance afvises fail-closed; ingen navn-, side-, nummer- eller tekstligheds-gæt.
- Raw OCR og ordret kildetekst ændres aldrig; normalisering er ikke tilladt i spanvalidering.
- `load_daa.R`, databasen, private reviewartefakter og produktionsdata må ikke ændres.
- 1939-filer med samtidige upstreamændringer redigeres først efter en frisk HEAD-/filoverlapkontrol.
- Hver produktionsændring følger RED -> GREEN -> REFACTOR og committes separat.

---

### Task 1: Valider hele evidence bundle 1.1 mod frosne renditions

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/evidence_contract.py:22-377`
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_contract.py:22-310`

**Interfaces:**

- Consumes: `schema_version="1.1"` og `source_rendition[].{rendition_id,source_id,sha256,verbatim_text}`.
- Produces: `validate_bundle(bundle: Path | Mapping[str, Any]) -> None`, som validerer alle nested collections og deres krydsreferencer.

- [ ] **Step 1: Opgrader testfixturen til en fuldt linket 1.1-bundle**

Tilføj `linked_bundle()` i `test_evidence_contract.py`. Den skal indeholde én rendition med teksten `Forord. Anna blev født 1801. Efterskrift.`, én occurrence for `Anna blev født 1801.`, én observation for `Anna`, én komplet mention, én persona med `source_id="2018-20"`, ét source record med samme source-ID og ét accepted anchor. Alle spans er absolutte `[char_from,char_to)` i renditionteksten, og `sha256` beregnes med `hashlib.sha256(text.encode("utf-8")).hexdigest()`.

- [ ] **Step 2: Skriv de røde contracttests**

```python
def test_bundle_rejects_observation_outside_its_occurrence():
    bundle = linked_bundle()
    bundle["observations"][0]["span"].update(char_from=0, char_to=4)
    bundle["observations"][0]["verbatim_text"] = "Foro"
    with pytest.raises(ContractError, match="inside its occurrence"):
        validate_bundle(bundle)

def test_bundle_rejects_unknown_nested_mention_field():
    bundle = linked_bundle()
    bundle["mentions"][0]["invented"] = True
    with pytest.raises(ContractError, match="unknown mention fields"):
        validate_bundle(bundle)

def test_bundle_rejects_rendition_hash_drift():
    bundle = linked_bundle()
    bundle["source_rendition"][0]["sha256"] = "0" * 64
    with pytest.raises(ContractError, match="rendition sha256"):
        validate_bundle(bundle)
```

- [ ] **Step 3: Kør RED**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_evidence_contract.py
```

Expected: de nye tests fejler, fordi nested collections, renditionhash og containment ikke valideres.

- [ ] **Step 4: Implementér 1.1-parseren**

Importér `hashlib`, skift versionsgaten til `"1.1"`, og tilføj:

```python
def _exact_fields(value: Mapping[str, Any], allowed: set[str], label: str) -> None:
    unknown = set(value) - allowed
    if unknown:
        raise ContractError(f"unknown {label} fields: {', '.join(sorted(unknown))}")

def _rendition_text_by_id(bundle: Mapping[str, Any]) -> dict[str, tuple[str, str]]:
    result: dict[str, tuple[str, str]] = {}
    for raw in bundle["source_rendition"]:
        _exact_fields(raw, {"rendition_id", "source_id", "sha256", "verbatim_text"}, "source rendition")
        rendition_id = _require(raw.get("rendition_id"), "rendition_id")
        source_id = _require(raw.get("source_id"), "source_id")
        text = _require(raw.get("verbatim_text"), "rendition verbatim_text")
        digest = _require(raw.get("sha256"), "rendition sha256").lower()
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != digest:
            raise ContractError("rendition sha256 does not match verbatim_text")
        if rendition_id in result:
            raise ContractError("duplicate rendition id")
        result[rendition_id] = (source_id, text)
    return result
```

Lad `_as_occurrence` og `_as_observation` slå `span.rendition_id` op her og sende hele renditionteksten til `_span_from_dict`; deres egen `verbatim_text` må aldrig være `source_text`. Parse mentions, source personas, placements og text variants med eksakte allowlists. Verificér mentionoffsets mod observationen, personaens mention-ID'er og source-ID, source-record source-ID, extraction-run-ID samt at observationens absolutte span er indeholdt i parent-occurrencens span på samme rendition.

- [ ] **Step 5: Kør GREEN**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_evidence_contract.py
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts
```

Expected: alle contracttests består; øvrige fixtures er eksplicit opgraderet til 1.1 eller tester afvisning af gammel version.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/evidence_contract.py \
  .claude/skills/daa-extract/scripts/test_evidence_contract.py
git commit -m "fix: bind evidence to frozen source renditions"
```

### Task 2: Producer absolutte recordankre i source-record-ledgeren

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/prepare_source_record_review.py:39-97`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_source_record_review.py:1-82`
- Modify: `.claude/skills/daa-extract/scripts/source_record_ledger.py:34-222`
- Modify: `.claude/skills/daa-extract/scripts/test_source_record_ledger.py:1-115`

**Interfaces:**

- Consumes: `build_accepted_review(..., rendition_text: str)` og exact-hashbundet manifest.
- Produces: obligatorisk `source_anchor.{char_from,char_to}` og evidence bundle 1.1 med absolutte spans.

- [ ] **Step 1: Skriv røde tests for source anchoring**

Kald `build_accepted_review` med keyword-argumentet `rendition_text="Forord\n" + posts[0]["raw_text"] + "\nSlut"` og assertér, at `source_anchor` starter ved `len("Forord\n")`. Tilføj en test med `text + "\n" + text`, som forventer `ReviewPreparationError("post tekstanker er ikke entydigt")`, og en ledger-test der fjerner `source_anchor` og forventer `LedgerError("source_anchor kræves")`.

- [ ] **Step 2: Kør RED**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_prepare_source_record_review.py \
  .claude/skills/daa-extract/scripts/test_source_record_ledger.py
```

Expected: signaturen mangler `rendition_text`, og ledgeren accepterer lokale spans.

- [ ] **Step 3: Implementér exact unique anchoring**

Verificér `sha256(rendition_text) == manifest.raw_text_sha256`. For hver accepteret post:

```python
start = rendition_text.find(text)
if start < 0 or rendition_text.find(text, start + 1) >= 0:
    raise ReviewPreparationError("post tekstanker er ikke entydigt")
source_anchor = {"char_from": start, "char_to": start + len(text)}
```

Gem `rendition_text` i reviewroden. Gør `source_anchor` obligatorisk i ledgeren, verificér `rendition_text[start:end] == verbatim_text`, og brug anchorens absolutte offsets som occurrence-span. Bundle 1.1's rendition indeholder source-ID, hash og ordret tekst; source records indeholder source-ID.

- [ ] **Step 4: Kør GREEN**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_prepare_source_record_review.py \
  .claude/skills/daa-extract/scripts/test_source_record_ledger.py
```

Expected: alle fokuserede tests består, inklusive opaque-key-, idempotens- og drifttests.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/prepare_source_record_review.py \
  .claude/skills/daa-extract/scripts/test_prepare_source_record_review.py \
  .claude/skills/daa-extract/scripts/source_record_ledger.py \
  .claude/skills/daa-extract/scripts/test_source_record_ledger.py
git commit -m "fix: require absolute source record anchors"
```

### Task 3: Bind personclaims til samme personas citerede observationer

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/evidence_extract.py:129-199`
- Modify: `.claude/skills/daa-extract/scripts/test_evidence_extract.py:63-215`

**Interfaces:**

- Consumes: en valideret evidence bundle 1.1.
- Produces: `validate_output(output)`, som kræver, at alle observationer citeret af et `person.*`-claim er mentions for claimets egen persona og ligger i claimets record.

- [ ] **Step 1: Opgrader extractionfixturen til 1.1**

Lad `_anchored_bundle()` have renditiontekst, source-ID på record/persona, komplette mentionoffsets og ét accepted anchor. Tilføj `two_person_bundle()` med to komplette rendition -> occurrence -> record -> observation -> mention -> persona-kæder.

- [ ] **Step 2: Skriv den røde krydspersona-test**

```python
def test_person_claim_rejects_another_personas_observation():
    bundle = two_person_bundle()
    with pytest.raises(ExtractionError, match="PERSONA_OBSERVATION"):
        validate_output({"evidence_bundle": bundle, "claims": [{
            "predicate": "person.name", "record_key": "rk-b",
            "source_persona_id": "persona-a", "observation_ids": ["obs-b"],
            "value": "Bodil",
        }]})
```

- [ ] **Step 3: Kør RED**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_evidence_extract.py::test_person_claim_rejects_another_personas_observation
```

Expected: claimet accepteres fejlagtigt, eller den forventede fejlkode mangler.

- [ ] **Step 4: Implementér persona-observation-record-kontrollen**

Erstat booleanen `persona_records` med et observation-map:

```python
persona_observations: dict[str, set[str]] = {}
for persona in bundle["source_personas"]:
    persona_id = str(persona["persona_id"])
    persona_observations[persona_id] = {
        mention_observation[str(mention_id)] for mention_id in persona["mention_ids"]
    }
```

For hvert personclaim skal `set(observation_ids)` være en delmængde af personaens observationer, og hver citeret observation skal gennem sit accepted anchor give claimets `record_key`. Ellers rejses `EXTRACTION_PERSONA_OBSERVATION_REQUIRED`. Den generelle record-key-gate bevares for alle claims.

- [ ] **Step 5: Kør GREEN**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_evidence_extract.py \
  .claude/skills/daa-extract/scripts/test_evidence_contract.py
```

Expected: alle tests består; ikke-personlig heraldik kræver fortsat ingen kunstig persona.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/evidence_extract.py \
  .claude/skills/daa-extract/scripts/test_evidence_extract.py
git commit -m "fix: bind person claims to persona observations"
```

### Task 4: Bevar og genvalidér 1939-baseline-hash

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/prepare_coverage_1939.py:418-499`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py:230-620`

**Interfaces:**

- Consumes: review/choice-root med schema-version, `edition="1939"`, `baseline_sha256` og entries.
- Produces: decisions-root med samme metadata og `materialize_coverage`, der afviser stale baseline før output åbnes.

- [ ] **Step 1: Kontrollér upstream-overlap**

```bash
git branch --show-current
git status --short --branch
git -C ../evidensbaseret-genimport rev-parse HEAD
git -C ../evidensbaseret-genimport status --short
git diff --name-only 2a02013..feat/evidensbaseret-genimport -- \
  .claude/skills/daa-extract/scripts/prepare_coverage_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
```

Hvis upstream har nye committed ændringer i filerne, integreres committene først. Dirty upstreamfiler må ikke kopieres eller overskrives.

- [ ] **Step 2: Skriv røde roundtriptests**

```python
def test_review_to_decisions_preserves_baseline_identity():
    review = complete_review()
    decisions = review_to_decisions(review)
    assert decisions["schema_version"] == review["schema_version"]
    assert decisions["edition"] == "1939"
    assert decisions["baseline_sha256"] == review["baseline_sha256"]
```

Tilføj også en materialiseringstest, der ændrer `decisions["baseline_sha256"]` til `"0" * 64`, forventer `ValueError("decisions baseline SHA-256 matcher ikke")` og asserterer, at outputfilen ikke findes.

- [ ] **Step 3: Kør RED**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py \
  -k 'preserves_baseline_identity or decisions_for_other_baseline'
```

Expected: decisions mangler metadata, og same-key stale baseline accepteres.

- [ ] **Step 4: Implementér hashbundet decisions-root**

`review_to_decisions` returnerer reviewets schema-version, edition og baseline-hash sammen med entries. I `materialize_coverage`, før kildefiler behandles eller `out_path` åbnes:

```python
if decisions_root.get("edition") != "1939":
    raise ValueError("decisions kontrakt er ugyldig")
if decisions_root.get("baseline_sha256") != _sha256(baseline_path):
    raise ValueError("decisions baseline SHA-256 matcher ikke")
```

Schema-versionen skal være identisk med den integrerede reviewkontrakt. Bevar alle stærkere source-/choice-hashchecks fra undtagelseskøen.

- [ ] **Step 5: Kør GREEN**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py \
  .claude/skills/daa-extract/scripts/test_review_choices_1939.py \
  .claude/skills/daa-extract/scripts/test_review_queue_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_review_queue_1939.py
```

Expected: alle tests består, og ingen privat reviewfil ændres.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/prepare_coverage_1939.py \
  .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py
git commit -m "fix: bind 1939 decisions to reviewed baseline"
```

### Task 5: Samlet evidensgate

**Files:**

- Verify only: `.claude/skills/daa-extract/scripts/`

**Interfaces:**

- Consumes: Tasks 1-4.
- Produces: frisk testbevis og ren worktree.

- [ ] **Step 1: Kør hele scriptsuiten**

```bash
/usr/bin/python3 -m pytest -q -p no:cacheprovider \
  .claude/skills/daa-extract/scripts
```

Expected: alle tests består; skips rapporteres med eksakt antal.

- [ ] **Step 2: Kør de tre tidligere reproduktioner som navngivne tests**

Kør observation-outside-occurrence, cross-persona-claim og stale 1939-baseline enkeltvis. Expected: alle tre består ved at observere den tilsigtede fail-closed fejl.

- [ ] **Step 3: Kontrollér diff og worktree**

```bash
git diff --check
git status --short --branch
git log --oneline -5
```

Expected: ingen whitespacefejl eller ucommittede filer; kun de planlagte commits ligger oven på designcommitten.
