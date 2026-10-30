#!/usr/bin/env Rscript
# Læse-kun eksport af helposter (occurrence-tekster) til klausul-segmentering (#148 4.1b).
# Trin 6a: helposten vælges pr. record af basens regel (private.record_helpost_status) og teksten er helpostens
# GÆLDENDE version (private.helpost_text_current). Records uden helpost (none) står som null-rækker i tekstfilen og
# i indeksfilens no_helpost-liste; ambiguous/outside stopper eksporten (EXPORT_HELPOST_INVALID).
# Åbner en REPEATABLE READ READ ONLY transaktion og ruller altid tilbage.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite); library(digest) })
args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--source-id", "--output-dir", "--helpost-kind")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags)) stop("EXPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) { i <- match(flag, args); if (is.na(i) || i == length(args) || grepl("^--", args[[i + 1L]])) stop("EXPORT_CLI_INVALID", call. = FALSE); args[[i + 1L]] }
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])))
source(file.path(script_dir, "export_legacy_migration_candidates_helpers.R"))  # genbrug lmc_validate_output_dir
source_id <- suppressWarnings(as.integer(value("--source-id"))); if (is.na(source_id) || source_id <= 0L) stop("EXPORT_CLI_INVALID", call. = FALSE)
helpost_kind <- value("--helpost-kind"); if (!nzchar(trimws(helpost_kind))) stop("EXPORT_CLI_INVALID", call. = FALSE)
output_dir <- lmc_validate_output_dir(value("--output-dir"))
texts_path <- file.path(output_dir, "clause-source-texts-v1.json"); index_path <- file.path(output_dir, "clause-source-index-v1.json")
if (file.exists(texts_path) || file.exists(index_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)
con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
invisible(DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"))
status_rows <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, h.status, h.observation_id, h.occurrence_id
    FROM (SELECT DISTINCT sr.id, sr.record_key
            FROM private.source_record sr
            JOIN private.source_record_anchor_current a ON a.source_record_id=sr.id AND a.decision_status='accepted'
            JOIN private.source_record_occurrence o ON o.id=a.occurrence_id
            JOIN private.source_rendition r ON r.id=o.rendition_id
           WHERE r.source_id=$1) sr
   CROSS JOIN LATERAL private.record_helpost_status(sr.id, $2) h
   ORDER BY sr.record_key COLLATE \"C\"", params = list(source_id, helpost_kind))
if (nrow(status_rows) == 0L) { DBI::dbExecute(con, "ROLLBACK"); stop("EXPORT_NO_ROWS", call. = FALSE) }
if (anyDuplicated(status_rows$record_key)) { DBI::dbExecute(con, "ROLLBACK"); stop("EXPORT_RECORD_KEY_NOT_UNIQUE", call. = FALSE) }
if (any(!status_rows$status %in% c("ok", "none"))) { DBI::dbExecute(con, "ROLLBACK"); stop("EXPORT_HELPOST_INVALID", call. = FALSE) }
ok_rows <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, o.occurrence_key, ob.page_from, ob.page_to, ob.char_from, ob.char_to, c.text_id, c.verbatim_text,
         encode(extensions.digest(c.verbatim_text,'sha256'),'hex') AS verbatim_sha256, r.content_sha256 AS rendition_content_sha256
    FROM private.source_observation ob
    JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id
    JOIN private.source_rendition r ON r.id=o.rendition_id
    JOIN private.source_record sr ON sr.source_id=r.source_id
    JOIN private.source_record_anchor_current a ON a.occurrence_id=o.id AND a.source_record_id=sr.id AND a.decision_status='accepted'
    CROSS JOIN LATERAL private.helpost_text_current(ob.id) c
   WHERE ob.id = ANY($1::uuid[])
   ORDER BY sr.record_key COLLATE \"C\"", params = list(paste0("{", paste(status_rows$observation_id[status_rows$status == "ok"], collapse = ","), "}")))
invisible(DBI::dbExecute(con, "ROLLBACK"))
none_keys <- status_rows$record_key[status_rows$status == "none"]
ok_keys <- status_rows$record_key[status_rows$status == "ok"]
# Transaktionen er rullet tilbage ovenfor; mængden (ikke kun antallet) af ok-rækker skal være præcis ok-recordene.
if (nrow(ok_rows) != length(ok_keys) || anyDuplicated(ok_rows$record_key) || !identical(sort(ok_rows$record_key, method = "radix"), sort(ok_keys, method = "radix")))
  stop("EXPORT_HELPOST_ROWS_MISMATCH", call. = FALSE)
cols <- c("record_key", "occurrence_key", "page_from", "page_to", "char_from", "char_to", "text_id", "verbatim_text", "verbatim_sha256", "rendition_content_sha256")
# Rækkeform med eksplicitte null-felter: no_helpost-rækker bærer kun record_key (Python-ledgeren tæller dem).
as_row <- function(src) lapply(setNames(cols, cols), function(k) if (is.null(src[[k]]) || is.na(src[[k]])) NULL else src[[k]])
out_rows <- c(lapply(seq_len(nrow(ok_rows)), function(i) as_row(as.list(ok_rows[i, , drop = FALSE]))),
              lapply(none_keys, function(k) as_row(list(record_key = k))))
out_rows <- out_rows[order(vapply(out_rows, function(r) r$record_key, ""), method = "radix")]
invisible(file.create(texts_path)); Sys.chmod(texts_path, "0600")
jsonlite::write_json(out_rows, texts_path, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
index_rows <- lapply(seq_len(nrow(ok_rows)), function(i) as_row(as.list(ok_rows[i, , drop = FALSE]))[setdiff(cols, "verbatim_text")])
no_helpost <- lapply(none_keys, function(k) list(record_key = k, status = "none"))
jsonlite::write_json(list(records = index_rows, no_helpost = no_helpost), index_path, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
cat(jsonlite::toJSON(list(records_ok = nrow(ok_rows), no_helpost = length(none_keys), texts_sha256 = digest::digest(file = texts_path, algo = "sha256")), auto_unbox = TRUE), "\n")
