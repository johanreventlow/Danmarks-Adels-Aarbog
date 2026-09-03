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
profile_config <- '{"run_key_prefix":"task7:","schema_version":"task7","extractor_version":"task7","rendition_key":"task7","rendition_kind":"ocr_text","rendition_metadata":{},"observation_extraction_method":"task7","citation_label_template":"task7 {page_from}"}'

stopifnot(q("SELECT public.narrative_record_contract_version() version")$version[[1L]] == 2L)
e("INSERT INTO auth.users(id,email) VALUES($1,'task7-generic@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'task7-generic@example.invalid','redaktion','Task 7') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
profile_hash <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) hash", list(profile_config))$hash[[1L]]
database_identity <- q("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text identity")$identity[[1L]]
for (source_id in c(153701L,153702L)) {
  e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Task 7','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING",list(source_id))
  e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,'task7-equal-hash','v1',$2,$3::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",list(source_id,profile_hash,profile_config))
}
e("SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
authorize <- function(source_id, manifest, preview) q("SELECT public.red_authorize_reimport($1,$2,$3,$4,'task7-equal-hash',$5,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",list(manifest,preview,database_identity,source_id,profile_hash))$id[[1L]]
begin <- function(id, manifest, preview) q("SELECT public.red_begin_reimport($1,$2,$3) id",list(id,manifest,preview))$id[[1L]]

# Equal manifest/preview hashes must remain scoped by source/profile identity.
manifest <- hash("9"); preview <- hash("8")
a1 <- authorize(153701L,manifest,preview); b1 <- begin(a1,manifest,preview)
a2 <- authorize(153702L,manifest,preview); b2 <- begin(a2,manifest,preview)
stopifnot(!identical(b1,b2), q("SELECT count(*) n FROM private.reimport_batch WHERE id IN ($1,$2) AND manifest_sha256=$3 AND preview_sha256=$4 AND profile_sha256=$5",list(b1,b2,manifest,preview,profile_hash))$n[[1L]] == 2L)
stopifnot(q("SELECT public.red_finalize_reimport($1)->>'status' status",list(b1))$status[[1L]] == "finalized")
stopifnot(q("SELECT public.red_finalize_reimport($1)->>'status' status",list(b2))$status[[1L]] == "finalized")

# Authorization rejects malformed count/element state before it reaches an open
# batch, and matching hashes cannot replay a finalized batch with another
# authorized element set.
malformed_counts <- try(q("SELECT public.red_authorize_reimport($1,$2,$3,$4,'task7-equal-hash',$5,'{\"person_creates\":\"0\",\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes')",list(hash("1"),preview,database_identity,153701L,profile_hash)), silent=TRUE)
malformed_elements <- try(q("SELECT public.red_authorize_reimport($1,$2,$3,$4,'task7-equal-hash',$5,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,jsonb_build_object('person-create:unexpected','{}'::jsonb),gen_random_uuid(),clock_timestamp()+interval '5 minutes')",list(hash("2"),preview,database_identity,153701L,profile_hash)), silent=TRUE)
stopifnot(inherits(malformed_counts,"try-error"), inherits(malformed_elements,"try-error"))
replay_auth <- q("INSERT INTO private.reimport_authorization(operation,manifest_sha256,preview_sha256,database_identity,source_id,profile_id,profile_sha256,expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at) VALUES('reimport',$1,$2,$3,153701,'task7-equal-hash',$4,'{\"person_creates\":1,\"source_evidence\":0}'::jsonb,jsonb_build_object('person-create:record-a','{}'::jsonb),$5,gen_random_uuid(),clock_timestamp()+interval '5 minutes','consumed',clock_timestamp()) RETURNING id",list(hash("3"),preview,database_identity,profile_hash,actor))$id[[1L]]
replay_batch <- q("INSERT INTO private.reimport_batch(authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,status,expected_counts,observed_counts,finalized_at) VALUES($1,$2,$3,153701,'task7-equal-hash',$4,$5,'finalized','{\"person_creates\":1,\"source_evidence\":0}'::jsonb,'{\"person_creates\":1,\"source_evidence\":0}'::jsonb,clock_timestamp()) RETURNING id",list(replay_auth,hash("3"),preview,profile_hash,actor))$id[[1L]]
drift_auth <- q("SELECT public.red_authorize_reimport($1,$2,$3,$4,'task7-equal-hash',$5,'{\"person_creates\":1,\"source_evidence\":0}'::jsonb,jsonb_build_object('person-create:record-b','{}'::jsonb),gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",list(hash("3"),preview,database_identity,153701L,profile_hash))$id[[1L]]
replay_drift <- try(q("SELECT public.red_begin_reimport($1,$2,$3)",list(drift_auth,hash("3"),preview)),silent=TRUE)
stopifnot(inherits(replay_drift,"try-error"),grepl("REIMPORT_WRITER_REPLAY_DRIFT",as.character(replay_drift),fixed=TRUE),
  q("SELECT id=$1 same_batch FROM private.reimport_batch WHERE id=$2",list(replay_batch,replay_batch))$same_batch[[1L]])

# A reversal authorization for profile 1 must not authorize either operation on profile 2.
reverse_auth <- q("SELECT public.red_authorize_reimport_reversal($1,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",list(b1))$id[[1L]]
cross_reverse <- try(q("SELECT public.red_reverse_reimport($1,$2)",list(b2,reverse_auth)),silent=TRUE)
cross_activate <- try(q("SELECT public.red_activate_reimport_batch($1,$2)",list(b2,reverse_auth)),silent=TRUE)
stopifnot(inherits(cross_reverse,"try-error"),grepl("REIMPORT_WRITER_REVERSAL_INVALID",as.character(cross_reverse),fixed=TRUE),
  inherits(cross_activate,"try-error"),grepl("REIMPORT_WRITER_CUTOVER_INVALID",as.character(cross_activate),fixed=TRUE))

# One actual generic person-create must pass through the #152 v2 record/publication kernel.
person_source <- 153703L; person_profile <- "task7-person"; person_manifest <- hash("6"); person_preview <- hash("5")
e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Task 7 person','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING",list(person_source))
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",list(person_source,person_profile,profile_hash,profile_config))
fixture_id <- -153703L; run_id <- q("SELECT gen_random_uuid() id")$id[[1L]]
e("INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES($1,'Task 7','Task 7','task7-person') ON CONFLICT(id) DO NOTHING",list(fixture_id))
e("INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES($1,$1,$2,'stamtavle','Task 7') ON CONFLICT(id) DO NOTHING",list(fixture_id,person_source))
e("INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES($1,$1,$1,'A','Task 7',1) ON CONFLICT(id) DO NOTHING",list(fixture_id))
e("INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,$2,'task7-placement','task7','task7','task7',$3,'{}'::jsonb)",list(run_id,person_source,hash("4")))
placement_rendition <- q("INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES($1,'task7-placement','ocr_text',$2,'{}'::jsonb) RETURNING id",list(person_source,hash("7")))$id[[1L]]
record_key <- "task7-person-record"; record_id <- q("INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES($1,$2,'person',$3) RETURNING id",list(person_source,record_key,run_id))$id[[1L]]
occurrence_id <- q("INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,'task7-placement',1,1,0,13,'Task 7 person',$2,$3,$4) RETURNING id",list(placement_rendition,hash("7"),hash("4"),run_id))$id[[1L]]
e("INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2,'accepted',jsonb_build_object('batch_id',$3::uuid,'element_id','task7-placement'),1,$3,'Task 7')",list(occurrence_id,record_id,actor))
observation_id <- q("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,'header',1,1,0,13,'Task 7 person','clear','task7',$2) RETURNING id",list(occurrence_id,run_id))$id[[1L]]
placement_id <- q("SELECT private.propose_source_record_placement($1,$2,$3,jsonb_build_object('fixture','task7-v2'),'Task 7') id",list(record_id,fixture_id,observation_id))$id[[1L]]
e("SELECT public.red_decide_source_record_placement($1,1,'accepted',jsonb_build_object('fixture','task7-v2'))",list(placement_id))
persona <- q("SELECT gen_random_uuid() id")$id[[1L]]
person_payload <- list(source_record_key=record_key,source_id=person_source,source_span=list(char_from=0L,char_to=13L),page_evidence=list(page_from=1L,page_to=1L),verbatim_text="Task 7 person",rendition_content_sha256=hash("7"),source_persona_id=persona,persona_key="task7-person",source_record_placement_id=placement_id,placement_role="principal_member",placement_basis_sha256=hash("2"),placement_review_sha256=hash("3"),placement_decision_sha256=hash("4"),name="Task 7",narrative=list(text="Task 7 person",source_record_key=record_key))
person_json <- jsonlite::toJSON(person_payload,auto_unbox=TRUE,null="null")
person_auth <- q("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,'{\"person_creates\":1,\"source_evidence\":0}'::jsonb,jsonb_build_object('person-create:task7',$7::jsonb),gen_random_uuid(),clock_timestamp()+interval '5 minutes') id",list(person_manifest,person_preview,database_identity,person_source,person_profile,profile_hash,person_json))$id[[1L]]
person_batch <- begin(person_auth,person_manifest,person_preview)
person_id <- q("SELECT public.red_apply_reimport_person_create($1,'person-create:task7',$2::jsonb) id",list(person_batch,person_json))$id[[1L]]
e("SELECT set_config('app.change_set_id','',true)")
stopifnot(q("SELECT public.red_finalize_reimport($1)->>'status' status",list(person_batch))$status[[1L]] == "finalized")
event_state <- q("SELECT e.payload->>'event_id' event_id,e.payload->>'narrative_id' narrative_id,e.payload->>'publication_state_sha256' publication_hash,e.payload->>'state_sha256' state_hash,exists(SELECT 1 FROM private.narrative_record_publication p JOIN public.narrative n ON n.id=p.narrative_id WHERE n.subjekt_type='person' AND n.subjekt_id=$2 AND p.source_record_id=$3) publication FROM private.reimport_event e WHERE e.batch_id=$1 AND e.operation='person_create'",list(person_batch,person_id,record_id))
stopifnot(nrow(event_state)==1L,nzchar(event_state$event_id[[1L]]),nzchar(event_state$narrative_id[[1L]]),grepl("^[0-9a-f]{64}$",event_state$publication_hash[[1L]]),grepl("^[0-9a-f]{64}$",event_state$state_hash[[1L]]),event_state$publication[[1L]])

# A dry transaction that has opened a generic batch leaves no authorization or batch row.
rollback_manifest <- hash("d"); before <- q("SELECT count(*) n FROM private.reimport_authorization WHERE manifest_sha256=$1",list(rollback_manifest))$n[[1L]]
dbBegin(con); e("SELECT set_config('request.jwt.claim.sub',$1,true)",list(actor)); rollback_auth <- authorize(153701L,rollback_manifest,preview); rollback_batch <- begin(rollback_auth,rollback_manifest,preview); stopifnot(nzchar(rollback_batch)); dbRollback(con)
stopifnot(q("SELECT count(*) n FROM private.reimport_authorization WHERE manifest_sha256=$1",list(rollback_manifest))$n[[1L]] == before,
  q("SELECT count(*) n FROM private.reimport_batch WHERE manifest_sha256=$1",list(rollback_manifest))$n[[1L]] == 0L)

# An authenticated principal without a redaktion profile is rejected before a ledger write.
e("SET ROLE authenticated"); e("SELECT set_config('request.jwt.claim.sub','15370000-0000-4000-8000-000000000099',false)")
unauthorized <- try(q("SELECT public.red_authorize_reimport($1,$2,$3,153701,'task7-equal-hash',$4,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes')",list(hash("e"),preview,database_identity,profile_hash)),silent=TRUE)
e("RESET ROLE"); e("SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
stopifnot(inherits(unauthorized,"try-error"))
cat("PASS generic reimport writer DBI integration\n")
