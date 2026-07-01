# TNG-QA Relationel Corroboration — Fase 1 Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Berig TNG-QA review-køen (`data/tng-review-queue.csv`) med et
transparent "familie-støtte"-signal, så en menneskelig reviewer hurtigere kan
afgøre usikre kandidat-par: "denne kandidats forælder/barn er allerede
sikkert matchet — stemmer det med TNG's egen familie-graf?"

**Architecture:** Nyt trin 4b i `R/tng-qa/run-pipeline.R`, mellem Trin 4
(fersk `crosswalk`) og Trin 5 (review-merge). To nye rene funktioner i
`R/tng-qa/04b-corroboration.R` (`family_corroboration()`,
`aggregate_familie_status()`), plus en additiv udvidelse af den
eksisterende `derive_our_pc()` i `06-compare.R`. Rører ikke
`04-match.R` (scoring/tier) eller `07-report.R`.

**Tech Stack:** R (base + `stringi`/`stringdist`/`DBI`/`duckdb`/`RPostgres`
allerede i brug), testthat.

## Global Constraints

- **Rører ALDRIG `score_pair()`/`assign_tiers()` i `04-match.R`.** Matching
  sker udelukkende på attributter — se den originale designbeslutning i
  `docs/superpowers/specs/2026-06-29-tng-qa-crosswalk-design.md`.
- **Fase 2 (Trin 6-relabeling, `enig_via_matching`) er UDEN FOR SCOPE for
  denne plan.** Den er blokeret af et separat, udestående fix i
  `merge_review_decisions()` (nøgling på `(person_id,tng_id)` +
  injektivitetstjek — M2 i `docs/tng-qa-koersel.md`). Ingen ændringer i
  denne plan må forudsætte at Fase 2 findes.
- **Ingen ny PII-eksponering ud over eksisterende git-ignorerede lokale
  filer.** `data/tng-corroboration.csv` skal tilføjes `.gitignore` — se
  Task 3.
- **Kun biologisk `rolle=="barn"`, aldrig `konfidens=="omstridt"`, som
  corroboration-kilde.** Se design-spec beslutning #3.
- **Følg eksisterende R-stil i `R/tng-qa/`:** rene funktioner, ingen
  side-effekter i beregningsfunktioner (kun `run-pipeline.R` gør fil-I/O),
  inline `rows[[length(rows)+1]] <- data.frame(...)`-idiom fra
  `06-compare.R` frem for closures/`<<-`.
- **Test-lokation:** `tests/testthat/`, kørt via `Rscript run-tests.R` fra
  repo-roden. IKKE `R/tng-qa/test-*.R` — den mappe scannes ikke af
  testrunneren.
- **Alle R-kommandoer køres fra repo-roden**
  (`/Users/johanreventlow/TypeScript/danmarksadelsaarbog`).

---

### Task 1: `derive_our_pc()` bærer `konfidens` videre (additiv)

**Files:**
- Modify: `R/tng-qa/06-compare.R:8-20`
- Test: `tests/testthat/test-compare.R` (tilføj nye `test_that`-blokke til
  eksisterende fil)

**Interfaces:**
- Consumes: `family_member`-data.frame med kolonner
  `family_id, person_id, rolle, konfidens` (allerede pull'et af
  `pull_ours()` i `02-pull-ours.R`).
- Produces: `derive_our_pc(family_member)` returnerer nu
  `data.frame(child_id, parent_id, rolle, konfidens)` — ÉN NY kolonne
  (`konfidens`) ud over de eksisterende tre. Eksisterende forbrugere
  (`compare_parent_child()`) læser kun `child_id`/`parent_id`/`rolle` og er
  upåvirkede af den ekstra kolonne.

- [ ] **Step 1: Skriv de fejlende tests**

Åbn `tests/testthat/test-compare.R` og tilføj til sidst i filen:

```r
test_that("derive_our_pc bærer konfidens videre fra barnets family_member-række", {
  fm <- data.frame(
    family_id = c(1L, 1L), person_id = c(10L, 20L),
    rolle = c("partner", "barn"), ordinal = c(NA, NA),
    konfidens = c(NA, "sandsynlig"), stringsAsFactors = FALSE)
  out <- derive_our_pc(fm)
  expect_equal(nrow(out), 1L)
  expect_equal(out$child_id, 20L)
  expect_equal(out$parent_id, 10L)
  expect_equal(out$konfidens, "sandsynlig")
})

test_that("derive_our_pc returnerer velformet tom data.frame med konfidens-kolonne", {
  fm <- data.frame(family_id = integer(0), person_id = integer(0),
                   rolle = character(0), ordinal = integer(0),
                   konfidens = character(0), stringsAsFactors = FALSE)
  out <- derive_our_pc(fm)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_true("konfidens" %in% names(out))
})

test_that("derive_our_pc håndterer flere børn i samme familie med forskellig konfidens", {
  fm <- data.frame(
    family_id = c(1L, 1L, 1L),
    person_id = c(10L, 20L, 21L),
    rolle = c("partner", "barn", "barn"),
    ordinal = c(NA, NA, NA),
    konfidens = c(NA, "sikker", "omstridt"), stringsAsFactors = FALSE)
  out <- derive_our_pc(fm)
  expect_equal(nrow(out), 2L)
  expect_equal(out$konfidens[out$child_id == 20L], "sikker")
  expect_equal(out$konfidens[out$child_id == 21L], "omstridt")
})
```

- [ ] **Step 2: Kør tests og bekræft at de fejler**

Run: `Rscript run-tests.R`
Expected: FAIL — enten "object 'konfidens' not found" eller
`expect_true("konfidens" %in% names(out))` fejler, fordi den nuværende
`derive_our_pc()` ikke returnerer en `konfidens`-kolonne.

- [ ] **Step 3: Implementér den minimale ændring**

I `R/tng-qa/06-compare.R`, erstat den eksisterende `derive_our_pc`
(linje 8-20):

```r
derive_our_pc <- function(family_member) {
  fm <- family_member
  parts <- lapply(unique(fm$family_id), function(fid) {
    kids    <- as.integer(fm$person_id[fm$family_id == fid & fm$rolle == "barn"])
    parents <- as.integer(fm$person_id[fm$family_id == fid & fm$rolle == "partner"])
    if (!length(kids) || !length(parents)) return(NULL)
    expand.grid(child_id = kids, parent_id = parents, KEEP.OUT.ATTRS = FALSE)
  })
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts))
    return(data.frame(child_id = integer(0), parent_id = integer(0), rolle = character(0)))
  out <- unique(do.call(rbind, parts))
  out$rolle <- "ukendt"
  out
}
```

med:

```r
derive_our_pc <- function(family_member) {
  fm <- family_member
  parts <- lapply(unique(fm$family_id), function(fid) {
    kid_rows <- fm[fm$family_id == fid & fm$rolle == "barn", ]
    parents  <- as.integer(fm$person_id[fm$family_id == fid & fm$rolle == "partner"])
    if (!nrow(kid_rows) || !length(parents)) return(NULL)
    do.call(rbind, lapply(seq_len(nrow(kid_rows)), function(k) {
      data.frame(child_id = as.integer(kid_rows$person_id[k]), parent_id = parents,
                 konfidens = kid_rows$konfidens[k], stringsAsFactors = FALSE)
    }))
  })
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts))
    return(data.frame(child_id = integer(0), parent_id = integer(0),
                       rolle = character(0), konfidens = character(0)))
  out <- unique(do.call(rbind, parts))
  out$rolle <- "ukendt"
  out
}
```

(Kommentaren over funktionen i filen — "Vores forælder-barn modelleres som
'barn' + 'partner' i samme family..." — forbliver uændret, den er stadig
korrekt.)

- [ ] **Step 4: Kør tests og bekræft at de består**

Run: `Rscript run-tests.R`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 103 ]` (100 eksisterende + 3 nye)

- [ ] **Step 5: Commit**

```bash
git add R/tng-qa/06-compare.R tests/testthat/test-compare.R
git commit -m "feat(tng-qa): bær konfidens videre gennem derive_our_pc()

Additiv udvidelse — nødvendig forudsætning for at relationel
corroboration (næste commit) kan udelukke omstridte forælder/barn-links
som evidenskilde. Eksisterende forbrugere (compare_parent_child) er
upåvirkede."
```

---

### Task 2: `family_corroboration()` + `aggregate_familie_status()`

**Files:**
- Create: `R/tng-qa/04b-corroboration.R`
- Test: `tests/testthat/test-corroboration.R` (ny fil)

**Interfaces:**
- Consumes:
  - `crosswalk`: `data.frame(person_id, tng_id, score, tier)` fra
    `assign_tiers()` (04-match.R) — kun `person_id`/`tng_id`/`tier` bruges.
  - `our_pc`: `data.frame(child_id, parent_id, rolle, konfidens)` fra
    `derive_our_pc()` (Task 1).
  - `tngc`: `data.frame(child_tng, father_tng, mother_tng)` fra
    `reshape_tng_children()` (06-compare.R, uændret).
- Produces:
  - `family_corroboration(crosswalk, our_pc, tngc)` →
    `data.frame(person_id, tng_id, child_id, parent_id, rolle,
    neighbor_person_id, neighbor_tng_id, status, familie_detalje)`.
    `status ∈ {"bekraeftet", "modstridende"}`. `child_id`/`parent_id` er
    ALTID i `our_pc`s egen, allerede-korrekte orientering — ingen gætning
    om retning i senere forbrug (se design-spec beslutning #4).
  - `aggregate_familie_status(corrob)` →
    `data.frame(person_id, tng_id, familie_status, familie_stoette_antal,
    familie_detalje)`, én række pr. `(person_id,tng_id)`.
    `familie_status ∈ {"bekraeftet", "modstridende"}` ("ingen_auto_nabo"
    tilføjes af kalderen ved venstre-join, se Task 4 — funktionen selv
    emitterer kun rækker der HAR mindst én nabo).

- [ ] **Step 1: Skriv de fejlende tests**

Opret `tests/testthat/test-corroboration.R`:

```r
test_that("family_corroboration bekræfter forælder-nabo når TNG-graf stemmer", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("auto", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 1L)
  expect_equal(out$status, "bekraeftet")
  expect_equal(out$rolle, "forælder")
  expect_equal(out$child_id, 2L)
  expect_equal(out$parent_id, 1L)
})

test_that("family_corroboration bekræfter barn-nabo med korrekt orientering når kandidaten er forælderen", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("review", "auto"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 1L)
  expect_equal(out$status, "bekraeftet")
  expect_equal(out$rolle, "barn")
  # Kandidaten under review (person 1) er FORÆLDEREN her — child_id skal
  # stadig pege på det faktiske barn (person 2), ikke flippes.
  expect_equal(out$child_id, 2L)
  expect_equal(out$parent_id, 1L)
})

test_that("family_corroboration markerer modstridende når TNG-grafen IKKE bekræfter", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I9"),
                          tier = c("auto", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  # TNG siger I9's far er I5, IKKE I1 -> modsiger vores forælder-antagelse
  tngc <- data.frame(child_tng = "I9", father_tng = "I5", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 1L)
  expect_equal(out$status, "modstridende")
})

test_that("family_corroboration udelukker konfidens='omstridt'", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("auto", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = "omstridt", stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 0L)
})

test_that("family_corroboration returnerer intet uden auto-matchet nabo", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("review", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 0L)
})

test_that("family_corroboration returnerer velformet tom data.frame uden review-tier par", {
  crosswalk <- data.frame(person_id = 1L, tng_id = "I1", tier = "auto", stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = integer(0), parent_id = integer(0), rolle = character(0),
                       konfidens = character(0), stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = character(0), father_tng = character(0),
                     mother_tng = character(0), stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
})

test_that("aggregate_familie_status samler flere bekræftende naboer til én række", {
  corrob <- data.frame(
    person_id = c(2L, 2L), tng_id = c("I2", "I2"),
    child_id = c(2L, 2L), parent_id = c(1L, 3L), rolle = c("forælder", "forælder"),
    neighbor_person_id = c(1L, 3L), neighbor_tng_id = c("I1", "I3"),
    status = c("bekraeftet", "bekraeftet"),
    familie_detalje = c("far-detalje", "mor-detalje"), stringsAsFactors = FALSE)
  out <- aggregate_familie_status(corrob)
  expect_equal(nrow(out), 1L)
  expect_equal(out$familie_status, "bekraeftet")
  expect_equal(out$familie_stoette_antal, 2L)
  expect_equal(out$familie_detalje, "far-detalje; mor-detalje")
})

test_that("aggregate_familie_status vælger bekræftet over modstridende ved blandet evidens", {
  corrob <- data.frame(
    person_id = c(2L, 2L), tng_id = c("I2", "I2"),
    child_id = c(2L, 2L), parent_id = c(1L, 3L), rolle = c("forælder", "forælder"),
    neighbor_person_id = c(1L, 3L), neighbor_tng_id = c("I1", "I3"),
    status = c("bekraeftet", "modstridende"),
    familie_detalje = c("far-bekræfter", "mor-modsiger"), stringsAsFactors = FALSE)
  out <- aggregate_familie_status(corrob)
  expect_equal(nrow(out), 1L)
  expect_equal(out$familie_status, "bekraeftet")
  expect_equal(out$familie_stoette_antal, 1L)
})

test_that("aggregate_familie_status returnerer velformet tom data.frame", {
  tom <- data.frame(person_id = integer(0), tng_id = character(0),
                    child_id = integer(0), parent_id = integer(0), rolle = character(0),
                    neighbor_person_id = integer(0), neighbor_tng_id = character(0),
                    status = character(0), familie_detalje = character(0),
                    stringsAsFactors = FALSE)
  out <- aggregate_familie_status(tom)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
})
```

- [ ] **Step 2: Kør tests og bekræft at de fejler**

Run: `Rscript run-tests.R`
Expected: FAIL — `could not find function "family_corroboration"` (filen
`04b-corroboration.R` findes endnu ikke).

- [ ] **Step 3: Implementér `04b-corroboration.R`**

Opret `R/tng-qa/04b-corroboration.R`:

```r
# Trin 4b: relationel corroboration af review-tier kandidater. Beregnes på
# den FERSKE crosswalk, FØR Trin 5's merge_review_decisions() (som flipper
# review-rækker til accepted/afvist) — ellers findes de aldrig. Se
# docs/superpowers/specs/2026-07-01-tng-qa-relationel-corroboration-design.md.
#
# Matcher ALDRIG på relationer (04-match.R's tier-tildeling er upåvirket) —
# dette er et beslutningsstøtte-signal til den menneskelige reviewer.

family_corroboration <- function(crosswalk, our_pc, tngc) {
  auto   <- crosswalk[crosswalk$tier == "auto", ]
  review <- crosswalk[crosswalk$tier == "review", ]
  auto_map <- setNames(auto$tng_id, as.character(auto$person_id))

  # Kun sikre/sandsynlige forælder-barn-links som corroboration-kilde —
  # aldrig 'omstridt' (design-spec beslutning #3).
  safe_pc <- our_pc[is.na(our_pc$konfidens) | our_pc$konfidens %in% c("sikker", "sandsynlig"), ]

  empty <- data.frame(person_id = integer(0), tng_id = character(0),
                       child_id = integer(0), parent_id = integer(0), rolle = character(0),
                       neighbor_person_id = integer(0), neighbor_tng_id = character(0),
                       status = character(0), familie_detalje = character(0),
                       stringsAsFactors = FALSE)
  if (!nrow(review)) return(empty)

  rows <- list()
  for (i in seq_len(nrow(review))) {
    pid <- review$person_id[i]; tid <- review$tng_id[i]

    # Nabo som FORÆLDER til kandidaten (pid er barnet i our_pc)
    parent_rows <- safe_pc[safe_pc$child_id == pid, ]
    for (j in seq_len(nrow(parent_rows))) {
      neighbor <- parent_rows$parent_id[j]
      neighbor_tng <- auto_map[as.character(neighbor)]
      if (is.na(neighbor_tng)) next
      hit <- any(tngc$child_tng == tid &
                 (tngc$father_tng == neighbor_tng | tngc$mother_tng == neighbor_tng), na.rm = TRUE)
      status <- if (hit) "bekraeftet" else "modstridende"
      label  <- if (hit) "bekræfter" else "modsiger"
      rows[[length(rows) + 1]] <- data.frame(
        person_id = pid, tng_id = tid, child_id = pid, parent_id = neighbor,
        rolle = "forælder", neighbor_person_id = neighbor, neighbor_tng_id = neighbor_tng,
        status = status,
        familie_detalje = sprintf(
          "forælder (person %d, TNG %s) er auto-matchet og %s TNG-relationen til kandidat %s",
          neighbor, neighbor_tng, label, tid),
        stringsAsFactors = FALSE)
    }

    # Nabo som BARN af kandidaten (pid er forælderen i our_pc)
    child_rows <- safe_pc[safe_pc$parent_id == pid, ]
    for (j in seq_len(nrow(child_rows))) {
      neighbor <- child_rows$child_id[j]
      neighbor_tng <- auto_map[as.character(neighbor)]
      if (is.na(neighbor_tng)) next
      hit <- any(tngc$child_tng == neighbor_tng &
                 (tngc$father_tng == tid | tngc$mother_tng == tid), na.rm = TRUE)
      status <- if (hit) "bekraeftet" else "modstridende"
      label  <- if (hit) "bekræfter" else "modsiger"
      rows[[length(rows) + 1]] <- data.frame(
        person_id = pid, tng_id = tid, child_id = neighbor, parent_id = pid,
        rolle = "barn", neighbor_person_id = neighbor, neighbor_tng_id = neighbor_tng,
        status = status,
        familie_detalje = sprintf(
          "barn (person %d, TNG %s) er auto-matchet og %s TNG-relationen til kandidat %s",
          neighbor, neighbor_tng, label, tid),
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(empty)
  do.call(rbind, rows)
}

aggregate_familie_status <- function(corrob) {
  empty <- data.frame(person_id = integer(0), tng_id = character(0),
                       familie_status = character(0), familie_stoette_antal = integer(0),
                       familie_detalje = character(0), stringsAsFactors = FALSE)
  if (!nrow(corrob)) return(empty)
  groups <- split(corrob, paste(corrob$person_id, corrob$tng_id))
  do.call(rbind, lapply(groups, function(g) data.frame(
    person_id = g$person_id[1], tng_id = g$tng_id[1],
    familie_status = if (any(g$status == "bekraeftet")) "bekraeftet" else "modstridende",
    familie_stoette_antal = sum(g$status == "bekraeftet"),
    familie_detalje = paste(g$familie_detalje, collapse = "; "),
    stringsAsFactors = FALSE)))
}
```

- [ ] **Step 4: Kør tests og bekræft at de består**

Run: `Rscript run-tests.R`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 112 ]` (103 fra Task 1 + 9 nye)

- [ ] **Step 5: Commit**

```bash
git add R/tng-qa/04b-corroboration.R tests/testthat/test-corroboration.R
git commit -m "feat(tng-qa): relationel corroboration af review-tier kandidater

family_corroboration() bruger allerede sikre (auto-tier) naboers matches
til at markere review-kandidater som bekræftet/modstridende via TNG's
familie-graf. aggregate_familie_status() samler til én status pr.
(person_id,tng_id). Rører ikke 04-match.R's scoring/tier-tildeling — rent
beslutningsstøtte-signal. Fase 1 af
docs/superpowers/specs/2026-07-01-tng-qa-relationel-corroboration-design.md
(Fase 2, Trin 6-relabeling, er separat og blokeret)."
```

---

### Task 3: `.gitignore` — dæk den nye lokale output-fil

**Files:**
- Modify: `.gitignore:18-21`

**Interfaces:** Ingen (konfigurationsfil).

- [ ] **Step 1: Tilføj linjen**

I `.gitignore`, find blokken:

```
# TNG-QA-afledte filer (crosswalk/review-kø/duckdb) — mapper til levende-data (GDPR, invariant #8)
data/tng.duckdb
data/tng-crosswalk.csv
data/tng-review-queue.csv
```

og udvid til:

```
# TNG-QA-afledte filer (crosswalk/review-kø/duckdb) — mapper til levende-data (GDPR, invariant #8)
data/tng.duckdb
data/tng-crosswalk.csv
data/tng-review-queue.csv
data/tng-corroboration.csv
```

- [ ] **Step 2: Verificér**

Run: `git check-ignore -v data/tng-corroboration.csv`
Expected: output viser `.gitignore:22:data/tng-corroboration.csv` (den
nøjagtige linje afhænger af hvor den lander — pointen er at kommandoen
returnerer en linje, ikke exit code 1/intet output).

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore(tng-qa): git-ignorér ny tng-corroboration.csv

Fanget af Codex-review: den nye output-fil var IKKE dækket af de
eksisterende tng.duckdb/tng-crosswalk.csv/tng-review-queue.csv-linjer,
modsat hvad design-spec'en oprindeligt antog."
```

---

### Task 4: Kobl `family_corroboration()` ind i `run-pipeline.R`

**Files:**
- Modify: `R/tng-qa/run-pipeline.R`

**Interfaces:**
- Consumes: `family_corroboration()`, `aggregate_familie_status()` (Task 2),
  `derive_our_pc()` (Task 1, uændret signatur), eksisterende
  `reshape_tng_children()`.
- Produces: `data/tng-corroboration.csv` (ny fil på disk, kun bekræftede
  `child_id,parent_id`-kanter — forbruges af Fase 2, IKKE af noget i denne
  plan). `data/tng-review-queue.csv` får tre nye kolonner:
  `familie_status`, `familie_stoette_antal`, `familie_detalje`.

- [ ] **Step 1: Flyt `our_pc`/`tngc`-beregning op, tilføj Trin 4b**

I `R/tng-qa/run-pipeline.R`, find:

```r
# ---- Trin 2: Supabase (read-only) -----------------------------------------
message("== Trin 2: Supabase (read-only) ==")
scon <- connect_readonly(); assert_readonly(scon)
ours <- pull_ours(scon)
dbDisconnect(scon)  # luk straks efter sidste brug (samme on.exit-fælde som tcon)

# ---- Trin 3-4: normalisér + match -----------------------------------------
```

og erstat med:

```r
# ---- Trin 2: Supabase (read-only) -----------------------------------------
message("== Trin 2: Supabase (read-only) ==")
scon <- connect_readonly(); assert_readonly(scon)
ours <- pull_ours(scon)
dbDisconnect(scon)  # luk straks efter sidste brug (samme on.exit-fælde som tcon)

# our_pc/tngc flyttet op fra Trin 6: Trin 4b (nedenfor) skal bruge dem FØR
# Trin 5's merge, og de afhænger kun af ours/tng_families/tng_children —
# ikke af crosswalk. our_pairs/our_attr forbliver ved Trin 6 (ubrugt af 4b).
our_pc <- derive_our_pc(ours$family_member)
tngc   <- reshape_tng_children(tng_children, tng_families)

# ---- Trin 3-4: normalisér + match -----------------------------------------
```

- [ ] **Step 2: Indsæt Trin 4b mellem Trin 4 og Trin 5**

Find:

```r
message(sprintf("  tiers: auto=%d review=%d none=%d (auto bootstrap-kalibreret; review bred)",
                tier_tab[["auto"]], tier_tab[["review"]], tier_tab[["none"]]))

# ---- Trin 5: review-merge (hvis afgørelser findes) ------------------------
```

og erstat med:

```r
message(sprintf("  tiers: auto=%d review=%d none=%d (auto bootstrap-kalibreret; review bred)",
                tier_tab[["auto"]], tier_tab[["review"]], tier_tab[["none"]]))

# ---- Trin 4b: relationel corroboration (annotation, IKKE tier-ændring) ----
# Fase 1 af docs/superpowers/specs/2026-07-01-tng-qa-relationel-corroboration-design.md.
# Beregnes på DENNE ferske crosswalk, FØR Trin 5's merge flipper review->accepted/afvist.
message("== Trin 4b: relationel corroboration ==")
corrob <- family_corroboration(crosswalk, our_pc, tngc)
confirmed_edges <- unique(corrob[corrob$status == "bekraeftet", c("child_id", "parent_id")])
write.csv(confirmed_edges, "data/tng-corroboration.csv", row.names = FALSE)
familie_summary <- aggregate_familie_status(corrob)
message(sprintf("  %d review-par med familie-nabo (bekræftet=%d, modstridende=%d)",
                nrow(familie_summary),
                sum(familie_summary$familie_status == "bekraeftet"),
                sum(familie_summary$familie_status == "modstridende")))

# ---- Trin 5: review-merge (hvis afgørelser findes) ------------------------
```

- [ ] **Step 3: Berig review-køen med familie-status før skrivning**

Find:

```r
rq <- crosswalk[crosswalk$tier == "review", ]
rq$afgoerelse <- ""
rq$ny_tng_id  <- ""
write.csv(rq, rq_csv, row.names = FALSE)
```

og erstat med:

```r
rq <- crosswalk[crosswalk$tier == "review", ]
rq$afgoerelse <- ""
rq$ny_tng_id  <- ""
rq <- merge(rq, familie_summary, by = c("person_id", "tng_id"), all.x = TRUE, sort = FALSE)
rq$familie_status[is.na(rq$familie_status)] <- "ingen_auto_nabo"
rq$familie_stoette_antal[is.na(rq$familie_stoette_antal)] <- 0L
rq$familie_detalje[is.na(rq$familie_detalje)] <- ""
write.csv(rq, rq_csv, row.names = FALSE)
```

- [ ] **Step 4: Fjern nu-overflødig duplikeret beregning i Trin 6**

Find (i Trin 6-blokken):

```r
# Sammenlignings-input
our_pairs <- our_spouse_pairs(ours$family, ours$family_member)
our_pc    <- derive_our_pc(ours$family_member)
our_attr  <- our_attr_frame(ours$person, ours$dates)
tngc      <- reshape_tng_children(tng_children, tng_families)
```

og erstat med:

```r
# Sammenlignings-input. our_pc/tngc er allerede beregnet ovenfor (Trin 4b
# har brug for dem tidligere i pipelinen) — kun our_pairs/our_attr er nye her.
our_pairs <- our_spouse_pairs(ours$family, ours$family_member)
our_attr  <- our_attr_frame(ours$person, ours$dates)
```

- [ ] **Step 5: Kør den fulde testsuite (regressionstjek)**

Run: `Rscript run-tests.R`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 112 ]` — uændret fra Task 2,
da `run-pipeline.R` selv ikke er del af testthat-suiten (det er et
orkestrerings-script, ikke en kilde til rene funktioner). Denne kørsel
bekræfter blot at Task 4 ikke har ødelagt noget i de eksisterende
funktionsfiler.

- [ ] **Step 6: Manuel røgtest af den fulde pipeline**

Dette kræver den lokale opsætning beskrevet i `docs/tng-qa-koersel.md`
(`~/.Renviron` med `SUPABASE_HOST`/`USER`/`PASSWORD`, samt
`jr_tng_reventlow.sql` i repo-roden) — samme forudsætning som al anden
kørsel af denne pipeline (ingen CI-gate, manuel procedure, jf.
`docs/tng-qa-koersel.md` §"Kørte / sprungne dele").

Run: `Rscript R/tng-qa/run-pipeline.R`

Forventet output inkluderer en ny linje mellem "Trin 3-4" og "Trin 5":

```
== Trin 4b: relationel corroboration ==
  X review-par med familie-nabo (bekræftet=Y, modstridende=Z)
```

Efter kørslen, inspicér:

```bash
head -3 data/tng-corroboration.csv
# Forventet: header "child_id,parent_id" + bekræftede kanter (kan være tom
# hvis Y=0 i outputtet ovenfor).

head -3 data/tng-review-queue.csv
# Forventet: kolonnerne familie_status/familie_stoette_antal/familie_detalje
# findes ud over de eksisterende (person_id,tng_id,score,tier,afgoerelse,ny_tng_id).
```

Hvis `Y` (bekræftet-tallet) er tæt på de tidligere fundne **133** unikke
personer fra analysen i design-specen, er implementeringen konsistent med
det forventede omfang (tallet kan afvige lidt hvis base/TNG-dump er
opdateret siden).

- [ ] **Step 7: Commit**

```bash
git add R/tng-qa/run-pipeline.R
git commit -m "feat(tng-qa): kobl relationel corroboration ind i pipeline-orkestreringen

Trin 4b beregnes mellem fersk crosswalk (Trin 4) og review-merge (Trin 5),
beriger tng-review-queue.csv med familie_status/familie_stoette_antal/
familie_detalje, og skriver data/tng-corroboration.csv (kun bekræftede
kanter — forbruges af den separate, blokerede Fase 2)."
```

---

## Efter Fase 1

Fase 2 (cirkularitets-relabeling `enig_via_matching` i Trin 6) kræver at
`merge_review_decisions()` først nøgles på `(person_id,tng_id)` i stedet
for `person_id` alene, plus et post-merge injektivitetstjek (M2). Det er en
selvstændig plan, ikke en fortsættelse af denne — se
§"Forudsætninger" i `docs/superpowers/specs/2026-07-01-tng-qa-relationel-corroboration-design.md`.
