#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--manifest", "--manifest-sha256", "--mode", "--output", "--authorization")
if (any(!flags %in% allowed) || anyDuplicated(flags)) stop("REIMPORT_NAME_COMPLETION_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]])) stop("REIMPORT_NAME_COMPLETION_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
if (!all(c("--manifest", "--manifest-sha256", "--mode", "--output") %in% flags)) stop("REIMPORT_NAME_COMPLETION_CLI_INVALID", call. = FALSE)
mode <- value("--mode")
if (!mode %in% c("dry-run", "apply") || (identical(mode, "apply") != ("--authorization" %in% flags))) stop("REIMPORT_NAME_COMPLETION_CLI_INVALID", call. = FALSE)
output <- value("--output")
if (file.exists(output)) stop("REIMPORT_NAME_COMPLETION_OUTPUT_EXISTS", call. = FALSE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_name_completion_helpers.R"))
manifest_path <- value("--manifest")
size <- file.info(manifest_path)$size
if (is.na(size)) stop("REIMPORT_NAME_COMPLETION_CLI_INVALID", call. = FALSE)
raw <- readBin(manifest_path, "raw", n = size)
manifest_sha256 <- value("--manifest-sha256")
if (!identical(digest::digest(raw, algo = "sha256", serialize = FALSE), manifest_sha256)) stop("REIMPORT_NAME_COMPLETION_MANIFEST_HASH_INVALID", call. = FALSE)
authorization <- if (identical(mode, "apply")) jsonlite::fromJSON(value("--authorization"), simplifyVector = FALSE) else NULL
connection_factory <- function() DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
result <- execute_name_completion(jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE), manifest_sha256, mode, new_name_completion_dbi_gateway(connection_factory), authorization)
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), output, useBytes = TRUE)
