## DB-free contract tests for the C3 apply database preview exporter.
## Fixtures contain identifiers, hashes and structural metadata only; no real
## narrative prose is ever read, and the one synthetic prose-like string used
## to prove it never reaches the RPC payload is fixture noise, not real text.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "c3_export_shared_1939_v50_helpers.R"))
source(file.path(script_dir, "export_c3_apply_preview_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "C3_TEST_EXPECTATION_FAILED") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, token) {
  observed <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(identical(observed, token), paste0("C3_TEST_ERROR_MISMATCH:", token, ":", observed))
}
sha <- function(letter) paste(rep(letter, 64L), collapse = "")

## ---- Candidate fixture (mirrors build_c3_apply_candidate_1939_v50.py's
## exact five-case, six-record output shape) ------------------------------

assign_decision <- function(rid, record_key, target_person_id, side = "501",
                            raw_char = "a", norm_char = "b") {
  list(
    action = "assign", rid = rid, record_key = record_key,
    target_person_id = target_person_id,
    raw_sha256 = sha(raw_char),
    normalized_text = "PROSE-FIXTURE-NEVER-SENT-TO-RPC",
    normalized_sha256 = sha(norm_char),
    normalization_version = "narrative_norm_v1",
    normalization_flags = list(),
    expected_narrative = list(
      privat = FALSE, side = side, record_label = record_key,
      citation_label = paste("DAA 1939 side", side))
  )
}
no_publication_decision <- function(rid, record_key) {
  list(action = "no_publication", rid = rid, record_key = record_key)
}

candidate_cases <- function() {
  list(
    list(case_id = "case-1", identity = list(action = "different", person_ids = c(101, 201)),
         record_decisions = list(assign_decision("rid-1", "rk-1", 101))),
    list(case_id = "case-2", identity = list(action = "different", person_ids = c(102, 202)),
         record_decisions = list(assign_decision("rid-2", "rk-2", 102))),
    list(case_id = "case-3", identity = list(action = "different", person_ids = c(103, 203)),
         record_decisions = list(assign_decision("rid-3", "rk-3", 103))),
    list(case_id = "case-4", identity = list(action = "different", person_ids = c(104, 204)),
         record_decisions = list(assign_decision("rid-4", "rk-4", 104))),
    list(case_id = "case-5", identity = list(action = "different", person_ids = c(105, 205)),
         record_decisions = list(assign_decision("rid-5", "rk-5", 105),
                                 no_publication_decision("rid-6", "rk-6")))
  )
}

candidate_document <- function(cases = candidate_cases(), schema_version =
                               "1939-v50-c3-apply-candidate-v1") {
  list(
    schema_version = schema_version,
    input_hashes = list(decisions_sha256 = sha("1"), selection_sha256 = sha("2"),
                        state_sha256 = sha("3"), review_sha256 = sha("4"),
                        c0_candidates_sha256 = sha("5"), c0_decisions_sha256 = sha("6")),
    counts = list(cases = 5, identity_different = 5, record_assign = 5,
                 record_no_publication = 1),
    cases = cases,
    canonical_content_sha256 = sha("7")
  )
}

candidate_raw <- function(document = candidate_document()) {
  charToRaw(enc2utf8(as.character(
    jsonlite::toJSON(document, auto_unbox = TRUE, null = "null"))))
}

## ---- RPC response fixture, matched to the candidate above ---------------

DB_NAME <- "postgres"
SYSTEM_IDENTIFIER <- "1234567890123456789"

default_rpc_response <- function() {
  list(
    database_name = DB_NAME,
    system_identifier = SYSTEM_IDENTIFIER,
    identity_pairs = list(
      list(case_id = "case-1", person_ids = c(101, 201), component_overlap = FALSE, existing_rejection = FALSE),
      list(case_id = "case-2", person_ids = c(102, 202), component_overlap = FALSE, existing_rejection = FALSE),
      list(case_id = "case-3", person_ids = c(103, 203), component_overlap = FALSE, existing_rejection = FALSE),
      list(case_id = "case-4", person_ids = c(104, 204), component_overlap = FALSE, existing_rejection = FALSE),
      list(case_id = "case-5", person_ids = c(105, 205), component_overlap = FALSE, existing_rejection = FALSE)
    ),
    source_records = list(
      list(rid = "rid-1", record_key = "rk-1", match_count = 1, verbatim_sha256 = sha("a"), side = "501"),
      list(rid = "rid-2", record_key = "rk-2", match_count = 1, verbatim_sha256 = sha("a"), side = "501"),
      list(rid = "rid-3", record_key = "rk-3", match_count = 1, verbatim_sha256 = sha("a"), side = "501"),
      list(rid = "rid-4", record_key = "rk-4", match_count = 1, verbatim_sha256 = sha("a"), side = "501"),
      list(rid = "rid-5", record_key = "rk-5", match_count = 1, verbatim_sha256 = sha("a"), side = "501"),
      list(rid = "rid-6", record_key = "rk-6", match_count = 1, verbatim_sha256 = sha("e"), side = "502")
    ),
    target_narratives = list(
      list(rid = "rid-1", person_id = 101, narrative_id = 9001, privat = FALSE, old_sha256 = sha("c")),
      list(rid = "rid-2", person_id = 102, narrative_id = 9002, privat = FALSE, old_sha256 = sha("c")),
      list(rid = "rid-3", person_id = 103, narrative_id = 9003, privat = FALSE, old_sha256 = sha("c")),
      list(rid = "rid-4", person_id = 104, narrative_id = 9004, privat = FALSE, old_sha256 = sha("c")),
      list(rid = "rid-5", person_id = 105, narrative_id = 9005, privat = FALSE, old_sha256 = sha("c"))
    ),
    ## Exactly one row per candidate record_key, always, with explicit
    ## "absent" where there is none. Omission is not a safe default (see
    ## the Task 2 report) so every fixture must enumerate all six.
    bindings = list(
      list(record_key = "rk-1", status = "absent", binding_person_id = 101),
      list(record_key = "rk-2", status = "absent", binding_person_id = 102),
      list(record_key = "rk-3", status = "absent", binding_person_id = 103),
      list(record_key = "rk-4", status = "absent", binding_person_id = 104),
      list(record_key = "rk-5", status = "absent", binding_person_id = 105),
      list(record_key = "rk-6", status = "absent", binding_person_id = 106)
    ),
    source_anchors = list(),
    identity_components = list()
  )
}

## ---- Fake gateway: records exact call order, never touches a real DB ----

fake_gateway <- function(rpc_response = default_rpc_response(), rpc_error = NULL,
                         readonly = "on", database_name = DB_NAME,
                         system_identifier = SYSTEM_IDENTIFIER) {
  calls <- list()
  record <- function(kind, sql, params) {
    calls[[length(calls) + 1L]] <<- list(kind = kind, sql = sql, params = params)
  }
  execute <- function(sql, params = NULL) { record("execute", sql, params); invisible(NULL) }
  query <- function(sql, params = NULL) {
    record("query", sql, params)
    if (identical(sql, "SHOW transaction_read_only"))
      return(data.frame(transaction_read_only = readonly, stringsAsFactors = FALSE))
    if (identical(sql, "SELECT current_database()"))
      return(data.frame(current_database = database_name, stringsAsFactors = FALSE))
    if (grepl("system_identifier", sql, fixed = TRUE))
      return(data.frame(system_identifier = system_identifier, stringsAsFactors = FALSE))
    if (grepl("red_preview_reimport_cases", sql, fixed = TRUE)) {
      if (!is.null(rpc_error)) stop(rpc_error)
      return(data.frame(result = as.character(jsonlite::toJSON(
        rpc_response, auto_unbox = TRUE, null = "null")), stringsAsFactors = FALSE))
    }
    stop(paste("uventet fake-query:", sql))
  }
  list(query = query, execute = execute, calls = function() calls)
}

last_call_sql <- function(gateway) {
  calls <- gateway$calls()
  if (!length(calls)) return(NA_character_)
  tail(calls, 1L)[[1L]]$sql
}

run_build <- function(gateway = fake_gateway(), document = candidate_document(),
                      expected_database_name = DB_NAME) {
  build_c3_apply_database_preview(candidate_raw(document), gateway,
                                  expected_database_name)
}

expect_fail_closed <- function(gateway, token, document = candidate_document(),
                               expected_database_name = DB_NAME) {
  observed <- tryCatch({
    run_build(gateway, document, expected_database_name)
    ""
  }, error = function(e) conditionMessage(e))
  expect(identical(observed, token), paste0("C3_TEST_FAILCLOSED:", token, ":", observed))
  expect(identical(last_call_sql(gateway), "ROLLBACK"),
         paste0("C3_TEST_ROLLBACK_LAST:", token, ":", last_call_sql(gateway)))
}

modify_response <- function(mutator, base = default_rpc_response()) mutator(base)

## ==========================================================================
## Step 1: fixed 8-call gateway sequence and canonical output
## ==========================================================================

fg <- fake_gateway()
result <- run_build(fg)
calls <- fg$calls()

expect(length(calls) == 8L, paste0("C3_TEST_CALL_COUNT:", length(calls)))
expect(identical(calls[[1L]]$sql, "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY"),
       "C3_TEST_CALL_1_BEGIN")
expect(grepl("statement_timeout", calls[[2L]]$sql, fixed = TRUE), "C3_TEST_CALL_2_STMT_TIMEOUT")
expect(grepl("lock_timeout", calls[[3L]]$sql, fixed = TRUE), "C3_TEST_CALL_3_LOCK_TIMEOUT")
expect(identical(calls[[4L]]$sql, "SHOW transaction_read_only"), "C3_TEST_CALL_4_SHOW_READONLY")
expect(identical(calls[[5L]]$sql, "SELECT current_database()"), "C3_TEST_CALL_5_CURRENT_DATABASE")
expect(grepl("system_identifier", calls[[6L]]$sql, fixed = TRUE), "C3_TEST_CALL_6_SYSTEM_IDENTIFIER")
expect(!identical(calls[[5L]]$sql, calls[[6L]]$sql), "C3_TEST_CALL_5_6_DISTINCT")
expect(grepl("red_preview_reimport_cases", calls[[7L]]$sql, fixed = TRUE),
       "C3_TEST_CALL_7_RPC")
expect(identical(calls[[7L]]$kind, "query"), "C3_TEST_CALL_7_IS_QUERY")
expect(identical(calls[[8L]]$sql, "ROLLBACK"), "C3_TEST_CALL_8_ROLLBACK")
## Fund M1: under the single-RPC design (Fund H1) there is exactly one
## domain-state call, so there is no interleaving window a fake gateway
## could exercise for a genuine concurrent-mutation test, and a fake has no
## MVCC snapshot semantics at all. What is testable and tested here is the
## structural guarantee M1 actually depends on: the transaction opens under
## REPEATABLE READ before any state is read, verbatim, as call 1.
expect(grepl("REPEATABLE READ", calls[[1L]]$sql, fixed = TRUE), "C3_TEST_REPEATABLE_READ")

## No SELECT beyond the five/six identity+RPC calls: calls 5-7 are query, and
## no other query-kind call exists anywhere in the sequence.
query_calls <- Filter(function(c) identical(c$kind, "query"), calls)
expect(length(query_calls) == 4L, paste0("C3_TEST_QUERY_CALL_COUNT:", length(query_calls)))

## p_selection carries hashes, never prose.
selection_text <- calls[[7L]]$params[[3L]]
selection_sent <- jsonlite::fromJSON(selection_text, simplifyVector = FALSE)
expect(identical(selection_sent$schema_version, "1939-v50-c3-apply-selection-v1"),
       "C3_TEST_SELECTION_SCHEMA")
expect(length(selection_sent$cases) == 5L, "C3_TEST_SELECTION_CASE_COUNT")
expect(!grepl("normalized_text", selection_text, fixed = TRUE), "C3_TEST_SELECTION_NO_PROSE_FIELD")
expect(!grepl("PROSE-FIXTURE", selection_text, fixed = TRUE), "C3_TEST_SELECTION_NO_PROSE_CONTENT")
expect(identical(calls[[7L]]$params[[1L]], 3L), "C3_TEST_SELECTION_SOURCE_ID")
expect(identical(calls[[7L]]$params[[2L]], "c3"), "C3_TEST_SELECTION_PHASE")
## p_selection must be an ordinary character parameter, not a jsonlite
## `json`-classed object, so DBI/RPostgres parameter binding never has to
## guess how to coerce it.
expect(is.character(selection_text) && !inherits(selection_text, "json"),
       "C3_TEST_SELECTION_PLAIN_CHARACTER")

## Output envelope: exact candidate SHA, database identity, canonical rows,
## before-state forwarded unreshaped from the RPC.
expect(identical(result$schema_version, "1939-v50-c3-apply-db-preview-v1"),
       "C3_TEST_RESULT_SCHEMA")
expect(identical(result$candidate_file_sha256,
                 digest::digest(candidate_raw(), algo = "sha256", serialize = FALSE)),
       "C3_TEST_RESULT_CANDIDATE_SHA")
expect(identical(result$database$database_name, DB_NAME), "C3_TEST_RESULT_DB_NAME")
expect(identical(result$database$system_identifier, SYSTEM_IDENTIFIER), "C3_TEST_RESULT_SYSTEM_ID")
expect(length(result$before_state$identity_pairs) == 5L, "C3_TEST_RESULT_IDENTITY_COUNT")
expect(length(result$before_state$source_records) == 6L, "C3_TEST_RESULT_SOURCE_COUNT")
expect(length(result$before_state$target_narratives) == 5L, "C3_TEST_RESULT_TARGET_COUNT")
expect(is.list(result$candidate) &&
       identical(result$candidate$schema_version, "1939-v50-c3-apply-candidate-v1"),
       "C3_TEST_RESULT_CANDIDATE_FORWARDED")

## Fund H1 "byte-publish": the RPC's exact returned text is retained
## verbatim (not just re-derived structurally from the parsed copy), plus
## its digest, so a later authorize/apply step can hash-bind against it.
rpc_exact_text <- as.character(jsonlite::toJSON(default_rpc_response(),
                                                 auto_unbox = TRUE, null = "null"))
expect(identical(result$before_state_canonical, rpc_exact_text),
       "C3_TEST_RESULT_CANONICAL_BYTES_EXACT")
expect(identical(result$before_state_canonical_sha256,
                 digest::digest(rpc_exact_text, algo = "sha256", serialize = FALSE)),
       "C3_TEST_RESULT_CANONICAL_SHA256")

## ==========================================================================
## Step 1b: pure-input validation (before any gateway call)
## ==========================================================================

expect_error(build_c3_apply_database_preview(candidate_raw(), fake_gateway(), ""),
             "C3_PREVIEW_DATABASE_NAME_INVALID")
expect_error(build_c3_apply_database_preview(candidate_raw(), fake_gateway(), "bad name"),
             "C3_PREVIEW_DATABASE_NAME_INVALID")
expect_error(build_c3_apply_database_preview(candidate_raw(), list(query = 1, execute = 2), DB_NAME),
             "C3_PREVIEW_GATEWAY_INVALID")
expect_error(build_c3_apply_database_preview("not raw bytes", fake_gateway(), DB_NAME),
             "C3_PREVIEW_CANDIDATE_INVALID")
expect_error(build_c3_apply_database_preview(charToRaw("{not json"), fake_gateway(), DB_NAME),
             "C3_PREVIEW_CANDIDATE_INVALID")
expect_error(build_c3_apply_database_preview(
  candidate_raw(candidate_document(schema_version = "wrong")), fake_gateway(), DB_NAME),
  "C3_PREVIEW_CANDIDATE_INVALID")

wrong_counts <- candidate_document()
wrong_counts$counts$cases <- 4
expect_error(build_c3_apply_database_preview(candidate_raw(wrong_counts), fake_gateway(), DB_NAME),
             "C3_PREVIEW_CANDIDATE_INVALID")

duplicate_rid_cases <- candidate_cases()
duplicate_rid_cases[[2L]]$record_decisions[[1L]]$rid <- "rid-1"
expect_error(build_c3_apply_database_preview(
  candidate_raw(candidate_document(cases = duplicate_rid_cases)), fake_gateway(), DB_NAME),
  "C3_PREVIEW_CANDIDATE_INVALID")

## ==========================================================================
## Step 2: fail-closed preview scenarios (mocked RPC exceptions/malformed
## responses). The R wrapper never re-derives these conditions with its own
## SQL; it only fails closed on what the (fake) RPC gave it. Every scenario
## asserts rollback is the last recorded call.
## ==========================================================================

## -- Missing / duplicate source record (RPC's own match-count signal) -----
missing_match <- modify_response(function(r) { r$source_records[[6L]]$match_count <- 0; r })
expect_fail_closed(fake_gateway(rpc_response = missing_match), "C3_PREVIEW_SOURCE_RECORD_INVALID")

duplicate_match <- modify_response(function(r) { r$source_records[[6L]]$match_count <- 2; r })
expect_fail_closed(fake_gateway(rpc_response = duplicate_match), "C3_PREVIEW_SOURCE_RECORD_INVALID")

## -- Target person/narrative mismatch --------------------------------------
target_mismatch <- modify_response(function(r) { r$target_narratives[[1L]]$person_id <- 999; r })
expect_fail_closed(fake_gateway(rpc_response = target_mismatch), "C3_PREVIEW_TARGET_MISMATCH")

## -- Private drift ----------------------------------------------------------
private_drift <- modify_response(function(r) { r$target_narratives[[1L]]$privat <- TRUE; r })
expect_fail_closed(fake_gateway(rpc_response = private_drift), "C3_PREVIEW_PRIVATE_DRIFT")

## -- Text / side drift -------------------------------------------------------
text_drift <- modify_response(function(r) { r$source_records[[1L]]$verbatim_sha256 <- sha("f"); r })
expect_fail_closed(fake_gateway(rpc_response = text_drift), "C3_PREVIEW_TEXT_DRIFT")

side_drift <- modify_response(function(r) { r$source_records[[1L]]$side <- "999"; r })
expect_fail_closed(fake_gateway(rpc_response = side_drift), "C3_PREVIEW_SIDE_DRIFT")

## -- Active binding for a no_publication record -----------------------------
active_no_publication <- modify_response(function(r) {
  r$bindings[[6L]]$status <- "published"
  r$bindings[[6L]]$binding_person_id <- 105
  r
})
expect_fail_closed(fake_gateway(rpc_response = active_no_publication),
                   "C3_PREVIEW_BINDING_ACTIVE_FOR_NO_PUBLICATION")

## -- Assign binding outside absent|draft_same_record ------------------------
bad_assign_binding <- modify_response(function(r) {
  r$bindings[[1L]]$status <- "published"
  r
})
expect_fail_closed(fake_gateway(rpc_response = bad_assign_binding), "C3_PREVIEW_BINDING_INVALID")

draft_other_assign_binding <- modify_response(function(r) {
  r$bindings[[1L]]$status <- "draft_other_record"
  r
})
expect_fail_closed(fake_gateway(rpc_response = draft_other_assign_binding),
                   "C3_PREVIEW_BINDING_INVALID")

## -- Multiple bindings for one record (a real record_key is then, by
## pigeonhole, missing from the six-row set) ---------------------------------
duplicate_binding <- modify_response(function(r) {
  r$bindings[[2L]] <- r$bindings[[1L]]  ## rk-2's slot now duplicates rk-1
  r
})
expect_fail_closed(fake_gateway(rpc_response = duplicate_binding), "C3_PREVIEW_BINDING_INVALID")

## -- Missing binding row entirely (RPC under-reports; must not read as a
## safe "absent" default) -----------------------------------------------------
missing_binding_row <- modify_response(function(r) { r$bindings <- r$bindings[-1L]; r })
expect_fail_closed(fake_gateway(rpc_response = missing_binding_row), "C3_PREVIEW_RESPONSE_INVALID")

## -- Component overlap -------------------------------------------------------
component_overlap <- modify_response(function(r) {
  r$identity_pairs[[1L]]$component_overlap <- TRUE; r
})
expect_fail_closed(fake_gateway(rpc_response = component_overlap), "C3_PREVIEW_COMPONENT_OVERLAP")

## -- Existing cross-component rejection drift -------------------------------
existing_rejection <- modify_response(function(r) {
  r$identity_pairs[[1L]]$existing_rejection <- TRUE; r
})
expect_fail_closed(fake_gateway(rpc_response = existing_rejection), "C3_PREVIEW_IDENTITY_REJECTED")

## -- Identity pair drift (person set changed under the case_id) ------------
identity_pair_drift <- modify_response(function(r) {
  r$identity_pairs[[1L]]$person_ids <- c(101, 999); r
})
expect_fail_closed(fake_gateway(rpc_response = identity_pair_drift),
                   "C3_PREVIEW_IDENTITY_PAIR_MISMATCH")

## -- Wrong database (own identity query, not the RPC echo) -----------------
expect_fail_closed(fake_gateway(), "C3_PREVIEW_DATABASE_MISMATCH",
                   expected_database_name = "a-different-database")

## -- RPC echo disagrees with the wrapper's own identity queries -------------
echo_mismatch <- modify_response(function(r) { r$system_identifier <- "999"; r })
expect_fail_closed(fake_gateway(rpc_response = echo_mismatch), "C3_PREVIEW_RPC_ECHO_MISMATCH")

## -- Not read-only -----------------------------------------------------------
expect_fail_closed(fake_gateway(readonly = "off"), "C3_PREVIEW_NOT_READ_ONLY")

## -- Missing capability: the RPC itself does not exist yet (Task 6) --------
undefined_function_condition <- structure(
  class = c("undefined_function", "error", "condition"),
  list(message = "function public.red_preview_reimport_cases(bigint, text, jsonb) does not exist",
       call = NULL))
expect_fail_closed(fake_gateway(rpc_error = undefined_function_condition),
                   "C3_PREVIEW_RPC_CAPABILITY_MISSING")

message_only_undefined <- simpleError("ERROR:  42883: function does not exist")
expect_fail_closed(fake_gateway(rpc_error = message_only_undefined),
                   "C3_PREVIEW_RPC_CAPABILITY_MISSING")

## -- Any other RPC failure fails closed too, generically --------------------
generic_rpc_failure <- simpleError("connection reset by peer")
expect_fail_closed(fake_gateway(rpc_error = generic_rpc_failure), "C3_PREVIEW_RPC_FAILED")

## -- Malformed RPC response shapes -------------------------------------------
extra_top_level_key <- modify_response(function(r) { r$unexpected <- "x"; r })
expect_fail_closed(fake_gateway(rpc_response = extra_top_level_key), "C3_PREVIEW_RESPONSE_INVALID")

missing_top_level_key <- modify_response(function(r) { r$bindings <- NULL; r })
expect_fail_closed(fake_gateway(rpc_response = missing_top_level_key), "C3_PREVIEW_RESPONSE_INVALID")

wrong_identity_pair_count <- modify_response(function(r) { r$identity_pairs <- r$identity_pairs[-1L]; r })
expect_fail_closed(fake_gateway(rpc_response = wrong_identity_pair_count), "C3_PREVIEW_RESPONSE_INVALID")

unknown_binding_record_key <- modify_response(function(r) {
  r$bindings[[1L]]$record_key <- "not-a-known-key"  ## rk-1 then, by pigeonhole, missing
  r
})
expect_fail_closed(fake_gateway(rpc_response = unknown_binding_record_key), "C3_PREVIEW_RESPONSE_INVALID")

## RPC query returns the wrong column entirely (no `result` column).
wrong_column_gateway <- (function() {
  base <- fake_gateway()
  calls <- list()
  record <- function(kind, sql, params) calls[[length(calls) + 1L]] <<- list(kind = kind, sql = sql, params = params)
  execute <- function(sql, params = NULL) { record("execute", sql, params); invisible(NULL) }
  query <- function(sql, params = NULL) {
    record("query", sql, params)
    if (grepl("red_preview_reimport_cases", sql, fixed = TRUE))
      return(data.frame(unexpected_column = "x", stringsAsFactors = FALSE))
    base$query(sql, params)
  }
  list(query = query, execute = execute, calls = function() calls)
})()
expect_fail_closed(wrong_column_gateway, "C3_PREVIEW_RESPONSE_INVALID")

## RPC query returns zero rows.
zero_row_gateway <- (function() {
  base <- fake_gateway()
  calls <- list()
  record <- function(kind, sql, params) calls[[length(calls) + 1L]] <<- list(kind = kind, sql = sql, params = params)
  execute <- function(sql, params = NULL) { record("execute", sql, params); invisible(NULL) }
  query <- function(sql, params = NULL) {
    record("query", sql, params)
    if (grepl("red_preview_reimport_cases", sql, fixed = TRUE))
      return(data.frame(result = character(0), stringsAsFactors = FALSE))
    base$query(sql, params)
  }
  list(query = query, execute = execute, calls = function() calls)
})()
expect_fail_closed(zero_row_gateway, "C3_PREVIEW_RESPONSE_INVALID")

## -- Fund 2 (review fix round 1): field-type checks previously missing on
## target_narratives.narrative_id/old_sha256, bindings.binding_person_id,
## and source_records.side for non-assign rows. Each malformed variant
## below must fail closed as C3_PREVIEW_RESPONSE_INVALID, and each
## corresponding NULL-is-allowed variant must still build successfully.
## `x[name] <- list(NULL)` is used (not `x$name <- NULL` / `x[[name]] <-
## NULL`, both of which DELETE the list element in R) to set a field to a
## real NULL while keeping the key present, matching how jsonlite parses a
## JSON `null` value from a real RPC response. ------------------------------

set_null_field <- function(lst, name) { lst[name] <- list(NULL); lst }

wrong_type_narrative_id <- modify_response(function(r) {
  r$target_narratives[[1L]]$narrative_id <- "not-a-number"; r
})
expect_fail_closed(fake_gateway(rpc_response = wrong_type_narrative_id),
                   "C3_PREVIEW_RESPONSE_INVALID")

null_narrative_id <- modify_response(function(r) {
  r$target_narratives[[1L]] <- set_null_field(r$target_narratives[[1L]], "narrative_id")
  r
})
null_narrative_id_result <- run_build(fake_gateway(rpc_response = null_narrative_id))
expect(is.null(null_narrative_id_result$before_state$target_narratives[[1L]]$narrative_id),
       "C3_TEST_NARRATIVE_ID_NULL_ALLOWED")

wrong_type_old_sha256 <- modify_response(function(r) {
  r$target_narratives[[1L]]$old_sha256 <- 12345; r
})
expect_fail_closed(fake_gateway(rpc_response = wrong_type_old_sha256),
                   "C3_PREVIEW_RESPONSE_INVALID")

malformed_old_sha256 <- modify_response(function(r) {
  r$target_narratives[[1L]]$old_sha256 <- "not-64-hex"; r
})
expect_fail_closed(fake_gateway(rpc_response = malformed_old_sha256),
                   "C3_PREVIEW_RESPONSE_INVALID")

null_old_sha256 <- modify_response(function(r) {
  r$target_narratives[[1L]] <- set_null_field(r$target_narratives[[1L]], "old_sha256")
  r
})
null_old_sha256_result <- run_build(fake_gateway(rpc_response = null_old_sha256))
expect(is.null(null_old_sha256_result$before_state$target_narratives[[1L]]$old_sha256),
       "C3_TEST_OLD_SHA256_NULL_ALLOWED")

wrong_type_binding_person_id <- modify_response(function(r) {
  r$bindings[[1L]]$binding_person_id <- "not-a-number"; r
})
expect_fail_closed(fake_gateway(rpc_response = wrong_type_binding_person_id),
                   "C3_PREVIEW_RESPONSE_INVALID")

null_binding_person_id <- modify_response(function(r) {
  r$bindings[[1L]] <- set_null_field(r$bindings[[1L]], "binding_person_id")
  r
})
null_binding_person_id_result <- run_build(fake_gateway(rpc_response = null_binding_person_id))
expect(is.null(null_binding_person_id_result$before_state$bindings[[1L]]$binding_person_id),
       "C3_TEST_BINDING_PERSON_ID_NULL_ALLOWED")

wrong_type_no_publication_side <- modify_response(function(r) {
  r$source_records[[6L]]$side <- 502; r  ## rid-6/rk-6 is the no_publication row
})
expect_fail_closed(fake_gateway(rpc_response = wrong_type_no_publication_side),
                   "C3_PREVIEW_RESPONSE_INVALID")

## -- Fund 3 (review fix round 1): a draft_same_record binding must be bound
## to the case's own target person; a draft bound to a DIFFERENT person must
## fail closed instead of passing as a clean absent-equivalent state. -------

draft_same_record_wrong_person <- modify_response(function(r) {
  r$bindings[[1L]]$status <- "draft_same_record"
  r$bindings[[1L]]$binding_person_id <- 999  ## rk-1's assign target is 101
  r
})
expect_fail_closed(fake_gateway(rpc_response = draft_same_record_wrong_person),
                   "C3_PREVIEW_BINDING_INVALID")

draft_same_record_matching_person <- modify_response(function(r) {
  r$bindings[[1L]]$status <- "draft_same_record"
  r$bindings[[1L]]$binding_person_id <- 101  ## matches rk-1's assign target
  r
})
draft_same_record_ok_result <- run_build(fake_gateway(rpc_response = draft_same_record_matching_person))
expect(identical(draft_same_record_ok_result$before_state$bindings[[1L]]$status,
                 "draft_same_record"),
       "C3_TEST_DRAFT_SAME_RECORD_MATCHING_PERSON_ALLOWED")

## Non-jsonb-looking result text (invalid JSON) also fails closed.
invalid_json_gateway <- (function() {
  base <- fake_gateway()
  calls <- list()
  record <- function(kind, sql, params) calls[[length(calls) + 1L]] <<- list(kind = kind, sql = sql, params = params)
  execute <- function(sql, params = NULL) { record("execute", sql, params); invisible(NULL) }
  query <- function(sql, params = NULL) {
    record("query", sql, params)
    if (grepl("red_preview_reimport_cases", sql, fixed = TRUE))
      return(data.frame(result = "{not valid json", stringsAsFactors = FALSE))
    base$query(sql, params)
  }
  list(query = query, execute = execute, calls = function() calls)
})()
expect_fail_closed(invalid_json_gateway, "C3_PREVIEW_RESPONSE_INVALID")

## ==========================================================================
## Rollback discipline: every one of the fail-closed cases above already
## asserted ROLLBACK was the final recorded call via expect_fail_closed().
## ==========================================================================

## ==========================================================================
## CLI preflight: DB-free. Every scenario here must fail before any
## DBI::dbConnect() attempt (never touches the network), mirroring the
## current-state exporter's `run_cli` discipline exactly.
## ==========================================================================

run_cli <- function(argv, pg_env) {
  result <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(file.path(script_dir, "export_c3_apply_preview_1939_v50.R"), argv),
    stdout = TRUE, stderr = TRUE, env = pg_env
  ))
  list(status = if (is.null(attr(result, "status"))) 0L else attr(result, "status"),
       output = result)
}
empty_pg <- c("PGDATABASE=", "PGHOST=", "PGPORT=", "PGUSER=", "PGPASSWORD=")
partial_pg <- c("PGDATABASE=postgres", "PGHOST=", "PGPORT=", "PGUSER=", "PGPASSWORD=")

candidate_path <- tempfile(fileext = ".json")
output_path <- tempfile(fileext = ".json")
unlink(output_path)
on.exit(unlink(c(candidate_path, output_path)), add = TRUE)
writeBin(candidate_raw(), candidate_path)

bad_args_cli <- run_cli(c("--candidate", candidate_path), empty_pg)
expect(identical(as.integer(bad_args_cli$status), 1L) &&
       length(bad_args_cli$output) == 1L &&
       identical(bad_args_cli$output[[1L]], "C3_PREVIEW_ARGUMENTS_INVALID"),
       paste0("C3_TEST_CLI_ARGS_PREFLIGHT:", bad_args_cli$status, ":",
              paste(bad_args_cli$output, collapse = "|")))

bad_db_name_cli <- run_cli(c("--candidate", candidate_path, "--output", output_path,
                             "--expect-database-name", "bad!name"), empty_pg)
expect(identical(as.integer(bad_db_name_cli$status), 1L) &&
       length(bad_db_name_cli$output) == 1L &&
       identical(bad_db_name_cli$output[[1L]], "C3_PREVIEW_DATABASE_NAME_INVALID"),
       paste0("C3_TEST_CLI_DBNAME_PREFLIGHT:", bad_db_name_cli$status, ":",
              paste(bad_db_name_cli$output, collapse = "|")))

writeBin(charToRaw("placeholder"), output_path)
output_exists_cli <- run_cli(c("--candidate", candidate_path, "--output", output_path,
                               "--expect-database-name", "postgres"), empty_pg)
unlink(output_path)
expect(identical(as.integer(output_exists_cli$status), 1L) &&
       length(output_exists_cli$output) == 1L &&
       identical(output_exists_cli$output[[1L]], "C3_PREVIEW_OUTPUT_EXISTS"),
       paste0("C3_TEST_CLI_OUTPUT_EXISTS_PREFLIGHT:", output_exists_cli$status, ":",
              paste(output_exists_cli$output, collapse = "|")))

malformed_candidate_path <- tempfile(fileext = ".json")
on.exit(unlink(malformed_candidate_path), add = TRUE)
writeBin(charToRaw("[]"), malformed_candidate_path)
malformed_candidate_cli <- run_cli(c("--candidate", malformed_candidate_path,
                                     "--output", output_path,
                                     "--expect-database-name", "postgres"), empty_pg)
expect(identical(as.integer(malformed_candidate_cli$status), 1L) &&
       length(malformed_candidate_cli$output) == 1L &&
       identical(malformed_candidate_cli$output[[1L]], "C3_PREVIEW_CANDIDATE_INVALID"),
       paste0("C3_TEST_CLI_CANDIDATE_PREFLIGHT:", malformed_candidate_cli$status, ":",
              paste(malformed_candidate_cli$output, collapse = "|")))

pg_env_cli <- run_cli(c("--candidate", candidate_path, "--output", output_path,
                        "--expect-database-name", "postgres"), partial_pg)
expect(identical(as.integer(pg_env_cli$status), 1L) &&
       length(pg_env_cli$output) == 1L &&
       identical(pg_env_cli$output[[1L]], "C3_PREVIEW_PG_ENV_INVALID"),
       paste0("C3_TEST_CLI_PG_ENV_PREFLIGHT:", pg_env_cli$status, ":",
              paste(pg_env_cli$output, collapse = "|")))

## Safe-output discipline: a credential sentinel present in the environment
## (but insufficient to reach a real connection attempt, per the partial-env
## gate above) must never appear, name or value, in stdout/stderr.
sentinel_pg <- c("PGDATABASE=sentinel-db", "PGHOST=", "PGPORT=6543",
                 "PGUSER=sentinel-user", "PGPASSWORD=SENTINEL-SECRET-VALUE")
sentinel_cli <- run_cli(c("--candidate", candidate_path, "--output", output_path,
                          "--expect-database-name", "postgres"), sentinel_pg)
sentinel_text <- paste(sentinel_cli$output, collapse = "\n")
expect(identical(as.integer(sentinel_cli$status), 1L) &&
       identical(sentinel_cli$output[[1L]], "C3_PREVIEW_PG_ENV_INVALID"),
       paste0("C3_TEST_CLI_SENTINEL_PREFLIGHT:", sentinel_cli$status))
expect(!grepl("SENTINEL-SECRET-VALUE", sentinel_text, fixed = TRUE), "C3_TEST_CLI_NO_PASSWORD_VALUE")
expect(!grepl("PGPASSWORD", sentinel_text, fixed = TRUE), "C3_TEST_CLI_NO_PASSWORD_NAME")
expect(!grepl("sentinel-user", sentinel_text, fixed = TRUE), "C3_TEST_CLI_NO_USER_VALUE")
expect(!grepl("sentinel-db", sentinel_text, fixed = TRUE), "C3_TEST_CLI_NO_DBNAME_VALUE")

cat(sprintf("test_export_c3_apply_preview_1939_v50: %d assertions OK\n", ok))
