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

legacy_script_file <- sys.frame(1)$ofile
if (is.null(legacy_script_file)) legacy_script_file <- "apply_reimport_1939_v50_helpers.R"
source(file.path(dirname(normalizePath(legacy_script_file, mustWork = FALSE)), "apply_reimport_helpers.R"))
execute_reimport_generic <- execute_reimport
new_dbi_writer_gateway <- new_reimport_dbi_gateway

legacy_reimport_profile <- function(manifest) {
  profile_config <- list(
    citation_label_template = "DAA 1939 side {page_from}",
    extractor_version = "production-writer-v1",
    observation_extraction_method = "human_reviewed_1939_v50",
    rendition_key = "daa-1939-calamari-r6-clean",
    rendition_kind = "ocr_text",
    rendition_metadata = list(edition = "1939"),
    run_key_prefix = "reimport-1939-v50:",
    schema_version = "1939-v50-production-write-manifest-v1"
  )
  list(id = as.integer(manifest$source$database_source_id),
    profile_id = "daa-1939-v50-production-write-v1",
    profile_sha256 = digest::digest(charToRaw(jsonlite::toJSON(
      profile_config, auto_unbox = TRUE, null = "null")),
      algo = "sha256", serialize = FALSE))
}

as_generic_reimport_manifest <- function(manifest) {
  validate_production_manifest(manifest)
  operations <- lapply(manifest$operations, function(operation) {
    operation$rendition_content_sha256 <- manifest$source$rendition_content_sha256
    operation
  })
  list(manifest_content_sha256 = manifest$manifest_content_sha256,
    source = legacy_reimport_profile(manifest),
    expected_counts = list(source_evidence = 305L, person_creates = 8L, canonical_delta = 0L),
    operations = operations)
}

execute_reimport <- function(manifest, preview_sha256, mode=c("dry-run","apply"), gateway,
                             authorization=NULL) {
  mode <- match.arg(mode)
  validate_production_manifest(manifest)
  if (!is.character(preview_sha256) || length(preview_sha256)!=1L || !grepl(hash_re,preview_sha256))
    stop_writer("REIMPORT_1939_PREVIEW_HASH_INVALID")
  if (mode=="apply" && (is.null(authorization) || !is.list(authorization) || is.null(authorization$id)))
    stop_writer("REIMPORT_1939_AUTHORIZATION_REQUIRED")
  execute_reimport_generic(as_generic_reimport_manifest(manifest), preview_sha256, mode,
    gateway, authorization)
}
