# Trin 4b: relationel corroboration af review-tier kandidater. Beregnes på
# den FERSKE crosswalk, FØR Trin 5's merge_review_decisions() (som flipper
# review-rækker til accepted/afvist) — ellers findes de aldrig. Se
# docs/superpowers/specs/2026-07-01-tng-qa-relationel-corroboration-design.md.
#
# Matcher ALDRIG på relationer (04-match.R's tier-tildeling er upåvirket) —
# dette er et beslutningsstøtte-signal til den menneskelige reviewer.

family_corroboration <- function(crosswalk, our_pc, tngc) {
  auto   <- crosswalk[crosswalk$tier == "auto", ]
  review <- crosswalk[crosswalk$tier == "review", ]
  auto_map <- setNames(auto$tng_id, as.character(auto$person_id))

  # Kun sikre/sandsynlige forælder-barn-links som corroboration-kilde —
  # aldrig 'omstridt' (design-spec beslutning #3).
  safe_pc <- our_pc[is.na(our_pc$konfidens) | our_pc$konfidens %in% c("sikker", "sandsynlig"), ]

  empty <- data.frame(person_id = integer(0), tng_id = character(0),
                       child_id = integer(0), parent_id = integer(0), rolle = character(0),
                       neighbor_person_id = integer(0), neighbor_tng_id = character(0),
                       status = character(0), familie_detalje = character(0),
                       stringsAsFactors = FALSE)
  if (!nrow(review)) return(empty)

  rows <- list()
  for (i in seq_len(nrow(review))) {
    pid <- review$person_id[i]; tid <- review$tng_id[i]

    # Nabo som FORÆLDER til kandidaten (pid er barnet i our_pc)
    parent_rows <- safe_pc[safe_pc$child_id == pid, ]
    for (j in seq_len(nrow(parent_rows))) {
      neighbor <- parent_rows$parent_id[j]
      neighbor_tng <- auto_map[as.character(neighbor)]
      if (is.na(neighbor_tng)) next
      hit <- any(tngc$child_tng == tid &
                 (tngc$father_tng == neighbor_tng | tngc$mother_tng == neighbor_tng), na.rm = TRUE)
      status <- if (hit) "bekraeftet" else "modstridende"
      label  <- if (hit) "bekræfter" else "modsiger"
      rows[[length(rows) + 1]] <- data.frame(
        person_id = pid, tng_id = tid, child_id = pid, parent_id = neighbor,
        rolle = "forælder", neighbor_person_id = neighbor, neighbor_tng_id = neighbor_tng,
        status = status,
        familie_detalje = sprintf(
          "forælder (person %d, TNG %s) er auto-matchet og %s TNG-relationen til kandidat %s",
          neighbor, neighbor_tng, label, tid),
        stringsAsFactors = FALSE)
    }

    # Nabo som BARN af kandidaten (pid er forælderen i our_pc)
    child_rows <- safe_pc[safe_pc$parent_id == pid, ]
    for (j in seq_len(nrow(child_rows))) {
      neighbor <- child_rows$child_id[j]
      neighbor_tng <- auto_map[as.character(neighbor)]
      if (is.na(neighbor_tng)) next
      hit <- any(tngc$child_tng == neighbor_tng &
                 (tngc$father_tng == tid | tngc$mother_tng == tid), na.rm = TRUE)
      status <- if (hit) "bekraeftet" else "modstridende"
      label  <- if (hit) "bekræfter" else "modsiger"
      rows[[length(rows) + 1]] <- data.frame(
        person_id = pid, tng_id = tid, child_id = neighbor, parent_id = pid,
        rolle = "barn", neighbor_person_id = neighbor, neighbor_tng_id = neighbor_tng,
        status = status,
        familie_detalje = sprintf(
          "barn (person %d, TNG %s) er auto-matchet og %s TNG-relationen til kandidat %s",
          neighbor, neighbor_tng, label, tid),
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(empty)
  do.call(rbind, rows)
}

aggregate_familie_status <- function(corrob) {
  empty <- data.frame(person_id = integer(0), tng_id = character(0),
                       familie_status = character(0), familie_stoette_antal = integer(0),
                       familie_detalje = character(0), stringsAsFactors = FALSE)
  if (!nrow(corrob)) return(empty)
  groups <- split(corrob, paste(corrob$person_id, corrob$tng_id))
  do.call(rbind, lapply(groups, function(g) data.frame(
    person_id = g$person_id[1], tng_id = g$tng_id[1],
    familie_status = if (any(g$status == "bekraeftet")) "bekraeftet" else "modstridende",
    familie_stoette_antal = sum(g$status == "bekraeftet"),
    familie_detalje = paste(g$familie_detalje, collapse = "; "),
    stringsAsFactors = FALSE)))
}
