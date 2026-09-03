## DB-fri tests for export_narrative_old_sha_1939_v50_helpers.R -- den rene
## dokument-bygger bag den reproducerbare v2-eksport (person_id,
## narrative_sha256, side, privat) af source_id=3-narrativer. Selve
## DBI-forbindelsen (real gateway + CLI) er IKKE testet her (samme
## konvention som de øvrige 1939-v50-writere: CLI-niveau-tests dækker kun
## argument-/hash-validering, aldrig en levende DB-forbindelse i den
## generiske suite).
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_narrative_old_sha_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

sha <- function(letter) paste(rep(letter, 64L), collapse = "")

fixture_rows <- function() {
  data.frame(
    person_id = c(986L, 924L, 975L),
    narrative_sha256 = c(sha("6"), sha("9"), sha("7")),
    side = c("503", NA_character_, "508"),
    privat = c(FALSE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
}

## ---------------------------------------------------------------------
## build_narrative_old_sha_export_1939_v50 -- succesvej
## ---------------------------------------------------------------------
doc <- build_narrative_old_sha_export_1939_v50(
  fixture_rows(),
  database_name = "daa1939_phase_b_rehearsal1",
  database_identity = "1234567890123456789",
  generator = "export_narrative_old_sha_1939_v50.R:v1",
  sql_text = "SELECT ..."
)

expect(identical(doc$schema_version, "1939-v50-narrative-old-sha-export-v2"))
expect(identical(doc$generator, "export_narrative_old_sha_1939_v50.R:v1"))
expect(identical(doc$database, list(database_identity = "1234567890123456789",
  database_name = "daa1939_phase_b_rehearsal1")))
expect(identical(doc$query, list(sql = "SELECT ...", source_id = 3L, subjekt_type = "person")))
expect(identical(doc$row_count, 3L))
expect(length(doc$rows) == 3L)

## -- deterministisk: input-rækkefølgen (986,924,975) sorteres til
## STIGENDE person_id (924,975,986), uafhængigt af hvilken rækkefølge SQL'en
## (eller en fremtidig omskrivning af den) leverer rækker i.
pids <- vapply(doc$rows, function(r) r$person_id, integer(1))
expect(identical(pids, c(924L, 975L, 986L)))

## -- rækkeform: person_id, narrative_sha256, side, privat -- i den
## rækkefølge, ingen ekstra/manglende nøgler
row_975 <- doc$rows[[2L]]
expect(identical(names(row_975), c("person_id", "narrative_sha256", "side", "privat")))
expect(identical(row_975$person_id, 975L))
expect(identical(row_975$narrative_sha256, sha("7")))
expect(identical(row_975$side, "508"))
expect(identical(row_975$privat, TRUE))

## -- side==NA (SQL NULL) bevares som NA i R-strukturen (serialiseres til
## JSON null af jsonlite -- ikke en droppet nøgle, jf. list(x=NULL) ville
## have fjernet den)
row_924 <- doc$rows[[1L]]
expect(is.na(row_924$side))
expect(identical(names(row_924), c("person_id", "narrative_sha256", "side", "privat")))

## ---------------------------------------------------------------------
## Afvisningsstier
## ---------------------------------------------------------------------

## -- manglende/forkerte kolonner
bad_cols <- fixture_rows(); bad_cols$privat <- NULL
expect_error(build_narrative_old_sha_export_1939_v50(bad_cols, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_ROWS_INVALID")

## -- ikke en data.frame
expect_error(build_narrative_old_sha_export_1939_v50(list(a = 1), "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_ROWS_INVALID")

## -- dubleret person_id
dup_rows <- fixture_rows()
dup_rows$person_id[[1L]] <- dup_rows$person_id[[2L]]
expect_error(build_narrative_old_sha_export_1939_v50(dup_rows, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_DUPLICATE_PERSON_ID")

## -- ugyldigt person_id (<=0, NA, ikke-heltal)
bad_pid_rows <- fixture_rows(); bad_pid_rows$person_id[[1L]] <- 0L
expect_error(build_narrative_old_sha_export_1939_v50(bad_pid_rows, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_PERSON_ID_INVALID")
bad_pid_rows2 <- fixture_rows(); bad_pid_rows2$person_id[[1L]] <- NA_integer_
expect_error(build_narrative_old_sha_export_1939_v50(bad_pid_rows2, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_PERSON_ID_INVALID")

## -- ugyldig narrative_sha256 (forkert form)
bad_sha_rows <- fixture_rows(); bad_sha_rows$narrative_sha256[[1L]] <- "not-a-hash"
expect_error(build_narrative_old_sha_export_1939_v50(bad_sha_rows, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_SHA_INVALID")

## -- privat==NA -- fail-closed (ubetinget default FALSE i skemaet, men ingen
## NOT NULL; en NA her er en ægte anomali, ikke stille tolereret)
bad_privat_rows <- fixture_rows(); bad_privat_rows$privat[[1L]] <- NA
expect_error(build_narrative_old_sha_export_1939_v50(bad_privat_rows, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_PRIVAT_INVALID")

## -- privat ikke logical
bad_privat_type_rows <- fixture_rows()
bad_privat_type_rows$privat <- as.character(bad_privat_type_rows$privat)
expect_error(build_narrative_old_sha_export_1939_v50(bad_privat_type_rows, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_ROWS_INVALID")

## -- side ikke character (og ikke NA)
bad_side_rows <- fixture_rows(); bad_side_rows$side <- as.list(bad_side_rows$side)
expect_error(build_narrative_old_sha_export_1939_v50(bad_side_rows, "db", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_ROWS_INVALID")

## -- tom database_name/identity/generator/sql -- struktur-guard
expect_error(build_narrative_old_sha_export_1939_v50(fixture_rows(), "", "1", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_METADATA_INVALID")
expect_error(build_narrative_old_sha_export_1939_v50(fixture_rows(), "db", "", "gen", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_METADATA_INVALID")
expect_error(build_narrative_old_sha_export_1939_v50(fixture_rows(), "db", "1", "", "sql"),
  "EXPORT_NARRATIVE_OLD_SHA_1939_METADATA_INVALID")
expect_error(build_narrative_old_sha_export_1939_v50(fixture_rows(), "db", "1", "gen", ""),
  "EXPORT_NARRATIVE_OLD_SHA_1939_METADATA_INVALID")

## -- 0 rækker er en gyldig (om end usædvanlig) eksport -- ikke en fejl i sig selv
empty_doc <- build_narrative_old_sha_export_1939_v50(fixture_rows()[0, ], "db", "1", "gen", "sql")
expect(identical(empty_doc$row_count, 0L))
expect(length(empty_doc$rows) == 0L)

## -- determinisme: to kald med samme (men omarrangerede) input giver
## byte-identisk JSON
json1 <- jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE)
doc2 <- build_narrative_old_sha_export_1939_v50(
  fixture_rows()[c(3L, 1L, 2L), ],
  database_name = "daa1939_phase_b_rehearsal1", database_identity = "1234567890123456789",
  generator = "export_narrative_old_sha_1939_v50.R:v1", sql_text = "SELECT ..."
)
json2 <- jsonlite::toJSON(doc2, auto_unbox = TRUE, pretty = TRUE)
expect(identical(as.character(json1), as.character(json2)))

## ---------------------------------------------------------------------
## CLI (export_narrative_old_sha_1939_v50.R) -- kun argument-/output-guards,
## ALDRIG en levende DB-forbindelse i denne suite (samme konvention som de
## øvrige 1939-v50-writeres CLI-tests).
## ---------------------------------------------------------------------
cli <- file.path(script_dir, "export_narrative_old_sha_1939_v50.R")

## -- --output allerede eksisterer -> CLI-fejl FØR nogen DB-forbindelse forsøges.
## on.exit() registreres FØR writeLines() (ikke efter) -- når denne fil
## køres via source(..., local=TRUE) (testthat-wrapperen, modsat en direkte
## `Rscript fil.R`-kørsel), fyrer on.exit() på den indre eval()-frame med
## det samme i stedet for ved scriptets reelle afslutning; havde den stået
## efter writeLines() ville den have slettet filen igen øjeblikkeligt, FØR
## system2-kaldet nedenfor kunne nå at se den. Samme rækkefølge som søskende-
## testfilerne (test_apply_narrative_replacement_1939_v50.R m.fl.).
existing_output <- tempfile("export-old-sha-", fileext = ".json")
on.exit(unlink(existing_output), add = TRUE)
writeLines("already-here", existing_output)
cli_output_exists <- suppressWarnings(system2("Rscript",
  c(cli, "--output", existing_output), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_output_exists, "status")), 1L) &&
  any(grepl("EXPORT_NARRATIVE_OLD_SHA_1939_OUTPUT_EXISTS", cli_output_exists, fixed = TRUE)))
expect(identical(readLines(existing_output), "already-here"))

## -- manglende --output -> CLI-fejl
cli_missing_output <- suppressWarnings(system2("Rscript", c(cli), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_missing_output, "status")), 1L) &&
  any(grepl("EXPORT_NARRATIVE_OLD_SHA_1939_CLI_INVALID", cli_missing_output, fixed = TRUE)))

## -- ukendt flag -> CLI-fejl
fresh_output <- tempfile("export-old-sha-unknown-flag-", fileext = ".json")
cli_unknown_flag <- suppressWarnings(system2("Rscript",
  c(cli, "--output", fresh_output, "--bogus"), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_unknown_flag, "status")), 1L) &&
  any(grepl("EXPORT_NARRATIVE_OLD_SHA_1939_CLI_INVALID", cli_unknown_flag, fixed = TRUE)))
expect(!file.exists(fresh_output))

cat(sprintf("PASS %d assertions\n", ok))
