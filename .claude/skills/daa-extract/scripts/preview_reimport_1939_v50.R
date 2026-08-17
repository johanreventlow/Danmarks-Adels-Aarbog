#!/usr/bin/env Rscript
# Strictly read-only Supabase/PostgreSQL comparison for the DAA 1939 v50
# import preview. This script never calls the legacy loader or a mutation RPC.

suppressPackageStartupMessages({
  library(DBI)
  library(jsonlite)
  library(RPostgres)
})

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(script_argument)) stop("DB_PREVIEW_SCRIPT_PATH_UNKNOWN", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", script_argument[[1L]]))
source(file.path(dirname(script_path), "preview_reimport_1939_v50_helpers.R"))

parse_cli <- function(args) {
  allowed <- c("input", "source-personas", "source-personas-sha256", "output",
    "report", "expected-database", "source-edition")
  values <- list("source-edition" = "DAA 1939")
  for (arg in args) {
    if (!grepl("^--[^=]+=.+$", arg)) stop("DB_PREVIEW_USAGE", call. = FALSE)
    key <- sub("^--([^=]+)=.*$", "\\1", arg)
    value <- sub("^--[^=]+=", "", arg)
    if (!key %in% allowed || !is.null(values[[key]]) && key != "source-edition") {
      stop("DB_PREVIEW_USAGE", call. = FALSE)
    }
    values[[key]] <- value
  }
  required <- c("input", "source-personas", "source-personas-sha256", "output", "report")
  if (any(!required %in% names(values))) stop("DB_PREVIEW_USAGE", call. = FALSE)
  values
}

sha256_file <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  raw <- readBin(connection, what = "raw", n = file.info(path)$size)
  digest::digest(raw, algo = "sha256", serialize = FALSE)
}

args <- parse_cli(commandArgs(trailingOnly = TRUE))
host <- Sys.getenv("SUPABASE_HOST")
user <- Sys.getenv("SUPABASE_USER")
password <- Sys.getenv("SUPABASE_PASSWORD")
port <- suppressWarnings(as.integer(Sys.getenv("SUPABASE_PORT", "5432")))
database <- Sys.getenv("SUPABASE_DB", "postgres")
expected_database <- args[["expected-database"]] %||% database
validate_preview_connection(host, user, password, port, database)

preview <- jsonlite::fromJSON(args$input, simplifyVector = FALSE)
source_personas <- jsonlite::fromJSON(args[["source-personas"]], simplifyVector = FALSE)
input_preview_sha256 <- sha256_file(args$input)
source_personas_sha256 <- sha256_file(args[["source-personas"]])
validate_source_persona_file_hash(source_personas$schema_version,
  source_personas_sha256, args[["source-personas-sha256"]])
validate_import_preview(preview)
validate_source_persona_materialization(source_personas, preview,
  input_preview_sha256, source_personas_sha256)

connection <- DBI::dbConnect(
  RPostgres::Postgres(), host = host, port = port, dbname = database,
  user = user, password = password,
  sslmode = Sys.getenv("SUPABASE_SSLMODE", "require"), bigint = "integer"
)
on.exit(if (!is.null(connection)) try(DBI::dbDisconnect(connection), silent = TRUE), add = TRUE)

query <- function(sql, params = list()) {
  if (length(params)) DBI::dbGetQuery(connection, sql, params = params) else DBI::dbGetQuery(connection, sql)
}
execute <- function(sql, params = list()) {
  if (length(params)) DBI::dbExecute(connection, sql, params = params) else DBI::dbExecute(connection, sql)
}

database_preview <- build_database_preview(
  preview, source_personas, source_personas_sha256, input_preview_sha256,
  query, execute,
  expected_database = expected_database,
  expected_source_edition = args[["source-edition"]]
)
DBI::dbDisconnect(connection)
connection <- NULL

write_database_preview_outputs(database_preview, args$output, args$report)
cat(render_database_preview_cli_stdout(
  database_preview, args$output, args$report
))
