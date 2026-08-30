library(testthat)

root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(
  root, ".claude", "skills", "daa-extract", "scripts",
  "writer_batch_contract_helpers.R"
), local = TRUE)

valid_profile <- function(...) {
  profile <- list(
    operation_family = "source-scoped-replace",
    contract_version = "writer-batch-v1",
    execution_kind = "apply",
    reversal_mode = "compensating",
    authorization_mode = "single_use_database_authorization",
    input_identity = list(
      schema_version = "source-scoped-replace-manifest-v1",
      canonical_json_sha256 = strrep("a", 64L)
    ),
    database_identity = list(
      database_name = "daa_writer_batch_test",
      system_identifier = "123456789"
    ),
    schema_contract_version = "narrative-contract-v2",
    scope = list(source_id = "1939"),
    element_ids = c("a", "b"),
    expected_counts = list(narrative_operations = 2L),
    adapter_invariants = list(draft_only = TRUE),
    lock_order = c("narrative_contract", "source_scope", "person", "ledger"),
    receipt_schema = "source-scoped-replace-receipt-v1",
    terminal_statuses = c("committed", "already_applied"),
    postverify_schema = "source-scoped-replace-postverify-v1"
  )
  replacements <- list(...)
  for (name in names(replacements)) profile[[name]] <- replacements[[name]]
  profile
}

test_that("profile validation closes the common writer contract", {
  expect_error(wb_validate_profile(list(operation_family = "x")),
               "WRITER_BATCH_PROFILE_KEYS_INVALID")
  expect_error(wb_validate_profile(valid_profile(execution_kind = "delete")),
               "WRITER_BATCH_EXECUTION_KIND_INVALID")
  expect_equal(wb_sha256(valid_profile(element_ids = c("b", "a"))),
               wb_sha256(valid_profile(element_ids = c("a", "b"))))

  unknown <- valid_profile(); unknown$unreviewed <- TRUE
  expect_error(wb_validate_profile(unknown), "WRITER_BATCH_PROFILE_KEYS_INVALID")
  expect_error(wb_validate_profile(valid_profile(element_ids = c("a", "a"))),
               "WRITER_BATCH_ELEMENT_IDS_INVALID")

  invalid_hash <- valid_profile()
  invalid_hash$input_identity$canonical_json_sha256 <- "not-a-sha256"
  expect_error(wb_validate_profile(invalid_hash), "WRITER_BATCH_HASH_INVALID")
  expect_error(wb_validate_profile(valid_profile(scope = list())),
               "WRITER_BATCH_SCOPE_INVALID")
  expect_error(wb_validate_profile(valid_profile(scope = list(source_id = ""))),
               "WRITER_BATCH_SCOPE_INVALID")
  expect_error(wb_validate_profile(valid_profile(database_identity = list())),
               "WRITER_BATCH_DATABASE_IDENTITY_INVALID")
  expect_error(wb_validate_profile(valid_profile(schema_contract_version = "")),
               "WRITER_BATCH_SCHEMA_CONTRACT_VERSION_INVALID")
  expect_error(wb_validate_profile(valid_profile(terminal_statuses = character())),
               "WRITER_BATCH_TERMINAL_STATUSES_INVALID")
  expect_error(wb_validate_profile(valid_profile(postverify_schema = "")),
               "WRITER_BATCH_POSTVERIFY_SCHEMA_INVALID")
  expect_error(wb_validate_profile(valid_profile(reversal_mode = "undo")),
               "WRITER_BATCH_REVERSAL_MODE_INVALID")
  expect_error(wb_validate_profile(valid_profile(
    execution_kind = "reversal", reversal_mode = "not_supported"
  )), "WRITER_BATCH_PROFILE_COMPATIBILITY_INVALID")
  expect_error(wb_validate_profile(valid_profile(
    execution_kind = "promotion", reversal_mode = "exact_restore"
  )), "WRITER_BATCH_PROFILE_COMPATIBILITY_INVALID")
  expect_error(wb_validate_profile(valid_profile(authorization_mode = "none")),
               "WRITER_BATCH_AUTHORIZATION_MODE_INVALID")
  expect_error(wb_validate_profile(valid_profile(
    execution_kind = "conformance_read_only",
    reversal_mode = "exact_restore",
    authorization_mode = "single_use_database_authorization"
  )), "WRITER_BATCH_PROFILE_COMPATIBILITY_INVALID")
  expect_no_error(wb_validate_profile(valid_profile(
    execution_kind = "conformance_read_only", reversal_mode = "exact_restore",
    authorization_mode = "none"
  )))

  expect_error(wb_validate_profile(valid_profile(expected_counts = list(
    narrative_operations = list(draft_created = 1.5)
  ))), "WRITER_BATCH_EXPECTED_COUNTS_INVALID")
  expect_error(wb_validate_profile(valid_profile(adapter_invariants = list(
    draft_only = list()
  ))), "WRITER_BATCH_ADAPTER_INVARIANTS_INVALID")
})

test_that("canonical JSON preserves precision, names, and contract array shapes", {
  expect_false(identical(
    wb_canonical_json(list(value = 1.00001)),
    wb_canonical_json(list(value = 1.00002))
  ))
  named_values <- wb_canonical_json(list(value = c(alpha = 1L, beta = 2L)))
  expect_match(named_values, '"alpha":1', fixed = TRUE)
  expect_match(named_values, '"beta":2', fixed = TRUE)
  expect_match(
    wb_canonical_json(valid_profile(element_ids = "a")),
    '"element_ids":["a"]', fixed = TRUE
  )
  expect_equal(
    wb_sha256(valid_profile(terminal_statuses = c("committed", "already_applied"))),
    wb_sha256(valid_profile(terminal_statuses = c("already_applied", "committed")))
  )
  expect_error(wb_canonical_json(list(value = factor("x"))),
               "WRITER_BATCH_CANONICAL_VALUE_INVALID")
})

valid_receipt <- function(profile = valid_profile()) {
  list(
    receipt_schema = profile$receipt_schema,
    profile = profile,
    profile_sha256 = wb_sha256(profile),
    mode = "historical",
    terminal_status = "committed",
    input_identity = profile$input_identity,
    database_identity = profile$database_identity,
    authorization_identity = list(
      mode = profile$authorization_mode,
      authority_id = "authorization-1",
      actor_id = "editor-1"
    ),
    operation_id = "batch-1",
    observed_counts = profile$expected_counts,
    verified_state = list(
      schema = profile$postverify_schema,
      sha256 = strrep("b", 64L)
    )
  )
}

test_that("historical receipts remain valid while current-state verification reports drift", {
  profile <- valid_profile()
  receipt <- valid_receipt(profile)
  expect_no_error(wb_validate_receipt(receipt, profile, "historical"))

  matching_state <- list(
    schema = profile$postverify_schema,
    sha256 = strrep("b", 64L)
  )
  expect_no_error(wb_validate_current_state(matching_state, receipt))

  later_state <- list(schema = profile$postverify_schema, sha256 = strrep("c", 64L))
  expect_no_error(wb_validate_receipt(receipt, profile, "historical"))
  expect_error(wb_validate_current_state(later_state, receipt),
               "WRITER_BATCH_CURRENT_STATE_DRIFT")

  expect_error(wb_validate_current_state(
    matching_state, list(postverify_sha256 = strrep("b", 64L))
  ), "WRITER_BATCH_RECEIPT_KEYS_INVALID")
})

test_that("receipt binds its profile, identities, authorization, operation, counts, and state", {
  profile <- valid_profile()
  receipt <- valid_receipt(profile)

  unknown <- receipt; unknown$unreviewed <- TRUE
  expect_error(wb_validate_receipt(unknown, profile, "historical"),
               "WRITER_BATCH_RECEIPT_KEYS_INVALID")
  missing <- receipt; missing$operation_id <- NULL
  expect_error(wb_validate_receipt(missing, profile, "historical"),
               "WRITER_BATCH_RECEIPT_KEYS_INVALID")
  wrong_authorization <- receipt
  wrong_authorization$authorization_identity$mode <- "actor_bound_preview_authorization"
  expect_error(wb_validate_receipt(wrong_authorization, profile, "historical"),
               "WRITER_BATCH_RECEIPT_AUTHORIZATION_INVALID")
  wrong_operation <- receipt; wrong_operation$operation_id <- ""
  expect_error(wb_validate_receipt(wrong_operation, profile, "historical"),
               "WRITER_BATCH_RECEIPT_OPERATION_ID_INVALID")
  wrong_profile_hash <- receipt; wrong_profile_hash$profile_sha256 <- strrep("c", 64L)
  expect_error(wb_validate_receipt(wrong_profile_hash, profile, "historical"),
               "WRITER_BATCH_RECEIPT_PROFILE_DRIFT")
  wrong_identity <- receipt
  wrong_identity$database_identity$system_identifier <- "987654321"
  expect_error(wb_validate_receipt(wrong_identity, profile, "historical"),
               "WRITER_BATCH_RECEIPT_IDENTITY_DRIFT")
  wrong_terminal <- receipt; wrong_terminal$terminal_status <- "rolled_back"
  expect_error(wb_validate_receipt(wrong_terminal, profile, "historical"),
               "WRITER_BATCH_RECEIPT_TERMINAL_STATUS_INVALID")
  wrong_counts <- receipt; wrong_counts$observed_counts$narrative_operations <- 999L
  expect_error(wb_validate_receipt(wrong_counts, profile, "historical"),
               "WRITER_BATCH_RECEIPT_COUNTS_INVALID")
  wrong_state <- receipt; wrong_state$verified_state$schema <- "other-postverify-v1"
  expect_error(wb_validate_receipt(wrong_state, profile, "historical"),
               "WRITER_BATCH_RECEIPT_POSTVERIFY_INVALID")
})
