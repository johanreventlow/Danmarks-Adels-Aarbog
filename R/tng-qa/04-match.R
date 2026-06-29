# Trin 4: blokering + score + injektive tiers. Matching ALDRIG på relationer.

default_cfg <- function() list(
  year_window = 5L, w_name = 0.6, w_birth = 0.2, w_death = 0.1, w_sex = 0.1,
  auto_cutoff = 0.90, review_cutoff = 0.70, ambiguity_margin = 0.05
)

name_similarity <- function(key_a, key_b) {
  1 - stringdist::stringdist(key_a, key_b, method = "jw", p = 0.1)
}

score_pair <- function(name_sim, birth_overlap, death_overlap, sex_eq, cfg) {
  cfg$w_name * name_sim +
    cfg$w_birth * as.numeric(birth_overlap) +
    cfg$w_death * as.numeric(death_overlap) +
    cfg$w_sex   * as.numeric(sex_eq)
}

assign_tiers <- function(scored, cfg) {
  scored$score <- mapply(score_pair, scored$name_sim, scored$birth_overlap,
                         scored$death_overlap, scored$sex_eq,
                         MoreArgs = list(cfg = cfg))
  scored <- scored[order(-scored$score), ]
  used_tng <- character(0); assigned_person <- integer(0)
  scored$tier <- "none"
  for (i in seq_len(nrow(scored))) {
    pid <- scored$person_id[i]; tid <- scored$tng_id[i]; sc <- scored$score[i]
    if (pid %in% assigned_person || tid %in% used_tng) { scored$tier[i] <- "none"; next }
    if (sc >= cfg$auto_cutoff && isTRUE(scored$unique_block[i])) {
      scored$tier[i] <- "auto"; used_tng <- c(used_tng, tid); assigned_person <- c(assigned_person, pid)
    } else if (sc >= cfg$review_cutoff) {
      scored$tier[i] <- "review"
    }
  }
  scored[, c("person_id", "tng_id", "score", "tier")]
}

eval_precision_recall <- function(crosswalk, truth) {
  m <- merge(crosswalk, truth, by = "person_id", suffixes = c("_cw", "_truth"))
  correct <- sum(m$tng_id_cw == m$tng_id_truth)
  list(precision = correct / nrow(crosswalk), recall = correct / nrow(truth))
}
