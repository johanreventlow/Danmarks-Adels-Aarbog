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

test_that("safe_*_ids er fail-closed på ukendt privacy-state", {
  person <- data.frame(id = c(1L,2L,3L,4L), levende = c(FALSE,TRUE,NA,FALSE),
                       privat = c(FALSE,FALSE,FALSE,TRUE), stringsAsFactors = FALSE)
  expect_equal(safe_our_ids(person), 1L)   # 2 levende, 3 NA-levende, 4 privat -> kun 1
  tp <- data.frame(personID = c("I1","I2","I3","I4"),
                   living = c("0","1","0",""), private = c("0","0","1","0"), stringsAsFactors = FALSE)
  expect_equal(safe_tng_ids(tp), "I1")     # I2 levende, I3 privat, I4 living="" (fail-closed)
})

test_that("gate_inputs dropper kanter med en levende person (også som RELATERET endepunkt)", {
  safe_our <- c(10L, 11L); safe_tng <- c("Ia", "Ib")    # 99 levende-vores; Ic levende-TNG
  xwalk <- data.frame(person_id = c(10L,11L,99L), tng_id = c("Ia","Ib","Ic"), stringsAsFactors = FALSE)
  our_pairs <- data.frame(person_id = c(10L,10L), spouse_id = c(11L,99L))      # 10-99: levende ægtefælle
  our_pc <- data.frame(child_id = c(10L,11L), parent_id = c(11L,99L), rolle = "ukendt")  # 11-99: levende forælder
  our_attr <- data.frame(person_id = c(10L,99L), birth_min = NA_integer_, birth_max = NA_integer_,
                         death_min = NA_integer_, death_max = NA_integer_, koen = "mand", stringsAsFactors = FALSE)
  tng_families <- data.frame(familyID = c("F1","F2"), husband = c("Ia","Ia"), wife = c("Ib","Ic"), stringsAsFactors = FALSE)
  tng_children <- data.frame(child_tng = c("Ia","Ic"), father_tng = c("Ic","Ia"), mother_tng = c("Ib","Ib"), stringsAsFactors = FALSE)
  g <- gate_inputs(xwalk, our_pairs, our_pc, our_attr, tng_families, tng_children, safe_our, safe_tng)
  expect_equal(g$xwalk$person_id, c(10L,11L))           # 99 (levende) ude
  expect_equal(g$our_pairs$spouse_id, 11L)              # 10-99 droppet (related levende)
  expect_equal(nrow(g$our_pc), 1L)                      # 11-99 droppet (related levende forælder)
  expect_equal(g$our_attr$person_id, 10L)               # 99 ude
  expect_equal(g$tng_families$familyID, "F1")           # F2 (levende TNG-wife Ic) droppet
  expect_equal(g$tng_children$child_tng, "Ia")          # levende-barn Ic-række væk
  expect_true(is.na(g$tng_children$father_tng))         # levende-TNG-far Ic -> slot skjult
  expect_equal(g$tng_children$mother_tng, "Ib")
})
