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
tcon <- dbConnect(duckdb::duckdb(), db)
tng_people   <- dbGetQuery(tcon, 'SELECT * FROM tng_people')
tng_families <- dbGetQuery(tcon, 'SELECT * FROM tng_families')
tng_children <- dbGetQuery(tcon, 'SELECT * FROM tng_children')
# Luk straks efter sidste brug. Et top-level on.exit() under source() bindes
# per-udtryk og ville fyre shutdown FØR næste query -> "Invalid connection".
dbDisconnect(tcon, shutdown = TRUE)

# ---- Trin 2: Supabase (read-only) -----------------------------------------
message("== Trin 2: Supabase (read-only) ==")
scon <- connect_readonly(); assert_readonly(scon)
ours <- pull_ours(scon)
dbDisconnect(scon)  # luk straks efter sidste brug (samme on.exit-fælde som tcon)

# ---- Trin 3-4: normalisér + match -----------------------------------------
# Byggeklodser: our_match_frame / tng_match_frame / build_scored (04-match.R).
# VIGTIGT: cfg-tærsklerne (auto_cutoff=0.90, review_cutoff=0.70) er IKKE
# kalibreret — intet facit-sæt findes endnu. Tier-tællingerne nedenfor er
# DIAGNOSTISKE, ikke et endeligt resultat. Den uniforme "Reventlow"-efternavn
# hæver name_sim's bund (review oversvømmes nær cutoff), og dato-løse par får
# gratis vægt (overlap NA→TRUE). Se docs/tng-qa-koersel.md § "Trin 3-4".
message("== Trin 3-4: normalisér + match ==")
our_norm  <- our_match_frame(ours$person, ours$dates)
tng_norm  <- tng_match_frame(tng_people)
scored    <- build_scored(our_norm, tng_norm, cfg)
crosswalk <- assign_tiers(scored, cfg)

n_unmatched <- nrow(our_norm) - length(unique(scored$person_id))
tier_tab    <- table(factor(crosswalk$tier, levels = c("auto", "review", "none")))
message(sprintf("  %d personer x %d TNG -> %d kandidat-par (%d uden kandidat)",
                nrow(our_norm), nrow(tng_norm), nrow(scored), n_unmatched))
message(sprintf("  tiers (DIAGNOSTISK, ukalibreret): auto=%d review=%d none=%d",
                tier_tab[["auto"]], tier_tab[["review"]], tier_tab[["none"]]))

# ---- Trin 5: review-merge (hvis afgørelser findes) ------------------------
message("== Trin 5: review-merge (hvis afgørelser findes) ==")
if (file.exists(rq_csv)) {
  dec <- read.csv(rq_csv, stringsAsFactors = FALSE)
  crosswalk <- merge_review_decisions(crosswalk, dec)
}
write.csv(crosswalk, cw_csv, row.names = FALSE)
# Review-kø MED udfyldelige beslutnings-kolonner: brugeren sætter `afgoerelse`
# (bekræft/afvis/ny-id) + evt. `ny_tng_id`; næste run fletter dem ind (Trin 5).
rq <- crosswalk[crosswalk$tier == "review", ]
rq$afgoerelse <- ""
rq$ny_tng_id  <- ""
write.csv(rq, rq_csv, row.names = FALSE)

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
