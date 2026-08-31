#!/usr/bin/env Rscript

# Precommit integration boundary for #153 Task 4C. Positive publication and
# lock-race cases intentionally run only after this task's committed tree has
# been registered as a V3 deployment.

required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg_values <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg_values) || any(!nzchar(pg_values))) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_ALL_FIVE_PG_VARIABLES_REQUIRED", call. = FALSE)
}
if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("RPostgres", quietly = TRUE)) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_DBI_OR_RPOSTGRES_MISSING", call. = FALSE)
}

con <- DBI::dbConnect(
  RPostgres::Postgres(),
  dbname = pg_values[["PGDATABASE"]],
  host = pg_values[["PGHOST"]],
  port = as.integer(pg_values[["PGPORT"]]),
  user = pg_values[["PGUSER"]],
  password = pg_values[["PGPASSWORD"]]
)
on.exit(DBI::dbDisconnect(con), add = TRUE)

scalar <- function(sql) {
  result <- DBI::dbGetQuery(con, sql)
  if (nrow(result) != 1L || ncol(result) != 1L) {
    stop("SOURCE_SCOPED_EVIDENCE_V3_INTEGRATION_QUERY_SHAPE_INVALID", call. = FALSE)
  }
  result[[1L, 1L]]
}

expect_true <- function(value, code) {
  if (!isTRUE(value)) stop(code, call. = FALSE)
  invisible(TRUE)
}

expect_true(
  identical(
    scalar("SELECT to_regprocedure('public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)')::text"),
    "red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)"
  ),
  "SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZE_SIGNATURE_INVALID"
)
expect_true(
  identical(
    scalar("SELECT to_regprocedure('public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)')::text"),
    "red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)"
  ),
  "SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_PUBLISH_SIGNATURE_INVALID"
)
expect_true(
  isTRUE(scalar("SELECT has_function_privilege('authenticated','public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)','EXECUTE')")) &&
    !isTRUE(scalar("SELECT has_function_privilege('anon','public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)','EXECUTE')")) &&
    !isTRUE(scalar("SELECT has_function_privilege('service_role','public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)','EXECUTE')")),
  "SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_ACL_INVALID"
)
expect_true(
  identical(
    as.integer(scalar("SELECT count(*) FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace WHERE namespace.nspname='public' AND relation.relname=ANY(ARRAY['source_scoped_evidence_visible_fact_ids','source_scoped_evidence_visible_assertion_ids','source_scoped_evidence_visible_citation_ids']) AND relation.relkind='v' AND relation.reloptions @> ARRAY['security_barrier=true']")),
    3L
  ),
  "SOURCE_SCOPED_EVIDENCE_V3_VISIBILITY_VIEW_CONTRACT_INVALID"
)
expect_true(
  is.na(scalar("SELECT to_regprocedure('private.source_scoped_evidence_v3_visibility_allowed(text,bigint)')::text")),
  "SOURCE_SCOPED_EVIDENCE_V3_PRIVATE_STATE_ORACLE_PRESENT"
)

cat("PASS source-scoped evidence V3 precommit integration boundary\n")
