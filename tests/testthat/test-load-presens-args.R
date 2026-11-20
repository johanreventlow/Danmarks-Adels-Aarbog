# Præsensloaderens argumenter (review 2026-10-27, fund 1c-01): --reset er fjernet,
# --jeg-mener-det er obligatorisk, og ukendte flag afvises. Testes uden DB.
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-presens/scripts/presens_args.R"))
})

test_that("parse_load_presens_args kræver --jeg-mener-det", {
  expect_error(parse_load_presens_args(c("clean.json")), "--jeg-mener-det")
  expect_error(parse_load_presens_args(c("clean.json", "DAA 2012-2014")), "--jeg-mener-det")
})

test_that("parse_load_presens_args afviser --reset med begrundelse", {
  expect_error(parse_load_presens_args(c("clean.json", "--reset", "--jeg-mener-det")),
               "--reset er fjernet")
})

test_that("parse_load_presens_args afviser ukendte flag og for mange positionelle", {
  expect_error(parse_load_presens_args(c("clean.json", "--dryrun", "--jeg-mener-det")), "Ukendt argument: --dryrun")
  expect_error(parse_load_presens_args(c("clean.json", "DAA 2012-2014", "ekstra", "--jeg-mener-det")),
               "for mange")
  expect_error(parse_load_presens_args(c("--jeg-mener-det")), "brug:")
})

test_that("parse_load_presens_args læser sti og udgave", {
  a <- parse_load_presens_args(c("clean.json", "DAA 2015-2017", "--jeg-mener-det"))
  expect_identical(a$path, "clean.json")
  expect_identical(a$udgave, "DAA 2015-2017")
  b <- parse_load_presens_args(c("--jeg-mener-det", "clean.json"))
  expect_identical(b$path, "clean.json")
  expect_identical(b$udgave, "DAA 2012-2014")
})

test_that("load_presens.R har ingen TRUNCATE og bruger parseren", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  src <- readLines(file.path(root, ".claude/skills/daa-presens/scripts/load_presens.R"), warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]
  expect_false(any(grepl("TRUNCATE|model_tables|RESET", code)))
  expect_true(any(grepl("parse_load_presens_args(commandArgs(trailingOnly = TRUE))", code, fixed = TRUE)))
})

test_that("load_presens.R skriver aldrig selv i person.visning_* (review 37, E5; invariant 4)", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  src <- readLines(file.path(root, ".claude/skills/daa-presens/scripts/load_presens.R"), warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]
  expect_false(any(grepl("UPDATE\\s+person", code, ignore.case = TRUE)))
  expect_false(any(grepl("visning_[a-z_]+\\s*=", code)))
  # men tjekker, at triggerne har fyldt cachen for de nye personer
  expect_true(any(grepl("p.visning_navn IS NULL", code, fixed = TRUE)))
  expect_true(any(grepl(".nye_personer <<- c(.nye_personer, pid)", code, fixed = TRUE)))
})

test_that("parse_load_presens_args: --dry-run alene eller --jeg-mener-det alene (review 37, E6)", {
  d <- parse_load_presens_args(c("clean.json", "DAA 2015-2017", "--dry-run"))
  expect_true(d$dry_run); expect_identical(d$udgave, "DAA 2015-2017")
  expect_false(parse_load_presens_args(c("clean.json", "--jeg-mener-det"))$dry_run)
  expect_error(parse_load_presens_args(c("clean.json", "--dry-run", "--jeg-mener-det")), "udelukker hinanden")
})

test_that("load_presens.R: genkørselsværn før første INSERT og sekvens-sync kun ved skrivning (E6)", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  src <- readLines(file.path(root, ".claude/skills/daa-presens/scripts/load_presens.R"), warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]
  vaern <- grep("FROM source WHERE slags = 'præsensliste' AND udgave = $1", code, fixed = TRUE)
  laas <- grep("IN EXCLUSIVE MODE", code, fixed = TRUE)
  foerste_insert <- grep("INSERT INTO source", code, fixed = TRUE)
  expect_length(vaern, 1L)
  expect_true(laas < vaern && vaern < foerste_insert)
  dry <- grep("if (DRY_RUN) {", code, fixed = TRUE)
  setval <- grep("setval(", code, fixed = TRUE)
  expect_length(dry, 1L); expect_length(setval, 1L)
  expect_true(setval > grep("} else {", code, fixed = TRUE)[grep("} else {", code, fixed = TRUE) > dry][1])
  expect_true(any(grepl("dbRollback(con)", code[dry:(dry + 3L)], fixed = TRUE)))
})
