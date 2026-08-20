## DB-fri tests for export_d2_spouse_selection_1939_v50_helpers.R.
## Selve DBI-forbindelsen er IKKE testet her (samme konvention som de oevrige
## 1939-v50-eksportoerer).
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_d2_spouse_selection_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

fixture_rows <- function() {
  data.frame(
    person_id = c(1487, 1480),
    visning_navn = c("B", "A"),
    partner_id = c(801, 800),
    har_samme_som = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  )
}
fixture_counts <- function(...) {
  base <- list(valgte = 2, staged_i_alt = 9, staged_bagefter = 7,
               ekstra_medrevne = 0, overlap_c0 = 0)
  utils::modifyList(base, list(...))
}

## 1) Lykkelig sti: dokumentet er sorteret paa person_id og baerer alle felter.
doc <- build_d2_spouse_selection_1939_v50(
  fixture_rows(), fixture_counts(), "postgres", "abc", "test")
expect(identical(doc$schema_version, "1.0"))
expect(identical(length(doc$selected), 2L))
expect(identical(doc$selected[[1]]$person_id, 1480))
expect(identical(doc$selected[[2]]$person_id, 1487))
expect(identical(doc$selected[[1]]$har_samme_som, TRUE))
expect(identical(doc$counts$valgte, 2))

## 2) counts$valgte skal stemme med antal raekker, ellers er maalingen raadden.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(valgte = 3), "postgres", "abc", "test"),
  "D2_SELECTION_COUNT_MISMATCH")

## 3) Dubletter i udvalget ville taelle en person to gange.
dup <- fixture_rows(); dup$person_id <- c(1480, 1480)
expect_error(
  build_d2_spouse_selection_1939_v50(dup, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_DUPLICATE_PERSON")

## 4) Ekstra medrevne betyder at RPC'en vil afstage nogen vi ikke har set paa.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(ekstra_medrevne = 1), "postgres", "abc", "test"),
  "D2_SELECTION_EXTRA_SWEPT")

## 5) Overlap med C0's uafklarede: D2 maa ikke publicere noget C0 ikke har afgjort.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(overlap_c0 = 1), "postgres", "abc", "test"),
  "D2_SELECTION_C0_OVERLAP")

## 6) Regnestykket skal gaa op: staged_i_alt - valgte == staged_bagefter.
##    Bemaerk: i CLI-wrapperen er dette IKKE et uafhaengigt kontroltal (den
##    udleder begge stoerrelser af samme maaling) -- gaten har taender for
##    haandbyggede dokumenter, altsaa praecis her.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows(), fixture_counts(staged_bagefter = 6), "postgres", "abc", "test"),
  "D2_SELECTION_REMAINDER_MISMATCH")

## 7) Tom mangde er ikke en gyldig D2-koersel.
expect_error(
  build_d2_spouse_selection_1939_v50(
    fixture_rows()[0, ], fixture_counts(valgte = 0, staged_bagefter = 9),
    "postgres", "abc", "test"),
  "D2_SELECTION_EMPTY")

cat(sprintf("OK: %d assertions\n", ok))
