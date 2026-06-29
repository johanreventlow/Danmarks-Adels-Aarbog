test_that("normalize_sex maps both vocabularies", {
  expect_equal(normalize_sex("M"), "mand")
  expect_equal(normalize_sex("kvinde"), "kvinde")
  expect_equal(normalize_sex(""), "ukendt")
})

test_that("strip_titles removes nobility predicates, keeps diacritics", {
  expect_equal(strip_titles("Greve Conrad"), "Conrad")
  expect_equal(strip_titles("Sofie Amalie"), "Sofie Amalie")
})

test_that("normalize_name inserts implicit Reventlow only when not married-in", {
  a <- normalize_name("Conrad", "")
  expect_equal(a$surname, "reventlow"); expect_true(a$implicit_surname)
  b <- normalize_name("Anna", "", married_in = TRUE)
  expect_equal(b$surname, ""); expect_false(b$implicit_surname)
  c <- normalize_name("Conrad", "Reventlow")
  expect_equal(c$key, "conrad reventlow"); expect_false(c$implicit_surname)
})

test_that("normalize_name preserves Danish diacritics in key", {
  expect_equal(normalize_name("Sofie Æbeltoft", "Brønshøj")$key, "sofie æbeltoft brønshøj")
})

test_that("parse_year_interval handles qualifiers and ranges", {
  expect_equal(parse_year_interval("1644"), c(1644L, 1644L))
  expect_equal(parse_year_interval("ca. 1650"), c(1645L, 1655L))
  expect_equal(parse_year_interval("før 1261"), c(NA_integer_, 1261L))
  expect_equal(parse_year_interval("1644-1650"), c(1644L, 1650L))
  expect_equal(parse_year_interval("ukendt"), c(NA_integer_, NA_integer_))
})

test_that("tng_date_to_interval parses and rejects zero-date", {
  expect_equal(tng_date_to_interval("1708-07-21"), c(1708L, 1708L))
  expect_equal(tng_date_to_interval("0000-00-00"), c(NA_integer_, NA_integer_))
})

test_that("intervals_overlap is NA-tolerant", {
  expect_true(intervals_overlap(c(1644L,1644L), c(1640L,1650L)))
  expect_false(intervals_overlap(c(1644L,1644L), c(1700L,1710L)))
  expect_true(intervals_overlap(c(NA,NA), c(1700L,1710L)))
})
