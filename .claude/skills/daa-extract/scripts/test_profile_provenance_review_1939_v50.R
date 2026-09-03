root <- normalizePath(getwd())
while (!file.exists(file.path(root, ".git")) && dirname(root) != root) root <- dirname(root)
scripts <- file.path(root, ".claude", "skills", "daa-extract", "scripts")
source(file.path(scripts, "preview_reimport_1939_v50_helpers.R"))
source(file.path(scripts, "profile_identity_review_1939_v50_helpers.R"))
source(file.path(scripts, "profile_provenance_review_1939_v50_helpers.R"))

provenance_preview_fixture <- function() {
  hash <- paste(rep("a", 64L), collapse = "")
  list(
    schema_version = "1939-v50-database-preview-v3",
    snapshot_at = "2026-08-18T08:00:00Z",
    input_preview = list(schema_version = "1939-v50-import-preview-v1",
      sha256 = paste(rep("b", 64L), collapse = ""),
      input_hashes = as.list(setNames(rep(hash, 6L), letters[1:6]))),
    database = list(database_name = "postgres", server_version = "17.6",
      server_version_num = "170006", transaction_read_only = "on"),
    source = list(id = 3L, udgave = "DAA 1939", import_key = "daa:1939"),
    capabilities = list(required_columns = 1L, missing = list()),
    canonical_mutations_authorized = FALSE,
    source_personas = list(target_mismatch_count = 0L),
    person_anchors = list(
      matched_count = 2L, missing_count = 0L, collision_count = 0L,
      matched = list(
        list(baseline_record_key = "old-a", person_id = 101L),
        list(baseline_record_key = "old-b", person_id = 102L)
      )
    ),
    reimport_gate = "NO-GO"
  )
}

provenance_fake_database <- function() {
  calls <- list()
  execute <- function(sql, params = list()) {
    calls[[length(calls) + 1L]] <<- list(kind = "execute", sql = sql, params = params)
    invisible(0L)
  }
  query <- function(sql, params = list()) {
    calls[[length(calls) + 1L]] <<- list(kind = "query", sql = sql, params = params)
    if (identical(sql, database_preview_sql_registry()$transaction_read_only)) {
      return(data.frame(transaction_read_only = "on"))
    }
    if (identical(sql, database_preview_sql_registry()$metadata)) {
      return(data.frame(database_name = "postgres", server_version = "17.6",
        server_version_num = "170006"))
    }
    if (identical(sql, database_preview_sql_registry()$profile_capability_columns)) {
      required <- required_identity_profile_columns()
      return(do.call(rbind, lapply(names(required), function(table) {
        bits <- strsplit(table, "\\.")[[1L]]
        data.frame(table_schema = bits[[1L]], table_name = bits[[2L]],
          column_name = required[[table]])
      })))
    }
    if (identical(sql, database_preview_sql_registry()$profile_anchors)) {
      return(data.frame(person_id = c(101L, 102L), record_key = c("old-a", "old-b"),
        visning_navn = c("Anna", "Bent"), staged = c(FALSE, FALSE)))
    }
    if (identical(sql, database_preview_sql_registry()$profile_narratives)) {
      return(data.frame(id = c(201L, 202L), person_id = c(101L, 102L),
        record_key = c("old-a", "old-b"), tekst = c("Anna f. 1800", "Bent nævnt"),
        side = c("10", "11"), privat = c(FALSE, FALSE), editorial_events = c(0L, 1L)))
    }
    if (identical(sql, database_preview_sql_registry()$profile_person_facts)) {
      return(data.frame(fact_id = 301L, person_id = 101L, record_key = "old-a",
        faktatype = "fødsel", assertion_id = 401L, vaerdi_tekst = NA_character_,
        date_raw = "1800", citation_id = 501L, citat_tekst = "f. 1800",
        citation_side = "10", editorial_events = 0L))
    }
    if (identical(sql, database_preview_sql_registry()$profile_relations)) {
      return(data.frame(relation_id = 601L, rolle = "ejer",
        subjekt_id = 101L, objekt_id = 9001L, subjekt_navn = "Anna",
        objekt_navn = NA_character_, assertion_id = 701L,
        vaerdi_tekst = "Gaarden", date_raw = NA_character_,
        citation_id = 801L, citat_tekst = "til Gaarden", citation_side = "10",
        editorial_events = 0L))
    }
    if (identical(sql, database_preview_sql_registry()$profile_family_members)) {
      return(data.frame(target_person_id = c(101L, 101L), family_id = c(901L, 901L),
        member_person_id = c(101L, 103L), member_role = c("partner", "partner"),
        member_name = c("Anna", "Carl"), editorial_events = c(0L, 0L)))
    }
    if (identical(sql, database_preview_sql_registry()$profile_family_facts)) {
      return(data.frame(target_person_id = 101L, fact_id = 1001L, family_id = 901L,
        faktatype = "vielse", assertion_id = 1101L, vaerdi_tekst = NA_character_,
        date_raw = "1820", citation_id = 1201L, citat_tekst = "g. 1820",
        citation_side = "10", editorial_events = 0L))
    }
    stop(paste("uventet fake-query:", sql))
  }
  list(execute = execute, query = query, calls = function() calls)
}

testthat::test_that("provenanceprofilen er read-only og dækker eksakte mapped par", {
  fake <- provenance_fake_database()
  result <- .build_provenance_database_profiles(
    provenance_preview_fixture(), fake$query, fake$execute,
    expected_database = "postgres", expected_profiles = 2L,
    database_preview_sha256 = paste(rep("c", 64L), collapse = ""),
    snapshot_at = "2026-08-18T09:00:00Z"
  )

  calls <- fake$calls()
  testthat::expect_identical(calls[[1L]]$sql, "BEGIN READ ONLY")
  testthat::expect_identical(calls[[4L]]$sql, "SHOW transaction_read_only")
  testthat::expect_identical(calls[[length(calls)]]$sql, "ROLLBACK")
  testthat::expect_equal(sum(vapply(calls, function(call) {
    identical(call$sql, "ROLLBACK")
  }, logical(1L))), 1L)
  testthat::expect_identical(result$schema_version,
    "1939-v50-provenance-db-profiles-v1")
  testthat::expect_equal(result$counts$profiles, 2L)
  testthat::expect_equal(vapply(result$profiles, `[[`, character(1L), "record_key"),
    c("old-a", "old-b"))
  testthat::expect_true(result$review_only)
  testthat::expect_false(result$canonical_mutations_authorized)
})

testthat::test_that("provenanceprofilen bevarer row-level source og editorial ejerskab", {
  fake <- provenance_fake_database()
  result <- .build_provenance_database_profiles(
    provenance_preview_fixture(), fake$query, fake$execute,
    expected_database = "postgres", expected_profiles = 2L,
    database_preview_sha256 = paste(rep("c", 64L), collapse = ""),
    snapshot_at = "2026-08-18T09:00:00Z"
  )
  anna <- result$profiles[[1L]]
  testthat::expect_equal(anna$facts[[1L]]$citation$text, "f. 1800")
  testthat::expect_equal(anna$facts[[1L]]$editorial_events, 0L)
  testthat::expect_equal(anna$relations[[1L]]$citation$text, "til Gaarden")
  testthat::expect_equal(anna$families[[1L]]$members[[2L]]$display_name, "Carl")
  testthat::expect_equal(anna$families[[1L]]$facts[[1L]]$raw_value, "1820")
  testthat::expect_equal(result$profiles[[2L]]$narratives[[1L]]$editorial_events, 1L)
})

testthat::test_that("provenanceprofilen afviser mapped drift og rollbacker", {
  preview <- provenance_preview_fixture()
  preview$person_anchors$matched[[1L]]$person_id <- 999L
  fake <- provenance_fake_database()
  testthat::expect_error(.build_provenance_database_profiles(
    preview, fake$query, fake$execute, expected_database = "postgres",
    expected_profiles = 2L,
    database_preview_sha256 = paste(rep("c", 64L), collapse = "")
  ), "PROVENANCE_PROFILE_ANCHOR_MISMATCH")
  testthat::expect_identical(tail(fake$calls(), 1L)[[1L]]$sql, "ROLLBACK")
})

testthat::test_that("produktionsprofilens offentlige interface låser 543-universet", {
  testthat::expect_false("expected_profiles" %in% names(formals(build_provenance_database_profiles)))
})

testthat::test_that("profile family facts er en registreret statisk read-only query", {
  sql <- database_preview_sql_registry()$profile_family_facts
  testthat::expect_no_error(assert_read_only_sql(sql))
  testthat::expect_error(assert_read_only_sql(paste(sql, "AND 1 = 1")),
    "DB_PREVIEW_SQL_FORBIDDEN")
})

testthat::test_that("provenanceprofil-output oprettes eksklusivt", {
  fake <- provenance_fake_database()
  result <- .build_provenance_database_profiles(
    provenance_preview_fixture(), fake$query, fake$execute,
    expected_database = "postgres", expected_profiles = 2L,
    database_preview_sha256 = paste(rep("c", 64L), collapse = ""),
    snapshot_at = "2026-08-18T09:00:00Z"
  )
  directory <- tempfile("provenance-profiles-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  output <- file.path(directory, "profiles.json")
  write_provenance_profile_output(result, output)
  parsed <- jsonlite::fromJSON(output, simplifyVector = FALSE)
  testthat::expect_equal(parsed$counts$profiles, 2L)
  testthat::expect_error(write_provenance_profile_output(result, output),
    "PROVENANCE_PROFILE_OUTPUT_EXISTS")
})
