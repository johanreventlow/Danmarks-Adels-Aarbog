library(testthat)

root <- normalizePath(file.path(getwd(), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"), local = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R"), local = TRUE)

sha <- function(letter) paste(rep(letter, 64L), collapse = "")

fixture_manifest <- function() {
  list(
    manifest_content_sha256 = sha("a"),
    source = list(id = 4242L, profile_id = "fixture-source-evidence-v1",
                  profile_sha256 = sha("b")),
    expected_counts = list(source_evidence = 2L, person_creates = 0L,
                           canonical_delta = 0L),
    operations = list(
      list(element_id = "source-evidence:I-1", dependency_class = "source_evidence",
           source_record_key = "I-1", disposition = "retain_source_only",
           category = "person_post", rendition_content_sha256 = sha("c"),
           source_span = list(char_from = 0L, char_to = 9L),
           page_evidence = list(page_from = 10L, page_to = 10L),
           verbatim_text = "Alfa Bravo"),
      list(element_id = "source-evidence:I-2a", dependency_class = "source_evidence",
           source_record_key = "I-2a", disposition = "retain_source_only",
           category = "person_post", rendition_content_sha256 = sha("c"),
           source_span = list(char_from = 20L, char_to = 33L),
           page_evidence = list(page_from = 10L, page_to = 11L),
           verbatim_text = "Charlie Delta")))
}

fake_query <- function(overrides = list()) {
  function(sql, params = list()) {
    if (grepl("transaction_read_only", sql, fixed = TRUE))
      return(overrides$state %||% data.frame(
        database_identity = "{\"database_name\":\"daa149a\",\"system_identifier\":\"1\"}",
        database_name = "daa149a", system_identifier = "1",
        transaction_read_only = "on", contract_version = 2L,
        stringsAsFactors = FALSE))
    if (grepl("reimport_writer_profile", sql, fixed = TRUE))
      return(overrides$profile %||% data.frame(n = 1L))
    if (grepl("source_rendition", sql, fixed = TRUE))
      return(data.frame(renditions = 0L, records = 0L, occurrences = 0L,
                        anchors = 0L, runs = 0L))
    if (grepl("person_external_id", sql, fixed = TRUE))
      return(overrides$keys %||% data.frame(record_key = c("I-1", "I-2a"),
                                             stringsAsFactors = FALSE))
    data.frame(h = sha("f"), stringsAsFactors = FALSE)
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x

test_that("authorization request mirrors the writer's closed payload contract", {
  request <- preview_authorization_request(fixture_manifest())
  expect_identical(names(request$expected_counts), c("person_creates", "source_evidence"))
  expect_identical(request$expected_counts$source_evidence, 2L)
  expect_identical(request$expected_counts$person_creates, 0L)
  expect_identical(sort(names(request$authorized_elements)),
                   c("source-evidence:I-1", "source-evidence:I-2a"))
  expect_true(all(grepl("^source-evidence:.+$", names(request$authorized_elements))))
  expect_null(request$authorized_elements[["source-evidence:I-1"]]$element_id)
  expect_null(request$authorized_elements[["source-evidence:I-1"]]$dependency_class)
  expect_identical(request$authorized_elements[["source-evidence:I-1"]]$disposition,
                   "retain_source_only")
})

test_that("preview refuses a writable transaction", {
  state <- data.frame(
    database_identity = "{\"database_name\":\"daa149a\",\"system_identifier\":\"1\"}",
    database_name = "daa149a", system_identifier = "1",
    transaction_read_only = "off", contract_version = 2L, stringsAsFactors = FALSE)
  expect_error(
    build_reimport_preview(fake_query(list(state = state)), fixture_manifest(), sha("e")),
    "PREVIEW_TRANSACTION_NOT_READ_ONLY")
})

test_that("preview refuses a base that is not on narrative record contract 2", {
  state <- data.frame(
    database_identity = "{\"database_name\":\"daa149a\",\"system_identifier\":\"1\"}",
    database_name = "daa149a", system_identifier = "1",
    transaction_read_only = "on", contract_version = 1L, stringsAsFactors = FALSE)
  expect_error(
    build_reimport_preview(fake_query(list(state = state)), fixture_manifest(), sha("e")),
    "PREVIEW_NARRATIVE_RECORD_CONTRACT_REQUIRED")
})

test_that("preview refuses a missing writer profile row", {
  expect_error(
    build_reimport_preview(fake_query(list(profile = data.frame(n = 0L))),
                           fixture_manifest(), sha("e")),
    "PREVIEW_WRITER_PROFILE_MISSING")
})

test_that("preview reports the record_key set difference as sets, not counts", {
  keys <- data.frame(record_key = c("I-1", "I-3"), stringsAsFactors = FALSE)
  preview <- build_reimport_preview(fake_query(list(keys = keys)),
                                    fixture_manifest(), sha("e"))
  expect_identical(preview$record_key_coverage$only_in_manifest, "I-2a")
  expect_identical(preview$record_key_coverage$only_in_person_external_id, "I-3")
})

test_that("preview binds the manifest and carries no verbatim text", {
  preview <- build_reimport_preview(fake_query(), fixture_manifest(), sha("e"))
  expect_identical(preview$manifest$manifest_content_sha256, sha("a"))
  expect_identical(preview$manifest$manifest_bytes_sha256, sha("e"))
  expect_identical(preview$before_counts$source_record, 0L)
  serialized <- jsonlite::toJSON(preview, auto_unbox = TRUE, null = "null")
  expect_false(grepl("Alfa Bravo", serialized, fixed = TRUE))
  expect_false(grepl("Charlie Delta", serialized, fixed = TRUE))
})

test_that("preview rejects a manifest with person_creates", {
  manifest <- fixture_manifest()
  manifest$expected_counts$person_creates <- 1L
  expect_error(build_reimport_preview(fake_query(), manifest, sha("e")),
               "REIMPORT_MANIFEST_COUNTS_INVALID")
})
