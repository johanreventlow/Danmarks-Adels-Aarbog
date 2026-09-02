# Disposable Task 8 proof: the SQL lifecycle, not a cooperative R mutex,
# holds a transaction-scoped `(source_id, profile_id)` writer lock.
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })
source(".claude/skills/daa-extract/scripts/apply_name_completion_helpers.R")

required_pg <- c("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD")
stopifnot(!any(is.na(Sys.getenv(required_pg, unset = NA_character_))))

connect <- function() {
  dbConnect(
    Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
    port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD")
  )
}
query <- function(con, sql, params = list()) {
  if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
}
execute <- function(con, sql, params = list()) {
  if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql)
}

# Each concurrent probe is an independently exec'd psql client.  Forking after
# RPostgres/libpq connections exist is unsafe on macOS and inherits native state.
worker_script <- tempfile("reimport-writer-lock-worker-", fileext = ".sh")
psql_binary <- Sys.which("psql")
if (!nzchar(psql_binary)) psql_binary <- "/opt/homebrew/opt/postgresql@17/bin/psql"
stopifnot(file.exists(psql_binary))
writeLines(c(
  "#!/bin/sh",
  "touch \"$1\"",
  "tmp=\"$3.pending.$$\"",
  "status_tmp=\"$5.pending.$$\"",
  paste0(shQuote(psql_binary), " -X -v ON_ERROR_STOP=1 -At -f \"$2\" > \"$tmp\" 2> \"$4\""),
  "rc=$?",
  "if [ \"$rc\" -eq 0 ]; then mv \"$tmp\" \"$3\"; else mv \"$tmp\" \"$3.failed\"; fi",
  "printf '%s\\n' \"$rc\" > \"$status_tmp\"",
  "mv \"$status_tmp\" \"$5\"",
  "exit \"$rc\""
), worker_script)
on.exit(unlink(worker_script), add = TRUE)

sql_literal <- function(value) paste0("'", gsub("'", "''", value, fixed = TRUE), "'")

# The worker writes status only by atomic rename after psql has committed or
# exited with an error.  A missing or empty status is therefore still pending,
# never evidence of either success or failure.
worker_status <- function(worker) {
  if (!file.exists(worker$status_path)) return(NULL)
  status <- readLines(worker$status_path, warn = FALSE)
  if (length(status) != 1L || !nzchar(status[[1L]])) return(NULL)
  status[[1L]]
}

launch_worker <- function(operation, actor, first, second = "", third = "", hold_after_apply = FALSE) {
  ready_path <- tempfile(paste0("reimport-writer-lock-ready-", operation, "-"))
  result_path <- tempfile(paste0("reimport-writer-lock-", operation, "-"))
  log_path <- tempfile(paste0("reimport-writer-lock-log-", operation, "-"))
  status_path <- tempfile(paste0("reimport-writer-lock-status-", operation, "-"))
  sql_path <- tempfile(paste0("reimport-writer-lock-sql-", operation, "-"), fileext = ".sql")
  worker_application <- paste0("reimport-lock-", operation)
  prefix <- c(
    "BEGIN;",
    paste0("SELECT set_config('request.jwt.claim.sub',", sql_literal(actor), ",true);"),
    paste0("SET application_name TO ", sql_literal(worker_application), ";")
  )
  select_result <- switch(operation,
    begin = paste0("SELECT 'OK:' || public.red_begin_reimport(", sql_literal(first), "::uuid,", sql_literal(second), ",", sql_literal(third), ");"),
    batch_result = paste0("SELECT 'OK:' || public.red_reimport_batch_result(", sql_literal(first), "::uuid,", sql_literal(second), "::uuid)::text;"),
    reversal_authorize = paste0("SELECT 'OK:' || public.red_authorize_reimport_reversal(", sql_literal(first), "::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');"),
    finalize_reimport = paste0("SELECT 'OK:' || public.red_finalize_reimport(", sql_literal(first), "::uuid)::text;"),
    completion_finalize = paste0("SELECT 'OK:' || public.red_finalize_reimport_name_completion(", sql_literal(first), "::uuid)::text;"),
    activate = paste0("SELECT 'OK:' || public.red_activate_reimport_batch(", sql_literal(first), "::uuid,", sql_literal(second), "::uuid)::text;"),
    completion_apply = {
      state <- jsonlite::fromJSON(first, simplifyVector = FALSE)
      payload <- jsonlite::toJSON(state$payload, auto_unbox = TRUE, null = "null")
      prefix <- c(prefix, paste0("SELECT set_config('application_name',", sql_literal(second), ",true);"))
      c(
        paste0("SELECT public.red_apply_reimport_name_completion(", sql_literal(state$child_batch_id), "::uuid,", sql_literal(state$element_id), ",", sql_literal(payload), "::jsonb);"),
        if (hold_after_apply) "SELECT pg_sleep(5);" else character(),
        paste0("SELECT 'OK:' || public.red_finalize_reimport_name_completion(", sql_literal(state$child_batch_id), "::uuid)::text;")
      )
    }
  )
  writeLines(c(prefix, select_result, "COMMIT;"), sql_path)
  system2("/bin/sh", c(worker_script, ready_path, sql_path, result_path, log_path, status_path), wait = FALSE)
  for (i in seq_len(200L)) {
    if (file.exists(ready_path)) return(list(ready_path = ready_path, result_path = result_path, log_path = log_path, status_path = status_path, sql_path = sql_path, application_name = worker_application))
    if (file.exists(result_path)) stop(operation, " worker failed before its query boundary: ", paste(readLines(result_path, warn = FALSE), collapse = " "))
    Sys.sleep(0.05)
  }
  stop(operation, " worker did not reach its query boundary: ", paste(readLines(log_path, warn = FALSE), collapse = " "))
}

wait_for_worker_query <- function(worker, function_name) {
  for (i in seq_len(200L)) {
    status <- worker_status(worker)
    if (!is.null(status) && status != "0") {
      stop("worker failed before ", function_name, ": ", paste(readLines(worker$log_path, warn = FALSE), collapse = " "))
    }
    active <- query(holder, "SELECT count(*) count FROM pg_stat_activity WHERE application_name=$1 AND query LIKE $2", list(worker$application_name, paste0("%", function_name, "%")))$count[[1L]]
    if (active == 1L) return(invisible())
    Sys.sleep(0.05)
  }
  stop("worker did not reach ", function_name, ": ", paste(readLines(worker$log_path, warn = FALSE), collapse = " "))
}
await_worker <- function(worker, label) {
  for (i in seq_len(200L)) {
    if (identical(worker_status(worker), "0") && file.exists(worker$result_path)) {
      result <- readLines(worker$result_path, warn = FALSE)
      complete <- result[startsWith(result, "OK:")]
      if (length(complete) == 1L) {
        unlink(c(worker$ready_path, worker$result_path, worker$log_path, worker$status_path, worker$sql_path))
        return(invisible(complete))
      }
    }
    Sys.sleep(0.05)
  }
  stop(label, " worker did not finish: ", paste(readLines(worker$log_path, warn = FALSE), collapse = " "))
}
await_worker_error <- function(worker, token, label) {
  for (i in seq_len(200L)) {
    status <- worker_status(worker)
    if (!is.null(status)) {
      log <- paste(readLines(worker$log_path, warn = FALSE), collapse = " ")
      unlink(c(worker$ready_path, worker$result_path, paste0(worker$result_path, ".failed"), worker$log_path, worker$status_path, worker$sql_path))
      stopifnot(status != "0", grepl(token, log, fixed = TRUE))
      return(invisible())
    }
    Sys.sleep(0.05)
  }
  stop(label, " worker did not fail")
}

holder <- connect()
same_profile <- connect()
other_profile <- connect()
on.exit(try(dbDisconnect(other_profile), silent = TRUE), add = TRUE)
on.exit(try(dbDisconnect(same_profile), silent = TRUE), add = TRUE)
on.exit(try(dbDisconnect(holder), silent = TRUE), add = TRUE)

actor <- "15380000-0000-4000-8000-000000000001"
source_id <- -153801L
profile_id <- "task8-lock"
other_profile_id <- "task8-lock-other"
config <- paste0(
  '{"run_key_prefix":"task8:","schema_version":"task8","extractor_version":"task8",',
  '"rendition_key":"task8","rendition_kind":"ocr_text","rendition_metadata":{},',
  '"observation_extraction_method":"task8","citation_label_template":"Task 8 {page_from}"}'
)

stopifnot(query(holder, "SELECT public.narrative_record_contract_version() version")$version[[1L]] == 2L)
execute(holder, "INSERT INTO auth.users(id,email) VALUES($1,'task8-lock@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
execute(holder, "INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'task8-lock@example.invalid','redaktion','Task 8 lock') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
execute(holder, "INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Task 8 lock','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING", list(source_id))
profile_hash <- query(holder, "SELECT private.reimport_canonical_json_sha256($1::jsonb) hash", list(config))$hash[[1L]]
for (id in c(profile_id, other_profile_id)) {
  execute(holder, paste(
    "INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)",
    "VALUES($1,$2,'task8',$3,$4::jsonb) ON CONFLICT(source_id,profile_id) DO NOTHING"
  ), list(source_id, id, profile_hash, config))
}

dbBegin(holder)
execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
execute(holder, "SET LOCAL ROLE service_role")
query(holder, paste(
  "SELECT public.red_authorize_reimport(repeat('8',64),repeat('7',64),",
  "jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,",
  "$1,$2,$3,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '1 minute') id"
), list(source_id, profile_id, profile_hash))

same_key <- paste("daa-reimport-writer", source_id, profile_id, sep = ":")
other_key <- paste("daa-reimport-writer", source_id, other_profile_id, sep = ":")
dbBegin(same_profile)
same_acquired <- query(same_profile, "SELECT pg_try_advisory_xact_lock(hashtextextended($1,0)) acquired", list(same_key))$acquired[[1L]]
dbRollback(same_profile)
dbBegin(other_profile)
other_acquired <- query(other_profile, "SELECT pg_try_advisory_xact_lock(hashtextextended($1,0)) acquired", list(other_key))$acquired[[1L]]
dbRollback(other_profile)
dbRollback(holder)

stopifnot(!same_acquired, other_acquired)

# Public lock behavior: its fixed contract binds only manifest + source/profile.
# Wrong source/profile combinations must fail without minting writer state, while
# the correct combination holds the same writer key seen by another connection.
lock_authorizations_before <- query(holder, "SELECT count(*) count FROM private.reimport_authorization")$count[[1L]]
for (lock_args in list(
  list(strrep("8", 64L), source_id + 1L, profile_id),
  list(strrep("8", 64L), source_id, "task8-lock-missing")
)) {
  lock_error <- tryCatch({
    dbBegin(holder)
    execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
    query(holder, "SELECT public.red_lock_reimport_name_completion($1,$2,$3)", lock_args)
    dbRollback(holder)
    ""
  }, error = function(e) {
    try(dbRollback(holder), silent = TRUE)
    conditionMessage(e)
  })
  stopifnot(grepl("REIMPORT_NAME_COMPLETION_INVALID", lock_error, fixed = TRUE))
}
dbBegin(holder)
execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
query(holder, "SELECT public.red_lock_reimport_name_completion($1,$2,$3)", list(strrep("8", 64L), source_id, profile_id))
dbBegin(same_profile)
public_lock_blocks_other <- !query(same_profile, "SELECT pg_try_advisory_xact_lock(hashtextextended($1,0)) acquired", list(same_key))$acquired[[1L]]
dbRollback(same_profile)
dbRollback(holder)
stopifnot(public_lock_blocks_other, query(holder, "SELECT count(*) count FROM private.reimport_authorization")$count[[1L]] == lock_authorizations_before)

# Task 11: profile lock must be acquired before any mutable authorization or
# batch row lock.  Every worker is an independent process; C's NOWAIT lock is
# the observable proof that B is waiting only on A's advisory lock.
execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))
task11_begin_auth <- query(holder, paste(
  "SELECT public.red_authorize_reimport(repeat('1',64),repeat('2',64),",
  "jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,",
  "$1,$2,$3,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id"
), list(source_id, profile_id, profile_hash))$id[[1L]]

# Discovery-to-lock drift: B has discovered the old tuple and is waiting for
# A's old writer key before C changes only the authorization tuple.  On release
# B must reject its post-lock reread without consuming the authorization.
dbBegin(holder)
execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
query(holder, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(same_key))
drift_worker <- launch_worker("begin", actor, task11_begin_auth, strrep("1", 64L), strrep("2", 64L))
for (i in seq_len(200L)) {
  waiting <- query(same_profile, "SELECT count(*) count FROM pg_stat_activity WHERE application_name=$1 AND wait_event_type='Lock' AND query LIKE '%red_begin_reimport%'", list(drift_worker$application_name))$count[[1L]]
  if (waiting == 1L) break
  Sys.sleep(0.05)
}
stopifnot(waiting == 1L)
execute(same_profile, "UPDATE private.reimport_authorization SET profile_id=$2 WHERE id=$1::uuid", list(task11_begin_auth, other_profile_id))
dbRollback(holder)
await_worker_error(drift_worker, "REIMPORT_WRITER_AUTHORIZATION_INVALID", "Task 11 discovery drift")
stopifnot(query(same_profile, "SELECT status FROM private.reimport_authorization WHERE id=$1::uuid", list(task11_begin_auth))$status[[1L]] == "issued")
execute(same_profile, "UPDATE private.reimport_authorization SET profile_id=$2 WHERE id=$1::uuid", list(task11_begin_auth, profile_id))

task11_profile_first <- function(label, operation, first, second = "", third = "", lock_sql, lock_params) {
  dbBegin(holder)
  execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
  query(holder, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(same_key))
  worker <- launch_worker(operation, actor, first, second, third)
  on.exit(unlink(worker$ready_path), add = TRUE)
  wait_for_worker_query(worker, switch(operation,
    begin = "red_begin_reimport",
    batch_result = "red_reimport_batch_result",
    reversal_authorize = "red_authorize_reimport_reversal",
    completion_finalize = "red_finalize_reimport_name_completion",
    activate = "red_activate_reimport_batch"
  ))
  row_lock_error <- tryCatch({
    dbBegin(same_profile)
    query(same_profile, lock_sql, lock_params)
    dbRollback(same_profile)
    ""
  }, error = function(e) {
    try(dbRollback(same_profile), silent = TRUE)
    conditionMessage(e)
  })
  dbRollback(holder)
  stopifnot(!nzchar(row_lock_error))
  await_worker(worker, label)
}

task11_begin_result <- task11_profile_first(
  "Task 11 begin", "begin", task11_begin_auth, strrep("1", 64L), strrep("2", 64L),
  "SELECT id FROM private.reimport_authorization WHERE id=$1::uuid FOR UPDATE NOWAIT", list(task11_begin_auth)
)
task11_source_batch <- sub("^OK:", "", task11_begin_result)
stopifnot(query(holder, "SELECT public.red_finalize_reimport($1::uuid)->>'status' status", list(task11_source_batch))$status[[1L]] == "finalized")

# The shared open-batch helper is used by several lifecycle RPCs.  This probe
# changes the discovered tuple while finalization is observably waiting on its
# old writer key; its re-read must reject without finalizing the batch.
task11_finalize_drift_auth <- query(holder, paste(
  "SELECT public.red_authorize_reimport(repeat('9',64),repeat('8',64),",
  "jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,",
  "$1,$2,$3,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id"
), list(source_id, profile_id, profile_hash))$id[[1L]]
task11_finalize_drift_batch <- query(holder,
  "SELECT public.red_begin_reimport($1::uuid,repeat('9',64),repeat('8',64)) id",
  list(task11_finalize_drift_auth))$id[[1L]]
dbBegin(holder)
execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
query(holder, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(same_key))
finalize_drift_worker <- launch_worker("finalize_reimport", actor, task11_finalize_drift_batch)
for (i in seq_len(200L)) {
  waiting <- query(same_profile, "SELECT count(*) count FROM pg_stat_activity WHERE application_name=$1 AND wait_event_type='Lock' AND query LIKE '%red_finalize_reimport%'", list(finalize_drift_worker$application_name))$count[[1L]]
  if (waiting == 1L) break
  Sys.sleep(0.05)
}
stopifnot(waiting == 1L)
execute(same_profile, "ALTER TABLE private.reimport_batch DISABLE TRIGGER ALL")
execute(same_profile, "UPDATE private.reimport_batch SET profile_id=$2 WHERE id=$1::uuid", list(task11_finalize_drift_batch, other_profile_id))
execute(same_profile, "ALTER TABLE private.reimport_batch ENABLE TRIGGER ALL")
dbRollback(holder)
await_worker_error(finalize_drift_worker, "REIMPORT_WRITER_BATCH_INVALID", "Task 11 shared open-batch discovery drift")
stopifnot(query(same_profile, "SELECT status FROM private.reimport_batch WHERE id=$1::uuid", list(task11_finalize_drift_batch))$status[[1L]] == "open")
execute(same_profile, "ALTER TABLE private.reimport_batch DISABLE TRIGGER ALL")
execute(same_profile, "UPDATE private.reimport_batch SET profile_id=$2 WHERE id=$1::uuid", list(task11_finalize_drift_batch, profile_id))
execute(same_profile, "ALTER TABLE private.reimport_batch ENABLE TRIGGER ALL")

# A direct lifecycle authorization follows the same discovery-to-lock rule.
# While B waits on the old writer key, C changes only the batch profile; no
# reversal authorization may be minted when B re-reads the changed row.
reversal_authorizations_before <- query(holder, "SELECT count(*) count FROM private.reimport_authorization")$count[[1L]]
dbBegin(holder)
execute(holder, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
query(holder, "SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(same_key))
reversal_drift_worker <- launch_worker("reversal_authorize", actor, task11_source_batch)
for (i in seq_len(200L)) {
  waiting <- query(same_profile, "SELECT count(*) count FROM pg_stat_activity WHERE application_name=$1 AND wait_event_type='Lock' AND query LIKE '%red_authorize_reimport_reversal%'", list(reversal_drift_worker$application_name))$count[[1L]]
  if (waiting == 1L) break
  Sys.sleep(0.05)
}
stopifnot(waiting == 1L)
execute(same_profile, "ALTER TABLE private.reimport_batch DISABLE TRIGGER ALL")
execute(same_profile, "UPDATE private.reimport_batch SET profile_id=$2 WHERE id=$1::uuid", list(task11_source_batch, other_profile_id))
execute(same_profile, "ALTER TABLE private.reimport_batch ENABLE TRIGGER ALL")
dbRollback(holder)
await_worker_error(reversal_drift_worker, "REIMPORT_WRITER_REVERSAL_INVALID", "Task 11 reversal discovery drift")
stopifnot(
  query(same_profile, "SELECT status FROM private.reimport_batch WHERE id=$1::uuid", list(task11_source_batch))$status[[1L]] == "finalized",
  query(same_profile, "SELECT count(*) count FROM private.reimport_authorization")$count[[1L]] == reversal_authorizations_before
)
execute(same_profile, "ALTER TABLE private.reimport_batch DISABLE TRIGGER ALL")
execute(same_profile, "UPDATE private.reimport_batch SET profile_id=$2 WHERE id=$1::uuid", list(task11_source_batch, profile_id))
execute(same_profile, "ALTER TABLE private.reimport_batch ENABLE TRIGGER ALL")

task11_result <- task11_profile_first(
  "Task 11 batch result", "batch_result", task11_begin_auth, task11_source_batch,
  lock_sql = "SELECT id FROM private.reimport_authorization WHERE id=$1::uuid FOR UPDATE NOWAIT", lock_params = list(task11_begin_auth)
)
stopifnot(grepl('"status": "finalized"|"status":"finalized"', task11_result))

task11_reversal_result <- task11_profile_first(
  "Task 11 reversal authorization", "reversal_authorize", task11_source_batch,
  lock_sql = "SELECT id FROM private.reimport_batch WHERE id=$1::uuid FOR UPDATE NOWAIT", lock_params = list(task11_source_batch)
)
stopifnot(nzchar(sub("^OK:", "", task11_reversal_result)))

task11_child_auth <- query(holder, paste(
  "INSERT INTO private.reimport_authorization(operation,manifest_sha256,preview_sha256,database_identity,source_id,profile_id,profile_sha256,expected_counts,authorized_elements,principal_id,nonce,expires_at)",
  "VALUES('name_completion',repeat('3',64),repeat('4',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,$1,$2,$3,'{\"name_completions\":0,\"operations\":0}'::jsonb,jsonb_build_object('source_batch_id',$4::uuid,'payloads','{}'::jsonb),$5::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes') RETURNING id"
), list(source_id, profile_id, profile_hash, task11_source_batch, actor))$id[[1L]]
task11_child_batch <- query(holder, paste(
  "INSERT INTO private.reimport_batch(authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,expected_counts)",
  "VALUES($1::uuid,repeat('3',64),repeat('4',64),$2,$3,$4,$5::uuid,'{\"name_completions\":0,\"operations\":0}'::jsonb) RETURNING id"
), list(task11_child_auth, source_id, profile_id, profile_hash, actor))$id[[1L]]
task11_finalize_result <- task11_profile_first(
  "Task 11 name-completion finalize", "completion_finalize", task11_child_batch,
  lock_sql = "SELECT id FROM private.reimport_batch WHERE id=$1::uuid FOR UPDATE NOWAIT", lock_params = list(task11_child_batch)
)
stopifnot(grepl('"status": "finalized"|"status":"finalized"', task11_finalize_result))

task11_cutover_auth <- query(holder,
  "SELECT public.red_authorize_reimport_cutover($1::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",
  list(task11_source_batch))$id[[1L]]
task11_activate_result <- task11_profile_first(
  "Task 11 activation", "activate", task11_source_batch, task11_cutover_auth,
  lock_sql = "SELECT id FROM private.reimport_authorization WHERE id=$1::uuid FOR UPDATE NOWAIT", lock_params = list(task11_cutover_auth)
)
stopifnot(grepl('"status": "activated"|"status":"activated"', task11_activate_result))

# Task 10: two profiles use database identities.  Their concurrent successful
# writes prove allocation safety without a private allocation lock.
fixture_sql <- paste(readLines("tests/sql/reimport-writer-locking-fixture.sql", warn = FALSE), collapse = "\n")
execute(holder, fixture_sql)

task9_source_a <- -153902L
task9_source_b <- -153903L
task9_profile_a <- "task9-name-lock-a"
task9_profile_b <- "task9-name-lock-b"
task9_actor <- "15390000-0000-4000-8000-000000000001"
execute(holder, "INSERT INTO auth.users(id,email) VALUES($1,'task9-lock@example.invalid') ON CONFLICT(id) DO NOTHING", list(task9_actor))
execute(holder, paste(
  "INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'task9-lock@example.invalid','redaktion','Task 9 lock')",
  "ON CONFLICT(id) DO UPDATE SET rolle='redaktion'"
), list(task9_actor))
seed_state <- function(source_id, profile_id, tag) {
  query(holder, "SELECT pg_temp.task9_seed_name_completion($1,$2,$3,$4::uuid) state",
        list(source_id, profile_id, tag, task9_actor))$state[[1L]]
}
state_a_json <- seed_state(task9_source_a, task9_profile_a, "a")
state_b_json <- seed_state(task9_source_b, task9_profile_b, "b")
state_a <- jsonlite::fromJSON(state_a_json, simplifyVector = FALSE)
state_b <- jsonlite::fromJSON(state_b_json, simplifyVector = FALSE)

# This must use the actual DBI gateway response, rather than a fake that adds
# fields the server did not return.  Before the Task 9 review correction, the
# real preflight object lacks its database identity and this call fails closed.
task9_source_c <- 153904L
task9_profile_c <- "task9-dbi-preflight"
state_c_json <- seed_state(task9_source_c, task9_profile_c, "dbi")
state_c <- jsonlite::fromJSON(state_c_json, simplifyVector = FALSE)
operation_c <- state_c$payload
operation_c$element_id <- state_c$element_id
manifest_c <- list(
  manifest_content_sha256 = paste(rep("c", 64L), collapse = ""),
  source = list(id = as.integer(state_c$source_id), profile_id = state_c$profile_id, profile_sha256 = state_c$profile_sha256),
  source_batch_id = state_c$source_batch_id,
  source_manifest_bytes_sha256 = paste(rep("b", 64L), collapse = ""),
  source_manifest_content_sha256 = paste(rep("a", 64L), collapse = ""),
  expected_counts = list(name_completions = 1L, operations = 1L), operations = list(operation_c)
)
Sys.setenv(DAA_REIMPORT_ACTOR_ID = task9_actor)
authorization_c <- list(
  authorization_id = state_c$child_authorization_id,
  database_name = query(holder, "SELECT current_database() name")$name[[1L]],
  system_identifier = as.character(query(holder, "SELECT (pg_control_system()).system_identifier::text id")$id[[1L]]),
  source = manifest_c$source
)
dbi_gateway_c <- new_name_completion_dbi_gateway(connect)
dbi_gateway_c$call("connect")
dbi_gateway_c$call("begin")
dbi_gateway_c$call("advisory_lock", manifest_c$source)
validate_generic_name_completion_preflight(dbi_gateway_c$call("preflight", manifest_c), manifest_c)
payloads_c <- jsonlite::fromJSON(query(holder, paste(
  "SELECT a.authorized_elements->'payloads'::text payloads FROM private.reimport_authorization a",
  "WHERE a.id=$1::uuid"
), list(state_c$child_authorization_id))$payloads[[1L]], simplifyVector = FALSE)
dbi_server_preflight_c <- dbi_gateway_c$call(
  "preflight_authorization", authorization_c, manifest_c, manifest_c$manifest_content_sha256,
  payloads_c
)
validate_name_completion_server_preflight(dbi_server_preflight_c, authorization_c, manifest_c, manifest_c$manifest_content_sha256)
dbi_gateway_c$call("rollback")

# RED evidence for the historic unprotected allocation shape: two sessions read
# the same next id, then the second stale insert collides after the first commits.
collision_other <- connect()
on.exit(try(dbDisconnect(collision_other), silent = TRUE), add = TRUE)
dbBegin(holder)
dbBegin(collision_other)
next_a <- query(holder, "SELECT coalesce(max(id),0)+1 id FROM public.fact")$id[[1L]]
next_b <- query(collision_other, "SELECT coalesce(max(id),0)+1 id FROM public.fact")$id[[1L]]
stopifnot(identical(next_a, next_b))
execute(holder, "INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES($1,'person',$2,'task9-red-max-id')",
        list(next_a, as.numeric(state_a$person_id)))
dbCommit(holder)
collision_error <- tryCatch({
  execute(collision_other, "INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES($1,'person',$2,'task9-red-max-id')",
          list(next_b, as.numeric(state_b$person_id)))
  ""
}, error = function(e) conditionMessage(e))
dbRollback(collision_other)
stopifnot(grepl("duplicate key|unique", collision_error, ignore.case = TRUE))
# The historic stale-id collision uses an explicit fixture id; restore the
# sequence baseline before exercising production default-id allocation.
query(holder, "SELECT setval(pg_get_serial_sequence('public.fact','id'),(SELECT max(id) FROM public.fact),true)")

worker_a <- launch_worker("completion_apply", task9_actor, state_a_json, "task9-name-completion-a", hold_after_apply = TRUE)

# Wait until A has completed its name-completion writes and is holding the
# transaction open in pg_sleep; this replaces the former fork-only ready file.
for (i in seq_len(200L)) {
  active_a <- query(holder, "SELECT count(*) count FROM pg_stat_activity WHERE application_name='task9-name-completion-a' AND query LIKE '%pg_sleep(5)%'")$count[[1L]]
  if (active_a == 1L) break
  Sys.sleep(0.05)
}
if (active_a != 1L) {
  stop("Task 9 worker A did not reach its post-apply hold: result=",
       paste(readLines(worker_a$result_path, warn = FALSE), collapse = " "),
       " log=", paste(readLines(worker_a$log_path, warn = FALSE), collapse = " "))
}

# Task 10 follow-up: this ordinary writer does not participate in the reimport
# writer lock.  It must still allocate distinct default IDs and commit while A
# is held after its identity-backed inserts, before A is released.
ordinary <- connect()
on.exit(try(dbDisconnect(ordinary), silent = TRUE), add = TRUE)
dbBegin(ordinary)
execute(ordinary, "SET LOCAL lock_timeout='500ms'")
ordinary_fact <- query(ordinary, paste(
  "INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)",
  "VALUES('person',$1,'task10-ordinary-concurrent') RETURNING id"
), list(as.numeric(state_a$person_id)))$id[[1L]]
ordinary_assertion <- query(ordinary, paste(
  "INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig)",
  "VALUES('fact',$1,'Task 10 ordinary concurrent',true) RETURNING id"
), list(ordinary_fact))$id[[1L]]
ordinary_citation <- query(ordinary, paste(
  "INSERT INTO public.citation(assertion_id,source_id,side,citat_tekst,kvalitet)",
  "VALUES($1,$2,'1','Task 10 ordinary concurrent','primær') RETURNING id"
), list(ordinary_assertion, task9_source_a))$id[[1L]]
dbCommit(ordinary)

worker_b <- launch_worker("completion_apply", task9_actor, state_b_json, "task9-name-completion-b")
completed_a <- sub("^OK:", "", await_worker(worker_a, "Task 9 writer A"))
completed_b <- sub("^OK:", "", await_worker(worker_b, "Task 9 writer B"))
stopifnot(jsonlite::fromJSON(completed_a)$status == "finalized", jsonlite::fromJSON(completed_b)$status == "finalized")

receipts <- query(holder, paste(
  "SELECT b.id batch_id,b.status,r.fact_id,r.assertion_id,r.citation_id,e.element_id,e.operation,c.citat_tekst",
  "FROM private.reimport_batch b JOIN private.reimport_name_completion_result r ON r.batch_id=b.id",
  "JOIN private.reimport_event e ON e.batch_id=b.id AND e.element_id=r.element_id",
  "JOIN public.citation c ON c.id=r.citation_id",
  "WHERE b.id IN ($1::uuid,$2::uuid) ORDER BY b.id"
), list(state_a$child_batch_id, state_b$child_batch_id))
stopifnot(nrow(receipts) == 2L, all(receipts$status == "finalized"), all(receipts$operation == "canonical_delta"))
stopifnot(length(unique(receipts$fact_id)) == 2L, length(unique(receipts$citation_id)) == 2L)
stopifnot(!(ordinary_fact %in% receipts$fact_id), !(ordinary_assertion %in% receipts$assertion_id),
          !(ordinary_citation %in% receipts$citation_id))
stopifnot(all(c(paste(task9_profile_a, "side 1"), paste(task9_profile_b, "side 1")) %in% receipts$citat_tekst))

cat("PASS Task 8 source/profile writer lock concurrency; Task 9 RED max(id)+1 collision and Task 10 concurrent ordinary/default identity-backed writes\n")
