#!/usr/bin/env Rscript
# Read-only extraction of the 23 database-only DAA 1939 profiles used by the
# v50 identity review. No mutation RPC or legacy loader is called.

suppressPackageStartupMessages({
  library(DBI)
  library(digest)
  library(jsonlite)
  library(RPostgres)
})

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(script_argument)) stop("IDENTITY_PROFILE_SCRIPT_PATH_UNKNOWN", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", script_argument[[1L]]))
source(file.path(dirname(script_path), "preview_reimport_1939_v50_helpers.R"))
source(file.path(dirname(script_path), "profile_identity_review_1939_v50_helpers.R"))

parse_identity_profile_cli <- function(args) {
  allowed <- c("database-preview", "output", "expected-database")
  values <- list()
  for (arg in args) {
    if (!grepl("^--[^=]+=.+$", arg)) stop("IDENTITY_PROFILE_USAGE", call. = FALSE)
    key <- sub("^--([^=]+)=.*$", "\\1", arg)
    value <- sub("^--[^=]+=", "", arg)
    if (!key %in% allowed || !is.null(values[[key]])) stop("IDENTITY_PROFILE_USAGE", call. = FALSE)
    values[[key]] <- value
  }
  if (any(!c("database-preview", "output") %in% names(values))) {
    stop("IDENTITY_PROFILE_USAGE", call. = FALSE)
  }
  values
}

sha256_file <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  raw <- readBin(connection, what = "raw", n = file.info(path)$size)
  digest::digest(raw, algo = "sha256", serialize = FALSE)
}

args <- parse_identity_profile_cli(commandArgs(trailingOnly = TRUE))
host <- Sys.getenv("SUPABASE_HOST")
user <- Sys.getenv("SUPABASE_USER")
password <- Sys.getenv("SUPABASE_PASSWORD")
port <- suppressWarnings(as.integer(Sys.getenv("SUPABASE_PORT", "5432")))
database <- Sys.getenv("SUPABASE_DB", "postgres")
expected_database <- args[["expected-database"]] %||% database
validate_preview_connection(host, user, password, port, database)

database_preview <- jsonlite::fromJSON(args[["database-preview"]], simplifyVector = FALSE)
validate_identity_database_preview(database_preview)
database_preview_sha256 <- sha256_file(args[["database-preview"]])

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

profiles <- build_identity_database_profiles(
  database_preview, query, execute,
  expected_database = expected_database,
  database_preview_sha256 = database_preview_sha256
)
DBI::dbDisconnect(connection)
connection <- NULL
write_identity_profile_output(profiles, args$output)

cat(jsonlite::toJSON(list(
  output = args$output,
  profiles = profiles$counts$profiles,
  review_only = TRUE,
  canonical_mutations_authorized = FALSE
), auto_unbox = TRUE))
cat("\n")

