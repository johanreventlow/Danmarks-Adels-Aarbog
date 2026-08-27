hash_re <- "^[0-9a-f]{64}$"

stop_writer <- function(code) stop(code, call. = FALSE)

validate_production_manifest <- function(x) {
  required <- c("schema_version","generator_version","input_hashes","source","expected_database_contract",
    "existing_anchors","person_creates","provenance_dispositions","canonical_delta",
    "operations","counts","expected_changes","manifest_content_sha256",
    "production_authorized","apply_gate","cutover_gate")
  if (!is.list(x) || !identical(sort(names(x)), sort(required)) ||
      !identical(x$schema_version,"1939-v50-production-write-manifest-v1") ||
      !identical(x$production_authorized,FALSE) || !identical(x$apply_gate,"NO-GO") ||
      !identical(x$cutover_gate,"NO-GO") || !grepl(hash_re,x$manifest_content_sha256) ||
      !identical(x$source$edition,"1939") || !identical(as.integer(x$source$database_source_id),3L))
    stop_writer("REIMPORT_1939_MANIFEST_INVALID")
  cts <- x$counts
  expected <- c(existing_anchors=543L,person_creates=8L,provenance_dispositions=305L,
    source_evidence_operations=305L,canonical_delta=0L,operations=313L)
  got <- vapply(names(expected),function(n) as.integer(cts[[n]]),integer(1))
  if (!identical(got,expected) || length(x$existing_anchors)!=543L ||
      length(x$person_creates)!=8L || length(x$provenance_dispositions)!=305L ||
      length(x$canonical_delta)!=0L || length(x$operations)!=313L)
    stop_writer("REIMPORT_1939_MANIFEST_COUNTS_INVALID")
  ids <- vapply(x$operations,function(z) z$element_id,character(1))
  classes <- vapply(x$operations,function(z) z$dependency_class,character(1))
  if (anyDuplicated(ids) || !identical(classes,c(rep("source_evidence",305),rep("person_create",8))))
    stop_writer("REIMPORT_1939_MANIFEST_ORDER_INVALID")
  create_keys <- vapply(x$person_creates,function(z) z$source_record_key,character(1))
  if (length(unique(create_keys))!=8L || any(vapply(x$person_creates,function(z) !isTRUE(z$staged) || !is.null(z$person_id),logical(1))))
    stop_writer("REIMPORT_1939_MANIFEST_PERSON_CREATE_INVALID")
  invisible(x)
}

authorized_element_payloads <- function(manifest) {
  payloads <- lapply(manifest$operations, function(op) {
    payload <- op
    payload$element_id <- NULL
    payload$dependency_class <- NULL
    payload$rendition_content_sha256 <- manifest$source$rendition_content_sha256
    payload
  })
  names(payloads) <- vapply(manifest$operations, function(op) op$element_id, character(1))
  payloads
}

execute_reimport <- function(manifest, preview_sha256, mode=c("dry-run","apply"), gateway,
                             authorization=NULL) {
  mode <- match.arg(mode); validate_production_manifest(manifest)
  if (!is.character(preview_sha256) || length(preview_sha256)!=1L || !grepl(hash_re,preview_sha256))
    stop_writer("REIMPORT_1939_PREVIEW_HASH_INVALID")
  if (mode=="apply" && (is.null(authorization) || !is.list(authorization) || is.null(authorization$id)))
    stop_writer("REIMPORT_1939_AUTHORIZATION_REQUIRED")
  call <- gateway$call; rolled <- FALSE; connected <- FALSE
  rollback_once <- function() if (connected && !rolled) { call("rollback"); rolled <<- TRUE }
  tryCatch({
    call("connect"); connected <- TRUE; call("begin"); call("advisory_lock")
    call("preflight",manifest,preview_sha256)
    batch <- call("begin_batch",if(mode=="apply") authorization else NULL,manifest,preview_sha256,mode)
    for (op in manifest$operations[vapply(manifest$operations,function(z) z$dependency_class=="source_evidence",logical(1))]) {
      payload <- op; payload$element_id <- NULL; payload$dependency_class <- NULL
      payload$rendition_content_sha256 <- manifest$source$rendition_content_sha256
      call("source_evidence",batch,op$element_id,payload)
    }
    person_map <- list()
    for (op in manifest$operations[vapply(manifest$operations,function(z) z$dependency_class=="person_create",logical(1))]) {
      payload <- op; payload$element_id <- NULL; payload$dependency_class <- NULL
      payload$rendition_content_sha256 <- manifest$source$rendition_content_sha256
      person_map[[op$source_record_key]] <- call("person_create",batch,op$element_id,payload)
    }
    for (op in manifest$canonical_delta) call("canonical_delta",batch,op$element_id,op)
    final <- call("finalize",batch)
    if (mode=="dry-run") rollback_once() else call("commit")
    list(mode=mode,status=final$status,person_id_map=person_map,committed=identical(mode,"apply"))
  }, error=function(e) { rollback_once(); stop(conditionMessage(e),call.=FALSE) })
}

new_dbi_writer_gateway <- function(connection_factory) {
  con <- NULL
  query <- function(sql,params=list()) {
    if (length(params)) DBI::dbGetQuery(con,sql,params=params) else DBI::dbGetQuery(con,sql)
  }
  execute <- function(sql,params=list()) {
    if (length(params)) DBI::dbExecute(con,sql,params=params) else DBI::dbExecute(con,sql)
  }
  list(call=function(name, ...) {
    args <- list(...)
    switch(name,
      connect={con <<- connection_factory(); invisible(NULL)},
      begin={DBI::dbBegin(con); invisible(NULL)},
      advisory_lock={query("SELECT pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0))"); invisible(NULL)},
      preflight={
        actor <- Sys.getenv("DAA_REIMPORT_ACTOR_ID")
        if (!grepl("^[0-9a-f]{8}-[0-9a-f-]{27}$",actor)) stop_writer("REIMPORT_1939_ACTOR_REQUIRED")
        query("SELECT set_config('request.jwt.claim.sub',$1,true)",list(actor))
        query("SELECT current_setting('transaction_read_only') AS transaction_read_only, current_database() AS database_name")
      },
      begin_batch={
        auth <- args[[1]]; manifest <- args[[2]]; preview <- args[[3]]; mode <- args[[4]]
        if (mode=="dry-run") {
          nonce <- query("SELECT gen_random_uuid() AS id")$id[[1]]
          counts <- jsonlite::toJSON(list(person_creates=8L,source_evidence=305L,canonical_delta=0L),auto_unbox=TRUE)
          elements <- jsonlite::toJSON(authorized_element_payloads(manifest),auto_unbox=TRUE,null="null")
          auth <- list(id=query("SELECT public.red_authorize_1939_v50_reimport($1,$2,current_database(),3,$3::jsonb,$4::jsonb,$5,clock_timestamp()+interval '10 minutes') AS id",list(manifest$manifest_content_sha256,preview,counts,elements,nonce))$id[[1]])
        }
        query("SELECT public.red_begin_1939_v50_reimport($1,$2,$3) AS id",list(auth$id,manifest$manifest_content_sha256,preview))$id[[1]]
      },
      source_evidence={execute("SELECT public.red_apply_1939_v50_source_evidence($1,$2,$3::jsonb)",list(args[[1]],args[[2]],jsonlite::toJSON(args[[3]],auto_unbox=TRUE,null="null"))); invisible(NULL)},
      person_create=query("SELECT public.red_apply_1939_v50_person_create($1,$2,$3::jsonb) AS id",list(args[[1]],args[[2]],jsonlite::toJSON(args[[3]],auto_unbox=TRUE,null="null")))$id[[1]],
      canonical_delta={execute("SELECT public.red_apply_1939_v50_canonical_delta($1,$2,$3::jsonb)",list(args[[1]],args[[2]],jsonlite::toJSON(args[[3]],auto_unbox=TRUE,null="null"))); invisible(NULL)},
      finalize=jsonlite::fromJSON(query("SELECT public.red_finalize_1939_v50_reimport($1)::text AS value",list(args[[1]]))$value[[1]],simplifyVector=FALSE),
      rollback={DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL)},
      commit={DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL)},
      stop_writer("REIMPORT_1939_GATEWAY_OPERATION_INVALID")
    )
  })
}
