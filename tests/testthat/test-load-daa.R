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

test_that("reset tillader kun den durabelt genafspillelige OCR-change_set", {
  expect_false(has_reset_blocking_editorial_changes(
    data.frame(operation = "red_ret_ocr_felt")
  ))
  expect_true(has_reset_blocking_editorial_changes(
    data.frame(operation = "red_opret_fakta")
  ))
  expect_true(has_reset_blocking_editorial_changes(
    data.frame(operation = c("red_ret_ocr_felt", "red_opret_fakta"))
  ))
  expect_true(has_reset_blocking_editorial_changes(data.frame(operation = NA_character_)))
})

test_that("korrektionsimport kræver eksplicit nøgle eller markeret legacy-tilstand", {
  parsed <- parse_load_daa_args(c(
    "tests/fixtures/person-ocr-kvalitetsark-clean.json", "DAA OCR-fixture",
    "--import-key=daa:test:ocr-kvalitetsark", "--reset"
  ))
  expect_identical(parsed$import_key, "daa:test:ocr-kvalitetsark")
  expect_false(parsed$legacy_import)
  expect_true(parsed$reset)

  expect_error(
    parse_load_daa_args(c("clean.json", "--import-key=")),
    "import-key må ikke være tom"
  )
  expect_error(
    parse_load_daa_args(c("clean.json", "DAA OCR-fixture")),
    "import-key kræves"
  )

  legacy <- parse_load_daa_args(c("clean.json", "--legacy-import"))
  expect_null(legacy$import_key)
  expect_true(legacy$legacy_import)
})

test_that("add_extid-bufferrækken bærer nr_label-baseret record_key", {
  rec <- list(linje = "I", nr = 15L, nr_label = "15a")
  row <- external_id_buffer_row(101L, 7L, rec$linje, rec$nr, record_key_of(rec))

  expect_identical(row, list(
    person_id = 101L, source_id = 7L, linje = "I", nr = 15L, record_key = "I-15a"
  ))
})

test_that("reset-listen bevarer import_korrektion uden for truncate", {
  expect_false("import_korrektion" %in% loader_model_tables())
})

test_that("reset tømmer versioneringshistorik men aldrig journalen (#124)", {
  # Historik nøglet til model-id'er må ikke overleve TRUNCATE — id-genbrug
  # ville knytte gamle events til nye, forkerte rækker.
  expect_setequal(loader_versioning_tables(), c("change_set", "change_event"))
  # Journalen er replay-laget og skal netop overleve reset.
  expect_false("import_korrektion" %in% loader_versioning_tables())
  # De to lister må ikke overlappe — hver tabel har præcis én reset-semantik.
  expect_length(intersect(loader_model_tables(), loader_versioning_tables()), 0)
})

test_that("gate-manifestet binder valideringsresultat til artefaktet (#126)", {
  sha <- "abc123"
  m <- list(sha256 = "ABC123", andel_rene = 0.95)   # case-ufølsom hash-match
  expect_true(verify_gate_manifest(m, sha)$ok)
  # forkert/ændret fil → afvis
  expect_false(verify_gate_manifest(list(sha256 = "def", andel_rene = 0.95), sha)$ok)
  # manifest uden hash → afvis
  expect_false(verify_gate_manifest(list(andel_rene = 0.95), sha)$ok)
  # rød gate (præcis den historiske 88,8 %-situation) → afvis
  roed <- verify_gate_manifest(list(sha256 = sha, andel_rene = 0.888), sha)
  expect_false(roed$ok); expect_match(roed$grund, "RØD")
  # manglende gate-tal → afvis (fail-closed)
  expect_false(verify_gate_manifest(list(sha256 = sha), sha)$ok)
  # tærskel kan skærpes
  expect_false(verify_gate_manifest(list(sha256 = sha, andel_rene = 0.95), sha, taerskel = 0.99)$ok)
})

test_that("--replace-kontrakten er fail-closed (#123 trin 3)", {
  a <- parse_load_daa_args(c("clean.json", "DAA 1939", "--replace", "--register=reg.json", "--dry-run"))
  expect_true(a$replace); expect_identical(a$register, "reg.json"); expect_null(a$import_key)
  # register er obligatorisk
  expect_error(parse_load_daa_args(c("c.json", "--replace")), "kræver --register")
  # udelukker reset/legacy/import-key (nøglen læses fra source-rækken)
  expect_error(parse_load_daa_args(c("c.json", "--replace", "--register=r.json", "--reset")), "udelukker")
  expect_error(parse_load_daa_args(c("c.json", "--replace", "--register=r.json", "--legacy-import")), "udelukker|kan ikke")
  expect_error(parse_load_daa_args(c("c.json", "--replace", "--register=r.json", "--import-key=k")), "angiv ikke")
  # almindelige modes påvirkes ikke
  expect_false(parse_load_daa_args(c("c.json", "--import-key=k"))$replace)
})

test_that("parse_load_daa_args kender --force-gate", {
  a <- parse_load_daa_args(c("clean.json", "DAA 1939", "--import-key=k", "--force-gate"))
  expect_true(a$force_gate)
  expect_false(parse_load_daa_args(c("clean.json", "--import-key=k"))$force_gate)
})

test_that("navn≠ref-guarden afviser kun beviselig uenighed (#125)", {
  # spøgelses-union-mønstret: partner_navn = mor, ref opløst til ane/far
  expect_false(partner_ref_navn_enige("Margrethe Rantzau", "Ditlev"))
  expect_false(partner_ref_navn_enige("Dorothea von Bülow", "Henning"))
  # 1939-mønstret: ref-personens navn-felt bærer kun fornavne
  expect_true(partner_ref_navn_enige("Anna Catharine Reventlow", "Anna Catharine"))
  # titel/adelspræfiks i partner_navn forstyrrer ikke token-subset
  expect_true(partner_ref_navn_enige("Oberst Joachim Diedrich von Dewitz", "Joachim Diedrich"))
  # delt distinkt navne-token (≥4 tegn) er nok
  expect_true(partner_ref_navn_enige("Magdalene Blome", "Otto Blome"))
  # kort fornavn (<4 tegn) matcher via token-subset, ikke substring
  expect_true(partner_ref_navn_enige("Cai von Thienen", "Cai"))
  expect_false(partner_ref_navn_enige("Anna", "Susanna"))  # ingen substring-falsk-positiv
  # NA (ukendt) må aldrig afvise — kun beviselig uenighed parkerer
  expect_identical(partner_ref_navn_enige(NULL, "Ditlev"), NA)
  expect_identical(partner_ref_navn_enige("Margrethe", NA), NA)
  expect_identical(partner_ref_navn_enige("", "Ditlev"), NA)
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

test_that("record_key_of bevarer postens nr_label og fejler lukket uden postnummer", {
  expect_identical(record_key_of(list(linje = "I", nr_label = "15a", nr = 15L)), "I-15a")
  expect_identical(record_key_of(list(linje = "III", nr_label = "79", nr = 79L)), "III-79")
  expect_identical(record_key_of(list(linje = "II", nr = 8L)), "II-8")
  expect_identical(record_key_of(list(linje = "II", person_id = 42L, navn = "Søren")), NA_character_)
})

test_that("record_key_of foretrækker postens EGEN record_key over den beregnede", {
  # Identitet udstedes, den udledes ikke: bærer posten et id fra
  # identitetsregisteret, er det dét der gælder — også når linje/nr findes og
  # ville give en anden (beregnet) nøgle. `linje-nr` er en gennemløbende tæller
  # for DAA 1939 og flytter sig ved re-segmentering; registerets id gør ikke.
  rec <- list(linje = "1939", nr_label = "42", nr = 42L,
              record_key = "c7a75809-80f8-4688-9915-82546f761236")
  expect_identical(record_key_of(rec), "c7a75809-80f8-4688-9915-82546f761236")
})

test_that("record_key_of falder tilbage til linje-nr når posten intet id bærer", {
  # DAA 2018-20 har ingen registernøgle i artefaktet; adfærden dér er uændret.
  expect_identical(record_key_of(list(linje = "I", nr_label = "15a", nr = 15L)), "I-15a")
})

test_that("record_key_of accepterer et id selv uden linje og nr", {
  # En omtale-post har ikke bogens nummerering, men kan godt bære et register-id.
  expect_identical(record_key_of(list(record_key = "abc-123")), "abc-123")
})

test_that("record_key_of ignorerer tomt eller NA id og bruger fallback", {
  expect_identical(record_key_of(list(linje = "I", nr = 3L, record_key = NA_character_)), "I-3")
  expect_identical(record_key_of(list(linje = "I", nr = 3L, record_key = "")), "I-3")
})

test_that("canonical_import_value emitterer faste JSON-former", {
  cases <- list(
    list(felt = "navn", value = "Conrad Detlev Reventlow",
         want = '{"value":"Conrad Detlev Reventlow"}'),
    list(felt = "navn", value = "Søren Ørsted Ågård",
         want = '{"value":"Søren Ørsted Ågård"}'),
    list(felt = "foedsel",
         value = list(raw = "* 1644", min = "1644-01-01", max = "1644-12-31",
                      qualifier = NA_character_, calendar = "gregoriansk", certainty = NA_character_),
         want = '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'),
    list(felt = "koen", value = "mand", want = '{"value":"mand"}')
  )

  for (case in cases) {
    expect_identical(as.character(canonical_import_value(case$felt, case$value)), case$want,
                     info = sprintf("felt=%s", case$felt))
  }
})

test_that("ocr_input_fingerprint bruger den fastlagte UTF-8-vektor", {
  importeret <- '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'
  expect_identical(
    ocr_input_fingerprint("daa:1939", "I-15a", "foedsel", importeret, "side=42;span=1"),
    "5fc3d843cc82550a45ff2a176bc7cc83"
  )
})

test_that("ocr_input_fingerprint canonicaliserer JSON før hash", {
  cases <- list(
    list(felt = "navn", canonical = '{"value":"Conrad Detlev Reventlow"}',
         samme = ' { "value" : "Conrad Detlev Reventlow" } '),
    list(felt = "foedsel",
         canonical = '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}',
         samme = '{"calendar":"gregoriansk", "max":"1644-12-31", "raw":"* 1644", "certainty":null, "min":"1644-01-01", "qualifier":null}'),
    list(felt = "koen", canonical = '{"value":"mand"}', samme = '{ "value" : "mand" }')
  )

  for (case in cases) {
    expect_identical(
      ocr_input_fingerprint("daa:1939", "I-15a", case$felt, case$samme, "side=42;span=1"),
      ocr_input_fingerprint("daa:1939", "I-15a", case$felt, case$canonical, "side=42;span=1"),
      info = sprintf("felt=%s", case$felt)
    )
  }
})

test_that("ocr_input_fingerprint bruger tom OCR-kontekst som SQL-kontrakten", {
  expect_identical(
    ocr_input_fingerprint("daa:test:ocr-kvalitetsark", "I-15a", "koen", "mand", NA_character_),
    "9918e9b8875add05ecc29f23b1bea916"
  )
})

test_that("apply_import_correction anvender kun en matchende rettet journalpost", {
  importeret <- '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'
  korrigeret <- '{"raw":"* 1645","min":"1645-01-01","max":"1645-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'
  correction <- list(
    id = 17L, import_key = "daa:1939", record_key = "I-15a", felt = "foedsel",
    input_fingerprint = "5fc3d843cc82550a45ff2a176bc7cc83",
    korrigeret = korrigeret, status = "rettet"
  )

  result <- apply_import_correction("daa:1939", "I-15a", "foedsel", importeret,
                                    "side=42;span=1", list(correction))
  expect_identical(result$value, korrigeret)
  expect_identical(result$status, "anvendt")
  expect_identical(result$fingerprint, "5fc3d843cc82550a45ff2a176bc7cc83")
  expect_identical(result$correction_id, 17L)
})

test_that("apply_import_correction lader godkendt og udskudt import stå uændret", {
  importeret <- '{"value":"Conrad Detlev Reventlow"}'
  fingerprint <- "babf4f524a74d4b5abea44789673a7e8"
  base <- list(
    id = 18L, import_key = "daa:1939", record_key = "I-15a", felt = "navn",
    input_fingerprint = fingerprint, korrigeret = NULL
  )

  for (journal_status in c("godkendt", "udskudt")) {
    correction <- c(base, list(status = journal_status))
    result <- apply_import_correction("daa:1939", "I-15a", "navn", importeret,
                                      "side=42;span=1", list(correction))
    expect_identical(result$value, importeret, info = journal_status)
    expect_identical(result$status, "ingen", info = journal_status)
  }
})

test_that("apply_import_correction markerer ændret OCR-kontekst som stale", {
  importeret <- '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'
  correction <- list(
    id = 19L, import_key = "daa:1939", record_key = "I-15a", felt = "foedsel",
    input_fingerprint = "5fc3d843cc82550a45ff2a176bc7cc83",
    korrigeret = '{"raw":"* 1645"}', status = "rettet"
  )

  result <- apply_import_correction("daa:1939", "I-15a", "foedsel", importeret,
                                    "side=43;span=1", list(correction))
  expect_identical(result$value, importeret)
  expect_identical(result$status, "stale")
  expect_identical(result$correction_id, 19L)
})

test_that("forudindlæste rettelser genafspilles for navn, dato og køn", {
  corrections <- index_import_corrections(list(
    list(id = 31L, import_key = "daa:test:ocr-kvalitetsark", record_key = "I-15a",
         felt = "navn", input_fingerprint = "ac44c464b6ebd8e7a8ef45b2feba4c75",
         korrigeret = '{"value":"Mikkel Rettet"}', status = "rettet"),
    list(id = 32L, import_key = "daa:test:ocr-kvalitetsark", record_key = "I-15a",
         felt = "foedsel", input_fingerprint = "a4edd8400a9239adf377b42eaba969e2",
         korrigeret = '{"raw":"1645-01-01","min":"1645-01-01","max":"1645-01-01","qualifier":"exact","calendar":"gregoriansk","certainty":null}', status = "rettet"),
    list(id = 33L, import_key = "daa:test:ocr-kvalitetsark", record_key = "I-15a",
         felt = "koen", input_fingerprint = "9918e9b8875add05ecc29f23b1bea916",
         korrigeret = '{"value":"kvinde"}', status = "rettet")
  ))

  navn <- apply_import_correction("daa:test:ocr-kvalitetsark", "I-15a", "navn",
                                  "Mikkel OCR", "Mikkel OCR, født 1644", corrections)
  foedsel <- apply_import_correction("daa:test:ocr-kvalitetsark", "I-15a", "foedsel",
    list(raw = "1644-01-01", min = "1644-01-01", max = "1644-01-01",
         qualifier = "exact", calendar = "gregoriansk", certainty = NA_character_),
    "født 1644-01-01", corrections)
  koen <- apply_import_correction("daa:test:ocr-kvalitetsark", "I-15a", "koen",
                                  "mand", NA_character_, corrections)

  expect_identical(navn$value, '{"value":"Mikkel Rettet"}')
  expect_identical(foedsel$value, '{"raw":"1645-01-01","min":"1645-01-01","max":"1645-01-01","qualifier":"exact","calendar":"gregoriansk","certainty":null}')
  expect_identical(koen$value, '{"value":"kvinde"}')
  expect_true(all(c(navn$status, foedsel$status, koen$status) == "anvendt"))
})

test_that("stale genafspilning lader importen stå og udpeger kun stale journal-id'er", {
  correction <- list(
    id = 41L, import_key = "daa:test:ocr-kvalitetsark", record_key = "I-15a",
    felt = "navn", input_fingerprint = "ac44c464b6ebd8e7a8ef45b2feba4c75",
    korrigeret = '{"value":"Mikkel Rettet"}', status = "rettet"
  )
  result <- apply_import_correction("daa:test:ocr-kvalitetsark", "I-15a", "navn",
                                    "Mikkel OCR", "ændret OCR-kontekst",
                                    index_import_corrections(list(correction)))

  expect_identical(result$value, "Mikkel OCR")
  expect_identical(result$status, "stale")
  expect_equal(stale_correction_ids(list(result, list(status = "anvendt", correction_id = 42L))), 41L)
})

# Fingerprintet daekker BAADE den importerede vaerdi og OCR-konteksten. Testen ovenfor
# aendrer kun konteksten; her aendres selve den importerede vaerdi med UAENDRET kontekst,
# saa fail-closed-garantien er daekket i begge retninger.
test_that("aendret importeret vaerdi giver stale selv naar OCR-konteksten er uaendret", {
  kontekst <- "Mikkel OCR, født 1644-01-01, død 1700-01-01."
  fingerprint_ved_import <- ocr_input_fingerprint(
    "daa:test:ocr-kvalitetsark", "I-15a", "navn", "Mikkel OCR", kontekst
  )
  correction <- list(
    id = 41L, import_key = "daa:test:ocr-kvalitetsark", record_key = "I-15a",
    felt = "navn", input_fingerprint = fingerprint_ved_import,
    korrigeret = '{"value":"Mikkel Rettet"}', status = "rettet"
  )
  index <- index_import_corrections(list(correction))

  uaendret <- apply_import_correction("daa:test:ocr-kvalitetsark", "I-15a", "navn",
                                      "Mikkel OCR", kontekst, index)
  expect_identical(uaendret$status, "anvendt")

  # Samme kontekst, men udtrækket leverer nu en anden importeret værdi.
  aendret <- apply_import_correction("daa:test:ocr-kvalitetsark", "I-15a", "navn",
                                     "Mikael OCR", kontekst, index)
  expect_identical(aendret$status, "stale")
  expect_identical(aendret$value, "Mikael OCR")
  expect_equal(stale_correction_ids(list(aendret)), 41L)
})

# jsonlite::fromJSON() har default null = "list", så JSON-null bliver til list() og ikke
# til NULL. Uden normalisering slipper den nul-længde-værdi hele vejen ind i buffer-rækken,
# hvor unlist() dropper den og kolonnen bliver kortere end tabellen.
test_that("korrektionsværdier normaliseres fra JSON-null til NA", {
  expect_identical(correction_scalar(list()), NA)
  expect_identical(correction_scalar(NULL), NA)
  expect_identical(correction_scalar(character(0)), NA)
  expect_identical(correction_scalar("Mikkel Rettet"), "Mikkel Rettet")
  expect_identical(correction_scalar(list("kvinde")), "kvinde")
  expect_error(correction_scalar(list("a", "b")), "skalar")
})

test_that("en rettet dato med certainty=null giver kun skalarer til buffer-rækken", {
  corrected <- jsonlite::fromJSON(
    '{"raw":"1645-01-01","min":"1645-01-01","max":"1645-01-01","qualifier":"exact","calendar":"gregoriansk","certainty":null}',
    simplifyVector = FALSE)

  expect_identical(length(corrected$certainty), 0L)   # fælden: JSON-null -> list()
  expect_identical(correction_scalar(corrected$certainty), NA)
  expect_identical(correction_scalar(corrected$raw), "1645-01-01")
})

test_that("buffer-kolonner med afvigende længde fejler med tabel- og kolonnenavn", {
  ok <- list(id = c(1L, 2L), vaerdi = c("a", "b"))
  expect_silent(assert_buffer_columns(ok, 2L, "assertion"))

  broken <- list(id = c(1L, 2L, 3L), date_certainty = c(NA, NA))
  expect_error(assert_buffer_columns(broken, 3L, "assertion"),
               "assertion.*date_certainty.*2.*3")
})

test_that("opt-in lokal DB-smoke genafspiller rettelser efter reset og ruller stale tilbage", {
  skip_if_not(identical(Sys.getenv("DAA_RUN_LOCAL_DB_SMOKE"), "1"))

  import_key <- "daa:test:ocr-kvalitetsark"
  record_key <- "I-15a"
  smoke_uid <- "00000000-0000-0000-0000-00000000f505"
  smoke_db <- "daa_person_grid_loader_task5_test"
  root <- normalizePath(file.path(getwd(), "..", ".."))
  fixture <- file.path(root, "tests/fixtures/person-ocr-kvalitetsark-clean.json")
  loader <- file.path(root, ".claude/skills/daa-extract/scripts/load_daa.R")
  # Gate-manifest (#126): loaderen afviser artefakter uden grønt manifest.
  # Testens artefakter (fixturen + afledte tempfiler) er kuraterede rene input,
  # så manifestet skrives ærligt pr. input (sha256 af de faktiske bytes).
  skip_if_not_installed("digest")
  write_manifest <- function(input) {
    poster <- jsonlite::fromJSON(input, simplifyVector = FALSE)
    manifest_path <- paste0(input, ".manifest.json")
    jsonlite::write_json(list(
      artefakt = basename(input),
      sha256 = digest::digest(file = input, algo = "sha256"),
      rene = length(poster), flaggede = 0L, andel_rene = 1.0
    ), manifest_path, auto_unbox = TRUE)
    manifest_path
  }
  on.exit(unlink(paste0(fixture, ".manifest.json")), add = TRUE)
  psql <- "/opt/homebrew/opt/postgresql@17/bin/psql"
  expect_true(grepl("^[a-z0-9_]+$", smoke_db))
  admin <- DBI::dbConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 5432,
                          dbname = "postgres", bigint = "integer")
  DBI::dbExecute(admin, sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE)", smoke_db))
  DBI::dbExecute(admin, sprintf("CREATE DATABASE %s", smoke_db))
  DBI::dbDisconnect(admin)
  drop_smoke_database <- function() {
    admin <- try(DBI::dbConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 5432,
                                dbname = "postgres", bigint = "integer"), silent = TRUE)
    if (!inherits(admin, "try-error")) {
      try(DBI::dbExecute(admin, sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE)", smoke_db)), silent = TRUE)
      DBI::dbDisconnect(admin)
    }
  }
  on.exit(drop_smoke_database(), add = TRUE)

  # Supabase-shim: auth-laget findes ikke i schema.sql. auth.uid() er Supabases
  # ægte definition, som RLS-politikkerne og korrektions-RPC'en bygger på.
  shim <- DBI::dbConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 5432,
                         dbname = smoke_db, bigint = "integer")
  DBI::dbExecute(shim, "
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
    END $$;")
  DBI::dbExecute(shim, "CREATE SCHEMA IF NOT EXISTS auth")
  DBI::dbExecute(shim, "CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, email text)")
  DBI::dbExecute(shim, "
    CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
    $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;")
  DBI::dbDisconnect(shim)

  for (sql_file in c("schema.sql", "db-migrations.sql", "db-rls.sql")) {
    output <- system2(psql, c("-h", "127.0.0.1", "-d", smoke_db, "-v", "ON_ERROR_STOP=1",
                              "-f", file.path(root, sql_file)), stdout = TRUE, stderr = TRUE)
    if (!identical(attr(output, "status") %||% 0L, 0L))
      stop("Kunne ikke oprette lokal smoke-database med ", sql_file, ":\n", paste(output, collapse = "\n"))
  }
  con <- DBI::dbConnect(RPostgres::Postgres(), host = "127.0.0.1", port = 5432,
                        dbname = smoke_db, bigint = "integer")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  cleanup <- function() {
    try(DBI::dbExecute(con, "DROP TRIGGER IF EXISTS daa_loader_smoke_fail ON person"), silent = TRUE)
    try(DBI::dbExecute(con, "DROP FUNCTION IF EXISTS daa_loader_smoke_fail()"), silent = TRUE)
    try(DBI::dbExecute(con, "DELETE FROM import_korrektion WHERE import_key=$1", params = list(import_key)), silent = TRUE)
    try(DBI::dbExecute(con, "DELETE FROM change_set WHERE operation='red_ret_ocr_felt' AND summary LIKE $1",
                       params = list(paste0("OCR-%: ", import_key, "/%"))), silent = TRUE)
    # Samme fulde reset-kontrakt som loaderen (#124): model + versionering,
    # ellers genindfører testens egen cleanup stale-historik-klassen lokalt.
    try(DBI::dbExecute(con, paste0("TRUNCATE ", paste(c(loader_model_tables(), loader_versioning_tables()), collapse = ", "), " RESTART IDENTITY CASCADE")), silent = TRUE)
    try(DBI::dbExecute(con, "DELETE FROM profiles WHERE id=$1", params = list(smoke_uid)), silent = TRUE)
    try(DBI::dbExecute(con, "DELETE FROM auth.users WHERE id=$1", params = list(smoke_uid)), silent = TRUE)
  }
  cleanup()
  on.exit(cleanup(), add = TRUE)

  # R indlæser ~/.Renviron ved opstart og OVERSKRIVER arvede miljøvariabler. Uden
  # R_ENVIRON_USER=/dev/null ville child-loaderen ignorere SUPABASE_* nedenfor og
  # forbinde til den rigtige (produktions-)vært fra ~/.Renviron.
  child_env <- c("R_ENVIRON_USER=/dev/null",
                 "SUPABASE_HOST=127.0.0.1", "SUPABASE_PORT=5432", paste0("SUPABASE_DB=", smoke_db),
                 "SUPABASE_USER=johanreventlow", "SUPABASE_PASSWORD=local-test-only",
                 "SUPABASE_SSLMODE=disable")

  # Fail-closed: bevis at child-processen faktisk ser den disponible lokale database,
  # før loaderen får lov at skrive noget som helst.
  probe <- system2("Rscript", c("-e", shQuote('cat(Sys.getenv("SUPABASE_HOST"), Sys.getenv("SUPABASE_DB"))')),
                   stdout = TRUE, stderr = TRUE, env = child_env)
  expect_identical(paste(probe, collapse = " "), paste("127.0.0.1", smoke_db))
  if (!identical(paste(probe, collapse = " "), paste("127.0.0.1", smoke_db)))
    stop("Child-R ser ikke smoke-databasen (~/.Renviron-override?); afbryder før skrivning: ",
         paste(probe, collapse = " "))

  run_loader <- function(input, reset = FALSE) {
    write_manifest(input)
    args <- c(loader, input, shQuote("DAA OCR-fixture 2026"), paste0("--import-key=", import_key))
    if (reset) args <- c(args, "--reset")
    old_wd <- setwd(root)
    on.exit(setwd(old_wd), add = TRUE)
    output <- system2("Rscript", args, stdout = TRUE, stderr = TRUE, env = child_env)
    list(status = attr(output, "status") %||% 0L, output = output)
  }
  scalar <- function(sql, params = list()) DBI::dbGetQuery(con, sql, params = params)[[1]][1]
  set_redaktion <- function() {
    DBI::dbExecute(con, "INSERT INTO auth.users(id,email) VALUES ($1,$2)",
                   params = list(smoke_uid, "loader-smoke@test.invalid"))
    DBI::dbExecute(con, "INSERT INTO profiles(id,rolle,email) VALUES ($1,'redaktion',$2)",
                   params = list(smoke_uid, "loader-smoke@test.invalid"))
    DBI::dbExecute(con, "SELECT set_config('request.jwt.claim.sub',$1,false)", params = list(smoke_uid))
  }
  grid_field <- function(person_id, felt) scalar(
    sprintf("SELECT input_fingerprint->>'%s' FROM red_person_grid() WHERE person_id=$1", felt), list(person_id)
  )
  call_correction <- function(person_id, felt, value) {
    fingerprint <- grid_field(person_id, felt)
    DBI::dbGetQuery(con,
      "SELECT red_ret_ocr_felt($1,$2,$3,$4,$5,$6::jsonb,'rettet')",
      params = list(person_id, import_key, record_key, felt, fingerprint, value))
  }

  initial <- run_loader(fixture, reset = TRUE)
  expect_identical(initial$status, 0L, info = paste(initial$output, collapse = "\n"))
  if (!identical(initial$status, 0L)) return(invisible())
  first_id <- scalar("SELECT person_id FROM person_external_id pei JOIN source s ON s.id=pei.source_id WHERE s.import_key=$1 AND pei.record_key=$2",
                     list(import_key, record_key))
  set_redaktion()
  call_correction(first_id, "navn", '{"value":"Mikkel Rettet"}')
  call_correction(first_id, "foedsel", '{"raw":"1645-01-01","min":"1645-01-01","max":"1645-01-01","qualifier":"exact","calendar":"gregoriansk","certainty":null}')
  call_correction(first_id, "doed", '{"raw":"1701-01-01","min":"1701-01-01","max":"1701-01-01","qualifier":"exact","calendar":"gregoriansk","certainty":null}')
  call_correction(first_id, "koen", '{"value":"kvinde"}')
  journal_id <- scalar("SELECT id FROM import_korrektion WHERE import_key=$1 AND record_key=$2 AND felt='navn'",
                       list(import_key, record_key))

  records <- jsonlite::fromJSON(fixture, simplifyVector = FALSE)
  reordered <- tempfile(fileext = ".json")
  jsonlite::write_json(rev(records), reordered, auto_unbox = TRUE, pretty = TRUE, null = "null")
  replay <- run_loader(reordered, reset = TRUE)
  expect_identical(replay$status, 0L, info = paste(replay$output, collapse = "\n"))
  second_id <- scalar("SELECT person_id FROM person_external_id pei JOIN source s ON s.id=pei.source_id WHERE s.import_key=$1 AND pei.record_key=$2",
                      list(import_key, record_key))
  expect_false(identical(first_id, second_id))
  expect_identical(scalar("SELECT visning_navn FROM person WHERE id=$1", list(second_id)), "Mikkel Rettet")
  expect_identical(scalar("SELECT koen FROM person WHERE id=$1", list(second_id)), "kvinde")
  expect_identical(scalar("SELECT a.date_raw FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id JOIN assertion a ON a.id=c.valgt_assertion_id WHERE f.subjekt_id=$1 AND f.faktatype='fødsel'", list(second_id)), "1645-01-01")
  expect_identical(scalar("SELECT a.date_raw FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id JOIN assertion a ON a.id=c.valgt_assertion_id WHERE f.subjekt_id=$1 AND f.faktatype='død'", list(second_id)), "1701-01-01")
  expect_identical(scalar("SELECT id FROM import_korrektion WHERE import_key=$1 AND record_key=$2 AND felt='navn'", list(import_key, record_key)), journal_id)

  stale_records <- jsonlite::fromJSON(reordered, simplifyVector = FALSE)
  stale_records[[2]]$navn_kilde_span <- "Mikkel OCR ændret OCR-kontekst."
  stale_input <- tempfile(fileext = ".json")
  jsonlite::write_json(stale_records, stale_input, auto_unbox = TRUE, pretty = TRUE, null = "null")
  stale <- run_loader(stale_input, reset = TRUE)
  expect_identical(stale$status, 0L, info = paste(stale$output, collapse = "\n"))
  stale_id <- scalar("SELECT person_id FROM person_external_id pei JOIN source s ON s.id=pei.source_id WHERE s.import_key=$1 AND pei.record_key=$2", list(import_key, record_key))
  expect_identical(scalar("SELECT visning_navn FROM person WHERE id=$1", list(stale_id)), "Mikkel OCR")
  expect_identical(scalar("SELECT status FROM import_korrektion WHERE id=$1", list(journal_id)), "stale")

  DBI::dbExecute(con, "UPDATE import_korrektion SET status='rettet' WHERE id=$1", params = list(journal_id))
  DBI::dbExecute(con, "CREATE FUNCTION daa_loader_smoke_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'DAA_SMOKE_AFTER_STALE'; END $$")
  DBI::dbExecute(con, "CREATE TRIGGER daa_loader_smoke_fail BEFORE UPDATE ON person FOR EACH STATEMENT EXECUTE FUNCTION daa_loader_smoke_fail()")
  # Denne kørsel SKAL fejle (triggeren ovenfor); system2's exit-status-warning er forventet.
  failed <- suppressWarnings(run_loader(stale_input, reset = TRUE))
  expect_false(identical(failed$status, 0L))
  expect_match(paste(failed$output, collapse = "\n"), "DAA_SMOKE_AFTER_STALE")
  expect_identical(scalar("SELECT status FROM import_korrektion WHERE id=$1", list(journal_id)), "rettet")
})
