# Fase D2 — de 21 gift-ind-ægtefæller: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicér de 21 staged gift-ind-ægtefæller, hvis partner allerede er
synlig, gennem en read-only eksport med kontroltal og én fail-closed apply.

**Architecture:** To R-scripts efter husets 1939-v50-mønster: en ren,
DB-fri helper-fil med al transformations- og valideringslogik (testbar uden
forbindelse) plus en tynd CLI-wrapper der åbner forbindelsen. Eksporten er
strengt read-only; apply'en kalder `red_publicer_personer` én gang bag en
eksplicit bekræftelses-flag.

**Tech Stack:** R (DBI/RPostgres), testthat, Postgres/Supabase.

**Spec:** `docs/superpowers/specs/2026-08-20-1939-v50-fase-d2-aegtefaeller-design.md`

---

## ⚠️ AFVIGELSER FRA DENNE PLAN — læs før du kopierer kode herfra

**Hele planen er udført** (commits `aaf96b0`, `f5f9789`, `61840e5`, `8297927`, `c8d2c7c`). Den kode,
der faktisk kører, står i scripterne — ikke her. **Kodeblokkene nedenfor
indeholder fem fejl, der alle er rettet i scripterne.** Kopiér dem ikke.

1. **Task 2, Step 1, test 10** — `fixture_doc(selected = list())` virker ikke.
   `modifyList` rekurserer, når begge sider er lister, og en navnløs tom liste
   efterlader feltet **urørt**. `D2_APPLY_EMPTY` ville aldrig fyre, og testen
   ville bestå af den forkerte grund. Byg doc'et og sæt `$selected <- list()`.

2. **Task 1, Step 5** — `md5(current_setting('cluster_name', true) || …)` giver
   `null` på Supabase. Brug D1's `(pg_control_system()).system_identifier::text`.

3. **Task 2, Step 5 — ville have stoppet Task 3.** Wrapperen kalder
   `red_publicer_personer` uden at etablere aktøren. RPC'en gates på
   `current_rolle()='redaktion'`, som udledes af `profiles WHERE id =
   auth.uid()`; over en direkte forbindelse er `auth.uid()` NULL → rollen bliver
   `medlem` → RPC'en kaster. Aktøren skal sættes med
   `set_config('request.jwt.claim.sub', <uuid>, true)` **inde i transaktionen**
   og verificeres mod `profiles` — som i fase B's og D1's apply-SQL.

4. **Task 2, Step 3 — `d2_plan_apply` sammenligner antal, ikke hvem.** Mister en
   valgt person sin synlige partner (men forbliver staged) mens en anden staged
   person får én, er antallene uændrede og SHA-låsen passerer — filen er ægte,
   bare forældet på en måde der bevarer antallet. Sammenlign id-**mængden**, og
   mål den inde i skrive-transaktionen (lukker samtidig TOCTOU-vinduet).

5. **Task 1 — ingen gate på `levende`/`privat`/navn.** SQL-prædikatet filtrerer
   kun på `staged` + synlig partner, så invariant 8 håndhæves ingen steder.
   Gaten hører i helperen, og `NA` skal spærre (`any(logical(0))` er `FALSE`, så
   en manglende kolonne ville få gaten til at tie).

**Desuden tilføjet ud over planen:** `--expect-sha256` og `--backup` er
obligatoriske; efterkontrollen kører inde i transaktionen med eksplicit
rollback; en fejlet `dbCommit` melder `D2_APPLY_COMMIT_UKENDT`.

**Task 3 afveg også:** planen udelod den rehearsal, D1's plan krævede. Den blev
kørt alligevel mod en frisk prod-restore, før prod-kørslen. Se
`docs/superpowers/reviews/1939-v50-fase-d2-go-pakke.md`.

**Task 3 er udført 2026-08-20** — `change_set 960`, staged 28 → 7. Kun trin 7
(brugerens verifikation i web-fladen) udestår.

---

## Global Constraints

- **Prod-wrappere skal være fail-closed.** Ethvert skrivende script SKAL
  kræve `--jeg-mener-det` og SKAL afvise ukendte og duplikerede flag med en
  fejl. Baggrund: i fase D1 blev et opfundet `--dryrun` stiltiende ignoreret,
  og 68 personer blev publiceret i prod uden godkendelse. Et ukendt flag må
  aldrig blive til en tavs accept.
- **Ingen navnematchning i udvælgelse.** Fornavne genbruges i hver generation
  i en adelsslægt. Kun `staged` + familie-relation afgør.
- **Eksporten skriver aldrig.** Ingen RPC-kald, ingen `UPDATE`.
- **`private.source_record` og narrativer røres ikke.** D2 rører kun
  `person.staged`.
- **Fejlkoder er stabile strenge** i `SCREAMING_SNAKE_CASE` med prefikset
  `D2_`, så de kan matches i tests og i drift.
- **R-scripts læser forbindelsen** fra `PGHOST`/`PGDATABASE`/… med fallback
  til `SUPABASE_*` — samme `env_or`-mønster som
  `export_d1_staged_selection_1939_v50.R:49-58`.

---

### Task 1: Eksport af de 21 (read-only) med kontroltal — ✅ UDFØRT (aaf96b0, hærdet i 61840e5)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_export_d2_spouse_selection_1939_v50.R`
- Create: `tests/testthat/test-export-d2-spouse-selection-1939-v50.R`

**Interfaces:**
- Consumes: intet fra tidligere tasks.
- Produces: `build_d2_spouse_selection_1939_v50(selected_rows, counts, database_name, database_identity, generator)` → `list` med felterne `schema_version`, `database_name`, `database_identity`, `generator`, `counts`, `selected`. Task 2 læser den JSON, dette bygger.

- [x] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_export_d2_spouse_selection_1939_v50.R`:

```r
## DB-fri tests for export_d2_spouse_selection_1939_v50_helpers.R.
## Selve DBI-forbindelsen er IKKE testet her (samme konvention som de oevrige
## 1939-v50-eksportoerer).
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_d2_spouse_selection_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

fixture_rows <- function() {
  data.frame(
    person_id = c(1487, 1480),
    visning_navn = c("B", "A"),
    partner_id = c(801, 800),
    har_samme_som = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  )
}
fixture_counts <- function(...) {
  base <- list(valgte = 2, staged_i_alt = 9, staged_bagefter = 7,
               ekstra_medrevne = 0, overlap_c0 = 0)
  utils::modifyList(base, list(...))
}

## 1) Lykkelig sti: dokumentet er sorteret paa person_id og baerer alle felter.
doc <- build_d2_spouse_selection_1939_v50(
  fixture_rows(), fixture_counts(), "postgres", "abc", "test")
expect(identical(doc$schema_version, "1.0"))
expect(identical(length(doc$selected), 2L))
expect(identical(doc$selected[[1]]$person_id, 1480))
expect(identical(doc$selected[[2]]$person_id, 1487))
expect(identical(doc$selected[[1]]$har_samme_som, TRUE))
expect(identical(doc$counts$valgte, 2))

## 2) counts$valgte skal stemme med antal raekker, ellers er maalingen raadden.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(valgte = 3), "postgres", "abc", "test"),
  "D2_SELECTION_COUNT_MISMATCH")

## 3) Dubletter i udvalget ville taelle en person to gange.
dup <- fixture_rows(); dup$person_id <- c(1480, 1480)
expect_error(
  build_d2_spouse_selection_1939_v50(dup, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_DUPLICATE_PERSON")

## 4) Ekstra medrevne betyder at RPC'en vil afstage nogen vi ikke har set paa.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(ekstra_medrevne = 1), "postgres", "abc", "test"),
  "D2_SELECTION_EXTRA_SWEPT")

## 5) Overlap med C0's uafklarede: D2 maa ikke publicere noget C0 ikke har afgjort.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(overlap_c0 = 1), "postgres", "abc", "test"),
  "D2_SELECTION_C0_OVERLAP")

## 6) Regnestykket skal gaa op: staged_i_alt - valgte == staged_bagefter.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(staged_bagefter = 6), "postgres", "abc", "test"),
  "D2_SELECTION_REMAINDER_MISMATCH")

## 7) Tom mangde er ikke en gyldig D2-koersel.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows()[0, ], fixture_counts(valgte = 0, staged_bagefter = 9),
    "postgres", "abc", "test"),
  "D2_SELECTION_EMPTY")

cat(sprintf("OK: %d assertions\n", ok))
```

Create `tests/testthat/test-export-d2-spouse-selection-1939-v50.R`:

```r
testthat::test_that("export-d2-spouse-selection R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_export_d2_spouse_selection_1939_v50.R", local = TRUE))
})
```

- [x] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_export_d2_spouse_selection_1939_v50.R
```
Expected: FAIL — `cannot open file 'export_d2_spouse_selection_1939_v50_helpers.R'`

- [x] **Step 3: Write the helpers**

Create `.claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50_helpers.R`:

```r
## Ren transformation: DB-raekker -> eksportdokument for fase D2.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme moenster som
## export_d1_staged_selection_1939_v50_helpers.R).
##
## Dokumentet er D2's grundlag: de staged gift-ind-aegtefaeller hvis partner
## allerede er synlig. Alle fem kontroltal valideres HER, saa en raadden
## maaling ikke kan naa frem til apply-trinnet.

build_d2_spouse_selection_1939_v50 <- function(selected_rows, counts,
                                               database_name, database_identity,
                                               generator) {
  n <- nrow(selected_rows)
  if (n == 0L) stop("D2_SELECTION_EMPTY", call. = FALSE)
  if (anyDuplicated(selected_rows$person_id))
    stop("D2_SELECTION_DUPLICATE_PERSON", call. = FALSE)
  if (!identical(as.numeric(counts$valgte), as.numeric(n)))
    stop("D2_SELECTION_COUNT_MISMATCH", call. = FALSE)
  ## RPC'ens medrivnings-praedikat filtrerer IKKE paa rolle: et staged barn i
  ## samme familie ville ogsaa blive afstaget. Er tallet ikke 0, publicerer vi
  ## nogen vi ikke har set paa.
  if (!identical(as.numeric(counts$ekstra_medrevne), 0))
    stop("D2_SELECTION_EXTRA_SWEPT", call. = FALSE)
  if (!identical(as.numeric(counts$overlap_c0), 0))
    stop("D2_SELECTION_C0_OVERLAP", call. = FALSE)
  if (!identical(as.numeric(counts$staged_i_alt) - as.numeric(counts$valgte),
                 as.numeric(counts$staged_bagefter)))
    stop("D2_SELECTION_REMAINDER_MISMATCH", call. = FALSE)

  selected <- lapply(order(selected_rows$person_id), function(i) list(
    person_id     = as.numeric(selected_rows$person_id[[i]]),
    visning_navn  = as.character(selected_rows$visning_navn[[i]]),
    partner_id    = as.numeric(selected_rows$partner_id[[i]]),
    har_samme_som = as.logical(selected_rows$har_samme_som[[i]])
  ))

  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       counts = counts, selected = selected)
}
```

- [x] **Step 4: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_export_d2_spouse_selection_1939_v50.R
```
Expected: `OK: 7 assertions`

- [x] **Step 5: Write the CLI wrapper**

Create `.claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50.R`:

```r
#!/usr/bin/env Rscript
## CLI: Rscript export_d2_spouse_selection_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY udvaelgelse af fase D2: de staged gift-ind-aegtefaeller hvis
## partner allerede er synlig.
##
## Udvaelgelsen bygger paa ET objektivt praedikat, aldrig paa navne:
##   person.staged AND der findes en partner i samme family som IKKE er staged.
## Navnematchning er bevidst udeladt: i en adelsslaegt genbruges fornavne i
## hver generation.
##
## Skriver aldrig til databasen; kalder ingen RPC.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("D2_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("D2_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("D2_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("D2_EXPORT_SELECTION_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags)
  value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_d2_spouse_selection_1939_v50_helpers.R"))

## C0's uafklarede person-id'er pr. 2026-08-19. En af dem i udvalget ville
## betyde at D2 publicerer noget, en anden fase endnu ikke har afgjort.
C0_UAFKLAREDE <- c(929, 930, 974, 977, 991, 1013, 1014, 1017, 1021, 1028,
                   1138, 1220, 1239, 1241, 1243, 1291)

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable"
            else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE")
            else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

identity <- DBI::dbGetQuery(con,
  "SELECT current_database() AS database_name,
          md5(current_setting('cluster_name', true) || current_database()) AS database_identity")
if (!is.na(expect_database_name) &&
    !identical(identity$database_name[[1L]], expect_database_name))
  stop("D2_EXPORT_SELECTION_DATABASE_MISMATCH", call. = FALSE)

selection_sql <- "
WITH s AS (
  SELECT p.id AS person_id, p.visning_navn,
         (SELECT min(f2.person_id) FROM family_member f1
            JOIN family_member f2 ON f2.family_id=f1.family_id
                                 AND f2.person_id<>p.id AND f2.rolle='partner'
            JOIN person a ON a.id=f2.person_id AND NOT a.staged
           WHERE f1.person_id=p.id AND f1.rolle='partner') AS partner_id
    FROM person p
   WHERE p.staged AND EXISTS (
     SELECT 1 FROM family_member f1
       JOIN family_member f2 ON f2.family_id=f1.family_id
                            AND f2.person_id<>p.id AND f2.rolle='partner'
       JOIN person a ON a.id=f2.person_id
      WHERE f1.person_id=p.id AND f1.rolle='partner' AND NOT a.staged)
)
SELECT s.person_id, s.visning_navn, s.partner_id,
       EXISTS (SELECT 1 FROM relation r
                WHERE r.rolle='samme_som'
                  AND ((r.subjekt_type='person' AND r.subjekt_id=s.person_id)
                    OR (r.objekt_type='person'  AND r.objekt_id =s.person_id))) AS har_samme_som
  FROM s ORDER BY s.person_id"
selected_rows <- DBI::dbGetQuery(con, selection_sql)

## Simulér RPC'ens EGEN WHERE-klausul, saa 'ekstra medrevne' kan maales foer
## apply. Praedikatet filtrerer bevidst ikke paa rolle -- det goer RPC'en heller
## ikke, og det er netop faelden vi vil se.
ids <- selected_rows$person_id
swept <- DBI::dbGetQuery(con, "
  SELECT count(*) AS n FROM person p
   WHERE p.staged = true
     AND (p.id = ANY($1::bigint[])
       OR EXISTS (SELECT 1 FROM family_member fm1
                    JOIN family_member fm2 ON fm2.family_id = fm1.family_id
                   WHERE fm1.person_id = p.id AND fm2.person_id = ANY($1::bigint[])))",
  params = list(paste0("{", paste(ids, collapse = ","), "}")))

staged_total <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM person WHERE staged")$n[[1L]]

counts <- list(
  valgte          = as.numeric(nrow(selected_rows)),
  staged_i_alt    = as.numeric(staged_total),
  staged_bagefter = as.numeric(staged_total) - as.numeric(swept$n[[1L]]),
  ekstra_medrevne = as.numeric(swept$n[[1L]]) - as.numeric(nrow(selected_rows)),
  overlap_c0      = as.numeric(length(intersect(ids, C0_UAFKLAREDE))))

doc <- build_d2_spouse_selection_1939_v50(
  selected_rows, counts,
  identity$database_name[[1L]], identity$database_identity[[1L]],
  "export_d2_spouse_selection_1939_v50.R")

writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE, null = "null"), output)
cat(sprintf("valgte=%d staged_i_alt=%d staged_bagefter=%d ekstra_medrevne=%d overlap_c0=%d\n",
            counts$valgte, counts$staged_i_alt, counts$staged_bagefter,
            counts$ekstra_medrevne, counts$overlap_c0))
```

- [x] **Step 6: Run the full R suite**

Run: `Rscript run-tests.R`
Expected: alle tests grønne, inkl. den nye `test-export-d2-spouse-selection-1939-v50.R`

- [x] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50*.R \
        .claude/skills/daa-extract/scripts/test_export_d2_spouse_selection_1939_v50.R \
        tests/testthat/test-export-d2-spouse-selection-1939-v50.R
git commit -m "feat(1939): read-only eksport af fase D2's 21 ægtefæller"
```

---

### Task 2: Fail-closed apply-wrapper — ✅ UDFØRT (f5f9789, hærdet i 61840e5)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50_helpers.R`
- Create: `.claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50.R`
- Create: `.claude/skills/daa-extract/scripts/test_apply_d2_spouses_1939_v50.R`
- Create: `tests/testthat/test-apply-d2-spouses-1939-v50.R`

**Interfaces:**
- Consumes: JSON-dokumentet fra Task 1 — felterne `counts` og `selected[].person_id`.
- Produces: `d2_parse_apply_args(args)` → `list(selection = <path>, expect_sha256 = <chr eller NA>)`, og `d2_plan_apply(doc, live_counts)` → `list(ids = <numeric>, forventet_bagefter = <numeric>)`.

- [x] **Step 1: Write the failing test**

Create `.claude/skills/daa-extract/scripts/test_apply_d2_spouses_1939_v50.R`:

```r
## DB-fri tests for apply_d2_spouses_1939_v50_helpers.R -- CLI-gaten og
## guarden mod at basen har flyttet sig siden eksporten.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_d2_spouses_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

## --- CLI-gaten ---------------------------------------------------------
## 1) Lykkelig sti.
parsed <- d2_parse_apply_args(c("--selection", "s.json", "--jeg-mener-det"))
expect(identical(parsed$selection, "s.json"))
expect(identical(parsed$expect_sha256, NA_character_))

## 2) UDEN bekraeftelses-flaget skal den afvise. Dette er hele pointen:
##    i fase D1 blev et opfundet --dryrun ignoreret, og 68 personer blev
##    publiceret i prod uden godkendelse.
expect_error(d2_parse_apply_args(c("--selection", "s.json")),
             "D2_APPLY_CONFIRMATION_REQUIRED")

## 3) Et UKENDT flag maa aldrig blive til tavs accept.
expect_error(
  d2_parse_apply_args(c("--selection", "s.json", "--dryrun", "--jeg-mener-det")),
  "D2_APPLY_CLI_INVALID")

## 4) Duplikerede flag er ogsaa en fejl.
expect_error(
  d2_parse_apply_args(c("--selection", "a.json", "--selection", "b.json",
                        "--jeg-mener-det")),
  "D2_APPLY_CLI_INVALID")

## 5) --selection er paakraevet.
expect_error(d2_parse_apply_args("--jeg-mener-det"), "D2_APPLY_CLI_INVALID")

## 6) En flag-vaerdi der selv ligner et flag er en tastefejl, ikke en vaerdi.
expect_error(
  d2_parse_apply_args(c("--selection", "--jeg-mener-det")),
  "D2_APPLY_CLI_INVALID")

## --- Guarden mod at basen har flyttet sig ------------------------------
fixture_doc <- function(...) {
  base <- list(
    counts = list(valgte = 2, staged_i_alt = 9, staged_bagefter = 7,
                  ekstra_medrevne = 0, overlap_c0 = 0),
    selected = list(list(person_id = 1480), list(person_id = 1487)))
  utils::modifyList(base, list(...))
}

## 7) Lykkelig sti: live-taellingen matcher eksporten.
plan <- d2_plan_apply(fixture_doc(), list(staged_i_alt = 9, valgte = 2))
expect(identical(plan$ids, c(1480, 1487)))
expect(identical(plan$forventet_bagefter, 7))

## 8) Har staged-maengden flyttet sig, er eksportens tal foraeldede.
expect_error(
  d2_plan_apply(fixture_doc(), list(staged_i_alt = 10, valgte = 2)),
  "D2_APPLY_STAGED_DRIFT")

## 9) Er selve udvalget skiftet, peger vi paa andre mennesker end dem der blev
##    gennemgaaet.
expect_error(
  d2_plan_apply(fixture_doc(), list(staged_i_alt = 9, valgte = 3)),
  "D2_APPLY_SELECTION_DRIFT")

## 10) Et tomt udvalg maa aldrig naa til apply.
expect_error(
  d2_plan_apply(fixture_doc(selected = list(), counts = list(
    valgte = 0, staged_i_alt = 9, staged_bagefter = 9,
    ekstra_medrevne = 0, overlap_c0 = 0)), list(staged_i_alt = 9, valgte = 0)),
  "D2_APPLY_EMPTY")

cat(sprintf("OK: %d assertions\n", ok))
```

Create `tests/testthat/test-apply-d2-spouses-1939-v50.R`:

```r
testthat::test_that("apply-d2-spouses R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_apply_d2_spouses_1939_v50.R", local = TRUE))
})
```

- [x] **Step 2: Run test to verify it fails**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_apply_d2_spouses_1939_v50.R
```
Expected: FAIL — `cannot open file 'apply_d2_spouses_1939_v50_helpers.R'`

- [x] **Step 3: Write the helpers**

Create `.claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50_helpers.R`:

```r
## Ren logik bag fase D2's apply: CLI-gaten og guarden mod at basen har
## flyttet sig siden eksporten. Ingen DB-adgang, saa begge kan testes uden
## forbindelse.

## Fail-closed argument-parser. Et ukendt flag er en FEJL, ikke noget der
## ignoreres: i fase D1 blev et opfundet --dryrun stiltiende slugt, og 68
## personer blev publiceret i prod uden godkendelse.
d2_parse_apply_args <- function(args) {
  allowed <- c("--selection", "--expect-sha256", "--jeg-mener-det")
  flags <- args[grepl("^--", args)]
  if (any(!flags %in% allowed) || anyDuplicated(flags))
    stop("D2_APPLY_CLI_INVALID", call. = FALSE)
  if (!("--selection" %in% flags)) stop("D2_APPLY_CLI_INVALID", call. = FALSE)
  value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
      stop("D2_APPLY_CLI_INVALID", call. = FALSE)
    args[[index + 1L]]
  }
  selection <- value("--selection")
  expect_sha256 <- if ("--expect-sha256" %in% flags) value("--expect-sha256") else NA_character_
  ## Bekraeftelsen tjekkes SIDST, saa en malformet kommandolinje aldrig kan
  ## fremstaa som "manglede bare bekraeftelsen".
  if (!("--jeg-mener-det" %in% flags))
    stop("D2_APPLY_CONFIRMATION_REQUIRED", call. = FALSE)
  list(selection = selection, expect_sha256 = expect_sha256)
}

## Sammenligner eksportens tal med basen som den ser ud NU.
d2_plan_apply <- function(doc, live_counts) {
  ids <- vapply(doc$selected, function(r) as.numeric(r$person_id), numeric(1))
  if (length(ids) == 0L) stop("D2_APPLY_EMPTY", call. = FALSE)
  if (!identical(as.numeric(live_counts$staged_i_alt),
                 as.numeric(doc$counts$staged_i_alt)))
    stop("D2_APPLY_STAGED_DRIFT", call. = FALSE)
  if (!identical(as.numeric(live_counts$valgte), as.numeric(doc$counts$valgte)))
    stop("D2_APPLY_SELECTION_DRIFT", call. = FALSE)
  list(ids = sort(ids),
       forventet_bagefter = as.numeric(doc$counts$staged_bagefter))
}
```

- [x] **Step 4: Run test to verify it passes**

Run:
```bash
cd .claude/skills/daa-extract/scripts && Rscript test_apply_d2_spouses_1939_v50.R
```
Expected: `OK: 10 assertions`

- [x] **Step 5: Write the CLI wrapper**

Create `.claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50.R`:

```r
#!/usr/bin/env Rscript
## CLI: Rscript apply_d2_spouses_1939_v50.R --selection PATH --jeg-mener-det
##   [--expect-sha256 HEX]
##
## SKRIVER TIL PRODUKTION. Kalder red_publicer_personer EEN gang med de 21
## person-id'er fra eksporten. Ingen retry: gaar det galt, stopper vi og
## undersoeger.
##
## --jeg-mener-det er obligatorisk, og ukendte flag afvises. Baggrund: i fase
## D1 blev et opfundet --dryrun ignoreret, og 68 personer blev publiceret uden
## godkendelse.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_d2_spouses_1939_v50_helpers.R"))

parsed <- d2_parse_apply_args(args)
if (!file.exists(parsed$selection)) stop("D2_APPLY_SELECTION_MISSING", call. = FALSE)
if (!is.na(parsed$expect_sha256)) {
  ## file= hasher filens bytes og matcher derfor `shasum -a 256` fra Step 2.
  ## digest(<streng>, serialize=FALSE) ville hashe indholdet som streng og
  ## kunne afvige paa afsluttende newline -- brug IKKE den form her.
  actual <- digest::digest(file = parsed$selection, algo = "sha256")
  if (!identical(actual, parsed$expect_sha256))
    stop("D2_APPLY_SELECTION_SHA_MISMATCH", call. = FALSE)
}
doc <- jsonlite::fromJSON(parsed$selection, simplifyVector = FALSE)

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable"
            else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE")
            else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

live_staged <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM person WHERE staged")$n[[1L]]
live_valgte <- DBI::dbGetQuery(con, "
  SELECT count(*) AS n FROM person p
   WHERE p.staged AND EXISTS (
     SELECT 1 FROM family_member f1
       JOIN family_member f2 ON f2.family_id=f1.family_id
                            AND f2.person_id<>p.id AND f2.rolle='partner'
       JOIN person a ON a.id=f2.person_id
      WHERE f1.person_id=p.id AND f1.rolle='partner' AND NOT a.staged)")$n[[1L]]

plan <- d2_plan_apply(doc, list(staged_i_alt = live_staged, valgte = live_valgte))

result <- DBI::dbGetQuery(con,
  "SELECT red_publicer_personer($1::bigint[]) AS resultat",
  params = list(paste0("{", paste(plan$ids, collapse = ","), "}")))
cat(result$resultat[[1L]], "\n")

efter <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM person WHERE staged")$n[[1L]]
if (!identical(as.numeric(efter), plan$forventet_bagefter))
  stop("D2_APPLY_POSTCHECK_MISMATCH", call. = FALSE)
cat(sprintf("OK: staged %d -> %d\n", live_staged, efter))
```

- [x] **Step 6: Run the full R suite**

Run: `Rscript run-tests.R`
Expected: alle tests grønne, inkl. `test-apply-d2-spouses-1939-v50.R`

- [x] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50*.R \
        .claude/skills/daa-extract/scripts/test_apply_d2_spouses_1939_v50.R \
        tests/testthat/test-apply-d2-spouses-1939-v50.R
git commit -m "feat(1939): fail-closed apply-wrapper til fase D2"
```

---

### Task 3: Kørsel mod prod — ✅ UDFØRT 2026-08-20 (change_set 960, staged 28 → 7)

**Files:**
- Modify: `docs/changelog.md`
- Modify: `docs/database-current-state.md`

**Interfaces:**
- Consumes: begge scripts fra Task 1 og 2.
- Produces: intet kode; prod-tilstanden ændres, og dokumentationen afstemmes.

> **GATE:** Dette trin skriver til produktion og må først køres, når brugeren
> udtrykkeligt har sagt GO til de faktiske tal fra Step 2. Ingen af trinene
> må slås sammen.

- [x] **Step 1: Tag backup**

Run:
```bash
mkdir -p work/task28-1939-v50-d2-aegtefaeller
pg_dump --format=custom --no-owner --no-acl \
  --file=work/task28-1939-v50-d2-aegtefaeller/pre-d2-$(date +%Y%m%d-%H%M%S).dump
chmod 0600 work/task28-1939-v50-d2-aegtefaeller/*.dump
shasum -a 256 work/task28-1939-v50-d2-aegtefaeller/*.dump
```
Expected: én dump-fil, 0600, SHA-256 noteret. Basen kører på free tier og har
ingen automatisk backup.

- [x] **Step 2: Kør eksporten (read-only) og fremlæg tallene**

Run:
```bash
Rscript .claude/skills/daa-extract/scripts/export_d2_spouse_selection_1939_v50.R \
  --output work/task28-1939-v50-d2-aegtefaeller/spouse-selection-v1.json
shasum -a 256 work/task28-1939-v50-d2-aegtefaeller/spouse-selection-v1.json
```
Expected: `valgte=21 staged_i_alt=28 staged_bagefter=7 ekstra_medrevne=0 overlap_c0=0`

**Afviger ét tal, STOP** og fremlæg afvigelsen for brugeren. Scriptet afbryder
selv ved `ekstra_medrevne > 0` og ved overlap med C0.

Fremlæg for brugeren: de fem tal, filens SHA-256, og at 21 mennesker bliver
offentligt synlige. Vent på eksplicit GO.

- [x] **Step 3: Apply — én gang, ingen retry**

Run:
```bash
Rscript .claude/skills/daa-extract/scripts/apply_d2_spouses_1939_v50.R \
  --selection work/task28-1939-v50-d2-aegtefaeller/spouse-selection-v1.json \
  --expect-sha256 <SHA fra Step 2> \
  --jeg-mener-det
```
Expected: `OK: staged 28 -> 7`

Fejler den, STOP. Kør ikke igen — undersøg først hvad der ændrede sig.

- [x] **Step 4: Efterkontrol**

Run (forbindelsen bygges af `~/.Renviron`, samme kilde som scripterne bruger):
```bash
val() { sed -n "s/^$1=//p" ~/.Renviron | tr -d '"' | head -1; }
export PGPASSWORD="$(val SUPABASE_PASSWORD)"
psql "host=$(val SUPABASE_HOST) port=$(val SUPABASE_PORT) dbname=$(val SUPABASE_DB) user=$(val SUPABASE_USER) sslmode=require" -X -c "
BEGIN READ ONLY;
SELECT count(*) FILTER (WHERE staged) AS staged_tilbage,
       count(*) AS personer_i_alt FROM person;
SELECT count(*) AS ikke_kvalificerede FROM person
 WHERE id = ANY('{1480,1487,1488,1553,1554,1555,1618,1650,1651,1657,1659,1662,1664,1665,1669,1671,1682,1695,1698,1714,1716}'::bigint[])
   AND (staged OR levende OR privat OR visning_navn IS NULL);
ROLLBACK;"
```
Expected: `staged_tilbage = 7`, `personer_i_alt` uændret, `ikke_kvalificerede = 0`

- [x] **Step 5: Opdatér dokumentationen**

Skriv i `docs/changelog.md` en dateret post med: de fem kontroltal, dump-filens
navn og SHA-256, change_set-id'et fra RPC-svaret, og at de 7 tilbage er D3's
blokerede. Afstem persontallene i `docs/database-current-state.md`.

- [x] **Step 6: Commit**

```bash
git add docs/changelog.md docs/database-current-state.md
git commit -m "docs(1939): fase D2 udført i prod — 21 ægtefæller publiceret"
```

- [ ] **Step 7: Brugerens verifikation i web-fladen** ← UDESTÅR

Bed brugeren bekræfte i web-fladen at et af de 21 ægteskaber nu viser begge
parter — og særligt at person 1662's ægteskab fremgår på den collapsede person
sammen med 785's.

---

## Fortrydelse

Går noget galt efter apply: RPC'en åbnede et `change_set`, og `person` står i
`version_pk_registry`. Publiceringen kan rulles tilbage ad den almindelige
fortryd-vej. Dump-filen fra Step 1 er sidste udvej.
