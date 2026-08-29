library(testthat)

root <- normalizePath(file.path(getwd(), "..", ".."))
helpers <- file.path(
  root, ".claude", "skills", "daa-extract", "scripts",
  "export_narrative_record_cutover_helpers.R"
)
source(helpers, local = TRUE)

sha <- function(value) digest::digest(value, algo = "sha256", serialize = FALSE)

record_rows <- function() data.frame(
  binding_id = c(
    "70000000-0000-0000-0000-000000000001",
    "70000000-0000-0000-0000-000000000002"
  ),
  narrative_id = c(101L, 102L),
  person_id = c(11L, 12L),
  source_id = c(5L, 5L),
  source_kind = c("DAA-udgave", "DAA-udgave"),
  source_record_id = c(
    "70000000-0000-0000-0000-000000000011",
    "70000000-0000-0000-0000-000000000012"
  ),
  record_key = c("side-2", "side-10"),
  status = c("published", "draft"),
  record_label = c("II.", "X."),
  citation_label = c("DAA 1939, s. 2", "DAA 1939, s. 10"),
  publication_state_sha256 = c(strrep("1", 64), strrep("3", 64)),
  narrative_text_sha256 = c(strrep("2", 64), strrep("4", 64)),
  binding_match_count = c(1L, 1L),
  stringsAsFactors = FALSE
)

legacy_rows <- function(refs = c(
  "70000000-0000-0000-0000-000000000101",
  "70000000-0000-0000-0000-000000000102"
)) data.frame(
  legacy_publication_ref = refs,
  narrative_id = c(201L, 202L),
  person_id = c(21L, 22L),
  source_id = c(6L, 6L),
  source_kind = c("DAA-udgave", "DAA-udgave"),
  narrative_text_sha256 = c(strrep("5", 64), strrep("7", 64)),
  baseline_sha256 = c(strrep("6", 64), strrep("8", 64)),
  binding_match_count = c(0L, 0L),
  stringsAsFactors = FALSE
)

identity_counts <- function() data.frame(
  accepted_identity_count = 2L,
  identity_blocked_record_count = 3L
)

counts_by_source <- function() data.frame(
  source_id = c(5L, 6L),
  record_candidates = c(2L, 0L),
  legacy_candidates = c(0L, 2L)
)

db_identity <- list(
  database_name = "daa_task7_synthetic",
  system_identifier = "7657242220770903427"
)

test_that("pure exporter emits canonical exact candidate and inventory bytes", {
  bundle <- nrk_export_build_bundle(
    record_rows(), legacy_rows(), counts_by_source(), identity_counts(), db_identity
  )
  expect_identical(sort(names(bundle)), sort(c(
    .nrk_record_candidates_name, .nrk_legacy_candidates_name, .nrk_inventory_name
  )))
  for (raw in bundle) {
    expect_type(raw, "raw")
    expect_identical(tail(raw, 1L), charToRaw("\n"))
    parsed <- jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
    expect_identical(nrk_canonical_raw(parsed), raw)
  }
  record <- jsonlite::fromJSON(
    rawToChar(bundle[[.nrk_record_candidates_name]]), simplifyVector = FALSE
  )
  legacy <- jsonlite::fromJSON(
    rawToChar(bundle[[.nrk_legacy_candidates_name]]), simplifyVector = FALSE
  )
  inventory <- jsonlite::fromJSON(
    rawToChar(bundle[[.nrk_inventory_name]]), simplifyVector = FALSE
  )
  expect_identical(vapply(record$rows, `[[`, "", "binding_id"), record_rows()$binding_id)
  expect_identical(vapply(legacy$rows, `[[`, 0L, "narrative_id"), c(201L, 202L))
  expect_identical(inventory$record_candidate_ids, as.list(record_rows()$binding_id))
  expect_identical(inventory$legacy_candidate_ids, as.list(c(201L, 202L)))
  expect_true(length(inventory$classified_direct_readers) == 10L)
  for (row in c(record$rows, legacy$rows)) {
    stated <- row$row_sha256
    row$row_sha256 <- NULL
    expect_identical(stated, sha(nrk_canonical_raw(row)))
  }
})

test_that("exporter preserves bigint identities above the JavaScript safe range", {
  records <- record_rows()
  records$narrative_id <- bit64::as.integer64(c("9007199254740993", "9007199254740994"))
  records$person_id <- bit64::as.integer64(c("9007199254740995", "9007199254740996"))
  records$source_id <- bit64::as.integer64(c("9007199254740997", "9007199254740997"))
  legacy <- legacy_rows()
  legacy$narrative_id <- bit64::as.integer64(c("9007199254740998", "9007199254740999"))
  legacy$person_id <- bit64::as.integer64(c("9007199254741000", "9007199254741001"))
  legacy$source_id <- bit64::as.integer64(c("9007199254741002", "9007199254741002"))
  counts <- data.frame(
    source_id = bit64::as.integer64(c("9007199254740997", "9007199254741002")),
    record_candidates = c(2L, 0L), legacy_candidates = c(0L, 2L)
  )
  bundle <- nrk_export_build_bundle(records, legacy, counts, identity_counts(), db_identity)
  record_text <- rawToChar(bundle[[.nrk_record_candidates_name]])
  legacy_text <- rawToChar(bundle[[.nrk_legacy_candidates_name]])
  expect_match(record_text, '"narrative_id":9007199254740993', fixed = TRUE)
  expect_match(record_text, '"person_id":9007199254740995', fixed = TRUE)
  expect_match(legacy_text, '"narrative_id":9007199254740998', fixed = TRUE)
})

test_that("export inventory counts are reconciled to candidate rows", {
  counts <- counts_by_source()
  counts$record_candidates[[1L]] <- 1L
  expect_error(
    nrk_export_build_bundle(record_rows(), legacy_rows(), counts, identity_counts(), db_identity),
    "INVENTORY_COUNTS_BY_SOURCE_MISMATCH", fixed = TRUE
  )
})

test_that("pure exporter rejects duplicates null hashes bad order ambiguity and non-DAA", {
  records <- record_rows()
  records$binding_id[[2L]] <- records$binding_id[[1L]]
  expect_error(
    nrk_export_build_bundle(records, legacy_rows(), counts_by_source(), identity_counts(), db_identity),
    "DUPLICATE_RECORD_CANDIDATE", fixed = TRUE
  )
  records <- record_rows()
  records$publication_state_sha256[[1L]] <- NA_character_
  expect_error(
    nrk_export_build_bundle(records, legacy_rows(), counts_by_source(), identity_counts(), db_identity),
    "INVALID_SHA256", fixed = TRUE
  )
  records <- record_rows()[2:1, ]
  expect_error(
    nrk_export_build_bundle(records, legacy_rows(), counts_by_source(), identity_counts(), db_identity),
    "RECORD_CANDIDATE_ORDER", fixed = TRUE
  )
  records <- record_rows()
  records$binding_match_count[[1L]] <- 2L
  expect_error(
    nrk_export_build_bundle(records, legacy_rows(), counts_by_source(), identity_counts(), db_identity),
    "AMBIGUOUS_RECORD_BINDING", fixed = TRUE
  )
  legacy <- legacy_rows()
  legacy$source_kind[[1L]] <- "arkiv"
  expect_error(
    nrk_export_build_bundle(record_rows(), legacy, counts_by_source(), identity_counts(), db_identity),
    "NON_DAA_CANDIDATE", fixed = TRUE
  )
})

test_that("new legacy refs are minted per candidate run and stay within one bundle", {
  first <- nrk_export_new_legacy_refs(c(201L, 202L))
  second <- nrk_export_new_legacy_refs(c(201L, 202L))
  expect_length(unique(first), 2L)
  expect_length(unique(second), 2L)
  expect_false(identical(first, second))
  expect_true(all(grepl(.nrk_uuid_pattern, first)))
})

fake_gateway <- function(fail_on = NULL) {
  log <- list()
  active <- FALSE
  query <- function(sql, params = list()) {
    log[[length(log) + 1L]] <<- list(kind = "query", sql = sql, params = params)
    if (!is.null(fail_on) && grepl(fail_on, sql, fixed = TRUE)) stop("synthetic db failure")
    if (grepl("NRK_EXPORT_DATABASE_IDENTITY", sql, fixed = TRUE)) {
      return(data.frame(
        database_name = db_identity$database_name,
        system_identifier = db_identity$system_identifier
      ))
    }
    if (grepl("narrative_record_contract_version", sql, fixed = TRUE)) {
      return(data.frame(contract_version = 1L))
    }
    if (grepl("NRK_EXPORT_RECORD_CANDIDATES", sql, fixed = TRUE)) return(record_rows())
    if (grepl("NRK_EXPORT_LEGACY_CANDIDATES", sql, fixed = TRUE)) return(legacy_rows())
    if (grepl("NRK_EXPORT_COUNTS_BY_SOURCE", sql, fixed = TRUE)) return(counts_by_source())
    if (grepl("NRK_EXPORT_IDENTITY_COUNTS", sql, fixed = TRUE)) return(identity_counts())
    data.frame(ok = TRUE)
  }
  list(
    begin = function() { active <<- TRUE; log[[length(log) + 1L]] <<- list(kind = "begin") },
    query = query,
    commit = function() { active <<- FALSE; log[[length(log) + 1L]] <<- list(kind = "commit") },
    rollback = function() { active <<- FALSE; log[[length(log) + 1L]] <<- list(kind = "rollback") },
    log = function() log,
    active = function() active
  )
}

test_that("export run takes read-only repeatable-read shared gate before separate measurements", {
  gateway <- fake_gateway()
  published <- NULL
  publisher <- function(output_dir, bundle, recover = FALSE) {
    published <<- list(output_dir = output_dir, bundle = bundle, recover = recover)
    "published"
  }
  result <- nrk_export_run(gateway, "/private/tmp/nrk-task7", publisher = publisher)
  log <- gateway$log()
  sql <- vapply(Filter(function(item) identical(item$kind, "query"), log), `[[`, "", "sql")
  expect_true(grepl("REPEATABLE READ READ ONLY", sql[[1L]], fixed = TRUE))
  expect_true(grepl("pg_advisory_xact_lock_shared", sql[[2L]], fixed = TRUE))
  expect_true(grepl("narrative_record_contract_version", sql[[3L]], fixed = TRUE))
  positions <- vapply(c(
    "NRK_EXPORT_RECORD_CANDIDATES", "NRK_EXPORT_LEGACY_CANDIDATES",
    "NRK_EXPORT_COUNTS_BY_SOURCE", "NRK_EXPORT_IDENTITY_COUNTS"
  ), function(marker) which(grepl(marker, sql, fixed = TRUE)), integer(1))
  expect_true(all(positions > 3L))
  expect_identical(log[[length(log)]]$kind, "commit")
  expect_false(gateway$active())
  expect_identical(published$output_dir, "/private/tmp/nrk-task7")
  expect_false(published$recover)
  expect_identical(sort(names(published$bundle)), sort(names(result$artifacts)))
  expect_identical(result$database, db_identity)
  expect_identical(result$hashes, lapply(result$artifacts, nrk_sha_raw))
})

test_that("export rolls back and publishes nothing on any query failure", {
  gateway <- fake_gateway("NRK_EXPORT_LEGACY_CANDIDATES")
  published <- FALSE
  expect_error(
    nrk_export_run(gateway, "/private/tmp/nrk-task7", publisher = function(...) {
      published <<- TRUE
    }),
    "synthetic db failure", fixed = TRUE
  )
  expect_false(published)
  expect_identical(tail(gateway$log(), 1L)[[1L]]$kind, "rollback")
  expect_false(gateway$active())
})

test_that("exporter requires explicit safe output and complete five-variable DB profile", {
  expect_error(nrk_validate_output_path(root), "OUTPUT_INSIDE_REPOSITORY", fixed = TRUE)
  expect_error(
    nrk_validate_output_path("/private/tmp/work/task7"), "OUTPUT_WORK_PATH", fixed = TRUE
  )
  sandbox <- tempfile("nrk-output-path-")
  dir.create(file.path(sandbox, "work", "approved"), recursive = TRUE, mode = "0700")
  expect_true(file.symlink(file.path(sandbox, "work"), file.path(sandbox, "alias")))
  on.exit(unlink(sandbox, recursive = TRUE), add = TRUE)
  expect_error(
    nrk_validate_output_path(file.path(sandbox, "alias", "approved")),
    "OUTPUT_WORK_PATH", fixed = TRUE
  )
  profile <- c(
    PGDATABASE = "daa", PGHOST = "127.0.0.1", PGPORT = "5432",
    PGUSER = "postgres", PGPASSWORD = ""
  )
  expect_identical(nrk_validate_pg_profile(profile), as.list(profile))
  expect_error(nrk_validate_pg_profile(profile[-1L]), "PG_PROFILE_INCOMPLETE", fixed = TRUE)
})

test_that("SQL is read-only, exact-set oriented and delegates canonical legacy state", {
  expect_match(.nrk_export_sql$record_candidates, "source.slags='DAA-udgave'", fixed = TRUE)
  expect_match(.nrk_export_sql$record_candidates, "narrative_publication_state", fixed = TRUE)
  expect_match(.nrk_export_sql$legacy_candidates, "NOT EXISTS", fixed = TRUE)
  expect_match(
    .nrk_export_sql$legacy_candidates,
    "narrative_legacy_candidate_publication_state", fixed = TRUE
  )
  expect_match(.nrk_export_sql$identity_counts, "source_record_placement_current", fixed = TRUE)
  expect_match(.nrk_export_sql$identity_counts, "source_persona_placement_current", fixed = TRUE)
  expect_match(.nrk_export_sql$identity_counts, "placement_role IN ('principal_member','co_principal')", fixed = TRUE)
  expect_match(.nrk_export_sql$identity_counts, "persona_placement.decision_status='accepted'", fixed = TRUE)
  expect_false(grepl("INSERT|UPDATE|DELETE|MERGE", paste(unlist(.nrk_export_sql), collapse = " ")))
})
