root <- normalizePath(getwd())
while (!file.exists(file.path(root, ".git")) && dirname(root) != root) root <- dirname(root)
helpers <- file.path(
  root, ".claude", "skills", "daa-extract", "scripts",
  "preview_reimport_1939_v50_helpers.R"
)
source(helpers)

preview_fixture <- function() {
  list(
    schema_version = "1939-v50-import-preview-v1",
    generator_version = "prepare_reimport_1939_v50.py:v1",
    source = list(
      edition = "1939", source_id = "1939", rendition_id = "rendition",
      input_hashes = as.list(setNames(rep(paste(rep("a", 64L), collapse = ""), 6L),
        c("calamari_sha256", "clean_sha256", "ledger_sha256",
          "materialization_sha256", "reconciliation_report_sha256",
          "reconciliation_sha256")))
    ),
    canonical_mutations_authorized = FALSE,
    counts = list(
      mapped_existing = 1L, retired_legacy = 1L,
      genuinely_new_pending = 1L, source_only_structural = 1L,
      source_only_cross_reference = 1L, source_records = 4L,
      facts = list(source_bound_literal = 1L, missing_provenance = 1L,
        nonliteral_provenance = 1L, retired_source_record = 0L),
      marriages = list(source_bound_literal = 1L, missing_provenance = 0L,
        nonliteral_provenance = 0L, retired_source_record = 0L),
      narratives = list(changed = 1L, unchanged = 0L, retired = 1L),
      relationships = list(legacy_structure_pending_revalidation = 1L)
    ),
    source_records = list(
      list(new_record_key = "new-a", acceptance_id = "accept-a",
        record_kind = "unclassified", disposition = "unchanged",
        source_span = list(char_from = 0L, char_to = 10L), verbatim_text = "Anna ny",
        baseline_record_keys = list("old-a"), person_creation = "requires_existing_anchor"),
      list(new_record_key = "new-b", acceptance_id = "accept-b",
        record_kind = "unclassified", disposition = "accepted_genuinely_new_source_record",
        source_span = list(char_from = 10L, char_to = 20L), verbatim_text = "Bent ny",
        baseline_record_keys = list(), person_creation = "forbidden"),
      list(new_record_key = "new-s", acceptance_id = "accept-s",
        record_kind = "structural_context", disposition = "accepted_structural_context",
        source_span = list(char_from = 20L, char_to = 30L), verbatim_text = "struktur",
        baseline_record_keys = list(), person_creation = "forbidden"),
      list(new_record_key = "new-x", acceptance_id = "accept-x",
        record_kind = "cross_reference", disposition = "accepted_cross_reference",
        source_span = list(char_from = 30L, char_to = 40L), verbatim_text = "se nr",
        baseline_record_keys = list(), person_creation = "forbidden")
    ),
    mapped_existing = list(list(
      baseline_record_key = "old-a", new_record_key = "new-a", legacy_name = "Anna",
      narrative_change = list(legacy_sha256 = paste(rep("b", 64L), collapse = ""),
        source_sha256 = paste(rep("c", 64L), collapse = ""), changed = TRUE,
        authorized = FALSE),
      fact_candidates = list(list(legacy_payload = list(faktatype = "fødsel"),
        provenance_status = "source_bound_literal", authorized = FALSE)),
      marriage_candidates = list(list(legacy_payload = list(partner_navn = "Else"),
        provenance_status = "source_bound_literal", authorized = FALSE)),
      relationship_candidates = list(list(kind = "children_reference",
        legacy_payload = list(nr_range = list(2L, 3L)),
        provenance_status = "legacy_structure_pending_revalidation", authorized = FALSE))
    )),
    retired_legacy = list(list(
      baseline_record_key = "old-retired", disposition = "retired_fragment",
      canonical_baseline_record_key = "old-a", retirement_reason = "fragment",
      fact_candidates = list(), marriage_candidates = list(), authorized = FALSE
    )),
    genuinely_new_pending = list(list(new_record_key = "new-b",
      source_span = list(char_from = 10L, char_to = 20L), verbatim_text = "Bent ny",
      person_creation = "forbidden", pending_gates = list(
        "source_persona", "identity", "interpretation_provenance"))),
    source_only_records = list(
      list(new_record_key = "new-s", classification = "source_only_structural",
        person_creation = "forbidden"),
      list(new_record_key = "new-x", classification = "source_only_cross_reference",
        person_creation = "forbidden")
    ),
    expected_database_changes = list(
      source_record_candidates = list("new-a", "new-b", "new-s", "new-x"),
      legacy_retirement_candidates = list("old-retired"),
      canonical_person_creates = list(), canonical_person_updates = list(),
      canonical_person_deletes = list(), authorized = FALSE
    ),
    preview_gate = "GO", reimport_gate = "NO-GO",
    reimport_blockers = list("database_comparison_pending")
  )
}

source_persona_fixture <- function() {
  list(
    schema_version = "1939-v50-source-persona-materialization-v1",
    generator_version = "materialize_source_personas_1939_v50.py:v1",
    source = list(
      edition = "1939", logical_source_id = "1939", database_source_id = 7L,
      input_hashes = list(
        database_preview_sha256 = paste(rep("b", 64L), collapse = ""),
        identity_decision_sha256s = list(paste(rep("c", 64L), collapse = "")),
        import_preview_sha256 = paste(rep("d", 64L), collapse = "")
      )
    ),
    canonical_mutations_authorized = FALSE,
    database_write_authorized = FALSE,
    counts = list(
      approved_identity_decisions = 1L, source_personas = 1L,
      accepted_identities = 1L, remaining_genuinely_new_pending = 0L
    ),
    source_personas = list(list(
      source_persona_id = "89d4ecfb-3408-5c38-8ce4-1af1b8a21157",
      persona_key = "1939:new-b", source_id = 7L,
      source_record_key = "new-b",
      source_span = list(char_from = 10L, char_to = 20L),
      verbatim_text = "Bent ny", target_record_key = "old-a",
      canonical_person_id = 101L, identity_status = "accepted",
      identity_decision = list(
        decision_batch = "batch-1",
        decision_batch_sha256 = paste(rep("c", 64L), collapse = ""),
        candidate_evidence_sha256 = paste(rep("f", 64L), collapse = ""),
        confirmation = "ja", reviewed_by = "codex-assisted:johan-reventlow"
      ),
      database_write_authorized = FALSE
    )),
    remaining_genuinely_new_pending = list(),
    expected_database_changes = list(
      source_persona_candidates = list("89d4ecfb-3408-5c38-8ce4-1af1b8a21157"),
      source_persona_identity_candidates = list("89d4ecfb-3408-5c38-8ce4-1af1b8a21157"),
      canonical_person_creates = list(), canonical_person_updates = list(),
      canonical_person_deletes = list(), authorized = FALSE
    ),
    source_persona_materialization_gate = "GO",
    database_write_gate = "NO-GO", reimport_gate = "NO-GO"
  )
}

fixture_sha <- function(char) paste(rep(char, 64L), collapse = "")

fake_database <- function() {
  calls <- list()
  execute <- function(sql, params = list()) {
    calls[[length(calls) + 1L]] <<- list(kind = "execute", sql = sql, params = params)
    invisible(0L)
  }
  query <- function(sql, params = list()) {
    calls[[length(calls) + 1L]] <<- list(kind = "query", sql = sql, params = params)
    if (grepl("SHOW transaction_read_only", sql, fixed = TRUE)) {
      return(data.frame(transaction_read_only = "on"))
    }
    if (grepl("current_database", sql, fixed = TRUE)) {
      return(data.frame(database_name = "postgres", server_version = "17.4",
        server_version_num = "170004"))
    }
    if (grepl("information_schema.columns", sql, fixed = TRUE)) {
      required <- required_database_columns()
      return(do.call(rbind, lapply(names(required), function(table) {
        bits <- strsplit(table, "\\.", fixed = FALSE)[[1L]]
        data.frame(table_schema = bits[[1L]], table_name = bits[[2L]],
          column_name = required[[table]])
      })))
    }
    if (grepl("FROM public.source", sql, fixed = TRUE)) {
      return(data.frame(id = 7, udgave = "DAA 1939", import_key = "daa:1939"))
    }
    if (grepl("FROM public.person_external_id pei", sql, fixed = TRUE) &&
        grepl("JOIN public.person p", sql, fixed = TRUE)) {
      return(data.frame(person_id = c(101, 102), record_key = c("old-a", "db-only"),
        linje = c("I", "I"), nr = c(1L, 2L), staged = c(FALSE, FALSE),
        visning_navn = c("Anna", "Database-only")))
    }
    if (grepl("FROM public.narrative n", sql, fixed = TRUE)) {
      return(data.frame(id = 201, person_id = 101, record_key = "old-a",
        tekst = "Anna gammel", privat = FALSE, editorial_events = 1L))
    }
    if (grepl("FROM public.fact f", sql, fixed = TRUE)) {
      return(data.frame(id = c(301, 302), person_id = c(101, 101),
        record_key = c("old-a", "old-a"), faktatype = c("navn", "fødsel"),
        editorial_events = c(0L, 1L), source_citations = c(1L, 0L)))
    }
    if (grepl("FROM public.relation r", sql, fixed = TRUE)) {
      return(data.frame(id = 401, rolle = "ejer", editorial_events = 0L,
        source_citations = 0L))
    }
    if (grepl("FROM public.family_member fm", sql, fixed = TRUE)) {
      return(data.frame(family_id = 501, person_id = 101, rolle = "partner",
        editorial_events = 1L))
    }
    if (grepl("FROM private.source_record sr", sql, fixed = TRUE)) {
      return(data.frame(record_key = c("new-a", "old-private"),
        record_kind = c("unclassified", "unclassified")))
    }
    if (grepl("FROM private.source_persona sp", sql, fixed = TRUE)) {
      return(data.frame(source_persona_id = character(), persona_key = character(),
        canonical_person_id = integer(), decision_status = character()))
    }
    stop(paste("uventet fake-query:", sql))
  }
  list(execute = execute, query = query, calls = function() calls)
}

testthat::test_that("SQL-vagten tillader kun den snævre read-only grammatik", {
  allowed <- c(
    "BEGIN READ ONLY", "SET LOCAL statement_timeout = '30s'",
    "SET LOCAL lock_timeout = '2s'", "SHOW transaction_read_only",
    paste("SELECT current_database() AS database_name,",
      "current_setting('server_version') AS server_version,",
      "current_setting('server_version_num') AS server_version_num"),
    "ROLLBACK"
  )
  for (sql in allowed) testthat::expect_invisible(assert_read_only_sql(sql))

  blocked <- c(
    "UPDATE person SET staged=false", "DELETE FROM fact", "INSERT INTO person VALUES (1)",
    "CREATE TEMP TABLE x(a int)", "COPY person FROM STDIN", "CALL mutate()",
    "SELECT pg_advisory_lock(1)", "SELECT 1; DELETE FROM person", "TRUNCATE person"
  )
  for (sql in blocked) {
    testthat::expect_error(assert_read_only_sql(sql), "DB_PREVIEW_SQL_FORBIDDEN")
  }
})

testthat::test_that("SQL-vagten afviser mutation-capable SELECT-funktioner", {
  attacks <- c(
    "SELECT public.red_set_koen(101, 'mand')",
    "SELECT set_config('search_path', 'evil', false)",
    "SELECT nextval('person_id_seq')",
    "SELECT setval('person_id_seq', 1)",
    "SELECT pg_notify('channel', 'payload')",
    "SELECT pg_advisory_unlock_all()",
    "SELECT dblink_exec('dbname=x', 'DELETE FROM person')",
    "SELECT lo_import('/tmp/secret')",
    paste("WITH mutated AS (SELECT public.red_set_koen(101, 'mand'))",
      "SELECT * FROM mutated"),
    "EXPLAIN SELECT set_config('search_path', 'evil', false)",
    "SELECT pg_catalog.\"set_config\"('search_path', 'evil', false)",
    "SELECT \"nextval\"('person_id_seq')",
    "SELECT pg_catalog.\"pg_notify\"('channel', 'payload')",
    "SELECT public.\"red_set_koen\"(101, 'mand')",
    "SELECT 42 AS harmless",
    "SELECT pg_catalog.current_database()",
    "SELECT current_database() -- registered-looking comment"
  )
  for (sql in attacks) {
    testthat::expect_error(assert_read_only_sql(sql), "DB_PREVIEW_SQL_FORBIDDEN")
  }
})

testthat::test_that("SQL-vagten tillader hele og kun previewets statiske registry", {
  registry <- database_preview_sql_registry()
  testthat::expect_true(length(registry) > 0L)
  testthat::expect_false(anyDuplicated(names(registry)) > 0L)
  for (sql in registry) testthat::expect_invisible(assert_read_only_sql(sql))
})

testthat::test_that("read-only bootstrap sker før alle domænequeries og rollbacker", {
  fake <- fake_database()

  result <- build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939",
    snapshot_at = "2026-08-17T12:00:00Z"
  )

  calls <- fake$calls()
  testthat::expect_identical(calls[[1L]]$sql, "BEGIN READ ONLY")
  testthat::expect_match(calls[[2L]]$sql, "statement_timeout")
  testthat::expect_match(calls[[3L]]$sql, "lock_timeout")
  testthat::expect_identical(calls[[4L]]$sql, "SHOW transaction_read_only")
  testthat::expect_identical(calls[[length(calls)]]$sql, "ROLLBACK")
  testthat::expect_identical(result$database$transaction_read_only, "on")
  testthat::expect_false(result$canonical_mutations_authorized)
  domain_sql <- paste(vapply(Filter(function(call) call$kind == "query", calls),
    function(call) call$sql, character(1L)), collapse = "\n")
  testthat::expect_match(domain_sql, "JOIN public.change_set cs")
  testthat::expect_match(domain_sql, "left\\(cs.operation, 4\\) = 'red_'")
})

testthat::test_that("preview klassificerer anchors, source records og beskyttede rækker", {
  fake <- fake_database()
  result <- build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939",
    snapshot_at = "2026-08-17T12:00:00Z"
  )

  testthat::expect_equal(result$person_anchors$matched_count, 1L)
  testthat::expect_equal(result$person_anchors$missing_count, 0L)
  testthat::expect_equal(result$person_anchors$collision_count, 0L)
  testthat::expect_equal(result$person_anchors$database_only_record_keys, list("db-only"))
  testthat::expect_equal(result$person_anchors$database_only, list(list(
    record_key = "db-only", person_id = 102L, visning_navn = "Database-only",
    staged = FALSE, source_narrative_count = 0L, fact_count = 0L,
    family_member_count = 0L
  )))
  testthat::expect_equal(result$person_anchors$retired_present_count, 0L)
  testthat::expect_equal(result$source_records$insert_count, 3L)
  testthat::expect_equal(result$source_records$existing_count, 1L)
  testthat::expect_equal(result$source_records$database_only_record_keys, list("old-private"))
  testthat::expect_equal(result$source_personas$planned_count, 1L)
  testthat::expect_equal(result$source_personas$remaining_pending_count, 0L)
  testthat::expect_equal(result$source_personas$insert_count, 1L)
  testthat::expect_equal(result$source_personas$existing_count, 0L)
  testthat::expect_equal(result$source_personas$collision_count, 0L)
  testthat::expect_equal(result$narratives$update_candidates, list(list(
    baseline_record_key = "old-a", narrative_id = 201,
    editorial_events = 1L, authorized = FALSE
  )))
  testthat::expect_equal(result$facts$database_existing_count, 2L)
  testthat::expect_equal(result$facts$database_editorial_count, 1L)
  testthat::expect_equal(result$facts$database_source_cited_count, 1L)
  testthat::expect_equal(result$facts$database_provenance_matrix,
    list(source_only = 1L, editorial_only = 1L, both = 0L, neither = 0L))
  testthat::expect_equal(result$relations$database_relation_count, 1L)
  testthat::expect_equal(result$relations$database_family_member_count, 1L)
  testthat::expect_equal(result$relations$database_provenance_matrix,
    list(source_only = 0L, editorial_only = 0L, both = 0L, neither = 1L))
  testthat::expect_equal(result$relations$database_role_counts, list(ejer = 1L))
  testthat::expect_equal(result$expected_database_changes$canonical_person_creates, list())
  testthat::expect_false(result$expected_database_changes$authorized)
  testthat::expect_identical(result$dry_run_gate, "GO")
  testthat::expect_identical(result$reimport_gate, "NO-GO")
  testthat::expect_false("missing_person_anchor:" %in% unlist(result$blockers))
  testthat::expect_true("unmapped_existing_1939_person_records:1" %in%
    unlist(result$blockers))
})

testthat::test_that("forkert database eller source stopper fail-closed", {
  fake <- fake_database()
  testthat::expect_error(build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute,
    expected_database = "wrong", expected_source_edition = "DAA 1939"
  ), "DB_PREVIEW_DATABASE_MISMATCH")
  testthat::expect_identical(tail(fake$calls(), 1L)[[1L]]$sql, "ROLLBACK")

  query <- fake_database()$query
  testthat::expect_error(build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    query, function(...) invisible(0L),
    expected_database = "postgres", expected_source_edition = "ukendt"
  ), "DB_PREVIEW_SOURCE_MISMATCH")
})

testthat::test_that("read-only off og capability drift stopper synligt", {
  fake <- fake_database()
  bad_readonly <- function(sql, params = list()) {
    if (grepl("SHOW transaction_read_only", sql, fixed = TRUE)) {
      return(data.frame(transaction_read_only = "off"))
    }
    fake$query(sql, params)
  }
  testthat::expect_error(build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    bad_readonly, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939"
  ), "DB_PREVIEW_NOT_READ_ONLY")

  fake2 <- fake_database()
  missing_capability <- function(sql, params = list()) {
    if (grepl("information_schema.columns", sql, fixed = TRUE)) {
      return(data.frame(table_schema = "public", table_name = "source", column_name = "id"))
    }
    fake2$query(sql, params)
  }
  testthat::expect_error(build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    missing_capability, fake2$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939"
  ), "DB_PREVIEW_CAPABILITY_BLOCKER")
})

testthat::test_that("manglende privat source-recordlag giver delvis NO-GO rapport", {
  fake <- fake_database()
  public_only <- function(sql, params = list()) {
    if (grepl("information_schema.columns", sql, fixed = TRUE)) {
      required <- required_database_columns()
      required <- required[startsWith(names(required), "public.")]
      return(do.call(rbind, lapply(names(required), function(table) {
        bits <- strsplit(table, "\\.", fixed = FALSE)[[1L]]
        data.frame(table_schema = bits[[1L]], table_name = bits[[2L]],
          column_name = required[[table]])
      })))
    }
    fake$query(sql, params)
  }

  result <- build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    public_only, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939",
    snapshot_at = "2026-08-17T12:00:00Z"
  )

  testthat::expect_false(result$source_records$comparison_available)
  testthat::expect_null(result$source_records$insert_count)
  testthat::expect_equal(result$capabilities$missing,
    list(
      "private.source_persona_identity.canonical_person_id",
      "private.source_persona_identity.decision_status",
      "private.source_persona_identity.source_persona_id",
      "private.source_persona.id", "private.source_persona.persona_key",
      "private.source_persona.source_id", "private.source_record.record_key",
      "private.source_record.record_kind", "private.source_record.source_id"
    ))
  testthat::expect_true("database_capability_blocker:private.source_record" %in%
    unlist(result$blockers))
  testthat::expect_true("database_capability_blocker:private.source_persona" %in%
    unlist(result$blockers))
  testthat::expect_false(result$source_personas$comparison_available)
  testthat::expect_null(result$source_personas$insert_count)
  testthat::expect_identical(result$dry_run_gate, "NO-GO")
  testthat::expect_identical(result$person_anchors$matched_count, 1L)
})

testthat::test_that("previewvalidering afviser canonical autorisation og malformed input", {
  invalid <- preview_fixture()
  invalid$canonical_mutations_authorized <- TRUE
  testthat::expect_error(validate_import_preview(invalid), "DB_PREVIEW_CANONICAL_MUTATION_FORBIDDEN")

  invalid <- preview_fixture()
  invalid$mapped_existing[[1L]]$baseline_record_key <- NULL
  testthat::expect_error(validate_import_preview(invalid), "DB_PREVIEW_INPUT_INVALID")
})

testthat::test_that("source-persona-materialisering valideres fail-closed mod preview og hash", {
  valid <- source_persona_fixture()
  testthat::expect_invisible(validate_source_persona_materialization(
    valid, preview_fixture(), fixture_sha("d"), fixture_sha("e")))

  mutations <- list(
    function(value) { value$source$input_hashes$import_preview_sha256 <- fixture_sha("0"); value },
    function(value) { value$source$logical_source_id <- "1940"; value },
    function(value) { value$counts$source_personas <- 2L; value },
    function(value) { value$source_personas[[1L]]$target_record_key <- ""; value },
    function(value) { value$source_personas[[1L]]$canonical_person_id <- NA_integer_; value },
    function(value) { value$source_personas[[1L]]$source_persona_id <- "not-a-uuid"; value },
    function(value) { value$database_write_authorized <- TRUE; value },
    function(value) { value$source_persona_materialization_gate <- "NO-GO"; value }
  )
  for (mutate in mutations) {
    invalid <- mutate(source_persona_fixture())
    testthat::expect_error(validate_source_persona_materialization(
      invalid, preview_fixture(), fixture_sha("d"), fixture_sha("e")),
      "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
})

testthat::test_that("database-only 1939-record kan vaere et eksplicit identitetsmaal", {
  materialization <- source_persona_fixture()
  materialization$source_personas[[1L]]$target_record_key <- "db-only"
  materialization$source_personas[[1L]]$canonical_person_id <- 102L

  testthat::expect_invisible(validate_source_persona_materialization(
    materialization, preview_fixture(), fixture_sha("d"), fixture_sha("e")))

  fake <- fake_database()
  result <- build_database_preview(
    preview_fixture(), materialization, fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939",
    snapshot_at = "2026-08-17T12:00:00Z"
  )
  testthat::expect_length(result$source_personas$target_mismatches, 0L)
})

testthat::test_that("database-preview outputs er eksklusive og uden credentials", {
  fake <- fake_database()
  result <- build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939",
    snapshot_at = "2026-08-17T12:00:00Z"
  )
  directory <- tempfile("v50-db-preview-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  output <- file.path(directory, "preview.json")
  report <- file.path(directory, "preview.md")

  write_database_preview_outputs(result, output, report)

  parsed <- jsonlite::fromJSON(output, simplifyVector = FALSE)
  testthat::expect_identical(parsed$database$database_name, "postgres")
  text <- paste(readLines(report, warn = FALSE), collapse = "\n")
  testthat::expect_match(text, "read-only")
  testthat::expect_false(grepl("password|postgresql://|supabase_password", text,
    ignore.case = TRUE))
  testthat::expect_error(write_database_preview_outputs(result, output, report),
    "File exists|findes")
})

testthat::test_that("forbindelsesvagten afviser transaction pooler og manglende secrets", {
  testthat::expect_error(validate_preview_connection(
    host = "pooler.example", user = "postgres", password = "secret",
    port = 6543L, database = "postgres"
  ), "DB_PREVIEW_TRANSACTION_POOLER_FORBIDDEN")
  testthat::expect_error(validate_preview_connection(
    host = "", user = "postgres", password = "secret",
    port = 5432L, database = "postgres"
  ), "DB_PREVIEW_CREDENTIALS_MISSING")
  testthat::expect_invisible(validate_preview_connection(
    host = "db.example", user = "postgres", password = "secret",
    port = 5432L, database = "postgres"
  ))
})

preview_v2_fixture <- function() {
  value <- preview_fixture()
  pending <- lapply(seq_len(41L), function(index) {
    key <- sprintf("new-p%02d", index)
    text <- sprintf("Persontekst %02d", index)
    list(
      new_record_key = key,
      source_span = list(char_from = index * 100L, char_to = index * 100L + nchar(text)),
      verbatim_text = text,
      person_creation = "forbidden",
      pending_gates = list("source_persona", "identity", "interpretation_provenance")
    )
  })
  value$genuinely_new_pending <- pending
  value$source_records <- c(
    value$source_records[c(1L, 3L, 4L)],
    lapply(pending, function(row) list(
      new_record_key = row$new_record_key,
      acceptance_id = paste0("accept-", row$new_record_key),
      record_kind = "unclassified",
      disposition = "accepted_genuinely_new_source_record",
      source_span = row$source_span,
      verbatim_text = row$verbatim_text,
      baseline_record_keys = list(),
      person_creation = "forbidden"
    ))
  )
  value$counts$genuinely_new_pending <- 41L
  value$counts$source_records <- 44L
  value
}

source_persona_v2_fixture <- function() {
  preview <- preview_v2_fixture()
  pending <- setNames(preview$genuinely_new_pending,
    vapply(preview$genuinely_new_pending, function(row) row$new_record_key, character(1L)))
  personas <- lapply(seq_len(32L), function(index) {
    source_key <- sprintf("new-p%02d", index)
    pending_row <- pending[[source_key]]
    identity <- if (index <= 24L) {
      list(
        decision_batch = "batch-v1",
        decision_batch_sha256 = fixture_sha("4"),
        candidate_evidence_sha256 = fixture_sha("5"),
        confirmation = "ja",
        reviewed_by = "test-reviewer"
      )
    } else {
      value <- list(
        decision = "same_existing_person",
        decision_artifact_sha256 = fixture_sha("2"),
        review_sha256 = fixture_sha("6"),
        proposal_evidence_sha256 = fixture_sha("7"),
        reviewed_by = "test-reviewer",
        decision_basis = "complete_fixture_evidence",
        reason = "fixture_target_agrees",
        review_status = "codex_verified"
      )
      if (index %in% c(29L, 31L)) {
        value$competing_target_record_key <- sprintf("competing-%02d", index)
        value$competing_canonical_person_id <- 1000L + index
        value$resolution_basis <-
          "explicit_user_instruction_prefer_later_full_person_over_summary_duplicate"
      }
      value
    }
    list(
      source_persona_id = sprintf("%08x-0000-5000-8000-%012d", index, index),
      persona_key = paste0("1939:", source_key),
      source_id = 7L,
      source_record_key = source_key,
      source_span = pending_row$source_span,
      verbatim_text = pending_row$verbatim_text,
      target_record_key = if (index == 1L) "old-a" else sprintf("db-target-%02d", index),
      canonical_person_id = 100L + index,
      identity_status = "accepted",
      identity_decision = identity,
      database_write_authorized = FALSE
    )
  })
  decision_row <- function(index, decision, owner = NULL) {
    source_key <- sprintf("new-p%02d", index)
    pending_row <- pending[[source_key]]
    row <- list(
      source_record_key = source_key,
      source_span = pending_row$source_span,
      verbatim_sha256 = digest::digest(charToRaw(enc2utf8(pending_row$verbatim_text)),
        algo = "sha256", serialize = FALSE),
      decision = decision,
      reason = "fixture_review",
      review_status = "codex_verified",
      review_sha256 = fixture_sha("6"),
      proposal_evidence_sha256 = fixture_sha("7")
    )
    if (!is.null(owner)) row$context_owner_record_key <- owner
    row
  }
  new_candidates <- lapply(33:40, decision_row, decision = "new_person_candidate")
  structural <- list(decision_row(
    41L, "structural_or_summary", owner = "new-a"))
  persona_ids <- lapply(personas, function(row) row$source_persona_id)
  list(
    schema_version = "1939-v50-source-persona-materialization-v2",
    generator_version = "materialize_remaining_source_personas_1939_v50.py:v1",
    source = list(
      edition = "1939", logical_source_id = "1939", database_source_id = 7L,
      input_hashes = list(
        source_persona_v1_sha256 = fixture_sha("1"),
        remaining_identity_decisions_sha256 = fixture_sha("2"),
        database_preview_sha256 = fixture_sha("3")
      )
    ),
    review_only = TRUE,
    canonical_mutations_authorized = FALSE,
    database_write_authorized = FALSE,
    counts = list(
      v1_source_personas = 24L, appended_source_personas = 8L,
      source_personas = 32L, same_existing_person = 8L,
      new_person_candidate = 8L, structural_or_summary = 1L, unresolved = 0L
    ),
    source_personas = personas,
    new_person_candidates = new_candidates,
    structural_or_summary = structural,
    unresolved = list(),
    expected_database_changes = list(
      source_persona_candidates = persona_ids,
      source_persona_identity_candidates = persona_ids,
      canonical_person_creates = list(), canonical_person_updates = list(),
      canonical_person_deletes = list(), authorized = FALSE
    ),
    source_persona_materialization_gate = "GO",
    database_gate = "NO-GO", reimport_gate = "NO-GO"
  )
}

fake_database_v3 <- function(target_person_override = NULL,
                             expose_private_tables = FALSE,
                             missing_family_capability = FALSE) {
  fake <- fake_database()
  query <- function(sql, params = list()) {
    if (grepl("information_schema.columns", sql, fixed = TRUE)) {
      required <- required_database_columns()
      required[["public.family"]] <- c("id", "type")
      if (missing_family_capability) required[["public.family"]] <- NULL
      if (!expose_private_tables) required <- required[startsWith(names(required), "public.")]
      return(do.call(rbind, lapply(names(required), function(table) {
        bits <- strsplit(table, "\\.")[[1L]]
        data.frame(table_schema = bits[[1L]], table_name = bits[[2L]],
          column_name = required[[table]])
      })))
    }
    if (grepl("FROM public.person_external_id pei", sql, fixed = TRUE) &&
        grepl("JOIN public.person p", sql, fixed = TRUE)) {
      person_ids <- 101:132
      if (!is.null(target_person_override)) {
        person_ids[[target_person_override$index]] <- target_person_override$person_id
      }
      return(data.frame(
        person_id = person_ids,
        record_key = c("old-a", sprintf("db-target-%02d", 2:32)),
        linje = rep("I", 32L), nr = seq_len(32L), staged = rep(FALSE, 32L),
        visning_navn = sprintf("Target %02d", seq_len(32L))
      ))
    }
    if (grepl("FROM public.family fam", sql, fixed = TRUE)) {
      return(data.frame(id = c(501L, 502L), type = c("vielse", "ugift union"),
        editorial_events = c(1L, 0L)))
    }
    if (grepl("FROM public.fact f", sql, fixed = TRUE) &&
        grepl("f.subjekt_type = 'family'", sql, fixed = TRUE)) {
      return(data.frame(
        id = c(601L, 602L, 603L), family_id = c(501L, 501L, 502L),
        faktatype = c("vielse", "skilsmisse", "vielse"),
        editorial_events = c(0L, 1L, 1L), source_citations = c(1L, 0L, 1L)
      ))
    }
    if (grepl("FROM public.family_member fm", sql, fixed = TRUE)) {
      return(data.frame(
        family_id = c(501L, 501L, 502L, 502L),
        person_id = c(101L, 999L, 102L, 998L),
        rolle = rep("partner", 4L), editorial_events = c(1L, 0L, 0L, 1L)
      ))
    }
    if (grepl("FROM private.", sql, fixed = TRUE)) {
      stop("private table query was attempted")
    }
    fake$query(sql, params)
  }
  list(execute = fake$execute, query = query, calls = fake$calls)
}

testthat::test_that("v1-input bevarer database-preview v2-kontrakten", {
  fake <- fake_database()
  result <- build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres",
    expected_source_edition = "DAA 1939", snapshot_at = "2026-08-17T12:00:00Z"
  )
  testthat::expect_identical(result$schema_version, "1939-v50-database-preview-v2")
  testthat::expect_false("families" %in% names(result))
  testthat::expect_false("new_person_candidate_count" %in% names(result$source_personas))
  testthat::expect_false(any(grepl("genuinely_new_person_creation_pending",
    unlist(result$blockers), fixed = TRUE)))
})

testthat::test_that("v1 CLI stdout er byte-identisk med pre-Task5-formatet", {
  fake <- fake_database()
  result <- build_database_preview(
    preview_fixture(), source_persona_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres",
    expected_source_edition = "DAA 1939", snapshot_at = "2026-08-17T12:00:00Z"
  )
  result_path <- tempfile(fileext = ".rds")
  stdout_path <- tempfile()
  stderr_path <- tempfile()
  on.exit(unlink(c(result_path, stdout_path, stderr_path)), add = TRUE)
  saveRDS(result, result_path)
  expression <- sprintf(
    "source(%s); preview <- readRDS(%s); cat(render_database_preview_cli_stdout(preview, 'out.json', 'report.md'))",
    encodeString(helpers, quote = "\""), encodeString(result_path, quote = "\"")
  )
  status <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "-e", shQuote(expression)), stdout = stdout_path, stderr = stderr_path)
  testthat::expect_identical(status, 0L)
  actual <- readBin(stdout_path, what = "raw", n = file.info(stdout_path)$size)
  expected <- charToRaw(paste0(
    '{"output":"out.json","report":"report.md","dry_run_gate":"GO",',
    '"reimport_gate":"NO-GO","person_anchors":{"matched":1,"missing":0,"collisions":0},',
    '"expected_source_record_inserts":3,"planned_source_personas":1,',
    '"remaining_identity_pending":0,"canonical_mutations_authorized":false}\n'
  ))
  testthat::expect_identical(actual, expected)
})

testthat::test_that("v3 CLI stdout bruger den udvidede v3-summary", {
  fake <- fake_database_v3()
  result <- build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres",
    expected_source_edition = "DAA 1939", snapshot_at = "2026-08-17T12:00:00Z"
  )
  summary <- jsonlite::fromJSON(render_database_preview_cli_stdout(
    result, "out-v3.json", "report-v3.md"), simplifyVector = FALSE)
  testthat::expect_identical(names(summary), c(
    "schema_version", "output", "report", "dry_run_gate", "reimport_gate",
    "person_anchors", "expected_source_record_inserts", "planned_source_personas",
    "matched_source_persona_targets", "mismatched_source_persona_targets",
    "remaining_identity_pending", "new_person_creation_pending",
    "structural_or_summary", "canonical_mutations_authorized"
  ))
  testthat::expect_identical(summary$schema_version, "1939-v50-database-preview-v3")
  testthat::expect_identical(summary$matched_source_persona_targets, 32L)
  testthat::expect_identical(summary$mismatched_source_persona_targets, 0L)
  testthat::expect_identical(summary$new_person_creation_pending, 8L)
  testthat::expect_identical(summary$structural_or_summary, 1L)
})

testthat::test_that("v3 stopper hvis public family capability mangler", {
  fake <- fake_database_v3(missing_family_capability = TRUE)
  testthat::expect_error(build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres"
  ), "DB_PREVIEW_CAPABILITY_BLOCKER.*public.family")
  testthat::expect_identical(tail(fake$calls(), 1L)[[1L]]$sql, "ROLLBACK")
})

testthat::test_that("v3 sammenligner family rows, komplette medlemmer og family facts", {
  fake <- fake_database_v3()
  result <- build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres",
    expected_source_edition = "DAA 1939", snapshot_at = "2026-08-17T12:00:00Z"
  )

  testthat::expect_identical(result$families$comparison_basis,
    "family_rows_complete_members_and_family_facts")
  testthat::expect_identical(result$families$database_family_count, 2L)
  testthat::expect_identical(result$families$database_family_editorial_count, 1L)
  testthat::expect_identical(result$families$database_family_member_count, 4L)
  testthat::expect_identical(result$families$database_family_member_editorial_count, 2L)
  testthat::expect_identical(result$families$database_family_fact_count, 3L)
  testthat::expect_identical(result$families$database_family_fact_editorial_count, 2L)
  testthat::expect_identical(result$families$database_family_fact_source_cited_count, 2L)
  testthat::expect_identical(result$families$database_family_fact_provenance_matrix,
    list(source_only = 1L, editorial_only = 1L, both = 1L, neither = 0L))
  testthat::expect_identical(result$families$database_change_coverage,
    list(family_rows = 1L, family_members = 2L, family_facts = 2L))
  testthat::expect_identical(result$relations$database_family_member_count, 4L)
  report <- render_database_preview_markdown(result)
  testthat::expect_match(report, "family facts / med redaktionelt spor / med 1939-citation: 3/2/2",
    fixed = TRUE)
})

testthat::test_that("v2-input giver v3 med 32/32 targets og praecise blockers", {
  fake <- fake_database_v3()
  result <- build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres",
    expected_source_edition = "DAA 1939", snapshot_at = "2026-08-17T12:00:00Z"
  )

  testthat::expect_identical(result$schema_version, "1939-v50-database-preview-v3")
  testthat::expect_identical(result$source_personas$planned_count, 32L)
  testthat::expect_identical(result$source_personas$target_matched_count, 32L)
  testthat::expect_identical(result$source_personas$target_mismatch_count, 0L)
  testthat::expect_identical(result$source_personas$new_person_candidate_count, 8L)
  testthat::expect_identical(result$source_personas$structural_or_summary_count, 1L)
  testthat::expect_identical(result$source_personas$unresolved_count, 0L)
  testthat::expect_identical(result$source_personas$remaining_pending_count, 0L)
  testthat::expect_length(result$source_personas$competition_resolutions, 2L)
  blockers <- unlist(result$blockers)
  testthat::expect_true("genuinely_new_person_creation_pending:8" %in% blockers)
  testthat::expect_false(any(grepl("genuinely_new_identity_pending", blockers, fixed = TRUE)))
  testthat::expect_false(any(grepl("structural_or_summary", blockers, fixed = TRUE)))
  testthat::expect_false(result$canonical_mutations_authorized)
  testthat::expect_false(result$expected_database_changes$authorized)
})

testthat::test_that("v2 target mismatch og private-table drift stopper fail-closed", {
  mismatch <- fake_database_v3(list(index = 32L, person_id = 999L))
  testthat::expect_error(build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    mismatch$query, mismatch$execute, expected_database = "postgres"
  ), "DB_PREVIEW_SOURCE_PERSONA_TARGET_MISMATCH")
  testthat::expect_identical(tail(mismatch$calls(), 1L)[[1L]]$sql, "ROLLBACK")

  private <- fake_database_v3(expose_private_tables = TRUE)
  testthat::expect_error(build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    private$query, private$execute, expected_database = "postgres"
  ), "DB_PREVIEW_PRIVATE_TABLE_DRIFT")
  testthat::expect_false(any(grepl("FROM private.",
    vapply(private$calls(), function(call) call$sql, character(1L)), fixed = TRUE)))
})

testthat::test_that("v2 category, lineage, authority og credentials valideres lukket", {
  mutations <- list(
    function(value) { value$counts$new_person_candidate <- 7L; value },
    function(value) { value$source$input_hashes$source_persona_v1_sha256 <- "bad"; value },
    function(value) {
      value$source_personas[[32L]]$identity_decision$decision_artifact_sha256 <-
        fixture_sha("9")
      value
    },
    function(value) { value$database_write_authorized <- TRUE; value },
    function(value) { value$password <- "must-never-serialize"; value },
    function(value) { value$schema_version <- "unknown"; value }
  )
  for (mutate in mutations) {
    invalid <- mutate(source_persona_v2_fixture())
    testthat::expect_error(validate_source_persona_materialization(
      invalid, preview_v2_fixture(), fixture_sha("d"), fixture_sha("e")),
      "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  }
})

testthat::test_that("v3-output serialiserer ingen credentialfelter", {
  fake <- fake_database_v3()
  result <- build_database_preview(
    preview_v2_fixture(), source_persona_v2_fixture(), fixture_sha("e"), fixture_sha("d"),
    fake$query, fake$execute, expected_database = "postgres",
    snapshot_at = "2026-08-17T12:00:00Z"
  )
  serialized <- jsonlite::toJSON(result, auto_unbox = TRUE, null = "null")
  testthat::expect_false(grepl(
    '"(password|host|user|credential|connection_string)"\\s*:', serialized,
    ignore.case = TRUE, perl = TRUE
  ))
})

testthat::test_that("v2-filhash er laast til det godkendte produktionsartefakt", {
  production_sha <-
    "450e2dae158573131d19333be3cebefe36bf6a5d269c7ff0059e17c5fcafa97c"
  testthat::expect_invisible(validate_source_persona_file_hash(
    "1939-v50-source-persona-materialization-v2", production_sha, production_sha))
  testthat::expect_error(validate_source_persona_file_hash(
    "1939-v50-source-persona-materialization-v2", fixture_sha("9"), fixture_sha("9")),
    "DB_PREVIEW_SOURCE_PERSONA_INVALID")
  testthat::expect_invisible(validate_source_persona_file_hash(
    "1939-v50-source-persona-materialization-v1", fixture_sha("8"), fixture_sha("8")))
})
