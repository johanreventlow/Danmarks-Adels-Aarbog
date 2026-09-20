library(testthat)

script_dir <- normalizePath(".claude/skills/daa-extract/scripts")
source(file.path(script_dir, "apply_source_scoped_replace_helpers.R"))

test_that("source-scoped replace adapter helper is available without database I/O", {
  expect_true(is.function(ssr_validate_manifest))
  expect_true(is.function(ssr_profile))
  expect_true(is.function(ssr_validate_terminal_receipt))
})
