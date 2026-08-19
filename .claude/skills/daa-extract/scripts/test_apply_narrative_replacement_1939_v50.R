script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_narrative_replacement_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

sha <- function(letter) paste(rep(letter, 64L), collapse = "")

## -- fixture-manifest: 551 operationer (543 create + 8 existing), samme
## invarianter som det rigtige (låste) manifest, men syntetiske person_id'er/
## nøgler så testen aldrig afhænger af PII eller af den frosne fil.
narrative_replacement_test_total <- 551L
narrative_replacement_test_existing <- 8L
narrative_replacement_test_create <- 543L

build_narrative_replacement_fixture_operations <- function() {
  lapply(seq_len(narrative_replacement_test_total), function(i) {
    person_id <- 900L + i
    binding <- if (i <= narrative_replacement_test_existing) "existing" else "create"
    key <- sprintf("record-aaaaaaaa-aaaa-4aaa-8aaa-%012d", i)
    page <- 500L + (i %/% 20L)
    text <- paste0("Normaliseret tekst for person ", person_id, " (post ", i, ").")
    list(
      person_id = person_id,
      source_record_key = key,
      source_span = list(char_from = i * 100L, char_to = i * 100L + 50L),
      page_from = page,
      raw_sha256 = digest::digest(paste0("raw-", key), algo = "sha256", serialize = FALSE),
      normalized_sha256 = digest::digest(enc2utf8(text), algo = "sha256", serialize = FALSE),
      normalized_text = text,
      expected_old_narrative_sha256 = digest::digest(paste0("old-", key), algo = "sha256", serialize = FALSE),
      binding = binding,
      record_label = key,
      citation_label = paste0("DAA 1939 side ", page)
    )
  })
}

fixture_manifest <- function() {
  manifest <- list(
    schema_version = "1939-v50-narrative-replacement-manifest-v1",
    generator_version = "test:v1",
    input_hashes = narrative_replacement_locked_input_hashes,
    source = list(
      edition = "1939", logical_source_id = "1939", database_source_id = 3L,
      rendition_content_sha256 = narrative_replacement_locked_input_hashes$calamari_sha256
    ),
    operations = build_narrative_replacement_fixture_operations(),
    counts = narrative_replacement_expected_counts,
    flags = list(),
    out_of_scope = lapply(1:26, function(i) list(person_id = 2000L + i, reason = "no_mapped_source_record")),
    production_authorized = FALSE, apply_gate = "NO-GO"
  )
  manifest$manifest_content_sha256 <- canonical_narrative_replacement_sha256(manifest)
  manifest
}

## -- preflight-fixture svarende til en frisk, uskrevet DB-tilstand for
## fixture-manifestet ovenfor: alle 551 findes med korrekt gammel SHA, de 8
## "existing" er allerede published, de 543 "create" har ingen binding endnu.
build_preflight_fixture <- function(manifest) {
  narrative_ids <- list()
  source_record_ids <- list()
  for (op in manifest$operations) {
    narrative_ids[[as.character(op$person_id)]] <- 5000L + op$person_id
    if (identical(op$binding, "create")) source_record_ids[[op$source_record_key]] <- paste0("uuid-", op$source_record_key)
  }
  list(
    database_name = "postgres", system_identifier = "1234567890123456789",
    narrative_ids = narrative_ids, source_record_ids = source_record_ids,
    narrative_count_before = 577L,
    canonical_counts_before = list(person = 1900L, fact = 12000L, relation = 3400L, family = 700L, family_member = 1400L)
  )
}

build_verify_fixture <- function(preflight) {
  list(published_bindings = 551L, narrative_count = preflight$narrative_count_before,
    canonical_counts = preflight$canonical_counts_before)
}

## -- fake gateway: standard-succesvej svarer korrekt på alt; fail_at
## simulerer en enkelt fejlende kaldstype (herunder specifikke
## manifest-uafhængige DB-svigt som "preflight" for old-sha-drift osv, ved at
## overstyre preflight_result/verify_result med et konfigureret svar der
## selv rammer en af de rene checker-funktioner nedenfor).
fake_gateway <- function(fail_at = NULL, preflight_override = NULL, verify_override = NULL) {
  log <- character()
  upsert_calls <- list()
  publish_calls <- list()
  manifest_ref <- NULL
  preflight_ref <- NULL
  call <- function(name, ...) {
    args <- list(...)
    log <<- c(log, name)
    if (identical(name, fail_at)) stop(paste0("FAIL_AT_", name), call. = FALSE)
    if (identical(name, "preflight")) {
      manifest_ref <<- args[[1L]]
      preflight_ref <<- if (!is.null(preflight_override)) preflight_override else build_preflight_fixture(manifest_ref)
      return(preflight_ref)
    }
    if (identical(name, "upsert_narrativ")) {
      op <- args[[1L]]
      upsert_calls[[length(upsert_calls) + 1L]] <<- op
      return(preflight_ref$narrative_ids[[as.character(op$person_id)]])
    }
    if (identical(name, "publish")) {
      publish_calls[[length(publish_calls) + 1L]] <<- args
      return(paste0("binding-", args[[1L]]))
    }
    if (identical(name, "verify")) {
      return(if (!is.null(verify_override)) verify_override else build_verify_fixture(preflight_ref))
    }
    invisible(NULL)
  }
  list(call = call, log = function() log,
    upsert_calls = function() upsert_calls, publish_calls = function() publish_calls)
}

## -- validator: succesvej
m <- fixture_manifest()
validate_narrative_replacement_manifest(m)
expect(TRUE)
expect(length(m$operations) == 551L)
expect(sum(vapply(m$operations, function(op) op$binding, character(1)) == "create") == 543L)
expect(sum(vapply(m$operations, function(op) op$binding, character(1)) == "existing") == 8L)

## -- succesvej: gateway-kaldsorden, dry-run ender i rollback, committed=FALSE
g <- fake_gateway()
out <- execute_narrative_replacement_1939(m, "dry-run", g)
expect(identical(out$mode, "dry-run") && identical(out$committed, FALSE))
log <- g$log()
expect(identical(log[1:3], c("connect", "begin", "preflight")))
expect(sum(log == "upsert_narrativ") == 551L)
expect(sum(log == "publish") == 543L)
expect(identical(log[length(log) - 1L], "verify"))
expect(identical(tail(log, 1L), "rollback"))
expect(!("commit" %in% log))
expect(length(log) == 3L + 551L + 543L + 1L + 1L)

## -- upsert_narrativ kaldes for ALLE 551 (både create og existing), i
## manifest-rækkefølge (stigende person_id)
upserted_pids <- vapply(g$upsert_calls(), function(op) op$person_id, numeric(1))
expect(identical(upserted_pids, vapply(m$operations, function(op) op$person_id, numeric(1))))

## -- Important (kontraktpræcisering): publish kaldes KUN for binding=="create"
## — de 8 "existing" bindinger må ALDRIG kaldes (ville fejle ALREADY_BOUND i
## den rigtige red_publicer_narrative_record). Uden denne assertion ville en
## refaktorering der publicerer alle 551 stadig give PASS på kaldsordens-
## tællingen alene, hvis nogen samtidig sænkede narrative_replacement_test_create.
publish_narrative_ids <- vapply(g$publish_calls(), function(a) a[[1L]], numeric(1))
existing_narrative_ids <- vapply(Filter(function(op) identical(op$binding, "existing"), m$operations),
  function(op) 5000L + op$person_id, numeric(1))
create_narrative_ids <- vapply(Filter(function(op) identical(op$binding, "create"), m$operations),
  function(op) 5000L + op$person_id, numeric(1))
expect(length(publish_narrative_ids) == 543L)
expect(all(publish_narrative_ids %in% create_narrative_ids))
expect(!any(publish_narrative_ids %in% existing_narrative_ids))
expect(length(intersect(publish_narrative_ids, existing_narrative_ids)) == 0L)

## -- publish-argumenter: (narrative_id, source_record_id, record_label, citation_label)
first_publish <- g$publish_calls()[[1L]]
first_create_op <- Filter(function(op) identical(op$binding, "create"), m$operations)[[1L]]
expect(identical(first_publish[[3L]], first_create_op$record_label))
expect(identical(first_publish[[4L]], first_create_op$citation_label))

## -- apply-mode ender i commit, committed=TRUE
g2 <- fake_gateway()
out2 <- execute_narrative_replacement_1939(m, "apply", g2)
expect(identical(out2$committed, TRUE) && identical(tail(g2$log(), 1L), "commit"))
expect(!("rollback" %in% g2$log()))

## -- connect-svigt: intet at rulle tilbage (transaktion aldrig startet)
g_connect <- fake_gateway("connect")
expect_error(execute_narrative_replacement_1939(m, "dry-run", g_connect), "FAIL_AT_connect")
expect(sum(g_connect$log() == "rollback") == 0L)

## -- manifest-validering SKAL ske FØR connect — ugyldigt manifest må ALDRIG
## åbne en prod-forbindelse eller starte en transaktion.
g_early <- fake_gateway()
bad_early <- fixture_manifest(); bad_early$counts$inserts <- 1L
expect_error(execute_narrative_replacement_1939(bad_early, "dry-run", g_early),
  "NARRATIVE_REPLACEMENT_1939_COUNTS_INVALID")
expect(length(g_early$log()) == 0L)

## -- alle øvrige fejlveje ender i PRÆCIS én rollback, aldrig commit (dry-run)
for (stage in c("preflight", "upsert_narrativ", "publish", "verify")) {
  g3 <- fake_gateway(stage)
  expect_error(execute_narrative_replacement_1939(m, "dry-run", g3), paste0("FAIL_AT_", stage))
  expect(sum(g3$log() == "rollback") == 1L)
  expect(!("commit" %in% g3$log()))
}
## -- samme i apply-mode: en fejl må ALDRIG committe, kun rulle tilbage
for (stage in c("preflight", "upsert_narrativ", "publish", "verify")) {
  g4 <- fake_gateway(stage)
  expect_error(execute_narrative_replacement_1939(m, "apply", g4), paste0("FAIL_AT_", stage))
  expect(sum(g4$log() == "rollback") == 1L)
  expect(!("commit" %in% g4$log()))
}

## -- gateway-guard
expect_error(execute_narrative_replacement_1939(m, "dry-run", list(call = "not-a-function")),
  "NARRATIVE_REPLACEMENT_1939_GATEWAY_INVALID")

## -- upsert returnerer forkert id (uventet insert) → abort med person_id, én
## rollback. fake_gateway's upsert_narrativ svarer normalt ALTID med
## preflight_ref$narrative_ids[[pid]] (per definition "korrekt"), så vi
## simulerer et REELT uventet-insert-svar ved at wrappe en gateway hvis
## upsert_narrativ svarer noget andet end preflight sagde:
g_unexpected_insert <- (function() {
  base <- fake_gateway()
  call <- base$call
  wrapped <- function(name, ...) {
    if (identical(name, "upsert_narrativ")) return(-1L)
    call(name, ...)
  }
  list(call = wrapped, log = base$log, upsert_calls = base$upsert_calls, publish_calls = base$publish_calls)
})()
expect_error(execute_narrative_replacement_1939(m, "dry-run", g_unexpected_insert),
  "NARRATIVE_REPLACEMENT_1939_UNEXPECTED_INSERT")

## -- preflight-shape-guard: manglende nøgle i preflight-svar afvises
g_bad_shape <- fake_gateway(preflight_override = list(database_name = "postgres"))
expect_error(execute_narrative_replacement_1939(m, "dry-run", g_bad_shape),
  "NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")

## -- verify-shape-guard: forkert published_bindings-tal afvises
g_bad_verify <- fake_gateway(verify_override = list(published_bindings = 550L,
  narrative_count = 577L, canonical_counts = list(person = 1L, fact = 1L, relation = 1L, family = 1L, family_member = 1L)))
expect_error(execute_narrative_replacement_1939(m, "dry-run", g_bad_verify),
  "NARRATIVE_REPLACEMENT_1939_VERIFY_INVALID")

## ---------------------------------------------------------------------
## Rene checker-funktioner (DB-fri, direkte input/output) — den egentlige
## replay-/drift-dækning bag "old-sha-drift → abort" og de øvrige
## SQL-fortolkede invarianter, uden nogen DB-forbindelse.
## ---------------------------------------------------------------------

## -- Postgres array-literal encoders (RPostgres/DBI-bind-fælde: en
## R-vektor bundet til ét placeholder bliver til n parametersæt, ikke ét
## array — se kommentar i helpers). Ren string-i/string-ud, DB-fri.
expect(identical(narrative_replacement_pg_bigint_array(c(1L, 2L, 924L)), "{1,2,924}"))
expect(identical(narrative_replacement_pg_bigint_array(924L), "{924}"))
expect(identical(narrative_replacement_pg_text_array(c("record-a", "record-b")), '{"record-a","record-b"}'))
expect(identical(narrative_replacement_pg_text_array("has\"quote"), '{"has\\"quote"}'))
expect(identical(narrative_replacement_pg_text_array("has\\backslash"), '{"has\\\\backslash"}'))

## -- narrative_replacement_check_batch_status
expect_error(narrative_replacement_check_batch_status("open"), "NARRATIVE_REPLACEMENT_1939_PHASE_A_BATCH_NOT_FINALIZED")
expect_error(narrative_replacement_check_batch_status(NA_character_), "NARRATIVE_REPLACEMENT_1939_PHASE_A_BATCH_NOT_FINALIZED")
narrative_replacement_check_batch_status("finalized")
expect(TRUE)

## -- narrative_replacement_check_old_sha: succesvej
matching_rows <- data.frame(
  person_id = vapply(m$operations, function(op) op$person_id, numeric(1)),
  narrative_id = vapply(m$operations, function(op) 5000L + op$person_id, numeric(1)),
  narrative_sha256 = vapply(m$operations, function(op) op$expected_old_narrative_sha256, character(1)),
  stringsAsFactors = FALSE
)
result <- narrative_replacement_check_old_sha(matching_rows, m)
expect(length(result) == 551L)
expect(identical(result[[as.character(m$operations[[1L]]$person_id)]], 5000L + m$operations[[1L]]$person_id))

## -- old-sha-drift → abort med det AFVIGENDE person_id (dette ER
## replay-værnet: efter en gennemført apply matcher intet, og en genkørsel
## skal afvises fail-closed netop her)
drifted_rows <- matching_rows
drift_target_pid <- m$operations[[37L]]$person_id
drifted_rows$narrative_sha256[drifted_rows$person_id == drift_target_pid] <- sha("9")
expect_error(narrative_replacement_check_old_sha(drifted_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_OLD_SHA_MISMATCH:", drift_target_pid))

## -- old-sha-drift rapporterer FØRSTE afvigelse i stigende person_id-orden,
## selv når flere er drevet
double_drift_rows <- matching_rows
second_drift_pid <- m$operations[[400L]]$person_id
double_drift_rows$narrative_sha256[double_drift_rows$person_id == drift_target_pid] <- sha("9")
double_drift_rows$narrative_sha256[double_drift_rows$person_id == second_drift_pid] <- sha("8")
expect_error(narrative_replacement_check_old_sha(double_drift_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_OLD_SHA_MISMATCH:", drift_target_pid))

## -- manglende narrativ for et person_id → abort med det person_id
missing_rows <- matching_rows[-1L, ]
expect_error(narrative_replacement_check_old_sha(missing_rows, m), "NARRATIVE_REPLACEMENT_1939_PREFLIGHT_COUNT_INVALID")

## ---------------------------------------------------------------------
## narrative_replacement_check_privat_and_side (Task 4-review Important 1,
## controller-ruling 2026-08-19): red_upsert_narrativ's UPDATE-gren
## overskriver privat OG side ubetinget — replay-værnet ovenfor dækkede
## oprindeligt kun tekst-SHA'en. Disse tests dækker begge afvisningsveje.
## ---------------------------------------------------------------------
privat_side_rows <- matching_rows
privat_side_rows$privat <- FALSE
privat_side_rows$side <- vapply(m$operations, function(op) as.character(op$page_from), character(1))

## -- succesvej: alle privat=FALSE, alle side==page_from
narrative_replacement_check_privat_and_side(privat_side_rows, m)
expect(TRUE)

## -- privat=TRUE for én post → ABORT fail-closed med det person_id (ville
## ellers tavst afprivatisere posten — brud på invariant 8/GDPR)
privat_true_rows <- privat_side_rows
privat_flag_pid <- m$operations[[9L]]$person_id
privat_true_rows$privat[privat_true_rows$person_id == privat_flag_pid] <- TRUE
expect_error(narrative_replacement_check_privat_and_side(privat_true_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_PRIVAT_FLAG_SET:", privat_flag_pid))

## -- privat=NA behandles IKKE som TRUE (isTRUE-værn) men rammer stadig ikke
## side-checket for samme post, da NA != FALSE ville være en anden fejlklasse
## — her tjekkes blot at NA ikke fejlagtigt trigger PRIVAT_FLAG_SET
na_privat_rows <- privat_side_rows
na_privat_rows$privat[[1L]] <- NA
narrative_replacement_check_privat_and_side(na_privat_rows, m)
expect(TRUE)

## -- side afviger fra page_from for én post → ABORT fail-closed med
## person_id + begge værdier (ville ellers kollapse en flersidet/håndrettet
## side-streng tavst, jf. COALESCE(p_side,side) der aldrig aktiveres når
## p_side altid er non-NULL)
side_drift_rows <- privat_side_rows
side_drift_pid <- m$operations[[15L]]$person_id
side_drift_rows$side[side_drift_rows$person_id == side_drift_pid] <- "596-598"
expect_error(narrative_replacement_check_privat_and_side(side_drift_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_SIDE_UNEXPECTED:", side_drift_pid,
    ":observed=596-598:expected=", m$operations[[15L]]$page_from))

## -- side==NA (NULL i DB) for én post → ABORT (COALESCE ville ellers sætte
## den til page_from, hvilket IKKE er en afvigelse vi ønsker at overse blot
## fordi den nuværende værdi tilfældigvis er tom)
side_null_rows <- privat_side_rows
side_null_pid <- m$operations[[21L]]$person_id
side_null_rows$side[side_null_rows$person_id == side_null_pid] <- NA_character_
expect_error(narrative_replacement_check_privat_and_side(side_null_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_SIDE_UNEXPECTED:", side_null_pid, ":observed=NULL"))

## -- manglende privat/side-kolonner → struktur-guard
expect_error(narrative_replacement_check_privat_and_side(matching_rows, m),
  "NARRATIVE_REPLACEMENT_1939_PREFLIGHT_COLUMNS_INVALID")

## -- privat prioriteres over side for SAMME post, hvis begge er i uorden
both_wrong_rows <- privat_side_rows
both_wrong_pid <- m$operations[[3L]]$person_id
both_wrong_rows$privat[both_wrong_rows$person_id == both_wrong_pid] <- TRUE
both_wrong_rows$side[both_wrong_rows$person_id == both_wrong_pid] <- "wrong"
expect_error(narrative_replacement_check_privat_and_side(both_wrong_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_PRIVAT_FLAG_SET:", both_wrong_pid))

## ---------------------------------------------------------------------
## Parameter-byggere (Task 4-review Minor 4): rækkefølgen til de to RPC'er
## SKAL matche schema.sql, og en test skal fange en ombytning direkte —
## ikke kun konstatere at RPC-navnet optræder et sted i gateway-kroppen.
## ---------------------------------------------------------------------
sample_op <- m$operations[[1L]]
upsert_params <- narrative_replacement_upsert_params(sample_op)
expect(identical(upsert_params, list(
  "person", sample_op$person_id, sample_op$normalized_text, FALSE, 3L, as.character(sample_op$page_from)
)))
## -- Rækkefølge/typer eksplicit, matcher red_upsert_narrativ(p_subjekt_type
## text,p_subjekt_id bigint,p_tekst text,p_privat boolean,p_source_id bigint,
## p_side text) — schema.sql:3868-3870
expect(length(upsert_params) == 6L)
expect(identical(upsert_params[[1L]], "person"))
expect(is.numeric(upsert_params[[2L]]) && identical(upsert_params[[2L]], sample_op$person_id))
expect(is.character(upsert_params[[3L]]) && identical(upsert_params[[3L]], sample_op$normalized_text))
expect(identical(upsert_params[[4L]], FALSE))
expect(identical(upsert_params[[5L]], 3L))
expect(is.character(upsert_params[[6L]]) && identical(upsert_params[[6L]], as.character(sample_op$page_from)))

publish_params <- narrative_replacement_publish_params(4242L, "uuid-x", "record-x", "DAA 1939 side 500")
## -- matcher red_publicer_narrative_record(p_narrative_id bigint,
## p_source_record_id uuid,p_record_label text,p_citation_label text) —
## schema.sql:3074-3075
expect(identical(publish_params, list(4242L, "uuid-x", "record-x", "DAA 1939 side 500")))
expect(length(publish_params) == 4L)
expect(identical(publish_params[[1L]], 4242L))
expect(identical(publish_params[[2L]], "uuid-x"))
expect(identical(publish_params[[3L]], "record-x"))
expect(identical(publish_params[[4L]], "DAA 1939 side 500"))

## -- narrative_replacement_check_bindings
narrative_ids_map <- result
existing_ids_vec <- vapply(Filter(function(op) identical(op$binding, "existing"), m$operations),
  function(op) narrative_ids_map[[as.character(op$person_id)]], numeric(1))
create_ids_vec <- vapply(Filter(function(op) identical(op$binding, "create"), m$operations),
  function(op) narrative_ids_map[[as.character(op$person_id)]], numeric(1))
good_binding_rows <- data.frame(narrative_id = existing_ids_vec, status = "published", stringsAsFactors = FALSE)
narrative_replacement_check_bindings(good_binding_rows, m, narrative_ids_map)
expect(TRUE)

## -- eksisterende binding IKKE published → afvist
bad_status_rows <- good_binding_rows
bad_status_rows$status[[1L]] <- "draft"
expect_error(narrative_replacement_check_bindings(bad_status_rows, m, narrative_ids_map),
  "NARRATIVE_REPLACEMENT_1939_EXISTING_BINDING_INVALID")

## -- en af de 543 "create" har allerede en binding → tabellen har 9 rækker
## i stedet for 8 → afvist på tabel-optællingen (Faktagrundlag: "præcis 8
## rækker ... i alt" — table-bred, ikke scopet til vores 551 narrative_id'er;
## ville ellers ramme ALREADY_BOUND i red_publicer_narrative_record)
rows_with_stray_create_binding <- rbind(good_binding_rows,
  data.frame(narrative_id = create_ids_vec[[1L]], status = "draft", stringsAsFactors = FALSE))
expect_error(narrative_replacement_check_bindings(rows_with_stray_create_binding, m, narrative_ids_map),
  "NARRATIVE_REPLACEMENT_1939_BINDING_TABLE_COUNT_INVALID")

## -- for få rækker i tabellen → afvist på tabel-optællingen
expect_error(narrative_replacement_check_bindings(good_binding_rows[-1L, ], m, narrative_ids_map),
  "NARRATIVE_REPLACEMENT_1939_BINDING_TABLE_COUNT_INVALID")

## -- tabellen har 8 rækker, alle published, men SÆTTET af narrative_id'er
## matcher ikke vores 8 "existing" — en fremmed binding har erstattet en af
## vores egne (nrow()==8 alene ville have overset dette)
rows_with_foreign_binding <- good_binding_rows
rows_with_foreign_binding$narrative_id[[1L]] <- create_ids_vec[[1L]]
expect_error(narrative_replacement_check_bindings(rows_with_foreign_binding, m, narrative_ids_map),
  "NARRATIVE_REPLACEMENT_1939_EXISTING_BINDING_MISMATCH")

## -- narrative_replacement_check_source_records
create_keys <- vapply(Filter(function(op) identical(op$binding, "create"), m$operations),
  function(op) op$source_record_key, character(1))
good_source_rows <- data.frame(record_key = create_keys,
  id = paste0("uuid-", create_keys), stringsAsFactors = FALSE)
resolved <- narrative_replacement_check_source_records(good_source_rows, create_keys)
expect(length(resolved) == 543L)
expect(identical(resolved[[create_keys[[1L]]]], paste0("uuid-", create_keys[[1L]])))

missing_source_rows <- good_source_rows[-1L, ]
expect_error(narrative_replacement_check_source_records(missing_source_rows, create_keys),
  "NARRATIVE_REPLACEMENT_1939_SOURCE_RECORD_COUNT_INVALID")

## -- narrative_replacement_check_verify_sha
good_verify_rows <- data.frame(
  person_id = vapply(m$operations, function(op) op$person_id, numeric(1)),
  narrative_sha256 = vapply(m$operations, function(op) op$normalized_sha256, character(1)),
  stringsAsFactors = FALSE
)
narrative_replacement_check_verify_sha(good_verify_rows, m)
expect(TRUE)
bad_verify_rows <- good_verify_rows
verify_drift_pid <- m$operations[[12L]]$person_id
bad_verify_rows$narrative_sha256[bad_verify_rows$person_id == verify_drift_pid] <- sha("7")
expect_error(narrative_replacement_check_verify_sha(bad_verify_rows, m),
  paste0("NARRATIVE_REPLACEMENT_1939_VERIFY_SHA_MISMATCH:", verify_drift_pid))

## -- narrative_replacement_check_verify_bindings / narrative_count / canonical_counts
## (begge tal er tabel-brede — "551 published bindinger i alt")
narrative_replacement_check_verify_bindings(551L, 551L)
expect(TRUE)
expect_error(narrative_replacement_check_verify_bindings(552L, 551L), "NARRATIVE_REPLACEMENT_1939_VERIFY_BINDINGS_INVALID")
expect_error(narrative_replacement_check_verify_bindings(551L, 550L), "NARRATIVE_REPLACEMENT_1939_VERIFY_BINDINGS_INVALID")

narrative_replacement_check_narrative_count(577L, 577L)
expect(TRUE)
expect_error(narrative_replacement_check_narrative_count(577L, 578L), "NARRATIVE_REPLACEMENT_1939_NARRATIVE_COUNT_CHANGED")

canonical_before <- list(person = 1900L, fact = 12000L, relation = 3400L, family = 700L, family_member = 1400L)
narrative_replacement_check_canonical_counts(canonical_before, canonical_before)
expect(TRUE)
canonical_after_drifted <- canonical_before; canonical_after_drifted$person <- 1901L
expect_error(narrative_replacement_check_canonical_counts(canonical_before, canonical_after_drifted),
  "NARRATIVE_REPLACEMENT_1939_CANONICAL_COUNTS_CHANGED")

## ---------------------------------------------------------------------
## Manifest-validator: afviste stier
## ---------------------------------------------------------------------

bad <- fixture_manifest(); bad$counts$inserts <- 1L
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_COUNTS_INVALID")
bad <- fixture_manifest(); bad$counts$narratives <- 550L
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_COUNTS_INVALID")
bad <- fixture_manifest(); bad$operations <- bad$operations[1:550]
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_COUNTS_INVALID")

bad <- fixture_manifest()
bad$operations[[2L]]$person_id <- bad$operations[[1L]]$person_id
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_ORDER_INVALID")

bad <- fixture_manifest()
bad$operations <- rev(bad$operations)
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_ORDER_INVALID")

bad <- fixture_manifest()
bad$operations[[1L]]$binding <- "something_else"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")

bad <- fixture_manifest()
bad$operations[[1L]]$record_label <- "not-the-key"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_BINDING_LABEL_INVALID")

bad <- fixture_manifest()
bad$operations[[1L]]$citation_label <- "wrong citation"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_BINDING_LABEL_INVALID")

bad <- fixture_manifest()
bad$operations[[1L]]$normalized_text <- paste0(bad$operations[[1L]]$normalized_text, " tampered")
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_NORMALIZED_SHA_INVALID")

bad <- fixture_manifest()
bad$operations[[1L]]$source_record_key <- "not-a-record-key"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")

bad <- fixture_manifest()
## flyt én "create" til "existing" uden at ændre labels → arithmetik knækker (542/9)
bad$operations[[551L]]$binding <- "existing"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_BINDING_ARITHMETIC_INVALID")

bad <- fixture_manifest(); bad$flags <- list(list(kind = "x"))
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_FLAGS_INVALID")

bad <- fixture_manifest(); bad$out_of_scope <- bad$out_of_scope[1:25]
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")

bad <- fixture_manifest(); bad$out_of_scope[[1L]]$reason <- "other"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")

bad <- fixture_manifest(); bad$out_of_scope[[2L]]$person_id <- bad$out_of_scope[[1L]]$person_id
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")

bad <- fixture_manifest(); bad$schema_version <- "other"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$production_authorized <- TRUE
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$apply_gate <- "GO"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$unknown_field <- TRUE
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_MANIFEST_INVALID")

bad <- fixture_manifest(); bad$input_hashes$phase_a_manifest_sha256 <- sha("9")
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_INPUT_HASHES_INVALID")

bad <- fixture_manifest(); bad$source$database_source_id <- 4L
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_SOURCE_INVALID")
bad <- fixture_manifest(); bad$source$rendition_content_sha256 <- sha("9")
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_SOURCE_INVALID")

bad <- fixture_manifest(); bad$generator_version <- "tampered"
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_CONTENT_HASH_INVALID")
bad <- fixture_manifest(); bad$manifest_content_sha256 <- sha("f")
expect_error(validate_narrative_replacement_manifest(bad), "NARRATIVE_REPLACEMENT_1939_CONTENT_HASH_INVALID")

## ---------------------------------------------------------------------
## Important (kontraktpræcisering): advisory-låsen deler nøgle med de øvrige
## 1939-v50-writere ('daa-1939-v50-production-writer'), OG denne writer må
## ALDRIG kunne kalde person_create/canonical_delta-RPC'erne — det er en
## helt anden skriveflade (person-skabelse/kanoniske deltas), som denne
## narrativ-/publicerings-writer ikke har noget forretning med. Mønster
## kopieret fra test_apply_phase_a_1939_v50.R (deparse(body(...))-teknikken).
## ---------------------------------------------------------------------
gateway_body <- paste(deparse(body(new_narrative_replacement_dbi_gateway)), collapse = "\n")
expect(grepl("daa-1939-v50-production-writer", gateway_body, fixed = TRUE))
expect(grepl("pg_advisory_xact_lock", gateway_body, fixed = TRUE))
expect(grepl("red_upsert_narrativ", gateway_body, fixed = TRUE))
expect(grepl("red_publicer_narrative_record", gateway_body, fixed = TRUE))
expect(grepl("narrative_replacement_phase_a_batch_id", gateway_body, fixed = TRUE))
for (rpc in c("red_apply_1939_v50_person_create", "red_apply_1939_v50_canonical_delta",
    "red_authorize_1939_v50_reimport", "red_begin_1939_v50_reimport", "red_finalize_1939_v50_reimport"))
  expect(!grepl(rpc, gateway_body, fixed = TRUE), rpc)

## -- CLI afviser forkert manifest-hash (system2, exit 1)
manifest_path <- tempfile("narrative-replacement-manifest-", fileext = ".json")
output_path <- tempfile("narrative-replacement-output-", fileext = ".json")
on.exit(unlink(c(manifest_path, output_path)), add = TRUE)
writeLines(jsonlite::toJSON(m, auto_unbox = TRUE, pretty = FALSE), manifest_path, useBytes = TRUE)
cli <- file.path(script_dir, "apply_narrative_replacement_1939_v50.R")
cli_bad_hash <- suppressWarnings(system2("Rscript", c(cli, "--manifest", manifest_path,
  "--manifest-sha256", sha("f"), "--output", output_path, "--dry-run"), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_bad_hash, "status")), 1L) &&
  any(grepl("NARRATIVE_REPLACEMENT_1939_MANIFEST_HASH_INVALID", cli_bad_hash, fixed = TRUE)))
expect(!file.exists(output_path))

## -- tilstand er OBLIGATORISK og gensidigt udelukkende. Hverken flag → CLI-fejl
## exit 1; BEGGE flag → CLI-fejl exit 1. En genbrugt shell-kommando uden
## --dry-run må ALDRIG stille committe.
cli_no_mode <- suppressWarnings(system2("Rscript", c(cli, "--manifest", manifest_path,
  "--manifest-sha256", sha("f"), "--output", output_path), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_no_mode, "status")), 1L) &&
  any(grepl("NARRATIVE_REPLACEMENT_1939_CLI_INVALID", cli_no_mode, fixed = TRUE)))
expect(!file.exists(output_path))

cli_both_modes <- suppressWarnings(system2("Rscript", c(cli, "--manifest", manifest_path,
  "--manifest-sha256", sha("f"), "--output", output_path, "--dry-run", "--apply"), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_both_modes, "status")), 1L) &&
  any(grepl("NARRATIVE_REPLACEMENT_1939_CLI_INVALID", cli_both_modes, fixed = TRUE)))
expect(!file.exists(output_path))

cat(sprintf("PASS %d assertions\n", ok))
