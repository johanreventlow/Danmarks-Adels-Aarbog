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

nrk_postverify_direct_readers <- function() .nrk_classified_readers()

nrk_postverify_required_acl <- function() {
  required <- c(
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
  required
}

.nrk_postverify_set <- function(value) sort(unique(as.character(unlist(value, use.names = FALSE))))

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

nrk_verify_narrative_record_cutover_postverify <- function(
  artifacts, nonce, expected_database, gateway
) {
  verified <- nrk_verify_cutover_artifacts(artifacts)
  if (!identical(verified$database, expected_database) ||
      !identical(gateway$identity(), expected_database)) {
    .nrk_postverify_fail("POSTVERIFY_DATABASE_IDENTITY_MISMATCH")
  }
  if (!identical(as.integer(gateway$version()), 2L)) {
    .nrk_postverify_fail("POSTVERIFY_CONTRACT_VERSION_INVALID")
  }
  receipts <- gateway$exact_receipts(nonce, verified$hashes, expected_database)
  if (length(receipts) != 1L || !identical(as.integer(gateway$nonce_receipt_count(nonce)), 1L)) {
    .nrk_postverify_fail("POSTVERIFY_RECEIPT_MISMATCH")
  }
  receipt <- .nrk_validate_receipt(receipts[[1L]], nonce, verified$hashes, expected_database)
  result <- receipt$result
  if (!identical(as.integer(result$contract_version_after), 2L)) {
    .nrk_postverify_fail("POSTVERIFY_RECEIPT_VERSION_MISMATCH")
  }
  documents <- verified$documents
  record_manifest <- documents$record_manifest$rows
  legacy_manifest <- documents$legacy_manifest$rows
  approval <- documents$approval
  expected_binding_ids <- vapply(record_manifest, `[[`, "", "binding_id")
  expected_legacy_narrative_ids <- vapply(legacy_manifest, `[[`, 0L, "narrative_id")
  source_record_ids <- vapply(record_manifest, `[[`, "", "source_record_id")
  expected_public_record_refs <- gateway$source_record_public_refs(source_record_ids)
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
    vapply(result$legacy_events, `[[`, 0L, "narrative_id"), expected_legacy_narrative_ids,
    "POSTVERIFY_LEGACY_EVENT_SET_MISMATCH"
  )
  .nrk_postverify_equal_set(result$legacy_hidden_ids, expected_hidden_ids,
                             "POSTVERIFY_HIDDEN_LEGACY_SET_MISMATCH")
  observed <- gateway$observed(nonce, verified$hashes, expected_database)
  .nrk_postverify_equal_set(observed$record_binding_ids, expected_binding_ids,
                             "POSTVERIFY_RECORD_BINDING_SET_MISMATCH")
  .nrk_postverify_equal_set(observed$legacy_narrative_ids, expected_legacy_narrative_ids,
                             "POSTVERIFY_LEGACY_SET_MISMATCH")
  .nrk_postverify_equal_set(observed$hidden_legacy_ids, expected_hidden_ids,
                             "POSTVERIFY_HIDDEN_LEGACY_SET_MISMATCH")
  .nrk_postverify_equal_set(gateway$public_v2_refs(record_manifest),
                             expected_public_record_refs,
                             "POSTVERIFY_PUBLIC_RECORD_REF_SET_MISMATCH")
  .nrk_postverify_equal_set(observed$public_legacy_narrative_ids,
                             expected_legacy_narrative_ids,
                             "POSTVERIFY_PUBLIC_LEGACY_SET_MISMATCH")
  .nrk_postverify_equal_scalar(observed$baseline_event_count,
                                length(expected_binding_ids) + length(expected_legacy_narrative_ids),
                                "POSTVERIFY_BASELINE_EVENT_COUNT_MISMATCH")
  .nrk_postverify_equal_scalar(observed$change_set_id, result$change_set_id,
                                "POSTVERIFY_CHANGE_SET_MISMATCH")
  .nrk_postverify_equal_scalar(observed$change_set_event_count,
                                length(expected_binding_ids) + length(expected_legacy_narrative_ids),
                                "POSTVERIFY_CHANGE_SET_SCOPE_MISMATCH")
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
  gateway <- nrk_db_cutover_gateway(connection)
  gateway$source_record_public_refs <- function(ids) {
    if (any(!grepl(.nrk_cutover_uuid, ids))) .nrk_postverify_fail("POSTVERIFY_SOURCE_RECORD_ID_INVALID")
    rows <- DBI::dbGetQuery(connection, paste0(
      "SELECT id::text,public_ref::text FROM private.source_record WHERE id IN (",
      paste(sprintf("'%s'::uuid", ids), collapse = ","), ")"
    ))
    refs <- setNames(rows$public_ref, rows$id)
    unname(refs[ids])
  }
  gateway$public_v2_refs <- function(rows) {
    person_ids <- sort(unique(vapply(rows, `[[`, 0L, "person_id")))
    result <- DBI::dbGetQuery(connection, paste0(
      "SELECT source_record_ref::text FROM public.public_person_bio_source_versions_v2(ARRAY[",
      paste(as.integer(person_ids), collapse = ","), "]) WHERE source_record_ref IS NOT NULL"
    ))
    as.list(result$source_record_ref)
  }
  gateway$observed <- function(nonce, hashes, database) {
    receipt <- DBI::dbGetQuery(connection, .nrk_apply_sql$exact_receipt,
      params = c(list(nonce), unname(hashes), unname(database)))
    if (nrow(receipt) != 1L) .nrk_postverify_fail("POSTVERIFY_RECEIPT_MISMATCH")
    result <- jsonlite::fromJSON(receipt$result_raw[[1L]], simplifyVector = FALSE)
    change_set_id <- result$change_set_id
    events <- DBI::dbGetQuery(connection, paste(
      "SELECT binding_id::text, narrative_id::text, legacy_publication_ref::text",
      "FROM private.narrative_publication_event WHERE change_set_id=$1::bigint",
      "AND event_type='baseline' ORDER BY narrative_id"), params = list(change_set_id))
    legacy <- DBI::dbGetQuery(connection, "SELECT narrative_id::text FROM private.narrative_legacy_publication WHERE status='grandfathered_publication' ORDER BY narrative_id")
    list(record_binding_ids = as.list(stats::na.omit(events$binding_id)),
      legacy_narrative_ids = as.list(legacy$narrative_id),
      hidden_legacy_ids = result$legacy_hidden_ids,
      baseline_event_count = nrow(events), change_set_id = change_set_id,
      change_set_event_count = nrow(events),
      public_record_narrative_ids = as.list(stats::na.omit(events$narrative_id[!is.na(events$binding_id)])),
      public_legacy_narrative_ids = as.list(stats::na.omit(events$narrative_id[is.na(events$binding_id)])),
      bindings = DBI::dbGetQuery(connection, "SELECT count(*)::integer AS n FROM private.narrative_record_publication")$n[[1L]],
      grandfathered_legacy = nrow(legacy),
      accepted_identities = jsonlite::fromJSON(rawToChar(raw$inventory), simplifyVector = FALSE)$accepted_identity_count,
      blocked_new_records = jsonlite::fromJSON(rawToChar(raw$inventory), simplifyVector = FALSE)$identity_blocked_record_count,
      direct_readers = nrk_postverify_direct_readers(), acl = nrk_postverify_required_acl())
  }
  result <- nrk_verify_narrative_record_cutover_postverify(
    raw, values$nonce, list(database_name = values$`expected-database-name`,
      system_identifier = values$`expected-system-identifier`), gateway)
  writeLines(jsonlite::toJSON(result[c("status", "receipt")], auto_unbox = TRUE, pretty = TRUE))
}

if (sys.nframe() == 0L) nrk_postverify_main()
