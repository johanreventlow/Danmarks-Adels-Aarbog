## Pure, DB-free transformation and gateway-orchestration for the C3 apply
## database preview. Every entry point sources
## c3_export_shared_1939_v50_helpers.R before this file.
##
## Fund H1: this script has no SQL registry of its own for domain state. It
## calls `public.red_preview_reimport_cases(p_source_id, p_phase,
## p_selection)` exactly once through the injected `gateway`, and forwards
## its canonical jsonb answer into the preview envelope unreshaped. This
## file only re-derives what is explicitly the R wrapper's own
## responsibility per the Task 2 ruling: database identity (its own two
## queries), and fail-closed structural/cross-checks of the RPC's answer
## against the candidate it was asked about. It never re-derives DB state
## with its own SQL.

## ---- Constants (documented, not CLI-configurable; see report) ----------

.c3_preview_source_id_1939 <- 3L
.c3_preview_phase <- "c3"
## Duplicated verbatim from apply_c3_1939_v50_helpers.R's own
## `.c3_apply_uuid_pattern` (not sourced from there -- this file's own header
## says every entry point sources only c3_export_shared_1939_v50_helpers.R
## plus its own task-specific helpers file, and the shared file defines no
## UUID pattern of its own). Same shape, same reason: RFC 4122 textual UUID.
.c3_preview_actor_id_pattern <-
  "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
## Task 2 addendum: `public.red_preview_reimport_cases` is SECURITY DEFINER
## and its first statement is `PERFORM private.require_reimport_1939_editor()`,
## which resolves `auth.uid()` from `request.jwt.claim.sub` and rejects unless
## the matching `profiles` row has `rolle='redaktion'` (schema.sql, function
## body at ~line 7387; the role gate itself at ~line 2377-2385). A direct DBI
## connection carries no JWT, so `auth.uid()` is NULL until this is set.
## `true` (transaction-local): confirmed empirically that `set_config(...,
## true)` issued in an implicit single-statement transaction reverts before
## the next explicit `BEGIN`, so this must run *inside* the same transaction
## as the RPC call, not before it opens -- mirroring
## `apply_c3_1939_v50_helpers.R`'s own `.c3_apply_prologue`, which sets it as
## the first statement immediately after `BEGIN`, not before.
.c3_preview_jwt_sql <- "SELECT set_config('request.jwt.claim.sub', $1, true) AS jwt_subject"
.c3_preview_statement_timeout_sql <- "SET LOCAL statement_timeout = '30s'"
.c3_preview_lock_timeout_sql <- "SET LOCAL lock_timeout = '2s'"
.c3_preview_rpc_response_keys <- c(
  "database_name", "system_identifier", "identity_pairs", "source_records",
  "target_narratives", "bindings", "source_anchors", "identity_components")
.c3_preview_identity_pair_keys <- c(
  "case_id", "person_ids", "component_overlap", "existing_rejection")
.c3_preview_source_record_keys <- c(
  "rid", "record_key", "match_count", "verbatim_sha256", "side")
.c3_preview_target_narrative_keys <- c(
  "rid", "person_id", "narrative_id", "privat", "old_text", "old_sha256")
.c3_preview_binding_keys <- c("record_key", "status", "binding_person_id")
.c3_preview_binding_statuses <- c(
  "absent", "draft_same_record", "draft_other_record", "published", "withdrawn")

## ---- Candidate structural validation (Task 1's output, byte-bound) -----

## `candidate_raw` is the exact raw bytes of the candidate-manifest file
## produced by build_c3_apply_candidate_1939_v50.py. Its
## `canonical_content_sha256` field is treated as an opaque value defined
## and computed by that Python builder; this function never recomputes it
## (doing so would require byte-exact reproduction of Python's
## json.dumps(sort_keys=True, separators=(",",":")) canonicalization in R,
## which is a needless and fragile duplication). The candidate's identity
## for every downstream consumer is instead the SHA-256 of these exact raw
## bytes, computed once by the CLI entry point via `digest::digest(...,
## serialize = FALSE)` and threaded through as `candidate_file_sha256`.
.c3_preview_parse_candidate <- function(candidate_raw) {
  if (!is.raw(candidate_raw)) .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
  candidate <- tryCatch(
    jsonlite::fromJSON(rawToChar(candidate_raw), simplifyVector = FALSE),
    error = function(e) .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID"))
  if (!is.list(candidate) ||
      !identical(candidate$schema_version, "1939-v50-c3-apply-candidate-v1") ||
      !.c3_common_scalar_string(candidate$canonical_content_sha256,
                                 "^[0-9a-f]{64}$"))
    .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
  scalar_count <- function(value, expected) {
    is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value == expected
  }
  counts <- candidate$counts
  if (!is.list(counts) || !setequal(names(counts),
        c("cases", "identity_different", "record_assign", "record_no_publication")) ||
      !scalar_count(counts$cases, 5) ||
      !scalar_count(counts$identity_different, 5) ||
      !scalar_count(counts$record_assign, 4) ||
      !scalar_count(counts$record_no_publication, 2))
    .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
  cases <- candidate$cases
  if (!is.list(cases) || length(cases) != 5L)
    .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")

  case_ids <- character(0L)
  all_records <- list()
  for (case in cases) {
    identity <- case$identity
    person_ids <- identity$person_ids
    if (!is.list(case) || !.c3_common_scalar_string(case$case_id) ||
        !is.list(identity) || !identical(identity$action, "different") ||
        !is.list(person_ids) || length(person_ids) != 2L ||
        !all(vapply(person_ids, function(x) is.numeric(x) && length(x) == 1L &&
                     !is.na(x) && x == floor(x) && x > 0, logical(1))))
      .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
    person_id_values <- as.numeric(unlist(person_ids))
    if (person_id_values[[1L]] >= person_id_values[[2L]])
      .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
    case_ids <- c(case_ids, case$case_id)

    decisions <- case$record_decisions
    if (!is.list(decisions) || length(decisions) < 1L)
      .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
    for (decision in decisions) {
      if (!is.list(decision) || !.c3_common_scalar_string(decision$rid))
        .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
      action <- decision$action
      if (identical(action, "assign")) {
        expected_narrative <- decision$expected_narrative
        if (!.c3_common_scalar_string(decision$record_key) ||
            !is.numeric(decision$target_person_id) ||
            length(decision$target_person_id) != 1L ||
            !.c3_common_scalar_string(decision$target_display_name) ||
            !.c3_common_scalar_string(decision$source_text) ||
            !.c3_common_scalar_string(decision$raw_sha256, "^[0-9a-f]{64}$") ||
            !.c3_common_scalar_string(decision$normalized_sha256, "^[0-9a-f]{64}$") ||
            !is.list(expected_narrative) ||
            !identical(expected_narrative$privat, FALSE) ||
            !.c3_common_scalar_string(expected_narrative$side))
          .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
        source_sha256 <- digest::digest(
          charToRaw(enc2utf8(decision$source_text)),
          algo = "sha256", serialize = FALSE)
        if (!identical(source_sha256, decision$raw_sha256))
          .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
      } else if (identical(action, "no_publication")) {
        if (!.c3_common_scalar_string(decision$record_key))
          .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
      } else {
        .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
      }
      all_records[[length(all_records) + 1L]] <- list(
        case_id = case$case_id, decision = decision)
    }
  }
  if (anyDuplicated(case_ids)) .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
  if (length(all_records) != 6L) .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
  rids <- vapply(all_records, function(x) x$decision$rid, character(1))
  if (anyDuplicated(rids)) .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")
  assign_n <- sum(vapply(all_records,
    function(x) identical(x$decision$action, "assign"), logical(1)))
  no_pub_n <- sum(vapply(all_records,
    function(x) identical(x$decision$action, "no_publication"), logical(1)))
  if (assign_n != 4L || no_pub_n != 2L)
    .c3_common_stop("C3_PREVIEW_CANDIDATE_INVALID")

  candidate
}

## ---- p_selection construction (documented contract for Task 6) ---------

## Builds the jsonb `p_selection` argument for
## `public.red_preview_reimport_cases`. Deliberately excludes narrative
## prose (`normalized_text`, `normalization_flags`,
## `normalization_version`): the RPC only needs hashes to measure drift, so
## prose never travels as a query parameter. See the Task 2 report for the
## full documented contract this binds Task 6 to.
.c3_preview_build_selection <- function(candidate) {
  cases <- lapply(candidate$cases, function(case) {
    person_ids <- as.integer(unlist(case$identity$person_ids))
    records <- lapply(case$record_decisions, function(decision) {
      if (identical(decision$action, "assign")) {
        list(
          rid = decision$rid, record_key = decision$record_key,
          action = "assign",
          target_person_id = as.integer(decision$target_person_id),
          raw_sha256 = decision$raw_sha256,
          normalized_sha256 = decision$normalized_sha256
        )
      } else {
        list(rid = decision$rid, record_key = decision$record_key,
             action = "no_publication")
      }
    })
    list(case_id = case$case_id,
         identity_pair = list(person_ids = person_ids),
         records = records)
  })
  list(schema_version = "1939-v50-c3-apply-selection-v1", cases = cases)
}

## Returns a plain character scalar (not a jsonlite `json`-classed object):
## DBI/RPostgres parameter binding must receive an ordinary character value.
.c3_preview_selection_json <- function(candidate) {
  as.character(jsonlite::toJSON(.c3_preview_build_selection(candidate),
                                auto_unbox = TRUE, null = "null"))
}

## ---- RPC response validation ---------------------------------------

.c3_preview_candidate_index <- function(candidate) {
  identity_by_case <- list()
  record_by_rid <- list()
  for (case in candidate$cases) {
    identity_by_case[[case$case_id]] <- as.numeric(unlist(case$identity$person_ids))
    for (decision in case$record_decisions) record_by_rid[[decision$rid]] <- decision
  }
  list(identity_by_case = identity_by_case, record_by_rid = record_by_rid)
}

.c3_preview_exact_keys <- function(value, expected, token) {
  if (!is.list(value) || !identical(sort(names(value)), sort(expected)))
    .c3_common_stop(token)
}

## Validates the RPC's parsed jsonb response against the candidate it was
## asked to measure, and against the wrapper's own database-identity
## queries. Fails closed with a specific token on the first structural or
## business-rule violation. Returns the (unmodified) response on success.
.c3_preview_validate_response <- function(response, candidate, database_name,
                                          system_identifier) {
  .c3_preview_exact_keys(response, .c3_preview_rpc_response_keys,
                          "C3_PREVIEW_RESPONSE_INVALID")
  if (!.c3_common_scalar_string(response$database_name) ||
      !identical(response$database_name, database_name) ||
      !.c3_common_scalar_string(response$system_identifier) ||
      !identical(response$system_identifier, system_identifier))
    .c3_common_stop("C3_PREVIEW_RPC_ECHO_MISMATCH")

  idx <- .c3_preview_candidate_index(candidate)

  ## identity_pairs: exactly 5, keyed by case_id, matched 1:1 against the
  ## candidate's 5 identity-different cases.
  identity_pairs <- response$identity_pairs
  if (!is.list(identity_pairs) || length(identity_pairs) != 5L)
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
  seen_cases <- character(0L)
  for (pair in identity_pairs) {
    .c3_preview_exact_keys(pair, .c3_preview_identity_pair_keys,
                            "C3_PREVIEW_RESPONSE_INVALID")
    case_id <- pair$case_id
    if (!.c3_common_scalar_string(case_id) ||
        is.null(idx$identity_by_case[[case_id]]) ||
        !is.logical(pair$component_overlap) || length(pair$component_overlap) != 1L ||
        is.na(pair$component_overlap) ||
        !is.logical(pair$existing_rejection) || length(pair$existing_rejection) != 1L ||
        is.na(pair$existing_rejection))
      .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    person_ids <- pair$person_ids
    if (!is.list(person_ids) || length(person_ids) != 2L ||
        !all(vapply(person_ids, function(x) is.numeric(x) && length(x) == 1L,
                     logical(1))))
      .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    observed <- as.numeric(unlist(person_ids))
    if (!identical(observed, idx$identity_by_case[[case_id]]))
      .c3_common_stop("C3_PREVIEW_IDENTITY_PAIR_MISMATCH")
    if (isTRUE(pair$component_overlap)) .c3_common_stop("C3_PREVIEW_COMPONENT_OVERLAP")
    if (isTRUE(pair$existing_rejection)) .c3_common_stop("C3_PREVIEW_IDENTITY_REJECTED")
    seen_cases <- c(seen_cases, case_id)
  }
  if (anyDuplicated(seen_cases) || !setequal(seen_cases, names(idx$identity_by_case)))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")

  ## source_records: exactly 6, one per candidate rid, unique match, current
  ## verbatim hash / side checked against the candidate for assign rows.
  source_records <- response$source_records
  if (!is.list(source_records) || length(source_records) != 6L)
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
  seen_rids <- character(0L)
  for (row in source_records) {
    .c3_preview_exact_keys(row, .c3_preview_source_record_keys,
                            "C3_PREVIEW_RESPONSE_INVALID")
    rid <- row$rid
    decision <- idx$record_by_rid[[rid]]
    if (!.c3_common_scalar_string(rid) || is.null(decision) ||
        !.c3_common_scalar_string(row$record_key) ||
        !identical(row$record_key, decision$record_key) ||
        !is.numeric(row$match_count) || length(row$match_count) != 1L ||
        !.c3_common_scalar_string(row$verbatim_sha256, "^[0-9a-f]{64}$") ||
        ## `side` is typechecked for every row, not only assign rows (Fund 2):
        ## a no_publication row's `side` was previously never inspected at
        ## all, so a wrong-typed value there passed the audit silently.
        !.c3_common_scalar_string(row$side))
      .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    if (!identical(as.numeric(row$match_count), 1))
      .c3_common_stop("C3_PREVIEW_SOURCE_RECORD_INVALID")
    if (identical(decision$action, "assign")) {
      if (!identical(row$verbatim_sha256, decision$raw_sha256))
        .c3_common_stop("C3_PREVIEW_TEXT_DRIFT")
      if (!identical(row$side, decision$expected_narrative$side))
        .c3_common_stop("C3_PREVIEW_SIDE_DRIFT")
    }
    seen_rids <- c(seen_rids, rid)
  }
  if (anyDuplicated(seen_rids) || !setequal(seen_rids, names(idx$record_by_rid)))
    .c3_common_stop("C3_PREVIEW_SOURCE_RECORD_INVALID")

  ## target_narratives: exactly one per assign rid, person/privat checked.
  assign_rids <- names(Filter(function(d) identical(d$action, "assign"),
                              idx$record_by_rid))
  target_narratives <- response$target_narratives
  if (!is.list(target_narratives) ||
      length(target_narratives) != length(assign_rids))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
  seen_target_rids <- character(0L)
  for (row in target_narratives) {
    .c3_preview_exact_keys(row, .c3_preview_target_narrative_keys,
                            "C3_PREVIEW_RESPONSE_INVALID")
    rid <- row$rid
    decision <- idx$record_by_rid[[rid]]
    ## narrative_id: int|null (Fund 2 — previously not typechecked at all).
    narrative_id_ok <- is.null(row$narrative_id) ||
      (is.numeric(row$narrative_id) && length(row$narrative_id) == 1L &&
       !is.na(row$narrative_id) && is.finite(row$narrative_id) &&
       row$narrative_id == floor(row$narrative_id) && row$narrative_id > 0)
    ## old_sha256: 64-hex string|null (Fund 2 — previously not typechecked).
    old_sha256_ok <- is.null(row$old_sha256) ||
      .c3_common_scalar_string(row$old_sha256, "^[0-9a-f]{64}$")
    old_text_ok <- is.null(row$old_text) || .c3_common_scalar_string(row$old_text)
    if (!.c3_common_scalar_string(rid) || is.null(decision) ||
        !identical(decision$action, "assign") ||
        !is.numeric(row$person_id) || length(row$person_id) != 1L ||
        !is.logical(row$privat) || length(row$privat) != 1L || is.na(row$privat) ||
        !narrative_id_ok || !old_text_ok || !old_sha256_ok)
      .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    if (is.null(row$narrative_id)) {
      if (!is.null(row$old_text) || !is.null(row$old_sha256))
        .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    } else {
      if (is.null(row$old_text) || is.null(row$old_sha256))
        .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
      measured_old_sha256 <- digest::digest(
        charToRaw(enc2utf8(row$old_text)), algo = "sha256", serialize = FALSE)
      if (!identical(measured_old_sha256, row$old_sha256))
        .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    }
    if (!identical(as.numeric(row$person_id), as.numeric(decision$target_person_id)))
      .c3_common_stop("C3_PREVIEW_TARGET_MISMATCH")
    if (isTRUE(row$privat)) .c3_common_stop("C3_PREVIEW_PRIVATE_DRIFT")
    seen_target_rids <- c(seen_target_rids, rid)
  }
  if (anyDuplicated(seen_target_rids) || !setequal(seen_target_rids, assign_rids))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")

  ## bindings: exactly one row per candidate record_key (6, always), with
  ## explicit status "absent" where none exists. Omission is deliberately
  ## NOT treated as "absent": an under-reporting RPC (silently dropping a
  ## record that actually has an active binding) must fail closed as a
  ## malformed response, not authorize a preview as if that record were
  ## clean. Business rule per action: assign allows absent|draft_same_record;
  ## no_publication forbids an active (published) binding.
  bindings <- response$bindings
  known_record_keys <- vapply(idx$record_by_rid, function(d) d$record_key, character(1))
  if (!is.list(bindings) || length(bindings) != length(known_record_keys))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
  seen_binding_keys <- character(0L)
  for (row in bindings) {
    .c3_preview_exact_keys(row, .c3_preview_binding_keys,
                            "C3_PREVIEW_RESPONSE_INVALID")
    record_key <- row$record_key
    ## binding_person_id: int|null (Fund 2 — previously not typechecked at
    ## all, and never cross-checked against anything — see Fund 3 below).
    binding_person_id_ok <- is.null(row$binding_person_id) ||
      (is.numeric(row$binding_person_id) && length(row$binding_person_id) == 1L &&
       !is.na(row$binding_person_id) && is.finite(row$binding_person_id) &&
       row$binding_person_id == floor(row$binding_person_id) &&
       row$binding_person_id > 0)
    if (!.c3_common_scalar_string(record_key) ||
        !(record_key %in% known_record_keys) ||
        !.c3_common_scalar_string(row$status) ||
        !(row$status %in% .c3_preview_binding_statuses) ||
        !binding_person_id_ok)
      .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
    if (record_key %in% seen_binding_keys)
      .c3_common_stop("C3_PREVIEW_BINDING_INVALID")
    ## `absent` is a complete state assertion, not merely a presentation
    ## label.  It is contradictory (and therefore unsafe) for the RPC to
    ## report both "absent" and an owning person id.
    if (identical(row$status, "absent") && !is.null(row$binding_person_id))
      .c3_common_stop("C3_PREVIEW_BINDING_INVALID")
    seen_binding_keys <- c(seen_binding_keys, record_key)
    decision <- Find(function(d) identical(d$record_key, record_key),
                      idx$record_by_rid)
    if (identical(decision$action, "assign")) {
      if (!(row$status %in% c("absent", "draft_same_record")))
        .c3_common_stop("C3_PREVIEW_BINDING_INVALID")
    } else if (identical(decision$action, "no_publication")) {
      if (identical(row$status, "published"))
        .c3_common_stop("C3_PREVIEW_BINDING_ACTIVE_FOR_NO_PUBLICATION")
    }
    ## Fund 3: `binding_person_id` was required in the key set but never
    ## cross-checked against anything. A `draft_same_record` binding is only
    ## meaningfully "the same record" if it is also bound to the case's own
    ## target person; a draft bound to a DIFFERENT person must not pass as
    ## clean — this is exactly the drift this task's own Step 2 names
    ## ("assign binding outside absent|draft_same_record").
    if (identical(row$status, "draft_same_record") &&
        identical(decision$action, "assign") &&
        !identical(as.numeric(row$binding_person_id),
                   as.numeric(decision$target_person_id)))
      .c3_common_stop("C3_PREVIEW_BINDING_INVALID")
  }
  if (!setequal(seen_binding_keys, known_record_keys))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")

  ## source_anchors / identity_components: informational, forwarded as-is
  ## for the human review surface; no Step-2 scenario names them, so they
  ## are only checked for gross shape (must be arrays), never business-rule
  ## validated here.
  if (!is.list(response$source_anchors) || !is.list(response$identity_components))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")

  response
}

## ---- Gateway orchestration (fixed call sequence, Fund H1) ---------------

## `gateway` is `list(query = function(sql, params) -> data.frame-or-list,
## execute = function(sql, params) -> invisible)`. Both are pure I/O
## injection points: the CLI entry point supplies a real DBI-backed
## implementation; tests supply a call-recording fake. Neither this
## function nor its caller ever issues any SQL beyond the fixed 9-call
## sequence documented in the Task 2 ruling (originally 8; the Task 2
## addendum added the `request.jwt.claim.sub` set_config call as the new
## call 2, immediately after BEGIN -- see the `.c3_preview_jwt_sql` constant's
## comment above for why).
build_c3_apply_database_preview <- function(candidate_raw, gateway,
                                            expected_database_name, actor_id) {
  if (!.c3_common_scalar_string(expected_database_name, "^[A-Za-z0-9_.-]+$"))
    .c3_common_stop("C3_PREVIEW_DATABASE_NAME_INVALID")
  if (!.c3_common_scalar_string(actor_id, .c3_preview_actor_id_pattern))
    .c3_common_stop("C3_PREVIEW_ACTOR_ID_INVALID")
  if (!is.list(gateway) || !is.function(gateway$query) || !is.function(gateway$execute))
    .c3_common_stop("C3_PREVIEW_GATEWAY_INVALID")
  candidate <- .c3_preview_parse_candidate(candidate_raw)
  candidate_file_sha256 <- digest::digest(candidate_raw, algo = "sha256",
                                          serialize = FALSE)
  selection_json <- .c3_preview_selection_json(candidate)

  query <- gateway$query
  execute <- gateway$execute
  rolled_back <- FALSE
  rollback <- function() {
    if (!rolled_back) {
      rolled_back <<- TRUE
      try(execute("ROLLBACK"), silent = TRUE)
    }
  }
  on.exit(rollback(), add = TRUE)

  execute("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY")
  ## Must be the first statement after BEGIN, not before it (see the constant's
  ## comment above): `request.jwt.claim.sub` is transaction-local so it has to
  ## be set inside the same transaction every later query in this sequence
  ## runs in, before the RPC call that is gated on it.
  query(.c3_preview_jwt_sql, list(actor_id))
  execute(.c3_preview_statement_timeout_sql)
  execute(.c3_preview_lock_timeout_sql)

  readonly <- query("SHOW transaction_read_only")
  if (!is.data.frame(readonly) || nrow(readonly) != 1L ||
      !identical(as.character(readonly[[1L]][[1L]]), "on"))
    .c3_common_stop("C3_PREVIEW_NOT_READ_ONLY")

  db_row <- query("SELECT current_database()")
  if (!is.data.frame(db_row) || nrow(db_row) != 1L)
    .c3_common_stop("C3_PREVIEW_QUERY_INVALID")
  database_name <- as.character(db_row[[1L]][[1L]])
  if (!identical(database_name, expected_database_name))
    .c3_common_stop("C3_PREVIEW_DATABASE_MISMATCH")

  sys_row <- query("SELECT (pg_control_system()).system_identifier::text")
  if (!is.data.frame(sys_row) || nrow(sys_row) != 1L)
    .c3_common_stop("C3_PREVIEW_QUERY_INVALID")
  system_identifier <- as.character(sys_row[[1L]][[1L]])
  if (!.c3_common_scalar_string(system_identifier, "^[0-9]+$"))
    .c3_common_stop("C3_PREVIEW_SYSTEM_IDENTIFIER_INVALID")

  rpc_result <- tryCatch(
    query("SELECT public.red_preview_reimport_cases($1, $2, $3) AS result",
          list(.c3_preview_source_id_1939, .c3_preview_phase, selection_json)),
    error = function(e) {
      classes <- class(e)
      message <- conditionMessage(e)
      if ("undefined_function" %in% classes ||
          grepl("42883|does not exist|undefined_function", message,
                ignore.case = TRUE))
        .c3_common_stop("C3_PREVIEW_RPC_CAPABILITY_MISSING")
      .c3_common_stop("C3_PREVIEW_RPC_FAILED")
    })
  if (!is.data.frame(rpc_result) || nrow(rpc_result) != 1L ||
      !"result" %in% names(rpc_result) ||
      !is.character(rpc_result$result[[1L]]) ||
      is.na(rpc_result$result[[1L]]))
    .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
  ## The exact text the RPC returned is retained verbatim (Fund H1:
  ## "byte-publicere dens canonical output uden at omforme det"). `response`
  ## below is a *parsed copy* used only to validate structure and business
  ## rules against the candidate; the parsed/re-serialized form is never
  ## what gets published. before_state_canonical + its digest are the exact
  ## bytes and the value future authorize/apply steps can hash-bind against.
  rpc_canonical_text <- rpc_result$result[[1L]]
  response <- tryCatch(
    jsonlite::fromJSON(rpc_canonical_text, simplifyVector = FALSE),
    error = function(e) .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID"))
  if (!is.list(response)) .c3_common_stop("C3_PREVIEW_RESPONSE_INVALID")
  validated <- .c3_preview_validate_response(response, candidate, database_name,
                                             system_identifier)

  rollback()

  list(
    schema_version = "1939-v50-c3-apply-db-preview-v1",
    candidate_file_sha256 = candidate_file_sha256,
    candidate_canonical_content_sha256 = candidate$canonical_content_sha256,
    database = list(database_name = database_name,
                     system_identifier = system_identifier),
    before_state = validated,
    before_state_canonical = rpc_canonical_text,
    before_state_canonical_sha256 = digest::digest(rpc_canonical_text, algo = "sha256",
                                                    serialize = FALSE),
    candidate = candidate
  )
}
