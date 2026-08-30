#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg)) {
  normalizePath(sub("^--file=", "", script_arg[[1L]]))
} else {
  normalizePath(file.path(
    getwd(), "..", "..", ".claude", "skills", "daa-extract", "scripts",
    "verify_narrative_record_cutover_postverify.R"
  ))
}
script_dir <- dirname(script_path)
source(file.path(script_dir, "apply_narrative_record_cutover_helpers.R"))
source(file.path(script_dir, "export_narrative_record_cutover_helpers.R"))

.nrk_postverify_fail <- function(token) stop(token, call. = FALSE)

nrk_postverify_direct_readers <- function() {
  classified <- .nrk_classified_readers()
  repository <- normalizePath(file.path(script_dir, "../../../.."), mustWork = TRUE)
  files <- unlist(lapply(c("web/src", "mobile/src"), function(directory) {
    list.files(file.path(repository, directory), pattern = "\\.(ts|tsx)$", recursive = TRUE,
      full.names = TRUE)
  }), use.names = FALSE)
  files <- files[!grepl("/(__tests__|test)/|\\.(test|spec)\\.(ts|tsx)$", files)]
  text <- lapply(files, readLines, warn = FALSE, encoding = "UTF-8")
  direct <- sub(paste0("^", repository, "/"), "", files[vapply(text, function(lines) {
    any(grepl(
      "\\.from\\(['\"]narrative['\"]\\)|public_person_bio_source_versions(_v2)?|red_person_narrative_records",
      lines
    ))
  }, logical(1))])
  expected <- vapply(classified, `[[`, "", "path")
  if (!identical(sort(direct, method = "radix"), sort(expected, method = "radix"))) {
    .nrk_postverify_fail("POSTVERIFY_DIRECT_READER_CHECKOUT_MISMATCH")
  }
  classified
}

nrk_postverify_required_acl <- function() {
  authenticated <- c(
    "public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)" = TRUE,
    "public.red_publicer_person_narrative_record(bigint,bigint,text,text)" = TRUE,
    "public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)" = TRUE,
    "public.red_revalider_person_narrative_record(bigint,bigint,text,text)" = TRUE,
    "public.red_kasser_person_narrative_record(bigint,bigint,text,text)" = TRUE,
    "public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)" = TRUE,
    "public.red_tilbagetraek_legacy_narrative(uuid,text,text)" = TRUE,
    "public.red_fortryd_person_narrative_publication_event(uuid,text)" = TRUE,
    "public.red_publicer_narrative_record(bigint,uuid,text,text)" = FALSE,
    "public.red_tilbagetraek_narrative_record(bigint)" = FALSE,
    "public.red_begin_1939_v50_reimport(uuid,text,text)" = FALSE,
    "public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)" = FALSE,
    "public.red_apply_1939_v50_person_create(uuid,text,jsonb)" = FALSE,
    "public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)" = FALSE,
    "public.red_finalize_1939_v50_reimport(uuid)" = FALSE,
    "public.red_reverse_1939_v50_reimport(uuid,uuid)" = FALSE,
    "public.red_activate_1939_v50_batch(uuid,uuid)" = FALSE,
    "public.red_apply_reimport_cases(uuid,text,text)" = FALSE,
    "public.red_reverse_reimport_cases(uuid,uuid)" = FALSE
  )
  service <- c(
    "public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)" = FALSE,
    "public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)" = FALSE,
    "public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)" = FALSE,
    "public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)" = FALSE,
    "public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)" = FALSE
  )
  signatures <- c(authenticated, service)
  roles <- c("PUBLIC", "anon", "authenticated", "service_role")
  expected <- unlist(lapply(names(signatures), function(signature) {
    values <- setNames(rep(FALSE, length(roles)), paste(signature, roles, sep = "|"))
    values[[paste(signature, "authenticated", sep = "|")]] <-
      if (signature %in% names(authenticated)) authenticated[[signature]] else FALSE
    values
  }), use.names = TRUE)
  expected
}

nrk_postverify_acl_observed <- function(rows, expected) {
  required <- c("signature", "routine_oid", "owner_oid", "role", "grantee_oid", "privilege_type")
  if (!is.data.frame(rows) || !setequal(names(rows), required)) {
    .nrk_postverify_fail("POSTVERIFY_ACL_OBSERVATION_INVALID")
  }
  signatures <- unique(sub("\\|.*$", "", names(expected)))
  observed_signatures <- unique(as.character(rows$signature))
  if (!identical(sort(observed_signatures, method = "radix"),
                 sort(signatures, method = "radix"))) {
    .nrk_postverify_fail("POSTVERIFY_ACL_SIGNATURE_MISSING")
  }
  for (signature in signatures) {
    oids <- unique(as.character(rows$routine_oid[rows$signature == signature]))
    if (length(oids) != 1L || is.na(oids) || !nzchar(oids)) {
      .nrk_postverify_fail("POSTVERIFY_ACL_SIGNATURE_MISSING")
    }
  }
  observed <- setNames(rep(FALSE, length(expected)), names(expected))
  execute <- rows[!is.na(rows$privilege_type) & rows$privilege_type == "EXECUTE", , drop = FALSE]
  if (nrow(execute)) {
    execute <- execute[as.character(execute$grantee_oid) != as.character(execute$owner_oid), , drop = FALSE]
    keys <- paste(execute$signature, execute$role, sep = "|")
    if (any(!keys %in% names(observed))) {
      .nrk_postverify_fail("POSTVERIFY_ACL_UNEXPECTED_GRANT")
    }
    if (any(!expected[keys])) {
      .nrk_postverify_fail("POSTVERIFY_ACL_UNEXPECTED_GRANT")
    }
    observed[unique(keys)] <- TRUE
  }
  observed
}

.nrk_postverify_set <- function(value) {
  flatten <- function(item) {
    if (is.list(item)) return(unlist(lapply(item, flatten), recursive = TRUE, use.names = FALSE))
    as.character(item)
  }
  sort(unique(as.character(flatten(value))), method = "radix")
}

.nrk_postverify_equal_set <- function(observed, expected, token) {
  if (!identical(.nrk_postverify_set(observed), .nrk_postverify_set(expected))) {
    .nrk_postverify_fail(token)
  }
}

.nrk_postverify_equal_scalar <- function(observed, expected, token) {
  if (!identical(as.character(observed), as.character(expected))) {
    .nrk_postverify_fail(token)
  }
}

.nrk_postverify_rows <- function(rows) {
  if (!is.list(rows)) .nrk_postverify_fail("POSTVERIFY_ROW_SHAPE_INVALID")
  lapply(rows, function(row) {
    if (!is.list(row)) .nrk_postverify_fail("POSTVERIFY_ROW_SHAPE_INVALID")
    row[] <- lapply(row, function(value) {
      if (is.list(value)) return(.nrk_postverify_rows(list(value))[[1L]])
      if (is.null(value)) return(NULL)
      if (length(value) == 1L && is.na(value)) return(NULL)
      as.character(value)
    })
    row
  })
}

.nrk_postverify_equal_rows <- function(observed, expected, token) {
  order_rows <- function(rows) {
    if (length(rows) && all(vapply(rows, function(row) "event_id" %in% names(row), logical(1)))) {
      rows <- rows[order(vapply(rows, function(row) as.character(row$event_id), ""), method = "radix")]
    }
    rows
  }
  observed <- order_rows(observed)
  expected <- order_rows(expected)
  observed <- .nrk_postverify_rows(observed)
  expected <- .nrk_postverify_rows(expected)
  if (!identical(
    jsonlite::toJSON(observed, auto_unbox = TRUE, null = "null", digits = NA),
    jsonlite::toJSON(expected, auto_unbox = TRUE, null = "null", digits = NA)
  )) .nrk_postverify_fail(token)
}

.nrk_postverify_receipt_event_rows <- function(result, record_manifest, legacy_manifest) {
  record_by_binding <- setNames(record_manifest, vapply(record_manifest, `[[`, "", "binding_id"))
  legacy_by_id <- setNames(legacy_manifest, vapply(legacy_manifest, function(row) {
    as.character(row$narrative_id)
  }, ""))
  records <- lapply(result$record_events, function(event) {
    manifest <- record_by_binding[[event$binding_id]]
    if (is.null(manifest)) .nrk_postverify_fail("POSTVERIFY_RECORD_EVENT_SET_MISMATCH")
    list(event_id = event$event_id, stream_ref = event$binding_id,
      stream_version = "1", event_type = "baseline", binding_id = event$binding_id,
      narrative_id = as.character(event$narrative_id), source_id = as.character(manifest$source_id),
      source_record_id = manifest$source_record_id, legacy_publication_ref = NULL,
      after_state_sha256 = event$publication_state_sha256,
      state_sha256 = event$state_sha256)
  })
  legacy <- lapply(result$legacy_events, function(event) {
    manifest <- legacy_by_id[[as.character(event$narrative_id)]]
    if (is.null(manifest)) .nrk_postverify_fail("POSTVERIFY_LEGACY_EVENT_SET_MISMATCH")
    list(event_id = event$event_id, stream_ref = event$legacy_publication_ref,
      stream_version = "1", event_type = "baseline", binding_id = NULL,
      narrative_id = as.character(event$narrative_id), source_id = as.character(manifest$source_id),
      source_record_id = NULL, legacy_publication_ref = event$legacy_publication_ref,
      after_state_sha256 = event$publication_state_sha256,
      state_sha256 = event$state_sha256)
  })
  c(records, legacy)
}

nrk_postverify_order_v2_rows <- function(events, legacy_keep_ids) {
  wrapped <- lapply(events, function(event) {
    state <- event$after_state
    if (!is.list(state)) .nrk_postverify_fail("POSTVERIFY_EVENT_STATE_SHAPE_MISMATCH")
    if (!is.null(event$binding_id) && !is.na(event$binding_id)) return(list(
      row = list(
        person_id = state$target$person_id, source_id = state$target$source_id,
        source_year = state$source$source_year, record_order = state$labels$record_order,
        source_record_ref = state$target$source_record_ref,
        source_label = state$source$source_label, record_label = state$labels$record_label,
        narrative_text = state$narrative$text, citation_label = state$labels$citation_label,
        provenance_kind = "source_record"
      ), kind = 0L, stable_tiebreak = state$target$source_record_ref
    ))
    if (as.character(event$narrative_id) %in% as.character(legacy_keep_ids)) return(list(
      row = list(
        person_id = state$target$person_id, source_id = state$target$source_id,
        source_year = state$source$source_year, record_order = NULL,
        source_record_ref = NULL, source_label = state$source$source_label,
        record_label = "Overgangsdata", narrative_text = state$narrative$text,
        citation_label = paste0(state$source$source_label, if (is.null(state$narrative$side) ||
          !nzchar(state$narrative$side)) "" else paste0(", s. ", state$narrative$side)),
        provenance_kind = "legacy_narrative"
      ), kind = 1L, stable_tiebreak = event$legacy_publication_ref
    ))
    NULL
  })
  wrapped <- wrapped[!vapply(wrapped, is.null, logical(1))]
  if (!length(wrapped)) return(list())
  years <- vapply(wrapped, function(item) {
    value <- item$row$source_year
    if (is.null(value) || (length(value) == 1L && is.na(value))) return(NA_integer_)
    converted <- suppressWarnings(as.integer(value))
    if (length(converted) != 1L || is.na(converted)) {
      .nrk_postverify_fail("POSTVERIFY_EVENT_STATE_SHAPE_MISMATCH")
    }
    converted
  }, integer(1))
  source_ids <- bit64::as.integer64(vapply(wrapped, function(item) {
    as.character(item$row$source_id)
  }, ""))
  kinds <- vapply(wrapped, `[[`, integer(1), "kind")
  record_orders <- vapply(wrapped, function(item) {
    if (is.null(item$row$record_order)) NA_integer_ else as.integer(item$row$record_order)
  }, integer(1))
  record_labels <- vapply(wrapped, function(item) as.character(item$row$record_label), "")
  record_refs <- vapply(wrapped, function(item) {
    if (is.null(item$row$source_record_ref)) "" else as.character(item$row$source_record_ref)
  }, "")
  stable_tiebreaks <- vapply(wrapped, function(item) as.character(item$stable_tiebreak), "")
  ordered <- order(is.na(years), -years, source_ids, kinds, is.na(record_orders), record_orders,
                   record_labels, record_refs, stable_tiebreaks, method = "radix")
  lapply(wrapped[ordered], `[[`, "row")
}

nrk_postverify_public_person_ids <- function(record_manifest, legacy_candidates) {
  ids <- c(
    vapply(record_manifest, function(row) as.character(row$person_id), ""),
    vapply(legacy_candidates, function(row) as.character(row$person_id), "")
  )
  if (!length(ids)) return(character())
  if (any(!grepl("^[0-9]+$", ids))) {
    .nrk_postverify_fail("POSTVERIFY_PERSON_ID_INVALID")
  }
  ids <- unique(ids)
  numeric_ids <- bit64::as.integer64(ids)
  if (anyNA(numeric_ids)) .nrk_postverify_fail("POSTVERIFY_PERSON_ID_INVALID")
  ids[order(numeric_ids, method = "radix")]
}

nrk_verify_narrative_record_cutover_postverify <- function(
  artifacts, nonce, expected_database, gateway
) {
  verified <- nrk_verify_cutover_artifacts(artifacts)
  documents <- verified$documents
  record_manifest <- documents$record_manifest$rows
  legacy_manifest <- documents$legacy_manifest$rows
  approval <- documents$approval
  snapshot <- gateway$snapshot(
    nonce, verified$hashes, expected_database, record_manifest, legacy_manifest,
    documents$legacy$rows
  )
  if (!identical(verified$database, expected_database) ||
      !identical(snapshot$identity, expected_database)) {
    .nrk_postverify_fail("POSTVERIFY_DATABASE_IDENTITY_MISMATCH")
  }
  if (!identical(as.integer(snapshot$version), 2L)) {
    .nrk_postverify_fail("POSTVERIFY_CONTRACT_VERSION_INVALID")
  }
  receipts <- snapshot$receipts
  if (length(receipts) != 1L || !identical(as.integer(snapshot$nonce_receipt_count), 1L)) {
    .nrk_postverify_fail("POSTVERIFY_RECEIPT_MISMATCH")
  }
  receipt <- .nrk_validate_receipt(receipts[[1L]], nonce, verified$hashes, expected_database)
  result <- receipt$result
  if (!identical(as.integer(result$contract_version_after), 2L)) {
    .nrk_postverify_fail("POSTVERIFY_RECEIPT_VERSION_MISMATCH")
  }
  expected_binding_ids <- vapply(record_manifest, `[[`, "", "binding_id")
  expected_legacy_narrative_ids <- vapply(legacy_manifest, function(row) {
    as.character(row$narrative_id)
  }, "")
  source_record_ids <- vapply(record_manifest, `[[`, "", "source_record_id")
  expected_public_record_refs <- snapshot$source_record_public_refs
  if (length(expected_public_record_refs) != length(source_record_ids) ||
      anyNA(expected_public_record_refs) || any(!nzchar(expected_public_record_refs))) {
    .nrk_postverify_fail("POSTVERIFY_SOURCE_RECORD_PUBLIC_REF_MISMATCH")
  }
  expected_hidden_ids <- approval$legacy_hide_ids
  .nrk_postverify_equal_set(
    vapply(result$record_events, `[[`, "", "binding_id"), expected_binding_ids,
    "POSTVERIFY_RECORD_EVENT_SET_MISMATCH"
  )
  .nrk_postverify_equal_set(
    vapply(result$legacy_events, function(row) as.character(row$narrative_id), ""),
    expected_legacy_narrative_ids,
    "POSTVERIFY_LEGACY_EVENT_SET_MISMATCH"
  )
  .nrk_postverify_equal_set(result$legacy_hidden_ids, expected_hidden_ids,
                             "POSTVERIFY_HIDDEN_LEGACY_SET_MISMATCH")
  observed <- snapshot$observed
  receipt_events <- .nrk_postverify_receipt_event_rows(
    result, record_manifest, legacy_manifest
  )
  observed_receipt_event_rows <- lapply(observed$receipt_event_rows, function(row) {
    row[names(receipt_events[[1L]])]
  })
  .nrk_postverify_equal_rows(
    observed_receipt_event_rows, receipt_events,
    "POSTVERIFY_RECEIPT_EVENT_ROW_MISMATCH"
  )
  if (any(!vapply(observed$receipt_event_rows, function(row) {
    legacy_event <- is.null(row$binding_id) || is.na(row$binding_id)
    identical(as.character(row$before_state_sha256), as.character(row$after_state_sha256)) &&
      identical(row$before_state, row$after_state) &&
      identical(row$decision_basis, paste("Godkendt", if (legacy_event) "grandfathered baseline" else "baseline", "ved contract cutover", nonce)) &&
      identical(row$decided_by_name, "Narrative record cutover")
  }, logical(1)))) .nrk_postverify_fail("POSTVERIFY_EVENT_BASELINE_INVARIANT_MISMATCH")
  if (length(observed$change_set_rows) != 1L ||
      !identical(as.character(observed$change_set_rows[[1L]]$id),
                 as.character(result$change_set_id)) ||
      !identical(observed$change_set_rows[[1L]]$operation,
                 "narrative_record_contract_cutover") ||
      !identical(observed$change_set_rows[[1L]]$actor_navn,
                 "Narrative record cutover") ||
      !identical(observed$change_set_rows[[1L]]$actor_rolle, "system") ||
      !identical(observed$change_set_rows[[1L]]$subjekt_synlighed, "offentlig") ||
      !identical(observed$change_set_rows[[1L]]$summary,
                 paste("Narrative record contract cutover", nonce))) {
    .nrk_postverify_fail("POSTVERIFY_CHANGE_SET_ROW_MISMATCH")
  }
  if (length(observed$change_event_rows) != 0L) {
    .nrk_postverify_fail("POSTVERIFY_CHANGE_SET_SCOPE_MISMATCH")
  }
  .nrk_postverify_equal_set(observed$record_binding_ids, expected_binding_ids,
                             "POSTVERIFY_RECORD_BINDING_SET_MISMATCH")
  .nrk_postverify_equal_set(observed$legacy_narrative_ids, expected_legacy_narrative_ids,
                             "POSTVERIFY_LEGACY_SET_MISMATCH")
  if (length(observed$hidden_legacy_ids)) {
    .nrk_postverify_fail("POSTVERIFY_HIDDEN_LEGACY_PRESENT")
  }
  .nrk_postverify_equal_set(snapshot$public_v2_refs,
                             expected_public_record_refs,
                             "POSTVERIFY_PUBLIC_RECORD_REF_SET_MISMATCH")
  expected_public_v2_rows <- nrk_postverify_order_v2_rows(
    observed$receipt_event_rows, approval$legacy_keep_ids
  )
  .nrk_postverify_equal_rows(
    observed$public_v2_rows, expected_public_v2_rows,
    "POSTVERIFY_PUBLIC_V2_ROW_MISMATCH"
  )
  .nrk_postverify_equal_set(observed$public_legacy_narrative_ids,
                             expected_legacy_narrative_ids,
                             "POSTVERIFY_PUBLIC_LEGACY_SET_MISMATCH")
  .nrk_postverify_equal_scalar(observed$baseline_event_count,
                                length(expected_binding_ids) + length(expected_legacy_narrative_ids),
                                "POSTVERIFY_BASELINE_EVENT_COUNT_MISMATCH")
  .nrk_postverify_equal_scalar(observed$change_set_id, result$change_set_id,
                                "POSTVERIFY_CHANGE_SET_MISMATCH")
  inventory <- documents$inventory
  .nrk_postverify_equal_scalar(observed$bindings, length(inventory$record_candidate_ids),
                                "POSTVERIFY_BINDING_COUNT_MISMATCH")
  .nrk_postverify_equal_scalar(observed$grandfathered_legacy,
                                length(approval$legacy_keep_ids),
                                "POSTVERIFY_GRANDFATHERED_LEGACY_COUNT_MISMATCH")
  .nrk_postverify_equal_scalar(observed$accepted_identities,
                                inventory$accepted_identity_count,
                                "POSTVERIFY_ACCEPTED_IDENTITY_COUNT_MISMATCH")
  .nrk_postverify_equal_scalar(observed$blocked_new_records,
                                inventory$identity_blocked_record_count,
                                "POSTVERIFY_BLOCKED_RECORD_COUNT_MISMATCH")
  if (!identical(observed$direct_readers, inventory$classified_direct_readers) ||
      !identical(observed$direct_readers, nrk_postverify_direct_readers())) {
    .nrk_postverify_fail("POSTVERIFY_DIRECT_READER_CLASSIFICATION_MISMATCH")
  }
  if (!identical(observed$acl, nrk_postverify_required_acl())) {
    .nrk_postverify_fail("POSTVERIFY_ACL_INVENTORY_MISMATCH")
  }
  list(status = "postverify_passed", receipt = receipt, observed = observed)
}

nrk_postverify_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  flags <- c("--record-candidates", "--legacy-candidates", "--record-manifest",
             "--legacy-manifest", "--inventory", "--approval", "--nonce",
             "--expected-database-name", "--expected-system-identifier")
  if (length(args) != length(flags) * 2L ||
      !identical(args[seq(1L, length(args), by = 2L)], flags)) {
    stop(paste("USAGE: verify_narrative_record_cutover_postverify.R",
               paste(flags, "VALUE", collapse = " ")), call. = FALSE)
  }
  values <- as.list(args[seq(2L, length(args), by = 2L)])
  names(values) <- sub("^--", "", flags)
  root <- normalizePath(file.path(script_dir, "../../../.."))
  paths <- nrk_validate_artifact_paths(c(
    values$`record-candidates`, values$`legacy-candidates`, values$`record-manifest`,
    values$`legacy-manifest`, values$inventory, values$approval
  ), root)
  raw <- lapply(paths, function(path) readBin(path, "raw", n = file.info(path)$size))
  names(raw) <- c("record", "legacy", "record_manifest", "legacy_manifest", "inventory", "approval")
  profile <- Sys.getenv(c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD"), unset = NA_character_)
  names(profile) <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
  profile <- nrk_validate_cutover_pg_profile(profile)
  connection <- DBI::dbConnect(RPostgres::Postgres(), dbname = profile$PGDATABASE,
    host = profile$PGHOST, port = as.integer(profile$PGPORT), user = profile$PGUSER,
    password = profile$PGPASSWORD)
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  base_gateway <- nrk_db_cutover_gateway(connection)
  gateway <- list(snapshot = function(nonce, hashes, database, record_manifest, legacy_manifest, legacy_candidates) {
    DBI::dbWithTransaction(connection, {
      DBI::dbExecute(connection, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
      DBI::dbGetQuery(connection, paste(
        "SELECT pg_advisory_xact_lock_shared(",
        "hashtextextended('daa-narrative-record-contract',0))"
      ))
      identity <- base_gateway$identity()
      version <- base_gateway$version()
      receipts <- base_gateway$exact_receipts(nonce, hashes, database)
      receipt_count <- base_gateway$nonce_receipt_count(nonce)
      if (length(receipts) != 1L) .nrk_postverify_fail("POSTVERIFY_RECEIPT_MISMATCH")
      result <- receipts[[1L]]$result
      change_set_id <- as.character(result$change_set_id)
      event_ids <- vapply(c(result$record_events, result$legacy_events), `[[`, "", "event_id")
      events <- DBI::dbGetQuery(connection, paste0(
        "SELECT id::text AS event_id,change_set_id::text,stream_ref::text,stream_version::text,event_type,",
        "binding_id::text,narrative_id::text,source_id::text,source_record_id::text,",
        "legacy_publication_ref::text,decision_basis,decided_by_name,before_state_sha256,after_state_sha256,",
        "before_state::text,after_state::text FROM private.narrative_publication_event ",
        "WHERE change_set_id=$1::bigint ORDER BY id::text"
      ), params = list(change_set_id))
      event_state_rows <- DBI::dbGetQuery(connection, paste0(
        "SELECT event.id::text AS event_id,CASE WHEN event.binding_id IS NOT NULL THEN ",
        "private.narrative_record_state(narrative.subjekt_id,narrative.source_id,record.record_key,false)->>'state_sha256' ",
        "ELSE private.narrative_legacy_state(event.legacy_publication_ref,false)->>'state_sha256' END AS state_sha256 ",
        "FROM private.narrative_publication_event event JOIN public.narrative narrative ",
        "ON narrative.id=event.narrative_id LEFT JOIN private.source_record record ",
        "ON record.id=event.source_record_id WHERE event.id IN (",
        paste(sprintf("'%s'::uuid", event_ids), collapse = ","), ")"
      ))
      event_state_by_id <- setNames(event_state_rows$state_sha256, event_state_rows$event_id)
      event_rows <- lapply(seq_len(nrow(events)), function(index) list(
        event_id = events$event_id[[index]], change_set_id = events$change_set_id[[index]],
        stream_ref = events$stream_ref[[index]],
        stream_version = events$stream_version[[index]], event_type = events$event_type[[index]],
        binding_id = events$binding_id[[index]], narrative_id = events$narrative_id[[index]],
        source_id = events$source_id[[index]], source_record_id = events$source_record_id[[index]],
        legacy_publication_ref = events$legacy_publication_ref[[index]],
        decision_basis = events$decision_basis[[index]], decided_by_name = events$decided_by_name[[index]],
        before_state_sha256 = events$before_state_sha256[[index]], after_state_sha256 = events$after_state_sha256[[index]],
        state_sha256 = event_state_by_id[[events$event_id[[index]]]],
        before_state = jsonlite::fromJSON(events$before_state[[index]], simplifyVector = FALSE,
          bigint_as_char = TRUE),
        after_state = jsonlite::fromJSON(events$after_state[[index]], simplifyVector = FALSE,
          bigint_as_char = TRUE)
      ))
      change_set <- DBI::dbGetQuery(connection, paste(
        "SELECT id::text,actor_navn,actor_rolle,operation,summary,subjekt_synlighed",
        "FROM public.change_set WHERE id=$1::bigint"), params = list(change_set_id))
      change_events <- DBI::dbGetQuery(connection,
        "SELECT id::text FROM public.change_event WHERE change_set_id=$1::bigint", params = list(change_set_id))
      source_ids <- vapply(record_manifest, `[[`, "", "source_record_id")
      refs <- DBI::dbGetQuery(connection, paste0(
        "SELECT id::text,public_ref::text FROM private.source_record WHERE id IN (",
        paste(sprintf("'%s'::uuid", source_ids), collapse = ","), ")"
      ))
      source_refs <- unname(setNames(refs$public_ref, refs$id)[source_ids])
      person_ids <- nrk_postverify_public_person_ids(record_manifest, legacy_candidates)
      public_rows <- DBI::dbGetQuery(connection, paste0(
        "SELECT person_id::text,source_id::text,source_year::text,record_order::text,",
        "source_record_ref::text,source_label,record_label,narrative_text,citation_label,provenance_kind ",
        "FROM public.public_person_bio_source_versions_v2(ARRAY[",
        paste(person_ids, collapse = ","), "]::bigint[])"
      ))
      v2_rows <- lapply(seq_len(nrow(public_rows)), function(index) as.list(public_rows[index, , drop = FALSE]))
      legacy <- DBI::dbGetQuery(connection, "SELECT narrative_id::text FROM private.narrative_legacy_publication WHERE status='grandfathered_publication' ORDER BY narrative_id")
      identity_counts <- DBI::dbGetQuery(connection, .nrk_export_sql$identity_counts)
      hidden_ids <- vapply(result$legacy_hidden_ids, as.character, "")
      hidden_present <- if (!length(hidden_ids)) character() else DBI::dbGetQuery(connection, paste0(
        "SELECT narrative_id::text FROM private.narrative_legacy_publication WHERE narrative_id IN (",
        paste(hidden_ids, collapse = ","), ")"
      ))$narrative_id
      acl_expected <- nrk_postverify_required_acl()
      acl_signatures <- unique(vapply(
        strsplit(names(acl_expected), "|", fixed = TRUE), `[[`, "", 1L
      ))
      acl_values <- paste(sprintf("('%s')", gsub("'", "''", acl_signatures, fixed = TRUE)),
                          collapse = ",")
      acl_rows <- DBI::dbGetQuery(connection, paste0(
        "WITH expected(signature) AS (VALUES ", acl_values, "), routines AS (",
        "SELECT expected.signature,routine.oid AS routine_oid,routine.proowner,routine.proacl ",
        "FROM expected LEFT JOIN pg_catalog.pg_proc routine ",
        "ON routine.oid=to_regprocedure(expected.signature)) ",
        "SELECT routines.signature,routines.routine_oid::text AS routine_oid,",
        "routines.proowner::text AS owner_oid,coalesce(grantee.rolname,'PUBLIC') AS role,",
        "privilege.grantee::text AS grantee_oid,privilege.privilege_type ",
        "FROM routines LEFT JOIN LATERAL aclexplode(CASE WHEN routines.routine_oid IS NULL ",
        "THEN ARRAY[]::aclitem[] ELSE coalesce(routines.proacl,acldefault('f',routines.proowner)) END) ",
        "privilege ON true LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid=privilege.grantee"
      ))
      acl_observed <- nrk_postverify_acl_observed(acl_rows, acl_expected)
      list(identity = identity, version = version, receipts = receipts,
        nonce_receipt_count = receipt_count, source_record_public_refs = source_refs,
        public_v2_refs = as.list(stats::na.omit(public_rows$source_record_ref)),
        observed = list(receipt_event_rows = event_rows,
          change_set_rows = lapply(seq_len(nrow(change_set)), function(i) as.list(change_set[i, , drop = FALSE])),
          change_event_rows = lapply(seq_len(nrow(change_events)), function(i) as.list(change_events[i, , drop = FALSE])),
          record_binding_ids = lapply(event_rows[vapply(event_rows, function(row) {
            !is.null(row$binding_id) && !is.na(row$binding_id)
          }, logical(1))], `[[`, "binding_id"),
          legacy_narrative_ids = as.list(legacy$narrative_id), hidden_legacy_ids = as.list(hidden_present),
          public_v2_rows = v2_rows,
          public_legacy_narrative_ids = as.list(legacy$narrative_id),
          baseline_event_count = nrow(events), change_set_id = change_set_id,
          bindings = DBI::dbGetQuery(connection, "SELECT count(*)::integer AS n FROM private.narrative_record_publication")$n[[1L]],
          grandfathered_legacy = nrow(legacy),
          accepted_identities = identity_counts$accepted_identity_count[[1L]],
          blocked_new_records = identity_counts$identity_blocked_record_count[[1L]],
          direct_readers = nrk_postverify_direct_readers(), acl = acl_observed)
      )
    })
  })
  result <- nrk_verify_narrative_record_cutover_postverify(
    raw, values$nonce, list(database_name = values$`expected-database-name`,
      system_identifier = values$`expected-system-identifier`), gateway)
  writeLines(jsonlite::toJSON(result[c("status", "receipt")], auto_unbox = TRUE, pretty = TRUE))
}

if (sys.nframe() == 0L) nrk_postverify_main()
