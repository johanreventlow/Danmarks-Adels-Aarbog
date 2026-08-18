#!/usr/bin/env Rscript
## CLI: Rscript apply_phase_a_1939_v50.R --manifest … --manifest-sha256 …
##   --preview-sha256 … --output … [--dry-run]
## Kører authorize→begin_batch→source_evidence×584→finalize→(rollback|commit).
## `--dry-run` slutter ALTID med rollback (aldrig commit). Prod-apply er
## ikke en del af dette program (Global Constraints) — dette script bygger
## og tester blot skrive-værktøjet.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--manifest", "--manifest-sha256", "--preview-sha256", "--output", "--dry-run")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("PHASE_A_1939_CLI_INVALID", call. = FALSE)
required <- c("--manifest", "--manifest-sha256", "--preview-sha256", "--output")
if (any(!required %in% flags)) stop("PHASE_A_1939_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("PHASE_A_1939_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
mode <- if ("--dry-run" %in% flags) "dry-run" else "apply"

output <- value("--output")
if (file.exists(output)) stop("PHASE_A_1939_OUTPUT_EXISTS", call. = FALSE)

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_phase_a_1939_v50_helpers.R"))

manifest_path <- value("--manifest")
manifest_size <- file.info(manifest_path)$size
if (is.na(manifest_size)) stop("PHASE_A_1939_CLI_INVALID", call. = FALSE)
raw <- readBin(manifest_path, "raw", n = manifest_size)
manifest_sha256 <- value("--manifest-sha256")
if (!identical(digest::digest(raw, algo = "sha256", serialize = FALSE), manifest_sha256))
  stop("PHASE_A_1939_MANIFEST_HASH_INVALID", call. = FALSE)
manifest <- jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
preview_sha256 <- value("--preview-sha256")

actor <- Sys.getenv("DAA_REIMPORT_ACTOR_ID")
if (!phase_a_uuid(actor)) stop("PHASE_A_1939_ACTOR_REQUIRED", call. = FALSE)

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
connection_factory <- function() {
  con <- DBI::dbConnect(RPostgres::Postgres(),
    dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
    port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
    password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
    sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable" else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE") else "require",
    bigint = "integer")
  tryCatch({
    DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub',$1,false)", params = list(actor))
    con
  }, error = function(e) { DBI::dbDisconnect(con); stop(conditionMessage(e), call. = FALSE) })
}

result <- execute_phase_a_1939(manifest, preview_sha256, mode, new_phase_a_dbi_gateway(connection_factory))
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), output, useBytes = TRUE)
