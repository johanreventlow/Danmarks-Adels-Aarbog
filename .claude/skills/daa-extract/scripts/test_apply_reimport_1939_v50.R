source("apply_reimport_1939_v50_helpers.R")

ok <- 0L
expect <- function(value, message="expectation failed") { if (!isTRUE(value)) stop(message); ok <<- ok + 1L }
expect_error <- function(expr, pattern) { got <- tryCatch({force(expr); ""}, error=function(e) conditionMessage(e)); expect(grepl(pattern, got, fixed=TRUE), paste(pattern, got)) }

fixture_manifest <- function() list(
  schema_version="1939-v50-production-write-manifest-v1",
  generator_version="test",
  input_hashes=list(database_preview_v3_sha256=paste(rep("b",64),collapse="")),
  source=list(edition="1939",logical_source_id="1939",database_source_id=3),
  expected_database_contract=list(postgres_major=17,writer_contract="1939-v50-production-writer-v1"),
  existing_anchors=lapply(1:543, function(i) list(baseline_record_key=paste0("b",i),person_id=i)),
  person_creates=lapply(1:8, function(i) list(element_id=paste0("person-create:r",i),dependency_class="person_create",source_record_key=paste0("r",i),source_id=3,name=paste0("N",i),staged=TRUE)),
  provenance_dispositions=lapply(1:305, function(i) list(review_subject_id=paste0("p",i))), canonical_delta=list(),
  operations=c(lapply(1:305,function(i) list(element_id=paste0("source-evidence:p",i),dependency_class="source_evidence",source_record_key=paste0("r",i),disposition="retain_source_only")),
               lapply(1:8,function(i) list(element_id=paste0("person-create:r",i),dependency_class="person_create",source_record_key=paste0("r",i),source_id=3,name=paste0("N",i),staged=TRUE))),
  counts=list(existing_anchors=543,person_creates=8,provenance_dispositions=305,source_evidence_operations=305,canonical_delta=0,operations=313),
  expected_changes=list(persons_created=8,source_evidence_written=305,canonical_rows_changed=0,persons_activated=0),
  manifest_content_sha256=paste(rep("a",64),collapse=""), production_authorized=FALSE,apply_gate="NO-GO",cutover_gate="NO-GO"
)

fake_gateway <- function() {
  log <- character(); ids <- 0L
  call <- function(name, ...) { log <<- c(log,name); if(name=="person_create") {ids<<-ids+1L; return(ids)}; if(name=="finalize") return(list(status="finalized")); invisible(NULL) }
  list(call=call,log=function() log)
}

m <- fixture_manifest(); validate_production_manifest(m)
expect(TRUE)
g <- fake_gateway(); out <- execute_reimport(m, paste(rep("c",64),collapse=""), "dry-run", g)
expect(identical(tail(g$log(),1),"rollback")); expect(!("commit" %in% g$log())); expect(length(out$person_id_map)==8)
expect(identical(g$log()[1:5],c("connect","begin","advisory_lock","preflight","begin_batch")))

g <- fake_gateway(); execute_reimport(m,paste(rep("c",64),collapse=""),"apply",g,authorization=list(id="auth"))
expect(identical(tail(g$log(),1),"commit"))
expect_error(execute_reimport(m,paste(rep("c",64),collapse=""),"apply",fake_gateway()),"REIMPORT_1939_AUTHORIZATION_REQUIRED")
m$production_authorized <- TRUE; expect_error(validate_production_manifest(m),"REIMPORT_1939_MANIFEST_INVALID")

cat(sprintf("PASS %d assertions\n",ok))
