#!/usr/bin/env Rscript
# Læse-kun før-billede for én source_evidence-apply. Åbner en REPEATABLE READ
# READ ONLY transaktion, kalder aldrig en muterende RPC og ruller altid tilbage.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--profile", "--manifest", "--manifest-sha256", "--output")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags))
  stop("PREVIEW_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("PREVIEW_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_reimport_helpers.R"))
source(file.path(script_dir, "export_reimport_preview_helpers.R"))

manifest_path <- value("--manifest")
size <- file.info(manifest_path)$size
if (is.na(size)) stop("PREVIEW_CLI_INVALID", call. = FALSE)
raw <- readBin(manifest_path, "raw", n = size)
manifest_bytes_sha256 <- digest::digest(raw, algo = "sha256", serialize = FALSE)
if (!identical(manifest_bytes_sha256, value("--manifest-sha256")))
  stop("PREVIEW_MANIFEST_HASH_INVALID", call. = FALSE)
manifest <- jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)

profile <- jsonlite::fromJSON(value("--profile"), simplifyVector = FALSE)
if (!identical(as.integer(profile$source_id), as.integer(manifest$source$id)) ||
    !identical(profile$profile_id, manifest$source$profile_id))
  stop("PREVIEW_PROFILE_MANIFEST_MISMATCH", call. = FALSE)

output <- value("--output")
if (file.exists(output)) stop("PREVIEW_OUTPUT_EXISTS", call. = FALSE)

con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"),
  host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
  user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
query <- function(sql, params = list())
  if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
preview <- build_reimport_preview(query, manifest, manifest_bytes_sha256)
DBI::dbExecute(con, "ROLLBACK")

writeLines(jsonlite::toJSON(preview, auto_unbox = TRUE, null = "null", pretty = TRUE),
           output)
cat(jsonlite::toJSON(list(
  preview_sha256 = digest::digest(file = output, algo = "sha256"),
  manifest_content_sha256 = manifest$manifest_content_sha256,
  manifest_bytes_sha256 = manifest_bytes_sha256,
  source_evidence = length(manifest$operations)
), auto_unbox = TRUE, pretty = TRUE), "\n")
