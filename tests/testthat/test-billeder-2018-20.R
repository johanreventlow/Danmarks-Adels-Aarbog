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
  expect_equal(portraet_handling(data.frame(media_id = c("1", "2"), slags = c("våben", "portræt"),
                                            primaer = c(FALSE, TRUE)))$handling, "behold")
  h <- portraet_handling(data.frame(media_id = c("1", "2"), slags = c("våben", " Portræt "),
                                    primaer = c(FALSE, FALSE)))
  expect_equal(h, list(handling = "laas", media_id = "2", person_id = NA_character_))
  uden_slags <- portraet_handling(data.frame(media_id = c("7", "8"), slags = c("våben", NA),
                                             primaer = c(FALSE, FALSE)))
  expect_equal(uden_slags, list(handling = "laas", media_id = "7", person_id = NA_character_))
})

test_that("plan: sikker egen kan publiceres, usikre og uafklarede kan ikke uden svar", {
  p <- byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier)
  expect_equal(p$noegle, c("a", "b", "c", "d"))
  expect_equal(p$maa_publiceres, c(FALSE, FALSE, TRUE, FALSE))
})

test_that("plan: låser kun ét portræt pr. person, selv med flere nye billeder", {
  m <- list(billeder = list(manifest_fix$billeder[[3]], modifyList(manifest_fix$billeder[[3]], list(noegle = "c2"))))
  medier <- data.frame(person_id = "501", media_id = "77", slags = "portræt", primaer = FALSE)
  p <- byg_plan(m, ext_fix, aeg_fix, medier)
  expect_equal(p$portraet[[1]][["501"]][c("handling", "media_id")], list(handling = "laas", media_id = "77"))
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

test_that("teknik fra billedteksten gemmes som faktum efter kreditlinjen (spec 2026-11-25-media-slags-ordliste)", {
  log <- anvend_med_fake(c(ny_raekke, list(teknik = "Maleri")), eksisterende = NULL)
  expect_equal(tail(log$rpc, 2), c("red_upsert_fakta", "red_upsert_fakta"))
  expect_equal(log$args$red_upsert_fakta$p_faktatype, "teknik")
  expect_equal(log$args$red_upsert_fakta$p_vaerdi, "Maleri")
  expect_equal(log$args$red_upsert_fakta$p_kilde_fritekst, "DAA 2018-20, s. 150")
  # uden teknik: kun kreditlinjen
  uden <- anvend_med_fake(c(ny_raekke, list(teknik = NULL)), eksisterende = NULL)
  expect_equal(sum(uden$rpc == "red_upsert_fakta"), 1L)
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

test_that("ægtefælle uden årstal i billedteksten vælter ikke og går til gennemgang", {
  to <- aeg_fix[, c("person_id", "visning_navn", "foedt_aar", "doed_aar")]
  ingen_aar <- match_aegtefaelle(c(NA_integer_, NA_integer_), "Emilia", to)
  expect_true(is.na(ingen_aar$person_id))
  expect_false(ingen_aar$sikker)
  en <- match_aegtefaelle(c(NA_integer_, NA_integer_), "Emilia", to[1, ])
  expect_equal(en$person_id, "9")
  expect_false(en$sikker)
})


# --- Final review-rettelser ---------------------------------------------------------------------------------

test_that("egen med ekstra tekst (»og hustru …«) går til gennemgang og kan ikke publiceres uden svar", {
  b <- modifyList(manifest_fix$billeder[[3]], list(ekstra_tekst = TRUE))
  r <- opslaa_afbildede(b, ext_fix, aeg_fix)
  expect_equal(r$person_ids, "501")
  expect_false(r$sikker)
  expect_match(r$begrundelse, "nævner mere")
  p <- byg_plan(list(billeder = list(b)), ext_fix, aeg_fix, tom_medier)
  expect_false(p$maa_publiceres)
})

test_that("portrætlås peger på det id, relationen faktisk sidder på (alias), og ignorerer fjernede medier", {
  medier <- data.frame(media_id = c("1", "2"), slags = c("portræt", "portræt"), primaer = c(FALSE, FALSE),
                       medlem = c("1600", "501"), upload_status = c("fjernet", "klar"))
  expect_equal(portraet_handling(medier), list(handling = "laas", media_id = "2", person_id = "501"))
  alias <- data.frame(media_id = "3", slags = "portræt", primaer = FALSE, medlem = "1600", upload_status = "klar")
  expect_equal(portraet_handling(alias)$person_id, "1600")
  kun_fjernet <- data.frame(media_id = "1", slags = "portræt", primaer = FALSE, medlem = "501", upload_status = "fjernet")
  expect_equal(portraet_handling(kun_fjernet)$handling, "ingen")
})

test_that("låsen kaldes på aliasets id", {
  r <- ny_raekke
  r$portraet[["501"]] <- list(handling = "laas", media_id = "42", person_id = "1600")
  log <- anvend_med_fake(r, eksisterende = NULL)
  expect_equal(log$args$red_saet_portraet, list(p_person_id = "1600", p_media_id = "42"))
})

test_that("OK er bundet til det forslag, projektejeren så", {
  svar <- data.frame(noegle = "b", svar = "OK")
  svar$person_ids <- I(list(character()))
  svar$forslag <- I(list(c("503", "504", "505")))
  expect_true(byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier, svar)$maa_publiceres[2])
  svar$forslag <- I(list(c("503", "504", "999")))
  expect_error(byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier, svar), "SVAR_FORSLAG_AENDRET")
})

test_that("svar på en ukendt nøgle afvises", {
  svar <- data.frame(noegle = "zzz", svar = "skjul")
  svar$person_ids <- I(list(character()))
  svar$forslag <- I(list(character()))
  expect_error(byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier, svar), "SVAR_UKENDT_NOEGLE")
})

test_that("gennemgangsfilen bærer manifestets sha256 og forslagene læses tilbage", {
  p <- byg_plan(manifest_fix, ext_fix, aeg_fix, tom_medier)
  sti <- tempfile(fileext = ".txt")
  skriv_gennemgang(p, sti, manifest_sha = "cafe01")
  s <- laes_svar(sti)
  expect_equal(attr(s, "manifest_sha"), "cafe01")
  linjer <- readLines(sti, encoding = "UTF-8")
  b <- grep("^b \\|", linjer)
  linjer[b] <- paste0(linjer[b], "OK")
  writeLines(linjer, sti, useBytes = TRUE)
  s <- laes_svar(sti)
  expect_equal(s$forslag[[1]], c("503", "504", "505"))
})

test_that("en ny prøvekørsel overskriver ikke en besvaret gennemgangsfil", {
  mappe <- tempfile(); dir.create(mappe)
  expect_equal(basename(gennemgang_sti(mappe)), "gennemgang.txt")
  writeLines("x", file.path(mappe, "gennemgang.txt"))
  expect_equal(basename(gennemgang_sti(mappe)), "gennemgang.ny.txt")
})

test_that("--proev-binding er et eget, ikke-skrivende flag", {
  a <- parse_billede_args("--proev-binding")
  expect_true(a$proev_binding)
  expect_false(a$skriv)
  expect_error(parse_billede_args(c("--proev-binding", "--jeg-mener-det")), "kan ikke kombineres")
})

test_that("optag_kald giver de præcise RPC-kald for ét billede, også lås og ekstra person", {
  r <- ny_raekke
  r$portraet[["501"]] <- list(handling = "laas", media_id = "42", person_id = "501")
  kald <- optag_kald(r)
  expect_equal(vapply(kald, `[[`, character(1), "navn"),
               c("red_saet_portraet", "red_upload_media", "red_relation", "red_registrer_media_variant",
                 "red_registrer_media_variant", "red_bekraeft_media_upload", "red_upsert_fakta"))
  expect_equal(kald[[2]]$args$p_original_filnavn, "daa-2018-20-s0150-1.jpg")
})

test_that("binding er bevist ved read-only- eller funktionsfejl, ikke ved typefejl", {
  expect_true(binding_ok("25006"))
  expect_true(binding_ok("P0001"))
  expect_false(binding_ok("42883"))
  expect_false(binding_ok("22P02"))
  expect_false(binding_ok(NA_character_))
})

test_that("sqlstate udledes af beskeden, også med ugyldige bytes (ø/æ i CONTEXT)", {
  m <- paste0("ERROR:  cannot execute INSERT in a read-only transaction\nCONTEXT: Uploadede media \xf8 ", "x")
  expect_equal(sqlstate_fra_besked(m), "25006")
  expect_equal(sqlstate_fra_besked("ERROR:  function public.red_x(p_a => unknown) does not exist"), "42883")
  expect_true(is.na(sqlstate_fra_besked("noget andet")))
})

# --- Runde 2: egne filer pr. manifest ----------------------------------------------------------------------------

test_that("ud_sti: runde 1 beholder navnene, runde 2 får endelsen -runde2", {
  expect_equal(ud_sti("m", "m/manifest.json", "plan.csv"), file.path("m", "plan.csv"))
  expect_equal(ud_sti("m", "m/manifest-runde2.json", "plan.csv"), file.path("m", "plan-runde2.csv"))
  expect_equal(ud_sti("m", "m/manifest-runde2.json", "gennemgang.txt"), file.path("m", "gennemgang-runde2.txt"))
})

test_that("runde 2 rører ikke runde 1's besvarede gennemgangsfil", {
  mappe <- tempfile(); dir.create(mappe)
  writeLines("runde 1 svar", file.path(mappe, "gennemgang.txt"))
  sti <- gennemgang_sti(mappe, file.path(mappe, "manifest-runde2.json"))
  expect_equal(basename(sti), "gennemgang-runde2.txt")
  writeLines("x", sti)
  expect_equal(basename(gennemgang_sti(mappe, file.path(mappe, "manifest-runde2.json"))), "gennemgang-runde2.ny.txt")
  expect_equal(readLines(file.path(mappe, "gennemgang.txt")), "runde 1 svar")
})

# --- Runde 3: objekt-koblinger (media → lineage/estate) ---------------------------------------------------------

objekt_billede <- billede('{"noegle":"daa-2018-20-s0055-1","side":55,"titel":"Lensgreve","klasse":"objekt","refs":[],
                           "aegtefaelle_anker":null,"objekt":{"type":"lineage","id":4}}')

test_that("objekt-billede er sikkert og kan publiceres uden personer", {
  r <- opslaa_afbildede(objekt_billede, ext_fix, aeg_fix)
  expect_equal(r$person_ids, character())
  expect_true(r$sikker)
  p <- byg_plan(list(billeder = list(objekt_billede)), ext_fix, aeg_fix, tom_medier)
  expect_true(p$maa_publiceres)
  expect_equal(p$objekt[[1]], list(type = "lineage", id = 4L))
  expect_length(p$portraet[[1]], 0)
})

test_that("objekt-billede kobles via p_objekt_type/p_objekt_id og aldrig til en person", {
  r <- ny_raekke
  r$person_ids <- character(); r$portraet <- list(); r$objekt <- list(type = "lineage", id = 4L)
  log <- anvend_med_fake(r, eksisterende = NULL)
  a <- log$args$red_upload_media
  expect_equal(a$p_objekt_type, "lineage")
  expect_equal(a$p_objekt_id, "4")
  expect_null(a$p_afbildet_person_id)
  expect_false("red_relation" %in% log$rpc)
})

test_that("objekt-billede kan også kobles til kuraterede personer (Vallø + Anna Sophia), og de skal findes", {
  med_person <- objekt_billede; med_person$refs <- list(list("V", 106))
  r <- opslaa_afbildede(med_person, ext_fix, aeg_fix)
  expect_equal(r$person_ids, "501")
  expect_true(r$sikker)
  ukendt <- objekt_billede; ukendt$refs <- list(list("I", 999))
  r <- opslaa_afbildede(ukendt, ext_fix, aeg_fix)
  expect_false(r$sikker)
  p <- byg_plan(list(billeder = list(ukendt)), ext_fix, aeg_fix, tom_medier)
  expect_false(p$maa_publiceres)
})

test_that("objekt + person: både p_afbildet_person_id og p_objekt_type sendes", {
  r <- ny_raekke
  r$person_ids <- "470"; r$portraet <- list(); r$objekt <- list(type = "estate", id = 196L)
  log <- anvend_med_fake(r, eksisterende = NULL)
  a <- log$args$red_upload_media
  expect_equal(a$p_afbildet_person_id, "470")
  expect_equal(a$p_objekt_type, "estate")
  expect_equal(a$p_objekt_id, "196")
})
