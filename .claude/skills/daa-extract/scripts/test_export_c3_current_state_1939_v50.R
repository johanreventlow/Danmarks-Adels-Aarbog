## DB-free contract tests for the C3 current structural-state exporter.
## Fixtures contain identifiers and structural metadata only.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "c3_export_shared_1939_v50_helpers.R"))
source(file.path(script_dir, "export_c3_current_state_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "C3_TEST_EXPECTATION_FAILED") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, token) {
  observed <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(identical(observed, token), paste0("C3_TEST_ERROR_MISMATCH:", token, ":", observed))
}
sha <- function(letter) paste(rep(letter, 64L), collapse = "")

person_rows <- function() {
  data.frame(
    person_id = c(1021, 1017),
    staged = c(FALSE, TRUE),
    privat = c(FALSE, FALSE),
    stringsAsFactors = FALSE
  )
}

narrative_rows <- function() {
  data.frame(
    person_id = c(1021, 1017),
    narrative_id = c(5021, 5017),
    old_sha256 = c(sha("b"), sha("a")),
    privat = c(FALSE, FALSE),
    side = c(NA_character_, "501"),
    source_record_id = c("00000000-0000-4000-8000-000000001021", NA_character_),
    binding_status = c("draft", NA_character_),
    stringsAsFactors = FALSE
  )
}

identity_rows <- function() {
  data.frame(
    rolle = c("samme_som", "ikke_samme_som", "samme_som"),
    subject_id = c(2040, 1021, 1017),
    object_id = c(1017, 1017, 2040),
    stringsAsFactors = FALSE
  )
}

partner_rows <- function() {
  data.frame(
    left_person_id = c(1017, 1017),
    right_person_id = c(1021, 1021),
    family_id = c(902, 901),
    stringsAsFactors = FALSE
  )
}

build <- function(ids = c(1017, 1021), persons = person_rows(),
                  narratives = narrative_rows(), identities = identity_rows()[0, ],
                  partners = partner_rows()[0, ], database_name = "postgres",
                  database_identity = "42", selection_sha256 = sha("a")) {
  build_c3_current_state_1939_v50(
    ids, persons, narratives, identities, partners, database_name,
    database_identity, "test:v1", selection_sha256
  )
}

## Base contract: deterministic output, exact safe fields, no narrative prose.
doc <- build(identities = identity_rows(), partners = partner_rows())
expect(identical(doc$schema_version, "1939-v50-c3-current-state-v1"),
       "C3_TEST_SCHEMA_VERSION")
expect(identical(doc$database_name, "postgres"), "C3_TEST_DATABASE_NAME")
expect(identical(doc$database_identity, "42"), "C3_TEST_DATABASE_IDENTITY")
expect(identical(doc$selection_sha256, sha("a")), "C3_TEST_SELECTION_SHA")
expect(identical(vapply(doc$persons, function(x) x$person_id, numeric(1)),
                 c(1017, 1021)), "C3_TEST_PERSON_SORT")
expect(identical(names(doc$persons[[1L]]), c("person_id", "staged", "privat")),
       "C3_TEST_PERSON_FIELDS")
expect(identical(vapply(doc$narratives, function(x) x$person_id, numeric(1)),
                 c(1017, 1021)), "C3_TEST_NARRATIVE_SORT")
expect(identical(names(doc$narratives[[1L]]),
                 c("person_id", "narrative_id", "old_sha256", "privat", "side",
                   "source_record_id", "binding_status")),
       "C3_TEST_NARRATIVE_FIELDS")
expect(!("tekst" %in% names(doc$narratives[[1L]])), "C3_TEST_NO_PROSE")
expect(is.na(doc$narratives[[1L]]$binding_status), "C3_TEST_NULL_BINDING")
expect(identical(doc$narratives[[2L]]$binding_status, "draft"),
       "C3_TEST_BINDING_STATUS")
expect(identical(vapply(doc$partner_conflicts, function(x) x$family_id, numeric(1)),
                 c(901, 902)), "C3_TEST_PARTNER_SORT")
expect(identical(doc$identity_edges[[1L]],
                 list(role = "ikke_samme_som", subject_id = 1017,
                      object_id = 1021)), "C3_TEST_NOT_SAME_NORMALIZED")
directed <- Filter(function(x) identical(x$role, "samme_som"), doc$identity_edges)
expect(length(directed) == 2L &&
       identical(vapply(directed, function(x) x$subject_id, numeric(1)), c(1017, 2040)) &&
       identical(vapply(directed, function(x) x$object_id, numeric(1)), c(2040, 1017)),
       "C3_TEST_SAME_DIRECTION_PRESERVED")

## Complete-column gates run before vector predicates.
missing_column <- person_rows()
missing_column$privat <- NULL
expect_error(build(persons = missing_column), "C3_STATE_PERSON_COLUMNS_INVALID")
missing_column <- narrative_rows()
missing_column$old_sha256 <- NULL
expect_error(build(narratives = missing_column), "C3_STATE_NARRATIVE_COLUMNS_INVALID")
missing_column <- identity_rows()
missing_column$rolle <- NULL
expect_error(build(identities = missing_column), "C3_STATE_EDGE_COLUMNS_INVALID")
missing_column <- partner_rows()
missing_column$family_id <- NULL
expect_error(build(partners = missing_column), "C3_STATE_PARTNER_COLUMNS_INVALID")

## Selected persons and person rows must be a one-to-one exact set.
expect_error(build(ids = c(1017, 1017)), "C3_STATE_PERSON_IDS_INVALID")
missing_person <- person_rows()[person_rows()$person_id != 1021, ]
expect_error(build(persons = missing_person), "C3_STATE_PERSON_SET_MISMATCH")
extra_person <- rbind(person_rows(), data.frame(person_id = 1100, staged = FALSE,
                                                privat = FALSE))
expect_error(build(persons = extra_person), "C3_STATE_PERSON_SET_MISMATCH")
duplicate_person <- rbind(person_rows(), person_rows()[1L, ])
expect_error(build(persons = duplicate_person), "C3_STATE_PERSON_DUPLICATE")

## Privacy is fail-closed for both TRUE and NA.
private_person <- person_rows(); private_person$privat[[1L]] <- TRUE
expect_error(build(persons = private_person), "C3_STATE_PERSON_PRIVATE")
unknown_person <- person_rows(); unknown_person$privat[[1L]] <- NA
expect_error(build(persons = unknown_person), "C3_STATE_PERSON_PRIVATE")
private_narrative <- narrative_rows(); private_narrative$privat[[1L]] <- TRUE
expect_error(build(narratives = private_narrative), "C3_STATE_NARRATIVE_PRIVATE")
unknown_narrative <- narrative_rows(); unknown_narrative$privat[[1L]] <- NA
expect_error(build(narratives = unknown_narrative), "C3_STATE_NARRATIVE_PRIVATE")

## Exactly one source-3 narrative for each selected person.
missing_narrative <- narrative_rows()[narrative_rows()$person_id != 1021, ]
expect_error(build(narratives = missing_narrative), "C3_STATE_NARRATIVE_SET_MISMATCH")
extra_narrative <- rbind(
  narrative_rows(),
  data.frame(person_id = 1100, narrative_id = 5100, old_sha256 = sha("c"),
             privat = FALSE, side = "502", source_record_id = NA_character_,
             binding_status = NA_character_)
)
expect_error(build(narratives = extra_narrative), "C3_STATE_NARRATIVE_SET_MISMATCH")
duplicate_narrative <- rbind(narrative_rows(), narrative_rows()[1L, ])
duplicate_narrative$narrative_id[[3L]] <- 6021
expect_error(build(narratives = duplicate_narrative), "C3_STATE_NARRATIVE_DUPLICATE")

bad_narrative_sha <- narrative_rows(); bad_narrative_sha$old_sha256[[1L]] <- "A"
expect_error(build(narratives = bad_narrative_sha), "C3_STATE_NARRATIVE_SHA_INVALID")

## Identity edges: one selected endpoint is enough; neither is terminal.
outside_edge <- data.frame(rolle = "samme_som", subject_id = 2040,
                           object_id = 1017, stringsAsFactors = FALSE)
outside_doc <- build(identities = outside_edge)
expect(identical(outside_doc$identity_edges[[1L]]$subject_id, 2040),
       "C3_TEST_OUTSIDE_ENDPOINT_PRESERVED")
neither_selected <- outside_edge
neither_selected$object_id <- 2050
expect_error(build(identities = neither_selected), "C3_STATE_EDGE_SELECTION_INVALID")
bad_endpoint <- outside_edge; bad_endpoint$subject_id <- NA_real_
expect_error(build(identities = bad_endpoint), "C3_STATE_EDGE_ENDPOINT_INVALID")
fractional_endpoint <- outside_edge; fractional_endpoint$subject_id <- 2040.5
expect_error(build(identities = fractional_endpoint), "C3_STATE_EDGE_ENDPOINT_INVALID")
bad_role <- outside_edge; bad_role$rolle <- "related"
expect_error(build(identities = bad_role), "C3_STATE_EDGE_ROLE_INVALID")
self_edge <- outside_edge; self_edge$subject_id <- 1017; self_edge$object_id <- 1017
expect_error(build(identities = self_edge), "C3_STATE_EDGE_DIRECTION_INVALID")
duplicate_edge <- rbind(outside_edge, outside_edge)
expect_error(build(identities = duplicate_edge), "C3_STATE_EDGE_DUPLICATE")
duplicate_not_same <- data.frame(
  rolle = c("ikke_samme_som", "ikke_samme_som"),
  subject_id = c(1017, 1021), object_id = c(1021, 1017),
  stringsAsFactors = FALSE
)
expect_error(build(identities = duplicate_not_same), "C3_STATE_EDGE_DUPLICATE")

## Partner conflicts remain numeric, normalized, selected-seed keyed and unique.
reversed_partner <- data.frame(left_person_id = 1021, right_person_id = 1017,
                               family_id = 900, stringsAsFactors = FALSE)
partner_doc <- build(partners = reversed_partner)
expect(identical(partner_doc$partner_conflicts[[1L]],
                 list(left_person_id = 1017, right_person_id = 1021,
                      family_id = 900)), "C3_TEST_PARTNER_NORMALIZED")
bad_partner <- reversed_partner; bad_partner$family_id <- NA_real_
expect_error(build(partners = bad_partner), "C3_STATE_PARTNER_ID_INVALID")
outside_partner <- reversed_partner; outside_partner$left_person_id <- 2040
expect_error(build(partners = outside_partner), "C3_STATE_PARTNER_SELECTION_INVALID")
duplicate_partner <- rbind(reversed_partner, reversed_partner)
expect_error(build(partners = duplicate_partner), "C3_STATE_PARTNER_DUPLICATE")

## Database and byte-binding metadata are strictly structural.
expect_error(build(database_name = ""), "C3_STATE_DATABASE_NAME_INVALID")
expect_error(build(database_identity = "system-42"), "C3_STATE_DATABASE_IDENTITY_INVALID")
expect_error(build(selection_sha256 = "A"), "C3_STATE_SELECTION_SHA_INVALID")

## CLI preflight is DB-free: malformed selection and partial PG env fail before
## any connection attempt, with token-only diagnostics.
run_cli <- function(selection_json, pg_env) {
  selection_path <- tempfile(fileext = ".json")
  output_path <- tempfile(fileext = ".json")
  unlink(output_path)
  on.exit(unlink(c(selection_path, output_path)), add = TRUE)
  writeBin(charToRaw(enc2utf8(selection_json)), selection_path)
  result <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c(file.path(script_dir, "export_c3_current_state_1939_v50.R"),
      "--selection", selection_path, "--output", output_path,
      "--expect-database-name", "postgres"),
    stdout = TRUE, stderr = TRUE, env = pg_env
  ))
  list(status = if (is.null(attr(result, "status"))) 0L else attr(result, "status"),
       output = result)
}
partial_pg <- c("PGDATABASE=postgres", "PGHOST=", "PGPORT=", "PGUSER=",
                "PGPASSWORD=")
malformed_cli <- run_cli("[]", partial_pg)
expect(identical(as.integer(malformed_cli$status), 1L) &&
       length(malformed_cli$output) == 1L &&
       identical(malformed_cli$output[[1L]], "C3_STATE_SELECTION_INVALID"),
       paste0("C3_TEST_CLI_SELECTION_PREFLIGHT:", malformed_cli$status, ":",
              paste(malformed_cli$output, collapse = "|")))
valid_selection <- jsonlite::toJSON(list(
  schema_version = "1939-v50-c3-selection-v1",
  input_hashes = list(c0_candidates_sha256 = sha("a"),
                      c0_decisions_sha256 = sha("b")),
  case_count = 7, record_count = 8, decision_line_count = 15,
  person_ids = I(c(1017, 1021))
), auto_unbox = TRUE)
partial_pg_cli <- run_cli(valid_selection, partial_pg)
expect(identical(as.integer(partial_pg_cli$status), 1L) &&
       length(partial_pg_cli$output) == 1L &&
       identical(partial_pg_cli$output[[1L]], "C3_STATE_PG_ENV_INVALID"),
       paste0("C3_TEST_CLI_PG_ENV_PREFLIGHT:", partial_pg_cli$status, ":",
              paste(partial_pg_cli$output, collapse = "|")))

cat(sprintf("test_export_c3_current_state_1939_v50: %d assertions OK\n", ok))
