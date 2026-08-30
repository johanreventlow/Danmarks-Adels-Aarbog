.nrk_record_candidates_name <- "narrative-record-baseline-candidates-v1.json"
.nrk_legacy_candidates_name <- "narrative-legacy-baseline-candidates-v1.json"
.nrk_inventory_name <- "narrative-record-cutover-inventory-v1.json"
.nrk_uuid_pattern <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
.nrk_sha256_pattern <- "^[0-9a-f]{64}$"
.nrk_export_helper_path <- local({
  paths <- vapply(sys.frames(), function(frame) {
    value <- frame$ofile
    if (is.null(value) || length(value) != 1L) "" else as.character(value)
  }, character(1))
  paths <- paths[basename(paths) == "export_narrative_record_cutover_helpers.R"]
  if (!length(paths)) NA_character_ else normalizePath(tail(paths, 1L))
})
.nrk_export_script_dir <- if (is.na(.nrk_export_helper_path)) {
  file.path(getwd(), ".claude", "skills", "daa-extract", "scripts")
} else dirname(.nrk_export_helper_path)
.nrk_export_repo_root <- normalizePath(
  file.path(.nrk_export_script_dir, "../../../.."), mustWork = FALSE
)

.nrk_export_sql <- list(
  isolation = "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY",
  gate = paste(
    "SELECT pg_advisory_xact_lock_shared(",
    "hashtextextended('daa-narrative-record-contract',0)) AS nrk_export_gate"
  ),
  version = paste(
    "SELECT public.narrative_record_contract_version()::integer",
    "AS contract_version"
  ),
  identity = paste(
    "/* NRK_EXPORT_DATABASE_IDENTITY */",
    "SELECT current_database()::text AS database_name,",
    "(pg_control_system()).system_identifier::text AS system_identifier"
  ),
  record_candidates = paste(
    "/* NRK_EXPORT_RECORD_CANDIDATES */",
    "SELECT binding.id::text AS binding_id, binding.narrative_id::bigint,",
    "narrative.subjekt_id::bigint AS person_id, narrative.source_id::bigint AS source_id,",
    "source.slags::text AS source_kind, binding.source_record_id::text,",
    "record.record_key::text, binding.status::text,",
    "binding.record_label::text, binding.citation_label::text,",
    "encode(extensions.digest(private.narrative_publication_state(narrative.subjekt_id,",
    "narrative.source_id,record.record_key)::text,'sha256'),'hex')",
    "AS publication_state_sha256,",
    "encode(extensions.digest(narrative.tekst,'sha256'),'hex') AS narrative_text_sha256,",
    "count(*) OVER (PARTITION BY binding.narrative_id)::integer AS binding_match_count",
    "FROM private.narrative_record_publication binding",
    "JOIN public.narrative narrative ON narrative.id=binding.narrative_id",
    "JOIN private.source_record record ON record.id=binding.source_record_id",
    "JOIN public.source source ON source.id=narrative.source_id",
    "WHERE source.slags='DAA-udgave'",
    "ORDER BY binding.id::text"
  ),
  legacy_candidates = paste(
    "/* NRK_EXPORT_LEGACY_CANDIDATES */ WITH eligible AS (",
    "SELECT narrative.id AS narrative_id, narrative.subjekt_id AS person_id, narrative.source_id,",
    "source.slags AS source_kind, encode(extensions.digest(narrative.tekst,'sha256'),'hex')",
    "AS narrative_text_sha256, gen_random_uuid() AS legacy_publication_ref",
    "FROM public.narrative narrative JOIN public.source source ON source.id=narrative.source_id",
    "JOIN public.person person ON person.id=narrative.subjekt_id",
    "WHERE narrative.subjekt_type='person' AND source.slags='DAA-udgave'",
    "AND narrative.privat IS NOT TRUE AND person.privat IS NOT TRUE",
    "AND person.staged IS NOT TRUE AND person.levende IS FALSE",
    "AND NOT EXISTS (SELECT 1 FROM private.narrative_record_publication binding",
    "WHERE binding.narrative_id=narrative.id)",
    "AND NOT EXISTS (SELECT 1 FROM private.narrative_legacy_publication legacy",
    "WHERE legacy.narrative_id=narrative.id)",
    ") SELECT eligible.legacy_publication_ref::text, eligible.narrative_id::bigint,",
    "eligible.person_id::bigint, eligible.source_id::bigint, eligible.source_kind::text,",
    "eligible.narrative_text_sha256,",
    "encode(extensions.digest(private.narrative_legacy_candidate_publication_state(",
    "eligible.narrative_id,eligible.source_id,eligible.legacy_publication_ref)::text,",
    "'sha256'),'hex') AS baseline_sha256, 0::integer AS binding_match_count",
    "FROM eligible ORDER BY eligible.narrative_id"
  ),
  counts_by_source = paste(
    "/* NRK_EXPORT_COUNTS_BY_SOURCE */ WITH record_counts AS (",
    "SELECT record.source_id, count(*)::integer AS record_candidates",
    "FROM private.narrative_record_publication binding JOIN private.source_record record",
    "ON record.id=binding.source_record_id JOIN public.source source",
    "ON source.id=record.source_id WHERE source.slags='DAA-udgave' GROUP BY record.source_id",
    "), legacy_counts AS (SELECT narrative.source_id, count(*)::integer",
    "AS legacy_candidates FROM public.narrative narrative JOIN public.source source",
    "ON source.id=narrative.source_id JOIN public.person person ON person.id=narrative.subjekt_id",
    "WHERE narrative.subjekt_type='person' AND source.slags='DAA-udgave'",
    "AND narrative.privat IS NOT TRUE AND person.privat IS NOT TRUE",
    "AND person.staged IS NOT TRUE AND person.levende IS FALSE AND NOT EXISTS (SELECT 1",
    "FROM private.narrative_record_publication binding WHERE binding.narrative_id=narrative.id)",
    "AND NOT EXISTS (SELECT 1 FROM private.narrative_legacy_publication legacy",
    "WHERE legacy.narrative_id=narrative.id) GROUP BY narrative.source_id)",
    "SELECT coalesce(record_counts.source_id,legacy_counts.source_id)::bigint AS source_id,",
    "coalesce(record_candidates,0)::integer AS record_candidates,",
    "coalesce(legacy_candidates,0)::integer AS legacy_candidates FROM record_counts",
    "FULL JOIN legacy_counts USING(source_id) ORDER BY source_id"
  ),
  identity_counts = paste(
    "/* NRK_EXPORT_IDENTITY_COUNTS */ SELECT",
    "(SELECT count(*)::integer FROM private.source_persona_identity identity_state",
    "JOIN private.source_persona persona ON persona.id=identity_state.source_persona_id",
    "JOIN public.source source ON source.id=persona.source_id",
    "WHERE source.slags='DAA-udgave' AND identity_state.decision_status='accepted')",
    "AS accepted_identity_count, (SELECT count(*)::integer",
    "FROM private.source_record record JOIN public.source source ON source.id=record.source_id",
    "WHERE source.slags='DAA-udgave' AND (SELECT count(DISTINCT identity_state.canonical_person_id)",
    "FROM private.source_record_placement_current record_placement",
    "JOIN private.source_persona_placement_current persona_placement",
    "ON persona_placement.record_placement_id=record_placement.id",
    "JOIN private.source_persona_identity identity_state",
    "ON identity_state.source_persona_id=persona_placement.source_persona_id",
    "WHERE record_placement.source_record_id=record.id",
    "AND record_placement.decision_status='accepted'",
    "AND persona_placement.decision_status='accepted'",
    "AND persona_placement.placement_role IN ('principal_member','co_principal')",
    "AND identity_state.decision_status='accepted')<>1) AS identity_blocked_record_count"
  )
)

.nrk_sorted_value <- function(value) {
  if (is.list(value)) {
    if (!is.null(names(value))) {
      value <- value[order(names(value), method = "radix")]
    }
    return(lapply(value, .nrk_sorted_value))
  }
  value
}

nrk_canonical_raw <- function(value) {
  text <- jsonlite::toJSON(
    .nrk_sorted_value(value), auto_unbox = TRUE, null = "null", na = "null",
    digits = NA, pretty = FALSE, force = TRUE
  )
  charToRaw(paste0(text, "\n"))
}

nrk_sha_raw <- function(value) {
  digest::digest(value, algo = "sha256", serialize = FALSE)
}

.nrk_fail <- function(token) stop(token, call. = FALSE)

.nrk_require_columns <- function(rows, expected, token) {
  if (!is.data.frame(rows) || !identical(names(rows), expected)) .nrk_fail(token)
}

.nrk_require_integer <- function(value, token) {
  if ((!is.integer(value) && !inherits(value, "integer64")) || anyNA(value)) .nrk_fail(token)
}

.nrk_require_text <- function(value, token, allow_blank = FALSE) {
  if (!is.character(value) || anyNA(value) || (!allow_blank && any(!nzchar(trimws(value))))) {
    .nrk_fail(token)
  }
}

.nrk_require_sha <- function(value) {
  .nrk_require_text(value, "INVALID_SHA256")
  if (any(!grepl(.nrk_sha256_pattern, value))) .nrk_fail("INVALID_SHA256")
}

.nrk_require_uuid <- function(value, token = "INVALID_UUID") {
  .nrk_require_text(value, token)
  if (any(!grepl(.nrk_uuid_pattern, value))) .nrk_fail(token)
}

.nrk_rows_as_lists <- function(rows, fields) {
  lapply(seq_len(nrow(rows)), function(index) {
    setNames(lapply(fields, function(field) rows[[field]][[index]]), fields)
  })
}

.nrk_hash_rows <- function(rows) {
  lapply(rows, function(row) {
    row$row_sha256 <- nrk_sha_raw(nrk_canonical_raw(row))
    row
  })
}

nrk_export_new_legacy_refs <- function(narrative_ids) {
  if ((!is.integer(narrative_ids) && !inherits(narrative_ids, "integer64")) ||
      anyNA(narrative_ids) || anyDuplicated(as.character(narrative_ids))) {
    .nrk_fail("INVALID_LEGACY_IDS")
  }
  vapply(narrative_ids, function(unused) {
    digits <- sample(c(0:9, letters[1:6]), 32L, replace = TRUE)
    digits[[13L]] <- "4"
    digits[[17L]] <- sample(c(8:9, letters[1:2]), 1L)
    paste0(
      paste0(digits[1:8], collapse = ""), "-", paste0(digits[9:12], collapse = ""), "-",
      paste0(digits[13:16], collapse = ""), "-", paste0(digits[17:20], collapse = ""), "-",
      paste0(digits[21:32], collapse = "")
    )
  }, character(1))
}

.nrk_classified_readers <- function() {
  paths <- c(
    "mobile/src/data/about.ts", "mobile/src/data/haendelser.ts", "mobile/src/data/load.ts",
    "mobile/src/data/presensLinjer.ts", "mobile/src/data/redaktionRead.ts",
    "web/src/data/feedAux.ts", "web/src/data/haendelser.ts", "web/src/data/presensLinjer.ts",
    "web/src/data/public.ts", "web/src/data/redaktionRead.ts"
  )
  classifications <- c(
    "non_person_control", "rls_gated_metadata", "v2_public_rpc", "non_person_control",
    "v2_editor_rpc", "v2_public_rpc", "rls_gated_metadata", "non_person_control",
    "v2_public_rpc", "v2_editor_rpc"
  )
  lapply(seq_along(paths), function(index) list(
    path = paths[[index]], classification = classifications[[index]]
  ))
}

nrk_export_build_bundle <- function(records, legacy, counts, identity, database) {
  record_fields <- c(
    "binding_id", "narrative_id", "person_id", "source_id", "source_kind",
    "source_record_id", "record_key", "status", "record_label", "citation_label",
    "publication_state_sha256", "narrative_text_sha256", "binding_match_count"
  )
  legacy_fields <- c(
    "legacy_publication_ref", "narrative_id", "person_id", "source_id", "source_kind",
    "narrative_text_sha256", "baseline_sha256", "binding_match_count"
  )
  .nrk_require_columns(records, record_fields, "RECORD_CANDIDATE_SHAPE")
  .nrk_require_columns(legacy, legacy_fields, "LEGACY_CANDIDATE_SHAPE")
  .nrk_require_columns(
    counts, c("source_id", "record_candidates", "legacy_candidates"),
    "COUNTS_BY_SOURCE_SHAPE"
  )
  .nrk_require_columns(
    identity, c("accepted_identity_count", "identity_blocked_record_count"),
    "IDENTITY_COUNTS_SHAPE"
  )
  if (!is.list(database) || !identical(names(database), c("database_name", "system_identifier"))) {
    .nrk_fail("DATABASE_IDENTITY_SHAPE")
  }
  .nrk_require_text(database$database_name, "DATABASE_NAME_REQUIRED")
  .nrk_require_text(database$system_identifier, "SYSTEM_IDENTIFIER_REQUIRED")

  .nrk_require_uuid(records$binding_id)
  .nrk_require_uuid(records$source_record_id)
  if (anyDuplicated(records$binding_id)) .nrk_fail("DUPLICATE_RECORD_CANDIDATE")
  if (!identical(records$binding_id, sort(records$binding_id, method = "radix"))) {
    .nrk_fail("RECORD_CANDIDATE_ORDER")
  }
  for (field in c("narrative_id", "person_id", "source_id", "binding_match_count")) {
    .nrk_require_integer(records[[field]], paste0("INVALID_INTEGER: ", field))
  }
  if (any(records$binding_match_count != 1L)) .nrk_fail("AMBIGUOUS_RECORD_BINDING")
  if (any(records$source_kind != "DAA-udgave")) .nrk_fail("NON_DAA_CANDIDATE")
  for (field in c("record_key", "record_label", "citation_label")) {
    .nrk_require_text(records[[field]], paste0("INVALID_TEXT: ", field))
  }
  if (any(!records$status %in% c("draft", "published", "withdrawn"))) {
    .nrk_fail("RECORD_STATUS_INVALID")
  }
  .nrk_require_sha(records$publication_state_sha256)
  .nrk_require_sha(records$narrative_text_sha256)

  .nrk_require_uuid(legacy$legacy_publication_ref)
  if (anyDuplicated(legacy$legacy_publication_ref)) .nrk_fail("DUPLICATE_LEGACY_PUBLICATION_REF")
  for (field in c("narrative_id", "person_id", "source_id", "binding_match_count")) {
    .nrk_require_integer(legacy[[field]], paste0("INVALID_INTEGER: ", field))
  }
  legacy_narrative_ids <- as.character(legacy$narrative_id)
  if (anyDuplicated(legacy_narrative_ids)) .nrk_fail("DUPLICATE_LEGACY_CANDIDATE")
  if (!identical(
    legacy_narrative_ids,
    as.character(sort(legacy$narrative_id, method = "radix"))
  )) {
    .nrk_fail("LEGACY_CANDIDATE_ORDER")
  }
  if (any(legacy$binding_match_count != 0L)) .nrk_fail("AMBIGUOUS_LEGACY_BINDING")
  if (any(legacy$source_kind != "DAA-udgave")) .nrk_fail("NON_DAA_CANDIDATE")
  .nrk_require_sha(legacy$narrative_text_sha256)
  .nrk_require_sha(legacy$baseline_sha256)

  for (field in names(counts)) .nrk_require_integer(counts[[field]], "COUNTS_INTEGER_REQUIRED")
  # RPostgres exposes bigint as bit64::integer64. Base anyDuplicated() compares
  # the underlying double payload and can classify distinct bigint values as
  # duplicates, and identical() treats distinct NaN payloads as equal. Compare
  # exact decimal representations after retaining integer64's numeric sort.
  count_source_ids <- as.character(counts$source_id)
  if (anyDuplicated(count_source_ids) ||
      !identical(count_source_ids, as.character(sort(counts$source_id)))) {
    .nrk_fail("COUNTS_BY_SOURCE_ORDER")
  }
  expected_source_ids <- sort(unique(c(records$source_id, legacy$source_id)))
  if (!identical(as.character(counts$source_id), as.character(expected_source_ids))) {
    .nrk_fail("INVENTORY_COUNTS_BY_SOURCE_MISMATCH")
  }
  expected_record_counts <- vapply(expected_source_ids, function(source_id) {
    sum(records$source_id == source_id)
  }, integer(1))
  expected_legacy_counts <- vapply(expected_source_ids, function(source_id) {
    sum(legacy$source_id == source_id)
  }, integer(1))
  if (!identical(counts$record_candidates, expected_record_counts) ||
      !identical(counts$legacy_candidates, expected_legacy_counts)) {
    .nrk_fail("INVENTORY_COUNTS_BY_SOURCE_MISMATCH")
  }
  .nrk_require_integer(identity$accepted_identity_count, "ACCEPTED_IDENTITY_COUNT")
  .nrk_require_integer(identity$identity_blocked_record_count, "BLOCKED_RECORD_COUNT")
  if (nrow(identity) != 1L) .nrk_fail("IDENTITY_COUNTS_CARDINALITY")

  record_rows <- .nrk_hash_rows(.nrk_rows_as_lists(records, record_fields))
  legacy_rows <- .nrk_hash_rows(.nrk_rows_as_lists(legacy, legacy_fields))
  count_rows <- .nrk_rows_as_lists(counts, names(counts))
  database <- list(
    database_name = database$database_name,
    system_identifier = database$system_identifier
  )
  documents <- list(
    record = list(
      schema_version = "narrative-record-baseline-candidates-v1",
      database = database, rows = record_rows
    ),
    legacy = list(
      schema_version = "narrative-legacy-baseline-candidates-v1",
      database = database, rows = legacy_rows
    ),
    inventory = list(
      schema_version = "narrative-record-cutover-inventory-v1",
      database = database,
      record_candidate_ids = as.list(records$binding_id),
      legacy_candidate_ids = as.list(legacy$narrative_id),
      counts_by_source = count_rows,
      accepted_identity_count = identity$accepted_identity_count[[1L]],
      identity_blocked_record_count = identity$identity_blocked_record_count[[1L]],
      classified_direct_readers = .nrk_classified_readers()
    )
  )
  setNames(
    lapply(documents, nrk_canonical_raw),
    c(.nrk_record_candidates_name, .nrk_legacy_candidates_name, .nrk_inventory_name)
  )
}

nrk_validate_output_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    .nrk_fail("OUTPUT_PATH_REQUIRED")
  }
  if (!grepl("^/", path)) .nrk_fail("OUTPUT_PATH_NOT_ABSOLUTE")
  components <- strsplit(path, "/", fixed = TRUE)[[1L]]
  if ("work" %in% components) .nrk_fail("OUTPUT_WORK_PATH")
  repo <- .nrk_export_repo_root
  candidate <- normalizePath(path, mustWork = FALSE)
  resolved_components <- strsplit(candidate, "/", fixed = TRUE)[[1L]]
  if ("work" %in% resolved_components) .nrk_fail("OUTPUT_WORK_PATH")
  if (identical(candidate, repo) || startsWith(candidate, paste0(repo, "/"))) {
    .nrk_fail("OUTPUT_INSIDE_REPOSITORY")
  }
  path
}

`%||%` <- function(left, right) if (is.null(left)) right else left

nrk_validate_pg_profile <- function(profile) {
  required <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
  if (is.null(names(profile)) || !setequal(names(profile), required) || length(profile) != 5L) {
    .nrk_fail("PG_PROFILE_INCOMPLETE")
  }
  profile <- profile[required]
  if (anyNA(profile) || any(!nzchar(profile[names(profile) != "PGPASSWORD"]))) {
    .nrk_fail("PG_PROFILE_INCOMPLETE")
  }
  as.list(profile)
}

.nrk_default_publisher <- function(output_dir, bundle, recover = FALSE) {
  payload <- jsonlite::toJSON(list(files = as.list(vapply(
    bundle, openssl::base64_encode, character(1)
  ))), auto_unbox = TRUE
  )
  script <- file.path(.nrk_export_script_dir, "build_narrative_record_cutover_review.py")
  mode <- if (recover) "recover-bundle-stdin" else "publish-bundle-stdin"
  output <- system2(
    "/usr/bin/python3", c(script, "--mode", mode, "--output-dir", output_dir),
    input = payload, stdout = TRUE, stderr = TRUE
  )
  status <- attr(output, "status") %||% 0L
  if (!identical(as.integer(status), 0L)) {
    .nrk_fail(paste("ARTIFACT_PUBLICATION_FAILED", paste(output, collapse = " | ")))
  }
  invisible(output)
}

nrk_export_run <- function(gateway, output_dir, publisher = .nrk_default_publisher) {
  nrk_validate_output_path(output_dir)
  committed <- FALSE
  gateway$begin()
  on.exit(if (!committed && gateway$active()) gateway$rollback(), add = TRUE)
  gateway$query(.nrk_export_sql$isolation)
  gateway$query(.nrk_export_sql$gate)
  version <- gateway$query(.nrk_export_sql$version)
  if (!is.data.frame(version) || nrow(version) != 1L ||
      !identical(as.integer(version$contract_version[[1L]]), 1L)) {
    .nrk_fail("CONTRACT_VERSION_NOT_ONE")
  }
  database_row <- gateway$query(.nrk_export_sql$identity)
  database <- list(
    database_name = database_row$database_name[[1L]],
    system_identifier = database_row$system_identifier[[1L]]
  )
  records <- gateway$query(.nrk_export_sql$record_candidates)
  legacy <- gateway$query(.nrk_export_sql$legacy_candidates)
  counts <- gateway$query(.nrk_export_sql$counts_by_source)
  identity <- gateway$query(.nrk_export_sql$identity_counts)
  artifacts <- nrk_export_build_bundle(records, legacy, counts, identity, database)
  gateway$commit()
  committed <- TRUE
  publisher(output_dir, artifacts, recover = FALSE)
  list(
    artifacts = artifacts, database = database,
    hashes = lapply(artifacts, nrk_sha_raw), publication = "published"
  )
}
