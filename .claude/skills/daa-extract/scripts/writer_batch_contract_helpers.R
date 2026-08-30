## Editionsneutral helpers for the closed writer/batch contract.
## They perform no database I/O and accept no narrative payloads.

.wb_stop <- function(code) stop(code, call. = FALSE)

.wb_scalar_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

.wb_hex_sha256 <- function(value) {
  .wb_scalar_string(value) && grepl("^[0-9a-f]{64}$", value)
}

.wb_canonicalize <- function(value, key = NULL) {
  if (inherits(value, "AsIs")) {
    attribute_names <- names(attributes(value))
    if (!identical(class(value), "AsIs") ||
        any(!(attribute_names %in% c("class", "names"))))
      .wb_stop("WRITER_BATCH_CANONICAL_VALUE_INVALID")
    attr(value, "class") <- NULL
    return(.wb_canonicalize(value, key))
  }
  if (is.list(value)) {
    value_names <- names(value)
    if (!is.null(value_names)) {
      if (anyNA(value_names) || any(!nzchar(value_names)) || anyDuplicated(value_names))
        .wb_stop("WRITER_BATCH_CANONICAL_KEYS_INVALID")
      order_index <- order(value_names, method = "radix")
      value <- value[order_index]
      value_names <- names(value)
      for (index in seq_along(value)) {
        value[[index]] <- .wb_canonicalize(value[[index]], value_names[[index]])
      }
      return(value)
    }
    return(lapply(value, .wb_canonicalize))
  }
  if (is.object(value) || is.raw(value) || is.complex(value) ||
      !(is.atomic(value) || is.null(value)))
    .wb_stop("WRITER_BATCH_CANONICAL_VALUE_INVALID")
  if (is.null(value)) return(value)
  if (!is.null(names(value))) {
    if (anyNA(names(value)) || any(!nzchar(names(value))) || anyDuplicated(names(value)))
      .wb_stop("WRITER_BATCH_CANONICAL_KEYS_INVALID")
    return(.wb_canonicalize(as.list(value)))
  }
  if (anyNA(value) || (is.numeric(value) && any(!is.finite(value))))
    .wb_stop("WRITER_BATCH_CANONICAL_VALUE_INVALID")
  if (identical(key, "element_ids") || identical(key, "terminal_statuses")) {
    if (!is.character(value)) .wb_stop("WRITER_BATCH_CANONICAL_VALUE_INVALID")
    value <- sort(value, method = "radix")
  }
  if (identical(key, "element_ids") || identical(key, "terminal_statuses") ||
      identical(key, "lock_order") || length(value) > 1L)
    return(I(value))
  value
}

wb_canonical_json <- function(value) {
  jsonlite::toJSON(
    .wb_canonicalize(value),
    auto_unbox = TRUE,
    null = "null",
    pretty = FALSE,
    digits = NA
  )
}

wb_sha256 <- function(value) {
  digest::digest(wb_canonical_json(value), algo = "sha256", serialize = FALSE)
}

.wb_validate_hashes <- function(value) {
  if (!is.list(value)) return(invisible(NULL))
  value_names <- names(value)
  if (!is.null(value_names)) {
    for (index in seq_along(value)) {
      if (grepl("sha256$", value_names[[index]]) &&
          !.wb_hex_sha256(value[[index]]))
        .wb_stop("WRITER_BATCH_HASH_INVALID")
      .wb_validate_hashes(value[[index]])
    }
  } else {
    lapply(value, .wb_validate_hashes)
  }
  invisible(NULL)
}

.wb_nonempty_named_list <- function(value) {
  is.list(value) && length(value) > 0L && !is.null(names(value)) &&
    all(!is.na(names(value)) & nzchar(names(value))) && !anyDuplicated(names(value))
}

.wb_string_set <- function(value) {
  is.character(value) && length(value) > 0L && !anyNA(value) &&
    is.null(names(value)) && all(nzchar(value)) && !anyDuplicated(value)
}

.wb_count_tree <- function(value) {
  if (is.list(value)) {
    return(.wb_nonempty_named_list(value) &&
           all(vapply(value, .wb_count_tree, logical(1))))
  }
  is.numeric(value) && !is.object(value) && length(value) == 1L &&
    !is.na(value) && is.finite(value) && value >= 0 && value == floor(value)
}

.wb_invariant_tree <- function(value) {
  if (is.list(value)) {
    return(.wb_nonempty_named_list(value) &&
           all(vapply(value, .wb_invariant_tree, logical(1))))
  }
  if (is.object(value) || length(value) != 1L || is.na(value)) return(FALSE)
  (is.logical(value)) || (is.character(value) && nzchar(value)) ||
    (is.numeric(value) && is.finite(value))
}

.wb_exact_named_list <- function(value, keys) {
  is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) &&
    length(value) == length(keys) && setequal(names(value), keys)
}

.wb_nonempty_value <- function(value) {
  if (is.null(value) || length(value) == 0L) return(FALSE)
  if (is.list(value)) return(all(vapply(value, .wb_nonempty_value, logical(1))))
  if (is.character(value)) return(!anyNA(value) && all(nzchar(value)))
  !anyNA(value)
}

wb_validate_profile <- function(profile) {
  required_keys <- c(
    "operation_family", "contract_version", "execution_kind", "reversal_mode",
    "authorization_mode", "input_identity", "database_identity",
    "schema_contract_version", "scope", "element_ids", "expected_counts",
    "adapter_invariants", "lock_order", "receipt_schema", "terminal_statuses",
    "postverify_schema"
  )
  if (!is.list(profile) || is.null(names(profile)) || anyDuplicated(names(profile)) ||
      !setequal(names(profile), required_keys) || length(profile) != length(required_keys))
    .wb_stop("WRITER_BATCH_PROFILE_KEYS_INVALID")
  if (!.wb_scalar_string(profile$operation_family))
    .wb_stop("WRITER_BATCH_OPERATION_FAMILY_INVALID")
  if (!.wb_scalar_string(profile$contract_version))
    .wb_stop("WRITER_BATCH_CONTRACT_VERSION_INVALID")
  if (!(.wb_scalar_string(profile$execution_kind) && profile$execution_kind %in% c(
    "apply", "reversal", "promotion", "cutover", "recover", "conformance_read_only"
  ))) .wb_stop("WRITER_BATCH_EXECUTION_KIND_INVALID")
  if (!(.wb_scalar_string(profile$reversal_mode) && profile$reversal_mode %in% c(
    "exact_restore", "compensating", "not_supported"
  ))) .wb_stop("WRITER_BATCH_REVERSAL_MODE_INVALID")
  if (!(.wb_scalar_string(profile$authorization_mode) && profile$authorization_mode %in% c(
    "single_use_database_authorization", "actor_bound_preview_authorization",
    "external_go_nonce_authorization", "none"
  )) || (identical(profile$authorization_mode, "none") &&
          !identical(profile$execution_kind, "conformance_read_only")))
    .wb_stop("WRITER_BATCH_AUTHORIZATION_MODE_INVALID")
  if (!.wb_nonempty_named_list(profile$input_identity) ||
      !.wb_scalar_string(profile$input_identity$schema_version))
    .wb_stop("WRITER_BATCH_INPUT_IDENTITY_INVALID")
  .wb_validate_hashes(profile)
  if (!.wb_hex_sha256(profile$input_identity$canonical_json_sha256))
    .wb_stop("WRITER_BATCH_HASH_INVALID")
  if (!.wb_nonempty_named_list(profile$database_identity) ||
      !.wb_scalar_string(profile$database_identity$database_name) ||
      !.wb_scalar_string(profile$database_identity$system_identifier))
    .wb_stop("WRITER_BATCH_DATABASE_IDENTITY_INVALID")
  if (!.wb_scalar_string(profile$schema_contract_version))
    .wb_stop("WRITER_BATCH_SCHEMA_CONTRACT_VERSION_INVALID")
  if (!.wb_nonempty_named_list(profile$scope) || !.wb_nonempty_value(profile$scope))
    .wb_stop("WRITER_BATCH_SCOPE_INVALID")
  if (!.wb_string_set(profile$element_ids))
    .wb_stop("WRITER_BATCH_ELEMENT_IDS_INVALID")
  if (!.wb_count_tree(profile$expected_counts))
    .wb_stop("WRITER_BATCH_EXPECTED_COUNTS_INVALID")
  if (!.wb_invariant_tree(profile$adapter_invariants))
    .wb_stop("WRITER_BATCH_ADAPTER_INVARIANTS_INVALID")
  if (!.wb_string_set(profile$lock_order))
    .wb_stop("WRITER_BATCH_LOCK_ORDER_INVALID")
  if (!.wb_scalar_string(profile$receipt_schema))
    .wb_stop("WRITER_BATCH_RECEIPT_SCHEMA_INVALID")
  if (!.wb_string_set(profile$terminal_statuses))
    .wb_stop("WRITER_BATCH_TERMINAL_STATUSES_INVALID")
  if (!.wb_scalar_string(profile$postverify_schema))
    .wb_stop("WRITER_BATCH_POSTVERIFY_SCHEMA_INVALID")
  compatible <- switch(profile$execution_kind,
    apply = identical(profile$reversal_mode, "compensating") &&
      identical(profile$authorization_mode, "single_use_database_authorization"),
    reversal = identical(profile$reversal_mode, "exact_restore") &&
      !identical(profile$authorization_mode, "none"),
    promotion = identical(profile$reversal_mode, "not_supported") &&
      identical(profile$authorization_mode, "single_use_database_authorization"),
    cutover = identical(profile$reversal_mode, "not_supported") &&
      identical(profile$authorization_mode, "external_go_nonce_authorization"),
    recover = identical(profile$reversal_mode, "not_supported") &&
      identical(profile$authorization_mode, "external_go_nonce_authorization"),
    conformance_read_only = identical(profile$reversal_mode, "exact_restore") &&
      identical(profile$authorization_mode, "none")
  )
  if (!isTRUE(compatible)) .wb_stop("WRITER_BATCH_PROFILE_COMPATIBILITY_INVALID")
  .wb_canonicalize(profile)
}

wb_validate_receipt <- function(receipt, profile, mode) {
  validated_profile <- wb_validate_profile(profile)
  required_keys <- c(
    "receipt_schema", "profile", "profile_sha256", "mode", "terminal_status",
    "input_identity", "database_identity", "authorization_identity", "operation_id",
    "observed_counts", "verified_state"
  )
  if (!is.list(receipt) || is.null(names(receipt)) || anyDuplicated(names(receipt)) ||
      !setequal(names(receipt), required_keys) || length(receipt) != length(required_keys))
    .wb_stop("WRITER_BATCH_RECEIPT_KEYS_INVALID")
  if (!identical(mode, "historical") || !identical(receipt$mode, mode))
    .wb_stop("WRITER_BATCH_RECEIPT_MODE_INVALID")
  if (!.wb_scalar_string(receipt$receipt_schema) ||
      !identical(receipt$receipt_schema, validated_profile$receipt_schema))
    .wb_stop("WRITER_BATCH_RECEIPT_SCHEMA_INVALID")
  if (!identical(wb_canonical_json(receipt$profile),
                 wb_canonical_json(validated_profile)))
    .wb_stop("WRITER_BATCH_RECEIPT_PROFILE_DRIFT")
  if (!.wb_hex_sha256(receipt$profile_sha256) ||
      !identical(receipt$profile_sha256, wb_sha256(validated_profile)))
    .wb_stop("WRITER_BATCH_RECEIPT_PROFILE_DRIFT")
  if (!.wb_scalar_string(receipt$terminal_status) ||
      !(receipt$terminal_status %in% validated_profile$terminal_statuses))
    .wb_stop("WRITER_BATCH_RECEIPT_TERMINAL_STATUS_INVALID")
  if (!identical(wb_canonical_json(receipt$input_identity),
                 wb_canonical_json(validated_profile$input_identity)) ||
      !identical(wb_canonical_json(receipt$database_identity),
                 wb_canonical_json(validated_profile$database_identity)))
    .wb_stop("WRITER_BATCH_RECEIPT_IDENTITY_DRIFT")
  if (!.wb_exact_named_list(receipt$authorization_identity,
                            c("mode", "authority_id", "actor_id")) ||
      !.wb_scalar_string(receipt$authorization_identity$mode) ||
      !.wb_scalar_string(receipt$authorization_identity$authority_id) ||
      !.wb_scalar_string(receipt$authorization_identity$actor_id) ||
      !identical(receipt$authorization_identity$mode,
                 validated_profile$authorization_mode))
    .wb_stop("WRITER_BATCH_RECEIPT_AUTHORIZATION_INVALID")
  if (!.wb_scalar_string(receipt$operation_id))
    .wb_stop("WRITER_BATCH_RECEIPT_OPERATION_ID_INVALID")
  if (!.wb_count_tree(receipt$observed_counts) ||
      !identical(wb_canonical_json(receipt$observed_counts),
                 wb_canonical_json(validated_profile$expected_counts)))
    .wb_stop("WRITER_BATCH_RECEIPT_COUNTS_INVALID")
  if (!.wb_exact_named_list(receipt$verified_state, c("schema", "sha256")) ||
      !.wb_scalar_string(receipt$verified_state$schema) ||
      !identical(receipt$verified_state$schema, validated_profile$postverify_schema) ||
      !.wb_hex_sha256(receipt$verified_state$sha256))
    .wb_stop("WRITER_BATCH_RECEIPT_POSTVERIFY_INVALID")
  .wb_canonicalize(receipt)
}

## Validates the trusted current-state projection supplied by an adapter's
## database query. This pure helper has no database access and cannot establish
## provenance itself; it therefore requires independent persisted receipt,
## profile, input, database, and operation bindings in `state`.
wb_validate_current_state <- function(state, receipt) {
  if (!is.list(receipt) || is.null(receipt$profile))
    .wb_stop("WRITER_BATCH_RECEIPT_KEYS_INVALID")
  validated_receipt <- wb_validate_receipt(receipt, receipt$profile, "historical")
  required_keys <- c(
    "receipt_sha256", "profile_sha256", "input_identity", "database_identity",
    "operation_id", "verified_state"
  )
  if (!.wb_exact_named_list(state, required_keys) ||
      !.wb_hex_sha256(state$receipt_sha256) ||
      !.wb_hex_sha256(state$profile_sha256) ||
      !is.list(state$input_identity) || !is.list(state$database_identity) ||
      !.wb_scalar_string(state$operation_id))
    .wb_stop("WRITER_BATCH_CURRENT_STATE_BINDINGS_INVALID")
  if (!identical(state$receipt_sha256, wb_sha256(validated_receipt)) ||
      !identical(state$profile_sha256, validated_receipt$profile_sha256) ||
      !identical(wb_canonical_json(state$input_identity),
                 wb_canonical_json(validated_receipt$input_identity)) ||
      !identical(wb_canonical_json(state$database_identity),
                 wb_canonical_json(validated_receipt$database_identity)) ||
      !identical(state$operation_id, validated_receipt$operation_id))
    .wb_stop("WRITER_BATCH_CURRENT_STATE_RECEIPT_DRIFT")
  if (!.wb_exact_named_list(state$verified_state, c("schema", "sha256")) ||
      !.wb_scalar_string(state$verified_state$schema) ||
      !.wb_hex_sha256(state$verified_state$sha256))
    .wb_stop("WRITER_BATCH_CURRENT_STATE_INVALID")
  if (!identical(state$verified_state$schema, validated_receipt$verified_state$schema) ||
      !identical(state$verified_state$sha256, validated_receipt$verified_state$sha256))
    .wb_stop("WRITER_BATCH_CURRENT_STATE_DRIFT")
  .wb_canonicalize(state)
}
