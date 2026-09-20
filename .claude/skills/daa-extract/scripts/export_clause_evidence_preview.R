#!/usr/bin/env Rscript
# Læse-kun før-billede for én clause_evidence-apply (#148 4.1c). Åbner en REPEATABLE READ
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
preview <- list(
  preview_schema_version = "clause-evidence-preview-v1",
  manifest_content_sha256 = manifest$manifest_content_sha256,
  manifest_bytes_sha256 = manifest_bytes_sha256,
  narrative_record_contract_version = query("SELECT public.narrative_record_contract_version() v")$v[[1L]],
  source = preview_source_state(query, manifest),
  expected_counts = reimport_writer_expected_counts(manifest),
  before_counts = list(
    helposts = query("SELECT count(*) n FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id JOIN private.source_rendition r ON r.id=o.rendition_id WHERE r.source_id=$1 AND ob.parent_observation_id IS NULL", list(manifest$source$id))$n[[1L]],
    clauses = query("SELECT count(*) n FROM private.source_observation ob JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id JOIN private.source_rendition r ON r.id=o.rendition_id WHERE r.source_id=$1 AND ob.observation_kind='clause'", list(manifest$source$id))$n[[1L]]),
  record_key_coverage = preview_record_key_coverage(query, manifest),
  canonical_baseline_sha256 = preview_canonical_baseline(query),
  database_write_authorized = FALSE, production_authorized = FALSE)
DBI::dbExecute(con, "ROLLBACK")

file.create(output)
Sys.chmod(output, "0600")
writeLines(jsonlite::toJSON(preview, auto_unbox = TRUE, null = "null", pretty = TRUE), output)
cat(jsonlite::toJSON(list(
  preview_sha256 = digest::digest(file = output, algo = "sha256"),
  manifest_content_sha256 = manifest$manifest_content_sha256,
  manifest_bytes_sha256 = manifest_bytes_sha256,
  clause_evidence = length(manifest$operations),
  clauses = sum(vapply(manifest$operations, function(op) length(op$clauses), integer(1)))
), auto_unbox = TRUE, pretty = TRUE), "\n")
