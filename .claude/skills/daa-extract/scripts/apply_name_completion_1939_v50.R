#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--manifest", "--manifest-sha256", "--mode", "--output", "--authorization")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("NAME_COMPLETION_1939_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("NAME_COMPLETION_1939_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
required <- c("--manifest", "--manifest-sha256", "--mode", "--output")
if (!all(required %in% flags)) stop("NAME_COMPLETION_1939_CLI_INVALID", call. = FALSE)
mode <- value("--mode")
if (!mode %in% c("dry-run", "apply") ||
    (identical(mode, "apply") && !"--authorization" %in% flags) ||
    (identical(mode, "dry-run") && "--authorization" %in% flags))
  stop("NAME_COMPLETION_1939_CLI_INVALID", call. = FALSE)
output <- value("--output")
if (file.exists(output)) stop("NAME_COMPLETION_1939_OUTPUT_EXISTS", call. = FALSE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_name_completion_1939_v50_helpers.R"))
manifest_path <- value("--manifest")
manifest_size <- file.info(manifest_path)$size
if (is.na(manifest_size)) stop("NAME_COMPLETION_1939_CLI_INVALID", call. = FALSE)
raw <- readBin(manifest_path, "raw", n = manifest_size)
manifest_sha256 <- value("--manifest-sha256")
if (!identical(digest::digest(raw, algo = "sha256", serialize = FALSE), manifest_sha256))
  stop("NAME_COMPLETION_1939_MANIFEST_HASH_INVALID", call. = FALSE)
manifest <- jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
authorization <- if (identical(mode, "apply")) {
  jsonlite::fromJSON(value("--authorization"), simplifyVector = FALSE)
} else NULL
actor <- Sys.getenv("DAA_REIMPORT_ACTOR_ID")
if (!name_completion_uuid(actor))
  stop("NAME_COMPLETION_1939_ACTOR_REQUIRED", call. = FALSE)
connection_factory <- function() {
  con <- DBI::dbConnect(
    RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
    port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD")
  )
  tryCatch({
    DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub',$1,false)", params = list(actor))
    con
  }, error = function(error) {
    DBI::dbDisconnect(con)
    stop(conditionMessage(error), call. = FALSE)
  })
}
gateway <- new_name_completion_dbi_gateway(connection_factory)
result <- execute_name_completion(manifest, manifest_sha256, mode, gateway, authorization)
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), output, useBytes = TRUE)
