## DB-frie tests for apply_c0_followup_1939_v50_helpers.R.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_c0_followup_1939_v50_helpers.R"))

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
fuld <- c("--manifest", "m.json", "--expect-sha256", "abc", "--backup", "b.dump",
          "--jeg-mener-det")

## 1) Lykkelig sti.
p <- c0f_parse_apply_args(fuld)
expect(identical(p$manifest, "m.json"))
expect(identical(p$expect_sha256, "abc"))
expect(identical(p$backup, "b.dump"))

## 2) UDEN bekraeftelse afvises. I fase D1 blev et opfundet --dryrun ignoreret,
##    og 68 personer blev publiceret i prod uden godkendelse.
expect_error(c0f_parse_apply_args(head(fuld, -1)), "C0F_APPLY_CONFIRMATION_REQUIRED")

## 3) Ukendt flag maa aldrig blive til tavs accept.
expect_error(c0f_parse_apply_args(c(fuld, "--dryrun")), "C0F_APPLY_CLI_INVALID")

## 4) Duplikeret flag.
expect_error(c0f_parse_apply_args(c(fuld, "--manifest", "n.json")), "C0F_APPLY_CLI_INVALID")

## 5) Hash-laasen er obligatorisk: uden den kan et haandredigeret manifest
##    saette sin egen forventning, som efterkontrollen saa "bekraefter".
expect_error(c0f_parse_apply_args(
  c("--manifest", "m.json", "--backup", "b.dump", "--jeg-mener-det")),
  "C0F_APPLY_SHA_REQUIRED")

## 6) Backup er obligatorisk: basen koerer paa free tier uden automatisk backup.
expect_error(c0f_parse_apply_args(
  c("--manifest", "m.json", "--expect-sha256", "abc", "--jeg-mener-det")),
  "C0F_APPLY_BACKUP_REQUIRED")

## 7) En flag-vaerdi der selv ligner et flag er en tastefejl, ikke en vaerdi.
expect_error(c0f_parse_apply_args(
  c("--manifest", "--expect-sha256", "abc", "--backup", "b.dump", "--jeg-mener-det")),
  "C0F_APPLY_CLI_INVALID")

## --- Guarden mod at basen har flyttet sig ------------------------------
## TRE operationer med FORSKELLIGE SHA'er hver (ikke en fælles konstant):
## en fixture med kun to ens SHA'er ville lade en ombytning af de to
## old-SHA'er passere upåagtet, og et hardkodet "2" ville ikke fange en
## konstant forventet_bindinger. Codex-review 2026-08-21 fandt begge.
OLD_A <- paste(rep("c", 64), collapse = "")
OLD_B <- paste(rep("d", 64), collapse = "")
OLD_C <- paste(rep("e", 64), collapse = "")
NEW_A <- paste(rep("1", 64), collapse = "")
NEW_B <- paste(rep("2", 64), collapse = "")
NEW_C <- paste(rep("3", 64), collapse = "")

fixture_manifest <- function(...) {
  base <- list(
    schema_version = "1939-v50-c0-followup-manifest-v1",
    database_name = "postgres", database_identity = "764273",
    counts = list(operations = 3, bindings_create = 3),
    operations = list(
      list(person_id = 963, narrative_id = 632, page_from = 508,
           expected_old_narrative_sha256 = OLD_A, new_text = "A", new_text_sha256 = NEW_A),
      list(person_id = 991, narrative_id = 660, page_from = 504,
           expected_old_narrative_sha256 = OLD_B, new_text = "B", new_text_sha256 = NEW_B),
      list(person_id = 1296, narrative_id = 900, page_from = 510,
           expected_old_narrative_sha256 = OLD_C, new_text = "C", new_text_sha256 = NEW_C)))
  utils::modifyList(base, list(...))
}
fixture_live <- function(...) {
  base <- list(
    narrative_ids = c(632, 660, 900), old_shas = c(OLD_A, OLD_B, OLD_C),
    privat = c(FALSE, FALSE, FALSE), sider = c("508", "504", "510"), bindinger = 0,
    database_name = "postgres", database_identity = "764273")
  utils::modifyList(base, list(...))
}

## 8) Lykkelig sti. forventet_bindinger er talt fra operationerne, IKKE en
##    hardkodet konstant -- eksplicit 3, ikke bare "== length(...)" igen.
plan <- c0f_plan_apply(fixture_manifest(), fixture_live())
expect(identical(length(plan$operations), 3L))
expect(identical(plan$forventet_bindinger, 3))

## 9) Teksten er aendret siden eksporten -- replay-vaernet. Kun FOERSTE
##    old_sha er forkert; de to andre er korrekte og forskellige fra
##    hinanden, saa testen ikke ville bestaa ved en fejlagtig ombytning.
expect_error(c0f_plan_apply(fixture_manifest(),
  fixture_live(old_shas = c(paste(rep("f", 64), collapse = ""), OLD_B, OLD_C))),
  "C0F_APPLY_OLD_SHA_MISMATCH")

## 10) privat=TRUE ville blive tavst afprivatiseret (GDPR, invariant 8).
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(privat = c(FALSE, TRUE, FALSE))),
             "C0F_APPLY_PRIVAT")

## 10b) NA spaerrer ogsaa.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(privat = c(NA, FALSE, FALSE))),
             "C0F_APPLY_PRIVAT")

## 11) Sidetallet er identitetskontrollen: afviger det, er recorden og
##     narrativet ikke samme trykte post.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(sider = c("999", "504", "510"))),
             "C0F_APPLY_SIDE_MISMATCH")

## 12) En eksisterende binding ville faa RPC'en til at kaste halvvejs igennem.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(bindinger = 1)),
             "C0F_APPLY_ALREADY_BOUND")

## 13) Narrativet er forsvundet.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(narrative_ids = c(632, 660, 999))),
             "C0F_APPLY_NARRATIVE_DRIFT")

## 13b) Et manifest bygget mod rehearsal-basen maa aldrig koeres mod prod.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(database_identity = "999")),
             "C0F_APPLY_DATABASE_MISMATCH")
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(database_name = "daa1939_c0f_rehearsal1")),
             "C0F_APPLY_DATABASE_MISMATCH")

## 14) Ukendt schema_version.
expect_error(c0f_plan_apply(fixture_manifest(schema_version = "x"), fixture_live()),
             "C0F_APPLY_SCHEMA_UNKNOWN")

## 15) Tom mangde naar aldrig apply.
tom <- fixture_manifest(counts = list(operations = 0, bindings_create = 0))
tom$operations <- list()
expect_error(c0f_plan_apply(tom, fixture_live(narrative_ids = numeric(0))),
             "C0F_APPLY_EMPTY")

## --- Efterkontrollen (netto-taelling) -----------------------------------
fixture_taelling <- function(...) {
  base <- list(bindinger = 0, narrativer = 1169, personer = 1811,
               fakta = 7197, relationer = 2030)
  utils::modifyList(base, list(...))
}

## 16) Lykkelig sti: praecis to nye bindinger, intet andet rykket.
expect(isTRUE(c0f_check_postcheck(fixture_taelling(),
                                  fixture_taelling(bindinger = 2), 2)))

## 17) Forkert antal bindinger.
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 3), 2), "C0F_APPLY_POSTCHECK_MISMATCH")

## 18) Fasen maa ikke aendre ANTALLET af narrativer, personer, fakta eller
##     relationer -- kun narrativ-teksten. Alle FIRE felter testes hver for
##     sig: en fjernet delta-kontrol for blot ét felt (fx fakta/relationer)
##     ville ellers bestaa upaagtet, som Codex-review 2026-08-21 paapegede.
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, narrativer = 1170), 2), "C0F_APPLY_DELTA_NOT_ZERO")
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, personer = 1812), 2), "C0F_APPLY_DELTA_NOT_ZERO")
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, fakta = 7198), 2), "C0F_APPLY_DELTA_NOT_ZERO")
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, relationer = 2031), 2), "C0F_APPLY_DELTA_NOT_ZERO")

## 19) Et tabt taellefelt maa ikke passere nul-delta:
##     identical(as.numeric(NULL), as.numeric(NULL)) er TRUE.
mangler <- fixture_taelling(); mangler$fakta <- NULL
expect_error(c0f_check_postcheck(mangler, fixture_taelling(bindinger = 2), 2),
             "C0F_APPLY_TAELLING_MANGLER")

## --- Mangde-kontrollen: beviser at DET SKREVNE er DET TILSIGTEDE --------
## Dette lukker CRITICAL-fundet fra Codex-review 2026-08-21: nettotal-tjek
## (postcheck ovenfor) ville lade en samtidig transaktion, der sletter een
## binding og opretter en anden, passere upaagtet (netto +9). Denne kontrol
## verificerer i stedet KONKRET hvilke narrativer der baerer new_text_sha256,
## og at hver har praecis een binding med det rette source_record_id.
ops_id <- list(
  list(narrative_id = 632, new_text_sha256 = "sha632", source_record_id = "src-10"),
  list(narrative_id = 660, new_text_sha256 = "sha660", source_record_id = "src-11"),
  list(narrative_id = 900, new_text_sha256 = "sha900", source_record_id = "src-12"))
shas_ok <- list(`632` = "sha632", `660` = "sha660", `900` = "sha900")
bindings_ok <- list(narrative_id = c(632, 660, 900),
                    source_record_id = c("src-10", "src-11", "src-12"))

## 20) Lykkelig sti.
expect(isTRUE(c0f_check_write_identity(ops_id, shas_ok, bindings_ok)))

## 21) Narrativets faktiske tekst-hash matcher IKKE manifestets new_text_sha256.
shas_forkert_hash <- shas_ok; shas_forkert_hash[["660"]] <- "noget-andet"
expect_error(c0f_check_write_identity(ops_id, shas_forkert_hash, bindings_ok),
             "C0F_APPLY_TEXT_HASH_MISMATCH")

## 22) Narrativets hash mangler helt (fx forkert narrative_id i opslaget).
shas_mangler <- shas_ok; shas_mangler[["900"]] <- NULL
expect_error(c0f_check_write_identity(ops_id, shas_mangler, bindings_ok),
             "C0F_APPLY_TEXT_HASH_MISSING")

## 23) Ingen binding fundet for et narrative_id -- RPC'en fejlede tavst,
##     eller en samtidig transaktion fjernede bindingen igen.
bindings_mangler <- list(narrative_id = c(632, 660), source_record_id = c("src-10", "src-11"))
expect_error(c0f_check_write_identity(ops_id, shas_ok, bindings_mangler),
             "C0F_APPLY_BINDING_COUNT_MISMATCH")

## 24) To bindinger for samme narrative_id -- den samtidig-transaktion-drift
##     Codex-review beskrev (een slettet, een anden oprettet) ville vise sig
##     her som enten 0 eller 2 raekker for det paagaeldende narrative_id.
bindings_dublet <- list(narrative_id = c(632, 632, 660, 900),
                        source_record_id = c("src-10", "src-10", "src-11", "src-12"))
expect_error(c0f_check_write_identity(ops_id, shas_ok, bindings_dublet),
             "C0F_APPLY_BINDING_COUNT_MISMATCH")

## 25) Bindingen findes, men peger paa et andet source_record end det vi
##     selv slog op og skrev.
bindings_forkert_kilde <- list(narrative_id = c(632, 660, 900),
                               source_record_id = c("forkert-kilde", "src-11", "src-12"))
expect_error(c0f_check_write_identity(ops_id, shas_ok, bindings_forkert_kilde),
             "C0F_APPLY_BINDING_SOURCE_MISMATCH")

cat(sprintf("OK: %d assertions\n", ok))
