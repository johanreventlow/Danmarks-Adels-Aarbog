## #153 Task 4D public V3 gateway. The supplied manifest JSON is compiler
## output; PostgreSQL remains the authority for every private binding and DML.

ssr_v3_validate_apply_request <- function(request) {
  fields <- c(
    "database_name", "system_identifier", "deployment_id", "actor_id", "nonce",
    "manifest_json", "manifest_semantic_sha256", "dry_run_semantic_sha256",
    "ownership_semantic_sha256", "artifact_sha256", "expires_at", "deployment_sha256"
  )
  if (!is.list(request) || !identical(sort(names(request)), sort(fields)) ||
      !is.character(request$database_name) || length(request$database_name) != 1L ||
      !nzchar(request$database_name) ||
      !is.character(request$system_identifier) || length(request$system_identifier) != 1L ||
      !nzchar(request$system_identifier) ||
      !all(vapply(request[c("deployment_id", "actor_id", "nonce")], ssr_v3_uuid, logical(1L))) ||
      !is.character(request$manifest_json) || length(request$manifest_json) != 1L ||
      !nzchar(request$manifest_json) ||
      !all(vapply(request[c(
        "manifest_semantic_sha256", "dry_run_semantic_sha256", "ownership_semantic_sha256",
        "artifact_sha256", "deployment_sha256"
      )], ssr_v3_sha256, logical(1L))) ||
      !is.character(request$expires_at) || length(request$expires_at) != 1L ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", request$expires_at)) {
    ssr_v3_stop("SOURCE_SCOPED_REPLACE_MANIFEST_INVALID")
  }
  request[fields]
}

ssr_v3_gateway_rpc <- function(gateway, name, params) {
  if (!is.list(gateway) || !is.function(gateway$rpc)) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_INVALID")
  }
  gateway$rpc(name, params)
}

ssr_v3_validate_observed_counts <- function(counts) {
  fields <- c(
    "source_operations", "content_revisions", "tombstone_revisions", "facts",
    "assertions", "citations", "narrative_operations"
  )
  if (!is.list(counts) || !identical(sort(names(counts)), sort(fields)) || any(!vapply(
    counts,
    function(value) is.numeric(value) && length(value) == 1L && !is.na(value) && value >= 0 && value == floor(value),
    logical(1L)
  ))) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_APPLY_INVALID")
  }
  counts[fields]
}

ssr_v3_validate_apply_receipt <- function(receipt, authorization_id, request) {
  fields <- c(
    "schema", "authorization_id", "batch_id", "terminal_status", "manifest_semantic_sha256",
    "observed_counts", "verified_state"
  )
  if (!is.list(receipt) || !identical(sort(names(receipt)), sort(fields)) ||
      !identical(receipt$schema, "source-scoped-evidence-v3-apply-receipt-v1") ||
      !identical(receipt$authorization_id, authorization_id) || !ssr_v3_uuid(receipt$batch_id) ||
      !identical(receipt$terminal_status, "applied") ||
      !identical(receipt$manifest_semantic_sha256, request$manifest_semantic_sha256) ||
      !is.list(receipt$verified_state)) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_APPLY_INVALID")
  }
  ssr_v3_validate_observed_counts(receipt$observed_counts)
  receipt
}

ssr_v3_validate_apply_response <- function(response, authorization_id, request) {
  fields <- c("replayed", "receipt")
  if (!is.list(response) || !identical(sort(names(response)), sort(fields)) ||
      !is.logical(response$replayed) || length(response$replayed) != 1L || is.na(response$replayed)) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_APPLY_INVALID")
  }
  list(replayed = response$replayed, receipt = ssr_v3_validate_apply_receipt(
    response$receipt, authorization_id, request
  ))
}

ssr_v3_validate_verify_response <- function(response, authorization_id, request, applied) {
  fields <- c("receipt", "apply_state", "publication_state")
  if (!is.list(response) || !identical(sort(names(response)), sort(fields))) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_VERIFY_INVALID")
  }
  receipt <- tryCatch(
    ssr_v3_validate_apply_receipt(response$receipt, authorization_id, request),
    error = function(error) ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_VERIFY_INVALID")
  )
  if (!identical(receipt, applied$receipt) || !identical(response$apply_state, receipt$verified_state) ||
      !is.list(response$publication_state) ||
      !identical(sort(names(response$publication_state)), sort(c("schema", "chains"))) ||
      !identical(response$publication_state$schema, "source-scoped-evidence-v3-publication-state-v1") ||
      !is.list(response$publication_state$chains)) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_VERIFY_INVALID")
  }
  list(receipt = receipt, apply_state = response$apply_state, publication_state = response$publication_state)
}

ssr_apply_v3 <- function(gateway, request) {
  checked <- ssr_v3_validate_apply_request(request)
  ssr_v3_preflight(gateway, checked[c(
    "manifest_semantic_sha256", "dry_run_semantic_sha256",
    "ownership_semantic_sha256", "deployment_id", "deployment_sha256"
  )])
  authorization <- ssr_v3_gateway_rpc(gateway, "public.red_authorize_source_scoped_replace_v3", list(
    checked$database_name, checked$system_identifier, checked$deployment_id,
    checked$actor_id, checked$nonce, checked$manifest_json,
    checked$manifest_semantic_sha256, checked$dry_run_semantic_sha256,
    checked$ownership_semantic_sha256, checked$artifact_sha256, checked$expires_at
  ))
  if (!is.list(authorization) || !ssr_v3_uuid(authorization$id)) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_AUTHORIZATION_INVALID")
  }
  applied <- ssr_v3_validate_apply_response(ssr_v3_gateway_rpc(
    gateway, "public.red_apply_source_scoped_replace_v3", list(
    authorization$id, checked$manifest_json
  )), authorization$id, checked)
  verified <- ssr_v3_validate_verify_response(ssr_v3_gateway_rpc(
    gateway, "public.red_verify_source_scoped_replace_v3", list(authorization$id)
  ), authorization$id, checked, applied)
  list(authorization_id = authorization$id, apply = applied, verify = verified)
}
