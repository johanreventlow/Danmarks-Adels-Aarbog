writer_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
`%||%` <- function(value, fallback) if (is.null(value)) fallback else value

writer_literal_rules <- data.frame(
  literal = c("source_id_3", "sr_source_id_not_3", "sp_source_id_not_3", "equals_8", "not_equals_8", "citation_label", "run_key", "name_completion_lock"),
  classification = c("profile", "generic_invariant", "generic_invariant", "manifest", "manifest", "profile", "manifest", "legacy_wrapper"),
  generic_target = c("source_id", "source_profile_validation", "source_profile_validation", "expected_counts", "expected_counts", "citation_label_template", "run_key_prefix", "generic_name_completion_lock"),
  pattern = c("source_id\\s*=\\s*3", "sr\\.source_id\\s*<>\\s*3", "sp\\.source_id\\s*<>\\s*3", "=8", "<>8", "DAA 1939 side", "reimport-1939-v50:", "daa-1939-v50-name-completion"),
  stringsAsFactors = FALSE
)

writer_expected_inventory <- read.table(text = "
citation_label|profile|citation_label_template|schema/private.reject_reimport_writer_mutation#1/citation_label/001
run_key|manifest|run_key_prefix|schema/private.reject_reimport_writer_mutation#1/run_key/001
run_key|manifest|run_key_prefix|migration/private.ensure_reimport_1939_source_evidence#1/run_key/001
run_key|manifest|run_key_prefix|migration/private.ensure_reimport_1939_source_evidence#1/run_key/002
citation_label|profile|citation_label_template|migration/public.red_apply_1939_v50_person_create#1/citation_label/001
run_key|manifest|run_key_prefix|migration/public.red_reverse_1939_v50_reimport#1/run_key/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/private.validate_reimport_1939_name_completion#1/name_completion_lock/001
not_equals_8|manifest|expected_counts|migration/private.validate_reimport_1939_name_completion#1/not_equals_8/001
not_equals_8|manifest|expected_counts|migration/private.validate_reimport_1939_name_completion#1/not_equals_8/002
source_id_3|profile|source_id|migration/private.validate_reimport_1939_name_completion#1/source_id_3/001
source_id_3|profile|source_id|migration/private.validate_reimport_1939_name_completion#1/source_id_3/002
source_id_3|profile|source_id|migration/private.validate_reimport_1939_name_completion#1/source_id_3/003
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/public.red_lock_1939_v50_name_completion#1/name_completion_lock/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/public.red_apply_1939_v50_name_completion#1/name_completion_lock/001
source_id_3|profile|source_id|migration/public.red_apply_1939_v50_name_completion#1/source_id_3/001
source_id_3|profile|source_id|migration/public.red_apply_1939_v50_name_completion#1/source_id_3/002
source_id_3|profile|source_id|migration/public.red_apply_1939_v50_name_completion#1/source_id_3/003
not_equals_8|manifest|expected_counts|migration/public.red_finalize_1939_v50_name_completion#1/not_equals_8/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/public.red_reverse_1939_v50_reimport#2/name_completion_lock/001
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/001
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/002
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/003
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/004
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/005
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/006
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/007
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#2/not_equals_8/008
sr_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_reverse_1939_v50_reimport#2/sr_source_id_not_3/001
sp_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_reverse_1939_v50_reimport#2/sp_source_id_not_3/001
run_key|manifest|run_key_prefix|migration/public.red_reverse_1939_v50_reimport#2/run_key/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/public.red_activate_1939_v50_batch#2/name_completion_lock/001
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/001
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/002
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/003
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/004
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/005
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/006
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/007
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/008
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#2/not_equals_8/009
sr_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_activate_1939_v50_batch#2/sr_source_id_not_3/001
sp_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_activate_1939_v50_batch#2/sp_source_id_not_3/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/public.red_reverse_1939_v50_reimport#3/name_completion_lock/001
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/001
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/002
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/003
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/004
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/005
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/006
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/007
not_equals_8|manifest|expected_counts|migration/public.red_reverse_1939_v50_reimport#3/not_equals_8/008
sr_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_reverse_1939_v50_reimport#3/sr_source_id_not_3/001
sp_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_reverse_1939_v50_reimport#3/sp_source_id_not_3/001
run_key|manifest|run_key_prefix|migration/public.red_reverse_1939_v50_reimport#3/run_key/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/public.red_activate_1939_v50_batch#3/name_completion_lock/001
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/001
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/002
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/003
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/004
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/005
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/006
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/007
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/008
not_equals_8|manifest|expected_counts|migration/public.red_activate_1939_v50_batch#3/not_equals_8/009
sr_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_activate_1939_v50_batch#3/sr_source_id_not_3/001
sp_source_id_not_3|generic_invariant|source_profile_validation|migration/public.red_activate_1939_v50_batch#3/sp_source_id_not_3/001
not_equals_8|manifest|expected_counts|migration/public.red_finalize_1939_v50_name_completion#2/not_equals_8/001
name_completion_lock|legacy_wrapper|generic_name_completion_lock|migration/private.validate_reimport_1939_name_completion#2/name_completion_lock/001
not_equals_8|manifest|expected_counts|migration/private.validate_reimport_1939_name_completion#2/not_equals_8/001
not_equals_8|manifest|expected_counts|migration/private.validate_reimport_1939_name_completion#2/not_equals_8/002
source_id_3|profile|source_id|migration/private.validate_reimport_1939_name_completion#2/source_id_3/001
source_id_3|profile|source_id|migration/private.validate_reimport_1939_name_completion#2/source_id_3/002
source_id_3|profile|source_id|migration/private.validate_reimport_1939_name_completion#2/source_id_3/003
", sep = "|", col.names = c("literal", "classification", "generic_target", "test_name"), comment.char = "", stringsAsFactors = FALSE)

writer_literal_occurrences <- function(lines, segment_name, first_line = 1L) {
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

writer_segment_occurrences <- function(path, first_line, last_line, segment_name) {
  lines <- readLines(file.path(writer_root, path), warn = FALSE)[first_line:last_line]
  writer_literal_occurrences(lines, segment_name, first_line)
}

writer_unique_anchor_index <- function(lines, anchor, anchor_name) {
  matches <- which(grepl(anchor, lines, fixed = TRUE))
  if (length(matches) != 1L) {
    stop(sprintf("%s anchor must occur exactly once (observed %d)", anchor_name, length(matches)), call. = FALSE)
  }
  matches[[1L]]
}

writer_semantic_section <- function(lines, start_anchor, end_anchor, section_name) {
  start <- writer_unique_anchor_index(lines, start_anchor, sprintf("%s start", section_name))
  end <- writer_unique_anchor_index(lines, end_anchor, sprintf("%s end", section_name))
  if (end <= start) {
    stop(sprintf("%s anchors are reversed", section_name), call. = FALSE)
  }
  list(lines = lines[start:(end - 1L)], first_line = start)
}

writer_semantic_section_occurrences <- function(path, start_anchor, end_anchor, section_name) {
  lines <- readLines(file.path(writer_root, path), warn = FALSE)
  section <- writer_semantic_section(lines, start_anchor, end_anchor, section_name)
  writer_literal_occurrences(section$lines, section_name, section$first_line)
}

writer_final_expected_inventory <- read.table(text = "
citation_label|profile|citation_label_template|final-schema/private.reject_reimport_writer_mutation#1/citation_label/001
run_key|manifest|run_key_prefix|final-schema/private.reject_reimport_writer_mutation#1/run_key/001
source_id_3|profile|source_id|final-schema/public.red_authorize_1939_v50_name_completion#1/source_id_3/001
source_id_3|profile|source_id|final-migration/top_level/source_id_3/001
citation_label|profile|citation_label_template|final-migration/private.reimport_canonical_json_sha256#1/citation_label/001
run_key|manifest|run_key_prefix|final-migration/private.reimport_canonical_json_sha256#1/run_key/001
source_id_3|profile|source_id|final-migration/public.red_activate_reimport_batch#2/source_id_3/001
source_id_3|profile|source_id|final-migration/public.red_activate_reimport_batch#2/source_id_3/002
source_id_3|profile|source_id|final-migration/public.red_authorize_1939_v50_name_completion#2/source_id_3/001
", sep = "|", col.names = c("literal", "classification", "generic_target", "test_name"), comment.char = "", stringsAsFactors = FALSE)

writer_final_inventory_key_counts <- function(inventory) {
  key_columns <- c("literal", "classification", "generic_target", "test_name")
  keys <- do.call(paste, c(inventory[key_columns], sep = "|"))
  table(keys)
}

extract_public_function <- function(text, name) {
  pattern <- paste0("(?s)CREATE(?: OR REPLACE)? FUNCTION public\\.", name, "\\s*\\([^)]*\\).*?AS \\$\\$.*?\\$\\$;")
  regmatches(text, regexpr(pattern, text, perl = TRUE))
}

extract_final_public_function <- function(text, name) {
  pattern <- paste0("(?s)CREATE(?: OR REPLACE)? FUNCTION public\\.", name, "\\s*\\([^)]*\\).*?AS \\$\\$.*?\\$\\$;")
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1L]]
  if (!length(matches)) "" else matches[[length(matches)]]
}

testthat::test_that("generic extractor recognizes a valid CREATE OR REPLACE function", {
  fixture <- paste("CREATE OR REPLACE FUNCTION public.red_fixture(p_value text)", "RETURNS void LANGUAGE plpgsql AS $$ BEGIN NULL; END $$;", sep = "\n")
  testthat::expect_match(extract_public_function(fixture, "red_fixture"), "red_fixture", fixed = TRUE)
})

testthat::test_that("Task 1 literal inventory exactly covers the designated schema and migration ranges", {
  observed <- rbind(
    writer_segment_occurrences("schema.sql", 2324L, 3098L, "schema"),
    writer_segment_occurrences("db-migrations.sql", 7559L, 8419L, "migration")
  )
  key_columns <- c("literal", "classification", "generic_target", "test_name")
  expected_keys <- do.call(paste, c(writer_expected_inventory[key_columns], sep = "|"))
  observed_keys <- do.call(paste, c(observed[key_columns], sep = "|"))
  all_keys <- sort(unique(c(expected_keys, observed_keys)))
  expected_counts <- tabulate(match(expected_keys, all_keys), nbins = length(all_keys))
  observed_counts <- tabulate(match(observed_keys, all_keys), nbins = length(all_keys))
  names(expected_counts) <- all_keys
  names(observed_counts) <- all_keys
  mismatched_keys <- all_keys[expected_counts != observed_counts]

  if (length(mismatched_keys)) {
    testthat::fail(paste(
      "writer literal inventory drift",
      paste(sprintf(
        "%s (expected %d, observed %d)",
        mismatched_keys,
        expected_counts[mismatched_keys],
        observed_counts[mismatched_keys]
      ), collapse = "\n"),
      sep = "\n"
    ))
  }
  testthat::expect_identical(observed_counts, expected_counts)
})

testthat::test_that("semantic writer-section anchors are unique, ordered, and scope literals", {
  start_anchor <- "-- WRITER START"
  end_anchor <- "-- WRITER END"
  fixture <- c("outside source_id = 3", start_anchor, "inside source_id = 3", end_anchor, "outside source_id = 3")
  section <- writer_semantic_section(fixture, start_anchor, end_anchor, "fixture")
  observed <- writer_literal_occurrences(section$lines, "fixture", section$first_line)
  testthat::expect_equal(nrow(observed), 1L)
  testthat::expect_identical(observed$literal, "source_id_3")
  testthat::expect_error(
    writer_semantic_section(c("before", end_anchor, "after"), start_anchor, end_anchor, "fixture"),
    "start anchor must occur exactly once"
  )
  testthat::expect_error(
    writer_semantic_section(c("before", start_anchor, "after"), start_anchor, end_anchor, "fixture"),
    "end anchor must occur exactly once"
  )
  testthat::expect_error(
    writer_semantic_section(c(start_anchor, start_anchor, end_anchor), start_anchor, end_anchor, "fixture"),
    "start anchor must occur exactly once"
  )
  testthat::expect_error(
    writer_semantic_section(c(start_anchor, end_anchor, end_anchor), start_anchor, end_anchor, "fixture"),
    "end anchor must occur exactly once"
  )
  testthat::expect_error(
    writer_semantic_section(c(end_anchor, start_anchor), start_anchor, end_anchor, "fixture"),
    "anchors are reversed"
  )

  inside_mutation <- writer_semantic_section(
    c("outside source_id = 3", start_anchor, "inside source_id = 3", "extra source_id = 3", end_anchor, "outside source_id = 3"),
    start_anchor, end_anchor, "fixture"
  )
  outside_mutation <- writer_semantic_section(
    c("outside source_id = 3", "extra source_id = 3", start_anchor, "inside source_id = 3", end_anchor, "outside source_id = 3"),
    start_anchor, end_anchor, "fixture"
  )
  testthat::expect_gt(
    nrow(writer_literal_occurrences(inside_mutation$lines, "fixture", inside_mutation$first_line)),
    nrow(observed)
  )
  testthat::expect_identical(
    writer_final_inventory_key_counts(writer_literal_occurrences(outside_mutation$lines, "fixture", outside_mutation$first_line)),
    writer_final_inventory_key_counts(observed)
  )
})

testthat::test_that("final writer inventory is anchored and multiplicity-sensitive", {
  sections <- list(
    list(path = "schema.sql", start = "-- #153: these are generic primaries. 1939 is a sealed profile, never a", end = "CREATE OR REPLACE FUNCTION public.public_person_bio_source_versions(p_person_ids bigint[])", name = "final-schema"),
    list(path = "db-migrations.sql", start = "-- #153: convert the legacy 1939 journal into the profile-bound v2 writer.", end = "CREATE OR REPLACE FUNCTION private.apply_narrative_record_cutover", name = "final-migration")
  )
  observed_parts <- lapply(sections, function(section) {
    writer_semantic_section_occurrences(section$path, section$start, section$end, section$name)
  })
  observed <- do.call(rbind, observed_parts)
  testthat::expect_identical(
    writer_final_inventory_key_counts(observed),
    writer_final_inventory_key_counts(writer_final_expected_inventory)
  )

  for (index in seq_along(sections)) {
    section <- sections[[index]]
    lines <- readLines(file.path(writer_root, section$path), warn = FALSE)
    extracted <- writer_semantic_section(lines, section$start, section$end, section$name)
    inside <- append(lines, "source_id = 3", after = extracted$first_line)
    outside <- append(lines, "source_id = 3", after = length(lines))
    mutated_inside <- writer_semantic_section(inside, section$start, section$end, section$name)
    mutated_outside <- writer_semantic_section(outside, section$start, section$end, section$name)
    testthat::expect_false(identical(
      writer_final_inventory_key_counts(writer_literal_occurrences(mutated_inside$lines, section$name, mutated_inside$first_line)),
      writer_final_inventory_key_counts(observed_parts[[index]])
    ), info = paste(section$name, "inside mutation"))
    testthat::expect_identical(
      writer_final_inventory_key_counts(writer_literal_occurrences(mutated_outside$lines, section$name, mutated_outside$first_line)),
      writer_final_inventory_key_counts(observed_parts[[index]]),
      info = paste(section$name, "outside mutation")
    )
  }
})

testthat::test_that("#153 coexistence sequence repair is transactional and CI resolves the historical fixture", {
  migration_text <- paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  conversion <- writer_semantic_section(
    strsplit(migration_text, "\n", fixed = TRUE)[[1L]],
    "-- #153: convert the legacy 1939 journal into the profile-bound v2 writer.",
    "CREATE OR REPLACE FUNCTION private.apply_narrative_record_cutover",
    "final-migration"
  )
  conversion_text <- paste(conversion$lines, collapse = "\n")
  ci_text <- paste(readLines(file.path(writer_root, ".github", "workflows", "ci.yml"), warn = FALSE), collapse = "\n")
  testthat::expect_false(grepl("PERFORM setval\\(pg_get_serial_sequence\\('private.reimport_event','id'\\)", conversion_text, perl = TRUE))
  testthat::expect_match(conversion_text, "ALTER SEQUENCE %s RESTART WITH %s", fixed = TRUE)
  testthat::expect_match(ci_text, "fetch-depth: 0", fixed = TRUE)
  testthat::expect_match(ci_text, "git cat-file -e 2d6aabf^{commit}", fixed = TRUE)
  testthat::expect_lt(
    regexpr("git cat-file -e 2d6aabf^{commit}", ci_text, fixed = TRUE)[[1L]],
    regexpr("git show 2d6aabf:schema.sql", ci_text, fixed = TRUE)[[1L]]
  )
})

testthat::test_that("generic reimport writer owns every formerly 1939-specific literal", {
  testthat::expect_identical(names(writer_expected_inventory), c("literal", "classification", "generic_target", "test_name"))
  testthat::expect_true(all(writer_expected_inventory$classification %in% c("generic_invariant", "profile", "manifest", "legacy_wrapper")))
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

testthat::test_that("writer profile identity is one sealed configuration per source/profile key", {
  schema_text <- paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n")
  migration_text <- paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  for (source_text in list(schema_text, migration_text)) {
    testthat::expect_match(source_text, "PRIMARY KEY(source_id,profile_id)", fixed = TRUE)
    testthat::expect_match(source_text, "profile_sha256=private.reimport_canonical_json_sha256(writer_config)", fixed = TRUE)
    testthat::expect_match(source_text, "REIMPORT_WRITER_PROFILE_HASH_INVALID", fixed = TRUE)
  }
})

testthat::test_that("generic replay is bound to the authorized counts and exact element set", {
  for (source_text in list(
    paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n"),
    paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  )) {
    result <- extract_public_function(source_text, "red_reimport_batch_result")
    testthat::expect_match(source_text, "REIMPORT_WRITER_REPLAY_DRIFT", fixed = TRUE)
    testthat::expect_match(source_text, "v_replay_auth.authorized_elements", fixed = TRUE)
    testthat::expect_match(result, "jsonb_object_keys", fixed = TRUE)
    testthat::expect_match(result, "REIMPORT_WRITER_BATCH_RESULT_INVALID", fixed = TRUE)
  }
})

testthat::test_that("every generic writer lifecycle locks its source/profile after the v2 gate", {
  sources <- list(
    schema = paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n"),
    migration = paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  )
  lifecycles <- c(
    "red_authorize_reimport", "red_preflight_reimport_authorization",
    "red_begin_reimport", "red_apply_reimport_source_evidence",
    "red_apply_reimport_person_create", "red_finalize_reimport",
    "red_authorize_reimport_reversal", "red_reverse_reimport",
    "red_authorize_reimport_cutover", "red_activate_reimport_batch",
    "red_authorize_reimport_name_completion", "red_preflight_reimport_name_completion",
    "red_begin_reimport_name_completion", "red_apply_reimport_name_completion",
    "red_finalize_reimport_name_completion"
  )
  for (source_text in sources) {
    testthat::expect_match(source_text,
      "CREATE(?: OR REPLACE)? FUNCTION private\\.lock_reimport_writer\\(p_source_id bigint,p_profile_id text\\)",
      perl = TRUE)
    for (lifecycle in lifecycles) {
      definition <- extract_final_public_function(source_text, lifecycle)
      testthat::expect_true(nzchar(definition), info = lifecycle)
      gate <- regexpr("REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED", definition, fixed = TRUE)
      writer_lock <- regexpr("private.lock_reimport_writer", definition, fixed = TRUE)
      testthat::expect_true(gate[[1L]] > 0L && writer_lock[[1L]] > gate[[1L]], info = lifecycle)
    }
  }
})

testthat::test_that("fresh preflight drops PUBLIC execute before the next function is created", {
  schema_text <- paste(readLines(file.path(writer_root, "schema.sql"), warn = FALSE), collapse = "\n")
  start <- regexpr(
    "CREATE FUNCTION public.red_preflight_reimport_authorization",
    schema_text, fixed = TRUE
  )[[1L]]
  next_function <- regexpr(
    "CREATE FUNCTION public.red_begin_reimport",
    schema_text, fixed = TRUE
  )[[1L]]
  testthat::expect_gt(start, 0L)
  testthat::expect_gt(next_function, start)
  immediate_contract <- substr(schema_text, start, next_function - 1L)
  testthat::expect_match(
    immediate_contract,
    "REVOKE ALL ON FUNCTION public.red_preflight_reimport_authorization(uuid,text,text)",
    fixed = TRUE
  )
  testthat::expect_match(
    immediate_contract,
    "GRANT EXECUTE ON FUNCTION public.red_preflight_reimport_authorization(uuid,text,text)",
    fixed = TRUE
  )
})

testthat::test_that("upgrade guard permits only exact terminal children and an empty legacy ledger", {
  migration_text <- paste(readLines(file.path(writer_root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  empty_fixture <- paste(readLines(file.path(writer_root, "tests", "sql", "reimport-writer-legacy-empty-fixture.sql"), warn = FALSE), collapse = "\n")
  invalid_fixture <- paste(readLines(file.path(writer_root, "tests", "sql", "reimport-writer-legacy-invalid-terminal-fixture.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_match(migration_text, "a.operation='reimport' AND b.status='finalized'", fixed = TRUE)
  testthat::expect_match(migration_text, "REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED", fixed = TRUE)
  testthat::expect_match(migration_text, "IF v_source_count<>0", fixed = TRUE)
  testthat::expect_match(migration_text, "REIMPORT_WRITER_LEGACY_SOURCE_IDENTITY_INVALID", fixed = TRUE)
  testthat::expect_match(empty_fixture, "REIMPORT_WRITER_LEGACY_EMPTY_FIXTURE_INVALID", fixed = TRUE)
  testthat::expect_match(invalid_fixture, "identity_wrong_source", fixed = TRUE)
  testthat::expect_match(invalid_fixture, "identity_multi_source", fixed = TRUE)
})

testthat::test_that("catalog parity includes effective function bodies and both terminal-child fixtures", {
  receipt <- paste(readLines(file.path(writer_root, "tests", "sql", "inspect-reimport-writer-catalog.sql"), warn = FALSE), collapse = "\n")
  migration_fixture <- paste(readLines(file.path(writer_root, "tests", "sql", "test-reimport-writer-migration.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_match(receipt, "pg_get_functiondef", fixed = TRUE)
  testthat::expect_match(receipt, "encode(extensions.digest", fixed = TRUE)
  testthat::expect_match(receipt, "row_value::text COLLATE \"C\"", fixed = TRUE)
  testthat::expect_match(migration_fixture, "operation='name_completion'", fixed = TRUE)
  testthat::expect_match(migration_fixture, "status='finalized'", fixed = TRUE)
  testthat::expect_match(migration_fixture, "source_batch.status='activated'", fixed = TRUE)
  testthat::expect_match(migration_fixture, "source_batch.status='reversed'", fixed = TRUE)
  testthat::expect_match(migration_fixture, "jsonb_build_object('source_batch_id',source_batch.id::text)", fixed = TRUE)
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

testthat::test_that("edition-named reimport surface is a closed, generic-free catalog", {
  verify_text <- paste(readLines(file.path(writer_root, "db-verify.sql"), warn = FALSE), collapse = "\n")
  catalog_test <- paste(readLines(file.path(writer_root, "tests", "sql", "test-reimport-edition-catalog.sql"), warn = FALSE), collapse = "\n")
  ci_text <- paste(readLines(file.path(writer_root, ".github", "workflows", "ci.yml"), warn = FALSE), collapse = "\n")
  expected_surface <- c(
    "reimport_1939_authorization", "reimport_1939_write_batch", "reimport_1939_write_event", "reimport_1939_name_completion_result",
    "red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamp with time zone)",
    "red_begin_1939_v50_reimport(uuid,text,text)", "red_apply_1939_v50_source_evidence(uuid,text,jsonb)",
    "red_apply_1939_v50_person_create(uuid,text,jsonb)", "red_apply_1939_v50_canonical_delta(uuid,text,jsonb)",
    "red_finalize_1939_v50_reimport(uuid)", "red_authorize_1939_v50_reversal(uuid,uuid,timestamp with time zone)",
    "red_reverse_1939_v50_reimport(uuid,uuid)", "red_authorize_1939_v50_cutover(uuid,uuid,timestamp with time zone)",
    "red_activate_1939_v50_batch(uuid,uuid)", "red_lock_1939_v50_name_completion(text)",
    "red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)",
    "red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)", "red_begin_1939_v50_name_completion(uuid,text,uuid)",
    "red_apply_1939_v50_name_completion(uuid,text,jsonb)", "red_finalize_1939_v50_name_completion(uuid)"
  )
  catalog_start <- regexpr("WITH expected\\(object_kind,object_schema,object_name,parent_identity\\) AS \\(", verify_text, perl = TRUE)
  testthat::expect_true(catalog_start[[1L]] > 0L)
  catalog_allowlist <- substring(verify_text, catalog_start[[1L]])
  catalog_end <- regexpr("\\), actual\\(object_kind,object_schema,object_name,parent_identity\\) AS", catalog_allowlist, perl = TRUE)
  testthat::expect_true(catalog_end[[1L]] > 0L)
  catalog_allowlist <- substring(catalog_allowlist, 1L, catalog_end[[1L]] - 1L)
  testthat::expect_match(verify_text, "CREATE OR REPLACE FUNCTION private.assert_reimport_edition_catalog", fixed = TRUE)
  testthat::expect_match(verify_text, "REIMPORT_EDITION_OBJECT_ALLOWLIST_DRIFT", fixed = TRUE)
  testthat::expect_true(all(vapply(expected_surface, function(item) grepl(item, catalog_allowlist, fixed = TRUE), logical(1))))
  testthat::expect_false(grepl("red_reimport_batch_result\\(uuid,uuid\\)", catalog_allowlist, perl = TRUE))
  for (kind in c("FUNCTION", "RELATION", "TYPE", "CONSTRAINT", "POLICY", "OWNED_SEQUENCE", "INDEX", "TRIGGER")) {
    testthat::expect_match(catalog_test, sprintf("task6_expect_catalog_drift('%s')", kind), fixed = TRUE)
  }
  testthat::expect_match(ci_text, "test-reimport-edition-catalog.sql", fixed = TRUE)
})
