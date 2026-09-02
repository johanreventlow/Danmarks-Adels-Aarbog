# Disposable #153 generic writer DBI integration.  It deliberately creates no
# historical source content; every identity and hash below is synthetic.
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })

stopifnot(nzchar(Sys.getenv("PGHOST")), nzchar(Sys.getenv("PGPORT")),
  nzchar(Sys.getenv("PGDATABASE")), nzchar(Sys.getenv("PGUSER")))
con <- dbConnect(Postgres(), dbname=Sys.getenv("PGDATABASE"), host=Sys.getenv("PGHOST"),
  port=Sys.getenv("PGPORT"), user=Sys.getenv("PGUSER"), password=Sys.getenv("PGPASSWORD"))
on.exit(dbDisconnect(con), add=TRUE)
q <- function(sql, params=list()) if (length(params)) dbGetQuery(con, sql, params=params) else dbGetQuery(con, sql)
e <- function(sql, params=list()) if (length(params)) dbExecute(con, sql, params=params) else dbExecute(con, sql)
hash <- function(char) paste(rep(char,64L),collapse="")
actor <- "15370000-0000-4000-8000-000000000001"
profile_hash <- hash("a")
profile_config <- '{"run_key_prefix":"task7:","schema_version":"task7","extractor_version":"task7","rendition_key":"task7","rendition_kind":"ocr_text","rendition_metadata":{},"observation_extraction_method":"task7","citation_label_template":"task7 {page_from}"}'

stopifnot(q("SELECT public.narrative_record_contract_version() version")$version[[1L]] == 2L)
e("INSERT INTO auth.users(id,email) VALUES($1,'task7-generic@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'task7-generic@example.invalid','redaktion','Task 7') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
for (source_id in c(153701L,153702L)) {
  e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Task 7','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING",list(source_id))
  e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,'task7-equal-hash','v1',$2,$3::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",list(source_id,profile_hash,profile_config))
}
e("SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
authorize <- function(source_id, manifest, preview) q("SELECT public.red_authorize_reimport($1,$2,current_database(),$3,'task7-equal-hash',$4,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",list(manifest,preview,source_id,profile_hash))$id[[1L]]
begin <- function(id, manifest, preview) q("SELECT public.red_begin_reimport($1,$2,$3) id",list(id,manifest,preview))$id[[1L]]

# Equal manifest/preview hashes must remain scoped by source/profile identity.
manifest <- hash("9"); preview <- hash("8")
a1 <- authorize(153701L,manifest,preview); b1 <- begin(a1,manifest,preview)
a2 <- authorize(153702L,manifest,preview); b2 <- begin(a2,manifest,preview)
stopifnot(!identical(b1,b2), q("SELECT count(*) n FROM private.reimport_batch WHERE id IN ($1,$2) AND manifest_sha256=$3 AND preview_sha256=$4 AND profile_sha256=$5",list(b1,b2,manifest,preview,profile_hash))$n[[1L]] == 2L)
stopifnot(q("SELECT public.red_finalize_reimport($1)->>'status' status",list(b1))$status[[1L]] == "finalized")
stopifnot(q("SELECT public.red_finalize_reimport($1)->>'status' status",list(b2))$status[[1L]] == "finalized")

# A reversal authorization for profile 1 must not authorize either operation on profile 2.
reverse_auth <- q("SELECT public.red_authorize_reimport_reversal($1,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",list(b1))$id[[1L]]
cross_reverse <- try(q("SELECT public.red_reverse_reimport($1,$2)",list(b2,reverse_auth)),silent=TRUE)
cross_activate <- try(q("SELECT public.red_activate_reimport_batch($1,$2)",list(b2,reverse_auth)),silent=TRUE)
stopifnot(inherits(cross_reverse,"try-error"),grepl("REIMPORT_WRITER_REVERSAL_INVALID",as.character(cross_reverse),fixed=TRUE),
  inherits(cross_activate,"try-error"),grepl("REIMPORT_WRITER_CUTOVER_INVALID",as.character(cross_activate),fixed=TRUE))

# A generic person-create remains event-backed through the v2 narrative RPC.
person_def <- q("SELECT pg_get_functiondef('public.red_apply_reimport_person_create(uuid,text,jsonb)'::regprocedure) definition")$definition[[1L]]
stopifnot(grepl("red_upsert_person_narrative_record",person_def,fixed=TRUE),grepl("INSERT INTO private.reimport_event",person_def,fixed=TRUE))

# A dry transaction that has opened a generic batch leaves no authorization or batch row.
rollback_manifest <- hash("d"); before <- q("SELECT count(*) n FROM private.reimport_authorization WHERE manifest_sha256=$1",list(rollback_manifest))$n[[1L]]
dbBegin(con); e("SELECT set_config('request.jwt.claim.sub',$1,true)",list(actor)); rollback_auth <- authorize(153701L,rollback_manifest,preview); rollback_batch <- begin(rollback_auth,rollback_manifest,preview); stopifnot(nzchar(rollback_batch)); dbRollback(con)
stopifnot(q("SELECT count(*) n FROM private.reimport_authorization WHERE manifest_sha256=$1",list(rollback_manifest))$n[[1L]] == before,
  q("SELECT count(*) n FROM private.reimport_batch WHERE manifest_sha256=$1",list(rollback_manifest))$n[[1L]] == 0L)

# An authenticated principal without a redaktion profile is rejected before a ledger write.
e("SET ROLE authenticated"); e("SELECT set_config('request.jwt.claim.sub','15370000-0000-4000-8000-000000000099',false)")
unauthorized <- try(q("SELECT public.red_authorize_reimport($1,$2,current_database(),153701,'task7-equal-hash',$3,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes')",list(hash("e"),preview,profile_hash)),silent=TRUE)
e("RESET ROLE"); e("SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
stopifnot(inherits(unauthorized,"try-error"))
cat("PASS generic reimport writer DBI integration\n")
