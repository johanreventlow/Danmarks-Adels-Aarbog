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
# AUTO-kriteriet er BOOTSTRAP-kalibreret (2026-06-30): auto kræver score >=
# auto_cutoff OG margin >= ambiguity_margin til nr. 2 (se default_cfg + calibrate.R).
# review_cutoff er IKKE kalibreret (kræver håndlabelt facit-sæt) — review-tier'en
# er stadig bred. Auto-tier'en er spot-check-valideret men ikke uafhængigt
# præcisions-målt. Se docs/tng-qa-koersel.md § "Trin 3-4".
message("== Trin 3-4: normalisér + match ==")
our_norm  <- our_match_frame(ours$person, ours$dates)
tng_norm  <- tng_match_frame(tng_people)
scored    <- build_scored(our_norm, tng_norm, cfg)
crosswalk <- assign_tiers(scored, cfg)

n_unmatched <- nrow(our_norm) - length(unique(scored$person_id))
tier_tab    <- table(factor(crosswalk$tier, levels = c("auto", "review", "none")))
message(sprintf("  %d personer x %d TNG -> %d kandidat-par (%d uden kandidat)",
                nrow(our_norm), nrow(tng_norm), nrow(scored), n_unmatched))
message(sprintf("  tiers: auto=%d review=%d none=%d (auto bootstrap-kalibreret; review bred)",
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

# Sammenlignings-input
our_pairs <- our_spouse_pairs(ours$family, ours$family_member)
our_pc    <- derive_our_pc(ours$family_member)
our_attr  <- our_attr_frame(ours$person, ours$dates)
tngc      <- reshape_tng_children(tng_children, tng_families)

# PRIMÆR PII-kontrol: input-gating til afdøde-ikke-private på BEGGE sider, FØR
# sammenligning (se 07-report.R). Ingen levende/privat person kan så optræde i
# `disc` — heller ikke som relateret endepunkt. assert_no_living_pii er backstop.
g <- gate_inputs(accepted_crosswalk(crosswalk), our_pairs, our_pc, our_attr,
                 tng_families, tngc,
                 safe_our = safe_our_ids(ours$person),
                 safe_tng = safe_tng_ids(tng_people))

pc <- compare_parent_child(g$our_pc, g$tng_children, g$xwalk)
names(pc)[names(pc) == "child_id"] <- "person_id"
disc <- rbind(
  compare_marriages(g$our_pairs, g$tng_families, g$xwalk),
  pc,
  compare_dates_sex(g$our_attr, tng_people, g$xwalk)
)
disc$person_id <- as.integer(disc$person_id)

living  <- as.integer(ours$person$id[ours$person$levende %in% TRUE | ours$person$privat %in% TRUE])
md      <- render_report(disc, ours$external_id, living, format(Sys.Date()))
dir.create("docs/reviews", showWarnings = FALSE, recursive = TRUE)
rapport <- sprintf("docs/reviews/tng-qa-rapport-%s.md", format(Sys.Date()))
writeLines(md, rapport)
act <- sum(disc$kategori %in% c("ekstra_hos_os", "mangler_hos_os", "dato_uenig", "køn_uenig"))
message(sprintf("  %d uenigheder (%d handlingsorienterede) -> %s", nrow(disc), act, rapport))

message("Færdig. Crosswalk: ", cw_csv)
