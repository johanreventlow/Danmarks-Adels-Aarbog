#!/usr/bin/env Rscript
# TNG-QA kalibrering — BOOTSTRAP mod eksakte matches.
# Kør fra repo-rod: Rscript R/tng-qa/calibrate.R
#
# Formål: vælg auto-tærskler (auto_cutoff + ambiguity_margin) uden et håndlabelt
# facit-sæt, ved at bruge de ENTYDIGE EKSAKTE matches som bootstrap-"truth".
#
# ÆRLIG begrænsning: ankrene er korrekte pr. konstruktion, så "anker-recall" er
# IKKE en uafhængig præcisions-måling. Den reelle præcisions-risiko er NON-anker-
# auto (matches der promoteres uden at være eksakte ankre) — dem LISTER scriptet
# til manuel øjen-kontrol. Erstat med et håndlabelt facit-sæt for endelig validering.
#
# Forudsætninger: data/tng.duckdb (kør run-pipeline.R Trin 1 først) + Supabase-env.

suppressPackageStartupMessages({ library(DBI) })
root <- normalizePath(".")
for (f in list.files(file.path(root, "R", "tng-qa"), pattern = "^[0-9].*\\.R$",
                     full.names = TRUE)) source(f)

# ---- Byg scored (genbruger pipeline-byggeklodserne) -----------------------
tcon <- dbConnect(duckdb::duckdb(), "data/tng.duckdb")
tng_people <- dbGetQuery(tcon, "SELECT * FROM tng_people")
dbDisconnect(tcon, shutdown = TRUE)
scon <- connect_readonly(); assert_readonly(scon)
ours <- pull_ours(scon); dbDisconnect(scon)

cfg      <- default_cfg()
our_norm <- our_match_frame(ours$person, ours$dates)
tng_norm <- tng_match_frame(tng_people)
scored   <- build_scored(our_norm, tng_norm, cfg)
scored$score <- mapply(score_pair, scored$name_sim, scored$birth_overlap,
                       scored$death_overlap, scored$sex_eq, MoreArgs = list(cfg = cfg))

# ---- Bootstrap-ankre: entydig EKSAKT match (navn>=0.98 + fødsel + død + køn) --
strict      <- scored$name_sim >= 0.98 & scored$birth_overlap &
               scored$death_overlap & scored$sex_eq
n_strict    <- tapply(strict, scored$person_id, sum)
anchor_pids <- as.integer(names(n_strict)[n_strict == 1])
message(sprintf("Personer m. kandidat: %d | bootstrap-ankre (entydig eksakt): %d",
                length(unique(scored$person_id)), length(anchor_pids)))

# ---- Sweep: auto-dækning + non-anker-auto pr. (auto_cutoff, ambiguity_margin) --
message("\nauto_cutoff  margin  auto_total  anker-auto  NON-anker-auto  anker-recall")
for (ac in c(0.85, 0.88, 0.90)) for (mg in c(0.03, 0.05, 0.08)) {
  c2 <- cfg; c2$auto_cutoff <- ac; c2$ambiguity_margin <- mg
  cw <- assign_tiers(scored[, setdiff(names(scored), c("score"))], c2)
  auto_pids <- cw$person_id[cw$tier == "auto"]
  message(sprintf("   %.2f      %.2f      %5d       %5d         %5d          %3.0f%%",
                  ac, mg, length(auto_pids), sum(auto_pids %in% anchor_pids),
                  sum(!auto_pids %in% anchor_pids),
                  100 * sum(anchor_pids %in% auto_pids) / length(anchor_pids)))
}

# ---- Spot-check-liste: NON-anker-auto ved default cfg ---------------------
cw   <- assign_tiers(scored[, setdiff(names(scored), c("score"))], cfg)
auto <- cw[cw$tier == "auto", ]   # assign_tiers returnerer allerede `score`
na   <- auto[!auto$person_id %in% anchor_pids, ]
na   <- na[order(-na$score), ]
o2   <- merge(na, our_norm[, c("person_id", "name_key", "birth_min", "death_min")], by = "person_id")
o2   <- o2[order(-o2$score), ]
t2   <- tng_norm[match(o2$tng_id, tng_norm$tng_id), c("name_key", "birth_min", "death_min")]
yr   <- function(x) ifelse(is.na(x), "?", x)
message(sprintf("\n-- NON-anker AUTO ved default cfg (%d stk) — øjen-kontrollér korrekthed --",
                nrow(o2)))
for (i in seq_len(nrow(o2))) message(sprintf("  %-26s %s/%s  ->  %-26s %s/%s  (%.3f)",
  substr(o2$name_key[i], 1, 26), yr(o2$birth_min[i]), yr(o2$death_min[i]),
  substr(t2$name_key[i], 1, 26), yr(t2$birth_min[i]), yr(t2$death_min[i]), o2$score[i]))
