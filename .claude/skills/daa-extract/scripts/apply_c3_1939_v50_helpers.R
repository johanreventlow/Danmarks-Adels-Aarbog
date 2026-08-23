## Pure transformation + gateway orchestration for the 1939 v50 fase C3
## atomic apply gateway (Task 8).
##
## Structure and discipline are lifted verbatim from the C3 export family
## (`export_c3_apply_preview_1939_v50_helpers.R`, Task 2): every entry point
## sources `c3_export_shared_1939_v50_helpers.R` first, all I/O goes through an
## injected `gateway` (`list(query, execute, close)`) so the whole call
## sequence is testable against a fake, and every failure is a bare
## `C3_APPLY_*` token -- never a message that could carry narrative prose.
##
## What this file is: the projection of Task 3's finalized manifest plus
## Task 4's text-free approval file into the exact `p_authorized_elements` /
## `p_expected_counts` payload Task 6's RPCs validate, and the fixed statement
## sequence that carries it to the database. It re-derives NO domain state of
## its own: `public.red_preview_reimport_cases` remains the single state
## oracle (Fund H1), and `public.red_apply_reimport_cases` re-measures
## everything under its own locks. The gateway never loops a domain RPC.

## ---- Constants ------------------------------------------------------------

.c3_apply_source_id <- 3L
.c3_apply_phase <- "c3"
.c3_apply_operation <- "apply"
.c3_apply_manifest_schema <- "1939-v50-c3-apply-manifest-v1"
.c3_apply_approval_schema <- "1939-v50-c3-apply-approvals-decisions-v1"
.c3_apply_selection_schema <- "1939-v50-c3-apply-selection-v1"
.c3_apply_receipt_schema <- "c3-apply-receipt-v1"
.c3_apply_modes <- c("gate-read-only", "preflight", "rehearse-rollback",
                     "apply", "status", "reverse")
.c3_apply_uuid_pattern <-
  "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

## The phase's five approved cases, pinned. Task 3's finalizer asserts the same
## five numbers offline and Task 6's validate_reimport_case_counts asserts the
## derived invariants server-side; this is the third, cheapest gate.
.c3_apply_expected_manifest_counts <- list(
  cases = 5L, identity_events = 5L, assign_events = 4L,
  no_publication_events = 2L, events = 11L)

## The four `expected_counts`/`observed_counts` keys apply's receipt does NOT
## share: observed_counts carries eight keys (three write-side measurements,
## no approvals attestation), expected_counts seven. Only the five shared keys
## are comparable -- an identical() over the two objects can never hold.
.c3_apply_shared_count_keys <- c("cases", "identity_events", "assign_events",
                                 "no_publication_events", "events")

## ---- SQL registry (fixed; no statement is built at call time) --------------

.c3_apply_sql <- list(
  begin = "BEGIN",
  begin_read_only = "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY",
  commit = "COMMIT",
  rollback = "ROLLBACK",
  ## statement_timeout: the apply RPC's own set_config cannot bound the call
  ## that IS the running statement (Task 6's comment says so explicitly), so
  ## the gateway sets its own before any RPC. lock_timeout likewise bounds the
  ## global advisory lock the RPC takes as its first lock step.
  statement_timeout = "SET LOCAL statement_timeout = '120s'",
  lock_timeout = "SET LOCAL lock_timeout = '5s'",
  read_statement_timeout = "SET LOCAL statement_timeout = '30s'",
  jwt = "SELECT set_config('request.jwt.claim.sub', $1, true) AS jwt_subject",
  profile = "SELECT rolle FROM profiles WHERE id = $1::uuid",
  role = "SELECT current_rolle() AS rolle",
  read_only = "SHOW transaction_read_only",
  ## The batch must own its change set: apply raises
  ## REIMPORT_CASE_FOREIGN_CHANGE_SET if app.change_set_id is already set when
  ## it runs. The gateway therefore opens no change set of its own, ever, and
  ## proves the session carries none before it calls anything.
  change_set = paste(
    "SELECT btrim(coalesce(current_setting('app.change_set_id', true), ''))",
    "AS change_set_id"),
  database = "SELECT current_database() AS database_name",
  system_identifier =
    "SELECT (pg_control_system()).system_identifier::text AS system_identifier",
  ## Fund B6: a reconciliation session must hold the SAME global writer lock
  ## before it looks anything up, so no earlier C3 transaction can still be in
  ## flight while it decides. Blocking (not try-lock) on purpose -- that wait
  ## IS the guarantee -- but bounded by the lock_timeout set just above it.
  advisory_lock = paste(
    "SELECT pg_advisory_xact_lock(",
    "hashtextextended('daa-1939-v50-production-writer', 0)) AS locked"),
  authorize = paste(
    "SELECT public.red_authorize_reimport_cases(",
    "$1::bigint, $2::text, $3::text, $4::text, $5::text, $6::text, $7::text,",
    "$8::text, $9::text, $10::text, $11::text, $12::jsonb, $13::jsonb,",
    "$14::uuid, clock_timestamp() + interval '15 minutes')",
    "AS authorization_id"),
  apply = paste(
    "SELECT public.red_apply_reimport_cases($1::uuid, $2::text, $3::text)",
    "AS receipt"),
  preview = paste(
    "SELECT public.red_preview_reimport_cases($1::bigint, $2::text, $3::jsonb)",
    "AS result"),
  reconcile_authorization = paste(
    "SELECT id::text AS id, status, source_id, phase, operation,",
    "manifest_sha256, preview_sha256, approval_sha256, decisions_sha256,",
    "state_sha256, text_bundle_sha256, database_name, system_identifier",
    "FROM private.reimport_case_authorization WHERE nonce = $1::uuid"),
  reconcile_batch = paste(
    "SELECT id::text AS id, status, change_set_id, manifest_sha256,",
    "preview_sha256, observed_counts::text AS observed_counts",
    "FROM private.reimport_case_batch WHERE authorization_id = $1::uuid"),
  reconcile_batch_by_manifest = paste(
    "SELECT count(*) AS n FROM private.reimport_case_batch",
    "WHERE source_id = $1::bigint AND phase = $2::text AND operation = 'apply'",
    "AND manifest_sha256 = $3::text AND preview_sha256 = $4::text"),
  reconcile_events = paste(
    "SELECT count(*) AS n FROM private.reimport_case_event",
    "WHERE batch_id = $1::uuid"),
  reverse_batch = paste(
    "SELECT id::text AS id, status, operation, source_id, phase,",
    "manifest_sha256, preview_sha256",
    "FROM private.reimport_case_batch WHERE id = $1::uuid"),
  ## The reversal authorization is hash-bound to the canonical receipt of the
  ## batch it withdraws. That canonicalisation is the database's own
  ## (private.reimport_1939_canonical_json_sha256); re-implementing it in R
  ## would be a second definition that could drift, so the value is asked for
  ## rather than computed -- the same Fund H1 reasoning as the state oracle.
  reversal_receipt_sha = paste(
    "SELECT private.reimport_1939_canonical_json_sha256(",
    "private.reimport_case_receipt($1::uuid)) AS receipt_sha256"),
  authorize_reversal = paste(
    "SELECT public.red_authorize_reimport_case_reversal(",
    "$1::uuid, $2::text, $3::uuid, clock_timestamp() + interval '15 minutes')",
    "AS authorization_id"),
  reverse = paste(
    "SELECT public.red_reverse_reimport_cases($1::uuid, $2::uuid) AS receipt")
)

## ---- Small typed accessors ------------------------------------------------

.c3_apply_exact_keys <- function(value, expected, token) {
  if (!is.list(value) || length(value) != length(expected) ||
      !setequal(names(value), expected))
    .c3_common_stop(token)
}

.c3_apply_int <- function(value, token) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      !is.finite(value) || value != floor(value) || value <= 0)
    .c3_common_stop(token)
  as.integer(value)
}

.c3_apply_optional_int <- function(value, token) {
  if (is.null(value)) return(NA_integer_)
  .c3_apply_int(value, token)
}

.c3_apply_hex <- function(value, token) {
  if (!.c3_common_scalar_string(value, "^[0-9a-f]{64}$")) .c3_common_stop(token)
  value
}

.c3_apply_optional_hex <- function(value, token) {
  if (is.null(value)) return(NA_character_)
  .c3_apply_hex(value, token)
}

.c3_apply_string <- function(value, token) {
  if (!.c3_common_scalar_string(value)) .c3_common_stop(token)
  value
}

.c3_apply_false <- function(value, token) {
  if (!identical(value, FALSE)) .c3_common_stop(token)
  FALSE
}

.c3_apply_bool <- function(value, token) {
  if (!is.logical(value) || length(value) != 1L || is.na(value))
    .c3_common_stop(token)
  as.logical(value)
}

.c3_apply_count <- function(value, expected, token) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      value != expected)
    .c3_common_stop(token)
  as.integer(expected)
}

## Serialisation for every jsonb parameter this gateway binds.
##   na = "null"   -- an R list DROPS a NULL member, so a nullable field must
##                    travel as NA and be rendered as JSON null; without this
##                    an assign element silently emits 12 keys instead of 13
##                    and the server rejects it as REIMPORT_CASE_ELEMENTS_INVALID.
##   digits = NA   -- full precision: an id emitted as 1e+05 is still a JSON
##                    number, so no server check would catch the wrong value.
.c3_apply_json <- function(value) {
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, na = "null",
                                null = "null", digits = NA))
}

.c3_apply_sha_raw <- function(raw) {
  digest::digest(raw, algo = "sha256", serialize = FALSE)
}

.c3_apply_parse_json <- function(raw, token) {
  if (!is.raw(raw)) .c3_common_stop(token)
  document <- tryCatch(jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE),
                       error = function(e) .c3_common_stop(token))
  if (!is.list(document)) .c3_common_stop(token)
  document
}

## ---- Manifest (Task 3 output) ---------------------------------------------

.c3_apply_parse_manifest <- function(manifest_raw) {
  token <- "C3_APPLY_MANIFEST_INVALID"
  manifest <- .c3_apply_parse_json(manifest_raw, token)
  if (!identical(manifest$schema_version, .c3_apply_manifest_schema))
    .c3_common_stop(token)
  .c3_apply_exact_keys(manifest, c("schema_version", "input_hashes", "database",
                                   "counts", "cases", "canonical_content_sha256"),
                        token)
  .c3_apply_exact_keys(manifest$input_hashes,
                       c("candidate_raw_sha256", "preview_raw_sha256",
                         "candidate_canonical_content_sha256",
                         "before_state_canonical_sha256"), token)
  for (name in names(manifest$input_hashes))
    .c3_apply_hex(manifest$input_hashes[[name]], token)
  .c3_apply_hex(manifest$canonical_content_sha256, token)
  .c3_apply_exact_keys(manifest$database,
                       c("database_name", "system_identifier"), token)
  .c3_apply_string(manifest$database$database_name, token)
  .c3_apply_string(manifest$database$system_identifier, token)

  .c3_apply_exact_keys(manifest$counts, names(.c3_apply_expected_manifest_counts),
                       "C3_APPLY_MANIFEST_COUNTS_INVALID")
  for (name in names(.c3_apply_expected_manifest_counts))
    .c3_apply_count(manifest$counts[[name]],
                    .c3_apply_expected_manifest_counts[[name]],
                    "C3_APPLY_MANIFEST_COUNTS_INVALID")
  if (!is.list(manifest$cases) || length(manifest$cases) != 5L)
    .c3_common_stop("C3_APPLY_MANIFEST_COUNTS_INVALID")
  manifest
}

## The flattening. Two files read side by side look like a near-match and are
## not: the finalizer NESTS the four narrative labels inside
## `after_state.expected_narrative`, while the element payload wants all four
## at its root; `target_narrative_id` is taken from BEFORE-state (there is no
## such field in after_state at all); and `raw_sha256`,
## `normalization_version`, `normalization_flags` are DROPPED -- the database
## has no use for them and they are already bound through `text_bundle_sha256`
## and `manifest_sha256`.
.c3_apply_manifest_elements <- function(manifest) {
  token <- "C3_APPLY_MANIFEST_INVALID"
  id_token <- "C3_APPLY_MANIFEST_ELEMENT_ID_INVALID"
  elements <- list()
  assign_element_ids <- character(0L)
  case_ids <- character(0L)
  selection_cases <- list()

  for (case in manifest$cases) {
    .c3_apply_exact_keys(case, c("element_id", "case_id", "after_state",
                                 "before_state", "events"), token)
    case_id <- .c3_apply_string(case$case_id, token)
    case_element_id <- paste0("case:", case_id)
    if (!identical(case$element_id, case_element_id)) .c3_common_stop(id_token)
    case_ids <- c(case_ids, case_id)

    .c3_apply_exact_keys(case$after_state, c("action", "person_ids"), token)
    if (!identical(case$after_state$action, "different")) .c3_common_stop(token)
    person_ids <- case$after_state$person_ids
    if (!is.list(person_ids) && !is.numeric(person_ids)) .c3_common_stop(token)
    person_ids <- as.numeric(unlist(person_ids, use.names = FALSE))
    if (length(person_ids) != 2L) .c3_common_stop(token)
    person_ids <- vapply(person_ids, .c3_apply_int, integer(1), token = token)
    if (person_ids[[1L]] >= person_ids[[2L]]) .c3_common_stop(token)

    .c3_apply_exact_keys(case$before_state,
                         c("component_overlap", "existing_rejection"), token)
    ## component_overlap TRUE can never be authorised (the server refuses it
    ## too); existing_rejection is free -- it selects created vs reused.
    .c3_apply_false(case$before_state$component_overlap,
                    "C3_APPLY_MANIFEST_COMPONENT_OVERLAP")
    existing_rejection <- .c3_apply_bool(case$before_state$existing_rejection, token)

    elements[[case_element_id]] <- list(
      case_id = case_id, action = "different",
      person_ids = person_ids,
      before_state = list(component_overlap = FALSE,
                          existing_rejection = existing_rejection))

    if (!is.list(case$events) || length(case$events) < 1L) .c3_common_stop(token)
    selection_records <- list()
    for (event in case$events) {
      .c3_apply_exact_keys(event, c("element_id", "rid", "record_key", "action",
                                    "after_state", "before_state"), token)
      rid <- .c3_apply_string(event$rid, token)
      record_key <- .c3_apply_string(event$record_key, token)
      event_element_id <- paste0(case_element_id, ":rid:", rid)
      if (!identical(event$element_id, event_element_id)) .c3_common_stop(id_token)
      if (!is.null(elements[[event_element_id]])) .c3_common_stop(id_token)

      source_record <- event$before_state$source_record
      .c3_apply_exact_keys(source_record,
                           c("match_count", "verbatim_sha256", "side"), token)
      source_state <- list(
        match_count = .c3_apply_count(source_record$match_count, 1L, token),
        verbatim_sha256 = .c3_apply_hex(source_record$verbatim_sha256, token),
        side = .c3_apply_string(source_record$side, token))
      binding <- event$before_state$binding
      .c3_apply_exact_keys(binding, c("status", "binding_person_id"), token)
      binding_state <- list(
        status = .c3_apply_string(binding$status, token),
        binding_person_id = .c3_apply_optional_int(binding$binding_person_id, token))

      if (identical(event$action, "assign")) {
        .c3_apply_exact_keys(event$before_state,
                             c("source_record", "target_narrative", "binding"), token)
        after <- event$after_state
        .c3_apply_exact_keys(after,
                             c("target_person_id", "raw_sha256", "normalized_text",
                               "normalized_sha256", "normalization_version",
                               "normalization_flags", "expected_narrative"), token)
        expected <- after$expected_narrative
        .c3_apply_exact_keys(expected,
                             c("privat", "side", "record_label", "citation_label"),
                             token)
        target <- event$before_state$target_narrative
        .c3_apply_exact_keys(target,
                             c("person_id", "narrative_id", "privat", "old_sha256"),
                             token)
        target_person_id <- .c3_apply_int(after$target_person_id, token)
        narrative_id <- .c3_apply_optional_int(target$narrative_id, token)
        old_sha256 <- .c3_apply_optional_hex(target$old_sha256, token)
        if (is.na(narrative_id) != is.na(old_sha256)) .c3_common_stop(token)
        side <- .c3_apply_string(expected$side, token)
        if (!identical(side, source_state$side)) .c3_common_stop(token)
        if (!identical(.c3_apply_int(target$person_id, token), target_person_id))
          .c3_common_stop(token)
        if (!(binding_state$status %in% c("absent", "draft_same_record")))
          .c3_common_stop("C3_APPLY_MANIFEST_BINDING_INVALID")
        if (identical(binding_state$status, "absent")) {
          if (!is.na(binding_state$binding_person_id))
            .c3_common_stop("C3_APPLY_MANIFEST_BINDING_INVALID")
        } else if (!identical(binding_state$binding_person_id, target_person_id)) {
          .c3_common_stop("C3_APPLY_MANIFEST_BINDING_INVALID")
        }

        elements[[event_element_id]] <- list(
          case_id = case_id, rid = rid, record_key = record_key,
          action = "assign",
          target_person_id = target_person_id,
          target_narrative_id = narrative_id,
          normalized_text = .c3_apply_string(after$normalized_text, token),
          normalized_sha256 = .c3_apply_hex(after$normalized_sha256, token),
          record_label = .c3_apply_string(expected$record_label, token),
          citation_label = .c3_apply_string(expected$citation_label, token),
          side = side,
          privat = .c3_apply_false(expected$privat, token),
          before_state = list(
            source_record = source_state,
            target_narrative = list(
              person_id = target_person_id, narrative_id = narrative_id,
              privat = .c3_apply_false(target$privat, token),
              old_sha256 = old_sha256),
            binding = binding_state))
        assign_element_ids <- c(assign_element_ids, event_element_id)
        selection_records[[length(selection_records) + 1L]] <- list(
          rid = rid, record_key = record_key, action = "assign",
          target_person_id = target_person_id,
          raw_sha256 = .c3_apply_hex(after$raw_sha256, token),
          normalized_sha256 = after$normalized_sha256)

      } else if (identical(event$action, "no_publication")) {
        .c3_apply_exact_keys(event$before_state, c("source_record", "binding"), token)
        if (!is.list(event$after_state) || length(event$after_state) != 0L)
          .c3_common_stop(token)
        if (!identical(binding_state$status, "absent") ||
            !is.na(binding_state$binding_person_id))
          .c3_common_stop("C3_APPLY_MANIFEST_BINDING_INVALID")
        elements[[event_element_id]] <- list(
          case_id = case_id, rid = rid, record_key = record_key,
          action = "no_publication",
          before_state = list(source_record = source_state, binding = binding_state))
        selection_records[[length(selection_records) + 1L]] <- list(
          rid = rid, record_key = record_key, action = "no_publication")
      } else {
        .c3_common_stop(token)
      }
    }
    selection_cases[[length(selection_cases) + 1L]] <- list(
      case_id = case_id, identity_pair = list(person_ids = person_ids),
      records = selection_records)
  }

  if (anyDuplicated(case_ids)) .c3_common_stop(id_token)
  if (length(elements) != .c3_apply_expected_manifest_counts$events)
    .c3_common_stop("C3_APPLY_MANIFEST_COUNTS_INVALID")
  if (length(assign_element_ids) != .c3_apply_expected_manifest_counts$assign_events)
    .c3_common_stop("C3_APPLY_MANIFEST_COUNTS_INVALID")
  list(elements = elements, assign_element_ids = assign_element_ids,
       selection = list(schema_version = .c3_apply_selection_schema,
                        cases = selection_cases))
}

## ---- Approval (Task 4 output) ---------------------------------------------

.c3_apply_parse_approval <- function(approval_raw, manifest, manifest_sha256,
                                     assign_element_ids) {
  token <- "C3_APPLY_APPROVAL_INVALID"
  approval <- .c3_apply_parse_json(approval_raw, token)
  if (!identical(approval$schema_version, .c3_apply_approval_schema))
    .c3_common_stop(token)
  .c3_apply_exact_keys(approval,
                       c("schema_version", "approvals_raw_sha256",
                         "manifest_raw_sha256", "manifest_canonical_content_sha256",
                         "text_bundle_sha256", "decisions", "counts"), token)
  for (name in c("approvals_raw_sha256", "manifest_raw_sha256",
                 "manifest_canonical_content_sha256", "text_bundle_sha256"))
    .c3_apply_hex(approval[[name]], token)

  ## The approval must be about THIS manifest, proven twice: the exact bytes
  ## the gateway is going to hash-bind, and the manifest's own canonical
  ## content hash. Either alone would let a re-rendered but semantically equal
  ## manifest slip past the human's attestation.
  if (!identical(approval$manifest_raw_sha256, manifest_sha256) ||
      !identical(approval$manifest_canonical_content_sha256,
                 manifest$canonical_content_sha256))
    .c3_common_stop("C3_APPLY_APPROVAL_MANIFEST_MISMATCH")

  .c3_apply_exact_keys(approval$counts,
                       c("decisions", "approved", "unresolved"), token)
  decisions <- approval$decisions
  if (!is.list(decisions) ||
      length(decisions) != .c3_apply_expected_manifest_counts$assign_events)
    .c3_common_stop("C3_APPLY_APPROVAL_ELEMENT_MISMATCH")
  seen <- character(0L)
  for (decision in decisions) {
    .c3_apply_exact_keys(decision, c("element_id", "status"), token)
    element_id <- .c3_apply_string(decision$element_id, token)
    if (!identical(decision$status, "approved"))
      .c3_common_stop("C3_APPLY_APPROVAL_NOT_APPROVED")
    seen <- c(seen, element_id)
  }
  if (anyDuplicated(seen) || !setequal(seen, assign_element_ids))
    .c3_common_stop("C3_APPLY_APPROVAL_ELEMENT_MISMATCH")
  approved <- .c3_apply_count(approval$counts$approved, length(seen),
                              "C3_APPLY_APPROVAL_NOT_APPROVED")
  unresolved <- .c3_apply_count(approval$counts$unresolved, 0L,
                                "C3_APPLY_APPROVAL_NOT_APPROVED")
  .c3_apply_count(approval$counts$decisions, length(seen),
                  "C3_APPLY_APPROVAL_ELEMENT_MISMATCH")
  list(approval = approval, approved = approved, unresolved = unresolved)
}

## ---- The authorization bundle ---------------------------------------------

## Every one of the six hashes must be DETERMINISTIC from the two files the
## CLI accepts. That is not a stylistic preference: authorize's nonce replay
## compares all six for equality, so a retry that derived one of them
## differently gets REIMPORT_CASE_NONCE_CONFLICT instead of the idempotent
## replay that makes commit-unknown recovery possible.
##
## The database treats all six as opaque 64-hex values, so the chain-position
## of two of them is this gateway's own ruling, recorded here so Task 9 cannot
## pick differently:
##   decisions_sha256 = manifest.input_hashes.candidate_raw_sha256
##     The candidate manifest IS the machine-readable decision set for the
##     phase (one identity decision per case, one assign/no_publication
##     decision per record). Rejected alternative:
##     approval.approvals_raw_sha256 -- that is the human APPROVAL sheet, an
##     artefact already pinned transitively by approval_sha256, and it says
##     nothing about the case decisions themselves.
##   state_sha256 = manifest.input_hashes.before_state_canonical_sha256
##     The canonical bytes of the measured before-state, i.e. the exact answer
##     red_preview_reimport_cases gave. Rejected alternative:
##     candidate_canonical_content_sha256 -- that is a candidate identity, not
##     a measured database state.
build_c3_apply_authorization <- function(manifest_raw, approval_raw) {
  manifest <- .c3_apply_parse_manifest(manifest_raw)
  manifest_sha256 <- .c3_apply_sha_raw(manifest_raw)
  projected <- .c3_apply_manifest_elements(manifest)
  approval_state <- .c3_apply_parse_approval(approval_raw, manifest,
                                             manifest_sha256,
                                             projected$assign_element_ids)
  approval_sha256 <- .c3_apply_sha_raw(approval_raw)

  expected_counts <- c(.c3_apply_expected_manifest_counts,
                       list(approvals_approved = approval_state$approved,
                            approvals_unresolved = approval_state$unresolved))
  hashes <- list(
    manifest_sha256 = manifest_sha256,
    preview_sha256 = manifest$input_hashes$preview_raw_sha256,
    approval_sha256 = approval_sha256,
    decisions_sha256 = manifest$input_hashes$candidate_raw_sha256,
    state_sha256 = manifest$input_hashes$before_state_canonical_sha256,
    text_bundle_sha256 = approval_state$approval$text_bundle_sha256)

  summary_line <- sprintf(
    paste("manifest_sha256=%s approval_sha256=%s preview_sha256=%s",
          "state_sha256=%s decisions_sha256=%s text_bundle_sha256=%s",
          "elements=%d events=%d approvals_approved=%d approvals_unresolved=%d"),
    hashes$manifest_sha256, hashes$approval_sha256, hashes$preview_sha256,
    hashes$state_sha256, hashes$decisions_sha256, hashes$text_bundle_sha256,
    length(projected$elements), expected_counts$events,
    expected_counts$approvals_approved, expected_counts$approvals_unresolved)

  list(
    manifest = manifest,
    hashes = hashes,
    database = manifest$database,
    element_ids = names(projected$elements),
    assign_element_ids = projected$assign_element_ids,
    expected_counts = expected_counts,
    expected_counts_json = .c3_apply_json(expected_counts),
    authorized_elements = projected$elements,
    authorized_elements_json = .c3_apply_json(projected$elements),
    selection_json = .c3_apply_json(projected$selection),
    summary_line = summary_line
  )
}

## ---- CLI arguments --------------------------------------------------------

.c3_apply_base_flags <- c("--mode", "--manifest", "--approval", "--nonce",
                          "--actor-id")
.c3_apply_reverse_flags <- c("--batch-id", "--reversal-nonce")

c3_apply_parse_args <- function(args) {
  token <- "C3_APPLY_ARGUMENTS_INVALID"
  if (!is.character(args)) .c3_common_stop(token)
  position <- which(args == "--mode")
  if (length(position) != 1L || position %% 2L != 1L ||
      position + 1L > length(args))
    .c3_common_stop(token)
  mode <- args[[position + 1L]]
  allowed <- if (identical(mode, "reverse")) {
    c(.c3_apply_base_flags, .c3_apply_reverse_flags)
  } else {
    .c3_apply_base_flags
  }
  parsed <- .c3_common_parse_flags(args, allowed, token)
  if (!(mode %in% .c3_apply_modes)) .c3_common_stop("C3_APPLY_MODE_INVALID")
  if (!.c3_common_scalar_string(parsed[["--nonce"]], .c3_apply_uuid_pattern))
    .c3_common_stop("C3_APPLY_NONCE_INVALID")
  if (!.c3_common_scalar_string(parsed[["--actor-id"]], .c3_apply_uuid_pattern))
    .c3_common_stop("C3_APPLY_ACTOR_ID_INVALID")
  result <- list(mode = mode, manifest = parsed[["--manifest"]],
                 approval = parsed[["--approval"]], nonce = parsed[["--nonce"]],
                 actor_id = parsed[["--actor-id"]],
                 batch_id = NULL, reversal_nonce = NULL)
  if (identical(mode, "reverse")) {
    if (!.c3_common_scalar_string(parsed[["--batch-id"]], .c3_apply_uuid_pattern))
      .c3_common_stop("C3_APPLY_BATCH_ID_INVALID")
    if (!.c3_common_scalar_string(parsed[["--reversal-nonce"]],
                                   .c3_apply_uuid_pattern) ||
        identical(parsed[["--reversal-nonce"]], parsed[["--nonce"]]))
      .c3_common_stop("C3_APPLY_NONCE_INVALID")
    result$batch_id <- parsed[["--batch-id"]]
    result$reversal_nonce <- parsed[["--reversal-nonce"]]
  }
  result
}

## All five PG variables together or none of them -- reused verbatim from the
## shared C3 export helper, so the gateway and the exporters cannot disagree
## about what a valid connection environment is.
c3_apply_pg_connection_values <- function() {
  .c3_common_pg_connection_values("C3_APPLY_PG_ENV_INVALID",
                                   "C3_APPLY_CONNECTION_ENV_INVALID")
}

## ---- Gateway primitives ---------------------------------------------------

.c3_apply_scalar <- function(rows, column, token) {
  if (!is.data.frame(rows) || nrow(rows) != 1L || !(column %in% names(rows)))
    .c3_common_stop(token)
  rows[[column]][[1L]]
}

.c3_apply_check_gateway <- function(gateway) {
  if (!is.list(gateway) || !is.function(gateway$query) ||
      !is.function(gateway$execute))
    .c3_common_stop("C3_APPLY_GATEWAY_INVALID")
  gateway
}

.c3_apply_open <- function(connect) {
  if (!is.function(connect)) .c3_common_stop("C3_APPLY_GATEWAY_INVALID")
  .c3_apply_check_gateway(connect())
}

.c3_apply_close <- function(gateway) {
  if (is.function(gateway$close)) try(gateway$close(), silent = TRUE)
  invisible(NULL)
}

## Server tokens are translated into this file's own namespace so a caller
## never has to pattern-match a foreign vocabulary, and so no free-text error
## body (which could quote narrative prose) is ever re-emitted.
.c3_apply_rpc_error <- function(error, fallback) {
  message <- conditionMessage(error)
  mapped <- c(
    REIMPORT_CASE_BATCH_REVERSED = "C3_APPLY_BATCH_REVERSED",
    REIMPORT_CASE_FOREIGN_CHANGE_SET = "C3_APPLY_FOREIGN_CHANGE_SET",
    REIMPORT_CASE_AUTHORIZATION_ALREADY_CONSUMED =
      "C3_APPLY_AUTHORIZATION_ALREADY_CONSUMED",
    REIMPORT_CASE_NONCE_CONFLICT = "C3_APPLY_NONCE_CONFLICT",
    REIMPORT_1939_ROLE_FORBIDDEN = "C3_APPLY_ROLE_FORBIDDEN")
  for (name in names(mapped))
    if (grepl(name, message, fixed = TRUE)) .c3_common_stop(mapped[[name]])
  .c3_common_stop(fallback)
}

.c3_apply_is_read_only_error <- function(error) {
  message <- conditionMessage(error)
  grepl("read-only transaction", message, fixed = TRUE) ||
    grepl("read only transaction", message, fixed = TRUE) ||
    grepl("25006", message, fixed = TRUE)
}

## The fixed prologue every mode runs, in exactly this order:
##   BEGIN -> JWT subject -> profile role -> current_rolle() gate
##   [-> read-only proof] -> statement_timeout -> lock_timeout
##   -> foreign-change-set guard -> database name -> system identifier.
.c3_apply_prologue <- function(gateway, bundle, actor_id, read_only) {
  gateway$execute(if (read_only) .c3_apply_sql$begin_read_only
                  else .c3_apply_sql$begin)
  ## The actor is established before anything else: every downstream gate
  ## (profiles under RLS, current_rolle(), the RPCs' own role gate) resolves
  ## through auth.uid(), which is NULL on a direct connection until this runs.
  gateway$query(.c3_apply_sql$jwt, list(actor_id))
  profile <- gateway$query(.c3_apply_sql$profile, list(actor_id))
  if (!is.data.frame(profile) || nrow(profile) != 1L ||
      !identical(as.character(profile[["rolle"]][[1L]]), "redaktion"))
    .c3_common_stop("C3_APPLY_ACTOR_NOT_REDAKTION")
  ## The profile row existing is not proof that set_config reached auth.uid()
  ## in THIS transaction. current_rolle() is the very function the RPCs gate on.
  role <- gateway$query(.c3_apply_sql$role)
  if (!identical(as.character(.c3_apply_scalar(role, "rolle",
                                                "C3_APPLY_GATE_NOT_OPEN")),
                 "redaktion"))
    .c3_common_stop("C3_APPLY_GATE_NOT_OPEN")
  if (read_only) {
    flag <- gateway$query(.c3_apply_sql$read_only)
    if (!is.data.frame(flag) || nrow(flag) != 1L ||
        !identical(as.character(flag[[1L]][[1L]]), "on"))
      .c3_common_stop("C3_APPLY_NOT_READ_ONLY")
  }
  gateway$execute(.c3_apply_sql$statement_timeout)
  gateway$execute(.c3_apply_sql$lock_timeout)
  change_set <- gateway$query(.c3_apply_sql$change_set)
  value <- .c3_apply_scalar(change_set, "change_set_id",
                            "C3_APPLY_FOREIGN_CHANGE_SET")
  if (!is.na(value) && nzchar(as.character(value)))
    .c3_common_stop("C3_APPLY_FOREIGN_CHANGE_SET")
  database_name <- as.character(.c3_apply_scalar(
    gateway$query(.c3_apply_sql$database), "database_name",
    "C3_APPLY_DATABASE_MISMATCH"))
  system_identifier <- as.character(.c3_apply_scalar(
    gateway$query(.c3_apply_sql$system_identifier), "system_identifier",
    "C3_APPLY_DATABASE_MISMATCH"))
  ## Fund B1, both fields separately: an artefact built against a rehearsal
  ## copy must fail closed against production and vice versa. The authorize
  ## RPC re-checks the same two values itself; this is the cheap local gate
  ## that stops the call before it is ever made.
  if (!identical(database_name, bundle$database$database_name) ||
      !identical(system_identifier, bundle$database$system_identifier))
    .c3_common_stop("C3_APPLY_DATABASE_MISMATCH")
  list(database_name = database_name, system_identifier = system_identifier)
}

.c3_apply_authorize <- function(gateway, bundle, nonce) {
  rows <- tryCatch(
    gateway$query(.c3_apply_sql$authorize, list(
      .c3_apply_source_id, .c3_apply_phase, .c3_apply_operation,
      bundle$hashes$manifest_sha256, bundle$hashes$preview_sha256,
      bundle$hashes$approval_sha256, bundle$hashes$decisions_sha256,
      bundle$hashes$state_sha256, bundle$hashes$text_bundle_sha256,
      bundle$database$database_name, bundle$database$system_identifier,
      bundle$expected_counts_json, bundle$authorized_elements_json, nonce)),
    error = function(e) .c3_apply_rpc_error(e, "C3_APPLY_AUTHORIZATION_FAILED"))
  id <- as.character(.c3_apply_scalar(rows, "authorization_id",
                                       "C3_APPLY_AUTHORIZATION_FAILED"))
  if (!.c3_common_scalar_string(id, .c3_apply_uuid_pattern))
    .c3_common_stop("C3_APPLY_AUTHORIZATION_FAILED")
  id
}

## ---- Receipt verification (local hashes only; no re-derived state) ---------

.c3_apply_verify_receipt <- function(receipt_text, bundle, operation,
                                     authorization_id) {
  token <- "C3_APPLY_RECEIPT_INVALID"
  if (!.c3_common_scalar_string(receipt_text)) .c3_common_stop(token)
  receipt <- tryCatch(jsonlite::fromJSON(receipt_text, simplifyVector = FALSE),
                      error = function(e) .c3_common_stop(token))
  if (!is.list(receipt) ||
      !identical(receipt$schema_version, .c3_apply_receipt_schema))
    .c3_common_stop(token)
  if (!identical(as.integer(receipt$source_id), .c3_apply_source_id) ||
      !identical(receipt$phase, .c3_apply_phase) ||
      !identical(receipt$operation, operation))
    .c3_common_stop("C3_APPLY_RECEIPT_MISMATCH")
  if (!identical(as.character(receipt$authorization_id), authorization_id))
    .c3_common_stop("C3_APPLY_RECEIPT_MISMATCH")
  if (!identical(receipt$status, "finalized"))
    .c3_common_stop("C3_APPLY_RECEIPT_NOT_FINALIZED")
  batch_id <- as.character(receipt$batch_id)
  if (!.c3_common_scalar_string(batch_id, .c3_apply_uuid_pattern))
    .c3_common_stop(token)
  change_set_id <- .c3_apply_int(receipt$change_set_id, token)

  if (identical(operation, .c3_apply_operation)) {
    ## An apply batch is pinned to the artefact chain by both hashes. A
    ## reversal batch is not: its manifest_sha256 is the applied batch's
    ## canonical receipt hash (Task 7), computed server-side.
    if (!identical(receipt$manifest_sha256, bundle$hashes$manifest_sha256) ||
        !identical(receipt$preview_sha256, bundle$hashes$preview_sha256))
      .c3_common_stop("C3_APPLY_RECEIPT_MISMATCH")
    observed <- receipt$observed_counts
    expected <- receipt$expected_counts
    if (!is.list(observed) || !is.list(expected))
      .c3_common_stop("C3_APPLY_RECEIPT_COUNTS_MISMATCH")
    for (name in names(bundle$expected_counts))
      if (!identical(as.integer(expected[[name]]),
                     as.integer(bundle$expected_counts[[name]])))
        .c3_common_stop("C3_APPLY_RECEIPT_COUNTS_MISMATCH")
    ## Only the FIVE shared keys: observed_counts adds narratives_written /
    ## source_records / persons and carries no approvals attestation, so the
    ## two objects can never be compared whole.
    for (name in .c3_apply_shared_count_keys)
      if (!identical(as.integer(observed[[name]]),
                     as.integer(bundle$expected_counts[[name]])))
        .c3_common_stop("C3_APPLY_RECEIPT_COUNTS_MISMATCH")
  }

  elements <- receipt$elements
  if (!is.list(elements) || length(elements) != length(bundle$element_ids))
    .c3_common_stop("C3_APPLY_RECEIPT_ELEMENT_MISMATCH")
  observed_ids <- vapply(elements, function(row) {
    if (!is.list(row) || !.c3_common_scalar_string(row$element_id))
      .c3_common_stop("C3_APPLY_RECEIPT_ELEMENT_MISMATCH")
    row$element_id
  }, character(1))
  ## The ledger must have recorded exactly the elements we authorised -- the
  ## one check that proves the batch is this manifest's batch and no other.
  if (anyDuplicated(observed_ids) || !setequal(observed_ids, bundle$element_ids))
    .c3_common_stop("C3_APPLY_RECEIPT_ELEMENT_MISMATCH")

  list(batch_id = batch_id, authorization_id = authorization_id,
       change_set_id = change_set_id, elements = length(observed_ids))
}

## ---- Reconciliation (Fund B6) ---------------------------------------------

## Outcomes, exactly three plus the deliberate-withdrawal case:
##   committed     -- the exact finalized receipt for our nonce AND all six
##                    hashes exists; nothing further to do.
##   not_committed -- no authorization row for our nonce and no batch anywhere
##                    for our (manifest, preview): safe, nothing was consumed.
##   reversed      -- the batch exists but was deliberately withdrawn
##                    (Task 7). A clear state, not an anomaly.
##   unknown       -- anything else: partial, drifted, or unexplained. The
##                    caller raises C3_APPLY_COMMIT_UNKNOWN; never a retry.
.c3_apply_reconcile <- function(gateway, bundle, nonce) {
  gateway$execute(.c3_apply_sql$begin_read_only)
  ## lock_timeout FIRST: the advisory lock below is blocking on purpose, and
  ## an unbounded wait would hang a supervised recovery with no output.
  gateway$execute(.c3_apply_sql$lock_timeout)
  gateway$execute(.c3_apply_sql$read_statement_timeout)
  ## Fund B6: take the global writer lock BEFORE any lookup. Once held, no
  ## earlier C3 transaction can still be in flight, so what we read is final.
  gateway$query(.c3_apply_sql$advisory_lock)

  authorization <- gateway$query(.c3_apply_sql$reconcile_authorization, list(nonce))
  if (!is.data.frame(authorization)) .c3_common_stop("C3_APPLY_RECONCILE_INVALID")
  if (nrow(authorization) == 0L) {
    batches <- gateway$query(.c3_apply_sql$reconcile_batch_by_manifest, list(
      .c3_apply_source_id, .c3_apply_phase, bundle$hashes$manifest_sha256,
      bundle$hashes$preview_sha256))
    n <- as.numeric(.c3_apply_scalar(batches, "n", "C3_APPLY_RECONCILE_INVALID"))
    return(list(outcome = if (identical(n, 0)) "not_committed" else "unknown"))
  }
  if (nrow(authorization) != 1L) return(list(outcome = "unknown"))

  expected <- list(
    source_id = as.character(.c3_apply_source_id), phase = .c3_apply_phase,
    operation = .c3_apply_operation,
    manifest_sha256 = bundle$hashes$manifest_sha256,
    preview_sha256 = bundle$hashes$preview_sha256,
    approval_sha256 = bundle$hashes$approval_sha256,
    decisions_sha256 = bundle$hashes$decisions_sha256,
    state_sha256 = bundle$hashes$state_sha256,
    text_bundle_sha256 = bundle$hashes$text_bundle_sha256,
    database_name = bundle$database$database_name,
    system_identifier = bundle$database$system_identifier)
  for (name in names(expected)) {
    if (!(name %in% names(authorization))) return(list(outcome = "unknown"))
    if (!identical(as.character(authorization[[name]][[1L]]), expected[[name]]))
      return(list(outcome = "unknown"))
  }
  authorization_id <- as.character(authorization[["id"]][[1L]])

  batch <- gateway$query(.c3_apply_sql$reconcile_batch, list(authorization_id))
  if (!is.data.frame(batch) || nrow(batch) != 1L) return(list(outcome = "unknown"))
  status <- as.character(batch[["status"]][[1L]])
  if (identical(status, "reversed"))
    return(list(outcome = "reversed",
                batch_id = as.character(batch[["id"]][[1L]])))
  if (!identical(status, "finalized")) return(list(outcome = "unknown"))
  if (!identical(as.character(batch[["manifest_sha256"]][[1L]]),
                 bundle$hashes$manifest_sha256) ||
      !identical(as.character(batch[["preview_sha256"]][[1L]]),
                 bundle$hashes$preview_sha256))
    return(list(outcome = "unknown"))
  observed <- tryCatch(
    jsonlite::fromJSON(as.character(batch[["observed_counts"]][[1L]]),
                        simplifyVector = FALSE),
    error = function(e) NULL)
  if (!is.list(observed)) return(list(outcome = "unknown"))
  for (name in .c3_apply_shared_count_keys)
    if (!identical(as.integer(observed[[name]]),
                   as.integer(bundle$expected_counts[[name]])))
      return(list(outcome = "unknown"))
  batch_id <- as.character(batch[["id"]][[1L]])
  events <- gateway$query(.c3_apply_sql$reconcile_events, list(batch_id))
  n <- as.numeric(.c3_apply_scalar(events, "n", "C3_APPLY_RECONCILE_INVALID"))
  if (!identical(as.integer(n), as.integer(bundle$expected_counts$events)))
    return(list(outcome = "unknown"))
  list(outcome = "committed", batch_id = batch_id,
       authorization_id = authorization_id,
       change_set_id = batch[["change_set_id"]][[1L]])
}

## Read-only measurement through the ONE state oracle. No SQL of this
## gateway's own ever touches domain tables (Fund H1).
.c3_apply_measure_state <- function(gateway, bundle, actor_id) {
  gateway$execute(.c3_apply_sql$begin_read_only)
  gateway$execute(.c3_apply_sql$read_statement_timeout)
  gateway$execute(.c3_apply_sql$lock_timeout)
  gateway$query(.c3_apply_sql$jwt, list(actor_id))
  rows <- tryCatch(
    gateway$query(.c3_apply_sql$preview, list(
      .c3_apply_source_id, .c3_apply_phase, bundle$selection_json)),
    error = function(e) .c3_apply_rpc_error(e, "C3_APPLY_PREVIEW_FAILED"))
  text <- as.character(.c3_apply_scalar(rows, "result", "C3_APPLY_PREVIEW_FAILED"))
  gateway$execute(.c3_apply_sql$rollback)
  digest::digest(text, algo = "sha256", serialize = FALSE)
}

## ---- Modes ----------------------------------------------------------------

.c3_apply_mode_gate_read_only <- function(bundle, options, connect) {
  gateway <- .c3_apply_open(connect)
  on.exit(.c3_apply_close(gateway), add = TRUE)
  outcome <- tryCatch({
    .c3_apply_prologue(gateway, bundle, options$actor_id, read_only = TRUE)
    ## The probe is the real authorization call. It passes the role gate
    ## FIRST (require_reimport_1939_editor runs in the function's DECLARE) and
    ## only then reaches its INSERT -- so a read-only write error proves the
    ## role gate was open, while a role token proves it was not.
    observed <- tryCatch({
      gateway$query(.c3_apply_sql$authorize, list(
        .c3_apply_source_id, .c3_apply_phase, .c3_apply_operation,
        bundle$hashes$manifest_sha256, bundle$hashes$preview_sha256,
        bundle$hashes$approval_sha256, bundle$hashes$decisions_sha256,
        bundle$hashes$state_sha256, bundle$hashes$text_bundle_sha256,
        bundle$database$database_name, bundle$database$system_identifier,
        bundle$expected_counts_json, bundle$authorized_elements_json,
        options$nonce))
      "succeeded"
    }, error = function(error) {
      if (.c3_apply_is_read_only_error(error)) "read_only" else "rejected"
    })
    if (identical(observed, "succeeded"))
      .c3_common_stop("C3_APPLY_GATE_NOT_READ_ONLY")
    if (!identical(observed, "read_only"))
      .c3_common_stop("C3_APPLY_GATE_ROLE_REJECTED")
    list(outcome = "gate_verified",
         summary = sprintf("mode=gate-read-only role=redaktion probe=read_only %s",
                            bundle$summary_line))
  }, error = function(error) {
    try(gateway$execute(.c3_apply_sql$rollback), silent = TRUE)
    stop(conditionMessage(error), call. = FALSE)
  })
  gateway$execute(.c3_apply_sql$rollback)
  outcome
}

.c3_apply_mode_preflight <- function(bundle, options, connect) {
  gateway <- .c3_apply_open(connect)
  on.exit(.c3_apply_close(gateway), add = TRUE)
  outcome <- tryCatch({
    identity <- .c3_apply_prologue(gateway, bundle, options$actor_id,
                                    read_only = TRUE)
    rows <- tryCatch(
      gateway$query(.c3_apply_sql$preview, list(
        .c3_apply_source_id, .c3_apply_phase, bundle$selection_json)),
      error = function(e) .c3_apply_rpc_error(e, "C3_APPLY_PREVIEW_FAILED"))
    text <- as.character(.c3_apply_scalar(rows, "result", "C3_APPLY_PREVIEW_FAILED"))
    state_sha256 <- digest::digest(text, algo = "sha256", serialize = FALSE)
    ## Reported, deliberately NOT enforced: red_apply_reimport_cases
    ## re-measures every case under its own locks and is the single
    ## enforcing drift gate (Fund H1). A second enforcement site here could
    ## only ever disagree with it.
    list(outcome = "preflight_ok", state_sha256 = state_sha256,
         state_matches_manifest = identical(state_sha256,
                                             bundle$hashes$state_sha256),
         summary = sprintf(
           "mode=preflight database=%s system_identifier=%s live_state_sha256=%s manifest_state_sha256=%s state_match=%s %s",
           identity$database_name, identity$system_identifier, state_sha256,
           bundle$hashes$state_sha256,
           identical(state_sha256, bundle$hashes$state_sha256),
           bundle$summary_line))
  }, error = function(error) {
    try(gateway$execute(.c3_apply_sql$rollback), silent = TRUE)
    stop(conditionMessage(error), call. = FALSE)
  })
  gateway$execute(.c3_apply_sql$rollback)
  outcome
}

## The write transaction, shared by `apply` and `rehearse-rollback`. It ends in
## exactly one of two ways: COMMIT (apply) or ROLLBACK (rehearsal). Nothing
## else happens between the receipt verification and that decision.
.c3_apply_write_transaction <- function(gateway, bundle, options, commit) {
  ## Everything the transaction produces is returned OUT of the tryCatch
  ## block. A `<<-` here would assign past this frame (the promise is
  ## evaluated in the caller's frame, so its enclosure is the closure
  ## environment, not this one) and leave the local binding NULL.
  attempt <- tryCatch({
    .c3_apply_prologue(gateway, bundle, options$actor_id, read_only = FALSE)
    authorization_id <- .c3_apply_authorize(gateway, bundle, options$nonce)
    rows <- tryCatch(
      gateway$query(.c3_apply_sql$apply, list(
        authorization_id, bundle$hashes$manifest_sha256,
        bundle$hashes$approval_sha256)),
      error = function(e) .c3_apply_rpc_error(e, "C3_APPLY_RPC_FAILED"))
    receipt_text <- as.character(.c3_apply_scalar(rows, "receipt",
                                                   "C3_APPLY_RECEIPT_INVALID"))
    list(authorization_id = authorization_id,
         verified = .c3_apply_verify_receipt(receipt_text, bundle,
                                              .c3_apply_operation,
                                              authorization_id))
  }, error = function(error) {
    try(gateway$execute(.c3_apply_sql$rollback), silent = TRUE)
    stop(conditionMessage(error), call. = FALSE)
  })
  verified <- attempt$verified
  authorization_id <- attempt$authorization_id
  if (!commit) {
    gateway$execute(.c3_apply_sql$rollback)
    return(list(state = "rolled_back", verified = verified,
                authorization_id = authorization_id))
  }
  ## Losing the link here leaves the outcome UNDECIDED, not partial. The
  ## caller reconnects, takes the global lock, and reconciles -- it never
  ## retries blind.
  committed <- tryCatch({ gateway$execute(.c3_apply_sql$commit); TRUE },
                        error = function(e) FALSE)
  list(state = if (committed) "committed" else "commit_unknown",
       verified = verified, authorization_id = authorization_id)
}

.c3_apply_reconcile_on_new_connection <- function(bundle, options, connect) {
  gateway <- .c3_apply_open(connect)
  on.exit(.c3_apply_close(gateway), add = TRUE)
  result <- tryCatch(.c3_apply_reconcile(gateway, bundle, options$nonce),
                     error = function(error) {
                       try(gateway$execute(.c3_apply_sql$rollback), silent = TRUE)
                       stop(conditionMessage(error), call. = FALSE)
                     })
  gateway$execute(.c3_apply_sql$rollback)
  result
}

.c3_apply_mode_apply <- function(bundle, options, connect) {
  gateway <- .c3_apply_open(connect)
  written <- tryCatch(
    .c3_apply_write_transaction(gateway, bundle, options, commit = TRUE),
    error = function(error) {
      .c3_apply_close(gateway)
      stop(conditionMessage(error), call. = FALSE)
    })
  .c3_apply_close(gateway)
  if (identical(written$state, "committed")) {
    verified <- written$verified
    return(list(outcome = "applied", batch_id = verified$batch_id,
                authorization_id = verified$authorization_id,
                change_set_id = verified$change_set_id,
                summary = sprintf(
                  "mode=apply outcome=applied batch_id=%s change_set_id=%s elements=%d %s",
                  verified$batch_id, verified$change_set_id, verified$elements,
                  bundle$summary_line)))
  }
  reconciled <- .c3_apply_reconcile_on_new_connection(bundle, options, connect)
  if (identical(reconciled$outcome, "unknown"))
    .c3_common_stop("C3_APPLY_COMMIT_UNKNOWN")
  list(outcome = reconciled$outcome, batch_id = reconciled$batch_id,
       authorization_id = reconciled$authorization_id,
       change_set_id = reconciled$change_set_id,
       summary = sprintf(
         "mode=apply outcome=%s batch_id=%s %s", reconciled$outcome,
         if (is.null(reconciled$batch_id)) "-" else reconciled$batch_id,
         bundle$summary_line))
}

.c3_apply_mode_status <- function(bundle, options, connect) {
  reconciled <- .c3_apply_reconcile_on_new_connection(bundle, options, connect)
  if (identical(reconciled$outcome, "unknown"))
    .c3_common_stop("C3_APPLY_COMMIT_UNKNOWN")
  list(outcome = reconciled$outcome, batch_id = reconciled$batch_id,
       authorization_id = reconciled$authorization_id,
       change_set_id = reconciled$change_set_id,
       summary = sprintf(
         "mode=status outcome=%s batch_id=%s %s", reconciled$outcome,
         if (is.null(reconciled$batch_id)) "-" else reconciled$batch_id,
         bundle$summary_line))
}

.c3_apply_mode_rehearse <- function(bundle, options, connect) {
  ## Three connections, in this order. The domain proof is SELF-measured
  ## (before vs after), not a comparison against the manifest's older recorded
  ## hash -- any unrelated local drift since the manifest was built would make
  ## that comparison false-fail while proving nothing about the rehearsal.
  before_gateway <- .c3_apply_open(connect)
  state_before <- tryCatch(
    .c3_apply_measure_state(before_gateway, bundle, options$actor_id),
    error = function(error) {
      .c3_apply_close(before_gateway); stop(conditionMessage(error), call. = FALSE)
    })
  .c3_apply_close(before_gateway)

  rehearsal_gateway <- .c3_apply_open(connect)
  written <- tryCatch(
    .c3_apply_write_transaction(rehearsal_gateway, bundle, options, commit = FALSE),
    error = function(error) {
      .c3_apply_close(rehearsal_gateway)
      stop(conditionMessage(error), call. = FALSE)
    })
  .c3_apply_close(rehearsal_gateway)
  if (!identical(written$state, "rolled_back"))
    .c3_common_stop("C3_APPLY_REHEARSAL_NOT_ROLLED_BACK")

  after_gateway <- .c3_apply_open(connect)
  proof <- tryCatch({
    reconciled <- .c3_apply_reconcile(after_gateway, bundle, options$nonce)
    after_gateway$execute(.c3_apply_sql$rollback)
    state_after <- .c3_apply_measure_state(after_gateway, bundle, options$actor_id)
    list(reconciled = reconciled, state_after = state_after)
  }, error = function(error) {
    .c3_apply_close(after_gateway); stop(conditionMessage(error), call. = FALSE)
  })
  .c3_apply_close(after_gateway)

  if (!identical(proof$reconciled$outcome, "not_committed"))
    .c3_common_stop("C3_APPLY_REHEARSAL_LEDGER_RESIDUE")
  if (!identical(state_before, proof$state_after))
    .c3_common_stop("C3_APPLY_REHEARSAL_DOMAIN_RESIDUE")

  list(outcome = "rehearsed",
       batch_id = written$verified$batch_id,
       state_before_sha256 = state_before,
       state_after_sha256 = proof$state_after,
       summary = sprintf(
         "mode=rehearse-rollback outcome=rehearsed rolled_back=true ledger_residue=none state_before_sha256=%s state_after_sha256=%s %s",
         state_before, proof$state_after, bundle$summary_line))
}

.c3_apply_mode_reverse <- function(bundle, options, connect) {
  gateway <- .c3_apply_open(connect)
  on.exit(.c3_apply_close(gateway), add = TRUE)
  result <- tryCatch({
    .c3_apply_prologue(gateway, bundle, options$actor_id, read_only = FALSE)
    batch <- gateway$query(.c3_apply_sql$reverse_batch, list(options$batch_id))
    if (!is.data.frame(batch) || nrow(batch) != 1L)
      .c3_common_stop("C3_APPLY_REVERSAL_BATCH_MISMATCH")
    ## The batch must belong to THIS artefact chain before anything else is
    ## asked about it -- otherwise a reversal authorisation could be minted
    ## for a batch the operator never approved.
    if (!identical(as.character(batch[["operation"]][[1L]]), "apply") ||
        !identical(as.character(batch[["phase"]][[1L]]), .c3_apply_phase) ||
        !identical(as.integer(batch[["source_id"]][[1L]]), .c3_apply_source_id) ||
        !identical(as.character(batch[["manifest_sha256"]][[1L]]),
                   bundle$hashes$manifest_sha256) ||
        !identical(as.character(batch[["preview_sha256"]][[1L]]),
                   bundle$hashes$preview_sha256))
      .c3_common_stop("C3_APPLY_REVERSAL_BATCH_MISMATCH")
    if (!identical(as.character(batch[["status"]][[1L]]), "finalized"))
      .c3_common_stop("C3_APPLY_REVERSAL_BATCH_NOT_REVERSIBLE")

    receipt_sha256 <- as.character(.c3_apply_scalar(
      gateway$query(.c3_apply_sql$reversal_receipt_sha, list(options$batch_id)),
      "receipt_sha256", "C3_APPLY_REVERSAL_RECEIPT_INVALID"))
    if (!.c3_common_scalar_string(receipt_sha256, "^[0-9a-f]{64}$"))
      .c3_common_stop("C3_APPLY_REVERSAL_RECEIPT_INVALID")

    authorization_id <- as.character(.c3_apply_scalar(
      tryCatch(gateway$query(.c3_apply_sql$authorize_reversal,
                              list(options$batch_id, receipt_sha256,
                                   options$reversal_nonce)),
               error = function(e)
                 .c3_apply_rpc_error(e, "C3_APPLY_AUTHORIZATION_FAILED")),
      "authorization_id", "C3_APPLY_AUTHORIZATION_FAILED"))
    if (!.c3_common_scalar_string(authorization_id, .c3_apply_uuid_pattern))
      .c3_common_stop("C3_APPLY_AUTHORIZATION_FAILED")

    rows <- tryCatch(
      gateway$query(.c3_apply_sql$reverse,
                     list(authorization_id, options$batch_id)),
      error = function(e) .c3_apply_rpc_error(e, "C3_APPLY_RPC_FAILED"))
    receipt_text <- as.character(.c3_apply_scalar(rows, "receipt",
                                                   "C3_APPLY_RECEIPT_INVALID"))
    verified <- .c3_apply_verify_receipt(receipt_text, bundle, "reversal",
                                          authorization_id)
    if (identical(verified$batch_id, options$batch_id))
      .c3_common_stop("C3_APPLY_RECEIPT_MISMATCH")
    verified
  }, error = function(error) {
    try(gateway$execute(.c3_apply_sql$rollback), silent = TRUE)
    stop(conditionMessage(error), call. = FALSE)
  })
  committed <- tryCatch({ gateway$execute(.c3_apply_sql$commit); TRUE },
                        error = function(e) FALSE)
  if (!committed) .c3_common_stop("C3_APPLY_COMMIT_UNKNOWN")
  list(outcome = "reversed_batch", batch_id = result$batch_id,
       reversed_batch_id = options$batch_id,
       change_set_id = result$change_set_id,
       summary = sprintf(
         "mode=reverse outcome=reversed_batch reversal_batch_id=%s reversed_batch_id=%s change_set_id=%s %s",
         result$batch_id, options$batch_id, result$change_set_id,
         bundle$summary_line))
}

## ---- Entry point ----------------------------------------------------------

## `connect` is a zero-argument factory returning
## `list(query(sql, params), execute(sql, params), close())`. The CLI supplies
## a DBI/RPostgres-backed implementation; the tests supply a call-recording
## fake. Every mode that needs more than one session calls the factory again --
## a fresh connection can never carry a leftover app.change_set_id, which is
## exactly the precondition red_apply_reimport_cases fails closed on.
c3_apply_run <- function(mode, bundle, options, connect) {
  if (!(is.character(mode) && length(mode) == 1L && mode %in% .c3_apply_modes))
    .c3_common_stop("C3_APPLY_MODE_INVALID")
  if (!is.list(bundle) || !is.list(options))
    .c3_common_stop("C3_APPLY_ARGUMENTS_INVALID")
  if (!.c3_common_scalar_string(options$actor_id, .c3_apply_uuid_pattern))
    .c3_common_stop("C3_APPLY_ACTOR_ID_INVALID")
  if (!.c3_common_scalar_string(options$nonce, .c3_apply_uuid_pattern))
    .c3_common_stop("C3_APPLY_NONCE_INVALID")
  switch(mode,
    "gate-read-only" = .c3_apply_mode_gate_read_only(bundle, options, connect),
    "preflight" = .c3_apply_mode_preflight(bundle, options, connect),
    "rehearse-rollback" = .c3_apply_mode_rehearse(bundle, options, connect),
    "apply" = .c3_apply_mode_apply(bundle, options, connect),
    "status" = .c3_apply_mode_status(bundle, options, connect),
    "reverse" = .c3_apply_mode_reverse(bundle, options, connect))
}
