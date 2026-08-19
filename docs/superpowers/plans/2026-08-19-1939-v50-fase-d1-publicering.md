# 1939 v50 fase D1 — publicering af de 44 staged probander: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gøre 44 staged 1939-probander (og de 24 partner-stubs, der følger
med dem) offentligt synlige — via husets eksisterende `red_publicer_personer`,
med menneskelig godkendelse pr. person og fuld gate-kæde.

**Architecture:** Read-only R-eksport udvælger de 44 deterministisk og
forudsiger partner-udvidelsen → Python-token-fil giver brugeren kontrol pr.
person → hash-låst apply-SQL med egne guards kører én atomisk transaktion,
først mod en frisk produktionsækvivalent restore, derefter mod prod.

**Tech Stack:** R m. DBI/RPostgres/jsonlite, Python 3 (stdlib), pytest, psql,
PostgreSQL 17.

**Spec:** `docs/superpowers/specs/2026-08-19-1939-v50-fase-d1-publicering-design.md`

## Global Constraints

- **D1 ændrer udelukkende `person.staged`.** Ingen fakta, relationer eller
  narrativer røres. Efterkontrollen skal bevise det.
- **Ingen DDL.** `red_publicer_personer(bigint[])` findes allerede
  (db-migrations.sql, 2026-07-20). Ingen ny RPC, ingen skemaændring.
  `get_advisors` er derfor ikke relevant.
- **Prod-gate:** frisk backup (0600 + SHA-256) → rehearsal mod frisk
  produktionsækvivalent restore m. byte-identiske før/efter-baselines →
  eksplicit brugergodkendelse m. eksakte hashes og tal → én apply, ingen retry.
- **Aktør:** `red_publicer_personer` kræver `current_rolle()='redaktion'`, som
  udledes af `profiles WHERE id = auth.uid()`. Over psql sættes den med
  `set_config('request.jwt.claim.sub', '<uuid>', true)` inde i transaktionen,
  efterfulgt af en verifikation af at netop den uuid har rollen — samme
  mønster som fase B's apply (linje 47-49 i `narrative-publication-apply.sql`).
  Redaktør-uuid i prod: `ba4ce28d-42a0-48af-a47c-773c26934236`.
- **Apply-SQL er hash-låst:** wrapper-scriptet afbryder, hvis SQL-filens
  SHA-256 afviger. Samme mønster som `narrative-publication-apply.sh`.
- **Supabase MCP `execute_sql` er read-only** og peger i denne session på en
  anden organisation (`BFH Metadata`). Prod nås kun via R/psql med
  `~/.Renviron`.
- **`work/` committes aldrig.** Kun scripts, tests og docs.
- **`load_daa.R` røres ikke og kaldes ikke.**
- Fejlkoder: `SCREAMING_SNAKE_CASE` med prefix `D1_`.

## File Structure

| Fil | Ansvar |
|---|---|
| `.claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50_helpers.R` | Ren funktion: rækker → eksportdokument. Testbar uden DB. |
| `.claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50.R` | CLI: read-only SELECT (udvalg + partnere + kontroltal) → JSON. |
| `.claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R` | R-assertions for helperen. |
| `tests/testthat/test-export-d1-staged-selection-1939-v50.R` | testthat-shim (CI's `r`-job). |
| `.claude/skills/daa-extract/scripts/convert_d1_publication_decisions_1939_v50.py` | `generate` + `convert` af token-filen; genberegner partner-udvidelsen ved `[VENT]`. |
| `.claude/skills/daa-extract/scripts/test_convert_d1_publication_decisions_1939_v50.py` | pytest for token-kontrakten. |
| `work/task27-1939-v50-d1-publicering/d1-publicering-apply.sql` | Hash-låst apply m. egne guards (ikke committet). |
| `work/task27-1939-v50-d1-publicering/d1-publicering-apply.sh` | Wrapper m. SHA-gate (ikke committet). |
| `work/task27-1939-v50-d1-publicering/d1-publicering-backup.sh` | Backup-wrapper (ikke committet). |
| `docs/superpowers/reviews/1939-v50-fase-d1-readiness.md` | GO-pakken. |

Arbejdsmappe: `work/task27-1939-v50-d1-publicering/`.

---

## Task 1: Deterministisk udvælgelse og partner-forudsigelse

Udvælgelsen må ikke være et skøn og må ikke afhænge af navne — staged person
927 hedder »Henrik« og deler navn med otte synlige personer.

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R`
- Create: `tests/testthat/test-export-d1-staged-selection-1939-v50.R`

**Interfaces:**
- Consumes: intet fra tidligere tasks.
- Produces: `work/task27-1939-v50-d1-publicering/staged-selection-v1.json`:
  ```
  {schema_version: "1.0", database_name, database_identity, generator,
   counts: {staged_total, selected, predicted_partners, blocked_no_binding,
            spouses_visible_partner},
   selected: [{person_id, visning_navn, side, fakta, samme_som_2020: bool,
               partner_ids: [int]}],
   predicted_partners: [{person_id, visning_navn, via_person_ids: [int]}]}
  ```
  R-funktionen hedder
  `build_d1_staged_selection_1939_v50(selected_rows, partner_rows, counts,
  database_name, database_identity, generator)`.

- [ ] **Step 1: Skriv den fejlende test**

Opret `.claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R`
efter husets mønster (standalone R-fil med egne `expect`-hjælpere, som
`test_export_c0_narrative_state_1939_v50.R`):

```r
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else { getwd() }
source(file.path(script_dir, "export_d1_staged_selection_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

sel <- data.frame(
  person_id = c(937, 927), visning_navn = c("Gotskalk [Reventlow]", "Henrik"),
  side = c("500", "507"), fakta = c(2, 1), samme_som_2020 = c(TRUE, FALSE),
  partner_ids = c("1467", ""), stringsAsFactors = FALSE)
par <- data.frame(
  person_id = 1467, visning_navn = "Anna Margarethe von der Lieth",
  via_person_ids = "937", stringsAsFactors = FALSE)
counts <- list(staged_total = 96L, selected = 2L, predicted_partners = 1L,
               blocked_no_binding = 7L, spouses_visible_partner = 21L)

doc <- build_d1_staged_selection_1939_v50(sel, par, counts, "postgres", "42", "test:v1")
expect(identical(doc$schema_version, "1.0"), "schema_version")
## Sorteret paa person_id -- eksporten skal vaere byte-stabil mellem koersler.
expect(identical(vapply(doc$selected, function(r) r$person_id, numeric(1)), c(927, 937)),
       "selected sorteret")
expect(identical(doc$selected[[2]]$partner_ids, 1467), "partner_ids som tal")
expect(identical(doc$selected[[1]]$partner_ids, numeric(0)), "tom partner-liste")
expect(isTRUE(doc$selected[[2]]$samme_som_2020), "samme_som-flag bevaret")
expect(identical(doc$counts$selected, 2L), "counts bevaret")

## Et forudsagt partner-id maa ALDRIG ogsaa staa i udvalget: saa ville
## publiceringen taelle den samme person to gange, og efterkontrollens
## forventede tal (68) ville vaere forkert.
sel2 <- sel; sel2$person_id <- c(937, 1467)
expect_error(build_d1_staged_selection_1939_v50(sel2, par, counts, "postgres", "42", "test:v1"),
             "D1_SELECTION_PARTNER_OVERLAP")

## Dublet i udvalget ville give samme fejl i ARRAY-argumentet.
sel3 <- sel; sel3$person_id <- c(937, 937)
expect_error(build_d1_staged_selection_1939_v50(sel3, par, counts, "postgres", "42", "test:v1"),
             "D1_SELECTION_DUPLICATE_PERSON")

cat(sprintf("test_export_d1_staged_selection_1939_v50: %d assertions OK\n", ok))
```

- [ ] **Step 2: Kør testen og bekræft at den fejler**

Run: `Rscript .claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R`
Expected: FAIL — `kan ikke åbne fil ... _helpers.R`.

- [ ] **Step 3: Skriv helperen**

```r
## Ren transformation: DB-raekker -> eksportdokument for fase D1.
## Ingen DB-adgang, saa den kan testes uden forbindelse.
build_d1_staged_selection_1939_v50 <- function(selected_rows, partner_rows, counts,
                                               database_name, database_identity,
                                               generator) {
  if (anyDuplicated(selected_rows$person_id))
    stop("D1_SELECTION_DUPLICATE_PERSON", call. = FALSE)
  if (anyDuplicated(partner_rows$person_id))
    stop("D1_SELECTION_DUPLICATE_PARTNER", call. = FALSE)
  ## En forudsagt partner maa ikke ogsaa vaere valgt: ellers taelles personen
  ## to gange, og efterkontrollens forventede antal bliver forkert.
  if (length(intersect(selected_rows$person_id, partner_rows$person_id)) > 0L)
    stop("D1_SELECTION_PARTNER_OVERLAP", call. = FALSE)
  ids <- function(text) {
    if (is.na(text) || !nzchar(text)) return(numeric(0))
    as.numeric(strsplit(text, ",", fixed = TRUE)[[1L]])
  }
  sel <- lapply(order(selected_rows$person_id), function(i) list(
    person_id = as.numeric(selected_rows$person_id[[i]]),
    visning_navn = as.character(selected_rows$visning_navn[[i]]),
    side = if (is.na(selected_rows$side[[i]])) NA else as.character(selected_rows$side[[i]]),
    fakta = as.numeric(selected_rows$fakta[[i]]),
    samme_som_2020 = as.logical(selected_rows$samme_som_2020[[i]]),
    partner_ids = ids(selected_rows$partner_ids[[i]])
  ))
  par <- lapply(order(partner_rows$person_id), function(i) list(
    person_id = as.numeric(partner_rows$person_id[[i]]),
    visning_navn = as.character(partner_rows$visning_navn[[i]]),
    via_person_ids = ids(partner_rows$via_person_ids[[i]])
  ))
  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       counts = counts, selected = sel, predicted_partners = par)
}
```

- [ ] **Step 4: Kør testen og bekræft at den passerer**

Run: `Rscript .claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R`
Expected: `8 assertions OK`.

- [ ] **Step 5: Skriv testthat-shim'en**

CI's `r`-job kører `test_dir("tests/testthat")`, ikke scripts-mappen direkte.

```r
testthat::test_that("export-d1-staged-selection R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_export_d1_staged_selection_1939_v50.R", local = TRUE))
})
```

Run: `Rscript -e 'testthat::test_dir("tests/testthat", filter="export-d1", stop_on_failure=TRUE)'`
Expected: `[ FAIL 0 | PASS 1 ]`.

- [ ] **Step 6: Skriv CLI-scriptet**

Opret `export_d1_staged_selection_1939_v50.R` med samme struktur som
`export_c0_narrative_state_1939_v50.R` (CLI-validering, `env_or`-forbindelse,
`--expect-database-name`, `output exists`-afvisning), fejlprefix
`D1_EXPORT_SELECTION`, og disse forespørgsler:

```r
sql_selected <- paste(
  "SELECT p.id AS person_id, p.visning_navn, n.side,",
  "(SELECT count(*) FROM fact f WHERE f.subjekt_type='person' AND f.subjekt_id=p.id) AS fakta,",
  "EXISTS (SELECT 1 FROM relation r JOIN person q",
  "        ON q.id = CASE WHEN r.subjekt_id=p.id THEN r.objekt_id ELSE r.subjekt_id END",
  "        WHERE r.rolle='samme_som'",
  "          AND ((r.subjekt_type='person' AND r.subjekt_id=p.id)",
  "            OR (r.objekt_type='person' AND r.objekt_id=p.id))",
  "          AND EXISTS (SELECT 1 FROM narrative n2 JOIN source s ON s.id=n2.source_id",
  "                      WHERE n2.subjekt_type='person' AND n2.subjekt_id=q.id",
  "                        AND s.aar=2020)) AS samme_som_2020,",
  "(SELECT string_agg(DISTINCT x.person_id::text, ',' ORDER BY x.person_id::text)",
  "   FROM family_member fm1 JOIN family_member fm2 ON fm2.family_id=fm1.family_id",
  "   JOIN person x ON x.id=fm2.person_id",
  "  WHERE fm1.person_id=p.id AND x.id<>p.id AND x.staged) AS partner_ids",
  "FROM person p",
  "JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "JOIN private.narrative_record_publication b",
  "  ON b.narrative_id=n.id AND b.status='published'",
  "WHERE p.staged ORDER BY p.id")
```

Partner-forudsigelsen skal spejle RPC'ens egen WHERE-klausul præcist
(db-migrations.sql: `staged = true AND (id = ANY(ids) OR EXISTS (…familie…))`):

```r
sql_partners <- paste(
  "WITH valgte AS (",
  "  SELECT p.id FROM person p",
  "  JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "  JOIN private.narrative_record_publication b",
  "    ON b.narrative_id=n.id AND b.status='published'",
  "  WHERE p.staged)",
  "SELECT p.id AS person_id, p.visning_navn,",
  "  (SELECT string_agg(DISTINCT v.id::text, ',' ORDER BY v.id::text)",
  "     FROM family_member fm1 JOIN family_member fm2 ON fm2.family_id=fm1.family_id",
  "     JOIN valgte v ON v.id=fm2.person_id WHERE fm1.person_id=p.id) AS via_person_ids",
  "FROM person p",
  "WHERE p.staged AND p.id NOT IN (SELECT id FROM valgte)",
  "  AND EXISTS (SELECT 1 FROM family_member fm1",
  "              JOIN family_member fm2 ON fm2.family_id=fm1.family_id",
  "              WHERE fm1.person_id=p.id AND fm2.person_id IN (SELECT id FROM valgte))",
  "ORDER BY p.id")
```

Kontroltallene hentes i én forespørgsel, så eksporten bærer hele billedet:

```r
sql_counts <- paste(
  "SELECT (SELECT count(*) FROM person WHERE staged) AS staged_total,",
  "(SELECT count(*) FROM person p",
  "   JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "   LEFT JOIN private.narrative_record_publication b ON b.narrative_id=n.id",
  "  WHERE p.staged AND b.narrative_id IS NULL) AS blocked_no_binding,",
  "(SELECT count(DISTINCT p.id) FROM person p JOIN family_member fm ON fm.person_id=p.id",
  "  WHERE p.staged",
  "    AND NOT EXISTS (SELECT 1 FROM narrative n WHERE n.subjekt_type='person'",
  "                      AND n.subjekt_id=p.id AND n.source_id=3)",
  "    AND EXISTS (SELECT 1 FROM family_member fm2 JOIN person q ON q.id=fm2.person_id",
  "                WHERE fm2.family_id=fm.family_id AND q.id<>p.id AND NOT q.staged))",
  "  AS spouses_visible_partner")
```

**C0-berøringskontrollen skal med i CLI'en**, ikke kun i spec'ens prosa:
udvælgelsen må ikke indeholde en person, C0 efterlod uafklaret. Listen er
fast (C0's sammenlægnings-, for kort- og gennemgangs-kandidater) og
sammenlignes efter udvælgelsen:

```r
## C0's uafklarede person-id'er pr. 2026-08-19 (kandidater i klasserne
## sammenlaegning / for_kort / gennemgang). En af dem i udvalget ville
## betyde at D1 publicerer noget, en anden fase endnu ikke har afgjort.
C0_UAFKLAREDE <- c(929, 930, 974, 977, 991, 1013, 1014, 1017, 1021, 1028,
                   1138, 1220, 1239, 1241, 1243, 1291)
overlap <- intersect(selected$person_id, C0_UAFKLAREDE)
if (length(overlap) > 0L)
  stop(paste0("D1_EXPORT_SELECTION_C0_OVERLAP:", paste(overlap, collapse = ",")),
       call. = FALSE)
```

- [ ] **Step 7: Kør eksporten mod prod (read-only)**

Run:
```bash
mkdir -p work/task27-1939-v50-d1-publicering
Rscript .claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50.R \
  --output work/task27-1939-v50-d1-publicering/staged-selection-v1.json
shasum -a 256 work/task27-1939-v50-d1-publicering/staged-selection-v1.json
```
Expected: `selected` = **44**, `predicted_partners` = **24**,
`staged_total` = **96**, `blocked_no_binding` = **7**,
`spouses_visible_partner` = **21**.

**Afviger ét af de fem tal, STOP.** Basen har ændret sig siden målingen
2026-08-19, og både spec'ens antagelser og efterkontrollens forventede 68
skal revurderes.

Scriptet afbryder desuden selv med `D1_EXPORT_SELECTION_C0_OVERLAP`, hvis en
af C0's uafklarede er havnet i udvalget.

**Verificér også de seks `samme_som`:** alle skal have `samme_som_2020` =
`true` og pege på 2020-udgaven. Peger én på en anden 1939-person, er det en
dublet inden for udgaven — ikke et tværudgave-link — og den skal ud af D1 og
over i C3.

```bash
/usr/bin/python3 -c "
import json
d=json.load(open('work/task27-1939-v50-d1-publicering/staged-selection-v1.json'))
s=[r for r in d['selected'] if r['samme_som_2020']]
print('m. tværudgave-samme_som:', len(s), [r['person_id'] for r in s])
print('i alt valgte:', len(d['selected']), '| forudsagte partnere:', len(d['predicted_partners']))
"
```
Expected: 6 med `samme_som_2020`, 44 valgte, 24 partnere.

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50.R \
        .claude/skills/daa-extract/scripts/export_d1_staged_selection_1939_v50_helpers.R \
        .claude/skills/daa-extract/scripts/test_export_d1_staged_selection_1939_v50.R \
        tests/testthat/test-export-d1-staged-selection-1939-v50.R
git commit -m "feat(1939): deterministisk udvælgelse af fase D1's staged probander"
```

---

## Task 2: Token-filen — med genberegning af partner-udvidelsen

**Files:**
- Create: `.claude/skills/daa-extract/scripts/convert_d1_publication_decisions_1939_v50.py`
- Test: `.claude/skills/daa-extract/scripts/test_convert_d1_publication_decisions_1939_v50.py`

**Interfaces:**
- Consumes: Task 1's `staged-selection-v1.json`.
- Produces:
  - `VALID_TOKENS = ("[PUBLICÉR]", "[VENT]")`
  - `assign_pids(selected) -> dict[int, str]` (`P01`, `P02`, … efter stigende `person_id`)
  - `generate_document(selection_doc) -> str`
  - `convert_edited_document(text, selection_doc) -> dict`
  - `recompute_partners(selection_doc, chosen_ids) -> list[int]`
  - Beslutnings-JSON:
    `{schema_version: "1.0", person_ids: [int], held_back: [int],
      predicted_partners: [int], expected_unstaged_total: int}`

**Den centrale regel:** `[VENT]` på en proband må ikke efterlade dennes
partner i publiceringen. `recompute_partners` udleder partnerne af de
**valgte** id'er alene — ikke af Task 1's fulde liste — så en tilbageholdt
proband trækker sine egne partnere med ud, medmindre en anden valgt proband
også deler familie med dem.

- [ ] **Step 1: Skriv de fejlende tests**

```python
import importlib.util
import json
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "convert_d1_publication_decisions_1939_v50",
    Path(__file__).resolve().parent / "convert_d1_publication_decisions_1939_v50.py")
c = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(c)

DOC = {
    "schema_version": "1.0",
    "counts": {"staged_total": 96, "selected": 3, "predicted_partners": 2,
               "blocked_no_binding": 7, "spouses_visible_partner": 21},
    "selected": [
        {"person_id": 927, "visning_navn": "Henrik", "side": "507", "fakta": 1,
         "samme_som_2020": False, "partner_ids": []},
        {"person_id": 937, "visning_navn": "Gotskalk [Reventlow]", "side": "500",
         "fakta": 2, "samme_som_2020": True, "partner_ids": [1467]},
        {"person_id": 947, "visning_navn": "Hedevig Maria", "side": "598", "fakta": 3,
         "samme_som_2020": False, "partner_ids": [1468, 1467]},
    ],
    "predicted_partners": [
        {"person_id": 1467, "visning_navn": "Anna Margarethe von der Lieth",
         "via_person_ids": [937, 947]},
        {"person_id": 1468, "visning_navn": "Jørgen Nielsen Pougdal",
         "via_person_ids": [947]},
    ],
}


def _retok(text, person_id, new_token):
    pid = c.assign_pids(DOC["selected"])[person_id]
    lines = text.split("\n")
    for i, line in enumerate(lines):
        parsed = c._parse_positional(line)
        if parsed and parsed[1] == pid:
            lines[i] = new_token + line[len(parsed[0]):]
            return "\n".join(lines)
    raise AssertionError("linje for {} ikke fundet".format(person_id))


def test_generate_udfylder_publicer_paa_alle():
    text = c.generate_document(DOC)
    assert text.count("[PUBLICÉR]") >= 3


def test_generate_er_deterministisk():
    assert c.generate_document(DOC) == c.generate_document(DOC)


def test_pid_foelger_stigende_person_id():
    pids = c.assign_pids(DOC["selected"])
    assert pids[927] == "P01" and pids[947] == "P03"


def test_linjen_viser_partnere_der_foelger_med():
    text = c.generate_document(DOC)
    assert "1467" in text and "1468" in text


def test_convert_uaendret_giver_alle_44():
    result = c.convert_edited_document(c.generate_document(DOC), DOC)
    assert result["person_ids"] == [927, 937, 947]
    assert result["held_back"] == []
    assert result["predicted_partners"] == [1467, 1468]
    assert result["expected_unstaged_total"] == 5


def test_vent_fjerner_personen_og_dens_enepartner():
    # 947 er eneste vej til 1468; holdes 947 tilbage, skal 1468 også ud.
    text = _retok(c.generate_document(DOC), 947, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert result["person_ids"] == [927, 937]
    assert result["held_back"] == [947]
    assert result["predicted_partners"] == [1467]  # 937 er stadig en vej til 1467
    assert result["expected_unstaged_total"] == 3


def test_vent_beholder_partner_der_naas_via_en_anden_valgt():
    text = _retok(c.generate_document(DOC), 937, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert 1467 in result["predicted_partners"]  # 947 er stadig en vej


def test_alle_vent_giver_tom_publicering():
    text = c.generate_document(DOC)
    for pid in (927, 937, 947):
        text = _retok(text, pid, "[VENT]")
    result = c.convert_edited_document(text, DOC)
    assert result["person_ids"] == []
    assert result["predicted_partners"] == []
    assert result["expected_unstaged_total"] == 0


def test_convert_afviser_ukendt_token():
    text = _retok(c.generate_document(DOC), 927, "[MÅSKE]")
    with pytest.raises(SystemExit) as excinfo:
        c.convert_edited_document(text, DOC)
    assert excinfo.value.code == 2


def test_convert_afviser_redigeret_kontekst():
    text = c.generate_document(DOC).replace("Hedevig Maria", "Hedevig Marie")
    with pytest.raises(SystemExit):
        c.convert_edited_document(text, DOC)


def test_convert_afviser_slettet_linje():
    lines = [l for l in c.generate_document(DOC).split("\n")
             if not l.startswith("[PUBLICÉR]")]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(lines), DOC)


def test_convert_afviser_duplikeret_pid():
    lines = c.generate_document(DOC).split("\n")
    index = next(i for i, l in enumerate(lines) if c._parse_positional(l))
    duplikeret = lines[:index + 1] + [lines[index]] + lines[index + 1:]
    with pytest.raises(SystemExit):
        c.convert_edited_document("\n".join(duplikeret), DOC)


def test_convert_afviser_selection_uden_records():
    with pytest.raises(SystemExit):
        c.convert_edited_document("uanset hvad", {"schema_version": "1.0",
                                                  "selected": [],
                                                  "predicted_partners": []})
```

- [ ] **Step 2: Kør testene og bekræft at de fejler**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_convert_d1_publication_decisions_1939_v50.py -q`
Expected: FAIL — modulet findes ikke.

- [ ] **Step 3: Skriv konverteren**

Genbrug C0-konverterens struktur (`convert_c0_linkage_decisions_1939_v50.py`):
samme `_parse_positional`/`_canonical_for_compare`-kontrakt, samme
byte-identitets-gate, samme `_fail`+`sys.exit(2)`. Forskellene:

```python
VALID_TOKENS = ("[PUBLICÉR]", "[VENT]")
DEFAULT_TOKEN = "[PUBLICÉR]"

# Cifre og accenttegn SKAL med i tokenklassen -- É i [PUBLICÉR] ville
# ellers falde uden for, og hele arket blev tomt ved konvertering.
_DECISION_HEAD_RE = re.compile(r"^(\[[A-ZÆØÅÉ0-9]+\])([ \t]+)(P\d{2})(?=[ \t])")


def assign_pids(selected):
    """P-id'er er en ren funktion af eksportfilen -- aldrig af den redigerede
    tekst. Mennesket vælger token, ikke identitet."""
    ordered = sorted(selected, key=lambda r: r["person_id"])
    return {r["person_id"]: "P{:02d}".format(i)
            for i, r in enumerate(ordered, start=1)}


def render_line(record, pid, token):
    partners = record["partner_ids"]
    følger = ("følger med: " + ", ".join(str(p) for p in partners)) if partners \
        else "ingen partner følger med"
    tvaer = " [samme_som 2020]" if record["samme_som_2020"] else ""
    return "{}  {}  s.{}  {} ({} fakta){}  |  {}".format(
        token, pid, record["side"], record["visning_navn"], record["fakta"],
        tvaer, følger)


def recompute_partners(selection_doc, chosen_ids):
    """Partnere udledes af de VALGTE id'er alene.

    Holdes en proband tilbage, må dens partner ikke publiceres i dens sted --
    med mindre en anden valgt proband også deler familie med partneren. Det
    spejler RPC'ens egen familie-klausul, scopet til udvalget."""
    chosen = set(chosen_ids)
    out = []
    for partner in selection_doc["predicted_partners"]:
        if chosen & set(partner["via_person_ids"]):
            out.append(partner["person_id"])
    return sorted(out)
```

`convert_edited_document` returnerer
`{"schema_version": "1.0", "person_ids": sorted(valgte), "held_back":
sorted(vent), "predicted_partners": recompute_partners(...),
"expected_unstaged_total": len(person_ids) + len(predicted_partners)}`.

- [ ] **Step 4: Kør testene og bekræft at de passerer**

Run: `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_convert_d1_publication_decisions_1939_v50.py -q`
Expected: `0 failed`.

- [ ] **Step 5: Generér den ægte token-fil og aflevér den**

```bash
D=work/task27-1939-v50-d1-publicering
/usr/bin/python3 .claude/skills/daa-extract/scripts/convert_d1_publication_decisions_1939_v50.py \
  generate --selection $D/staged-selection-v1.json --output $D/d1-afgoerelser.txt
grep -cE '^\[[A-ZÆØÅÉ0-9]+\][ \t]+P[0-9]{2}' $D/d1-afgoerelser.txt   # forventet: 44
shasum -a 256 $D/d1-afgoerelser.txt
```

Send filen til brugeren med `SendUserFile`. **Stop og vent på afgørelserne.**

- [ ] **Step 6: Konvertér brugerens afgørelser**

```bash
D=work/task27-1939-v50-d1-publicering
/usr/bin/python3 .claude/skills/daa-extract/scripts/convert_d1_publication_decisions_1939_v50.py \
  convert --selection $D/staged-selection-v1.json --decisions $D/d1-afgoerelser.txt \
  --output $D/d1-afgoerelser.json
```
Expected: `expected_unstaged_total` = 68, hvis alle 44 står som `[PUBLICÉR]`.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/convert_d1_publication_decisions_1939_v50.py \
        .claude/skills/daa-extract/scripts/test_convert_d1_publication_decisions_1939_v50.py
git commit -m "feat(1939): token-fil til fase D1 m. genberegnet partner-udvidelse"
```

---

## Task 3: Apply-SQL med egne guards + rehearsal mod frisk restore

**Files:**
- Create: `work/task27-1939-v50-d1-publicering/d1-publicering-apply.sql` (ikke committet)
- Create: `work/task27-1939-v50-d1-publicering/d1-publicering-apply.sh` (ikke committet)
- Create: `work/task27-1939-v50-d1-publicering/d1-publicering-backup.sh` (ikke committet)

**Interfaces:**
- Consumes: Task 2's `d1-afgoerelser.json`.
- Produces: en hash-låst apply, der er kørt og verificeret mod en
  produktionsækvivalent restore.

- [ ] **Step 1: Skriv apply-SQL'en**

Én `DO`-blok i én transaktion, der bærer alle guards selv — samme mønster som
fase B's `narrative-publication-apply.sql`:

```sql
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_ids bigint[] := ARRAY[/* de valgte person_ids fra d1-afgoerelser.json */]::bigint[];
  v_expected_total integer := 68;   -- expected_unstaged_total fra beslutningsfilen
  v_before_staged integer;
  v_after_staged integer;
  v_before_person integer; v_after_person integer;
  v_before_fact integer;   v_after_fact integer;
  v_before_relation integer; v_after_relation integer;
  v_result jsonb;
BEGIN
  -- 1. Aktør: RPC'en kræver rollen redaktion, som udledes af auth.uid().
  PERFORM set_config('request.jwt.claim.sub', 'ba4ce28d-42a0-48af-a47c-773c26934236', true);
  IF (SELECT rolle FROM profiles WHERE id = 'ba4ce28d-42a0-48af-a47c-773c26934236') <> 'redaktion' THEN
    RAISE EXCEPTION 'D1_APPLY_ABORT: aktoer er ikke redaktion';
  END IF;

  -- 2. Baseline paa alt der IKKE maa aendre sig.
  SELECT count(*) INTO v_before_staged   FROM person WHERE staged;
  SELECT count(*) INTO v_before_person   FROM person;
  SELECT count(*) INTO v_before_fact     FROM fact;
  SELECT count(*) INTO v_before_relation FROM relation;
  IF v_before_staged <> 96 THEN
    RAISE EXCEPTION 'D1_APPLY_ABORT: forventede 96 staged, fandt %', v_before_staged;
  END IF;

  -- 3. Alle valgte SKAL vaere staged i forvejen; ellers er listen foraeldet.
  IF EXISTS (SELECT 1 FROM unnest(v_ids) AS t(id)
             WHERE NOT EXISTS (SELECT 1 FROM person p WHERE p.id=t.id AND p.staged)) THEN
    RAISE EXCEPTION 'D1_APPLY_ABORT: mindst ét valgt id er ikke staged';
  END IF;

  -- 4. Selve publiceringen (gaar gennem begin_change_set -> fortrydbar).
  v_result := red_publicer_personer(v_ids);

  -- 5. Efterkontrol: praecis det forventede antal, og nul delta paa alt andet.
  SELECT count(*) INTO v_after_staged   FROM person WHERE staged;
  SELECT count(*) INTO v_after_person   FROM person;
  SELECT count(*) INTO v_after_fact     FROM fact;
  SELECT count(*) INTO v_after_relation FROM relation;
  IF (v_before_staged - v_after_staged) <> v_expected_total THEN
    RAISE EXCEPTION 'D1_APPLY_ABORT: afstagede % , forventede %',
      v_before_staged - v_after_staged, v_expected_total;
  END IF;
  IF v_after_person <> v_before_person OR v_after_fact <> v_before_fact
     OR v_after_relation <> v_before_relation THEN
    RAISE EXCEPTION 'D1_APPLY_ABORT: kanonisk delta ud over staged';
  END IF;
  RAISE NOTICE 'D1_APPLY_OK: %', v_result;
END $$;
COMMIT;
```

Guard 5's andet led er kernen: D1 må **kun** ændre `staged`. Ændrer
person-, fact- eller relation-antallet sig, ruller hele transaktionen tilbage.

- [ ] **Step 2: Skriv wrapper-scriptet med SHA-gate**

Kopi af `work/task25-1939-v50-production-writer/narrative-publication-apply.sh`
med `APPLY_SQL` peget på D1's fil og `EXPECTED_SHA` sat til dens faktiske
SHA-256. Wrapper'en afbryder, hvis filen er ændret siden godkendelsen.

- [ ] **Step 3: Tag et friskt prod-dump**

Kopi af `narrative-publication-backup.sh` med
`DEST=…/daa-local-d1-rehearsal-$STAMP.dump`. Kør det og notér sti, mode,
bytes, SHA-256 og katalogantal.

- [ ] **Step 4: Restore til en frisk lokal base**

```bash
/opt/homebrew/opt/postgresql@17/bin/createdb daa1939_d1_rehearsal1
/opt/homebrew/opt/postgresql@17/bin/pg_restore --no-owner --no-privileges \
  -d daa1939_d1_rehearsal1 <dump-sti>
```
Verificér kontroltal mod prod: `person` 1812, staged 96, kilde-3-`narrative`
577, `private.source_record` 592. Notér cluster-id og bekræft at det er en
**anden identitet** end produktionen.

- [ ] **Step 5: Kør apply mod rehearsal-basen**

```bash
PGDATABASE=daa1939_d1_rehearsal1 psql -X -v ON_ERROR_STOP=1 \
  -d daa1939_d1_rehearsal1 -f work/task27-1939-v50-d1-publicering/d1-publicering-apply.sql
```
Expected: `D1_APPLY_OK`, exit 0.

**Partner-asserten er fasens vigtigste kontrol:** efterkontrollen skal vise
præcis 68 afstagede. Rammer den flere, findes der en familie-kant, vi ikke
kender — og så publiceres personer, ingen har godkendt. Det skal stoppe
kørslen her, ikke opdages i produktionen.

- [ ] **Step 6: Verificér efter-tilstanden i rehearsal-basen**

```sql
SELECT count(*) FILTER (WHERE staged) AS staged_tilbage,
       (SELECT count(*) FROM person) AS personer,
       (SELECT count(*) FROM fact) AS fakta,
       (SELECT count(*) FROM relation) AS relationer FROM person;
```
Expected: `staged_tilbage` = 28, og personer/fakta/relationer identiske med
før-tallene.

- [ ] **Step 7: Kør apply igen (idempotens)**

Expected: **afvist fail-closed** på guard 2 (`forventede 96 staged, fandt 28`).
En gentaget kørsel må ikke kunne gøre skade.

- [ ] **Step 8: Skriv rehearsal-rapporten**

`work/task27-1939-v50-d1-publicering/d1-rehearsal-report.md` (ikke committet)
med alle kommandoer, hashes og observerede tal.

---

## Task 4: GO-pakken

**Files:**
- Create: `docs/superpowers/reviews/1939-v50-fase-d1-readiness.md`

- [ ] **Step 1: Skriv readiness-dokumentet**

Skal indeholde, med eksakte værdier:

- Backup: sti, mode, bytes, SHA-256, katalogantal.
- Apply-SQL'ens SHA-256 (den wrapper'en er låst til).
- Beslutningsfilens og beslutnings-JSON'ens SHA-256.
- **Tallet 68**, forklaret: 44 valgte + 24 partner-stubs. Ikke »vi publicerer
  44«.
- Rehearsal-resultatet: 68 afstagede, 28 tilbage, nul kanonisk delta,
  gentaget kørsel afvist.
- At publiceringen er **fortrydbar** (`person` i `version_pk_registry`,
  RPC'en åbner change_set) — og at det ikke er en grund til at springe gates
  over.
- Hvad der bliver offentligt: 68 personer om afdøde fra DAA 1939. Ingen
  levende, ingen private.
- Eksplicit rest: 28 staged tilbage (7 blokerede af C0/C3, 21 til D2).

- [ ] **Step 2: Fremlæg for brugeren og vent på GO**

Ingen apply uden eksplicit godkendelse med tallene foran sig.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/reviews/1939-v50-fase-d1-readiness.md
git commit -m "docs(1939): GO-pakke for fase D1's publicering"
```

---

## Task 5: Prod-apply, efterkontrol og dokumentation

- [ ] **Step 1: Tag en frisk backup umiddelbart før**

Kør backup-scriptet igen med
`DEST=…/daa-production-before-d1-apply-$STAMP.dump`. Notér sti, mode, bytes,
SHA-256 og katalogantal. Denne backup er ny — rehearsal-dumpet tæller ikke.

- [ ] **Step 2: Kør apply mod prod — én gang**

```bash
bash work/task27-1939-v50-d1-publicering/d1-publicering-apply.sh
```
Expected: `D1_APPLY_OK`, exit 0.

**Ved fejl: ingen retry.** Blokken ruller selv tilbage. Rapportér fejlkoden
og stop; en fejlet guard betyder, at virkeligheden afviger fra det, GO-pakken
beskrev.

- [ ] **Step 3: Efterkontrol mod prod (read-only)**

```sql
SELECT count(*) FILTER (WHERE staged) AS staged_tilbage FROM person;
SELECT count(*) AS personer FROM person;
SELECT count(*) AS fakta FROM fact;
SELECT count(*) AS relationer FROM relation;
SELECT id, beskrivelse FROM change_set ORDER BY id DESC LIMIT 1;
```
Expected: `staged_tilbage` = 28; personer/fakta/relationer uændrede (1812 /
7199 / 2031 pr. 2026-08-19); nyeste change_set er `red_publicer_personer`.

- [ ] **Step 4: Verificér at de 68 faktisk er offentligt kvalificerede**

```sql
SELECT count(*) AS offentligt_kvalificerede FROM person p
WHERE p.id = ANY(ARRAY[/* de 68 */]::bigint[])
  AND NOT p.staged AND NOT p.levende AND NOT p.privat;
```
Expected: 68. `staged` alene gør ikke en person synlig — `levende` og
`privat` gælder stadig (invariant 8).

- [ ] **Step 5: Opdatér dokumentationen**

- `docs/changelog.md`: ny dateret post øverst med tallene og resten.
- `docs/database-current-state.md`: staged-tallet 96 → 28.
- `docs/superpowers/reviews/1939-v50-fase-d1-readiness.md`: tilføj
  »udført«-afsnit med de observerede efterkontroltal.

- [ ] **Step 6: Commit**

```bash
git add docs/changelog.md docs/database-current-state.md \
        docs/superpowers/reviews/1939-v50-fase-d1-readiness.md
git commit -m "docs(1939): fase D1 udført i prod — 68 personer publiceret"
```

- [ ] **Step 7: Bed brugeren verificere i web-fladen**

Nævn 2-3 konkrete person-id'er fra de 68 (fx 937 Gotskalk, 947 Hedevig
Maria), så kontrollen er hurtig. En publicering er udadvendt; det er værd at
se den med egne øjne.

---

## Definition of done

1. De 44 er udvalgt deterministisk af de tre objektive kriterier, og de fem
   kontroltal (96/44/24/7/21) er bekræftet mod prod.
2. Brugeren har truffet en afgørelse pr. person, og konverteren har
   genberegnet partner-udvidelsen ud fra de valgte.
3. Rehearsal mod frisk produktionsækvivalent restore: præcis 68 afstagede,
   28 tilbage, nul kanonisk delta, gentaget kørsel fail-closed afvist.
4. GO-pakken fremlagt med eksakte hashes og tal, og godkendt.
5. Én apply mod prod, ingen retry; efterkontrollen bekræfter 28 tilbage og
   uændrede person-/fact-/relation-tællinger.
6. De 68 er offentligt kvalificerede (ikke staged, ikke levende, ikke
   private).
7. Dokumentationen afstemt; brugeren har set resultatet i web-fladen.

## Uden for denne plan

De 7 blokerede staged (venter på C0's efterkørsel og C3). De 21 ægtefæller
med synlig partner (D2). Pensionering af dubletter — der er ingen i denne
mængde. Enhver ændring af fakta, relationer eller narrativer.
