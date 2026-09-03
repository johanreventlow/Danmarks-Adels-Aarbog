`%||%` <- function(left, right) if (is.null(left)) right else left

.nrk_cutover_uuid <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
.nrk_cutover_sha <- "^[0-9a-f]{64}$"
.nrk_receipt_name <- "narrative-record-cutover-receipt-v1.json"

.nrk_apply_sql <- list(
  identity = paste(
    "SELECT current_database()::text AS database_name,",
    "(pg_control_system()).system_identifier::text AS system_identifier"
  ),
  version = "SELECT public.narrative_record_contract_version()::integer AS version",
  kernel = paste(
    "SELECT private.apply_narrative_record_cutover(",
    "$1,$2,$3,$4,$5,$6,$7::uuid,$8,$9) AS result"
  ),
  snapshot = paste(
    "SELECT jsonb_build_object(",
    "'version',public.narrative_record_contract_version(),",
    "'contract',(SELECT to_jsonb(contract) FROM private.narrative_record_contract contract),",
    "'binding_count',(SELECT count(*) FROM private.narrative_record_publication),",
    "'binding_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(binding::text,E'\\n'",
    "ORDER BY binding.id::text),''),'sha256'),'hex')",
    "FROM private.narrative_record_publication binding),",
    "'event_count',(SELECT count(*) FROM private.narrative_publication_event),",
    "'event_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(event::text,E'\\n'",
    "ORDER BY event.id::text),''),'sha256'),'hex') FROM private.narrative_publication_event event),",
    "'legacy_count',(SELECT count(*) FROM private.narrative_legacy_publication),",
    "'legacy_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(legacy::text,E'\\n'",
    "ORDER BY legacy.legacy_publication_ref::text),''),'sha256'),'hex')",
    "FROM private.narrative_legacy_publication legacy),",
    "'receipt_count',(SELECT count(*) FROM private.narrative_record_cutover_receipt),",
    "'receipt_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(receipt::text,E'\\n'",
    "ORDER BY receipt.nonce::text),''),'sha256'),'hex')",
    "FROM private.narrative_record_cutover_receipt receipt),",
    "'change_set_count',(SELECT count(*) FROM public.change_set),",
    "'change_set_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(change_set::text,E'\\n'",
    "ORDER BY change_set.id),''),'sha256'),'hex') FROM public.change_set change_set),",
    "'change_event_count',(SELECT count(*) FROM public.change_event),",
    "'change_event_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(change_event::text,E'\\n'",
    "ORDER BY change_event.id),''),'sha256'),'hex') FROM public.change_event change_event),",
    "'narrative_sequence',(SELECT jsonb_build_object('last_value',last_value,'is_called',is_called)",
    "FROM public.narrative_id_seq),",
    "'change_set_sequence',(SELECT jsonb_build_object('last_value',last_value,'is_called',is_called)",
    "FROM public.change_set_id_seq),",
    "'function_acl_sha256',(SELECT encode(extensions.digest(coalesce(string_agg(",
    "format('%s.%s(%s)|%s',namespace.nspname,routine.proname,",
    "pg_get_function_identity_arguments(routine.oid),coalesce(routine.proacl::text,'<NULL>')),",
    "E'\\n' ORDER BY namespace.nspname,routine.proname,",
    "pg_get_function_identity_arguments(routine.oid)),''),'sha256'),'hex')",
    "FROM pg_catalog.pg_proc routine JOIN pg_catalog.pg_namespace namespace",
    "ON namespace.oid=routine.pronamespace",
    "WHERE namespace.nspname IN ('public','private'))) AS snapshot"
  ),
  exact_receipt = paste(
    "SELECT nonce::text, jsonb_build_object(",
    "'record_candidates_sha256',record_candidates_sha256,",
    "'legacy_candidates_sha256',legacy_candidates_sha256,",
    "'record_manifest_sha256',record_manifest_sha256,",
    "'legacy_manifest_sha256',legacy_manifest_sha256,",
    "'inventory_sha256',inventory_sha256,'approval_sha256',approval_sha256",
    ") AS input_hashes, jsonb_build_object('database_name',database_name,",
    "'system_identifier',system_identifier) AS database,result::text AS result_raw,",
    "result_sha256,committed_at",
    "FROM private.narrative_record_cutover_receipt WHERE nonce=$1::uuid",
    "AND record_candidates_sha256=$2 AND legacy_candidates_sha256=$3",
    "AND record_manifest_sha256=$4 AND legacy_manifest_sha256=$5",
    "AND inventory_sha256=$6 AND approval_sha256=$7",
    "AND database_name=$8 AND system_identifier=$9",
    "AND result_sha256=encode(extensions.digest(result::text,'sha256'),'hex')",
    "AND result->>'nonce'=($1::uuid)::text",
    "AND result->'database'=jsonb_build_object(",
    "'database_name',$8::text,'system_identifier',$9::text)",
    "AND result->'input_hashes'=jsonb_build_object(",
    "'record_candidates_sha256',$2::text,'legacy_candidates_sha256',$3::text,",
    "'record_manifest_sha256',$4::text,'legacy_manifest_sha256',$5::text,",
    "'inventory_sha256',$6::text,'approval_sha256',$7::text)"
  ),
  nonce_receipt_count = paste(
    "SELECT count(*)::integer AS receipt_count",
    "FROM private.narrative_record_cutover_receipt WHERE nonce=$1::uuid"
  )
)

.nrk_cutover_fail <- function(token) stop(token, call. = FALSE)

.nrk_cutover_sha_raw <- function(raw) {
  digest::digest(raw, algo = "sha256", serialize = FALSE)
}

.nrk_cutover_parse <- function(raw, token) {
  if (!is.raw(raw)) .nrk_cutover_fail(token)
  tryCatch(
    jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE, bigint_as_char = TRUE),
    error = function(error) .nrk_cutover_fail(token)
  )
}

.nrk_cutover_bigint <- function(value) {
  valid_character <- is.character(value) && length(value) == 1L &&
    grepl("^-?(0|[1-9][0-9]*)$", value)
  if (length(value) != 1L || anyNA(value) ||
      !(is.integer(value) || inherits(value, "integer64") || valid_character)) {
    .nrk_cutover_fail("CUTOVER_DB_RESULT_BIGINT_INVALID")
  }
  converted <- bit64::as.integer64(value)
  if (is.na(converted)) .nrk_cutover_fail("CUTOVER_DB_RESULT_BIGINT_INVALID")
  converted
}

.nrk_parse_cutover_result_json <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
  }
  result <- tryCatch(
    jsonlite::fromJSON(value, simplifyVector = FALSE, bigint_as_char = TRUE),
    error = function(error) .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
  )
  if (!is.list(result) || is.null(names(result))) {
    .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
  }
  for (name in intersect(
    c("contract_version_before", "contract_version_after", "change_set_id"),
    names(result)
  )) result[[name]] <- .nrk_cutover_bigint(result[[name]])
  if (!is.null(result$sequence)) {
    if (!is.list(result$sequence)) .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
    for (name in intersect(c("before", "floor", "after"), names(result$sequence))) {
      result$sequence[[name]] <- .nrk_cutover_bigint(result$sequence[[name]])
    }
  }
  if (!is.null(result$legacy_hidden_ids)) {
    if (!is.list(result$legacy_hidden_ids)) {
      .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
    }
    result$legacy_hidden_ids <- lapply(result$legacy_hidden_ids, .nrk_cutover_bigint)
  }
  for (collection in c("record_events", "legacy_events")) {
    if (is.null(result[[collection]])) next
    if (!is.list(result[[collection]])) .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
    result[[collection]] <- lapply(result[[collection]], function(event) {
      if (!is.list(event)) .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
      if ("narrative_id" %in% names(event)) {
        event$narrative_id <- .nrk_cutover_bigint(event$narrative_id)
      }
      if ("event_id" %in% names(event) &&
          (!is.character(event$event_id) || length(event$event_id) != 1L ||
           !grepl(.nrk_cutover_uuid, event$event_id))) {
        .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
      }
      event
    })
  }
  result
}

.nrk_cutover_database <- function(document) {
  database <- document$database
  if (!is.list(database) || !setequal(names(database), c("database_name", "system_identifier")) ||
      !is.character(database$database_name) || length(database$database_name) != 1L ||
      !nzchar(database$database_name) || !is.character(database$system_identifier) ||
      length(database$system_identifier) != 1L || !nzchar(database$system_identifier)) {
    .nrk_cutover_fail("CUTOVER_DATABASE_IDENTITY_INVALID")
  }
  list(
    database_name = database$database_name,
    system_identifier = database$system_identifier
  )
}

nrk_verify_cutover_artifacts <- function(artifacts) {
  required <- c(
    "record", "legacy", "record_manifest", "legacy_manifest", "inventory", "approval"
  )
  if (!is.list(artifacts) || !identical(sort(names(artifacts)), sort(required)) ||
      any(!vapply(artifacts, is.raw, logical(1)))) {
    .nrk_cutover_fail("CUTOVER_ARTIFACT_SET_INVALID")
  }
  documents <- lapply(names(artifacts), function(name) {
    .nrk_cutover_parse(artifacts[[name]], paste0("CUTOVER_ARTIFACT_JSON_INVALID: ", name))
  })
  names(documents) <- names(artifacts)
  schemas <- c(
    record = "narrative-record-baseline-candidates-v1",
    legacy = "narrative-legacy-baseline-candidates-v1",
    record_manifest = "narrative-record-baseline-manifest-v1",
    legacy_manifest = "narrative-legacy-baseline-manifest-v1",
    inventory = "narrative-record-cutover-inventory-v1",
    approval = "narrative-record-cutover-approval-v1"
  )
  for (name in names(schemas)) {
    if (!identical(documents[[name]]$schema_version, schemas[[name]])) {
      .nrk_cutover_fail("CUTOVER_ARTIFACT_SCHEMA_INVALID")
    }
  }
  database <- .nrk_cutover_database(documents$record)
  for (name in names(documents)[-1L]) {
    if (!identical(.nrk_cutover_database(documents[[name]]), database)) {
      .nrk_cutover_fail("CUTOVER_ARTIFACT_DATABASE_IDENTITY_MISMATCH")
    }
  }
  hashes <- list(
    record_candidates_sha256 = .nrk_cutover_sha_raw(artifacts$record),
    legacy_candidates_sha256 = .nrk_cutover_sha_raw(artifacts$legacy),
    record_manifest_sha256 = .nrk_cutover_sha_raw(artifacts$record_manifest),
    legacy_manifest_sha256 = .nrk_cutover_sha_raw(artifacts$legacy_manifest),
    inventory_sha256 = .nrk_cutover_sha_raw(artifacts$inventory),
    approval_sha256 = .nrk_cutover_sha_raw(artifacts$approval)
  )
  embedded <- documents$approval$input_hashes
  for (name in setdiff(names(hashes), "approval_sha256")) {
    if (!is.character(embedded[[name]]) || !grepl(.nrk_cutover_sha, embedded[[name]]) ||
        !identical(embedded[[name]], hashes[[name]])) {
      .nrk_cutover_fail("CUTOVER_ARTIFACT_HASH_MISMATCH")
    }
  }
  if (!identical(documents$record_manifest$record_candidates_sha256,
                 hashes$record_candidates_sha256) ||
      !identical(documents$legacy_manifest$legacy_candidates_sha256,
                 hashes$legacy_candidates_sha256)) {
    .nrk_cutover_fail("CUTOVER_ARTIFACT_HASH_MISMATCH")
  }
  list(
    artifacts = artifacts, documents = documents, hashes = hashes, database = database,
    raw_text = lapply(artifacts, rawToChar)
  )
}

nrk_validate_cutover_mode <- function(mode) {
  if (!is.character(mode) || length(mode) != 1L ||
      !mode %in% c("preflight", "rollback", "apply", "recover")) {
    .nrk_cutover_fail("CUTOVER_MODE_INVALID")
  }
  mode
}

nrk_validate_cutover_nonce <- function(nonce) {
  if (!is.character(nonce) || length(nonce) != 1L || is.na(nonce) ||
      !grepl(.nrk_cutover_uuid, nonce)) {
    .nrk_cutover_fail("CUTOVER_NONCE_INVALID")
  }
  nonce
}

nrk_validate_cutover_pg_profile <- function(profile) {
  required <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
  if (is.null(names(profile)) || length(profile) != 5L || !setequal(names(profile), required)) {
    .nrk_cutover_fail("PG_PROFILE_INCOMPLETE")
  }
  profile <- profile[required]
  if (anyNA(profile) || any(!nzchar(profile[names(profile) != "PGPASSWORD"]))) {
    .nrk_cutover_fail("PG_PROFILE_INCOMPLETE")
  }
  as.list(profile)
}

.nrk_kernel_arguments <- function(verified, nonce, database_name, system_identifier) {
  list(
    record_candidates_raw = verified$raw_text$record,
    legacy_candidates_raw = verified$raw_text$legacy,
    record_manifest_raw = verified$raw_text$record_manifest,
    legacy_manifest_raw = verified$raw_text$legacy_manifest,
    inventory_raw = verified$raw_text$inventory,
    approval_raw = verified$raw_text$approval,
    nonce = nonce, expected_database_name = database_name,
    expected_system_identifier = system_identifier,
    hashes = verified$hashes,
    database = list(database_name = database_name, system_identifier = system_identifier)
  )
}

.nrk_sorted_json <- function(value) {
  if (is.list(value)) {
    if (!is.null(names(value))) value <- value[order(names(value), method = "radix")]
    return(lapply(value, .nrk_sorted_json))
  }
  value
}

.nrk_canonical_receipt_raw <- function(value) charToRaw(paste0(jsonlite::toJSON(
  .nrk_sorted_json(value), auto_unbox = TRUE, null = "null", na = "null",
  digits = NA, pretty = FALSE, force = TRUE
), "\n"))

nrk_receipt_from_result <- function(arguments, result) {
  receipt <- list(
    schema_version = "narrative-record-cutover-receipt-v1",
    nonce = arguments$nonce,
    database = arguments$database,
    input_hashes = arguments$hashes,
    result = result
  )
  result_raw <- rawToChar(.nrk_canonical_receipt_raw(result))
  result_raw <- substr(result_raw, 1L, nchar(result_raw, type = "bytes") - 1L)
  receipt$result_raw <- result_raw
  receipt$result_sha256 <- .nrk_cutover_sha_raw(charToRaw(result_raw))
  receipt
}

.nrk_validate_receipt <- function(receipt, nonce, hashes, database) {
  same_named_scalars <- function(left, right) {
    is.list(left) && is.list(right) && setequal(names(left), names(right)) &&
      all(vapply(names(right), function(name) identical(left[[name]], right[[name]]),
                 logical(1)))
  }
  result_raw <- if (is.list(receipt)) {
    receipt$result_raw %||% attr(receipt, "nrk_result_raw", exact = TRUE)
  } else NULL
  if (!is.list(receipt) || !identical(receipt$nonce, nonce) ||
      !same_named_scalars(receipt$input_hashes, hashes) ||
      !same_named_scalars(receipt$database, database) ||
      !is.list(receipt$result) || !identical(receipt$result$nonce, nonce) ||
      !same_named_scalars(receipt$result$input_hashes, hashes) ||
      !same_named_scalars(receipt$result$database, database) ||
      !is.character(result_raw) || length(result_raw) != 1L ||
      !is.character(receipt$result_sha256) ||
      !grepl(.nrk_cutover_sha, receipt$result_sha256)) {
    .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  }
  parsed_result <- tryCatch(
    .nrk_parse_cutover_result_json(result_raw),
    error = function(error) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  )
  if (!identical(
        .nrk_canonical_receipt_raw(parsed_result),
        .nrk_canonical_receipt_raw(receipt$result)
      ) || !identical(
        .nrk_cutover_sha_raw(charToRaw(result_raw)),
        receipt$result_sha256
      )) {
    .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  }
  receipt$result_raw <- NULL
  attr(receipt, "nrk_result_raw") <- result_raw
  receipt$schema_version <- "narrative-record-cutover-receipt-v1"
  receipt
}

nrk_cutover_execute <- function(
  mode, artifacts, nonce, expected_database_name, expected_system_identifier,
  gateway, receipt_publisher
) {
  mode <- nrk_validate_cutover_mode(mode)
  nonce <- nrk_validate_cutover_nonce(nonce)
  verified <- nrk_verify_cutover_artifacts(artifacts)
  expected_database <- list(
    database_name = expected_database_name,
    system_identifier = expected_system_identifier
  )
  if (!identical(verified$database, expected_database) ||
      !identical(gateway$identity(), expected_database)) {
    .nrk_cutover_fail("CUTOVER_DATABASE_IDENTITY_MISMATCH")
  }
  arguments <- .nrk_kernel_arguments(
    verified, nonce, expected_database_name, expected_system_identifier
  )

  if (mode == "recover") {
    receipts <- tryCatch(
      gateway$exact_receipts(nonce, verified$hashes, expected_database),
      error = function(error) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
    )
    count <- tryCatch(
      gateway$nonce_receipt_count(nonce),
      error = function(error) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
    )
    if (length(receipts) != 1L || !identical(as.integer(count), 1L)) {
      .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
    }
    receipt <- .nrk_validate_receipt(
      receipts[[1L]], nonce, verified$hashes, expected_database
    )
    tryCatch(
      receipt_publisher(receipt, recover = TRUE),
      error = function(error) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
    )
    return(list(status = "recovered", receipt = receipt))
  }

  if (!identical(as.integer(gateway$version()), 1L)) {
    .nrk_cutover_fail("CUTOVER_CONTRACT_VERSION_NOT_ONE")
  }
  before <- gateway$snapshot()
  gateway$begin()
  completed <- FALSE
  on.exit(if (!completed && gateway$active()) gateway$rollback(), add = TRUE)
  result <- gateway$kernel(arguments)
  if (mode %in% c("preflight", "rollback")) {
    gateway$rollback()
    completed <- TRUE
    after <- gateway$snapshot()
    if (!identical(before, after)) .nrk_cutover_fail("CUTOVER_ROLLBACK_STATE_DRIFT")
    return(list(
      status = if (mode == "preflight") "preflight_rolled_back" else "rollback_verified",
      before = before, after = after, predicted_result = result
    ))
  }

  commit_ok <- tryCatch({ gateway$commit(); TRUE }, error = function(error) FALSE)
  completed <- TRUE
  if (!commit_ok) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  reconnect_ok <- tryCatch({ gateway$reconnect(); TRUE }, error = function(error) FALSE)
  if (!reconnect_ok) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  receipts <- tryCatch(
    gateway$exact_receipts(nonce, verified$hashes, expected_database),
    error = function(error) list()
  )
  count <- tryCatch(gateway$nonce_receipt_count(nonce), error = function(error) -1L)
  if (length(receipts) != 1L || !identical(as.integer(count), 1L)) {
    .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  }
  receipt <- .nrk_validate_receipt(receipts[[1L]], nonce, verified$hashes, expected_database)
  tryCatch(
    receipt_publisher(receipt, recover = FALSE),
    error = function(error) .nrk_cutover_fail("CUTOVER_RECOVERY_REQUIRED")
  )
  list(status = "committed", receipt = receipt, result = result)
}

nrk_db_cutover_gateway <- function(connection, reconnect_factory = NULL) {
  active <- FALSE
  connected <- TRUE
  current_connection <- connection
  parse_json_column <- function(value) {
    value <- value[[1L]]
    if (is.list(value)) return(value)
    jsonlite::fromJSON(value, simplifyVector = FALSE, bigint_as_char = TRUE)
  }
  list(
    identity = function() {
      row <- DBI::dbGetQuery(current_connection, .nrk_apply_sql$identity)
      list(database_name = row$database_name[[1L]],
           system_identifier = row$system_identifier[[1L]])
    },
    version = function() DBI::dbGetQuery(current_connection, .nrk_apply_sql$version)$version[[1L]],
    snapshot = function() parse_json_column(
      DBI::dbGetQuery(current_connection, .nrk_apply_sql$snapshot)$snapshot
    ),
    begin = function() { DBI::dbBegin(current_connection); active <<- TRUE },
    kernel = function(arguments) {
      params <- unname(arguments[c(
        "record_candidates_raw", "legacy_candidates_raw", "record_manifest_raw",
        "legacy_manifest_raw", "inventory_raw", "approval_raw", "nonce",
        "expected_database_name", "expected_system_identifier"
      )])
      value <- DBI::dbGetQuery(current_connection, .nrk_apply_sql$kernel, params = params)$result
      value <- value[[1L]]
      if (!is.character(value)) .nrk_cutover_fail("CUTOVER_DB_RESULT_JSON_INVALID")
      .nrk_parse_cutover_result_json(value)
    },
    commit = function() { on.exit(active <<- FALSE); DBI::dbCommit(current_connection) },
    rollback = function() { on.exit(active <<- FALSE); DBI::dbRollback(current_connection) },
    reconnect = function() {
      if (active || !is.function(reconnect_factory)) {
        .nrk_cutover_fail("CUTOVER_DB_RECONNECT_UNAVAILABLE")
      }
      if (connected) {
        try(DBI::dbDisconnect(current_connection), silent = TRUE)
        connected <<- FALSE
      }
      current_connection <<- reconnect_factory()
      connected <<- TRUE
      invisible(NULL)
    },
    disconnect = function() {
      if (connected) {
        try(DBI::dbDisconnect(current_connection), silent = TRUE)
        connected <<- FALSE
      }
      invisible(NULL)
    },
    exact_receipts = function(nonce, hashes, database) {
      params <- c(list(nonce), unname(hashes), unname(database))
      rows <- DBI::dbGetQuery(current_connection, .nrk_apply_sql$exact_receipt, params = params)
      lapply(seq_len(nrow(rows)), function(index) list(
        nonce = rows$nonce[[index]],
        input_hashes = if (is.list(rows$input_hashes)) rows$input_hashes[[index]] else
          jsonlite::fromJSON(rows$input_hashes[[index]], simplifyVector = FALSE),
        database = if (is.list(rows$database)) rows$database[[index]] else
          jsonlite::fromJSON(rows$database[[index]], simplifyVector = FALSE),
        result = .nrk_parse_cutover_result_json(rows$result_raw[[index]]),
        result_raw = rows$result_raw[[index]],
        result_sha256 = rows$result_sha256[[index]],
        committed_at = as.character(rows$committed_at[[index]])
      ))
    },
    nonce_receipt_count = function(nonce) DBI::dbGetQuery(
      current_connection, .nrk_apply_sql$nonce_receipt_count, params = list(nonce)
    )$receipt_count[[1L]],
    active = function() active
  )
}

.nrk_has_work_component <- function(path) {
  "work" %in% strsplit(path, "/", fixed = TRUE)[[1L]]
}

.nrk_inside_repository <- function(path, repository_root) {
  identical(path, repository_root) || startsWith(path, paste0(repository_root, "/"))
}

nrk_validate_artifact_paths <- function(paths, repository_root) {
  if (!is.character(paths) || length(paths) != 6L || anyNA(paths) ||
      any(!grepl("^/", paths))) {
    .nrk_cutover_fail("CUTOVER_ARTIFACT_PATH_INVALID")
  }
  repository_root <- normalizePath(repository_root, mustWork = TRUE)
  vapply(paths, function(path) {
    if (.nrk_has_work_component(path)) .nrk_cutover_fail("OUTPUT_WORK_PATH")
    info <- file.info(path)
    link <- Sys.readlink(path)
    if (is.na(info$isdir) || info$isdir || (!is.na(link) && nzchar(link))) {
      .nrk_cutover_fail("CUTOVER_ARTIFACT_PATH_INVALID")
    }
    resolved <- normalizePath(path, mustWork = TRUE)
    if (.nrk_has_work_component(resolved)) .nrk_cutover_fail("OUTPUT_WORK_PATH")
    if (.nrk_inside_repository(resolved, repository_root)) {
      .nrk_cutover_fail("OUTPUT_INSIDE_REPOSITORY")
    }
    resolved
  }, character(1), USE.NAMES = FALSE)
}

nrk_validate_receipt_path <- function(path, repository_root) {
  if (!is.character(path) || length(path) != 1L || !grepl("^/", path)) {
    .nrk_cutover_fail("CUTOVER_RECEIPT_PATH_INVALID")
  }
  if (!identical(basename(path), .nrk_receipt_name)) {
    .nrk_cutover_fail("CUTOVER_RECEIPT_FILENAME_INVALID")
  }
  if (.nrk_has_work_component(path)) .nrk_cutover_fail("OUTPUT_WORK_PATH")
  parent <- dirname(path)
  parent_link <- Sys.readlink(parent)
  parent_info <- file.info(parent)
  if (!dir.exists(parent) || is.na(parent_info$isdir) || !parent_info$isdir ||
      (!is.na(parent_link) && nzchar(parent_link))) {
    .nrk_cutover_fail("CUTOVER_RECEIPT_DIRECTORY_INVALID")
  }
  if (bitwAnd(as.integer(parent_info$mode), 511L) != 448L) {
    .nrk_cutover_fail("CUTOVER_RECEIPT_DIRECTORY_MODE_INVALID")
  }
  resolved_parent <- normalizePath(parent, mustWork = TRUE)
  if (.nrk_has_work_component(resolved_parent)) .nrk_cutover_fail("OUTPUT_WORK_PATH")
  candidate <- file.path(resolved_parent, basename(path))
  repository_root <- normalizePath(repository_root, mustWork = TRUE)
  if (.nrk_inside_repository(candidate, repository_root)) {
    .nrk_cutover_fail("OUTPUT_INSIDE_REPOSITORY")
  }
  target_link <- Sys.readlink(path)
  if (!is.na(target_link) && nzchar(target_link)) {
    .nrk_cutover_fail("CUTOVER_RECEIPT_PATH_INVALID")
  }
  candidate
}
