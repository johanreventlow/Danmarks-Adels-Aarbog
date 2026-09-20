## Pure structural transformation for the C3 current-state export.
## This file has no database access and never accepts narrative prose.
##
## Every entry point sources c3_export_shared_1939_v50_helpers.R before this
## file. The `.c3_state_*` names below are thin aliases onto the shared
## primitives, kept so this file's external contract (and its existing
## tests) stay unchanged while the implementation is genuinely shared with
## export_c3_apply_preview_1939_v50.R.

.c3_state_stop <- .c3_common_stop
.c3_state_require_columns <- .c3_common_require_columns
.c3_state_valid_ids <- .c3_common_valid_ids
.c3_state_scalar_string <- .c3_common_scalar_string
.c3_state_optional_strings <- .c3_common_optional_strings

build_c3_current_state_1939_v50 <- function(
    person_ids, person_rows, narrative_rows, identity_rows, partner_conflict_rows,
    database_name, database_identity, generator, selection_sha256) {
  person_columns <- c("person_id", "staged", "privat")
  narrative_columns <- c("person_id", "narrative_id", "old_sha256", "privat",
                         "side", "source_record_id", "binding_status")
  edge_columns <- c("rolle", "subject_id", "object_id")
  partner_columns <- c("left_person_id", "right_person_id", "family_id")

  ## Column presence is checked before every vector predicate. Missing privacy
  ## columns must never turn into any(logical(0)) == FALSE.
  .c3_state_require_columns(person_rows, person_columns,
                            "C3_STATE_PERSON_COLUMNS_INVALID")
  .c3_state_require_columns(narrative_rows, narrative_columns,
                            "C3_STATE_NARRATIVE_COLUMNS_INVALID")
  .c3_state_require_columns(identity_rows, edge_columns,
                            "C3_STATE_EDGE_COLUMNS_INVALID")
  .c3_state_require_columns(partner_conflict_rows, partner_columns,
                            "C3_STATE_PARTNER_COLUMNS_INVALID")

  if (!.c3_state_valid_ids(person_ids) || anyDuplicated(person_ids))
    .c3_state_stop("C3_STATE_PERSON_IDS_INVALID")
  selected_ids <- sort(as.numeric(person_ids), method = "radix")

  if (!.c3_state_valid_ids(person_rows$person_id))
    .c3_state_stop("C3_STATE_PERSON_ID_INVALID")
  if (anyDuplicated(person_rows$person_id))
    .c3_state_stop("C3_STATE_PERSON_DUPLICATE")
  if (!setequal(as.numeric(person_rows$person_id), selected_ids) ||
      nrow(person_rows) != length(selected_ids))
    .c3_state_stop("C3_STATE_PERSON_SET_MISMATCH")
  if (!is.logical(person_rows$staged) || anyNA(person_rows$staged))
    .c3_state_stop("C3_STATE_PERSON_STAGED_INVALID")
  if (!is.logical(person_rows$privat) ||
      any(is.na(person_rows$privat) | person_rows$privat))
    .c3_state_stop("C3_STATE_PERSON_PRIVATE")

  if (!.c3_state_valid_ids(narrative_rows$person_id) ||
      !.c3_state_valid_ids(narrative_rows$narrative_id))
    .c3_state_stop("C3_STATE_NARRATIVE_ID_INVALID")
  if (anyDuplicated(narrative_rows$person_id) ||
      anyDuplicated(narrative_rows$narrative_id))
    .c3_state_stop("C3_STATE_NARRATIVE_DUPLICATE")
  if (!setequal(as.numeric(narrative_rows$person_id), selected_ids) ||
      nrow(narrative_rows) != length(selected_ids))
    .c3_state_stop("C3_STATE_NARRATIVE_SET_MISMATCH")
  if (!is.character(narrative_rows$old_sha256) ||
      any(is.na(narrative_rows$old_sha256) |
          !grepl("^[0-9a-f]{64}$", narrative_rows$old_sha256)))
    .c3_state_stop("C3_STATE_NARRATIVE_SHA_INVALID")
  if (!is.logical(narrative_rows$privat) ||
      any(is.na(narrative_rows$privat) | narrative_rows$privat))
    .c3_state_stop("C3_STATE_NARRATIVE_PRIVATE")
  if (!.c3_state_optional_strings(narrative_rows$side) ||
      !.c3_state_optional_strings(narrative_rows$source_record_id) ||
      !.c3_state_optional_strings(narrative_rows$binding_status))
    .c3_state_stop("C3_STATE_NARRATIVE_METADATA_INVALID")
  uuid_pattern <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  bound <- !is.na(narrative_rows$source_record_id)
  if (any(bound & !grepl(uuid_pattern, narrative_rows$source_record_id)) ||
      any(bound != !is.na(narrative_rows$binding_status)) ||
      any(!is.na(narrative_rows$binding_status) &
          !(narrative_rows$binding_status %in% c("draft", "published", "withdrawn"))))
    .c3_state_stop("C3_STATE_BINDING_INVALID")

  if (!is.character(identity_rows$rolle))
    .c3_state_stop("C3_STATE_EDGE_ROLE_INVALID")
  if (nrow(identity_rows) > 0L) {
    if (!.c3_state_valid_ids(identity_rows$subject_id) ||
        !.c3_state_valid_ids(identity_rows$object_id))
      .c3_state_stop("C3_STATE_EDGE_ENDPOINT_INVALID")
    if (any(is.na(identity_rows$rolle)) ||
        any(!(identity_rows$rolle %in% c("samme_som", "ikke_samme_som"))))
      .c3_state_stop("C3_STATE_EDGE_ROLE_INVALID")
    if (any(identity_rows$subject_id == identity_rows$object_id))
      .c3_state_stop("C3_STATE_EDGE_DIRECTION_INVALID")
    if (any(!(identity_rows$subject_id %in% selected_ids) &
            !(identity_rows$object_id %in% selected_ids)))
      .c3_state_stop("C3_STATE_EDGE_SELECTION_INVALID")
  }
  normalized_edges <- data.frame(
    role = as.character(identity_rows$rolle),
    subject_id = as.numeric(identity_rows$subject_id),
    object_id = as.numeric(identity_rows$object_id),
    stringsAsFactors = FALSE
  )
  not_same <- normalized_edges$role == "ikke_samme_som"
  if (any(not_same)) {
    lower <- pmin(normalized_edges$subject_id[not_same],
                  normalized_edges$object_id[not_same])
    upper <- pmax(normalized_edges$subject_id[not_same],
                  normalized_edges$object_id[not_same])
    normalized_edges$subject_id[not_same] <- lower
    normalized_edges$object_id[not_same] <- upper
  }
  edge_keys <- paste(normalized_edges$role, normalized_edges$subject_id,
                     normalized_edges$object_id, sep = ":")
  if (anyDuplicated(edge_keys)) .c3_state_stop("C3_STATE_EDGE_DUPLICATE")

  if (nrow(partner_conflict_rows) > 0L &&
      (!.c3_state_valid_ids(partner_conflict_rows$left_person_id) ||
       !.c3_state_valid_ids(partner_conflict_rows$right_person_id) ||
       !.c3_state_valid_ids(partner_conflict_rows$family_id)))
    .c3_state_stop("C3_STATE_PARTNER_ID_INVALID")
  normalized_partners <- data.frame(
    left_person_id = pmin(as.numeric(partner_conflict_rows$left_person_id),
                          as.numeric(partner_conflict_rows$right_person_id)),
    right_person_id = pmax(as.numeric(partner_conflict_rows$left_person_id),
                           as.numeric(partner_conflict_rows$right_person_id)),
    family_id = as.numeric(partner_conflict_rows$family_id)
  )
  if (nrow(normalized_partners) > 0L) {
    if (any(normalized_partners$left_person_id == normalized_partners$right_person_id) ||
        any(!(normalized_partners$left_person_id %in% selected_ids)) ||
        any(!(normalized_partners$right_person_id %in% selected_ids)))
      .c3_state_stop("C3_STATE_PARTNER_SELECTION_INVALID")
  }
  partner_keys <- paste(normalized_partners$left_person_id,
                        normalized_partners$right_person_id,
                        normalized_partners$family_id, sep = ":")
  if (anyDuplicated(partner_keys)) .c3_state_stop("C3_STATE_PARTNER_DUPLICATE")

  if (!.c3_state_scalar_string(database_name, "^[A-Za-z0-9_.-]+$"))
    .c3_state_stop("C3_STATE_DATABASE_NAME_INVALID")
  if (!.c3_state_scalar_string(database_identity, "^[0-9]+$"))
    .c3_state_stop("C3_STATE_DATABASE_IDENTITY_INVALID")
  if (!.c3_state_scalar_string(generator, "^[A-Za-z0-9_.:/-]+$"))
    .c3_state_stop("C3_STATE_GENERATOR_INVALID")
  if (!.c3_state_scalar_string(selection_sha256, "^[0-9a-f]{64}$"))
    .c3_state_stop("C3_STATE_SELECTION_SHA_INVALID")

  persons <- lapply(order(person_rows$person_id), function(i) list(
    person_id = as.numeric(person_rows$person_id[[i]]),
    staged = as.logical(person_rows$staged[[i]]),
    privat = as.logical(person_rows$privat[[i]])
  ))
  narratives <- lapply(order(narrative_rows$person_id, narrative_rows$narrative_id),
                       function(i) list(
    person_id = as.numeric(narrative_rows$person_id[[i]]),
    narrative_id = as.numeric(narrative_rows$narrative_id[[i]]),
    old_sha256 = as.character(narrative_rows$old_sha256[[i]]),
    privat = as.logical(narrative_rows$privat[[i]]),
    side = if (is.na(narrative_rows$side[[i]])) NA_character_
           else as.character(narrative_rows$side[[i]]),
    source_record_id = if (is.na(narrative_rows$source_record_id[[i]])) NA_character_
                       else as.character(narrative_rows$source_record_id[[i]]),
    binding_status = if (is.na(narrative_rows$binding_status[[i]])) NA_character_
                     else as.character(narrative_rows$binding_status[[i]])
  ))
  identity_edges <- if (nrow(normalized_edges) == 0L) list() else {
    edge_order <- order(normalized_edges$role, normalized_edges$subject_id,
                        normalized_edges$object_id, method = "radix")
    lapply(edge_order, function(i) list(
      role = normalized_edges$role[[i]],
      subject_id = normalized_edges$subject_id[[i]],
      object_id = normalized_edges$object_id[[i]]
    ))
  }
  partner_conflicts <- if (nrow(normalized_partners) == 0L) list() else {
    partner_order <- order(normalized_partners$left_person_id,
                           normalized_partners$right_person_id,
                           normalized_partners$family_id, method = "radix")
    lapply(partner_order, function(i) list(
      left_person_id = normalized_partners$left_person_id[[i]],
      right_person_id = normalized_partners$right_person_id[[i]],
      family_id = normalized_partners$family_id[[i]]
    ))
  }

  list(
    schema_version = "1939-v50-c3-current-state-v1",
    database_name = database_name,
    database_identity = database_identity,
    generator = generator,
    selection_sha256 = selection_sha256,
    persons = persons,
    narratives = narratives,
    identity_edges = identity_edges,
    partner_conflicts = partner_conflicts
  )
}
