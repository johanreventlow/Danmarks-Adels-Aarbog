#!/usr/bin/env Rscript
## Read-only export of the selected C3 structural database state.
## Narrative prose is hashed in the database and never enters R.

.c3_state_main <- function() {
  script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
  script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
  source(file.path(script_dir, "export_c3_current_state_1939_v50_helpers.R"))

  args <- commandArgs(trailingOnly = TRUE)
  allowed <- c("--selection", "--output", "--expect-database-name")
  if (length(args) != 6L || any(seq_along(args) %% 2L == 0L & grepl("^--", args)) ||
      any(seq_along(args) %% 2L == 1L & !grepl("^--", args)))
    .c3_state_stop("C3_STATE_ARGUMENTS_INVALID")
  flags <- args[seq.int(1L, length(args), by = 2L)]
  values <- args[seq.int(2L, length(args), by = 2L)]
  if (anyDuplicated(flags) || !setequal(flags, allowed) || any(!nzchar(values)))
    .c3_state_stop("C3_STATE_ARGUMENTS_INVALID")
  value <- function(flag) values[[match(flag, flags)]]
  selection_path <- value("--selection")
  output_path <- value("--output")
  expected_database_name <- value("--expect-database-name")
  if (!.c3_state_scalar_string(expected_database_name, "^[A-Za-z0-9_.-]+$"))
    .c3_state_stop("C3_STATE_DATABASE_NAME_INVALID")
  if (file.exists(output_path)) .c3_state_stop("C3_STATE_OUTPUT_EXISTS")

  selection_raw <- tryCatch({
    size <- file.info(selection_path)$size
    if (length(size) != 1L || is.na(size) || size <= 0) stop("invalid")
    readBin(selection_path, what = "raw", n = size)
  }, error = function(e) .c3_state_stop("C3_STATE_SELECTION_INVALID"))
  selection_sha256 <- digest::digest(selection_raw, algo = "sha256", serialize = FALSE)
  selection <- tryCatch(
    jsonlite::fromJSON(rawToChar(selection_raw), simplifyVector = TRUE),
    error = function(e) .c3_state_stop("C3_STATE_SELECTION_INVALID")
  )

  scalar_count <- function(value, expected) {
    is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value == expected
  }
  hashes <- selection$input_hashes
  valid_hashes <- is.list(hashes) &&
    setequal(names(hashes), c("c0_candidates_sha256", "c0_decisions_sha256")) &&
    all(vapply(hashes, .c3_state_scalar_string, logical(1),
               pattern = "^[0-9a-f]{64}$"))
  if (!is.list(selection) ||
      !identical(selection$schema_version, "1939-v50-c3-selection-v1") ||
      !scalar_count(selection$case_count, 7) ||
      !scalar_count(selection$record_count, 8) ||
      !scalar_count(selection$decision_line_count, 15) ||
      !valid_hashes || !.c3_state_valid_ids(selection$person_ids) ||
      anyDuplicated(selection$person_ids))
    .c3_state_stop("C3_STATE_SELECTION_INVALID")
  person_ids <- sort(as.numeric(selection$person_ids), method = "radix")

  pg_names <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
  pg_set <- nzchar(Sys.getenv(pg_names))
  if (any(pg_set) && !all(pg_set)) .c3_state_stop("C3_STATE_PG_ENV_INVALID")
  local_pg <- all(pg_set)
  env_or <- function(primary, fallback) {
    result <- Sys.getenv(primary)
    if (nzchar(result)) result else Sys.getenv(fallback)
  }
  connection_values <- list(
    dbname = env_or("PGDATABASE", "SUPABASE_DB"),
    host = env_or("PGHOST", "SUPABASE_HOST"),
    port = env_or("PGPORT", "SUPABASE_PORT"),
    user = env_or("PGUSER", "SUPABASE_USER"),
    password = env_or("PGPASSWORD", "SUPABASE_PASSWORD")
  )
  port <- suppressWarnings(as.integer(connection_values$port))
  if (any(!nzchar(unlist(connection_values, use.names = FALSE))) ||
      is.na(port) || port < 1L || port > 65535L)
    .c3_state_stop("C3_STATE_CONNECTION_ENV_INVALID")

  con <- tryCatch(
    DBI::dbConnect(
      RPostgres::Postgres(), dbname = connection_values$dbname,
      host = connection_values$host, port = port, user = connection_values$user,
      password = connection_values$password,
      sslmode = if (local_pg) "disable" else {
        sslmode <- Sys.getenv("SUPABASE_SSLMODE")
        if (nzchar(sslmode)) sslmode else "require"
      },
      bigint = "integer"
    ),
    error = function(e) .c3_state_stop("C3_STATE_DATABASE_CONNECT_FAILED")
  )
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  query <- function(sql, params = NULL) {
    tryCatch(
      if (is.null(params)) DBI::dbGetQuery(con, sql)
      else DBI::dbGetQuery(con, sql, params = params),
      error = function(e) .c3_state_stop("C3_STATE_DATABASE_QUERY_FAILED")
    )
  }
  identity <- query(
    "SELECT current_database(), (pg_control_system()).system_identifier::text;"
  )
  if (nrow(identity) != 1L || ncol(identity) != 2L)
    .c3_state_stop("C3_STATE_DATABASE_IDENTITY_INVALID")
  database_name <- as.character(identity[[1L]][[1L]])
  database_identity <- as.character(identity[[2L]][[1L]])
  if (!identical(database_name, expected_database_name))
    .c3_state_stop("C3_STATE_DATABASE_MISMATCH")

  pg_ids <- paste0("{", paste(as.integer(person_ids), collapse = ","), "}")
  params <- list(pg_ids)
  person_rows <- query(
    paste(
      "SELECT id AS person_id, staged, privat FROM person",
      "WHERE id = ANY($1) ORDER BY id;"
    ), params
  )
  narrative_rows <- query(
    paste(
      "SELECT n.subjekt_id AS person_id, n.id AS narrative_id,",
      "encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS old_sha256,",
      "n.privat, n.side, p.source_record_id, p.status AS binding_status",
      "FROM narrative n",
      "LEFT JOIN private.narrative_record_publication p ON p.narrative_id=n.id",
      "WHERE n.subjekt_type='person' AND n.source_id=3 AND n.subjekt_id=ANY($1);"
    ), params
  )
  identity_rows <- query(
    paste(
      "SELECT rolle, subjekt_id AS subject_id, objekt_id AS object_id",
      "FROM relation",
      "WHERE subjekt_type='person' AND objekt_type='person'",
      "AND rolle IN ('samme_som','ikke_samme_som')",
      "AND (subjekt_id=ANY($1) OR objekt_id=ANY($1));"
    ), params
  )
  partner_conflict_rows <- query(
    paste(
      "WITH selected(person_id) AS (SELECT unnest($1::bigint[])),",
      "components AS (",
      "SELECT s.person_id AS seed_id,g.pid AS member_id",
      "FROM selected s",
      "CROSS JOIN LATERAL public._samme_som_gruppe(s.person_id) g",
      ")",
      "SELECT DISTINCT least(a.seed_id,b.seed_id) AS left_person_id,",
      "greatest(a.seed_id,b.seed_id) AS right_person_id,fa.family_id",
      "FROM family_member fa",
      "JOIN components a ON a.member_id=fa.person_id",
      "JOIN family_member fb ON fb.family_id=fa.family_id",
      "AND fb.rolle='partner' AND fb.person_id<>fa.person_id",
      "JOIN components b ON b.member_id=fb.person_id AND b.seed_id<>a.seed_id",
      "WHERE fa.rolle='partner'",
      "ORDER BY left_person_id,right_person_id,fa.family_id;"
    ), params
  )

  person_rows$person_id <- as.numeric(person_rows$person_id)
  person_rows$staged <- as.logical(person_rows$staged)
  person_rows$privat <- as.logical(person_rows$privat)
  narrative_rows$person_id <- as.numeric(narrative_rows$person_id)
  narrative_rows$narrative_id <- as.numeric(narrative_rows$narrative_id)
  narrative_rows$old_sha256 <- as.character(narrative_rows$old_sha256)
  narrative_rows$privat <- as.logical(narrative_rows$privat)
  narrative_rows$side <- as.character(narrative_rows$side)
  narrative_rows$source_record_id <- as.character(narrative_rows$source_record_id)
  narrative_rows$binding_status <- as.character(narrative_rows$binding_status)
  identity_rows$rolle <- as.character(identity_rows$rolle)
  identity_rows$subject_id <- as.numeric(identity_rows$subject_id)
  identity_rows$object_id <- as.numeric(identity_rows$object_id)
  partner_conflict_rows$left_person_id <- as.numeric(partner_conflict_rows$left_person_id)
  partner_conflict_rows$right_person_id <- as.numeric(partner_conflict_rows$right_person_id)
  partner_conflict_rows$family_id <- as.numeric(partner_conflict_rows$family_id)

  document <- build_c3_current_state_1939_v50(
    person_ids, person_rows, narrative_rows, identity_rows, partner_conflict_rows,
    database_name, database_identity, "export_c3_current_state_1939_v50.R:v1",
    selection_sha256
  )
  rendered <- paste0(jsonlite::toJSON(document, auto_unbox = TRUE, pretty = TRUE,
                                      null = "null"), "\n")
  temporary <- tempfile(pattern = ".c3-state-", tmpdir = dirname(output_path))
  on.exit(unlink(temporary), add = TRUE)
  tryCatch(writeBin(charToRaw(enc2utf8(rendered)), temporary),
           error = function(e) .c3_state_stop("C3_STATE_OUTPUT_WRITE_FAILED"))
  if (!isTRUE(file.link(temporary, output_path))) {
    if (file.exists(output_path)) .c3_state_stop("C3_STATE_OUTPUT_EXISTS")
    .c3_state_stop("C3_STATE_OUTPUT_WRITE_FAILED")
  }
  unlink(temporary)
  cat(sprintf("persons=%d narratives=%d identity_edges=%d partner_conflicts=%d\n",
              length(document$persons), length(document$narratives),
              length(document$identity_edges), length(document$partner_conflicts)))
  invisible(0L)
}

.c3_state_status <- tryCatch(
  .c3_state_main(),
  error = function(error) {
    token <- conditionMessage(error)
    if (!grepl("^C3_STATE_[A-Z0-9_]+$", token)) token <- "C3_STATE_INTERNAL_ERROR"
    cat(token, "\n", sep = "", file = stderr())
    1L
  }
)
quit(save = "no", status = .c3_state_status)
