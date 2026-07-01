test_that("set_decision opdaterer afgoerelse for det rigtige par", {
  rq <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                   afgoerelse = c("", ""), ny_tng_id = c("", ""), stringsAsFactors = FALSE)
  out <- set_decision(rq, 1L, "I1", "bekræft")
  expect_equal(out$afgoerelse, c("bekræft", ""))
  expect_equal(out$ny_tng_id, c("", ""))
})

test_that("set_decision gemmer ny_tng_id kun ved afgoerelse='ny-id'", {
  rq <- data.frame(person_id = 1L, tng_id = "I1", afgoerelse = "", ny_tng_id = "",
                   stringsAsFactors = FALSE)
  out <- set_decision(rq, 1L, "I1", "ny-id", "I99")
  expect_equal(out$afgoerelse, "ny-id")
  expect_equal(out$ny_tng_id, "I99")
})

test_that("set_decision rydder ny_tng_id hvis afgoerelse skifter væk fra ny-id", {
  rq <- data.frame(person_id = 1L, tng_id = "I1", afgoerelse = "ny-id", ny_tng_id = "I99",
                   stringsAsFactors = FALSE)
  out <- set_decision(rq, 1L, "I1", "bekræft")
  expect_equal(out$ny_tng_id, "")
})

test_that("set_decision afviser ugyldig afgoerelse-værdi", {
  rq <- data.frame(person_id = 1L, tng_id = "I1", afgoerelse = "", ny_tng_id = "",
                   stringsAsFactors = FALSE)
  expect_error(set_decision(rq, 1L, "I1", "måske"), "Ugyldig afgoerelse")
})

test_that("set_decision kræver ny_tng_id udfyldt ved ny-id", {
  rq <- data.frame(person_id = 1L, tng_id = "I1", afgoerelse = "", ny_tng_id = "",
                   stringsAsFactors = FALSE)
  expect_error(set_decision(rq, 1L, "I1", "ny-id", ""), "ny_tng_id")
})

test_that("set_decision fejler på ukendt (person_id,tng_id)-par", {
  rq <- data.frame(person_id = 1L, tng_id = "I1", afgoerelse = "", ny_tng_id = "",
                   stringsAsFactors = FALSE)
  expect_error(set_decision(rq, 99L, "I99", "bekræft"), "Intet review-par")
})

test_that("review_progress tæller korrekt", {
  rq <- data.frame(person_id = c(1L, 2L, 3L), tng_id = c("I1", "I2", "I3"),
                   afgoerelse = c("bekræft", "", "afvis"), stringsAsFactors = FALSE)
  p <- review_progress(rq)
  expect_equal(p$total, 3L)
  expect_equal(p$besluttet, 2L)
  expect_equal(p$resterende, 1L)
})

test_that("load_review_queue fejler pænt uden fil", {
  expect_error(load_review_queue(tempfile()), "kør R/tng-qa/run-pipeline.R")
})

test_that("write_review_queue + load_review_queue rundtur bevarer data", {
  rq <- data.frame(person_id = 1L, tng_id = "I1", afgoerelse = "bekræft",
                   ny_tng_id = "", stringsAsFactors = FALSE)
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  write_review_queue(rq, f)
  out <- load_review_queue(f)
  expect_equal(out$afgoerelse, "bekræft")
})
