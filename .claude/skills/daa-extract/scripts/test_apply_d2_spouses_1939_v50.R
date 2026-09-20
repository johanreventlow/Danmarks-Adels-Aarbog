## DB-fri tests for apply_d2_spouses_1939_v50_helpers.R -- CLI-gaten og
## guarden mod at basen har flyttet sig siden eksporten.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_d2_spouses_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

## --- CLI-gaten ---------------------------------------------------------
## 1) Lykkelig sti.
parsed <- d2_parse_apply_args(c("--selection", "s.json", "--expect-sha256", "abc",
                                "--backup", "b.dump", "--jeg-mener-det"))
expect(identical(parsed$selection, "s.json"))
expect(identical(parsed$expect_sha256, "abc"))
expect(identical(parsed$backup, "b.dump"))

## 2) UDEN bekraeftelses-flaget skal den afvise. Dette er hele pointen:
##    i fase D1 blev et opfundet --dryrun ignoreret, og 68 personer blev
##    publiceret i prod uden godkendelse.
expect_error(d2_parse_apply_args(c("--selection", "s.json", "--expect-sha256", "abc",
                                   "--backup", "b.dump")),
             "D2_APPLY_CONFIRMATION_REQUIRED")

## 2b) Hash-laasen er OBLIGATORISK. Uden den kan et haandredigeret
##     udvalgsdokument saette sin egen forventning til efterkontrollen, som
##     saa "bekraefter" den. Det er den sidste haandredigerings-vej i en
##     wrapper hvis hele formaal er at vaere fail-closed.
expect_error(d2_parse_apply_args(c("--selection", "s.json", "--backup", "b.dump",
                                   "--jeg-mener-det")),
             "D2_APPLY_SHA_REQUIRED")

## 2c) Basen koerer paa free tier UDEN automatisk backup. At tage en dump er
##     en instruktion i planen; her er det en betingelse for at koere.
expect_error(d2_parse_apply_args(c("--selection", "s.json", "--expect-sha256",
                                   "abc", "--jeg-mener-det")),
             "D2_APPLY_BACKUP_REQUIRED")

## 3) Et UKENDT flag maa aldrig blive til tavs accept.
expect_error(
  d2_parse_apply_args(c("--selection", "s.json", "--expect-sha256", "abc",
                        "--backup", "b.dump", "--dryrun", "--jeg-mener-det")),
  "D2_APPLY_CLI_INVALID")

## 4) Duplikerede flag er ogsaa en fejl.
expect_error(
  d2_parse_apply_args(c("--selection", "a.json", "--selection", "b.json",
                        "--expect-sha256", "abc", "--backup", "b.dump",
                        "--jeg-mener-det")),
  "D2_APPLY_CLI_INVALID")

## 5) --selection er paakraevet.
expect_error(d2_parse_apply_args(c("--expect-sha256", "abc", "--backup",
                                   "b.dump", "--jeg-mener-det")),
             "D2_APPLY_CLI_INVALID")

## 6) En flag-vaerdi der selv ligner et flag er en tastefejl, ikke en vaerdi.
expect_error(
  d2_parse_apply_args(c("--selection", "--expect-sha256", "abc", "--backup",
                        "b.dump", "--jeg-mener-det")),
  "D2_APPLY_CLI_INVALID")

## --- Guarden mod at basen har flyttet sig ------------------------------
fixture_doc <- function(...) {
  base <- list(
    schema_version = "1.0", database_name = "postgres",
    database_identity = "764273", 
    counts = list(valgte = 2, staged_i_alt = 9, staged_bagefter = 7,
                  ekstra_medrevne = 0, overlap_c0 = 0),
    selected = list(list(person_id = 1480), list(person_id = 1487)))
  utils::modifyList(base, list(...))
}
fixture_live <- function(...) {
  base <- list(staged_i_alt = 9, valgte_ids = c(1480, 1487),
               database_name = "postgres", database_identity = "764273")
  utils::modifyList(base, list(...))
}

## 7) Lykkelig sti: basen ser ud praecis som eksporten beskrev.
plan <- d2_plan_apply(fixture_doc(), fixture_live())
expect(identical(plan$ids, c(1480, 1487)))
expect(identical(plan$forventet_bagefter, 7))

## 8) Har staged-maengden flyttet sig, er eksportens tal foraeldede.
expect_error(d2_plan_apply(fixture_doc(), fixture_live(staged_i_alt = 10)),
             "D2_APPLY_STAGED_DRIFT")

## 9) DET FARLIGE TILFAELDE: samme ANTAL kandidater, andre mennesker.
##    En valgt person mister sin synlige partner (men forbliver staged) mens
##    en anden staged person faar én. Antal staged og antal kandidater er
##    uaendret, og SHA-laasen passerer -- filen er jo aegte. Kun en
##    sammenligning af selve ID-MAENGDEN fanger det.
expect_error(d2_plan_apply(fixture_doc(), fixture_live(valgte_ids = c(1480, 1499))),
             "D2_APPLY_SELECTION_DRIFT")

## 9b) Faerre kandidater end eksporten saa.
expect_error(d2_plan_apply(fixture_doc(), fixture_live(valgte_ids = 1480)),
             "D2_APPLY_SELECTION_DRIFT")

## 9c) Raekkefoelge maa IKKE goere en forskel -- ellers ville guarden fyre
##     paa en base der er fuldstaendig uaendret.
expect(identical(d2_plan_apply(fixture_doc(), fixture_live(valgte_ids = c(1487, 1480)))$ids,
                 c(1480, 1487)))

## 9d) En eksport fra en ANDEN base ville ellers passere alt oevrigt.
expect_error(d2_plan_apply(fixture_doc(), fixture_live(database_identity = "999")),
             "D2_APPLY_DATABASE_MISMATCH")
expect_error(d2_plan_apply(fixture_doc(), fixture_live(database_name = "anden")),
             "D2_APPLY_DATABASE_MISMATCH")

## 9e) Dokumentets egne gate-tal genlaeses: filen kan vaere haandbygget og
##     behoever ikke komme fra eksporten.
expect_error(
  d2_plan_apply(fixture_doc(counts = list(valgte = 2, staged_i_alt = 9,
    staged_bagefter = 7, ekstra_medrevne = 1, overlap_c0 = 0)), fixture_live()),
  "D2_APPLY_EXTRA_SWEPT")
expect_error(
  d2_plan_apply(fixture_doc(counts = list(valgte = 2, staged_i_alt = 9,
    staged_bagefter = 7, ekstra_medrevne = 0, overlap_c0 = 1)), fixture_live()),
  "D2_APPLY_C0_OVERLAP")
expect_error(
  d2_plan_apply(fixture_doc(counts = list(valgte = 3, staged_i_alt = 9,
    staged_bagefter = 7, ekstra_medrevne = 0, overlap_c0 = 0)), fixture_live()),
  "D2_APPLY_COUNT_MISMATCH")
expect_error(d2_plan_apply(fixture_doc(schema_version = "2.0"), fixture_live()),
             "D2_APPLY_SCHEMA_UNKNOWN")

## 10) Et tomt udvalg maa aldrig naa til apply.
##     Bemaerk: doc'et bygges IKKE med modifyList(selected = list()).
##     modifyList rekurserer naar begge sider er lister, og en navnloes tom
##     liste efterlader feltet UROERT -- guarden ville aldrig fyre, og testen
##     ville bestaa af den forkerte grund.
tom_doc <- fixture_doc(counts = list(valgte = 0, staged_i_alt = 9,
                                     staged_bagefter = 9, ekstra_medrevne = 0,
                                     overlap_c0 = 0))
tom_doc$selected <- list()
expect(identical(length(tom_doc$selected), 0L))
expect_error(d2_plan_apply(tom_doc, fixture_live(valgte_ids = numeric(0))),
             "D2_APPLY_EMPTY")

## --- Efterkontrollen (DB-fri) ------------------------------------------
## D2 roerer UDELUKKENDE person.staged. Efterkontrollen koerer inde i
## transaktionen, saa en afvigelse ruller tilbage i stedet for at efterlade
## prod aendret -- planen lagde den efter commit, hvor den kun kunne melde.
fixture_taelling <- function(...) {
  base <- list(staged = 28, person = 1811, fact = 7199, relation = 2031,
               narrative = 592)
  utils::modifyList(base, list(...))
}

## 11) Lykkelig sti: kun staged har flyttet sig, og til det forventede tal.
expect(isTRUE(d2_check_postcheck(fixture_taelling(),
                                 fixture_taelling(staged = 7), 7)))

## 12) Forkert antal afstagede: RPC'ens medrivning ramte bredere end maalt.
expect_error(
  d2_check_postcheck(fixture_taelling(), fixture_taelling(staged = 8), 7),
  "D2_APPLY_POSTCHECK_MISMATCH")

## 13) Enhver anden aendring end staged er et brud paa fasens loefte.
expect_error(
  d2_check_postcheck(fixture_taelling(),
                     fixture_taelling(staged = 7, fact = 7200), 7),
  "D2_APPLY_DELTA_NOT_ZERO")
expect_error(
  d2_check_postcheck(fixture_taelling(),
                     fixture_taelling(staged = 7, person = 1812), 7),
  "D2_APPLY_DELTA_NOT_ZERO")
expect_error(
  d2_check_postcheck(fixture_taelling(),
                     fixture_taelling(staged = 7, narrative = 591), 7),
  "D2_APPLY_DELTA_NOT_ZERO")

## 14) Et tabt taellefelt maa ikke passere nul-delta:
##     identical(as.numeric(NULL), as.numeric(NULL)) er TRUE.
mangler <- fixture_taelling(); mangler$fact <- NULL
expect_error(d2_check_postcheck(mangler, fixture_taelling(staged = 7), 7),
             "D2_APPLY_TAELLING_MANGLER")
expect_error(d2_check_postcheck(fixture_taelling(), mangler, 7),
             "D2_APPLY_TAELLING_MANGLER")

cat(sprintf("OK: %d assertions\n", ok))
