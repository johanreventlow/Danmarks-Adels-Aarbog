# De gamle loadere fryses (docs/decisions.md 2026-10-27, B5): post_load_fixup.R og
# backfill_slaegtled.R kræver --jeg-mener-det, afviser ukendte flag og stopper før
# enhver transaktion, når narrative-record-kontrakten ikke er v1. load_daa.R er
# allerede lukket ved sin egen kontraktport. Testes uden DB.
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-extract/scripts/load_helpers.R"))
})

test_that("parse_legacy_script_args kræver --jeg-mener-det og afviser ukendte flag", {
  u <- "brug: x.R [a]"
  expect_error(parse_legacy_script_args(c("a"), u, 1L), "--jeg-mener-det")
  expect_error(parse_legacy_script_args(c("a", "--dryrun", "--jeg-mener-det"), u, 1L), "Ukendt argument: --dryrun")
  expect_error(parse_legacy_script_args(c("a", "b", "--jeg-mener-det"), u, 1L), "for mange")
  a <- parse_legacy_script_args(c("--jeg-mener-det", "a"), u, 1L)
  expect_identical(a$positional, "a")
  expect_identical(a$values, list())
})

test_that("parse_legacy_script_args tillader kun navngivne værdiflag", {
  u <- "brug: x.R seg.json"
  a <- parse_legacy_script_args(c("seg.json", "--source-id=7", "--jeg-mener-det"), u, 2L, value_flags = "--source-id=")
  expect_identical(a$values[["--source-id="]], "7")
  expect_error(parse_legacy_script_args(c("seg.json", "--source-id", "--jeg-mener-det"), u, 2L, value_flags = "--source-id="),
               "Ukendt argument: --source-id")
  expect_error(parse_legacy_script_args(c("seg.json", "--source-id=1", "--source-id=2", "--jeg-mener-det"), u, 2L,
                                        value_flags = "--source-id="), "kun angives én gang")
})

test_that("assert_legacy_contract_open lukker ved alt andet end v1", {
  expect_invisible(assert_legacy_contract_open(1L))
  expect_error(assert_legacy_contract_open(2L), "LEGACY_LOADER_FROZEN")
  expect_error(assert_legacy_contract_open(NA_integer_), "LEGACY_LOADER_FROZEN")
  expect_error(assert_legacy_contract_open(integer(0)), "LEGACY_LOADER_FROZEN")
})

test_that("post_load_fixup.R og backfill_slaegtled.R tjekker kontrakt og flag før transaktionen", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  scripts <- file.path(root, ".claude/skills/daa-extract/scripts")
  for (f in c("post_load_fixup.R", "backfill_slaegtled.R")) {
    src <- readLines(file.path(scripts, f), warn = FALSE)
    code <- src[!grepl("^\\s*#", src)]
    l_args <- grep("parse_legacy_script_args\\(", code)[1]
    l_contract <- grep("assert_legacy_contract_open\\(", code)[1]
    l_begin <- grep("^dbBegin\\(con\\)", code)[1]
    expect_false(is.na(l_args), info = f)
    expect_false(is.na(l_contract), info = f)
    expect_true(l_args < l_contract && l_contract < l_begin, info = f)
  }
  post <- readLines(file.path(scripts, "post_load_fixup.R"), warn = FALSE)
  call <- grep("system2\\(\"Rscript\"", post, value = TRUE)
  expect_length(call, 1L)
  expect_match(call, "--jeg-mener-det", fixed = TRUE)
})
