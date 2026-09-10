#!/usr/bin/env Rscript
# Læse-kun eksport af helposter (occurrence-tekster) til klausul-segmentering (#148 4.1b).
# Åbner en REPEATABLE READ READ ONLY transaktion og ruller altid tilbage.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite); library(digest) })
args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--source-id", "--output-dir")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags)) stop("EXPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) { i <- match(flag, args); if (is.na(i) || i == length(args) || grepl("^--", args[[i + 1L]])) stop("EXPORT_CLI_INVALID", call. = FALSE); args[[i + 1L]] }
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])))
source(file.path(script_dir, "export_legacy_migration_candidates_helpers.R"))  # genbrug lmc_validate_output_dir
source_id <- suppressWarnings(as.integer(value("--source-id"))); if (is.na(source_id) || source_id <= 0L) stop("EXPORT_CLI_INVALID", call. = FALSE)
output_dir <- lmc_validate_output_dir(value("--output-dir"))
texts_path <- file.path(output_dir, "clause-source-texts-v1.json"); index_path <- file.path(output_dir, "clause-source-index-v1.json")
if (file.exists(texts_path) || file.exists(index_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)
con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
rows <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, o.occurrence_key, ob.page_from, ob.page_to, ob.char_from, ob.char_to, ob.verbatim_text,
         encode(extensions.digest(ob.verbatim_text,'sha256'),'hex') AS verbatim_sha256, r.content_sha256 AS rendition_content_sha256
    FROM private.source_observation ob
    JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id
    JOIN private.source_rendition r ON r.id=o.rendition_id
    JOIN private.source_record_anchor_current a ON a.occurrence_id=o.id AND a.decision_status='accepted'
    JOIN private.source_record sr ON sr.id=a.source_record_id
   WHERE r.source_id=$1 AND ob.parent_observation_id IS NULL
   ORDER BY sr.record_key COLLATE \"C\"", params = list(source_id))
DBI::dbExecute(con, "ROLLBACK")
if (nrow(rows) == 0L) stop("EXPORT_NO_ROWS", call. = FALSE)
if (anyDuplicated(rows$record_key)) stop("EXPORT_RECORD_KEY_NOT_UNIQUE", call. = FALSE)
file.create(texts_path); Sys.chmod(texts_path, "0600")
jsonlite::write_json(rows, texts_path, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
jsonlite::write_json(rows[, setdiff(names(rows), "verbatim_text")], index_path, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
cat(jsonlite::toJSON(list(records = nrow(rows), texts_sha256 = digest::digest(file = texts_path, algo = "sha256")), auto_unbox = TRUE), "\n")
