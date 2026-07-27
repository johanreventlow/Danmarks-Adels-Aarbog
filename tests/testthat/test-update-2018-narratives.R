script <- file.path("R", "update-2018-narratives.R")
if (!file.exists(script)) script <- file.path("..", "..", "R", "update-2018-narratives.R")
source(script, local = TRUE)

test_that("argument parser has a usable default artifact", {
  config <- parse_update_2018_args(character())
  expect_equal(config$artifact, "work/patch_2018_slaegtled_bleed.json")
  expect_false(config$apply)
  expect_equal(config$expected_source_id, 1L)
})

test_that("target gate rejects a mismatched project", {
  config <- list(allow_local = FALSE, expected_project_ref = "expected-ref")
  expect_error(
    assert_connection_target(config, "pooler.example", 5432L, "postgres.other-ref"),
    "matcher ikke"
  )
})

test_that("local override only accepts local hosts", {
  config <- list(allow_local = TRUE, expected_project_ref = "")
  expect_invisible(assert_connection_target(config, "localhost", 5432L, "local"))
  expect_error(assert_connection_target(config, "remote.example", 5432L, "local"), "lokal")
})

test_that("patch loader rejects duplicate (linje, nr) keys", {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp))
  jsonlite::write_json(list(
    list(linje = "IV", nr = 9, narrative = "tekst A"),
    list(linje = "IV", nr = 9, narrative = "tekst B")
  ), tmp, auto_unbox = TRUE)
  expect_error(load_2018_narrative_patch(tmp), "duplikerede")
})

test_that("patch loader rejects empty narrative text", {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp))
  jsonlite::write_json(list(
    list(linje = "IV", nr = 9, narrative = "  ")
  ), tmp, auto_unbox = TRUE)
  expect_error(load_2018_narrative_patch(tmp), "tomme narrativer")
})

test_that("patch loader accepts a well-formed targeted patch", {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp))
  jsonlite::write_json(list(
    list(linje = "IV", nr = 9, narrative = "Komtesse Caroline Mathilde ...Kloster."),
    list(linje = "V", nr = 1, narrative = "Greve Conrad de Reventlow ...")
  ), tmp, auto_unbox = TRUE)
  patch <- load_2018_narrative_patch(tmp)
  expect_equal(nrow(patch), 2L)
  expect_equal(patch$linje, c("IV", "V"))
  expect_equal(patch$nr, c(9L, 1L))
})

test_that("plan marks only genuinely changed text, keyed on (linje, nr)", {
  mapping <- data.frame(
    linje = c("IV", "IV", "V"), nr = c(1, 9, 1),
    person_id = 11:13, narrative_id = 21:23,
    tekst = c("samme", "gammel med bleed", "samme"),
    staged = TRUE, stringsAsFactors = FALSE
  )
  patch <- data.frame(
    linje = c("IV", "IV", "V"), nr = c(1, 9, 1),
    tekst = c("samme", "renset uden bleed", "samme"),
    stringsAsFactors = FALSE
  )
  plan <- plan_2018_update(mapping, patch)
  expect_equal(plan$changed, c(FALSE, TRUE, FALSE))
})

test_that("(linje, nr) alene er IKKE globalt unikt i denne udgave", {
  # I-15a/b/c deler basenr 15 i prod (under-litererede poster) — scriptet skal
  # fail-closed hvis en navngiven nøgle rammer flere rækker, ikke bare tage den første.
  mapping <- data.frame(
    linje = c("I", "I"), nr = c(15, 15),
    person_id = c(101, 102), narrative_id = c(201, 202),
    tekst = c("Eler ...", "Reymar ..."),
    stringsAsFactors = FALSE
  )
  patch <- data.frame(linje = "I", nr = 15, tekst = "ny tekst", stringsAsFactors = FALSE)
  # plan_2018_update selv tjekker kun 1:1-join-antal, ikke flertydighed i DB'en —
  # det gør read_2018_mapping (DB-afhængig, ikke testet her). Denne test dokumenterer
  # at merge() på en ikke-unik nøgle producerer FLERE rækker end patch, hvilket
  # plan_2018_update's nrow-guard fanger.
  expect_error(plan_2018_update(mapping, patch), "kunne ikke joines 1:1")
})
