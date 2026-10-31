#!/usr/bin/env Rscript

# Trin 6b, Task 6: publication_identity (ceremoni C) mod to rigtige samtidige sessioner (PostgreSQL 17). En "holder"-
# forbindelse holder én side åben i en transaktion; den anden side er en selvstændig R-proces (processx) med sin egen
# RPostgres-forbindelse; en observatør ser ventetiderne med pg_blocking_pids og pg_locks.
#
# (a) C mod en tilbagetrækning (red_tilbagetraek_person_narrative_record) af samme record, begge rækkefølger:
#   a1: C (apply) holder recorden; tilbagetrækningen venter på recordens række og lykkes, når C committer —
#       C ændrer ikke publiceringstilstanden (spec §4.3 pkt. 5: projektejeren kan trække en F tilbage efter C);
#   a2: tilbagetrækningen holder recorden; C venter på recordens række og afvises med PUBLICATION_IDENTITY_BINDING_DRIFT.
#   Ingen deadlock i nogen rækkefølge.
# (b) C mod red_record_identity_candidates (eksklusiv kildelås):
#   b1: C (apply) holder låsen; registreringen af en ny kørsel venter og lykkes, når C committer;
#   b2: registreringen holder låsen; C venter og afvises med PUBLICATION_IDENTITY_RUN_STALE.
#
# Kræver en base som klausul-writer-testene: evidence-promotion-bootstrap, schema.sql, db-rls.sql,
# 1939-v50-writer-bootstrap, reimport-writer-v2-bootstrap, (db-migrations.sql to gange, db-rls.sql).
# Testen committer syntetiske fixtures (kilde -6640) og rydder dem ved start og slut, så den kan genkøres på samme base.
# Codex 6B-01: finalize kræver hele B-batchens kontrolmængde, så hvert scenarie committer kun sin apply (én persona af
# fire); låsene, scenarierne prøver, tages af apply. Finalize og mængdekontrollen dækkes i test-publication-identity.sql.
# Køres fra repo-roden.

required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg_values <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg_values) || any(!nzchar(pg_values))) {
  stop("PUBLICATION_IDENTITY_CONCURRENCY_ALL_FIVE_PG_VARIABLES_REQUIRED: ", paste(required_pg, collapse = ", "), call. = FALSE)
}
for (package in c("DBI", "RPostgres", "processx", "jsonlite")) {
  if (!requireNamespace(package, quietly = TRUE)) stop("PUBLICATION_IDENTITY_CONCURRENCY_R_PACKAGES_REQUIRED: ", package, call. = FALSE)
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
  DBI::dbExecute(con, "SET statement_timeout='30s'")
  con
}
scalar <- function(con, sql, params = list()) {
  result <- if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  if (nrow(result) != 1L || ncol(result) != 1L) stop("PUBLICATION_IDENTITY_CONCURRENCY_SCALAR_SHAPE: ", sql, call. = FALSE)
  result[[1L]][[1L]]
}

# Fixturefunktionerne er pg_temp-funktioner; hvert psql-kald indlæser dem i sin egen session og returnerer én værdi.
fixture_file <- file.path("tests", "sql", "fixtures", "publication-identity.sql")
psql_value <- function(sql) {
  args <- c("-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-f", fixture_file, "-c", sql)
  result <- processx::run("psql", args, env = c("current", PGOPTIONS = "-c client_min_messages=warning"), error_on_status = FALSE)
  if (result$status != 0L) stop("PUBLICATION_IDENTITY_CONCURRENCY_FIXTURE_FAILED: ", result$stderr, call. = FALSE)
  lines <- strsplit(trimws(result$stdout), "\n", fixed = TRUE)[[1L]]
  lines[[length(lines)]]
}

actor <- "11000000-0000-0000-0000-00000006b6c1"
worker_program <- paste0(
  "args<-commandArgs(trailingOnly=TRUE);application_name<-args[[1L]];sql<-args[[2L]];actor_id<-args[[3L]];",
  "con<-DBI::dbConnect(RPostgres::Postgres(),dbname=Sys.getenv('PGDATABASE'),host=Sys.getenv('PGHOST'),",
  "port=as.integer(Sys.getenv('PGPORT')),user=Sys.getenv('PGUSER'),password=Sys.getenv('PGPASSWORD'));",
  "on.exit(DBI::dbDisconnect(con),add=TRUE);",
  "DBI::dbGetQuery(con,\"SELECT set_config('application_name',$1,false)\",params=list(application_name));",
  "DBI::dbExecute(con,\"SET statement_timeout='30s'\");",
  "DBI::dbGetQuery(con,\"SELECT set_config('request.jwt.claim.sub',$1,false)\",params=list(actor_id));",
  "DBI::dbExecute(con,'SET ROLE authenticated');",
  "code<-tryCatch({v<-DBI::dbGetQuery(con,sql);cat('PI_VALUE:',as.character(v[[1L]][[1L]]),'\\n',sep='');'OK'},",
  "error=function(error){message<-conditionMessage(error);",
  "cat('PI_DB_ERROR:',gsub('[\\r\\n]+',' | ',message),'\\n',file=stderr(),sep='');",
  "if(grepl('deadlock detected',message,fixed=TRUE))'DEADLOCK' else {",
  "match<-regexpr('(?:PUBLICATION_IDENTITY|NARRATIVE_RECORD|IDENTITY_CANDIDATE|RECORD|EVIDENCE|REIMPORT)_[A-Z0-9_]+',message,perl=TRUE);",
  "if(match[[1L]]<0L)'UNCLASSIFIED_DATABASE_ERROR' else regmatches(message,match)}});",
  "cat('PI_RESULT_CODE:',code,'\\n',sep='')"
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
collect_worker <- function(job, timeout = 40) {
  deadline <- Sys.time() + timeout
  while (job$is_alive()) {
    if (Sys.time() > deadline) { try(job$kill(), silent = TRUE); stop("PUBLICATION_IDENTITY_CONCURRENCY_WORKER_TIMEOUT", call. = FALSE) }
    Sys.sleep(0.02)
  }
  output <- paste(job$read_all_output(), job$read_all_error(), sep = "\n")
  code <- regmatches(output, regexec("PI_RESULT_CODE:([A-Z0-9_]+)", output, perl = TRUE))[[1L]]
  if (length(code) != 2L) stop("PUBLICATION_IDENTITY_CONCURRENCY_WORKER_RESULT_INVALID: ", output, call. = FALSE)
  list(code = code[[2L]], output = output)
}
backend_pid <- function(observer, application_name, timeout = 15) {
  deadline <- Sys.time() + timeout
  repeat {
    pid <- DBI::dbGetQuery(observer, "SELECT pid FROM pg_stat_activity WHERE datname=current_database() AND application_name=$1",
                           params = list(application_name))
    if (nrow(pid) == 1L) return(as.integer(pid$pid[[1L]]))
    if (Sys.time() > deadline) stop("PUBLICATION_IDENTITY_CONCURRENCY_SESSION_NOT_FOUND: ", application_name, call. = FALSE)
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
    if (Sys.time() > deadline) stop("PUBLICATION_IDENTITY_CONCURRENCY_EXPECTED_LOCK_WAIT_NOT_OBSERVED: ", application_name, call. = FALSE)
    Sys.sleep(0.02)
  }
}
# Venteren står på recordens række: den har (som første venter) rækkens tuple-lås på private.source_record.
waits_on_record_row <- function(observer, application_name) {
  isTRUE(scalar(observer, paste0(
    "SELECT EXISTS(SELECT 1 FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid ",
    "WHERE a.application_name=$1 AND a.datname=current_database() AND l.locktype='tuple' ",
    "AND l.relation='private.source_record'::regclass)"), list(application_name)))
}
# Venteren står på en rådgivende lås (kildens kandidatlås).
waits_on_advisory <- function(observer, application_name) {
  isTRUE(scalar(observer, paste0(
    "SELECT EXISTS(SELECT 1 FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid ",
    "WHERE a.application_name=$1 AND a.datname=current_database() AND l.locktype='advisory' AND NOT l.granted)"),
    list(application_name)))
}

# Rydder testens committede fixtures (kilde -6640, personer -6640001..-6640004). Som superbruger uden triggere
# (evidensrækkerne er append-only); rækkefølgen er uden betydning, når fremmednøgler er slået fra.
cleanup_fixtures <- function(con) {
  recs <- "SELECT id FROM private.source_record WHERE source_id=-6640"
  obs <- paste0("SELECT o.id FROM private.source_observation o JOIN private.source_record_occurrence c ON c.id=o.occurrence_id ",
                "JOIN private.source_rendition r ON r.id=c.rendition_id WHERE r.source_id=-6640")
  rends <- "SELECT id FROM private.source_rendition WHERE source_id=-6640"
  personas <- "SELECT id FROM private.source_persona WHERE source_id=-6640"
  runs <- "SELECT id FROM private.source_persona_identity_candidate_run WHERE source_id=-6640"
  sets <- sprintf("SELECT id FROM public.change_set WHERE actor_id='%s'", actor)
  statements <- c(
    "DELETE FROM private.reimport_event WHERE batch_id IN (SELECT id FROM private.reimport_batch WHERE source_id=-6640)",
    "DELETE FROM private.reimport_batch WHERE source_id=-6640",
    "DELETE FROM private.reimport_authorization WHERE source_id=-6640",
    "DELETE FROM private.reimport_writer_profile WHERE source_id=-6640",
    paste0("DELETE FROM private.source_persona_identity_event WHERE source_persona_id IN (", personas, ")"),
    paste0("DELETE FROM private.source_persona_identity WHERE source_persona_id IN (", personas, ")"),
    paste0("DELETE FROM private.source_persona_identity_candidate WHERE run_id IN (", runs, ")"),
    "DELETE FROM private.source_persona_identity_candidate_run WHERE source_id=-6640",
    paste0("DELETE FROM private.source_persona_mention WHERE persona_id IN (", personas, ")"),
    "DELETE FROM private.source_persona WHERE source_id=-6640",
    paste0("DELETE FROM private.source_mention WHERE observation_id IN (", obs, ")"),
    paste0("DELETE FROM private.source_record_anchor_event WHERE source_record_id IN (", recs, ")"),
    paste0("DELETE FROM private.source_observation WHERE id IN (", obs, ")"),
    paste0("DELETE FROM private.source_record_occurrence WHERE rendition_id IN (", rends, ")"),
    paste0("DELETE FROM private.narrative_publication_event WHERE source_record_id IN (", recs, ")"),
    paste0("DELETE FROM private.narrative_record_publication WHERE source_record_id IN (", recs, ")"),
    "DELETE FROM private.source_record WHERE source_id=-6640",
    "DELETE FROM private.source_rendition WHERE source_id=-6640",
    "DELETE FROM private.extraction_run WHERE source_id=-6640",
    paste0("DELETE FROM public.change_event WHERE change_set_id IN (", sets, ")"),
    paste0("DELETE FROM public.change_set WHERE id IN (", sets, ")"),
    "DELETE FROM public.narrative WHERE source_id=-6640",
    "DELETE FROM public.person_external_id WHERE source_id=-6640",
    "DELETE FROM public.person WHERE id BETWEEN -6640004 AND -6640001",
    "DELETE FROM public.source WHERE id=-6640")
  DBI::dbBegin(con)
  tryCatch({
    DBI::dbExecute(con, "SET LOCAL session_replication_role=replica")
    for (statement in statements) DBI::dbExecute(con, statement)
    DBI::dbCommit(con)
  }, error = function(error) { try(DBI::dbRollback(con), silent = TRUE); stop(error) })
}

controller <- connect("pi_controller")
observer <- connect("pi_observer")
holder <- connect("pi_holder")
on.exit({
  try(DBI::dbRollback(holder), silent = TRUE)
  try(cleanup_fixtures(controller), silent = TRUE)
  DBI::dbDisconnect(holder); DBI::dbDisconnect(controller); DBI::dbDisconnect(observer)
}, add = TRUE)
cleanup_fixtures(controller)
holder_pid <- as.integer(scalar(holder, "SELECT pg_backend_pid()"))
q <- function(value) DBI::dbQuoteLiteral(controller, value)

# Verden: fire B-personas (alle svag: navn uden årstal) og kørsel 1.
world <- psql_value(sprintf("SELECT pg_temp.pi_world(-6640,'%s',4)::text", actor))
cfg <- '{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}'
cands <- psql_value(sprintf(paste0(
  "SELECT jsonb_agg(pg_temp.pi_cand(pg_temp.pi_persona(%s::jsonb,i),-6640000-i,1,",
  "jsonb_build_array(pg_temp.pi_ms(-6640000-i,0.95,ARRAY['name']))) ORDER BY i)::text FROM generate_series(1,4) i"), q(world)))
run1 <- psql_value(sprintf("SELECT pg_temp.pi_run(%s::jsonb,%s::jsonb,%s::jsonb)::text", q(world), q(cfg), q(cands)))
payload <- function(i, run) psql_value(sprintf("SELECT pg_temp.pi_payload(%s::jsonb,%d,'%s','svag','S')::text", q(world), i, run))
element <- function(p) psql_value(sprintf("SELECT pg_temp.pi_el(%s::jsonb)", q(p)))
begin_batch <- function(tag, p) {
  psql_value(sprintf("SELECT pg_temp.pi_begin(%s::jsonb,'%s',pg_temp.pi_elements(jsonb_build_array(%s::jsonb)))::text",
                     q(world), tag, q(p)))
}
apply_sql <- function(batch, p) {
  sprintf("SELECT public.red_apply_reimport_publication_identity('%s'::uuid,%s,%s::jsonb)::text", batch, q(element(p)), q(p))
}
holder_begin <- function() {
  DBI::dbBegin(holder)
  DBI::dbGetQuery(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", params = list(actor))
  invisible(DBI::dbExecute(holder, "SET LOCAL ROLE authenticated"))
}
persona_id <- function(i) psql_value(sprintf("SELECT pg_temp.pi_persona(%s::jsonb,%d)::text", q(world), i))
identity_of <- function(i) {
  DBI::dbGetQuery(controller, "SELECT decision_status,version FROM private.source_persona_identity WHERE source_persona_id=$1::uuid",
                  params = list(persona_id(i)))
}
state_sha <- function(i) {
  as.character(scalar(controller, sprintf("SELECT private.narrative_record_state(%d,-6640,'r%d',false)->>'state_sha256'", -6640000L - i, i)))
}
binding_status <- function(i) {
  as.character(scalar(controller, paste0("SELECT b.status FROM private.narrative_record_publication b ",
    "JOIN private.source_record r ON r.id=b.source_record_id WHERE r.source_id=-6640 AND r.record_key=$1 ORDER BY b.id LIMIT 1"),
    list(paste0("r", i))))
}
withdraw_sql <- function(i, sha) {
  sprintf("SELECT public.red_tilbagetraek_person_narrative_record(%d,-6640,'r%d','%s')::text", -6640000L - i, i, sha)
}

# a1: C (apply) holder recorden r1; tilbagetrækningen venter på recordens række.
p1 <- payload(1, run1); batch_a1 <- begin_batch("conc-a1", p1); sha1 <- state_sha(1)
holder_begin()
invisible(scalar(holder, apply_sql(batch_a1, p1)))
job <- launch_worker("pi_wd1", withdraw_sql(1, sha1))
wait_blocked_by(observer, "pi_wd1", holder_pid)
expect_true(waits_on_record_row(observer, "pi_wd1"), "PUBLICATION_IDENTITY_CONCURRENCY_A1_NOT_ON_RECORD")
DBI::dbCommit(holder)
result <- collect_worker(job)
expect_true(identical(result$code, "OK"), paste0("PUBLICATION_IDENTITY_CONCURRENCY_A1_WITHDRAWAL: ", result$output))
id1 <- identity_of(1)
expect_true(nrow(id1) == 1L && id1$decision_status == "accepted" && id1$version == 1L, "PUBLICATION_IDENTITY_CONCURRENCY_A1_IDENTITY")
expect_true(identical(binding_status(1), "withdrawn"), "PUBLICATION_IDENTITY_CONCURRENCY_A1_BINDING")

# a2: tilbagetrækningen holder recorden r2; C venter på recordens række og afvises.
p2 <- payload(2, run1); batch_a2 <- begin_batch("conc-a2", p2); sha2 <- state_sha(2)
holder_begin()
invisible(scalar(holder, withdraw_sql(2, sha2)))
job <- launch_worker("pi_c2", apply_sql(batch_a2, p2))
wait_blocked_by(observer, "pi_c2", holder_pid)
expect_true(waits_on_record_row(observer, "pi_c2"), "PUBLICATION_IDENTITY_CONCURRENCY_A2_NOT_ON_RECORD")
DBI::dbCommit(holder)
result <- collect_worker(job)
expect_true(identical(result$code, "PUBLICATION_IDENTITY_BINDING_DRIFT"), paste0("PUBLICATION_IDENTITY_CONCURRENCY_A2_C: ", result$output))
expect_true(nrow(identity_of(2)) == 0L, "PUBLICATION_IDENTITY_CONCURRENCY_A2_WROTE")

# b1: C holder den eksklusive kandidatlås; registreringen af kørsel 2 venter og lykkes, når C committer.
p3 <- payload(3, run1); batch_b1 <- begin_batch("conc-b1", p3)
spec <- psql_value(sprintf(paste0("SELECT jsonb_build_object('mode','list','persona_ids',jsonb_agg(x ORDER BY x))::text ",
                                  "FROM jsonb_array_elements_text(%s::jsonb->'personas') x"), q(world)))
register_sql <- function(config) {
  sprintf(paste0("SELECT public.red_record_identity_candidates(jsonb_build_object('source_id',-6640,'generator_version','t6b',",
                 "'config',%s::jsonb,'input_spec',%s::jsonb,'input_sha256',public.red_identity_candidate_input(-6640,%s::jsonb)->>'input_sha256'),",
                 "%s::jsonb)::text"), q(config), q(spec), q(spec), q(cands))
}
holder_begin()
invisible(scalar(holder, apply_sql(batch_b1, p3)))
job <- launch_worker("pi_reg1", register_sql('{"topK":10,"autoCutoff":0.9,"controlMargin":0.05,"v":2}'))
wait_blocked_by(observer, "pi_reg1", holder_pid)
expect_true(waits_on_advisory(observer, "pi_reg1"), "PUBLICATION_IDENTITY_CONCURRENCY_B1_NOT_ON_SOURCE_LOCK")
DBI::dbCommit(holder)
result <- collect_worker(job)
expect_true(identical(result$code, "OK"), paste0("PUBLICATION_IDENTITY_CONCURRENCY_B1_REGISTRATION: ", result$output))
expect_true(nrow(identity_of(3)) == 1L, "PUBLICATION_IDENTITY_CONCURRENCY_B1_IDENTITY")
run2 <- as.character(scalar(controller,
  "SELECT id::text FROM private.source_persona_identity_candidate_run WHERE source_id=-6640 ORDER BY run_seq DESC LIMIT 1"))
expect_true(!identical(run2, run1), "PUBLICATION_IDENTITY_CONCURRENCY_B1_NO_NEW_RUN")

# b2: registreringen af kørsel 3 holder låsen; C (mod kørsel 2, den seneste ved autorisationen) venter og afvises.
p4 <- payload(4, run2); batch_b2 <- begin_batch("conc-b2", p4)
holder_begin()
invisible(scalar(holder, register_sql('{"topK":10,"autoCutoff":0.9,"controlMargin":0.05,"v":3}')))
job <- launch_worker("pi_c4", apply_sql(batch_b2, p4))
wait_blocked_by(observer, "pi_c4", holder_pid)
expect_true(waits_on_advisory(observer, "pi_c4"), "PUBLICATION_IDENTITY_CONCURRENCY_B2_NOT_ON_SOURCE_LOCK")
DBI::dbCommit(holder)
result <- collect_worker(job)
expect_true(identical(result$code, "PUBLICATION_IDENTITY_RUN_STALE"), paste0("PUBLICATION_IDENTITY_CONCURRENCY_B2_C: ", result$output))
expect_true(nrow(identity_of(4)) == 0L, "PUBLICATION_IDENTITY_CONCURRENCY_B2_WROTE")

cleanup_fixtures(controller)
expect_true(as.integer(scalar(controller, "SELECT count(*) FROM public.source WHERE id=-6640")) == 0L, "PUBLICATION_IDENTITY_CONCURRENCY_CLEANUP")
cat(sprintf("OK: test-publication-identity-concurrency (%d assertions, %.1f s)\n", assertions,
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
