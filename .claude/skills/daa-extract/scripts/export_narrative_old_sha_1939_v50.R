#!/usr/bin/env Rscript
## CLI: Rscript export_narrative_old_sha_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY export of the current source_id=3 (DAA 1939) person-narrative
## state (person_id, narrative_sha256, side, privat) -- the reproducible
## replacement for Task 2's ad hoc psql export (schema v1: person_id +
## narrative_sha256 only). build_narrative_replacement_manifest_1939_v50.py
## consumes this (schema v2) to derive expected_old_side/expected_old_privat
## per operation and the documented side_corrections list. Never writes to
## the database; never calls any RPC; no actor/JWT context required (a plain
## SELECT, not an authenticated write path).
##
## `--expect-database-name` is an optional safety check: if supplied, the
## script aborts BEFORE running the export query if the connected
## `current_database()` does not match -- guards against accidentally
## pointing this at the wrong local Postgres instance (rehearsal vs. a
## stray leftover database).
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("EXPORT_NARRATIVE_OLD_SHA_1939_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("EXPORT_NARRATIVE_OLD_SHA_1939_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("EXPORT_NARRATIVE_OLD_SHA_1939_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("EXPORT_NARRATIVE_OLD_SHA_1939_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags) value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_narrative_old_sha_1939_v50_helpers.R"))

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable" else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE") else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

identity <- DBI::dbGetQuery(con,
  "SELECT current_database() AS database_name,(pg_control_system()).system_identifier::text AS system_identifier")
database_name <- identity$database_name[[1L]]
if (!is.na(expect_database_name) && !identical(database_name, expect_database_name))
  stop(paste0("EXPORT_NARRATIVE_OLD_SHA_1939_DATABASE_MISMATCH:observed=", database_name,
    ":expected=", expect_database_name), call. = FALSE)

sql_text <- paste(
  "SELECT subjekt_id AS person_id,",
  "encode(sha256(convert_to(tekst,'UTF8')),'hex') AS narrative_sha256,",
  "side, privat",
  "FROM narrative WHERE subjekt_type='person' AND source_id=3 ORDER BY subjekt_id"
)
rows <- DBI::dbGetQuery(con, sql_text)
rows$person_id <- as.numeric(rows$person_id)
rows$narrative_sha256 <- as.character(rows$narrative_sha256)
rows$side <- as.character(rows$side)
rows$privat <- as.logical(rows$privat)

doc <- build_narrative_old_sha_export_1939_v50(
  rows, database_name = database_name, database_identity = identity$system_identifier[[1L]],
  generator = "export_narrative_old_sha_1939_v50.R:v1", sql_text = sql_text
)
writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE), output, useBytes = TRUE)
