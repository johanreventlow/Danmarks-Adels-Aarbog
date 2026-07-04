#!/usr/bin/env Rscript
# =====================================================================
#  03-geocode.R — VALGFRIT fallback: geokod de steder TNG ikke dækkede
#  (tier=="none" i data/geo-crosswalk.csv) via OpenStreetMap Nominatim.
#  Kør EFTER run-geo-enrich.R, fra repo-rod:
#      Rscript R/geo-enrich/03-geocode.R
#
#  Skriver KUN review-kandidater til data/geo-geocode-candidates.csv — aldrig
#  auto-anvendt (geokodning er lavere-tillid end tng_places). Gennemgå og flet
#  godkendte rækker ind i geo-crosswalk.csv (sæt anvend=TRUE) før --apply.
#
#  NYE afhængigheder (ikke ellers brugt i R-koden): httr2, jsonlite.
#  Nominatim-brugsvilkår: max 1 request/sekund + reel User-Agent. Overhold dem —
#  scriptet rate-limiter og cacher, så gentagne kørsler ikke rammer API'et igen.
#  Højere DK-præcision kan fås via DAWA/Dataforsyningen (dawa.aws.dk/steder) —
#  bevidst ikke wiret her (kræver egen endpoint-tuning); Nominatim dækker DK+DE.
# =====================================================================
suppressPackageStartupMessages({ library(httr2); library(jsonlite) })
source(file.path(normalizePath("."), "R", "geo-enrich", "geo_helpers.R"))

cw_csv    <- "data/geo-crosswalk.csv"
cand_csv  <- "data/geo-geocode-candidates.csv"
cache_csv <- "data/geo-geocode-cache.csv"
UA <- "danmarks-adels-aarbog geo-enrich (kontakt: johan@reventlow.dk)"
BIAS_CC <- "dk,de" # slægten pendlede mellem Danmark og Holsten

if (!file.exists(cw_csv)) stop("Kør run-geo-enrich.R først (mangler ", cw_csv, ").")
cw <- read.csv(cw_csv, stringsAsFactors = FALSE, encoding = "UTF-8")
todo <- cw[cw$tier == "none" & nzchar(trimws(cw$navn)), c("place_id", "navn"), drop = FALSE]
if (!nrow(todo)) { message("Ingen tier=none-steder at geokode."); quit(save = "no") }

# Cache: navn-nøgle -> lat/lon (så gentagne kørsler ikke geokoder igen).
cache <- if (file.exists(cache_csv)) read.csv(cache_csv, stringsAsFactors = FALSE) else
  data.frame(key = character(), lat = double(), lon = double(), display = character(), stringsAsFactors = FALSE)

geocode_one <- function(navn) {
  key <- normalize_place_key(navn)
  hit <- cache[cache$key == key, , drop = FALSE]
  if (nrow(hit)) return(hit[1, c("lat", "lon", "display")])
  Sys.sleep(1.1) # Nominatim: ≤1 req/s
  resp <- tryCatch(
    request("https://nominatim.openstreetmap.org/search") |>
      req_user_agent(UA) |>
      req_url_query(q = navn, format = "jsonv2", limit = 1, countrycodes = BIAS_CC) |>
      req_perform() |> resp_body_string() |> fromJSON(),
    error = function(e) { message("  geokod-fejl for '", navn, "': ", conditionMessage(e)); NULL })
  res <- if (is.null(resp) || !length(resp) || is.null(nrow(resp)) || nrow(resp) == 0)
    data.frame(lat = NA_real_, lon = NA_real_, display = NA_character_) else
    data.frame(lat = as.numeric(resp$lat[1]), lon = as.numeric(resp$lon[1]),
               display = as.character(resp$display_name[1]))
  cache[nrow(cache) + 1, ] <<- list(key, res$lat, res$lon, res$display)
  res
}

message(sprintf("== geokoder %d steder (Nominatim, ~1/s) ==", nrow(todo)))
rows <- lapply(seq_len(nrow(todo)), function(i) {
  g <- geocode_one(todo$navn[i])
  data.frame(place_id = todo$place_id[i], navn = todo$navn[i], tier = "review",
             method = "nominatim", tng_place = g$display,
             lat = parse_coord(g$lat, "lat"), lon = parse_coord(g$lon, "lon"),
             anvend = "", stringsAsFactors = FALSE)
})
cand <- do.call(rbind, rows)
write.csv(cache, cache_csv, row.names = FALSE, fileEncoding = "UTF-8")
write.csv(cand, cand_csv, row.names = FALSE, fileEncoding = "UTF-8")
message(sprintf("  %d/%d fik en kandidat -> %s (gennemgå, sæt anvend=TRUE, flet ind i %s)",
                sum(!is.na(cand$lat)), nrow(cand), cand_csv, cw_csv))
