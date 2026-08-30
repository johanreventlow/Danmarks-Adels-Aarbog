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
blocks <- regmatches(
  fixture_sql,
  gregexpr("(?s)DO \\$[^$]+\\$.*?END \\$[^$]+\\$;", fixture_sql, perl = TRUE)
)[[1L]]
if (length(blocks) < 2L) stop("INTEGRATION_FIXTURE_PARSE_FAILED", call. = FALSE)
for (block in blocks) DBI::dbExecute(con, block)

# Preserve the sanitized fixture only for this disposable DBI race. Both worker
# processes use DBI/RPostgres, wait behind the same writer advisory lock, then
# apply the same already-authorized request. Exactly one final batch and two
# byte-identical replay receipts is the race invariant.
DBI::dbExecute(con, "SET daa.evidence_promotion_keep_fixture = 'on'")
for (block in blocks) DBI::dbExecute(con, block)
race <- DBI::dbGetQuery(con, "
  SELECT a.actor_id::text AS actor_id, b.authorization_id::text AS authorization_id,
         b.preview_hash,
         jsonb_agg(jsonb_build_object('interpretation_id',p.interpretation_id,
           'target_type',p.target_type,'target_id',p.target_id)
           ORDER BY p.interpretation_id,p.target_type,p.target_id)::text AS items
    FROM private.interpretation_promotion_batch b
    JOIN private.interpretation_promotion_authorization a ON a.id=b.authorization_id
    JOIN private.interpretation_promotion p ON p.batch_id=b.id
   WHERE b.status='finalized'
   GROUP BY a.actor_id,b.authorization_id,b.preview_hash
   ORDER BY b.authorization_id DESC LIMIT 1
")
if (nrow(race) != 1L) stop("INTEGRATION_RACE_FIXTURE_MISSING", call. = FALSE)
DBI::dbExecute(con, "SELECT pg_advisory_lock(hashtextextended('daa-evidence-promotion-writer',0))")
worker <- function() {
  db <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
    port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
  on.exit(DBI::dbDisconnect(db), add = TRUE)
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
Sys.sleep(0.2)
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
cat("PASS evidence-promotion writer contract DBI integration (barriered concurrent writer replay)\n")
