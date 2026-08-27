# Fail-closed helpers for the DAA 1939 v50 database preview.
# This file deliberately has no connection side effects and is testable with
# injected query/execute functions.

`%||%` <- function(value, fallback) if (is.null(value)) fallback else value

preview_stop <- function(code, detail = NULL) {
  message <- if (is.null(detail) || !nzchar(as.character(detail))) code else {
    paste(code, as.character(detail), sep = ": ")
  }
  stop(message, call. = FALSE)
}

scalar_text <- function(value, code = "DB_PREVIEW_INPUT_INVALID") {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    preview_stop(code)
  }
  value
}

scalar_false <- function(value, code = "DB_PREVIEW_CANONICAL_MUTATION_FORBIDDEN") {
  if (!is.logical(value) || length(value) != 1L || is.na(value) || value) {
    preview_stop(code)
  }
  invisible(TRUE)
}

scalar_sha256 <- function(value, code = "DB_PREVIEW_SOURCE_PERSONA_INVALID") {
  value <- scalar_text(value, code)
  if (!grepl("^[0-9a-f]{64}$", value)) preview_stop(code)
  value
}

validate_source_persona_file_hash <- function(schema_version, actual_sha256,
                                                supplied_sha256) {
  schema_version <- scalar_text(schema_version, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  actual_sha256 <- scalar_sha256(actual_sha256)
  supplied_sha256 <- scalar_sha256(supplied_sha256)
  if (!schema_version %in% c(
      "1939-v50-source-persona-materialization-v1",
      "1939-v50-source-persona-materialization-v2") ||
      !identical(actual_sha256, supplied_sha256) ||
      identical(schema_version, "1939-v50-source-persona-materialization-v2") &&
        !identical(actual_sha256,
          "450e2dae158573131d19333be3cebefe36bf6a5d269c7ff0059e17c5fcafa97c")) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  invisible(TRUE)
}

scalar_positive_integer <- function(value, code = "DB_PREVIEW_SOURCE_PERSONA_INVALID") {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      value < 1 || value != floor(value)) preview_stop(code)
  as.integer(value)
}

scalar_uuid_v5 <- function(value, code = "DB_PREVIEW_SOURCE_PERSONA_INVALID") {
  value <- scalar_text(value, code)
  if (!grepl(
      "^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
      value)) preview_stop(code)
  value
}

as_character_list <- function(values) {
  if (!length(values)) return(list())
  lapply(as.character(values), identity)
}

database_preview_sql_registry <- function() {
  list(
    begin_read_only = "BEGIN READ ONLY",
    rollback = "ROLLBACK",
    statement_timeout = "SET LOCAL statement_timeout = '30s'",
    lock_timeout = "SET LOCAL lock_timeout = '2s'",
    transaction_read_only = "SHOW transaction_read_only",
    metadata = paste(
      "SELECT current_database() AS database_name,",
      "current_setting('server_version') AS server_version,",
      "current_setting('server_version_num') AS server_version_num"
    ),
    capability_columns = paste(
      "SELECT table_schema, table_name, column_name",
      "FROM information_schema.columns",
      "WHERE table_schema IN ('public','private')",
      "ORDER BY table_schema, table_name, ordinal_position"
    ),
    source = "SELECT id, udgave, import_key FROM public.source WHERE udgave = $1 ORDER BY id",
    anchors = paste(
      "SELECT pei.person_id, pei.record_key, pei.linje, pei.nr, p.staged, p.visning_navn",
      "FROM public.person_external_id pei",
      "JOIN public.person p ON p.id = pei.person_id",
      "WHERE pei.source_id = $1",
      "ORDER BY pei.record_key, pei.person_id"
    ),
    narratives = paste(
      "SELECT n.id, pei.person_id, pei.record_key, n.tekst, n.privat,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'narrative' AND ce.row_pk->>'id' = n.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events",
      "FROM public.narrative n",
      "JOIN public.person_external_id pei ON pei.person_id = n.subjekt_id AND pei.source_id = $1",
      "WHERE n.subjekt_type = 'person' AND n.source_id = $1",
      "ORDER BY pei.record_key, n.id"
    ),
    person_facts = paste(
      "SELECT f.id, pei.person_id, pei.record_key, f.faktatype,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'fact' AND ce.row_pk->>'id' = f.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events,",
      "(SELECT count(*) FROM public.assertion a JOIN public.citation c ON c.assertion_id = a.id",
      " WHERE a.target_type = 'fact' AND a.target_id = f.id AND c.source_id = $1) AS source_citations",
      "FROM public.fact f",
      "JOIN public.person_external_id pei ON pei.person_id = f.subjekt_id AND pei.source_id = $1",
      "WHERE f.subjekt_type = 'person'",
      "ORDER BY pei.record_key, f.id"
    ),
    families = paste(
      "SELECT fam.id, fam.type,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'family' AND ce.row_pk->>'id' = fam.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events",
      "FROM public.family fam",
      "WHERE EXISTS (SELECT 1 FROM public.family_member scope",
      " JOIN public.person_external_id pei ON pei.person_id = scope.person_id",
      " WHERE scope.family_id = fam.id AND pei.source_id = $1)",
      "ORDER BY fam.id"
    ),
    family_facts = paste(
      "SELECT f.id, f.subjekt_id AS family_id, f.faktatype,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'fact' AND ce.row_pk->>'id' = f.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events,",
      "(SELECT count(*) FROM public.assertion a JOIN public.citation c ON c.assertion_id = a.id",
      " WHERE a.target_type = 'fact' AND a.target_id = f.id AND c.source_id = $1) AS source_citations",
      "FROM public.fact f",
      "WHERE f.subjekt_type = 'family' AND EXISTS (",
      " SELECT 1 FROM public.family_member scope",
      " JOIN public.person_external_id pei ON pei.person_id = scope.person_id",
      " WHERE scope.family_id = f.subjekt_id AND pei.source_id = $1)",
      "ORDER BY f.subjekt_id, f.id"
    ),
    relations = paste(
      "SELECT r.id, r.rolle,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'relation' AND ce.row_pk->>'id' = r.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events,",
      "(SELECT count(*) FROM public.assertion a JOIN public.citation c ON c.assertion_id = a.id",
      " WHERE a.target_type = 'relation' AND a.target_id = r.id AND c.source_id = $1) AS source_citations",
      "FROM public.relation r",
      "WHERE (r.subjekt_type = 'person' AND EXISTS (SELECT 1 FROM public.person_external_id pei",
      "       WHERE pei.source_id = $1 AND pei.person_id = r.subjekt_id))",
      "   OR (r.objekt_type = 'person' AND EXISTS (SELECT 1 FROM public.person_external_id pei",
      "       WHERE pei.source_id = $1 AND pei.person_id = r.objekt_id))",
      "ORDER BY r.id"
    ),
    family_members_v3 = paste(
      "SELECT fm.family_id, fm.person_id, fm.rolle,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'family_member'",
      " AND ce.row_pk->>'family_id' = fm.family_id::text",
      " AND ce.row_pk->>'person_id' = fm.person_id::text",
      " AND ce.row_pk->>'rolle' = fm.rolle",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events",
      "FROM public.family_member fm",
      "WHERE EXISTS (SELECT 1 FROM public.family_member scope",
      " JOIN public.person_external_id pei ON pei.person_id = scope.person_id",
      " WHERE scope.family_id = fm.family_id AND pei.source_id = $1)",
      "ORDER BY fm.family_id, fm.person_id, fm.rolle"
    ),
    family_members_v2 = paste(
      "SELECT fm.family_id, fm.person_id, fm.rolle,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'family_member'",
      " AND ce.row_pk->>'family_id' = fm.family_id::text",
      " AND ce.row_pk->>'person_id' = fm.person_id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events",
      "FROM public.family_member fm",
      "WHERE EXISTS (SELECT 1 FROM public.person_external_id pei",
      "  WHERE pei.source_id = $1 AND pei.person_id = fm.person_id)",
      "ORDER BY fm.family_id, fm.person_id, fm.rolle"
    ),
    source_records = paste(
      "SELECT sr.record_key, sr.record_kind FROM private.source_record sr",
      "WHERE sr.source_id = $1 ORDER BY sr.record_key"
    ),
    source_personas = paste(
      "SELECT sp.id::text AS source_persona_id, sp.persona_key,",
      "spi.canonical_person_id, spi.decision_status",
      "FROM private.source_persona sp",
      "LEFT JOIN private.source_persona_identity spi ON spi.source_persona_id = sp.id",
      "WHERE sp.source_id = $1 ORDER BY sp.persona_key, sp.id"
    ),
    profile_capability_columns = paste(
      "SELECT table_schema, table_name, column_name",
      "FROM information_schema.columns",
      "WHERE table_schema = 'public'",
      "ORDER BY table_schema, table_name, ordinal_position"
    ),
    profile_anchors = paste(
      "SELECT pei.person_id, pei.record_key, p.visning_navn, p.staged",
      "FROM public.person_external_id pei",
      "JOIN public.person p ON p.id = pei.person_id",
      "WHERE pei.source_id = $1",
      "ORDER BY pei.record_key, pei.person_id"
    ),
    profile_narratives = paste(
      "SELECT n.id, pei.person_id, pei.record_key, n.tekst, n.side, n.privat,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'narrative' AND ce.row_pk->>'id' = n.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events",
      "FROM public.narrative n",
      "JOIN public.person_external_id pei ON pei.person_id = n.subjekt_id AND pei.source_id = $1",
      "WHERE n.subjekt_type = 'person' AND n.source_id = $1",
      "ORDER BY pei.record_key, n.id"
    ),
    profile_person_facts = paste(
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
    ),
    profile_relations = paste(
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
    ),
    profile_family_members = paste(
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
    ),
    profile_family_facts = paste(
      "SELECT target.person_id AS target_person_id, f.id AS fact_id,",
      "f.subjekt_id AS family_id, f.faktatype, a.id AS assertion_id,",
      "a.vaerdi_tekst, a.date_raw, c.id AS citation_id, c.citat_tekst,",
      "c.side AS citation_side,",
      "(SELECT count(*) FROM public.change_event ce",
      " JOIN public.change_set cs ON cs.id = ce.change_set_id",
      " WHERE ce.tabel = 'fact' AND ce.row_pk->>'id' = f.id::text",
      " AND left(cs.operation, 4) = 'red_') AS editorial_events",
      "FROM public.family_member target",
      "JOIN public.person_external_id pei ON pei.person_id = target.person_id AND pei.source_id = $1",
      "JOIN public.fact f ON f.subjekt_type = 'family' AND f.subjekt_id = target.family_id",
      "LEFT JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id",
      "LEFT JOIN public.citation c ON c.assertion_id = a.id AND c.source_id = $1",
      "ORDER BY target.person_id, f.subjekt_id, f.id, a.id, c.id"
    )
  )
}

normalize_database_preview_sql <- function(sql) {
  gsub("\\s+", " ", trimws(sql), perl = TRUE)
}

assert_read_only_sql <- function(sql) {
  sql <- scalar_text(sql, "DB_PREVIEW_SQL_FORBIDDEN")
  if (grepl(";|--|/\\*|\\*/", sql, perl = TRUE)) {
    preview_stop("DB_PREVIEW_SQL_FORBIDDEN")
  }
  registered <- vapply(database_preview_sql_registry(),
    normalize_database_preview_sql, character(1L))
  if (!normalize_database_preview_sql(sql) %in% registered) {
    preview_stop("DB_PREVIEW_SQL_FORBIDDEN")
  }
  invisible(TRUE)
}

required_database_columns <- function(include_family = FALSE) {
  required <- list(
    "public.source" = c("id", "udgave", "import_key"),
    "public.person_external_id" = c("person_id", "source_id", "record_key", "linje", "nr"),
    "public.person" = c("id", "staged", "visning_navn"),
    "public.narrative" = c("id", "subjekt_type", "subjekt_id", "source_id", "tekst", "privat"),
    "public.fact" = c("id", "subjekt_type", "subjekt_id", "faktatype"),
    "public.relation" = c("id", "subjekt_type", "subjekt_id", "objekt_type", "objekt_id", "rolle"),
    "public.family_member" = c("family_id", "person_id", "rolle"),
    "public.assertion" = c("id", "target_type", "target_id"),
    "public.citation" = c("assertion_id", "source_id", "citat_tekst"),
    "public.change_event" = c("change_set_id", "tabel", "row_pk"),
    "public.change_set" = c("id", "operation"),
    "private.source_record" = c("source_id", "record_key", "record_kind"),
    "private.source_persona" = c("id", "source_id", "persona_key"),
    "private.source_persona_identity" = c(
      "source_persona_id", "canonical_person_id", "decision_status")
  )
  if (isTRUE(include_family)) required[["public.family"]] <- c("id", "type")
  required
}

validate_preview_connection <- function(host, user, password, port, database) {
  values <- c(host = host, user = user, password = password, database = database)
  if (any(!nzchar(values)) || any(is.na(values))) {
    preview_stop("DB_PREVIEW_CREDENTIALS_MISSING")
  }
  if (length(port) != 1L || is.na(port) || as.integer(port) < 1L || as.integer(port) > 65535L) {
    preview_stop("DB_PREVIEW_CONNECTION_INVALID")
  }
  if (as.integer(port) == 6543L) {
    preview_stop("DB_PREVIEW_TRANSACTION_POOLER_FORBIDDEN")
  }
  invisible(TRUE)
}

validate_import_preview <- function(preview) {
  if (!is.list(preview) || !identical(preview$schema_version, "1939-v50-import-preview-v1") ||
      !identical(preview$preview_gate, "GO") || !identical(preview$reimport_gate, "NO-GO")) {
    preview_stop("DB_PREVIEW_INPUT_INVALID")
  }
  scalar_false(preview$canonical_mutations_authorized)
  if (!is.list(preview$source) || !identical(preview$source$edition, "1939") ||
      !is.list(preview$source$input_hashes) || length(preview$source$input_hashes) != 6L ||
      !is.list(preview$mapped_existing) || !is.list(preview$retired_legacy) ||
      !is.list(preview$source_records) || !is.list(preview$genuinely_new_pending) ||
      !is.list(preview$source_only_records) || !is.list(preview$counts)) {
    preview_stop("DB_PREVIEW_INPUT_INVALID")
  }
  mapped_keys <- vapply(preview$mapped_existing, function(row) {
    if (!is.list(row)) preview_stop("DB_PREVIEW_INPUT_INVALID")
    scalar_text(row$baseline_record_key)
  }, character(1L))
  mapped_new <- vapply(preview$mapped_existing, function(row) {
    scalar_text(row$new_record_key)
  }, character(1L))
  retired_keys <- vapply(preview$retired_legacy, function(row) {
    if (!is.list(row)) preview_stop("DB_PREVIEW_INPUT_INVALID")
    scalar_text(row$baseline_record_key)
  }, character(1L))
  source_keys <- vapply(preview$source_records, function(row) {
    if (!is.list(row)) preview_stop("DB_PREVIEW_INPUT_INVALID")
    scalar_text(row$new_record_key)
  }, character(1L))
  if (anyDuplicated(mapped_keys) || anyDuplicated(mapped_new) || anyDuplicated(retired_keys) ||
      anyDuplicated(source_keys) || length(intersect(mapped_keys, retired_keys)) ||
      !setequal(mapped_new, vapply(Filter(function(row) length(row$baseline_record_keys) == 1L,
        preview$source_records), function(row) scalar_text(row$new_record_key), character(1L)))) {
    preview_stop("DB_PREVIEW_INPUT_INVALID")
  }
  if (!identical(as.integer(preview$counts$mapped_existing), length(mapped_keys)) ||
      !identical(as.integer(preview$counts$retired_legacy), length(retired_keys)) ||
      !identical(as.integer(preview$counts$source_records), length(source_keys))) {
    preview_stop("DB_PREVIEW_INPUT_INVALID")
  }
  invisible(TRUE)
}

validate_source_persona_materialization_v1 <- function(materialization, preview,
                                                         input_preview_sha256,
                                                         materialization_sha256) {
  validate_import_preview(preview)
  input_preview_sha256 <- scalar_sha256(input_preview_sha256)
  materialization_sha256 <- scalar_sha256(materialization_sha256)
  if (!is.list(materialization) ||
      !identical(materialization$schema_version,
        "1939-v50-source-persona-materialization-v1") ||
      !identical(materialization$source_persona_materialization_gate, "GO") ||
      !identical(materialization$database_write_gate, "NO-GO") ||
      !identical(materialization$reimport_gate, "NO-GO")) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  scalar_false(materialization$canonical_mutations_authorized,
    "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  scalar_false(materialization$database_write_authorized,
    "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  if (!is.list(materialization$source) ||
      !identical(materialization$source$edition, "1939") ||
      !identical(materialization$source$logical_source_id, preview$source$source_id) ||
      !is.list(materialization$source$input_hashes) ||
      !identical(materialization$source$input_hashes$import_preview_sha256,
        input_preview_sha256) || !is.list(materialization$counts) ||
      !is.list(materialization$source_personas) ||
      !is.list(materialization$remaining_genuinely_new_pending) ||
      !is.list(materialization$expected_database_changes)) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  database_source_id <- scalar_positive_integer(
    materialization$source$database_source_id)
  personas <- materialization$source_personas
  remaining <- materialization$remaining_genuinely_new_pending
  counts <- materialization$counts
  if (!identical(as.integer(counts$approved_identity_decisions), length(personas)) ||
      !identical(as.integer(counts$source_personas), length(personas)) ||
      !identical(as.integer(counts$accepted_identities), length(personas)) ||
      !identical(as.integer(counts$remaining_genuinely_new_pending), length(remaining))) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  pending_by_key <- setNames(preview$genuinely_new_pending,
    vapply(preview$genuinely_new_pending, function(row) scalar_text(row$new_record_key),
      character(1L)))
  persona_keys <- character()
  source_keys <- character()
  target_keys <- character()
  canonical_ids <- integer()
  for (row in personas) {
    if (!is.list(row)) preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    source_key <- scalar_text(row$source_record_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    pending <- pending_by_key[[source_key]]
    if (is.null(pending) || scalar_positive_integer(row$source_id) != database_source_id ||
        !identical(row$source_span, pending$source_span) ||
        !identical(row$verbatim_text, pending$verbatim_text) ||
        !identical(row$identity_status, "accepted") ||
        !identical(row$database_write_authorized, FALSE)) {
      preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    persona_key <- scalar_text(row$persona_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    if (!identical(persona_key,
        paste0(materialization$source$logical_source_id, ":", source_key))) {
      preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    persona_keys <- c(persona_keys, persona_key)
    scalar_uuid_v5(row$source_persona_id)
    source_keys <- c(source_keys, source_key)
    target_keys <- c(target_keys,
      scalar_text(row$target_record_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID"))
    canonical_ids <- c(canonical_ids, scalar_positive_integer(row$canonical_person_id))
  }
  remaining_keys <- vapply(remaining,
    function(row) scalar_text(row$new_record_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID"),
    character(1L))
  pending_keys <- names(pending_by_key)
  if (anyDuplicated(persona_keys) || anyDuplicated(source_keys) ||
      anyDuplicated(target_keys) || anyDuplicated(canonical_ids) ||
      anyDuplicated(remaining_keys) || length(intersect(source_keys, remaining_keys)) ||
      !setequal(c(source_keys, remaining_keys), pending_keys)) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  changes <- materialization$expected_database_changes
  if (!identical(changes$authorized, FALSE) ||
      !identical(changes$canonical_person_creates, list()) ||
      !identical(changes$canonical_person_updates, list()) ||
      !identical(changes$canonical_person_deletes, list())) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  invisible(TRUE)
}

exact_names <- function(value, expected) {
  is.list(value) && length(value) == length(expected) &&
    identical(sort(names(value)), sort(expected))
}

scalar_nonnegative_integer <- function(value,
                                       code = "DB_PREVIEW_SOURCE_PERSONA_INVALID") {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      value < 0 || value != floor(value)) preview_stop(code)
  as.integer(value)
}

validate_source_span <- function(value,
                                 code = "DB_PREVIEW_SOURCE_PERSONA_INVALID") {
  if (!exact_names(value, c("char_from", "char_to"))) preview_stop(code)
  char_from <- scalar_nonnegative_integer(value$char_from, code)
  char_to <- scalar_nonnegative_integer(value$char_to, code)
  if (char_to <= char_from) preview_stop(code)
  list(char_from = char_from, char_to = char_to)
}

sha256_text <- function(value) {
  value <- scalar_text(value, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  digest::digest(charToRaw(enc2utf8(value)), algo = "sha256", serialize = FALSE)
}

source_persona_prefix_sha256 <- function(rows) {
  payload <- jsonlite::toJSON(rows, auto_unbox = TRUE, pretty = TRUE,
    null = "null", na = "null")
  digest::digest(charToRaw(enc2utf8(payload)), algo = "sha256", serialize = FALSE)
}

validate_source_persona_materialization_v2 <- function(materialization, preview,
                                                         input_preview_sha256,
                                                         materialization_sha256) {
  validate_import_preview(preview)
  input_preview_sha256 <- scalar_sha256(input_preview_sha256)
  materialization_sha256 <- scalar_sha256(materialization_sha256)
  top_level_names <- c(
    "schema_version", "generator_version", "source", "review_only",
    "canonical_mutations_authorized", "database_write_authorized", "counts",
    "source_personas", "new_person_candidates", "structural_or_summary",
    "unresolved", "expected_database_changes",
    "source_persona_materialization_gate", "database_gate", "reimport_gate"
  )
  if (!exact_names(materialization, top_level_names) ||
      !identical(materialization$schema_version,
        "1939-v50-source-persona-materialization-v2") ||
      !identical(materialization$generator_version,
        "materialize_remaining_source_personas_1939_v50.py:v1") ||
      !identical(materialization$review_only, TRUE) ||
      !identical(materialization$source_persona_materialization_gate, "GO") ||
      !identical(materialization$database_gate, "NO-GO") ||
      !identical(materialization$reimport_gate, "NO-GO")) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  scalar_false(materialization$canonical_mutations_authorized,
    "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  scalar_false(materialization$database_write_authorized,
    "DB_PREVIEW_SOURCE_PERSONA_INVALID")

  source <- materialization$source
  if (!exact_names(source,
      c("edition", "logical_source_id", "database_source_id", "input_hashes")) ||
      !identical(source$edition, "1939") ||
      !identical(source$logical_source_id, preview$source$source_id)) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  database_source_id <- scalar_positive_integer(source$database_source_id)
  hashes <- source$input_hashes
  if (!exact_names(hashes, c("source_persona_v1_sha256",
      "remaining_identity_decisions_sha256", "database_preview_sha256"))) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  v1_sha256 <- scalar_sha256(hashes$source_persona_v1_sha256)
  decisions_sha256 <- scalar_sha256(hashes$remaining_identity_decisions_sha256)
  database_preview_sha256 <- scalar_sha256(hashes$database_preview_sha256)
  production_v1_sha256 <-
    "07756ef4faf17561cf84095c5abe47919064d72ceecd3e1d9f725281ab0b172d"
  if (identical(v1_sha256, production_v1_sha256) &&
      (!identical(decisions_sha256,
          "a86b508205ca413f1c7f4af2f747b320f9f77bde7fb686dc10cf343b16565ebe") ||
       !identical(database_preview_sha256,
          "a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c") ||
       !identical(input_preview_sha256,
          "04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5") ||
       !identical(materialization_sha256,
          "450e2dae158573131d19333be3cebefe36bf6a5d269c7ff0059e17c5fcafa97c"))) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }

  counts <- materialization$counts
  expected_counts <- list(
    v1_source_personas = 24L, appended_source_personas = 8L,
    source_personas = 32L, same_existing_person = 8L,
    new_person_candidate = 8L, structural_or_summary = 1L, unresolved = 0L
  )
  if (!exact_names(counts, names(expected_counts))) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  observed_counts <- lapply(names(expected_counts), function(name) {
    scalar_nonnegative_integer(counts[[name]])
  })
  names(observed_counts) <- names(expected_counts)
  if (!identical(observed_counts, expected_counts) ||
      !is.list(materialization$source_personas) ||
      length(materialization$source_personas) != 32L ||
      !is.list(materialization$new_person_candidates) ||
      length(materialization$new_person_candidates) != 8L ||
      !is.list(materialization$structural_or_summary) ||
      length(materialization$structural_or_summary) != 1L ||
      !is.list(materialization$unresolved) ||
      length(materialization$unresolved) != 0L) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }

  pending_by_key <- list()
  for (row in preview$genuinely_new_pending) {
    if (!is.list(row)) preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    key <- scalar_text(row$new_record_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    if (!is.null(pending_by_key[[key]])) preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    pending_by_key[[key]] <- row
  }
  if (length(pending_by_key) != 41L) preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")

  persona_row_names <- c(
    "source_persona_id", "persona_key", "source_id", "source_record_key",
    "source_span", "verbatim_text", "target_record_key", "canonical_person_id",
    "identity_status", "identity_decision", "database_write_authorized"
  )
  v1_identity_names <- c(
    "decision_batch", "decision_batch_sha256", "candidate_evidence_sha256",
    "confirmation", "reviewed_by"
  )
  appended_identity_names <- c(
    "decision", "decision_artifact_sha256", "review_sha256",
    "proposal_evidence_sha256", "reviewed_by", "decision_basis", "reason",
    "review_status"
  )
  competition_names <- c(
    "competing_target_record_key", "competing_canonical_person_id",
    "resolution_basis"
  )
  persona_ids <- character()
  persona_keys <- character()
  source_keys <- character()
  target_keys <- character()
  canonical_ids <- integer()
  competition_count <- 0L
  for (index in seq_along(materialization$source_personas)) {
    row <- materialization$source_personas[[index]]
    if (!exact_names(row, persona_row_names)) {
      preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    source_key <- scalar_text(row$source_record_key,
      "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    pending <- pending_by_key[[source_key]]
    span <- validate_source_span(row$source_span)
    verbatim <- scalar_text(row$verbatim_text, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    if (is.null(pending) || !identical(span, pending$source_span) ||
        !identical(verbatim, pending$verbatim_text) ||
        span$char_to - span$char_from != nchar(verbatim, type = "chars") ||
        scalar_positive_integer(row$source_id) != database_source_id ||
        !identical(row$persona_key, paste0(source$logical_source_id, ":", source_key)) ||
        !identical(row$identity_status, "accepted") ||
        !identical(row$database_write_authorized, FALSE)) {
      preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    persona_ids <- c(persona_ids, scalar_uuid_v5(row$source_persona_id))
    persona_keys <- c(persona_keys, row$persona_key)
    source_keys <- c(source_keys, source_key)
    target_keys <- c(target_keys,
      scalar_text(row$target_record_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID"))
    canonical_ids <- c(canonical_ids,
      scalar_positive_integer(row$canonical_person_id))
    identity <- row$identity_decision
    if (index <= 24L) {
      if (!exact_names(identity, v1_identity_names)) {
        preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
      }
      scalar_text(identity$decision_batch, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
      scalar_sha256(identity$decision_batch_sha256)
      scalar_sha256(identity$candidate_evidence_sha256)
      scalar_text(identity$confirmation, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
      scalar_text(identity$reviewed_by, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    } else {
      present_competition <- intersect(names(identity), competition_names)
      expected_identity_names <- appended_identity_names
      if (length(present_competition)) {
        if (!setequal(present_competition, competition_names)) {
          preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
        }
        expected_identity_names <- c(expected_identity_names, competition_names)
        competition_count <- competition_count + 1L
        competing_target <- scalar_text(identity$competing_target_record_key,
          "DB_PREVIEW_SOURCE_PERSONA_INVALID")
        competing_person <- scalar_positive_integer(identity$competing_canonical_person_id)
        if (identical(competing_target, row$target_record_key) ||
            identical(competing_person, as.integer(row$canonical_person_id)) ||
            !identical(identity$resolution_basis,
              "explicit_user_instruction_prefer_later_full_person_over_summary_duplicate")) {
          preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
        }
      }
      if (!exact_names(identity, expected_identity_names) ||
          !identical(identity$decision, "same_existing_person") ||
          !identical(identity$decision_artifact_sha256, decisions_sha256)) {
        preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
      }
      scalar_sha256(identity$review_sha256)
      scalar_sha256(identity$proposal_evidence_sha256)
      for (field in c("reviewed_by", "decision_basis", "reason", "review_status")) {
        scalar_text(identity[[field]], "DB_PREVIEW_SOURCE_PERSONA_INVALID")
      }
    }
  }
  if (anyDuplicated(persona_ids) || anyDuplicated(persona_keys) ||
      anyDuplicated(source_keys) || anyDuplicated(target_keys) ||
      anyDuplicated(canonical_ids) || competition_count != 2L) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  if (identical(v1_sha256, production_v1_sha256) &&
      !identical(source_persona_prefix_sha256(materialization$source_personas[seq_len(24L)]),
        "7f4b6b625b6e3589c14b8bdd35887e4e4f28b2156966199b48d40e23188ae827")) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }

  decision_common_names <- c(
    "source_record_key", "source_span", "verbatim_sha256", "decision", "reason",
    "review_status", "review_sha256", "proposal_evidence_sha256"
  )
  disposition_keys <- character()
  validate_disposition <- function(row, decision, structural = FALSE) {
    expected_names <- decision_common_names
    if (structural) expected_names <- c(expected_names, "context_owner_record_key")
    if (!exact_names(row, expected_names) || !identical(row$decision, decision)) {
      preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    key <- scalar_text(row$source_record_key, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    pending <- pending_by_key[[key]]
    if (is.null(pending) || !identical(validate_source_span(row$source_span),
        pending$source_span) || !identical(scalar_sha256(row$verbatim_sha256),
        sha256_text(pending$verbatim_text))) {
      preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    scalar_text(row$reason, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    scalar_text(row$review_status, "DB_PREVIEW_SOURCE_PERSONA_INVALID")
    scalar_sha256(row$review_sha256)
    scalar_sha256(row$proposal_evidence_sha256)
    if (structural) {
      owner <- scalar_text(row$context_owner_record_key,
        "DB_PREVIEW_SOURCE_PERSONA_INVALID")
      preview_source_keys <- vapply(preview$source_records,
        function(value) scalar_text(value$new_record_key,
          "DB_PREVIEW_SOURCE_PERSONA_INVALID"), character(1L))
      if (!owner %in% preview_source_keys) preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
    }
    key
  }
  for (row in materialization$new_person_candidates) {
    disposition_keys <- c(disposition_keys,
      validate_disposition(row, "new_person_candidate"))
  }
  for (row in materialization$structural_or_summary) {
    disposition_keys <- c(disposition_keys,
      validate_disposition(row, "structural_or_summary", structural = TRUE))
  }
  for (row in materialization$unresolved) {
    disposition_keys <- c(disposition_keys, validate_disposition(row, "unresolved"))
  }
  if (anyDuplicated(disposition_keys) || length(intersect(source_keys, disposition_keys)) ||
      !setequal(c(source_keys, disposition_keys), names(pending_by_key))) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }

  changes <- materialization$expected_database_changes
  if (!exact_names(changes, c(
      "source_persona_candidates", "source_persona_identity_candidates",
      "canonical_person_creates", "canonical_person_updates",
      "canonical_person_deletes", "authorized")) ||
      !identical(changes$source_persona_candidates, as_character_list(persona_ids)) ||
      !identical(changes$source_persona_identity_candidates, as_character_list(persona_ids)) ||
      !identical(changes$canonical_person_creates, list()) ||
      !identical(changes$canonical_person_updates, list()) ||
      !identical(changes$canonical_person_deletes, list()) ||
      !identical(changes$authorized, FALSE)) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
  invisible(TRUE)
}

validate_source_persona_materialization <- function(materialization, preview,
                                                      input_preview_sha256,
                                                      materialization_sha256) {
  if (is.list(materialization) && identical(materialization$schema_version,
      "1939-v50-source-persona-materialization-v1")) {
    return(validate_source_persona_materialization_v1(materialization, preview,
      input_preview_sha256, materialization_sha256))
  }
  if (is.list(materialization) && identical(materialization$schema_version,
      "1939-v50-source-persona-materialization-v2")) {
    return(validate_source_persona_materialization_v2(materialization, preview,
      input_preview_sha256, materialization_sha256))
  }
  preview_stop("DB_PREVIEW_SOURCE_PERSONA_INVALID")
}

safe_sum <- function(values) {
  if (!length(values)) return(0L)
  as.integer(sum(as.integer(values), na.rm = TRUE))
}

event_count <- function(frame) {
  if (!nrow(frame) || !"editorial_events" %in% names(frame)) return(0L)
  as.integer(sum(as.integer(frame$editorial_events) > 0L, na.rm = TRUE))
}

provenance_matrix <- function(frame) {
  if (!nrow(frame)) {
    return(list(source_only = 0L, editorial_only = 0L, both = 0L, neither = 0L))
  }
  source_bound <- as.integer(frame$source_citations) > 0L
  editorial <- as.integer(frame$editorial_events) > 0L
  list(
    source_only = as.integer(sum(source_bound & !editorial, na.rm = TRUE)),
    editorial_only = as.integer(sum(!source_bound & editorial, na.rm = TRUE)),
    both = as.integer(sum(source_bound & editorial, na.rm = TRUE)),
    neither = as.integer(sum(!source_bound & !editorial, na.rm = TRUE))
  )
}

named_counts <- function(values) {
  if (!length(values)) return(list())
  counts <- table(as.character(values), useNA = "no")
  as.list(setNames(as.integer(counts), names(counts)))
}

build_database_preview <- function(preview, source_persona_materialization,
                                   source_persona_materialization_sha256,
                                   input_preview_sha256,
                                   query_fn, execute_fn, expected_database,
                                   expected_source_edition = "DAA 1939",
                                   snapshot_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) {
  validate_import_preview(preview)
  validate_source_persona_materialization(source_persona_materialization, preview,
    input_preview_sha256, source_persona_materialization_sha256)
  is_v3 <- identical(source_persona_materialization$schema_version,
    "1939-v50-source-persona-materialization-v2")
  expected_database <- scalar_text(expected_database, "DB_PREVIEW_DATABASE_MISMATCH")
  expected_source_edition <- scalar_text(expected_source_edition, "DB_PREVIEW_SOURCE_MISMATCH")
  if (!is.function(query_fn) || !is.function(execute_fn)) preview_stop("DB_PREVIEW_INPUT_INVALID")
  sql <- database_preview_sql_registry()

  execute <- function(sql, params = list()) {
    assert_read_only_sql(sql)
    execute_fn(sql, params)
  }
  query <- function(sql, params = list()) {
    assert_read_only_sql(sql)
    value <- query_fn(sql, params)
    if (!is.data.frame(value)) preview_stop("DB_PREVIEW_QUERY_INVALID")
    value
  }

  execute(sql$begin_read_only)
  on.exit(try(execute(sql$rollback), silent = TRUE), add = TRUE)
  execute(sql$statement_timeout)
  execute(sql$lock_timeout)

  readonly <- query(sql$transaction_read_only)
  if (nrow(readonly) != 1L || !identical(as.character(readonly$transaction_read_only[[1L]]), "on")) {
    preview_stop("DB_PREVIEW_NOT_READ_ONLY")
  }
  metadata <- query(sql$metadata)
  if (nrow(metadata) != 1L || !identical(as.character(metadata$database_name[[1L]]), expected_database)) {
    preview_stop("DB_PREVIEW_DATABASE_MISMATCH")
  }

  columns <- query(sql$capability_columns)
  required <- required_database_columns(include_family = is_v3)
  actual <- if (nrow(columns)) {
    paste(columns$table_schema, columns$table_name, columns$column_name, sep = ".")
  } else character()
  missing <- unlist(lapply(names(required), function(table) {
    expected <- paste(table, required[[table]], sep = ".")
    setdiff(expected, actual)
  }), use.names = FALSE)
  missing <- sort(missing)
  missing_public <- missing[startsWith(missing, "public.")]
  if (length(missing_public)) {
    preview_stop("DB_PREVIEW_CAPABILITY_BLOCKER", paste(missing_public, collapse = ","))
  }
  private_source_record_available <- !any(startsWith(missing, "private.source_record."))
  private_source_persona_available <-
    !any(startsWith(missing, "private.source_persona.")) &&
    !any(startsWith(missing, "private.source_persona_identity."))
  if (is_v3 && (private_source_record_available || private_source_persona_available)) {
    preview_stop("DB_PREVIEW_PRIVATE_TABLE_DRIFT")
  }

  source <- query(sql$source, list(expected_source_edition))
  if (nrow(source) != 1L || !identical(as.character(source$udgave[[1L]]), expected_source_edition)) {
    preview_stop("DB_PREVIEW_SOURCE_MISMATCH")
  }
  source_id <- as.integer(source$id[[1L]])
  if (!identical(source_id,
      as.integer(source_persona_materialization$source$database_source_id))) {
    preview_stop("DB_PREVIEW_SOURCE_MISMATCH")
  }

  anchors <- query(sql$anchors, list(source_id))
  if (nrow(anchors) && (any(is.na(anchors$record_key)) || any(!nzchar(anchors$record_key)))) {
    preview_stop("DB_PREVIEW_PERSON_ANCHOR_INVALID")
  }

  narratives <- query(sql$narratives, list(source_id))
  facts <- query(sql$person_facts, list(source_id))
  families <- if (is_v3) {
    query(sql$families, list(source_id))
  } else data.frame(id = integer(), type = character(), editorial_events = integer())
  family_facts <- if (is_v3) {
    query(sql$family_facts, list(source_id))
  } else data.frame(id = integer(), family_id = integer(), faktatype = character(),
    editorial_events = integer(), source_citations = integer())
  relations <- query(sql$relations, list(source_id))
  family_members <- if (is_v3) {
    query(sql$family_members_v3, list(source_id))
  } else {
    query(sql$family_members_v2, list(source_id))
  }
  source_records <- if (private_source_record_available) {
    query(sql$source_records, list(source_id))
  } else data.frame(record_key = character(), record_kind = character())
  database_source_personas <- if (private_source_persona_available) {
    query(sql$source_personas, list(source_id))
  } else data.frame(source_persona_id = character(), persona_key = character(),
    canonical_person_id = integer(), decision_status = character())

  active_keys <- sort(vapply(preview$mapped_existing, function(row) row$baseline_record_key, character(1L)))
  retired_keys <- sort(vapply(preview$retired_legacy, function(row) row$baseline_record_key, character(1L)))
  db_keys <- if (nrow(anchors)) as.character(anchors$record_key) else character()
  db_groups <- split(seq_len(nrow(anchors)), db_keys)
  matched <- list()
  missing_keys <- character()
  collisions <- list()
  for (key in active_keys) {
    indexes <- db_groups[[key]] %||% integer()
    if (!length(indexes)) {
      missing_keys <- c(missing_keys, key)
    } else if (length(indexes) == 1L) {
      matched[[length(matched) + 1L]] <- list(
        baseline_record_key = key,
        person_id = as.integer(anchors$person_id[[indexes[[1L]]]])
      )
    } else {
      collisions[[length(collisions) + 1L]] <- list(
        baseline_record_key = key,
        person_ids = as_character_list(sort(as.integer(anchors$person_id[indexes])))
      )
    }
  }
  database_only <- sort(setdiff(unique(db_keys), c(active_keys, retired_keys)))
  retired_present <- sort(intersect(retired_keys, unique(db_keys)))
  anchor_details <- function(keys) {
    lapply(keys, function(key) {
      index <- which(db_keys == key)[[1L]]
      list(
        record_key = key,
        person_id = as.integer(anchors$person_id[[index]]),
        visning_navn = as.character(anchors$visning_navn[[index]]),
        staged = as.logical(anchors$staged[[index]]),
        source_narrative_count = as.integer(sum(narratives$person_id == anchors$person_id[[index]],
          na.rm = TRUE)),
        fact_count = as.integer(sum(facts$person_id == anchors$person_id[[index]], na.rm = TRUE)),
        family_member_count = as.integer(sum(family_members$person_id == anchors$person_id[[index]],
          na.rm = TRUE))
      )
    })
  }
  database_only_details <- anchor_details(database_only)
  retired_present_details <- anchor_details(retired_present)

  preview_source_keys <- sort(vapply(preview$source_records, function(row) row$new_record_key, character(1L)))
  database_source_keys <- if (private_source_record_available && nrow(source_records)) {
    sort(unique(as.character(source_records$record_key)))
  } else character()
  source_inserts <- if (private_source_record_available) {
    sort(setdiff(preview_source_keys, database_source_keys))
  } else NULL
  source_existing <- if (private_source_record_available) {
    sort(intersect(preview_source_keys, database_source_keys))
  } else NULL
  source_database_only <- if (private_source_record_available) {
    sort(setdiff(database_source_keys, preview_source_keys))
  } else NULL

  planned_personas <- source_persona_materialization$source_personas
  planned_persona_keys <- vapply(planned_personas,
    function(row) scalar_text(row$persona_key), character(1L))
  database_persona_keys <- if (private_source_persona_available &&
      nrow(database_source_personas)) {
    as.character(database_source_personas$persona_key)
  } else character()
  database_persona_groups <- split(seq_len(nrow(database_source_personas)),
    database_persona_keys)
  persona_existing <- list()
  persona_inserts <- list()
  persona_collisions <- list()
  target_mismatches <- list()
  for (row in planned_personas) {
    anchor_indexes <- db_groups[[row$target_record_key]] %||% integer()
    if (length(anchor_indexes) != 1L ||
        as.integer(anchors$person_id[[anchor_indexes[[1L]]]]) !=
          as.integer(row$canonical_person_id)) {
      target_mismatches[[length(target_mismatches) + 1L]] <- list(
        source_record_key = row$source_record_key,
        target_record_key = row$target_record_key,
        canonical_person_id = as.integer(row$canonical_person_id)
      )
    }
    if (!private_source_persona_available) next
    indexes <- database_persona_groups[[row$persona_key]] %||% integer()
    candidate <- list(
      source_persona_id = row$source_persona_id,
      persona_key = row$persona_key,
      source_record_key = row$source_record_key,
      canonical_person_id = as.integer(row$canonical_person_id),
      authorized = FALSE
    )
    if (!length(indexes)) {
      persona_inserts[[length(persona_inserts) + 1L]] <- candidate
    } else if (length(indexes) != 1L) {
      persona_collisions[[length(persona_collisions) + 1L]] <- c(candidate,
        list(reason = "duplicate_persona_key"))
    } else {
      index <- indexes[[1L]]
      same <- identical(as.character(database_source_personas$source_persona_id[[index]]),
          row$source_persona_id) &&
        identical(as.integer(database_source_personas$canonical_person_id[[index]]),
          as.integer(row$canonical_person_id)) &&
        identical(as.character(database_source_personas$decision_status[[index]]),
          "accepted")
      if (same) {
        persona_existing[[length(persona_existing) + 1L]] <- candidate
      } else {
        persona_collisions[[length(persona_collisions) + 1L]] <- c(candidate,
          list(reason = "existing_persona_or_identity_mismatch"))
      }
    }
  }
  if (is_v3 && length(target_mismatches)) {
    preview_stop("DB_PREVIEW_SOURCE_PERSONA_TARGET_MISMATCH")
  }
  persona_database_only <- if (private_source_persona_available) {
    sort(setdiff(unique(database_persona_keys), planned_persona_keys))
  } else NULL

  source_verbatim <- setNames(
    vapply(preview$source_records, function(row) scalar_text(row$verbatim_text), character(1L)),
    vapply(preview$source_records, function(row) row$new_record_key, character(1L))
  )
  narrative_inserts <- list()
  narrative_updates <- list()
  narrative_unchanged <- list()
  narrative_collisions <- list()
  narrative_groups <- if (nrow(narratives)) split(seq_len(nrow(narratives)), narratives$record_key) else list()
  for (row in preview$mapped_existing) {
    key <- row$baseline_record_key
    indexes <- narrative_groups[[key]] %||% integer()
    if (!length(indexes)) {
      narrative_inserts[[length(narrative_inserts) + 1L]] <- list(
        baseline_record_key = key, authorized = FALSE
      )
    } else if (length(indexes) > 1L) {
      narrative_collisions[[length(narrative_collisions) + 1L]] <- list(
        baseline_record_key = key,
        narrative_ids = as_character_list(sort(as.integer(narratives$id[indexes])))
      )
    } else {
      index <- indexes[[1L]]
      target_text <- source_verbatim[[row$new_record_key]]
      current_text <- as.character(narratives$tekst[[index]])
      value <- list(baseline_record_key = key,
        narrative_id = as.integer(narratives$id[[index]]),
        editorial_events = as.integer(narratives$editorial_events[[index]]),
        authorized = FALSE)
      if (identical(current_text, target_text)) {
        narrative_unchanged[[length(narrative_unchanged) + 1L]] <- value
      } else {
        narrative_updates[[length(narrative_updates) + 1L]] <- value
      }
    }
  }

  fact_counts <- preview$counts$facts
  marriage_counts <- preview$counts$marriages
  relationship_counts <- preview$counts$relationships
  new_person_candidate_count <- if (is_v3) {
    length(source_persona_materialization$new_person_candidates)
  } else 0L
  structural_or_summary_count <- if (is_v3) {
    length(source_persona_materialization$structural_or_summary)
  } else 0L
  unresolved_count <- if (is_v3) {
    length(source_persona_materialization$unresolved)
  } else length(source_persona_materialization$remaining_genuinely_new_pending)
  competition_resolutions <- if (is_v3) {
    Filter(Negate(is.null), lapply(planned_personas, function(row) {
      identity <- row$identity_decision
      if (is.null(identity$competing_target_record_key)) return(NULL)
      list(
        source_record_key = row$source_record_key,
        selected_target_record_key = row$target_record_key,
        selected_canonical_person_id = as.integer(row$canonical_person_id),
        competing_target_record_key = identity$competing_target_record_key,
        competing_canonical_person_id = as.integer(identity$competing_canonical_person_id),
        resolution_basis = identity$resolution_basis,
        authorized = FALSE
      )
    }))
  } else list()
  blockers <- c(
    if (!private_source_record_available) "database_capability_blocker:private.source_record" else character(),
    if (!private_source_persona_available) "database_capability_blocker:private.source_persona" else character(),
    if (length(missing_keys)) paste0("missing_person_anchor:", missing_keys) else character(),
    vapply(collisions, function(row) paste0("person_anchor_collision:", row$baseline_record_key), character(1L)),
    vapply(target_mismatches, function(row) paste0(
      "source_persona_target_mismatch:", row$source_record_key), character(1L)),
    vapply(persona_collisions, function(row) paste0(
      "source_persona_collision:", row$source_record_key), character(1L)),
    vapply(narrative_collisions, function(row) paste0("narrative_collision:", row$baseline_record_key), character(1L)),
    if (length(database_only)) paste0("unmapped_existing_1939_person_records:", length(database_only)) else character(),
    if (is_v3 && unresolved_count > 0L)
      paste0("genuinely_new_identity_pending:", unresolved_count) else character(),
    if (is_v3 && new_person_candidate_count > 0L)
      paste0("genuinely_new_person_creation_pending:",
        new_person_candidate_count) else character(),
    if (!is_v3 && length(source_persona_materialization$remaining_genuinely_new_pending))
      paste0("genuinely_new_identity_pending:",
        length(source_persona_materialization$remaining_genuinely_new_pending)) else character(),
    if (safe_sum(fact_counts$missing_provenance) + safe_sum(fact_counts$nonliteral_provenance))
      paste0("fact_provenance_pending:", safe_sum(fact_counts$missing_provenance) + safe_sum(fact_counts$nonliteral_provenance)) else character(),
    if (safe_sum(marriage_counts$missing_provenance) + safe_sum(marriage_counts$nonliteral_provenance))
      paste0("marriage_provenance_pending:", safe_sum(marriage_counts$missing_provenance) + safe_sum(marriage_counts$nonliteral_provenance)) else character(),
    if (safe_sum(relationship_counts$legacy_structure_pending_revalidation))
      paste0("relationship_provenance_pending:", safe_sum(relationship_counts$legacy_structure_pending_revalidation)) else character(),
    "production_writer_not_authorized"
  )

  result <- list(
    schema_version = if (is_v3) "1939-v50-database-preview-v3" else
      "1939-v50-database-preview-v2",
    snapshot_at = scalar_text(snapshot_at, "DB_PREVIEW_INPUT_INVALID"),
    input_preview = list(
      schema_version = preview$schema_version,
      sha256 = input_preview_sha256,
      input_hashes = preview$source$input_hashes
    ),
    source_persona_materialization = list(
      schema_version = source_persona_materialization$schema_version,
      sha256 = source_persona_materialization_sha256
    ),
    database = list(
      database_name = as.character(metadata$database_name[[1L]]),
      server_version = as.character(metadata$server_version[[1L]]),
      server_version_num = as.character(metadata$server_version_num[[1L]]),
      transaction_read_only = as.character(readonly$transaction_read_only[[1L]])
    ),
    source = list(id = source_id, udgave = as.character(source$udgave[[1L]]),
      import_key = as.character(source$import_key[[1L]])),
    capabilities = list(required_columns = safe_sum(lengths(required)),
      missing = as_character_list(missing)),
    canonical_mutations_authorized = FALSE,
    person_anchors = list(
      matched_count = length(matched), missing_count = length(missing_keys),
      collision_count = length(collisions), retired_present_count = length(retired_present),
      matched = matched, missing_record_keys = as_character_list(missing_keys),
      collisions = collisions, retired_present_record_keys = as_character_list(retired_present),
      retired_present = retired_present_details,
      database_only_record_keys = as_character_list(database_only),
      database_only = database_only_details
    ),
    source_records = list(
      comparison_available = private_source_record_available,
      existing_count = if (private_source_record_available) length(source_existing) else NULL,
      insert_count = if (private_source_record_available) length(source_inserts) else NULL,
      existing_record_keys = if (private_source_record_available) as_character_list(source_existing) else NULL,
      insert_record_keys = if (private_source_record_available) as_character_list(source_inserts) else NULL,
      database_only_record_keys = if (private_source_record_available) as_character_list(source_database_only) else NULL
    ),
    source_personas = c(list(
      comparison_available = private_source_persona_available,
      planned_count = length(planned_personas),
      remaining_pending_count = unresolved_count,
      existing_count = if (private_source_persona_available) length(persona_existing) else NULL,
      insert_count = if (private_source_persona_available) length(persona_inserts) else NULL,
      collision_count = if (private_source_persona_available) length(persona_collisions) else NULL,
      existing = if (private_source_persona_available) persona_existing else NULL,
      insert_candidates = if (private_source_persona_available) persona_inserts else NULL,
      collisions = if (private_source_persona_available) persona_collisions else NULL,
      target_mismatches = target_mismatches,
      database_only_persona_keys = if (private_source_persona_available)
        as_character_list(persona_database_only) else NULL
    ), if (is_v3) list(
      target_matched_count = length(planned_personas) - length(target_mismatches),
      target_mismatch_count = length(target_mismatches),
      new_person_candidate_count = new_person_candidate_count,
      structural_or_summary_count = structural_or_summary_count,
      unresolved_count = unresolved_count,
      competition_resolutions = competition_resolutions
    ) else list()),
    narratives = list(
      insert_count = length(narrative_inserts), update_count = length(narrative_updates),
      unchanged_count = length(narrative_unchanged), collision_count = length(narrative_collisions),
      insert_candidates = narrative_inserts, update_candidates = narrative_updates,
      unchanged = narrative_unchanged, collisions = narrative_collisions,
      database_editorial_count = event_count(narratives)
    ),
    facts = list(
      preview_literal_count = safe_sum(fact_counts$source_bound_literal),
      preview_parked_count = safe_sum(fact_counts$missing_provenance) +
        safe_sum(fact_counts$nonliteral_provenance) + safe_sum(fact_counts$retired_source_record),
      database_existing_count = nrow(facts),
      database_editorial_count = event_count(facts),
      database_source_cited_count = if (nrow(facts))
        as.integer(sum(as.integer(facts$source_citations) > 0L, na.rm = TRUE)) else 0L,
      database_provenance_matrix = provenance_matrix(facts)
    ),
    relations = list(
      preview_marriage_literal_count = safe_sum(marriage_counts$source_bound_literal),
      preview_marriage_parked_count = safe_sum(marriage_counts$missing_provenance) +
        safe_sum(marriage_counts$nonliteral_provenance) + safe_sum(marriage_counts$retired_source_record),
      preview_relationship_pending_count = safe_sum(relationship_counts$legacy_structure_pending_revalidation),
      database_relation_count = nrow(relations),
      database_family_member_count = nrow(family_members),
      database_relation_editorial_count = event_count(relations),
      database_family_member_editorial_count = event_count(family_members),
      database_source_cited_relation_count = if (nrow(relations))
        as.integer(sum(as.integer(relations$source_citations) > 0L, na.rm = TRUE)) else 0L,
      database_provenance_matrix = provenance_matrix(relations),
      database_role_counts = named_counts(relations$rolle)
    ),
    expected_database_changes = list(
      source_record_inserts = if (private_source_record_available) as_character_list(source_inserts) else NULL,
      source_record_existing = if (private_source_record_available) as_character_list(source_existing) else NULL,
      source_persona_inserts = if (private_source_persona_available) persona_inserts else NULL,
      source_persona_existing = if (private_source_persona_available) persona_existing else NULL,
      source_persona_identity_candidates = if (private_source_persona_available)
        c(persona_inserts, persona_existing) else NULL,
      legacy_retirements_present = as_character_list(retired_present),
      narrative_inserts = narrative_inserts, narrative_updates = narrative_updates,
      fact_candidates_eligible = safe_sum(fact_counts$source_bound_literal),
      marriage_candidates_eligible = safe_sum(marriage_counts$source_bound_literal),
      canonical_person_creates = list(), canonical_person_updates = list(),
      canonical_person_deletes = list(), authorized = FALSE
    ),
    blockers = as_character_list(unique(blockers)),
    dry_run_gate = if (private_source_record_available && private_source_persona_available)
      "GO" else "NO-GO",
    reimport_gate = "NO-GO"
  )
  if (is_v3) {
    result$families <- list(
      comparison_basis = "family_rows_complete_members_and_family_facts",
      database_family_count = nrow(families),
      database_family_editorial_count = event_count(families),
      database_family_type_counts = named_counts(families$type),
      database_family_member_count = nrow(family_members),
      database_family_member_editorial_count = event_count(family_members),
      database_family_member_role_counts = named_counts(family_members$rolle),
      database_family_fact_count = nrow(family_facts),
      database_family_fact_editorial_count = event_count(family_facts),
      database_family_fact_source_cited_count = if (nrow(family_facts))
        as.integer(sum(as.integer(family_facts$source_citations) > 0L,
          na.rm = TRUE)) else 0L,
      database_family_fact_provenance_matrix = provenance_matrix(family_facts),
      database_family_fact_type_counts = named_counts(family_facts$faktatype),
      database_change_coverage = list(
        family_rows = event_count(families),
        family_members = event_count(family_members),
        family_facts = event_count(family_facts)
      )
    )
  }
  result
}

render_database_preview_markdown <- function(preview) {
  is_v3 <- identical(preview$schema_version, "1939-v50-database-preview-v3")
  family_lines <- if (is_v3) {
    c(
      "",
      "## Familier og familie-facts",
      sprintf("- family rows / med redaktionelt spor: %d/%d",
        preview$families$database_family_count,
        preview$families$database_family_editorial_count),
      sprintf("- komplette family members / med redaktionelt spor: %d/%d",
        preview$families$database_family_member_count,
        preview$families$database_family_member_editorial_count),
      sprintf("- family facts / med redaktionelt spor / med 1939-citation: %d/%d/%d",
        preview$families$database_family_fact_count,
        preview$families$database_family_fact_editorial_count,
        preview$families$database_family_fact_source_cited_count),
      sprintf("- family-fact provenance source-only/editorial-only/begge/ingen: %d/%d/%d/%d",
        preview$families$database_family_fact_provenance_matrix$source_only,
        preview$families$database_family_fact_provenance_matrix$editorial_only,
        preview$families$database_family_fact_provenance_matrix$both,
        preview$families$database_family_fact_provenance_matrix$neither)
    )
  } else character()
  source_record_lines <- if (isTRUE(preview$source_records$comparison_available)) {
    c(
      sprintf("- eksisterende source records: %d", preview$source_records$existing_count),
      sprintf("- forventede source-record inserts: %d", preview$source_records$insert_count)
    )
  } else {
    "- source-record sammenligning: utilgængelig (privat evidenslag mangler)"
  }
  source_persona_lines <- if (isTRUE(preview$source_personas$comparison_available)) {
    c(
      sprintf("- planlagte source-personaer: %d", preview$source_personas$planned_count),
      sprintf("- eksisterende / inserts / kollisioner: %d/%d/%d",
        preview$source_personas$existing_count, preview$source_personas$insert_count,
        preview$source_personas$collision_count),
      sprintf("- resterende uafklarede identiteter: %d",
        preview$source_personas$remaining_pending_count)
    )
  } else {
    c(
      sprintf("- planlagte source-personaer: %d", preview$source_personas$planned_count),
      "- source-persona sammenligning: utilgængelig (privat evidenslag mangler)",
      sprintf("- resterende uafklarede identiteter: %d",
        preview$source_personas$remaining_pending_count)
    )
  }
  if (is_v3) {
    source_persona_lines <- c(source_persona_lines,
      sprintf("- friske target-matches / mismatches: %d/%d",
        preview$source_personas$target_matched_count,
        preview$source_personas$target_mismatch_count),
      sprintf("- nye personkandidater / strukturelle / uafklarede: %d/%d/%d",
        preview$source_personas$new_person_candidate_count,
        preview$source_personas$structural_or_summary_count,
        preview$source_personas$unresolved_count),
      sprintf("- eksplicitte konkurrenceløsninger (kun provenance): %d",
        length(preview$source_personas$competition_resolutions)))
  }
  lines <- c(
    "# DAA 1939 v50 database-preview",
    "",
    "Skrivebeskyttet read-only sammenligning. Intet er skrevet til databasen.",
    "",
    "## Session",
    sprintf("- database: `%s`", preview$database$database_name),
    sprintf("- PostgreSQL: `%s`", preview$database$server_version),
    sprintf("- transaction_read_only: `%s`", preview$database$transaction_read_only),
    sprintf("- snapshot: `%s`", preview$snapshot_at),
    "",
    "## Personankre",
    sprintf("- matchede: %d", preview$person_anchors$matched_count),
    sprintf("- manglende: %d", preview$person_anchors$missing_count),
    sprintf("- kollisioner: %d", preview$person_anchors$collision_count),
    sprintf("- pensionerede stadig i databasen: %d", preview$person_anchors$retired_present_count),
    sprintf("- eksisterende 1939-personposter uden v50-baseline-mapping: %d",
      length(preview$person_anchors$database_only_record_keys)),
    "",
    "## Source records og narrativer",
    source_record_lines,
    source_persona_lines,
    sprintf("- narrative inserts/updates/unchanged/kollisioner: %d/%d/%d/%d",
      preview$narratives$insert_count, preview$narratives$update_count,
      preview$narratives$unchanged_count, preview$narratives$collision_count),
    "",
    "## Fakta og relationer",
    sprintf("- sikre fact-kandidater / parkerede: %d/%d",
      preview$facts$preview_literal_count, preview$facts$preview_parked_count),
    sprintf("- eksisterende facts / med redaktionelt spor / med 1939-citation: %d/%d/%d",
      preview$facts$database_existing_count, preview$facts$database_editorial_count,
      preview$facts$database_source_cited_count),
    sprintf("- fact provenance source-only/editorial-only/begge/ingen: %d/%d/%d/%d",
      preview$facts$database_provenance_matrix$source_only,
      preview$facts$database_provenance_matrix$editorial_only,
      preview$facts$database_provenance_matrix$both,
      preview$facts$database_provenance_matrix$neither),
    family_lines,
    sprintf("- sikre ægteskabskandidater / parkerede: %d/%d",
      preview$relations$preview_marriage_literal_count,
      preview$relations$preview_marriage_parked_count),
    sprintf("- børnerelationer til genvalidering: %d",
      preview$relations$preview_relationship_pending_count),
    sprintf("- eksisterende relationer / family members: %d/%d",
      preview$relations$database_relation_count,
      preview$relations$database_family_member_count),
    sprintf("- relation provenance source-only/editorial-only/begge/ingen: %d/%d/%d/%d",
      preview$relations$database_provenance_matrix$source_only,
      preview$relations$database_provenance_matrix$editorial_only,
      preview$relations$database_provenance_matrix$both,
      preview$relations$database_provenance_matrix$neither),
    sprintf("- relationer pr. rolle: %s", paste(sprintf("%s=%s",
      names(preview$relations$database_role_counts),
      unlist(preview$relations$database_role_counts, use.names = FALSE)), collapse = ", ")),
    "",
    sprintf("- dry-run gate: **%s**", preview$dry_run_gate),
    sprintf("- reimport gate: **%s**", preview$reimport_gate),
    "",
    "## Blokeringer"
  )
  blockers <- if (length(preview$blockers)) {
    vapply(preview$blockers, function(value) paste0("- `", value, "`"), character(1L))
  } else "- ingen"
  paste(c(lines, blockers, ""), collapse = "\n")
}

render_database_preview_cli_stdout <- function(preview, output_path, report_path) {
  is_v3 <- identical(preview$schema_version, "1939-v50-database-preview-v3")
  summary <- if (is_v3) {
    list(
      schema_version = preview$schema_version,
      output = output_path,
      report = report_path,
      dry_run_gate = preview$dry_run_gate,
      reimport_gate = preview$reimport_gate,
      person_anchors = list(
        matched = preview$person_anchors$matched_count,
        missing = preview$person_anchors$missing_count,
        collisions = preview$person_anchors$collision_count
      ),
      expected_source_record_inserts = preview$source_records$insert_count,
      planned_source_personas = preview$source_personas$planned_count,
      matched_source_persona_targets = preview$source_personas$target_matched_count,
      mismatched_source_persona_targets = preview$source_personas$target_mismatch_count,
      remaining_identity_pending = preview$source_personas$remaining_pending_count,
      new_person_creation_pending = preview$source_personas$new_person_candidate_count,
      structural_or_summary = preview$source_personas$structural_or_summary_count,
      canonical_mutations_authorized = FALSE
    )
  } else {
    list(
      output = output_path,
      report = report_path,
      dry_run_gate = preview$dry_run_gate,
      reimport_gate = preview$reimport_gate,
      person_anchors = list(
        matched = preview$person_anchors$matched_count,
        missing = preview$person_anchors$missing_count,
        collisions = preview$person_anchors$collision_count
      ),
      expected_source_record_inserts = preview$source_records$insert_count,
      planned_source_personas = preview$source_personas$planned_count,
      remaining_identity_pending = preview$source_personas$remaining_pending_count,
      canonical_mutations_authorized = FALSE
    )
  }
  paste0(jsonlite::toJSON(summary, auto_unbox = TRUE, null = "null"), "\n")
}

write_database_preview_outputs <- function(preview, output_path, report_path) {
  output_path <- scalar_text(output_path, "DB_PREVIEW_OUTPUT_INVALID")
  report_path <- scalar_text(report_path, "DB_PREVIEW_OUTPUT_INVALID")
  if (identical(normalizePath(output_path, mustWork = FALSE),
      normalizePath(report_path, mustWork = FALSE))) {
    preview_stop("DB_PREVIEW_OUTPUT_INVALID")
  }
  if (file.exists(output_path) || file.exists(report_path)) {
    stop("File exists: database-preview output overskrives ikke", call. = FALSE)
  }
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(report_path), recursive = TRUE, showWarnings = FALSE)
  output_connection <- report_connection <- NULL
  created <- character()
  success <- FALSE
  on.exit({
    if (!is.null(output_connection)) try(close(output_connection), silent = TRUE)
    if (!is.null(report_connection)) try(close(report_connection), silent = TRUE)
    if (!success && length(created)) unlink(created, force = TRUE)
  }, add = TRUE)
  output_connection <- file(output_path, open = "wx", encoding = "UTF-8")
  created <- c(created, output_path)
  report_connection <- file(report_path, open = "wx", encoding = "UTF-8")
  created <- c(created, report_path)
  writeLines(jsonlite::toJSON(preview, auto_unbox = TRUE, pretty = TRUE,
    null = "null", na = "null"), output_connection, useBytes = TRUE)
  writeLines(render_database_preview_markdown(preview), report_connection, useBytes = TRUE)
  close(output_connection)
  output_connection <- NULL
  close(report_connection)
  report_connection <- NULL
  success <- TRUE
  invisible(list(output = output_path, report = report_path))
}
