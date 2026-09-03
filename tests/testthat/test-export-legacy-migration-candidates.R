root <- normalizePath(file.path(testthat::test_path(), "../.."))
source(file.path(root, ".claude/skills/daa-extract/scripts/export_legacy_migration_candidates_helpers.R"))

test_that("work-stier afvises", {
  expect_error(lmc_validate_output_dir("/tmp/work/x"), "OUTPUT_WORK_PATH")
  expect_error(lmc_validate_output_dir("relative/dir"), "OUTPUT_DIR_NOT_ABSOLUTE")
})
test_that("kandidat-SQL bærer ingen tekstkolonne", {
  expect_false(grepl("\\btekst\\b", lmc_sql$candidates))
  expect_true(grepl("verbatim_text", lmc_sql$texts))
  expect_true(grepl("narrative_legacy_publication", lmc_sql$candidates))
})
test_that("output-dir skal eksistere og være en mappe", {
  expect_error(lmc_validate_output_dir("/this/path/does/not/exist/anywhere"), "OUTPUT_DIR_INVALID")
})
test_that("output-dir skal have mode 0700", {
  dir <- tempfile("lmc-mode-test-")
  dir.create(dir, mode = "0755")
  on.exit(unlink(dir, recursive = TRUE))
  expect_error(lmc_validate_output_dir(dir), "OUTPUT_DIR_MODE_INVALID")
  Sys.chmod(dir, "0700")
  expect_identical(lmc_validate_output_dir(dir), normalizePath(dir, mustWork = TRUE))
})
test_that("kandidatlisten bærer ingen tekstfelter og har den lukkede feltmængde", {
  rows <- data.frame(
    record_key = "K1", person_id = 11L, narrative_id = 21L, person_levende = FALSE,
    person_privat = FALSE, person_staged = FALSE, narrative_privat = FALSE,
    narrative_text_sha256 = strrep("1", 64L), occurrence_verbatim_sha256 = strrep("1", 64L),
    legacy_publication_ref = "11111111-1111-4111-8111-111111111111",
    legacy_status = "grandfathered_publication", legacy_baseline_sha256 = strrep("3", 64L),
    persons_for_record_key = 1L, external_ids_for_person = 1L, narratives_for_person = 1L,
    already_bound = FALSE, stringsAsFactors = FALSE
  )
  built <- lmc_build_candidates(rows)
  expect_length(built, 1L)
  expect_identical(sort(names(built[[1L]])), sort(c(
    "record_key", "person_id", "narrative_id", "person_levende", "person_privat", "person_staged",
    "narrative_privat", "narrative_text_sha256", "occurrence_verbatim_sha256", "legacy_publication_ref",
    "legacy_status", "legacy_baseline_sha256", "persons_for_record_key", "external_ids_for_person",
    "narratives_for_person", "already_bound"
  )))
  serialized <- jsonlite::toJSON(built, auto_unbox = TRUE, null = "null")
  expect_false(grepl("Alfa|Bravo", serialized))
})
test_that("teksterne nøgles på record_key", {
  rows <- data.frame(
    record_key = c("K1", "K2"), narrative_text = c("Alfa", "Bravo"),
    occurrence_text = c("Alfa", "Bravo"), stringsAsFactors = FALSE
  )
  built <- lmc_build_texts(rows)
  expect_identical(names(built), c("K1", "K2"))
  expect_identical(built$K1$narrative_text, "Alfa")
})
