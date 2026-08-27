# Read-only database profiles for all mapped DAA 1939 v50 provenance subjects.
# Requires preview_reimport_1939_v50_helpers.R and
# profile_identity_review_1939_v50_helpers.R to be sourced first.

provenance_profile_stop <- function(code, detail = NULL) {
  message <- if (is.null(detail) || !nzchar(as.character(detail))) code else {
    paste(code, as.character(detail), sep = ": ")
  }
  stop(message, call. = FALSE)
}

provenance_profile_text <- function(value, code = "PROVENANCE_PROFILE_INPUT_INVALID") {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    provenance_profile_stop(code)
  }
  value
}

provenance_profile_positive_integer <- function(value,
    code = "PROVENANCE_PROFILE_INPUT_INVALID") {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      value < 1 || value != floor(value)) provenance_profile_stop(code)
  as.integer(value)
}

provenance_profile_hash <- function(value) {
  value <- provenance_profile_text(value, "PROVENANCE_PROFILE_HASH_INVALID")
  if (!grepl("^[0-9a-f]{64}$", value)) {
    provenance_profile_stop("PROVENANCE_PROFILE_HASH_INVALID")
  }
  value
}

validate_provenance_database_preview <- function(preview, expected_profiles) {
  expected_profiles <- provenance_profile_positive_integer(expected_profiles)
  if (!is.list(preview) ||
      !identical(preview$schema_version, "1939-v50-database-preview-v3") ||
      !identical(preview$canonical_mutations_authorized, FALSE) ||
      !identical(preview$reimport_gate, "NO-GO") ||
      !is.list(preview$database) ||
      !identical(preview$database$transaction_read_only, "on") ||
      !is.list(preview$source) ||
      !identical(preview$source$udgave, "DAA 1939") ||
      !is.list(preview$person_anchors) ||
      !identical(preview$person_anchors$missing_count, 0L) ||
      !identical(preview$person_anchors$collision_count, 0L) ||
      !is.list(preview$source_personas) ||
      !identical(preview$source_personas$target_mismatch_count, 0L)) {
    provenance_profile_stop("PROVENANCE_PROFILE_INPUT_INVALID")
  }
  rows <- preview$person_anchors$matched
  if (!is.list(rows) || length(rows) != expected_profiles ||
      !identical(preview$person_anchors$matched_count, expected_profiles)) {
    provenance_profile_stop("PROVENANCE_PROFILE_COVERAGE_INVALID")
  }
  keys <- vapply(rows, function(row) {
    if (!is.list(row)) provenance_profile_stop("PROVENANCE_PROFILE_INPUT_INVALID")
    provenance_profile_text(row$baseline_record_key)
  }, character(1L))
  ids <- vapply(rows, function(row) {
    provenance_profile_positive_integer(row$person_id)
  }, integer(1L))
  if (anyDuplicated(keys) || anyDuplicated(ids) || !identical(keys, sort(keys))) {
    provenance_profile_stop("PROVENANCE_PROFILE_COVERAGE_INVALID")
  }
  list(keys = keys, person_ids = ids)
}

provenance_profile_query_rows <- function(frame, column, value) {
  if (!nrow(frame)) return(integer())
  which(!is.na(frame[[column]]) & frame[[column]] == value)
}

provenance_profile_editorial_events <- function(frame, index) {
  if (!"editorial_events" %in% names(frame) || is.na(frame$editorial_events[[index]])) {
    return(0L)
  }
  as.integer(frame$editorial_events[[index]])
}

provenance_profile_nullable_text <- function(value) {
  if (!length(value) || is.na(value[[1L]]) || !nzchar(as.character(value[[1L]]))) return(NULL)
  as.character(value[[1L]])
}

provenance_profile_nullable_integer <- function(value) {
  if (!length(value) || is.na(value[[1L]])) return(NULL)
  as.integer(value[[1L]])
}

provenance_profile_evidence_row <- function(frame, index, id_column) {
  raw <- if (!is.na(frame$date_raw[[index]]) &&
      nzchar(as.character(frame$date_raw[[index]]))) {
    frame$date_raw[index]
  } else frame$vaerdi_tekst[index]
  list(
    row_id = as.integer(frame[[id_column]][[index]]),
    assertion_id = provenance_profile_nullable_integer(frame$assertion_id[index]),
    raw_value = provenance_profile_nullable_text(raw),
    citation = if (is.na(frame$citation_id[[index]])) NULL else list(
      citation_id = as.integer(frame$citation_id[[index]]),
      text = provenance_profile_nullable_text(frame$citat_tekst[index]),
      page = provenance_profile_nullable_text(frame$citation_side[index])
    ),
    editorial_events = provenance_profile_editorial_events(frame, index)
  )
}

.build_provenance_database_profiles <- function(database_preview, query_fn, execute_fn,
    expected_database, expected_profiles = 543L, database_preview_sha256,
    snapshot_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) {
  declared <- validate_provenance_database_preview(database_preview, expected_profiles)
  expected_database <- provenance_profile_text(expected_database,
    "PROVENANCE_PROFILE_DATABASE_MISMATCH")
  database_preview_sha256 <- provenance_profile_hash(database_preview_sha256)
  if (!is.function(query_fn) || !is.function(execute_fn)) {
    provenance_profile_stop("PROVENANCE_PROFILE_INPUT_INVALID")
  }

  execute <- function(sql, params = list()) {
    assert_read_only_sql(sql)
    execute_fn(sql, params)
  }
  query <- function(sql, params = list()) {
    assert_read_only_sql(sql)
    value <- query_fn(sql, params)
    if (!is.data.frame(value)) provenance_profile_stop("PROVENANCE_PROFILE_QUERY_INVALID")
    value
  }
  sql <- database_preview_sql_registry()

  transaction_active <- FALSE
  execute(sql$begin_read_only)
  transaction_active <- TRUE
  on.exit(if (transaction_active) try(execute(sql$rollback), silent = TRUE), add = TRUE)
  execute(sql$statement_timeout)
  execute(sql$lock_timeout)
  readonly <- query(sql$transaction_read_only)
  if (nrow(readonly) != 1L ||
      !identical(as.character(readonly$transaction_read_only[[1L]]), "on")) {
    provenance_profile_stop("PROVENANCE_PROFILE_NOT_READ_ONLY")
  }
  metadata <- query(sql$metadata)
  if (nrow(metadata) != 1L ||
      !identical(as.character(metadata$database_name[[1L]]), expected_database)) {
    provenance_profile_stop("PROVENANCE_PROFILE_DATABASE_MISMATCH")
  }
  columns <- query(sql$profile_capability_columns)
  actual_columns <- if (nrow(columns)) {
    paste(columns$table_schema, columns$table_name, columns$column_name, sep = ".")
  } else character()
  required <- required_identity_profile_columns()
  missing <- unlist(lapply(names(required), function(table) {
    setdiff(paste(table, required[[table]], sep = "."), actual_columns)
  }), use.names = FALSE)
  if (length(missing)) {
    provenance_profile_stop("PROVENANCE_PROFILE_CAPABILITY_BLOCKER",
      paste(sort(missing), collapse = ","))
  }

  source_id <- provenance_profile_positive_integer(database_preview$source$id)
  anchors_all <- query(sql$profile_anchors, list(source_id))
  keep <- anchors_all$record_key %in% declared$keys
  anchors <- anchors_all[keep, , drop = FALSE]
  actual_pairs <- paste(as.character(anchors$record_key), as.integer(anchors$person_id), sep = ":")
  declared_pairs <- paste(declared$keys, declared$person_ids, sep = ":")
  if (nrow(anchors) != length(declared$keys) || anyDuplicated(anchors$record_key) ||
      anyDuplicated(anchors$person_id) ||
      !identical(sort(actual_pairs), sort(declared_pairs))) {
    provenance_profile_stop("PROVENANCE_PROFILE_ANCHOR_MISMATCH")
  }

  narratives_all <- query(sql$profile_narratives, list(source_id))
  narratives <- narratives_all[narratives_all$record_key %in% declared$keys, , drop = FALSE]
  facts_all <- query(sql$profile_person_facts, list(source_id))
  facts <- facts_all[facts_all$record_key %in% declared$keys, , drop = FALSE]
  relations <- query(sql$profile_relations, list(source_id))
  family_members_all <- query(sql$profile_family_members, list(source_id))
  family_members <- family_members_all[
    family_members_all$target_person_id %in% declared$person_ids, , drop = FALSE]
  family_facts_all <- query(sql$profile_family_facts, list(source_id))
  family_facts <- family_facts_all[
    family_facts_all$target_person_id %in% declared$person_ids, , drop = FALSE]

  profiles <- lapply(seq_along(declared$keys), function(position) {
    key <- declared$keys[[position]]
    person_id <- declared$person_ids[[position]]
    anchor_index <- which(anchors$record_key == key & anchors$person_id == person_id)[[1L]]
    narrative_indexes <- provenance_profile_query_rows(narratives, "record_key", key)
    fact_indexes <- provenance_profile_query_rows(facts, "record_key", key)
    relation_indexes <- if (nrow(relations)) {
      which(relations$subjekt_id == person_id | relations$objekt_id == person_id)
    } else integer()
    member_indexes <- provenance_profile_query_rows(family_members, "target_person_id", person_id)
    family_ids <- if (length(member_indexes)) {
      sort(unique(as.integer(family_members$family_id[member_indexes])))
    } else integer()
    list(
      record_key = key,
      person_id = person_id,
      display_name = as.character(anchors$visning_navn[[anchor_index]]),
      staged = as.logical(anchors$staged[[anchor_index]]),
      narratives = lapply(narrative_indexes, function(index) list(
        narrative_id = as.integer(narratives$id[[index]]),
        text = as.character(narratives$tekst[[index]]),
        page = provenance_profile_nullable_text(narratives$side[index]),
        private = as.logical(narratives$privat[[index]]),
        editorial_events = provenance_profile_editorial_events(narratives, index)
      )),
      facts = lapply(fact_indexes, function(index) {
        row <- provenance_profile_evidence_row(facts, index, "fact_id")
        c(list(fact_id = row$row_id,
               fact_type = as.character(facts$faktatype[[index]])), row[names(row) != "row_id"])
      }),
      relations = lapply(relation_indexes, function(index) {
        row <- provenance_profile_evidence_row(relations, index, "relation_id")
        c(list(relation_id = row$row_id,
               role = as.character(relations$rolle[[index]]),
               subject_person_id = as.integer(relations$subjekt_id[[index]]),
               subject_display_name = provenance_profile_nullable_text(relations$subjekt_navn[index]),
               object_person_id = as.integer(relations$objekt_id[[index]]),
               object_display_name = provenance_profile_nullable_text(relations$objekt_navn[index])),
          row[names(row) != "row_id"])
      }),
      families = lapply(family_ids, function(family_id) {
        members <- member_indexes[family_members$family_id[member_indexes] == family_id]
        ff <- which(family_facts$target_person_id == person_id &
          family_facts$family_id == family_id)
        list(
          family_id = family_id,
          members = lapply(members, function(index) list(
            person_id = as.integer(family_members$member_person_id[[index]]),
            role = as.character(family_members$member_role[[index]]),
            display_name = as.character(family_members$member_name[[index]]),
            editorial_events = provenance_profile_editorial_events(family_members, index)
          )),
          facts = lapply(ff, function(index) {
            row <- provenance_profile_evidence_row(family_facts, index, "fact_id")
            c(list(fact_id = row$row_id,
                   fact_type = as.character(family_facts$faktatype[[index]])),
              row[names(row) != "row_id"])
          })
        )
      })
    )
  })

  execute(sql$rollback)
  transaction_active <- FALSE
  list(
    schema_version = "1939-v50-provenance-db-profiles-v1",
    generator_version = "profile_provenance_review_1939_v50.R:v1",
    snapshot_at = provenance_profile_text(snapshot_at),
    input = list(
      database_preview_sha256 = database_preview_sha256,
      import_preview_sha256 = database_preview$input_preview$sha256,
      declared_record_keys = as.list(declared$keys)
    ),
    database = list(
      database_name = as.character(metadata$database_name[[1L]]),
      server_version = as.character(metadata$server_version[[1L]]),
      server_version_num = as.character(metadata$server_version_num[[1L]]),
      transaction_read_only = "on",
      source_id = source_id
    ),
    counts = list(
      profiles = length(profiles),
      narratives = sum(vapply(profiles, function(row) length(row$narratives), integer(1L))),
      facts = sum(vapply(profiles, function(row) length(row$facts), integer(1L))),
      relations = sum(vapply(profiles, function(row) length(row$relations), integer(1L))),
      families = sum(vapply(profiles, function(row) length(row$families), integer(1L))),
      family_facts = sum(vapply(profiles, function(row) {
        sum(vapply(row$families, function(family) length(family$facts), integer(1L)))
      }, integer(1L)))
    ),
    profiles = profiles,
    review_only = TRUE,
    database_write_authorized = FALSE,
    canonical_mutations_authorized = FALSE
  )
}

build_provenance_database_profiles <- function(database_preview, query_fn, execute_fn,
    expected_database, database_preview_sha256,
    snapshot_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) {
  .build_provenance_database_profiles(
    database_preview, query_fn, execute_fn,
    expected_database = expected_database,
    expected_profiles = 543L,
    database_preview_sha256 = database_preview_sha256,
    snapshot_at = snapshot_at
  )
}

write_provenance_profile_output <- function(value, path) {
  path <- provenance_profile_text(path, "PROVENANCE_PROFILE_OUTPUT_INVALID")
  if (file.exists(path)) {
    provenance_profile_stop("PROVENANCE_PROFILE_OUTPUT_EXISTS")
  }
  parent <- dirname(path)
  if (!dir.exists(parent)) dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  connection <- NULL
  success <- FALSE
  on.exit({
    if (!is.null(connection)) try(close(connection), silent = TRUE)
    if (!success && file.exists(path)) unlink(path, force = TRUE)
  }, add = TRUE)
  connection <- file(path, open = "wx", encoding = "UTF-8")
  writeLines(jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE,
    null = "null", digits = NA), connection, useBytes = TRUE)
  close(connection)
  connection <- NULL
  success <- TRUE
  invisible(path)
}
