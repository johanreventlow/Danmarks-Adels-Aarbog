#!/usr/bin/env Rscript

# #153 Task 4C: precommit contract assertions and an opt-in, deployment-bound
# publication proof.  The latter only runs against a fresh local disposable DB.

required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg) || any(!nzchar(pg))) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_ALL_FIVE_PG_VARIABLES_REQUIRED", call. = FALSE)
}
if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("RPostgres", quietly = TRUE)) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_DBI_OR_RPOSTGRES_MISSING", call. = FALSE)
}

con <- DBI::dbConnect(RPostgres::Postgres(), dbname = pg[["PGDATABASE"]],
                      host = pg[["PGHOST"]], port = as.integer(pg[["PGPORT"]]),
                      user = pg[["PGUSER"]], password = pg[["PGPASSWORD"]])
on.exit(DBI::dbDisconnect(con), add = TRUE)

scalar <- function(sql) {
  value <- DBI::dbGetQuery(con, sql)
  if (nrow(value) != 1L || ncol(value) != 1L) {
    stop("SOURCE_SCOPED_EVIDENCE_V3_INTEGRATION_QUERY_SHAPE_INVALID", call. = FALSE)
  }
  value[[1L, 1L]]
}
expect_true <- function(value, code) {
  if (!isTRUE(value)) stop(code, call. = FALSE)
  invisible(TRUE)
}
execute <- function(sql, params = NULL) DBI::dbExecute(con, sql, params = params)
expect_db_error <- function(code, operation) {
  execute("SAVEPOINT source_scoped_evidence_v3_expected_error")
  result <- suppressWarnings(try(operation(), silent = TRUE))
  suppressWarnings(execute("ROLLBACK TO SAVEPOINT source_scoped_evidence_v3_expected_error"))
  if (!inherits(result, "try-error") || !grepl(code, as.character(result), fixed = TRUE)) {
    stop(paste0("SOURCE_SCOPED_EVIDENCE_V3_EXPECTED_ERROR_MISSING: ", code), call. = FALSE)
  }
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
  identical(as.integer(scalar("SELECT count(*) FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace WHERE namespace.nspname='public' AND relation.relname=ANY(ARRAY['source_scoped_evidence_visible_fact_ids','source_scoped_evidence_visible_assertion_ids','source_scoped_evidence_visible_citation_ids']) AND relation.relkind='v' AND relation.reloptions @> ARRAY['security_barrier=true']")), 3L),
  "SOURCE_SCOPED_EVIDENCE_V3_VISIBILITY_VIEW_CONTRACT_INVALID"
)
expect_true(
  is.na(scalar("SELECT to_regprocedure('private.source_scoped_evidence_v3_visibility_allowed(text,bigint)')::text")),
  "SOURCE_SCOPED_EVIDENCE_V3_PRIVATE_STATE_ORACLE_PRESENT"
)

if (identical(Sys.getenv("SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT"), "1")) {
  tree_id <- Sys.getenv("SOURCE_SCOPED_EVIDENCE_V3_TREE_ID", unset = "")
  artifact_sha256 <- Sys.getenv("SOURCE_SCOPED_EVIDENCE_V3_ARTIFACT_SHA256", unset = "")
  if (!grepl("^[0-9a-f]{40}$", tree_id) || !grepl("^[0-9a-f]{64}$", artifact_sha256)) {
    stop("SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_BINDING_ENV_INVALID", call. = FALSE)
  }
  deployment <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT deployment.id::text,deployment.deployment_sha256,",
      "deployment.repository_tree_id,deployment.repository_writer_artifact_sha256,",
      "deployment.database_name,deployment.system_identifier,inventory.inventory_result_sha256 ",
      "FROM private.source_scoped_evidence_v3_deployment deployment ",
      "JOIN private.source_scoped_evidence_contract_inventory inventory ON inventory.id=deployment.inventory_id ",
      "WHERE deployment.repository_tree_id=$1 AND deployment.repository_writer_artifact_sha256=$2 ",
      "AND deployment.database_name=current_database() ORDER BY deployment.registered_at DESC,deployment.id DESC"
    ), params = list(tree_id, artifact_sha256)
  )
  expect_true(
    nrow(deployment) == 1L && grepl("^[0-9a-f]{64}$", deployment$deployment_sha256[[1L]]) &&
      identical(deployment$repository_tree_id[[1L]], tree_id) &&
      identical(deployment$repository_writer_artifact_sha256[[1L]], artifact_sha256) &&
      identical(deployment$database_name[[1L]], pg[["PGDATABASE"]]) &&
      grepl("^[0-9]+$", deployment$system_identifier[[1L]]) &&
      grepl("^[0-9a-f]{64}$", deployment$inventory_result_sha256[[1L]]),
    "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_DEPLOYMENT_BINDING_INVALID"
  )
  expect_true(
    isTRUE(scalar("SELECT EXISTS (SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt WHERE receipt.contract_version='source-scoped-evidence-v3-task4c-v7' AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4c_contract_sha256())")),
    "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_RECEIPT_DRIFT"
  )
  expect_true(
    grepl("(task4c|test|ci|disposable)", pg[["PGDATABASE"]], ignore.case = TRUE) &&
      pg[["PGHOST"]] %in% c("127.0.0.1", "localhost", "/tmp"),
    "SOURCE_SCOPED_EVIDENCE_V3_DISPOSABLE_LOCAL_DATABASE_REQUIRED"
  )

  actor <- "00000000-0000-0000-0000-000000153401"
  ids <- list(
    run = "00000000-0000-0000-0000-000000153402",
    rendition = "00000000-0000-0000-0000-000000153403",
    record = "00000000-0000-0000-0000-000000153404",
    occurrence = "00000000-0000-0000-0000-000000153405",
    observation = "00000000-0000-0000-0000-000000153406",
    persona = "00000000-0000-0000-0000-000000153407",
    record_placement = "00000000-0000-0000-0000-000000153408",
    persona_placement = "00000000-0000-0000-0000-000000153409",
    chain = "00000000-0000-0000-0000-000000153410",
    revision = "00000000-0000-0000-0000-000000153411",
    mention = "00000000-0000-0000-0000-000000153412",
    identity_event = "00000000-0000-0000-0000-000000153413"
  )
  source_id <- -9153401L
  person_id <- -9153401L
  fact_id <- -9153402L
  assertion_id <- -9153403L
  citation_id <- -9153404L

  DBI::dbBegin(con)
  execute("INSERT INTO auth.users(id,email) VALUES($1,$2)", list(actor, "task4c-postcommit@example.invalid"))
  execute("INSERT INTO public.profiles(id,rolle) VALUES($1,'redaktion')", list(actor))
  execute("INSERT INTO public.person(id,levende,privat,staged,visning_navn) VALUES($1,false,false,false,'Task 4C postcommit')", list(person_id))
  execute("INSERT INTO public.source(id,slags,titel,udgave,aar,import_key) VALUES($1,'DAA-udgave','Task 4C postcommit','synthetic',1939,'task4c-postcommit')", list(source_id))
  execute("INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,$2,'task4c','1','task4c','task4c',repeat('1',64),'{}')", list(ids$run, source_id))
  execute("INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES($1,$2,'task4c','text_layer',repeat('2',64),'{}')", list(ids$rendition, source_id))
  execute("INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES($1,'Task 4C','Task 4C','task4c')", list(source_id))
  execute("INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES($1,$1,$1,'stamtavle','Task 4C')", list(source_id))
  execute("INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES($1,$1,$1,'A','Task 4C',1)", list(source_id))
  execute("INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES($1,$2,'task4c-record','person',$3)", list(ids$record, source_id, ids$run))
  execute("INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,$2,'task4c',1,1,0,10,'Task 4C','task4c-physical','task4c-structural',$3)", list(ids$occurrence, ids$rendition, ids$run))
  execute("INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2,'accepted',jsonb_build_object('basis','task4c'),1,$3,'Task 4C')", list(ids$occurrence, ids$record, actor))
  execute("INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,$2,'header',1,1,0,10,'Task 4C','clear','task4c',$3)", list(ids$observation, ids$occurrence, ids$run))
  execute("INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES($1,$2,'task4c-persona',$3)", list(ids$persona, source_id, ids$run))
  execute("INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) VALUES($1,$2,'person_name',0,4,'Task',$3)", list(ids$mention, ids$observation, ids$run))
  execute("INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES($1,$2,'primary',1)", list(ids$persona, ids$mention))
  execute("INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status) VALUES($1,$2,$3,$4,'accepted')", list(ids$record_placement, ids$record, source_id, ids$observation))
  execute("INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES($1,1,'accepted',jsonb_build_object('basis','task4c'),'migration','Task 4C')", list(ids$record_placement))
  execute("INSERT INTO private.source_persona_placement(id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status) VALUES($1,$2,$3,'principal_member',$4,'accepted')", list(ids$persona_placement, ids$persona, ids$record_placement, ids$observation))
  execute("INSERT INTO private.source_persona_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES($1,1,'accepted',jsonb_build_object('basis','task4c'),'migration','Task 4C')", list(ids$persona_placement))
  execute("INSERT INTO private.source_persona_identity_event(id,source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) VALUES($1,$2,$3,'accepted',1,jsonb_build_object('basis','task4c'),$4,'Task 4C',transaction_timestamp())", list(ids$identity_event, ids$persona, person_id, actor))
  execute("INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) VALUES($1,$2,'accepted',1,jsonb_build_object('basis','task4c'),$3,'Task 4C',transaction_timestamp())", list(ids$persona, person_id, actor))
  execute("INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES($1,'person',$2,'fixture')", list(fact_id, person_id))
  execute("INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst) VALUES($1,'fact',$2,'fixture')", list(assertion_id, fact_id))
  execute("INSERT INTO public.citation(id,assertion_id,source_id,side) VALUES($1,$2,$3,'1')", list(citation_id, assertion_id, source_id))
  execute("INSERT INTO private.source_scoped_evidence_v3_chain(id,source_id,source_record_id,source_record_key,source_persona_id,canonical_person_id,chain_key) VALUES($1,$2,$3,'task4c-record',$4,$5,repeat('4',64))", list(ids$chain, source_id, ids$record, ids$persona, person_id))
  execute("INSERT INTO private.source_scoped_evidence_v3_revision(id,chain_id,revision,fact_id,revision_kind,chain_sha256,manifest_semantic_sha256) VALUES($1,$2,1,$3,'content',repeat('5',64),repeat('6',64))", list(ids$revision, ids$chain, fact_id))
  execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,fact_id) VALUES($1,'fact','fact',$2)", list(ids$revision, fact_id))
  execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,assertion_id) VALUES($1,'assertion','assertion',$2)", list(ids$revision, assertion_id))
  execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,citation_id) VALUES($1,'citation','citation',$2)", list(ids$revision, citation_id))
  created_event <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,after_state_sha256,revision_id) VALUES($1,$2,'source_revision_created',private.source_scoped_evidence_v3_chain_state_sha256($2,$3,NULL,1,$1),$3)", list(created_event, ids$chain, ids$revision))
  state_hash <- DBI::dbGetQuery(con, "SELECT state_sha256 FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=$1", params = list(ids$chain))$state_sha256[[1L]]
  eligible_event <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
  eligible_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,NULL,2,$3) AS hash", params = list(ids$chain, ids$revision, eligible_event))$hash[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'eligible',$3,$4,$5)", list(eligible_event, ids$chain, state_hash, eligible_hash, ids$revision))
  execute("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))
  payload <- paste0('{"schema":"source-scoped-evidence-v3-publication-decision-v1","chain_id":"', ids$chain, '","revision_id":"', ids$revision, '","deployment_id":"', deployment$id[[1L]], '","deployment_sha256":"', deployment$deployment_sha256[[1L]], '","expected_state_sha256":"', eligible_hash, '","decision":"publish","rationale":"Task 4C postcommit"}')
  authorize <- function(chain_id, revision_id, deployment_id, state_hash, decision_payload, nonce, expiry = "clock_timestamp()+interval '5 minutes'") {
    DBI::dbGetQuery(con, paste0("SELECT public.red_authorize_source_scoped_evidence_publication_v3($1,$2,$3,$4,$5::jsonb,$6,", expiry, ")::text AS id"), params = list(chain_id, revision_id, deployment_id, state_hash, decision_payload, nonce))$id[[1L]]
  }
  authorize_attempt <- function(chain_id, revision_id, deployment_id, state_hash, decision_payload, nonce, expiry = "clock_timestamp()+interval '5 minutes'") {
    execute(paste0("SELECT public.red_authorize_source_scoped_evidence_publication_v3($1,$2,$3,$4,$5::jsonb,$6,", expiry, ")"), params = list(chain_id, revision_id, deployment_id, state_hash, decision_payload, nonce))
  }
  expect_db_error("SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_ROLE_FORBIDDEN", function() {
    execute("SELECT set_config('request.jwt.claim.sub',$1,false)", list("00000000-0000-0000-0000-000000153499"))
    authorize_attempt(ids$chain, ids$revision, deployment$id[[1L]], eligible_hash, payload, "00000000-0000-0000-0000-000000153491")
  })
  execute("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))
  expect_db_error("SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID", function() authorize_attempt(ids$chain, ids$revision, deployment$id[[1L]], eligible_hash, payload, "00000000-0000-0000-0000-000000153492", "clock_timestamp()-interval '1 minute'"))
  stale_payload <- sub(eligible_hash, strrep("0", 64L), payload, fixed = TRUE)
  expect_db_error("SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_STALE", function() authorize_attempt(ids$chain, ids$revision, deployment$id[[1L]], strrep("0", 64L), stale_payload, "00000000-0000-0000-0000-000000153493"))
  forged_deployment <- "00000000-0000-0000-0000-000000153494"
  forged_payload <- sub(deployment$id[[1L]], forged_deployment, payload, fixed = TRUE)
  expect_db_error("SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_DEPLOYMENT_INVALID", function() authorize_attempt(ids$chain, ids$revision, forged_deployment, eligible_hash, forged_payload, "00000000-0000-0000-0000-000000153495"))
  publication_nonce <- "00000000-0000-0000-0000-000000153414"
  authorization <- authorize(ids$chain, ids$revision, deployment$id[[1L]], eligible_hash, payload, publication_nonce)
  if (identical(Sys.getenv("SOURCE_SCOPED_EVIDENCE_V3_RACE"), "1")) {
    if (!requireNamespace("processx", quietly = TRUE)) {
      stop("SOURCE_SCOPED_EVIDENCE_V3_PROCESSX_MISSING", call. = FALSE)
    }
    DBI::dbCommit(con)
    worker_program <- paste0(
      "args<-commandArgs(trailingOnly=TRUE);con<-DBI::dbConnect(RPostgres::Postgres(),dbname=Sys.getenv('PGDATABASE'),host=Sys.getenv('PGHOST'),port=as.integer(Sys.getenv('PGPORT')),user=Sys.getenv('PGUSER'),password=Sys.getenv('PGPASSWORD'));on.exit(DBI::dbDisconnect(con),add=TRUE);invisible(DBI::dbGetQuery(con,\"SELECT set_config('application_name',$1,false)\",params=list(args[[1L]])));invisible(DBI::dbGetQuery(con,\"SELECT set_config('request.jwt.claim.sub',$1,false)\",params=list(args[[2L]])));result<-tryCatch(DBI::dbGetQuery(con,\"SELECT public.red_publish_source_scoped_evidence_revision_v3($1,$2::jsonb)::text AS receipt\",params=list(args[[3L]],args[[4L]]))$receipt[[1L]],error=function(error)paste0('ERROR:',conditionMessage(error)));cat(result)"
    )
    launch_worker <- function(name, authorization_id, decision_payload) processx::process$new(
      file.path(R.home("bin"), "Rscript"),
      args = c("--vanilla", "-e", worker_program, name, actor, authorization_id, decision_payload),
      env = c(PGDATABASE = pg[["PGDATABASE"]], PGHOST = pg[["PGHOST"]],
              PGPORT = pg[["PGPORT"]], PGUSER = pg[["PGUSER"]], PGPASSWORD = pg[["PGPASSWORD"]]),
      stdout = "|", stderr = "|", cleanup_tree = TRUE
    )
    run_publication_race <- function(decision, authorization_id, decision_payload,
                                     expected_revision_id, expected_state_version,
                                     expected_publication_count) {
      DBI::dbBegin(con)
      execute("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(paste0("daa-source-scoped-replace:", source_id)))
      worker_run_id <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
      worker_names <- c(
        paste0("task4c-", decision, "-race-one-", worker_run_id),
        paste0("task4c-", decision, "-race-two-", worker_run_id)
      )
      jobs <- list(
        launch_worker(worker_names[[1L]], authorization_id, decision_payload),
        launch_worker(worker_names[[2L]], authorization_id, decision_payload)
      )
      deadline <- Sys.time() + 5
      repeat {
        waiting <- DBI::dbGetQuery(con, paste0(
          "SELECT count(*)::integer AS n FROM pg_locks lock ",
          "JOIN pg_stat_activity activity ON activity.pid=lock.pid ",
          "WHERE lock.locktype='advisory' AND NOT lock.granted ",
          "AND activity.application_name IN ($1,$2) ",
          "AND lock.database=(SELECT oid FROM pg_database WHERE datname=current_database()) ",
          "AND lock.classid::int8=((hashtextextended($3,0)>>32)&4294967295) ",
          "AND lock.objid::int8=(hashtextextended($3,0)&4294967295) ",
          "AND lock.objsubid=1"
        ), params = c(as.list(worker_names), list(paste0("daa-source-scoped-replace:", source_id))))$n[[1L]]
        if (waiting >= 2L) break
        if (Sys.time() >= deadline) stop(paste0("SOURCE_SCOPED_EVIDENCE_V3_", toupper(decision), "_RACE_NOT_BLOCKED"), call. = FALSE)
        Sys.sleep(0.02)
      }
      DBI::dbCommit(con)
      for (job in jobs) job$wait(10000)
      outputs <- vapply(jobs, function(job) job$read_all_output(), character(1))
      errors <- vapply(jobs, function(job) job$read_all_error(), character(1))
      statuses <- vapply(jobs, function(job) job$get_exit_status(), integer(1))
      if (!(all(statuses == 0L) && all(!nzchar(errors)) &&
        all(!grepl("ERROR:", outputs, fixed = TRUE)) && identical(outputs[[1L]], outputs[[2L]]))) {
        stop(paste0("SOURCE_SCOPED_EVIDENCE_V3_", toupper(decision), "_RACE_REPLAY_INVALID: statuses=", paste(statuses, collapse = ","), "; outputs=", paste(outputs, collapse = " | "), "; errors=", paste(errors, collapse = " | ")), call. = FALSE)
      }
      state_after_race <- DBI::dbGetQuery(con, "SELECT visible_revision_id::text,state_version FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=$1", params = list(ids$chain))
      publication_count <- DBI::dbGetQuery(con, "SELECT count(*)::integer AS n FROM private.source_scoped_evidence_v3_publication WHERE chain_id=$1", params = list(ids$chain))$n[[1L]]
      visible_revision_matches <- if (is.na(expected_revision_id)) {
        is.na(state_after_race$visible_revision_id[[1L]])
      } else {
        identical(state_after_race$visible_revision_id[[1L]], expected_revision_id)
      }
      expect_true(visible_revision_matches &&
        identical(as.integer(state_after_race$state_version[[1L]]), expected_state_version) &&
        publication_count == expected_publication_count,
        paste0("SOURCE_SCOPED_EVIDENCE_V3_", toupper(decision), "_RACE_STATE_INVALID"))
      invisible(outputs[[1L]])
    }
    run_publication_race("publish", authorization, payload, ids$revision, 3L, 1L)

    revision_two <- "00000000-0000-0000-0000-000000153415"
    fact_two <- -9153405L
    assertion_two <- -9153406L
    citation_two <- -9153407L
    state_after_publish <- DBI::dbGetQuery(con, "SELECT state_sha256 FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=$1", params = list(ids$chain))$state_sha256[[1L]]
    execute("INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES($1,'person',$2,'fixture')", list(fact_two, person_id))
    execute("INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst) VALUES($1,'fact',$2,'fixture two')", list(assertion_two, fact_two))
    execute("INSERT INTO public.citation(id,assertion_id,source_id,side) VALUES($1,$2,$3,'2')", list(citation_two, assertion_two, source_id))
    execute("INSERT INTO private.source_scoped_evidence_v3_revision(id,chain_id,revision,predecessor_revision_id,fact_id,revision_kind,chain_sha256,manifest_semantic_sha256) VALUES($1,$2,2,$3,$4,'content',repeat('7',64),repeat('8',64))", list(revision_two, ids$chain, ids$revision, fact_two))
    execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,fact_id) VALUES($1,'fact','fact',$2)", list(revision_two, fact_two))
    execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,assertion_id) VALUES($1,'assertion','assertion',$2)", list(revision_two, assertion_two))
    execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,citation_id) VALUES($1,'citation','citation',$2)", list(revision_two, citation_two))
    revision_two_created <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
    revision_two_created_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,4,$4) AS hash", params = list(ids$chain, revision_two, ids$revision, revision_two_created))$hash[[1L]]
    execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'source_revision_created',$3,$4,$5)", list(revision_two_created, ids$chain, state_after_publish, revision_two_created_hash, revision_two))
    revision_two_eligible <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
    revision_two_eligible_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,5,$4) AS hash", params = list(ids$chain, revision_two, ids$revision, revision_two_eligible))$hash[[1L]]
    execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'eligible',$3,$4,$5)", list(revision_two_eligible, ids$chain, revision_two_created_hash, revision_two_eligible_hash, revision_two))
    supersede_payload <- paste0('{"schema":"source-scoped-evidence-v3-publication-decision-v1","chain_id":"', ids$chain, '","revision_id":"', revision_two, '","deployment_id":"', deployment$id[[1L]], '","deployment_sha256":"', deployment$deployment_sha256[[1L]], '","expected_state_sha256":"', revision_two_eligible_hash, '","decision":"supersede","rationale":"Task 4C postcommit"}')
    supersede_authorization <- authorize(ids$chain, revision_two, deployment$id[[1L]], revision_two_eligible_hash, supersede_payload, "00000000-0000-0000-0000-000000153416")
    run_publication_race("supersede", supersede_authorization, supersede_payload, revision_two, 6L, 2L)

    tombstone_revision <- "00000000-0000-0000-0000-000000153417"
    state_after_supersede <- DBI::dbGetQuery(con, "SELECT state_sha256 FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=$1", params = list(ids$chain))$state_sha256[[1L]]
    execute("INSERT INTO private.source_scoped_evidence_v3_revision(id,chain_id,revision,predecessor_revision_id,revision_kind,chain_sha256,manifest_semantic_sha256) VALUES($1,$2,3,$3,'tombstone',repeat('9',64),repeat('a',64))", list(tombstone_revision, ids$chain, revision_two))
    tombstone_created <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
    tombstone_created_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,7,$4) AS hash", params = list(ids$chain, tombstone_revision, revision_two, tombstone_created))$hash[[1L]]
    execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'source_revision_created',$3,$4,$5)", list(tombstone_created, ids$chain, state_after_supersede, tombstone_created_hash, tombstone_revision))
    tombstone_eligible <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
    tombstone_eligible_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,8,$4) AS hash", params = list(ids$chain, tombstone_revision, revision_two, tombstone_eligible))$hash[[1L]]
    execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'eligible',$3,$4,$5)", list(tombstone_eligible, ids$chain, tombstone_created_hash, tombstone_eligible_hash, tombstone_revision))
    withdraw_payload <- paste0('{"schema":"source-scoped-evidence-v3-publication-decision-v1","chain_id":"', ids$chain, '","revision_id":"', tombstone_revision, '","deployment_id":"', deployment$id[[1L]], '","deployment_sha256":"', deployment$deployment_sha256[[1L]], '","expected_state_sha256":"', tombstone_eligible_hash, '","decision":"withdraw","rationale":"Task 4C postcommit"}')
    withdraw_authorization <- authorize(ids$chain, tombstone_revision, deployment$id[[1L]], tombstone_eligible_hash, withdraw_payload, "00000000-0000-0000-0000-000000153418")
    run_publication_race("withdraw", withdraw_authorization, withdraw_payload, NA_character_, 9L, 3L)
    cat("PASS source-scoped evidence V3 postcommit publish/supersede/withdraw races\n")
    quit(save = "no", status = 0L)
  }
  expect_db_error("SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_NONCE_REPLAY", function() authorize_attempt(ids$chain, ids$revision, deployment$id[[1L]], eligible_hash, payload, publication_nonce))
  mismatched_payload <- sub("Task 4C postcommit", "mismatch", payload, fixed = TRUE)
  expect_db_error("SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_INVALID", function() execute("SELECT public.red_publish_source_scoped_evidence_revision_v3($1,$2::jsonb)", params = list(authorization, mismatched_payload)))
  receipt <- DBI::dbGetQuery(con, "SELECT public.red_publish_source_scoped_evidence_revision_v3($1,$2::jsonb)::text AS receipt", params = list(authorization, payload))$receipt[[1L]]
  expect_true(grepl(deployment$id[[1L]], receipt, fixed = TRUE) && grepl('"decision": "publish"', receipt, fixed = TRUE), "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_PUBLISH_RECEIPT_INVALID")
  execute("SET LOCAL ROLE anon")
  visible <- DBI::dbGetQuery(con, "SELECT (SELECT count(*)::integer FROM public.fact WHERE id=-9153402) AS fact_count,(SELECT count(*)::integer FROM public.assertion WHERE id=-9153403) AS assertion_count,(SELECT count(*)::integer FROM public.citation WHERE id=-9153404) AS citation_count")
  visible_ids <- DBI::dbGetQuery(con, "SELECT (SELECT count(*)::integer FROM public.source_scoped_evidence_visible_fact_ids WHERE id=-9153402) AS fact_view_count,(SELECT count(*)::integer FROM public.source_scoped_evidence_visible_assertion_ids WHERE id=-9153403) AS assertion_view_count,(SELECT count(*)::integer FROM public.source_scoped_evidence_visible_citation_ids WHERE id=-9153404) AS citation_view_count")
  execute("RESET ROLE")
  expect_true(all(as.integer(visible[1L, ]) == 1L) && all(as.integer(visible_ids[1L, ]) == 1L), "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_PUBLISH_VISIBILITY_INVALID")

  revision_two <- "00000000-0000-0000-0000-000000153415"
  fact_two <- -9153405L
  assertion_two <- -9153406L
  citation_two <- -9153407L
  state_after_publish <- DBI::dbGetQuery(con, "SELECT state_sha256 FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=$1", params = list(ids$chain))$state_sha256[[1L]]
  execute("INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES($1,'person',$2,'fixture')", list(fact_two, person_id))
  execute("INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst) VALUES($1,'fact',$2,'fixture two')", list(assertion_two, fact_two))
  execute("INSERT INTO public.citation(id,assertion_id,source_id,side) VALUES($1,$2,$3,'2')", list(citation_two, assertion_two, source_id))
  execute("INSERT INTO private.source_scoped_evidence_v3_revision(id,chain_id,revision,predecessor_revision_id,fact_id,revision_kind,chain_sha256,manifest_semantic_sha256) VALUES($1,$2,2,$3,$4,'content',repeat('7',64),repeat('8',64))", list(revision_two, ids$chain, ids$revision, fact_two))
  execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,fact_id) VALUES($1,'fact','fact',$2)", list(revision_two, fact_two))
  execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,assertion_id) VALUES($1,'assertion','assertion',$2)", list(revision_two, assertion_two))
  execute("INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,citation_id) VALUES($1,'citation','citation',$2)", list(revision_two, citation_two))
  revision_two_created <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
  revision_two_created_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,4,$4) AS hash", params = list(ids$chain, revision_two, ids$revision, revision_two_created))$hash[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'source_revision_created',$3,$4,$5)", list(revision_two_created, ids$chain, state_after_publish, revision_two_created_hash, revision_two))
  revision_two_eligible <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
  revision_two_eligible_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,5,$4) AS hash", params = list(ids$chain, revision_two, ids$revision, revision_two_eligible))$hash[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'eligible',$3,$4,$5)", list(revision_two_eligible, ids$chain, revision_two_created_hash, revision_two_eligible_hash, revision_two))
  supersede_payload <- paste0('{"schema":"source-scoped-evidence-v3-publication-decision-v1","chain_id":"', ids$chain, '","revision_id":"', revision_two, '","deployment_id":"', deployment$id[[1L]], '","deployment_sha256":"', deployment$deployment_sha256[[1L]], '","expected_state_sha256":"', revision_two_eligible_hash, '","decision":"supersede","rationale":"Task 4C postcommit"}')
  supersede_authorization <- DBI::dbGetQuery(con, "SELECT public.red_authorize_source_scoped_evidence_publication_v3($1,$2,$3,$4,$5::jsonb,$6,clock_timestamp()+interval '5 minutes')::text AS id", params = list(ids$chain, revision_two, deployment$id[[1L]], revision_two_eligible_hash, supersede_payload, "00000000-0000-0000-0000-000000153416"))$id[[1L]]
  supersede_receipt <- DBI::dbGetQuery(con, "SELECT public.red_publish_source_scoped_evidence_revision_v3($1,$2::jsonb)::text AS receipt", params = list(supersede_authorization, supersede_payload))$receipt[[1L]]
  expect_true(grepl('"decision": "supersede"', supersede_receipt, fixed = TRUE), "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_SUPERSEDE_RECEIPT_INVALID")
  execute("SET LOCAL ROLE anon")
  superseded_visibility <- DBI::dbGetQuery(con, "SELECT (SELECT count(*)::integer FROM public.fact WHERE id=-9153402) AS old_fact,(SELECT count(*)::integer FROM public.fact WHERE id=-9153405) AS new_fact,(SELECT count(*)::integer FROM public.assertion WHERE id=-9153403) AS old_assertion,(SELECT count(*)::integer FROM public.assertion WHERE id=-9153406) AS new_assertion,(SELECT count(*)::integer FROM public.citation WHERE id=-9153404) AS old_citation,(SELECT count(*)::integer FROM public.citation WHERE id=-9153407) AS new_citation")
  execute("RESET ROLE")
  expect_true(identical(as.integer(superseded_visibility[1L, ]), c(0L,1L,0L,1L,0L,1L)), "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_SUPERSEDE_VISIBILITY_INVALID")

  tombstone_revision <- "00000000-0000-0000-0000-000000153417"
  state_after_supersede <- DBI::dbGetQuery(con, "SELECT state_sha256 FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=$1", params = list(ids$chain))$state_sha256[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_revision(id,chain_id,revision,predecessor_revision_id,revision_kind,chain_sha256,manifest_semantic_sha256) VALUES($1,$2,3,$3,'tombstone',repeat('9',64),repeat('a',64))", list(tombstone_revision, ids$chain, revision_two))
  tombstone_created <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
  tombstone_created_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,7,$4) AS hash", params = list(ids$chain, tombstone_revision, revision_two, tombstone_created))$hash[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'source_revision_created',$3,$4,$5)", list(tombstone_created, ids$chain, state_after_supersede, tombstone_created_hash, tombstone_revision))
  tombstone_eligible <- DBI::dbGetQuery(con, "SELECT gen_random_uuid()::text AS id")$id[[1L]]
  tombstone_eligible_hash <- DBI::dbGetQuery(con, "SELECT private.source_scoped_evidence_v3_chain_state_sha256($1,$2,$3,8,$4) AS hash", params = list(ids$chain, tombstone_revision, revision_two, tombstone_eligible))$hash[[1L]]
  execute("INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id) VALUES($1,$2,'eligible',$3,$4,$5)", list(tombstone_eligible, ids$chain, tombstone_created_hash, tombstone_eligible_hash, tombstone_revision))
  withdraw_payload <- paste0('{"schema":"source-scoped-evidence-v3-publication-decision-v1","chain_id":"', ids$chain, '","revision_id":"', tombstone_revision, '","deployment_id":"', deployment$id[[1L]], '","deployment_sha256":"', deployment$deployment_sha256[[1L]], '","expected_state_sha256":"', tombstone_eligible_hash, '","decision":"withdraw","rationale":"Task 4C postcommit"}')
  withdraw_authorization <- DBI::dbGetQuery(con, "SELECT public.red_authorize_source_scoped_evidence_publication_v3($1,$2,$3,$4,$5::jsonb,$6,clock_timestamp()+interval '5 minutes')::text AS id", params = list(ids$chain, tombstone_revision, deployment$id[[1L]], tombstone_eligible_hash, withdraw_payload, "00000000-0000-0000-0000-000000153418"))$id[[1L]]
  withdraw_receipt <- DBI::dbGetQuery(con, "SELECT public.red_publish_source_scoped_evidence_revision_v3($1,$2::jsonb)::text AS receipt", params = list(withdraw_authorization, withdraw_payload))$receipt[[1L]]
  expect_true(grepl('"decision": "withdraw"', withdraw_receipt, fixed = TRUE), "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_WITHDRAW_RECEIPT_INVALID")
  execute("SET LOCAL ROLE anon")
  withdrawn_visibility <- DBI::dbGetQuery(con, "SELECT (SELECT count(*)::integer FROM public.fact WHERE id=-9153405) AS fact_count,(SELECT count(*)::integer FROM public.assertion WHERE id=-9153406) AS assertion_count,(SELECT count(*)::integer FROM public.citation WHERE id=-9153407) AS citation_count")
  execute("RESET ROLE")
  expect_true(identical(as.integer(withdrawn_visibility[1L, ]), c(0L,0L,0L)), "SOURCE_SCOPED_EVIDENCE_V3_POSTCOMMIT_WITHDRAW_VISIBILITY_INVALID")
  DBI::dbRollback(con)
  cat("PASS source-scoped evidence V3 postcommit deployment binding\n")
}

cat("PASS source-scoped evidence V3 precommit integration boundary\n")
