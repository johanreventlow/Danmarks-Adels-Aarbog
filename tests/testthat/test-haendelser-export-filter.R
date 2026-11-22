# #130: hændelses-eksporten sender narrativer til en sprogmodel. Mængden må aldrig være bredere end gæstens
# læserflade: #415's samme_som-gruppe (person_offentlig) og publiceringsgaten (kontrakt v2), både i udtrækket og i
# den uafhængige selvkontrol, og forbindelsen skal være læse-kun. Prod 2026-11-21: det gamle filter tog 13
# narrativer med, som gaten afviser.
test_that("hændelses-eksporten filtrerer som gæstens læserflade og er læse-kun", {
  f <- testthat::test_path("..", "..", ".claude", "skills", "daa-haendelser", "scripts", "export_narratives.R")
  src <- paste(readLines(f, encoding = "UTF-8"), collapse = "\n")
  udtraek <- regmatches(src, regexpr('eligible_sql <- "[^"]*"', src))
  kontrol <- regmatches(src, regexpr("bad_sql <- sprintf\\([^;]*?ids\\s*\\)", src, perl = TRUE))
  expect_length(udtraek, 1)
  expect_length(kontrol, 1)
  expect_match(udtraek, "public.person_offentlig(n.subjekt_id) IS TRUE", fixed = TRUE)
  expect_match(udtraek, "public.person_daa_narrative_publication_allowed(n.id) IS TRUE", fixed = TRUE)
  expect_match(kontrol, "public.person_offentlig(n.subjekt_id) IS NOT TRUE", fixed = TRUE)
  expect_match(kontrol, "public.person_daa_narrative_publication_allowed(n.id) IS NOT TRUE", fixed = TRUE)
  expect_match(src, "SET default_transaction_read_only = on", fixed = TRUE)
  expect_match(src, "EKSPORT_IKKE_LAESE_KUN", fixed = TRUE)
})
