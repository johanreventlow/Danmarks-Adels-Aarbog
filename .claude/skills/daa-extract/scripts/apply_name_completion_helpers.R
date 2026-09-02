name_completion_hash_re <- "^[0-9a-f]{64}$"
name_completion_uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

stop_name_completion <- function(code) stop(code, call. = FALSE)

generic_name_completion_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && grepl(name_completion_hash_re, value)
}

generic_name_completion_uuid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && grepl(name_completion_uuid_re, value)
}

name_completion_named <- function(value, expected) {
  is.list(value) && identical(sort(names(value)), sort(expected))
}

validate_generic_name_completion_manifest <- function(manifest) {
  required <- c("manifest_content_sha256", "source", "source_batch_id", "source_manifest_bytes_sha256", "source_manifest_content_sha256", "expected_counts", "operations")
  if (!name_completion_named(manifest, required) || !generic_name_completion_hash(manifest$manifest_content_sha256) ||
      !name_completion_named(manifest$source, c("id", "profile_id", "profile_sha256")) ||
      !is.integer(manifest$source$id) || length(manifest$source$id) != 1L || is.na(manifest$source$id) || manifest$source$id <= 0L ||
      !is.character(manifest$source$profile_id) || length(manifest$source$profile_id) != 1L || is.na(manifest$source$profile_id) || !nzchar(manifest$source$profile_id) ||
      !generic_name_completion_hash(manifest$source$profile_sha256))
    stop_name_completion("REIMPORT_NAME_COMPLETION_MANIFEST_PROFILE_INVALID")
  if (!generic_name_completion_uuid(manifest$source_batch_id) || !generic_name_completion_hash(manifest$source_manifest_bytes_sha256) ||
      !generic_name_completion_hash(manifest$source_manifest_content_sha256) ||
      !name_completion_named(manifest$expected_counts, c("name_completions", "operations")) ||
      any(!vapply(manifest$expected_counts, function(value) is.integer(value) && length(value) == 1L && !is.na(value) && value >= 0L, logical(1))) ||
      !identical(manifest$expected_counts$name_completions, manifest$expected_counts$operations) || !is.list(manifest$operations) ||
      length(manifest$operations) != as.integer(manifest$expected_counts$operations) ||
      !all(vapply(manifest$operations, function(operation) is.list(operation) && is.character(operation$element_id) &&
        length(operation$element_id) == 1L && nzchar(operation$element_id), logical(1))) ||
      anyDuplicated(vapply(manifest$operations, `[[`, "", "element_id")))
    stop_name_completion("REIMPORT_NAME_COMPLETION_MANIFEST_INVALID")
  invisible(manifest)
}

name_completion_payloads <- function(manifest) {
  validate_generic_name_completion_manifest(manifest)
  payloads <- lapply(manifest$operations, function(operation) {
    operation$element_id <- NULL
    operation
  })
  names(payloads) <- vapply(manifest$operations, `[[`, "", "element_id")
  payloads
}

validate_generic_name_completion_preflight <- function(preflight, manifest) {
  required <- c("database_identity", "actor_id", "transaction_read_only", "source", "locked_payload_count")
  if (!name_completion_named(preflight, required) ||
      !is.character(preflight$database_identity) || length(preflight$database_identity) != 1L || is.na(preflight$database_identity) || !nzchar(preflight$database_identity) ||
      !generic_name_completion_uuid(preflight$actor_id) || !identical(preflight$transaction_read_only, "off") ||
      !identical(preflight$source, manifest$source) || !is.integer(preflight$locked_payload_count) ||
      length(preflight$locked_payload_count) != 1L || !identical(preflight$locked_payload_count, as.integer(length(manifest$operations))))
    stop_name_completion("REIMPORT_NAME_COMPLETION_DATABASE_PROFILE_MISMATCH")
  invisible(preflight)
}

validate_generic_name_completion_authorization <- function(authorization, manifest = NULL) {
  if (!is.list(authorization) || !generic_name_completion_uuid(authorization$authorization_id) ||
      !is.character(authorization$database_name) || length(authorization$database_name) != 1L ||
      !is.character(authorization$system_identifier) || length(authorization$system_identifier) != 1L ||
      !is.list(authorization$source) || (!is.null(manifest) && !identical(authorization$source, manifest$source)))
    stop_name_completion("REIMPORT_NAME_COMPLETION_AUTHORIZATION_REQUIRED")
  invisible(authorization)
}

validate_name_completion_server_preflight <- function(result, authorization, manifest, manifest_sha256) {
  required <- c("valid", "database_name", "system_identifier", "source_batch_id", "manifest_sha256")
  if (!name_completion_named(result, c("authorization", "preflight")))
    stop_name_completion("REIMPORT_NAME_COMPLETION_PREFLIGHT_INVALID")
  validate_generic_name_completion_authorization(result$authorization, manifest)
  if (!identical(result$authorization, authorization))
    stop_name_completion("REIMPORT_NAME_COMPLETION_AUTHORIZATION_REQUIRED")
  if (!name_completion_named(result$preflight, required) || !identical(result$preflight$valid, TRUE) ||
      !identical(result$preflight$source_batch_id, manifest$source_batch_id) ||
      !identical(result$preflight$manifest_sha256, manifest_sha256) ||
      !is.character(authorization$database_name) || !identical(result$preflight$database_name, authorization$database_name) ||
      !is.character(authorization$system_identifier) || !identical(result$preflight$system_identifier, authorization$system_identifier))
    stop_name_completion("REIMPORT_NAME_COMPLETION_PREFLIGHT_INVALID")
  invisible(result)
}

execute_name_completion <- function(manifest, manifest_sha256, mode = c("dry-run", "apply"), gateway, authorization = NULL) {
  mode <- match.arg(mode)
  validate_generic_name_completion_manifest(manifest)
  if (!generic_name_completion_hash(manifest_sha256))
    stop_name_completion("REIMPORT_NAME_COMPLETION_MANIFEST_HASH_INVALID")
  if (!is.list(gateway) || !is.function(gateway$call)) stop_name_completion("REIMPORT_NAME_COMPLETION_GATEWAY_INVALID")
  if (identical(mode, "apply")) validate_generic_name_completion_authorization(authorization, manifest)
  call <- gateway$call
  connected <- FALSE
  rolled_back <- FALSE
  rollback_once <- function() {
    if (connected && !rolled_back) {
      rolled_back <<- TRUE
      call("rollback")
    }
  }
  tryCatch({
    call("connect")
    connected <- TRUE
    call("begin")
    call("advisory_lock", manifest$source)
    validate_generic_name_completion_preflight(call("preflight", manifest), manifest)
    resolved_authorization <- call("authorize", manifest, manifest_sha256, mode, authorization)
    validate_generic_name_completion_authorization(resolved_authorization, manifest)
    server_preflight <- call("preflight_authorization", resolved_authorization, manifest, manifest_sha256, name_completion_payloads(manifest))
    validate_name_completion_server_preflight(server_preflight, resolved_authorization, manifest, manifest_sha256)
    batch_id <- call("begin_batch", resolved_authorization, manifest, manifest_sha256)
    for (operation in manifest$operations) {
      payload <- operation
      payload$element_id <- NULL
      call("name_completion", batch_id, operation$element_id, payload)
    }
    final <- call("finalize", batch_id)
    expected_keys <- vapply(manifest$operations, `[[`, "", "element_id")
    expected_result_fields <- c("person_id", "fact_id", "assertion_id", "citation_id", "conclusion_id")
    if (!name_completion_named(final, c("batch_id", "status", "counts", "result_map")) || !is.list(final$result_map) ||
        !identical(names(final$result_map), expected_keys) ||
        !all(vapply(final$result_map, name_completion_named, logical(1), expected_result_fields)))
      stop_name_completion("REIMPORT_NAME_COMPLETION_FINALIZE_INVALID")
    if (identical(mode, "dry-run")) rollback_once() else call("commit")
    list(mode = mode, status = final$status, batch_id = final$batch_id, authorization = resolved_authorization,
      result_map = final$result_map, committed = identical(mode, "apply"))
  }, error = function(error) {
    rollback_once()
    stop(conditionMessage(error), call. = FALSE)
  })
}

new_name_completion_dbi_gateway <- function(connection_factory) {
  con <- NULL
  query <- function(sql, params = list()) {
    if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  }
  execute <- function(sql, params = list()) {
    if (length(params)) DBI::dbExecute(con, sql, params = params) else DBI::dbExecute(con, sql)
  }
  list(call = function(name, ...) {
    args <- list(...)
    switch(name,
      connect = { con <<- connection_factory(); invisible(NULL) },
      begin = { DBI::dbBegin(con); invisible(NULL) },
      advisory_lock = {
        source <- args[[1L]]
        query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(
          paste("daa-reimport-name-completion", source$id, source$profile_id, sep = ":")))
        invisible(NULL)
      },
      preflight = {
        manifest <- args[[1L]]
        actor <- Sys.getenv("DAA_REIMPORT_ACTOR_ID")
        if (!generic_name_completion_uuid(actor)) stop_name_completion("REIMPORT_NAME_COMPLETION_ACTOR_REQUIRED")
        query("SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
        state <- query("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS database_identity, current_setting('request.jwt.claim.sub',true) AS actor_id, current_setting('transaction_read_only') AS transaction_read_only")
        list(database_identity = state$database_identity[[1L]], actor_id = state$actor_id[[1L]],
          transaction_read_only = state$transaction_read_only[[1L]], source = manifest$source,
          locked_payload_count = as.integer(length(manifest$operations)))
      },
      authorize = {
        manifest <- args[[1L]]
        manifest_sha256 <- args[[2L]]
        mode <- args[[3L]]
        supplied <- args[[4L]]
        if (identical(mode, "apply")) return(supplied)
        jsonlite::fromJSON(query("SELECT public.red_authorize_reimport_name_completion($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9::jsonb)::text AS value", list(
          manifest_sha256, manifest$source_batch_id, manifest$source_manifest_bytes_sha256,
          manifest$source_manifest_content_sha256, manifest$source$id, manifest$source$profile_id, manifest$source$profile_sha256, jsonlite::toJSON(manifest$expected_counts, auto_unbox = TRUE),
          jsonlite::toJSON(name_completion_payloads(manifest), auto_unbox = TRUE, null = "null")))$value[[1L]], simplifyVector = FALSE)
      },
      preflight_authorization = {
        authorization <- args[[1L]]
        manifest <- args[[2L]]
        response <- jsonlite::fromJSON(query("SELECT public.red_preflight_reimport_name_completion($1,$2,$3,$4::jsonb)::text AS value", list(
          authorization$authorization_id, manifest$source_batch_id, args[[3L]],
          jsonlite::toJSON(args[[4L]], auto_unbox = TRUE, null = "null")))$value[[1L]], simplifyVector = FALSE)
        response
      },
      begin_batch = query("SELECT public.red_begin_reimport_name_completion($1,$2,$3) AS id", list(
        args[[1L]]$authorization_id, args[[3L]], args[[2L]]$source_batch_id))$id[[1L]],
      name_completion = {
        execute("SELECT public.red_apply_reimport_name_completion($1,$2,$3::jsonb)", list(
          args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))
        query("SELECT set_config('app.change_set_id','',true)")
        invisible(NULL)
      },
      finalize = jsonlite::fromJSON(query("SELECT public.red_finalize_reimport_name_completion($1)::text AS value", list(args[[1L]]))$value[[1L]], simplifyVector = FALSE),
      rollback = { DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      commit = { DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      stop_name_completion("REIMPORT_NAME_COMPLETION_GATEWAY_OPERATION_INVALID")
    )
  })
}

new_default_name_completion_dbi_gateway <- function() {
  new_name_completion_dbi_gateway(function() DBI::dbConnect(RPostgres::Postgres(),
    dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
    user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD")))
}
