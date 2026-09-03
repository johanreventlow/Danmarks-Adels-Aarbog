## DB-fri tests for export_c0_followup_selection_1939_v50_helpers.R.
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "export_c0_followup_selection_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

SHA <- paste(rep("a", 64), collapse = "")
fixture_rows <- function() {
  data.frame(
    person_id = c(967, 963, 978, 991, 992, 1296, 1297, 1298, 1299),
    narrative_id = c(636, 632, 647, 660, 661, 965, 966, 967, 968),
    old_sha256 = rep(SHA, 9),
    privat = rep(FALSE, 9),
    side = c("508", "508", "509", "504", "504", "574", "574", "574", "574"),
    stringsAsFactors = FALSE
  )
}

## 1) Lykkelig sti: sorteret paa person_id, alle felter baaret videre.
doc <- build_c0_followup_selection_1939_v50(fixture_rows(), "postgres", "764273", "test")
expect(identical(doc$schema_version, "1.0"))
expect(identical(length(doc$selected), 9L))
expect(identical(doc$selected[[1]]$person_id, 963))
expect(identical(doc$selected[[9]]$person_id, 1299))
expect(identical(doc$selected[[1]]$side, "508"))

## 2) Antallet er laast til NI. 1017 er flyttet til C3, og et tiende id ville
##    betyde at nogen har genindsat den -- eller at udvalget er skredet.
expect_error(build_c0_followup_selection_1939_v50(
  fixture_rows()[1:8, ], "postgres", "764273", "test"), "C0F_SELECTION_COUNT_INVALID")

## 3) Praecis DE ni id'er -- ikke ni vilkaarlige.
forkert <- fixture_rows(); forkert$person_id[[1]] <- 1017
expect_error(build_c0_followup_selection_1939_v50(
  forkert, "postgres", "764273", "test"), "C0F_SELECTION_IDS_INVALID")

## 4) privat=TRUE er et GDPR-broud (invariant 8), ikke en datafejl: writeren
##    sender altid p_privat=false, saa posten ville blive tavst afprivatiseret.
priv <- fixture_rows(); priv$privat[[3]] <- TRUE
expect_error(build_c0_followup_selection_1939_v50(
  priv, "postgres", "764273", "test"), "C0F_SELECTION_PRIVAT")

## 4b) NA spaerrer ogsaa: publicering skal kraeve bevis, ikke fravaer af modbevis.
priv_na <- fixture_rows(); priv_na$privat[[3]] <- NA
expect_error(build_c0_followup_selection_1939_v50(
  priv_na, "postgres", "764273", "test"), "C0F_SELECTION_PRIVAT")

## 5) Uden narrativ er der intet at erstatte.
mangler <- fixture_rows(); mangler$narrative_id[[2]] <- NA
expect_error(build_c0_followup_selection_1939_v50(
  mangler, "postgres", "764273", "test"), "C0F_SELECTION_NARRATIVE_MISSING")

## 6) old_sha256 er replay-vaernets anker; en malformet hash goer det tandloest.
daarlig <- fixture_rows(); daarlig$old_sha256[[4]] <- "kort"
expect_error(build_c0_followup_selection_1939_v50(
  daarlig, "postgres", "764273", "test"), "C0F_SELECTION_SHA_INVALID")

## 7) En manglende kolonne maa ikke ligne "ingen problemer": any(logical(0))
##    er FALSE, saa en fail-closed gate ville vaere tavs.
for (kolonne in c("privat", "side", "old_sha256", "narrative_id")) {
  uden <- fixture_rows(); uden[[kolonne]] <- NULL
  expect_error(build_c0_followup_selection_1939_v50(
    uden, "postgres", "764273", "test"), "C0F_SELECTION_KOLONNE_MANGLER")
}

cat(sprintf("OK: %d assertions\n", ok))
