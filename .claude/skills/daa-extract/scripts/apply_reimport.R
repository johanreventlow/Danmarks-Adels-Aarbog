#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--manifest", "--manifest-sha256", "--preview-sha256", "--dry-run", "--apply", "--authorization")
if (any(!flags %in% allowed) || anyDuplicated(flags)) stop("REIMPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]])) stop("REIMPORT_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
if (!all(c("--manifest", "--manifest-sha256", "--preview-sha256") %in% flags)) stop("REIMPORT_CLI_INVALID", call. = FALSE)
mode <- if ("--dry-run" %in% flags) "dry-run" else if ("--apply" %in% flags) "apply" else stop("REIMPORT_CLI_INVALID", call. = FALSE)
if (all(c("--dry-run", "--apply") %in% flags) || (identical(mode, "apply") != ("--authorization" %in% flags))) stop("REIMPORT_CLI_INVALID", call. = FALSE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_reimport_helpers.R"))
manifest_path <- value("--manifest")
size <- file.info(manifest_path)$size
if (is.na(size)) stop("REIMPORT_CLI_INVALID", call. = FALSE)
raw <- readBin(manifest_path, "raw", n = size)
if (!identical(digest::digest(raw, algo = "sha256", serialize = FALSE), value("--manifest-sha256"))) stop("REIMPORT_MANIFEST_HASH_INVALID", call. = FALSE)
authorization <- if (identical(mode, "apply")) jsonlite::fromJSON(value("--authorization"), simplifyVector = FALSE) else NULL
connection_factory <- function() DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
result <- execute_reimport(jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE), value("--preview-sha256"), mode, new_reimport_dbi_gateway(connection_factory), authorization)
cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), "\n")
