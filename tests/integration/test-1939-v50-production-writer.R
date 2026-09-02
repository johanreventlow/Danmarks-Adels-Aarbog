root <- normalizePath(file.path(dirname(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE)[1])),"../.."))
source(file.path(root,".claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R"))
actor <- "11111111-1111-4111-8111-111111111111"
Sys.setenv(DAA_REIMPORT_ACTOR_ID=actor)
connect <- function() {
  con <- DBI::dbConnect(RPostgres::Postgres(),dbname=Sys.getenv("PGDATABASE"),host=Sys.getenv("PGHOST","localhost"),port=Sys.getenv("PGPORT","5432"),user=Sys.getenv("PGUSER","postgres"),password=Sys.getenv("PGPASSWORD"))
  if (identical(Sys.getenv("DAA_REIMPORT_TEST_ROLE"), "authenticated")) DBI::dbExecute(con,"SET ROLE authenticated")
  con
}
q <- function(con,sql,params=list()) if(length(params)) DBI::dbGetQuery(con,sql,params=params) else DBI::dbGetQuery(con,sql)
make_create <- function(i, placement_id) {
 key<-paste0("record-ci-",i); text<-paste0("CI person ",i); persona<-sprintf("00000000-0000-5000-8000-%012d",i)
 list(element_id=paste0("person-create:",key),dependency_class="person_create",source_record_key=key,source_id=3L,edition="1939",
  source_span=list(char_from=i*10L,char_to=i*10L+nchar(text)),page_evidence=list(page_from=500L,page_to=500L),verbatim_text=text,verbatim_sha256=digest::digest(text,algo="sha256",serialize=FALSE),
  source_persona_id=persona,persona_key=paste0("1939:",key),
  source_record_placement_id=placement_id,placement_role="principal_member",
  placement_basis_sha256=paste(rep("2",64),collapse=""),placement_review_sha256=paste(rep("3",64),collapse=""),placement_decision_sha256=paste(rep("4",64),collapse=""),
  identity_decision_sha256=paste(rep("d",64),collapse=""),review_sha256=paste(rep("e",64),collapse=""),decision_basis="fixture",name=text,sex=NULL,
  narrative=list(text=text,source_record_key=key),source_mentions=list(list(kind="person",text=text,source_record_key=key)),persona_mention_links=list(list(source_persona_id=persona,source_record_key=key)),facts=list(),relations=list(),families=list(),uncertainties=list(),staged=TRUE)
}
make_evidence <- function(i) { text<-paste0("source evidence ",i); list(element_id=paste0("source-evidence:ci-",i),dependency_class="source_evidence",review_subject_id=paste0("ci-",i),source_record_key=paste0("record-source-",i),category="fact",disposition="retain_source_only",evidence_sha256=digest::digest(text,algo="sha256",serialize=FALSE),canonical_target=list(canonical_person_id=1L),source_span=list(char_from=i*20L,char_to=i*20L+nchar(text)),page_evidence=list(page_from=500L,page_to=500L),verbatim_text=text,legacy_payload=list(value=text)) }
seed_v2_record_placements <- function(con) {
  DBI::dbExecute(con,"INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES(-153201,'Task 4 R fixture','Task 4 R fixture','task-4-r-fixture') ON CONFLICT(id) DO NOTHING")
  DBI::dbExecute(con,"INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES(-153201,-153201,3,'stamtavle','Task 4 R fixture') ON CONFLICT(id) DO NOTHING")
  DBI::dbExecute(con,"INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES(-153201,-153201,-153201,'A','Task 4 R fixture',1) ON CONFLICT(id) DO NOTHING")
  run_id <- q(con,"SELECT gen_random_uuid() id")$id[[1]]
  DBI::dbExecute(con,"INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,3,'task4-r-v2-placement','fixture-v2','fixture-v2','fixture-v2',$2,'{}'::jsonb)",list(run_id,paste(rep("d",64),collapse="")))
  rendition_id <- q(con,"INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES(3,'task4-r-v2-placement','ocr_text',$1,'{}'::jsonb) RETURNING id",list(paste(rep("d",64),collapse="")))$id[[1]]
  q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
  vapply(seq_len(8L),function(i) {
    key <- paste0("record-ci-",i); text <- paste0("CI person ",i)
    record_id <- q(con,"INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES(3,$1,'person',$2) RETURNING id",list(key,run_id))$id[[1]]
    occurrence_id <- q(con,"INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,$2,500,500,$3,$4,$5,$6,$7,$8) RETURNING id",list(rendition_id,paste0("task4-r-placement:",key),i*10L,i*10L+nchar(text),text,digest::digest(text,algo="sha256",serialize=FALSE),paste(rep("e",64),collapse=""),run_id))$id[[1]]
    DBI::dbExecute(con,"INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2,'accepted','{\"fixture\":\"task4-r-v2\"}'::jsonb,1,$3,'Task 4 R fixture')",list(occurrence_id,record_id,actor))
    observation_id <- q(con,"INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,'header',500,500,$2,$3,$4,'clear','fixture-v2',$5) RETURNING id",list(occurrence_id,i*10L,i*10L+nchar(text),text,run_id))$id[[1]]
    placement_id <- q(con,"SELECT private.propose_source_record_placement($1,-153201,$2,jsonb_build_object('fixture','task4-r-v2'),'Task 4 R fixture') id",list(record_id,observation_id))$id[[1]]
    q(con,"SELECT public.red_decide_source_record_placement($1,1,'accepted',jsonb_build_object('fixture','task4-r-v2'))",list(placement_id))
    accepted <- q(con,"SELECT decision_status FROM private.source_record_placement_current WHERE id=$1",list(placement_id))$decision_status[[1]]
    stopifnot(identical(accepted,"accepted"))
    placement_id
  },character(1))
}
preview <- paste(rep("b",64),collapse="")
emitted_sql <- character()
gateway <- function() new_dbi_writer_gateway(function() connect(), function(sql) emitted_sql <<- c(emitted_sql, sql))
con <- connect(); on.exit(try(DBI::dbDisconnect(con),silent=TRUE),add=TRUE)
placement_ids <- seed_v2_record_placements(con)
creates <- mapply(make_create,seq_len(8L),placement_ids,SIMPLIFY=FALSE)
evidence <- lapply(seq_len(305L),make_evidence)
manifest <- list(
 schema_version="1939-v50-production-write-manifest-v1",generator_version="integration-fixture",
 input_hashes=list(database_preview_v3_sha256=paste(rep("b",64),collapse="")),source=list(edition="1939",logical_source_id="1939",database_source_id=3L,rendition_content_sha256=paste(rep("d",64),collapse="")),
 expected_database_contract=list(postgres_major=17L,writer_contract="1939-v50-production-writer-v1"),
 existing_anchors=lapply(1:543,function(i) list(baseline_record_key=paste0("baseline-",i),person_id=i)),
 person_creates=creates,
 provenance_dispositions=lapply(1:305,function(i) list(review_subject_id=paste0("ci-",i))),canonical_delta=list(),
 operations=c(evidence,creates),
 counts=list(existing_anchors=543L,person_creates=8L,provenance_dispositions=305L,source_evidence_operations=305L,canonical_delta=0L,operations=313L),
 expected_changes=list(persons_created=8L,source_evidence_written=305L,canonical_rows_changed=0L,persons_activated=0L),
 manifest_content_sha256=paste(rep("c",64),collapse=""),production_authorized=FALSE,apply_gate="NO-GO",cutover_gate="NO-GO")
generic_manifest <- as_generic_reimport_manifest(manifest)
generic_expected_counts <- jsonlite::toJSON(reimport_writer_expected_counts(generic_manifest), auto_unbox=TRUE)
generic_authorized <- jsonlite::toJSON(reimport_authorized_payloads(generic_manifest), auto_unbox=TRUE, null="null")
DBI::dbExecute(con, "INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'fixture-v2',$3,$4::jsonb)", list(
  generic_manifest$source$id, generic_manifest$source$profile_id,
  generic_manifest$source$profile_sha256,
  '{"run_key_prefix":"reimport-1939-v50:","schema_version":"1939-v50-production-write-manifest-v1","extractor_version":"production-writer-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"fixture","citation_label_template":"DAA 1939 side {page_from}"}'))
race <- connect(); DBI::dbBegin(con); DBI::dbBegin(race)
q(con,"SELECT pg_advisory_xact_lock(hashtextextended($1,0))",list("daa-reimport:3:daa-1939-v50-production-write-v1"))
stopifnot(!q(race,"SELECT pg_try_advisory_xact_lock(hashtextextended($1,0)) acquired",list("daa-reimport:3:daa-1939-v50-production-write-v1"))$acquired[[1]])
DBI::dbRollback(race); DBI::dbDisconnect(race); DBI::dbRollback(con)
before <- q(con,"SELECT (SELECT count(*) FROM person) persons,(SELECT count(*) FROM private.reimport_1939_write_batch) batches,(SELECT count(*) FROM private.reimport_1939_write_event) events")
DBI::dbDisconnect(con); con <- NULL
dry <- execute_reimport(manifest,preview,"dry-run",gateway())
stopifnot(dry$status %in% c("finalized","already_applied"),!dry$committed)
con <- connect(); after <- q(con,"SELECT (SELECT count(*) FROM person) persons,(SELECT count(*) FROM private.reimport_1939_write_batch) batches,(SELECT count(*) FROM private.reimport_1939_write_event) events")
stopifnot(identical(before,after))
q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
q(con,"SET ROLE service_role")
auth <- q(con,"SELECT red_authorize_reimport($1,$2,current_database(),$3,$4,$5,$6::jsonb,$7::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(generic_manifest$manifest_content_sha256,preview,generic_manifest$source$id,generic_manifest$source$profile_id,generic_manifest$source$profile_sha256,generic_expected_counts,generic_authorized))$id[[1]]
q(con,"RESET ROLE")
role_manifest <- paste(rep("9",64),collapse="")
q(con,"SET ROLE service_role")
role_auth <- q(con,"SELECT red_authorize_reimport($1,$2,current_database(),$3,$4,$5,'{\"person_creates\":0,\"source_evidence\":0}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(role_manifest,preview,generic_manifest$source$id,generic_manifest$source$profile_id,generic_manifest$source$profile_sha256))$id[[1]]
q(con,"RESET ROLE")
q(con,"SET ROLE authenticated")
role_batch <- q(con,"SELECT red_begin_reimport($1,$2,$3) id",list(role_auth,role_manifest,preview))$id[[1]]
role_result <- jsonlite::fromJSON(q(con,"SELECT red_reimport_batch_result($1,$2)::text value",list(role_auth,role_batch))$value[[1]],simplifyVector=FALSE)
q(con,"RESET ROLE")
stopifnot(identical(role_result$status,"open"),identical(role_result$replayed,FALSE),length(role_result$person_id_map)==0L)
DBI::dbDisconnect(con); con <- NULL
emitted_sql <- character()
applied <- execute_reimport(manifest,preview,"apply",gateway(),list(id=auth))
stopifnot(applied$committed,length(applied$person_id_map)==8L)
stopifnot(any(grepl("public.red_reimport_batch_result", emitted_sql, fixed=TRUE)),
  !any(grepl("private.reimport_", emitted_sql, fixed=TRUE)))
con <- connect(); q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
state <- q(con,"SELECT (SELECT count(*) FROM person_external_id WHERE record_key LIKE 'record-ci-%') persons,(SELECT count(*) FROM private.reimport_1939_write_event e JOIN private.reimport_1939_write_batch b ON b.id=e.batch_id WHERE e.operation='source_evidence' AND b.manifest_sha256=$1) evidence,(SELECT count(*) FROM private.reimport_batch WHERE manifest_sha256=$1 AND source_id=3 AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=repeat('a',64)) profile_bound",list(manifest$manifest_content_sha256))
stopifnot(state$persons[[1]]==8,state$evidence[[1]]==305,state$profile_bound[[1]]==1)
provenance <- q(con,"SELECT (SELECT count(*) FROM private.source_record WHERE record_key LIKE 'record-ci-%' OR record_key LIKE 'record-source-%') records,(SELECT count(*) FROM private.source_observation o JOIN private.extraction_run r ON r.id=o.extraction_run_id WHERE r.run_key='reimport-1939-v50:'||$1) observations,(SELECT count(*) FROM private.source_persona WHERE persona_key LIKE '1939:record-ci-%') personas,(SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id WHERE p.persona_key LIKE '1939:record-ci-%' AND i.decision_status='accepted') identities,(SELECT count(*) FROM narrative WHERE subjekt_type='person' AND tekst LIKE 'CI person %') narratives",list(manifest$manifest_content_sha256))
stopifnot(provenance$records[[1]]==313,provenance$observations[[1]]==313,provenance$personas[[1]]==8,provenance$identities[[1]]==8,provenance$narratives[[1]]==8)
q(con,"SET ROLE service_role")
auth2 <- q(con,"SELECT red_authorize_reimport($1,$2,current_database(),$3,$4,$5,$6::jsonb,$7::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(generic_manifest$manifest_content_sha256,preview,generic_manifest$source$id,generic_manifest$source$profile_id,generic_manifest$source$profile_sha256,generic_expected_counts,generic_authorized))$id[[1]]
q(con,"RESET ROLE")
DBI::dbDisconnect(con); con <- NULL
Sys.setenv(DAA_REIMPORT_TEST_ROLE="authenticated")
emitted_sql <- character()
replayed <- execute_reimport(manifest,preview,"apply",gateway(),list(id=auth2))
Sys.unsetenv("DAA_REIMPORT_TEST_ROLE")
stopifnot(replayed$status=="already_applied",replayed$committed,length(replayed$person_id_map)==8L)
stopifnot(any(grepl("public.red_reimport_batch_result", emitted_sql, fixed=TRUE)),
  !any(grepl("private.reimport_", emitted_sql, fixed=TRUE)))
con <- connect(); q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
tamper_manifest_sha <- paste(rep("f",64),collapse="")
tamper_auth <- q(con,"SELECT red_authorize_reimport($1,$2,current_database(),$3,$4,$5,$6::jsonb,$7::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(tamper_manifest_sha,preview,generic_manifest$source$id,generic_manifest$source$profile_id,generic_manifest$source$profile_sha256,generic_expected_counts,generic_authorized))$id[[1]]
tamper_batch <- q(con,"SELECT red_begin_reimport($1,$2,$3) id",list(tamper_auth,tamper_manifest_sha,preview))$id[[1]]
tampered <- reimport_authorized_payloads(generic_manifest); tampered[[1]]$verbatim_text <- paste0(tampered[[1]]$verbatim_text,"!")
drift <- try(q(con,"SELECT red_apply_reimport_source_evidence($1,$2,$3::jsonb)",list(tamper_batch,"source-evidence:ci-1",jsonlite::toJSON(tampered[[1]],auto_unbox=TRUE,null="null"))),silent=TRUE)
stopifnot(inherits(drift,"try-error"),grepl("REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED",as.character(drift),fixed=TRUE))
invisible(q(con,"SET ROLE anon")); visible <- q(con,"SELECT count(*) n FROM person_external_id WHERE record_key LIKE 'record-ci-%'")$n[[1]]; invisible(q(con,"RESET ROLE")); stopifnot(visible==0)
q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
batch <- q(con,"SELECT id FROM private.reimport_1939_write_batch WHERE manifest_sha256=$1 AND status='finalized'",list(manifest$manifest_content_sha256))$id[[1]]
completion_payloads <- q(con,"SELECT jsonb_object_agg('name-completion:'||e.source_record_key,jsonb_build_object('source_batch_id',e.batch_id,'source_person_create_element_id',e.element_id,'person_id',e.canonical_person_id,'source_id',b.source_id,'edition','1939','source_record_key',e.source_record_key,'source_persona_id',e.payload->>'source_persona_id','name',e.payload->>'name','source_span',e.payload->'source_span','page_evidence',e.payload->'page_evidence','verbatim_text',e.payload->>'verbatim_text','verbatim_sha256',e.payload->>'verbatim_sha256','source_payload_sha256',e.payload->>'authorized_payload_sha256','expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1)) ORDER BY e.element_id)::text payloads FROM private.reimport_event e JOIN private.reimport_batch b ON b.id=e.batch_id WHERE e.batch_id=$1 AND e.operation='person_create'",list(batch))$payloads[[1]]
completion_hash <- paste(rep("1",64),collapse="")
completion_auth <- jsonlite::fromJSON(q(con,"SELECT red_authorize_1939_v50_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)::text value",list(completion_hash,batch,preview,manifest$manifest_content_sha256,'{"name_completions":8,"operations":8}',completion_payloads))$value[[1]])$authorization_id
completion_batch <- q(con,"SELECT red_begin_1939_v50_name_completion($1,$2,$3) id",list(completion_auth,completion_hash,batch))$id[[1]]
for (element_id in names(jsonlite::fromJSON(completion_payloads,simplifyVector=FALSE))) {
  completion_payload <- jsonlite::fromJSON(completion_payloads,simplifyVector=FALSE)[[element_id]]
  invisible(q(con,"SELECT red_apply_1939_v50_name_completion($1,$2,$3::jsonb)",list(completion_batch,element_id,jsonlite::toJSON(completion_payload,auto_unbox=TRUE,null="null"))))
}
completion_result <- jsonlite::fromJSON(q(con,"SELECT red_finalize_1939_v50_name_completion($1)::text value",list(completion_batch))$value[[1]])
stopifnot(completion_result$status=="finalized")
q(con,"SELECT set_config('app.change_set_id','',true)")
cutover_auth <- q(con,"SELECT red_authorize_1939_v50_cutover($1,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(batch))$id[[1]]
activation <- jsonlite::fromJSON(q(con,"SELECT red_activate_1939_v50_batch($1,$2)::text value",list(batch,cutover_auth))$value[[1]])
stopifnot(activation$status=="activated")
rev <- q(con,"SELECT red_authorize_1939_v50_reversal($1,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(batch))$id[[1]]
result <- jsonlite::fromJSON(q(con,"SELECT red_reverse_1939_v50_reimport($1,$2)::text value",list(batch,rev))$value[[1]])
stopifnot(result$status=="reversed",q(con,"SELECT count(*) n FROM person_external_id WHERE record_key LIKE 'record-ci-%'")$n[[1]]==8)
stopifnot(q(con,"SELECT count(*) n FROM person p JOIN person_external_id e ON e.person_id=p.id WHERE e.record_key LIKE 'record-ci-%' AND p.staged")$n[[1]]==8)
stopifnot(q(con,"SELECT count(*) n FROM private.source_record WHERE record_key LIKE 'record-ci-%' OR record_key LIKE 'record-source-%'")$n[[1]]==313)
stopifnot(q(con,"SELECT count(*) n FROM private.source_persona_identity WHERE decision_status='superseded'")$n[[1]]==8)
next_id <- q(con,"INSERT INTO person(staged,visning_navn) VALUES(false,'sequence-check') RETURNING id")$id[[1]]
stopifnot(next_id>max(unlist(applied$person_id_map)))
DBI::dbDisconnect(con); con <- NULL
cat("PASS DAA 1939 v50 PostgreSQL integration\n")
