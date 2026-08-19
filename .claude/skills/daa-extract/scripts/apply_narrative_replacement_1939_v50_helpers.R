## Fase B-writer: erstatter 551 narrativer (551x red_upsert_narrativ) og
## publicerer 543 record-bindinger (543x red_publicer_narrative_record) i ÉN
## transaktion. Manifestet er FROSSET (bruger-godkendt); denne wrapper
## asserterer det bogstaveligt mod de låste tal fra
## build_narrative_replacement_manifest_1939_v50.py i stedet for at genudlede
## dem. Mønstret er kopieret fra apply_phase_a_1939_v50_helpers.R /
## apply_name_completion_1939_v50_helpers.R — koden er bevidst IKKE delt
## (batch-specifik designbeslutning, jf. de øvrige 1939-writere).
##
## Til forskel fra fase A/name-completion har denne writer INGEN dedikeret
## authorize/begin_batch/finalize-RPC-familie at læne sig op af — kun de to
## eksisterende, prod-live RPC'er `red_upsert_narrativ` og
## `red_publicer_narrative_record`. Preflight og verify er derfor almindelig
## SELECT-SQL fortolket af rene (DB-fri, testbare) R-funktioner nedenfor.

narrative_replacement_hash_re <- "^[0-9a-f]{64}$"
narrative_replacement_lock_key <- "daa-1939-v50-production-writer"
narrative_replacement_phase_a_batch_id <- "328a813a-3c04-4265-8263-79ba3b2a0715"

## -- låst 2026-08-18 (task-context.md, Faktagrundlag) — manifestet er
## endeligt, så disse er bogstavelige forventninger, ikke genudledte.
## old_narrative_sha_export_sha256 opdateret 2026-08-19 (controller-ruling):
## v2-eksporten (person_id/narrative_sha256/side/privat, genereret af den
## reproducerbare export_narrative_old_sha_1939_v50.R mod
## daa1939_phase_b_rehearsal1) erstatter v1 (kun person_id/narrative_sha256)
## -- rehearsalens dry-run fandt at DB's narrative.side for person 975/986
## afveg fra manifestets page_from, og v1 kunne ikke bære de to dokumenterede
## rettelser eksplicit.
narrative_replacement_locked_input_hashes <- list(
  phase_a_manifest_sha256 = "1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208",
  production_manifest_sha256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f",
  narrative_publication_manifest_sha256 = "d71908cf3a998d57602a91d936a2c1b19cf874da938bdef0d691fda9a2ac7654",
  calamari_sha256 = "020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37",
  old_narrative_sha_export_sha256 = "ec9845e0504d77980182617afd9f1b7daddb447d12e55dd4f6148c435987fec6",
  decisions_sha256 = "4090680b0fc9cb2c590b2235606536557d0c4dd7afebe5cc6e34b415334e5f0b"
)

## -- antal DOKUMENTEREDE side-rettelser er låst (2 -- person 975: DB side
## 508 rettes til 509; 986: DB side 503 rettes til 505 -- controller-
## verificeret 2026-08-19, se task-5-report.md), men INDHOLDET (hvilke
## person_id'er/tal) valideres STRUKTURELT i validate_narrative_replacement_
## manifest (person_id findes blandt operations, observed != expected,
## expected matcher den operations page_from) -- ikke som en hardkodet
## literal-liste. Samme mønster som bindings_create/bindings_existing
## (543/8): tallet er låst, de specifikke identiteter er det ikke, så
## R-testens syntetiske fixture kan udøve den fulde kontrakt uden at
## afhænge af de rigtige person_id'er.
narrative_replacement_expected_side_corrections <- 2L

narrative_replacement_expected_counts <- list(
  narratives = 551L, updates = 551L, inserts = 0L,
  bindings_create = 543L, bindings_existing = 8L,
  side_corrections = narrative_replacement_expected_side_corrections
)

stop_narrative_replacement <- function(code) stop(code, call. = FALSE)

narrative_replacement_names_equal <- function(value, expected) {
  is.list(value) && !is.null(names(value)) && !anyNA(names(value)) &&
    !anyDuplicated(names(value)) && identical(sort(names(value)), sort(expected))
}

narrative_replacement_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && grepl(narrative_replacement_hash_re, value)
}

narrative_replacement_uuid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[0-9a-f]{8}-[0-9a-f-]{27}$", value)
}

narrative_replacement_source_record_key <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^record-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", value)
}

narrative_replacement_int <- function(value) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || value %% 1 != 0) return(NA_integer_)
  as.integer(value)
}

narrative_replacement_scalar_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

## -- Postgres array-literal encoders. RPostgres/DBI treats a length-n R
## vector bound to one placeholder as n PARAMETER SETS (row-by-row batching),
## NOT as a single array value — binding a 551-long vector to `$1::bigint[]`
## does not build `{...}`. Every existing 1939-v50 writer avoids vector
## binds entirely (preview_narrative_publication_1939_v50_helpers.R builds
## `$1::uuid,$2::uuid,...` with one scalar per placeholder instead); we bind
## more rows than that pattern comfortably supports, so we build the literal
## text ourselves and bind it as ONE scalar string to `$1::bigint[]`/
## `$1::text[]`. Pure + directly testable (no DB).
narrative_replacement_pg_bigint_array <- function(x) {
  paste0("{", paste(as.integer(x), collapse = ","), "}")
}
narrative_replacement_pg_text_array <- function(x) {
  x <- as.character(x)
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub('"', '\\"', x, fixed = TRUE)
  paste0("{", paste0('"', x, '"', collapse = ","), "}")
}

## -- kanonisk indhold-sha256 (sortnøgle-genberegning), samme mønster som
## canonical_phase_a_sha256/canonical_name_completion_sha256, egen kopi.
canonical_narrative_replacement_value <- function(value) {
  if (!is.list(value)) return(value)
  value_names <- names(value)
  if (is.null(value_names)) return(lapply(value, canonical_narrative_replacement_value))
  if (anyNA(value_names) || anyDuplicated(value_names))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_CANONICAL_INVALID")
  ordered_names <- sort(value_names, method = "radix")
  result <- lapply(ordered_names, function(name) canonical_narrative_replacement_value(value[[name]]))
  names(result) <- ordered_names
  result
}

canonical_narrative_replacement_sha256 <- function(value) {
  json <- jsonlite::toJSON(canonical_narrative_replacement_value(value), auto_unbox = TRUE, null = "null", pretty = FALSE)
  digest::digest(enc2utf8(json), algo = "sha256", serialize = FALSE)
}

## ---------------------------------------------------------------------
## Manifest-validering
## ---------------------------------------------------------------------

narrative_replacement_operation_required_keys <- c(
  "binding", "citation_label", "expected_old_narrative_sha256", "expected_old_privat",
  "expected_old_side", "normalized_sha256",
  "normalized_text", "page_from", "person_id", "raw_sha256", "record_label",
  "source_record_key", "source_span"
)

validate_narrative_replacement_operation <- function(op) {
  if (!narrative_replacement_names_equal(op, narrative_replacement_operation_required_keys))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  person_id <- narrative_replacement_int(op$person_id)
  if (is.na(person_id) || person_id <= 0L) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (!narrative_replacement_source_record_key(op$source_record_key))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (!identical(op$record_label, op$source_record_key))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_BINDING_LABEL_INVALID")
  span <- op$source_span
  if (!narrative_replacement_names_equal(span, c("char_from", "char_to")) ||
      is.na(narrative_replacement_int(span$char_from)) || is.na(narrative_replacement_int(span$char_to)) ||
      narrative_replacement_int(span$char_from) < 0L ||
      narrative_replacement_int(span$char_to) <= narrative_replacement_int(span$char_from))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  page_from <- narrative_replacement_int(op$page_from)
  if (is.na(page_from) || page_from < 1L) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (!identical(op$citation_label, paste0("DAA 1939 side ", page_from)))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_BINDING_LABEL_INVALID")
  if (!narrative_replacement_hash(op$raw_sha256) || !narrative_replacement_hash(op$normalized_sha256) ||
      !narrative_replacement_hash(op$expected_old_narrative_sha256))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  ## expected_old_privat: build-time guarantee (Python builder aborts if any
  ## of the 551 has privat=true in the export) -- validated here as a
  ## literal, so a builder regression is caught at manifest-load-time, not
  ## only later against a live DB.
  if (!identical(op$expected_old_privat, FALSE))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (!narrative_replacement_scalar_string(op$expected_old_side))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (!narrative_replacement_scalar_string(op$normalized_text))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (!identical(digest::digest(enc2utf8(op$normalized_text), algo = "sha256", serialize = FALSE), op$normalized_sha256))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_NORMALIZED_SHA_INVALID")
  if (!identical(op$binding, "create") && !identical(op$binding, "existing"))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  invisible(op$binding)
}

narrative_replacement_required_manifest_keys <- c(
  "schema_version", "generator_version", "input_hashes", "source", "operations",
  "counts", "flags", "out_of_scope", "side_corrections", "production_authorized", "apply_gate",
  "manifest_content_sha256"
)

validate_narrative_replacement_manifest <- function(x) {
  if (!narrative_replacement_names_equal(x, narrative_replacement_required_manifest_keys))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_MANIFEST_INVALID")
  if (!identical(x$schema_version, "1939-v50-narrative-replacement-manifest-v2") ||
      !narrative_replacement_scalar_string(x$generator_version) ||
      !identical(x$production_authorized, FALSE) || !identical(x$apply_gate, "NO-GO") ||
      !narrative_replacement_hash(x$manifest_content_sha256))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_MANIFEST_INVALID")

  if (!narrative_replacement_names_equal(x$input_hashes, names(narrative_replacement_locked_input_hashes)) ||
      !identical(x$input_hashes, narrative_replacement_locked_input_hashes))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_INPUT_HASHES_INVALID")

  src <- x$source
  if (!narrative_replacement_names_equal(src, c("edition", "logical_source_id", "database_source_id", "rendition_content_sha256")) ||
      !identical(src$edition, "1939") || !identical(src$logical_source_id, "1939") ||
      !identical(narrative_replacement_int(src$database_source_id), 3L) ||
      !identical(src$rendition_content_sha256, narrative_replacement_locked_input_hashes$calamari_sha256))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_SOURCE_INVALID")

  got_counts <- list(
    narratives = narrative_replacement_int(x$counts$narratives),
    updates = narrative_replacement_int(x$counts$updates),
    inserts = narrative_replacement_int(x$counts$inserts),
    bindings_create = narrative_replacement_int(x$counts$bindings_create),
    bindings_existing = narrative_replacement_int(x$counts$bindings_existing),
    side_corrections = narrative_replacement_int(x$counts$side_corrections)
  )
  if (!narrative_replacement_names_equal(x$counts, names(narrative_replacement_expected_counts)) ||
      !identical(got_counts, narrative_replacement_expected_counts))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_COUNTS_INVALID")

  if (!is.list(x$flags) || length(x$flags) != 0L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_FLAGS_INVALID")

  oos <- x$out_of_scope
  if (!is.list(oos) || length(oos) != 26L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")
  oos_ids <- vapply(oos, function(entry) {
    if (!narrative_replacement_names_equal(entry, c("person_id", "reason")) ||
        !identical(entry$reason, "no_mapped_source_record"))
      stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")
    pid <- narrative_replacement_int(entry$person_id)
    if (is.na(pid) || pid <= 0L) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")
    pid
  }, integer(1))
  if (anyDuplicated(oos_ids)) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OUT_OF_SCOPE_INVALID")

  ops <- x$operations
  if (!is.list(ops) || length(ops) != 551L) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_COUNTS_INVALID")
  person_ids <- vapply(ops, function(op) {
    pid <- narrative_replacement_int(op$person_id)
    if (is.na(pid)) NA_integer_ else pid
  }, integer(1))
  if (anyNA(person_ids)) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_OPERATION_INVALID")
  if (anyDuplicated(person_ids)) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_ORDER_INVALID")
  if (!identical(person_ids, sort(person_ids))) stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_ORDER_INVALID")

  bindings <- vapply(ops, validate_narrative_replacement_operation, character(1))
  if (sum(bindings == "create") != 543L || sum(bindings == "existing") != 8L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_BINDING_ARITHMETIC_INVALID")

  ## side_corrections: COUNT is locked (2, via got_counts above); CONTENT is
  ## validated structurally -- each entry must name a real in-scope
  ## person_id, observed != expected (an identity "correction" isn't one),
  ## and (cross-checked below) must match that operation's own
  ## expected_old_side/page_from exactly. This is the same split as
  ## bindings_create/bindings_existing (543/8 locked, specific person_ids
  ## not hardcoded) -- keeps the contract enforced without baking production
  ## person_ids into the general-purpose validator.
  sc <- x$side_corrections
  if (!is.list(sc) || length(sc) != narrative_replacement_expected_side_corrections)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_SIDE_CORRECTIONS_INVALID")
  got_side_corrections <- lapply(sc, function(entry) {
    if (!narrative_replacement_names_equal(entry, c("person_id", "observed", "expected")))
      stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_SIDE_CORRECTIONS_INVALID")
    pid <- narrative_replacement_int(entry$person_id)
    if (is.na(pid) || !(pid %in% person_ids) ||
        !narrative_replacement_scalar_string(entry$observed) || !narrative_replacement_scalar_string(entry$expected) ||
        identical(entry$observed, entry$expected))
      stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_SIDE_CORRECTIONS_INVALID")
    list(person_id = pid, observed = entry$observed, expected = entry$expected)
  })
  correction_pids <- vapply(got_side_corrections, function(c) c$person_id, integer(1))
  if (anyDuplicated(correction_pids))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_SIDE_CORRECTIONS_INVALID")

  ## Cross-check EVERY operation's expected_old_side against side_corrections
  ## membership -- an operation NOT in the corrections list must claim
  ## expected_old_side==page_from; one that IS listed must claim exactly the
  ## documented "observed" value (and the correction's own "expected" must
  ## equal that op's page_from). Catches a manifest whose top-level
  ## side_corrections list is structurally valid but whose per-operation
  ## fields have silently decoupled from it -- also proves every correction
  ## entry is actually consumed by a real operation (no orphans), since
  ## every op is visited and correction_pids is a subset of person_ids.
  correction_by_pid <- stats::setNames(got_side_corrections, as.character(correction_pids))
  for (op in ops) {
    pid_key <- as.character(narrative_replacement_int(op$person_id))
    expected_side <- as.character(narrative_replacement_int(op$page_from))
    correction <- correction_by_pid[[pid_key]]
    ok <- if (is.null(correction)) {
      identical(op$expected_old_side, expected_side)
    } else {
      identical(op$expected_old_side, correction$observed) && identical(correction$expected, expected_side)
    }
    if (!ok) stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_SIDE_CORRECTIONS_OP_MISMATCH:", pid_key))
  }

  content <- x
  content$manifest_content_sha256 <- NULL
  if (!identical(canonical_narrative_replacement_sha256(content), x$manifest_content_sha256))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_CONTENT_HASH_INVALID")

  invisible(x)
}

## ---------------------------------------------------------------------
## Rene (DB-fri, direkte testbare) preflight/verify-fortolkere. Den
## virkelige DBI-gateway kalder disse på resultatet af almindelig SELECT-SQL
## — se new_narrative_replacement_dbi_gateway nedenfor. At holde
## sammenligningslogikken her (i stedet for indlejret i SQL-strenge) gør
## replay-værnet (Faktagrundlag: "old-sha-drift → abort") testbart uden DB.
## ---------------------------------------------------------------------

narrative_replacement_check_batch_status <- function(status) {
  if (!identical(status, "finalized"))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PHASE_A_BATCH_NOT_FINALIZED")
  invisible(TRUE)
}

## rows: data.frame(person_id, narrative_id, narrative_sha256) — én række pr.
## nuværende narrativ for de 551 person_id'er i manifestet. Returnerer en
## navngivet liste person_id(character) -> narrative_id(integer). Fail-closed
## på FØRSTE afvigelse i manifest-rækkefølge (stigende person_id) — dette ER
## replay-værnet: en gennemført apply ændrer teksten, så en genkørsel altid
## rammer denne afvigelse.
narrative_replacement_check_old_sha <- function(rows, manifest) {
  if (!is.data.frame(rows) || nrow(rows) != length(manifest$operations) || anyDuplicated(rows$person_id))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_COUNT_INVALID")
  result <- list()
  for (op in manifest$operations) {
    idx <- match(op$person_id, rows$person_id)
    if (is.na(idx))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_NARRATIVE_MISSING:", op$person_id))
    if (!identical(as.character(rows$narrative_sha256[[idx]]), op$expected_old_narrative_sha256))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_OLD_SHA_MISMATCH:", op$person_id))
    result[[as.character(op$person_id)]] <- as.integer(rows$narrative_id[[idx]])
  }
  result
}

## rows: SAMME data.frame som narrative_replacement_check_old_sha (person_id,
## narrative_id, narrative_sha256) men UDVIDET med privat/side — se Task
## 4-review Important 1 (controller-ruling 2026-08-19). red_upsert_narrativ's
## UPDATE-gren skriver TRE kolonner (schema.sql:3884: tekst, privat,
## side=COALESCE(p_side,side)), men replay-værnet ovenfor dækker kun tekst.
## Denne funktion lukker de to andre:
##   (1) privat=TRUE for en af de 551 → ABORT, UÆNDRET (Task 4-fix). Writeren
##       sender altid p_privat=FALSE, så en post der i dag er privat ville
##       blive tavst afprivatiseret — public_person_bio_source_versions
##       filtrerer netop på dette flag (schema.sql:3061), så brud er et
##       GDPR-brud (invariant 8), ikke bare en datafejl.
##   (2) side afviger fra manifestets page_from → ABORT, MEDMINDRE person_id
##       findes i manifest$side_corrections MED PRÆCIS matchende
##       observed/expected (2026-08-19 controller-ruling: person 975/986 er
##       to dokumenterede gamle importfejl, verificeret uden for denne
##       kørsel — se task-5-report.md/build_narrative_replacement_manifest's
##       side_corrections). En korrektion der ikke matcher DB's FAKTISKE
##       observed-værdi PRÆCIST er FORÆLDET (allerede rettet af en anden
##       vej, eller DB har flyttet sig yderligere siden manifestet blev
##       frosset) og skal ABORTE, ikke stille tillades eller stiltiende
##       springes over — korrektionslisten er et fastfrosset foto af DB's
##       tilstand på fryse-tidspunktet, ikke en generel tilladelse.
## Fail-closed på FØRSTE afvigelse i manifest-rækkefølge (stigende person_id),
## privat prioriteret før side for samme post.
narrative_replacement_check_privat_and_side <- function(rows, manifest) {
  if (!is.data.frame(rows) || !all(c("privat", "side") %in% names(rows)))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_COLUMNS_INVALID")
  corrections_by_pid <- stats::setNames(manifest$side_corrections,
    vapply(manifest$side_corrections, function(c) as.character(narrative_replacement_int(c$person_id)), character(1)))
  for (op in manifest$operations) {
    idx <- match(op$person_id, rows$person_id)
    if (is.na(idx))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_NARRATIVE_MISSING:", op$person_id))
    if (isTRUE(rows$privat[[idx]]))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_PRIVAT_FLAG_SET:", op$person_id))
    observed_side <- rows$side[[idx]]
    expected_side <- as.character(op$page_from)
    observed_side_label <- if (is.na(observed_side)) "NULL" else as.character(observed_side)

    pid_key <- as.character(op$person_id)
    correction <- corrections_by_pid[[pid_key]]
    if (!is.null(correction)) {
      ## En dokumenteret korrektion findes for dette person_id -- DB's
      ## FAKTISKE observed-værdi skal matche korrektionens "observed" HELT
      ## PRÆCIST, ellers er korrektionen forældet (kollapset-til/allerede
      ## fikset/drevet-yderligere) og skal ABORTE, ikke stiltiende passere.
      if (!identical(observed_side_label, correction$observed))
        stop_narrative_replacement(paste0(
          "NARRATIVE_REPLACEMENT_1939_SIDE_CORRECTION_STALE:", op$person_id,
          ":db=", observed_side_label, ":manifest_observed=", correction$observed))
      next  ## korrektionen dækker netop denne dokumenterede afvigelse
    }

    if (!identical(observed_side_label, expected_side) || is.na(observed_side))
      stop_narrative_replacement(paste0(
        "NARRATIVE_REPLACEMENT_1939_SIDE_UNEXPECTED:", op$person_id,
        ":observed=", observed_side_label, ":expected=", expected_side))
  }
  invisible(TRUE)
}

## rows: HELE private.narrative_record_publication-tabellen (ikke scopet til
## de 551) — Faktagrundlag er eksplicit: "præcis 8 rækker ... i alt". At
## tælle tabel-bredt (frem for kun blandt vores 551 narrative_id'er) fanger
## også en 9. binding et helt andet sted i tabellen, som en scopet optælling
## ville have overset. Reviewer-fund (Task 4 self-review): en scopet
## optælling er en svagere kontrakt end den Faktagrundlag faktisk beskriver.
narrative_replacement_check_bindings <- function(rows, manifest, narrative_ids) {
  if (!is.data.frame(rows) || nrow(rows) != 8L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_BINDING_TABLE_COUNT_INVALID")
  if (!all(rows$status == "published"))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_EXISTING_BINDING_INVALID")
  existing_ops <- Filter(function(op) identical(op$binding, "existing"), manifest$operations)
  existing_ids <- vapply(existing_ops, function(op) narrative_ids[[as.character(op$person_id)]], integer(1))
  if (length(existing_ids) != 8L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_BINDING_ARITHMETIC_INVALID")
  ## setequal frem for %in%: fanger BÅDE "tabellen indeholder en fremmed id"
  ## OG "en af vores 8 forventede eksisterer slet ikke" — nrow(rows)==8
  ## alene kunne maskere den sidste, hvis en fremmed id snuger sig ind i
  ## stedet for en af vores egne.
  if (!setequal(as.integer(rows$narrative_id), as.integer(existing_ids)))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_EXISTING_BINDING_MISMATCH")
  invisible(TRUE)
}

## rows: data.frame(record_key, id) fra private.source_record (source_id=3)
## for de 543 "create"-nøgler. Fase A-batchen SKAL være finalized for at
## disse findes (Faktagrundlag) — en manglende nøgle betyder enten at fase A
## ikke er kørt, eller at manifestet peger på en nøgle uden for fase A's 543.
narrative_replacement_check_source_records <- function(rows, create_keys) {
  if (!is.data.frame(rows) || nrow(rows) != length(create_keys) || anyDuplicated(rows$record_key))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_SOURCE_RECORD_COUNT_INVALID")
  result <- list()
  for (key in create_keys) {
    idx <- match(key, rows$record_key)
    if (is.na(idx))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_SOURCE_RECORD_MISSING:", key))
    result[[key]] <- as.character(rows$id[[idx]])
  }
  result
}

## rows: data.frame(person_id, narrative_sha256) genlæst EFTER de 551
## red_upsert_narrativ-kald.
narrative_replacement_check_verify_sha <- function(rows, manifest) {
  if (!is.data.frame(rows) || nrow(rows) != length(manifest$operations))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_VERIFY_COUNT_INVALID")
  for (op in manifest$operations) {
    idx <- match(op$person_id, rows$person_id)
    if (is.na(idx))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_VERIFY_MISSING:", op$person_id))
    if (!identical(as.character(rows$narrative_sha256[[idx]]), op$normalized_sha256))
      stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_VERIFY_SHA_MISMATCH:", op$person_id))
  }
  invisible(TRUE)
}

## total_count/published_count: HELE tabellen (ikke scopet) — "551 published
## bindinger i alt" (Faktagrundlag) betyder bogstaveligt tabellens fulde
## rækketal, ikke kun blandt vores 551 narrative_id'er. Kræver BEGGE ==551,
## så der hverken kan være en 552. draft-strage-række eller en 552. binding
## et andet sted.
narrative_replacement_check_verify_bindings <- function(total_count, published_count) {
  if (!identical(narrative_replacement_int(total_count), 551L) ||
      !identical(narrative_replacement_int(published_count), 551L))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_VERIFY_BINDINGS_INVALID")
  invisible(TRUE)
}

narrative_replacement_check_narrative_count <- function(before, after) {
  if (!identical(narrative_replacement_int(before), narrative_replacement_int(after)))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_NARRATIVE_COUNT_CHANGED")
  invisible(TRUE)
}

## before/after: named list(person=,fact=,relation=,family=,family_member=)
## — "family" dækkes af BÅDE family og family_member (union-tabellen og
## medlemskabet), så en union-side-effekt af en narrativ-erstatning aldrig
## kan glide igennem uopdaget.
narrative_replacement_check_canonical_counts <- function(before, after) {
  if (!identical(before, after))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_CANONICAL_COUNTS_CHANGED")
  invisible(TRUE)
}

## ---------------------------------------------------------------------
## Rene parameter-byggere til de to RPC-kald (Task 4-review Minor 4). Den
## rigtige gateway bruger disse i stedet for at bygge parameterlisten
## inline i query()-kaldet, så rækkefølgen kan asserteres DIREKTE i en test
## uden at gå via SQL/mock-udtræk — en ombytning af fx `FALSE`/`3L` giver et
## rødt test-svigt her, i stedet for først at vise sig som en DB-typefejl
## eller et forkert kildebundet narrativ.
## ---------------------------------------------------------------------

## Rækkefølge SKAL matche red_upsert_narrativ(p_subjekt_type,p_subjekt_id,
## p_tekst,p_privat,p_source_id,p_side) — schema.sql:3868-3870.
narrative_replacement_upsert_params <- function(op) {
  list("person", op$person_id, op$normalized_text, FALSE, 3L, as.character(op$page_from))
}

## Rækkefølge SKAL matche red_publicer_narrative_record(p_narrative_id,
## p_source_record_id,p_record_label,p_citation_label) — schema.sql:3074-3075.
narrative_replacement_publish_params <- function(narrative_id, source_record_id, record_label, citation_label) {
  list(narrative_id, source_record_id, record_label, citation_label)
}

## ---------------------------------------------------------------------
## Struktur-validering af gateway-svar (forsvar i dybden — fanger en
## fake/DBI-gateway-bug selvom de rene checkers ovenfor allerede passerede).
## ---------------------------------------------------------------------

validate_narrative_replacement_preflight_shape <- function(preflight) {
  required <- c("database_name", "system_identifier", "narrative_ids", "source_record_ids",
    "narrative_count_before", "canonical_counts_before")
  if (!narrative_replacement_names_equal(preflight, required))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  if (!narrative_replacement_scalar_string(preflight$database_name))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  if (!is.character(preflight$system_identifier) || length(preflight$system_identifier) != 1L ||
      is.na(preflight$system_identifier) || !grepl("^[0-9]+$", preflight$system_identifier))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  if (!is.list(preflight$narrative_ids) || length(preflight$narrative_ids) != 551L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  if (!is.list(preflight$source_record_ids) || length(preflight$source_record_ids) != 543L)
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  if (is.na(narrative_replacement_int(preflight$narrative_count_before)))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  if (!is.list(preflight$canonical_counts_before) ||
      !narrative_replacement_names_equal(preflight$canonical_counts_before,
        c("person", "fact", "relation", "family", "family_member")))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PREFLIGHT_INVALID")
  invisible(preflight)
}

validate_narrative_replacement_verify_shape <- function(verify) {
  required <- c("published_bindings", "narrative_count", "canonical_counts")
  if (!narrative_replacement_names_equal(verify, required))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_VERIFY_INVALID")
  if (!identical(narrative_replacement_int(verify$published_bindings), 551L))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_VERIFY_INVALID")
  if (is.na(narrative_replacement_int(verify$narrative_count)))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_VERIFY_INVALID")
  if (!is.list(verify$canonical_counts) ||
      !narrative_replacement_names_equal(verify$canonical_counts,
        c("person", "fact", "relation", "family", "family_member")))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_VERIFY_INVALID")
  invisible(verify)
}

## ---------------------------------------------------------------------
## Eksekvering. Kaldsorden: connect, begin (inkl. advisory lock), preflight,
## 551x upsert_narrativ, 543x publish (KUN binding=="create"), verify,
## rollback (dry-run) | commit (apply). Selve prod-apply'et er ikke en del af
## dette program (Global Constraints) — denne wrapper bygger og TESTER blot
## skrive-værktøjet; Task 5 kører rehearsalen, Task 6 den gatede prod-apply.
## ---------------------------------------------------------------------

execute_narrative_replacement_1939 <- function(manifest, mode = c("dry-run", "apply"), gateway) {
  mode <- match.arg(mode)
  validate_narrative_replacement_manifest(manifest)
  if (!is.list(gateway) || !is.function(gateway$call))
    stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_GATEWAY_INVALID")
  call <- gateway$call
  connected <- FALSE
  rolled_back <- FALSE
  rollback_once <- function() {
    if (connected && !rolled_back) {
      rolled_back <<- TRUE
      call("rollback")
    }
  }
  tryCatch({
    call("connect")
    connected <- TRUE
    call("begin")
    preflight <- call("preflight", manifest)
    validate_narrative_replacement_preflight_shape(preflight)

    for (op in manifest$operations) {
      expected_id <- preflight$narrative_ids[[as.character(op$person_id)]]
      if (is.null(expected_id))
        stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_NARRATIVE_MISSING:", op$person_id))
      got_id <- call("upsert_narrativ", op)
      if (!identical(narrative_replacement_int(got_id), narrative_replacement_int(expected_id)))
        stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_UNEXPECTED_INSERT:", op$person_id))
    }

    published <- list()
    for (op in manifest$operations) {
      if (!identical(op$binding, "create")) next
      narrative_id <- preflight$narrative_ids[[as.character(op$person_id)]]
      source_record_id <- preflight$source_record_ids[[op$source_record_key]]
      if (is.null(source_record_id))
        stop_narrative_replacement(paste0("NARRATIVE_REPLACEMENT_1939_SOURCE_RECORD_MISSING:", op$source_record_key))
      binding_id <- call("publish", narrative_id, source_record_id, op$record_label, op$citation_label)
      published[[op$source_record_key]] <- binding_id
    }
    if (length(published) != 543L)
      stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_PUBLISH_COUNT_INVALID")

    verify <- call("verify", manifest, preflight)
    validate_narrative_replacement_verify_shape(verify)

    if (identical(mode, "dry-run")) rollback_once() else call("commit")
    list(
      mode = mode, committed = identical(mode, "apply"),
      database_name = preflight$database_name, system_identifier = preflight$system_identifier,
      narratives_updated = length(manifest$operations),
      bindings_published = verify$published_bindings,
      canonical_counts = verify$canonical_counts
    )
  }, error = function(e) {
    rollback_once()
    stop(conditionMessage(e), call. = FALSE)
  })
}

## ---------------------------------------------------------------------
## Rigtig DBI-gateway. Rører ALDRIG prod fra denne task (kaldes kun af CLI'et,
## som Task 5/6 kører mod rehearsal/prod) — men skal være korrekt, da Task 5
## bruger den uændret.
## ---------------------------------------------------------------------

new_narrative_replacement_dbi_gateway <- function(connection_factory) {
  con <- NULL
  query <- function(sql, params = list()) {
    if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  }
  canonical_counts_now <- function() {
    row <- query(paste(
      "SELECT",
      "(SELECT count(*) FROM public.person) AS person,",
      "(SELECT count(*) FROM public.fact) AS fact,",
      "(SELECT count(*) FROM public.relation) AS relation,",
      "(SELECT count(*) FROM public.family) AS family,",
      "(SELECT count(*) FROM public.family_member) AS family_member"
    ))
    list(
      person = as.integer(row$person[[1L]]), fact = as.integer(row$fact[[1L]]),
      relation = as.integer(row$relation[[1L]]), family = as.integer(row$family[[1L]]),
      family_member = as.integer(row$family_member[[1L]])
    )
  }
  list(call = function(name, ...) {
    args <- list(...)
    switch(name,
      connect = { con <<- connection_factory(); invisible(NULL) },
      begin = {
        DBI::dbBegin(con)
        ## Samme låsenøgle som apply_phase_a_1939_v50/apply_reimport_1939_v50 —
        ## denne writer skriver mod samme narrative/source_record-domæne og
        ## SKAL serialisere mod de øvrige 1939-v50-writere, ikke bare mod sig
        ## selv. Nøglen er bevidst inlinet som literal (ikke via konstanten)
        ## så en deparse(body(...))-assertion kan se den direkte i SQL'en.
        query("SELECT pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0))")
        invisible(NULL)
      },
      preflight = {
        manifest <- args[[1L]]
        identity <- query("SELECT current_database() AS database_name,(pg_control_system()).system_identifier::text AS system_identifier")
        batch <- query("SELECT status FROM private.reimport_1939_write_batch WHERE id=$1::uuid",
          list(narrative_replacement_phase_a_batch_id))
        narrative_replacement_check_batch_status(if (nrow(batch) == 1L) batch$status[[1L]] else NA_character_)

        person_ids <- vapply(manifest$operations, function(op) op$person_id, integer(1))
        ## Important 1 (Task 4-review, controller-ruling 2026-08-19): n.privat
        ## og n.side tilføjet — red_upsert_narrativ's UPDATE-gren skriver
        ## begge kolonner ubetinget, men replay-værnet dækkede oprindeligt kun
        ## n.tekst. Se narrative_replacement_check_privat_and_side.
        narrative_rows <- query(
          paste(
            "SELECT n.subjekt_id AS person_id, n.id AS narrative_id,",
            "encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS narrative_sha256,",
            "n.privat AS privat, n.side AS side",
            "FROM public.narrative n WHERE n.subjekt_type='person' AND n.source_id=3",
            "AND n.subjekt_id = ANY($1::bigint[])"
          ),
          list(narrative_replacement_pg_bigint_array(person_ids))
        )
        narrative_ids <- narrative_replacement_check_old_sha(narrative_rows, manifest)
        narrative_replacement_check_privat_and_side(narrative_rows, manifest)

        ## HELE tabellen (ikke scopet til vores 551 narrative_id'er) —
        ## Faktagrundlag: "præcis 8 rækker ... i alt". Array-fri forespørgsel.
        binding_rows <- query("SELECT narrative_id, status FROM private.narrative_record_publication")
        narrative_replacement_check_bindings(binding_rows, manifest, narrative_ids)

        create_keys <- vapply(Filter(function(op) identical(op$binding, "create"), manifest$operations),
          function(op) op$source_record_key, character(1))
        source_rows <- query(
          "SELECT record_key, id::text AS id FROM private.source_record WHERE source_id=3 AND record_key = ANY($1::text[])",
          list(narrative_replacement_pg_text_array(create_keys))
        )
        source_record_ids <- narrative_replacement_check_source_records(source_rows, create_keys)

        narrative_count_before <- as.integer(query("SELECT count(*) AS n FROM public.narrative")$n[[1L]])
        canonical_counts_before <- canonical_counts_now()

        list(
          database_name = identity$database_name[[1L]], system_identifier = identity$system_identifier[[1L]],
          narrative_ids = narrative_ids, source_record_ids = source_record_ids,
          narrative_count_before = narrative_count_before, canonical_counts_before = canonical_counts_before
        )
      },
      upsert_narrativ = {
        op <- args[[1L]]
        query(
          "SELECT public.red_upsert_narrativ($1,$2,$3,$4,$5,$6) AS id",
          narrative_replacement_upsert_params(op)
        )$id[[1L]]
      },
      publish = {
        narrative_id <- args[[1L]]; source_record_id <- args[[2L]]
        record_label <- args[[3L]]; citation_label <- args[[4L]]
        query(
          "SELECT public.red_publicer_narrative_record($1,$2::uuid,$3,$4)::text AS id",
          narrative_replacement_publish_params(narrative_id, source_record_id, record_label, citation_label)
        )$id[[1L]]
      },
      verify = {
        manifest <- args[[1L]]; preflight <- args[[2L]]
        person_ids <- vapply(manifest$operations, function(op) op$person_id, integer(1))
        narrative_rows <- query(
          paste(
            "SELECT n.subjekt_id AS person_id,",
            "encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS narrative_sha256",
            "FROM public.narrative n WHERE n.subjekt_type='person' AND n.source_id=3",
            "AND n.subjekt_id = ANY($1::bigint[])"
          ),
          list(narrative_replacement_pg_bigint_array(person_ids))
        )
        narrative_replacement_check_verify_sha(narrative_rows, manifest)

        ## HELE tabellen — "551 published bindinger i alt" (Faktagrundlag)
        ## betyder tabellens fulde rækketal, ikke kun blandt vores 551
        ## narrative_id'er. Array-fri.
        total_count <- as.integer(query("SELECT count(*) AS n FROM private.narrative_record_publication")$n[[1L]])
        published_count <- as.integer(query(
          "SELECT count(*) AS n FROM private.narrative_record_publication WHERE status='published'"
        )$n[[1L]])
        narrative_replacement_check_verify_bindings(total_count, published_count)

        narrative_count_after <- as.integer(query("SELECT count(*) AS n FROM public.narrative")$n[[1L]])
        narrative_replacement_check_narrative_count(preflight$narrative_count_before, narrative_count_after)

        canonical_counts_after <- canonical_counts_now()
        narrative_replacement_check_canonical_counts(preflight$canonical_counts_before, canonical_counts_after)

        list(published_bindings = published_count, narrative_count = narrative_count_after,
          canonical_counts = canonical_counts_after)
      },
      rollback = { DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      commit = { DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      stop_narrative_replacement("NARRATIVE_REPLACEMENT_1939_GATEWAY_OPERATION_INVALID")
    )
  })
}
