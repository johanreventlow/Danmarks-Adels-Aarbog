# Rene, DB-frie hjælpere fra load_daa.R (load_helpers.R) — testes uden Supabase-forbindelse.
# testthat sætter wd til tests/testthat under test_dir(); repo root = ../.. (samme mønster
# som helper-source.R).
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-extract/scripts/load_helpers.R"))
})

test_that("buffer_counts tæller rækker pr. tabel", {
  buf <- list(person = list(list(id=1), list(id=2)), fact = list(list(id=1)))
  expect_equal(buffer_counts(buf), c(person = 2L, fact = 1L))
})

test_that("has_editorial_changes ser kun red_-operationer som redaktionelle", {
  expect_false(has_editorial_changes(data.frame(operation = c("daa_import"))))
  expect_true(has_editorial_changes(data.frame(operation = c("daa_import", "red_opret_fakta"))))
  expect_false(has_editorial_changes(data.frame(operation = character(0))))
})
