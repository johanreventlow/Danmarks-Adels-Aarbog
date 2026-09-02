# Disposable Task 8 proof: the SQL lifecycle, not a cooperative R mutex,
# holds a transaction-scoped `(source_id, profile_id)` writer lock.
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })

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
cat("PASS Task 8 source/profile writer lock concurrency\n")
