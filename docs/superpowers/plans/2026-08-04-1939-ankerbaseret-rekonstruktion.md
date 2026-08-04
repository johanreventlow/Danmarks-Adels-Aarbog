# 1939 ankerbaseret rekonstruktion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Genskab en profile-pinnet 1939-segmentering fra Calamari med positiv,
injektiv coverage mod de 546 historiske records — uden databaseændring eller
automatisk faktapromovering.

**Architecture:** En ny, ren Python-validator ejer coverage-kontrakten mellem
en historisk `record_key` og ét nyt kandidatanker. Den eksisterende
`segment.py` udvides kun med syntetisk beviste Calamari-layoutvarianter, og
en privat bridge-input binder de resulterende spans til rå OCR-struktur og
PDF-side. Private artefakter skrives kun under ignoreret `work/`; den
trackede kode accepterer eller afviser dem, men opfinder aldrig et match.

**Tech Stack:** Python 3 standardbibliotek, pytest, frosne private OCR/PDF
artefakter og eksisterende `.claude/skills/daa-extract/scripts/segment.py`.

## Global Constraints

- Calamari er primær ordret rendition; rå OCR leverer kun dokumenteret
  strukturhjælp og må ikke stiltiende erstatte prosa.
- Baseline på 546 `record_key`s er kompletheds-kort, ikke faktuelt facit.
- Hvert automatisk accepteret match kræver eksakt Calamari-span, PDF-side,
  rendition-hash og én rå-structure-bro; navn, nummer eller tekstlig lighed
  alene er aldrig tilstrækkeligt.
- `accepteret`, `eksplicit_dublet` og `menneskeark` er de eneste
  coverage-statusser. Uafklarethed er en fejl, ikke en default.
- Globale kandidat-id'er og baseline-`record_key`s skal være injektive.
- De syv historiske oversigtsdubletter markeres eksplicit og forfremmes aldrig
  automatisk.
- Testdata i repository er syntetiske. OCR, PDF-udsnit, coverage-ledger og
  modeloutput forbliver ignorerede arbejdsartefakter.
- Ingen ændring af `load_daa.R`, Supabase, Vercel, faktapipeline eller
  databaseposter.
- Kør `git branch --show-current` før hver mutation og hver commit.

---

### Task 1: Indfør den fail-closed coverage-kontrakt

**Files:**

- Create: `.claude/skills/daa-extract/scripts/coverage_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_coverage_1939.py`

**Interfaces:**

- Produces `validate_coverage(bundle: dict, *, expected_baseline_keys:
  set[str]) -> dict[str, dict]`.
- Bundle-formatet er præcist:

```json
{
  "schema_version": 1,
  "source": {
    "edition": "1939",
    "calamari_sha256": "64 lowercase hex",
    "raw_ocr_sha256": "64 lowercase hex",
    "pdf_sha256": "64 lowercase hex"
  },
  "entries": [{
    "baseline_record_key": "opaque-key",
    "status": "accepteret",
    "candidate": {
      "candidate_id": "1939-candidate-001",
      "postklasse": "nummereret",
      "calamari_span": {"char_from": 0, "char_to": 10},
      "pdf_pages": [496],
      "raw_structure_bridge": {
        "kind": "line_header",
        "raw_char_from": 0,
        "raw_char_to": 10
      }
    }
  }]
}
```

- `status="eksplicit_dublet"` kræver `duplicate_of_baseline_record_key`
  og må ikke indeholde `candidate`.
- `status="menneskeark"` kræver en ikke-tom `reason` og må ikke
  indeholde `candidate`.

- [ ] **Step 1: Skriv de fejlede kontrakttests**

Opret syntetiske helpers `source()`, `accepted(key, candidate_id)`,
`duplicate(key, target)` og `parked(key, reason)`. Tilføj mindst disse
tests:

```python
def test_accepts_complete_injective_coverage():
    result = validate_coverage(
        {"schema_version": 1, "source": source(), "entries": [
            accepted("rk-1", "candidate-1"),
            duplicate("rk-2", "rk-1"),
            parked("rk-3", "pdf-side-mangler"),
        ]},
        expected_baseline_keys={"rk-1", "rk-2", "rk-3"},
    )
    assert result["rk-1"]["status"] == "accepteret"

def test_rejects_duplicate_candidate_id():
    bundle = {"schema_version": 1, "source": source(), "entries": [
        accepted("rk-1", "candidate-1"),
        accepted("rk-2", "candidate-1"),
    ]}
    with pytest.raises(ValueError, match="ikke-injektiv kandidat"):
        validate_coverage(bundle, expected_baseline_keys={"rk-1", "rk-2"})
```

Tilføj separate negative tests for manglende baseline-key, ekstra key, dublet
baseline-key, ukendt status, hash med forkert format, tomt span, omvendt span,
tom PDF-sideliste, manglende rå-bro, `menneskeark` uden reason og
`eksplicit_dublet` med kandidat.

- [ ] **Step 2: Kør testene rødt**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_coverage_1939.py -q
```

Forvent: importfejl for `coverage_1939`.

- [ ] **Step 3: Implementér den mindste rene validator**

Opret `coverage_1939.py` med:

```python
ALLOWED_STATUSES = {"accepteret", "eksplicit_dublet", "menneskeark"}
POSTKLASSER = {"nummereret", "stamfader", "oversigtspost"}

def validate_coverage(bundle: dict, *, expected_baseline_keys: set[str]) -> dict[str, dict]:
    """Valider hele den private 1939-coverage; udfører ingen I/O."""
```

Valider mapping-typer før feltadgang. Kræv eksakt key-mængde mod
`expected_baseline_keys`, 64-tegns små SHA-256-strenge og tre kildehashes.
For accepterede entries kræves positivt, ikke-tomt `candidate_id`, gyldig
`postklasse`, heltals-span med `0 <= char_from < char_to`, mindst én
positiv PDF-side og rå-bro med positivt spænd. Brug sete mængder, så samme
candidate-id, span eller baseline-key giver `ValueError`. Returnér en ny
ordbog indekseret på baseline-key; mutér aldrig bundle-input.

- [ ] **Step 4: Kør coverage-testene grønt**

Kør den fokuserede kommando fra trin 2. Forvent alle tests grønne.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/coverage_1939.py .claude/skills/daa-extract/scripts/test_coverage_1939.py
git commit -m "feat: validate anchored 1939 coverage"
```

### Task 2: Gør Calamari-layoutvariationer eksplicitte og testbare

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/segment.py`
- Modify: `.claude/skills/daa-extract/scripts/test_segment_1939.py`

**Interfaces:**

- Produces `_post_start_1939(line, profile)` med en ny, snæver
  `calamari_post_header_re`-vej, som kun accepterer en nummerlinje når den
  både opfylder `POST_1939_RE` og en dokumenteret Calamari-navneform.
- Bevarer alle eksisterende 2018-20- og 1939-raw-output byte-for-byte på de
  eksisterende syntetiske fixtures.

- [ ] **Step 1: Skriv fejlede syntetiske regressionscases**

Tilføj tre små Calamari-lignende headers til `test_segment_1939.py`: et
nummer efterfulgt af tæt navn, et nummer efterfulgt af forkortet navn med
punktum og en ægte kildehenvisning med samme nummerform. Test:

```python
def test_calamari_header_accepts_documented_tight_name_layout():
    posts, _ = run_structural("   7. A. B. Reventlow\n", "1939")
    assert [post["nr_label"] for post in posts] == ["7"]

def test_calamari_header_does_not_accept_source_reference():
    posts, _ = run_structural("   7. : Se S. 521.\n", "1939")
    assert posts == []
```

Tilføj en test der sikrer, at en løbenummerlinje med almindelig prosa og uden
navnesignal fortsat afvises. Brug kun opdigtede navne.

- [ ] **Step 2: Kør de nye tests rødt**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_segment_1939.py -q -k calamari_header
```

Forvent: den positive case fejler, mens afvisningscasene består.

- [ ] **Step 3: Implementér en snæver Calamari-regel**

Tilføj en profilregex, der kræver mindst to navne-lignende tokens i de første
80 tegn efter `nr.`; initialer tæller kun sammen med mindst ét alfabetisk
token på mindst tre bogstaver. Kør denne regel **efter** den eksisterende
`dato_fortsaettelse_re` og `kildelinje_re`-afvisning og **før**
`spaerret_navn_re`-fallbacken:

```python
calamari_name = profile["calamari_post_header_re"].search(efter_markoer[:80])
gyldigt_hoved = (
    profile["navnloest_barn_re"].match(efter_markoer)
    or profile["spaerret_navn_re"].search(efter_markoer[:80])
    or calamari_name
)
```

Bevar `rest` uændret i outputtet. Ret ikke centrering, linje-id eller
strukturelle headers i denne task.

- [ ] **Step 4: Kør segmenteringsregression grønt**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_segment_1939.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_segment.py -q
```

Forvent: alle syntetiske tests grønne; private OCR-tests må fortsat skippe,
hvis input ikke findes.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/segment.py .claude/skills/daa-extract/scripts/test_segment_1939.py
git commit -m "fix: recognize bounded 1939 calamari headers"
```

### Task 3: Bind private Calamari-kandidater til eksakte kildeankre

**Files:**

- Create: `.claude/skills/daa-extract/scripts/prepare_coverage_1939.py`
- Create: `.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/coverage_1939.py`

**Interfaces:**

- Produces `build_candidates(calamari_text: str, posts: list[dict],
  raw_bridges: list[dict]) -> list[dict]`.
- Hver returneret kandidat har `candidate_id`, `postklasse`,
  `calamari_span`, `pdf_pages` og `raw_structure_bridge`.
- `raw_bridges` er en privat, eksplicit liste med
  `candidate_id`, `calamari_span`, `raw_char_from`,
  `raw_char_to`, `kind` og `pdf_pages`; funktionen må ikke
  konstruere broer ud fra navnelighed eller forsøge tekstlig søgning.

- [ ] **Step 1: Skriv fejlede anker-tests**

Brug en syntetisk Calamari-streng med to nummererede poster og en
`raw_bridges`-liste. Test både eksakt span og fejl:

```python
def test_build_candidates_preserves_exact_calamari_slice():
    text = "1. Alfa\n2. Beta\n"
    posts = [{"lokal_id": "I.1", "postklasse": None, "raw_text": "1. Alfa"}]
    result = build_candidates(text, posts, [bridge("I.1", 0, 7, [496])])
    assert result[0]["calamari_span"] == {"char_from": 0, "char_to": 7}

def test_build_candidates_rejects_bridge_without_exact_post_slice():
    with pytest.raises(ValueError, match="ikke eksakt Calamari-span"):
        build_candidates("1. Alfa\n", posts, [bridge("I.1", 1, 7, [496])])
```

Tilføj tests for to broer til samme kandidat, bro til ukendt kandidat, overlap
mellem accepterede Calamari-spans, side-uoverensstemmelse og raw-span uden
positiv længde.

- [ ] **Step 2: Kør testene rødt**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py -q
```

Forvent: importfejl for `prepare_coverage_1939`.

- [ ] **Step 3: Implementér deterministisk kandidatbygning**

Opret `prepare_coverage_1939.py`. Kræv én eksplicit bridge per kandidat,
med et Calamari-span, der er helt, positivt, ikke-overlappende og ligger inden
for `calamari_text`. Kræv, at bridge-inputtet indeholder den eksakte
`calamari_verbatim_text` og kontrollér tegn-for-tegn, at den er identisk med
`calamari_text[char_from:char_to]`; dette undgår den whitespace-normaliserede
`raw_text`-fælde. Kræv identisk, ikke-tom `pdf_pages` i post og bridge.
Oversæt `postklasse=None` til `nummereret`; accepter kun de tre
postklasser fra `coverage_1939.POSTKLASSER`. Send derefter kandidaterne
gennem den samme span- og injektivitetsvalidering som coverage-kontrakten.

- [ ] **Step 4: Kør forberedelses- og coverage-testene grønt**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py .claude/skills/daa-extract/scripts/test_coverage_1939.py -q
```

Forvent: alle tests grønne.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/prepare_coverage_1939.py .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py .claude/skills/daa-extract/scripts/coverage_1939.py
git commit -m "feat: bind 1939 candidates to exact source anchors"
```

### Task 4: Byg og auditér den private 546-coverage uden mutation

**Files:**

- Modify: `.claude/skills/daa-extract/scripts/prepare_coverage_1939.py`
- Modify: `.claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py`
- Modify: `docs/superpowers/reviews/1939-evidence-pilot.md`

**Interfaces:**

- Adds CLI:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_coverage_1939.py \
  --calamari work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --raw work_1939_stamtavle/raw.txt \
  --pdf "Dansk Adels Aarbog - Reventlow 1939.pdf" \
  --baseline work_1939_stamtavle/clean_1939_v2.json \
  --bridges work/task19-1939-pilot/structure-bridges.json \
  --out work/task19-1939-pilot/coverage.json
```

- The CLI opens output exclusively with `x`; it never overwrites an existing
  private coverage file. It exits nonzero unless all 546 baseline keys have
  exactly one permitted coverage status.

- [ ] **Step 1: Skriv de fejlede CLI-tests**

Brug `tmp_path` med syntetiske små inputfiler. Test at et eksisterende
`--out` giver `FileExistsError`, at en baseline med én uforklaret key
giver `ValueError` med `baseline-dækning fejler`, og at en fuld
syntetisk bundle skrives én gang med tre SHA-256-hashes.

- [ ] **Step 2: Kør CLI-testene rødt**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py -q -k "cli or output"
```

Forvent: fejl, fordi CLI og eksklusiv skrivning mangler.

- [ ] **Step 3: Implementér eksklusiv privat materialisering**

Læs inputs binært for SHA-256. Udled baseline-key-mængden kun fra
`record_key` i `clean_1939_v2.json`; afvis tomme eller dublette nøgler.
Byg kandidater med Task 3-funktionen, læs de eksplicitte bridges og valider
den fulde coverage med `validate_coverage`. Skriv derefter kun canonical
JSON til en ny fil med `Path.open("x", encoding="utf-8")`. Funktionen må
ikke kalde `afstem_v2.anvend_forslag`, `build_1939_v2`,
`efterudtraek_1939`, databasekode eller netværk.

- [ ] **Step 4: Kør privat audit og kontroller output**

Kør CLI'en mod de frosne private artefakter. Uanset udfald må den ikke
overskrive nogen eksisterende fil. Bekræft:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py .claude/skills/daa-extract/scripts/test_coverage_1939.py -q
git status --short
```

Forvent ved uafklarede kandidater: nonzero og ingen `coverage.json`.
Forvent ved komplet, godkendt bridge-input: ny ignoreret `coverage.json`
med 546 entries og ingen trackede artefaktændringer.

- [ ] **Step 5: Dokumentér det målte resultat og commit kun kode/dokumentation**

Ret pilotrapportens formulering `546 nummererede records` til
`546 coverage-records` og indsæt den målte fordeling
`nummereret/stamfader/oversigt/dublet/menneskeark`, inputhashes og
GO/NO-GO. Commit aldrig `work/`-output:

```bash
git branch --show-current
git add .claude/skills/daa-extract/scripts/prepare_coverage_1939.py .claude/skills/daa-extract/scripts/test_prepare_coverage_1939.py docs/superpowers/reviews/1939-evidence-pilot.md
git commit -m "feat: audit anchored 1939 coverage"
```

### Task 5: Udfør samlet regression og fastfrys næste gate

**Files:**

- Modify: `docs/superpowers/reviews/1939-evidence-pilot.md`

**Interfaces:**

- Produces a single documented status: `GO for source-record pilot only` or
  `NO-GO with exact menneskeark-count`. Neither status authorizes facts,
  identity promotion or database projection.

- [ ] **Step 1: Kør den fulde scriptsuite**

Kør:

```bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
```

Notér pass/fail/skip præcist. Hvis en historisk, urelateret test fejler, skal
den adskilles fra de fokuserede Task 1-4-resultater og ikke omklassificeres
som grøn baseline.

- [ ] **Step 2: Kør determinisme- og kontraktkontrol**

Kør segmentering og coverage-materialisering to gange mod samme private
input, men med to forskellige nye `--out`-stier. Sammenlign canonical JSON
efter at have fjernet outputfilnavn; kræv identisk hash. Kør derefter en
kopi med ét ændret Calamari-tegn, ét ændret PDF-sidenummer og én dublet
candidate-id; hver skal fejle lukket.

- [ ] **Step 3: Opdatér den endelige gate**

I pilotrapporten skal status være:

```text
GO: alle 546 keys forklaret, alle accepterede spans/PDF-sider/bridges valideret,
og menneskeark er eksplicit.
NO-GO: mindst én key, span, hash, side, bridge eller injektivitetsregel fejler.
```

Skriv aldrig `klar til databaseprojektion` i nogen af tilfældene.

- [ ] **Step 4: Commit**

```bash
git branch --show-current
git add docs/superpowers/reviews/1939-evidence-pilot.md
git commit -m "docs: record 1939 reconstruction gate"
```

## Plan self-review

- **Specdækning:** Task 1 dækker status, hashes, fail-closed coverage og
  injektivitet. Task 2 dækker den dokumenterede Calamari-headerregression.
  Task 3 binder nye kandidater til eksakte spans, sider og rå struktur.
  Task 4 materialiserer kun privat, fuld 546-coverage og retter
  pilotrapportens fejlagtige “nummererede”-betegnelse. Task 5 dækker samlet
  regression, determinisme og den ikke-producerende GO/NO-GO-gate.
- **Fuldstændighed:** Planen indeholder ingen ufærdige markører eller
  implicitte fejlveje.
- **Typekonsistens:** `candidate_id`, `postklasse`, `calamari_span`,
  `pdf_pages`, `raw_structure_bridge`, `record_key` og de tre
  coverage-statusser er identiske i alle tasks.
