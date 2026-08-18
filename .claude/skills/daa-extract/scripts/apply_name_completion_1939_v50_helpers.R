name_completion_hash_re <- "^[0-9a-f]{64}$"
name_completion_source_batch_id <- "560c39f8-5c87-4c0d-a768-025d97fa2974"
name_completion_source_manifest_bytes_sha256 <- "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
name_completion_source_manifest_content_sha256 <- "8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03"

stop_name_completion <- function(code) stop(code, call. = FALSE)

name_completion_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl(name_completion_hash_re, value)
}

name_completion_names <- function(value, expected) {
  is.list(value) && identical(sort(names(value)), sort(expected))
}

name_completion_integer <- function(value, expected) {
  is.integer(value) && length(value) == 1L && !is.na(value) && identical(value, expected)
}

name_completion_rows <- list(
  list("record-3766faae-ae21-412a-8cfb-745a19ac77f0", 1846L, "Ditlev", 503L),
  list("record-43d4974a-0532-421d-a3fb-8e7c575a67e7", 1847L, "Gerhard (Gherardus de Reventlow)", 506L),
  list("record-80180a6e-2cc6-4968-81ca-004b6662d8ce", 1848L, "Henning", 506L),
  list("record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422", 1849L, "Henning Reventlow", 508L),
  list("record-8f346104-cf3c-465f-bfa3-efb78be436b2", 1850L, "Iven (Ywanus de Reuentlo)", 506L),
  list("record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58", 1851L, "Henning", 508L),
  list("record-b626f5ff-f2fb-4061-bfce-988dbddec846", 1852L, "Henrik", 506L),
  list("record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d", 1853L, "Margrethe", 517L)
)

validate_name_completion_operation <- function(op, row) {
  required <- c("element_id", "source_batch_id", "source_person_create_element_id",
    "person_id", "source_id", "edition", "source_record_key", "source_persona_id",
    "name", "source_span", "page_evidence", "verbatim_text", "verbatim_sha256",
    "source_payload_sha256", "expected_before", "expected_after")
  if (!name_completion_names(op, required))
    stop_name_completion("NAME_COMPLETION_1939_OPERATION_INVALID")
  key <- row[[1L]]
  if (!identical(op$element_id, paste0("name-completion:", key)) ||
      !identical(op$source_batch_id, name_completion_source_batch_id) ||
      !identical(op$source_person_create_element_id, paste0("person-create:", key)) ||
      !name_completion_integer(op$person_id, row[[2L]]) ||
      !name_completion_integer(op$source_id, 3L) || !identical(op$edition, "1939") ||
      !identical(op$source_record_key, key) || !is.character(op$source_persona_id) ||
      length(op$source_persona_id) != 1L || is.na(op$source_persona_id) ||
      !nzchar(op$source_persona_id) || !identical(op$name, row[[3L]]))
    stop_name_completion("NAME_COMPLETION_1939_BINDING_INVALID")
  if (!name_completion_names(op$source_span, c("char_from", "char_to")) ||
      !is.integer(op$source_span$char_from) || !is.integer(op$source_span$char_to) ||
      op$source_span$char_from < 0L || op$source_span$char_to <= op$source_span$char_from ||
      !name_completion_names(op$page_evidence, c("page_from", "page_to")) ||
      !name_completion_integer(op$page_evidence$page_from, row[[4L]]) ||
      !name_completion_integer(op$page_evidence$page_to, row[[4L]]) ||
      !is.character(op$verbatim_text) || length(op$verbatim_text) != 1L ||
      is.na(op$verbatim_text) || !nzchar(op$verbatim_text) ||
      !name_completion_hash(op$verbatim_sha256) || !name_completion_hash(op$source_payload_sha256))
    stop_name_completion("NAME_COMPLETION_1939_OPERATION_INVALID")
  before <- list(staged = TRUE, name_cache_empty = TRUE, name_facts = 0L)
  after <- list(name_fact = 1L, selected_assertion = 1L, daa_1939_citation = 1L, conclusion = 1L)
  if (!identical(op$expected_before, before) || !identical(op$expected_after, after))
    stop_name_completion("NAME_COMPLETION_1939_EXPECTED_CHANGES_INVALID")
  invisible(op)
}

validate_name_completion_manifest <- function(x) {
  required <- c("schema_version", "generator_version", "input_hashes", "source",
    "source_batch_id", "source_manifest_bytes_sha256", "source_manifest_content_sha256",
    "operations", "counts", "expected_changes", "production_authorized",
    "cutover_authorized", "manifest_content_sha256")
  if (!name_completion_names(x, required) ||
      !identical(x$schema_version, "1939-v50-name-completion-manifest-v1") ||
      !is.character(x$generator_version) || length(x$generator_version) != 1L ||
      !identical(x$production_authorized, FALSE) || !identical(x$cutover_authorized, FALSE))
    stop_name_completion("NAME_COMPLETION_1939_MANIFEST_INVALID")
  if (!name_completion_hash(x$manifest_content_sha256))
    stop_name_completion("NAME_COMPLETION_1939_HASH_INVALID")
  if (!name_completion_names(x$input_hashes, c("production_manifest_sha256",
      "production_apply_sha256", "post_apply_audit_sha256")) ||
      any(!vapply(x$input_hashes, name_completion_hash, logical(1))) ||
      !identical(x$input_hashes$production_manifest_sha256,
        name_completion_source_manifest_bytes_sha256) ||
      !name_completion_names(x$source, c("edition", "source_id")) ||
      !identical(x$source$edition, "1939") || !name_completion_integer(x$source$source_id, 3L))
    stop_name_completion("NAME_COMPLETION_1939_DATABASE_IDENTITY_INVALID")
  if (!identical(x$source_batch_id, name_completion_source_batch_id) ||
      !identical(x$source_manifest_bytes_sha256,
        name_completion_source_manifest_bytes_sha256) ||
      !identical(x$source_manifest_content_sha256,
        name_completion_source_manifest_content_sha256))
    stop_name_completion("NAME_COMPLETION_1939_SOURCE_BATCH_INVALID")
  expected_counts <- list(name_completions = 8L, operations = 8L)
  expected_changes <- list(facts_created = 8L, assertions_created = 8L,
    citations_created = 8L, conclusions_created = 8L, persons_created = 0L,
    persons_activated = 0L, relations_changed = 0L, families_changed = 0L)
  if (!identical(x$counts, expected_counts) || length(x$operations) != 8L)
    stop_name_completion("NAME_COMPLETION_1939_COUNTS_INVALID")
  if (!identical(x$expected_changes, expected_changes))
    stop_name_completion("NAME_COMPLETION_1939_EXPECTED_CHANGES_INVALID")
  if (!all(vapply(x$operations, is.list, logical(1))) ||
      !identical(vapply(x$operations, function(op) op$element_id, character(1)),
        vapply(name_completion_rows, function(row) paste0("name-completion:", row[[1L]]), character(1))))
    stop_name_completion("NAME_COMPLETION_1939_ORDER_INVALID")
  for (index in seq_along(name_completion_rows)) {
    validate_name_completion_operation(x$operations[[index]], name_completion_rows[[index]])
  }
  invisible(x)
}

strip_transport <- function(operation) {
  payload <- operation
  payload$element_id <- NULL
  payload
}

authorized_name_payloads <- function(x) {
  validate_name_completion_manifest(x)
  payloads <- lapply(x$operations, strip_transport)
  names(payloads) <- vapply(x$operations, function(op) op$element_id, character(1))
  payloads
}

execute_name_completion <- function(manifest, manifest_sha256,
                                    mode = c("dry-run", "apply"), gateway,
                                    authorization = NULL) {
  mode <- match.arg(mode)
  validate_name_completion_manifest(manifest)
  if (!name_completion_hash(manifest_sha256))
    stop_name_completion("NAME_COMPLETION_1939_MANIFEST_HASH_INVALID")
  if (!is.list(gateway) || !is.function(gateway$call))
    stop_name_completion("NAME_COMPLETION_1939_GATEWAY_INVALID")
  if (identical(mode, "apply") && (!is.list(authorization) ||
      !is.character(authorization$id) || length(authorization$id) != 1L ||
      is.na(authorization$id) || !nzchar(authorization$id)))
    stop_name_completion("NAME_COMPLETION_1939_AUTHORIZATION_REQUIRED")
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
    call("advisory_lock")
    call("preflight", manifest, manifest_sha256)
    batch <- call("begin_batch", authorization, manifest, manifest_sha256, mode)
    for (op in manifest$operations)
      call("name_completion", batch, op$element_id, strip_transport(op))
    final <- call("finalize", batch)
    if (identical(mode, "dry-run")) rollback_once() else call("commit")
    list(mode = mode, status = final$status, batch_id = final$batch_id,
      committed = identical(mode, "apply"))
  }, error = function(e) {
    rollback_once()
    stop(conditionMessage(e), call. = FALSE)
  })
}

new_name_completion_dbi_gateway <- function(connection_factory) {
  con <- NULL
  query <- function(sql, params = list()) DBI::dbGetQuery(con, sql, params = params)
  execute <- function(sql, params = list()) DBI::dbExecute(con, sql, params = params)
  list(call = function(name, ...) {
    args <- list(...)
    switch(name,
      connect = { con <<- connection_factory(); invisible(NULL) },
      begin = { DBI::dbBegin(con); invisible(NULL) },
      advisory_lock = {
        query("SELECT pg_advisory_xact_lock(hashtextextended('daa-1939-v50-name-completion',0))")
        invisible(NULL)
      },
      preflight = {
        query("SELECT current_database() AS database_name, (pg_control_system()).system_identifier::text AS system_identifier")
        invisible(NULL)
      },
      begin_batch = {
        authorization <- args[[1L]]
        manifest <- args[[2L]]
        manifest_sha256 <- args[[3L]]
        mode <- args[[4L]]
        if (identical(mode, "dry-run")) {
          nonce <- query("SELECT gen_random_uuid() AS id")$id[[1L]]
          authorization <- list(id = query(
            "SELECT public.red_authorize_1939_v50_name_completion($1,$2,$3,$4::jsonb,$5::jsonb,$6,clock_timestamp()+interval '10 minutes') AS id",
            list(manifest_sha256, manifest$source_batch_id, manifest$source$source_id,
              jsonlite::toJSON(manifest$counts, auto_unbox = TRUE),
              jsonlite::toJSON(authorized_name_payloads(manifest), auto_unbox = TRUE, null = "null"), nonce)
          )$id[[1L]])
        }
        query("SELECT public.red_begin_1939_v50_name_completion($1,$2,$3) AS id",
          list(authorization$id, manifest_sha256, manifest$source_batch_id))$id[[1L]]
      },
      name_completion = {
        execute("SELECT public.red_apply_1939_v50_name_completion($1,$2,$3::jsonb)",
          list(args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))
        invisible(NULL)
      },
      finalize = jsonlite::fromJSON(query(
        "SELECT public.red_finalize_1939_v50_name_completion($1)::text AS value", list(args[[1L]])
      )$value[[1L]], simplifyVector = FALSE),
      rollback = { DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      commit = { DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      stop_name_completion("NAME_COMPLETION_1939_GATEWAY_OPERATION_INVALID")
    )
  })
}
