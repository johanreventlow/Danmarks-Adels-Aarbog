required <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
if (any(is.na(Sys.getenv(required, unset = NA_character_)))) stop("PG_PROFILE_INCOMPLETE", call. = FALSE)
if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RPostgres", quietly = TRUE)) {
  stop("DBI_OR_RPOSTGRES_MISSING", call. = FALSE)
}

con <- DBI::dbConnect(
  RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
  port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD")
)
on.exit(DBI::dbDisconnect(con), add = TRUE)
con2 <- DBI::dbConnect(
  RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
  port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD")
)
on.exit(DBI::dbDisconnect(con2), add = TRUE)

scalar <- function(sql) {
  value <- DBI::dbGetQuery(con, sql)
  if (nrow(value) != 1L || ncol(value) != 1L) stop("INTEGRATION_SHAPE_INVALID", call. = FALSE)
  value[[1L, 1L]]
}

stopifnot(
  identical(scalar("SELECT to_regclass('private.interpretation_promotion_authorization')::text"),
            "private.interpretation_promotion_authorization"),
  identical(scalar("SELECT to_regprocedure('public.red_authorize_interpretation_promotions(jsonb,text,uuid,timestamptz)')::text"),
            "red_authorize_interpretation_promotions(jsonb,text,uuid,timestamp with time zone)"),
  identical(scalar("SELECT to_regprocedure('public.red_promote_interpretations_batch(jsonb,text,uuid)')::text"),
            "red_promote_interpretations_batch(jsonb,text,uuid)"),
  !isTRUE(scalar("SELECT has_table_privilege('authenticated','private.interpretation_promotion_authorization','SELECT')")),
  !isTRUE(scalar("SELECT has_table_privilege('anon','private.interpretation_promotion_batch','SELECT')")),
  isTRUE(scalar("SELECT has_function_privilege('authenticated','public.red_authorize_interpretation_promotions(jsonb,text,uuid,timestamptz)','EXECUTE')")),
  !isTRUE(scalar("SELECT has_function_privilege('anon','public.red_promote_interpretations_batch(jsonb,text,uuid)','EXECUTE')"))
)

pid1 <- scalar("SELECT pg_backend_pid()")
pid2 <- DBI::dbGetQuery(con2, "SELECT pg_backend_pid()")[[1L, 1L]]
if (identical(pid1, pid2)) stop("INTEGRATION_SECOND_SESSION_MISSING", call. = FALSE)

# The SQL fixture is deliberately executed through this DBI integration entry
# point: it creates sanitized actor/evidence fixtures, calls preview ->
# authorize -> apply, checks the closed receipt, and rolls all synthetic data
# back. It is the same disposable database used by this R process; no catalog-
# only substitute is accepted here.
fixture <- Sys.getenv(
  "DAA_EVIDENCE_PROMOTION_SQL_TEST",
  unset = "tests/sql/test-evidence-promotion.sql"
)
if (!file.exists(fixture)) stop("INTEGRATION_FIXTURE_MISSING", call. = FALSE)
fixture_sql <- paste(readLines(fixture, warn = FALSE), collapse = "\n")
migration_lines <- readLines("db-migrations.sql", warn = FALSE)
migration_start <- grep("^-- #153 Task 3:", migration_lines)[1L]
migration_end <- grep("^CREATE OR REPLACE FUNCTION private\\.interpretation_promotion_profile", migration_lines)
migration_end <- migration_end[migration_end > migration_start][1L] - 1L
if (is.na(migration_start) || is.na(migration_end) ||
    any(trimws(migration_lines[migration_start:migration_end]) %in% c("BEGIN;", "COMMIT;"))) {
  stop("INTEGRATION_MIGRATION_NESTED_TRANSACTION", call. = FALSE)
}
blocks <- regmatches(
  fixture_sql,
  gregexpr("(?s)DO \\$[^$]+\\$.*?END \\$[^$]+\\$;", fixture_sql, perl = TRUE)
)[[1L]]
if (length(blocks) < 2L) stop("INTEGRATION_FIXTURE_PARSE_FAILED", call. = FALSE)
for (block in blocks) DBI::dbExecute(con, block)

# Preserve a sanitized, *issued* authorization only for this disposable DBI
# race. Both workers use DBI/RPostgres, wait behind the writer lock, then race
# through apply/finalize. The first finalizes; the second can only return that
# newly-created receipt.
DBI::dbExecute(con, "SET daa.evidence_promotion_keep_fixture = 'on'")
DBI::dbExecute(con, "SET daa.evidence_promotion_race_issued = 'on'")
for (block in blocks) DBI::dbExecute(con, block)
race <- DBI::dbGetQuery(con, "
  SELECT a.actor_id::text AS actor_id, a.id::text AS authorization_id,
         a.preview_hash,
         jsonb_build_array(jsonb_build_object('interpretation_id',i.id,
           'target_type','assertion','target_id',-987650091))::text AS items
    FROM private.interpretation_promotion_authorization a
    JOIN private.interpretation i ON i.source_id=-987650091 AND i.status='accepted'
   WHERE a.nonce='91000000-0000-0000-0000-000000000091'
     AND a.status='issued'
   ORDER BY a.issued_at DESC LIMIT 1
")
if (nrow(race) != 1L) stop("INTEGRATION_RACE_FIXTURE_MISSING", call. = FALSE)
pre_final <- DBI::dbGetQuery(con, sprintf(
  "SELECT count(*) AS n FROM private.interpretation_promotion_batch WHERE authorization_id=%s::uuid",
  DBI::dbQuoteString(con, race$authorization_id[[1L]])
))$n[[1L]]
if (!identical(as.integer(pre_final), 0L)) stop("INTEGRATION_RACE_ALREADY_FINALIZED", call. = FALSE)
DBI::dbExecute(con, "SELECT pg_advisory_lock(hashtextextended('daa-evidence-promotion-writer',0))")
worker <- function() {
  db <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
    port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
  on.exit(DBI::dbDisconnect(db), add = TRUE)
  DBI::dbExecute(db, "SET application_name = 'daa-evidence-promotion-writer-race'")
  DBI::dbExecute(db, "BEGIN")
  on.exit(try(DBI::dbExecute(db, "ROLLBACK"), silent = TRUE), add = TRUE)
  DBI::dbExecute(db, "SET LOCAL ROLE authenticated")
  DBI::dbExecute(db, sprintf("SELECT set_config('request.jwt.claim.sub', %s, true)", DBI::dbQuoteString(db, race$actor_id[[1L]])))
  out <- DBI::dbGetQuery(db, sprintf(
    "SELECT public.red_promote_interpretations_batch(%s::jsonb,%s,%s::uuid)::text AS receipt",
    DBI::dbQuoteString(db, race$items[[1L]]), DBI::dbQuoteString(db, race$preview_hash[[1L]]),
    DBI::dbQuoteString(db, race$authorization_id[[1L]])
  ))$receipt[[1L]]
  DBI::dbExecute(db, "COMMIT")
  out
}
jobs <- list(parallel::mcparallel(worker()), parallel::mcparallel(worker()))
ready <- data.frame()
for (attempt in seq_len(100L)) {
  ready <- DBI::dbGetQuery(con, "
    SELECT activity.pid, activity.wait_event_type, activity.wait_event,
           waiting.classid, waiting.objid, holder.pid AS holder_pid
      FROM pg_stat_activity activity
      JOIN pg_locks waiting ON waiting.pid=activity.pid
      JOIN pg_locks holder ON holder.locktype='advisory' AND holder.granted
        AND holder.pid=pg_backend_pid()
        AND holder.classid=waiting.classid AND holder.objid=waiting.objid
     WHERE activity.application_name='daa-evidence-promotion-writer-race'
       AND waiting.locktype='advisory' AND NOT waiting.granted
     ORDER BY activity.pid
  ")
  if (nrow(ready) == 2L && length(unique(ready$pid)) == 2L &&
      all(ready$wait_event_type == "Lock") && all(ready$wait_event == "advisory") &&
      all(ready$holder_pid == pid1) && length(unique(paste(ready$classid, ready$objid))) == 1L) break
  Sys.sleep(0.05)
}
if (nrow(ready) != 2L || length(unique(ready$pid)) != 2L ||
    !all(ready$wait_event_type == "Lock") || !all(ready$wait_event == "advisory") ||
    !all(ready$holder_pid == pid1) || length(unique(paste(ready$classid, ready$objid))) != 1L) {
  DBI::dbExecute(con, "SELECT pg_advisory_unlock(hashtextextended('daa-evidence-promotion-writer',0))")
  parallel::mccollect(jobs, wait = TRUE)
  stop("INTEGRATION_WRITER_RACE_BARRIER_NOT_READY", call. = FALSE)
}
DBI::dbExecute(con, "SELECT pg_advisory_unlock(hashtextextended('daa-evidence-promotion-writer',0))")
receipts <- unlist(parallel::mccollect(jobs), use.names = FALSE)
if (length(receipts) != 2L || !identical(receipts[[1L]], receipts[[2L]])) {
  stop("INTEGRATION_WRITER_RACE_RECEIPT_MISMATCH", call. = FALSE)
}
final <- DBI::dbGetQuery(con, sprintf(
  "SELECT count(*) AS n FROM private.interpretation_promotion_batch WHERE authorization_id=%s::uuid AND status='finalized'",
  DBI::dbQuoteString(con, race$authorization_id[[1L]])
))$n[[1L]]
if (!identical(as.integer(final), 1L)) stop("INTEGRATION_WRITER_RACE_PARTIAL_STATE", call. = FALSE)
promotions <- DBI::dbGetQuery(con, sprintf(
  "SELECT count(*) AS n FROM private.interpretation_promotion p JOIN private.interpretation_promotion_batch b ON b.id=p.batch_id WHERE b.authorization_id=%s::uuid",
  DBI::dbQuoteString(con, race$authorization_id[[1L]])
))$n[[1L]]
if (!identical(as.integer(promotions), 1L)) stop("INTEGRATION_WRITER_RACE_PROMOTION_PARTIAL_STATE", call. = FALSE)
cat(sprintf(
  "PASS evidence-promotion writer contract DBI integration (barriered issued-authority finalize race; worker_pids=%s; advisory_key=%s/%s)\n",
  paste(ready$pid, collapse = ","), ready$classid[[1L]], ready$objid[[1L]]
))
