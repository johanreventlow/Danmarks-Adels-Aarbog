writer_root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
`%||%` <- function(value, fallback) if (is.null(value)) fallback else value

writer_literal_rules <- data.frame(
  literal = c("integer_3", "equals_8", "not_equals_8", "citation_label", "run_key", "name_completion_lock"),
  pattern = c("\\b3\\b", "=8", "<>8", "DAA 1939 side", "reimport-1939-v50:", "daa-1939-v50-name-completion"),
  stringsAsFactors = FALSE
)

writer_literal_occurrences <- function(lines, segment_name, first_line = 1L) {
  context_name <- "top_level"
  function_instances <- list()
  literal_ordinals <- list()
  observed <- list()
  body_delimiter <- NULL
  for (index in seq_along(lines)) {
    function_match <- regexec("^\\s*CREATE(?: OR REPLACE)? FUNCTION ([[:alnum:]_.]+)", lines[[index]], perl = TRUE)
    captures <- regmatches(lines[[index]], function_match)[[1L]]
    if (length(captures) > 1L) {
      if (!identical(context_name, "top_level")) stop("nested writer function declaration", call. = FALSE)
      base <- captures[[2L]]
      function_instances[[base]] <- (function_instances[[base]] %||% 0L) + 1L
      context_name <- sprintf("%s#%d", base, function_instances[[base]])
      body_delimiter <- NULL
    }
    for (rule_index in seq_len(nrow(writer_literal_rules))) {
      rule <- writer_literal_rules[rule_index, ]; matches <- gregexpr(rule$pattern, lines[[index]], perl = TRUE)[[1L]]
      if (matches[[1L]] == -1L) next
      ordinal_key <- paste(context_name, rule$literal, sep = "|")
      for (ignored in matches) {
        literal_ordinals[[ordinal_key]] <- (literal_ordinals[[ordinal_key]] %||% 0L) + 1L
        observed[[length(observed) + 1L]] <- data.frame(literal = rule$literal, test_name = sprintf("%s/%s/%s/%03d", segment_name, context_name, rule$literal, literal_ordinals[[ordinal_key]]), line = first_line + index - 1L, stringsAsFactors = FALSE)
      }
    }

    if (!identical(context_name, "top_level")) {
      opened_here <- FALSE
      if (is.null(body_delimiter)) {
        delimiter_match <- regexec("\\bAS\\s+(\\$[[:alnum:]_]*\\$)", lines[[index]], perl = TRUE)
        delimiter_captures <- regmatches(lines[[index]], delimiter_match)[[1L]]
        if (length(delimiter_captures) > 1L) {
          body_delimiter <- delimiter_captures[[2L]]
          opened_here <- TRUE
        }
      }
      if (!is.null(body_delimiter)) {
        delimiter_positions <- gregexpr(body_delimiter, lines[[index]], fixed = TRUE)[[1L]]
        delimiter_count <- if (delimiter_positions[[1L]] == -1L) 0L else length(delimiter_positions)
        if ((!opened_here && delimiter_count >= 1L) || (opened_here && delimiter_count >= 2L)) {
          context_name <- "top_level"
          body_delimiter <- NULL
        }
      }
    }
  }
  if (!identical(context_name, "top_level")) stop("unterminated writer function", call. = FALSE)
  do.call(rbind, observed)
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
integer_3|profile|source_id|final-schema/top_level/integer_3/001
citation_label|profile|citation_label_template|final-schema/top_level/citation_label/001
run_key|profile|run_key_prefix|final-schema/top_level/run_key/001
integer_3|profile|source_id|final-schema/top_level/integer_3/002
integer_3|generic_invariant|expected_counts_key_arity|final-schema/private.validate_reimport_authorization_payload#1/integer_3/001
integer_3|generic_invariant|expected_counts_key_arity|final-schema/public.red_reimport_batch_result#1/integer_3/001
integer_3|legacy_wrapper|legacy_expected_count_shape|final-schema/public.red_authorize_1939_v50_reimport#1/integer_3/001
integer_3|profile|source_id|final-schema/public.red_authorize_1939_v50_reimport#1/integer_3/002
integer_3|profile|source_id|final-schema/public.red_authorize_1939_v50_reimport#1/integer_3/003
integer_3|profile|source_id|final-schema/public.red_lock_1939_v50_name_completion#1/integer_3/001
integer_3|profile|source_id|final-schema/public.red_authorize_1939_v50_name_completion#1/integer_3/001
integer_3|profile|source_id|final-schema/public.red_authorize_1939_v50_name_completion#1/integer_3/002
integer_3|generic_invariant|comment_spec_section|final-schema/top_level/integer_3/003
integer_3|profile|source_id|final-schema/top_level/integer_3/004
citation_label|profile|citation_label_template|final-schema/top_level/citation_label/002
integer_3|profile|source_id|final-schema/top_level/integer_3/005
integer_3|profile|source_id|final-schema/top_level/integer_3/006
citation_label|profile|citation_label_template|final-schema/top_level/citation_label/003
integer_3|profile|source_id|final-schema/top_level/integer_3/007
integer_3|profile|source_id|final-schema/top_level/integer_3/008
citation_label|profile|citation_label_template|final-schema/top_level/citation_label/004
integer_3|profile|source_id|final-schema/top_level/integer_3/009
integer_3|generic_invariant|comment_step_number|final-schema/top_level/integer_3/010
integer_3|generic_invariant|comment_step_number|final-schema/top_level/integer_3/011
integer_3|generic_invariant|comment_step_number|final-schema/private.write_source_text_revision#1/integer_3/001
integer_3|profile|source_id|final-migration/top_level/integer_3/001
integer_3|profile|source_id|final-migration/top_level/integer_3/002
citation_label|profile|citation_label_template|final-migration/top_level/citation_label/001
run_key|profile|run_key_prefix|final-migration/top_level/run_key/001
integer_3|profile|source_id|final-migration/top_level/integer_3/003
integer_3|generic_invariant|profile_foreign_key_arity|final-migration/top_level/integer_3/004
integer_3|generic_invariant|profile_foreign_key_arity|final-migration/top_level/integer_3/005
integer_3|profile|source_id|final-migration/top_level/integer_3/006
integer_3|profile|source_id|final-migration/top_level/integer_3/007
integer_3|profile|source_id|final-migration/top_level/integer_3/008
integer_3|legacy_wrapper|legacy_expected_count_shape|final-migration/public.red_authorize_1939_v50_reimport#1/integer_3/001
integer_3|profile|source_id|final-migration/public.red_authorize_1939_v50_reimport#1/integer_3/002
integer_3|profile|source_id|final-migration/public.red_authorize_1939_v50_reimport#1/integer_3/003
integer_3|profile|source_id|final-migration/public.red_lock_1939_v50_name_completion#2/integer_3/001
integer_3|profile|source_id|final-migration/public.red_authorize_1939_v50_name_completion#2/integer_3/001
integer_3|profile|source_id|final-migration/public.red_authorize_1939_v50_name_completion#2/integer_3/002
", sep = "|", col.names = c("literal", "classification", "generic_target", "test_name"), comment.char = "", stringsAsFactors = FALSE)

writer_inventory_detection_counts <- function(inventory) {
  key_columns <- c("literal", "test_name")
  keys <- do.call(paste, c(inventory[key_columns], sep = "|"))
  table(keys)
}

writer_validate_ci_history_contract <- function(workflow) {
  full_history <- list()
  for (job_name in names(workflow$jobs)) {
    steps <- workflow$jobs[[job_name]]$steps %||% list()
    for (step_index in seq_along(steps)) {
      step <- steps[[step_index]]
      if (step$uses %||% "" %in% c("actions/checkout@v4", "actions/checkout@11d5960a326750d5838078e36cf38b85af677262") &&
          identical(as.integer(step$with[["fetch-depth"]] %||% NA_integer_), 0L)) {
        full_history[[length(full_history) + 1L]] <- list(job = job_name, step = step_index)
      }
    }
  }
  if (length(full_history) != 1L) stop("expected exactly one full-history checkout", call. = FALSE)
  if (!identical(full_history[[1L]]$job, "writer-1939-v50-db")) {
    stop("full-history checkout must belong to writer-1939-v50-db", call. = FALSE)
  }

  migration_steps <- workflow$jobs[["writer-1939-v50-db"]]$steps %||% list()
  matching_steps <- which(vapply(
    migration_steps,
    function(step) identical(step$name %||% "", "Reimport writer migration from pre-153 ledger"),
    logical(1)
  ))
  if (length(matching_steps) != 1L) stop("expected exactly one historical migration step", call. = FALSE)
  run <- migration_steps[[matching_steps]]$run %||% ""
  cat_file <- regexpr("git cat-file -e 2d6aabf^{commit}", run, fixed = TRUE)[[1L]]
  git_shows <- gregexpr("git show ", run, fixed = TRUE)[[1L]]
  if (cat_file < 1L || git_shows[[1L]] < 1L || cat_file >= min(git_shows)) {
    stop("cat-file must precede the first historical git show in the migration step", call. = FALSE)
  }
  invisible(TRUE)
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

testthat::test_that("semantic writer-section anchors are unique, ordered, and scope literals", {
  start_anchor <- "-- WRITER START"
  end_anchor <- "-- WRITER END"
  fixture <- c("outside source_id = 3", start_anchor, "inside source_id = 3", end_anchor, "outside source_id = 3")
  section <- writer_semantic_section(fixture, start_anchor, end_anchor, "fixture")
  observed <- writer_literal_occurrences(section$lines, "fixture", section$first_line)
  testthat::expect_equal(nrow(observed), 1L)
  testthat::expect_identical(observed$literal, "integer_3")
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
    writer_inventory_detection_counts(writer_literal_occurrences(outside_mutation$lines, "fixture", outside_mutation$first_line)),
    writer_inventory_detection_counts(observed)
  )
})

testthat::test_that("literal detection covers source-id SQL forms and resets function context", {
  fixture <- c(
    "CREATE FUNCTION private.fixture() RETURNS void LANGUAGE plpgsql AS $$",
    "BEGIN PERFORM source_id = 3; END",
    "$$;",
    "SELECT 3,'daa-1939-v50-production-write-v1';",
    "WHERE EXISTS(SELECT 1 FROM public.source WHERE id=3);",
    "PERFORM public.red_lock_reimport_name_completion(m,3,'daa-1939-v50-production-write-v1');"
  )
  observed <- writer_literal_occurrences(fixture, "fixture")
  testthat::expect_equal(sum(observed$literal == "integer_3"), 4L)
  testthat::expect_true(any(grepl("fixture/private.fixture#1/integer_3/001", observed$test_name, fixed = TRUE)))
  testthat::expect_equal(sum(grepl("fixture/top_level/integer_3/", observed$test_name, fixed = TRUE)), 3L)

  top_level <- writer_literal_occurrences(c(
    "source_id = 3;",
    "CREATE FUNCTION private.fixture() RETURNS void LANGUAGE plpgsql AS $$ BEGIN NULL; END $$;"
  ), "movement")
  inside_function <- writer_literal_occurrences(c(
    "CREATE FUNCTION private.fixture() RETURNS void LANGUAGE plpgsql AS $$ BEGIN source_id = 3; END $$;"
  ), "movement")
  testthat::expect_false(identical(
    writer_inventory_detection_counts(top_level),
    writer_inventory_detection_counts(inside_function)
  ))
})

testthat::test_that("CI history contract is bound to exactly the migration job and step", {
  workflow <- yaml::read_yaml(file.path(writer_root, ".github", "workflows", "ci.yml"))
  testthat::expect_silent(writer_validate_ci_history_contract(workflow))

  extra_history <- workflow
  # Et navngivet job med checkout som første trin; jobs[[1L]] er changes-filteret uden checkout.
  extra_history$jobs[["node"]]$steps[[1L]]$with <- list(`fetch-depth` = 0L)
  testthat::expect_error(writer_validate_ci_history_contract(extra_history), "exactly one full-history checkout")

  reordered <- workflow
  migration_steps <- reordered$jobs[["writer-1939-v50-db"]]$steps
  migration_index <- which(vapply(migration_steps, function(step) identical(step$name %||% "", "Reimport writer migration from pre-153 ledger"), logical(1)))
  migration_steps[[migration_index]]$run <- sub(
    "git cat-file -e 2d6aabf\\^\\{commit\\}\\n",
    "",
    migration_steps[[migration_index]]$run
  )
  reordered$jobs[["writer-1939-v50-db"]]$steps <- migration_steps
  testthat::expect_error(writer_validate_ci_history_contract(reordered), "precede the first historical git show")
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
    writer_inventory_detection_counts(observed),
    writer_inventory_detection_counts(writer_final_expected_inventory)
  )

  for (index in seq_along(sections)) {
    section <- sections[[index]]
    lines <- readLines(file.path(writer_root, section$path), warn = FALSE)
    extracted <- writer_semantic_section(lines, section$start, section$end, section$name)
    for (mutation in c(
      "source_id = 3",
      "SELECT 3,'daa-1939-v50-production-write-v1';",
      "PERFORM public.red_lock_reimport_name_completion(m,3,'daa-1939-v50-production-write-v1');"
    )) {
      inside <- append(lines, mutation, after = extracted$first_line)
      outside <- append(lines, mutation, after = length(lines))
      mutated_inside <- writer_semantic_section(inside, section$start, section$end, section$name)
      mutated_outside <- writer_semantic_section(outside, section$start, section$end, section$name)
      testthat::expect_false(identical(
        writer_inventory_detection_counts(writer_literal_occurrences(mutated_inside$lines, section$name, mutated_inside$first_line)),
        writer_inventory_detection_counts(observed_parts[[index]])
      ), info = paste(section$name, "inside mutation", mutation))
      testthat::expect_identical(
        writer_inventory_detection_counts(writer_literal_occurrences(mutated_outside$lines, section$name, mutated_outside$first_line)),
        writer_inventory_detection_counts(observed_parts[[index]]),
        info = paste(section$name, "outside mutation", mutation)
      )
    }
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
  testthat::expect_false(grepl("PERFORM setval\\(pg_get_serial_sequence\\('private.reimport_event','id'\\)", conversion_text, perl = TRUE))
  testthat::expect_match(conversion_text, "ALTER SEQUENCE %s RESTART WITH %s", fixed = TRUE)
})

testthat::test_that("generic reimport writer owns every formerly 1939-specific literal", {
  testthat::expect_identical(names(writer_final_expected_inventory), c("literal", "classification", "generic_target", "test_name"))
  testthat::expect_true(all(writer_final_expected_inventory$classification %in% c("generic_invariant", "profile", "manifest", "legacy_wrapper")))
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
  # #153/#149a: a finalized reimport batch that created no person is terminal,
  # so the guard exempts exactly that shape.  Pin both sides of the exemption.
  source_evidence_fixture <- paste(readLines(file.path(writer_root, "tests", "sql", "reimport-writer-legacy-source-evidence-fixture.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_match(migration_text, "v_terminal_source_evidence_ids", fixed = TRUE)
  testthat::expect_match(migration_text, "b.expected_counts->>'person_creates'='0'", fixed = TRUE)
  testthat::expect_match(migration_text, "a.expected_counts IS NOT DISTINCT FROM b.expected_counts", fixed = TRUE)
  testthat::expect_match(source_evidence_fixture, "'source_evidence'", fixed = TRUE)
  testthat::expect_match(invalid_fixture, "finalized_person_creates", fixed = TRUE)
  testthat::expect_match(invalid_fixture, "finalized_count_mismatch", fixed = TRUE)
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
