library(testthat)

root <- normalizePath(file.path(getwd(), "..", ".."))
helpers <- file.path(
  root, ".claude", "skills", "daa-extract", "scripts",
  "apply_narrative_record_cutover_helpers.R"
)
source(helpers, local = TRUE)

sha <- function(raw) digest::digest(raw, algo = "sha256", serialize = FALSE)
raw_json <- function(value) charToRaw(paste0(
  jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", na = "null"), "\n"
))

artifact_fixture <- function() {
  database <- list(database_name = "daa_task7", system_identifier = "7657242220770903427")
  candidates <- list(
    record = raw_json(list(
      schema_version = "narrative-record-baseline-candidates-v1",
      database = database, rows = list()
    )),
    legacy = raw_json(list(
      schema_version = "narrative-legacy-baseline-candidates-v1",
      database = database, rows = list()
    )),
    inventory = raw_json(list(
      schema_version = "narrative-record-cutover-inventory-v1",
      database = database, record_candidate_ids = list(), legacy_candidate_ids = list(),
      counts_by_source = list(), accepted_identity_count = 0L,
      identity_blocked_record_count = 0L, classified_direct_readers = list()
    ))
  )
  manifests <- list(
    record_manifest = raw_json(list(
      schema_version = "narrative-record-baseline-manifest-v1", database = database,
      record_candidates_sha256 = sha(candidates$record), rows = list()
    )),
    legacy_manifest = raw_json(list(
      schema_version = "narrative-legacy-baseline-manifest-v1", database = database,
      legacy_candidates_sha256 = sha(candidates$legacy), rows = list()
    ))
  )
  approval <- raw_json(list(
    schema_version = "narrative-record-cutover-approval-v1", database = database,
    input_hashes = list(
      approval_decisions_sha256 = strrep("a", 64),
      record_candidates_sha256 = sha(candidates$record),
      legacy_candidates_sha256 = sha(candidates$legacy),
      inventory_sha256 = sha(candidates$inventory),
      record_manifest_sha256 = sha(manifests$record_manifest),
      legacy_manifest_sha256 = sha(manifests$legacy_manifest)
    ),
    record_approved_ids = list(), record_approved_rows = list(),
    legacy_keep_ids = list(), legacy_keep_rows = list(),
    legacy_hide_ids = list(), legacy_hide_rows = list(),
    counts = list(record_approved = 0L, legacy_candidates = 0L,
                  legacy_keep = 0L, legacy_hide = 0L)
  ))
  c(candidates, manifests, list(approval = approval))
}

fake_cutover_gateway <- function(commit_unknown = FALSE, receipt_override = NULL) {
  active <- FALSE
  committed <- FALSE
  log <- list()
  before <- list(version = 1L, receipt_count = 0L, event_count = 0L,
                 legacy_count = 0L, sequence = 40L)
  kernel_result <- list(
    nonce = "70000000-0000-0000-0000-000000000701",
    contract_version_after = 2L, record_events = list(), legacy_events = list(),
    sequence = list(before = 40L, floor = 41L, after = 41L)
  )
  receipt <- NULL
  list(
    identity = function() list(
      database_name = "daa_task7", system_identifier = "7657242220770903427"
    ),
    version = function() if (committed) 2L else 1L,
    snapshot = function() if (committed) {
      list(version = 2L, receipt_count = 1L, event_count = 0L,
           legacy_count = 0L, sequence = 41L)
    } else before,
    begin = function() { active <<- TRUE; log[[length(log) + 1L]] <<- "begin" },
    kernel = function(arguments) {
      log[[length(log) + 1L]] <<- list(kernel = arguments)
      resolved_result <- kernel_result
      resolved_result$database <- arguments$database
      resolved_result$input_hashes <- arguments$hashes
      receipt <<- nrk_receipt_from_result(arguments, resolved_result)
      resolved_result
    },
    commit = function() {
      committed <<- TRUE
      active <<- FALSE
      log[[length(log) + 1L]] <<- "commit"
      if (commit_unknown) stop("synthetic lost commit acknowledgement")
    },
    reconnect = function() {
      log[[length(log) + 1L]] <<- "reconnect"
      invisible(NULL)
    },
    rollback = function() {
      active <<- FALSE
      log[[length(log) + 1L]] <<- "rollback"
    },
    exact_receipts = function(nonce, hashes, database) {
      candidate <- receipt_override %||% receipt
      if (is.null(candidate) || !identical(candidate$nonce, nonce) ||
          !identical(candidate$input_hashes, hashes) ||
          !identical(candidate$database, database)) return(list())
      list(candidate)
    },
    nonce_receipt_count = function(nonce) as.integer(!is.null(receipt_override %||% receipt)),
    active = function() active,
    log = function() log
  )
}

test_that("artifact verification binds all six raw hashes and exact DB identity", {
  artifacts <- artifact_fixture()
  verified <- nrk_verify_cutover_artifacts(artifacts)
  expect_identical(sort(names(verified$hashes)), sort(c(
    "record_candidates_sha256", "legacy_candidates_sha256",
    "record_manifest_sha256", "legacy_manifest_sha256",
    "inventory_sha256", "approval_sha256"
  )))
  expect_identical(verified$database$database_name, "daa_task7")
  drift <- artifacts
  drift$inventory <- c(drift$inventory, charToRaw(" "))
  expect_error(nrk_verify_cutover_artifacts(drift), "CUTOVER_ARTIFACT_HASH_MISMATCH",
               fixed = TRUE)
})

test_that("preflight runs the real kernel only inside rollback", {
  artifacts <- artifact_fixture()
  gateway <- fake_cutover_gateway()
  result <- nrk_cutover_execute(
    "preflight", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", gateway,
    receipt_publisher = function(...) fail("preflight published a receipt")
  )
  expect_identical(result$status, "preflight_rolled_back")
  expect_identical(gateway$log()[[1L]], "begin")
  expect_true(is.list(gateway$log()[[2L]]) && "kernel" %in% names(gateway$log()[[2L]]))
  expect_identical(gateway$log()[[3L]], "rollback")
  expect_identical(gateway$snapshot()$version, 1L)
})

test_that("rollback proves exact before-state restoration", {
  artifacts <- artifact_fixture()
  gateway <- fake_cutover_gateway()
  result <- nrk_cutover_execute(
    "rollback", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", gateway,
    receipt_publisher = function(...) fail("rollback published a receipt")
  )
  expect_identical(result$status, "rollback_verified")
  expect_identical(result$before, result$after)
  expect_identical(tail(gateway$log(), 1L)[[1L]], "rollback")
})

test_that("apply commits then resolves and publishes the exact receipt", {
  artifacts <- artifact_fixture()
  gateway <- fake_cutover_gateway()
  published <- NULL
  result <- nrk_cutover_execute(
    "apply", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", gateway,
    receipt_publisher = function(receipt, recover) {
      published <<- list(receipt = receipt, recover = recover)
    }
  )
  expect_identical(result$status, "committed")
  expect_false(published$recover)
  expect_identical(published$receipt$nonce,
                   "70000000-0000-0000-0000-000000000701")
  expect_identical(gateway$version(), 2L)
  expect_identical(gateway$log()[[4L]], "reconnect")
})

test_that("DB result parsing and receipt publication preserve bigint beyond JS range", {
  result <- .nrk_parse_cutover_result_json(paste0(
    '{"change_set_id":9007199254740993,"contract_version_after":2,',
    '"legacy_events":[{"event_id":"70000000-0000-0000-0000-000000000794",',
    '"narrative_id":9007199254740995}],',
    '"legacy_hidden_ids":[9007199254740996],"record_events":[],',
    '"sequence":{"after":9007199254740999,"before":9007199254740997,',
    '"floor":9007199254740998}}'
  ))
  expect_s3_class(result$change_set_id, "integer64")
  expect_identical(as.character(result$change_set_id), "9007199254740993")
  expect_identical(
    result$legacy_events[[1L]]$event_id,
    "70000000-0000-0000-0000-000000000794"
  )
  expect_identical(as.character(result$legacy_events[[1L]]$narrative_id),
                   "9007199254740995")
  expect_identical(as.character(result$legacy_hidden_ids[[1L]]), "9007199254740996")
  expect_identical(as.character(result$sequence$after), "9007199254740999")

  artifacts <- artifact_fixture()
  verified <- nrk_verify_cutover_artifacts(artifacts)
  arguments <- .nrk_kernel_arguments(
    verified, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427"
  )
  result$nonce <- arguments$nonce
  result$database <- arguments$database
  result$input_hashes <- arguments$hashes
  receipt <- nrk_receipt_from_result(arguments, result)
  validated <- .nrk_validate_receipt(
    receipt, arguments$nonce, arguments$hashes, arguments$database
  )
  published <- rawToChar(.nrk_canonical_receipt_raw(validated))
  expect_match(published, '"change_set_id":9007199254740993', fixed = TRUE)
  expect_match(published, '"after":9007199254740999', fixed = TRUE)
  expect_false("result_raw" %in% names(validated))
  expect_false(grepl('"result_raw"', published, fixed = TRUE))

  receipt$result_raw <- paste0(receipt$result_raw, " ")
  expect_error(
    .nrk_validate_receipt(receipt, arguments$nonce, arguments$hashes, arguments$database),
    "CUTOVER_RECOVERY_REQUIRED", fixed = TRUE
  )
})

test_that("artifact JSON parsing preserves bigint decimals before validation", {
  parsed <- .nrk_cutover_parse(
    charToRaw('{"narrative_id":9007199254740995}\n'),
    "CUTOVER_ARTIFACT_JSON_INVALID: bigint"
  )
  expect_identical(parsed$narrative_id, "9007199254740995")
})

test_that("post-commit publication uncertainty always requires recovery", {
  artifacts <- artifact_fixture()
  gateway <- fake_cutover_gateway()
  expect_error(nrk_cutover_execute(
    "apply", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", gateway,
    receipt_publisher = function(...) stop("synthetic publication failure")
  ), "CUTOVER_RECOVERY_REQUIRED", fixed = TRUE)
})

test_that("lost commit acknowledgement is never guessed", {
  artifacts <- artifact_fixture()
  gateway <- fake_cutover_gateway(commit_unknown = TRUE)
  expect_error(nrk_cutover_execute(
    "apply", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", gateway,
    receipt_publisher = function(...) fail("ambiguous apply published")
  ), "CUTOVER_RECOVERY_REQUIRED", fixed = TRUE)
})

test_that("recover resolves exactly nonce plus all six hashes and rejects ambiguity", {
  artifacts <- artifact_fixture()
  applied <- fake_cutover_gateway()
  try(nrk_cutover_execute(
    "apply", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", applied,
    receipt_publisher = function(...) invisible(NULL)
  ), silent = TRUE)
  published <- NULL
  recovered <- nrk_cutover_execute(
    "recover", artifacts, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", applied,
    receipt_publisher = function(receipt, recover) {
      published <<- list(receipt = receipt, recover = recover)
    }
  )
  expect_identical(recovered$status, "recovered")
  expect_true(published$recover)
  shuffled <- recovered$receipt
  shuffled$input_hashes <- rev(shuffled$input_hashes)
  expect_silent(.nrk_validate_receipt(
    shuffled, shuffled$nonce, recovered$receipt$input_hashes,
    recovered$receipt$database
  ))
  mismatched_result <- recovered$receipt
  mismatched_result$result$nonce <- "70000000-0000-0000-0000-000000000799"
  expect_error(.nrk_validate_receipt(
    mismatched_result, recovered$receipt$nonce, recovered$receipt$input_hashes,
    recovered$receipt$database
  ), "CUTOVER_RECOVERY_REQUIRED", fixed = TRUE)

  wrong <- artifacts
  wrong$approval <- c(wrong$approval, charToRaw(" "))
  expect_error(nrk_cutover_execute(
    "recover", wrong, "70000000-0000-0000-0000-000000000701",
    "daa_task7", "7657242220770903427", applied,
    receipt_publisher = function(...) NULL
  ), "CUTOVER_RECOVERY_REQUIRED", fixed = TRUE)
})

test_that("gateway requires exact mode nonce identity and complete PG profile", {
  expect_error(nrk_validate_cutover_mode("preview"), "CUTOVER_MODE_INVALID", fixed = TRUE)
  expect_error(nrk_validate_cutover_nonce("not-a-uuid"), "CUTOVER_NONCE_INVALID", fixed = TRUE)
  profile <- c(
    PGDATABASE = "daa", PGHOST = "127.0.0.1", PGPORT = "5432",
    PGUSER = "postgres", PGPASSWORD = ""
  )
  expect_identical(nrk_validate_cutover_pg_profile(profile), as.list(profile))
  expect_error(nrk_validate_cutover_pg_profile(profile[-5L]), "PG_PROFILE_INCOMPLETE",
               fixed = TRUE)
})

test_that("receipt path is prevalidated as a real private directory", {
  repository_root <- normalizePath(root)
  private_parent <- tempfile("task7-receipt-")
  dir.create(private_parent, mode = "0700")
  Sys.chmod(private_parent, mode = "0700")
  path <- file.path(private_parent, .nrk_receipt_name)
  expect_identical(
    nrk_validate_receipt_path(path, repository_root),
    file.path(normalizePath(private_parent), .nrk_receipt_name)
  )

  public_parent <- tempfile("task7-receipt-public-")
  dir.create(public_parent, mode = "0755")
  Sys.chmod(public_parent, mode = "0755")
  expect_error(
    nrk_validate_receipt_path(file.path(public_parent, .nrk_receipt_name), repository_root),
    "CUTOVER_RECEIPT_DIRECTORY_MODE_INVALID", fixed = TRUE
  )
  expect_error(
    nrk_validate_receipt_path(file.path(tempfile("task7-missing-"), .nrk_receipt_name),
    repository_root), "CUTOVER_RECEIPT_DIRECTORY_INVALID", fixed = TRUE
  )

  sensitive_root <- tempfile("task7-sensitive-")
  sensitive_parent <- file.path(sensitive_root, "work", "approved")
  receipt_parent <- file.path(sensitive_parent, "receipt")
  dir.create(receipt_parent, recursive = TRUE, mode = "0700")
  Sys.chmod(c(sensitive_root, file.path(sensitive_root, "work"), sensitive_parent,
              receipt_parent), "0700")
  alias_parent <- tempfile("task7-alias-")
  expect_true(file.symlink(sensitive_parent, alias_parent))
  expect_error(
    nrk_validate_receipt_path(
      file.path(alias_parent, "receipt", .nrk_receipt_name), repository_root
    ),
    "OUTPUT_WORK_PATH", fixed = TRUE
  )
})

test_that("all apply artifacts are validated before any bytes are read", {
  repository_root <- normalizePath(root)
  sensitive_root <- tempfile("task7-input-sensitive-")
  sensitive_parent <- file.path(sensitive_root, "work", "approved")
  dir.create(sensitive_parent, recursive = TRUE, mode = "0700")
  artifact <- file.path(sensitive_parent, "candidate.json")
  writeBin(charToRaw("{}\n"), artifact)
  alias_parent <- tempfile("task7-input-alias-")
  expect_true(file.symlink(sensitive_parent, alias_parent))
  expect_error(
    nrk_validate_artifact_paths(
      rep(file.path(alias_parent, "candidate.json"), 6L), repository_root
    ),
    "OUTPUT_WORK_PATH", fixed = TRUE
  )
})

test_that("SQL gateway is parameterized and recovery matches all six hashes", {
  expect_match(.nrk_apply_sql$kernel, "apply_narrative_record_cutover", fixed = TRUE)
  expect_match(.nrk_apply_sql$exact_receipt, "record_candidates_sha256=$2", fixed = TRUE)
  expect_match(.nrk_apply_sql$exact_receipt, "approval_sha256=$7", fixed = TRUE)
  expect_match(.nrk_apply_sql$exact_receipt, "database_name=$8", fixed = TRUE)
  expect_match(.nrk_apply_sql$exact_receipt, "system_identifier=$9", fixed = TRUE)
  expect_match(.nrk_apply_sql$exact_receipt, "result_sha256=encode", fixed = TRUE)
  expect_match(.nrk_apply_sql$exact_receipt, "result->'input_hashes'=jsonb_build_object", fixed = TRUE)
  expect_match(.nrk_apply_sql$snapshot, "function_acl_sha256", fixed = TRUE)
  expect_match(.nrk_apply_sql$snapshot, "change_set_sha256", fixed = TRUE)
  expect_match(.nrk_apply_sql$snapshot, "change_event_sha256", fixed = TRUE)
  expect_match(.nrk_apply_sql$snapshot, "change_set_sequence", fixed = TRUE)
  expect_false(grepl("paste0\\(|sprintf\\(", paste(unlist(.nrk_apply_sql), collapse = "")))
})
