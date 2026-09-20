root <- normalizePath(getwd())
while (!file.exists(file.path(root, ".git")) && dirname(root) != root) root <- dirname(root)
scripts <- file.path(root, ".claude", "skills", "daa-extract", "scripts")
source(file.path(scripts, "preview_reimport_1939_v50_helpers.R"))
source(file.path(scripts, "profile_identity_review_1939_v50_helpers.R"))

database_preview_fixture <- function() {
  hash <- paste(rep("a", 64L), collapse = "")
  list(
    schema_version = "1939-v50-database-preview-v1",
    snapshot_at = "2026-08-17T12:00:00Z",
    input_preview = list(schema_version = "1939-v50-import-preview-v1",
      input_hashes = as.list(setNames(rep(hash, 6L), letters[1:6]))),
    database = list(database_name = "postgres", server_version = "17.4",
      server_version_num = "170004", transaction_read_only = "on"),
    source = list(id = 7L, udgave = "DAA 1939", import_key = "daa:1939"),
    capabilities = list(required_columns = 1L, missing = list()),
    canonical_mutations_authorized = FALSE,
    person_anchors = list(
      database_only_record_keys = list("old-b", "old-c"),
      database_only = list(
        list(record_key = "old-b", person_id = 102L, visning_navn = "Bent Jensen",
          staged = FALSE, source_narrative_count = 1L, fact_count = 1L,
          family_member_count = 1L),
        list(record_key = "old-c", person_id = 103L, visning_navn = "Claus",
          staged = FALSE, source_narrative_count = 1L, fact_count = 0L,
          family_member_count = 0L)
      )
    ),
    reimport_gate = "NO-GO"
  )
}

profile_fake_database <- function() {
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
      required <- required_identity_profile_columns()
      return(do.call(rbind, lapply(names(required), function(table) {
        bits <- strsplit(table, "\\.")[[1L]]
        data.frame(table_schema = bits[[1L]], table_name = bits[[2L]],
          column_name = required[[table]])
      })))
    }
    if (grepl("SELECT pei.person_id, pei.record_key, p.visning_navn, p.staged", sql,
        fixed = TRUE)) {
      return(data.frame(person_id = c(102L, 103L), record_key = c("old-b", "old-c"),
        visning_navn = c("Bent Jensen", "Claus"), staged = c(FALSE, FALSE)))
    }
    if (grepl("FROM public.narrative n", sql, fixed = TRUE)) {
      return(data.frame(id = c(201L, 202L), person_id = c(102L, 103L),
        record_key = c("old-b", "old-c"), tekst = c("Bent født 1800", "Claus nævnt"),
        side = c("10", "11"), privat = c(FALSE, FALSE), editorial_events = c(0L, 1L)))
    }
    if (grepl("FROM public.fact f", sql, fixed = TRUE)) {
      return(data.frame(fact_id = 301L, person_id = 102L, record_key = "old-b",
        faktatype = "fødsel", assertion_id = 401L, vaerdi_tekst = NA_character_,
        date_raw = "1800", citation_id = 501L, citat_tekst = "født 1800",
        citation_side = "10", editorial_events = 0L))
    }
    if (grepl("FROM public.relation r", sql, fixed = TRUE)) {
      return(data.frame(relation_id = 601L, rolle = "samme_som",
        subjekt_id = 102L, objekt_id = 999L, subjekt_navn = "Bent Jensen",
        objekt_navn = "B. Jensen", assertion_id = NA_integer_,
        vaerdi_tekst = NA_character_, date_raw = NA_character_,
        citation_id = NA_integer_, citat_tekst = NA_character_,
        citation_side = NA_character_, editorial_events = 1L))
    }
    if (grepl("FROM public.family_member target", sql, fixed = TRUE)) {
      return(data.frame(target_person_id = 102L, family_id = 701L,
        member_person_id = c(102L, 104L), member_role = c("partner", "partner"),
        member_name = c("Bent Jensen", "Else Jensen"), editorial_events = c(0L, 0L)))
    }
    stop(paste("uventet fake-query:", sql))
  }
  list(execute = execute, query = query, calls = function() calls)
}

testthat::test_that("profiludtraek er read-only og dækker præcis deklarerede par", {
  fake <- profile_fake_database()
  result <- build_identity_database_profiles(
    database_preview_fixture(), fake$query, fake$execute,
    expected_database = "postgres", snapshot_at = "2026-08-17T13:00:00Z"
  )

  calls <- fake$calls()
  testthat::expect_identical(calls[[1L]]$sql, "BEGIN READ ONLY")
  testthat::expect_identical(calls[[4L]]$sql, "SHOW transaction_read_only")
  testthat::expect_identical(calls[[length(calls)]]$sql, "ROLLBACK")
  testthat::expect_identical(result$schema_version, "1939-v50-identity-db-profiles-v1")
  testthat::expect_equal(result$counts$profiles, 2L)
  testthat::expect_equal(vapply(result$profiles, `[[`, character(1L), "record_key"),
    c("old-b", "old-c"))
  testthat::expect_true(result$review_only)
  testthat::expect_false(result$canonical_mutations_authorized)
})

testthat::test_that("profilen bevarer source og editorial provenance", {
  fake <- profile_fake_database()
  result <- build_identity_database_profiles(
    database_preview_fixture(), fake$query, fake$execute,
    expected_database = "postgres", snapshot_at = "2026-08-17T13:00:00Z"
  )
  bent <- result$profiles[[1L]]
  testthat::expect_equal(bent$narratives[[1L]]$text, "Bent født 1800")
  testthat::expect_equal(bent$facts[[1L]]$citation$text, "født 1800")
  testthat::expect_equal(bent$facts[[1L]]$raw_value, "1800")
  testthat::expect_equal(bent$families[[1L]]$members[[2L]]$display_name, "Else Jensen")
  testthat::expect_equal(bent$relations[[1L]]$object_display_name, "B. Jensen")
  testthat::expect_equal(bent$relations[[1L]]$editorial_events, 1L)
})

testthat::test_that("profiludtraek afviser drift og rollbacker", {
  preview <- database_preview_fixture()
  preview$person_anchors$database_only[[1L]]$person_id <- 999L
  fake <- profile_fake_database()
  testthat::expect_error(build_identity_database_profiles(
    preview, fake$query, fake$execute, expected_database = "postgres"
  ), "IDENTITY_PROFILE_ANCHOR_MISMATCH")
  testthat::expect_identical(tail(fake$calls(), 1L)[[1L]]$sql, "ROLLBACK")

  preview <- database_preview_fixture()
  preview$person_anchors$database_only[[2L]]$record_key <- "old-b"
  testthat::expect_error(validate_identity_database_preview(preview),
    "IDENTITY_PROFILE_INPUT_INVALID")
})

testthat::test_that("profil-output er eksklusivt og hashbundet", {
  fake <- profile_fake_database()
  preview <- database_preview_fixture()
  result <- build_identity_database_profiles(
    preview, fake$query, fake$execute, expected_database = "postgres",
    database_preview_sha256 = paste(rep("b", 64L), collapse = ""),
    snapshot_at = "2026-08-17T13:00:00Z"
  )
  testthat::expect_equal(result$input$database_preview_sha256,
    paste(rep("b", 64L), collapse = ""))

  directory <- tempfile("identity-profiles-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  output <- file.path(directory, "profiles.json")
  write_identity_profile_output(result, output)
  parsed <- jsonlite::fromJSON(output, simplifyVector = FALSE)
  testthat::expect_equal(parsed$counts$profiles, 2L)
  testthat::expect_error(write_identity_profile_output(result, output), "File exists|findes")
})
