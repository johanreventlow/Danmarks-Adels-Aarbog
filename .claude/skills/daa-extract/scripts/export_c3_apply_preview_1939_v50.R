#!/usr/bin/env Rscript
## Read-only export of the C3 apply database preview: measures the exact
## current database state for the five cases in a hash-bound candidate
## manifest, through exactly one RPC call (public.red_preview_reimport_cases,
## Fund H1). Always BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY ...
## ROLLBACK; never mutates production. Narrative prose that arrives via the
## candidate file may reach the output JSON (see the Task 2 report); it
## never reaches stdout/stderr.

.c3_preview_main <- function() {
  script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
  script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
  source(file.path(script_dir, "c3_export_shared_1939_v50_helpers.R"))
  source(file.path(script_dir, "export_c3_apply_preview_1939_v50_helpers.R"))

  args <- commandArgs(trailingOnly = TRUE)
  allowed <- c("--candidate", "--output", "--expect-database-name", "--actor-id")
  parsed <- .c3_common_parse_flags(args, allowed, "C3_PREVIEW_ARGUMENTS_INVALID")
  candidate_path <- parsed[["--candidate"]]
  output_path <- parsed[["--output"]]
  expected_database_name <- parsed[["--expect-database-name"]]
  actor_id <- parsed[["--actor-id"]]
  if (!.c3_common_scalar_string(expected_database_name, "^[A-Za-z0-9_.-]+$"))
    .c3_common_stop("C3_PREVIEW_DATABASE_NAME_INVALID")
  ## Task 2 addendum: red_preview_reimport_cases is SECURITY DEFINER and its
  ## first statement gates on auth.uid(), which a direct DBI connection never
  ## carries -- see export_c3_apply_preview_1939_v50_helpers.R's
  ## `.c3_preview_jwt_sql` comment for the full chain. Validated here, DB-free,
  ## before any connection is opened, mirroring the database-name check
  ## immediately above it.
  if (!.c3_common_scalar_string(actor_id, .c3_preview_actor_id_pattern))
    .c3_common_stop("C3_PREVIEW_ACTOR_ID_INVALID")
  .c3_common_refuse_existing_output(output_path, "C3_PREVIEW_OUTPUT_EXISTS")

  candidate_raw <- .c3_common_read_regular_raw(candidate_path,
                                               "C3_PREVIEW_CANDIDATE_UNREADABLE")
  ## Fail closed on a malformed candidate before ever opening a database
  ## connection, mirroring the current-state exporter's pre-connect
  ## selection validation. build_c3_apply_database_preview() re-validates
  ## the same candidate bytes internally; this is a deliberately cheap,
  ## redundant DB-free gate, not a second source of truth.
  invisible(.c3_preview_parse_candidate(candidate_raw))

  connection_values <- .c3_common_pg_connection_values(
    "C3_PREVIEW_PG_ENV_INVALID", "C3_PREVIEW_CONNECTION_ENV_INVALID")

  con <- tryCatch(
    DBI::dbConnect(
      RPostgres::Postgres(), dbname = connection_values$dbname,
      host = connection_values$host, port = connection_values$port,
      user = connection_values$user, password = connection_values$password,
      sslmode = if (connection_values$local) "disable" else {
        sslmode <- Sys.getenv("SUPABASE_SSLMODE")
        if (nzchar(sslmode)) sslmode else "require"
      },
      bigint = "integer"
    ),
    error = function(e) .c3_common_stop("C3_PREVIEW_DATABASE_CONNECT_FAILED")
  )
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  gateway <- list(
    query = function(sql, params = NULL) {
      if (is.null(params) || !length(params)) DBI::dbGetQuery(con, sql)
      else DBI::dbGetQuery(con, sql, params = params)
    },
    execute = function(sql, params = NULL) {
      if (is.null(params) || !length(params)) DBI::dbExecute(con, sql)
      else DBI::dbExecute(con, sql, params = params)
      invisible(NULL)
    }
  )

  preview <- build_c3_apply_database_preview(candidate_raw, gateway,
                                             expected_database_name, actor_id)

  rendered <- paste0(jsonlite::toJSON(preview, auto_unbox = TRUE, pretty = TRUE,
                                      null = "null"), "\n")
  .c3_common_publish_exclusive(rendered, output_path, "C3_PREVIEW_OUTPUT_EXISTS",
                                "C3_PREVIEW_OUTPUT_WRITE_FAILED")
  before <- preview$before_state
  cat(sprintf(
    "schema=%s database=%s identity_pairs=%d source_records=%d target_narratives=%d bindings=%d output=%s candidate_sha256=%s\n",
    preview$schema_version, preview$database$database_name,
    length(before$identity_pairs), length(before$source_records),
    length(before$target_narratives), length(before$bindings),
    basename(output_path), preview$candidate_file_sha256))
  invisible(0L)
}

.c3_preview_status <- tryCatch(
  .c3_preview_main(),
  error = function(error) {
    token <- conditionMessage(error)
    if (!grepl("^C3_PREVIEW_[A-Z0-9_]+$", token)) token <- "C3_PREVIEW_INTERNAL_ERROR"
    cat(token, "\n", sep = "", file = stderr())
    1L
  }
)
quit(save = "no", status = .c3_preview_status)
