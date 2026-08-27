## DB-fri tests for export_c0_narrative_state_1939_v50_helpers.R -- den rene
## dokument-bygger bag fase C0's read-only eksport af prods
## source_id=3-narrativbestand (tekst + metadata + record-binding). Selve
## DBI-forbindelsen er IKKE testet her (samme konvention som de øvrige
## 1939-v50-eksportører).
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_c0_narrative_state_1939_v50_helpers.R"))

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
    person_id = c(1299, 929),
    visning_navn = c("Ferdinand Einar Julius Gottlieb", "Henrik [Reventlow]"),
    staged = c(FALSE, TRUE),
    side = c("574-75", NA_character_),
    privat = c(FALSE, FALSE),
    tekst = c("Greve Ferdinand\ntil Vindeholme", "Henrik"),
    tekst_sha256 = c(sha("a"), sha("b")),
    har_record_binding = c(FALSE, FALSE),
    binding_status = c(NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
}

build <- function(rows) {
  build_c0_narrative_state_export_1939_v50(
    rows, database_name = "postgres", database_identity = "42",
    generator = "test:v1", sql_text = "SELECT 1")
}

## Sortering, byte-eksakt tekst og NA-semantik
doc <- build(fixture_rows())
expect(identical(doc$schema_version, "1.0"), "schema_version")
expect(identical(doc$row_count, 2L), "row_count")
expect(identical(vapply(doc$rows, function(r) r$person_id, numeric(1)), c(929, 1299)),
       "sorteret paa person_id")
expect(identical(doc$rows[[2]]$tekst, "Greve Ferdinand\ntil Vindeholme"),
       "tekst bevaret byte-eksakt")
expect(isTRUE(doc$rows[[1]]$staged), "staged bevaret")
## NA, ikke NULL: jsonlite skriver NULL i en liste som `{}` (et tomt objekt),
## som Python ville laese som en truthy dict. NA bliver til `null` -> None.
expect(is.na(doc$rows[[1]]$side), "manglende side skal vaere NA, ikke NULL")

## Dublet person_id -- to narrativer paa samme person i samme udgave ville
## goere lukningens person-regnskab tvetydigt.
rows <- fixture_rows()
rows$person_id <- c(1, 1)
expect_error(build(rows), "C0_EXPORT_DUPLICATE_PERSON")

## Ugyldig sha -- en forkert hash ville tie i hele kaeden.
rows <- fixture_rows()
rows$tekst_sha256 <- c("ikke-en-sha", sha("b"))
expect_error(build(rows), "C0_EXPORT_SHA_INVALID")

## binding_status bevares naar den findes
rows <- fixture_rows()
rows$har_record_binding <- c(TRUE, FALSE)
rows$binding_status <- c("published", NA_character_)
doc <- build(rows)
bound <- Filter(function(r) isTRUE(r$har_record_binding), doc$rows)[[1L]]
expect(identical(bound$binding_status, "published"), "binding_status bevaret")

cat(sprintf("test_export_c0_narrative_state_1939_v50: %d assertions OK\n", ok))
