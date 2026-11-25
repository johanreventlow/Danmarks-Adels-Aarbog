# Flytning af billedtypen fra teknik til motiv for de 56 billeder, projektejeren godkendte 2026-11-25
# (gennemgang-slags-56.html: »OK«). Spec: docs/superpowers/specs/2026-11-25-media-slags-ordliste-design.md.
#
#   maleri (45) og foto (9) → portræt; scanning (2, linjevåbnene) → våben.
#   Teknik som medie-faktum kun for bogens billeder (original_filnavn daa-2018-20-…), hvor billedteksten siger det:
#   maleri → »Maleri« (»Malet af …«), foto → »Fotografi« (»Foto: …«). De ældre uploads (10-16) får ingen teknik.
#
# Skriver gennem redaktørens RPC'er (red_opdater_media, red_upsert_fakta), så hver ændring står i historikken og kan
# fortrydes. Idempotent: et billede, der allerede har den nye slags, springes over; en eksisterende teknik røres ikke.
#
# Brug (fra repo-roden, i projektejerens shell):
#   Rscript R/media-slags-flytning.R                   # plan: læser prod, skriver intet
#   Rscript R/media-slags-flytning.R --proev-binding   # afspiller kaldene for ét billede i en READ ONLY-transaktion
#   Rscript R/media-slags-flytning.R --jeg-mener-det   # skriver til prod

FLYT_REDAKTOER_UUID <- "ba4ce28d-42a0-48af-a47c-773c26934236" # samme som R/billeder-2018-20-load.R

# Projektejerens godkendte mængde (2026-11-25). Planen stopper, hvis prods mængde afviger.
FLYT_GODKENDT <- list(
  maleri = as.character(c(36, 37, 38, 41, 42, 57, 60, 63, 64, 67, 68, 71, 72, 74, 76, 77, 81, 82, 83, 84, 85, 86, 87,
                          90, 91, 92, 93, 102, 104, 105, 106, 107, 128, 131, 134, 135, 136, 146, 147, 148, 149, 151,
                          153, 160, 161)),
  foto = as.character(c(10, 11, 12, 13, 14, 16, 141, 156, 169)),
  scanning = as.character(c(7, 8))
)
FLYT_NY_SLAGS <- c(maleri = "portræt", foto = "portræt", scanning = "våben")
FLYT_TEKNIK <- c(maleri = "Maleri", foto = "Fotografi")

# rows: data.frame(id, slags, original_filnavn, har_teknik) for de godkendte id'er (fra prod).
# allerede: id'er, der allerede har den nye slags (fra en tidligere, evt. afbrudt kørsel).
byg_flytteplan <- function(rows, godkendt = FLYT_GODKENDT, allerede = character()) {
  for (gl in names(godkendt)) {
    faktisk <- sort(c(rows$id[rows$slags == gl], intersect(allerede, godkendt[[gl]])))
    if (!identical(faktisk, sort(godkendt[[gl]]))) {
      stop(sprintf("FLYT_MAENGDE_AENDRET: prods »%s«-mængde afviger fra den godkendte (mangler: %s; ekstra: %s)", gl,
                   paste(setdiff(godkendt[[gl]], faktisk), collapse = ","), paste(setdiff(faktisk, godkendt[[gl]]), collapse = ",")),
           call. = FALSE)
    }
  }
  r <- rows[rows$slags %in% names(godkendt) & !(rows$id %in% allerede), , drop = FALSE]
  bog <- grepl("^daa-2018-20-s[0-9]{4}-", r$original_filnavn)
  side <- rep(NA_integer_, nrow(r))
  side[bog] <- as.integer(sub("^daa-2018-20-s([0-9]{4})-.*$", "\\1", r$original_filnavn[bog]))
  teknik <- ifelse(bog & !r$har_teknik & r$slags %in% names(FLYT_TEKNIK), unname(FLYT_TEKNIK[r$slags]), NA_character_)
  data.frame(id = r$id, gl_slags = r$slags, ny_slags = unname(FLYT_NY_SLAGS[r$slags]), teknik = teknik,
             side = as.integer(side), stringsAsFactors = FALSE)
}

# raekke: list(id, ny_slags, teknik, side). ops: transaktion, aktoer, rpc (som R/billeder-2018-20-load.R).
anvend_flytning <- function(raekke, ops) {
  ops$transaktion(function() {
    rolle <- ops$aktoer(FLYT_REDAKTOER_UUID)
    if (!identical(rolle, "redaktion")) stop("Aktøren er ikke redaktion — intet skrevet.", call. = FALSE)
    ops$rpc("red_opdater_media", list(p_media_id = raekke$id, p_slags = raekke$ny_slags))
    if (!is.na(raekke$teknik)) {
      ops$rpc("red_upsert_fakta", list(
        p_subjekt_type = "media", p_subjekt_id = raekke$id, p_faktatype = "teknik", p_vaerdi = raekke$teknik,
        p_kilde_fritekst = sprintf("DAA 2018-20, s. %d", as.integer(raekke$side))))
    }
  })
  invisible(TRUE)
}

hent_flytteraekker <- function(con) {
  ids <- unique(unlist(FLYT_GODKENDT))
  r <- DBI::dbGetQuery(con, "
    SELECT m.id::text AS id, m.slags, coalesce(m.original_filnavn, '') AS original_filnavn,
           EXISTS (SELECT 1 FROM fact f WHERE f.subjekt_type = 'media' AND f.subjekt_id = m.id AND f.faktatype = 'teknik')
             AS har_teknik
      FROM media m WHERE m.id = ANY($1::bigint[]) ORDER BY m.id", params = list(paste0("{", paste(ids, collapse = ","), "}")))
  r$har_teknik <- as.logical(r$har_teknik)
  # den nye slags pr. godkendt id; et id, der allerede har den, er flyttet (fx ved en afbrudt kørsel)
  ny_for <- stats::setNames(rep(unname(FLYT_NY_SLAGS[names(FLYT_GODKENDT)]), lengths(FLYT_GODKENDT)), unlist(FLYT_GODKENDT))
  allerede <- r$id[r$slags == ny_for[r$id]]
  list(rows = r[!(r$id %in% allerede), , drop = FALSE], allerede = allerede, alle = r)
}

run_media_slags_flytning <- function(args = commandArgs(trailingOnly = TRUE)) {
  ukendt <- setdiff(args, c("--jeg-mener-det", "--proev-binding"))
  if (length(ukendt)) stop(sprintf("Ukendt flag: %s", paste(ukendt, collapse = " ")), call. = FALSE)
  skriv <- "--jeg-mener-det" %in% args
  proev <- "--proev-binding" %in% args
  if (skriv && proev) stop("--proev-binding kan ikke kombineres med --jeg-mener-det", call. = FALSE)

  loader <- new.env()
  sys.source(file.path("R", "billeder-2018-20-load.R"), envir = loader)
  janitor <- loader$source_janitor_helpers()
  con <- janitor$connect_media_janitor_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  h <- hent_flytteraekker(con)
  if (nrow(h$alle) != length(unique(unlist(FLYT_GODKENDT)))) {
    stop(sprintf("FLYT_MAENGDE_AENDRET: %d af 56 godkendte billeder findes i prod.", nrow(h$alle)), call. = FALSE)
  }
  plan <- byg_flytteplan(h$rows, allerede = h$allerede)
  message(sprintf("Plan: %d billeder at flytte (%d allerede flyttet) · %d teknik-fakta · %s",
                  nrow(plan), length(h$allerede), sum(!is.na(plan$teknik)),
                  paste(sprintf("%s→%s %d", names(table(plan$gl_slags)), FLYT_NY_SLAGS[names(table(plan$gl_slags))],
                                as.integer(table(plan$gl_slags))), collapse = ", ")))

  ops <- loader$default_billede_ops(con, janitor)
  if (proev) {
    if (!nrow(plan)) { message("Intet at prøve: alt er flyttet."); return(invisible(NULL)) }
    i <- which(!is.na(plan$teknik))[1]; if (is.na(i)) i <- 1L
    kald <- list()
    anvend_flytning(as.list(plan[i, ]), list(transaktion = function(fn) fn(), aktoer = function(u) "redaktion",
      rpc = function(navn, args) kald[[length(kald) + 1L]] <<- list(navn = navn, args = args)))
    for (k in kald) {
      DBI::dbExecute(con, "BEGIN READ ONLY")
      DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub', $1, true)", params = list(FLYT_REDAKTOER_UUID))
      res <- tryCatch({ DBI::dbGetQuery(con, loader$byg_rpc_sql(k$navn, k$args), params = unname(k$args)); "intet (read-only burde stoppe)" },
                      error = function(e) { st <- loader$sqlstate_fra_besked(conditionMessage(e))
                        sprintf("%s %s", if (loader$binding_ok(st)) "OK" else "FEJL", paste0(st, ": ", substr(conditionMessage(e), 1, 100))) })
      DBI::dbExecute(con, "ROLLBACK")
      message(sprintf("%-20s %s", k$navn, res))
    }
    return(invisible(NULL))
  }
  if (!skriv) { message("Prøvekørsel: intet skrevet. Kør med --jeg-mener-det for at skrive."); return(invisible(plan)) }

  res <- vapply(seq_len(nrow(plan)), function(i) {
    tryCatch({ anvend_flytning(as.list(plan[i, ]), ops); "flyttet" }, error = function(e) paste("fejl:", conditionMessage(e)))
  }, character(1))
  print(table(res))
  efter <- DBI::dbGetQuery(con, "SELECT slags, count(*)::int AS n FROM media GROUP BY 1 ORDER BY 2 DESC")
  print(efter)
  invisible(res)
}

if (sys.nframe() == 0L) run_media_slags_flytning()
