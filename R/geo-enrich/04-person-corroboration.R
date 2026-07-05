#!/usr/bin/env Rscript
# =====================================================================
#  04-person-corroboration.R — bekræft eksisterende sted-matches ved at
#  krydstjekke personer knyttet til stedet mod TNG's egne fritekst-stedfelter.
#  Kør EFTER run-geo-enrich.R (kræver data/geo-crosswalk.csv), fra repo-rod:
#      Rscript R/geo-enrich/04-person-corroboration.R
#
#  Princip (som R/tng-qa/04b-corroboration.R): ANNOTATION, IKKE tier-ændring.
#  Tilføjer person_checked/person_confirmed/person_detalje til
#  data/geo-crosswalk.csv — ændrer ALDRIG tier/anvend automatisk. Du vurderer
#  selv om en stærkt bekræftet review-række skal have anvend=TRUE.
#
#  Genbruger den EKSISTERENDE, kalibrerede person-crosswalk fra R/tng-qa
#  (data/tng-crosswalk.csv, kun tier=="auto") — beregner IKKE person-matching
#  forfra (undgår en ny, bredere læsning af navne/levende-status).
#
#  Forudsætninger:
#    - data/geo-crosswalk.csv (kør run-geo-enrich.R først)
#    - data/tng-crosswalk.csv (kør R/tng-qa/run-pipeline.R hvis den mangler)
#    - jr_tng_reventlow.sql i repo-rod
#    - SUPABASE_HOST/USER/PASSWORD i ~/.Renviron (read-only: SELECT fra
#      `fact` — kun person_id/faktatype/sted_id, ingen navne/levende-flag)
# =====================================================================
suppressPackageStartupMessages({ library(DBI); library(duckdb); library(RPostgres) })

root <- normalizePath(".")
source(file.path(root, "R", "tng-qa", "01-extract-tng.R")) # load_tng_table
source(file.path(root, "R", "tng-qa", "02-pull-ours.R"))   # connect_readonly, assert_readonly
source(file.path(root, "R", "geo-enrich", "geo_helpers.R"))

cw_csv    <- "data/geo-crosswalk.csv"
xwalk_csv <- "data/tng-crosswalk.csv"
dump      <- "jr_tng_reventlow.sql"
geo_db    <- "data/geo-tng.duckdb"

if (!file.exists(cw_csv)) stop("Mangler ", cw_csv, " — kør run-geo-enrich.R først.")
if (!file.exists(xwalk_csv)) stop("Mangler ", xwalk_csv, " — kør R/tng-qa/run-pipeline.R først.")
if (!file.exists(dump)) stop("TNG-dump mangler: ", dump)

crosswalk <- read.csv(cw_csv, stringsAsFactors = FALSE, encoding = "UTF-8")

# ---- 1) Person-crosswalk (genbrug, kun auto-tier — pålidelig identitet) ---
message("== 1: person-crosswalk (auto-tier, genbrugt fra tng-qa) ==")
person_crosswalk <- read.csv(xwalk_csv, stringsAsFactors = FALSE)
person_crosswalk <- person_crosswalk[person_crosswalk$tier == "auto", c("person_id", "tng_id")]
message(sprintf("  %d auto-tier person-matches", nrow(person_crosswalk)))

# ---- 2) tng_people's stedfelter -> DuckDB (fritekst, ingen placeID-FK) -----
message("== 2: tng_people -> DuckDB (birthplace/deathplace/burialplace/baptplace) ==")
tcon <- dbConnect(duckdb::duckdb(), geo_db)
load_tng_table(tcon, dump, "tng_people")
# personID (varchar, fx "I7089") — SAMME nøgle som tng-qa's crosswalk bruger som tng_id
# (04-match.R:124: tng_id = tp$personID), IKKE den interne heltals-ID.
tng_person_places <- dbGetQuery(tcon,
  'SELECT "personID" AS tng_id, birthplace, deathplace, burialplace, baptplace FROM "tng_people"')
dbDisconnect(tcon, shutdown = TRUE)
message(sprintf("  %d tng_people-rækker", nrow(tng_person_places)))

# ---- 3) Vores fact-rækker (read-only) — KUN person_id/faktatype/sted_id ---
message("== 3: fact <- Supabase (read-only; person_id, faktatype, sted_id) ==")
scon <- connect_readonly(); assert_readonly(scon)
place_facts <- dbGetQuery(scon, sprintf(
  "SELECT subjekt_id AS person_id, faktatype, sted_id AS place_id FROM fact
   WHERE subjekt_type='person' AND sted_id IS NOT NULL AND faktatype IN (%s)",
  paste(sprintf("'%s'", names(FAKTATYPE_TO_TNG_FIELD)), collapse = ",")))
dbDisconnect(scon)
message(sprintf("  %d geo-bærende person-fakta (fødsel/dåb/død/begravelse/bisættelse)", nrow(place_facts)))

# ---- 4) Corroborér + skriv (annotation, ikke tier-ændring) -----------------
message("== 4: corroborér + skriv (annotation) ==")
enriched <- corroborate_places_by_person(crosswalk, place_facts, person_crosswalk, tng_person_places)
write.csv(enriched, cw_csv, row.names = FALSE, fileEncoding = "UTF-8")

n_checked <- sum(enriched$person_checked > 0)
n_conflict <- sum(enriched$person_checked > 0 & enriched$person_confirmed < enriched$person_checked)
message(sprintf("  %d rækker fik mindst én person-corroboration (%d med mindst én afvigelse)",
                n_checked, n_conflict))
message(sprintf("  -> %s opdateret med person_checked/person_confirmed/person_detalje", cw_csv))
message("  (tier/anvend er UÆNDRET — gennemgå person_detalje i review-rækker selv)")
