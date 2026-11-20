# Review 37, E4: id'er i hændelses-loaderen. Rene tests uden DB.
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-haendelser/scripts/load_haendelser_helpers.R"))
})
loader_src <- function() readLines(normalizePath(file.path(getwd(), "..", "..",
  ".claude/skills/daa-haendelser/scripts/load_haendelser.R")), encoding = "UTF-8")

test_that("fælden findes: integer64 mister klassen i for og ved rbind med NA-først", {
  skip_if_not_installed("bit64")
  ids <- bit64::as.integer64(c("3000000001", "42"))
  klasser <- character(); for (id in ids) klasser <- c(klasser, class(id))
  expect_equal(klasser, c("numeric", "numeric")) # derfor aldrig integer64 i loaderen
  r <- rbind(data.frame(fact_id = NA_real_), data.frame(fact_id = bit64::as.integer64("3000000005")))
  expect_false(isTRUE(all.equal(r$fact_id[[2]], 3000000005)))
})

test_that("loaderen henter id'er som numeric og vagter dem", {
  src <- paste(loader_src(), collapse = "\n")
  expect_match(src, 'bigint="numeric"', fixed = TRUE)
  expect_false(grepl('bigint="integer64"', src, fixed = TRUE))
  expect_false(grepl("for \\(id in plan\\$deletes\\$id\\)", src))
  expect_match(src, "assert_id_numerisk(plan$updates, plan$deletes, new_rows)", fixed = TRUE)
  expect_match(src, 'kraev_en_raekke("DELETE haendelse"', fixed = TRUE)
  expect_match(src, 'kraev_en_raekke("UPDATE haendelse"', fixed = TRUE)
})

test_that("kraev_en_raekke: kun præcis én ramt række går igennem", {
  expect_silent(kraev_en_raekke("DELETE haendelse", 3000000001, 1L))
  expect_error(kraev_en_raekke("DELETE haendelse", 3000000001, 0L), "id=3000000001 ramte 0 rækker")
  expect_error(kraev_en_raekke("UPDATE haendelse", 7, 2), "ramte 2 rækker")
})

test_that("assert_id_numerisk: afviser integer64, brøker, denormale og ikke-positive id'er", {
  expect_true(assert_id_numerisk(data.frame(id = c(1, 3000000001), fact_id = c(NA, 5))))
  expect_true(assert_id_numerisk(data.frame()))
  skip_if_not_installed("bit64")
  expect_error(assert_id_numerisk(data.frame(id = bit64::as.integer64(1))), "integer64")
  expect_error(assert_id_numerisk(data.frame(fact_id = 1.48e-314)), "fact_id har ugyldige")
  expect_error(assert_id_numerisk(data.frame(id = 0)), "id har ugyldige")
  expect_error(assert_id_numerisk(data.frame(relation_id = 2.5)), "relation_id har ugyldige")
})

test_that("plan_merge bevarer store numeric id'er uændret i deletes og updates", {
  old <- data.frame(id = c(3000000001, 3000000002), narrative_id = 10, noegle = c("a", "b"),
                    feed_status = "kandidat", kategori = "embede", date_min = "1580-01-01",
                    date_max = "1580-12-31", stringsAsFactors = FALSE)
  new <- data.frame(narrative_id = 10, noegle = "a", kategori = "embede", date_min = "1580-01-01",
                    date_max = "1580-12-31", stringsAsFactors = FALSE)
  p <- plan_merge(old, new)
  expect_identical(p$updates$id, 3000000001)
  expect_identical(p$deletes$id, 3000000002)
  ids <- numeric(); for (i in seq_len(nrow(p$deletes))) ids <- c(ids, p$deletes$id[[i]])
  expect_identical(ids, 3000000002)
})
