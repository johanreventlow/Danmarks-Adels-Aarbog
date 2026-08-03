# Rene kontrakttests for den nye evidensprojektion. Ingen databaseforbindelse.
root <- normalizePath(getwd())
while (!file.exists(file.path(root, ".git")) && dirname(root) != root) root <- dirname(root)
source(file.path(root, ".claude", "skills", "daa-extract", "scripts", "project_evidence_helpers.R"))

testthat::test_that("accepterede forekomster kan dele én kanonisk person uden at kopiere personen", {
  plan <- build_evidence_projection_plan(list(
    list(source_persona_id = "a", source_id = 1939L, record_key = "r-1", status = "accepted", canonical_person_id = 77L),
    list(source_persona_id = "b", source_id = 1939L, record_key = "r-2", status = "accepted", canonical_person_id = 77L),
    list(source_persona_id = "c", source_id = 1939L, record_key = "r-3", status = "accepted", canonical_person_id = 77L)
  ))
  testthat::expect_equal(plan$canonical_person_ids, 77L)
  testthat::expect_equal(length(plan$provenance), 3L)
  testthat::expect_true(all(vapply(plan$provenance, `[[`, integer(1), "canonical_person_id") == 77L))
})

testthat::test_that("uafklaret eller afvist persona kan aldrig skabe en kanonisk person", {
  plan <- build_evidence_projection_plan(list(
    list(source_persona_id = "u", source_id = 1939L, record_key = "r-u", status = "unresolved", canonical_person_id = NULL),
    list(source_persona_id = "d", source_id = 1939L, record_key = "r-d", status = "rejected", canonical_person_id = NULL)
  ))
  testthat::expect_length(plan$canonical_person_ids, 0L)
  testthat::expect_length(plan$provenance, 0L)
})

testthat::test_that("projektion fejler lukket på manglende positiv kildeproveniens", {
  testthat::expect_error(build_evidence_projection_plan(list(
    list(source_persona_id = "a", source_id = 1939L, record_key = "", status = "accepted", canonical_person_id = 77L)
  )), "PROVENANCE")
})

testthat::test_that("en persona må ikke have modstridende accepterede kanoniske mål", {
  testthat::expect_error(build_evidence_projection_plan(list(
    list(source_persona_id = "a", source_id = 1939L, record_key = "r-1", status = "accepted", canonical_person_id = 77L),
    list(source_persona_id = "a", source_id = 1939L, record_key = "r-1", status = "accepted", canonical_person_id = 88L)
  )), "IDENTITY")
})

testthat::test_that("en hel accepteret batch skrives og committes samlet", {
  calls <- character(); written <- list()
  result <- project_evidence_batch(list(
    list(source_persona_id = "a", source_id = 1939L, record_key = "r-1", status = "accepted", canonical_person_id = 77L),
    list(source_persona_id = "b", source_id = 1939L, record_key = "r-2", status = "accepted", canonical_person_id = 77L)
  ), begin = function() calls <<- c(calls, "begin"),
  write = function(row) { calls <<- c(calls, "write"); written[[length(written) + 1L]] <<- row },
  commit = function() calls <<- c(calls, "commit"), rollback = function() calls <<- c(calls, "rollback"))
  testthat::expect_equal(calls, c("begin", "write", "write", "commit"))
  testthat::expect_length(written, 2L)
  testthat::expect_equal(result$canonical_person_ids, 77L)
})

testthat::test_that("skrivefejl ruller hele batchen tilbage", {
  calls <- character(); n <- 0L
  testthat::expect_error(project_evidence_batch(list(
    list(source_persona_id = "a", source_id = 1939L, record_key = "r-1", status = "accepted", canonical_person_id = 77L),
    list(source_persona_id = "b", source_id = 1939L, record_key = "r-2", status = "accepted", canonical_person_id = 77L)
  ), begin = function() calls <<- c(calls, "begin"),
  write = function(row) { n <<- n + 1L; calls <<- c(calls, "write"); if (n == 2L) stop("DB failed") },
  commit = function() calls <<- c(calls, "commit"), rollback = function() calls <<- c(calls, "rollback")), "DB failed")
  testthat::expect_equal(calls, c("begin", "write", "write", "rollback"))
})
