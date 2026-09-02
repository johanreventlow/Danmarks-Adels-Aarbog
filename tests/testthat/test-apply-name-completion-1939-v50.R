library(testthat)

root <- normalizePath(file.path(getwd(), "../.."), mustWork = TRUE)
adapter <- file.path(root, ".claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R")
cli <- file.path(root, ".claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R")
old <- getwd()
on.exit(setwd(old), add = TRUE)
setwd(dirname(adapter))
source(basename(adapter), local = TRUE)

test_that("1939 name-completion adapter pins its legacy manifest to the generic profile", {
  profile <- legacy_name_completion_profile(list(source = list(source_id = 3L)))
  expect_identical(profile$id, 3L)
  expect_identical(profile$profile_id, "daa-1939-v50-production-write-v1")
  expect_match(profile$profile_sha256, "^[0-9a-f]{64}$")
})

test_that("1939 name-completion files contain no direct database or legacy RPC gateway", {
  adapter_text <- paste(readLines(adapter, warn = FALSE), collapse = "\n")
  cli_text <- paste(readLines(cli, warn = FALSE), collapse = "\n")
  expect_false(grepl("DBI::|RPostgres::|red_[a-z_]*1939_v50", adapter_text))
  expect_false(grepl("DBI::|RPostgres::|red_[a-z_]*1939_v50", cli_text))
  expect_match(adapter_text, "execute_name_completion_generic")
})
