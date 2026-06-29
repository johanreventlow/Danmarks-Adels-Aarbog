test_that("filter_living drops living persons", {
  d <- data.frame(person_id = c(1L,2L), kategori = c("x","y"), detalje = c("a","b"), stringsAsFactors = FALSE)
  expect_equal(nrow(filter_living(d, living_person_ids = 2L)), 1L)
})

test_that("assert_no_living_pii blocks a living id in text", {
  expect_error(assert_no_living_pii("se person 2 her", living_person_ids = 2L), "PII")
  expect_invisible(assert_no_living_pii("ingen følsomme", living_person_ids = 2L))
})

test_that("render_report produces markdown and passes gate for dead-only", {
  d <- data.frame(person_id = 1L, tng_id = "I1", kategori = "dato_uenig", detalje = "fødsel", stringsAsFactors = FALSE)
  ext <- data.frame(person_id = 1L, linje = "I", nr = 5L, stringsAsFactors = FALSE)
  md <- render_report(d, ext, living_person_ids = integer(0), date = "2026-06-29")
  expect_match(md, "TNG-QA")
  expect_match(md, "I-5")
})
