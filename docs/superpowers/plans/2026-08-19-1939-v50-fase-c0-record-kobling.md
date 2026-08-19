# 1939 v50 fase C0 — kobling af de 41 »ægte nye« records: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afgøre alle 41 kilderecords, der fejlagtigt blev klassificeret
`accepted_genuinely_new_source_record`, mod prods eksisterende 1939-personer —
og levere afgørelserne som en menneskeredigerbar token-fil, uden at skrive
til produktionsdatabasen.

**Architecture:** Read-only R-eksport af prods 1939-narrativbestand (projektets
DB-mønster) → ren, deterministisk Python-matchning mod de hash-låste
preview-artefakter → rapport med lukning begge veje → token-fil med udfyldte
anbefalinger + fail-closed konverter. Ingen writer, intet manifest, ingen
prod-mutation i denne plan.

**Tech Stack:** Python 3 (stdlib alene: `difflib`, `unicodedata`, `hashlib`,
`json`, `re`, `argparse`), pytest 8.4.2, R m. DBI/RPostgres/jsonlite, testthat.

**Spec:** `docs/superpowers/specs/2026-08-19-1939-v50-fase-c0-record-kobling-design.md`

## Global Constraints

- **Ingen prod-skrivning i denne plan.** Ingen RPC-kald, intet manifest, ingen
  `apply_migration`. R-scriptet kører rene `SELECT`s.
- **Verbatim er uforanderligt.** Rendition, spans og `citat_tekst` normaliseres
  aldrig. Al normalisering sker i hukommelsen til sammenligning.
- **Hash-låste input.** `import-preview-v1.json` =
  `04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5`;
  `database-preview-v1.json` =
  `a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c`;
  `boundary-materialization-v3-ditlev.json` =
  `73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f`.
  Filnavne-versionering (`…-v33` … `-v49`) er IKKE en ordning og må aldrig
  bruges til at vælge input.
- **Determinisme.** Samme input → samme output-bytes, uafhængigt af
  `PYTHONHASHSEED`. Ingen tidsstempler eller tilfældighed i output-*indhold*.
- **Fail-closed.** Manglende, tvetydige eller uventede data → lavere
  anbefalingsklasse eller `sys.exit(2)` med en navngiven fejlkode. Aldrig en
  udfyldt kobling på usikkert grundlag.
- **`work/` committes aldrig.** Kun scripts, tests og docs committes.
- **`load_daa.R` røres ikke og kaldes ikke.**
- **Supabase-MCP'en i denne session peger på en anden organisation
  (`BFH Metadata`) end DAA-basen.** Prod nås udelukkende via R/psql med
  `~/.Renviron`. Forsøg ikke at læse DAA-prod gennem MCP.
- Fejlkoder er `SCREAMING_SNAKE_CASE` med prefix `C0_`, som i de øvrige
  v50-scripts.

## File Structure

| Fil | Ansvar |
|---|---|
| `.claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50_helpers.R` | Ren funktion: rækker → eksportdokument. Testbar uden DB. |
| `.claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50.R` | CLI: read-only SELECT mod prod → JSON. |
| `.claude/skills/daa-extract/scripts/match_c0_records_1939_v50.py` | Ren matchningslogik: skelet-normalisering, tre signaler, klassificering. Ingen I/O. |
| `.claude/skills/daa-extract/scripts/build_c0_record_linkage_1939_v50.py` | CLI: hash-validerer input, kører matchning, skriver kandidat-JSON + rapport. |
| `.claude/skills/daa-extract/scripts/convert_c0_linkage_decisions_1939_v50.py` | `generate` + `convert` af token-filen, fail-closed. |
| `.claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py` | pytest for matchningslogikken. |
| `.claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py` | pytest for byggerens gates og lukning. |
| `.claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py` | pytest for token-filens kontrakt. |
| `tests/testthat/test-export-c0-narrative-state-1939-v50.R` | testthat for R-helperen. |

Arbejdsmappe for artefakter: `work/task26-1939-v50-c0-record-linkage/`.

---

## Task 1: Read-only eksport af prods 1939-narrativbestand

Fase B's restmængde skal **genmåles**, ikke arves. Preview'ens
`person_anchors.database_only` er frosset 2026-08-17 og er ikke facit:
verificeret 2026-08-19 deler den kun 22 af 23 medlemmer med
gammel-tekst-listen (1802 hhv. 991 er unikke for hver liste).

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50.R`
- Test: `tests/testthat/test-export-c0-narrative-state-1939-v50.R`

**Interfaces:**
- Consumes: intet fra tidligere tasks.
- Produces: `work/task26-1939-v50-c0-record-linkage/narrative-state-v1.json` med
  `{schema_version: "1.0", database_name, database_identity, generator,
  sql_text, rows: [{person_id: int, visning_navn: str, staged: bool,
  side: str|null, privat: bool, tekst: str, tekst_sha256: str,
  har_record_binding: bool}]}`, sorteret på `person_id`.
  R-funktionen hedder `build_c0_narrative_state_export_1939_v50(rows,
  database_name, database_identity, generator, sql_text)`.

- [ ] **Step 1: Skriv den fejlende test**

Opret `tests/testthat/test-export-c0-narrative-state-1939-v50.R`:

```r
source(file.path("..", "..", ".claude", "skills", "daa-extract", "scripts",
                 "export_c0_narrative_state_1939_v50_helpers.R"))

test_that("eksporten sorterer på person_id og bevarer tekst byte-eksakt", {
  rows <- data.frame(
    person_id = c(1299, 929),
    visning_navn = c("Ferdinand Einar Julius Gottlieb", "Henrik [Reventlow]"),
    staged = c(FALSE, TRUE),
    side = c("574-75", NA_character_),
    privat = c(FALSE, FALSE),
    tekst = c("Greve Ferdinand\ntil Vindeholme", "Henrik"),
    tekst_sha256 = c(strrep("a", 64), strrep("b", 64)),
    har_record_binding = c(FALSE, FALSE),
    stringsAsFactors = FALSE
  )
  doc <- build_c0_narrative_state_export_1939_v50(
    rows, database_name = "postgres", database_identity = "42",
    generator = "test:v1", sql_text = "SELECT 1")
  expect_equal(doc$schema_version, "1.0")
  expect_equal(vapply(doc$rows, function(r) r$person_id, numeric(1)), c(929, 1299))
  expect_equal(doc$rows[[2]]$tekst, "Greve Ferdinand\ntil Vindeholme")
  expect_true(doc$rows[[1]]$staged)
  # NA, ikke NULL: jsonlite skriver NULL i en liste som `{}` (et tomt objekt),
  # hvilket Python ville læse som en truthy dict. NA bliver til `null` -> None.
  expect_true(is.na(doc$rows[[1]]$side))
})

test_that("dublet person_id afvises", {
  rows <- data.frame(
    person_id = c(1, 1), visning_navn = c("A", "B"), staged = c(FALSE, FALSE),
    side = c(NA_character_, NA_character_), privat = c(FALSE, FALSE),
    tekst = c("x", "y"), tekst_sha256 = c(strrep("a", 64), strrep("b", 64)),
    har_record_binding = c(FALSE, FALSE), stringsAsFactors = FALSE)
  expect_error(
    build_c0_narrative_state_export_1939_v50(rows, "postgres", "42", "test:v1", "SELECT 1"),
    "C0_EXPORT_DUPLICATE_PERSON")
})
```

- [ ] **Step 2: Kør testen og bekræft at den fejler**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-export-c0-narrative-state-1939-v50.R")'`
Expected: FAIL — `could not find function "build_c0_narrative_state_export_1939_v50"`.

- [ ] **Step 3: Skriv helperen**

Opret `export_c0_narrative_state_1939_v50_helpers.R`:

```r
## Ren transformation: DB-rækker -> eksportdokument. Ingen DB-adgang, så
## den kan testes uden forbindelse (mønster fra
## export_narrative_old_sha_1939_v50_helpers.R).
build_c0_narrative_state_export_1939_v50 <- function(rows, database_name,
                                                     database_identity,
                                                     generator, sql_text) {
  if (anyDuplicated(rows$person_id)) stop("C0_EXPORT_DUPLICATE_PERSON", call. = FALSE)
  if (any(!grepl("^[0-9a-f]{64}$", rows$tekst_sha256))) stop("C0_EXPORT_SHA_INVALID", call. = FALSE)
  order_index <- order(rows$person_id)
  out <- lapply(order_index, function(i) {
    list(
      person_id = as.numeric(rows$person_id[[i]]),
      visning_navn = as.character(rows$visning_navn[[i]]),
      staged = as.logical(rows$staged[[i]]),
      # NA (ikke NULL) -> jsonlite skriver `null`; NULL ville blive `{}`.
      side = if (is.na(rows$side[[i]])) NA else as.character(rows$side[[i]]),
      privat = as.logical(rows$privat[[i]]),
      tekst = as.character(rows$tekst[[i]]),
      tekst_sha256 = as.character(rows$tekst_sha256[[i]]),
      har_record_binding = as.logical(rows$har_record_binding[[i]])
    )
  })
  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       sql_text = sql_text, row_count = length(out), rows = out)
}
```

- [ ] **Step 4: Kør testen og bekræft at den passerer**

Run: `Rscript -e 'testthat::test_file("tests/testthat/test-export-c0-narrative-state-1939-v50.R")'`
Expected: PASS (2/2).

- [ ] **Step 5: Skriv CLI-scriptet**

Opret `export_c0_narrative_state_1939_v50.R` som en tro kopi af strukturen i
`export_narrative_old_sha_1939_v50.R` (samme CLI-validering, samme
`env_or`-forbindelse, samme `--expect-database-name`-gate, samme
`output exists`-afvisning), med disse to ændringer — fejlkode-prefix
`C0_EXPORT_NARRATIVE_STATE` og denne forespørgsel:

```r
sql_text <- paste(
  "SELECT n.subjekt_id AS person_id, p.visning_navn, p.staged,",
  "n.side, n.privat, n.tekst,",
  "encode(sha256(convert_to(n.tekst,'UTF8')),'hex') AS tekst_sha256,",
  "EXISTS (SELECT 1 FROM narrative_record_publication b",
  "        WHERE b.narrative_id = n.id) AS har_record_binding",
  "FROM narrative n JOIN person p ON p.id = n.subjekt_id",
  "WHERE n.subjekt_type='person' AND n.source_id=3 ORDER BY n.subjekt_id"
)
```

Verificér kolonnenavnene mod `schema.sql` før kørsel; afviger
`narrative_record_publication`s FK-navn, rettes forespørgslen (ikke
helperen). `sha256()` er ukvalificeret her med vilje: den er en indbygget
pgcrypto-fri funktion i PG 17, i modsætning til `digest()`, som fase B måtte
skema-kvalificere fordi prods `search_path` mangler `extensions`.

- [ ] **Step 6: Kør eksporten mod prod (read-only)**

Run:
```bash
mkdir -p work/task26-1939-v50-c0-record-linkage
Rscript .claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50.R \
  --output work/task26-1939-v50-c0-record-linkage/narrative-state-v1.json
shasum -a 256 work/task26-1939-v50-c0-record-linkage/narrative-state-v1.json
```
Expected: `row_count` = 577 (prods source_id=3-bestand pr. fase B).

- [ ] **Step 6b: Verificér at binding-proxyen måler det rigtige**

`har_record_binding == false` er en *proxy* for »teksten er stadig
gammel«. Den skal efterprøves, før Task 3 bygger sin lukning på den —
ellers navngiver rapporten de forkerte personer som fund.

Run:
```bash
python3 - <<'PY'
import json
doc = json.load(open("work/task26-1939-v50-c0-record-linkage/narrative-state-v1.json"))
unbound = sorted(r["person_id"] for r in doc["rows"] if not r["har_record_binding"])
print("rækker:", doc["row_count"], "| uden binding:", len(unbound))
print(unbound)
empirisk = {929,930,933,934,935,940,963,967,974,977,978,992,1013,1014,1017,
            1021,1135,1138,1296,1297,1298,1299,1802}
print("i empirisk, ikke i proxy:", sorted(empirisk - set(unbound)))
print("i proxy, ikke i empirisk:", sorted(set(unbound) - empirisk))
PY
```

Fase B skrev 551 upserts / 543 publiceringer, og 8 var publiceret i
forvejen. Er dækningen 551 af 577, er det ubundne sæt 26 — ikke 23. **Kræv
en forklaring på hver afvigelse fra den empiriske liste** (som stammer fra
gårsdagens prod-måling). Er afvigelsen ikke forklarlig, er proxyen forkert,
og gammel-tekst-sættet skal i stedet udledes ved at sammenholde
`tekst_sha256` med fase B-manifestets `expected_new`-shas. STOP og rapportér
frem for at gætte — hele lukningen hviler på dette sæt.

Afviger `row_count` fra 577, STOP ligeledes: bestanden har ændret sig siden
fase B, og alle efterfølgende tal skal revurderes.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50_helpers.R \
        .claude/skills/daa-extract/scripts/export_c0_narrative_state_1939_v50.R \
        tests/testthat/test-export-c0-narrative-state-1939-v50.R
git commit -m "feat(1939): read-only eksport af 1939-narrativbestanden til fase C0"
```

---

## Task 2: Matchningslogikken (ren, deterministisk, uden I/O)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/match_c0_records_1939_v50.py`
- Test: `.claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py`

**Interfaces:**
- Consumes: intet fra tidligere tasks (rene funktioner over almindelige dicts).
- Produces:
  - `COMPARE_VERSION = "c0_compare_v1"`
  - `text_skeleton(raw: str) -> str`
  - `similarity(a_skeleton: str, b_skeleton: str) -> dict` →
    `{"ratio": float, "coverage": float,
      "containment": "none"|"record_in_person"|"person_in_record"|"exact"}`
  - `name_signal(verbatim: str, visning_navn: str) -> bool`
  - `page_signal(record_pages: dict|None, person_side: str|None) -> bool|None`
  - `classify(candidates: list[dict], record_skeleton_len: int) -> str` →
    `"kobling"|"gennemgang"|"sammenlaegning"|"aegte_ny"|"for_kort"`
  - Tærskler som modul-konstanter: `CANDIDATE_COVERAGE = 0.55`,
    `STRONG_COVERAGE = 0.85`, `MIN_SKELETON_CHARS = 60`.

**Hvorfor `MIN_SKELETON_CHARS`:** målt på det ægte grundlag er de 41
recordskeletter mellem 10 og 918 tegn; **6 er under 60**. Den korteste er
«4. Margrethe.» → `4margrethe`. Med min-normaliseret coverage matcher den
ethvert narrativ der indeholder ordet »Margrethe« med coverage ≈1.0 og
containment `record_in_person`. Uden en nedre grænse ville de seks
producere dusinvis af kandidater hver og blive klassificeret
`sammenlaegning` — altså rutet til C3 som fragmenter, hvilket de ikke er.
De er for korte til at bære et tekstsignal, og det er en femte, ærlig
klasse: `for_kort`.

**Hvorfor `coverage` og ikke `ratio`:** `SequenceMatcher.ratio()` er
symmetrisk — `2·M/(len(a)+len(b))`. En record på 400 tegn der ligger
*perfekt* inde i et narrativ på 4000 tegn scorer ≈0.18. Med en
ratio-tærskel ville den kun overleve via eksakt containment, som ét
transponeret OCR-tegn ødelægger — og så bliver en ægte match stemplet
`aegte_ny` uden flag. Det er nøjagtig den fejlklasse C0 findes for at
fange. `coverage = matchede tegn / min(længderne)` er ~1.0 for »record
ligger i narrativ med lidt OCR-støj«, uanset længdeforskellen. `ratio`
beholdes i outputtet som information, men styrer intet.

**Hvorfor skelet-normalisering frem for `narrative_norm_v1`:** designdokumentet
foreslog at genbruge fase B's transform til sammenligning. Under
planlægningen viste det sig både enklere og strengere at sammenligne på et
*skelet* — kun alfanumeriske tegn, casefoldet. Det gør ombrydning, bindestreger
og OCR-indsatte mellemrum irrelevante uden at arve norm_v1's beslutninger om
tvetydige bindestreger. Kalibreringsankeret «Gottlie b» → «gottlieb» er
netop den klasse. Verbatim røres stadig aldrig.

- [ ] **Step 1: Skriv de fejlende tests**

Opret `test_match_c0_records_1939_v50.py`:

```python
import importlib.util
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "match_c0_records_1939_v50",
    Path(__file__).resolve().parent / "match_c0_records_1939_v50.py")
m = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(m)


def test_skeleton_fjerner_ombrydning_og_ocr_mellemrum():
    a = m.text_skeleton("5. Greve Ferdinand Einar Julius Gottlie b til\nVindeholme")
    b = m.text_skeleton("Greve Ferdinand Einar Julius Gottlieb til Vindeholme")
    assert a.endswith("gottliebtilvindeholme")
    assert b in a


def test_skeleton_er_idempotent():
    once = m.text_skeleton("A-\nbe  c.")
    assert m.text_skeleton(once) == once


def test_similarity_exact():
    s = m.similarity("abc", "abc")
    assert s["containment"] == "exact"
    assert s["ratio"] == 1.0
    assert s["coverage"] == 1.0


def test_kort_record_i_lang_narrativ_er_kandidat():
    # Den fælde ratio() ville falde i: perfekt delstreng, stor længdeforskel.
    record = m.text_skeleton("Greve Ferdinand Einar Julius Gottlie b til Vindeholme")
    person = m.text_skeleton("x" * 3000 + "Greve Ferdinand Einar Julius Gottlieb til Vindeholme" + "y" * 3000)
    s = m.similarity(record, person)
    assert s["coverage"] >= 0.9
    assert s["ratio"] < 0.3  # dokumenterer hvorfor ratio ikke må styre


def test_similarity_containment_begge_veje():
    assert m.similarity("abc", "xxabcxx")["containment"] == "record_in_person"
    assert m.similarity("xxabcxx", "abc")["containment"] == "person_in_record"
    assert m.similarity("abc", "def")["containment"] == "none"


def test_name_signal_taaler_ocr_mellemrum_og_klammer():
    assert m.name_signal("Greve Ferdinand Einar Julius Gottlie b til", "Ferdinand Einar Julius Gottlieb")
    assert m.name_signal("Henrik Reventlow, f. 1600", "Henrik [Reventlow]")
    assert not m.name_signal("Christian Ditlev", "Anna Sophie")


def test_page_signal_er_none_naar_side_mangler():
    assert m.page_signal({"page_from": 574, "page_to": 575}, None) is None
    assert m.page_signal(None, "574-75") is None


def test_page_signal_matcher_overlap():
    assert m.page_signal({"page_from": 574, "page_to": 575}, "574-75") is True
    assert m.page_signal({"page_from": 574, "page_to": 575}, "575") is True
    assert m.page_signal({"page_from": 574, "page_to": 575}, "601") is False


LANG = 400  # skeletlængde over MIN_SKELETON_CHARS


def test_classify_kobling_kraever_bekraeftende_signal():
    cand = [{"person_id": 1299, "coverage": 0.97, "containment": "record_in_person",
             "name_signal": True, "page_signal": True}]
    assert m.classify(cand, LANG) == "kobling"


def test_classify_gennemgang_naar_kun_tekst_taler():
    cand = [{"person_id": 1299, "coverage": 0.97, "containment": "record_in_person",
             "name_signal": False, "page_signal": None}]
    assert m.classify(cand, LANG) == "gennemgang"


def test_classify_sammenlaegning_ved_flere_kandidater():
    cand = [{"person_id": 1296, "coverage": 0.95, "containment": "person_in_record",
             "name_signal": True, "page_signal": True},
            {"person_id": 1297, "coverage": 0.93, "containment": "person_in_record",
             "name_signal": True, "page_signal": True}]
    assert m.classify(cand, LANG) == "sammenlaegning"


def test_classify_aegte_ny_uden_kandidater():
    assert m.classify([], LANG) == "aegte_ny"


def test_classify_er_fail_closed_ved_svag_daekning():
    cand = [{"person_id": 5, "coverage": 0.56, "containment": "none",
             "name_signal": True, "page_signal": True}]
    assert m.classify(cand, LANG) == "gennemgang"


def test_kort_record_bliver_for_kort_ikke_sammenlaegning():
    # "4. Margrethe." -> "4margrethe" (10 tegn) matcher promiskuøst.
    # Den må ALDRIG rutes til C3 som fragment.
    cand = [{"person_id": i, "coverage": 1.0, "containment": "record_in_person",
             "name_signal": True, "page_signal": None} for i in (10, 11, 12)]
    assert m.classify(cand, len(m.text_skeleton("4. Margrethe."))) == "for_kort"


def test_kort_record_uden_kandidater_er_ogsaa_for_kort():
    assert m.classify([], 10) == "for_kort"
```

- [ ] **Step 2: Kør testene og bekræft at de fejler**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py -v`
Expected: FAIL — `FileNotFoundError` / modulet findes ikke.

- [ ] **Step 3: Skriv modulet**

Opret `match_c0_records_1939_v50.py`:

```python
#!/usr/bin/env python3
"""Deterministisk matchning af DAA 1939 v50's 41 »ægte nye« kilderecords
mod prods eksisterende 1939-personer (fase C0).

Rene funktioner, ingen I/O, ingen database, ingen model. Klassifikationen
der omgøres (``accepted_genuinely_new_source_record``) blev truffet
model-assisteret; det der omgør den skal være genkørbart og reviewbart.

Ingen af disse funktioner kobler noget. De producerer en ANBEFALING;
mennesket træffer alle 41 afgørelser.
"""
from __future__ import annotations

import difflib
import re
import unicodedata
from typing import Any, Dict, List, Optional

COMPARE_VERSION = "c0_compare_v1"

# Tærskler styrer KUN hvilken anbefaling der udfyldes og hvilken rækkefølge
# posterne står i -- aldrig hvad der sker med data. Kalibreret i Task 3 mod
# BEGGE ankre: person 1299 (skal blive kobling) og von Carlstein-noten
# (skal blive aegte_ny).
CANDIDATE_COVERAGE = 0.55
STRONG_COVERAGE = 0.85

_NON_ALNUM = re.compile(r"[^0-9a-z]+")


def text_skeleton(raw: str) -> str:
    """Reducér til sammenligningsskelet: NFC, casefold, kun alfanumerisk.

    Fjerner ombrydning, bindestreger, tegnsætning og OCR-indsatte mellemrum
    i ét greb, så «Gottlie b» og «Gottlieb» er samme streng. Bruges KUN til
    sammenligning -- resultatet skrives aldrig nogen steder."""
    folded = unicodedata.normalize("NFC", raw).casefold()
    return _NON_ALNUM.sub("", folded)


def similarity(a_skeleton: str, b_skeleton: str) -> Dict[str, Any]:
    """``coverage`` er det styrende mål; ``ratio`` er kun information.

    ``autojunk=False`` er ikke valgfrit: autojunk kasserer tegn der optræder
    i mere end 1 % af en lang streng, og på et skelet af små bogstaver ville
    det stille og roligt smide de almindelige bogstaver væk."""
    if a_skeleton == b_skeleton and a_skeleton:
        return {"ratio": 1.0, "coverage": 1.0, "containment": "exact"}
    containment = "none"
    if a_skeleton and a_skeleton in b_skeleton:
        containment = "record_in_person"
    elif b_skeleton and b_skeleton in a_skeleton:
        containment = "person_in_record"
    matcher = difflib.SequenceMatcher(None, a_skeleton, b_skeleton, autojunk=False)
    matched = sum(block.size for block in matcher.get_matching_blocks())
    denominator = min(len(a_skeleton), len(b_skeleton)) or 1
    return {
        "ratio": round(matcher.ratio(), 6),
        "coverage": round(matched / denominator, 6),
        "containment": containment,
    }


NGRAM = 20


def shares_ngram(a_skeleton: str, b_skeleton: str) -> bool:
    """Billigt forfilter: kræv mindst ét fælles sammenhængende n-gram, før
    den dyre sammenligning køres. Korte skeletter (< 2·NGRAM) undtages —
    ellers ville forfilteret selv skjule netop de korte records."""
    if len(a_skeleton) < 2 * NGRAM or len(b_skeleton) < 2 * NGRAM:
        return True
    grams = {a_skeleton[i:i + NGRAM] for i in range(len(a_skeleton) - NGRAM + 1)}
    return any(b_skeleton[i:i + NGRAM] in grams
               for i in range(len(b_skeleton) - NGRAM + 1))


def name_signal(verbatim: str, visning_navn: str) -> bool:
    """Sandt hvis personens navn optræder i recordens tekst.

    Klammer i visning_navn (``Henrik [Reventlow]``, loaderens markering af
    udledt slægtsnavn) forsvinder i skelettet, så navnet sammenlignes som
    det læses."""
    name = text_skeleton(visning_navn)
    if len(name) < 4:
        return False
    return name in text_skeleton(verbatim)


_PAGE_NUM = re.compile(r"\d+")


def page_signal(record_pages: Optional[Dict[str, int]],
                person_side: Optional[str]) -> Optional[bool]:
    """Sandt/falsk ved sideoverlap; ``None`` når signalet ikke kan afgøres.

    ``None`` nedgraderer anbefalingen, men spærrer ikke posten -- manglende
    sidehenvisning er almindeligt i de gamle importrækker og siger intet om
    identiteten.

    Reglen er ETHVERT overlap, ikke alle-inden-for: prods sidefelter er
    ujævne (én trykt side kan dække to kildesider), så et strengere krav
    ville give falske negativer. Signalet kan kun OPGRADERE en anbefaling --
    det spærrer aldrig -- så et generøst overlap er den sikre retning."""
    if not record_pages or not person_side:
        return None
    numbers = [int(n) for n in _PAGE_NUM.findall(person_side)]
    if not numbers:
        return None
    lo, hi = record_pages["page_from"], record_pages["page_to"]
    # "574-75" betyder 574-575: et forkortet slut-tal udvides mod start-tallet.
    expanded = []
    for index, value in enumerate(numbers):
        if index > 0 and value < numbers[0]:
            prefix = str(numbers[0])[: len(str(numbers[0])) - len(str(value))]
            value = int(prefix + str(value)) if prefix else value
        expanded.append(value)
    return any(lo <= value <= hi for value in expanded)


MIN_SKELETON_CHARS = 60


def classify(candidates: List[Dict[str, Any]], record_skeleton_len: int) -> str:
    """Klassificér en record ud fra dens kandidatliste og dens egen længde.

    Fail-closed: enhver tvivl falder til ``gennemgang``/``for_kort``, aldrig
    til ``kobling``.

    ``for_kort`` går FORAN alt andet: en record på 10 skeletttegn
    («4. Margrethe.») matcher promiskuøst, og dens kandidatliste er støj,
    ikke evidens. At kalde den ``sammenlaegning`` ville rute den til C3 som
    et fragment, den ikke er."""
    if record_skeleton_len < MIN_SKELETON_CHARS:
        return "for_kort"
    strong = [c for c in candidates if c["coverage"] >= CANDIDATE_COVERAGE
              or c["containment"] != "none"]
    if not strong:
        return "aegte_ny"
    if len(strong) > 1:
        return "sammenlaegning"
    only = strong[0]
    corroborating = sum(1 for signal in (only.get("name_signal"), only.get("page_signal"))
                        if signal is True)
    text_is_strong = only["coverage"] >= STRONG_COVERAGE or only["containment"] != "none"
    if text_is_strong and corroborating >= 1:
        return "kobling"
    return "gennemgang"
```

- [ ] **Step 4: Kør testene og bekræft at de passerer**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py -v`
Expected: PASS (11/11).

- [ ] **Step 5: Bekræft determinisme**

Run:
```bash
for seed in 0 1 12345; do PYTHONHASHSEED=$seed python3 -m pytest \
  .claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py -q | tail -1; done
```
Expected: identisk resultatlinje alle tre gange.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/match_c0_records_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py
git commit -m "feat(1939): deterministisk matchningslogik til fase C0"
```

---

## Task 3: Byggeren — kandidatliste, kalibrering og lukning begge veje

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_c0_record_linkage_1939_v50.py`
- Test: `.claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py`

**Interfaces:**
- Consumes: `match_c0_records_1939_v50` (Task 2) via `importlib`, cwd-uafhængigt,
  som i `build_narrative_replacement_manifest_1939_v50.py`. Task 1's
  `narrative-state-v1.json`.
- Produces: `work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json`:
  ```
  {schema_version: "1.0", compare_version: "c0_compare_v1",
   input_hashes: {import_preview, database_preview, boundary, narrative_state},
   counts: {records: 41, kobling: int, gennemgang: int, for_kort: int,
            sammenlaegning: int, aegte_ny: int},
   prefilter: {pairs_total: int, pairs_skipped: int, ngram: 20},
   closure: {old_text_persons: [int], old_text_explained: [int],
             old_text_unexplained: [int], old_text_resolved_in_c0: [int],
             old_text_deferred_c3: [int],
             database_only_persons: [int], database_only_unexplained: [int]},
   records: [{new_record_key, source_span, pages, verbatim_text,
              classification, candidates: [{person_id, visning_navn, staged,
              side, ratio, containment, name_signal, page_signal,
              person_tekst}]}]}
  ```
  Records sorteres på `new_record_key`; kandidater på faldende `ratio`, derefter
  stigende `person_id`.

**CLI:**
```
build_c0_record_linkage_1939_v50.py --import-preview PATH --database-preview PATH
  --boundary PATH --narrative-state PATH --output PATH [--report PATH]
```
Alle stier hash-valideres mod de låste konstanter (`narrative-state` er ikke
låst — den er frisk pr. kørsel, og dens hash skrives i `input_hashes`).

- [ ] **Step 1: Skriv de fejlende tests**

Opret `test_build_c0_record_linkage_1939_v50.py`:

```python
import importlib.util
import json
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "build_c0_record_linkage_1939_v50",
    Path(__file__).resolve().parent / "build_c0_record_linkage_1939_v50.py")
b = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(b)


def _person(person_id, navn, tekst, side=None, staged=False, binding=False):
    return {"person_id": person_id, "visning_navn": navn, "staged": staged,
            "side": side, "privat": False, "tekst": tekst,
            "tekst_sha256": "0" * 64, "har_record_binding": binding}


def test_record_med_eksakt_tekst_bliver_kobling():
    records = [{"new_record_key": "record-a", "source_span": {"char_from": 1, "char_to": 9},
                "verbatim_text": "Greve Ferdinand Gottlie b til Vindeholme"}]
    persons = [_person(1299, "Ferdinand Gottlieb", "Greve Ferdinand Gottlieb til Vindeholme",
                       side="574-75")]
    pages = {"record-a": {"page_from": 574, "page_to": 575}}
    result = b.build_records(records, persons, pages)
    assert result[0]["classification"] == "kobling"
    assert result[0]["candidates"][0]["person_id"] == 1299


def test_record_der_matcher_to_personer_spaerres():
    records = [{"new_record_key": "record-b", "source_span": {"char_from": 1, "char_to": 9},
                "verbatim_text": "Anna Sophie f. 1693 og Christian Ditlev f. 1710"}]
    persons = [_person(1296, "Anna Sophie", "Anna Sophie f. 1693"),
               _person(1297, "Christian Ditlev", "Christian Ditlev f. 1710")]
    result = b.build_records(records, persons, {})
    assert result[0]["classification"] == "sammenlaegning"
    assert len(result[0]["candidates"]) == 2


def test_record_uden_lighed_bliver_aegte_ny():
    records = [{"new_record_key": "record-c", "source_span": {"char_from": 1, "char_to": 9},
                "verbatim_text": "Ifølge velvillig Meddelelse fra Fru Hildegard"}]
    persons = [_person(1, "Otto", "Otto til Søbo, var 1260 Ridder")]
    result = b.build_records(records, persons, {})
    assert result[0]["classification"] == "aegte_ny"
    assert result[0]["candidates"] == []


def test_lukning_markerer_uforklaret_gammel_tekst():
    closure = b.build_closure(
        records=[{"new_record_key": "record-a", "classification": "kobling",
                  "candidates": [{"person_id": 1299}]}],
        old_text_persons=[1299, 1802], database_only_persons=[1299, 991])
    assert closure["old_text_explained"] == [1299]
    assert closure["old_text_unexplained"] == [1802]
    assert closure["database_only_unexplained"] == [991]


def test_spaerret_record_forklarer_men_loeser_ikke():
    # En sammenlægningspost FORKLARER hvorfor personerne har gammel tekst
    # (en record peger på dem), men LØSER dem ikke i C0 -- de er udskudt til
    # C3. De to spørgsmål holdes adskilt, så fragmentpersonerne hverken
    # forsvinder i "forklaret" eller forurener det ægte fund "uforklaret".
    closure = b.build_closure(
        records=[{"new_record_key": "record-b", "classification": "sammenlaegning",
                  "candidates": [{"person_id": 1296}, {"person_id": 1297}]}],
        old_text_persons=[1296, 1297], database_only_persons=[])
    assert sorted(closure["old_text_explained"]) == [1296, 1297]
    assert closure["old_text_unexplained"] == []
    assert sorted(closure["old_text_deferred_c3"]) == [1296, 1297]
    assert closure["old_text_resolved_in_c0"] == []


def test_hash_gate_afviser_forkert_input(tmp_path):
    wrong = tmp_path / "wrong.json"
    wrong.write_text("{}", encoding="utf-8")
    with pytest.raises(SystemExit) as excinfo:
        b.load_locked(wrong, "0" * 64, "C0_LINKAGE_IMPORT_PREVIEW_HASH_MISMATCH")
    assert excinfo.value.code == 2


def test_kalibreringsanker_er_haardkodet():
    assert b.CALIBRATION_RECORD_KEY == "record-82f49e95-e5ce-4e08-9840-d0e334b4ba50"
    assert b.CALIBRATION_PERSON_ID == 1299
```

- [ ] **Step 2: Kør testene og bekræft at de fejler**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py -v`
Expected: FAIL — modulet findes ikke.

- [ ] **Step 3: Skriv byggeren**

Opret `build_c0_record_linkage_1939_v50.py` med denne kerne (CLI-delen følger
`build_phase_a_anchor_manifest_1939_v50.py`s mønster: argparse, hash-gates,
`_fail()` med `sys.exit(2)`, `json.dump(..., ensure_ascii=False, sort_keys=True,
indent=2)`):

```python
#!/usr/bin/env python3
"""Byg fase C0's kandidatliste: de 41 »ægte nye« records mod prods
1939-personer. Read-only, deterministisk, skriver intet til databasen og
producerer intet manifest -- kun beslutningsgrundlag."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

_SCRIPTS_DIR = Path(__file__).resolve().parent

LOCKED_IMPORT_PREVIEW_SHA256 = "04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5"
LOCKED_DATABASE_PREVIEW_SHA256 = "a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c"
LOCKED_BOUNDARY_SHA256 = "73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f"

EXPECTED_GENUINELY_NEW = 41

# Bekræftet sandt positiv (docs/superpowers/specs/2026-08-19-...-design.md):
# recorden dækker s. 574-575 og person 1299 bærer netop den tekst.
CALIBRATION_RECORD_KEY = "record-82f49e95-e5ce-4e08-9840-d0e334b4ba50"
CALIBRATION_PERSON_ID = 1299


def _fail(code: str) -> None:
    print(code, file=sys.stderr)
    sys.exit(2)


def _import_match_module():
    spec = importlib.util.spec_from_file_location(
        "match_c0_records_1939_v50", _SCRIPTS_DIR / "match_c0_records_1939_v50.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


match = _import_match_module()


def load_locked(path: Path, expected_sha256: str, failure_code: str) -> Dict[str, Any]:
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected_sha256:
        _fail(failure_code)
    return json.loads(raw.decode("utf-8"))


def build_records(records: List[Dict[str, Any]], persons: List[Dict[str, Any]],
                  pages_by_key: Dict[str, Dict[str, int]],
                  prefilter_stats: Optional[Dict[str, int]] = None) -> List[Dict[str, Any]]:
    person_skeletons = [(p, match.text_skeleton(p["tekst"])) for p in persons]
    out: List[Dict[str, Any]] = []
    for record in sorted(records, key=lambda r: r["new_record_key"]):
        verbatim = record["verbatim_text"]
        record_skeleton = match.text_skeleton(verbatim)
        pages = pages_by_key.get(record["new_record_key"])
        candidates: List[Dict[str, Any]] = []
        for person, person_skeleton in person_skeletons:
            if prefilter_stats is not None:
                prefilter_stats["pairs_total"] = prefilter_stats.get("pairs_total", 0) + 1
            # Forfilteret er en optimering, ikke en beslutning -- og det tælles,
            # så et stille loft aldrig kan læses som fuld dækning.
            if not match.shares_ngram(record_skeleton, person_skeleton):
                if prefilter_stats is not None:
                    prefilter_stats["pairs_skipped"] = prefilter_stats.get("pairs_skipped", 0) + 1
                continue
            scores = match.similarity(record_skeleton, person_skeleton)
            if scores["coverage"] < match.CANDIDATE_COVERAGE and scores["containment"] == "none":
                continue
            candidates.append({
                "person_id": person["person_id"],
                "visning_navn": person["visning_navn"],
                "staged": person["staged"],
                "side": person.get("side"),
                "ratio": scores["ratio"],
                "coverage": scores["coverage"],
                "containment": scores["containment"],
                "name_signal": match.name_signal(verbatim, person["visning_navn"]),
                "page_signal": match.page_signal(pages, person.get("side")),
                "person_tekst": person["tekst"],
            })
        candidates.sort(key=lambda c: (-c["coverage"], c["person_id"]))
        classification = match.classify(candidates, len(record_skeleton))
        if classification == "for_kort":
            # Kandidatlisten er støj; de fem bedste vises alene til orientering.
            candidates = candidates[:5]
        out.append({
            "new_record_key": record["new_record_key"],
            "source_span": record["source_span"],
            "pages": pages,
            "verbatim_text": verbatim,
            "skeleton_len": len(record_skeleton),
            "classification": classification,
            "candidates": candidates,
        })
    return out


def build_closure(records: List[Dict[str, Any]], old_text_persons: List[int],
                  database_only_persons: List[int]) -> Dict[str, Any]:
    """Adskil FORKLARET fra LØST.

    *Forklaret* = mindst én record peger på personen, uanset klasse. En
    person ingen record peger på, er fasens ægte fund: så er hypotesen om
    fejlklassifikation ufuldstændig for netop den.

    *Løst i C0* = forklaret af en record der kan afgøres nu (kobling eller
    gennemgang). Fragmentposterne forklarer, men løser ikke -- de er udskudt
    til C3, og deres personer skal kunne tælles særskilt frem for at gemme
    sig i en samlet 'forklaret'-procent."""
    explained: set[int] = set()
    resolvable: set[int] = set()
    for record in records:
        # ``for_kort`` bidrager til INGEN af delene: dens kandidater er
        # ordsammenfald, ikke evidens, og at lade dem tælle som forklaring
        # ville skjule ægte uforklarede personer bag støj.
        if record["classification"] == "for_kort":
            continue
        for candidate in record["candidates"]:
            explained.add(candidate["person_id"])
            if record["classification"] in ("kobling", "gennemgang"):
                resolvable.add(candidate["person_id"])
    old_text = sorted(set(old_text_persons))
    database_only = sorted(set(database_only_persons))
    return {
        "old_text_persons": old_text,
        "old_text_explained": sorted(p for p in old_text if p in explained),
        "old_text_unexplained": sorted(p for p in old_text if p not in explained),
        "old_text_resolved_in_c0": sorted(p for p in old_text if p in resolvable),
        "old_text_deferred_c3": sorted(
            p for p in old_text if p in explained and p not in resolvable),
        "database_only_persons": database_only,
        "database_only_unexplained": sorted(p for p in database_only if p not in explained),
    }
```

Resten af filen: `main()` med argparse, hash-gates (de tre låste + fri hash på
`--narrative-state`), udledning af `old_text_persons` (personer i
`narrative-state` med `har_record_binding == false`) og `database_only_persons`
(fra database-preview), sidekortet via en kopi af `_boundary_pages`-opslaget
(anchor `(char_from, char_to)` → `page_from`/`page_to`, med samme
verbatim-verifikation og samme fail-closed adfærd), assert på
`EXPECTED_GENUINELY_NEW`, kalibrerings-assert, og skrivning af JSON + valgfri
markdown-rapport.

**Gates i `main()`.** Kalibreringsankeret alene beviser kun, at tærsklerne
ikke er for *stramme*. Intet i det fanger tærskler der er for *løse* — og
en løs tærskel udfylder `[KOBL]` på hele korpus, hvorefter et menneskes
realistiske adfærd er at acceptere anbefalingerne. Derfor tre gates, ikke én:

```python
    # 1. Positivt anker: tærsklerne må ikke være for stramme.
    calibration = next((r for r in built if r["new_record_key"] == CALIBRATION_RECORD_KEY), None)
    if calibration is None:
        _fail("C0_LINKAGE_CALIBRATION_RECORD_MISSING")
    if calibration["classification"] != "kobling" or not calibration["candidates"] or \
            calibration["candidates"][0]["person_id"] != CALIBRATION_PERSON_ID:
        _fail(f"C0_LINKAGE_CALIBRATION_FAILED:{calibration['classification']}")

    # 2. Ingen person må være topkandidat for to records. To poster der begge
    #    anbefaler KOBL -> 1299 er en selvmodsigelse, som arket ikke afslører:
    #    linjerne står langt fra hinanden, hver især plausible.
    claimed: Dict[int, str] = {}
    for record in built:
        if record["classification"] not in ("kobling", "gennemgang") or not record["candidates"]:
            continue
        top = record["candidates"][0]["person_id"]
        if top in claimed:
            _fail(f"C0_LINKAGE_PERSON_CLAIMED_TWICE:{top}:{claimed[top]}:{record['new_record_key']}")
        claimed[top] = record["new_record_key"]

    # 3. Alarm, ikke sandhed: flyder over halvdelen af korpus ind som
    #    koblinger, er tærsklerne løse -- 41 records mod ~23-26 personer med
    #    gammel tekst gør et stort tal usandsynligt.
    if sum(1 for r in built if r["classification"] == "kobling") > 25:
        _fail("C0_LINKAGE_KOBLING_DISTRIBUTION_IMPLAUSIBLE")
```

`_fail` her betyder *stop og tænk*, ikke *justér tallet til det passerer*.

- [ ] **Step 4: Kør testene og bekræft at de passerer**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py -v`
Expected: PASS (7/7).

- [ ] **Step 5: Kør byggeren på det ægte grundlag**

Run:
```bash
python3 .claude/skills/daa-extract/scripts/build_c0_record_linkage_1939_v50.py \
  --import-preview work/task21-1939-v50-import-preview/import-preview-v1.json \
  --database-preview work/task21-1939-v50-import-preview/database-preview-v1.json \
  --boundary work/task20-1939-full/boundary-materialization-v3-ditlev.json \
  --narrative-state work/task26-1939-v50-c0-record-linkage/narrative-state-v1.json \
  --output work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json \
  --report work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.md
```
Expected: exit 0. **Fejler en gate, er tærsklerne forkerte — justér
`CANDIDATE_COVERAGE`/`STRONG_COVERAGE` i Task 2's modul, kør Task 2's tests
igen, og notér justeringen i rapporten. Justér ALDRIG ankeret eller
gate-grænserne for at få asserten til at passere.**

- [ ] **Step 5b: Fastlæg det negative regressionsanker**

Et negativt anker kan ikke hårdkodes på forhånd — man skal se data først.
Vælg fra kørslen én record der klassificeres `aegte_ny` med den laveste
bedste coverage, læs dens verbatim-tekst, og bekræft manuelt at den ikke
handler om en person i prod. Hårdkod derefter dens nøgle som
`NEGATIVE_ANCHOR_RECORD_KEY` med en assert om at den forbliver `aegte_ny`,
og notér i rapporten hvorfor netop den blev valgt.

Bemærk: `record-ca225a9a…` (von Carlstein-noten) er **ikke** blandt de 41 —
den er et `accepted_carryover` source record. Brug den ikke.

- [ ] **Step 6: Bekræft determinisme på det ægte grundlag**

Run: kør Step 5's kommando to gange til to forskellige `--output`-stier med
`PYTHONHASHSEED=0` hhv. `PYTHONHASHSEED=99999`, og `shasum -a 256` begge.
Expected: identiske hashes.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/build_c0_record_linkage_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py
git commit -m "feat(1939): byg fase C0's kandidatliste m. lukning begge veje"
```

---

## Task 4: Token-filen — generate og fail-closed convert

**Files:**
- Create: `.claude/skills/daa-extract/scripts/convert_c0_linkage_decisions_1939_v50.py`
- Test: `.claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py`

**Interfaces:**
- Consumes: Task 3's `linkage-candidates-v1.json`.
- Produces:
  - `generate_document(candidates_doc: dict) -> str`
  - `convert_edited_document(text: str, candidates_doc: dict) -> dict`
  - `VALID_TOKENS = {"[KOBL]", "[NY]", "[C3]", "[SPØRG]"}`
  - Beslutnings-JSON:
    `{schema_version: "1.0", decisions: [{new_record_key, token,
    person_id: int|null}]}` — `person_id` udfyldes kun ved `[KOBL]` og tages
    fra kandidatlisten, aldrig fra den redigerede tekst.

**Linjeformat** (mønster fra `convert_narrative_decisions_1939_v50.py`:
`[TOKEN]` først, derefter et byte-låst id og byte-låst kontekst):

```
[KOBL]  R07  s.574-575  ->  1299 Ferdinand Einar Julius Gottlieb  (ratio 0.97, indeholdt, navn✓, side✓)
```

Kun bracket-tokenet må redigeres. Alt efter R-id'et sammenlignes byte-for-byte
mod den friskt genskabte linje; enhver anden ændring afvises med linjenummer.

**Sektioner, mistænkelige øverst:**

| Sektion | Poster | Udfyldt token |
|---|---|---|
| `KRÆVER STILLINGTAGEN` | `gennemgang` | `[SPØRG]` |
| `FOR KORT TIL AT MATCHE` | `for_kort` | `[SPØRG]` |
| `SAMMENLÆGNING — spærret for kobling (→ C3)` | `sammenlaegning` | `[C3]` |
| `FORESLÅET KOBLING` | `kobling` | `[KOBL]` |
| `INGEN KANDIDAT` | `aegte_ny` | `[NY]` |

`for_kort`-sektionen viser recordens fulde verbatim-tekst (den er jo kort)
og de fem bedste kandidater **mærket som ordsammenfald, ikke forslag**.
`[KOBL]` er tilladt her — mennesket kan se hvad værktøjet ikke kan — men
kun mod den øverste kandidat, som alle andre steder.

`[SPØRG]` er en bevidst escape-ventil: uden den ville et menneske i tvivl
være tvunget til at gætte mellem tre bindende udfald.

- [ ] **Step 1: Skriv de fejlende tests**

Opret `test_convert_c0_linkage_decisions_1939_v50.py`:

```python
import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "convert_c0_linkage_decisions_1939_v50",
    Path(__file__).resolve().parent / "convert_c0_linkage_decisions_1939_v50.py")
c = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(c)

DOC = {
    "schema_version": "1.0",
    "records": [
        {"new_record_key": "record-a", "classification": "kobling",
         "pages": {"page_from": 574, "page_to": 575}, "verbatim_text": "Greve Ferdinand",
         "candidates": [{"person_id": 1299, "visning_navn": "Ferdinand Gottlieb",
                         "staged": False, "side": "574-75", "ratio": 0.97,
                         "containment": "record_in_person", "name_signal": True,
                         "page_signal": True, "person_tekst": "Greve Ferdinand"}]},
        {"new_record_key": "record-b", "classification": "sammenlaegning",
         "pages": None, "verbatim_text": "Anna og Christian",
         "candidates": [{"person_id": 1296, "visning_navn": "Anna", "staged": False,
                         "side": None, "ratio": 0.9, "containment": "person_in_record",
                         "name_signal": True, "page_signal": None, "person_tekst": "Anna"},
                        {"person_id": 1297, "visning_navn": "Christian", "staged": True,
                         "side": None, "ratio": 0.8, "containment": "person_in_record",
                         "name_signal": True, "page_signal": None, "person_tekst": "Christian"}]},
        {"new_record_key": "record-c", "classification": "aegte_ny",
         "pages": None, "verbatim_text": "Ifølge velvillig Meddelelse", "candidates": []},
    ],
}


def test_generate_udfylder_anbefaling_pr_klasse():
    text = c.generate_document(DOC)
    assert "[KOBL]" in text and "[C3]" in text and "[NY]" in text
    assert text.index("SAMMENLÆGNING") < text.index("FORESLÅET KOBLING")


def test_generate_er_deterministisk():
    assert c.generate_document(DOC) == c.generate_document(DOC)


def test_convert_uaendret_dokument_giver_anbefalingerne():
    result = c.convert_edited_document(c.generate_document(DOC), DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-a"]["token"] == "[KOBL]"
    assert by_key["record-a"]["person_id"] == 1299
    assert by_key["record-b"]["token"] == "[C3]"
    assert by_key["record-b"]["person_id"] is None
    assert by_key["record-c"]["token"] == "[NY]"


def test_convert_accepterer_menneskets_omvalg():
    text = c.generate_document(DOC).replace("[KOBL]", "[SPØRG]", 1)
    result = c.convert_edited_document(text, DOC)
    by_key = {d["new_record_key"]: d for d in result["decisions"]}
    assert by_key["record-a"]["token"] == "[SPØRG]"
    assert by_key["record-a"]["person_id"] is None


def test_convert_afviser_kobl_paa_spaerret_post():
    text = c.generate_document(DOC).replace("[C3]", "[KOBL]", 1)
    with pytest.raises(SystemExit) as excinfo:
        c.convert_edited_document(text, DOC)
    assert excinfo.value.code == 2


def test_convert_afviser_kobl_uden_kandidat():
    text = c.generate_document(DOC).replace("[NY]", "[KOBL]", 1)
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_redigeret_kontekst():
    text = c.generate_document(DOC).replace("Ferdinand Gottlieb", "Ferdinand Gottlie")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_ukendt_token():
    text = c.generate_document(DOC).replace("[NY]", "[MÅSKE]", 1)
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_slettet_linje():
    lines = c.generate_document(DOC).split("\n")
    kept = [line for line in lines if not line.startswith("[NY]")]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(kept), DOC)


def test_convert_afviser_duplikeret_rid():
    lines = c.generate_document(DOC).split("\n")
    doubled = []
    for line in lines:
        doubled.append(line)
        if line.startswith("[NY]"):
            doubled.append(line)
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(doubled), DOC)
```

- [ ] **Step 2: Kør testene og bekræft at de fejler**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py -v`
Expected: FAIL — modulet findes ikke.

- [ ] **Step 3: Skriv konverteren**

Opret `convert_c0_linkage_decisions_1939_v50.py`. Kontrakten, punkt for punkt:

1. `assign_rids(records)` — R-id'er (`R01`, `R02`, …) tildeles ud fra
   `records` sorteret på `new_record_key`, nummereret fra 1. Identitet
   udledes ALDRIG af den redigerede tekst.
2. `render_line(record, rid, token)` — bygger linjen ovenfor. For
   `sammenlaegning` listes alle kandidat-id'er i kontekstdelen; for
   `aegte_ny` skrives `ingen kandidat` plus de første 60 tegn af
   `verbatim_text` med linjeskift erstattet af `⏎`.
3. `generate_document(doc)` — instruktionshoved (hvilke tokens findes, hvad
   de betyder, at kun tokenet må ændres), derefter de fire sektioner i den
   viste rækkefølge, hver med `== TITEL (n) ==`.
Kernen, konkret:

```python
VALID_TOKENS = {"[KOBL]", "[NY]", "[C3]", "[SPØRG]"}
DEFAULT_TOKEN_BY_CLASS = {"kobling": "[KOBL]", "gennemgang": "[SPØRG]",
                          "for_kort": "[SPØRG]", "sammenlaegning": "[C3]",
                          "aegte_ny": "[NY]"}
SECTION_ORDER = ["gennemgang", "for_kort", "sammenlaegning", "kobling", "aegte_ny"]
SECTION_TITLES = {
    "gennemgang": "KRÆVER STILLINGTAGEN ({n})",
    "for_kort": "FOR KORT TIL AT MATCHE ({n}) — kandidater er ordsammenfald",
    "sammenlaegning": "SAMMENLÆGNING — spærret for kobling (→ C3) ({n})",
    "kobling": "FORESLÅET KOBLING ({n})",
    "aegte_ny": "INGEN KANDIDAT ({n})",
}

_DECISION_HEAD_RE = re.compile(r"^(\[[A-ZÆØÅ]+\])([ \t]+)(R\d{2})(?=[ \t])")


def assign_rids(records):
    """R-id'er er en ren funktion af kandidatfilen -- aldrig af den
    redigerede tekst. Mennesket vælger token, ikke identitet."""
    ordered = sorted(records, key=lambda r: r["new_record_key"])
    return {r["new_record_key"]: f"R{i:02d}" for i, r in enumerate(ordered, start=1)}


def _flat(text, limit=60):
    collapsed = " ".join(text.split())
    return collapsed[:limit] + ("…" if len(collapsed) > limit else "")


def render_line(record, rid, token):
    pages = record.get("pages")
    page_text = f"s.{pages['page_from']}-{pages['page_to']}" if pages else "s.?"
    cands = record["candidates"]
    if not cands:
        context = f"ingen kandidat  |  {_flat(record['verbatim_text'])}"
    elif len(cands) == 1:
        c = cands[0]
        marks = ("navn✓" if c["name_signal"] else "navn✗") + ", " + (
            "side✓" if c["page_signal"] is True else
            "side✗" if c["page_signal"] is False else "side?")
        staged = " [staged]" if c["staged"] else ""
        context = (f"-> {c['person_id']} {c['visning_navn']}{staged}  "
                   f"(ratio {c['ratio']:.2f}, {c['containment']}, {marks})")
    else:
        ids = ", ".join(f"{c['person_id']} {c['visning_navn']}" for c in cands)
        context = f"-> {len(cands)} kandidater: {ids}"
    return f"{token}  {rid}  {page_text}  {context}"


def _canonical_for_compare(line):
    """Kollaps kun whitespace-løbet mellem token og R-id: et menneske der
    erstatter [KOBL] med [SPØRG] flytter kolonnen, og det er tilladt.
    Alt efter R-id'et skal være byte-identisk."""
    match = _DECISION_HEAD_RE.match(line)
    if match is None:
        return line
    return match.group(1) + " " + line[match.end(2):]
```

4. `convert_edited_document(text, doc)` —
   - parser `^(\[[A-ZÆØÅ]+\])([ \t]+)(R\d{2})(?=[ \t])`;
   - genskaber hele dokumentet med de parsede tokens og kræver
     byte-identitet med input bortset fra whitespace-løbet mellem token og
     R-id (samme lempelse som fase B: et menneske der erstatter `[KOBL]`
     med `[SPØRG]` flytter kolonnen);
   - kræver at hvert R-id optræder præcis én gang og at linjeantal og
     rækkefølge er uændret;
   - afviser `[KOBL]` når `classification == "sammenlaegning"`
     (`C0_DECISIONS_KOBL_ON_BLOCKED_RECORD`) eller når kandidatlisten er tom
     (`C0_DECISIONS_KOBL_WITHOUT_CANDIDATE`);
   - sætter `person_id` fra `candidates[0]["person_id"]` ved `[KOBL]`, ellers
     `None`;
   - alle fejl: `print(kode, file=sys.stderr)` + `sys.exit(2)`.
5. `main()` — `generate`/`convert`-subkommandoer, `--candidates`, `--output`,
   afviser eksisterende output-fil.

- [ ] **Step 4: Kør testene og bekræft at de passerer**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py -v`
Expected: PASS (10/10).

- [ ] **Step 5: Kør hele pytest-suiten for C0**

Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_match_c0_records_1939_v50.py .claude/skills/daa-extract/scripts/test_build_c0_record_linkage_1939_v50.py .claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py -q`
Expected: `0 failed` — ingen fejl, ingen fejl-i-opsætning. (Et fast
forventet antal skrives ikke her: tests tilføjes undervejs, og et forældet
tal ville få skridtet til at fejle af den forkerte grund.)

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/daa-extract/scripts/convert_c0_linkage_decisions_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_convert_c0_linkage_decisions_1939_v50.py
git commit -m "feat(1939): token-fil m. fail-closed konverter til fase C0"
```

---

## Task 5: Kørsel, rapport og aflevering til mennesket

**Files:**
- Create: `docs/superpowers/reviews/1939-v50-fase-c0-linkage-report.md`
- Modify: `docs/changelog.md` (ny post øverst)

**Interfaces:**
- Consumes: Task 3's kandidat-JSON, Task 4's `generate`.
- Produces: token-filen til brugeren + en rapport der kan reviewes uafhængigt.

- [ ] **Step 1: Generér token-filen**

Run:
```bash
python3 .claude/skills/daa-extract/scripts/convert_c0_linkage_decisions_1939_v50.py generate \
  --candidates work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json \
  --output work/task26-1939-v50-c0-record-linkage/c0-afgoerelser.txt
shasum -a 256 work/task26-1939-v50-c0-record-linkage/c0-afgoerelser.txt
```
Expected: 41 beslutningslinjer. Verificér med
`grep -cE '^\[[A-ZÆØÅ]+\][ \t]+R[0-9]{2}' work/task26-1939-v50-c0-record-linkage/c0-afgoerelser.txt`
→ `41`.

- [ ] **Step 2: Verificér at uændret fil konverterer rent**

Run:
```bash
python3 .claude/skills/daa-extract/scripts/convert_c0_linkage_decisions_1939_v50.py convert \
  --candidates work/task26-1939-v50-c0-record-linkage/linkage-candidates-v1.json \
  --decisions work/task26-1939-v50-c0-record-linkage/c0-afgoerelser.txt \
  --output work/task26-1939-v50-c0-record-linkage/c0-afgoerelser-roundtrip.json
```
Expected: exit 0, 41 beslutninger. Dette er en roundtrip-kontrol, ikke en
afgørelse — filen slettes bagefter.

- [ ] **Step 3: Skriv rapporten**

Opret `docs/superpowers/reviews/1939-v50-fase-c0-linkage-report.md` med:
- inputtabellen med alle fire SHA-256 (de tre låste + `narrative-state`);
- klassefordelingen (kobling / gennemgang / sammenlægning / ægte ny);
- **lukning begge veje**, med de fire tal holdt adskilt: forklaret, løst i
  C0, udskudt til C3, og **uforklaret** — sidstnævnte som en navngiven
  liste over person-id'er. Det er fasens vigtigste fund, ikke en fodnote,
  og må ikke rulles sammen i én "forklaret"-procent;
- resultatet af Step 6b's proxy-verifikation (afvigelser mellem
  binding-proxyen og den empiriske gammel-tekst-liste, med forklaring);
- `for_kort`-posterne navngivet, og forfilterets `pairs_skipped` — et
  stille loft må aldrig kunne læses som fuld dækning;
- eventuelle tærskeljusteringer fra Task 3 Step 5, med begrundelse;
- eksplicit: ingen prod-skrivning udført, staged forbliver staged,
  personoprettelse og sammenlægning udskudt til hhv. egen GO-pakke og C3.

- [ ] **Step 4: Opdatér changelog**

Tilføj en post øverst i `docs/changelog.md` efter husets stil (dateret
overskrift + kort prosa): hvad C0 målte, hvad der venter på brugerens
afgørelser, og at intet er skrevet til prod.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/reviews/1939-v50-fase-c0-linkage-report.md docs/changelog.md
git commit -m "docs(1939): fase C0's kandidatrapport og lukning begge veje"
```

- [ ] **Step 6: Aflevér til brugeren**

Send token-filen med `SendUserFile` og opsummér: antal pr. klasse, de
uforklarede personer, og hvad de fire tokens betyder. **Stop her.**
Prod-skrivningen er en separat GO-pakke og ligger uden for denne plan.

---

## Definition of done

1. Alle 41 records har en klassifikation og en udfyldt anbefaling.
2. Lukning begge veje er rapporteret, og uforklarede personer er navngivet.
3. Alle tre gates i `main()` passerer uden at ankre eller grænser er
   justeret: positivt anker (record `82f49e95…` → person 1299 = `kobling`),
   negativt anker (Step 5b, `aegte_ny`), ingen person hævdet to gange, og
   koblings-fordelingen under alarmgrænsen.
4. Binding-proxyen er verificeret mod den empiriske gammel-tekst-liste
   (Step 6b), og enhver afvigelse er forklaret i rapporten.
5. Token-filen er genereret, roundtrip-verificeret og afleveret.
6. Intet er skrevet til produktionsdatabasen.
7. Pytest- og testthat-suiterne grønne (0 failed); determinisme bevist
   under tre `PYTHONHASHSEED`-værdier.

## Uden for denne plan

Fase B-efterkørslen for `[KOBL]`-afgørelserne (eget manifest, egen GO-pakke,
og den skal bære fase B's to fangne fælder: replay-værn der dækker
`privat`/`side`, og skema-kvalificeret `digest()`). Personoprettelse for
`[NY]` (task 25-mønstret, egen autorisation og eget cutover-gate).
Sammenlægningerne (C3). OCR-fejl i teksten (redaktørfladen). Publicering af
staged personer (fase D).
