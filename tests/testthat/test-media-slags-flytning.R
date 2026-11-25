# Billedtype som kontrolleret ordliste: flytning af de 56 godkendte billeder fra teknik til motiv
# (spec docs/superpowers/specs/2026-11-25-media-slags-ordliste-design.md).

root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(root, "R", "media-slags-flytning.R"))

raekker <- function(...) {
  d <- data.frame(...)
  d$id <- as.character(d$id)
  d
}

test_that("de godkendte id'er er 45 maleri, 9 foto og 2 scanning", {
  expect_length(FLYT_GODKENDT$maleri, 45L)
  expect_length(FLYT_GODKENDT$foto, 9L)
  expect_length(FLYT_GODKENDT$scanning, 2L)
  expect_length(unique(unlist(FLYT_GODKENDT)), 56L)
})

test_that("planen: motiv efter gammel slags, teknik kun for bogens billeder", {
  r <- raekker(id = c(36, 141, 10, 7), slags = c("maleri", "foto", "foto", "scanning"),
               original_filnavn = c("daa-2018-20-s0182-1.jpg", "daa-2018-20-s0335-1.jpg", "default.jpg", "linje.png"),
               har_teknik = c(FALSE, FALSE, FALSE, FALSE))
  p <- byg_flytteplan(r, godkendt = list(maleri = "36", foto = c("141", "10"), scanning = "7"))
  expect_equal(p$ny_slags, c("portræt", "portræt", "portræt", "våben"))
  expect_equal(p$teknik, c("Maleri", "Fotografi", NA, NA))
  expect_equal(p$side, c(182L, 335L, NA, NA))
})

test_that("planen stopper, når prods mængde ikke er den godkendte (mængde, ikke antal)", {
  r <- raekker(id = c(36, 99), slags = c("maleri", "maleri"), original_filnavn = c("a", "b"), har_teknik = FALSE)
  expect_error(byg_flytteplan(r, godkendt = list(maleri = c("36", "37"), foto = character(), scanning = character())),
               "FLYT_MAENGDE_AENDRET")
})

test_that("allerede flyttede rækker springes over; eksisterende teknik overskrives ikke", {
  r <- raekker(id = c(36, 37), slags = c("portræt", "maleri"), original_filnavn = c("daa-2018-20-s0182-1.jpg", "daa-2018-20-s0183-1.jpg"),
               har_teknik = c(TRUE, TRUE))
  p <- byg_flytteplan(r, godkendt = list(maleri = c("36", "37"), foto = character(), scanning = character()),
                      allerede = "36")
  expect_equal(p$id, "37")
  expect_true(is.na(p$teknik))
})

test_that("anvend: aktør, så slags, så teknik — i én transaktion pr. billede", {
  log <- new.env(); log$rpc <- character(); log$args <- list()
  ops <- list(
    transaktion = function(fn) fn(),
    aktoer = function(uuid) { log$rpc <- c(log$rpc, "set_config"); "redaktion" },
    rpc = function(navn, args) { log$rpc <- c(log$rpc, navn); log$args[[length(log$args) + 1L]] <- args; NULL }
  )
  anvend_flytning(list(id = "36", ny_slags = "portræt", teknik = "Maleri", side = 182L), ops)
  expect_equal(log$rpc, c("set_config", "red_opdater_media", "red_upsert_fakta"))
  expect_equal(log$args[[1]], list(p_media_id = "36", p_slags = "portræt"))
  expect_equal(log$args[[2]]$p_faktatype, "teknik")
  expect_equal(log$args[[2]]$p_vaerdi, "Maleri")
  expect_equal(log$args[[2]]$p_kilde_fritekst, "DAA 2018-20, s. 182")
  log$rpc <- character()
  anvend_flytning(list(id = "7", ny_slags = "våben", teknik = NA_character_, side = NA_integer_), ops)
  expect_equal(log$rpc, c("set_config", "red_opdater_media"))
})

test_that("anvend stopper, hvis aktøren ikke er redaktør", {
  ops <- list(transaktion = function(fn) fn(), aktoer = function(uuid) NA_character_, rpc = function(n, a) NULL)
  expect_error(anvend_flytning(list(id = "36", ny_slags = "portræt", teknik = NA_character_, side = NA_integer_), ops),
               "redaktion")
})
