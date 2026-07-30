# .claude/skills/daa-extract/scripts/load_helpers.R
# Rene, DB-frie hjælpere til load_daa.R — unit-testbare i testthat (ingen DB-I/O, ingen <<-).

# Tæller rækker pr. tabel i en buffer (enten en list — testthat-fixture — eller det
# rigtige .buf-environment fra load_daa.R). NB: names() bruges frem for ls() — ls()
# alfabetiserer, hvilket ikke matcher indsættelsesrækkefølgen for en list() og giver
# et positions-mismatch i expect_equal() mod en named vector i anden rækkefølge.
buffer_counts <- function(buf) {
  tbls <- names(buf)
  vapply(setNames(tbls, tbls), function(t) length(buf[[t]]), integer(1))
}

# FK-/mål-afhængig COPY-rækkefølge. Source-rækken skrives direkte før bufferen flushes.
# Polymorfe target_id'er har ingen fysisk FK, men behandles som en reel afhængighed:
# både fact og relation skal derfor eksistere før assertion/conclusion-laget.
load_flush_order <- function() c(
  "place", "person", "person_external_id", "estate", "organisation",
  "historical_event", "family", "family_member", "fact", "relation",
  "assertion", "citation", "conclusion", "note", "narrative"
)

flush_buffer_in_dependency_order <- function(buf, append_table) {
  for (tbl in load_flush_order()) {
    rows <- buf[[tbl]]
    if (length(rows)) append_table(tbl, rows)
  }
  invisible()
}

# Redaktionelle change_set-rækker (operation 'red_%') markerer arbejde der ikke må
# TRUNCATE'es. Import/load-changes gør ikke. Ren funktion; cs = data.frame m. 'operation'.
has_editorial_changes <- function(cs) {
  if (is.null(cs) || !nrow(cs)) return(FALSE)
  any(grepl("^red_", cs$operation))
}

# Kun OCR-rettelserne kan genopbygges sikkert fra import_korrektion efter reset.
# Alle øvrige redaktionelle change_set-operationer skal fortsat stoppe reset fail-closed.
has_reset_blocking_editorial_changes <- function(cs) {
  if (is.null(cs) || !nrow(cs)) return(FALSE)
  operation <- as.character(cs$operation)
  any(is.na(operation) | (grepl("^red_", operation) & operation != "red_ret_ocr_felt"))
}

# Gate-manifest-verifikation (#126): ren, DB-fri kontrakt. Manifestet skrives af
# validate.py sammen med clean.json; loaderen afviser artefakter hvis hash ikke
# matcher (forkert/ændret fil) eller hvis gaten var rød ved valideringen.
# Tærsklen 0.90 er den gate der historisk blev håndhævet pr. proces (og brudt:
# 1939 kom i prod på 88,8 %) — nu maskinel.
verify_gate_manifest <- function(manifest, faktisk_sha256, taerskel = 0.90) {
  m_sha <- manifest$sha256
  if (is.null(m_sha) || !length(m_sha) || is.na(m_sha) ||
      !identical(tolower(as.character(m_sha)), tolower(as.character(faktisk_sha256))))
    return(list(ok = FALSE, grund = "sha256-mismatch: manifestet beskriver ikke denne fil"))
  andel <- suppressWarnings(as.numeric(manifest$andel_rene))
  if (!length(andel) || is.na(andel))
    return(list(ok = FALSE, grund = "manifest mangler andel_rene"))
  if (andel < taerskel)
    return(list(ok = FALSE, grund = sprintf("gate RØD: andel_rene %.1f%% < tærskel %.0f%%",
                                            100 * andel, 100 * taerskel)))
  list(ok = TRUE, grund = sprintf("gate GRØN: andel_rene %.1f%%", 100 * andel))
}

# Korrektionsimporter skal have en stabil, eksplicit nøgle. Ældre importer er kun
# tilladt med et bevidst legacy-flag og får derfor NULL import_key/record_key i DB.
parse_load_daa_args <- function(argv) {
  if (!length(argv) || startsWith(argv[1], "--"))
    stop("brug: load_daa.R clean.json [udgave] --import-key=<nøgle> [--reset] [--force-reset] [--force-gate] [--dry-run] [--staged] | --legacy-import")

  import_flags <- grep("^--import-key=", argv, value = TRUE)
  if (length(import_flags) > 1L) stop("--import-key må kun angives én gang")
  legacy_import <- "--legacy-import" %in% argv
  if (legacy_import && length(import_flags))
    stop("--legacy-import og --import-key kan ikke kombineres")
  if (!legacy_import && !length(import_flags))
    stop("--import-key kræves; brug kun --legacy-import for en ikke-redigerbar legacy-import")

  import_key <- if (length(import_flags)) sub("^--import-key=", "", import_flags) else NULL
  if (!is.null(import_key) && !nzchar(trimws(import_key))) stop("import-key må ikke være tom")
  positional <- argv[-1][!startsWith(argv[-1], "--")]
  list(
    path = argv[1],
    udgave = if (length(positional)) positional[1] else "DAA 2018-20",
    import_key = import_key,
    legacy_import = legacy_import,
    reset = "--reset" %in% argv,
    force_reset = "--force-reset" %in% argv,
    force_gate = "--force-gate" %in% argv,
    dry_run = "--dry-run" %in% argv,
    staged = "--staged" %in% argv
  )
}

# Den fulde resetliste er centraliseret her, så kontrakten kan testes uden DB-forbindelse.
loader_model_tables <- function() c(
  "note", "citation", "conclusion", "assertion", "relation", "fact",
  "family_member", "family", "person_external_id", "narrative", "person",
  "coat_of_arms", "historical_event", "media", "estate", "organisation", "place", "source"
)

# Versioneringstabeller der SKAL med i en reset-TRUNCATE (#124): historikken er
# nøglet til model-id'er som TRUNCATE frigiver til genbrug — overlever den,
# fremstår gamle events knyttet til nye, forkerte rækker. import_korrektion er
# bevidst IKKE her: journalen er nøglet på (import_key, record_key) og skal
# netop overleve reset (replay-laget).
loader_versioning_tables <- function() c("change_set", "change_event")

external_id_buffer_row <- function(pid, sid, linje, nr, record_key) {
  list(person_id = pid, source_id = sid, linje = linje, nr = nr, record_key = record_key)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Reload-stabil postnøgle: bogens linje + dens label (15a må aldrig blive til 15).
# Uden begge bog-identiteter er opslaget ikke sikkert; database-id og navn er bevidst
# ikke kandidater til fallback.
record_key_of <- function(rec) {
  # Bærer posten et id fra identitetsregisteret, er DET nøglen — også når
  # linje/nr findes. Identitet udstedes, den udledes ikke: `linje-nr` er for
  # DAA 1939 en gennemløbende tæller der flytter sig ved re-segmentering, mens
  # registerets id er mintet én gang mod en fysisk boglokator
  # (data/identitet/, docs/decisions.md).
  #
  # Fallback til `linje-nr` bevarer DAA 2018-20 uændret: dér er artefaktets
  # filnavne selv nøglen, og der er intet register-id på posten.
  udstedt <- rec$record_key
  if (!is.null(udstedt) && length(udstedt) == 1L && !is.na(udstedt) &&
      nzchar(as.character(udstedt))) {
    return(as.character(udstedt))
  }
  linje <- rec$linje
  nr <- rec$nr_label %||% rec$nr
  if (is.null(linje) || length(linje) == 0L || is.na(linje) ||
      is.null(nr) || length(nr) == 0L || is.na(nr)) return(NA_character_)
  paste0(as.character(linje), "-", as.character(nr))
}

# Journalen gemmer importerede værdier i en lille, fast JSON-kontrakt, så både R og
# SQL kan fingerprint'e samme bytes. Listeorden er JSON-nøgleorden.
canonical_import_value <- function(felt, value) {
  if (felt %in% c("foedsel", "doed")) {
    date_value <- if (is.list(value)) value else list(raw = value)
    canonical <- list(
      raw = date_value$raw %||% date_value$date_raw %||% NA_character_,
      min = date_value$min %||% date_value$date_min %||% NA_character_,
      max = date_value$max %||% date_value$date_max %||% NA_character_,
      qualifier = date_value$qualifier %||% date_value$date_qualifier %||% NA_character_,
      calendar = date_value$calendar %||% "gregoriansk",
      certainty = date_value$certainty %||% date_value$date_certainty %||% NA_character_
    )
  } else {
    canonical <- list(value = value)
  }
  jsonlite::toJSON(canonical, auto_unbox = TRUE, null = "null", na = "null")
}

.canonical_import_json <- function(felt, importeret) {
  if (is.character(importeret) && length(importeret) == 1L) {
    parsed <- tryCatch(jsonlite::fromJSON(importeret, simplifyVector = FALSE),
                       error = function(e) NULL)
    if (is.list(parsed)) {
      value <- if (felt %in% c("foedsel", "doed")) parsed else
        if ("value" %in% names(parsed)) parsed$value else parsed
      return(canonical_import_value(felt, value))
    }
  }
  canonical_import_value(felt, importeret)
}

ocr_input_fingerprint <- function(import_key, record_key, felt, importeret, ocr_context) {
  text_part <- function(value) {
    if (is.null(value) || !length(value) || is.na(value[1])) "" else as.character(value[1])
  }
  values <- c(text_part(import_key), text_part(record_key), text_part(felt),
              .canonical_import_json(felt, importeret), text_part(ocr_context))
  payload <- paste(enc2utf8(as.character(values)), collapse = rawToChar(as.raw(0x1f)))
  digest::digest(payload, algo = "md5", serialize = FALSE)
}

.correction_rows <- function(corrections) {
  if (is.null(corrections) || !length(corrections)) return(list())
  if (is.data.frame(corrections)) {
    return(lapply(seq_len(nrow(corrections)), function(i) as.list(corrections[i, , drop = FALSE])))
  }
  corrections
}

.same_correction_key <- function(a, b) {
  length(a) == 1L && length(b) == 1L && !is.na(a) && !is.na(b) &&
    identical(as.character(a), as.character(b))
}

.correction_index_key <- function(record_key, felt) paste(record_key, felt, sep = rawToChar(as.raw(0x1f)))

# Preload er én DB-forespørgsel i loaderen; dette indeks gør alle efterfølgende opslag O(1).
index_import_corrections <- function(corrections) {
  index <- new.env(parent = emptyenv())
  for (row in .correction_rows(corrections)) {
    if (!is.null(row$record_key) && !is.null(row$felt))
      assign(.correction_index_key(row$record_key, row$felt), row, envir = index)
  }
  index
}

.find_import_correction <- function(import_key, record_key, felt, corrections) {
  if (is.environment(corrections))
    return(get0(.correction_index_key(record_key, felt), envir = corrections, inherits = FALSE))
  matches <- Filter(function(row) {
    .same_correction_key(row$import_key, import_key) &&
      .same_correction_key(row$record_key, record_key) &&
      .same_correction_key(row$felt, felt)
  }, .correction_rows(corrections))
  if (length(matches)) matches[[1]] else NULL
}

apply_import_correction <- function(import_key, record_key, felt, importeret,
                                    ocr_context, corrections) {
  fingerprint <- ocr_input_fingerprint(import_key, record_key, felt, importeret, ocr_context)
  result <- list(value = importeret, status = "ingen", fingerprint = fingerprint,
                 correction_id = NA)
  correction <- .find_import_correction(import_key, record_key, felt, corrections)
  if (is.null(correction)) return(result)
  result$correction_id <- correction$id %||% NA
  if (!.same_correction_key(correction$input_fingerprint, fingerprint)) {
    result$status <- "stale"
    return(result)
  }
  if (identical(correction$status, "rettet") && !is.null(correction$korrigeret)) {
    result$value <- correction$korrigeret
    result$status <- "anvendt"
  }
  result
}

# Normalisér en enkelt værdi fra en afkodet korrektion til en buffer-egnet skalar.
# jsonlite::fromJSON() bruger default null = "list", så JSON-null bliver list() og ikke
# NULL. En sådan nul-længde-værdi overlever g()'s NULL-guard, og unlist() i rows_to_df
# dropper den bagefter, så kolonnen bliver kortere end tabellen.
correction_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA)
  if (length(x) > 1L)
    stop("Korrektionsværdi skal være en skalar, fik ", length(x), " elementer.")
  if (is.list(x)) return(correction_scalar(x[[1L]]))
  x
}

# Fail-closed: en buffer-kolonne der ikke har præcis én værdi pr. række ville ellers
# først fejle i as.data.frame() med en besked uden tabel- eller kolonnenavn.
assert_buffer_columns <- function(data, nrows, tbl = NA_character_) {
  lens <- vapply(data, length, integer(1))
  bad <- names(lens)[lens != nrows]
  if (length(bad))
    stop("Buffer-tabel '", tbl, "': kolonne(r) ", paste(bad, collapse = ", "),
         " har længde ", paste(lens[bad], collapse = ", "),
         " men tabellen har ", nrows, " rækker.")
  invisible(TRUE)
}

stale_correction_ids <- function(results) {
  ids <- vapply(results, function(result) {
    if (identical(result$status, "stale")) result$correction_id %||% NA else NA
  }, numeric(1))
  unique(ids[!is.na(ids)])
}

# Er en DB-fejlbesked et "relation findes ikke"-signal (Postgres 42P01)? Så er
# change_set-tabellen fraværende (umigreret base) -> sikkert at antage 0 redaktionelle
# rækker. Alle andre fejl er usikre og skal fejle lukket.
is_missing_table_error <- function(msg) {
  grepl("relation .* does not exist|42P01", msg %||% "", ignore.case = TRUE)
}

# Intern reference = "se nr. N" / "nr. N" / "… linje, nr. N" i SAMME kilde.
# Ekstern (anden DAA-udgave, "DAA 1937, II, 122") -> NULL: stub oprettes stadig.
parse_intern_ref <- function(ref, default_linje) {
  if (is.null(ref) || length(ref) == 0 || is.na(ref)) return(NULL)
  if (grepl("DAA|\\b1[89]\\d\\d\\b", ref)) return(NULL)   # ekstern udgave
  linje <- default_linje
  lm <- regmatches(ref, regexpr("\\b(I{1,3}V?|VI{0,3})\\b(?=\\.?\\s*Den|,\\s*nr)", ref, perl=TRUE))
  if (length(lm) && nzchar(lm)) linje <- lm
  nm <- regmatches(ref, regexpr("nr\\.?\\s*(\\d+)", ref, perl=TRUE))
  if (!length(nm) || !nzchar(nm)) return(NULL)
  nr <- sub(".*?(\\d+).*", "\\1", nm)
  list(linje = linje, nr = nr)
}

# Nøgler i pmap der matcher et barn-basenr. Foretræk eksakt "linje-nr"; ellers
# 15a/15b-varianter (barn af en 15a/15b-forælder registreres under labels, ikke basenr).
resolve_barn_keys <- function(linje, nr, pmap_keys) {
  eksakt <- paste0(linje, "-", nr)
  if (eksakt %in% pmap_keys) return(eksakt)
  grep(sprintf("^%s-%d[a-z]$", linje, nr), pmap_keys, value = TRUE)
}
# Diagnostisk årsag til et barn-opslag, ud fra de resolverede nøgler.
barn_lookup_reason <- function(keys) if (length(keys) > 0) "ok" else "nr_ikke_i_forael_linje"

# Danske ordenstals-ord -> tal. Returnerer ét entydigt tal, ellers NA (flere
# distinkte ord => tvetydigt). Fixed-substring (ikke \\b) fordi æ/ø/å ikke er
# pålidelige word-chars i R's regex-motor.
.dk_ordinal_tal <- function(low) {
  ord <- c("første"=1L, "anden"=2L, "andet"=2L, "tredje"=3L,
           "fjerde"=4L, "femte"=5L, "sjette"=6L, "syvende"=7L)
  traf <- ord[vapply(names(ord), function(w) grepl(w, low, fixed = TRUE), logical(1))]
  vals <- unique(unname(traf))
  if (length(vals) == 1L) vals else NA_integer_
}

# navn≠ref-guard (#125; diskriminator-beslutning 2026-07-03): når en ægteskabs-
# post BÅDE bærer partner_navn og en intern partner_ekstern_ref, skal de to
# uafhængige signaler være enige før ref-linket bruges — mis-opløste "se nr."-
# refs skabte 26 spøgelses-unioner (barn "gift" med egen ane). Tolerant
# sammenligning i match_barn_union-stil: alle tokens fra den ene side indeholdt
# i den anden (1939-poster bærer ofte kun fornavne i navn-feltet), ellers delt
# navne-token ≥4 tegn. TRUE = enige, FALSE = uenige (afvis ref-linket),
# NA = kan ikke afgøres (navn mangler på en side) — NA må ALDRIG afvise:
# kun beviselig uenighed parkerer, jf. konservativ-scope-læringen.
partner_ref_navn_enige <- function(partner_navn, ref_navn) {
  toks <- function(x) {
    if (is.null(x) || length(x) == 0L || is.na(x)) return(character(0))
    t <- strsplit(tolower(trimws(as.character(x))), "[^[:alnum:]]+")[[1]]
    t[nzchar(t)]
  }
  pt <- toks(partner_navn); rt <- toks(ref_navn)
  if (!length(pt) || !length(rt)) return(NA)
  if (all(pt %in% rt) || all(rt %in% pt)) return(TRUE)
  length(intersect(pt[nchar(pt) >= 4L], rt[nchar(rt) >= 4L])) > 0L
}

# match_barn_union: knyt et barns fritekst-`aegteskab_kontekst` til ét af
# forælderens ægteskaber. `aegteskaber` er rec$aegteskaber (samme rækkefølge som
# loaderens `fams`-liste), hvert element en liste m. $ordinal + $partner_navn.
#
# Primær anker: PARTNERNAVN (positions-uafhængigt, entydigt når navne adskiller
# sig). Kryds-tjek: ordenstals-ord mappet til det ægteskab hvis $ordinal *er lig*
# tallet (ikke positionelt — nogle rækker kan have ordinal=NA). Er begge til
# stede og uenige => NA (log, gæt aldrig). Navngiver konteksten en partner der
# ikke er blandt ægteskaberne (fx et barn af en ikke-registreret forbindelse)
# => NA m. reason 'ukendt_partner', så kalderen kan parkere frem for at fejl-
# tilknytte til 1. ægteskab.
#
# Retur: list(idx=<1-baseret indeks i aegteskaber, el. NA>, reason, via).
match_barn_union <- function(ctx, aegteskaber) {
  na_res <- function(reason) list(idx = NA_integer_, reason = reason, via = NA_character_)
  n <- length(aegteskaber)
  if (n == 0L) return(na_res("ingen_aegteskaber"))
  if (is.null(ctx) || length(ctx) == 0L || is.na(ctx) || !nzchar(trimws(ctx)))
    return(na_res("tom_kontekst"))
  low <- tolower(ctx)

  # --- primær: partnernavn (fuldt navn som substring; ellers distinkt efternavn) ---
  pnames <- vapply(aegteskaber, function(a) {
    v <- a[["partner_navn"]]
    if (is.null(v) || length(v) == 0L || is.na(v)) "" else tolower(trimws(v))
  }, character(1))
  partner_hits <- which(vapply(seq_len(n), function(i) {
    pn <- pnames[i]
    if (!nzchar(pn)) return(FALSE)
    if (grepl(pn, low, fixed = TRUE)) return(TRUE)          # fuldt navn nævnt
    toks <- strsplit(pn, "\\s+")[[1]]
    efternavn <- toks[length(toks)]                          # "von Qualen" -> "qualen"
    nchar(efternavn) >= 4L && grepl(efternavn, low, fixed = TRUE)
  }, logical(1)))

  # --- kryds-tjek: ordenstals-ord -> ægteskab hvis $ordinal matcher tallet ---
  ord_num <- .dk_ordinal_tal(low)
  ordinal_hits <- if (!is.na(ord_num)) {
    which(vapply(aegteskaber, function(a) {
      o <- a[["ordinal"]]
      !is.null(o) && length(o) && !is.na(o) && suppressWarnings(as.integer(o)) == ord_num
    }, logical(1)))
  } else integer(0)

  up <- unique(partner_hits); uo <- unique(ordinal_hits)
  if (length(up) == 1L && length(uo) == 1L) {
    if (up == uo) return(list(idx = up, reason = "ok", via = "begge"))
    return(na_res("konflikt_partner_vs_ordenstal"))
  }
  if (length(up) == 1L) return(list(idx = up, reason = "ok", via = "partner"))
  if (length(uo) == 1L) return(list(idx = uo, reason = "ok", via = "ordenstal"))
  if (length(up) > 1L)  return(na_res("flertydigt_partnernavn"))
  na_res("ukendt_partner")   # partner nævnt men ikke blandt ægteskaberne, el. intet spor
}
