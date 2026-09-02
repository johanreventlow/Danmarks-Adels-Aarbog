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

worker <- function(state_json, application_name, ready_path = NULL, release_path = NULL) {
  state <- jsonlite::fromJSON(state_json, simplifyVector = FALSE)
  con <- connect()
  on.exit(try(dbDisconnect(con), silent = TRUE), add = TRUE)
  dbBegin(con)
  execute(con, "SELECT set_config('request.jwt.claim.sub',$1,true)", list(task9_actor))
  execute(con, "SELECT set_config('application_name',$1,true)", list(application_name))
  payload <- jsonlite::toJSON(state$payload, auto_unbox = TRUE, null = "null")
  query(con, "SELECT public.red_apply_reimport_name_completion($1::uuid,$2,$3::jsonb)",
        list(state$child_batch_id, state$element_id, payload))
  if (!is.null(ready_path)) {
    stopifnot(file.create(ready_path))
    for (i in seq_len(100L)) {
      if (file.exists(release_path)) break
      Sys.sleep(0.05)
    }
    stopifnot(file.exists(release_path))
  }
  finalized <- query(con, "SELECT public.red_finalize_reimport_name_completion($1::uuid) result", list(state$child_batch_id))$result[[1L]]
  dbCommit(con)
  finalized
}

ready_a <- tempfile("task9-name-completion-a-")
release_a <- tempfile("task9-name-completion-release-")
worker_a <- parallel::mcparallel(worker(state_a_json, "task9-name-completion-a", ready_a, release_a), silent = TRUE)
for (i in seq_len(100L)) {
  if (file.exists(ready_a)) break
  Sys.sleep(0.05)
}
if (!file.exists(ready_a)) {
  worker_a_error <- parallel::mccollect(worker_a, wait = TRUE)[[1L]]
  stop("Task 9 writer A did not reach the post-allocation hold: ", worker_a_error)
}
worker_b <- parallel::mcparallel(worker(state_b_json, "task9-name-completion-b"), silent = TRUE)
stopifnot(file.create(release_a))
completed_a <- parallel::mccollect(worker_a, wait = TRUE)[[1L]]
completed_b <- parallel::mccollect(worker_b, wait = TRUE)[[1L]]
stopifnot(!inherits(completed_a, "try-error"), !inherits(completed_b, "try-error"))
stopifnot(jsonlite::fromJSON(completed_a)$status == "finalized", jsonlite::fromJSON(completed_b)$status == "finalized")

receipts <- query(holder, paste(
  "SELECT b.id batch_id,b.status,r.fact_id,r.citation_id,e.element_id,e.operation,c.citat_tekst",
  "FROM private.reimport_batch b JOIN private.reimport_name_completion_result r ON r.batch_id=b.id",
  "JOIN private.reimport_event e ON e.batch_id=b.id AND e.element_id=r.element_id",
  "JOIN public.citation c ON c.id=r.citation_id",
  "WHERE b.id IN ($1::uuid,$2::uuid) ORDER BY b.id"
), list(state_a$child_batch_id, state_b$child_batch_id))
stopifnot(nrow(receipts) == 2L, all(receipts$status == "finalized"), all(receipts$operation == "canonical_delta"))
stopifnot(length(unique(receipts$fact_id)) == 2L, length(unique(receipts$citation_id)) == 2L)
stopifnot(all(c(paste(task9_profile_a, "side 1"), paste(task9_profile_b, "side 1")) %in% receipts$citat_tekst))

cat("PASS Task 8 source/profile writer lock concurrency; Task 9 RED max(id)+1 collision and Task 10 concurrent identity-backed name-completion writes\n")
