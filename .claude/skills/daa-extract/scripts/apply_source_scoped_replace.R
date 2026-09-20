#!/usr/bin/env Rscript
## Gateway for the source-scoped replace RPCs.  It never writes model tables.

source("apply_source_scoped_replace_helpers.R")

ssr_json <- function(value) jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA)

ssr_db_identity <- function(con) {
  row <- DBI::dbGetQuery(con,
    "SELECT current_database() AS database_name, system_identifier::text AS system_identifier FROM pg_control_system()")
  if (nrow(row) != 1L) stop("SOURCE_SCOPED_REPLACE_DATABASE_IDENTITY_INVALID", call. = FALSE)
  list(database_name = as.character(row$database_name[[1]]), system_identifier = as.character(row$system_identifier[[1]]))
}

ssr_fetch_receipt <- function(connection_factory, authorization_id) {
  con <- connection_factory()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- DBI::dbGetQuery(con,
    "SELECT public.red_verify_source_scoped_replace($1) AS result", params = list(authorization_id))
  if (nrow(row) != 1L) stop("SOURCE_SCOPED_REPLACE_RECEIPT_NOT_FOUND", call. = FALSE)
  jsonlite::fromJSON(as.character(row$result[[1]]), simplifyVector = FALSE)
}

ssr_apply_manifest <- function(manifest, actor_id, nonce, expires_at, connection_factory) {
  manifest <- ssr_validate_manifest(manifest)
  con <- connection_factory()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "BEGIN READ ONLY")
  identity <- tryCatch(ssr_db_identity(con), finally = DBI::dbExecute(con, "ROLLBACK"))
  profile <- ssr_profile(manifest, identity)

  DBI::dbExecute(con, "BEGIN")
  DBI::dbExecute(con, "SET LOCAL lock_timeout = '5s'")
  DBI::dbExecute(con, "SET LOCAL statement_timeout = '30s'")
  authorization <- DBI::dbGetQuery(con,
    "SELECT public.red_authorize_source_scoped_replace($1,$2,$3::uuid,$4::uuid,$5::jsonb,$6,$7,$8::timestamptz) AS id",
    params = list(identity$database_name, identity$system_identifier, actor_id, nonce, ssr_json(manifest),
                  manifest$dry_run_sha256, manifest$ownership_sha256, expires_at))
  if (nrow(authorization) != 1L) stop("SOURCE_SCOPED_REPLACE_AUTHORIZATION_MISSING", call. = FALSE)
  authorization_id <- as.character(authorization$id[[1]])
  DBI::dbExecute(con, "COMMIT")

  DBI::dbExecute(con, "BEGIN")
  DBI::dbExecute(con, "SET LOCAL lock_timeout = '5s'")
  DBI::dbExecute(con, "SET LOCAL statement_timeout = '30s'")
  apply_error <- NULL
  tryCatch({
    DBI::dbGetQuery(con, "SELECT public.red_apply_source_scoped_replace($1::uuid,$2::jsonb) AS receipt",
      params = list(authorization_id, ssr_json(manifest)))
    DBI::dbExecute(con, "COMMIT")
  }, error = function(error) {
    apply_error <<- error
    try(DBI::dbExecute(con, "ROLLBACK"), silent = TRUE)
  })
  # A lost commit acknowledgement is reconciled only from a new connection.
  receipt <- tryCatch(ssr_fetch_receipt(connection_factory, authorization_id), error = function(error) NULL)
  if (is.null(receipt)) {
    if (!is.null(apply_error)) stop(conditionMessage(apply_error), call. = FALSE)
    stop("SOURCE_SCOPED_REPLACE_RECEIPT_NOT_FOUND", call. = FALSE)
  }
  if (!identical(receipt$receipt$terminal_status, "committed") ||
      !is.character(receipt$receipt$manifest_sha256) || length(receipt$receipt$manifest_sha256) != 1L ||
      !grepl("^[0-9a-f]{64}$", receipt$receipt$manifest_sha256))
    stop("SOURCE_SCOPED_REPLACE_TERMINAL_RECEIPT_INVALID", call. = FALSE)
  list(authorization_id = authorization_id, profile = profile, receipt = receipt)
}
