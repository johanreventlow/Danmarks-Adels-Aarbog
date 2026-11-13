# load_haendelser.R skriver til prod: skrivning kræver --jeg-mener-det, dry-run er
# eksplicit, og ukendte flag afvises. Testes uden DB.
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-haendelser/scripts/load_haendelser_helpers.R"))
})

test_that("uden flag afvises kørslen (ingen skrivning ved forglemmelse)", {
  expect_error(parse_load_haendelser_args(c("clean.json")), "--jeg-mener-det er obligatorisk")
})

test_that("--dry-run alene er tilladt og giver dry_run = TRUE", {
  a <- parse_load_haendelser_args(c("clean.json", "--dry-run"))
  expect_identical(a, list(path = "clean.json", dry_run = TRUE))
})

test_that("--jeg-mener-det giver skrivning", {
  a <- parse_load_haendelser_args(c("--jeg-mener-det", "clean.json"))
  expect_identical(a, list(path = "clean.json", dry_run = FALSE))
})

test_that("begge flag samtidig afvises", {
  expect_error(parse_load_haendelser_args(c("clean.json", "--dry-run", "--jeg-mener-det")),
               "udelukker hinanden")
})

test_that("ukendte flag og forkert antal positionelle argumenter afvises", {
  expect_error(parse_load_haendelser_args(c("clean.json", "--dryrun")), "Ukendt argument: --dryrun")
  expect_error(parse_load_haendelser_args(c("--dry-run")), "brug:")
  expect_error(parse_load_haendelser_args(c("a.json", "b.json", "--dry-run")), "brug:")
})
