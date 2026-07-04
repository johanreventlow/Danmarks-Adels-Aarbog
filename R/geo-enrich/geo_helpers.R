# geo_helpers.R — Rene, DB-frie hjælpere til koordinat-berigelse af place.lat/lon.
# Testbare uden DB/net (samme mønster som .claude/skills/daa-extract/scripts/load_helpers.R
# og R/tng-qa/03-normalize.R). Diakritik bevares ALTID. Ingen side-effekter.
#
# Rygraden: TNG's `tng_places` (~6.788 punkter, lat/lon, fritekst-hierarki) matches mod
# vores `place.navn` og fylder de tomme lat/lon. Deterministisk + tiered (auto/review/none),
# så resultatet kan review-gennemgås i en CSV før det skrives — som tng-qa-crosswalken.

suppressPackageStartupMessages({ library(stringi) })

.lower <- function(s) stringi::stri_trans_tolower(s, locale = "da_DK")

# Normaliseringsnøgle for et stednavn. SKAL matche get_place()'s dedup-nøgle i
# load_daa.R (tolower(trimws(navn))) så vi rammer de EKSISTERENDE place-rækker;
# plus whitespace-kollaps + trimning af trailing tegnsætning for robusthed.
normalize_place_key <- function(navn) {
  ifelse(is.na(navn), NA_character_, {
    k <- .lower(trimws(navn))
    k <- gsub("\\s+", " ", k)
    k <- gsub("[.,;:]+$", "", k) # "kbh." -> "kbh"
    trimws(k)
  })
}

# TNG's `place` er hierarkisk "Blad, Forælder, …, Land". Bladet (første komponent) er
# mest specifikt og er primær match-nøgle mod vores typisk korte navne.
tng_place_leaf <- function(place) {
  vapply(place, function(p) {
    if (is.na(p)) return(NA_character_)
    trimws(strsplit(p, ",", fixed = TRUE)[[1]][1])
  }, character(1), USE.NAMES = FALSE)
}

# ASCII-translitererer danske/tyske diakritiske tegn til deres konventionelle postale/
# tastatur-substitution (æ→ae, ø→oe, å→aa; plus ä/ö/ü/ß for det holstensk-tyske materiale).
# MySQL-dumps fra ældre systemer translittererer ofte diakritik på denne måde, og generisk
# Jaro-Winkler-similarity fanger den IKKE pålideligt for korte navne — verificeret empirisk:
# "Plön" vs "Ploen" scorer kun jw=0.78 (langt under enhver fornuftig fuzzy-tærskel), mens en
# ÆGTE stavevariant som "Kjøbenhavn" vs "København" scorer 0.97. Transliteration er derfor en
# egen deterministisk match-tier (ikke en justering af fuzzy-tærsklen). Input SKAL være
# small-caps (normalize_place_key kalder .lower() først).
fold_da_ascii <- function(s) {
  s <- gsub("æ", "ae", s, fixed = TRUE)
  s <- gsub("ø", "oe", s, fixed = TRUE)
  s <- gsub("å", "aa", s, fixed = TRUE)
  s <- gsub("ä", "ae", s, fixed = TRUE)
  s <- gsub("ö", "oe", s, fixed = TRUE)
  s <- gsub("ü", "ue", s, fixed = TRUE)
  s <- gsub("ß", "ss", s, fixed = TRUE)
  s
}

# Parse + validér én koordinat fra TNG (VARCHAR i dumpet). NA ved tom/0/ugyldig —
# TNG bruger "0"/"" for "ukendt", og en (0,0)-koordinat (Null Island) er aldrig et
# dansk/holstensk sted.
parse_coord <- function(x, kind = c("lat", "lon")) {
  kind <- match.arg(kind)
  v <- suppressWarnings(as.numeric(x))
  lim <- if (kind == "lat") 90 else 180
  ifelse(is.na(v) | v == 0 | abs(v) > lim, NA_real_, v)
}

# Vælg en kolonne fra en data.frame ud fra kandidat-navne (TNG-kolonnenavne varierer
# lidt mellem versioner). Returnér den første der findes, ellers stop med en klar fejl.
pick_col <- function(df, candidates, what) {
  hit <- candidates[candidates %in% names(df)]
  if (!length(hit)) {
    stop(sprintf("geo-enrich: fandt ingen %s-kolonne (prøvede: %s). Faktiske kolonner: %s",
                 what, paste(candidates, collapse = ", "), paste(names(df), collapse = ", ")))
  }
  hit[1]
}

default_geo_cfg <- function() list(
  # Fuzzy-tærskel (Jaro-Winkler similarity) for review-tier når intet eksakt/ascii-match findes.
  # IKKE kalibreret mod facit endnu — hold review bred, auto konservativ (som tng-qa).
  fuzzy_review_sim = 0.92,
  # Koordinater regnes som "enige" hvis de er ens afrundet til så mange decimaler (~100 m).
  coord_round = 3
)

# Byg TNG-opslag: én række pr. VALIDT (koordinat-bærende) tng_places-punkt, med
# normaliseret blad-nøgle + fuld-nøgle (+ ASCII-foldede varianter). Input er allerede
# kolonne-udtrukket.
build_tng_index <- function(tng_place, tng_lat, tng_lon) {
  lat <- parse_coord(tng_lat, "lat")
  lon <- parse_coord(tng_lon, "lon")
  ok <- !is.na(lat) & !is.na(lon) & !is.na(tng_place)
  leaf_key <- normalize_place_key(tng_place_leaf(tng_place[ok]))
  full_key <- normalize_place_key(tng_place[ok])
  data.frame(
    place = tng_place[ok],
    leaf_key = leaf_key, full_key = full_key,
    leaf_key_ascii = fold_da_ascii(leaf_key), full_key_ascii = fold_da_ascii(full_key),
    lat = lat[ok], lon = lon[ok],
    stringsAsFactors = FALSE
  )
}

# Er et sæt koordinat-par "enige" (samme punkt)? Bruges til at afgøre om flere TNG-rækker
# med samme navn peger på ét sted (auto) eller flere (tvetydigt → review).
.coords_agree <- function(lat, lon, round_dp) {
  length(unique(paste(round(lat, round_dp), round(lon, round_dp)))) == 1
}

# Match vores place-rækker mod TNG-indekset. Returnér ÉN række pr. place med bedste
# kandidat + tier (auto / review / none). Rene data.frames ind og ud.
#   places: data.frame(id, navn)
#   tng_idx: output af build_tng_index()
match_places <- function(places, tng_idx, cfg = default_geo_cfg()) {
  our_key <- normalize_place_key(places$navn)
  our_key_ascii <- fold_da_ascii(our_key)
  out <- lapply(seq_len(nrow(places)), function(i) {
    key <- our_key[i]
    key_ascii <- our_key_ascii[i]
    base <- data.frame(place_id = places$id[i], navn = places$navn[i], our_key = key,
                       tier = "none", method = NA_character_, score = NA_real_,
                       n_kandidater = 0L, tng_place = NA_character_,
                       lat = NA_real_, lon = NA_real_, stringsAsFactors = FALSE)
    if (is.na(key) || !nzchar(key)) return(base)

    # 1) Eksakt (rå nøgle): blad- eller fuld-nøgle er identisk.
    hit <- tng_idx[tng_idx$leaf_key == key | tng_idx$full_key == key, , drop = FALSE]
    method <- "eksakt"
    if (!nrow(hit)) {
      # 1b) Eksakt via ASCII-translitteration (æ/ø/å/ä/ö/ü/ß) — deterministisk, IKKE fuzzy;
      # se fold_da_ascii()-kommentaren for hvorfor dette ikke kan foldes ind i fuzzy-trinnet.
      hit <- tng_idx[tng_idx$leaf_key_ascii == key_ascii | tng_idx$full_key_ascii == key_ascii, , drop = FALSE]
      method <- "ascii-translit"
    }
    if (nrow(hit)) {
      agree <- .coords_agree(hit$lat, hit$lon, cfg$coord_round)
      base$n_kandidater <- nrow(hit)
      base$method <- method
      base$score <- 1
      base$tng_place <- hit$place[1]
      base$lat <- hit$lat[1]; base$lon <- hit$lon[1]
      base$tier <- if (agree) "auto" else "review" # samme navn, forskellige punkter → menneske afgør
      return(base)
    }

    # 2) Fuzzy: bedste Jaro-Winkler-lighed mod blad-nøglerne (rå — ascii-varianten er
    # allerede afklaret i trin 1b, så dette er ægte stavevarianter/tastefejl).
    sim <- stringdist::stringsim(key, tng_idx$leaf_key, method = "jw")
    j <- which.max(sim)
    if (length(j) && sim[j] >= cfg$fuzzy_review_sim) {
      base$n_kandidater <- sum(sim >= cfg$fuzzy_review_sim)
      base$method <- "fuzzy"
      base$score <- sim[j]
      base$tng_place <- tng_idx$place[j]
      base$lat <- tng_idx$lat[j]; base$lon <- tng_idx$lon[j]
      base$tier <- "review" # fuzzy er ALDRIG auto
    }
    base
  })
  do.call(rbind, out)
}

# Crosswalk med review-kolonne: auto → anvend=TRUE, review → tom (bruger udfylder),
# none → FALSE. Kun rækker med gyldige koordinater er kandidater.
build_geo_crosswalk <- function(matched) {
  anvend <- ifelse(matched$tier == "auto", "TRUE",
                   ifelse(matched$tier == "review", "", "FALSE"))
  cbind(matched, anvend = anvend, stringsAsFactors = FALSE)
}

# Filtrér crosswalk til de rækker der skal SKRIVES: anvend sandt + gyldige koordinater.
rows_to_apply <- function(crosswalk) {
  yes <- tolower(trimws(as.character(crosswalk$anvend))) %in% c("true", "ja", "1", "x")
  keep <- yes & !is.na(crosswalk$lat) & !is.na(crosswalk$lon)
  crosswalk[keep, c("place_id", "navn", "lat", "lon"), drop = FALSE]
}
