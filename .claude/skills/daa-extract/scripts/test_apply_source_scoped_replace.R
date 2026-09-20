library(testthat)

source("apply_source_scoped_replace_helpers.R")

manifest <- list(
  schema = "source-scoped-replace-v1", source_id = 77,
  record_keys = I("1939:0001"), input_sha256 = paste0(rep("a", 64), collapse = ""),
  dry_run_sha256 = paste0(rep("b", 64), collapse = ""),
  ownership_sha256 = paste0(rep("c", 64), collapse = ""),
  expected_counts = list(narrative_operations = 1L, source_operations = 1L),
  policy_decisions = list(new_records = list(), discontinued_records = list()),
  narrative_operations = list(list(element_id = 9L, person_id = 42L, source_id = 77L,
    record_key = "1939:0001", text = "hemmelig tekst", text_sha256 = digest::digest("hemmelig tekst", algo = "sha256", serialize = FALSE),
    expected_state_sha256 = paste0(rep("d", 64), collapse = ""))),
  source_operations = list(list(action = "replace_owned_facts", record_key = "1939:0001"))
)

test_that("preflight requires a closed verified manifest", {
  expect_equal(ssr_validate_manifest(manifest)$source_id, 77L)
  open_manifest <- manifest
  open_manifest$extra <- TRUE
  expect_error(ssr_validate_manifest(open_manifest), "SOURCE_SCOPED_REPLACE_MANIFEST")
  bad_text <- manifest
  bad_text$narrative_operations[[1]]$text_sha256 <- paste0(rep("e", 64), collapse = "")
  expect_error(ssr_validate_manifest(bad_text), "SOURCE_SCOPED_REPLACE_MANIFEST")
})

test_that("receipt validation never admits text and is bound to DB state", {
  profile <- ssr_profile(manifest, list(database_name = "disposable", system_identifier = "system"))
  receipt <- list(
    receipt_schema = profile$receipt_schema, profile = profile, profile_sha256 = wb_sha256(profile),
    mode = "historical", terminal_status = "committed", input_identity = profile$input_identity,
    database_identity = profile$database_identity,
    authorization_identity = list(mode = profile$authorization_mode, authority_id = "auth", actor_id = "actor"),
    operation_id = "op", observed_counts = profile$expected_counts,
    verified_state = list(schema = profile$postverify_schema, sha256 = paste0(rep("f", 64), collapse = ""))
  )
  expect_silent(ssr_validate_terminal_receipt(receipt, profile))
  receipt$events <- list(list(text = "hemmelig tekst"))
  expect_error(ssr_validate_terminal_receipt(receipt, profile), "WRITER_BATCH_RECEIPT_KEYS_INVALID")
})
