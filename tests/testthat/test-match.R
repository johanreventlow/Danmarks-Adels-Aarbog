test_that("name_similarity rewards near-identical keys", {
  expect_gt(name_similarity("conrad reventlow", "conradt reventlow"), 0.9)
  expect_lt(name_similarity("conrad reventlow", "ditlev brockdorff"), 0.6)
})

test_that("assign_tiers enforces injective 1:1 and conflict->none", {
  cfg <- default_cfg()
  scored <- data.frame(
    person_id = c(1L, 1L, 2L),
    tng_id    = c("I9", "I8", "I9"),
    name_sim  = c(0.99, 0.40, 0.97),
    birth_overlap = c(TRUE, FALSE, TRUE),
    death_overlap = c(TRUE, FALSE, TRUE),
    sex_eq    = c(TRUE, TRUE, TRUE),
    unique_block = c(TRUE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  out <- assign_tiers(scored, cfg)
  # person 1 keeps I9 (auto); person 2 also wants I9 -> conflict -> review/none, never duplicate auto
  i9 <- out[out$tng_id == "I9" & out$tier == "auto", ]
  expect_equal(nrow(i9), 1L)
  expect_equal(i9$person_id, 1L)
  # person 2 lost the unique I9 -> not auto
  expect_false(any(out$person_id == 2L & out$tier == "auto"))
})

test_that("eval_precision_recall computes against truth", {
  cw <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","IX"), stringsAsFactors = FALSE)
  truth <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"), stringsAsFactors = FALSE)
  pr <- eval_precision_recall(cw, truth)
  expect_equal(pr$precision, 2/3)
  expect_equal(pr$recall, 2/3)
})

test_that("assign_tiers sends high-score non-unique (unclaimed) to review, not auto", {
  cfg <- default_cfg()
  scored <- data.frame(
    person_id = 5L, tng_id = "I50",
    name_sim = 0.99, birth_overlap = TRUE, death_overlap = TRUE,
    sex_eq = TRUE, unique_block = FALSE,
    stringsAsFactors = FALSE
  )
  out <- assign_tiers(scored, cfg)
  expect_equal(out$tier, "review")   # >= auto_cutoff but not unique -> review, never auto
})
