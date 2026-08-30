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
  expect_error(wb_validate_profile(valid_profile(authorization_mode = "none")),
               "WRITER_BATCH_AUTHORIZATION_MODE_INVALID")
  expect_no_error(wb_validate_profile(valid_profile(
    execution_kind = "conformance_read_only", authorization_mode = "none"
  )))
})

valid_receipt <- function(profile = valid_profile()) {
  list(
    receipt_schema = profile$receipt_schema,
    profile_sha256 = wb_sha256(profile),
    mode = "historical",
    terminal_status = "committed",
    input_identity = profile$input_identity,
    database_identity = profile$database_identity,
    observed_counts = profile$expected_counts,
    postverify_sha256 = strrep("b", 64L)
  )
}

test_that("historical receipts remain valid while current-state verification reports drift", {
  profile <- valid_profile()
  receipt <- valid_receipt(profile)
  expect_no_error(wb_validate_receipt(receipt, profile, "historical"))

  later_state <- list(postverify_sha256 = strrep("c", 64L))
  expect_no_error(wb_validate_receipt(receipt, profile, "historical"))
  expect_error(wb_validate_current_state(later_state, receipt),
               "WRITER_BATCH_CURRENT_STATE_DRIFT")
})
