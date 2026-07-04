#!/usr/bin/env Rscript
# =====================================================================
#  run-geo-enrich.R — fyld place.lat/lon fra TNG's tng_places.
#  Kør fra repo-rod:  Rscript R/geo-enrich/run-geo-enrich.R            (dry-run)
#                     Rscript R/geo-enrich/run-geo-enrich.R --apply    (skriv koordinater)
#
#  Forudsætninger (samme som R/tng-qa):
#    - jr_tng_reventlow.sql i repo-rod (git-ignoreret MySQL-dump)
#    - SUPABASE_HOST / SUPABASE_USER / SUPABASE_PASSWORD i ~/.Renviron
#      (--apply kræver en SKRIVE-rolle; læs-only til at bygge crosswalken)
#    - Pakker: DBI, duckdb, RPostgres, stringi, stringdist
#
#  Flow (spejler tng-qa-crosswalken):
#    1. tng_places -> DuckDB (genbruger 01-extract-tng.R)
#    2. place (id,navn,lat,lon) <- Supabase read-only (genbruger 02-pull-ours.R)
#    3. match -> data/geo-crosswalk.csv  (auto=TRUE, review=tom, none=FALSE i `anvend`)
#    4. --apply: UPDATE place SET lat,lon WHERE id=? AND lat IS NULL  (idempotent, i txn)
#       for rækker hvor `anvend` er sandt. Review-rækker skrives KUN efter du har
#       redigeret CSV'en (sæt anvend=TRUE) og kørt igen med --apply.
# =====================================================================
suppressPackageStartupMessages({ library(DBI); library(duckdb); library(RPostgres) })

root <- normalizePath(".")
source(file.path(root, "R", "tng-qa", "01-extract-tng.R")) # build/load_tng_table, tng_create_columns
source(file.path(root, "R", "tng-qa", "02-pull-ours.R"))   # connect_readonly, assert_readonly
source(file.path(root, "R", "geo-enrich", "geo_helpers.R"))

args     <- commandArgs(trailingOnly = TRUE)
do_apply <- "--apply" %in% args
dump     <- "jr_tng_reventlow.sql"
geo_db   <- "data/geo-tng.duckdb"
cw_csv   <- "data/geo-crosswalk.csv"
cfg      <- default_geo_cfg()
dir.create("data", showWarnings = FALSE)

# ---- 1) tng_places -> DuckDB ----------------------------------------------
if (!file.exists(dump)) stop(sprintf("TNG-dump mangler: %s (læg den i repo-rod; git-ignoreret).", dump))
message("== 1: tng_places -> DuckDB ==")
if (file.exists(geo_db)) unlink(geo_db)
tcon <- dbConnect(duckdb::duckdb(), geo_db)
n <- load_tng_table(tcon, dump, "tng_places") # generisk: parser CREATE/INSERT for tabellen
message(sprintf("  tng_places: %d rækker", n))
tng_places <- dbGetQuery(tcon, 'SELECT * FROM "tng_places"')
dbDisconnect(tcon, shutdown = TRUE) # luk straks (jf. run-pipeline.R on.exit-fælden)

# Kolonnenavne varierer let mellem TNG-versioner → vælg robust.
col_place <- pick_col(tng_places, c("place", "placename", "Place"), "stednavn")
col_lat   <- pick_col(tng_places, c("latitude", "lat", "Latitude"), "breddegrad")
col_lon   <- pick_col(tng_places, c("longitude", "lon", "lng", "Longitude"), "længdegrad")
tng_idx <- build_tng_index(tng_places[[col_place]], tng_places[[col_lat]], tng_places[[col_lon]])
message(sprintf("  %d TNG-punkter med gyldige koordinater", nrow(tng_idx)))

# ---- 2) place <- Supabase (read-only) -------------------------------------
message("== 2: place <- Supabase (read-only) ==")
scon <- connect_readonly(); assert_readonly(scon)
places <- dbGetQuery(scon, "SELECT id, navn, lat, lon FROM place")
dbDisconnect(scon)
message(sprintf("  %d place-rækker (%d mangler koordinater)",
                nrow(places), sum(is.na(places$lat) | is.na(places$lon))))

# ---- 3) match -> crosswalk ------------------------------------------------
message("== 3: match + crosswalk ==")
# Match kun de steder der endnu MANGLER koordinater (idempotent; rør ikke berigede/kuraterede).
todo <- places[is.na(places$lat) | is.na(places$lon), c("id", "navn")]
matched <- match_places(todo, tng_idx, cfg)
crosswalk <- build_geo_crosswalk(matched)
write.csv(crosswalk, cw_csv, row.names = FALSE, fileEncoding = "UTF-8")
tier_tab <- table(factor(crosswalk$tier, levels = c("auto", "review", "none")))
message(sprintf("  tiers: auto=%d review=%d none=%d -> %s",
                tier_tab[["auto"]], tier_tab[["review"]], tier_tab[["none"]], cw_csv))
message("  (review-rækker: åbn CSV'en, sæt `anvend`=TRUE på dem du godkender, kør igen med --apply)")

# ---- 4) apply (kun med --apply) -------------------------------------------
apply_rows <- rows_to_apply(crosswalk)
if (!do_apply) {
  message(sprintf("== DRY-RUN == %d rækker ville blive skrevet (kør med --apply). Ingen ændringer.",
                  nrow(apply_rows)))
  print(utils::head(apply_rows, 20))
  quit(save = "no")
}

if (!nrow(apply_rows)) { message("Ingen rækker at skrive (anvend-kolonnen er tom/FALSE)."); quit(save = "no") }
message(sprintf("== 4: APPLY == skriver %d koordinat-sæt til place ==", nrow(apply_rows)))
wcon <- dbConnect(RPostgres::Postgres(), host = Sys.getenv("SUPABASE_HOST"),
                  port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                  dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                  user = Sys.getenv("SUPABASE_USER"), password = Sys.getenv("SUPABASE_PASSWORD"),
                  sslmode = "require", bigint = "integer")
n_upd <- 0L
dbBegin(wcon)
tryCatch({
  for (i in seq_len(nrow(apply_rows))) {
    # AND lat IS NULL: idempotent + overskriver aldrig et manuelt kurateret punkt.
    n_upd <- n_upd + dbExecute(wcon,
      "UPDATE place SET lat=$1, lon=$2 WHERE id=$3 AND (lat IS NULL OR lon IS NULL)",
      params = list(apply_rows$lat[i], apply_rows$lon[i], apply_rows$place_id[i]))
  }
  dbCommit(wcon); message(sprintf("  OK: %d place-rækker opdateret", n_upd))
}, error = function(e) { dbRollback(wcon); dbDisconnect(wcon); stop("apply fejlede, rullet tilbage: ", conditionMessage(e)) })

cat("\n=== verifikation ===\n")
print(dbGetQuery(wcon, "SELECT count(*) AS med_koordinat FROM place WHERE lat IS NOT NULL AND lon IS NOT NULL"))
dbDisconnect(wcon)
