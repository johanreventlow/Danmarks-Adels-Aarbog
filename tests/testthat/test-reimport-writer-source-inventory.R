writer_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
`%||%` <- function(value, fallback) if (is.null(value)) fallback else value

writer_literal_rules <- data.frame(
  literal = c("source_id_3", "sr_source_id_not_3", "sp_source_id_not_3", "equals_8", "not_equals_8", "citation_label", "run_key", "name_completion_lock"),
  classification = c("profile", "generic_invariant", "generic_invariant", "manifest", "manifest", "profile", "manifest", "legacy_wrapper"),
  generic_target = c("source_id", "source_profile_validation", "source_profile_validation", "expected_counts", "expected_counts", "citation_label_template", "run_key_prefix", "generic_name_completion_lock"),
  pattern = c("source_id\\s*=\\s*3", "sr\\.source_id\\s*<>\\s*3", "sp\\.source_id\\s*<>\\s*3", "=8", "<>8", "DAA 1939 side", "reimport-1939-v50:", "daa-1939-v50-name-completion"),
  stringsAsFactors = FALSE
)

writer_inventory_groups <- read.table(text = "
schema private.ensure_reimport_1939_source_evidence#1 run_key 2
schema public.red_apply_1939_v50_person_create#1 citation_label 1
schema public.red_reverse_1939_v50_reimport#1 name_completion_lock 1
schema public.red_reverse_1939_v50_reimport#1 not_equals_8 8
schema public.red_reverse_1939_v50_reimport#1 sr_source_id_not_3 1
schema public.red_reverse_1939_v50_reimport#1 sp_source_id_not_3 1
schema public.red_reverse_1939_v50_reimport#1 run_key 1
schema public.red_activate_1939_v50_batch#1 name_completion_lock 1
schema public.red_activate_1939_v50_batch#1 not_equals_8 9
schema public.red_activate_1939_v50_batch#1 sr_source_id_not_3 1
schema public.red_activate_1939_v50_batch#1 sp_source_id_not_3 1
schema public.red_activate_1939_v50_batch#1 not_equals_8 1
schema private.validate_reimport_1939_name_completion#1 name_completion_lock 1
schema private.validate_reimport_1939_name_completion#1 not_equals_8 2
schema private.validate_reimport_1939_name_completion#1 source_id_3 3
schema public.red_lock_1939_v50_name_completion#1 name_completion_lock 1
schema public.red_apply_1939_v50_name_completion#1 name_completion_lock 1
schema public.red_apply_1939_v50_name_completion#1 source_id_3 3
schema public.red_finalize_1939_v50_name_completion#1 not_equals_8 1
migration private.ensure_reimport_1939_source_evidence#1 run_key 2
migration public.red_apply_1939_v50_person_create#1 citation_label 1
migration public.red_reverse_1939_v50_reimport#1 run_key 1
migration private.validate_reimport_1939_name_completion#1 name_completion_lock 1
migration private.validate_reimport_1939_name_completion#1 not_equals_8 2
migration private.validate_reimport_1939_name_completion#1 source_id_3 3
migration public.red_lock_1939_v50_name_completion#1 name_completion_lock 1
migration public.red_apply_1939_v50_name_completion#1 name_completion_lock 1
migration public.red_apply_1939_v50_name_completion#1 source_id_3 3
migration public.red_finalize_1939_v50_name_completion#1 not_equals_8 1
migration public.red_reverse_1939_v50_reimport#2 name_completion_lock 1
migration public.red_reverse_1939_v50_reimport#2 not_equals_8 8
migration public.red_reverse_1939_v50_reimport#2 sr_source_id_not_3 1
migration public.red_reverse_1939_v50_reimport#2 sp_source_id_not_3 1
migration public.red_reverse_1939_v50_reimport#2 run_key 1
migration public.red_activate_1939_v50_batch#2 name_completion_lock 1
migration public.red_activate_1939_v50_batch#2 not_equals_8 9
migration public.red_activate_1939_v50_batch#2 sr_source_id_not_3 1
migration public.red_activate_1939_v50_batch#2 sp_source_id_not_3 1
migration public.red_activate_1939_v50_batch#2 not_equals_8 1
migration public.red_reverse_1939_v50_reimport#3 name_completion_lock 1
migration public.red_reverse_1939_v50_reimport#3 not_equals_8 8
migration public.red_reverse_1939_v50_reimport#3 sr_source_id_not_3 1
migration public.red_reverse_1939_v50_reimport#3 sp_source_id_not_3 1
migration public.red_reverse_1939_v50_reimport#3 run_key 1
migration public.red_activate_1939_v50_batch#3 name_completion_lock 1
migration public.red_activate_1939_v50_batch#3 not_equals_8 9
migration public.red_activate_1939_v50_batch#3 sr_source_id_not_3 1
migration public.red_activate_1939_v50_batch#3 sp_source_id_not_3 1
migration public.red_activate_1939_v50_batch#3 not_equals_8 1
migration public.red_finalize_1939_v50_name_completion#2 not_equals_8 1
migration private.validate_reimport_1939_name_completion#2 name_completion_lock 1
migration private.validate_reimport_1939_name_completion#2 not_equals_8 2
migration private.validate_reimport_1939_name_completion#2 source_id_3 3
", col.names = c("segment", "function_name", "literal", "count"), comment.char = "", stringsAsFactors = FALSE)

writer_inventory <- do.call(rbind, lapply(seq_len(nrow(writer_inventory_groups)), function(index) {
  group <- writer_inventory_groups[index, ]
  rule <- writer_literal_rules[writer_literal_rules$literal == group$literal, ]
  data.frame(literal = rep(group$literal, group$count), classification = rep(rule$classification, group$count), generic_target = rep(rule$generic_target, group$count), test_name = sprintf("%s/%s/%s/%03d", group$segment, group$function_name, group$literal, seq_len(group$count)), stringsAsFactors = FALSE)
}))

writer_segment_occurrences <- function(path, first_line, last_line, segment_name) {
  lines <- readLines(file.path(writer_root, path), warn = FALSE)[first_line:last_line]
  function_name <- "top_level"; function_instances <- list(); literal_ordinals <- list(); observed <- list()
  for (index in seq_along(lines)) {
    function_match <- regexec("^\\s*CREATE(?: OR REPLACE)? FUNCTION ([[:alnum:]_.]+)", lines[[index]], perl = TRUE)
    captures <- regmatches(lines[[index]], function_match)[[1L]]
    if (length(captures) > 1L) {
      base <- captures[[2L]]; function_instances[[base]] <- (function_instances[[base]] %||% 0L) + 1L
      function_name <- sprintf("%s#%d", base, function_instances[[base]]); literal_ordinals <- list()
    }
    for (rule_index in seq_len(nrow(writer_literal_rules))) {
      rule <- writer_literal_rules[rule_index, ]; matches <- gregexpr(rule$pattern, lines[[index]], perl = TRUE)[[1L]]
      if (matches[[1L]] == -1L) next
      ordinal_key <- paste(function_name, rule$literal, sep = "|")
      for (ignored in matches) {
        literal_ordinals[[ordinal_key]] <- (literal_ordinals[[ordinal_key]] %||% 0L) + 1L
        observed[[length(observed) + 1L]] <- data.frame(literal = rule$literal, classification = rule$classification, generic_target = rule$generic_target, test_name = sprintf("%s/%s/%s/%03d", segment_name, function_name, rule$literal, literal_ordinals[[ordinal_key]]), line = first_line + index - 1L, stringsAsFactors = FALSE)
      }
    }
  }
  do.call(rbind, observed)
}

extract_public_function <- function(text, name) {
  pattern <- paste0("(?s)CREATE(?: OR REPLACE)? FUNCTION public\\.", name, "\\s*\\([^)]*\\).*?AS \\$\\$.*?\\$\\$;")
  regmatches(text, regexpr(pattern, text, perl = TRUE))
}

testthat::test_that("generic extractor recognizes a valid CREATE OR REPLACE function", {
  fixture <- paste("CREATE OR REPLACE FUNCTION public.red_fixture(p_value text)", "RETURNS void LANGUAGE plpgsql AS $$ BEGIN NULL; END $$;", sep = "\n")
  testthat::expect_match(extract_public_function(fixture, "red_fixture"), "red_fixture", fixed = TRUE)
})

testthat::test_that("Task 1 literal inventory retains exact schema and migration classification coverage", {
  segment_counts <- table(writer_inventory_groups$segment)
  testthat::expect_identical(names(segment_counts), c("migration", "schema"))
  testthat::expect_identical(unname(as.integer(segment_counts)), c(34L, 19L))
  classification_counts <- table(writer_inventory$classification)
  testthat::expect_identical(names(classification_counts), c("generic_invariant", "legacy_wrapper", "manifest", "profile"))
  testthat::expect_identical(unname(as.integer(classification_counts)), c(12L, 13L, 71L, 17L))
  testthat::expect_identical(
    writer_literal_rules[, c("literal", "classification", "generic_target")],
    data.frame(
      literal = c("source_id_3", "sr_source_id_not_3", "sp_source_id_not_3", "equals_8", "not_equals_8", "citation_label", "run_key", "name_completion_lock"),
      classification = c("profile", "generic_invariant", "generic_invariant", "manifest", "manifest", "profile", "manifest", "legacy_wrapper"),
      generic_target = c("source_id", "source_profile_validation", "source_profile_validation", "expected_counts", "expected_counts", "citation_label_template", "run_key_prefix", "generic_name_completion_lock"),
      stringsAsFactors = FALSE
    )
  )
})

testthat::test_that("generic reimport writer owns every formerly 1939-specific literal", {
  testthat::expect_identical(names(writer_inventory), c("literal", "classification", "generic_target", "test_name"))
  testthat::expect_true(all(writer_inventory$classification %in% c("generic_invariant", "profile", "manifest", "legacy_wrapper")))
  schema_primary <- paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_false(grepl("CREATE TABLE private\\.reimport_1939_(authorization|write_batch|write_event|name_completion_result)", schema_primary, perl = TRUE))

  generic_sources <- list(
    schema = paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n"),
    migration = paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  )
  generic_names <- c("red_authorize_reimport", "red_begin_reimport", "red_apply_reimport_source_evidence", "red_apply_reimport_person_create", "red_finalize_reimport", "red_authorize_reimport_reversal", "red_reverse_reimport", "red_authorize_reimport_cutover", "red_activate_reimport_batch")
  generic_definitions <- lapply(generic_sources, function(source_text) {
    definitions <- lapply(generic_names, extract_public_function, text = source_text)
    names(definitions) <- generic_names
    definitions
  })
  testthat::expect_true(all(vapply(generic_definitions, function(definitions) all(lengths(definitions) == 1L), logical(1))))
  if (any(!vapply(generic_definitions, function(definitions) all(lengths(definitions) == 1L), logical(1)))) return(invisible())

  forbidden_literals <- paste(writer_literal_rules$pattern, collapse = "|")
  for (source_name in names(generic_definitions)) {
    for (definition in generic_definitions[[source_name]]) {
      lock <- regexpr("pg_advisory_xact_lock_shared\\(hashtextextended\\('daa-narrative-record-contract',0\\)\\)", definition, perl = TRUE)
      gate <- regexpr("REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED", definition, perl = TRUE)
      mutation <- regexpr("\\b(INSERT|UPDATE|DELETE)\\b", definition, perl = TRUE)
      testthat::expect_true(lock[[1L]] > 0L && gate[[1L]] > lock[[1L]] && (mutation[[1L]] == -1L || mutation[[1L]] > gate[[1L]]))
      testthat::expect_false(grepl(forbidden_literals, definition, perl = TRUE))
      testthat::expect_false(grepl("\\b(INSERT|UPDATE|DELETE)\\s+(INTO\\s+)?(public\\.narrative|private\\.narrative_record_publication)\\b", definition, perl = TRUE))
    }
    generic_person_create <- generic_definitions[[source_name]][["red_apply_reimport_person_create"]]
    for (required in c("red_upsert_person_narrative_record", "event_id", "narrative_id", "publication_state_sha256", "state_sha256", "INSERT INTO private.reimport_event")) testthat::expect_match(generic_person_create, required, fixed = TRUE)
  }
})

testthat::test_that("profile-bound writer keeps the immutable triple at every ledger boundary", {
  schema_text <- paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n")
  migration_text <- paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  for (source_text in list(schema_text, migration_text)) {
    testthat::expect_match(source_text, "reimport_writer_profile", fixed = TRUE)
    testthat::expect_match(source_text, "UNIQUE(source_id,profile_id,profile_sha256)", fixed = TRUE)
    testthat::expect_match(source_text, "FOREIGN KEY(source_id,profile_id,profile_sha256)", fixed = TRUE)
    testthat::expect_match(source_text, "REIMPORT_WRITER_PROFILE_APPEND_ONLY", fixed = TRUE)
    testthat::expect_match(source_text, "REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED", fixed = TRUE)
  }
})

testthat::test_that("migration writer keeps fresh-equivalent finalize, replay, and helper ACL guards", {
  migration_text <- paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  migration_begin <- extract_public_function(migration_text, "red_begin_reimport")
  migration_finalize <- extract_public_function(migration_text, "red_finalize_reimport")
  testthat::expect_match(migration_begin, "private.require_reimport_writer_editor", fixed = TRUE)
  testthat::expect_match(migration_begin, "profile_sha256=a.profile_sha256", fixed = TRUE)
  testthat::expect_match(migration_begin, "status='finalized'", fixed = TRUE)
  testthat::expect_match(migration_finalize, "private.require_reimport_open_batch", fixed = TRUE)
  testthat::expect_match(migration_finalize, "REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH", fixed = TRUE)
  testthat::expect_match(migration_text, "private.ensure_reimport_source_evidence(uuid,text,jsonb)", fixed = TRUE)
  testthat::expect_match(migration_text, "private.require_reimport_open_batch(uuid)", fixed = TRUE)
  testthat::expect_match(migration_text, "FROM PUBLIC,anon,authenticated,service_role", fixed = TRUE)
})
