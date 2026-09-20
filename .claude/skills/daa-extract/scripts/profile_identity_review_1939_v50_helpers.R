# Read-only database profiling for the 1939 v50 identity review.
# Requires preview_reimport_1939_v50_helpers.R to be sourced first.

identity_profile_stop <- function(code, detail = NULL) {
  message <- if (is.null(detail) || !nzchar(as.character(detail))) code else {
    paste(code, as.character(detail), sep = ": ")
  }
  stop(message, call. = FALSE)
}

identity_scalar_text <- function(value, code = "IDENTITY_PROFILE_INPUT_INVALID") {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    identity_profile_stop(code)
  }
  value
}

identity_nullable_text <- function(value) {
  if (!length(value) || is.na(value[[1L]]) || !nzchar(as.character(value[[1L]]))) return(NULL)
  as.character(value[[1L]])
}

identity_nullable_integer <- function(value) {
  if (!length(value) || is.na(value[[1L]])) return(NULL)
  as.integer(value[[1L]])
}

required_identity_profile_columns <- function() {
  list(
    "public.person_external_id" = c("person_id", "source_id", "record_key"),
    "public.person" = c("id", "staged", "visning_navn"),
    "public.narrative" = c("id", "subjekt_type", "subjekt_id", "source_id", "tekst", "side", "privat"),
    "public.fact" = c("id", "subjekt_type", "subjekt_id", "faktatype"),
    "public.assertion" = c("id", "target_type", "target_id", "vaerdi_tekst", "date_raw"),
    "public.citation" = c("id", "assertion_id", "source_id", "side", "citat_tekst"),
    "public.relation" = c("id", "subjekt_type", "subjekt_id", "objekt_type", "objekt_id", "rolle"),
    "public.family_member" = c("family_id", "person_id", "rolle"),
    "public.change_event" = c("change_set_id", "tabel", "row_pk"),
    "public.change_set" = c("id", "operation")
  )
}

validate_identity_database_preview <- function(preview) {
  if (!is.list(preview) ||
      !identical(preview$schema_version, "1939-v50-database-preview-v1") ||
      !identical(preview$reimport_gate, "NO-GO") ||
      !is.list(preview$input_preview) ||
      !identical(preview$input_preview$schema_version, "1939-v50-import-preview-v1") ||
      !is.list(preview$database) ||
      !identical(preview$database$transaction_read_only, "on") ||
      !is.list(preview$source) ||
      !identical(preview$source$udgave, "DAA 1939") ||
      !is.list(preview$person_anchors) ||
      !is.list(preview$person_anchors$database_only_record_keys) ||
      !is.list(preview$person_anchors$database_only) ||
      !identical(preview$canonical_mutations_authorized, FALSE)) {
    identity_profile_stop("IDENTITY_PROFILE_INPUT_INVALID")
  }
  keys <- vapply(preview$person_anchors$database_only_record_keys,
    identity_scalar_text, character(1L))
  details <- preview$person_anchors$database_only
  detail_keys <- vapply(details, function(row) {
    if (!is.list(row)) identity_profile_stop("IDENTITY_PROFILE_INPUT_INVALID")
    identity_scalar_text(row$record_key)
  }, character(1L))
  person_ids <- vapply(details, function(row) {
    value <- row$person_id
    if (length(value) != 1L || is.na(value) || as.integer(value) < 1L) {
      identity_profile_stop("IDENTITY_PROFILE_INPUT_INVALID")
    }
    as.integer(value)
  }, integer(1L))
  if (!length(keys) || anyDuplicated(keys) || anyDuplicated(detail_keys) ||
      anyDuplicated(person_ids) || !identical(sort(keys), sort(detail_keys)) ||
      !identical(keys, sort(keys)) || !identical(detail_keys, sort(detail_keys))) {
    identity_profile_stop("IDENTITY_PROFILE_INPUT_INVALID")
  }
  invisible(TRUE)
}

identity_profile_hash <- function(value, code = "IDENTITY_PROFILE_INPUT_INVALID") {
  if (is.null(value)) return(NULL)
  value <- identity_scalar_text(value, code)
  if (!grepl("^[0-9a-f]{64}$", value)) identity_profile_stop(code)
  value
}

identity_group_rows <- function(frame, column, value) {
  if (!nrow(frame)) return(integer())
  which(!is.na(frame[[column]]) & frame[[column]] == value)
}

identity_editorial_events <- function(frame, index) {
  if (!"editorial_events" %in% names(frame) || is.na(frame$editorial_events[[index]])) return(0L)
  as.integer(frame$editorial_events[[index]])
}

build_identity_database_profiles <- function(database_preview, query_fn, execute_fn,
    expected_database, database_preview_sha256 = NULL,
    snapshot_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) {
  validate_identity_database_preview(database_preview)
  expected_database <- identity_scalar_text(expected_database, "IDENTITY_PROFILE_DATABASE_MISMATCH")
  database_preview_sha256 <- identity_profile_hash(database_preview_sha256)
  if (!is.function(query_fn) || !is.function(execute_fn)) {
    identity_profile_stop("IDENTITY_PROFILE_INPUT_INVALID")
  }

  execute <- function(sql, params = list()) {
    assert_read_only_sql(sql)
    execute_fn(sql, params)
  }
  query <- function(sql, params = list()) {
    assert_read_only_sql(sql)
    value <- query_fn(sql, params)
    if (!is.data.frame(value)) identity_profile_stop("IDENTITY_PROFILE_QUERY_INVALID")
    value
  }

  execute("BEGIN READ ONLY")
  on.exit(try(execute("ROLLBACK"), silent = TRUE), add = TRUE)
  execute("SET LOCAL statement_timeout = '30s'")
  execute("SET LOCAL lock_timeout = '2s'")
  readonly <- query("SHOW transaction_read_only")
  if (nrow(readonly) != 1L || !identical(as.character(readonly$transaction_read_only[[1L]]), "on")) {
    identity_profile_stop("IDENTITY_PROFILE_NOT_READ_ONLY")
  }
  metadata <- query(paste(
    "SELECT current_database() AS database_name,",
    "current_setting('server_version') AS server_version,",
    "current_setting('server_version_num') AS server_version_num"
  ))
  if (nrow(metadata) != 1L ||
      !identical(as.character(metadata$database_name[[1L]]), expected_database)) {
    identity_profile_stop("IDENTITY_PROFILE_DATABASE_MISMATCH")
  }
  columns <- query(paste(
    "SELECT table_schema, table_name, column_name",
    "FROM information_schema.columns",
    "WHERE table_schema = 'public'",
    "ORDER BY table_schema, table_name, ordinal_position"
  ))
  actual_columns <- if (nrow(columns)) {
    paste(columns$table_schema, columns$table_name, columns$column_name, sep = ".")
  } else character()
  required <- required_identity_profile_columns()
  missing <- unlist(lapply(names(required), function(table) {
    setdiff(paste(table, required[[table]], sep = "."), actual_columns)
  }), use.names = FALSE)
  if (length(missing)) {
    identity_profile_stop("IDENTITY_PROFILE_CAPABILITY_BLOCKER", paste(sort(missing), collapse = ","))
  }

  source_id <- as.integer(database_preview$source$id)
  declared <- database_preview$person_anchors$database_only
  declared_keys <- vapply(declared, `[[`, character(1L), "record_key")
  declared_ids <- vapply(declared, function(row) as.integer(row$person_id), integer(1L))

  anchors_all <- query(paste(
    "SELECT pei.person_id, pei.record_key, p.visning_navn, p.staged",
    "FROM public.person_external_id pei",
    "JOIN public.person p ON p.id = pei.person_id",
    "WHERE pei.source_id = $1",
    "ORDER BY pei.record_key, pei.person_id"
  ), list(source_id))
  keep <- anchors_all$record_key %in% declared_keys
  anchors <- anchors_all[keep, , drop = FALSE]
  anchor_pairs <- paste(as.character(anchors$record_key), as.integer(anchors$person_id), sep = ":")
  declared_pairs <- paste(declared_keys, declared_ids, sep = ":")
  if (nrow(anchors) != length(declared_keys) || anyDuplicated(anchors$record_key) ||
      anyDuplicated(anchors$person_id) || !identical(sort(anchor_pairs), sort(declared_pairs))) {
    identity_profile_stop("IDENTITY_PROFILE_ANCHOR_MISMATCH")
  }

  narratives_all <- query(paste(
    "SELECT n.id, pei.person_id, pei.record_key, n.tekst, n.side, n.privat,",
    "(SELECT count(*) FROM public.change_event ce",
    " JOIN public.change_set cs ON cs.id = ce.change_set_id",
    " WHERE ce.tabel = 'narrative' AND ce.row_pk->>'id' = n.id::text",
    " AND left(cs.operation, 4) = 'red_') AS editorial_events",
    "FROM public.narrative n",
    "JOIN public.person_external_id pei ON pei.person_id = n.subjekt_id AND pei.source_id = $1",
    "WHERE n.subjekt_type = 'person' AND n.source_id = $1",
    "ORDER BY pei.record_key, n.id"
  ), list(source_id))
  narratives <- narratives_all[narratives_all$record_key %in% declared_keys, , drop = FALSE]

  facts_all <- query(paste(
    "SELECT f.id AS fact_id, pei.person_id, pei.record_key, f.faktatype,",
    "a.id AS assertion_id, a.vaerdi_tekst, a.date_raw, c.id AS citation_id,",
    "c.citat_tekst, c.side AS citation_side,",
    "(SELECT count(*) FROM public.change_event ce",
    " JOIN public.change_set cs ON cs.id = ce.change_set_id",
    " WHERE ce.tabel = 'fact' AND ce.row_pk->>'id' = f.id::text",
    " AND left(cs.operation, 4) = 'red_') AS editorial_events",
    "FROM public.fact f",
    "JOIN public.person_external_id pei ON pei.person_id = f.subjekt_id AND pei.source_id = $1",
    "LEFT JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id",
    "LEFT JOIN public.citation c ON c.assertion_id = a.id AND c.source_id = $1",
    "WHERE f.subjekt_type = 'person'",
    "ORDER BY pei.record_key, f.id, a.id, c.id"
  ), list(source_id))
  facts <- facts_all[facts_all$record_key %in% declared_keys, , drop = FALSE]

  relations_all <- query(paste(
    "SELECT r.id AS relation_id, r.rolle, r.subjekt_id, r.objekt_id,",
    "ps.visning_navn AS subjekt_navn, po.visning_navn AS objekt_navn,",
    "a.id AS assertion_id, a.vaerdi_tekst, a.date_raw, c.id AS citation_id,",
    "c.citat_tekst, c.side AS citation_side,",
    "(SELECT count(*) FROM public.change_event ce",
    " JOIN public.change_set cs ON cs.id = ce.change_set_id",
    " WHERE ce.tabel = 'relation' AND ce.row_pk->>'id' = r.id::text",
    " AND left(cs.operation, 4) = 'red_') AS editorial_events",
    "FROM public.relation r",
    "LEFT JOIN public.person ps ON r.subjekt_type = 'person' AND ps.id = r.subjekt_id",
    "LEFT JOIN public.person po ON r.objekt_type = 'person' AND po.id = r.objekt_id",
    "LEFT JOIN public.assertion a ON a.target_type = 'relation' AND a.target_id = r.id",
    "LEFT JOIN public.citation c ON c.assertion_id = a.id AND c.source_id = $1",
    "WHERE (r.subjekt_type = 'person' AND EXISTS (SELECT 1 FROM public.person_external_id pei",
    " WHERE pei.source_id = $1 AND pei.person_id = r.subjekt_id))",
    "OR (r.objekt_type = 'person' AND EXISTS (SELECT 1 FROM public.person_external_id pei",
    " WHERE pei.source_id = $1 AND pei.person_id = r.objekt_id))",
    "ORDER BY r.id, a.id, c.id"
  ), list(source_id))

  family_members_all <- query(paste(
    "SELECT target.person_id AS target_person_id, fm.family_id, fm.person_id AS member_person_id,",
    "fm.rolle AS member_role, p.visning_navn AS member_name,",
    "(SELECT count(*) FROM public.change_event ce",
    " JOIN public.change_set cs ON cs.id = ce.change_set_id",
    " WHERE ce.tabel = 'family_member' AND ce.row_pk->>'family_id' = fm.family_id::text",
    " AND ce.row_pk->>'person_id' = fm.person_id::text",
    " AND left(cs.operation, 4) = 'red_') AS editorial_events",
    "FROM public.family_member target",
    "JOIN public.person_external_id pei ON pei.person_id = target.person_id AND pei.source_id = $1",
    "JOIN public.family_member fm ON fm.family_id = target.family_id",
    "JOIN public.person p ON p.id = fm.person_id",
    "ORDER BY target.person_id, fm.family_id, fm.rolle, fm.person_id"
  ), list(source_id))
  family_members <- family_members_all[family_members_all$target_person_id %in% declared_ids, , drop = FALSE]

  profiles <- lapply(seq_along(declared_keys), function(position) {
    key <- declared_keys[[position]]
    person_id <- declared_ids[[position]]
    anchor_index <- which(anchors$record_key == key & anchors$person_id == person_id)[[1L]]
    narrative_indexes <- identity_group_rows(narratives, "record_key", key)
    fact_indexes <- identity_group_rows(facts, "record_key", key)
    relation_indexes <- if (nrow(relations_all)) {
      which(relations_all$subjekt_id == person_id | relations_all$objekt_id == person_id)
    } else integer()
    family_indexes <- identity_group_rows(family_members, "target_person_id", person_id)
    family_ids <- if (length(family_indexes)) unique(as.integer(family_members$family_id[family_indexes])) else integer()

    list(
      record_key = key,
      person_id = person_id,
      display_name = as.character(anchors$visning_navn[[anchor_index]]),
      staged = as.logical(anchors$staged[[anchor_index]]),
      narratives = lapply(narrative_indexes, function(index) list(
        narrative_id = as.integer(narratives$id[[index]]),
        text = as.character(narratives$tekst[[index]]),
        page = identity_nullable_text(narratives$side[index]),
        private = as.logical(narratives$privat[[index]]),
        editorial_events = identity_editorial_events(narratives, index)
      )),
      facts = lapply(fact_indexes, function(index) list(
        fact_id = as.integer(facts$fact_id[[index]]),
        fact_type = as.character(facts$faktatype[[index]]),
        assertion_id = identity_nullable_integer(facts$assertion_id[index]),
        raw_value = identity_nullable_text(if (!is.na(facts$date_raw[[index]]) &&
          nzchar(as.character(facts$date_raw[[index]]))) facts$date_raw[index] else facts$vaerdi_tekst[index]),
        citation = if (is.na(facts$citation_id[[index]])) NULL else list(
          citation_id = as.integer(facts$citation_id[[index]]),
          text = identity_nullable_text(facts$citat_tekst[index]),
          page = identity_nullable_text(facts$citation_side[index])
        ),
        editorial_events = identity_editorial_events(facts, index)
      )),
      relations = lapply(relation_indexes, function(index) list(
        relation_id = as.integer(relations_all$relation_id[[index]]),
        role = as.character(relations_all$rolle[[index]]),
        subject_person_id = as.integer(relations_all$subjekt_id[[index]]),
        subject_display_name = identity_nullable_text(relations_all$subjekt_navn[index]),
        object_person_id = as.integer(relations_all$objekt_id[[index]]),
        object_display_name = identity_nullable_text(relations_all$objekt_navn[index]),
        assertion_id = identity_nullable_integer(relations_all$assertion_id[index]),
        raw_value = identity_nullable_text(if (!is.na(relations_all$date_raw[[index]]) &&
          nzchar(as.character(relations_all$date_raw[[index]]))) relations_all$date_raw[index] else
          relations_all$vaerdi_tekst[index]),
        citation = if (is.na(relations_all$citation_id[[index]])) NULL else list(
          citation_id = as.integer(relations_all$citation_id[[index]]),
          text = identity_nullable_text(relations_all$citat_tekst[index]),
          page = identity_nullable_text(relations_all$citation_side[index])
        ),
        editorial_events = identity_editorial_events(relations_all, index)
      )),
      families = lapply(sort(family_ids), function(family_id) {
        member_indexes <- family_indexes[family_members$family_id[family_indexes] == family_id]
        list(
          family_id = family_id,
          members = lapply(member_indexes, function(index) list(
            person_id = as.integer(family_members$member_person_id[[index]]),
            role = as.character(family_members$member_role[[index]]),
            display_name = as.character(family_members$member_name[[index]]),
            editorial_events = identity_editorial_events(family_members, index)
          ))
        )
      })
    )
  })

  list(
    schema_version = "1939-v50-identity-db-profiles-v1",
    generator_version = "profile_identity_review_1939_v50.R:v1",
    snapshot_at = identity_scalar_text(snapshot_at),
    input = list(
      database_preview_sha256 = database_preview_sha256,
      import_preview_input_hashes = database_preview$input_preview$input_hashes,
      declared_record_keys = as.list(declared_keys)
    ),
    database = list(
      database_name = as.character(metadata$database_name[[1L]]),
      server_version = as.character(metadata$server_version[[1L]]),
      server_version_num = as.character(metadata$server_version_num[[1L]]),
      transaction_read_only = as.character(readonly$transaction_read_only[[1L]])
    ),
    source = database_preview$source,
    review_only = TRUE,
    canonical_mutations_authorized = FALSE,
    counts = list(
      profiles = length(profiles),
      narratives = sum(vapply(profiles, function(row) length(row$narratives), integer(1L))),
      facts = sum(vapply(profiles, function(row) length(row$facts), integer(1L))),
      relations = sum(vapply(profiles, function(row) length(row$relations), integer(1L))),
      families = sum(vapply(profiles, function(row) length(row$families), integer(1L)))
    ),
    profiles = profiles
  )
}

write_identity_profile_output <- function(profiles, output_path) {
  output_path <- identity_scalar_text(output_path, "IDENTITY_PROFILE_OUTPUT_INVALID")
  if (file.exists(output_path)) stop("File exists: identity profile output overskrives ikke", call. = FALSE)
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  connection <- NULL
  success <- FALSE
  on.exit({
    if (!is.null(connection)) try(close(connection), silent = TRUE)
    if (!success && file.exists(output_path)) unlink(output_path, force = TRUE)
  }, add = TRUE)
  connection <- file(output_path, open = "wx", encoding = "UTF-8")
  writeLines(jsonlite::toJSON(profiles, auto_unbox = TRUE, pretty = TRUE,
    null = "null", na = "null"), connection, useBytes = TRUE)
  close(connection)
  connection <- NULL
  success <- TRUE
  invisible(output_path)
}

