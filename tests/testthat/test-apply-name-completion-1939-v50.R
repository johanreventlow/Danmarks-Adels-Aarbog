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
  expect_identical(profile$profile_sha256,
    "25349caff16f2c13002a4950e80fe8697ffcf49e196dbcd9d1550919caf52fd3")
})

test_that("1939 adapter enriches only the exact SQL legacy authorization token", {
  manifest <- list(source = list(source_id = 3L))
  legacy <- list(
    authorization_id = "11111111-1111-4111-8111-111111111111",
    database_name = "disposable_v2",
    system_identifier = "12345"
  )

  enriched <- legacy_name_completion_authorization(legacy, manifest)
  expect_identical(names(enriched), c("authorization_id", "database_name", "system_identifier", "source"))
  expect_identical(enriched$source, legacy_name_completion_profile(manifest))
  expect_error(
    legacy_name_completion_authorization(c(legacy, list(source = list(id = 4L))), manifest),
    "NAME_COMPLETION_1939_AUTHORIZATION_INVALID"
  )
  expect_error(
    legacy_name_completion_authorization(c(legacy, list(extra = TRUE)), manifest),
    "NAME_COMPLETION_1939_AUTHORIZATION_INVALID"
  )
})

test_that("1939 adapter rejects caller-supplied source before opening its gateway", {
  source_payload <- function(index, row) {
    text <- paste0(row[[3L]], " fixture")
    list(
      element_id = paste0("name-completion:", row[[1L]]),
      source_batch_id = name_completion_source_batch_id,
      source_person_create_element_id = paste0("person-create:", row[[1L]]),
      person_id = row[[2L]], source_id = 3L, edition = "1939",
      source_record_key = row[[1L]], source_persona_id = sprintf("00000000-0000-4000-8000-%012d", index),
      name = row[[3L]], source_span = list(char_from = as.integer(index), char_to = as.integer(index + 1L)),
      page_evidence = list(page_from = row[[4L]], page_to = row[[4L]]),
      verbatim_text = text, verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
      source_payload_sha256 = paste(rep("a", 64L), collapse = ""),
      expected_before = list(staged = TRUE, name_cache_empty = TRUE, name_facts = 0L),
      expected_after = list(name_fact = 1L, selected_assertion = 1L, daa_1939_citation = 1L, conclusion = 1L)
    )
  }
  manifest <- list(
    schema_version = "1939-v50-name-completion-manifest-v1", generator_version = "fixture",
    input_hashes = list(production_manifest_sha256 = name_completion_source_manifest_bytes_sha256,
      production_apply_sha256 = paste(rep("b", 64L), collapse = ""), post_apply_audit_sha256 = paste(rep("c", 64L), collapse = "")),
    source = list(edition = "1939", source_id = 3L), source_batch_id = name_completion_source_batch_id,
    source_manifest_bytes_sha256 = name_completion_source_manifest_bytes_sha256,
    source_manifest_content_sha256 = name_completion_source_manifest_content_sha256,
    operations = Map(source_payload, seq_along(name_completion_rows), name_completion_rows),
    counts = list(name_completions = 8L, operations = 8L),
    expected_changes = list(facts_created = 8L, assertions_created = 8L, citations_created = 8L,
      conclusions_created = 8L, persons_created = 0L, persons_activated = 0L,
      relations_changed = 0L, families_changed = 0L),
    production_authorized = FALSE, cutover_authorized = FALSE
  )
  manifest$manifest_content_sha256 <- canonical_name_completion_sha256(manifest)
  connections <- 0L
  exact_token <- list(authorization_id = "11111111-1111-4111-8111-111111111111",
    database_name = "disposable_v2", system_identifier = "12345")
  expect_error(execute_name_completion(manifest, paste(rep("d", 64L), collapse = ""), "apply",
    list(call = function(...) { connections <<- connections + 1L }),
    c(exact_token, list(source = legacy_name_completion_profile(manifest)))),
    "NAME_COMPLETION_1939_AUTHORIZATION_INVALID")
  expect_identical(connections, 0L)
})

test_that("1939 name-completion files contain no direct database or legacy RPC gateway", {
  adapter_text <- paste(readLines(adapter, warn = FALSE), collapse = "\n")
  cli_text <- paste(readLines(cli, warn = FALSE), collapse = "\n")
  expect_false(grepl("DBI::|RPostgres::|red_[a-z_]*1939_v50", adapter_text))
  expect_false(grepl("DBI::|RPostgres::|red_[a-z_]*1939_v50", cli_text))
  expect_match(adapter_text, "execute_name_completion_generic")
})
