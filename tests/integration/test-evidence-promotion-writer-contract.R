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
cat("PASS evidence-promotion writer contract DBI integration (two PostgreSQL sessions)\n")
