library(testthat)

root <- normalizePath(file.path(getwd(), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"), local = TRUE)

sha <- function(letter) paste(rep(letter, 64L), collapse = "")

reimport_manifest <- function() {
  list(
    manifest_content_sha256 = sha("a"),
    source = list(
      id = 17L,
      profile_id = "test-reimport-profile-v1",
      profile_sha256 = sha("b")
    ),
    expected_counts = list(source_evidence = 1L, person_creates = 0L, canonical_delta = 0L),
    operations = list(list(
      element_id = "source-evidence:fixture-1",
      dependency_class = "source_evidence",
      source_record_key = "fixture-1",
      payload_sha256 = sha("c")
    ))
  )
}

reimport_gateway <- function(manifest, preflight = NULL) {
  calls <- list()
  sql <- c(
    preflight = "SELECT current_database(), current_setting('transaction_read_only')",
    authorize = "SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9,$10)",
    preflight_authorization = "SELECT public.red_preflight_reimport_authorization($1,$2,$3)",
    begin_batch = "SELECT public.red_begin_reimport($1,$2,$3)",
    batch_result = "SELECT public.red_reimport_batch_result($1,$2)",
    source_evidence = "SELECT public.red_apply_reimport_source_evidence($1,$2,$3::jsonb)",
    person_create = "SELECT public.red_apply_reimport_person_create($1,$2,$3::jsonb)",
    finalize = "SELECT public.red_finalize_reimport($1)"
  )
  gateway <- list(call = function(name, ...) {
    statement <- if (name %in% names(sql)) sql[[name]] else name
    calls[[name]] <<- c(calls[[name]], statement)
    if (identical(name, "preflight")) {
      return(preflight %||% list(
        database_identity = "reimport-test:system-1",
        actor_id = "11111111-1111-4111-8111-111111111111",
        transaction_read_only = "off",
        source = manifest$source,
        locked_payload_count = 1L
      ))
    }
    if (identical(name, "authorize")) return(list(id = "22222222-2222-4222-8222-222222222222"))
    if (identical(name, "preflight_authorization")) return(list(
      authorization_id = "22222222-2222-4222-8222-222222222222",
      database_identity = "reimport-test:system-1", source = manifest$source,
      manifest_sha256 = manifest$manifest_content_sha256, preview_sha256 = list(...)[[3L]]
    ))
    if (identical(name, "begin_batch")) return("33333333-3333-4333-8333-333333333333")
    if (identical(name, "batch_result")) return(list(
      batch_id = "33333333-3333-4333-8333-333333333333", status = "open",
      replayed = FALSE, person_id_map = list()))
    if (identical(name, "person_create")) return(91L)
    if (identical(name, "finalize")) return(list(status = "finalized"))
    invisible(NULL)
  })
  list(gateway = gateway, calls = function() calls)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

test_that("reimport manifest rejects incomplete or malformed profile identity before gateway use", {
  manifest <- reimport_manifest()
  missing <- manifest
  missing$source$profile_id <- NULL
  gateway <- reimport_gateway(manifest)
  expect_error(execute_reimport(missing, sha("d"), "dry-run", gateway$gateway),
    "REIMPORT_MANIFEST_PROFILE_INVALID")
  expect_length(gateway$calls(), 0L)

  malformed <- manifest
  malformed$source$profile_sha256 <- "not-a-sha256"
  expect_error(execute_reimport(malformed, sha("d"), "dry-run", gateway$gateway),
    "REIMPORT_MANIFEST_PROFILE_INVALID")
  expect_length(gateway$calls(), 0L)
})

test_that("reimport refuses a database profile mismatch before authorization", {
  manifest <- reimport_manifest()
  gateway <- reimport_gateway(manifest, list(
    database_identity = "reimport-test:system-1",
    actor_id = "11111111-1111-4111-8111-111111111111",
    transaction_read_only = "off",
    source = utils::modifyList(manifest$source, list(profile_sha256 = sha("e"))),
    locked_payload_count = 1L
  ))
  expect_error(execute_reimport(manifest, sha("d"), "dry-run", gateway$gateway),
    "REIMPORT_DATABASE_PROFILE_MISMATCH")
  expect_true("preflight" %in% names(gateway$calls()))
  expect_false("authorize" %in% names(gateway$calls()))
})

test_that("reimport rejects an authorization whose server profile differs from the manifest", {
  manifest <- reimport_manifest()
  gateway <- reimport_gateway(manifest)
  original <- gateway$gateway$call
  gateway$gateway$call <- function(name, ...) {
    if (identical(name, "preflight_authorization")) return(list(
      authorization_id = "22222222-2222-4222-8222-222222222222",
      database_identity = "reimport-test:system-1",
      source = utils::modifyList(manifest$source, list(profile_sha256 = sha("f"))),
      manifest_sha256 = manifest$manifest_content_sha256, preview_sha256 = sha("d")
    ))
    original(name, ...)
  }
  expect_error(execute_reimport(manifest, sha("d"), "dry-run", gateway$gateway),
    "REIMPORT_AUTHORIZATION_BINDING_INVALID")
  expect_false("begin_batch" %in% names(gateway$calls()))
})

test_that("reimport rejects an authorization preflight bound to a different database identity", {
  manifest <- reimport_manifest()
  gateway <- reimport_gateway(manifest)
  original <- gateway$gateway$call
  gateway$gateway$call <- function(name, ...) {
    if (identical(name, "preflight_authorization")) return(list(
      authorization_id = "22222222-2222-4222-8222-222222222222",
      database_identity = "reimport-test:other-system", source = manifest$source,
      manifest_sha256 = manifest$manifest_content_sha256, preview_sha256 = sha("d")
    ))
    original(name, ...)
  }
  expect_error(execute_reimport(manifest, sha("d"), "dry-run", gateway$gateway),
    "REIMPORT_AUTHORIZATION_BINDING_INVALID")
  expect_false("begin_batch" %in% names(gateway$calls()))
})

test_that("reimport gateway uses only generic writer RPCs", {
  manifest <- reimport_manifest()
  gateway <- reimport_gateway(manifest)
  result <- execute_reimport(manifest, sha("d"), "dry-run", gateway$gateway)
  calls <- gateway$calls()
  expect_identical(result$status, "finalized")
  expect_match(calls[["authorize"]], "red_authorize_reimport")
  expect_false(any(grepl("1939_v50|source_id=3", unlist(calls))))
})

test_that("reimport projects canonical-delta validation out of writer counts", {
  manifest <- reimport_manifest()
  expect_identical(reimport_writer_expected_counts(manifest),
    list(person_creates = 0L, source_evidence = 1L))
})

test_that("reimport accepts semantically identical expected counts in another JSON key order", {
  manifest <- reimport_manifest()
  manifest$expected_counts <- list(
    canonical_delta = 0L,
    person_creates = 0L,
    source_evidence = 1L
  )

  expect_no_error(validate_reimport_manifest(manifest))
})

test_that("reimport rejects malformed public batch-result envelopes", {
  result <- list(batch_id = "33333333-3333-4333-8333-333333333333",
    status = c("open", "finalized"), replayed = FALSE, person_id_map = list())
  expect_error(validate_reimport_batch_result(result, result$batch_id),
    "REIMPORT_BATCH_RESULT_INVALID")
})

test_that("reimport returns an existing finalized batch without replaying operations", {
  manifest <- reimport_manifest()
  calls <- character()
  gateway <- list(call = function(name, ...) {
    calls <<- c(calls, name)
    switch(name,
      connect = invisible(NULL), begin = invisible(NULL), advisory_lock = invisible(NULL),
      preflight = list(database_identity = "reimport-test:system-1",
        actor_id = "11111111-1111-4111-8111-111111111111", transaction_read_only = "off",
        source = manifest$source, locked_payload_count = 1L),
      authorize = list(id = "22222222-2222-4222-8222-222222222222"),
      preflight_authorization = list(authorization_id = "22222222-2222-4222-8222-222222222222",
        database_identity = "reimport-test:system-1", source = manifest$source,
        manifest_sha256 = manifest$manifest_content_sha256, preview_sha256 = sha("d")),
      begin_batch = "33333333-3333-4333-8333-333333333333",
      batch_result = list(batch_id = "33333333-3333-4333-8333-333333333333",
        status = "finalized", replayed = TRUE, person_id_map = list("fixture-1" = 91L)),
      commit = invisible(NULL), rollback = invisible(NULL),
      stop("unexpected gateway operation", call. = FALSE)
    )
  })
  result <- execute_reimport(manifest, sha("d"), "apply", gateway,
    list(id = "22222222-2222-4222-8222-222222222222"))
  expect_identical(result$status, "already_applied")
  expect_identical(result$person_id_map, list("fixture-1" = 91L))
  expect_true("batch_result" %in% calls)
  expect_false("source_evidence" %in% calls)
})

# --- 4.4: klausul-niveauet er ikke dækket af expected_counts ------------------
# Batchens expected_counts tæller ELEMENTER. Writeren returnerer
# interpretations_written pr. element, og kun den kontrol fanger et tabt claim.
proposal_manifest <- function() {
  list(
    manifest_content_sha256 = sha("a"),
    source = list(id = 17L, profile_id = "test-proposal-profile-v1", profile_sha256 = sha("b")),
    expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L,
                           interpretation_proposals = 1L),
    operations = list(list(
      element_id = "interpretation-proposal:fixture-1",
      dependency_class = "interpretation_proposal",
      source_record_key = "fixture-1",
      runner_manifest_sha256 = sha("c"),
      model_version = "test-model",
      prompt_version = sha("d"),
      claims = list(list(claim_id = "c1"), list(claim_id = "c2"))
    ))
  )
}

proposal_gateway <- function(manifest, written) {
  base <- reimport_gateway(manifest)
  inner <- base$gateway$call
  list(gateway = list(call = function(name, ...) {
    if (identical(name, "interpretation_proposal"))
      return(list(interpretations_written = written, clauses_dispositioned = 1L,
                  run_id = "44444444-4444-4444-8444-444444444444"))
    inner(name, ...)
  }))
}

test_that("interpretation_proposal afstemmer writerens claim-antal mod manifestets", {
  manifest <- proposal_manifest()
  expect_error(
    execute_reimport(manifest, sha("e"), "dry-run", proposal_gateway(manifest, 1L)$gateway),
    "REIMPORT_WRITER_INTERPRETATION_COUNT_MISMATCH")

  result <- execute_reimport(manifest, sha("e"), "dry-run", proposal_gateway(manifest, 2L)$gateway)
  expect_identical(result$status, "finalized")
  expect_false(result$committed)
})
