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

test_that("compare_parent_child matches per-parent role, not lumped", {
  xwalk <- data.frame(person_id = c(1L,2L), tng_id = c("I1","I2"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 1L, parent_id = 2L, rolle = "fader", stringsAsFactors = FALSE)
  tng_ok  <- data.frame(child_tng = "I1", father_tng = "I2", mother_tng = NA_character_, stringsAsFactors = FALSE)
  tng_bad <- data.frame(child_tng = "I1", father_tng = NA_character_, mother_tng = "I2", stringsAsFactors = FALSE)
  expect_true("enig"  %in% compare_parent_child(our_pc, tng_ok,  xwalk)$kategori)
  expect_false("enig" %in% compare_parent_child(our_pc, tng_bad, xwalk)$kategori)  # role mismatch
})

test_that("compare_parent_child reports mangler_hos_os when TNG edge absent in ours", {
  xwalk <- data.frame(person_id = c(1L,2L), tng_id = c("I1","I2"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = integer(0), parent_id = integer(0), rolle = character(0), stringsAsFactors = FALSE)
  tng <- data.frame(child_tng = "I1", father_tng = "I2", mother_tng = NA_character_, stringsAsFactors = FALSE)
  out <- compare_parent_child(our_pc, tng, xwalk)
  expect_true("mangler_hos_os" %in% out$kategori)
  expect_s3_class(out, "data.frame")
})

test_that("compare_marriages returns well-formed empty df on no edges", {
  xwalk <- data.frame(person_id = integer(0), tng_id = character(0), stringsAsFactors = FALSE)
  our_pairs <- data.frame(person_id = integer(0), spouse_id = integer(0))
  tng_families <- data.frame(husband = character(0), wife = character(0), marrdatetr = character(0), stringsAsFactors = FALSE)
  out <- compare_marriages(our_pairs, tng_families, xwalk)
  expect_s3_class(out, "data.frame"); expect_equal(nrow(out), 0L)
})
