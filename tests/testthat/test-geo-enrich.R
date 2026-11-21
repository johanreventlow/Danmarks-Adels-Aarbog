# Rene helper-tests for geo-berigelse (ingen DB/net). Kør: Rscript run-tests.R
root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(root, "R", "geo-enrich", "geo_helpers.R"))

test_that("normalize_place_key: lowercase (da), trailing-tegnsætning, whitespace, diakritik bevaret", {
  expect_equal(normalize_place_key("København"), "københavn")
  expect_equal(normalize_place_key("  Kbh. "), "kbh")
  expect_equal(normalize_place_key("Horslunde  Kirke"), "horslunde kirke")
  expect_equal(normalize_place_key("Plön"), "plön") # ö bevaret
  expect_true(is.na(normalize_place_key(NA)))
})

test_that("tng_place_leaf: første komponent i hierarkiet, vektoriseret", {
  expect_equal(tng_place_leaf("Selent, Plön, Schleswig-Holstein, Deutschland"), "Selent")
  expect_equal(tng_place_leaf(c("København, Danmark", NA)), c("København", NA))
})

test_that("fold_da_ascii: dansk/tysk diakritik -> konventionel ASCII-translitteration", {
  expect_equal(fold_da_ascii("københavn"), "koebenhavn")
  expect_equal(fold_da_ascii("christianssæde"), "christianssaede")
  expect_equal(fold_da_ascii("plön"), "ploen")
  expect_equal(fold_da_ascii("gråsten"), "graasten")
  expect_equal(fold_da_ascii("münchen"), "muenchen")
  expect_equal(fold_da_ascii("straße"), "strasse")
})

test_that("parse_coord: tom/0/uden-for-interval -> NA; gyldig -> tal", {
  expect_true(is.na(parse_coord("0", "lat")))
  expect_true(is.na(parse_coord("", "lon")))
  expect_true(is.na(parse_coord("100", "lat")))   # >90
  expect_true(is.na(parse_coord("200", "lon")))   # >180
  expect_equal(parse_coord("55.6761", "lat"), 55.6761)
  expect_equal(parse_coord("-12.5", "lon"), -12.5)
})

test_that("build_tng_index: frafiltrerer koordinatløse punkter", {
  idx <- build_tng_index(
    tng_place = c("København, Danmark", "Ukendt", "Selent, Plön"),
    tng_lat   = c("55.68", "0", "54.30"),
    tng_lon   = c("12.57", "0", "10.42"))
  expect_equal(nrow(idx), 2)
  expect_equal(sort(idx$leaf_key), c("københavn", "selent"))
})

test_that("match_places: eksakt blad-match => auto", {
  idx <- build_tng_index("København, Danmark", "55.68", "12.57")
  m <- match_places(data.frame(id = 1, navn = "København"), idx)
  expect_equal(m$tier, "auto")
  expect_equal(m$method, "eksakt")
  expect_equal(m$lat, 55.68)
})

test_that("match_places: samme navn, forskellige punkter => review (tvetydigt)", {
  idx <- build_tng_index(c("Sankt Nikolaj, Danmark", "Sankt Nikolaj, Danmark"),
                         c("55.10", "56.90"), c("11.10", "10.10"))
  m <- match_places(data.frame(id = 1, navn = "Sankt Nikolaj"), idx)
  expect_equal(m$tier, "review")
  expect_equal(m$n_kandidater, 2L)
})

test_that("match_places: ASCII-transliteret navn (æ/ø/å) => auto via tier 1b, IKKE fuzzy", {
  # Verificeret empirisk: generisk Jaro-Winkler rammer KUN 0.78 for "Plön"~"Ploen" (under
  # enhver fornuftig fuzzy-tærskel) — uden ascii-translit-tieren ville disse ende som "none".
  idx <- build_tng_index(
    tng_place = c("Christianssæde, Lolland", "Plön, Schleswig-Holstein"),
    tng_lat   = c("54.86", "54.16"), tng_lon = c("11.28", "10.42"))
  m1 <- match_places(data.frame(id = 1, navn = "Christianssaede"), idx)
  expect_equal(m1$tier, "auto")
  expect_equal(m1$method, "ascii-translit")
  m2 <- match_places(data.frame(id = 2, navn = "Ploen"), idx)
  expect_equal(m2$tier, "auto")
  expect_equal(m2$method, "ascii-translit")
})

test_that("match_places: ægte stavevariant (ikke ascii-fold) => fuzzy/review; intet match => none", {
  # Verificeret empirisk: "Kjøbenhavn" (historisk stavning) vs "København" scorer jw=0.97 —
  # en ægte fuzzy-case, adskilt fra ascii-translit-tieren ovenfor.
  idx <- build_tng_index("København, Danmark", "55.68", "12.57")
  m_fuzzy <- match_places(data.frame(id = 1, navn = "Kjøbenhavn"), idx)
  expect_equal(m_fuzzy$tier, "review")
  expect_equal(m_fuzzy$method, "fuzzy")
  m_none <- match_places(data.frame(id = 2, navn = " Helt Andet Sted"), idx)
  expect_equal(m_none$tier, "none")
  expect_true(is.na(m_none$lat))
})

test_that("rows_to_apply: kun anvend-sandt + gyldige koordinater", {
  cw <- data.frame(
    place_id = 1:4, navn = letters[1:4],
    lat = c(55, 56, NA, 54), lon = c(12, 13, 11, 10),
    anvend = c("TRUE", "ja", "TRUE", "FALSE"), stringsAsFactors = FALSE)
  ap <- rows_to_apply(cw)
  expect_equal(ap$place_id, c(1L, 2L)) # 3 mangler koordinat, 4 er FALSE
})

test_that("compare_place_texts: eksakt/ascii-translit/fuzzy/ingen + NA ved tomt input", {
  expect_equal(compare_place_texts("København", "København")$method, "eksakt")
  expect_true(compare_place_texts("København", "København")$match)
  cmp_ascii <- compare_place_texts("Plön", "Ploen")
  expect_true(cmp_ascii$match); expect_equal(cmp_ascii$method, "ascii-translit")
  cmp_fuzzy <- compare_place_texts("Kjøbenhavn", "København")
  expect_true(cmp_fuzzy$match); expect_equal(cmp_fuzzy$method, "fuzzy")
  cmp_no <- compare_place_texts("Helt Andet Sted", "København")
  expect_false(cmp_no$match)
  expect_true(is.na(compare_place_texts("", "København")$match))
  expect_true(is.na(compare_place_texts(NA, "København")$match))
})

test_that("corroborate_places_by_person: bekræftende person -> checked+confirmed", {
  crosswalk <- data.frame(place_id = 1, navn = "Christianssæde", tier = "review",
                          tng_place = "Christianssæde, Lolland", stringsAsFactors = FALSE)
  place_facts <- data.frame(person_id = 100, faktatype = "fødsel", place_id = 1, stringsAsFactors = FALSE)
  person_crosswalk <- data.frame(person_id = 100, tng_id = 999, stringsAsFactors = FALSE)
  tng_person_places <- data.frame(tng_id = 999, birthplace = "Christianssæde, Lolland",
                                  deathplace = "", burialplace = "", baptplace = "", stringsAsFactors = FALSE)
  out <- corroborate_places_by_person(crosswalk, place_facts, person_crosswalk, tng_person_places)
  expect_equal(out$person_checked, 1L)
  expect_equal(out$person_confirmed, 1L)
  expect_match(out$person_detalje, "fødsel\\(birthplace\\)=OK")
})

test_that("corroborate_places_by_person: afvigende person -> checked men IKKE confirmed", {
  crosswalk <- data.frame(place_id = 1, navn = "Kolding", tier = "review",
                          tng_place = "Kolding, Vejle, Danmark", stringsAsFactors = FALSE)
  place_facts <- data.frame(person_id = 100, faktatype = "død", place_id = 1, stringsAsFactors = FALSE)
  person_crosswalk <- data.frame(person_id = 100, tng_id = 999, stringsAsFactors = FALSE)
  tng_person_places <- data.frame(tng_id = 999, birthplace = "", deathplace = "Helt Andet Sted",
                                  burialplace = "", baptplace = "", stringsAsFactors = FALSE)
  out <- corroborate_places_by_person(crosswalk, place_facts, person_crosswalk, tng_person_places)
  expect_equal(out$person_checked, 1L)
  expect_equal(out$person_confirmed, 0L)
  expect_match(out$person_detalje, "død\\(deathplace\\)=AFVIG")
})

test_that("corroborate_places_by_person: linket person UDEN auto-tier crosswalk-modpart springes over (ikke fejl)", {
  # Regressionstest: fanget ved ægte kørsel mod prod (714 place-rækker, kun 342/925 personer
  # har en auto-tier person-match) — pc_by_person[[ukendt_id]] KASTEDE ("subscript out of
  # bounds") fordi opslaget dengang var en navngivet vektor, ikke en liste. Dette er
  # HOVEDtilfældet i virkeligheden, ikke et sjældent edge-case.
  crosswalk <- data.frame(place_id = 1, navn = "Kolding", tier = "review",
                          tng_place = "Kolding, Vejle, Danmark", stringsAsFactors = FALSE)
  place_facts <- data.frame(person_id = 12345, faktatype = "fødsel", place_id = 1, stringsAsFactors = FALSE)
  out <- corroborate_places_by_person(
    crosswalk, place_facts,
    person_crosswalk = data.frame(person_id = integer(), tng_id = character(), stringsAsFactors = FALSE),
    tng_person_places = data.frame(tng_id = character(), birthplace = character(), deathplace = character(),
                                   burialplace = character(), baptplace = character(), stringsAsFactors = FALSE))
  expect_equal(out$person_checked, 0L)
  expect_equal(out$person_detalje, "")
})

test_that("corroborate_places_by_person: person-match uden tng_people-modpart springes over (ikke fejl)", {
  # Samme fælde, anden opslags-tabel (tpp_by_id): tng_id findes i person-crosswalken,
  # men ikke i tng_person_places (fx pga. gedcom-filtrering ved ekstraktion).
  crosswalk <- data.frame(place_id = 1, navn = "Kolding", tier = "review",
                          tng_place = "Kolding, Vejle, Danmark", stringsAsFactors = FALSE)
  place_facts <- data.frame(person_id = 100, faktatype = "fødsel", place_id = 1, stringsAsFactors = FALSE)
  person_crosswalk <- data.frame(person_id = 100, tng_id = "I999", stringsAsFactors = FALSE)
  out <- corroborate_places_by_person(
    crosswalk, place_facts, person_crosswalk,
    tng_person_places = data.frame(tng_id = character(), birthplace = character(), deathplace = character(),
                                   burialplace = character(), baptplace = character(), stringsAsFactors = FALSE))
  expect_equal(out$person_checked, 0L)
  expect_equal(out$person_detalje, "")
})

test_that("corroborate_places_by_person: ingen linkede/matchede personer -> 0/0, tom detalje", {
  crosswalk <- data.frame(place_id = 1, navn = "Kolding", tier = "auto",
                          tng_place = "Kolding, Vejle, Danmark", stringsAsFactors = FALSE)
  out <- corroborate_places_by_person(
    crosswalk, place_facts = data.frame(person_id = integer(), faktatype = character(), place_id = integer()),
    person_crosswalk = data.frame(person_id = integer(), tng_id = integer()),
    tng_person_places = data.frame(tng_id = integer(), birthplace = character(),
                                   deathplace = character(), burialplace = character(), baptplace = character()))
  expect_equal(out$person_checked, 0L)
  expect_equal(out$person_confirmed, 0L)
  expect_equal(out$person_detalje, "")
})

test_that("corroborate_places_by_person: none-tier (tng_place NA) springes over", {
  crosswalk <- data.frame(place_id = 1, navn = "Ukendt", tier = "none",
                          tng_place = NA_character_, stringsAsFactors = FALSE)
  out <- corroborate_places_by_person(
    crosswalk, place_facts = data.frame(person_id = 100, faktatype = "fødsel", place_id = 1),
    person_crosswalk = data.frame(person_id = 100, tng_id = 999),
    tng_person_places = data.frame(tng_id = 999, birthplace = "Et Sted", deathplace = "",
                                   burialplace = "", baptplace = ""))
  expect_equal(out$person_checked, 0L)
  expect_equal(out$person_detalje, "")
})

# ---- Review 37, E3: menneskets godkendelser overlever en ny kørsel --------------------
.cw <- function(place_id, tng_place, lat, lon, anvend, navn = paste0("sted", place_id))
  data.frame(place_id = place_id, navn = navn, tng_place = tng_place, lat = lat, lon = lon,
             tier = "review", anvend = anvend, stringsAsFactors = FALSE)

test_that("merge_crosswalk_approvals: uændret match beholder menneskets anvend", {
  ny  <- .cw(1:3, c("A", "B", "C"), c(55, 56, 57), c(12, 13, 14), c("", "", "TRUE"))
  gml <- .cw(1:3, c("A", "B", "C"), c(55, 56, 57), c(12, 13, 14), c("TRUE", "FALSE", "FALSE"))
  m <- merge_crosswalk_approvals(ny, gml)
  expect_equal(m$crosswalk$anvend, c("TRUE", "FALSE", "FALSE")) # også et afvist auto-match holdes
  expect_equal(c(m$bevaret, m$forkastet), c(3L, 0L))
})

test_that("merge_crosswalk_approvals: ændret punkt, ændret navn eller forsvundet sted forkaster godkendelsen", {
  ny  <- .cw(1:2, c("A", "Bx"), c(55.5, 56), c(12, 13), c("", ""))
  gml <- .cw(1:3, c("A", "B", "C"), c(55, 56, 57), c(12, 13, 14), c("TRUE", "TRUE", "TRUE"))
  m <- merge_crosswalk_approvals(ny, gml)
  expect_equal(m$crosswalk$anvend, c("", ""))
  expect_equal(c(m$bevaret, m$forkastet), c(0L, 3L))
})

test_that("merge_crosswalk_approvals: tomme/NA-celler er ingen beslutning; CSV-afrunding tåles", {
  ny  <- .cw(1:2, c("A", "B"), c(55.123456789012345, 56), c(12, 13), c("", "TRUE"))
  gml <- .cw(1:2, c("A", "B"), c(55.1234567890123, 56), c(12, 13), c("ja", NA))
  gml$anvend[2] <- "NA"
  m <- merge_crosswalk_approvals(ny, gml)
  expect_equal(m$crosswalk$anvend, c("ja", "TRUE"))
  expect_equal(c(m$bevaret, m$forkastet), c(1L, 0L))
  expect_identical(merge_crosswalk_approvals(ny, NULL)$crosswalk, ny)
})

test_that("merge_crosswalk_approvals: dublet place_id i den gamle CSV stopper", {
  ny  <- .cw(1L, "A", 55, 12, "")
  gml <- .cw(c(1L, 1L), c("A", "A"), c(55, 55), c(12, 12), c("TRUE", "FALSE"))
  expect_error(merge_crosswalk_approvals(ny, gml), "dublet place_id")
})

test_that("verify_apply_rows: stopper, hvis place mangler eller har skiftet navn", {
  places <- data.frame(id = 1:3, navn = c("sted1", "sted2", "Nyt navn"), stringsAsFactors = FALSE)
  ok <- rows_to_apply(.cw(1:2, c("A", "B"), c(55, 56), c(12, 13), c("TRUE", "TRUE")))
  expect_silent(verify_apply_rows(ok, places))
  omdoebt <- rows_to_apply(.cw(3L, "C", 57, 14, "TRUE"))
  expect_error(verify_apply_rows(omdoebt, places), "place_id 3")
  slettet <- rows_to_apply(.cw(9L, "C", 57, 14, "TRUE"))
  expect_error(verify_apply_rows(slettet, places), "place_id 9")
  expect_error(verify_apply_rows(omdoebt, places), "^(?!.*Nyt navn)", perl = TRUE) # intet stednavn i fejlen
})

test_that("run-geo-enrich.R: --apply genberegner ikke og skriver ikke CSV'en", {
  src <- readLines(file.path(root, "R", "geo-enrich", "run-geo-enrich.R"), encoding = "UTF-8")
  apply_start <- grep("^if \\(do_apply\\) \\{", src)
  apply_end <- grep("^# ---- 1\\) tng_places", src)
  expect_length(apply_start, 1L); expect_length(apply_end, 1L)
  expect_lt(apply_start, apply_end) # apply-grenen ligger før genberegningen og slutter med quit()
  apply_gren <- src[apply_start:(apply_end - 1L)]
  expect_false(any(grepl("write\\.csv|match_places|build_geo_crosswalk", apply_gren)))
  expect_true(any(grepl("verify_apply_rows", apply_gren)))
  expect_true(any(grepl("quit\\(save = \"no\"\\)", tail(apply_gren, 3))))
})

test_that("merge/verify: integer64 place_id fra basen matcher CSV'ens heltal (samme fælde som E4)", {
  skip_if_not_installed("bit64")
  ny <- .cw(1:2, c("A", "B"), c(55, 56), c(12, 13), c("", ""))
  ny$place_id <- bit64::as.integer64(c(1, 3000000002))
  gml <- .cw(c(1L, 2L), c("A", "B"), c(55, 56), c(12, 13), c("TRUE", "FALSE"))
  gml$place_id <- c(1, 3000000002)
  m <- merge_crosswalk_approvals(ny, gml)
  expect_equal(m$crosswalk$anvend, c("TRUE", "FALSE"))
  expect_equal(c(m$bevaret, m$forkastet), c(2L, 0L))
  places <- data.frame(id = bit64::as.integer64(c(1, 3000000002)), navn = c("sted1", "sted2"))
  ok <- rows_to_apply(.cw(c(1, 3000000002), c("A", "B"), c(55, 56), c(12, 13), c("TRUE", "TRUE"),
                          navn = c("sted1", "sted2")))
  expect_silent(verify_apply_rows(ok, places))
})

test_that("run-geo-enrich.R: forkastede godkendelser gemmes, før CSV'en overskrives", {
  src <- readLines(file.path(root, "R", "geo-enrich", "run-geo-enrich.R"), encoding = "UTF-8")
  bak <- grep("file.copy(cw_csv, bak)", src, fixed = TRUE)
  skriv <- grep("^write\\.csv\\(crosswalk, cw_csv", src)
  expect_length(bak, 1L); expect_length(skriv, 1L)
  expect_lt(bak, skriv)
})

test_that("merge_crosswalk_approvals: auto -> review overfører ikke den automatiske accept (Codex)", {
  ny  <- .cw(1L, "A", 55, 12, ""); ny$tier <- "review"
  gml <- .cw(1L, "A", 55, 12, "TRUE"); gml$tier <- "auto"
  m <- merge_crosswalk_approvals(ny, gml)
  expect_equal(m$crosswalk$anvend, "")
  expect_equal(c(m$bevaret, m$forkastet), c(0L, 1L))
})

test_that("run-geo-enrich.R: UPDATE kræver uændret navn og apply henter id'er som numeric (Codex)", {
  src <- paste(readLines(file.path(root, "R", "geo-enrich", "run-geo-enrich.R"), encoding = "UTF-8"), collapse = "\n")
  expect_match(src, "WHERE id=$3 AND navn=$4 AND (lat IS NULL OR lon IS NULL)", fixed = TRUE)
  expect_match(src, 'bigint = "numeric"', fixed = TRUE)
})
