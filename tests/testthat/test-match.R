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

test_that("our_match_frame: år fra Date + implicit Reventlow-efternavn", {
  person <- data.frame(id = 7L, koen = "mand", visning_navn = "Conrad",
                       visning_foedt = NA, visning_doed = NA, stringsAsFactors = FALSE)
  dates <- data.frame(person_id = 7L, faktatype = "fødsel",
                      date_min = as.Date("1644-01-01"), date_max = as.Date("1644-12-31"),
                      date_raw = "*1644", stringsAsFactors = FALSE)
  fr <- our_match_frame(person, dates)
  expect_equal(fr$name_key, "conrad reventlow")  # implicit efternavn tilføjet
  expect_equal(fr$birth_min, 1644L)              # Date -> heltals-år
  expect_equal(fr$block, "c")
})

test_that("build_scored: blokerer på initial, vinduer på fødselsår, sætter unique_block", {
  cfg <- default_cfg()
  our_norm <- data.frame(
    person_id = c(1L, 2L),
    name_key  = c("conrad reventlow", "anna reventlow"),
    block     = c("c", "a"),
    birth_min = c(1644L, NA_integer_), birth_max = c(1644L, NA_integer_),
    death_min = NA_integer_, death_max = NA_integer_,
    sex = c("mand", "kvinde"), stringsAsFactors = FALSE)
  tng_norm <- data.frame(
    tng_id    = c("I1", "I2", "I3"),
    name_key  = c("conrad reventlow", "christian reventlow", "anna reventlow"),
    block     = c("c", "c", "a"),
    birth_min = c(1644L, 1700L, NA_integer_),
    birth_max = c(1644L, 1700L, NA_integer_),
    death_min = NA_integer_, death_max = NA_integer_,
    sex = c("mand", "mand", "kvinde"), stringsAsFactors = FALSE)
  sc <- build_scored(our_norm, tng_norm, cfg)
  # person 1: I2 (1700) falder ud af ±5-vinduet -> kun I1 -> unikt
  p1 <- sc[sc$person_id == 1L, ]
  expect_equal(p1$tng_id, "I1")
  expect_true(p1$unique_block)
  expect_true(p1$birth_overlap)
  # person 2: intet fødselsår -> rent navne-fallback, ene block-a-kandidat
  p2 <- sc[sc$person_id == 2L, ]
  expect_equal(p2$tng_id, "I3")
  expect_true(p2$unique_block)
  # ingen NA-score lækker ind i assign_tiers (order(-score) ville fejle lydløst)
  expect_false(any(is.na(score_pair(sc$name_sim, sc$birth_overlap,
                                     sc$death_overlap, sc$sex_eq, cfg))))
})

test_that("build_scored top-K capper på score, ikke name_sim — fødsels-korrekt match overlever", {
  cfg <- default_cfg(); cfg$top_k <- 1L           # behold kun ÉN kandidat -> cap'en afgør
  our_norm <- data.frame(
    person_id = 1L, name_key = "otto reventlow", block = "o",
    birth_min = 1719L, birth_max = 1719L, death_min = NA_integer_, death_max = NA_integer_,
    sex = "mand", stringsAsFactors = FALSE)
  # Begge "otto reventlow" (name_sim ~1.0). Det FØDSELS-FORKERTE står først
  # (1722, i ±5-vinduet men birth_overlap=FALSE); det korrekte (1719) sidst.
  tng_norm <- data.frame(
    tng_id    = c("I_off", "I_exact"),
    name_key  = c("otto reventlow", "otto reventlow"),
    block     = c("o", "o"),
    birth_min = c(1722L, 1719L), birth_max = c(1722L, 1719L),
    death_min = NA_integer_, death_max = NA_integer_,
    sex = c("mand", "mand"), stringsAsFactors = FALSE)
  sc <- build_scored(our_norm, tng_norm, cfg)
  expect_equal(nrow(sc), 1L)
  expect_equal(sc$tng_id, "I_exact")   # score-baseret cap beholder fødsels-matchet
  expect_true(sc$birth_overlap)
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
