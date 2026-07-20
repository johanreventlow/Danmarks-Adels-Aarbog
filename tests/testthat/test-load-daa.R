# Rene, DB-frie hjælpere fra load_daa.R (load_helpers.R) — testes uden Supabase-forbindelse.
# testthat sætter wd til tests/testthat under test_dir(); repo root = ../.. (samme mønster
# som helper-source.R).
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  source(file.path(root, ".claude/skills/daa-extract/scripts/load_helpers.R"))
})

test_that("buffer_counts tæller rækker pr. tabel", {
  buf <- list(person = list(list(id=1), list(id=2)), fact = list(list(id=1)))
  expect_equal(buffer_counts(buf), c(person = 2L, fact = 1L))
})

test_that("flush skriver relation før relationsevidens og bevarer øvrige afhængigheder", {
  fixture <- list(
    citation = list(list(id = 40, assertion_id = 30, source_id = 1)),
    conclusion = list(list(id = 50, target_type = "relation", target_id = 20,
                           valgt_assertion_id = 30)),
    assertion = list(list(id = 30, target_type = "relation", target_id = 20)),
    relation = list(list(id = 20, subjekt_type = "person", subjekt_id = 10,
                         objekt_type = "estate", objekt_id = 11)),
    fact = list(list(id = 21, subjekt_type = "person", subjekt_id = 10)),
    family = list(list(id = 12)),
    family_member = list(list(family_id = 12, person_id = 10)),
    person = list(list(id = 10)),
    estate = list(list(id = 11)),
    place = list(list(id = 9))
  )
  written <- character()

  flush_buffer_in_dependency_order(fixture, function(tbl, rows) {
    if (tbl == "family_member") expect_true(all(c("person", "family") %in% written))
    if (tbl == "fact") expect_true(all(c("person", "place") %in% written))
    if (tbl == "relation") expect_true(all(c("person", "estate") %in% written))
    if (tbl == "assertion") expect_true(all(c("fact", "relation") %in% written))
    if (tbl %in% c("citation", "conclusion")) expect_true("assertion" %in% written)
    expect_true(length(rows) > 0L)
    written <<- c(written, tbl)
  })

  expect_lt(match("relation", written), match("assertion", written))
  expect_lt(match("assertion", written), match("citation", written))
  expect_lt(match("assertion", written), match("conclusion", written))
})

test_that("has_editorial_changes ser kun red_-operationer som redaktionelle", {
  expect_false(has_editorial_changes(data.frame(operation = c("daa_import"))))
  expect_true(has_editorial_changes(data.frame(operation = c("daa_import", "red_opret_fakta"))))
  expect_false(has_editorial_changes(data.frame(operation = character(0))))
})

test_that("is_missing_table_error genkender 42P01 / does not exist", {
  expect_true(is_missing_table_error('relation "change_set" does not exist'))
  expect_true(is_missing_table_error("ERROR: 42P01"))
  expect_false(is_missing_table_error("could not connect to server"))
  expect_false(is_missing_table_error("permission denied for table change_set"))
  expect_false(is_missing_table_error(NULL))
})

test_that("parse_intern_ref genkender interne se-nr", {
  expect_equal(parse_intern_ref("se nr. 97", "I"), list(linje="I", nr="97"))
  expect_equal(parse_intern_ref("nr. 106", "III"), list(linje="III", nr="106"))
  expect_equal(parse_intern_ref("von Reventlow. III. Den mecklenburgske linje, nr. 79", "I"),
               list(linje="III", nr="79"))
})
test_that("parse_intern_ref afviser eksterne udgave-refs", {
  expect_null(parse_intern_ref("DAA 1937, II, 122", "I"))
  expect_null(parse_intern_ref("DAA 1913, 135", "I"))
  expect_null(parse_intern_ref(NA, "I"))
})

test_that("resolve_barn_keys foretrækker eksakt basenr, ellers a/b-varianter", {
  expect_equal(resolve_barn_keys("I", 15, c("I-15", "I-15a")), "I-15")
  expect_setequal(resolve_barn_keys("I", 15, c("I-15a", "I-15b")), c("I-15a", "I-15b"))
  expect_equal(resolve_barn_keys("I", 99, c("I-15")), character(0))
})
test_that("barn_lookup_reason klassificerer på resolverede nøgler", {
  expect_equal(barn_lookup_reason(c("I-30")), "ok")
  expect_equal(barn_lookup_reason(character(0)), "nr_ikke_i_forael_linje")
})

# ---- match_barn_union: barnets aegteskab_kontekst -> hvilket af forælderens ægteskaber ----
# Bygger på ægte Reventlow-data (Conrad V-1, Iwan I-60, Berend III-49, Friedrich III-61).
aeg <- function(...) list(...)                       # bekvemmelighed
m2  <- aeg(list(ordinal=1L, partner_navn="Anna Margaretha Gabel"),
           list(ordinal=2L, partner_navn="Sophia Amalia Hahn"))

test_that("match_barn_union rammer rette union når navn OG ordenstal er enige", {
  expect_equal(match_barn_union("af første ægteskab med Anna Margaretha Gabel", m2)$idx, 1L)
  r <- match_barn_union("af andet ægteskab med Sophia Amalia Hahn", m2)
  expect_equal(r$idx, 2L)
  expect_equal(r$via, "begge")
})

test_that("ordenstal bryder tvetydigt partnernavn (Iwan I-60: 3. og 4. ægteskab samme navn)", {
  m4 <- aeg(list(ordinal=1L, partner_navn="Anna von Ahlefeldt"),
            list(ordinal=2L, partner_navn="Anna von Buchwaldt"),
            list(ordinal=3L, partner_navn="Margaretha von Rantzau"),
            list(ordinal=4L, partner_navn="Margaretha von Rantzau"))
  r <- match_barn_union("af tredje ægteskab med Margaretha von Rantzau", m4)
  expect_equal(r$idx, 3L)         # navn matcher 3 OG 4; "tredje" afgør
  expect_equal(r$via, "ordenstal")
})

test_that("partnernavn alene afgør når ordenstal-ord mangler", {
  r <- match_barn_union("med Anna Maria von Weltzien",
                        aeg(list(ordinal=1L, partner_navn="Christina von Damme"),
                            list(ordinal=2L, partner_navn="Anna Maria von Weltzien")))
  expect_equal(r$idx, 2L)
  expect_equal(r$via, "partner")
})

test_that("ukendt partner (ikke blandt ægteskaberne) giver NA, ikke gæt (Friedrich III-61)", {
  m <- aeg(list(ordinal=1L, partner_navn="Catharina von Brockdorff"),
           list(ordinal=2L, partner_navn="Anna Hedwig von Qualen"))
  r <- match_barn_union("med Margaretha von Rumohr (se nr. 55)", m)
  expect_true(is.na(r$idx))
  expect_equal(r$reason, "ukendt_partner")
})

test_that("navn og ordenstal i konflikt giver NA (ingen gætning)", {
  r <- match_barn_union("af første ægteskab med Sophia Amalia Hahn", m2)
  expect_true(is.na(r$idx))
  expect_equal(r$reason, "konflikt_partner_vs_ordenstal")
})

test_that("tom kontekst og ingen ægteskaber giver sigende NA-reason", {
  expect_equal(match_barn_union("", m2)$reason, "tom_kontekst")
  expect_equal(match_barn_union(NA, m2)$reason, "tom_kontekst")
  expect_equal(match_barn_union("af andet ægteskab med X", list())$reason, "ingen_aegteskaber")
})
