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
    rows = list(list(binding_id = "70000000-0000-0000-0000-000000000001", narrative_id = 11L, person_id = 1L, source_id = 1939L,
      source_record_id = "70000000-0000-0000-0000-000000000011"))
  ))
  legacy <- raw_json(list(
    schema_version = "narrative-legacy-baseline-candidates-v1", database = database,
    rows = list(list(legacy_publication_ref = "70000000-0000-0000-0000-000000000101", narrative_id = 21L, person_id = 1L, source_id = 1939L))
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
    rows = list(list(binding_id = "70000000-0000-0000-0000-000000000001", narrative_id = 11L, person_id = 1L, source_id = 1939L,
      source_record_id = "70000000-0000-0000-0000-000000000011"))
  ))
  legacy_manifest <- raw_json(list(
    schema_version = "narrative-legacy-baseline-manifest-v1", database = database,
    legacy_candidates_sha256 = sha(legacy),
    rows = list(list(legacy_publication_ref = "70000000-0000-0000-0000-000000000101", narrative_id = 21L, person_id = 1L, source_id = 1939L))
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
    record_events = list(list(binding_id = "70000000-0000-0000-0000-000000000001", narrative_id = bit64::as.integer64(11),
      event_id = "70000000-0000-0000-0000-000000000201", publication_state_sha256 = paste(rep("a", 64L), collapse = ""),
      state_sha256 = paste(rep("b", 64L), collapse = ""))),
    legacy_events = list(list(legacy_publication_ref = "70000000-0000-0000-0000-000000000101", narrative_id = bit64::as.integer64(21),
      event_id = "70000000-0000-0000-0000-000000000202", publication_state_sha256 = paste(rep("c", 64L), collapse = ""),
      state_sha256 = paste(rep("d", 64L), collapse = ""))),
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
    public_v2_rows = list(list(person_id = 1L, source_id = 1939L, source_year = 1939L,
      record_order = 1L, source_record_ref = "70000000-0000-0000-0000-000000000901",
      source_label = "DAA 1939", record_label = "Record", narrative_text = "bound",
      citation_label = "DAA", provenance_kind = "source_record"),
    list(person_id = 1L, source_id = 1939L, source_year = 1939L, record_order = NULL,
      source_record_ref = NULL, source_label = "DAA 1939", record_label = "Overgangsdata",
      narrative_text = "bound", citation_label = "DAA 1939, s. 7", provenance_kind = "legacy_narrative")),
    public_legacy_narrative_ids = list(21L),
    bindings = 1L, grandfathered_legacy = 1L, accepted_identities = 2L,
    blocked_new_records = 3L, direct_readers = nrk_postverify_direct_readers(),
    acl = nrk_postverify_required_acl()
  )
  event_state <- list(target = list(person_id = 1L, source_id = 1939L,
      source_record_ref = "70000000-0000-0000-0000-000000000901"),
    source = list(source_year = 1939L, source_label = "DAA 1939"),
    labels = list(record_order = 1L, record_label = "Record", citation_label = "DAA"),
    narrative = list(text = "bound", side = "7"))
  observed$receipt_event_rows <- list(
    list(event_id = result$record_events[[1L]]$event_id, stream_ref = result$record_events[[1L]]$binding_id,
      stream_version = "1", event_type = "baseline", binding_id = result$record_events[[1L]]$binding_id,
      narrative_id = bit64::as.integer64(11), source_id = bit64::as.integer64(1939),
      source_record_id = "70000000-0000-0000-0000-000000000011", legacy_publication_ref = NULL,
      decision_basis = "Godkendt baseline ved contract cutover 70000000-0000-0000-0000-000000000713",
      decided_by_name = "Narrative record cutover", before_state_sha256 = result$record_events[[1L]]$publication_state_sha256,
      after_state_sha256 = result$record_events[[1L]]$publication_state_sha256,
      state_sha256 = result$record_events[[1L]]$state_sha256, before_state = event_state, after_state = event_state),
    list(event_id = result$legacy_events[[1L]]$event_id, stream_ref = result$legacy_events[[1L]]$legacy_publication_ref,
      stream_version = "1", event_type = "baseline", binding_id = NA_character_,
      narrative_id = bit64::as.integer64(21), source_id = bit64::as.integer64(1939),
      source_record_id = NA_character_, legacy_publication_ref = result$legacy_events[[1L]]$legacy_publication_ref,
      decision_basis = "Godkendt grandfathered baseline ved contract cutover 70000000-0000-0000-0000-000000000713",
      decided_by_name = "Narrative record cutover", before_state_sha256 = result$legacy_events[[1L]]$publication_state_sha256,
      after_state_sha256 = result$legacy_events[[1L]]$publication_state_sha256,
      state_sha256 = result$legacy_events[[1L]]$state_sha256, before_state = event_state, after_state = event_state)
  )
  observed$change_set_rows <- list(list(id = bit64::as.integer64(51), actor_navn = "Narrative record cutover",
    actor_rolle = "system", operation = "narrative_record_contract_cutover",
    summary = "Narrative record contract cutover 70000000-0000-0000-0000-000000000713",
    subjekt_synlighed = "offentlig"))
  observed$change_event_rows <- list()
  if (!is.null(drift)) observed[[drift]] <- list()
  list(snapshot = function(...) list(
    identity = verified$database, version = 2L, receipts = list(receipt),
    nonce_receipt_count = 1L,
    source_record_public_refs = setNames(
      list("70000000-0000-0000-0000-000000000901"),
      "70000000-0000-0000-0000-000000000011"
    )[vapply(verified$documents$record_manifest$rows, `[[`, "", "source_record_id")],
    public_v2_refs = observed$public_record_refs, observed = observed
  ))
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

test_that("postverify rejects a full public v2 row drift even when its ref survives", {
  artifacts <- fixture()
  gateway <- fake_gateway(cutover_artifacts(artifacts))
  snapshot <- gateway$snapshot()
  snapshot$observed$public_v2_rows[[1L]]$narrative_text <- "drifted"
  gateway$snapshot <- function(...) snapshot
  expect_error(
    nrk_verify_narrative_record_cutover_postverify(
      cutover_artifacts(artifacts), "70000000-0000-0000-0000-000000000713",
      artifacts$database, gateway
    ),
    "POSTVERIFY_PUBLIC_V2_ROW_MISMATCH", fixed = TRUE
  )
})

test_that("postverify derives v2 ordering independently of receipt event UUID order", {
  event <- function(event_id, source_year, source_id, source_record_ref) list(
    event_id = event_id, binding_id = paste0("binding-", source_record_ref),
    narrative_id = 1L, after_state = list(
      target = list(person_id = 1L, source_id = source_id,
        source_record_ref = source_record_ref),
      source = list(source_year = source_year, source_label = "DAA"),
      labels = list(record_order = 1L, record_label = "Record", citation_label = "DAA"),
      narrative = list(text = "bound", side = "")
    )
  )
  rows <- nrk_postverify_order_v2_rows(list(
    event("00000000-0000-0000-0000-000000000002", 1939L, 9L,
      "70000000-0000-0000-0000-000000000009"),
    event("ffffffff-ffff-ffff-ffff-ffffffffffff", 1940L, 1L,
      "70000000-0000-0000-0000-000000000001"),
    event("00000000-0000-0000-0000-000000000003", NULL, 2L,
      "70000000-0000-0000-0000-000000000002")
  ), integer())
  expect_identical(vapply(rows, `[[`, "", "source_record_ref"), c(
    "70000000-0000-0000-0000-000000000001",
    "70000000-0000-0000-0000-000000000009",
    "70000000-0000-0000-0000-000000000002"
  ))
})

test_that("postverify includes legacy-only people in the public RPC scope", {
  record_manifest <- list(list(person_id = "9007199254740993"))
  legacy_candidates <- list(list(person_id = "9007199254740995"))
  expect_identical(
    nrk_postverify_public_person_ids(record_manifest, legacy_candidates),
    c("9007199254740993", "9007199254740995")
  )
})

test_that("postverify ACL observation rejects absent signatures and default PUBLIC execute", {
  expected <- nrk_postverify_required_acl()
  signatures <- unique(sub("\\|.*$", "", names(expected)))
  missing <- data.frame(
    signature = signatures[-1L], routine_oid = as.character(seq_along(signatures[-1L])),
    owner_oid = "10", role = "PUBLIC", grantee_oid = "0", privilege_type = NA_character_
  )
  expect_error(
    nrk_postverify_acl_observed(missing, expected),
    "POSTVERIFY_ACL_SIGNATURE_MISSING", fixed = TRUE
  )
  public_execute <- data.frame(
    signature = signatures, routine_oid = as.character(seq_along(signatures)),
    owner_oid = "10", role = "PUBLIC", grantee_oid = "0", privilege_type = "EXECUTE"
  )
  expect_error(
    nrk_postverify_acl_observed(public_execute, expected),
    "POSTVERIFY_ACL_UNEXPECTED_GRANT", fixed = TRUE
  )
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

test_that("postverify rejects an additional private event in the receipt change set", {
  artifacts <- fixture()
  gateway <- fake_gateway(cutover_artifacts(artifacts))
  snapshot <- gateway$snapshot()
  extra <- snapshot$observed$receipt_event_rows[[1L]]
  extra$event_id <- "70000000-0000-0000-0000-000000000299"
  snapshot$observed$receipt_event_rows <- c(snapshot$observed$receipt_event_rows, list(extra))
  gateway$snapshot <- function(...) snapshot
  expect_error(
    nrk_verify_narrative_record_cutover_postverify(
      cutover_artifacts(artifacts), "70000000-0000-0000-0000-000000000713",
      artifacts$database, gateway
    ), "POSTVERIFY_RECEIPT_EVENT_ROW_MISMATCH", fixed = TRUE
  )
})

test_that("postverify rejects independently observed poststate drift", {
  artifacts <- fixture()
  cases <- list(
    POSTVERIFY_RECEIPT_EVENT_ROW_MISMATCH = function(snapshot) {
      snapshot$observed$receipt_event_rows[[1L]]$after_state_sha256 <- "wrong"
      snapshot
    },
    POSTVERIFY_CHANGE_SET_ROW_MISMATCH = function(snapshot) {
      snapshot$observed$change_set_rows[[1L]]$operation <- "wrong"
      snapshot
    },
    POSTVERIFY_HIDDEN_LEGACY_PRESENT = function(snapshot) {
      snapshot$observed$hidden_legacy_ids <- list(bit64::as.integer64(99))
      snapshot
    },
    POSTVERIFY_ACCEPTED_IDENTITY_COUNT_MISMATCH = function(snapshot) {
      snapshot$observed$accepted_identities <- 99L
      snapshot
    },
    POSTVERIFY_DIRECT_READER_CLASSIFICATION_MISMATCH = function(snapshot) {
      snapshot$observed$direct_readers <- list()
      snapshot
    },
    POSTVERIFY_ACL_INVENTORY_MISMATCH = function(snapshot) {
      snapshot$observed$acl[[1L]] <- !snapshot$observed$acl[[1L]]
      snapshot
    },
    POSTVERIFY_PUBLIC_V2_ROW_MISMATCH = function(snapshot) {
      snapshot$observed$public_v2_rows <- snapshot$observed$public_v2_rows[1L]
      snapshot
    },
    POSTVERIFY_BINDING_COUNT_MISMATCH = function(snapshot) {
      snapshot$observed$bindings <- NA_integer_
      snapshot
    }
  )
  for (token in names(cases)) {
    gateway <- fake_gateway(cutover_artifacts(artifacts))
    snapshot <- cases[[token]](gateway$snapshot())
    gateway$snapshot <- function(...) snapshot
    expect_error(
      nrk_verify_narrative_record_cutover_postverify(
        cutover_artifacts(artifacts), "70000000-0000-0000-0000-000000000713",
        artifacts$database, gateway
      ), token, fixed = TRUE
    )
  }
})
