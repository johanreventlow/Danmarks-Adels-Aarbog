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
    levende = c(FALSE, FALSE),
    privat = c(FALSE, FALSE),
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

## 8) Invariant 8: en levende eller privatmarkeret person maa aldrig
##    publiceres. SQL-praedikatet filtrerer ikke paa det, saa gaten skal
##    sidde her -- ellers er den ingen steder.
lev <- fixture_rows(); lev$levende <- c(FALSE, TRUE)
expect_error(
  build_d2_spouse_selection_1939_v50(lev, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_NOT_PUBLIC_SAFE")
pri <- fixture_rows(); pri$privat <- c(TRUE, FALSE)
expect_error(
  build_d2_spouse_selection_1939_v50(pri, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_NOT_PUBLIC_SAFE")

## 8b) NA maa spaerre, ikke slippe igennem: any(c(NA)) er NA, ikke FALSE.
nas <- fixture_rows(); nas$levende <- c(FALSE, NA)
expect_error(
  build_d2_spouse_selection_1939_v50(nas, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_NOT_PUBLIC_SAFE")

## 9) Uden navn bliver personen en tom raekke i fladen.
u1 <- fixture_rows(); u1$visning_navn <- c("B", NA_character_)
expect_error(
  build_d2_spouse_selection_1939_v50(u1, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_MISSING_NAME")
u2 <- fixture_rows(); u2$visning_navn <- c("B", "   ")
expect_error(
  build_d2_spouse_selection_1939_v50(u2, fixture_counts(), "postgres", "abc", "test"),
  "D2_SELECTION_MISSING_NAME")

## 10) En MANGLENDE kolonne maa ikke ligne "ingen problemer". any(logical(0))
##     er FALSE, saa gaten ville vaere tavs -- fravaer af data ville se ud som
##     fravaer af levende personer. Fixturerne kan ikke fange det, fordi de
##     alle baerer alle kolonner.
for (kolonne in c("levende", "privat", "visning_navn")) {
  uden <- fixture_rows(); uden[[kolonne]] <- NULL
  expect_error(
    build_d2_spouse_selection_1939_v50(uden, fixture_counts(), "p", "a", "t"),
    "D2_SELECTION_KOLONNE_MANGLER")
}

cat(sprintf("OK: %d assertions\n", ok))
