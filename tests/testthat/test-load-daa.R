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

test_that("is_missing_table_error genkender 42P01 / does not exist", {
  expect_true(is_missing_table_error('relation "change_set" does not exist'))
  expect_true(is_missing_table_error("ERROR: 42P01"))
  expect_false(is_missing_table_error("could not connect to server"))
  expect_false(is_missing_table_error("permission denied for table change_set"))
  expect_false(is_missing_table_error(NULL))
})

test_that("parse_intern_ref genkender interne se-nr", {
  expect_equal(parse_intern_ref("se nr. 97", "I"), list(linje="I", nr="97"))
  expect_equal(parse_intern_ref("nr. 106", "III"), list(linje="III", nr="106"))
  expect_equal(parse_intern_ref("von Reventlow. III. Den mecklenburgske linje, nr. 79", "I"),
               list(linje="III", nr="79"))
})
test_that("parse_intern_ref afviser eksterne udgave-refs", {
  expect_null(parse_intern_ref("DAA 1937, II, 122", "I"))
  expect_null(parse_intern_ref("DAA 1913, 135", "I"))
  expect_null(parse_intern_ref(NA, "I"))
})
