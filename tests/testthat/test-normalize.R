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
