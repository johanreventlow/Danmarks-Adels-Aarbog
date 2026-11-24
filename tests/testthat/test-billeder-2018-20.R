root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(root, "R", "billeder-2018-20-load.R"))

billede <- function(json) jsonlite::fromJSON(json, simplifyVector = FALSE)

ext_fix <- data.frame(linje = c("V", "IV", "V", "V", "V"), nr = c(106L, 2L, 192L, 194L, 193L),
                      person_id = c("501", "502", "503", "504", "505"))
aeg_fix <- data.frame(anker_person_id = c("502", "502"), person_id = c("9", "10"),
                      visning_navn = c("Emilia Bernstorff", "Anna X"),
                      foedt_aar = c(1766L, 1770L), doed_aar = c(1855L, 1840L))
tom_medier <- data.frame(person_id = character(), media_id = character(), slags = character(),
                         primaer = logical())

manifest_fix <- list(billeder = list(
  billede('{"noegle":"a","side":185,"titel":"Emilia","klasse":"aegtefaelle","refs":[],
            "aegtefaelle_anker":["IV",2],"aegtefaelle_navn":"Emilia","aegtefaelle_aar":[1700,1750]}'),
  billede('{"noegle":"b","side":365,"titel":"Fra venstre","klasse":"gruppe",
            "refs":[["V",192],["V",194],["V",193]],"aegtefaelle_anker":null}'),
  billede('{"noegle":"c","side":300,"titel":"Hofjægermester","klasse":"egen","refs":[["V",106]],
            "aegtefaelle_anker":null}'),
  billede('{"noegle":"d","side":272,"titel":"","klasse":"uafklaret","refs":[],"aegtefaelle_anker":null}')
))

test_that("egen ref slås op i person_external_id", {
  r <- opslaa_afbildede(manifest_fix$billeder[[3]], ext_fix, aeg_fix)
  expect_equal(r$person_ids, "501")
  expect_true(r$sikker)
})

test_that("ukendt ref giver NA og er usikker", {
  b <- billede('{"klasse":"egen","refs":[["I",999]],"aegtefaelle_anker":null}')
  r <- opslaa_afbildede(b, ext_fix, aeg_fix)
  expect_true(is.na(r$person_ids))
  expect_false(r$sikker)
})

test_that("ægtefælle er sikker kun ved entydigt årsmatch", {
  to <- aeg_fix[, c("person_id", "visning_navn", "foedt_aar", "doed_aar")]
  m <- match_aegtefaelle(c(1766L, 1855L), "Emilia", to)
  expect_equal(m$person_id, "9")
  expect_true(m$sikker)
  samme <- transform(to, foedt_aar = 1766L, doed_aar = 1855L)
  expect_false(match_aegtefaelle(c(1766L, 1855L), "Emilia", samme)$sikker)
  ingen <- match_aegtefaelle(c(1700L, 1750L), "X", to)
  expect_true(is.na(ingen$person_id))
  expect_false(ingen$sikker)
})

test_that("ægtefælle uden dødsår matcher på fødeår", {
  to <- aeg_fix[, c("person_id", "visning_navn", "foedt_aar", "doed_aar")]
  m <- match_aegtefaelle(c(1766L, NA), "Emilia", to)
  expect_equal(m$person_id, "9")
  expect_true(m$sikker)
})

test_that("eneste ægtefælle uden årsmatch foreslås, men usikkert", {
  en <- aeg_fix[1, c("person_id", "visning_navn", "foedt_aar", "doed_aar")]
  m <- match_aegtefaelle(c(1700L, 1750L), "Emilia", en)
  expect_equal(m$person_id, "9")
  expect_false(m$sikker)
})

test_that("gruppe slås op, men går altid til gennemgang", {
  r <- opslaa_afbildede(manifest_fix$billeder[[2]], ext_fix, aeg_fix)
  expect_equal(r$person_ids, c("503", "504", "505"))
  expect_false(r$sikker)
})

test_that("gruppe med én ukoblet person må ikke publiceres", {
  expect_false(kan_publiceres(c("1", NA), alle_koblet = FALSE))
  expect_false(kan_publiceres(c("1", NA), alle_koblet = TRUE))
  expect_false(kan_publiceres(character(), alle_koblet = TRUE))
  expect_true(kan_publiceres(c("1", "2"), alle_koblet = TRUE))
})

test_that("portræt: ingen billeder → ingen; primaer → behold; billeder uden primaer → lås det viste", {
  tom <- data.frame(media_id = character(), slags = character(), primaer = logical())
  expect_equal(portraet_handling(tom)$handling, "ingen")
  expect_equal(portraet_handling(data.frame(media_id = c("1", "2"), slags = c("scanning", "foto"),
                                            primaer = c(FALSE, TRUE)))$handling, "behold")
  h <- portraet_handling(data.frame(media_id = c("1", "2"), slags = c("scanning", " Foto "),
                                    primaer = c(FALSE, FALSE)))
  expect_equal(h, list(handling = "laas", media_id = "2"))
  uden_slags <- portraet_handling(data.frame(media_id = c("7", "8"), slags = c("scanning", NA),
                                             primaer = c(FALSE, FALSE)))
  expect_equal(uden_slags, list(handling = "laas", media_id = "7"))
})

test_that("plan: sikker egen kan publiceres, usikre og uafklarede kan ikke uden svar", {
  p <- byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier)
  expect_equal(p$noegle, c("a", "b", "c", "d"))
  expect_equal(p$maa_publiceres, c(FALSE, FALSE, TRUE, FALSE))
})

test_that("plan: låser kun ét portræt pr. person, selv med flere nye billeder", {
  m <- list(billeder = list(manifest_fix$billeder[[3]], modifyList(manifest_fix$billeder[[3]], list(noegle = "c2"))))
  medier <- data.frame(person_id = "501", media_id = "77", slags = "foto", primaer = FALSE)
  p <- byg_plan(m, ext_fix, aeg_fix, medier)
  expect_equal(p$portraet[[1]][["501"]], list(handling = "laas", media_id = "77"))
  expect_equal(p$portraet[[2]][["501"]]$handling, "behold")
})

test_that("usikre koblinger og svar: OK/ret/skjul", {
  svar <- data.frame(noegle = c("a", "b", "c"), svar = c("ret", "OK", "skjul"))
  svar$person_ids <- I(list("7", character(), character()))
  p <- byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier, svar)
  expect_equal(p$person_ids[[which(p$noegle == "a")]], "7")
  expect_true(p$maa_publiceres[p$noegle == "a"])
  expect_true(p$maa_publiceres[p$noegle == "b"])
  expect_false(p$maa_publiceres[p$noegle == "c"])
  expect_false(p$maa_publiceres[p$noegle == "d"])
})

test_that("gennemgangsfil: kun usikre, læses tilbage som svar", {
  p <- byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier)
  sti <- tempfile(fileext = ".txt")
  skriv_gennemgang(p, sti)
  linjer <- readLines(sti, encoding = "UTF-8")
  data_linjer <- grep("^[^#]", linjer, value = TRUE)
  expect_equal(sub(" \\|.*", "", data_linjer), c("a", "b", "d"))
  data_linjer[1] <- paste0(data_linjer[1], "ret 7, 8")
  data_linjer[2] <- paste0(data_linjer[2], "OK")
  writeLines(data_linjer, sti, useBytes = TRUE)
  s <- laes_svar(sti)
  expect_equal(s$noegle, c("a", "b"))
  expect_equal(s$svar, c("ret", "OK"))
  expect_equal(s$person_ids[[1]], c("7", "8"))
})

test_that("ugyldigt svar afvises", {
  sti <- tempfile(fileext = ".txt")
  writeLines("a | 185 | Emilia | forslag: 9 | svar: måske", sti)
  expect_error(laes_svar(sti), "Ugyldigt svar")
})

test_that("args: plan er standard, --jeg-mener-det skriver", {
  a <- parse_billede_args(character())
  expect_false(a$skriv)
  expect_equal(a$manifest, "work_2018_saerudgave/billeder/manifest.json")
  expect_null(a$svar)
  expect_true(parse_billede_args("--jeg-mener-det")$skriv)
  expect_equal(parse_billede_args(c("--svar", "x.txt"))$svar, "x.txt")
  expect_error(parse_billede_args("--ukendt"), "Ukendt flag")
  expect_error(parse_billede_args("--svar"), "kræver en sti")
})

# --- Task 3: skrivning via injicerede ops --------------------------------------------------------------------

ny_raekke <- list(
  noegle = "daa-2018-20-s0150-1", side = 150L, person_ids = c("501", "502"), maa_publiceres = TRUE,
  portraet = list("501" = list(handling = "ingen", media_id = NA_character_),
                  "502" = list(handling = "behold", media_id = NA_character_)),
  sha256 = "abcdef0123", titel = "Tysk kansler Detlef von Reventlow", kunstner = NULL, datering = NULL,
  slags = "portræt",
  filer = list(large = "k-large.jpg", medium = "k-medium.jpg", thumb = "k-thumb.jpg"),
  dims = list(large = list(499L, 754L), medium = list(499L, 754L), thumb = list(499L, 754L)),
  bytes = list(large = 57000L, medium = 40000L, thumb = 30000L)
)

med_portraet <- function(r, handling, media_id) {
  r$portraet[["501"]] <- list(handling = handling, media_id = media_id)
  r
}

anvend_med_fake <- function(raekke, eksisterende, har_variant = c(thumb = FALSE, medium = FALSE),
                            rolle = "redaktion") {
  log <- new.env()
  log$upload <- character(); log$rpc <- character(); log$args <- list()
  ops <- list(
    find_media = function(filnavn) { log$find <- filnavn; eksisterende },
    upload = function(sti, fil) log$upload <- c(log$upload, sti),
    transaktion = function(fn) fn(),
    aktoer = function(uuid) { log$rpc <- c(log$rpc, "set_config"); log$uuid <- uuid; rolle },
    rpc = function(navn, args) {
      log$rpc <- c(log$rpc, navn)
      log$args[[navn]] <- args
      if (navn == "red_upload_media") "900" else NULL
    },
    har_variant = function(media_id, tier) unname(har_variant[[tier]])
  )
  log$resultat <- anvend_billede(raekke, "/manifestmappe", ops)
  as.list(log)
}

test_that("nyt billede: bytes først, så RPC-rækkefølgen", {
  log <- anvend_med_fake(ny_raekke, eksisterende = NULL)
  expect_equal(log$resultat, "importeret")
  expect_equal(log$find, "daa-2018-20-s0150-1.jpg")
  expect_equal(log$upload, c("redaktor/ab/abcdef0123-large.jpg", "redaktor/ab/abcdef0123-medium.jpg",
                             "redaktor/ab/abcdef0123-thumb.jpg"))
  expect_equal(log$rpc, c("set_config", "red_upload_media", "red_relation", "red_registrer_media_variant",
                          "red_registrer_media_variant", "red_bekraeft_media_upload", "red_upsert_fakta"))
  expect_equal(log$uuid, "ba4ce28d-42a0-48af-a47c-773c26934236")
  a <- log$args$red_upload_media
  expect_equal(a$p_original_filnavn, "daa-2018-20-s0150-1.jpg")
  expect_equal(a$p_rettigheder_status, "ukendt")
  expect_true(a$p_maa_publiceres)
  expect_equal(a$p_storage_path, "redaktor/ab/abcdef0123-large.jpg")
  expect_equal(a$p_afbildet_person_id, "501")
  expect_equal(a$p_sha256, "abcdef0123")
  expect_equal(log$args$red_relation$p_subjekt_id, "502")
  expect_equal(log$args$red_relation$p_objekt_id, "900")
  expect_equal(log$args$red_relation$p_rolle, "afbildet")
  expect_equal(log$args$red_upsert_fakta$p_vaerdi, "Gengivet fra Danmarks Adels Aarbog 2018-20, s. 150")
  expect_equal(log$args$red_upsert_fakta$p_faktatype, "kreditlinje")
  expect_equal(log$args$red_upsert_fakta$p_subjekt_id, "900")
})

test_that("lås nuværende portræt FØR koblingen", {
  log <- anvend_med_fake(med_portraet(ny_raekke, "laas", "42"), eksisterende = NULL)
  expect_lt(which(log$rpc == "red_saet_portraet"), which(log$rpc == "red_upload_media"))
  expect_equal(log$args$red_saet_portraet, list(p_person_id = "501", p_media_id = "42"))
})

test_that("klar → springes over uden kald", {
  log <- anvend_med_fake(ny_raekke, eksisterende = list(id = "5", upload_status = "klar"))
  expect_equal(log$resultat, "sprunget_over")
  expect_length(log$rpc, 0)
  expect_length(log$upload, 0)
})

test_that("kladde → genoptag manglende varianter + bekræft, ingen ny red_upload_media", {
  log <- anvend_med_fake(ny_raekke, eksisterende = list(id = "5", upload_status = "kladde"),
                         har_variant = c(thumb = TRUE, medium = FALSE))
  expect_equal(log$resultat, "genoptaget")
  expect_false("red_upload_media" %in% log$rpc)
  expect_equal(sum(log$rpc == "red_registrer_media_variant"), 1)
  expect_equal(log$args$red_registrer_media_variant$p_tier, "medium")
  expect_true("red_bekraeft_media_upload" %in% log$rpc)
})

test_that("maa_publiceres følger planen", {
  r <- ny_raekke; r$maa_publiceres <- FALSE
  log <- anvend_med_fake(r, eksisterende = NULL)
  expect_false(log$args$red_upload_media$p_maa_publiceres)
})

test_that("ukoblede personer springes over ved koblingen", {
  r <- ny_raekke; r$person_ids <- c(NA, "502"); r$maa_publiceres <- FALSE
  log <- anvend_med_fake(r, eksisterende = NULL)
  expect_equal(log$args$red_upload_media$p_afbildet_person_id, "502")
  expect_false("red_relation" %in% log$rpc)
  r$person_ids <- NA_character_
  log <- anvend_med_fake(r, eksisterende = NULL)
  expect_null(log$args$red_upload_media$p_afbildet_person_id)
})

test_that("rollegate: forkert rolle stopper før skrivning", {
  expect_error(anvend_med_fake(ny_raekke, eksisterende = NULL, rolle = "medlem"), "BILLEDER_ACTOR_NOT_REDAKTION")
})

test_that("RPC-SQL bruger navngivne parametre", {
  expect_equal(byg_rpc_sql("red_x", list(p_a = 1, p_b = "x")), "SELECT public.red_x(p_a => $1, p_b => $2)")
  expect_equal(byg_rpc_sql("red_y", list()), "SELECT public.red_y()")
})

test_that("storage-stier følger buildShaStoragePaths", {
  expect_equal(billede_sti("abcdef", "thumb"), "redaktor/ab/abcdef-thumb.jpg")
})
