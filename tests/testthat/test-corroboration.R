test_that("family_corroboration bekræfter forælder-nabo når TNG-graf stemmer", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("auto", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 1L)
  expect_equal(out$status, "bekraeftet")
  expect_equal(out$rolle, "forælder")
  expect_equal(out$child_id, 2L)
  expect_equal(out$parent_id, 1L)
})

test_that("family_corroboration bekræfter barn-nabo med korrekt orientering når kandidaten er forælderen", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("review", "auto"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 1L)
  expect_equal(out$status, "bekraeftet")
  expect_equal(out$rolle, "barn")
  # Kandidaten under review (person 1) er FORÆLDEREN her — child_id skal
  # stadig pege på det faktiske barn (person 2), ikke flippes.
  expect_equal(out$child_id, 2L)
  expect_equal(out$parent_id, 1L)
})

test_that("family_corroboration markerer modstridende når TNG-grafen IKKE bekræfter", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I9"),
                          tier = c("auto", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  # TNG siger I9's far er I5, IKKE I1 -> modsiger vores forælder-antagelse
  tngc <- data.frame(child_tng = "I9", father_tng = "I5", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 1L)
  expect_equal(out$status, "modstridende")
})

test_that("family_corroboration udelukker konfidens='omstridt'", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("auto", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = "omstridt", stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 0L)
})

test_that("family_corroboration returnerer intet uden auto-matchet nabo", {
  crosswalk <- data.frame(person_id = c(1L, 2L), tng_id = c("I1", "I2"),
                          tier = c("review", "review"), stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = 2L, parent_id = 1L, rolle = "ukendt",
                       konfidens = NA_character_, stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = "I2", father_tng = "I1", mother_tng = NA_character_,
                     stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_equal(nrow(out), 0L)
})

test_that("family_corroboration returnerer velformet tom data.frame uden review-tier par", {
  crosswalk <- data.frame(person_id = 1L, tng_id = "I1", tier = "auto", stringsAsFactors = FALSE)
  our_pc <- data.frame(child_id = integer(0), parent_id = integer(0), rolle = character(0),
                       konfidens = character(0), stringsAsFactors = FALSE)
  tngc <- data.frame(child_tng = character(0), father_tng = character(0),
                     mother_tng = character(0), stringsAsFactors = FALSE)
  out <- family_corroboration(crosswalk, our_pc, tngc)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
})

test_that("aggregate_familie_status samler flere bekræftende naboer til én række", {
  corrob <- data.frame(
    person_id = c(2L, 2L), tng_id = c("I2", "I2"),
    child_id = c(2L, 2L), parent_id = c(1L, 3L), rolle = c("forælder", "forælder"),
    neighbor_person_id = c(1L, 3L), neighbor_tng_id = c("I1", "I3"),
    status = c("bekraeftet", "bekraeftet"),
    familie_detalje = c("far-detalje", "mor-detalje"), stringsAsFactors = FALSE)
  out <- aggregate_familie_status(corrob)
  expect_equal(nrow(out), 1L)
  expect_equal(out$familie_status, "bekraeftet")
  expect_equal(out$familie_stoette_antal, 2L)
  expect_equal(out$familie_detalje, "far-detalje; mor-detalje")
})

test_that("aggregate_familie_status vælger bekræftet over modstridende ved blandet evidens", {
  corrob <- data.frame(
    person_id = c(2L, 2L), tng_id = c("I2", "I2"),
    child_id = c(2L, 2L), parent_id = c(1L, 3L), rolle = c("forælder", "forælder"),
    neighbor_person_id = c(1L, 3L), neighbor_tng_id = c("I1", "I3"),
    status = c("bekraeftet", "modstridende"),
    familie_detalje = c("far-bekræfter", "mor-modsiger"), stringsAsFactors = FALSE)
  out <- aggregate_familie_status(corrob)
  expect_equal(nrow(out), 1L)
  expect_equal(out$familie_status, "bekraeftet")
  expect_equal(out$familie_stoette_antal, 1L)
})

test_that("aggregate_familie_status returnerer velformet tom data.frame", {
  tom <- data.frame(person_id = integer(0), tng_id = character(0),
                    child_id = integer(0), parent_id = integer(0), rolle = character(0),
                    neighbor_person_id = integer(0), neighbor_tng_id = character(0),
                    status = character(0), familie_detalje = character(0),
                    stringsAsFactors = FALSE)
  out <- aggregate_familie_status(tom)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
})
