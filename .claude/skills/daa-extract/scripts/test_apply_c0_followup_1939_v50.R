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
SHA <- paste(rep("c", 64), collapse = "")
fixture_manifest <- function(...) {
  base <- list(
    schema_version = "1939-v50-c0-followup-manifest-v1",
    database_name = "postgres", database_identity = "764273",
    counts = list(operations = 2, bindings_create = 2),
    operations = list(
      list(person_id = 963, narrative_id = 632, page_from = 508,
           expected_old_narrative_sha256 = SHA, new_text = "A", new_text_sha256 = SHA),
      list(person_id = 991, narrative_id = 660, page_from = 504,
           expected_old_narrative_sha256 = SHA, new_text = "B", new_text_sha256 = SHA)))
  utils::modifyList(base, list(...))
}
fixture_live <- function(...) {
  base <- list(
    narrative_ids = c(632, 660), old_shas = c(SHA, SHA),
    privat = c(FALSE, FALSE), sider = c("508", "504"), bindinger = 0,
    database_name = "postgres", database_identity = "764273")
  utils::modifyList(base, list(...))
}

## 8) Lykkelig sti.
plan <- c0f_plan_apply(fixture_manifest(), fixture_live())
expect(identical(length(plan$operations), 2L))
expect(identical(plan$forventet_bindinger, 2))

## 9) Teksten er aendret siden eksporten -- replay-vaernet.
expect_error(c0f_plan_apply(fixture_manifest(),
  fixture_live(old_shas = c(paste(rep("d", 64), collapse = ""), SHA))),
  "C0F_APPLY_OLD_SHA_MISMATCH")

## 10) privat=TRUE ville blive tavst afprivatiseret (GDPR, invariant 8).
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(privat = c(FALSE, TRUE))),
             "C0F_APPLY_PRIVAT")

## 10b) NA spaerrer ogsaa.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(privat = c(NA, FALSE))),
             "C0F_APPLY_PRIVAT")

## 11) Sidetallet er identitetskontrollen: afviger det, er recorden og
##     narrativet ikke samme trykte post.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(sider = c("999", "504"))),
             "C0F_APPLY_SIDE_MISMATCH")

## 12) En eksisterende binding ville faa RPC'en til at kaste halvvejs igennem.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(bindinger = 1)),
             "C0F_APPLY_ALREADY_BOUND")

## 13) Narrativet er forsvundet.
expect_error(c0f_plan_apply(fixture_manifest(), fixture_live(narrative_ids = c(632, 999))),
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

## --- Efterkontrollen ---------------------------------------------------
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

## 18) Fasen maa ikke aendre ANTALLET af narrativer -- kun deres tekst.
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, narrativer = 1170), 2), "C0F_APPLY_DELTA_NOT_ZERO")
expect_error(c0f_check_postcheck(fixture_taelling(),
  fixture_taelling(bindinger = 2, personer = 1812), 2), "C0F_APPLY_DELTA_NOT_ZERO")

## 19) Et tabt taellefelt maa ikke passere nul-delta:
##     identical(as.numeric(NULL), as.numeric(NULL)) er TRUE.
mangler <- fixture_taelling(); mangler$fakta <- NULL
expect_error(c0f_check_postcheck(mangler, fixture_taelling(bindinger = 2), 2),
             "C0F_APPLY_TAELLING_MANGLER")

cat(sprintf("OK: %d assertions\n", ok))
