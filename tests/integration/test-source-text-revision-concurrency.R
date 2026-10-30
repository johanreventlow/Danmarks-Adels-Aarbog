#!/usr/bin/env Rscript

# Trin 6a, Task 5: lås før måling i source_text_revision (spec §4.4 pkt. 0, Codex F1), bevist med rigtige
# samtidige sessioner mod PostgreSQL 17. Hver samtidig session er en selvstændig R-proces (processx) med sin egen
# RPostgres-forbindelse; controlleren observerer ventetiderne med pg_blocking_pids.
#
# Barrieren er en almindelig rækkelås, ikke en testkrog i produktionskoden: controlleren holder renditionsrækken
# FOR UPDATE. Revisionen (session A) tager sine låse (helpost, klausulsæt, afhængige fortolkninger), måler
# afhængigheder og bindinger og standser så ved trin 4, fordi tekstversionens fremmednøgle til renditionen skal
# have FOR KEY SHARE på rækken. Mens A står dér med alle sine låse, prøver session B at promovere en accepteret
# afhængig fortolkning.
#
#   Rækkefølge 1: A låser først. B skal vente på A (pg_blocking_pids(B) indeholder A). A committer; B fejler, og
#                 ingen promotion er skrevet på den nu forældede fortolkning.
#   Rækkefølge 2: B promoverer først i en åben transaktion. A skal vente på B, før den måler. B committer; A's
#                 måling indeholder den nye binding og afviser mod et manifest uden den
#                 (TEXT_REVISION_BINDING_SET_DRIFT). Havde A målt før låsen, ville den have overset bindingen og
#                 forældet fortolkningen uden at kvittere for tabet.
#
# Kræver en frisk base: evidence-promotion-bootstrap, schema.sql, db-rls.sql, 1939-v50-writer-bootstrap,
# reimport-writer-v2-bootstrap, db-rls.sql (som klausul-writer-testene). Testen committer syntetiske fixtures.

required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg_values <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg_values) || any(!nzchar(pg_values))) {
  stop("TEXT_REVISION_CONCURRENCY_ALL_FIVE_PG_VARIABLES_REQUIRED: ", paste(required_pg, collapse = ", "), call. = FALSE)
}
for (package in c("DBI", "RPostgres", "processx", "jsonlite")) {
  if (!requireNamespace(package, quietly = TRUE)) stop("TEXT_REVISION_CONCURRENCY_R_PACKAGES_REQUIRED: ", package, call. = FALSE)
}
pg <- as.list(stats::setNames(pg_values, required_pg))

started <- Sys.time()
assertions <- 0L
expect_true <- function(value, code) {
  assertions <<- assertions + 1L
  if (!isTRUE(value)) stop(code, call. = FALSE)
  invisible(TRUE)
}

connect <- function(application_name) {
  con <- DBI::dbConnect(RPostgres::Postgres(), dbname = pg$PGDATABASE, host = pg$PGHOST,
                        port = as.integer(pg$PGPORT), user = pg$PGUSER, password = pg$PGPASSWORD)
  DBI::dbGetQuery(con, "SELECT set_config('application_name',$1,false)", params = list(application_name))
  DBI::dbExecute(con, "SET statement_timeout='20s'")
  con
}
scalar <- function(con, sql, params = list()) {
  result <- if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  if (nrow(result) != 1L || ncol(result) != 1L) stop("TEXT_REVISION_CONCURRENCY_SCALAR_SHAPE: ", sql, call. = FALSE)
  result[[1L]][[1L]]
}

# Fixturefunktionerne er pg_temp-funktioner; hvert psql-kald indlæser dem i sin egen session og returnerer én værdi.
fixture_files <- file.path("tests", "sql", "fixtures", c("relation-5b.sql", "relation-2a.sql", "source-text-revision.sql"))
psql_value <- function(sql) {
  args <- c("-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", as.vector(rbind("-f", fixture_files)), "-c", sql)
  result <- processx::run("psql", args, env = c("current", PGOPTIONS = "-c client_min_messages=warning"), error_on_status = FALSE)
  if (result$status != 0L) stop("TEXT_REVISION_CONCURRENCY_FIXTURE_FAILED: ", result$stderr, call. = FALSE)
  lines <- strsplit(trimws(result$stdout), "\n", fixed = TRUE)[[1L]]
  lines[[length(lines)]]
}

actor <- "11000000-0000-0000-0000-00000006a5c1"

# Opret en post med afgjort ægteskab (familiebinding) og en accepteret, IKKE promoveret dødsfortolkning, en payload
# målt nu (kun familiebindingen) og en åben batch med autorisationen.
prepare_case <- function(controller, base, nonce) {
  fx <- psql_value(sprintf("SELECT pg_temp.t5_post(%d,'%s',false,false)::text", base, actor))
  fx_list <- jsonlite::fromJSON(fx, simplifyVector = FALSE)
  payload <- psql_value(sprintf(
    "SELECT pg_temp.t5_payload(%s::jsonb,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'])::text",
    DBI::dbQuoteLiteral(controller, fx)))
  payload_list <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
  expect_true(length(payload_list$expected_binding_loss) == 1L &&
                identical(payload_list$expected_binding_loss[[1L]]$target_type, "family"),
              "TEXT_REVISION_CONCURRENCY_FIXTURE_BINDINGS")
  element <- paste0("source-text-revision:", fx_list$record_key)
  manifest <- digest_sha256(paste0("t5-conc:", nonce))
  identity <- scalar(controller, paste0(
    "SELECT jsonb_build_object('database_name',current_database(),",
    "'system_identifier',(pg_control_system()).system_identifier::text)::text"))
  invisible(scalar(controller, "SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor)))
  invisible(DBI::dbExecute(controller, "SET ROLE service_role"))
  authorization <- scalar(controller, paste0(
    "SELECT public.red_authorize_reimport($1,$2,$3,$4::bigint,$5,$6,",
    "'{\"person_creates\":0,\"source_evidence\":0,\"source_text_revision\":1}'::jsonb,",
    "jsonb_build_object($7::text,$8::jsonb),gen_random_uuid(),clock_timestamp()+interval '10 minutes')::text"),
    list(manifest, manifest, identity, as.character(fx_list$source), fx_list$profile$profile_id,
         fx_list$profile$profile_sha256, element, payload))
  invisible(DBI::dbExecute(controller, "RESET ROLE"))
  invisible(DBI::dbExecute(controller, "SET ROLE authenticated"))
  invisible(scalar(controller, "SELECT public.red_preflight_reimport_authorization($1::uuid,$2,$3)::text", list(authorization, manifest, manifest)))
  batch <- scalar(controller, "SELECT public.red_begin_reimport($1::uuid,$2,$3)::text", list(authorization, manifest, manifest))
  invisible(DBI::dbExecute(controller, "RESET ROLE"))
  list(fx = fx_list, fx_text = fx, payload = payload, element = element, batch = batch, authorization = authorization)
}

digest_sha256 <- function(text) scalar(controller, "SELECT encode(extensions.digest($1,'sha256'),'hex')", list(text))

worker_program <- paste0(
  "args<-commandArgs(trailingOnly=TRUE);application_name<-args[[1L]];sql<-args[[2L]];actor_id<-args[[3L]];",
  "con<-DBI::dbConnect(RPostgres::Postgres(),dbname=Sys.getenv('PGDATABASE'),host=Sys.getenv('PGHOST'),",
  "port=as.integer(Sys.getenv('PGPORT')),user=Sys.getenv('PGUSER'),password=Sys.getenv('PGPASSWORD'));",
  "on.exit(DBI::dbDisconnect(con),add=TRUE);",
  "DBI::dbGetQuery(con,\"SELECT set_config('application_name',$1,false)\",params=list(application_name));",
  "DBI::dbExecute(con,\"SET statement_timeout='20s'\");",
  "DBI::dbGetQuery(con,\"SELECT set_config('request.jwt.claim.sub',$1,false)\",params=list(actor_id));",
  "DBI::dbExecute(con,'SET ROLE authenticated');",
  "code<-tryCatch({v<-DBI::dbGetQuery(con,sql);cat('T5_VALUE:',as.character(v[[1L]][[1L]]),'\\n',sep='');'OK'},",
  "error=function(error){message<-conditionMessage(error);",
  "cat('T5_DB_ERROR:',gsub('[\\r\\n]+',' | ',message),'\\n',file=stderr(),sep='');",
  "match<-regexpr('(?:TEXT_REVISION|EVIDENCE|REIMPORT)_[A-Z0-9_]+',message,perl=TRUE);",
  "if(match[[1L]]<0L)'UNCLASSIFIED_DATABASE_ERROR' else regmatches(message,match)});",
  "cat('T5_RESULT_CODE:',code,'\\n',sep='')"
)
launch_worker <- function(application_name, sql) {
  library_env <- Sys.getenv(c("R_LIBS", "R_LIBS_USER", "R_LIBS_SITE"), unset = NA_character_)
  library_env <- library_env[!is.na(library_env) & nzchar(library_env)]
  processx::process$new(
    file.path(R.home("bin"), "Rscript"), args = c("--vanilla", "-e", worker_program, application_name, sql, actor),
    env = c(PGDATABASE = pg$PGDATABASE, PGHOST = pg$PGHOST, PGPORT = pg$PGPORT, PGUSER = pg$PGUSER,
            PGPASSWORD = pg$PGPASSWORD, library_env),
    stdout = "|", stderr = "|", cleanup_tree = TRUE)
}
collect_worker <- function(job, timeout = 30) {
  deadline <- Sys.time() + timeout
  while (job$is_alive()) {
    if (Sys.time() > deadline) { try(job$kill(), silent = TRUE); stop("TEXT_REVISION_CONCURRENCY_WORKER_TIMEOUT", call. = FALSE) }
    Sys.sleep(0.02)
  }
  output <- paste(job$read_all_output(), job$read_all_error(), sep = "\n")
  code <- regmatches(output, regexec("T5_RESULT_CODE:([A-Z0-9_]+)", output, perl = TRUE))[[1L]]
  if (length(code) != 2L) stop("TEXT_REVISION_CONCURRENCY_WORKER_RESULT_INVALID: ", output, call. = FALSE)
  value <- regmatches(output, regexec("T5_VALUE:([^\n]*)", output, perl = TRUE))[[1L]]
  list(code = code[[2L]], value = if (length(value) == 2L) value[[2L]] else NA_character_, output = output)
}
backend_pid <- function(observer, application_name, timeout = 15) {
  deadline <- Sys.time() + timeout
  repeat {
    pid <- DBI::dbGetQuery(observer, "SELECT pid FROM pg_stat_activity WHERE datname=current_database() AND application_name=$1",
                           params = list(application_name))
    if (nrow(pid) == 1L) return(as.integer(pid$pid[[1L]]))
    if (Sys.time() > deadline) stop("TEXT_REVISION_CONCURRENCY_SESSION_NOT_FOUND: ", application_name, call. = FALSE)
    Sys.sleep(0.02)
  }
}
# Vent, til sessionen application_name venter på en lås, som blocker_pid holder.
wait_blocked_by <- function(observer, application_name, blocker_pid, timeout = 15) {
  deadline <- Sys.time() + timeout
  repeat {
    blocked <- isTRUE(scalar(observer, paste0(
      "SELECT coalesce(bool_or($2::integer=ANY(pg_blocking_pids(pid))),false) FROM pg_stat_activity ",
      "WHERE datname=current_database() AND application_name=$1"), list(application_name, blocker_pid)))
    if (blocked) return(invisible(TRUE))
    if (Sys.time() > deadline) {
      details <- DBI::dbGetQuery(observer, paste0(
        "SELECT application_name,pid,state,wait_event_type,wait_event,pg_blocking_pids(pid)::text AS blockers ",
        "FROM pg_stat_activity WHERE datname=current_database() AND application_name LIKE 't5_%'"))
      stop("TEXT_REVISION_CONCURRENCY_EXPECTED_LOCK_WAIT_NOT_OBSERVED: ", application_name, " ",
           paste(capture.output(print(details)), collapse = " "), call. = FALSE)
    }
    Sys.sleep(0.02)
  }
}
apply_sql <- function(case) {
  sprintf("SELECT public.red_apply_reimport_source_text_revision('%s'::uuid,'%s',%s::jsonb)::text",
          case$batch, case$element, DBI::dbQuoteLiteral(controller, case$payload))
}
promote_sql <- function(items) {
  sprintf(paste0("SELECT public.red_promote_interpretations_batch(%s::jsonb,",
                 "public.red_preview_interpretation_promotions(%s::jsonb)->>'preview_hash')::text"),
          DBI::dbQuoteLiteral(controller, items), DBI::dbQuoteLiteral(controller, items))
}
death_promotions <- function(case) {
  as.integer(scalar(controller, paste0(
    "SELECT count(*) FROM private.interpretation_promotion p JOIN private.interpretation q ON q.id=p.interpretation_id ",
    "WHERE q.interpretation_key=$1::uuid"), list(case$fx$death_key)))
}
death_status <- function(case) {
  scalar(controller, "SELECT status FROM private.interpretation_current WHERE interpretation_key=$1::uuid", list(case$fx$death_key))
}

controller <- connect("t5_controller")
observer <- connect("t5_observer")
on.exit({ DBI::dbDisconnect(controller); DBI::dbDisconnect(observer) }, add = TRUE)

# ---------------------------------------------------------------------------------------------------------------
# Rækkefølge 1: A låser først, B venter på A og fejler efter A's commit.
case1 <- prepare_case(controller, -66101L, "order-1")
items1 <- jsonlite::toJSON(case1$fx$death_items, auto_unbox = TRUE)
expect_true(identical(death_status(case1), "accepted") && death_promotions(case1) == 0L, "TEXT_REVISION_CONCURRENCY_1_PRECONDITION")
barrier <- connect("t5_barrier")
DBI::dbBegin(barrier)
invisible(scalar(barrier, "SELECT count(*) FROM (SELECT 1 FROM private.source_rendition WHERE id=$1::uuid FOR UPDATE) x", list(case1$fx$src$rend)))
barrier_pid <- as.integer(scalar(barrier, "SELECT pg_backend_pid()"))
job_a <- launch_worker("t5_a1", apply_sql(case1))
wait_blocked_by(observer, "t5_a1", barrier_pid)
a_pid <- backend_pid(observer, "t5_a1")
# A står ved trin 4 med alle sine låse; nu prøver B at promovere den afhængige fortolkning.
job_b <- launch_worker("t5_b1", promote_sql(items1))
wait_blocked_by(observer, "t5_b1", a_pid)
expect_true(death_promotions(case1) == 0L, "TEXT_REVISION_CONCURRENCY_1_B_WROTE_WHILE_WAITING")
DBI::dbCommit(barrier)
DBI::dbDisconnect(barrier)
result_a <- collect_worker(job_a)
result_b <- collect_worker(job_b)
expect_true(identical(result_a$code, "OK"), paste0("TEXT_REVISION_CONCURRENCY_1_A_FAILED: ", result_a$output))
expect_true(!identical(result_b$code, "OK") && grepl("^EVIDENCE_", result_b$code),
            paste0("TEXT_REVISION_CONCURRENCY_1_B_NOT_REJECTED: ", result_b$output))
receipt_a <- jsonlite::fromJSON(result_a$value, simplifyVector = FALSE)
expect_true(length(receipt_a$binding_loss) == 1L && identical(receipt_a$binding_loss[[1L]]$target_type, "family"),
            "TEXT_REVISION_CONCURRENCY_1_RECEIPT_BINDINGS")
expect_true(case1$fx$death_key %in% unlist(receipt_a$superseded_keys), "TEXT_REVISION_CONCURRENCY_1_RECEIPT_KEYS")
expect_true(identical(death_status(case1), "superseded"), "TEXT_REVISION_CONCURRENCY_1_DEATH_NOT_SUPERSEDED")
expect_true(death_promotions(case1) == 0L, "TEXT_REVISION_CONCURRENCY_1_PROMOTION_ON_SUPERSEDED")
invisible(scalar(controller, "SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor)))
invisible(DBI::dbExecute(controller, "SET ROLE authenticated"))
finalize1 <- jsonlite::fromJSON(scalar(controller, "SELECT public.red_finalize_reimport($1::uuid)::text", list(case1$batch)))
invisible(DBI::dbExecute(controller, "RESET ROLE"))
expect_true(identical(finalize1$status, "finalized") && identical(as.integer(finalize1$counts$source_text_revision), 1L),
            "TEXT_REVISION_CONCURRENCY_1_FINALIZE")

# ---------------------------------------------------------------------------------------------------------------
# Rækkefølge 2: B promoverer først (åben transaktion); A venter på B før målingen og afviser bagefter med drift.
case2 <- prepare_case(controller, -66201L, "order-2")
items2 <- jsonlite::toJSON(case2$fx$death_items, auto_unbox = TRUE)
session_b <- connect("t5_b2")
invisible(scalar(session_b, "SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor)))
DBI::dbBegin(session_b)
invisible(DBI::dbExecute(session_b, "SET LOCAL ROLE authenticated"))
invisible(scalar(session_b, promote_sql(items2)))
b_pid <- as.integer(scalar(session_b, "SELECT pg_backend_pid()"))
job_a2 <- launch_worker("t5_a2", apply_sql(case2))
wait_blocked_by(observer, "t5_a2", b_pid)
expect_true(identical(as.integer(scalar(observer,
  "SELECT count(*) FROM private.source_observation_text WHERE observation_id=$1::uuid", list(case2$fx$helpost))), 0L),
  "TEXT_REVISION_CONCURRENCY_2_A_WROTE_WHILE_WAITING")
DBI::dbCommit(session_b)
DBI::dbDisconnect(session_b)
result_a2 <- collect_worker(job_a2)
expect_true(identical(result_a2$code, "TEXT_REVISION_BINDING_SET_DRIFT"),
            paste0("TEXT_REVISION_CONCURRENCY_2_A_NOT_DRIFT: ", result_a2$output))
expect_true(death_promotions(case2) == 1L && identical(death_status(case2), "accepted"),
            "TEXT_REVISION_CONCURRENCY_2_B_PROMOTION_LOST")
expect_true(identical(as.integer(scalar(controller,
  "SELECT count(*) FROM private.source_observation_text WHERE observation_id=$1::uuid", list(case2$fx$helpost))), 0L) &&
  identical(as.integer(scalar(controller,
  "SELECT count(*) FROM private.reimport_event WHERE batch_id=$1::uuid", list(case2$batch))), 0L),
  "TEXT_REVISION_CONCURRENCY_2_A_WROTE")
# Med et manifest, der kender den nye binding, går revisionen igennem (samme batch er stadig åben).
fixed_payload <- psql_value(sprintf(
  "SELECT pg_temp.t5_payload(%s::jsonb,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'])::text",
  DBI::dbQuoteLiteral(controller, case2$fx_text)))
expect_true(length(jsonlite::fromJSON(fixed_payload, simplifyVector = FALSE)$expected_binding_loss) == 2L,
            "TEXT_REVISION_CONCURRENCY_2_REMEASURE")

cat(sprintf("OK: test-source-text-revision-concurrency (%d assertions, %.1f s)\n", assertions,
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
