# TNG-QA Crosswalk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read-only R-pipeline der bruger TNG-dumpet som sammenlignings-reference til at afsløre kandidat-fejl i ægteskaber/forældre-barn/datoer/køn i vores Supabase-base, via en genbrugbar fuzzy-matchet crosswalk.

**Architecture:** Seks isolerede trin (extract → pull → normalisér → match → review → sammenlign), rene funktioner adskilt fra I/O. TNG-dump (MySQL) escape-fixes og loades til lokal DuckDB. Attribut-baseret, ikke-cirkulær matching med injektiv 1:1 crosswalk og tre tiers. Diskrepans-rapport bag en PII-gate.

**Tech Stack:** R (DBI, duckdb, RPostgres, dplyr, stringdist, stringi, testthat).

**Spec:** `docs/superpowers/specs/2026-06-29-tng-qa-crosswalk-design.md`

## Global Constraints

- **Read-only mod Supabase.** Ingen INSERT/UPDATE/DELETE. Brug dedikeret SELECT-only forbindelse + read-only transaktion; valider ved opstart.
- **Diakritik bevares ALTID** (æøå/accenter). Aldrig ASCII-folding. Lowercase kun til sammenligning, rå form til rapport.
- **TNG = reference, ikke facit.** Uenigheder = uafklarede, ikke "vores fejl".
- **Følsomme filer git-ignored** (allerede i `.gitignore`): `data/tng.duckdb`, `data/tng-crosswalk.csv`, `data/tng-review-queue.csv`. Forlader aldrig disken.
- **Committed rapport må ikke indeholde levende-PII.** PII-gate håndhæver.
- **Matching aldrig på relationer** (ikke-cirkularitet). Struktur kun som review-flag.
- **Crosswalk injektiv** (global 1:1). **Kant sammenlignes kun når begge endepunkter matchet.**
- Alle nye R-filer under `R/tng-qa/`. Tests under `tests/testthat/`. Kun funktions-definitioner i kildefiler (ingen top-level eksekvering).
- Sekretter fra `~/.Renviron` (`SUPABASE_HOST/USER/PASSWORD`), aldrig i kode/git.

---

### Task 1: Test-harness setup

**Files:**
- Create: `tests/testthat/helper-source.R`
- Create: `run-tests.R`
- Create: `R/tng-qa/.gitkeep`

**Interfaces:**
- Produces: testthat kører alle `tests/testthat/test-*.R`; `helper-source.R` source'er alle `R/tng-qa/*.R` så rene funktioner er tilgængelige i tests.

- [ ] **Step 1: Create the source helper**

`tests/testthat/helper-source.R`:
```r
# Sources all pipeline modules so tests see their functions.
# testthat sets wd to tests/testthat during test_dir(); repo root = ../..
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  qa <- file.path(root, "R", "tng-qa")
  files <- list.files(qa, pattern = "\\.R$", full.names = TRUE)
  for (f in files) source(f)
})
```

- [ ] **Step 2: Create the runner**

`run-tests.R`:
```r
#!/usr/bin/env Rscript
testthat::test_dir("tests/testthat", stop_on_failure = TRUE)
```

- [ ] **Step 3: Placeholder so the dir exists**

```bash
mkdir -p R/tng-qa tests/testthat && touch R/tng-qa/.gitkeep
```

- [ ] **Step 4: Add a trivial smoke test and run it**

`tests/testthat/test-smoke.R`:
```r
test_that("harness runs", { expect_true(TRUE) })
```
Run: `Rscript run-tests.R`
Expected: PASS (1 test). (Smoke-testen slettes i Task 2.)

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helper-source.R run-tests.R R/tng-qa/.gitkeep tests/testthat/test-smoke.R
git commit -m "test(tng-qa): testthat-harness + modul-sourcing"
```

---

### Task 2: MySQL-literal fixer

Konverterer mysqldump-escaping til DuckDB-kompatibel SQL, så DuckDB's parser kan splitte tuples korrekt.

**Files:**
- Create: `R/tng-qa/01-extract-tng.R`
- Test: `tests/testthat/test-extract.R`
- Delete: `tests/testthat/test-smoke.R`

**Interfaces:**
- Produces: `fix_mysql_literals(s: character) -> character` — på en INSERT-linje: `\\`→`\`, `\'`→`''`, `\"`→`"`, backticks→double-quotes; bevarer strenge-indhold ellers.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-extract.R`:
```r
test_that("fix_mysql_literals converts escaping to DuckDB form", {
  expect_equal(fix_mysql_literals("INSERT INTO `t` VALUES (1,'O\\'Brien')"),
               'INSERT INTO "t" VALUES (1,\'O\'\'Brien\')')
  expect_equal(fix_mysql_literals("(1,'a\\\\b')"), "(1,'a\\b')")  # \\ -> \
  expect_equal(fix_mysql_literals("(1,'s3\\\"x')"), "(1,'s3\"x')") # \" -> "
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function fix_mysql_literals").

- [ ] **Step 3: Write minimal implementation**

`R/tng-qa/01-extract-tng.R`:
```r
# Trin 1: TNG-dump (MySQL) -> lokal DuckDB. Kun funktions-definitioner.

# Konverter mysqldump-escaping til DuckDB-kompatibel SQL.
fix_mysql_literals <- function(s) {
  SENT <- "\001BSLASH\001"                            # sentinel, optræder ikke i dumps
  s <- gsub("\\\\\\\\", SENT, s, perl = TRUE)         # \\  -> sentinel
  s <- gsub("\\\\'", "''", s, perl = TRUE)          # \'  -> ''
  s <- gsub('\\\\"', '"', s, perl = TRUE)           # \"  -> "
  s <- gsub(SENT, "\\", s, fixed = TRUE)                # sentinel -> single backslash
  s <- gsub("`", '"', s, fixed = TRUE)              # backtick-identifiers -> double quotes
  s
}
```

- [ ] **Step 4: Run test + remove smoke test**

```bash
rm tests/testthat/test-smoke.R
Rscript run-tests.R
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add R/tng-qa/01-extract-tng.R tests/testthat/test-extract.R
git rm tests/testthat/test-smoke.R
git commit -m "feat(tng-qa): mysqldump-literal-fixer til DuckDB"
```

---

### Task 3: TNG extractor → DuckDB

**Files:**
- Modify: `R/tng-qa/01-extract-tng.R`
- Test: `tests/testthat/test-extract.R`
- Test fixture: `tests/testthat/fixtures/mini-tng.sql`

**Interfaces:**
- Consumes: `fix_mysql_literals()`.
- Produces:
  - `tng_create_columns(dump_path, table) -> character` (kolonnenavne i CREATE TABLE-rækkefølge).
  - `load_tng_table(con, dump_path, table) -> integer` (antal rækker; opretter VARCHAR-tabel + indsætter alle rækker).
  - `build_tng_duckdb(dump_path, db_path) -> character` (db_path; loader `tng_people`,`tng_families`,`tng_children`,`tng_associations`).

- [ ] **Step 1: Create the fixture**

`tests/testthat/fixtures/mini-tng.sql`:
```sql
CREATE TABLE `tng_people` (
  `personID` varchar(22) NOT NULL,
  `firstname` varchar(127) NOT NULL,
  `lastname` varchar(127) NOT NULL,
  `birthdatetr` date NOT NULL,
  `deathdatetr` date NOT NULL,
  `sex` varchar(25) NOT NULL,
  `living` tinyint NOT NULL,
  `private` tinyint NOT NULL
) ENGINE=InnoDB;
INSERT INTO `tng_people` VALUES ('I1','Conrad','Reventlow','1644-04-21','1708-07-21','M',0,0),('I2','O\'Hara','','1650-01-01','0000-00-00','F',0,0);
```

- [ ] **Step 2: Write the failing test**

Append to `tests/testthat/test-extract.R`:
```r
test_that("build_tng_duckdb loads people with columns and escaping", {
  dump <- testthat::test_path("fixtures", "mini-tng.sql")
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)
  build_tng_duckdb(dump, db, tables = "tng_people")
  con <- DBI::dbConnect(duckdb::duckdb(), db)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  ppl <- DBI::dbGetQuery(con, 'SELECT * FROM tng_people ORDER BY "personID"')
  expect_equal(nrow(ppl), 2L)
  expect_equal(ppl$firstname, c("Conrad", "O'Hara"))
  expect_equal(ppl$living, c("0", "0"))
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function build_tng_duckdb").

- [ ] **Step 4: Implement**

Append to `R/tng-qa/01-extract-tng.R`:
```r
tng_create_columns <- function(dump_path, table) {
  lines <- readLines(dump_path, warn = FALSE)
  start <- grep(sprintf("^CREATE TABLE `%s`", table), lines)
  if (!length(start)) stop(sprintf("CREATE TABLE `%s` ikke fundet", table))
  end <- grep("^\\)", lines)
  end <- end[end > start[1]][1]
  body <- lines[(start[1] + 1):(end - 1)]
  col_lines <- grep("^\\s+`", body, value = TRUE)
  sub("^\\s+`([^`]+)`.*$", "\\1", col_lines)
}

load_tng_table <- function(con, dump_path, table) {
  cols <- tng_create_columns(dump_path, table)
  DBI::dbExecute(con, sprintf('DROP TABLE IF EXISTS "%s"', table))
  coldef <- paste(sprintf('"%s" VARCHAR', cols), collapse = ", ")
  DBI::dbExecute(con, sprintf('CREATE TABLE "%s" (%s)', table, coldef))
  lines <- readLines(dump_path, warn = FALSE)
  ins <- grep(sprintf("^INSERT INTO `%s` VALUES", table), lines, value = TRUE)
  n <- 0L
  for (stmt in ins) {
    fixed <- fix_mysql_literals(stmt)
    DBI::dbExecute(con, fixed)
  }
  DBI::dbGetQuery(con, sprintf('SELECT COUNT(*) AS n FROM "%s"', table))$n
}

build_tng_duckdb <- function(dump_path, db_path,
                             tables = c("tng_people", "tng_families",
                                        "tng_children", "tng_associations")) {
  if (file.exists(db_path)) unlink(db_path)
  con <- DBI::dbConnect(duckdb::duckdb(), db_path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  for (t in tables) {
    n <- load_tng_table(con, dump_path, t)
    message(sprintf("TNG %s: %d rækker", t, n))
  }
  db_path
}
```

- [ ] **Step 5: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/01-extract-tng.R tests/testthat/test-extract.R tests/testthat/fixtures/mini-tng.sql
git commit -m "feat(tng-qa): TNG-dump -> DuckDB extractor"
```

---

### Task 4: Navne-normalisering

**Files:**
- Create: `R/tng-qa/03-normalize.R`
- Test: `tests/testthat/test-normalize.R`

**Interfaces:**
- Produces:
  - `strip_titles(s) -> character` (fjerner greve/lensgreve/grevinde/til/von/af-prædikater).
  - `normalize_sex(x) -> character` ("mand"/"kvinde"/"ukendt").
  - `normalize_name(first, last, married_in = FALSE) -> list(given, surname, key, implicit_surname)`. `key` = lowercased "given surname" m. bevaret diakritik; implicit "reventlow" KUN når `last` tom OG `married_in` FALSE; `implicit_surname=TRUE` flager det.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-normalize.R`:
```r
test_that("normalize_sex maps both vocabularies", {
  expect_equal(normalize_sex("M"), "mand")
  expect_equal(normalize_sex("kvinde"), "kvinde")
  expect_equal(normalize_sex(""), "ukendt")
})

test_that("strip_titles removes nobility predicates, keeps diacritics", {
  expect_equal(strip_titles("Greve Conrad"), "Conrad")
  expect_equal(strip_titles("Sofie Amalie"), "Sofie Amalie")
})

test_that("normalize_name inserts implicit Reventlow only when not married-in", {
  a <- normalize_name("Conrad", "")
  expect_equal(a$surname, "reventlow"); expect_true(a$implicit_surname)
  b <- normalize_name("Anna", "", married_in = TRUE)
  expect_equal(b$surname, ""); expect_false(b$implicit_surname)
  c <- normalize_name("Conrad", "Reventlow")
  expect_equal(c$key, "conrad reventlow"); expect_false(c$implicit_surname)
})

test_that("normalize_name preserves Danish diacritics in key", {
  expect_equal(normalize_name("Sofie Æbeltoft", "Brønshøj")$key, "sofie æbeltoft brønshøj")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function normalize_name").

- [ ] **Step 3: Implement**

`R/tng-qa/03-normalize.R`:
```r
# Trin 3: normalisering. Rene funktioner. Diakritik bevares ALTID.

.lower <- function(s) stringi::stri_trans_tolower(s, locale = "da_DK")

strip_titles <- function(s) {
  if (is.na(s)) return(s)
  pat <- "\\b(lensgreve|lensgrevinde|greve|grevinde|baron|baronesse|friherre|til|von|af)\\b"
  out <- gsub(pat, "", s, ignore.case = TRUE, perl = TRUE)
  trimws(gsub("\\s+", " ", out))
}

normalize_sex <- function(x) {
  x <- .lower(trimws(ifelse(is.na(x), "", x)))
  if (x %in% c("m", "mand", "male")) "mand"
  else if (x %in% c("f", "k", "kvinde", "female")) "kvinde"
  else "ukendt"
}

normalize_name <- function(first, last, married_in = FALSE) {
  first <- ifelse(is.na(first), "", first)
  last  <- ifelse(is.na(last), "", last)
  given <- trimws(strip_titles(first))
  surname_raw <- trimws(strip_titles(last))
  implicit <- FALSE
  if (surname_raw == "" && !married_in) { surname_raw <- "Reventlow"; implicit <- TRUE }
  key <- trimws(gsub("\\s+", " ", paste(.lower(given), .lower(surname_raw))))
  list(given = given, surname = .lower(surname_raw), key = key, implicit_surname = implicit)
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/03-normalize.R tests/testthat/test-normalize.R
git commit -m "feat(tng-qa): navne/køn-normalisering m. diakritik-bevarelse"
```

---

### Task 5: Dato-normalisering

**Files:**
- Modify: `R/tng-qa/03-normalize.R`
- Test: `tests/testthat/test-normalize.R`

**Interfaces:**
- Produces:
  - `parse_year_interval(text) -> c(min_year, max_year)` (integer; NA hvis uparsbar; håndterer "ca."/"før"/"efter"/"1644" og intervaller "1644-1650").
  - `tng_date_to_interval(d) -> c(min_year, max_year)` (fra "YYYY-MM-DD"; "0000-00-00"→NA).
  - `intervals_overlap(a, b) -> logical` (NA-tolerant: NA i en ende = ingen konflikt = TRUE).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-normalize.R`:
```r
test_that("parse_year_interval handles qualifiers and ranges", {
  expect_equal(parse_year_interval("1644"), c(1644L, 1644L))
  expect_equal(parse_year_interval("ca. 1650"), c(1645L, 1655L))
  expect_equal(parse_year_interval("før 1261"), c(NA_integer_, 1261L))
  expect_equal(parse_year_interval("1644-1650"), c(1644L, 1650L))
  expect_equal(parse_year_interval("ukendt"), c(NA_integer_, NA_integer_))
})

test_that("tng_date_to_interval parses and rejects zero-date", {
  expect_equal(tng_date_to_interval("1708-07-21"), c(1708L, 1708L))
  expect_equal(tng_date_to_interval("0000-00-00"), c(NA_integer_, NA_integer_))
})

test_that("intervals_overlap is NA-tolerant", {
  expect_true(intervals_overlap(c(1644L,1644L), c(1640L,1650L)))
  expect_false(intervals_overlap(c(1644L,1644L), c(1700L,1710L)))
  expect_true(intervals_overlap(c(NA,NA), c(1700L,1710L)))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function parse_year_interval").

- [ ] **Step 3: Implement**

Append to `R/tng-qa/03-normalize.R`:
```r
parse_year_interval <- function(text) {
  if (is.na(text) || !nzchar(trimws(text))) return(c(NA_integer_, NA_integer_))
  t <- .lower(text)
  yrs <- as.integer(regmatches(t, gregexpr("\\d{3,4}", t))[[1]])
  if (!length(yrs)) return(c(NA_integer_, NA_integer_))
  if (grepl("\\d{3,4}\\s*[-–]\\s*\\d{3,4}", t) && length(yrs) >= 2)
    return(c(min(yrs), max(yrs)))
  if (grepl("\\b(ca\\.?|omkring|c\\.)\\b", t)) return(c(yrs[1] - 5L, yrs[1] + 5L))
  if (grepl("\\b(før|inden)\\b", t)) return(c(NA_integer_, yrs[1]))
  if (grepl("\\b(efter)\\b", t)) return(c(yrs[1], NA_integer_))
  c(yrs[1], yrs[1])
}

tng_date_to_interval <- function(d) {
  if (is.na(d) || !grepl("^\\d{4}-\\d{2}-\\d{2}$", d) || startsWith(d, "0000"))
    return(c(NA_integer_, NA_integer_))
  y <- as.integer(substr(d, 1, 4))
  c(y, y)
}

intervals_overlap <- function(a, b) {
  amin <- if (is.na(a[1])) -Inf else a[1]; amax <- if (is.na(a[2]))  Inf else a[2]
  bmin <- if (is.na(b[1])) -Inf else b[1]; bmax <- if (is.na(b[2]))  Inf else b[2]
  amin <= bmax && bmin <= amax
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/03-normalize.R tests/testthat/test-normalize.R
git commit -m "feat(tng-qa): dato-interval-normalisering (fuzzy, NA-tolerant)"
```

---

### Task 6: Read-only Supabase-pull

**Files:**
- Create: `R/tng-qa/02-pull-ours.R`
- Test: `tests/testthat/test-pull.R`

**Interfaces:**
- Produces:
  - `connect_readonly() -> DBIConnection` (creds fra env; sætter `SET default_transaction_read_only = on`; fail fast hvis env mangler).
  - `assert_readonly(con)` (stop hvis en test-write lykkes).
  - `pull_ours(con) -> list(person, external_id, family, family_member, dates)` (`dates` fra `conclusion.valgt_assertion_id` join `assertion`/`fact` for faktatype ∈ fødsel/død).

- [ ] **Step 1: Write the failing test (guard-logik, ingen live-DB)**

`tests/testthat/test-pull.R`:
```r
test_that("connect_readonly fails fast without creds", {
  withr::with_envvar(c(SUPABASE_HOST = "", SUPABASE_USER = "", SUPABASE_PASSWORD = ""), {
    expect_error(connect_readonly(), "SUPABASE_")
  })
})

test_that("ours_birth_death_sql selects via conclusion.valgt_assertion_id", {
  sql <- ours_birth_death_sql()
  expect_match(sql, "valgt_assertion_id")
  expect_match(sql, "fødsel|foedsel")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function connect_readonly").
(Hvis `withr` mangler: `Rscript -e 'install.packages("withr")'`.)

- [ ] **Step 3: Implement**

`R/tng-qa/02-pull-ours.R`:
```r
# Trin 2: read-only pull fra Supabase. Kun funktions-definitioner.

connect_readonly <- function() {
  host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER")
  pw   <- Sys.getenv("SUPABASE_PASSWORD")
  if (host == "" || user == "" || pw == "")
    stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron (read-only rolle anbefales).")
  con <- DBI::dbConnect(RPostgres::Postgres(), host = host, user = user, password = pw,
                        dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                        port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                        sslmode = "require")
  DBI::dbExecute(con, "SET default_transaction_read_only = on")
  con
}

assert_readonly <- function(con) {
  ok <- tryCatch({
    DBI::dbExecute(con, "CREATE TEMP TABLE _ro_probe(x int)"); FALSE
  }, error = function(e) TRUE)
  if (!ok) stop("Forbindelsen er IKKE read-only — afbryd (least-privilege krav).")
  invisible(TRUE)
}

ours_birth_death_sql <- function() {
  paste(
    "SELECT f.subjekt_id AS person_id, f.faktatype,",
    "       a.date_min, a.date_max, a.date_raw",
    "FROM fact f",
    "JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id",
    "JOIN assertion  a ON a.id=c.valgt_assertion_id",
    "WHERE f.subjekt_type='person' AND f.faktatype IN ('fødsel','død')"
  )
}

pull_ours <- function(con) {
  q <- function(s) DBI::dbGetQuery(con, s)
  list(
    person        = q("SELECT id, koen, visning_navn, visning_foedt, visning_doed, levende, privat FROM person"),
    external_id   = q("SELECT person_id, source_id, linje, nr FROM person_external_id"),
    family        = q("SELECT id, type FROM family"),
    family_member = q("SELECT family_id, person_id, rolle, ordinal, konfidens FROM family_member"),
    dates         = q(ours_birth_death_sql())
  )
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/02-pull-ours.R tests/testthat/test-pull.R
git commit -m "feat(tng-qa): read-only Supabase-pull + read-only-guard"
```

---

### Task 7: Matching — blokering, score, injektive tiers + eval

**Files:**
- Create: `R/tng-qa/04-match.R`
- Test: `tests/testthat/test-match.R`

**Interfaces:**
- Consumes: normaliserings-funktioner.
- Produces:
  - `name_similarity(key_a, key_b) -> numeric` (Jaro-Winkler 0..1).
  - `score_pair(name_sim, birth_overlap, death_overlap, sex_eq, cfg) -> numeric` (0..1).
  - `default_cfg() -> list` (year_window, vægte, cutoffs, ambiguity_margin).
  - `assign_tiers(scored, cfg) -> data.frame(person_id, tng_id, score, tier)` — injektiv (1:1) + entydigheds-gate; `tier ∈ auto/review/none`.
  - `eval_precision_recall(crosswalk, truth) -> list(precision, recall)`.
- `scored` = `data.frame(person_id, tng_id, name_sim, birth_overlap, death_overlap, sex_eq, unique_block)`.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-match.R`:
```r
test_that("name_similarity rewards near-identical keys", {
  expect_gt(name_similarity("conrad reventlow", "conradt reventlow"), 0.9)
  expect_lt(name_similarity("conrad reventlow", "ditlev brockdorff"), 0.6)
})

test_that("assign_tiers enforces injective 1:1 and ambiguity->review", {
  cfg <- default_cfg()
  scored <- data.frame(
    person_id = c(1L, 1L, 2L),
    tng_id    = c("I9", "I8", "I9"),
    name_sim  = c(0.99, 0.40, 0.97),
    birth_overlap = c(TRUE, FALSE, TRUE),
    death_overlap = c(TRUE, FALSE, TRUE),
    sex_eq    = c(TRUE, TRUE, TRUE),
    unique_block = c(TRUE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  out <- assign_tiers(scored, cfg)
  # person 1 keeps I9 (auto); person 2 also wants I9 -> conflict -> review/none, never duplicate auto
  i9 <- out[out$tng_id == "I9" & out$tier == "auto", ]
  expect_equal(nrow(i9), 1L)
  expect_equal(i9$person_id, 1L)
  # person 2 lost the unique I9 -> not auto
  expect_false(any(out$person_id == 2L & out$tier == "auto"))
})

test_that("eval_precision_recall computes against truth", {
  cw <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","IX"), stringsAsFactors = FALSE)
  truth <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"), stringsAsFactors = FALSE)
  pr <- eval_precision_recall(cw, truth)
  expect_equal(pr$precision, 2/3)
  expect_equal(pr$recall, 2/3)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function name_similarity").

- [ ] **Step 3: Implement**

`R/tng-qa/04-match.R`:
```r
# Trin 4: blokering + score + injektive tiers. Matching ALDRIG på relationer.

default_cfg <- function() list(
  year_window = 5L, w_name = 0.6, w_birth = 0.2, w_death = 0.1, w_sex = 0.1,
  auto_cutoff = 0.90, review_cutoff = 0.70, ambiguity_margin = 0.05
)

name_similarity <- function(key_a, key_b) {
  1 - stringdist::stringdist(key_a, key_b, method = "jw", p = 0.1)
}

score_pair <- function(name_sim, birth_overlap, death_overlap, sex_eq, cfg) {
  cfg$w_name * name_sim +
    cfg$w_birth * as.numeric(birth_overlap) +
    cfg$w_death * as.numeric(death_overlap) +
    cfg$w_sex   * as.numeric(sex_eq)
}

assign_tiers <- function(scored, cfg) {
  scored$score <- mapply(score_pair, scored$name_sim, scored$birth_overlap,
                         scored$death_overlap, scored$sex_eq,
                         MoreArgs = list(cfg = cfg))
  scored <- scored[order(-scored$score), ]
  used_tng <- character(0); assigned_person <- integer(0)
  scored$tier <- "none"
  for (i in seq_len(nrow(scored))) {
    pid <- scored$person_id[i]; tid <- scored$tng_id[i]; sc <- scored$score[i]
    if (pid %in% assigned_person || tid %in% used_tng) { scored$tier[i] <- "none"; next }
    if (sc >= cfg$auto_cutoff && isTRUE(scored$unique_block[i])) {
      scored$tier[i] <- "auto"; used_tng <- c(used_tng, tid); assigned_person <- c(assigned_person, pid)
    } else if (sc >= cfg$review_cutoff) {
      scored$tier[i] <- "review"
    }
  }
  scored[, c("person_id", "tng_id", "score", "tier")]
}

eval_precision_recall <- function(crosswalk, truth) {
  m <- merge(crosswalk, truth, by = "person_id", suffixes = c("_cw", "_truth"))
  correct <- sum(m$tng_id_cw == m$tng_id_truth)
  list(precision = correct / nrow(crosswalk), recall = correct / nrow(truth))
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/04-match.R tests/testthat/test-match.R
git commit -m "feat(tng-qa): injektiv matching m. tiers + precision/recall-eval"
```

---

### Task 8: Review-merge (idempotent)

**Files:**
- Create: `R/tng-qa/05-review.R`
- Test: `tests/testthat/test-review.R`

**Interfaces:**
- Produces: `merge_review_decisions(crosswalk, decisions) -> data.frame` — `decisions` har kolonner `person_id, tng_id, afgoerelse ∈ {bekræft, afvis, ny-id}, ny_tng_id`. Bekræftede review→accepted; afviste fjernes + huskes (`tier='afvist'`); `ny-id` sætter `tng_id<-ny_tng_id, tier='accepted'`. Idempotent: gentaget kald = samme output.

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-review.R`:
```r
test_that("merge_review_decisions applies confirm/reject/new-id idempotently", {
  cw <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"),
                   score = c(0.8,0.75,0.72), tier = c("review","review","review"),
                   stringsAsFactors = FALSE)
  dec <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"),
                    afgoerelse = c("bekræft","afvis","ny-id"), ny_tng_id = c(NA,NA,"I99"),
                    stringsAsFactors = FALSE)
  out1 <- merge_review_decisions(cw, dec)
  expect_equal(out1$tier[out1$person_id==1L], "accepted")
  expect_equal(out1$tier[out1$person_id==2L], "afvist")
  expect_equal(out1$tng_id[out1$person_id==3L], "I99")
  expect_equal(out1$tier[out1$person_id==3L], "accepted")
  out2 <- merge_review_decisions(out1, dec)  # idempotent
  expect_equal(out1[order(out1$person_id),], out2[order(out2$person_id),])
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function merge_review_decisions").

- [ ] **Step 3: Implement**

`R/tng-qa/05-review.R`:
```r
# Trin 5: flet manuelle review-afgørelser ind. Idempotent.

merge_review_decisions <- function(crosswalk, decisions) {
  cw <- crosswalk
  for (i in seq_len(nrow(decisions))) {
    pid <- decisions$person_id[i]; a <- decisions$afgoerelse[i]
    row <- which(cw$person_id == pid)
    if (!length(row)) next
    if (a == "bekræft") cw$tier[row] <- "accepted"
    else if (a == "afvis") cw$tier[row] <- "afvist"
    else if (a == "ny-id") { cw$tng_id[row] <- decisions$ny_tng_id[i]; cw$tier[row] <- "accepted" }
  }
  cw
}

accepted_crosswalk <- function(crosswalk) {
  crosswalk[crosswalk$tier %in% c("auto", "accepted"), c("person_id", "tng_id")]
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/05-review.R tests/testthat/test-review.R
git commit -m "feat(tng-qa): idempotent review-merge"
```

---

### Task 9: Relations-sammenligning + scope-guard

**Files:**
- Create: `R/tng-qa/06-compare.R`
- Test: `tests/testthat/test-compare.R`

**Interfaces:**
- Consumes: `accepted_crosswalk()`, `intervals_overlap()`.
- Produces:
  - `our_spouse_pairs(family, family_member) -> data.frame(person_id, spouse_id)` (partner↔partner i samme family).
  - `compare_marriages(our_pairs, tng_families, xwalk) -> data.frame(person_id, tng_id, kategori, detalje)` — kategori ∈ {mangler_hos_os, ekstra_hos_os, enig, uden_for_scope}.
  - `compare_parent_child(our_pc, tng_children, xwalk) -> data.frame(...)` — per-forælder (frel/mrel) + scope-guard.
  - `compare_dates_sex(our_attr, tng_people, xwalk) -> data.frame(...)`.
- `xwalk` = `data.frame(person_id, tng_id)` (kun accepteret).

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-compare.R`:
```r
test_that("compare_marriages flags missing/extra only when both endpoints matched", {
  xwalk <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"), stringsAsFactors = FALSE)
  our_pairs <- data.frame(person_id = c(1L), spouse_id = c(2L))      # we say 1—2
  tng_families <- data.frame(husband = c("I1"), wife = c("I9"), marrdatetr = c("1670-01-01"),
                             stringsAsFactors = FALSE)               # TNG says I1—I9 (I9 out of scope)
  out <- compare_marriages(our_pairs, tng_families, xwalk)
  # our 1—2 has no TNG support -> ekstra_hos_os; TNG I1—I9 endpoint out of scope -> uden_for_scope
  expect_true("ekstra_hos_os" %in% out$kategori)
  expect_true("uden_for_scope" %in% out$kategori)
  expect_false("mangler_hos_os" %in% out$kategori)  # never claim missing when endpoint unmatched
})

test_that("compare_marriages reports agreement", {
  xwalk <- data.frame(person_id = c(1L,2L), tng_id = c("I1","I2"), stringsAsFactors = FALSE)
  our_pairs <- data.frame(person_id = 1L, spouse_id = 2L)
  tng_families <- data.frame(husband = "I1", wife = "I2", marrdatetr = "1670-01-01", stringsAsFactors = FALSE)
  out <- compare_marriages(our_pairs, tng_families, xwalk)
  expect_true("enig" %in% out$kategori)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function compare_marriages").

- [ ] **Step 3: Implement**

`R/tng-qa/06-compare.R`:
```r
# Trin 6: relations-sammenligning. Kant sammenlignes KUN når begge endepunkter matchet.

our_spouse_pairs <- function(family, family_member) {
  partners <- family_member[family_member$rolle == "partner", ]
  out <- data.frame(person_id = integer(0), spouse_id = integer(0))
  for (fid in unique(partners$family_id)) {
    ps <- partners$person_id[partners$family_id == fid]
    if (length(ps) >= 2)
      for (a in ps) for (b in ps) if (a != b)
        out <- rbind(out, data.frame(person_id = a, spouse_id = b))
  }
  unique(out)
}

compare_marriages <- function(our_pairs, tng_families, xwalk) {
  to_tng <- function(pid) xwalk$tng_id[match(pid, xwalk$person_id)]
  rows <- list()
  # our edges -> is there a TNG family with the matched pair?
  tng_set <- rbind(
    data.frame(a = tng_families$husband, b = tng_families$wife, stringsAsFactors = FALSE),
    data.frame(a = tng_families$wife, b = tng_families$husband, stringsAsFactors = FALSE)
  )
  for (i in seq_len(nrow(our_pairs))) {
    pid <- our_pairs$person_id[i]; sid <- our_pairs$spouse_id[i]
    t_p <- to_tng(pid); t_s <- to_tng(sid)
    if (is.na(t_p) || is.na(t_s)) {
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = NA_character_,
        kategori = "uden_for_scope", detalje = "ægtefælle ikke matchet")
      next
    }
    hit <- any(tng_set$a == t_p & tng_set$b == t_s)
    rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = t_p,
      kategori = if (hit) "enig" else "ekstra_hos_os",
      detalje = sprintf("vores: %d—%d", pid, sid))
  }
  # TNG edges where our matched person has a spouse in TNG we lack
  our_set <- rbind(
    data.frame(a = our_pairs$person_id, b = our_pairs$spouse_id),
    data.frame(a = our_pairs$spouse_id, b = our_pairs$person_id)
  )
  for (i in seq_len(nrow(tng_families))) {
    h <- tng_families$husband[i]; w <- tng_families$wife[i]
    p_h <- xwalk$person_id[match(h, xwalk$tng_id)]
    p_w <- xwalk$person_id[match(w, xwalk$tng_id)]
    if (is.na(p_h) || is.na(p_w)) {
      known <- if (!is.na(p_h)) p_h else if (!is.na(p_w)) p_w else NA_integer_
      if (!is.na(known))
        rows[[length(rows)+1]] <- data.frame(person_id = known, tng_id = if (!is.na(p_h)) h else w,
          kategori = "uden_for_scope", detalje = "TNG-ægtefælle uden for vores scope")
      next
    }
    has <- any(our_set$a == p_h & our_set$b == p_w)
    if (!has)
      rows[[length(rows)+1]] <- data.frame(person_id = p_h, tng_id = h,
        kategori = "mangler_hos_os", detalje = sprintf("TNG: %s—%s", h, w))
  }
  do.call(rbind, rows)
}

compare_parent_child <- function(our_pc, tng_children, xwalk) {
  # our_pc: data.frame(child_id, parent_id, rolle); tng_children: data.frame(child_tng, father_tng, mother_tng, frel, mrel)
  to_tng <- function(pid) xwalk$tng_id[match(pid, xwalk$person_id)]
  rows <- list()
  for (i in seq_len(nrow(our_pc))) {
    c_t <- to_tng(our_pc$child_id[i]); p_t <- to_tng(our_pc$parent_id[i])
    if (is.na(c_t) || is.na(p_t)) {
      rows[[length(rows)+1]] <- data.frame(child_id = our_pc$child_id[i], tng_id = NA_character_,
        kategori = "uden_for_scope", detalje = "barn/forælder ikke matchet"); next }
    tc <- tng_children[tng_children$child_tng == c_t, ]
    hit <- nrow(tc) && (p_t %in% c(tc$father_tng, tc$mother_tng))
    rows[[length(rows)+1]] <- data.frame(child_id = our_pc$child_id[i], tng_id = c_t,
      kategori = if (hit) "enig" else "ekstra_hos_os",
      detalje = sprintf("vores forælder %d (%s)", our_pc$parent_id[i], our_pc$rolle[i]))
  }
  do.call(rbind, rows)
}

compare_dates_sex <- function(our_attr, tng_people, xwalk) {
  # our_attr: data.frame(person_id, birth_min,birth_max,death_min,death_max, koen)
  rows <- list()
  for (i in seq_len(nrow(our_attr))) {
    pid <- our_attr$person_id[i]; tid <- xwalk$tng_id[match(pid, xwalk$person_id)]
    if (is.na(tid)) next
    tp <- tng_people[tng_people$personID == tid, ]
    if (!nrow(tp)) next
    tb <- tng_date_to_interval(tp$birthdatetr[1]); td <- tng_date_to_interval(tp$deathdatetr[1])
    if (!intervals_overlap(c(our_attr$birth_min[i], our_attr$birth_max[i]), tb))
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = tid, kategori = "dato_uenig",
        detalje = sprintf("fødsel: vores [%s,%s] vs TNG %s", our_attr$birth_min[i], our_attr$birth_max[i], tp$birthdatetr[1]))
    if (!intervals_overlap(c(our_attr$death_min[i], our_attr$death_max[i]), td))
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = tid, kategori = "dato_uenig",
        detalje = sprintf("død: vores [%s,%s] vs TNG %s", our_attr$death_min[i], our_attr$death_max[i], tp$deathdatetr[1]))
    if (normalize_sex(our_attr$koen[i]) != normalize_sex(tp$sex[1]) &&
        normalize_sex(tp$sex[1]) != "ukendt" && normalize_sex(our_attr$koen[i]) != "ukendt")
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = tid, kategori = "køn_uenig",
        detalje = sprintf("vores %s vs TNG %s", our_attr$koen[i], tp$sex[1]))
  }
  if (length(rows)) do.call(rbind, rows) else
    data.frame(person_id = integer(0), tng_id = character(0), kategori = character(0), detalje = character(0))
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/06-compare.R tests/testthat/test-compare.R
git commit -m "feat(tng-qa): relations-sammenligning m. scope-guard + per-forælder"
```

---

### Task 10: PII-gate + rapport-render

**Files:**
- Create: `R/tng-qa/07-report.R`
- Test: `tests/testthat/test-report.R`

**Interfaces:**
- Consumes: sammenlignings-output.
- Produces:
  - `filter_living(discrepancies, living_person_ids) -> data.frame` (fjerner rækker hvor person_id er levende/privat).
  - `assert_no_living_pii(report_text, living_person_ids) -> invisible(TRUE)` (stop hvis et levende person_id optræder i rapport-teksten).
  - `render_report(discrepancies, ext_id, living_person_ids, date) -> character` (markdown; labels = DAA linje/nr; kalder PII-gate før retur).

- [ ] **Step 1: Write the failing test**

`tests/testthat/test-report.R`:
```r
test_that("filter_living drops living persons", {
  d <- data.frame(person_id = c(1L,2L), kategori = c("x","y"), detalje = c("a","b"), stringsAsFactors = FALSE)
  expect_equal(nrow(filter_living(d, living_person_ids = 2L)), 1L)
})

test_that("assert_no_living_pii blocks a living id in text", {
  expect_error(assert_no_living_pii("se person 2 her", living_person_ids = 2L), "PII")
  expect_invisible(assert_no_living_pii("ingen følsomme", living_person_ids = 2L))
})

test_that("render_report produces markdown and passes gate for dead-only", {
  d <- data.frame(person_id = 1L, tng_id = "I1", kategori = "dato_uenig", detalje = "fødsel", stringsAsFactors = FALSE)
  ext <- data.frame(person_id = 1L, linje = "I", nr = 5L, stringsAsFactors = FALSE)
  md <- render_report(d, ext, living_person_ids = integer(0), date = "2026-06-29")
  expect_match(md, "TNG-QA")
  expect_match(md, "I-5")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Rscript run-tests.R`
Expected: FAIL ("could not find function filter_living").

- [ ] **Step 3: Implement**

`R/tng-qa/07-report.R`:
```r
# PII-gate + markdown-render. Committed rapport må aldrig indeholde levende-PII.

filter_living <- function(discrepancies, living_person_ids) {
  discrepancies[!(discrepancies$person_id %in% living_person_ids), , drop = FALSE]
}

assert_no_living_pii <- function(report_text, living_person_ids) {
  for (id in living_person_ids) {
    if (grepl(sprintf("\\b%d\\b", id), report_text))
      stop(sprintf("PII-gate: levende person_id %d optræder i rapporten — commit afvist.", id))
  }
  invisible(TRUE)
}

.label <- function(pid, ext_id) {
  r <- ext_id[ext_id$person_id == pid, ]
  if (nrow(r)) sprintf("%s-%s", r$linje[1], r$nr[1]) else sprintf("p%d", pid)
}

render_report <- function(discrepancies, ext_id, living_person_ids, date) {
  d <- filter_living(discrepancies, living_person_ids)
  lines <- c(sprintf("# TNG-QA-rapport %s", date),
             "",
             "> TNG = sammenlignings-reference, ikke facit. Uenighed = uafklaret til afgørelse.",
             "")
  for (kat in unique(d$kategori)) {
    lines <- c(lines, sprintf("## %s", kat), "")
    sub <- d[d$kategori == kat, ]
    for (i in seq_len(nrow(sub)))
      lines <- c(lines, sprintf("- **%s** (%s): %s",
                                .label(sub$person_id[i], ext_id), sub$tng_id[i], sub$detalje[i]))
    lines <- c(lines, "")
  }
  txt <- paste(lines, collapse = "\n")
  assert_no_living_pii(txt, living_person_ids)
  txt
}
```

- [ ] **Step 4: Run test + commit**

```bash
Rscript run-tests.R   # Expected: PASS
git add R/tng-qa/07-report.R tests/testthat/test-report.R
git commit -m "feat(tng-qa): PII-gate + markdown-rapport-render"
```

---

### Task 11: Orkestrator + brugsanvisning

**Files:**
- Create: `R/tng-qa/run-pipeline.R`
- Create: `docs/tng-qa-koersel.md`

**Interfaces:**
- Consumes: alle modul-funktioner.
- Produces: kørbart script der bygger DuckDB, puller vores data, normaliserer, matcher, fletter review, sammenligner, og skriver crosswalk + review-kø + rapport. Ingen unit-test (I/O-orkestrering); verificeres ved manuel e2e mod lille udsnit.

- [ ] **Step 1: Write the orchestrator**

`R/tng-qa/run-pipeline.R`:
```r
#!/usr/bin/env Rscript
# Orkestrering. Kør fra repo-rod: Rscript R/tng-qa/run-pipeline.R
suppressPackageStartupMessages({ library(DBI) })
root <- normalizePath(".")
for (f in list.files(file.path(root, "R", "tng-qa"), pattern = "^[0-9].*\\.R$", full.names = TRUE)) source(f)

dump   <- "jr_tng_reventlow.sql"
db     <- "data/tng.duckdb"
cw_csv <- "data/tng-crosswalk.csv"
rq_csv <- "data/tng-review-queue.csv"
cfg    <- default_cfg()

message("== Trin 1: TNG -> DuckDB ==")
build_tng_duckdb(dump, db)
tcon <- dbConnect(duckdb::duckdb(), db); on.exit(dbDisconnect(tcon, shutdown = TRUE), add = TRUE)
tng_people   <- dbGetQuery(tcon, 'SELECT * FROM tng_people')
tng_families <- dbGetQuery(tcon, 'SELECT * FROM tng_families')
tng_children <- dbGetQuery(tcon, 'SELECT * FROM tng_children')

message("== Trin 2: Supabase (read-only) ==")
scon <- connect_readonly(); assert_readonly(scon); on.exit(dbDisconnect(scon), add = TRUE)
ours <- pull_ours(scon)

message("== Trin 3-4: normalisér + match ==")
# (byg `scored` fra ours + tng_people via normalize_* og block; se docs/tng-qa-koersel.md for blok-detaljer)
# crosswalk <- assign_tiers(scored, cfg)

message("== Trin 5: review-merge (hvis afgørelser findes) ==")
if (file.exists(rq_csv)) {
  dec <- read.csv(rq_csv, stringsAsFactors = FALSE)
  crosswalk <- merge_review_decisions(crosswalk, dec)
}
write.csv(crosswalk, cw_csv, row.names = FALSE)
write.csv(crosswalk[crosswalk$tier == "review", ], rq_csv, row.names = FALSE)

message("== Trin 6: sammenlign + rapport ==")
xwalk <- accepted_crosswalk(crosswalk)
# disc <- rbind(compare_marriages(...), compare_parent_child(...), compare_dates_sex(...))
# living <- ours$person$id[ours$person$levende | ours$person$privat]
# md <- render_report(disc, ours$external_id, living, format(Sys.Date()))
# writeLines(md, sprintf("docs/reviews/tng-qa-rapport-%s.md", format(Sys.Date())))
message("Færdig. Crosswalk: ", cw_csv)
```

- [ ] **Step 2: Write usage doc**

`docs/tng-qa-koersel.md` — dokumentér: env-vars (`SUPABASE_HOST/USER/PASSWORD`, helst SELECT-only rolle), `Rscript R/tng-qa/run-pipeline.R`, review-kø-workflow (udfyld `afgoerelse`, kør igen), og at crosswalk/duckdb/review-kø er git-ignored (GDPR). Noter at blokerings-/score-detaljerne i trin 3-4 kalibreres mod et håndlabelt facit-sæt.

- [ ] **Step 3: Manual end-to-end (lille udsnit)**

Kør pipelinen mod et udsnit; bekræft at `data/tng-crosswalk.csv` + review-kø dannes, og at en rapport renderes uden PII-gate-fejl. Dokumentér kørte/sprungne dele.

- [ ] **Step 4: Commit**

```bash
git add R/tng-qa/run-pipeline.R docs/tng-qa-koersel.md
git commit -m "feat(tng-qa): pipeline-orkestrator + brugsanvisning"
```

---

## Self-Review

**Spec-dækning:** extract (T2-3), pull read-only+least-priv (T6), normalisér navn/dato/køn (T4-5), implicit-Reventlow-hypotese (T4), injektiv tier-match + entydighed + eval (T7), review idempotent + proveniens (T8, proveniens dokumenteres i run-doc/crosswalk-kolonner), sammenligning alle 4 dimensioner + scope-guard + per-forælder (T9), PII-gate (T10), TNG=reference (rapport-header T10), orkestrering (T11). Alle spec-sektioner har en task.

**Kendt forenkling:** `run-pipeline.R` (T11) har de DB→`scored`-byggende linjer som kommentar-skitse, fordi blok-konstruktionen kalibreres empirisk (spec §trin 4 / risici) — de rene byggesten er fuldt testet i T4-7. Implementøren færdiggør blok-glue i T11-step 3 mod facit-sættet.

**Type-konsistens:** `crosswalk`-kolonner (`person_id, tng_id, score, tier`) ens i T7/T8/T11; `xwalk`(`person_id,tng_id`) fra `accepted_crosswalk()` brugt i T9. `tier`-værdier `auto/review/none/accepted/afvist` konsistente. `normalize_sex` genbrugt i T9.
