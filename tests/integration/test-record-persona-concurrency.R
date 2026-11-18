#!/usr/bin/env Rscript

# record_persona låser recorden før målingen (som publication_persona), bevist med to rigtige samtidige sessioner mod
# PostgreSQL 17. Hver session er en selvstændig R-proces (processx) med sin egen RPostgres-forbindelse; controlleren
# observerer ventetiderne med pg_blocking_pids.
#
# To batches (to profiler, så writer-låsen ikke serialiserer dem) rammer SAMME helpost-record uden aktiv tekstbinding.
# Posten har en tilbagetrukket binding (den står ikke i vejen for writeren), og den er barrieren: controlleren holder
# rækken FOR UPDATE. Writer A tager recordlåsen (source_record ... FOR UPDATE) og standser så på publikationsrækken.
# Writer B blokerer på recordlåsen, som A holder. Når barrieren slippes, committer A, og B afvises med
# RECORD_PERSONA_EXISTS. Uden recordlåsen ville B måle før A's commit og skrive en anden persona på samme mention.
#
# Kræver en frisk base som klausul-writer-testene: evidence-promotion-bootstrap, schema.sql, db-rls.sql,
# 1939-v50-writer-bootstrap, reimport-writer-v2-bootstrap, (db-migrations.sql to gange, db-rls.sql).
# Testen committer syntetiske fixtures (kilde -6230) og rydder dem ved start og slut, så den kan genkøres på samme base.
# Køres fra repo-roden.

required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg_values <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg_values) || any(!nzchar(pg_values))) {
  stop("RECORD_PERSONA_CONCURRENCY_ALL_FIVE_PG_VARIABLES_REQUIRED: ", paste(required_pg, collapse = ", "), call. = FALSE)
}
for (package in c("DBI", "RPostgres", "processx", "jsonlite")) {
  if (!requireNamespace(package, quietly = TRUE)) stop("RECORD_PERSONA_CONCURRENCY_R_PACKAGES_REQUIRED: ", package, call. = FALSE)
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
  if (nrow(result) != 1L || ncol(result) != 1L) stop("RECORD_PERSONA_CONCURRENCY_SCALAR_SHAPE: ", sql, call. = FALSE)
  result[[1L]][[1L]]
}

# Fixturefunktionerne er pg_temp-funktioner; hvert psql-kald indlæser dem i sin egen session og returnerer én værdi.
fixture_files <- c(file.path("tests", "sql", "fixtures", "publication-persona.sql"),
                   file.path("tests", "sql", "fixtures", "record-persona.sql"))
psql_value <- function(sql) {
  args <- c("-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-f", fixture_files[[1L]], "-f", fixture_files[[2L]], "-c", sql)
  result <- processx::run("psql", args, env = c("current", PGOPTIONS = "-c client_min_messages=warning"), error_on_status = FALSE)
  if (result$status != 0L) stop("RECORD_PERSONA_CONCURRENCY_FIXTURE_FAILED: ", result$stderr, call. = FALSE)
  lines <- strsplit(trimws(result$stdout), "\n", fixed = TRUE)[[1L]]
  lines[[length(lines)]]
}

actor <- "11000000-0000-0000-0000-0000000c07c1"
worker_program <- paste0(
  "args<-commandArgs(trailingOnly=TRUE);application_name<-args[[1L]];sql<-args[[2L]];actor_id<-args[[3L]];",
  "con<-DBI::dbConnect(RPostgres::Postgres(),dbname=Sys.getenv('PGDATABASE'),host=Sys.getenv('PGHOST'),",
  "port=as.integer(Sys.getenv('PGPORT')),user=Sys.getenv('PGUSER'),password=Sys.getenv('PGPASSWORD'));",
  "on.exit(DBI::dbDisconnect(con),add=TRUE);",
  "DBI::dbGetQuery(con,\"SELECT set_config('application_name',$1,false)\",params=list(application_name));",
  "DBI::dbExecute(con,\"SET statement_timeout='20s'\");",
  "DBI::dbGetQuery(con,\"SELECT set_config('request.jwt.claim.sub',$1,false)\",params=list(actor_id));",
  "DBI::dbExecute(con,'SET ROLE authenticated');",
  "code<-tryCatch({v<-DBI::dbGetQuery(con,sql);cat('RP_VALUE:',as.character(v[[1L]][[1L]]),'\\n',sep='');'OK'},",
  "error=function(error){message<-conditionMessage(error);",
  "cat('RP_DB_ERROR:',gsub('[\\r\\n]+',' | ',message),'\\n',file=stderr(),sep='');",
  "match<-regexpr('(?:RECORD_PERSONA|RECORD|EVIDENCE|REIMPORT)_[A-Z0-9_]+',message,perl=TRUE);",
  "if(match[[1L]]<0L)'UNCLASSIFIED_DATABASE_ERROR' else regmatches(message,match)});",
  "cat('RP_RESULT_CODE:',code,'\\n',sep='')"
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
    if (Sys.time() > deadline) { try(job$kill(), silent = TRUE); stop("RECORD_PERSONA_CONCURRENCY_WORKER_TIMEOUT", call. = FALSE) }
    Sys.sleep(0.02)
  }
  output <- paste(job$read_all_output(), job$read_all_error(), sep = "\n")
  code <- regmatches(output, regexec("RP_RESULT_CODE:([A-Z0-9_]+)", output, perl = TRUE))[[1L]]
  if (length(code) != 2L) stop("RECORD_PERSONA_CONCURRENCY_WORKER_RESULT_INVALID: ", output, call. = FALSE)
  list(code = code[[2L]], output = output)
}
backend_pid <- function(observer, application_name, timeout = 15) {
  deadline <- Sys.time() + timeout
  repeat {
    pid <- DBI::dbGetQuery(observer, "SELECT pid FROM pg_stat_activity WHERE datname=current_database() AND application_name=$1",
                           params = list(application_name))
    if (nrow(pid) == 1L) return(as.integer(pid$pid[[1L]]))
    if (Sys.time() > deadline) stop("RECORD_PERSONA_CONCURRENCY_SESSION_NOT_FOUND: ", application_name, call. = FALSE)
    Sys.sleep(0.02)
  }
}
wait_blocked_by <- function(observer, application_name, blocker_pid, timeout = 15) {
  deadline <- Sys.time() + timeout
  repeat {
    blocked <- isTRUE(scalar(observer, paste0(
      "SELECT coalesce(bool_or($2::integer=ANY(pg_blocking_pids(pid))),false) FROM pg_stat_activity ",
      "WHERE datname=current_database() AND application_name=$1"), list(application_name, blocker_pid)))
    if (blocked) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("RECORD_PERSONA_CONCURRENCY_EXPECTED_LOCK_WAIT_NOT_OBSERVED: ", application_name, call. = FALSE)
    Sys.sleep(0.02)
  }
}

# Rydder testens committede fixtures (kilde -6230, person -623001). Som superbruger uden triggere (evidensrækkerne er
# append-only); rækkefølgen er uden betydning, når fremmednøgler er slået fra.
cleanup_fixtures <- function(con) {
  recs <- "SELECT id FROM private.source_record WHERE source_id=-6230"
  obs <- paste0("SELECT o.id FROM private.source_observation o JOIN private.source_record_occurrence c ON c.id=o.occurrence_id ",
                "JOIN private.source_rendition r ON r.id=c.rendition_id WHERE r.source_id=-6230")
  rends <- "SELECT id FROM private.source_rendition WHERE source_id=-6230"
  statements <- c(
    "DELETE FROM private.reimport_event WHERE batch_id IN (SELECT id FROM private.reimport_batch WHERE source_id=-6230)",
    "DELETE FROM private.reimport_batch WHERE source_id=-6230",
    "DELETE FROM private.reimport_authorization WHERE source_id=-6230",
    "DELETE FROM private.reimport_writer_profile WHERE source_id=-6230",
    "DELETE FROM private.source_persona_mention WHERE persona_id IN (SELECT id FROM private.source_persona WHERE source_id=-6230)",
    "DELETE FROM private.source_persona WHERE source_id=-6230",
    paste0("DELETE FROM private.source_mention WHERE observation_id IN (", obs, ")"),
    paste0("DELETE FROM private.source_record_anchor_event WHERE source_record_id IN (", recs, ")"),
    paste0("DELETE FROM private.source_observation WHERE id IN (", obs, ")"),
    paste0("DELETE FROM private.source_record_occurrence WHERE rendition_id IN (", rends, ")"),
    paste0("DELETE FROM private.narrative_record_publication WHERE source_record_id IN (", recs, ")"),
    "DELETE FROM private.source_record WHERE source_id=-6230",
    "DELETE FROM private.source_rendition WHERE source_id=-6230",
    "DELETE FROM private.extraction_run WHERE source_id=-6230",
    "DELETE FROM public.narrative WHERE source_id=-6230",
    "DELETE FROM public.person_external_id WHERE source_id=-6230",
    "DELETE FROM public.person WHERE id=-623001",
    "DELETE FROM public.source WHERE id=-6230")
  DBI::dbBegin(con)
  tryCatch({
    DBI::dbExecute(con, "SET LOCAL session_replication_role=replica")
    for (statement in statements) DBI::dbExecute(con, statement)
    DBI::dbCommit(con)
  }, error = function(error) { try(DBI::dbRollback(con), silent = TRUE); stop(error) })
}

controller <- connect("rp_controller")
observer <- connect("rp_observer")
on.exit({ try(cleanup_fixtures(controller), silent = TRUE); DBI::dbDisconnect(controller); DBI::dbDisconnect(observer) }, add = TRUE)
cleanup_fixtures(controller)

src_json <- psql_value(sprintf("SELECT pg_temp.pp_source(-6230,'%s')::text", actor))
fx_json <- psql_value(sprintf("SELECT pg_temp.rp_post(%s::jsonb,'cc',-623001,'{\"binding\":\"withdrawn\"}')::text",
                               DBI::dbQuoteLiteral(controller, src_json)))
src <- jsonlite::fromJSON(src_json, simplifyVector = FALSE)
fx <- jsonlite::fromJSON(fx_json, simplifyVector = FALSE)
payload <- psql_value(sprintf("SELECT pg_temp.rp_payload(%s::jsonb,%s::jsonb)::text",
                              DBI::dbQuoteLiteral(controller, src_json), DBI::dbQuoteLiteral(controller, fx_json)))
element <- "record-persona:cc"
elements <- psql_value(sprintf("SELECT jsonb_build_object(%s::text,%s::jsonb)::text",
                               DBI::dbQuoteLiteral(controller, element), DBI::dbQuoteLiteral(controller, payload)))
begin_batch <- function(profile, tag) {
  psql_value(sprintf("SELECT pg_temp.rp_begin(%s::jsonb,'%s','%s',%s::jsonb)::text",
                     DBI::dbQuoteLiteral(controller, src_json), profile, tag, DBI::dbQuoteLiteral(controller, elements)))
}
batch_a <- begin_batch("fixture-pub-a", "conc-a")
batch_b <- begin_batch("fixture-pub-b", "conc-b")
apply_sql <- function(batch) {
  sprintf("SELECT public.red_apply_reimport_record_persona('%s'::uuid,%s,%s::jsonb)::text", batch,
          DBI::dbQuoteLiteral(controller, element), DBI::dbQuoteLiteral(controller, payload))
}
personas <- function() as.integer(scalar(controller, "SELECT count(*) FROM private.source_persona WHERE source_id=-6230"))
expect_true(personas() == 0L, "RECORD_PERSONA_CONCURRENCY_PRECONDITION")
expect_true(identical(as.character(scalar(controller, paste0(
  "SELECT string_agg(status,',' ORDER BY id) FROM private.narrative_record_publication WHERE source_record_id=$1::uuid"),
  list(fx$record))), "withdrawn"), "RECORD_PERSONA_CONCURRENCY_BARRIER_NOT_WITHDRAWN")

barrier <- connect("rp_barrier")
DBI::dbBegin(barrier)
invisible(scalar(barrier, "SELECT count(*) FROM (SELECT 1 FROM private.narrative_record_publication WHERE source_record_id=$1::uuid FOR UPDATE) x",
                 list(fx$record)))
barrier_pid <- as.integer(scalar(barrier, "SELECT pg_backend_pid()"))
job_a <- launch_worker("rp_a", apply_sql(batch_a))
wait_blocked_by(observer, "rp_a", barrier_pid)
a_pid <- backend_pid(observer, "rp_a")
# A har recordlåsen og venter på publikationsrækken; B skal vente på A's recordlås.
job_b <- launch_worker("rp_b", apply_sql(batch_b))
wait_blocked_by(observer, "rp_b", a_pid)
# B venter på A's transaktion (recordrækken), ikke blot i kø bag A på controllerens lås: uden recordlåsen ville B vente
# på controllerens transaktion, og pg_blocking_pids ville stadig pege på A (A står først i samme kø).
deadline <- Sys.time() + 15
repeat {
  waits_on_record <- isTRUE(scalar(observer, paste0(
    "SELECT EXISTS(SELECT 1 FROM pg_locks w JOIN pg_stat_activity wa ON wa.pid=w.pid ",
    "JOIN pg_locks h ON h.pid=$1 AND h.locktype='transactionid' AND h.granted AND h.transactionid=w.transactionid ",
    "WHERE wa.application_name='rp_b' AND wa.datname=current_database() AND w.locktype='transactionid' AND NOT w.granted)"),
    list(a_pid)))
  if (waits_on_record) break
  if (Sys.time() > deadline) stop("RECORD_PERSONA_CONCURRENCY_B_NOT_WAITING_ON_RECORD", call. = FALSE)
  Sys.sleep(0.02)
}
expect_true(personas() == 0L, "RECORD_PERSONA_CONCURRENCY_WROTE_WHILE_WAITING")
DBI::dbCommit(barrier)
DBI::dbDisconnect(barrier)
result_a <- collect_worker(job_a)
result_b <- collect_worker(job_b)
expect_true(identical(result_a$code, "OK"), paste0("RECORD_PERSONA_CONCURRENCY_A_FAILED: ", result_a$output))
expect_true(identical(result_b$code, "RECORD_PERSONA_EXISTS"), paste0("RECORD_PERSONA_CONCURRENCY_B_NOT_EXISTS: ", result_b$output))
expect_true(personas() == 1L, "RECORD_PERSONA_CONCURRENCY_PERSONA_COUNT")
expect_true(as.integer(scalar(controller, "SELECT count(*) FROM private.source_persona_mention WHERE mention_id=$1::uuid", list(fx$mention))) == 1L,
            "RECORD_PERSONA_CONCURRENCY_MENTION_COUNT")
expect_true(as.integer(scalar(controller, "SELECT count(*) FROM private.reimport_event WHERE batch_id=$1::uuid", list(batch_b))) == 0L,
            "RECORD_PERSONA_CONCURRENCY_B_EVENT")

cleanup_fixtures(controller)
expect_true(as.integer(scalar(controller, "SELECT count(*) FROM public.source WHERE id=-6230")) == 0L, "RECORD_PERSONA_CONCURRENCY_CLEANUP")
cat(sprintf("OK: test-record-persona-concurrency (%d assertions, %.1f s)\n", assertions,
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
