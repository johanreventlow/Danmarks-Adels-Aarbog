name_completion_hash_re <- "^[0-9a-f]{64}$"
name_completion_source_batch_id <- "560c39f8-5c87-4c0d-a768-025d97fa2974"
name_completion_source_manifest_bytes_sha256 <- "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f"
name_completion_source_manifest_content_sha256 <- "8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03"

stop_name_completion <- function(code) stop(code, call. = FALSE)

legacy_name_completion_file <- sys.frame(1)$ofile
if (is.null(legacy_name_completion_file)) legacy_name_completion_file <- "apply_name_completion_1939_v50_helpers.R"
source(file.path(dirname(normalizePath(legacy_name_completion_file, mustWork = FALSE)), "apply_name_completion_helpers.R"))
execute_name_completion_generic <- execute_name_completion
new_name_completion_dbi_gateway_generic <- new_name_completion_dbi_gateway

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

name_completion_uuid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", value)
}

canonical_name_completion_value <- function(value) {
  if (!is.list(value)) return(value)
  value_names <- names(value)
  if (is.null(value_names)) return(lapply(value, canonical_name_completion_value))
  if (anyNA(value_names) || anyDuplicated(value_names))
    stop_name_completion("NAME_COMPLETION_1939_CANONICAL_INVALID")
  ordered_names <- sort(value_names, method = "radix")
  result <- lapply(ordered_names, function(name) canonical_name_completion_value(value[[name]]))
  names(result) <- ordered_names
  result
}

canonical_name_completion_sha256 <- function(value) {
  json <- jsonlite::toJSON(canonical_name_completion_value(value), auto_unbox = TRUE,
    null = "null", pretty = FALSE)
  digest::digest(enc2utf8(json), algo = "sha256", serialize = FALSE)
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
      !name_completion_hash(op$verbatim_sha256) ||
      !identical(digest::digest(op$verbatim_text, algo = "sha256", serialize = FALSE),
        op$verbatim_sha256) || !name_completion_hash(op$source_payload_sha256))
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
  content <- x
  content$manifest_content_sha256 <- NULL
  if (!identical(canonical_name_completion_sha256(content), x$manifest_content_sha256))
    stop_name_completion("NAME_COMPLETION_1939_CONTENT_HASH_INVALID")
  invisible(x)
}

legacy_name_completion_profile <- function(manifest) {
  list(id = as.integer(manifest$source$source_id),
    profile_id = "daa-1939-v50-production-write-v1",
    profile_sha256 = paste(rep("a", 64L), collapse = ""))
}

as_generic_name_completion_manifest <- function(manifest) {
  validate_name_completion_manifest(manifest)
  list(manifest_content_sha256 = manifest$manifest_content_sha256,
    source = legacy_name_completion_profile(manifest),
    source_batch_id = manifest$source_batch_id,
    source_manifest_bytes_sha256 = manifest$source_manifest_bytes_sha256,
    source_manifest_content_sha256 = manifest$source_manifest_content_sha256,
    expected_counts = manifest$counts,
    operations = manifest$operations)
}

authorized_name_payloads <- function(manifest) {
  name_completion_payloads(as_generic_name_completion_manifest(manifest))
}

execute_name_completion <- function(manifest, manifest_sha256,
                                    mode = c("dry-run", "apply"), gateway,
                                    authorization = NULL) {
  mode <- match.arg(mode)
  validate_name_completion_manifest(manifest)
  if (!name_completion_hash(manifest_sha256))
    stop_name_completion("NAME_COMPLETION_1939_MANIFEST_HASH_INVALID")
  if (identical(mode, "apply") && is.null(authorization))
    stop_name_completion("NAME_COMPLETION_1939_AUTHORIZATION_REQUIRED")
  execute_name_completion_generic(as_generic_name_completion_manifest(manifest), manifest_sha256,
    mode, gateway, authorization)
}

new_name_completion_dbi_gateway <- new_name_completion_dbi_gateway_generic
