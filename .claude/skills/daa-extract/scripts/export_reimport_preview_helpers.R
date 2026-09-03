# Fail-closed, forbindelsesfrie helpers til det læse-kun før-billede, der
# binder én source_evidence-apply. Filen har ingen sideeffekter og testes med
# injiceret query-funktion.

`%||%` <- function(value, fallback) if (is.null(value)) fallback else value

preview_stop <- function(code) stop(code, call. = FALSE)

preview_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[0-9a-f]{64}$", value)
}

preview_authorization_request <- function(manifest) {
  validate_reimport_manifest(manifest)
  if (!identical(manifest$expected_counts$person_creates, 0L) ||
      !identical(manifest$expected_counts$canonical_delta, 0L))
    preview_stop("PREVIEW_PERSON_CREATE_FORBIDDEN")
  list(
    expected_counts = reimport_writer_expected_counts(manifest),
    authorized_elements = reimport_authorized_payloads(manifest)
  )
}

preview_source_state <- function(query, manifest) {
  state <- query(paste(
    "SELECT jsonb_build_object('database_name',current_database(),",
    "'system_identifier',(pg_control_system()).system_identifier::text)::text",
    "AS database_identity, current_database() AS database_name,",
    "(pg_control_system()).system_identifier::text AS system_identifier,",
    "current_setting('transaction_read_only') AS transaction_read_only,",
    "public.narrative_record_contract_version() AS contract_version"))
  if (!identical(as.character(state$transaction_read_only[[1L]]), "on"))
    preview_stop("PREVIEW_TRANSACTION_NOT_READ_ONLY")
  if (!identical(as.integer(state$contract_version[[1L]]), 2L))
    preview_stop("PREVIEW_NARRATIVE_RECORD_CONTRACT_REQUIRED")
  profile <- query(paste(
    "SELECT count(*) AS n FROM private.reimport_writer_profile",
    "WHERE source_id=$1 AND profile_id=$2 AND profile_sha256=$3"),
    list(manifest$source$id, manifest$source$profile_id,
         manifest$source$profile_sha256))
  if (!identical(as.integer(profile$n[[1L]]), 1L))
    preview_stop("PREVIEW_WRITER_PROFILE_MISSING")
  state
}

preview_before_counts <- function(query, manifest) {
  counts <- query(paste(
    "SELECT (SELECT count(*) FROM private.source_rendition WHERE source_id=$1) AS renditions,",
    "(SELECT count(*) FROM private.source_record WHERE source_id=$1) AS records,",
    "(SELECT count(*) FROM private.source_record_occurrence o",
    " JOIN private.source_rendition r ON r.id=o.rendition_id WHERE r.source_id=$1) AS occurrences,",
    "(SELECT count(*) FROM private.source_record_anchor_event a",
    " JOIN private.source_record sr ON sr.id=a.source_record_id",
    " WHERE sr.source_id=$1 AND a.decision_status='accepted') AS anchors,",
    "(SELECT count(*) FROM private.extraction_run WHERE source_id=$1) AS runs"),
    list(manifest$source$id))
  list(
    source_rendition = as.integer(counts$renditions[[1L]]),
    source_record = as.integer(counts$records[[1L]]),
    source_record_occurrence = as.integer(counts$occurrences[[1L]]),
    source_record_anchor_accepted = as.integer(counts$anchors[[1L]]),
    extraction_run = as.integer(counts$runs[[1L]])
  )
}

preview_record_key_coverage <- function(query, manifest) {
  manifest_keys <- sort(vapply(manifest$operations, `[[`, "", "source_record_key"))
  rows <- query(
    "SELECT record_key FROM public.person_external_id WHERE source_id=$1 AND record_key IS NOT NULL",
    list(manifest$source$id))
  external_keys <- sort(unique(as.character(rows$record_key)))
  list(
    manifest_keys = length(manifest_keys),
    person_external_id_keys = length(external_keys),
    only_in_manifest = setdiff(manifest_keys, external_keys),
    only_in_person_external_id = setdiff(external_keys, manifest_keys)
  )
}

preview_canonical_baseline <- function(query) {
  aggregate <- function(sql) {
    row <- query(sprintf(paste(
      "SELECT coalesce(encode(sha256(convert_to(",
      "string_agg(row_text, chr(10) ORDER BY row_text),'UTF8')),'hex'),'empty') AS h",
      "FROM (%s) s"), sql))
    as.character(row$h[[1L]])
  }
  list(
    person = aggregate("SELECT p::text AS row_text FROM public.person p"),
    fact = aggregate("SELECT f::text AS row_text FROM public.fact f"),
    family_member = aggregate("SELECT m::text AS row_text FROM public.family_member m"),
    narrative = aggregate("SELECT n::text AS row_text FROM public.narrative n"),
    narrative_record_publication = aggregate(
      "SELECT b::text AS row_text FROM private.narrative_record_publication b")
  )
}

preview_legacy_before_counts <- function(query, manifest) {
  counts <- query(paste(
    "SELECT (SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.source_id=$1 AND l.status='grandfathered_publication') AS grandfathered,",
    "(SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.source_id=$1 AND l.status='migrated') AS migrated,",
    "(SELECT count(*) FROM private.narrative_legacy_publication l WHERE l.source_id=$1 AND l.status='withdrawn') AS withdrawn,",
    "(SELECT count(*) FROM private.narrative_record_publication b JOIN private.source_record r ON r.id=b.source_record_id WHERE r.source_id=$1 AND b.status='published') AS bound_published,",
    "(SELECT count(*) FROM private.narrative_record_publication b JOIN private.source_record r ON r.id=b.source_record_id WHERE r.source_id=$1 AND b.status='draft') AS bound_draft,",
    "(SELECT count(*) FROM private.source_persona p WHERE p.source_id=$1) AS personas,",
    "(SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id WHERE p.source_id=$1 AND i.decision_status='accepted') AS identities,",
    "(SELECT count(*) FROM public.narrative n WHERE n.source_id=$1 AND n.subjekt_type='person') AS narratives"),
    list(manifest$source$id))
  lapply(as.list(counts[1L, ]), as.integer)
}

preview_legacy_ledger_coverage <- function(query, manifest) {
  legacy_ops <- Filter(function(operation) identical(operation$dependency_class, "legacy_migration"),
                        manifest$operations)
  if (!length(legacy_ops)) return(invisible(NULL))
  narrative_ids <- vapply(legacy_ops, function(operation) as.integer(operation$narrative_id), integer(1))
  narrative_ids_literal <- paste0("{", paste(narrative_ids, collapse = ","), "}")
  rows <- query(paste(
    "SELECT narrative_id, legacy_publication_ref::text AS legacy_publication_ref,",
    "status, baseline_sha256 FROM private.narrative_legacy_publication",
    "WHERE narrative_id = ANY($1::bigint[])"), list(narrative_ids_literal))
  ledger <- new.env(parent = emptyenv())
  if (nrow(rows))
    for (index in seq_len(nrow(rows)))
      assign(as.character(rows$narrative_id[[index]]), list(
        legacy_publication_ref = rows$legacy_publication_ref[[index]],
        status = rows$status[[index]],
        baseline_sha256 = rows$baseline_sha256[[index]]), envir = ledger)
  for (operation in legacy_ops) {
    key <- as.character(operation$narrative_id)
    entry <- if (exists(key, envir = ledger, inherits = FALSE)) get(key, envir = ledger) else NULL
    if (identical(operation$disposition, "bound_published")) {
      if (is.null(entry) || !identical(entry$status, "grandfathered_publication") ||
          !identical(entry$legacy_publication_ref, operation$legacy_publication_ref) ||
          !identical(entry$baseline_sha256, operation$legacy_baseline_sha256))
        preview_stop("PREVIEW_LEGACY_LEDGER_INCONSISTENT")
    } else if (identical(operation$disposition, "bound_draft")) {
      if (!is.null(entry)) preview_stop("PREVIEW_LEGACY_LEDGER_INCONSISTENT")
    } else {
      preview_stop("PREVIEW_LEGACY_LEDGER_INCONSISTENT")
    }
  }
  invisible(NULL)
}

build_reimport_preview <- function(query, manifest, manifest_bytes_sha256) {
  request <- preview_authorization_request(manifest)
  if (!preview_hash(manifest_bytes_sha256))
    preview_stop("PREVIEW_MANIFEST_BYTES_HASH_INVALID")
  state <- preview_source_state(query, manifest)
  preview <- list(
    preview_schema_version = "reimport-source-evidence-preview-v1",
    database = list(
      database_identity = as.character(state$database_identity[[1L]]),
      database_name = as.character(state$database_name[[1L]]),
      system_identifier = as.character(state$system_identifier[[1L]]),
      narrative_record_contract_version = 2L),
    source = manifest$source,
    manifest = list(
      manifest_content_sha256 = manifest$manifest_content_sha256,
      manifest_bytes_sha256 = manifest_bytes_sha256),
    expected_counts = request$expected_counts,
    before_counts = preview_before_counts(query, manifest),
    record_key_coverage = preview_record_key_coverage(query, manifest),
    canonical_baseline_sha256 = preview_canonical_baseline(query),
    database_write_authorized = FALSE,
    production_authorized = FALSE
  )
  if (isTRUE(manifest$expected_counts$legacy_migrations > 0L)) {
    preview_legacy_ledger_coverage(query, manifest)
    preview$legacy_before_counts <- preview_legacy_before_counts(query, manifest)
  }
  preview
}
