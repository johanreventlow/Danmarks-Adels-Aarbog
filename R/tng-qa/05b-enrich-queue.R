# Berig review-køen med navne/datoer til menneskelig gennemgang (Shiny-app +
# manuel CSV-redigering). Kun til data/tng-review-queue.csv, som allerede er
# git-ignoreret og allerede kan referere levende personer (samme risikokategori
# som i dag — ingen ny PII-eksponering, kun læsbar form af samme id'er).

our_navn_lookup <- function(person, ext_id) {
  # person$id kommer råt fra RPostgres (BIGINT -> integer64); .label() gør
  # sprintf("%d", pid), som fejler på integer64 — kræver samme as.integer()-
  # konvertering som resten af pipelinen allerede bruger konsekvent
  # (fx our_match_frame(), derive_our_pc()).
  pid_int <- as.integer(person$id)
  labels <- vapply(pid_int, function(pid) .label(pid, ext_id), character(1))
  setNames(sprintf("%s %s", labels, person$visning_navn), as.character(pid_int))
}

tng_navn_lookup <- function(tng_people) {
  setNames(trimws(paste(tng_people$firstname, tng_people$lastname)), tng_people$personID)
}

# Erstatter de id-baserede referencer i family_corroboration()'s familie_detalje
# ("person <id>", "TNG I<n>") med navne — uden at røre selve
# family_corroboration()/aggregate_familie_status() (04b-corroboration.R),
# som bevidst er id-baserede, rene, allerede shippede funktioner.
resolve_familie_detalje <- function(detalje, tng_id, our_navn, tng_navn) {
  vapply(seq_along(detalje), function(i) {
    d <- detalje[i]
    if (is.na(d) || !nzchar(d)) return(d)
    kandidat_navn <- tng_navn[tng_id[i]]
    if (!is.na(kandidat_navn)) d <- gsub(tng_id[i], kandidat_navn, d, fixed = TRUE)
    for (m in unique(unlist(regmatches(d, gregexpr("person \\d+", d))))) {
      navn <- our_navn[sub("person ", "", m)]
      if (!is.na(navn)) d <- gsub(m, navn, d, fixed = TRUE)
    }
    for (m in unique(unlist(regmatches(d, gregexpr("TNG I\\d+", d))))) {
      tid <- sub("TNG ", "", m)
      navn <- tng_navn[tid]
      if (!is.na(navn)) d <- gsub(m, sprintf("%s (%s)", navn, tid), d, fixed = TRUE)
    }
    d
  }, character(1))
}

enrich_review_queue <- function(rq, person, ext_id, tng_people) {
  our_navn <- our_navn_lookup(person, ext_id)
  tng_navn <- tng_navn_lookup(tng_people)

  rq$vores_label <- vapply(rq$person_id, function(pid) .label(pid, ext_id), character(1))
  rq$vores_navn  <- person$visning_navn[match(rq$person_id, person$id)]
  rq$vores_foedt <- person$visning_foedt[match(rq$person_id, person$id)]
  rq$vores_doed  <- person$visning_doed[match(rq$person_id, person$id)]
  rq$tng_navn    <- tng_navn[rq$tng_id]
  rq$tng_foedt   <- tng_people$birthdatetr[match(rq$tng_id, tng_people$personID)]
  rq$tng_doed    <- tng_people$deathdatetr[match(rq$tng_id, tng_people$personID)]

  if ("familie_detalje" %in% names(rq)) {
    rq$familie_detalje <- resolve_familie_detalje(rq$familie_detalje, rq$tng_id, our_navn, tng_navn)
  }
  rq
}
