root <- normalizePath(file.path(testthat::test_path(), "../.."))
source(file.path(root, ".claude/skills/daa-extract/scripts/export_legacy_migration_candidates_helpers.R"))

test_that("work-stier afvises", {
  expect_error(lmc_validate_output_dir("/tmp/work/x"), "OUTPUT_WORK_PATH")
  expect_error(lmc_validate_output_dir("relative/dir"), "OUTPUT_DIR_NOT_ABSOLUTE")
})
test_that("work_*-præfikserede sti-komponenter afvises (CLAUDE.md: work_1939_stamtavle, work_presens)", {
  expect_error(lmc_validate_output_dir("/tmp/work_1939_stamtavle/x"), "OUTPUT_WORK_PATH")
  expect_error(lmc_validate_output_dir("/tmp/work_presens/x"), "OUTPUT_WORK_PATH")
})
test_that("en sti-komponent der blot starter med 'work' uden understreg er ikke ramt (fx 'workshop')", {
  expect_false(lmc_has_work_component("/tmp/workshop/x"))
})
test_that("kandidat-SQL bærer ingen rå tekst uden for digest()", {
  # Enhver forekomst af 'tekst'/'verbatim_text' skal stå inde i et digest(...)-kald;
  # fjern alle digest(...)-udtryk og assertér at ordene så er væk.
  stripped <- gsub("digest\\([^)]*\\)", "", lmc_sql$candidates)
  expect_false(grepl("\\btekst\\b", stripped))
  expect_false(grepl("verbatim_text", stripped))
  expect_true(grepl("digest\\(narrative\\.tekst,'sha256'\\)", lmc_sql$candidates))
  expect_true(grepl("digest\\(occurrence\\.verbatim_text,'sha256'\\)", lmc_sql$candidates))
  expect_true(grepl("narrative_legacy_publication", lmc_sql$candidates))
})
test_that("teksternes SQL henter rå tekst direkte", {
  expect_true(grepl("verbatim_text", lmc_sql$texts))
  expect_true(grepl("narrative\\.tekst", lmc_sql$texts))
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

.lmc_fake_candidate_row <- function(...) {
  base <- list(
    record_key = "K1", person_id = 1L, narrative_id = 2L, person_levende = FALSE,
    person_privat = FALSE, person_staged = FALSE, narrative_privat = FALSE,
    narrative_text_sha256 = strrep("1", 64L), occurrence_verbatim_sha256 = strrep("1", 64L),
    legacy_publication_ref = NA_character_, legacy_status = NA_character_,
    legacy_baseline_sha256 = NA_character_, persons_for_record_key = 1L,
    external_ids_for_person = 1L, narratives_for_person = 1L, already_bound = FALSE
  )
  overrides <- list(...)
  base[names(overrides)] <- overrides
  do.call(data.frame, c(base, list(stringsAsFactors = FALSE)))
}

test_that("lmc_export_run fejler højt når ledger-tabellen mangler (#152)", {
  fake_query <- function(sql, params = list()) {
    if (grepl("to_regclass", sql, fixed = TRUE)) return(data.frame(present = FALSE))
    stop("UNEXPECTED_QUERY_CALLED: manglende ledger-tabel skal stoppe eksporten før noget andet forespørges")
  }
  expect_error(lmc_export_run(fake_query, 1L), "LEGACY_MIGRATION_LEDGER_TABLE_MISSING")
})
test_that("lmc_export_run fejler højt ved NULL narrative_text_sha256", {
  fake_query <- function(sql, params = list()) {
    if (grepl("to_regclass", sql, fixed = TRUE)) return(data.frame(present = TRUE))
    if (grepl("LMC_EXPORT_CANDIDATES", sql, fixed = TRUE))
      return(.lmc_fake_candidate_row(narrative_text_sha256 = NA_character_))
    stop("UNEXPECTED_QUERY_CALLED")
  }
  expect_error(lmc_export_run(fake_query, 1L), "LEGACY_MIGRATION_EXPORT_HASH_MISSING")
})
test_that("lmc_export_run lykkes, når ledger-tabellen findes og hashen er sat", {
  fake_query <- function(sql, params = list()) {
    if (grepl("to_regclass", sql, fixed = TRUE)) return(data.frame(present = TRUE))
    if (grepl("LMC_EXPORT_CANDIDATES", sql, fixed = TRUE)) return(.lmc_fake_candidate_row())
    if (grepl("LMC_EXPORT_TEXTS", sql, fixed = TRUE)) return(data.frame(
      record_key = "K1", narrative_text = "Alfa Bravo", occurrence_text = "Alfa Bravo",
      stringsAsFactors = FALSE))
    stop("UNEXPECTED_QUERY_CALLED")
  }
  result <- lmc_export_run(fake_query, 1L)
  expect_length(result$candidates, 1L)
  expect_identical(result$candidates[[1L]]$record_key, "K1")
  expect_identical(names(result$texts), "K1")
})
