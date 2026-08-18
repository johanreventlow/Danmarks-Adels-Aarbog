script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_phase_a_1939_v50_helpers.R"))

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
phase_a_test_rendition_sha256 <- sha("b")

build_phase_a_fixture_operations <- function() {
  n <- 584L
  canonical_count <- 543L
  lapply(seq_len(n), function(i) {
    key <- sprintf("record-%04d", i)
    span_from <- i * 100L
    category <- if (i %% 37L == 0L) "structural_context" else if (i %% 53L == 0L) "cross_reference" else "person"
    payload <- list(
      element_id = paste0("phase-a:", key),
      dependency_class = "source_evidence",
      review_subject_id = key,
      source_record_key = key,
      category = category,
      disposition = "retain_source_only"
    )
    if (i <= canonical_count) {
      payload$canonical_target <- list(person_id = 1000L + i)
      payload$legacy_payload <- list(
        baseline_record_key = paste0("baseline-", key),
        legacy_name = if (i %% 5L == 0L) NULL else paste0("Legacy ", i)
      )
    }
    payload$source_span <- list(char_from = span_from, char_to = span_from + 50L)
    payload$page_evidence <- list(page_from = 5L + (i %/% 20L), page_to = 5L + (i %/% 20L))
    payload$verbatim_text <- paste0("Verbatim text for ", key)
    payload$rendition_content_sha256 <- phase_a_test_rendition_sha256
    payload$evidence_sha256 <- digest::digest(key, algo = "sha256", serialize = FALSE)
    payload
  })
}

fixture_manifest <- function() {
  manifest <- list(
    schema_version = "1939-v50-phase-a-anchor-manifest-v1",
    generator_version = "test:v1",
    input_hashes = list(
      import_preview_sha256 = sha("1"), database_preview_sha256 = sha("2"),
      production_manifest_sha256 = sha("3"), boundary_sha256 = sha("4"),
      calamari_sha256 = phase_a_test_rendition_sha256
    ),
    source = list(
      edition = "1939", logical_source_id = "1939", database_source_id = 3L,
      rendition_content_sha256 = phase_a_test_rendition_sha256
    ),
    arithmetic = list(
      source_records = 592L, excluded_already_written = 8L,
      elements = 584L, canonical_targets = 543L
    ),
    operations = build_phase_a_fixture_operations(),
    counts = list(person_creates = 0L, source_evidence = 584L, canonical_delta = 0L),
    expected_changes = list(
      persons_created = 0L, source_evidence_written = 584L,
      canonical_rows_changed = 0L, persons_activated = 0L
    ),
    production_authorized = FALSE, apply_gate = "NO-GO"
  )
  manifest$manifest_content_sha256 <- canonical_phase_a_sha256(manifest)
  manifest
}

fake_gateway <- function(fail_at = NULL) {
  log <- character()
  source_evidence_calls <- list()
  call <- function(name, ...) {
    args <- list(...)
    log <<- c(log, name)
    if (identical(name, fail_at)) stop(paste0("FAIL_AT_", name), call. = FALSE)
    if (identical(name, "authorize")) return("authorization-id")
    if (identical(name, "begin_batch")) return("batch-id")
    if (identical(name, "source_evidence")) {
      source_evidence_calls[[length(source_evidence_calls) + 1L]] <<- args
      return(invisible(NULL))
    }
    if (identical(name, "finalize")) {
      return(list(status = "finalized",
        counts = list(person_creates = 0L, source_evidence = 584L, canonical_delta = 0L)))
    }
    invisible(NULL)
  }
  list(call = call, log = function() log,
    source_evidence_calls = function() source_evidence_calls)
}

## -- validator: succesvej
m <- fixture_manifest()
validate_phase_a_manifest(m)
expect(TRUE)

## -- succesvej: gateway-kaldsorden, dry-run ender i rollback, committed=FALSE
g <- fake_gateway()
out <- execute_phase_a_1939(m, sha("a"), "dry-run", g)
expect(identical(out$mode, "dry-run") && identical(out$committed, FALSE) &&
  identical(out$status, "finalized"))
log <- g$log()
expect(identical(log[1:4], c("connect", "begin", "authorize", "begin_batch")))
expect(sum(log == "source_evidence") == 584L)
expect(identical(log[length(log) - 1L], "finalize"))
expect(identical(tail(log, 1L), "rollback"))
expect(!("commit" %in% log))
expect(length(log) == 4L + 584L + 1L + 1L)

## -- authorize/apply-payload skal være byte-lige (samme jsonlite-serialisering)
payloads <- authorized_phase_a_payloads(m)
expect(length(payloads) == 584L)
calls <- g$source_evidence_calls()
expect(length(calls) == 584L)
first_id <- m$operations[[1L]]$element_id
expect(identical(calls[[1L]][[3L]], payloads[[first_id]]))

## -- Important 1 (review): strip_phase_a_transport SKAL fjerne element_id/
## dependency_class, og resultatet SKAL være en delmængde af de 11
## SQL-kontrakt-nøgler. Uden denne assertion fanger intet en NULL-tildeling
## der forsvinder fra strip_phase_a_transport ved en refaktorering — de
## øvrige checks (identical(x,x), round-trip) holder stadig grønne selv om
## BEGGE veje bærer den ekstra nøgle, og fejlen dukker først op i prod som
## REIMPORT_1939_SOURCE_EVIDENCE_INVALID.
expect(!any(c("element_id", "dependency_class") %in% names(payloads[[first_id]])))
expect(length(setdiff(names(payloads[[first_id]]), phase_a_sql_payload_keys)) == 0L)
expect(all(vapply(payloads, function(p) {
  !any(c("element_id", "dependency_class") %in% names(p)) &&
    length(setdiff(names(p), phase_a_sql_payload_keys)) == 0L
}, logical(1))))

## -- den relevante ækvivalens er IKKE identical(x,x) på samme R-objekt, men
## at Postgres' `authorized_elements->element_id IS DISTINCT FROM p_payload`
## ser den samme værdi, uanset om den kommer fra ÉN samlet jsonb-kort-
## serialisering (authorize) eller EN individuel jsonb-serialisering (apply).
## Simuler det round-trip her (element_id 1 = canonical_target+string
## legacy_name; element_id 98 = canonical_target+null legacy_name;
## element_id 544 = uden canonical_target).
elements_roundtrip <- jsonlite::fromJSON(
  jsonlite::toJSON(payloads, auto_unbox = TRUE, null = "null"),
  simplifyVector = FALSE)
check_element_roundtrip <- function(index) {
  id <- m$operations[[index]]$element_id
  individual_roundtrip <- jsonlite::fromJSON(
    jsonlite::toJSON(payloads[[id]], auto_unbox = TRUE, null = "null"),
    simplifyVector = FALSE)
  identical(elements_roundtrip[[id]], individual_roundtrip)
}
expect(check_element_roundtrip(1L)) # canonical_target + string legacy_name
expect(check_element_roundtrip(5L)) # canonical_target + NULL legacy_name (i %% 5 == 0)
expect(check_element_roundtrip(544L)) # uden canonical_target/legacy_payload

## -- apply-mode ender i commit, committed=TRUE
g2 <- fake_gateway()
out2 <- execute_phase_a_1939(m, sha("a"), "apply", g2)
expect(identical(out2$committed, TRUE) && identical(tail(g2$log(), 1L), "commit"))
expect(!("rollback" %in% g2$log()))

## -- connect-svigt: intet at rulle tilbage (transaktion aldrig startet)
g_connect <- fake_gateway("connect")
expect_error(execute_phase_a_1939(m, sha("a"), "dry-run", g_connect), "FAIL_AT_connect")
expect(sum(g_connect$log() == "rollback") == 0L)

## -- Important 1b (review): manifest-validering SKAL ske FØR connect —
## ugyldigt manifest må ALDRIG åbne en prod-forbindelse eller starte en
## transaktion. Uden denne assertion ville en refaktorering der flytter
## validate_phase_a_manifest() ned under call("connect") stadig give
## PASS på alle andre 63+ assertions.
g_early <- fake_gateway()
bad_early <- fixture_manifest(); bad_early$counts$person_creates <- 1L
expect_error(execute_phase_a_1939(bad_early, sha("a"), "dry-run", g_early),
  "PHASE_A_1939_COUNTS_INVALID")
expect(length(g_early$log()) == 0L)

## -- alle øvrige fejlveje ender i PRÆCIS én rollback, aldrig commit
for (stage in c("authorize", "begin_batch", "source_evidence", "finalize")) {
  g3 <- fake_gateway(stage)
  expect_error(execute_phase_a_1939(m, sha("a"), "dry-run", g3), paste0("FAIL_AT_", stage))
  expect(sum(g3$log() == "rollback") == 1L)
  expect(!("commit" %in% g3$log()))
}
for (stage in c("authorize", "begin_batch", "source_evidence", "finalize")) {
  g4 <- fake_gateway(stage)
  expect_error(execute_phase_a_1939(m, sha("a"), "apply", g4), paste0("FAIL_AT_", stage))
  expect(sum(g4$log() == "rollback") == 1L)
  expect(!("commit" %in% g4$log()))
}

## -- preview-hash format
expect_error(execute_phase_a_1939(m, "not-a-hash", "dry-run", fake_gateway()),
  "PHASE_A_1939_PREVIEW_HASH_INVALID")

## -- validator afviser: forkerte counts
bad <- fixture_manifest(); bad$counts$person_creates <- 1L
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_COUNTS_INVALID")
bad <- fixture_manifest(); bad$counts$source_evidence <- 583L
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_COUNTS_INVALID")
bad <- fixture_manifest(); bad$counts$canonical_delta <- 1L
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_COUNTS_INVALID")
bad <- fixture_manifest(); bad$operations <- bad$operations[1:583]
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_COUNTS_INVALID")

## -- validator afviser: dublet-element-ids
bad <- fixture_manifest()
bad$operations[[2L]]$element_id <- bad$operations[[1L]]$element_id
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_ORDER_INVALID")

## -- validator afviser: forkert rækkefølge (ikke sorteret)
bad <- fixture_manifest()
bad$operations <- rev(bad$operations)
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_ORDER_INVALID")

## -- validator afviser: disposition != retain_source_only
bad <- fixture_manifest()
bad$operations[[1L]]$disposition <- "something_else"
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_DISPOSITION_INVALID")

## -- validator afviser: dependency_class != source_evidence (hard-lock, ingen person_create/canonical_delta)
bad <- fixture_manifest()
bad$operations[[1L]]$dependency_class <- "person_create"
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_DEPENDENCY_CLASS_INVALID")

## -- validator afviser: payload-nøgler uden for SQL-kontrakten
bad <- fixture_manifest()
bad$operations[[1L]]$unexpected_key <- "nope"
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_PAYLOAD_KEY_INVALID")

## -- validator afviser: rendition-drift (afviger fra source$rendition_content_sha256)
bad <- fixture_manifest()
bad$operations[[1L]]$rendition_content_sha256 <- sha("9")
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_RENDITION_DRIFT")

## -- validator afviser: forkert canonical_target-optælling (skal være PRÆCIS 543)
bad <- fixture_manifest()
bad$operations[[1L]]$canonical_target <- NULL
bad$operations[[1L]]$legacy_payload <- NULL
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_ARITHMETIC_INVALID")

## -- validator afviser: manglende content-sha-match (kanonisk sortnøgle-genberegning)
bad <- fixture_manifest(); bad$generator_version <- "tampered generator"
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_CONTENT_HASH_INVALID")
bad <- fixture_manifest(); bad$manifest_content_sha256 <- sha("f")
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_CONTENT_HASH_INVALID")

## -- validator afviser: forkert schema_version / production_authorized / apply_gate
bad <- fixture_manifest(); bad$schema_version <- "other"
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$production_authorized <- TRUE
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$apply_gate <- "GO"
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$unknown_field <- TRUE
expect_error(validate_phase_a_manifest(bad), "PHASE_A_1939_MANIFEST_INVALID")

## -- gateway-guard
expect_error(execute_phase_a_1939(m, sha("a"), "dry-run", list(call = "not-a-function")),
  "PHASE_A_1939_GATEWAY_INVALID")

## -- Important 3 (review, controller-ruling): advisory-låsen deler nøgle
## med apply_reimport_1939_v50 (samme skrive-domæne), OG "source-only" er
## en testet egenskab, ikke en påstand — fase A må ALDRIG kunne kalde
## person_create/canonical_delta-RPC'erne. Mønster kopieret fra
## test_apply_name_completion_1939_v50.R (deparse(body(...))-teknikken).
gateway_body <- paste(deparse(body(new_phase_a_dbi_gateway)), collapse = "\n")
expect(grepl("daa-1939-v50-production-writer", gateway_body, fixed = TRUE))
expect(grepl("pg_advisory_xact_lock", gateway_body, fixed = TRUE))
for (rpc in c("red_authorize_1939_v50_reimport", "red_begin_1939_v50_reimport",
    "red_apply_1939_v50_source_evidence", "red_finalize_1939_v50_reimport"))
  expect(grepl(rpc, gateway_body, fixed = TRUE), rpc)
for (rpc in c("red_apply_1939_v50_person_create", "red_apply_1939_v50_canonical_delta"))
  expect(!grepl(rpc, gateway_body, fixed = TRUE), rpc)

## -- CLI afviser forkert manifest-hash (system2, exit 1)
manifest_path <- tempfile("phase-a-manifest-", fileext = ".json")
output_path <- tempfile("phase-a-output-", fileext = ".json")
on.exit(unlink(c(manifest_path, output_path)), add = TRUE)
writeLines(jsonlite::toJSON(m, auto_unbox = TRUE, pretty = FALSE), manifest_path, useBytes = TRUE)
cli <- file.path(script_dir, "apply_phase_a_1939_v50.R")
cli_result <- suppressWarnings(system2("Rscript", c(cli, "--manifest", manifest_path,
  "--manifest-sha256", sha("f"), "--preview-sha256", sha("a"), "--output", output_path,
  "--dry-run"), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_result, "status")), 1L) &&
  any(grepl("PHASE_A_1939_MANIFEST_HASH_INVALID", cli_result, fixed = TRUE)))
expect(!file.exists(output_path))

## -- Important 2 (controller-ruling): tilstand er OBLIGATORISK og gensidigt
## udelukkende. Hverken flag → CLI-fejl exit 1; BEGGE flag → CLI-fejl exit 1.
## En genbrugt shell-kommando uden --dry-run må ALDRIG stille committe.
cli_no_mode <- suppressWarnings(system2("Rscript", c(cli, "--manifest", manifest_path,
  "--manifest-sha256", sha("f"), "--preview-sha256", sha("a"), "--output", output_path),
  stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_no_mode, "status")), 1L) &&
  any(grepl("PHASE_A_1939_CLI_INVALID", cli_no_mode, fixed = TRUE)))
expect(!file.exists(output_path))

cli_both_modes <- suppressWarnings(system2("Rscript", c(cli, "--manifest", manifest_path,
  "--manifest-sha256", sha("f"), "--preview-sha256", sha("a"), "--output", output_path,
  "--dry-run", "--apply"), stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(cli_both_modes, "status")), 1L) &&
  any(grepl("PHASE_A_1939_CLI_INVALID", cli_both_modes, fixed = TRUE)))
expect(!file.exists(output_path))

cat(sprintf("PASS %d assertions\n", ok))
