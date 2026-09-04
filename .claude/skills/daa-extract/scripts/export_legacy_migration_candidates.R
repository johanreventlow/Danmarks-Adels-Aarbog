#!/usr/bin/env Rscript
# Læse-kun eksport af legacy-migration-kandidater (spec §7, brief Task 7).
# Åbner en REPEATABLE READ READ ONLY transaktion, kalder aldrig en muterende
# RPC og ruller altid tilbage. Kandidatfilen bærer ingen rå tekst; teksterne
# skrives i en separat 0600-fil.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--source-id", "--output-dir")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags))
  stop("EXPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("EXPORT_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_legacy_migration_candidates_helpers.R"))

source_id <- suppressWarnings(as.integer(value("--source-id")))
if (is.na(source_id) || source_id <= 0L) stop("EXPORT_CLI_INVALID", call. = FALSE)

output_dir <- lmc_validate_output_dir(value("--output-dir"))
candidates_path <- file.path(output_dir, "legacy-migration-candidates-v1.json")
texts_path <- file.path(output_dir, "legacy-migration-texts-v1.json")
if (file.exists(candidates_path) || file.exists(texts_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)

con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"),
  host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
  user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
query <- function(sql, params = list())
  if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
result <- lmc_export_run(query, source_id)
DBI::dbExecute(con, "ROLLBACK")

jsonlite::write_json(result$candidates, candidates_path,
  auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
# Opret tekstfilen restriktivt FØR den bærer indhold — intet vindue hvor en
# fil med levende personers narrativtekst ligger med standardrettigheder.
file.create(texts_path)
Sys.chmod(texts_path, "0600")
jsonlite::write_json(result$texts, texts_path,
  auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)

cat(jsonlite::toJSON(list(
  candidates = length(result$candidates),
  already_bound = sum(vapply(result$candidates, function(row) isTRUE(row$already_bound), logical(1)))
), auto_unbox = TRUE, pretty = TRUE), "\n")
