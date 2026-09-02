library(testthat)

root <- normalizePath(file.path(getwd(), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_name_completion_helpers.R"), local = TRUE)

sha <- function(letter) paste(rep(letter, 64L), collapse = "")
`%||%` <- function(x, y) if (is.null(x)) y else x

name_completion_manifest <- function() {
  list(
    manifest_content_sha256 = sha("a"),
    source = list(
      id = 17L,
      profile_id = "test-reimport-profile-v1",
      profile_sha256 = sha("b")
    ),
    source_batch_id = "33333333-3333-4333-8333-333333333333",
    source_manifest_bytes_sha256 = sha("c"),
    source_manifest_content_sha256 = sha("d"),
    expected_counts = list(name_completions = 1L, operations = 1L),
    operations = list(list(
      element_id = "name-completion:fixture-1",
      person_id = 91L,
      source_record_key = "fixture-1",
      payload_sha256 = sha("e")
    ))
  )
}

name_completion_gateway <- function(manifest, preflight = NULL) {
  calls <- list()
  sql <- c(
    preflight = "SELECT current_database(), current_setting('transaction_read_only')",
    authorize = "SELECT public.red_authorize_reimport_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)",
    begin_batch = "SELECT public.red_begin_reimport_name_completion($1,$2,$3)",
    name_completion = "SELECT public.red_apply_reimport_name_completion($1,$2,$3::jsonb)",
    finalize = "SELECT public.red_finalize_reimport_name_completion($1)"
  )
  gateway <- list(call = function(name, ...) {
    statement <- if (name %in% names(sql)) sql[[name]] else name
    calls[[name]] <<- c(calls[[name]], statement)
    if (identical(name, "preflight")) {
      return(preflight %||% list(
        database_identity = "completion-test:system-1",
        actor_id = "11111111-1111-4111-8111-111111111111",
        transaction_read_only = "off",
        source = manifest$source,
        locked_payload_count = 1L
      ))
    }
    if (identical(name, "authorize")) return(list(
      authorization_id = "22222222-2222-4222-8222-222222222222",
      database_name = "completion-test", system_identifier = "system-1", source = manifest$source
    ))
    if (identical(name, "preflight_authorization")) return(list(
      valid = TRUE, database_name = "completion-test", system_identifier = "system-1",
      source_batch_id = manifest$source_batch_id, manifest_sha256 = list(...)[[3L]]
    ))
    if (identical(name, "begin_batch")) return("44444444-4444-4444-8444-444444444444")
    if (identical(name, "finalize")) return(list(
      batch_id = "44444444-4444-4444-8444-444444444444", status = "finalized",
      counts = list(name_completions = 1L, operations = 1L),
      result_map = list("name-completion:fixture-1" = list(
        person_id = 91L, fact_id = 1L, assertion_id = 2L, citation_id = 3L, conclusion_id = 4L
      ))
    ))
    invisible(NULL)
  })
  list(gateway = gateway, calls = function() calls)
}

test_that("name-completion manifest rejects incomplete or malformed profile identity before gateway use", {
  manifest <- name_completion_manifest()
  missing <- manifest
  missing$source$id <- NULL
  gateway <- name_completion_gateway(manifest)
  expect_error(execute_name_completion(missing, sha("a"), "dry-run", gateway$gateway),
    "REIMPORT_NAME_COMPLETION_MANIFEST_PROFILE_INVALID")
  expect_length(gateway$calls(), 0L)

  malformed <- manifest
  malformed$source$profile_sha256 <- "not-a-sha256"
  expect_error(execute_name_completion(malformed, sha("a"), "dry-run", gateway$gateway),
    "REIMPORT_NAME_COMPLETION_MANIFEST_PROFILE_INVALID")
  expect_length(gateway$calls(), 0L)
})

test_that("name completion refuses a database profile mismatch before authorization", {
  manifest <- name_completion_manifest()
  gateway <- name_completion_gateway(manifest, list(
    database_identity = "completion-test:system-1",
    actor_id = "11111111-1111-4111-8111-111111111111",
    transaction_read_only = "off",
    source = utils::modifyList(manifest$source, list(profile_sha256 = sha("f"))),
    locked_payload_count = 1L
  ))
  expect_error(execute_name_completion(manifest, sha("a"), "dry-run", gateway$gateway),
    "REIMPORT_NAME_COMPLETION_DATABASE_PROFILE_MISMATCH")
  expect_true("preflight" %in% names(gateway$calls()))
  expect_false("authorize" %in% names(gateway$calls()))
})

test_that("name completion rejects a server authorization profile mismatch before child begin", {
  manifest <- name_completion_manifest()
  gateway <- name_completion_gateway(manifest)
  original <- gateway$gateway$call
  gateway$gateway$call <- function(name, ...) {
    if (identical(name, "authorize")) return(list(
      authorization_id = "22222222-2222-4222-8222-222222222222",
      database_name = "completion-test", system_identifier = "system-1",
      source = utils::modifyList(manifest$source, list(profile_id = "other"))
    ))
    original(name, ...)
  }
  expect_error(execute_name_completion(manifest, sha("a"), "dry-run", gateway$gateway),
    "REIMPORT_NAME_COMPLETION_AUTHORIZATION_REQUIRED")
  expect_false("preflight_authorization" %in% names(gateway$calls()))
})

test_that("name completion rejects an authorization preflight from another system identity", {
  manifest <- name_completion_manifest()
  gateway <- name_completion_gateway(manifest)
  original <- gateway$gateway$call
  gateway$gateway$call <- function(name, ...) {
    if (identical(name, "preflight_authorization")) return(list(
      valid = TRUE, database_name = "completion-test", system_identifier = "other-system",
      source_batch_id = manifest$source_batch_id, manifest_sha256 = sha("a")
    ))
    original(name, ...)
  }
  expect_error(execute_name_completion(manifest, sha("a"), "dry-run", gateway$gateway),
    "REIMPORT_NAME_COMPLETION_PREFLIGHT_INVALID")
  expect_false("begin_batch" %in% names(gateway$calls()))
})

test_that("name completion gateway uses only generic writer RPCs", {
  manifest <- name_completion_manifest()
  gateway <- name_completion_gateway(manifest)
  result <- execute_name_completion(manifest, sha("a"), "dry-run", gateway$gateway)
  calls <- gateway$calls()
  expect_identical(result$status, "finalized")
  expect_match(calls[["authorize"]], "red_authorize_reimport_name_completion")
  expect_false(any(grepl("1939_v50|source_id=3", unlist(calls))))
})
