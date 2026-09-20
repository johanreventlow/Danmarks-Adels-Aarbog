## Pure validation and receipt binding for #153's source-scoped replace adapter.
## Database provenance is intentionally established only by the gateway's RPC queries.

.ssr_helper_path <- sys.frame(1)$ofile
if (is.null(.ssr_helper_path)) .ssr_helper_path <- "apply_source_scoped_replace_helpers.R"
source(file.path(dirname(normalizePath(.ssr_helper_path)), "writer_batch_contract_helpers.R"))

.ssr_stop <- function(code) stop(code, call. = FALSE)
.ssr_hex <- function(value) is.character(value) && length(value) == 1L && !is.na(value) &&
  grepl("^[0-9a-f]{64}$", value)
.ssr_exact <- function(value, keys, code) {
  if (!is.list(value) || is.null(names(value)) || anyDuplicated(names(value)) ||
      length(value) != length(keys) || !setequal(names(value), keys)) .ssr_stop(code)
  value
}

ssr_validate_manifest <- function(manifest) {
  .ssr_exact(manifest, c("schema", "source_id", "record_keys", "input_sha256", "dry_run_sha256",
    "ownership_sha256", "expected_counts", "policy_decisions", "narrative_operations", "source_operations"),
    "SOURCE_SCOPED_REPLACE_MANIFEST_SCHEMA_INVALID")
  if (!identical(manifest$schema, "source-scoped-replace-v1") ||
      !is.numeric(manifest$source_id) || length(manifest$source_id) != 1L || is.na(manifest$source_id) ||
      manifest$source_id <= 0 || !is.character(manifest$record_keys) || !inherits(manifest$record_keys, "AsIs") ||
      anyNA(manifest$record_keys) || any(!nzchar(manifest$record_keys)) || anyDuplicated(manifest$record_keys) ||
      !identical(as.character(manifest$record_keys), sort(as.character(manifest$record_keys), method = "radix")) ||
      !all(vapply(manifest[c("input_sha256", "dry_run_sha256", "ownership_sha256")], .ssr_hex, logical(1))))
    .ssr_stop("SOURCE_SCOPED_REPLACE_MANIFEST_INVALID")
  .ssr_exact(manifest$expected_counts, c("narrative_operations", "source_operations"),
             "SOURCE_SCOPED_REPLACE_MANIFEST_COUNTS_INVALID")
  if (any(!vapply(manifest$expected_counts, function(x) is.numeric(x) && length(x) == 1L &&
                   !is.na(x) && x >= 0 && x == floor(x), logical(1))))
    .ssr_stop("SOURCE_SCOPED_REPLACE_MANIFEST_COUNTS_INVALID")
  .ssr_exact(manifest$policy_decisions, c("new_records", "discontinued_records"),
             "SOURCE_SCOPED_REPLACE_MANIFEST_POLICY_INVALID")
  if (!is.list(manifest$narrative_operations) || !is.list(manifest$source_operations))
    .ssr_stop("SOURCE_SCOPED_REPLACE_MANIFEST_ARRAY_INVALID")
  for (op in manifest$narrative_operations) {
    .ssr_exact(op, c("element_id", "person_id", "source_id", "record_key", "text", "text_sha256", "expected_state_sha256"),
               "SOURCE_SCOPED_REPLACE_MANIFEST_NARRATIVE_INVALID")
    if (!identical(as.numeric(op$source_id), as.numeric(manifest$source_id)) ||
        !is.character(op$text) || length(op$text) != 1L || is.na(op$text) || !nzchar(op$text) ||
        !.ssr_hex(op$text_sha256) || !identical(digest::digest(op$text, algo = "sha256", serialize = FALSE), op$text_sha256) ||
        !.ssr_hex(op$expected_state_sha256)) .ssr_stop("SOURCE_SCOPED_REPLACE_MANIFEST_NARRATIVE_INVALID")
  }
  if (length(manifest$narrative_operations) != manifest$expected_counts$narrative_operations ||
      length(manifest$source_operations) != manifest$expected_counts$source_operations)
    .ssr_stop("SOURCE_SCOPED_REPLACE_MANIFEST_COUNTS_INVALID")
  manifest
}

ssr_profile <- function(manifest, database_identity) {
  manifest <- ssr_validate_manifest(manifest)
  .ssr_exact(database_identity, c("database_name", "system_identifier"),
             "SOURCE_SCOPED_REPLACE_DATABASE_IDENTITY_INVALID")
  element_ids <- vapply(manifest$narrative_operations, function(op) as.character(op$element_id), character(1))
  wb_validate_profile(list(
    operation_family = "source_scoped_replace", contract_version = "source-scoped-replace-v1",
    execution_kind = "apply", reversal_mode = "compensating",
    authorization_mode = "single_use_database_authorization",
    input_identity = list(schema_version = "source-scoped-replace-v1", canonical_json_sha256 = manifest$input_sha256,
      dry_run_sha256 = manifest$dry_run_sha256, ownership_sha256 = manifest$ownership_sha256),
    database_identity = database_identity, schema_contract_version = "narrative-record-v2",
    scope = list(source_id = as.character(manifest$source_id), record_keys_sha256 = digest::digest(paste(manifest$record_keys, collapse = "\n"), algo = "sha256", serialize = FALSE)),
    element_ids = I(sort(element_ids, method = "radix")), expected_counts = manifest$expected_counts,
    adapter_invariants = list(draft_events_only = TRUE, no_model_table_append = TRUE, source_scope_locked = TRUE),
    lock_order = I(c("narrative_contract", "source_scope", "people", "source_records", "narratives_bindings", "adapter_ledger")),
    receipt_schema = "source-scoped-replace-receipt-v1", terminal_statuses = I("committed"),
    postverify_schema = "source-scoped-replace-current-state-v1"
  ))
}

ssr_validate_terminal_receipt <- function(receipt, profile) {
  wb_validate_receipt(receipt, profile, "historical")
}
