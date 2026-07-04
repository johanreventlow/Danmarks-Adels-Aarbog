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
