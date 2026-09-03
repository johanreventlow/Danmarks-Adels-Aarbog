#!/usr/bin/env Rscript
## CLI for the 1939 v50 fase C3 atomic apply gateway.
##
##   Rscript apply_c3_1939_v50.R --mode MODE --manifest PATH --approval PATH \
##       --nonce UUID --actor-id UUID [--batch-id UUID --reversal-nonce UUID]
##
## MODE is one of:
##   gate-read-only     proves the redaktion role gate is open and that the
##                      authorization call still cannot write inside
##                      BEGIN ... READ ONLY. Mutates nothing.
##   preflight          every artefact and database gate, plus a read-only
##                      measurement through the state oracle. Mutates nothing.
##   rehearse-rollback  authorization + the one batch apply + receipt
##                      verification in ONE transaction, then an EXPLICIT
##                      rollback, then a reconnect that proves neither receipt
##                      rows nor domain mutations remain. Intended for a
##                      disposable local database ONLY.
##   apply              WRITES. One transaction, one batch RPC, one commit.
##   status             read-only reconciliation by nonce plus all six hashes.
##   reverse            WRITES. Withdraws an applied batch (its own
##                      authorization artefact, its own nonce).
##
## Connection settings come ONLY from the all-five-or-none PG environment
## contract (PGDATABASE/PGHOST/PGPORT/PGUSER/PGPASSWORD together, or none of
## them and the SUPABASE_* fallback instead). Nothing is configurable on the
## command line, so a rehearsal can never be pointed at production by a typo.
##
## Only counts, IDs and hashes are ever printed. Narrative prose reaches the
## database as an authorization parameter and never touches stdout/stderr.
##
## If `apply` reports `outcome=not_committed` (exit 2), the transaction was
## proven NOT to have committed and nothing was consumed. Retry by re-running
## `--mode apply` with THE SAME `--nonce`: authorize compares all six hashes on
## nonce replay, so the same nonce keeps the retry idempotent and keeps a later
## `--mode status` on that nonce meaningful. A fresh nonce would also fail
## closed, but it discards the handle reconciliation is read through.
## `outcome=reversed` means the batch was deliberately withdrawn -- not a
## failure, and never something to retry. The terminal token
## C3_APPLY_COMMIT_UNKNOWN means manual audit, never an automatic retry.

.c3_apply_main <- function() {
  script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
  script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
  source(file.path(script_dir, "c3_export_shared_1939_v50_helpers.R"))
  source(file.path(script_dir, "apply_c3_1939_v50_helpers.R"))

  parsed <- c3_apply_parse_args(commandArgs(trailingOnly = TRUE))
  manifest_raw <- .c3_common_read_regular_raw(parsed$manifest,
                                              "C3_APPLY_MANIFEST_UNREADABLE")
  approval_raw <- .c3_common_read_regular_raw(parsed$approval,
                                              "C3_APPLY_APPROVAL_UNREADABLE")
  ## Every artefact gate runs BEFORE a connection is ever opened.
  bundle <- build_c3_apply_authorization(manifest_raw, approval_raw)

  connection_values <- c3_apply_pg_connection_values()
  ## A fresh connection per call, and one per session the mode needs. That is
  ## what guarantees no leftover app.change_set_id can be carried into
  ## red_apply_reimport_cases, which fails closed on exactly that
  ## (REIMPORT_CASE_FOREIGN_CHANGE_SET). This gateway opens no change set of
  ## its own at any point.
  connect <- function() {
    con <- tryCatch(
      DBI::dbConnect(
        RPostgres::Postgres(), dbname = connection_values$dbname,
        host = connection_values$host, port = connection_values$port,
        user = connection_values$user, password = connection_values$password,
        sslmode = if (connection_values$local) "disable" else {
          sslmode <- Sys.getenv("SUPABASE_SSLMODE")
          if (nzchar(sslmode)) sslmode else "require"
        },
        bigint = "integer"
      ),
      error = function(e) .c3_common_stop("C3_APPLY_DATABASE_CONNECT_FAILED"))
    list(
      query = function(sql, params = NULL) {
        if (is.null(params) || !length(params)) DBI::dbGetQuery(con, sql)
        else DBI::dbGetQuery(con, sql, params = params)
      },
      execute = function(sql, params = NULL) {
        if (is.null(params) || !length(params)) DBI::dbExecute(con, sql)
        else DBI::dbExecute(con, sql, params = params)
        invisible(NULL)
      },
      close = function() invisible(try(DBI::dbDisconnect(con), silent = TRUE))
    )
  }

  result <- c3_apply_run(parsed$mode, bundle, parsed, connect)
  cat(result$summary, "\n", sep = "")
  ## A non-committed apply is a legitimate, safe answer -- but never a
  ## success: exit non-zero so a supervising script cannot read it as one.
  if (identical(parsed$mode, "apply") &&
      !identical(result$outcome, "applied") &&
      !identical(result$outcome, "committed"))
    return(2L)
  0L
}

.c3_apply_status <- tryCatch(
  .c3_apply_main(),
  error = function(error) {
    token <- conditionMessage(error)
    if (!grepl("^C3_APPLY_[A-Z0-9_]+$", token)) token <- "C3_APPLY_INTERNAL_ERROR"
    cat(token, "\n", sep = "", file = stderr())
    1L
  }
)
quit(save = "no", status = .c3_apply_status)
