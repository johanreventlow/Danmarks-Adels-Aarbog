#!/usr/bin/env Rscript

# #153 Task 4C: prove that the documented RLS runner is atomic.  The RLS file
# deliberately remains composable inside existing SQL test transactions, so
# this integration test owns the outer psql --single-transaction boundary.

required_pg <- c("PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGDATABASE")
pg_values <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg_values) || any(!nzchar(pg_values))) {
  stop(
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_ALL_FIVE_PG_VARIABLES_REQUIRED: ",
    paste(required_pg, collapse = ", "),
    call. = FALSE
  )
}

`%||%` <- function(value, fallback) {
  if (is.null(value)) fallback else value
}

root <- normalizePath(".")
if (!file.exists(file.path(root, "schema.sql")) ||
    !file.exists(file.path(root, "db-rls.sql"))) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_REPOSITORY_ROOT_REQUIRED", call. = FALSE)
}

psql <- Sys.which("psql")
if (!nzchar(psql) && file.exists("/opt/homebrew/opt/postgresql@17/bin/psql")) {
  psql <- "/opt/homebrew/opt/postgresql@17/bin/psql"
}
if (!nzchar(psql) || !file.exists(psql)) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_PSQL_REQUIRED", call. = FALSE)
}

database_name <- paste0("daa153_rls_atomic_", Sys.getpid())
if (!grepl("^[a-z0-9_]+$", database_name)) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_DATABASE_NAME_INVALID", call. = FALSE)
}

connection_args <- c(
  "-X", "-h", pg_values[["PGHOST"]], "-p", pg_values[["PGPORT"]],
  "-U", pg_values[["PGUSER"]]
)
child_env <- paste0("PGPASSWORD=", pg_values[["PGPASSWORD"]])

run_psql <- function(database, sql = NULL, file = NULL, single_transaction = FALSE,
                     tuples_only = FALSE) {
  if (!xor(!is.null(sql), !is.null(file))) {
    stop("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_QUERY_SHAPE_INVALID", call. = FALSE)
  }
  args <- c(connection_args, "-d", database, "-v", "ON_ERROR_STOP=1")
  if (tuples_only) args <- c(args, "-tA")
  if (single_transaction) args <- c(args, "--single-transaction")
  if (!is.null(sql)) args <- c(args, "-c", shQuote(sql))
  if (!is.null(file)) args <- c(args, "-f", file)
  output <- suppressWarnings(
    system2(psql, args, stdout = TRUE, stderr = TRUE, env = child_env)
  )
  list(status = attr(output, "status") %||% 0L, output = output)
}

fail <- function(code, detail = NULL) {
  if (!is.null(detail) && length(detail)) {
    stop(paste(code, paste(detail, collapse = "\n"), sep = ": "), call. = FALSE)
  }
  stop(code, call. = FALSE)
}

expect_success <- function(result, code) {
  if (!identical(result$status, 0L)) fail(code, result$output)
  invisible(result)
}

scalar <- function(database, sql, code) {
  result <- expect_success(run_psql(database, sql = sql, tuples_only = TRUE), code)
  trimws(paste(result$output, collapse = "\n"))
}

cleanup_status <- NA_integer_

main <- function() {
  database_created <- FALSE
  drop_disposable_database <- function() {
    if (!database_created) return(invisible(NULL))
    result <- run_psql(
      "postgres",
      sql = paste0("DROP DATABASE IF EXISTS ", database_name, " WITH (FORCE)")
    )
    cleanup_status <<- result$status
    if (!identical(result$status, 0L)) {
      fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_CLEANUP_FAILED", result$output)
    }
    database_created <<- FALSE
    invisible(NULL)
  }
  on.exit(drop_disposable_database(), add = TRUE)

  expect_success(
    run_psql("postgres", sql = paste0("CREATE DATABASE ", database_name)),
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_CREATE_DATABASE_FAILED"
  )
  database_created <- TRUE
  expect_success(
    run_psql(database_name, file = file.path(root, "tests/sql/evidence-promotion-bootstrap.sql")),
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_BOOTSTRAP_FAILED"
  )
  expect_success(
    run_psql(
      database_name,
      sql = "CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions"
    ),
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_DBLINK_BOOTSTRAP_FAILED"
  )
  expect_success(
    run_psql(database_name, file = file.path(root, "schema.sql")),
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_SCHEMA_FAILED"
  )

  run_rls <- function() {
    run_psql(
      database_name,
      file = file.path(root, "db-rls.sql"),
      single_transaction = TRUE
    )
  }

  expect_success(run_rls(), "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_FRESH_APPLY_FAILED")
  receipt_query <- paste0(
    "SELECT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt ",
    "WHERE receipt.contract_version='source-scoped-evidence-v3-task4c-v7' ",
    "AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4c_contract_sha256())"
  )
  if (!identical(scalar(database_name, receipt_query,
                        "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_RECEIPT_QUERY_FAILED"), "t")) {
    fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_FRESH_RECEIPT_INVALID")
  }
  expect_success(run_rls(), "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_RERUN_FAILED")

  task4c_acl_query <- paste0(
    "SELECT coalesce(proacl,acldefault('f',proowner))::text FROM pg_proc ",
    "WHERE oid='public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)'::regprocedure"
  )
  task4c_acl_before <- scalar(
    database_name, task4c_acl_query,
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_ACL_QUERY_FAILED"
  )

  expect_success(
    run_psql(
      database_name,
      sql = "DROP FUNCTION public.red_activate_1939_v50_batch(uuid,uuid)"
    ),
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_FAULT_SETUP_FAILED"
  )
  fault_result <- run_rls()
  if (identical(fault_result$status, 0L) || !any(grepl(
    "RLS_REDACTION_RPC_ALLOW_LIST_SIGNATURE_MISSING", fault_result$output, fixed = TRUE
  ))) {
    fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_FAULT_NOT_OBSERVED", fault_result$output)
  }
  if (!identical(scalar(database_name, receipt_query,
                        "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_RECEIPT_RECHECK_FAILED"), "t")) {
    fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_RECEIPT_ROLLBACK_INVALID")
  }
  task4c_acl_after <- scalar(
    database_name, task4c_acl_query,
    "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_ACL_RECHECK_FAILED"
  )
  if (!identical(task4c_acl_after, task4c_acl_before)) {
    fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_ACL_ROLLBACK_INVALID")
  }
  invisible(NULL)
}

main()
if (!identical(cleanup_status, 0L)) {
  fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_CLEANUP_STATUS_INVALID")
}
if (!identical(scalar(
  "postgres",
  paste0("SELECT NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='", database_name, "')"),
  "SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_CLEANUP_QUERY_FAILED"
), "t")) {
  fail("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_CLEANUP_OWNERSHIP_INVALID")
}
cat("SOURCE_SCOPED_EVIDENCE_V3_RLS_ATOMIC_PASS\n")
