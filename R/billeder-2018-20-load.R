# Indlæsning af portrætter fra DAA 2018-20 (særudgaven) som redaktionelle medier.
#
# Spec: docs/superpowers/specs/2026-11-24-billeder-2018-20-design.md (trin 2-3).
# Plan: docs/superpowers/plans/2026-11-24-billeder-2018-20.md (Task 2-3).
#
# Brug (fra repo-roden, i projektejerens shell):
#   Rscript R/billeder-2018-20-load.R                              # plan: læser prod, skriver intet
#   Rscript R/billeder-2018-20-load.R --svar <gennemgang.txt>      # plan med projektejerens svar
#   Rscript R/billeder-2018-20-load.R --svar <fil> --jeg-mener-det # skriver til prod
#
# Input: work_2018_saerudgave/billeder/manifest.json (fra .claude/skills/daa-extract/scripts/billeder_2018_20.py).
# Output (gitignoreret): plan.csv, gennemgang.txt, rapport.csv i samme mappe.

BILLEDER_MANIFEST <- "work_2018_saerudgave/billeder/manifest.json"
BILLEDER_PORTRAET_SLAGS <- c("foto", "maleri", "portræt", "portraet") # = PORTRAIT_SLAGS i web/src/data/media.ts

# ---------------------------------------------------------------------------------------------------------------
# Rene funktioner (Task 2)
# ---------------------------------------------------------------------------------------------------------------

parse_billede_args <- function(args) {
  ud <- list(skriv = FALSE, manifest = BILLEDER_MANIFEST, svar = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (identical(a, "--jeg-mener-det")) {
      ud$skriv <- TRUE
    } else if (identical(a, "--svar") || identical(a, "--manifest")) {
      if (i == length(args) || startsWith(args[[i + 1L]], "--")) stop(sprintf("%s kræver en sti", a), call. = FALSE)
      ud[[sub("^--", "", a)]] <- args[[i + 1L]]
      i <- i + 1L
    } else {
      stop(sprintf("Ukendt flag: %s", a), call. = FALSE)
    }
    i <- i + 1L
  }
  ud
}

.ref_til_person <- function(ref, ext) {
  hit <- ext$person_id[ext$linje == ref[[1]] & ext$nr == as.integer(ref[[2]])]
  if (length(hit) == 1L) as.character(hit) else NA_character_
}

match_aegtefaelle <- function(aar, navn, kandidater) {
  foedt <- suppressWarnings(as.integer(aar[[1]]))
  doed <- if (length(aar) >= 2L) suppressWarnings(as.integer(aar[[2]])) else NA_integer_
  if (nrow(kandidater) == 0L) {
    return(list(person_id = NA_character_, sikker = FALSE, begrundelse = "ankeret har ingen ægtefæller"))
  }
  passer <- !is.na(kandidater$foedt_aar) & kandidater$foedt_aar == foedt &
    (is.na(doed) | (!is.na(kandidater$doed_aar) & kandidater$doed_aar == doed))
  if (sum(passer) == 1L) {
    return(list(person_id = as.character(kandidater$person_id[passer]), sikker = TRUE,
                begrundelse = sprintf("ægtefælle med samme år: %s", kandidater$visning_navn[passer])))
  }
  if (sum(passer) > 1L) {
    return(list(person_id = as.character(kandidater$person_id[passer][[1]]), sikker = FALSE,
                begrundelse = sprintf("%d ægtefæller med samme år", sum(passer))))
  }
  if (nrow(kandidater) == 1L) {
    return(list(person_id = as.character(kandidater$person_id[[1]]), sikker = FALSE,
                begrundelse = sprintf("eneste ægtefælle (%s), år passer ikke", kandidater$visning_navn[[1]])))
  }
  list(person_id = NA_character_, sikker = FALSE, begrundelse = "ingen ægtefælle med samme år")
}

opslaa_afbildede <- function(billede, ext, aegtefaeller) {
  klasse <- billede$klasse
  refs <- billede$refs %||% list()
  if (identical(klasse, "aegtefaelle")) {
    anker <- .ref_til_person(billede$aegtefaelle_anker, ext)
    if (is.na(anker)) {
      return(list(person_ids = NA_character_, sikker = FALSE, begrundelse = "ankerets henvisning findes ikke"))
    }
    kand <- aegtefaeller[aegtefaeller$anker_person_id == anker,
                         c("person_id", "visning_navn", "foedt_aar", "doed_aar"), drop = FALSE]
    aar <- billede$aegtefaelle_aar %||% list(NA, NA)
    aar <- vapply(aar, function(x) if (is.null(x)) NA_integer_ else as.integer(x), integer(1))
    m <- match_aegtefaelle(aar, billede$aegtefaelle_navn, kand)
    return(list(person_ids = m$person_id, sikker = m$sikker, begrundelse = m$begrundelse))
  }
  if (length(refs) == 0L) {
    return(list(person_ids = NA_character_, sikker = FALSE, begrundelse = "ingen henvisning i billedteksten"))
  }
  ids <- vapply(refs, .ref_til_person, character(1), ext = ext)
  alle <- !anyNA(ids)
  if (identical(klasse, "egen")) {
    return(list(person_ids = ids, sikker = alle,
                begrundelse = if (alle) "henvisning" else "henvisningen findes ikke"))
  }
  list(person_ids = ids, sikker = FALSE,
       begrundelse = sprintf("%s: %d henvisninger, tjek om billedet viser andre", klasse, length(refs)))
}

kan_publiceres <- function(person_ids, alle_koblet) {
  isTRUE(alle_koblet) && length(person_ids) > 0L && !anyNA(person_ids)
}

portraet_handling <- function(medier) {
  if (nrow(medier) == 0L) return(list(handling = "ingen", media_id = NA_character_))
  if (any(medier$primaer %in% TRUE)) return(list(handling = "behold", media_id = NA_character_))
  slags <- tolower(trimws(ifelse(is.na(medier$slags), "", medier$slags)))
  i <- which(slags %in% BILLEDER_PORTRAET_SLAGS)
  valgt <- if (length(i)) i[[1]] else 1L
  list(handling = "laas", media_id = as.character(medier$media_id[[valgt]]))
}

byg_plan <- function(manifest, ext, aegtefaeller, person_medier, svar = NULL) {
  billeder <- manifest$billeder
  laast <- character()
  raekker <- lapply(billeder, function(b) {
    o <- opslaa_afbildede(b, ext, aegtefaeller)
    ids <- o$person_ids
    sikker <- o$sikker
    skjul <- FALSE
    besvaret <- if (is.null(svar)) integer() else which(svar$noegle == b$noegle)
    if (length(besvaret)) {
      s <- svar[besvaret[[1]], ]
      if (s$svar == "OK") {
        sikker <- TRUE
      } else if (s$svar == "ret") {
        ids <- as.character(s$person_ids[[1]])
        sikker <- TRUE
      } else if (s$svar == "skjul") {
        skjul <- TRUE
      }
    }
    portraet <- list()
    for (pid in unique(ids[!is.na(ids)])) {
      if (pid %in% laast) {
        portraet[[pid]] <- list(handling = "behold", media_id = NA_character_)
        next
      }
      h <- portraet_handling(person_medier[person_medier$person_id == pid, , drop = FALSE])
      if (h$handling == "laas") laast <<- c(laast, pid)
      portraet[[pid]] <- h
    }
    list(noegle = b$noegle, side = as.integer(b$side), person_ids = ids, sikker = sikker,
         maa_publiceres = !skjul && kan_publiceres(ids, sikker), portraet = portraet,
         begrundelse = o$begrundelse, titel = b$titel %||% "")
  })
  data.frame(
    noegle = vapply(raekker, `[[`, character(1), "noegle"),
    side = vapply(raekker, `[[`, integer(1), "side"),
    person_ids = I(lapply(raekker, `[[`, "person_ids")),
    sikker = vapply(raekker, `[[`, logical(1), "sikker"),
    maa_publiceres = vapply(raekker, `[[`, logical(1), "maa_publiceres"),
    portraet = I(lapply(raekker, `[[`, "portraet")),
    begrundelse = vapply(raekker, `[[`, character(1), "begrundelse"),
    titel = vapply(raekker, `[[`, character(1), "titel"),
    stringsAsFactors = FALSE
  )
}

skriv_gennemgang <- function(plan, sti) {
  usikre <- plan[!plan$sikker, , drop = FALSE]
  hoved <- c(
    "# Gennemgang af usikre billedkoblinger (DAA 2018-20). Skriv dit svar efter »svar:« på hver linje:",
    "#   OK            forslaget er rigtigt",
    "#   ret 12, 34    billedet viser person-id 12 og 34 (erstatter forslaget)",
    "#   skjul         importér billedet skjult (opfølgning senere)",
    "# Linjer uden svar importeres skjult."
  )
  linjer <- vapply(seq_len(nrow(usikre)), function(i) {
    ids <- usikre$person_ids[[i]]
    sprintf("%s | %d | %s | forslag: %s (%s) | svar: ", usikre$noegle[[i]], usikre$side[[i]],
            gsub("\\|", "/", usikre$titel[[i]]), paste(ifelse(is.na(ids), "?", ids), collapse = ", "),
            usikre$begrundelse[[i]])
  }, character(1))
  writeLines(enc2utf8(c(hoved, linjer)), sti, useBytes = TRUE)
  invisible(sti)
}

laes_svar <- function(sti) {
  linjer <- readLines(sti, encoding = "UTF-8", warn = FALSE)
  linjer <- linjer[nzchar(trimws(linjer)) & !startsWith(linjer, "#")]
  noegler <- character()
  svar <- character()
  ids <- list()
  for (linje in linjer) {
    noegle <- trimws(sub(" \\|.*$", "", linje))
    tekst <- trimws(sub("^.*\\| svar:", "", linje))
    if (!nzchar(tekst)) next
    if (identical(tolower(tekst), "ok")) {
      s <- "OK"; p <- character()
    } else if (identical(tolower(tekst), "skjul")) {
      s <- "skjul"; p <- character()
    } else if (grepl("^ret\\s+[0-9]+(\\s*,\\s*[0-9]+)*$", tekst, ignore.case = TRUE)) {
      s <- "ret"; p <- trimws(strsplit(sub("^ret\\s+", "", tekst, ignore.case = TRUE), ",")[[1]])
    } else {
      stop(sprintf("Ugyldigt svar for %s: »%s« (brug OK, ret <id>[, <id>] eller skjul)", noegle, tekst), call. = FALSE)
    }
    noegler <- c(noegler, noegle); svar <- c(svar, s); ids <- c(ids, list(p))
  }
  ud <- data.frame(noegle = noegler, svar = svar, stringsAsFactors = FALSE)
  ud$person_ids <- I(ids)
  ud
}

`%||%` <- function(a, b) if (is.null(a)) b else a
