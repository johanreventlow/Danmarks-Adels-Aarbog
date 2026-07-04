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

test_that("match_places: kun fuzzy => review, aldrig auto; intet match => none", {
  idx <- build_tng_index("Christianssæde, Lolland", "54.86", "11.28")
  m_fuzzy <- match_places(data.frame(id = 1, navn = "Christianssaede"), idx) # ae vs æ
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
