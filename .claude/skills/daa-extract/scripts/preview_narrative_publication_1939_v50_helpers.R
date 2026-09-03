publication_hash_re <- "^[0-9a-f]{64}$"
publication_database_identity <- "7642734024280108049"
publication_source_batch_id <- "560c39f8-5c87-4c0d-a768-025d97fa2974"
publication_completion_batch_id <- "0b0055f6-9ad4-4f09-8f23-b8976d8f1996"

publication_locked_rows <- list(
  list(binding_id="9f9fbfd2-9784-4295-99be-2503c858bf19",narrative_id=1188L,person_id=1846L,source_record_id="a0765bb0-4f22-43e0-b44d-4f439f7305b3",record_key="record-3766faae-ae21-412a-8cfb-745a19ac77f0",record_ref="3c5ea543-f5ef-45f6-8973-5e8b63dd15da",record_label="record-3766faae-ae21-412a-8cfb-745a19ac77f0",citation_label="DAA 1939 side 503",page="503",expected_status="draft"),
  list(binding_id="2cc42378-8550-404f-876b-c0a48d39be2a",narrative_id=1189L,person_id=1847L,source_record_id="22e1a64b-269f-4aa8-87af-cefbe40a29ac",record_key="record-43d4974a-0532-421d-a3fb-8e7c575a67e7",record_ref="8e9efd2e-49cc-4977-8d7e-104fa3e3d1b7",record_label="record-43d4974a-0532-421d-a3fb-8e7c575a67e7",citation_label="DAA 1939 side 506",page="506",expected_status="draft"),
  list(binding_id="2ecfa104-fd4e-4530-93f2-e4d453200009",narrative_id=1190L,person_id=1848L,source_record_id="3d701306-8a9a-4060-b884-8120e9475120",record_key="record-80180a6e-2cc6-4968-81ca-004b6662d8ce",record_ref="7d34d55a-b8b4-4c99-9506-74c0d44650a9",record_label="record-80180a6e-2cc6-4968-81ca-004b6662d8ce",citation_label="DAA 1939 side 506",page="506",expected_status="draft"),
  list(binding_id="6ef99e20-4b47-4d37-94ef-67c82fed13eb",narrative_id=1191L,person_id=1849L,source_record_id="6a5fed3d-4dc9-4719-ab5f-c1733d7f87fd",record_key="record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422",record_ref="36400cfd-9531-4d7c-b64b-6293ea791709",record_label="record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422",citation_label="DAA 1939 side 508",page="508",expected_status="draft"),
  list(binding_id="937c9ef1-5eba-4a1b-9b51-9a522cf4207c",narrative_id=1192L,person_id=1850L,source_record_id="b9907530-139f-4165-bc95-2c933f5bc254",record_key="record-8f346104-cf3c-465f-bfa3-efb78be436b2",record_ref="d6723b2c-7b82-4bd2-b869-063094a3e855",record_label="record-8f346104-cf3c-465f-bfa3-efb78be436b2",citation_label="DAA 1939 side 506",page="506",expected_status="draft"),
  list(binding_id="eeac6d78-79e7-4141-ae51-be16a8ed7929",narrative_id=1193L,person_id=1851L,source_record_id="afe065bb-9334-49c5-b9da-4f9e949389ae",record_key="record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58",record_ref="23100933-853e-4778-bcd7-e020bd7c2670",record_label="record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58",citation_label="DAA 1939 side 508",page="508",expected_status="draft"),
  list(binding_id="e88fb965-efb4-41bf-81e0-f73045f251a2",narrative_id=1194L,person_id=1852L,source_record_id="88cf453a-4534-446a-8ae3-8b5bf2e4a0bc",record_key="record-b626f5ff-f2fb-4061-bfce-988dbddec846",record_ref="d2518ab6-ed4d-4855-9013-f696dfad4198",record_label="record-b626f5ff-f2fb-4061-bfce-988dbddec846",citation_label="DAA 1939 side 506",page="506",expected_status="draft"),
  list(binding_id="c9f4eeb8-6b42-453a-aa48-2b05d4403313",narrative_id=1195L,person_id=1853L,source_record_id="905560ea-a403-4c55-85c0-2c50478dadc2",record_key="record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d",record_ref="58ee75d5-a48b-478e-92e7-fb3b5ade0cd9",record_label="record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d",citation_label="DAA 1939 side 517",page="517",expected_status="draft")
)

stop_publication <- function(code) stop(code, call. = FALSE)
publication_names <- function(value, expected) is.list(value) && identical(sort(names(value)), sort(expected))
publication_hash <- function(value) is.character(value) && length(value)==1L && !is.na(value) && grepl(publication_hash_re,value)
publication_uuid <- function(value) is.character(value) && length(value)==1L && !is.na(value) &&
  grepl("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",value)

canonical_publication_value <- function(value) {
  if (!is.list(value)) return(value)
  n <- names(value)
  if (is.null(n)) return(lapply(value,canonical_publication_value))
  if (anyNA(n) || anyDuplicated(n)) stop_publication("NARRATIVE_PUBLICATION_1939_CANONICAL_INVALID")
  ordered <- sort(n,method="radix")
  result <- lapply(ordered,function(key) canonical_publication_value(value[[key]]))
  names(result) <- ordered
  result
}

canonical_publication_sha256 <- function(value) {
  json <- jsonlite::toJSON(canonical_publication_value(value),auto_unbox=TRUE,null="null",pretty=FALSE)
  digest::digest(enc2utf8(json),algo="sha256",serialize=FALSE)
}

validate_publication_manifest <- function(x) {
  required <- c("schema_version","generator_version","database_identity","source_batch_id",
    "completion_batch_id","input_hashes","bindings","counts","expected_changes",
    "production_authorized","cutover_authorized","manifest_content_sha256")
  if (!publication_names(x,required) ||
      !identical(x$schema_version,"1939-v50-narrative-publication-manifest-v1") ||
      !is.character(x$generator_version) || length(x$generator_version)!=1L ||
      !identical(x$database_identity,publication_database_identity) ||
      !identical(x$source_batch_id,publication_source_batch_id) ||
      !identical(x$completion_batch_id,publication_completion_batch_id) ||
      !identical(x$production_authorized,FALSE) || !identical(x$cutover_authorized,FALSE))
    stop_publication("NARRATIVE_PUBLICATION_1939_MANIFEST_INVALID")
  if (!publication_names(x$input_hashes,c("cutover_preview_sha256","name_completion_verification_sha256")) ||
      any(!vapply(x$input_hashes,publication_hash,logical(1))) ||
      !identical(x$input_hashes$cutover_preview_sha256,"8ab606f55f28e763786568bfa9bb9def829f19bd724c53d4ce6cd560465b63c7") ||
      !identical(x$input_hashes$name_completion_verification_sha256,"b452983d3488b2517da1e404855a5b1da2fbb107a54cee57f056f4f25b7b56db"))
    stop_publication("NARRATIVE_PUBLICATION_1939_INPUT_HASH_INVALID")
  if (!identical(x$bindings,publication_locked_rows) ||
      !identical(x$counts,list(bindings=8L)) ||
      !identical(x$expected_changes,list(bindings_published=8L,persons_activated=0L,
        persons_created=0L,facts_created=0L,relations_created=0L,families_created=0L)))
    stop_publication("NARRATIVE_PUBLICATION_1939_BINDING_INVALID")
  if (!publication_hash(x$manifest_content_sha256))
    stop_publication("NARRATIVE_PUBLICATION_1939_CONTENT_HASH_INVALID")
  content <- x; content$manifest_content_sha256 <- NULL
  if (!identical(canonical_publication_sha256(content),x$manifest_content_sha256))
    stop_publication("NARRATIVE_PUBLICATION_1939_CONTENT_HASH_INVALID")
  invisible(x)
}

execute_publication_preview <- function(manifest,manifest_sha256,gateway) {
  validate_publication_manifest(manifest)
  if (!publication_hash(manifest_sha256)) stop_publication("NARRATIVE_PUBLICATION_1939_MANIFEST_HASH_INVALID")
  if (!is.list(gateway) || !is.function(gateway$call)) stop_publication("NARRATIVE_PUBLICATION_1939_GATEWAY_INVALID")
  call <- gateway$call; connected <- FALSE; rolled_back <- FALSE
  rollback_once <- function() if (connected && !rolled_back) { rolled_back <<- TRUE; call("rollback") }
  tryCatch({
    call("connect"); connected <- TRUE; call("begin")
    preflight <- call("preflight",manifest)
    if (!publication_names(preflight,c("database_name","system_identifier","matched_bindings","draft_bindings")) ||
        !is.character(preflight$database_name) || length(preflight$database_name)!=1L ||
        is.na(preflight$database_name) || !nzchar(preflight$database_name) ||
        !is.character(preflight$system_identifier) || length(preflight$system_identifier)!=1L ||
        is.na(preflight$system_identifier) || !grepl("^[0-9]+$",preflight$system_identifier) ||
        (identical(preflight$database_name,"postgres") &&
          !identical(preflight$system_identifier,publication_database_identity)) ||
        !identical(preflight$matched_bindings,8L) || !identical(preflight$draft_bindings,8L))
      stop_publication("NARRATIVE_PUBLICATION_1939_PREFLIGHT_INVALID")
    returned <- vapply(manifest$bindings,function(binding) call("publish",binding),character(1))
    if (!identical(returned,vapply(manifest$bindings,`[[`,"","binding_id")))
      stop_publication("NARRATIVE_PUBLICATION_1939_PUBLISH_INVALID")
    verified <- call("verify",manifest)
    if (!publication_names(verified,c("published_bindings","binding_ids","record_refs")) ||
        !identical(verified$published_bindings,8L) ||
        !identical(verified$binding_ids,vapply(manifest$bindings,`[[`,"","binding_id")) ||
        !identical(verified$record_refs,vapply(manifest$bindings,`[[`,"","record_ref")))
      stop_publication("NARRATIVE_PUBLICATION_1939_VERIFY_INVALID")
    rollback_once()
    list(status="dry_run_complete",committed=FALSE,database_identity=preflight$system_identifier,
      bindings_published=verified$published_bindings,binding_ids=verified$binding_ids)
  },error=function(e){ rollback_once(); stop(conditionMessage(e),call.=FALSE) })
}

publication_rows_match <- function(rows,manifest,status) {
  if (nrow(rows)!=8L) return(FALSE)
  observed <- lapply(seq_len(nrow(rows)),function(i) list(
    binding_id=rows$binding_id[[i]],narrative_id=as.integer(rows$narrative_id[[i]]),
    person_id=as.integer(rows$person_id[[i]]),source_record_id=rows$source_record_id[[i]],
    record_key=rows$record_key[[i]],record_ref=rows$record_ref[[i]],
    record_label=rows$record_label[[i]],citation_label=rows$citation_label[[i]],
    page=rows$page[[i]],expected_status=rows$expected_status[[i]]))
  expected <- lapply(manifest$bindings,function(binding) {
    binding$expected_status <- status
    binding
  })
  identical(observed,expected)
}

new_publication_dbi_gateway <- function(connection_factory) {
  con <- NULL
  query <- function(sql,params=list()) {
    if (length(params)) DBI::dbGetQuery(con,sql,params=params) else DBI::dbGetQuery(con,sql)
  }
  binding_query <- function(manifest,for_update=FALSE) {
    placeholders <- paste0("$",seq_along(manifest$bindings),"::uuid",collapse=",")
    sql <- paste0("SELECT p.id::text binding_id,p.narrative_id,n.subjekt_id person_id,p.source_record_id::text,sr.record_key,p.record_ref::text,p.record_label,p.citation_label,n.side page,p.status expected_status FROM private.narrative_record_publication p JOIN public.narrative n ON n.id=p.narrative_id JOIN private.source_record sr ON sr.id=p.source_record_id WHERE p.id IN (",placeholders,") ORDER BY n.subjekt_id",if(for_update) " FOR UPDATE OF p" else "")
    query(sql,lapply(manifest$bindings,`[[`,"binding_id"))
  }
  list(call=function(name,...) {
    args <- list(...)
    switch(name,
      connect={con <<- connection_factory(); invisible(NULL)},
      begin={DBI::dbBegin(con); invisible(NULL)},
      preflight={
        manifest <- args[[1L]]
        identity <- query("SELECT current_database() database_name,(pg_control_system()).system_identifier::text system_identifier")
        batches <- query("SELECT id::text,status FROM private.reimport_1939_write_batch WHERE id IN ($1::uuid,$2::uuid) ORDER BY id",list(manifest$completion_batch_id,manifest$source_batch_id))
        rows <- binding_query(manifest,TRUE)
        if (!identical(as.character(batches$id),sort(c(manifest$completion_batch_id,manifest$source_batch_id))) ||
            any(as.character(batches$status)!="finalized") || !publication_rows_match(rows,manifest,"draft"))
          stop_publication("NARRATIVE_PUBLICATION_1939_PREFLIGHT_INVALID")
        list(database_name=identity$database_name[[1L]],system_identifier=identity$system_identifier[[1L]],
          matched_bindings=as.integer(nrow(rows)),draft_bindings=as.integer(sum(rows$expected_status=="draft")))
      },
      publish={
        binding <- args[[1L]]
        query("SELECT public.red_publicer_narrative_record($1,$2::uuid,$3,$4)::text id",
          list(binding$narrative_id,binding$source_record_id,binding$record_label,binding$citation_label))$id[[1L]]
      },
      verify={
        manifest <- args[[1L]]; rows <- binding_query(manifest,FALSE)
        if (!publication_rows_match(rows,manifest,"published")) stop_publication("NARRATIVE_PUBLICATION_1939_VERIFY_INVALID")
        list(published_bindings=as.integer(sum(rows$expected_status=="published")),
          binding_ids=as.character(rows$binding_id),record_refs=as.character(rows$record_ref))
      },
      rollback={DBI::dbRollback(con);DBI::dbDisconnect(con);con <<- NULL;invisible(NULL)},
      stop_publication("NARRATIVE_PUBLICATION_1939_GATEWAY_OPERATION_INVALID")
    )
  })
}
