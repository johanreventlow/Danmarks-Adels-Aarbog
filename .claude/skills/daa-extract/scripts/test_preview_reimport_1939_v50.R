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
      edition = "1939", source_id = "daa-1939", rendition_id = "rendition",
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
      person_creation = "forbidden")),
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
    stop(paste("uventet fake-query:", sql))
  }
  list(execute = execute, query = query, calls = function() calls)
}

testthat::test_that("SQL-vagten tillader kun den snævre read-only grammatik", {
  allowed <- c(
    "BEGIN READ ONLY", "SET LOCAL statement_timeout = '30s'",
    "SET LOCAL lock_timeout = '2s'", "SHOW transaction_read_only",
    "SELECT current_database()", "ROLLBACK"
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

testthat::test_that("read-only bootstrap sker før alle domænequeries og rollbacker", {
  fake <- fake_database()

  result <- build_database_preview(
    preview_fixture(), fake$query, fake$execute,
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
    preview_fixture(), fake$query, fake$execute,
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
    preview_fixture(), fake$query, fake$execute,
    expected_database = "wrong", expected_source_edition = "DAA 1939"
  ), "DB_PREVIEW_DATABASE_MISMATCH")
  testthat::expect_identical(tail(fake$calls(), 1L)[[1L]]$sql, "ROLLBACK")

  query <- fake_database()$query
  testthat::expect_error(build_database_preview(
    preview_fixture(), query, function(...) invisible(0L),
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
    preview_fixture(), bad_readonly, fake$execute,
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
    preview_fixture(), missing_capability, fake2$execute,
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
    preview_fixture(), public_only, fake$execute,
    expected_database = "postgres", expected_source_edition = "DAA 1939",
    snapshot_at = "2026-08-17T12:00:00Z"
  )

  testthat::expect_false(result$source_records$comparison_available)
  testthat::expect_null(result$source_records$insert_count)
  testthat::expect_equal(result$capabilities$missing,
    list("private.source_record.record_key", "private.source_record.record_kind",
      "private.source_record.source_id"))
  testthat::expect_true("database_capability_blocker:private.source_record" %in%
    unlist(result$blockers))
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

testthat::test_that("database-preview outputs er eksklusive og uden credentials", {
  fake <- fake_database()
  result <- build_database_preview(
    preview_fixture(), fake$query, fake$execute,
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
