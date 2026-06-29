test_that("compare_marriages flags missing/extra only when both endpoints matched", {
  xwalk <- data.frame(person_id = c(1L,2L,3L), tng_id = c("I1","I2","I3"), stringsAsFactors = FALSE)
  our_pairs <- data.frame(person_id = c(1L), spouse_id = c(2L))      # we say 1—2
  tng_families <- data.frame(husband = c("I1"), wife = c("I9"), marrdatetr = c("1670-01-01"),
                             stringsAsFactors = FALSE)               # TNG says I1—I9 (I9 out of scope)
  out <- compare_marriages(our_pairs, tng_families, xwalk)
  # our 1—2 has no TNG support -> ekstra_hos_os; TNG I1—I9 endpoint out of scope -> uden_for_scope
  expect_true("ekstra_hos_os" %in% out$kategori)
  expect_true("uden_for_scope" %in% out$kategori)
  expect_false("mangler_hos_os" %in% out$kategori)  # never claim missing when endpoint unmatched
})

test_that("compare_marriages reports agreement", {
  xwalk <- data.frame(person_id = c(1L,2L), tng_id = c("I1","I2"), stringsAsFactors = FALSE)
  our_pairs <- data.frame(person_id = 1L, spouse_id = 2L)
  tng_families <- data.frame(husband = "I1", wife = "I2", marrdatetr = "1670-01-01", stringsAsFactors = FALSE)
  out <- compare_marriages(our_pairs, tng_families, xwalk)
  expect_true("enig" %in% out$kategori)
})
