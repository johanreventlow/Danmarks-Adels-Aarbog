## DB-fri tests for export_d1_staged_selection_1939_v50_helpers.R -- den rene
## dokument-bygger bag fase D1's read-only udvaelgelse af staged probander.
## Selve DBI-forbindelsen er IKKE testet her (samme konvention som de oevrige
## 1939-v50-eksportoerer).
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_d1_staged_selection_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

fixture_selected <- function() {
  data.frame(
    person_id = c(937, 927),
    visning_navn = c("Gotskalk [Reventlow]", "Henrik"),
    side = c("500", "507"),
    fakta = c(2, 1),
    samme_som_2020 = c(TRUE, FALSE),
    partner_ids = c("1467", NA_character_),
    stringsAsFactors = FALSE
  )
}
fixture_partners <- function() {
  data.frame(
    person_id = 1467,
    visning_navn = "Anna Margarethe von der Lieth",
    via_person_ids = "937",
    stringsAsFactors = FALSE
  )
}
fixture_counts <- function() {
  list(staged_total = 96L, selected = 2L, predicted_partners = 1L,
       blocked_no_binding = 7L, spouses_visible_partner = 21L)
}
build <- function(sel = fixture_selected(), par = fixture_partners(),
                  counts = fixture_counts()) {
  build_d1_staged_selection_1939_v50(sel, par, counts, "postgres", "42", "test:v1")
}

doc <- build()
expect(identical(doc$schema_version, "1.0"), "schema_version")
## Sorteret paa person_id -- eksporten skal vaere byte-stabil mellem koersler.
expect(identical(vapply(doc$selected, function(r) r$person_id, numeric(1)), c(927, 937)),
       "selected sorteret paa person_id")
## as.numeric() stripper I()-wrapperens AsIs-klasse; vaerdierne skal matche,
## og array-formen kontrolleres separat paa den serialiserede JSON nedenfor.
expect(identical(as.numeric(doc$selected[[2]]$partner_ids), 1467), "partner_ids parset som tal")
expect(identical(as.numeric(doc$selected[[1]]$partner_ids), numeric(0)), "tom partner-liste")
expect(isTRUE(doc$selected[[2]]$samme_som_2020), "samme_som-flag bevaret")
expect(identical(doc$counts$selected, 2L), "counts bevaret")
expect(identical(as.numeric(doc$predicted_partners[[1]]$via_person_ids), 937), "via_person_ids parset")

## Et forudsagt partner-id maa ALDRIG ogsaa staa i udvalget: saa ville
## publiceringen taelle samme person to gange, og efterkontrollens forventede
## tal (68) ville vaere forkert.
sel_overlap <- fixture_selected()
sel_overlap$person_id <- c(937, 1467)
expect_error(build(sel = sel_overlap), "D1_SELECTION_PARTNER_OVERLAP")

## Dublet i udvalget ville give samme id to gange i ARRAY-argumentet.
sel_dublet <- fixture_selected()
sel_dublet$person_id <- c(937, 937)
expect_error(build(sel = sel_dublet), "D1_SELECTION_DUPLICATE_PERSON")

par_dublet <- fixture_partners()
par_dublet <- rbind(par_dublet, par_dublet)
expect_error(build(par = par_dublet), "D1_SELECTION_DUPLICATE_PARTNER")

## Flere partnere paa én linje skal parses som en liste, ikke som én streng.
sel_flere <- fixture_selected()
sel_flere$partner_ids <- c("1467,1468", NA_character_)
doc_flere <- build(sel = sel_flere, par = fixture_partners())
expect(identical(as.numeric(doc_flere$selected[[2]]$partner_ids), c(1467, 1468)),
       "flere partner_ids parset")

## En ENKELT partner skal serialiseres som ARRAY, ikke som skalar. jsonlite's
## auto_unbox goer ellers [1467] til 1467, og Python ville laese ét id som et
## tal frem for en liste -- konverteren i Task 2 ville gaa ned paa den foerste
## proband med praecis én partner.
json <- jsonlite::toJSON(build(), auto_unbox = TRUE)
expect(grepl('"partner_ids":[1467]', json, fixed = TRUE),
       paste("enkelt partner_ids skal vaere array:", json))
expect(grepl('"partner_ids":[]', json, fixed = TRUE),
       "tom partner_ids skal vaere tomt array")
expect(grepl('"via_person_ids":[937]', json, fixed = TRUE),
       "enkelt via_person_ids skal vaere array")

cat(sprintf("test_export_d1_staged_selection_1939_v50: %d assertions OK\n", ok))
