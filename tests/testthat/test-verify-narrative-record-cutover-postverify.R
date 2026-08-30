library(testthat)

root <- normalizePath(file.path(getwd(), "..", ".."))
script <- file.path(
  root, ".claude", "skills", "daa-extract", "scripts",
  "verify_narrative_record_cutover_postverify.R"
)
source(script, local = TRUE)

raw_json <- function(value) charToRaw(paste0(
  jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", na = "null"), "\n"
))

sha <- function(raw) digest::digest(raw, algo = "sha256", serialize = FALSE)

fixture <- function() {
  database <- list(database_name = "daa_task13", system_identifier = "7713")
  record <- raw_json(list(
    schema_version = "narrative-record-baseline-candidates-v1", database = database,
    rows = list(list(binding_id = "70000000-0000-0000-0000-000000000001", narrative_id = 11L, person_id = 1L,
      source_record_id = "70000000-0000-0000-0000-000000000011"))
  ))
  legacy <- raw_json(list(
    schema_version = "narrative-legacy-baseline-candidates-v1", database = database,
    rows = list(list(legacy_publication_ref = "70000000-0000-0000-0000-000000000101", narrative_id = 21L))
  ))
  inventory <- raw_json(list(
    schema_version = "narrative-record-cutover-inventory-v1", database = database,
    record_candidate_ids = list("70000000-0000-0000-0000-000000000001"),
    legacy_candidate_ids = list(21L), counts_by_source = list(),
    accepted_identity_count = 2L, identity_blocked_record_count = 3L,
    classified_direct_readers = nrk_postverify_direct_readers()
  ))
  record_manifest <- raw_json(list(
    schema_version = "narrative-record-baseline-manifest-v1", database = database,
    record_candidates_sha256 = sha(record),
    rows = list(list(binding_id = "70000000-0000-0000-0000-000000000001", narrative_id = 11L, person_id = 1L,
      source_record_id = "70000000-0000-0000-0000-000000000011"))
  ))
  legacy_manifest <- raw_json(list(
    schema_version = "narrative-legacy-baseline-manifest-v1", database = database,
    legacy_candidates_sha256 = sha(legacy),
    rows = list(list(legacy_publication_ref = "70000000-0000-0000-0000-000000000101", narrative_id = 21L))
  ))
  approval <- raw_json(list(
    schema_version = "narrative-record-cutover-approval-v1", database = database,
    input_hashes = list(
      record_candidates_sha256 = sha(record), legacy_candidates_sha256 = sha(legacy),
      inventory_sha256 = sha(inventory), record_manifest_sha256 = sha(record_manifest),
      legacy_manifest_sha256 = sha(legacy_manifest)
    ),
    record_approved_ids = list("70000000-0000-0000-0000-000000000001"),
    legacy_keep_ids = list(21L), legacy_hide_ids = list()
  ))
  list(record = record, legacy = legacy, inventory = inventory,
       record_manifest = record_manifest, legacy_manifest = legacy_manifest,
       approval = approval, database = database)
}

fake_gateway <- function(artifacts, drift = NULL) {
  verified <- nrk_verify_cutover_artifacts(artifacts)
  result <- list(
    nonce = "70000000-0000-0000-0000-000000000713", database = verified$database,
    input_hashes = verified$hashes, contract_version_after = 2L,
    change_set_id = 51L,
    record_events = list(list(binding_id = "70000000-0000-0000-0000-000000000001", narrative_id = 11L)),
    legacy_events = list(list(legacy_publication_ref = "70000000-0000-0000-0000-000000000101", narrative_id = 21L)),
    legacy_hidden_ids = list()
  )
  receipt <- list(nonce = result$nonce, database = verified$database,
                  input_hashes = verified$hashes, result = result,
                  result_raw = jsonlite::toJSON(result, auto_unbox = TRUE),
                  result_sha256 = sha(charToRaw(jsonlite::toJSON(result, auto_unbox = TRUE))))
  observed <- list(
    record_binding_ids = list("70000000-0000-0000-0000-000000000001"),
    legacy_narrative_ids = list(21L), hidden_legacy_ids = list(),
    baseline_event_count = 2L, change_set_id = 51L, change_set_event_count = 2L,
    public_record_refs = list("70000000-0000-0000-0000-000000000901"),
    public_legacy_narrative_ids = list(21L),
    bindings = 1L, grandfathered_legacy = 1L, accepted_identities = 2L,
    blocked_new_records = 3L, direct_readers = nrk_postverify_direct_readers(),
    acl = nrk_postverify_required_acl()
  )
  if (!is.null(drift)) observed[[drift]] <- list()
  list(
    identity = function() verified$database,
    version = function() 2L,
    exact_receipts = function(...) list(receipt),
    nonce_receipt_count = function(...) 1L,
    source_record_public_refs = function(ids) setNames(
      list("70000000-0000-0000-0000-000000000901"),
      "70000000-0000-0000-0000-000000000011"
    )[ids],
    public_v2_refs = function(...) observed$public_record_refs,
    observed = function(...) observed
  )
}

cutover_artifacts <- function(bundle) bundle[c(
  "record", "legacy", "inventory", "record_manifest", "legacy_manifest", "approval"
)]

test_that("postverify proves the complete receipt-bound production shape", {
  artifacts <- fixture()
  outcome <- nrk_verify_narrative_record_cutover_postverify(
    cutover_artifacts(artifacts), "70000000-0000-0000-0000-000000000713", artifacts$database,
    fake_gateway(cutover_artifacts(artifacts))
  )
  expect_identical(outcome$status, "postverify_passed")
  expect_identical(outcome$receipt$result$change_set_id, 51L)
})

test_that("postverify fails closed when public v2 source-record refs drift", {
  artifacts <- fixture()
  expect_error(
    nrk_verify_narrative_record_cutover_postverify(
      cutover_artifacts(artifacts), "70000000-0000-0000-0000-000000000713", artifacts$database,
      fake_gateway(cutover_artifacts(artifacts), "public_record_refs")
    ),
    "POSTVERIFY_PUBLIC_RECORD_REF_SET_MISMATCH", fixed = TRUE
  )
})
