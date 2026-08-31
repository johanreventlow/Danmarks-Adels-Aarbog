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

if (identical(Sys.getenv("SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT"), "1")) {
  expected_tree_id <- Sys.getenv("SOURCE_SCOPED_EVIDENCE_V3_TREE_ID", unset = "")
  expected_artifact_sha256 <- Sys.getenv(
    "SOURCE_SCOPED_EVIDENCE_V3_ARTIFACT_SHA256",
    unset = ""
  )
  if (!grepl("^[0-9a-f]{40}$", expected_tree_id) ||
      !grepl("^[0-9a-f]{64}$", expected_artifact_sha256)) {
    stop("SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_BINDING_ENV_INVALID", call. = FALSE)
  }
  deployment <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT deployment.id::text,deployment.deployment_sha256,",
      " deployment.repository_tree_id,deployment.repository_writer_artifact_sha256,",
      " deployment.database_name,deployment.system_identifier,",
      " inventory.inventory_result_sha256 ",
      "FROM private.source_scoped_evidence_v3_deployment deployment ",
      "JOIN private.source_scoped_evidence_contract_inventory inventory ",
      "  ON inventory.id=deployment.inventory_id ",
      "WHERE deployment.repository_tree_id=$1 ",
      "  AND deployment.repository_writer_artifact_sha256=$2 ",
      "  AND deployment.database_name=current_database() ",
      "ORDER BY deployment.registered_at DESC,deployment.id DESC"
    ),
    params = list(expected_tree_id, expected_artifact_sha256)
  )
  expect_true(
    nrow(deployment) == 1L &&
      grepl("^[0-9a-f]{64}$", deployment$deployment_sha256[[1L]]) &&
      identical(deployment$repository_tree_id[[1L]], expected_tree_id) &&
      identical(
        deployment$repository_writer_artifact_sha256[[1L]],
        expected_artifact_sha256
      ) &&
      identical(deployment$database_name[[1L]], pg_values[["PGDATABASE"]]) &&
      grepl("^[0-9]+$", deployment$system_identifier[[1L]]) &&
      grepl("^[0-9a-f]{64}$", deployment$inventory_result_sha256[[1L]]),
    "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_DEPLOYMENT_BINDING_INVALID"
  )
  expect_true(
    isTRUE(scalar(
      paste0(
        "SELECT EXISTS (SELECT 1 ",
        "FROM private.source_scoped_evidence_v3_migration_receipt receipt ",
        "WHERE receipt.contract_version='source-scoped-evidence-v3-task4c-v4' ",
        "AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4c_contract_sha256())"
      )
    )),
    "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_RECEIPT_DRIFT"
  )
  cat("PASS source-scoped evidence V3 postcommit deployment binding\n")
}

cat("PASS source-scoped evidence V3 precommit integration boundary\n")
