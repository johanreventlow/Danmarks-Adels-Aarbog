## DB-free contract tests for the C3 apply gateway (Task 8).
##
## Every test here runs against a FAKE gateway (a call-recording stand-in for
## the DBI-backed one the CLI builds). Nothing in this file opens a database
## connection, and no fixture carries real narrative prose -- the single
## prose-shaped string is synthetic fixture noise whose only job is to prove
## it never reaches stdout/stderr.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "c3_export_shared_1939_v50_helpers.R"))
source(file.path(script_dir, "apply_c3_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "C3_TEST_EXPECTATION_FAILED") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, token) {
  observed <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(identical(observed, token),
         paste0("C3_TEST_ERROR_MISMATCH:", token, ":", observed))
}
sha <- function(letter) paste(rep(letter, 64L), collapse = "")
uuid <- function(tail) paste0("00000000-0000-4c33-8000-00000000", tail)

## ---------------------------------------------------------------------------
## Fixtures: a synthetic Task 3 manifest + Task 4 approval file
## ---------------------------------------------------------------------------

DB_NAME <- "postgres"
SYS_ID <- "7100000000000000001"
NONCE <- uuid("0011")
REVERSAL_NONCE <- uuid("0012")
ACTOR <- uuid("0001")
BATCH_ID <- uuid("00b1")
NEW_BATCH_ID <- uuid("00b2")
AUTH_ID <- uuid("00a1")

manifest_assign_event <- function(index, narrative_id = 700L + index) {
  side <- as.character(500L + index)
  record_key <- paste0("t8-record-", index)
  list(
    element_id = paste0("case:T8CASE", index, ":rid:R0", index),
    rid = paste0("R0", index),
    record_key = record_key,
    action = "assign",
    after_state = list(
      target_person_id = 100L + index,
      raw_sha256 = sha(letters[index]),
      normalized_text = "SYNTETISK-FIXTURE-TEKST-ALDRIG-PROD",
      normalized_sha256 = sha(as.character(index)),
      normalization_version = "narrative_norm_v1",
      normalization_flags = list(),
      expected_narrative = list(
        privat = FALSE, side = side, record_label = record_key,
        citation_label = paste("DAA 1939 side", side))
    ),
    before_state = list(
      source_record = list(match_count = 1L, verbatim_sha256 = sha(letters[index]),
                           side = side),
      target_narrative = list(person_id = 100L + index, narrative_id = narrative_id,
                              privat = FALSE, old_sha256 = sha("f")),
      binding = list(status = "absent", binding_person_id = NULL)
    )
  )
}

manifest_no_publication_event <- function(case_index = 5L, rid_index = 6L) {
  list(
    element_id = paste0("case:T8CASE", case_index, ":rid:R0", rid_index),
    rid = paste0("R0", rid_index),
    record_key = paste0("t8-record-", rid_index),
    action = "no_publication",
    after_state = structure(list(), names = character(0)),
    before_state = list(
      source_record = list(match_count = 1L, verbatim_sha256 = sha("6"),
                           side = "506"),
      binding = list(status = "absent", binding_person_id = NULL)
    )
  )
}

manifest_document <- function(mutate = identity) {
  cases <- lapply(1:5, function(index) {
    ## Spejler fasens reelle facon (2026-08-23): case 4 er no_publication-only
    ## (modstykke til den ægte R28), case 5 bærer assign + no_publication.
    events <- if (index == 4L) list(manifest_no_publication_event(4L, 4L))
              else list(manifest_assign_event(index))
    if (index == 5L) events <- c(events, list(manifest_no_publication_event()))
    list(
      element_id = paste0("case:T8CASE", index),
      case_id = paste0("T8CASE", index),
      after_state = list(action = "different",
                         person_ids = c(100L + index, 200L + index)),
      before_state = list(component_overlap = FALSE, existing_rejection = FALSE),
      events = events
    )
  })
  mutate(list(
    schema_version = "1939-v50-c3-apply-manifest-v1",
    input_hashes = list(
      candidate_raw_sha256 = sha("1"), preview_raw_sha256 = sha("2"),
      candidate_canonical_content_sha256 = sha("3"),
      before_state_canonical_sha256 = sha("4")),
    database = list(database_name = DB_NAME, system_identifier = SYS_ID),
    counts = list(cases = 5L, identity_events = 5L, assign_events = 4L,
                  no_publication_events = 2L, events = 11L),
    cases = cases,
    canonical_content_sha256 = sha("5")
  ))
}

raw_of <- function(document) {
  charToRaw(enc2utf8(as.character(jsonlite::toJSON(
    document, auto_unbox = TRUE, null = "null", digits = NA))))
}

MANIFEST_RAW <- raw_of(manifest_document())
MANIFEST_SHA <- digest::digest(MANIFEST_RAW, algo = "sha256", serialize = FALSE)

approval_document <- function(mutate = identity,
                              manifest_sha = MANIFEST_SHA) {
  mutate(list(
    schema_version = "1939-v50-c3-apply-approvals-decisions-v1",
    approvals_raw_sha256 = sha("7"),
    manifest_raw_sha256 = manifest_sha,
    manifest_canonical_content_sha256 = sha("5"),
    text_bundle_sha256 = sha("8"),
    ## Kun de fire assign-elementer (case 4 er no_publication-only).
    decisions = lapply(c(1L, 2L, 3L, 5L), function(index) list(
      element_id = paste0("case:T8CASE", index, ":rid:R0", index),
      status = "approved")),
    counts = list(decisions = 4L, approved = 4L, unresolved = 0L)
  ))
}

APPROVAL_RAW <- raw_of(approval_document())
APPROVAL_SHA <- digest::digest(APPROVAL_RAW, algo = "sha256", serialize = FALSE)

## ---------------------------------------------------------------------------
## Fake gateway: records every statement in order, answers by SQL pattern
## ---------------------------------------------------------------------------

frame <- function(...) data.frame(..., stringsAsFactors = FALSE)

default_answers <- function(overrides = list()) {
  answers <- list(
    role_profile = frame(rolle = "redaktion"),
    role_current = frame(rolle = "redaktion"),
    read_only = frame(transaction_read_only = "on"),
    change_set = frame(change_set_id = NA_character_),
    database = frame(database_name = DB_NAME),
    system_identifier = frame(system_identifier = SYS_ID),
    authorize = frame(authorization_id = AUTH_ID),
    apply = frame(receipt = NA_character_),
    advisory = frame(locked = TRUE)
  )
  for (name in names(overrides)) answers[[name]] <- overrides[[name]]
  answers
}

receipt_json <- function(mutate = identity, operation = "apply",
                         element_ids = NULL, batch_id = NEW_BATCH_ID,
                         authorization_id = AUTH_ID) {
  if (is.null(element_ids)) {
    element_ids <- c(paste0("case:T8CASE", 1:5),
                     paste0("case:T8CASE", 1:5, ":rid:R0", 1:5),
                     "case:T8CASE5:rid:R06")
  }
  receipt <- list(
    schema_version = "c3-apply-receipt-v1",
    batch_id = batch_id, authorization_id = authorization_id,
    source_id = 3L, phase = "c3", operation = operation,
    status = "finalized", change_set_id = 4242L,
    manifest_sha256 = MANIFEST_SHA, preview_sha256 = sha("2"),
    expected_counts = list(cases = 5L, identity_events = 5L, assign_events = 4L,
                           no_publication_events = 2L, events = 11L,
                           approvals_approved = 4L, approvals_unresolved = 0L),
    observed_counts = list(cases = 5L, identity_events = 5L, assign_events = 4L,
                           no_publication_events = 2L, events = 11L,
                           narratives_written = 4L, source_records = 6L,
                           persons = 10L),
    elements = lapply(element_ids, function(id) list(
      element_id = id, action = "record_assign",
      payload_schema_version = "c3-apply-v1", result = list(),
      before_sha256 = sha("a"), after_sha256 = sha("b")))
  )
  as.character(jsonlite::toJSON(mutate(receipt), auto_unbox = TRUE,
                                null = "null", digits = NA))
}

make_fake <- function(answers = default_answers(), fail_on = NULL,
                      fail_token = "boom") {
  calls <- new.env(parent = emptyenv())
  calls$log <- character(0)
  calls$params <- list()
  record <- function(sql, params) {
    calls$log <- c(calls$log, sql)
    calls$params[[length(calls$params) + 1L]] <- params
    if (!is.null(fail_on) && grepl(fail_on, sql, fixed = TRUE))
      stop(fail_token, call. = FALSE)
  }
  answer <- function(sql) {
    ## Ledger-table patterns are matched FIRST: their SELECT lists legitimately
    ## contain column names (system_identifier, ...) that would otherwise be
    ## captured by the identity-query patterns below.
    if (grepl("reimport_case_authorization", sql, fixed = TRUE))
      return(answers$reconcile_authorization)
    if (grepl("reimport_case_event", sql, fixed = TRUE))
      return(answers$reconcile_events)
    if (grepl("reimport_case_batch", sql, fixed = TRUE)) {
      if (grepl("WHERE authorization_id =", sql, fixed = TRUE))
        return(answers$reconcile_batch)
      if (grepl("WHERE id =", sql, fixed = TRUE)) return(answers$reverse_batch)
      return(answers$reconcile_batch_by_manifest)
    }
    if (grepl("reimport_case_receipt", sql, fixed = TRUE)) return(answers$receipt_sha)
    if (grepl("FROM profiles", sql, fixed = TRUE)) return(answers$role_profile)
    if (grepl("current_rolle()", sql, fixed = TRUE)) return(answers$role_current)
    if (grepl("transaction_read_only", sql, fixed = TRUE)) return(answers$read_only)
    if (grepl("app.change_set_id", sql, fixed = TRUE)) return(answers$change_set)
    if (grepl("current_database()", sql, fixed = TRUE)) return(answers$database)
    if (grepl("system_identifier", sql, fixed = TRUE)) return(answers$system_identifier)
    if (grepl("pg_advisory_xact_lock", sql, fixed = TRUE)) return(answers$advisory)
    if (grepl("red_authorize_reimport_case_reversal", sql, fixed = TRUE))
      return(answers$authorize_reversal)
    if (grepl("red_authorize_reimport_cases", sql, fixed = TRUE)) return(answers$authorize)
    if (grepl("red_apply_reimport_cases", sql, fixed = TRUE)) return(answers$apply)
    if (grepl("red_reverse_reimport_cases", sql, fixed = TRUE)) return(answers$reverse)
    if (grepl("red_preview_reimport_cases", sql, fixed = TRUE)) return(answers$preview)
    if (grepl("set_config", sql, fixed = TRUE)) return(frame(set_config = ""))
    frame(x = NA)
  }
  gateway <- list(
    query = function(sql, params = NULL) { record(sql, params); answer(sql) },
    execute = function(sql, params = NULL) { record(sql, params); invisible(NULL) },
    close = function() invisible(NULL)
  )
  list(gateway = gateway, calls = calls)
}

connector <- function(...) {
  fakes <- list(...)
  index <- 0L
  function() { index <<- index + 1L; fakes[[index]]$gateway }
}

## ===========================================================================
## Step 1a: the all-five-or-none PG environment contract
## ===========================================================================

local({
  pg_names <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
  saved <- Sys.getenv(pg_names, unset = NA)
  restore <- function() {
    for (name in pg_names) {
      value <- saved[[name]]
      if (is.na(value)) Sys.unsetenv(name) else do.call(Sys.setenv,
                                                        stats::setNames(list(value), name))
    }
  }
  on.exit(restore(), add = TRUE)
  full <- list(PGDATABASE = "d", PGHOST = "h", PGPORT = "5432",
               PGUSER = "u", PGPASSWORD = "p")
  ## Every nonempty PROPER subset of the five must be refused before connect.
  for (size in 1:4) {
    for (combo in combn(5L, size, simplify = FALSE)) {
      for (name in pg_names) Sys.unsetenv(name)
      do.call(Sys.setenv, full[combo])
      expect_error(c3_apply_pg_connection_values(), "C3_APPLY_PG_ENV_INVALID")
    }
  }
  ## All five present -> local connection values.
  for (name in pg_names) Sys.unsetenv(name)
  do.call(Sys.setenv, full)
  values <- c3_apply_pg_connection_values()
  expect(identical(values$local, TRUE))
  expect(identical(values$port, 5432L))
  ## None present -> the SUPABASE_* fallback path (no local flag).
  for (name in pg_names) Sys.unsetenv(name)
})

## ===========================================================================
## Step 1b: CLI argument contract
## ===========================================================================

base_args <- function(mode = "apply") {
  c("--mode", mode, "--manifest", "m.json", "--approval", "a.json",
    "--nonce", NONCE, "--actor-id", ACTOR)
}

expect_error(c3_apply_parse_args(character(0)), "C3_APPLY_ARGUMENTS_INVALID")
expect_error(c3_apply_parse_args(base_args()[1:8]), "C3_APPLY_ARGUMENTS_INVALID")
expect_error(c3_apply_parse_args(c(base_args(), "--extra", "x")),
             "C3_APPLY_ARGUMENTS_INVALID")
expect_error(c3_apply_parse_args(base_args("nonsense")), "C3_APPLY_MODE_INVALID")
expect_error(c3_apply_parse_args(c("--mode", "apply", "--manifest", "m.json",
                                   "--approval", "a.json", "--nonce", "not-a-uuid",
                                   "--actor-id", ACTOR)), "C3_APPLY_NONCE_INVALID")
expect_error(c3_apply_parse_args(c("--mode", "apply", "--manifest", "m.json",
                                   "--approval", "a.json", "--nonce", NONCE,
                                   "--actor-id", "nope")), "C3_APPLY_ACTOR_ID_INVALID")
## reverse needs two more flags; the other modes must refuse them.
expect_error(c3_apply_parse_args(base_args("reverse")), "C3_APPLY_ARGUMENTS_INVALID")
expect_error(c3_apply_parse_args(c(base_args("apply"), "--batch-id", BATCH_ID,
                                   "--reversal-nonce", REVERSAL_NONCE)),
             "C3_APPLY_ARGUMENTS_INVALID")
expect_error(c3_apply_parse_args(c(base_args("reverse"), "--batch-id", "nope",
                                   "--reversal-nonce", REVERSAL_NONCE)),
             "C3_APPLY_BATCH_ID_INVALID")
expect_error(c3_apply_parse_args(c(base_args("reverse"), "--batch-id", BATCH_ID,
                                   "--reversal-nonce", NONCE)),
             "C3_APPLY_NONCE_INVALID")
for (mode in c("gate-read-only", "preflight", "rehearse-rollback", "apply", "status")) {
  parsed <- c3_apply_parse_args(base_args(mode))
  expect(identical(parsed$mode, mode))
  expect(identical(parsed$manifest, "m.json"))
  expect(identical(parsed$approval, "a.json"))
  expect(identical(parsed$nonce, NONCE))
  expect(identical(parsed$actor_id, ACTOR))
}
reverse_parsed <- c3_apply_parse_args(c(base_args("reverse"), "--batch-id", BATCH_ID,
                                        "--reversal-nonce", REVERSAL_NONCE))
expect(identical(reverse_parsed$batch_id, BATCH_ID))
expect(identical(reverse_parsed$reversal_nonce, REVERSAL_NONCE))

## ===========================================================================
## Step 1c: artifact gates
## ===========================================================================

expect_error(build_c3_apply_authorization(raw_of(list(a = 1)), APPROVAL_RAW),
             "C3_APPLY_MANIFEST_INVALID")
expect_error(build_c3_apply_authorization(MANIFEST_RAW, raw_of(list(a = 1))),
             "C3_APPLY_APPROVAL_INVALID")
## Approval must be bound to THIS manifest, by both raw bytes and canonical hash.
expect_error(
  build_c3_apply_authorization(
    MANIFEST_RAW, raw_of(approval_document(manifest_sha = sha("0")))),
  "C3_APPLY_APPROVAL_MANIFEST_MISMATCH")
expect_error(
  build_c3_apply_authorization(
    MANIFEST_RAW,
    raw_of(approval_document(function(a) {
      a$manifest_canonical_content_sha256 <- sha("0"); a }))),
  "C3_APPLY_APPROVAL_MANIFEST_MISMATCH")
## Five approvals, zero unresolved -- anything else is refused.
expect_error(
  build_c3_apply_authorization(
    MANIFEST_RAW,
    raw_of(approval_document(function(a) {
      a$decisions[[3L]]$status <- "unresolved"
      a$counts <- list(decisions = 4L, approved = 3L, unresolved = 1L); a }))),
  "C3_APPLY_APPROVAL_NOT_APPROVED")
## Approval decisions must name exactly the manifest's five assign elements.
expect_error(
  build_c3_apply_authorization(
    MANIFEST_RAW,
    raw_of(approval_document(function(a) {
      a$decisions[[2L]]$element_id <- "case:T8CASE2:rid:R99"; a }))),
  "C3_APPLY_APPROVAL_ELEMENT_MISMATCH")
## Manifest counts are pinned to the phase's exact five-case shape.
expect_error(
  build_c3_apply_authorization(
    raw_of(manifest_document(function(m) { m$counts$events <- 12L; m })),
    APPROVAL_RAW),
  "C3_APPLY_MANIFEST_COUNTS_INVALID")
## An element_id that is not derived from its own payload fields is refused.
expect_error(
  build_c3_apply_authorization(
    raw_of(manifest_document(function(m) {
      m$cases[[2L]]$element_id <- "case:WRONG"; m })),
    APPROVAL_RAW),
  "C3_APPLY_MANIFEST_ELEMENT_ID_INVALID")
expect_error(
  build_c3_apply_authorization(
    raw_of(manifest_document(function(m) {
      m$cases[[1L]]$events[[1L]]$element_id <- "case:T8CASE1:rid:WRONG"; m })),
    APPROVAL_RAW),
  "C3_APPLY_MANIFEST_ELEMENT_ID_INVALID")

## ===========================================================================
## Step 1d: THE transformation contract -- manifest -> authorized_elements /
## expected_counts, asserted on the SERIALIZED JSON (field name for field
## name), because an R-list comparison passes while the wire form is wrong.
## ===========================================================================

## A manifest variant plus the approval file that is actually bound to it.
bundle_for <- function(mutate) {
  manifest_raw <- raw_of(manifest_document(mutate))
  build_c3_apply_authorization(
    manifest_raw,
    raw_of(approval_document(manifest_sha = digest::digest(
      manifest_raw, algo = "sha256", serialize = FALSE))))
}

bundle <- build_c3_apply_authorization(MANIFEST_RAW, APPROVAL_RAW)

expect(identical(bundle$hashes$manifest_sha256, MANIFEST_SHA))
expect(identical(bundle$hashes$approval_sha256, APPROVAL_SHA))
expect(identical(bundle$hashes$preview_sha256, sha("2")))
expect(identical(bundle$hashes$state_sha256, sha("4")))
expect(identical(bundle$hashes$decisions_sha256, sha("1")))
expect(identical(bundle$hashes$text_bundle_sha256, sha("8")))
expect(identical(bundle$database$database_name, DB_NAME))
expect(identical(bundle$database$system_identifier, SYS_ID))

counts <- jsonlite::fromJSON(bundle$expected_counts_json, simplifyVector = FALSE)
expect(setequal(names(counts), c("cases", "identity_events", "assign_events",
                                 "no_publication_events", "events",
                                 "approvals_approved", "approvals_unresolved")))
expect(length(counts) == 7L)
expect(identical(counts$cases, 5L) || identical(counts$cases, 5))
expect(identical(as.integer(counts$events), 11L))
expect(identical(as.integer(counts$approvals_approved), 4L))
expect(identical(as.integer(counts$approvals_unresolved), 0L))

elements <- jsonlite::fromJSON(bundle$authorized_elements_json,
                               simplifyVector = FALSE)
expect(length(elements) == 11L)
expect(setequal(names(elements),
                c(paste0("case:T8CASE", 1:5),
                  paste0("case:T8CASE", 1:5, ":rid:R0", 1:5),
                  "case:T8CASE5:rid:R06")))

identity_element <- elements[["case:T8CASE2"]]
expect(length(identity_element) == 4L)
expect(setequal(names(identity_element),
                c("case_id", "action", "person_ids", "before_state")))
expect(identical(identity_element$case_id, "T8CASE2"))
expect(identical(identity_element$action, "different"))
expect(identical(as.integer(unlist(identity_element$person_ids)), c(102L, 202L)))
expect(length(identity_element$before_state) == 2L)
expect(identical(identity_element$before_state$component_overlap, FALSE))
expect(identical(identity_element$before_state$existing_rejection, FALSE))

assign_element <- elements[["case:T8CASE3:rid:R03"]]
expect(length(assign_element) == 13L)
expect(setequal(names(assign_element),
                c("case_id", "rid", "record_key", "action", "target_person_id",
                  "target_narrative_id", "normalized_text", "normalized_sha256",
                  "record_label", "citation_label", "side", "privat",
                  "before_state")))
expect(identical(assign_element$action, "assign"))
expect(identical(assign_element$rid, "R03"))
expect(identical(assign_element$record_key, "t8-record-3"))
expect(identical(as.integer(assign_element$target_person_id), 103L))
expect(identical(as.integer(assign_element$target_narrative_id), 703L))
expect(identical(assign_element$normalized_sha256, sha("3")))
expect(identical(assign_element$record_label, "t8-record-3"))
expect(identical(assign_element$citation_label, "DAA 1939 side 503"))
expect(identical(assign_element$side, "503"))
expect(identical(assign_element$privat, FALSE))
## The flattening drops normalization_version / normalization_flags / raw_sha256.
expect(is.null(assign_element$normalization_version))
expect(is.null(assign_element$normalization_flags))
expect(is.null(assign_element$raw_sha256))
expect(length(assign_element$before_state) == 3L)
expect(setequal(names(assign_element$before_state),
                c("source_record", "target_narrative", "binding")))
expect(length(assign_element$before_state$source_record) == 3L)
expect(identical(as.integer(assign_element$before_state$source_record$match_count), 1L))
expect(identical(assign_element$before_state$source_record$side, "503"))
expect(length(assign_element$before_state$target_narrative) == 4L)
expect(identical(as.integer(assign_element$before_state$target_narrative$person_id), 103L))
expect(identical(as.integer(assign_element$before_state$target_narrative$narrative_id), 703L))
expect(identical(assign_element$before_state$target_narrative$privat, FALSE))
expect(identical(assign_element$before_state$target_narrative$old_sha256, sha("f")))
expect(length(assign_element$before_state$binding) == 2L)
expect(identical(assign_element$before_state$binding$status, "absent"))

no_pub_element <- elements[["case:T8CASE5:rid:R06"]]
expect(length(no_pub_element) == 5L)
expect(setequal(names(no_pub_element),
                c("case_id", "rid", "record_key", "action", "before_state")))
expect(identical(no_pub_element$action, "no_publication"))
expect(length(no_pub_element$before_state) == 2L)
expect(setequal(names(no_pub_element$before_state), c("source_record", "binding")))

## NULL-bearing fields must serialize as JSON null, not disappear (an R list
## silently drops a NULL member, which would emit 12 keys instead of 13).
expect(grepl('"binding_person_id":null', bundle$authorized_elements_json, fixed = TRUE))
null_narrative_bundle <- bundle_for(
  (function(m) {
    ## `x$k <- NULL` REMOVES the key in R; `x["k"] <- list(NULL)` keeps it with
    ## a null value, which is what the finalizer's JSON actually contains.
    m$cases[[1L]]$events[[1L]]$before_state$target_narrative["narrative_id"] <-
      list(NULL)
    m$cases[[1L]]$events[[1L]]$before_state$target_narrative["old_sha256"] <-
      list(NULL)
    m }))
null_elements <- jsonlite::fromJSON(null_narrative_bundle$authorized_elements_json,
                                    simplifyVector = FALSE)
expect(length(null_elements[["case:T8CASE1:rid:R01"]]) == 13L)
expect(is.null(null_elements[["case:T8CASE1:rid:R01"]]$target_narrative_id))
expect(grepl('"target_narrative_id":null',
             null_narrative_bundle$authorized_elements_json, fixed = TRUE))
## Large ids must never emit in scientific notation (jsonb_typeof='number' is
## checked server-side, but 1e+05 would also be a silently wrong id).
big_bundle <- bundle_for(function(m) {
  m$cases[[1L]]$events[[1L]]$before_state$target_narrative$narrative_id <- 100000L
  m })
expect(grepl('"target_narrative_id":100000', big_bundle$authorized_elements_json,
             fixed = TRUE))
expect(!grepl("e+", big_bundle$authorized_elements_json, fixed = TRUE))

## Prose never leaves through anything but the authorize payload.
expect(grepl("SYNTETISK-FIXTURE-TEKST", bundle$authorized_elements_json, fixed = TRUE))
expect(!grepl("SYNTETISK-FIXTURE-TEKST", bundle$selection_json, fixed = TRUE))
expect(!grepl("SYNTETISK-FIXTURE-TEKST", bundle$summary_line, fixed = TRUE))

## The p_selection payload is rebuilt from the manifest, hash-only.
selection <- jsonlite::fromJSON(bundle$selection_json, simplifyVector = FALSE)
expect(identical(selection$schema_version, "1939-v50-c3-apply-selection-v1"))
expect(length(selection$cases) == 5L)
expect(length(selection$cases[[5L]]$records) == 2L)
expect(identical(selection$cases[[5L]]$records[[2L]]$action, "no_publication"))

## ===========================================================================
## Step 1e: gateway call ORDER for apply
## ===========================================================================

apply_answers <- function(mutate = identity) {
  default_answers(list(apply = frame(receipt = mutate(receipt_json()))))
}

fake <- make_fake(apply_answers())
result <- c3_apply_run("apply", bundle,
                       list(nonce = NONCE, actor_id = ACTOR),
                       connector(fake))
expect(identical(result$outcome, "applied"))
expect(identical(result$batch_id, NEW_BATCH_ID))
expect(identical(as.integer(result$change_set_id), 4242L))

log <- fake$calls$log
expect(identical(log[[1L]], "BEGIN"))
expect(grepl("request.jwt.claim.sub", log[[2L]], fixed = TRUE))
expect(grepl("FROM profiles", log[[3L]], fixed = TRUE))
expect(grepl("current_rolle()", log[[4L]], fixed = TRUE))
expect(grepl("SET LOCAL statement_timeout", log[[5L]], fixed = TRUE))
expect(grepl("SET LOCAL lock_timeout", log[[6L]], fixed = TRUE))
expect(grepl("app.change_set_id", log[[7L]], fixed = TRUE))
expect(grepl("current_database()", log[[8L]], fixed = TRUE))
expect(grepl("system_identifier", log[[9L]], fixed = TRUE))
expect(grepl("red_authorize_reimport_cases", log[[10L]], fixed = TRUE))
expect(grepl("red_apply_reimport_cases", log[[11L]], fixed = TRUE))
expect(identical(log[[12L]], "COMMIT"))
expect(length(log) == 12L)
## Exactly one apply call, ever -- the gateway never loops domain RPCs.
expect(sum(grepl("red_apply_reimport_cases", log, fixed = TRUE)) == 1L)
expect(sum(grepl("red_authorize_reimport_cases", log, fixed = TRUE)) == 1L)
## expires_at is computed server-side (clock skew is not a gateway concern).
expect(any(grepl("clock_timestamp()", log, fixed = TRUE)))

## Fail-closed gates, each in its own run.
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(
                 role_profile = frame(rolle = "medlem")))))),
  "C3_APPLY_ACTOR_NOT_REDAKTION")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(
                 role_current = frame(rolle = "medlem")))))),
  "C3_APPLY_GATE_NOT_OPEN")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(
                 change_set = frame(change_set_id = "77")))))),
  "C3_APPLY_FOREIGN_CHANGE_SET")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(
                 database = frame(database_name = "andet")))))),
  "C3_APPLY_DATABASE_MISMATCH")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(
                 system_identifier = frame(system_identifier = "999")))))),
  "C3_APPLY_DATABASE_MISMATCH")

## ===========================================================================
## Step 1f: receipt verification against local hashes
## ===========================================================================

expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(function(j) sub(
                 MANIFEST_SHA, sha("0"), j, fixed = TRUE))))),
  "C3_APPLY_RECEIPT_MISMATCH")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(function(j) sub(
                 '"status":"finalized"', '"status":"open"', j, fixed = TRUE))))),
  "C3_APPLY_RECEIPT_NOT_FINALIZED")
## observed_counts carries EIGHT keys against expected_counts' seven: only the
## five shared keys may be compared, and they must agree.
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(function(j) sub(
                 '"narratives_written":4', '"narratives_written":3', j,
                 fixed = TRUE))))),
  "")  ## an unrelated observed key must NOT fail the run
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(apply = frame(
                 receipt = receipt_json(function(r) {
                   r$observed_counts$assign_events <- 5L; r }))))))),
  "C3_APPLY_RECEIPT_COUNTS_MISMATCH")
## The ledger must have recorded exactly our eleven element ids.
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(apply = frame(
                 receipt = receipt_json(element_ids = c(
                   paste0("case:T8CASE", 1:5),
                   paste0("case:T8CASE", 1:5, ":rid:R0", 1:5),
                   "case:T8CASE5:rid:R99")))))))),
  "C3_APPLY_RECEIPT_ELEMENT_MISMATCH")

## ===========================================================================
## Step 2: commit-unknown -- reconnect, take the global lock FIRST, then look
## up by nonce plus ALL hashes. Three-way outcome.
## ===========================================================================

reconcile_authorization_frame <- function(mutate = identity, status = "consumed") {
  row <- frame(
    id = AUTH_ID, status = status, source_id = 3L, phase = "c3",
    operation = "apply", manifest_sha256 = MANIFEST_SHA,
    preview_sha256 = sha("2"), approval_sha256 = APPROVAL_SHA,
    decisions_sha256 = sha("1"), state_sha256 = sha("4"),
    text_bundle_sha256 = sha("8"), database_name = DB_NAME,
    system_identifier = SYS_ID)
  mutate(row)
}

reconcile_batch_frame <- function(status = "finalized",
                                  observed = NULL) {
  if (is.null(observed)) {
    observed <- as.character(jsonlite::toJSON(list(
      cases = 5L, identity_events = 5L, assign_events = 4L,
      no_publication_events = 2L, events = 11L, narratives_written = 4L,
      source_records = 6L, persons = 10L), auto_unbox = TRUE))
  }
  frame(id = NEW_BATCH_ID, status = status, change_set_id = 4242L,
        manifest_sha256 = MANIFEST_SHA, preview_sha256 = sha("2"),
        observed_counts = observed)
}

## NOTE: c(list(a=1), list(a=2)) keeps BOTH names, and [["a"]] then returns
## the first -- so overrides must be merged by assignment, not concatenation.
merge_answers <- function(base, overrides) {
  for (name in names(overrides)) base[[name]] <- overrides[[name]]
  base
}

commit_unknown_answers <- function(overrides = list()) {
  default_answers(merge_answers(list(
    reconcile_authorization = reconcile_authorization_frame(),
    reconcile_batch = reconcile_batch_frame(),
    reconcile_batch_by_manifest = frame(n = 1L),
    reconcile_events = frame(n = 11L)), overrides))
}

## (a) exact finalized receipt found -> success, no new mutation.
applier <- make_fake(apply_answers(), fail_on = "COMMIT", fail_token = "link lost")
reconciler <- make_fake(commit_unknown_answers())
result <- c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
                       connector(applier, reconciler))
expect(identical(result$outcome, "committed"))
expect(identical(result$batch_id, NEW_BATCH_ID))
rlog <- reconciler$calls$log
expect(grepl("READ ONLY", rlog[[1L]], fixed = TRUE))
expect(grepl("SET LOCAL lock_timeout", rlog[[2L]], fixed = TRUE))
expect(grepl("SET LOCAL statement_timeout", rlog[[3L]], fixed = TRUE))
## Fund B6: the GLOBAL advisory lock is taken BEFORE any nonce/hash lookup.
expect(grepl("pg_advisory_xact_lock", rlog[[4L]], fixed = TRUE))
expect(grepl("daa-1939-v50-production-writer", rlog[[4L]], fixed = TRUE))
expect(grepl("hashtextextended", rlog[[4L]], fixed = TRUE))
expect(grepl("reimport_case_authorization", rlog[[5L]], fixed = TRUE))
expect(!any(grepl("reimport_case_authorization", rlog[1:4], fixed = TRUE)))
expect(identical(rlog[[length(rlog)]], "ROLLBACK"))
## No writing RPC is ever called on the reconciliation connection.
expect(!any(grepl("red_apply_reimport_cases", rlog, fixed = TRUE)))
expect(!any(grepl("red_authorize_reimport_cases", rlog, fixed = TRUE)))

## (b) nothing found -> safe non-commit.
result <- c3_apply_run(
  "apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
  connector(make_fake(apply_answers(), fail_on = "COMMIT"),
            make_fake(commit_unknown_answers(list(
              reconcile_authorization = reconcile_authorization_frame()[0L, ],
              reconcile_batch = reconcile_batch_frame()[0L, ],
              reconcile_batch_by_manifest = frame(n = 0L))))))
expect(identical(result$outcome, "not_committed"))

## (c) drifted / partial receipts -> terminal C3_APPLY_COMMIT_UNKNOWN.
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(), fail_on = "COMMIT"),
                         make_fake(commit_unknown_answers(list(
                           reconcile_batch = reconcile_batch_frame("open")))))),
  "C3_APPLY_COMMIT_UNKNOWN")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(), fail_on = "COMMIT"),
                         make_fake(commit_unknown_answers(list(
                           reconcile_authorization = reconcile_authorization_frame(
                             function(row) { row$approval_sha256 <- sha("0"); row })))))),
  "C3_APPLY_COMMIT_UNKNOWN")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(), fail_on = "COMMIT"),
                         make_fake(commit_unknown_answers(list(
                           reconcile_authorization = reconcile_authorization_frame(
                             function(row) { row$state_sha256 <- sha("0"); row })))))),
  "C3_APPLY_COMMIT_UNKNOWN")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(), fail_on = "COMMIT"),
                         make_fake(commit_unknown_answers(list(
                           reconcile_events = frame(n = 10L)))))),
  "C3_APPLY_COMMIT_UNKNOWN")
## A batch that exists for our manifest under some OTHER nonce is not "safe".
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(), fail_on = "COMMIT"),
                         make_fake(commit_unknown_answers(list(
                           reconcile_authorization = reconcile_authorization_frame()[0L, ],
                           reconcile_batch = reconcile_batch_frame()[0L, ],
                           reconcile_batch_by_manifest = frame(n = 1L)))))),
  "C3_APPLY_COMMIT_UNKNOWN")

## (d) a deliberately REVERSED batch is its own clear state, never the generic
## already-consumed / commit-unknown bucket (Task 6/7 contract 2).
result <- c3_apply_run(
  "apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
  connector(make_fake(apply_answers(), fail_on = "COMMIT"),
            make_fake(commit_unknown_answers(list(
              reconcile_batch = reconcile_batch_frame("reversed"))))))
expect(identical(result$outcome, "reversed"))

## The same three-way logic drives `status` mode, with no apply connection.
status_result <- c3_apply_run("status", bundle, list(nonce = NONCE, actor_id = ACTOR),
                              connector(make_fake(commit_unknown_answers())))
expect(identical(status_result$outcome, "committed"))
status_fake <- make_fake(commit_unknown_answers())
invisible(c3_apply_run("status", bundle, list(nonce = NONCE, actor_id = ACTOR),
                       connector(status_fake)))
expect(!any(grepl("red_", status_fake$calls$log, fixed = TRUE)))

## The RPC's own reversed/consumed tokens are mapped, not swallowed.
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(),
                                   fail_on = "red_apply_reimport_cases",
                                   fail_token = "REIMPORT_CASE_BATCH_REVERSED"))),
  "C3_APPLY_BATCH_REVERSED")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(),
                                   fail_on = "red_apply_reimport_cases",
                                   fail_token = "REIMPORT_CASE_FOREIGN_CHANGE_SET"))),
  "C3_APPLY_FOREIGN_CHANGE_SET")
expect_error(
  c3_apply_run("apply", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(apply_answers(),
                                   fail_on = "red_apply_reimport_cases",
                                   fail_token = "REIMPORT_CASE_SOURCE_RECORD_DRIFT"))),
  "C3_APPLY_RPC_FAILED")

## ===========================================================================
## Step 3: gate-read-only
## ===========================================================================

readonly_fake <- make_fake(default_answers(),
                           fail_on = "red_authorize_reimport_cases",
                           fail_token = paste(
                             "cannot execute INSERT in a read-only transaction"))
result <- c3_apply_run("gate-read-only", bundle,
                       list(nonce = NONCE, actor_id = ACTOR),
                       connector(readonly_fake))
expect(identical(result$outcome, "gate_verified"))
glog <- readonly_fake$calls$log
expect(grepl("READ ONLY", glog[[1L]], fixed = TRUE))
expect(grepl("request.jwt.claim.sub", glog[[2L]], fixed = TRUE))
expect(grepl("FROM profiles", glog[[3L]], fixed = TRUE))
expect(grepl("current_rolle()", glog[[4L]], fixed = TRUE))
expect(grepl("transaction_read_only", glog[[5L]], fixed = TRUE))
expect(identical(glog[[length(glog)]], "ROLLBACK"))
## A role rejection is NOT a read-only proof.
expect_error(
  c3_apply_run("gate-read-only", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(),
                                   fail_on = "red_authorize_reimport_cases",
                                   fail_token = "REIMPORT_1939_ROLE_FORBIDDEN"))),
  "C3_APPLY_GATE_ROLE_REJECTED")
## Nor is a successful authorization.
expect_error(
  c3_apply_run("gate-read-only", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers()))),
  "C3_APPLY_GATE_NOT_READ_ONLY")
## Nor is the transaction actually read-only if the server says otherwise.
expect_error(
  c3_apply_run("gate-read-only", bundle, list(nonce = NONCE, actor_id = ACTOR),
               connector(make_fake(default_answers(list(
                 read_only = frame(transaction_read_only = "off")))))),
  "C3_APPLY_NOT_READ_ONLY")

## ===========================================================================
## Step 3b: preflight -- every gate, no RPC write at all
## ===========================================================================

preflight_fake <- make_fake(default_answers(list(
  preview = frame(result = "canonical-state-A"))))
result <- c3_apply_run("preflight", bundle, list(nonce = NONCE, actor_id = ACTOR),
                       connector(preflight_fake))
expect(identical(result$outcome, "preflight_ok"))
plog <- preflight_fake$calls$log
expect(grepl("READ ONLY", plog[[1L]], fixed = TRUE))
expect(!any(grepl("red_authorize", plog, fixed = TRUE)))
expect(!any(grepl("red_apply", plog, fixed = TRUE)))
expect(identical(plog[[length(plog)]], "ROLLBACK"))

## ===========================================================================
## Step 4: rehearse-rollback -- authorize + one apply + receipt verification in
## ONE transaction, then an EXPLICIT rollback, then a reconnect that proves
## neither receipt rows nor domain mutations remain.
## ===========================================================================

preview_answer <- function(text = "canonical-state-A") frame(result = text)

rehearse_connector <- function(before = "state-A", after = "state-A",
                               reconcile = NULL) {
  if (is.null(reconcile)) {
    reconcile <- commit_unknown_answers(list(
      reconcile_authorization = reconcile_authorization_frame()[0L, ],
      reconcile_batch = reconcile_batch_frame()[0L, ],
      reconcile_batch_by_manifest = frame(n = 0L)))
  }
  measure_before <- make_fake(default_answers(list(preview = preview_answer(before))))
  rehearsal <- make_fake(apply_answers())
  measure_after <- make_fake(merge_answers(
    reconcile, list(preview = preview_answer(after))))
  list(fakes = list(measure_before, rehearsal, measure_after),
       connect = connector(measure_before, rehearsal, measure_after))
}

pieces <- rehearse_connector()
result <- c3_apply_run("rehearse-rollback", bundle,
                       list(nonce = NONCE, actor_id = ACTOR), pieces$connect)
expect(identical(result$outcome, "rehearsed"))
rehearsal_log <- pieces$fakes[[2L]]$calls$log
expect(identical(rehearsal_log[[1L]], "BEGIN"))
expect(grepl("red_authorize_reimport_cases", rehearsal_log[[10L]], fixed = TRUE))
expect(grepl("red_apply_reimport_cases", rehearsal_log[[11L]], fixed = TRUE))
expect(identical(rehearsal_log[[12L]], "ROLLBACK"))
expect(!("COMMIT" %in% rehearsal_log))
## The domain proof is self-measured before/after, through the ONE state
## oracle -- not a comparison against the manifest's older recorded hash.
expect(any(grepl("red_preview_reimport_cases", pieces$fakes[[1L]]$calls$log,
                 fixed = TRUE)))
expect(any(grepl("red_preview_reimport_cases", pieces$fakes[[3L]]$calls$log,
                 fixed = TRUE)))
expect(identical(result$state_before_sha256, result$state_after_sha256))

## Domain drift after the rollback is terminal.
expect_error(
  c3_apply_run("rehearse-rollback", bundle, list(nonce = NONCE, actor_id = ACTOR),
               rehearse_connector(before = "state-A", after = "state-B")$connect),
  "C3_APPLY_REHEARSAL_DOMAIN_RESIDUE")
## A surviving ledger row after the rollback is terminal.
expect_error(
  c3_apply_run("rehearse-rollback", bundle, list(nonce = NONCE, actor_id = ACTOR),
               rehearse_connector(reconcile = commit_unknown_answers())$connect),
  "C3_APPLY_REHEARSAL_LEDGER_RESIDUE")

## ===========================================================================
## Step 4b: reverse -- its own authorization artefact and its own CLI mode
## ===========================================================================

reverse_answers <- function(overrides = list()) {
  default_answers(merge_answers(list(
    receipt_sha = frame(receipt_sha256 = sha("9")),
    reverse_batch = frame(id = BATCH_ID, status = "finalized",
                          operation = "apply", source_id = 3L, phase = "c3",
                          manifest_sha256 = MANIFEST_SHA,
                          preview_sha256 = sha("2")),
    authorize_reversal = frame(authorization_id = uuid("00a2")),
    reverse = frame(receipt = receipt_json(operation = "reversal",
                                           batch_id = uuid("00b9"),
                                           authorization_id = uuid("00a2")))),
    overrides))
}

reverse_fake <- make_fake(reverse_answers())
result <- c3_apply_run("reverse", bundle,
                       list(nonce = NONCE, actor_id = ACTOR, batch_id = BATCH_ID,
                            reversal_nonce = REVERSAL_NONCE),
                       connector(reverse_fake))
expect(identical(result$outcome, "reversed_batch"))
vlog <- reverse_fake$calls$log
expect(identical(vlog[[1L]], "BEGIN"))
expect(sum(grepl("red_reverse_reimport_cases", vlog, fixed = TRUE)) == 1L)
expect(sum(grepl("red_authorize_reimport_case_reversal", vlog, fixed = TRUE)) == 1L)
expect(identical(vlog[[length(vlog)]], "COMMIT"))
## The batch being reversed must belong to THIS manifest chain.
expect_error(
  c3_apply_run("reverse", bundle,
               list(nonce = NONCE, actor_id = ACTOR, batch_id = BATCH_ID,
                    reversal_nonce = REVERSAL_NONCE),
               connector(make_fake(reverse_answers(list(
                 reverse_batch = frame(id = BATCH_ID, status = "finalized",
                                       operation = "apply", source_id = 3L,
                                       phase = "c3",
                                       manifest_sha256 = sha("0"),
                                       preview_sha256 = sha("2"))))))),
  "C3_APPLY_REVERSAL_BATCH_MISMATCH")
expect_error(
  c3_apply_run("reverse", bundle,
               list(nonce = NONCE, actor_id = ACTOR, batch_id = BATCH_ID,
                    reversal_nonce = REVERSAL_NONCE),
               connector(make_fake(reverse_answers(list(
                 reverse_batch = frame(id = BATCH_ID, status = "reversed",
                                       operation = "apply", source_id = 3L,
                                       phase = "c3",
                                       manifest_sha256 = MANIFEST_SHA,
                                       preview_sha256 = sha("2"))))))),
  "C3_APPLY_REVERSAL_BATCH_NOT_REVERSIBLE")

## ===========================================================================
## Cross-tool pin: REAL finalizer + converter output, not a hand-written mirror
##
## Every other fixture in this file is written by hand to mirror
## finalize_c3_apply_manifest_1939_v50.py and
## convert_c3_apply_approvals_1939_v50.py. That pins one side only: if either
## Python tool changed its output shape, all the assertions above would still
## pass. These two files are genuine output of those tools (produced against a
## disposable local Postgres during Task 8's rehearsal, see the task report);
## they contain no real prose and no PII. Asserting the projection against
## them is what makes a finalizer/gateway divergence fail in CI rather than in
## a production window.
##
## Only the projection is exercised -- build_c3_apply_authorization() never
## compares `database` against a live connection, so the fixtures' recorded
## database name / system identifier are inert here.
## ===========================================================================

local({
  manifest_raw <- .c3_common_read_regular_raw(
    file.path(script_dir, "fixtures", "c3-apply", "manifest.json"), "C3_APPLY_MANIFEST_UNREADABLE")
  approval_raw <- .c3_common_read_regular_raw(
    file.path(script_dir, "fixtures", "c3-apply", "approval.json"), "C3_APPLY_APPROVAL_UNREADABLE")
  real <- build_c3_apply_authorization(manifest_raw, approval_raw)
  expect(length(real$element_ids) == 11L)
  expect(length(real$assign_element_ids) == 4L)
  real_elements <- jsonlite::fromJSON(real$authorized_elements_json,
                                       simplifyVector = FALSE)
  expect(setequal(names(real_elements), real$element_ids))
  key_counts <- vapply(real_elements, length, integer(1))
  actions <- vapply(real_elements, function(e) e$action, character(1))
  expect(all(key_counts[actions == "different"] == 4L))
  expect(all(key_counts[actions == "assign"] == 13L))
  expect(all(key_counts[actions == "no_publication"] == 5L))
  expect(sum(actions == "different") == 5L)
  expect(sum(actions == "assign") == 4L)
  expect(sum(actions == "no_publication") == 2L)
  real_counts <- jsonlite::fromJSON(real$expected_counts_json, simplifyVector = FALSE)
  expect(length(real_counts) == 7L)
  expect(identical(as.integer(real_counts$events), 11L))
  expect(identical(as.integer(real_counts$approvals_approved), 4L))
  expect(identical(as.integer(real_counts$approvals_unresolved), 0L))
  ## Element ids are exactly the finalizer's own element_id values.
  manifest <- jsonlite::fromJSON(rawToChar(manifest_raw), simplifyVector = FALSE)
  finalizer_ids <- unlist(lapply(manifest$cases, function(case)
    c(case$element_id, vapply(case$events, function(e) e$element_id, character(1)))))
  expect(setequal(finalizer_ids, real$element_ids))
})

## ===========================================================================
## Step 5: printed output carries only safe counts / ids / hashes
## ===========================================================================

expect(!grepl("SYNTETISK-FIXTURE-TEKST", result$summary, fixed = TRUE))
expect(!grepl("SYNTETISK", bundle$summary_line, fixed = TRUE))
expect(grepl(MANIFEST_SHA, bundle$summary_line, fixed = TRUE))

cat(sprintf("OK: apply_c3_1939_v50 gateway contract -- %d assertions\n", ok))
