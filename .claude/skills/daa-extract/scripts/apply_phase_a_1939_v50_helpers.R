## Fase A-writer: skriver KUN source_evidence-elementer (retain_source_only)
## for den låste 584/0/0-batch fra `build_phase_a_anchor_manifest_1939_v50.py`.
## Delt RPC-familie med `apply_reimport_1939_v50_helpers.R`
## (red_authorize_1939_v50_reimport/red_begin_1939_v50_reimport/
## red_apply_1939_v50_source_evidence/red_finalize_1939_v50_reimport) —
## men EGEN, hård-låst validator: denne wrapper afviser alt der ikke er
## nøjagtig fase-A-batchen. Mønstret er kopieret fra
## apply_reimport_1939_v50_helpers.R / apply_name_completion_1939_v50_helpers.R
## — koden er bevidst IKKE delt (batch-specifik designbeslutning).

phase_a_hash_re <- "^[0-9a-f]{64}$"

phase_a_sql_payload_keys <- c(
  "review_subject_id", "source_record_key", "category", "disposition",
  "evidence_sha256", "canonical_target", "source_span", "page_evidence",
  "verbatim_text", "legacy_payload", "rendition_content_sha256"
)
phase_a_sql_payload_required <- c(
  "review_subject_id", "source_record_key", "category", "disposition",
  "evidence_sha256", "source_span", "page_evidence", "verbatim_text",
  "rendition_content_sha256"
)

phase_a_required_manifest_keys <- c(
  "apply_gate", "arithmetic", "counts", "expected_changes", "generator_version",
  "input_hashes", "operations", "production_authorized", "schema_version",
  "source", "manifest_content_sha256"
)

phase_a_expected_counts <- list(person_creates = 0L, source_evidence = 584L, canonical_delta = 0L)
phase_a_expected_changes <- list(
  persons_created = 0L, source_evidence_written = 584L,
  canonical_rows_changed = 0L, persons_activated = 0L
)
phase_a_expected_arithmetic <- list(
  source_records = 592L, excluded_already_written = 8L,
  elements = 584L, canonical_targets = 543L
)

stop_phase_a <- function(code) stop(code, call. = FALSE)

phase_a_names_equal <- function(value, expected) {
  is.list(value) && !is.null(names(value)) && !anyNA(names(value)) &&
    !anyDuplicated(names(value)) && identical(sort(names(value)), sort(expected))
}

phase_a_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && grepl(phase_a_hash_re, value)
}

phase_a_uuid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[0-9a-f]{8}-[0-9a-f-]{27}$", value)
}

phase_a_int <- function(value) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || value %% 1 != 0) return(NA_integer_)
  as.integer(value)
}

phase_a_scalar_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

## -- kanonisk indhold-sha256 (sortnøgle-genberegning), samme mønster som
## canonical_name_completion_sha256/canonical_publication_sha256, egen kopi.
canonical_phase_a_value <- function(value) {
  if (!is.list(value)) return(value)
  value_names <- names(value)
  if (is.null(value_names)) return(lapply(value, canonical_phase_a_value))
  if (anyNA(value_names) || anyDuplicated(value_names)) stop_phase_a("PHASE_A_1939_CANONICAL_INVALID")
  ordered_names <- sort(value_names, method = "radix")
  result <- lapply(ordered_names, function(name) canonical_phase_a_value(value[[name]]))
  names(result) <- ordered_names
  result
}

canonical_phase_a_sha256 <- function(value) {
  json <- jsonlite::toJSON(canonical_phase_a_value(value), auto_unbox = TRUE, null = "null", pretty = FALSE)
  digest::digest(enc2utf8(json), algo = "sha256", serialize = FALSE)
}

strip_phase_a_transport <- function(op) {
  payload <- op
  payload$element_id <- NULL
  payload$dependency_class <- NULL
  payload
}

authorized_phase_a_payloads <- function(manifest) {
  payloads <- lapply(manifest$operations, strip_phase_a_transport)
  names(payloads) <- vapply(manifest$operations, function(op) op$element_id, character(1))
  payloads
}

## -- pr.-operation-validering. Returnerer TRUE hvis operationen har
## canonical_target (bruges til at tælle de forventede 543).
validate_phase_a_operation <- function(op, rendition_sha256) {
  if (!is.list(op) || is.null(names(op)) || anyNA(names(op)) || anyDuplicated(names(op)))
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  op_names <- names(op)
  allowed <- c("element_id", "dependency_class", phase_a_sql_payload_keys)
  if (length(setdiff(op_names, allowed)) > 0L) stop_phase_a("PHASE_A_1939_PAYLOAD_KEY_INVALID")
  if (length(setdiff(phase_a_sql_payload_required, op_names)) > 0L)
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (!identical(op$dependency_class, "source_evidence"))
    stop_phase_a("PHASE_A_1939_DEPENDENCY_CLASS_INVALID")
  if (!phase_a_scalar_string(op$element_id) || !startsWith(op$element_id, "phase-a:"))
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (!identical(op$disposition, "retain_source_only"))
    stop_phase_a("PHASE_A_1939_DISPOSITION_INVALID")
  if (!phase_a_scalar_string(op$source_record_key) || !identical(op$review_subject_id, op$source_record_key))
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (!phase_a_scalar_string(op$category) ||
      !(op$category %in% c("person", "structural_context", "cross_reference")))
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (!phase_a_hash(op$evidence_sha256)) stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  span <- op$source_span
  if (!phase_a_names_equal(span, c("char_from", "char_to")) ||
      is.na(phase_a_int(span$char_from)) || is.na(phase_a_int(span$char_to)) ||
      phase_a_int(span$char_from) < 0L || phase_a_int(span$char_to) <= phase_a_int(span$char_from))
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  page <- op$page_evidence
  if (!phase_a_names_equal(page, c("page_from", "page_to")) ||
      is.na(phase_a_int(page$page_from)) || is.na(phase_a_int(page$page_to)) ||
      phase_a_int(page$page_from) < 1L || phase_a_int(page$page_to) < phase_a_int(page$page_from))
    stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (!phase_a_scalar_string(op$verbatim_text)) stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (!identical(op$rendition_content_sha256, rendition_sha256))
    stop_phase_a("PHASE_A_1939_RENDITION_DRIFT")
  has_canonical <- "canonical_target" %in% op_names
  has_legacy <- "legacy_payload" %in% op_names
  if (has_canonical != has_legacy) stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (has_canonical) {
    target <- op$canonical_target
    if (!phase_a_names_equal(target, "person_id") ||
        is.na(phase_a_int(target$person_id)) || phase_a_int(target$person_id) <= 0L)
      stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
    legacy <- op$legacy_payload
    if (!phase_a_names_equal(legacy, c("baseline_record_key", "legacy_name")) ||
        !phase_a_scalar_string(legacy$baseline_record_key) ||
        !(is.null(legacy$legacy_name) || phase_a_scalar_string(legacy$legacy_name)))
      stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  }
  has_canonical
}

validate_phase_a_manifest <- function(x) {
  if (!phase_a_names_equal(x, phase_a_required_manifest_keys))
    stop_phase_a("PHASE_A_1939_MANIFEST_INVALID")
  if (!identical(x$schema_version, "1939-v50-phase-a-anchor-manifest-v1") ||
      !identical(x$production_authorized, FALSE) || !identical(x$apply_gate, "NO-GO") ||
      !phase_a_hash(x$manifest_content_sha256) ||
      !phase_a_scalar_string(x$generator_version))
    stop_phase_a("PHASE_A_1939_MANIFEST_INVALID")

  src <- x$source
  if (!phase_a_names_equal(src, c("edition", "logical_source_id", "database_source_id", "rendition_content_sha256")) ||
      !identical(src$edition, "1939") || !identical(src$logical_source_id, "1939") ||
      is.na(phase_a_int(src$database_source_id)) || !identical(phase_a_int(src$database_source_id), 3L) ||
      !phase_a_hash(src$rendition_content_sha256))
    stop_phase_a("PHASE_A_1939_SOURCE_INVALID")

  if (!is.list(x$input_hashes) || is.null(names(x$input_hashes)) || anyNA(names(x$input_hashes)) ||
      anyDuplicated(names(x$input_hashes)) || length(x$input_hashes) < 1L ||
      any(!vapply(x$input_hashes, phase_a_hash, logical(1))))
    stop_phase_a("PHASE_A_1939_INPUT_HASHES_INVALID")

  got_counts <- list(
    person_creates = phase_a_int(x$counts$person_creates),
    source_evidence = phase_a_int(x$counts$source_evidence),
    canonical_delta = phase_a_int(x$counts$canonical_delta)
  )
  if (!phase_a_names_equal(x$counts, names(phase_a_expected_counts)) ||
      !identical(got_counts, phase_a_expected_counts))
    stop_phase_a("PHASE_A_1939_COUNTS_INVALID")

  got_changes <- list(
    persons_created = phase_a_int(x$expected_changes$persons_created),
    source_evidence_written = phase_a_int(x$expected_changes$source_evidence_written),
    canonical_rows_changed = phase_a_int(x$expected_changes$canonical_rows_changed),
    persons_activated = phase_a_int(x$expected_changes$persons_activated)
  )
  if (!phase_a_names_equal(x$expected_changes, names(phase_a_expected_changes)) ||
      !identical(got_changes, phase_a_expected_changes))
    stop_phase_a("PHASE_A_1939_EXPECTED_CHANGES_INVALID")

  got_arith <- list(
    source_records = phase_a_int(x$arithmetic$source_records),
    excluded_already_written = phase_a_int(x$arithmetic$excluded_already_written),
    elements = phase_a_int(x$arithmetic$elements),
    canonical_targets = phase_a_int(x$arithmetic$canonical_targets)
  )
  if (!phase_a_names_equal(x$arithmetic, names(phase_a_expected_arithmetic)) ||
      !identical(got_arith, phase_a_expected_arithmetic))
    stop_phase_a("PHASE_A_1939_ARITHMETIC_INVALID")

  ops <- x$operations
  if (!is.list(ops) || length(ops) != 584L) stop_phase_a("PHASE_A_1939_COUNTS_INVALID")
  ids <- vapply(ops, function(op) {
    if (is.list(op) && phase_a_scalar_string(op$element_id)) op$element_id else NA_character_
  }, character(1))
  if (anyNA(ids)) stop_phase_a("PHASE_A_1939_OPERATION_INVALID")
  if (anyDuplicated(ids)) stop_phase_a("PHASE_A_1939_ORDER_INVALID")
  if (!identical(ids, sort(ids, method = "radix"))) stop_phase_a("PHASE_A_1939_ORDER_INVALID")

  canonical_flags <- vapply(ops, validate_phase_a_operation, logical(1), rendition_sha256 = src$rendition_content_sha256)
  if (sum(canonical_flags) != 543L) stop_phase_a("PHASE_A_1939_ARITHMETIC_INVALID")

  content <- x
  content$manifest_content_sha256 <- NULL
  if (!identical(canonical_phase_a_sha256(content), x$manifest_content_sha256))
    stop_phase_a("PHASE_A_1939_CONTENT_HASH_INVALID")

  invisible(x)
}

## -- eksekvering. Selv-autoriserer (authorize) i BÅDE dry-run og apply —
## fase-A skriver kun source_evidence (ingen person_create/canonical_delta),
## og selve prod-apply'et er ikke en del af dette program (Global Constraints);
## denne wrapper bygger og TESTER blot skrive-værktøjet.
execute_phase_a_1939 <- function(manifest, preview_sha256, mode = c("dry-run", "apply"), gateway) {
  mode <- match.arg(mode)
  validate_phase_a_manifest(manifest)
  if (!phase_a_hash(preview_sha256)) stop_phase_a("PHASE_A_1939_PREVIEW_HASH_INVALID")
  if (!is.list(gateway) || !is.function(gateway$call)) stop_phase_a("PHASE_A_1939_GATEWAY_INVALID")
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
    authorization_id <- call("authorize", manifest, preview_sha256)
    batch_id <- call("begin_batch", authorization_id, manifest, preview_sha256)
    payloads <- authorized_phase_a_payloads(manifest)
    for (op in manifest$operations) {
      call("source_evidence", batch_id, op$element_id, payloads[[op$element_id]])
    }
    final <- call("finalize", batch_id)
    if (!is.list(final) || !phase_a_scalar_string(final$status))
      stop_phase_a("PHASE_A_1939_FINALIZE_INVALID")
    if (identical(mode, "dry-run")) rollback_once() else call("commit")
    list(
      mode = mode, batch_id = batch_id, status = final$status,
      counts = final$counts, committed = identical(mode, "apply")
    )
  }, error = function(e) {
    rollback_once()
    stop(conditionMessage(e), call. = FALSE)
  })
}

new_phase_a_dbi_gateway <- function(connection_factory) {
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
      begin = {
        DBI::dbBegin(con)
        query("SELECT pg_advisory_xact_lock(hashtextextended('daa-1939-v50-phase-a-writer',0))")
        invisible(NULL)
      },
      authorize = {
        manifest <- args[[1L]]; preview <- args[[2L]]
        nonce <- query("SELECT gen_random_uuid() AS id")$id[[1L]]
        counts_json <- jsonlite::toJSON(manifest$counts, auto_unbox = TRUE)
        elements_json <- jsonlite::toJSON(authorized_phase_a_payloads(manifest), auto_unbox = TRUE, null = "null")
        query(
          "SELECT public.red_authorize_1939_v50_reimport($1,$2,current_database(),$3,$4::jsonb,$5::jsonb,$6,clock_timestamp()+interval '10 minutes') AS id",
          list(manifest$manifest_content_sha256, preview, manifest$source$database_source_id,
            counts_json, elements_json, nonce)
        )$id[[1L]]
      },
      begin_batch = {
        authorization_id <- args[[1L]]; manifest <- args[[2L]]; preview <- args[[3L]]
        query(
          "SELECT public.red_begin_1939_v50_reimport($1,$2,$3) AS id",
          list(authorization_id, manifest$manifest_content_sha256, preview)
        )$id[[1L]]
      },
      source_evidence = {
        execute(
          "SELECT public.red_apply_1939_v50_source_evidence($1,$2,$3::jsonb)",
          list(args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null"))
        )
        invisible(NULL)
      },
      finalize = jsonlite::fromJSON(
        query("SELECT public.red_finalize_1939_v50_reimport($1)::text AS value", list(args[[1L]]))$value[[1L]],
        simplifyVector = FALSE
      ),
      rollback = { DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      commit = { DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      stop_phase_a("PHASE_A_1939_GATEWAY_OPERATION_INVALID")
    )
  })
}
