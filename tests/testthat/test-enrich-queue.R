test_that("enrich_review_queue tilføjer navn/dato-kolonner for begge sider", {
  rq <- data.frame(person_id = 2L, tng_id = "I2", score = 0.8, tier = "review",
                   familie_detalje = "", stringsAsFactors = FALSE)
  person <- data.frame(id = c(1L, 2L), visning_navn = c("Christian Reventlow", "Sophie Reventlow"),
                       visning_foedt = c("1650", "1660"), visning_doed = c("1720", "1730"),
                       stringsAsFactors = FALSE)
  ext_id <- data.frame(person_id = 2L, linje = "III", nr = "123", stringsAsFactors = FALSE)
  tng_people <- data.frame(personID = "I2", firstname = "Sophie", lastname = "Reventlow",
                           birthdatetr = "1660-01-01", deathdatetr = "1730-01-01",
                           stringsAsFactors = FALSE)
  out <- enrich_review_queue(rq, person, ext_id, tng_people)
  expect_equal(out$vores_label, "III-123")
  expect_equal(out$vores_navn, "Sophie Reventlow")
  expect_equal(out$vores_foedt, "1660")
  expect_equal(out$vores_doed, "1730")
  expect_equal(out$tng_navn, "Sophie Reventlow")
  expect_equal(out$tng_foedt, "1660-01-01")
  expect_equal(out$tng_doed, "1730-01-01")
})

test_that("enrich_review_queue falder tilbage til p<id>-label uden DAA-eksternid", {
  rq <- data.frame(person_id = 99L, tng_id = "I9", score = 0.8, tier = "review",
                   familie_detalje = "", stringsAsFactors = FALSE)
  person <- data.frame(id = 99L, visning_navn = "Ukendt", visning_foedt = NA_character_,
                       visning_doed = NA_character_, stringsAsFactors = FALSE)
  ext_id <- data.frame(person_id = integer(0), linje = character(0), nr = character(0),
                       stringsAsFactors = FALSE)
  tng_people <- data.frame(personID = "I9", firstname = "Ukendt", lastname = "",
                           birthdatetr = NA_character_, deathdatetr = NA_character_,
                           stringsAsFactors = FALSE)
  out <- enrich_review_queue(rq, person, ext_id, tng_people)
  expect_equal(out$vores_label, "p99")
})

test_that("resolve_familie_detalje erstatter person- og TNG-id'er med navne", {
  our_navn <- c("2" = "III-123 Sophie Reventlow")
  tng_navn <- c("I1" = "Sophie Reventlow", "I2" = "Christian Reventlow")
  d <- "forælder (person 2, TNG I1) er auto-matchet og bekræfter TNG-relationen til kandidat I2"
  out <- resolve_familie_detalje(d, tng_id = "I2", our_navn = our_navn, tng_navn = tng_navn)
  expect_equal(out, "forælder (III-123 Sophie Reventlow, Sophie Reventlow (I1)) er auto-matchet og bekræfter TNG-relationen til kandidat Christian Reventlow")
})

test_that("resolve_familie_detalje er fail-soft ved ukendte id'er (ingen crash)", {
  d <- "forælder (person 404, TNG I404) er auto-matchet og bekræfter TNG-relationen til kandidat I2"
  out <- resolve_familie_detalje(d, tng_id = "I2", our_navn = c("1" = "Kendt"), tng_navn = c("I2" = "Christian"))
  expect_equal(out, "forælder (person 404, TNG I404) er auto-matchet og bekræfter TNG-relationen til kandidat Christian")
})

test_that("resolve_familie_detalje lader tom streng være uændret", {
  out <- resolve_familie_detalje("", tng_id = "I2", our_navn = character(0), tng_navn = character(0))
  expect_equal(out, "")
})

test_that("enrich_review_queue håndterer tom review-kø uden fejl", {
  rq <- data.frame(person_id = integer(0), tng_id = character(0), score = numeric(0),
                   tier = character(0), familie_detalje = character(0), stringsAsFactors = FALSE)
  person <- data.frame(id = integer(0), visning_navn = character(0), visning_foedt = character(0),
                       visning_doed = character(0), stringsAsFactors = FALSE)
  ext_id <- data.frame(person_id = integer(0), linje = character(0), nr = character(0),
                       stringsAsFactors = FALSE)
  tng_people <- data.frame(personID = character(0), firstname = character(0), lastname = character(0),
                           birthdatetr = character(0), deathdatetr = character(0), stringsAsFactors = FALSE)
  out <- enrich_review_queue(rq, person, ext_id, tng_people)
  expect_equal(nrow(out), 0L)
  expect_true(all(c("vores_navn", "tng_navn") %in% names(out)))
})
