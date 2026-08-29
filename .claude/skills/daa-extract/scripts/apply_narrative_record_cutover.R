#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
script_dir <- dirname(script_path)
source(file.path(script_dir, "apply_narrative_record_cutover_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
flags <- c(
  "--mode", "--record-candidates", "--legacy-candidates", "--record-manifest",
  "--legacy-manifest", "--inventory", "--approval", "--receipt", "--nonce",
  "--expected-database-name", "--expected-system-identifier"
)
if (length(args) != length(flags) * 2L ||
    !identical(args[seq(1L, length(args), by = 2L)], flags)) {
  stop(paste("USAGE: apply_narrative_record_cutover.R", paste(flags, "VALUE", collapse = " ")),
       call. = FALSE)
}
values <- as.list(args[seq(2L, length(args), by = 2L)])
names(values) <- sub("^--", "", flags)

repository_root <- normalizePath(file.path(script_dir, "../../../.."))
artifact_paths <- nrk_validate_artifact_paths(c(
  values$`record-candidates`, values$`legacy-candidates`, values$`record-manifest`,
  values$`legacy-manifest`, values$inventory, values$approval
), repository_root)
receipt_path <- nrk_validate_receipt_path(values$receipt, repository_root)

read_raw <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) stop("CUTOVER_ARTIFACT_PATH_INVALID", call. = FALSE)
  connection <- file(path, open = "rb")
  on.exit(close(connection))
  readBin(connection, what = "raw", n = size)
}
artifacts <- list(
  record = read_raw(artifact_paths[[1L]]),
  legacy = read_raw(artifact_paths[[2L]]),
  record_manifest = read_raw(artifact_paths[[3L]]),
  legacy_manifest = read_raw(artifact_paths[[4L]]),
  inventory = read_raw(artifact_paths[[5L]]),
  approval = read_raw(artifact_paths[[6L]])
)

required <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
profile <- Sys.getenv(required, unset = NA_character_)
names(profile) <- required
profile <- nrk_validate_cutover_pg_profile(profile)
connect_cutover_database <- function() DBI::dbConnect(
  RPostgres::Postgres(), dbname = profile$PGDATABASE, host = profile$PGHOST,
  port = as.integer(profile$PGPORT), user = profile$PGUSER,
  password = profile$PGPASSWORD
)
gateway <- nrk_db_cutover_gateway(
  connect_cutover_database(), reconnect_factory = connect_cutover_database
)
on.exit(gateway$disconnect(), add = TRUE)

receipt_publisher <- function(receipt, recover) {
  raw <- .nrk_canonical_receipt_raw(receipt)
  payload <- jsonlite::toJSON(list(files = setNames(list(
    openssl::base64_encode(raw)
  ), .nrk_receipt_name)), auto_unbox = TRUE)
  mode <- if (recover) "recover-bundle-stdin" else "publish-bundle-stdin"
  output <- system2(
    "/usr/bin/python3",
    c(file.path(script_dir, "build_narrative_record_cutover_review.py"),
      "--mode", mode, "--output-dir", dirname(receipt_path)),
    input = payload, stdout = TRUE, stderr = TRUE
  )
  if (!identical(as.integer(attr(output, "status") %||% 0L), 0L)) {
    stop("CUTOVER_RECEIPT_PUBLICATION_FAILED", call. = FALSE)
  }
  invisible(output)
}

result <- nrk_cutover_execute(
  values$mode, artifacts, values$nonce, values$`expected-database-name`,
  values$`expected-system-identifier`, gateway, receipt_publisher
)
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, null = "null"))
