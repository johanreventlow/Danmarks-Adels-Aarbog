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

test_that("union_index_for_kontekst mapper ordinal-tekst til indeks", {
  expect_equal(union_index_for_kontekst("af første ægteskab med Anna von Ahlefeldt"), 1L)
  expect_equal(union_index_for_kontekst("af andet ægteskab med NN"), 2L)
  expect_equal(union_index_for_kontekst("af 3. ægteskab"), 3L)
  expect_true(is.na(union_index_for_kontekst("med Elisabeth NN (se nr. 1)")))
  expect_true(is.na(union_index_for_kontekst(NULL)))
})
test_that("resolve_barn_keys foretrækker eksakt basenr, ellers a/b-varianter", {
  expect_equal(resolve_barn_keys("I", 15, c("I-15", "I-15a")), "I-15")
  expect_setequal(resolve_barn_keys("I", 15, c("I-15a", "I-15b")), c("I-15a", "I-15b"))
  expect_equal(resolve_barn_keys("I", 99, c("I-15")), character(0))
})
test_that("barn_lookup_reason klassificerer på resolverede nøgler", {
  expect_equal(barn_lookup_reason(c("I-30")), "ok")
  expect_equal(barn_lookup_reason(character(0)), "nr_ikke_i_forael_linje")
})
