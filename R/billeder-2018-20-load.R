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
  ud <- list(skriv = FALSE, manifest = BILLEDER_MANIFEST, svar = NULL, proev_binding = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (identical(a, "--jeg-mener-det")) {
      ud$skriv <- TRUE
    } else if (identical(a, "--proev-binding")) {
      ud$proev_binding <- TRUE
    } else if (identical(a, "--svar") || identical(a, "--manifest")) {
      if (i == length(args) || startsWith(args[[i + 1L]], "--")) stop(sprintf("%s kræver en sti", a), call. = FALSE)
      ud[[sub("^--", "", a)]] <- args[[i + 1L]]
      i <- i + 1L
    } else {
      stop(sprintf("Ukendt flag: %s", a), call. = FALSE)
    }
    i <- i + 1L
  }
  if (ud$skriv && ud$proev_binding) stop("--proev-binding kan ikke kombineres med --jeg-mener-det", call. = FALSE)
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
  passer <- if (is.na(foedt)) rep(FALSE, nrow(kandidater)) else
    (!is.na(kandidater$foedt_aar) & kandidater$foedt_aar == foedt &
       (is.na(doed) | (!is.na(kandidater$doed_aar) & kandidater$doed_aar == doed)))
  passer <- passer %in% TRUE
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
  # Runde 3: kuraterede objekt-koblinger (media → lineage/estate). Kuraterede person-henvisninger (fx Vallø + Anna
  # Sophia, projektejeren 24/11) slås op som andre; findes én ikke, er billedet usikkert og skjules (fail-closed).
  if (!is.null(billede$objekt)) {
    ids <- vapply(refs, .ref_til_person, character(1), ext = ext)
    return(list(person_ids = ids, sikker = !anyNA(ids),
                begrundelse = sprintf("objekt: %s %s%s", billede$objekt$type, billede$objekt$id,
                                      if (length(ids)) " + personer" else "")))
  }
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
    if (isTRUE(billede$ekstra_tekst)) {
      return(list(person_ids = m$person_id, sikker = FALSE,
                  begrundelse = paste0(m$begrundelse, "; billedteksten nævner mere end personen")))
    }
    return(list(person_ids = m$person_id, sikker = m$sikker, begrundelse = m$begrundelse))
  }
  if (length(refs) == 0L) {
    return(list(person_ids = NA_character_, sikker = FALSE, begrundelse = "ingen henvisning i billedteksten"))
  }
  ids <- vapply(refs, .ref_til_person, character(1), ext = ext)
  alle <- !anyNA(ids)
  if (identical(klasse, "egen") && isTRUE(billede$ekstra_tekst)) {
    return(list(person_ids = ids, sikker = FALSE,
                begrundelse = "billedteksten nævner mere end personen (fx »og hustru«): tilføj de øvrige afbildede"))
  }
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
  # Fjernede medier vises ikke og kan ikke låses (final review, vigtigt fund 2).
  if ("upload_status" %in% names(medier)) medier <- medier[medier$upload_status %in% "klar", , drop = FALSE]
  if (nrow(medier) == 0L) return(list(handling = "ingen", media_id = NA_character_, person_id = NA_character_))
  if (any(medier$primaer %in% TRUE)) {
    return(list(handling = "behold", media_id = NA_character_, person_id = NA_character_))
  }
  slags <- tolower(trimws(ifelse(is.na(medier$slags), "", medier$slags)))
  i <- which(slags %in% BILLEDER_PORTRAET_SLAGS)
  valgt <- if (length(i)) i[[1]] else 1L
  # Låsen skal sidde på det id, relationen faktisk har (et samme_som-alias), ellers afviser red_saet_portraet.
  medlem <- if ("medlem" %in% names(medier)) as.character(medier$medlem[[valgt]]) else NA_character_
  list(handling = "laas", media_id = as.character(medier$media_id[[valgt]]), person_id = medlem)
}

byg_plan <- function(manifest, ext, aegtefaeller, person_medier, svar = NULL) {
  billeder <- manifest$billeder
  if (!is.null(svar) && nrow(svar)) {
    kendte <- vapply(billeder, `[[`, character(1), "noegle")
    ukendte <- setdiff(svar$noegle, kendte)
    if (length(ukendte)) stop(sprintf("SVAR_UKENDT_NOEGLE: %s", paste(ukendte, collapse = ", ")), call. = FALSE)
  }
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
        # OK gælder det forslag, projektejeren så — ikke hvad prod giver i dag (final review, vigtigt fund 3).
        set_forslag <- if ("forslag" %in% names(svar)) as.character(s$forslag[[1]]) else NULL
        if (!is.null(set_forslag) && !identical(sort(set_forslag), sort(ifelse(is.na(ids), "?", ids)))) {
          stop(sprintf("SVAR_FORSLAG_AENDRET: %s (så %s, nu %s)", b$noegle, paste(set_forslag, collapse = ","),
                       paste(ids, collapse = ",")), call. = FALSE)
        }
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
    objekt <- if (is.null(b$objekt)) NULL else list(type = as.character(b$objekt$type), id = as.integer(b$objekt$id))
    publicerbar <- kan_publiceres(ids, sikker) || (!is.null(objekt) && length(ids) == 0L && isTRUE(sikker))
    list(noegle = b$noegle, side = as.integer(b$side), person_ids = ids, sikker = sikker, objekt = objekt,
         maa_publiceres = !skjul && publicerbar, portraet = portraet,
         begrundelse = o$begrundelse, titel = b$titel %||% "")
  })
  data.frame(
    noegle = vapply(raekker, `[[`, character(1), "noegle"),
    side = vapply(raekker, `[[`, integer(1), "side"),
    person_ids = I(lapply(raekker, `[[`, "person_ids")),
    sikker = vapply(raekker, `[[`, logical(1), "sikker"),
    maa_publiceres = vapply(raekker, `[[`, logical(1), "maa_publiceres"),
    portraet = I(lapply(raekker, `[[`, "portraet")),
    objekt = I(lapply(raekker, function(r) r$objekt)),
    begrundelse = vapply(raekker, `[[`, character(1), "begrundelse"),
    titel = vapply(raekker, `[[`, character(1), "titel"),
    stringsAsFactors = FALSE
  )
}

# Runde 1 (manifest.json) beholder filnavnene; et andet manifest (fx manifest-runde2.json) får dets endelse på plan,
# gennemgang og rapport, så en ny runde aldrig overskriver en tidligere rundes godkendte svar.
ud_sti <- function(mappe, manifest, navn) {
  stamme <- sub("\\.json$", "", basename(manifest))
  endelse <- sub("^manifest", "", stamme)
  if (!nzchar(endelse)) return(file.path(mappe, navn))
  file.path(mappe, sub("(\\.[^.]+)$", paste0(endelse, "\\1"), navn))
}

gennemgang_sti <- function(mappe, manifest = file.path(mappe, "manifest.json")) {
  sti <- ud_sti(mappe, manifest, "gennemgang.txt")
  if (file.exists(sti)) sub("\\.txt$", ".ny.txt", sti) else sti
}

skriv_gennemgang <- function(plan, sti, manifest_sha = NULL) {
  usikre <- plan[!plan$sikker, , drop = FALSE]
  hoved <- c(
    "# Gennemgang af usikre billedkoblinger (DAA 2018-20). Skriv dit svar efter »svar:« på hver linje:",
    "#   OK            forslaget er rigtigt",
    "#   ret 12, 34    billedet viser person-id 12 og 34 (erstatter forslaget)",
    "#   skjul         importér billedet skjult (opfølgning senere)",
    "# Linjer uden svar importeres skjult.",
    if (!is.null(manifest_sha)) sprintf("# manifest-sha256: %s", manifest_sha)
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
  alle_linjer <- readLines(sti, encoding = "UTF-8", warn = FALSE)
  sha_linje <- grep("^# manifest-sha256: ", alle_linjer, value = TRUE)
  linjer <- alle_linjer[nzchar(trimws(alle_linjer)) & !startsWith(alle_linjer, "#")]
  noegler <- character()
  svar <- character()
  ids <- list()
  forslag <- list()
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
    f <- regmatches(linje, regexec("forslag: ([0-9?, ]*)", linje))[[1]]
    f <- if (length(f) == 2L) trimws(strsplit(f[[2]], ",")[[1]]) else character()
    noegler <- c(noegler, noegle); svar <- c(svar, s); ids <- c(ids, list(p)); forslag <- c(forslag, list(f[nzchar(f)]))
  }
  ud <- data.frame(noegle = noegler, svar = svar, stringsAsFactors = FALSE)
  ud$person_ids <- I(ids)
  ud$forslag <- I(forslag)
  attr(ud, "manifest_sha") <- if (length(sha_linje)) sub("^# manifest-sha256: ", "", sha_linje[[1]]) else NA_character_
  ud
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------------------------------------------
# Skrivning (Task 3): DB + Storage bag injicerede ops, så rækkefølgen kan testes uden prod.
# ---------------------------------------------------------------------------------------------------------------

BILLEDER_REDAKTOER_UUID <- "ba4ce28d-42a0-48af-a47c-773c26934236" # samme som apply_d2_spouses_1939_v50.R
BILLEDER_VARIANTER <- c("medium", "thumb")

billede_sti <- function(sha, tier) sprintf("redaktor/%s/%s-%s.jpg", substr(sha, 1L, 2L), sha, tier)

byg_rpc_sql <- function(navn, args) {
  dele <- if (length(args)) paste0(names(args), " => $", seq_along(args)) else character()
  sprintf("SELECT public.%s(%s)", navn, paste(dele, collapse = ", "))
}

.kreditlinje <- function(side) sprintf("Gengivet fra Danmarks Adels Aarbog 2018-20, s. %d", as.integer(side))

anvend_billede <- function(raekke, mappe, ops) {
  filnavn <- paste0(raekke$noegle, ".jpg")
  eks <- ops$find_media(filnavn)
  if (!is.null(eks) && identical(eks$upload_status, "klar")) return("sprunget_over")

  sha <- raekke$sha256
  # Bytes først (idempotent på sha-stier, som i web/src/data/redaktionWrite.ts).
  for (tier in c("large", BILLEDER_VARIANTER)) {
    ops$upload(billede_sti(sha, tier), file.path(mappe, raekke$filer[[tier]]))
  }
  ids <- raekke$person_ids[!is.na(raekke$person_ids)]
  dim_af <- function(tier, i) as.integer(raekke$dims[[tier]][[i]])

  ops$transaktion(function() {
    if (!identical(ops$aktoer(BILLEDER_REDAKTOER_UUID), "redaktion")) {
      stop("BILLEDER_ACTOR_NOT_REDAKTION", call. = FALSE)
    }
    if (is.null(eks)) {
      for (pid in names(raekke$portraet)) {
        h <- raekke$portraet[[pid]]
        if (identical(h$handling, "laas")) {
          laas_id <- if (!is.null(h$person_id) && !is.na(h$person_id)) h$person_id else pid
          ops$rpc("red_saet_portraet", list(p_person_id = laas_id, p_media_id = h$media_id))
        }
      }
      args <- list(
        p_slags = raekke$slags, p_titel = raekke$titel, p_storage_path = billede_sti(sha, "large"),
        p_mime = "image/jpeg", p_kunstner = raekke$kunstner, p_datering = raekke$datering,
        p_afbildet_person_id = if (length(ids)) ids[[1]] else NULL,
        p_objekt_type = if (!is.null(raekke$objekt)) raekke$objekt$type else NULL,
        p_objekt_id = if (!is.null(raekke$objekt)) as.character(raekke$objekt$id) else NULL,
        p_byte_size = as.integer(raekke$bytes$large), p_bredde = dim_af("large", 1L), p_hoejde = dim_af("large", 2L),
        p_sha256 = sha, p_original_filnavn = filnavn,
        p_rettigheder_status = "ukendt", p_maa_publiceres = isTRUE(raekke$maa_publiceres)
      )
      media_id <- as.character(ops$rpc("red_upload_media", Filter(Negate(is.null), args)))
      for (pid in ids[-1]) {
        ops$rpc("red_relation", list(p_subjekt_type = "person", p_subjekt_id = pid, p_objekt_type = "media",
                                     p_objekt_id = media_id, p_rolle = "afbildet"))
      }
    } else {
      media_id <- as.character(eks$id)
    }
    for (tier in BILLEDER_VARIANTER) {
      if (!is.null(eks) && isTRUE(ops$har_variant(media_id, tier))) next
      ops$rpc("red_registrer_media_variant", list(
        p_media_id = media_id, p_tier = tier, p_storage_path = billede_sti(sha, tier), p_mime = "image/jpeg",
        p_byte_size = as.integer(raekke$bytes[[tier]]), p_bredde = dim_af(tier, 1L), p_hoejde = dim_af(tier, 2L)))
    }
    ops$rpc("red_bekraeft_media_upload", list(p_media_id = media_id))
    ops$rpc("red_upsert_fakta", list(
      p_subjekt_type = "media", p_subjekt_id = media_id, p_faktatype = "kreditlinje",
      p_vaerdi = .kreditlinje(raekke$side), p_kilde_fritekst = sprintf("DAA 2018-20, s. %d", as.integer(raekke$side))))
  })
  if (is.null(eks)) "importeret" else "genoptaget"
}

# ---------------------------------------------------------------------------------------------------------------
# Rigtige ops og kørsel (kræver ~/.Renviron; køres i projektejerens shell)
# ---------------------------------------------------------------------------------------------------------------

source_janitor_helpers <- function() {
  e <- new.env()
  sys.source(file.path("R", "media-janitor.R"), envir = e)
  e
}

default_billede_ops <- function(con, janitor) {
  storage <- janitor$storage_api_context()
  list(
    find_media = function(filnavn) {
      r <- DBI::dbGetQuery(con, "SELECT id::text AS id, upload_status FROM media WHERE original_filnavn = $1
                                 ORDER BY id LIMIT 1", params = list(filnavn))
      if (nrow(r) == 0L) NULL else list(id = r$id[[1]], upload_status = r$upload_status[[1]])
    },
    upload = function(sti, fil) {
      httr2::request(paste0(storage$base_url, "/storage/v1/object/media/", janitor$encode_storage_path(sti))) |>
        httr2::req_method("POST") |>
        httr2::req_headers(apikey = storage$key, Authorization = paste("Bearer", storage$key),
                           `x-upsert` = "true", `content-type` = "image/jpeg") |>
        httr2::req_body_file(fil, type = "image/jpeg") |>
        httr2::req_perform()
      invisible(TRUE)
    },
    transaktion = function(fn) DBI::dbWithTransaction(con, fn()),
    aktoer = function(uuid) {
      # dbGetQuery, ikke dbExecute: set_config ER en SELECT.
      DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub', $1, true)", params = list(uuid))
      r <- DBI::dbGetQuery(con, "SELECT rolle FROM profiles WHERE id = $1::uuid", params = list(uuid))
      if (nrow(r) == 1L) r$rolle[[1]] else NA_character_
    },
    rpc = function(navn, args) {
      r <- DBI::dbGetQuery(con, byg_rpc_sql(navn, args), params = unname(lapply(args, function(x) x)))
      if (nrow(r) && ncol(r)) r[[1]][[1]] else NULL
    },
    har_variant = function(media_id, tier) {
      DBI::dbGetQuery(con, "SELECT EXISTS (SELECT 1 FROM media_variant WHERE media_id = $1::bigint AND tier = $2) AS f",
                      params = list(media_id, tier))$f[[1]]
    }
  )
}

# ---------------------------------------------------------------------------------------------------------------
# Prøve af RPC-bindingen mod en rigtig base uden at skrive (final review, vigtigt fund 4): de præcise kald for ét
# billede afspilles hver for sig i en READ ONLY-transaktion. Binder parametrene, når kaldet enten rammer read-only-
# spærren (25006) eller funktionens egen RAISE (P0001); en typefejl (fx 42883/22P02) betyder forkert binding.
# ---------------------------------------------------------------------------------------------------------------

optag_kald <- function(raekke) {
  kald <- list()
  ops <- list(
    find_media = function(filnavn) NULL,
    upload = function(sti, fil) invisible(TRUE),
    transaktion = function(fn) fn(),
    aktoer = function(uuid) "redaktion",
    rpc = function(navn, args) {
      kald[[length(kald) + 1L]] <<- list(navn = navn, args = args)
      if (navn == "red_upload_media") "0" else NULL
    },
    har_variant = function(media_id, tier) FALSE
  )
  anvend_billede(raekke, ".", ops)
  kald
}

sqlstate_fra_besked <- function(m) {
  # useBytes: beskedens CONTEXT kan bære æ/ø i en kodning, grepl ellers ikke kan læse (gav NA ved første prøve).
  if (grepl("read-only transaction", m, fixed = TRUE, useBytes = TRUE)) return("25006")
  if (grepl("does not exist", m, fixed = TRUE, useBytes = TRUE)) return("42883")
  NA_character_
}

binding_ok <- function(sqlstate) isTRUE(sqlstate %in% c("25006", "P0001"))

proev_binding <- function(con, raekke, sqlstate_af) {
  resultater <- vapply(optag_kald(raekke), function(k) {
    DBI::dbExecute(con, "BEGIN READ ONLY")
    on.exit(DBI::dbExecute(con, "ROLLBACK"), add = TRUE)
    DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub', $1, true)", params = list(BILLEDER_REDAKTOER_UUID))
    fejl <- tryCatch({
      DBI::dbGetQuery(con, byg_rpc_sql(k$navn, k$args), params = unname(k$args))
      "intet (skrev intet? read-only burde stoppe)"
    }, error = function(e) {
      st <- sqlstate_af(e)
      sprintf("%s %s", if (binding_ok(st)) "OK" else "FEJL", paste0(st, ": ", substr(conditionMessage(e), 1, 120)))
    })
    sprintf("%-30s %s", k$navn, fejl)
  }, character(1))
  message(paste(resultater, collapse = "\n"))
  invisible(all(startsWith(sub("^\\S+\\s+", "", resultater), "OK")))
}

hent_opslag <- function(con, person_ids) {
  ext <- DBI::dbGetQuery(con, "SELECT linje, nr, person_id::text AS person_id FROM person_external_id
                               WHERE source_id = 1")
  aegtefaeller <- DBI::dbGetQuery(con, "
    SELECT a.person_id::text AS anker_person_id, b.person_id::text AS person_id, p.visning_navn,
           substring(p.visning_foedt FROM '\\d{4}')::int AS foedt_aar,
           substring(p.visning_doed FROM '\\d{4}')::int AS doed_aar
      FROM family_member a
      JOIN family_member b ON b.family_id = a.family_id AND b.rolle = 'partner' AND b.person_id <> a.person_id
      JOIN person p ON p.id = b.person_id
     WHERE a.rolle = 'partner'
     ORDER BY a.person_id, b.person_id")
  medier <- if (length(person_ids)) DBI::dbGetQuery(con, "
    WITH valgt AS (SELECT unnest($1::bigint[]) AS person_id),
    gruppe AS (
      SELECT v.person_id, v.person_id AS medlem FROM valgt v
      UNION SELECT v.person_id, CASE WHEN r.subjekt_id = v.person_id THEN r.objekt_id ELSE r.subjekt_id END
        FROM valgt v JOIN relation r ON r.rolle = 'samme_som' AND r.subjekt_type = 'person' AND r.objekt_type = 'person'
                                    AND v.person_id IN (r.subjekt_id, r.objekt_id))
    SELECT g.person_id::text AS person_id, m.id::text AS media_id, m.slags,
           coalesce((r.kvalifikator->>'primaer')::boolean, false) AS primaer,
           g.medlem::text AS medlem, m.upload_status
      FROM gruppe g
      JOIN relation r ON r.subjekt_type = 'person' AND r.subjekt_id = g.medlem
                     AND r.objekt_type = 'media' AND r.rolle = 'afbildet'
      JOIN media m ON m.id = r.objekt_id
     ORDER BY g.person_id, r.id", params = list(paste0("{", paste(person_ids, collapse = ","), "}")))
  else data.frame(person_id = character(), media_id = character(), slags = character(), primaer = logical(),
                  medlem = character(), upload_status = character())
  list(ext = ext, aegtefaeller = aegtefaeller, medier = medier)
}

skriv_plan_csv <- function(plan, sti) {
  flad <- data.frame(
    noegle = plan$noegle, side = plan$side,
    person_ids = vapply(plan$person_ids, function(x) paste(ifelse(is.na(x), "?", x), collapse = ";"), character(1)),
    sikker = plan$sikker, maa_publiceres = plan$maa_publiceres,
    portraet = vapply(plan$portraet, function(p) paste(vapply(names(p), function(n)
      paste0(n, ":", p[[n]]$handling, if (identical(p[[n]]$handling, "laas")) paste0("=", p[[n]]$media_id) else ""),
      character(1)), collapse = ";"), character(1)),
    begrundelse = plan$begrundelse, titel = plan$titel, stringsAsFactors = FALSE)
  utils::write.csv(flad, sti, row.names = FALSE, fileEncoding = "UTF-8")
}

run_billeder_2018_20 <- function(args = commandArgs(trailingOnly = TRUE)) {
  opt <- parse_billede_args(args)
  mappe <- dirname(opt$manifest)
  manifest <- jsonlite::fromJSON(opt$manifest, simplifyVector = FALSE)
  manifest_sha <- digest::digest(file = opt$manifest, algo = "sha256")
  svar <- if (is.null(opt$svar)) NULL else laes_svar(opt$svar)
  if (!is.null(svar)) {
    message(sprintf("Svarfil sha256: %s", digest::digest(file = opt$svar, algo = "sha256")))
    if (!identical(attr(svar, "manifest_sha"), manifest_sha)) {
      stop("SVAR_MANIFEST_AENDRET: svarfilen hører til et andet manifest — kør planen igen og gennemgå på ny.", call. = FALSE)
    }
  }
  janitor <- source_janitor_helpers()
  con <- janitor$connect_media_janitor_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  foreloebig <- hent_opslag(con, character())
  udkast <- byg_plan(manifest, foreloebig$ext, foreloebig$aegtefaeller, foreloebig$medier, svar)
  alle_ids <- unique(stats::na.omit(unlist(udkast$person_ids)))
  opslag <- hent_opslag(con, alle_ids)
  plan <- byg_plan(manifest, opslag$ext, opslag$aegtefaeller, opslag$medier, svar)

  skriv_plan_csv(plan, ud_sti(mappe, opt$manifest, "plan.csv"))
  if (is.null(opt$svar)) {
    sti <- gennemgang_sti(mappe, opt$manifest)
    skriv_gennemgang(plan, sti, manifest_sha)
    message(sprintf("Gennemgang: %s", sti))
  }
  if (opt$proev_binding) {
    # Prøv et objekt-billede, hvis manifestet har et (runde 3: p_objekt_type/p_objekt_id), ellers et med to personer.
    objekt_i <- which(!vapply(plan$objekt, is.null, logical(1)))
    i <- if (length(objekt_i)) objekt_i[[1]] else
      which(lengths(plan$person_ids) >= 2L & !vapply(plan$person_ids, anyNA, logical(1)))[[1]]
    b <- stats::setNames(manifest$billeder, vapply(manifest$billeder, `[[`, character(1), "noegle"))[[plan$noegle[[i]]]]
    raekke <- c(b[c("noegle", "side", "sha256", "titel", "kunstner", "datering", "slags", "filer", "dims", "bytes")],
                list(person_ids = plan$person_ids[[i]], maa_publiceres = FALSE, objekt = plan$objekt[[i]],
                     portraet = if (!length(plan$person_ids[[i]])) list() else
                       stats::setNames(list(list(handling = "laas", media_id = "0",
                                                 person_id = plan$person_ids[[i]][[1]])), plan$person_ids[[i]][[1]])))
    sqlstate_af <- function(e) {
      st <- janitor$db_error_sqlstate(e)
      if (!is.na(st)) return(st)
      sqlstate_fra_besked(conditionMessage(e))
    }
    ok <- proev_binding(con, raekke, sqlstate_af)
    message(if (ok) "Binding: alle kald bundet korrekt (intet skrevet)." else "Binding: se FEJL-linjerne ovenfor.")
    return(invisible(ok))
  }
  laase <- sum(vapply(plan$portraet, function(p) sum(vapply(p, function(h) identical(h$handling, "laas"), logical(1))),
                      numeric(1)))
  message(sprintf("Plan: %d billeder · %d sikre · %d usikre · %d synlige · %d skjulte · %d portrætlåse",
                  nrow(plan), sum(plan$sikker), sum(!plan$sikker), sum(plan$maa_publiceres),
                  sum(!plan$maa_publiceres), laase))
  if (!opt$skriv) {
    message("Prøvekørsel: intet skrevet. Kør med --jeg-mener-det for at skrive.")
    return(invisible(plan))
  }

  ops <- default_billede_ops(con, janitor)
  efter_noegle <- stats::setNames(manifest$billeder, vapply(manifest$billeder, `[[`, character(1), "noegle"))
  resultater <- vapply(seq_len(nrow(plan)), function(i) {
    b <- efter_noegle[[plan$noegle[[i]]]]
    raekke <- c(b[c("noegle", "side", "sha256", "titel", "kunstner", "datering", "slags", "filer", "dims", "bytes")],
                list(person_ids = plan$person_ids[[i]], maa_publiceres = plan$maa_publiceres[[i]],
                     portraet = plan$portraet[[i]], objekt = plan$objekt[[i]]))
    tryCatch(anvend_billede(raekke, mappe, ops), error = function(e) paste("fejl:", conditionMessage(e)))
  }, character(1))
  rapport <- data.frame(noegle = plan$noegle, resultat = resultater, maa_publiceres = plan$maa_publiceres)
  utils::write.csv(rapport, ud_sti(mappe, opt$manifest, "rapport.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  message(paste(capture.output(print(table(sub(":.*", "", resultater)))), collapse = "\n"))
  invisible(rapport)
}

if (sys.nframe() == 0L) run_billeder_2018_20()
