script <- file.path("R", "update-1939-narratives.R")
if (!file.exists(script)) script <- file.path("..", "..", "R", "update-1939-narratives.R")
source(script, local = TRUE)

test_that("argument parser has a usable default artifact", {
  config <- parse_update_1939_args(character())
  expect_equal(config$artifact, "work_1939_stamtavle/clean_1939.json")
  expect_false(config$apply)
})

test_that("target gate rejects a mismatched project", {
  config <- list(allow_local = FALSE, expected_project_ref = "expected-ref")
  expect_error(
    assert_connection_target(config, "pooler.example", 5432L, "postgres.other-ref"),
    "matcher ikke"
  )
})

test_that("prod target gate requires session pooler port", {
  config <- list(allow_local = FALSE, expected_project_ref = "expected-ref")
  expect_error(
    assert_connection_target(config, "expected-ref.pooler", 6543L, "postgres.expected-ref"),
    "port 5432"
  )
})

test_that("local override only accepts local hosts", {
  config <- list(allow_local = TRUE, expected_project_ref = "")
  expect_invisible(assert_connection_target(config, "localhost", 5432L, "local"))
  expect_error(assert_connection_target(config, "remote.example", 5432L, "local"), "lokal")
})

test_that("plan marks text and nullable side changes", {
  mapping <- data.frame(
    nr = 1:3, person_id = 11:13, narrative_id = 21:23,
    tekst = c("samme", "gammel", "samme"), side = c("1", NA, "3"),
    staged = TRUE, levende = FALSE, privat = FALSE
  )
  patch <- data.frame(
    nr = 1:3, tekst = c("samme", "ny", "samme"), side = c("1", "2", NA),
    stringsAsFactors = FALSE
  )
  plan <- plan_1939_update(mapping, patch)
  expect_equal(plan$text_changed, c(FALSE, TRUE, FALSE))
  expect_equal(plan$side_changed, c(FALSE, TRUE, TRUE))
  expect_equal(plan$changed, c(FALSE, TRUE, TRUE))
})
