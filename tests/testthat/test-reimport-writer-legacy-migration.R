root <- normalizePath(file.path(testthat::test_path(), "../.."))
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"))
sha <- function(ch) paste(rep(ch, 64L), collapse = "")
op <- function(key) list(
  element_id = paste0("legacy-migration:", key), dependency_class = "legacy_migration",
  source_record_key = key, source_id = 7L, person_id = 11L, narrative_id = 21L,
  disposition = "bound_published", narrative_text_sha256 = sha("1"),
  occurrence_verbatim_sha256 = sha("1"), normalized_text_sha256 = sha("2"),
  legacy_publication_ref = "11111111-1111-4111-8111-111111111111",
  legacy_baseline_sha256 = sha("3"), persona_key = key)
manifest <- function(...) list(
  manifest_content_sha256 = sha("a"),
  source = list(id = 7L, profile_id = "fixture-legacy-migration-v1", profile_sha256 = sha("b")),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L, legacy_migrations = 1L),
  dispositions = list(list(record_key = "K1", disposition = "bound_published")),
  operations = list(op("K1")), ...)

test_that("tre-nøgle-manifest med legacy_migration valideres", {
  expect_silent(validate_reimport_manifest(manifest()))
  expect_identical(reimport_writer_expected_counts(manifest()),
    list(person_creates = 0L, source_evidence = 0L, legacy_migrations = 1L))
})
test_that("to-nøgle-manifest (149a) valideres stadig", {
  m <- manifest(); m$expected_counts$legacy_migrations <- NULL; m$dispositions <- NULL
  m$operations <- list(); m$expected_counts$source_evidence <- 0L
  expect_silent(validate_reimport_manifest(m))
  expect_identical(names(reimport_writer_expected_counts(m)), c("person_creates", "source_evidence"))
})
test_that("legacy_migrations skal matche antallet af elementer", {
  m <- manifest(); m$expected_counts$legacy_migrations <- 2L
  expect_error(validate_reimport_manifest(m), "REIMPORT_MANIFEST_COUNTS_INVALID")
})
test_that("ukendt dependency_class afvises", {
  m <- manifest(); m$operations[[1]]$dependency_class <- "legacy_migrate"
  expect_error(validate_reimport_manifest(m), "REIMPORT_MANIFEST_OPERATIONS_INVALID")
})
test_that("gateway dispatcher legacy_migration og nulstiller change set", {
  calls <- list()
  gateway <- list(call = function(name, ...) {
    calls[[length(calls) + 1L]] <<- name
    switch(name,
      preflight = list(database_identity = "db", actor_id = "11111111-1111-4111-8111-111111111111",
        transaction_read_only = "off", source = manifest()$source, locked_payload_count = 1L),
      authorize = list(id = "22222222-2222-4222-8222-222222222222"),
      preflight_authorization = list(authorization_id = "22222222-2222-4222-8222-222222222222",
        database_identity = "db", source = manifest()$source, manifest_sha256 = sha("a"), preview_sha256 = sha("e")),
      begin_batch = "33333333-3333-4333-8333-333333333333",
      batch_result = list(batch_id = "33333333-3333-4333-8333-333333333333", status = "open", replayed = FALSE, person_id_map = list()),
      legacy_migration = list(binding_id = "x"),
      finalize = list(status = "finalized"),
      invisible(NULL))
  })
  result <- execute_reimport(manifest(), sha("e"), "dry-run", gateway)
  expect_identical(result$status, "finalized")
  expect_true("legacy_migration" %in% calls)
})
