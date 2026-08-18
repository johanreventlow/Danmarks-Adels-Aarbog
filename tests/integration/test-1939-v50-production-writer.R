root <- normalizePath(file.path(dirname(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE)[1])),"../.."))
source(file.path(root,".claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R"))
actor <- "11111111-1111-4111-8111-111111111111"
Sys.setenv(DAA_REIMPORT_ACTOR_ID=actor)
connect <- function() DBI::dbConnect(RPostgres::Postgres(),dbname=Sys.getenv("PGDATABASE"),host=Sys.getenv("PGHOST","localhost"),port=Sys.getenv("PGPORT","5432"),user=Sys.getenv("PGUSER","postgres"),password=Sys.getenv("PGPASSWORD"))
q <- function(con,sql,params=list()) if(length(params)) DBI::dbGetQuery(con,sql,params=params) else DBI::dbGetQuery(con,sql)
make_create <- function(i) {
 key<-paste0("record-ci-",i); text<-paste0("CI person ",i); persona<-sprintf("00000000-0000-5000-8000-%012d",i)
 list(element_id=paste0("person-create:",key),dependency_class="person_create",source_record_key=key,source_id=3L,edition="1939",
  source_span=list(char_from=i*10L,char_to=i*10L+nchar(text)),page_evidence=list(page_from=500L,page_to=500L),verbatim_text=text,verbatim_sha256=digest::digest(text,algo="sha256",serialize=FALSE),
  source_persona_id=persona,persona_key=paste0("1939:",key),identity_decision_sha256=paste(rep("d",64),collapse=""),review_sha256=paste(rep("e",64),collapse=""),decision_basis="fixture",name=text,sex=NULL,
  narrative=list(text=text,source_record_key=key),source_mentions=list(list(kind="person",text=text,source_record_key=key)),persona_mention_links=list(list(source_persona_id=persona,source_record_key=key)),facts=list(),relations=list(),families=list(),uncertainties=list(),staged=TRUE)
}
make_evidence <- function(i) { text<-paste0("source evidence ",i); list(element_id=paste0("source-evidence:ci-",i),dependency_class="source_evidence",review_subject_id=paste0("ci-",i),source_record_key=paste0("record-source-",i),category="fact",disposition="retain_source_only",evidence_sha256=digest::digest(text,algo="sha256",serialize=FALSE),canonical_target=list(canonical_person_id=1L),source_span=list(char_from=i*20L,char_to=i*20L+nchar(text)),page_evidence=list(page_from=500L,page_to=500L),verbatim_text=text,legacy_payload=list(value=text)) }
creates <- lapply(1:8,make_create); evidence <- lapply(1:305,make_evidence)
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
preview <- paste(rep("b",64),collapse="")
gateway <- function() new_dbi_writer_gateway(connect)
con <- connect(); on.exit(try(DBI::dbDisconnect(con),silent=TRUE),add=TRUE)
race <- connect(); DBI::dbBegin(con); DBI::dbBegin(race)
q(con,"SELECT pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0))")
stopifnot(!q(race,"SELECT pg_try_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0)) acquired")$acquired[[1]])
DBI::dbRollback(race); DBI::dbDisconnect(race); DBI::dbRollback(con)
before <- q(con,"SELECT (SELECT count(*) FROM person) persons,(SELECT count(*) FROM private.reimport_1939_write_batch) batches,(SELECT count(*) FROM private.reimport_1939_write_event) events")
DBI::dbDisconnect(con); con <- NULL
dry <- execute_reimport(manifest,preview,"dry-run",gateway())
stopifnot(dry$status %in% c("finalized","already_applied"),!dry$committed)
con <- connect(); after <- q(con,"SELECT (SELECT count(*) FROM person) persons,(SELECT count(*) FROM private.reimport_1939_write_batch) batches,(SELECT count(*) FROM private.reimport_1939_write_event) events")
stopifnot(identical(before,after))
q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
authorized <- jsonlite::toJSON(authorized_element_payloads(manifest),auto_unbox=TRUE,null="null")
auth <- q(con,"SELECT red_authorize_1939_v50_reimport($1,$2,current_database(),3,$3::jsonb,$4::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(manifest$manifest_content_sha256,preview,'{"person_creates":8,"source_evidence":305,"canonical_delta":0}',authorized))$id[[1]]
DBI::dbDisconnect(con); con <- NULL
applied <- execute_reimport(manifest,preview,"apply",gateway(),list(id=auth))
stopifnot(applied$committed,length(applied$person_id_map)==8L)
con <- connect(); q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
state <- q(con,"SELECT (SELECT count(*) FROM person_external_id WHERE record_key LIKE 'record-ci-%') persons,(SELECT count(*) FROM private.reimport_1939_write_event e JOIN private.reimport_1939_write_batch b ON b.id=e.batch_id WHERE e.operation='source_evidence' AND b.manifest_sha256=$1) evidence",list(manifest$manifest_content_sha256))
stopifnot(state$persons[[1]]==8,state$evidence[[1]]==305)
provenance <- q(con,"SELECT (SELECT count(*) FROM private.source_record WHERE record_key LIKE 'record-ci-%' OR record_key LIKE 'record-source-%') records,(SELECT count(*) FROM private.source_observation o JOIN private.extraction_run r ON r.id=o.extraction_run_id WHERE r.run_key='reimport-1939-v50:'||$1) observations,(SELECT count(*) FROM private.source_persona WHERE persona_key LIKE '1939:record-ci-%') personas,(SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id WHERE p.persona_key LIKE '1939:record-ci-%' AND i.decision_status='accepted') identities,(SELECT count(*) FROM narrative WHERE subjekt_type='person' AND tekst LIKE 'CI person %') narratives",list(manifest$manifest_content_sha256))
stopifnot(provenance$records[[1]]==313,provenance$observations[[1]]==313,provenance$personas[[1]]==8,provenance$identities[[1]]==8,provenance$narratives[[1]]==8)
auth2 <- q(con,"SELECT red_authorize_1939_v50_reimport($1,$2,current_database(),3,$3::jsonb,$4::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(manifest$manifest_content_sha256,preview,'{"person_creates":8,"source_evidence":305,"canonical_delta":0}',authorized))$id[[1]]
DBI::dbDisconnect(con); con <- NULL
replayed <- execute_reimport(manifest,preview,"apply",gateway(),list(id=auth2))
stopifnot(replayed$status=="already_applied",replayed$committed,length(replayed$person_id_map)==8L)
con <- connect(); q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
tampered <- authorized_element_payloads(manifest); tampered[[1]]$verbatim_text <- paste0(tampered[[1]]$verbatim_text,"!")
drift <- try(q(con,"SELECT red_authorize_1939_v50_reimport($1,$2,current_database(),3,$3::jsonb,$4::jsonb,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(manifest$manifest_content_sha256,preview,'{"person_creates":8,"source_evidence":305,"canonical_delta":0}',jsonlite::toJSON(tampered,auto_unbox=TRUE,null="null"))),silent=TRUE)
stopifnot(inherits(drift,"try-error"),grepl("REIMPORT_1939_MANIFEST_ELEMENT_DRIFT",as.character(drift),fixed=TRUE))
invisible(q(con,"SET ROLE anon")); visible <- q(con,"SELECT count(*) n FROM person_external_id WHERE record_key LIKE 'record-ci-%'")$n[[1]]; invisible(q(con,"RESET ROLE")); stopifnot(visible==0)
q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor))
batch <- q(con,"SELECT id FROM private.reimport_1939_write_batch WHERE manifest_sha256=$1 AND status='finalized'",list(manifest$manifest_content_sha256))$id[[1]]
rev <- q(con,"SELECT red_authorize_1939_v50_reversal($1,gen_random_uuid(),clock_timestamp()+interval '10 minutes') id",list(batch))$id[[1]]
result <- jsonlite::fromJSON(q(con,"SELECT red_reverse_1939_v50_reimport($1,$2)::text value",list(batch,rev))$value[[1]])
stopifnot(result$status=="reversed",q(con,"SELECT count(*) n FROM person_external_id WHERE record_key LIKE 'record-ci-%'")$n[[1]]==0)
stopifnot(q(con,"SELECT count(*) n FROM person WHERE status='reimport_1939_reversed' AND staged")$n[[1]]==8)
stopifnot(q(con,"SELECT count(*) n FROM private.source_record WHERE record_key LIKE 'record-ci-%' OR record_key LIKE 'record-source-%'")$n[[1]]==313)
stopifnot(q(con,"SELECT count(*) n FROM private.source_persona_identity WHERE decision_status='superseded'")$n[[1]]==8)
next_id <- q(con,"INSERT INTO person(staged,visning_navn) VALUES(false,'sequence-check') RETURNING id")$id[[1]]
stopifnot(next_id>max(unlist(applied$person_id_map)))
DBI::dbDisconnect(con); con <- NULL
cat("PASS DAA 1939 v50 PostgreSQL integration\n")
