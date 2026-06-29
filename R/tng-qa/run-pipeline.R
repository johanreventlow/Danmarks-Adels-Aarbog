#!/usr/bin/env Rscript
# TNG-QA pipeline-orkestrator.
# Kør fra repo-rod: Rscript R/tng-qa/run-pipeline.R
#
# BEMÆRK: Trin 3-4 (byg `scored` fra ours + tng_people) er et kommentar-
# skelet der kalibreres empirisk mod et håndlabelt facit-sæt inden
# prod-kørsel. Se docs/tng-qa-koersel.md § "Trin 3-4: blokering + score".
#
# Forudsætninger:
#   - jr_tng_reventlow.sql i repo-rod (git-ignoreret)
#   - SUPABASE_HOST / SUPABASE_USER / SUPABASE_PASSWORD sat i ~/.Renviron
#   - Pakker: DBI, duckdb, RPostgres, stringi, stringdist, testthat

suppressPackageStartupMessages({ library(DBI) })

root <- normalizePath(".")
for (f in list.files(file.path(root, "R", "tng-qa"), pattern = "^[0-9].*\\.R$",
                     full.names = TRUE)) source(f)

dump   <- "jr_tng_reventlow.sql"
db     <- "data/tng.duckdb"
cw_csv <- "data/tng-crosswalk.csv"
rq_csv <- "data/tng-review-queue.csv"
cfg    <- default_cfg()

# ---- Trin 1: TNG -> DuckDB ------------------------------------------------
message("== Trin 1: TNG -> DuckDB ==")
build_tng_duckdb(dump, db)
tcon <- dbConnect(duckdb::duckdb(), db); on.exit(dbDisconnect(tcon, shutdown = TRUE), add = TRUE)
tng_people   <- dbGetQuery(tcon, 'SELECT * FROM tng_people')
tng_families <- dbGetQuery(tcon, 'SELECT * FROM tng_families')
tng_children <- dbGetQuery(tcon, 'SELECT * FROM tng_children')

# ---- Trin 2: Supabase (read-only) -----------------------------------------
message("== Trin 2: Supabase (read-only) ==")
scon <- connect_readonly(); assert_readonly(scon); on.exit(dbDisconnect(scon), add = TRUE)
ours <- pull_ours(scon)

# ---- Trin 3-4: normalisér + match -----------------------------------------
message("== Trin 3-4: normalisér + match ==")
#
# Byg `scored` (data.frame med kolonner person_id, tng_id, name_sim,
# birth_overlap, death_overlap, sex_eq, unique_block) ved at:
#
#   1. Normalisér vores folk:
#      our_norm <- lapply(seq_len(nrow(ours$person)), function(i) {
#        p <- ours$person[i, ]
#        nm <- normalize_name(p$visning_navn, last = "", married_in = FALSE)
#        birth <- ours$dates[ours$dates$person_id == p$id &
#                            ours$dates$faktatype == "fødsel", ]
#        death <- ours$dates[ours$dates$person_id == p$id &
#                            ours$dates$faktatype == "død",   ]
#        list(person_id  = p$id,
#             name_key   = nm$key,
#             birth_int  = if (nrow(birth)) c(birth$date_min[1], birth$date_max[1])
#                          else c(NA_integer_, NA_integer_),
#             death_int  = if (nrow(death)) c(death$date_min[1], death$date_max[1])
#                          else c(NA_integer_, NA_integer_),
#             koen       = p$koen)
#      })
#
#   2. Normalisér TNG-folk analogt (normalize_name / tng_date_to_interval).
#
#   3. Bloker (fx felles efternavn-initial + ±cfg$year_window fødselsdekade).
#      unique_block = TRUE hvis TNG-kandidaten er ENESTE kandidat i blokken.
#
#   4. Score hvert kandidat-par med score_pair() og saml i `scored`.
#      scored = data.frame(person_id, tng_id,
#                          name_sim, birth_overlap, death_overlap, sex_eq,
#                          unique_block)
#
# Tærsklerne (cfg$auto_cutoff = 0.90, cfg$review_cutoff = 0.70) er IKKE
# empirisk kalibreret endnu — justér mod facit-sæt inden prod.
# Se docs/tng-qa-koersel.md § "Trin 3-4" for kalibreringsprocedure.
#
# crosswalk <- assign_tiers(scored, cfg)

# Guard: trin 3-4 glue must be completed before trin 5 can run
if (!exists("crosswalk")) stop(
  "Trin 3-4 (scored -> crosswalk) er en kalibrerings-skeleton der endnu ikke er ",
  "færdiggjort. Byg `scored` fra ours+tng_people og afkommentér ",
  "`crosswalk <- assign_tiers(scored, cfg)` før trin 5-6 kan køre. ",
  "Se docs/tng-qa-koersel.md (kalibrering mod facit-sæt)."
)

# ---- Trin 5: review-merge (hvis afgørelser findes) ------------------------
message("== Trin 5: review-merge (hvis afgørelser findes) ==")
if (file.exists(rq_csv)) {
  dec <- read.csv(rq_csv, stringsAsFactors = FALSE)
  crosswalk <- merge_review_decisions(crosswalk, dec)
}
write.csv(crosswalk, cw_csv, row.names = FALSE)
write.csv(crosswalk[crosswalk$tier == "review", ], rq_csv, row.names = FALSE)

# ---- Trin 6: sammenlign + rapport -----------------------------------------
message("== Trin 6: sammenlign + rapport ==")
xwalk <- accepted_crosswalk(crosswalk)
#
# Byg sammenlignings-input og kør de tre dimensioner:
#
#   our_pairs <- our_spouse_pairs(ours$family, ours$family_member)
#   our_pc    <- <aflede child_id/parent_id/rolle fra ours$family_member>
#   our_attr  <- <join ours$person + ours$dates til
#                  data.frame(person_id, birth_min, birth_max,
#                             death_min, death_max, koen)>
#
#   disc <- rbind(
#     compare_marriages(our_pairs, tng_families, xwalk),
#     compare_parent_child(our_pc, tng_children, xwalk),
#     compare_dates_sex(our_attr, tng_people, xwalk)
#   )
#   disc$person_id <- as.integer(disc$person_id)    # entydigt for PII-gate
#
# GDPR-note: PII-gate fejler lukket hvis `detalje`-strengen indeholder
# raw person_id på en levende person. Kortlæg related person_ids til
# DAA linje/nr-labels (ours$external_id) FØR render_report(), så
# rapporten er committable. Se docs/tng-qa-koersel.md § "GDPR PII-gate".
#
#   living <- ours$person$id[ours$person$levende | ours$person$privat]
#   md <- render_report(disc, ours$external_id, living, format(Sys.Date()))
#   writeLines(md, sprintf("docs/reviews/tng-qa-rapport-%s.md",
#                          format(Sys.Date())))

message("Færdig. Crosswalk: ", cw_csv)
