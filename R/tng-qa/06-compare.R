# Trin 6: relations-sammenligning. Kant sammenlignes KUN når begge endepunkter matchet.

# ---- Glue: byg sammenlignings-input fra ours / TNG -------------------------

# Vores forælder-barn modelleres som 'barn' + 'partner' i samme family (ingen
# fader/moder-rolle). Udled (barn, partner)-par; rolle='ukendt' tjekker
# edge-eksistens mod begge TNG-slots (køn-mismatch fanges af compare_dates_sex).
derive_our_pc <- function(family_member) {
  fm <- family_member
  parts <- lapply(unique(fm$family_id), function(fid) {
    kid_rows <- fm[fm$family_id == fid & fm$rolle == "barn", ]
    parents  <- as.integer(fm$person_id[fm$family_id == fid & fm$rolle == "partner"])
    if (!nrow(kid_rows) || !length(parents)) return(NULL)
    do.call(rbind, lapply(seq_len(nrow(kid_rows)), function(k) {
      data.frame(child_id = as.integer(kid_rows$person_id[k]), parent_id = parents,
                 konfidens = kid_rows$konfidens[k], stringsAsFactors = FALSE)
    }))
  })
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts))
    return(data.frame(child_id = integer(0), parent_id = integer(0),
                       rolle = character(0), konfidens = character(0)))
  out <- unique(do.call(rbind, parts))
  out$rolle <- "ukendt"
  out
}

# Vores datoer/køn til compare_dates_sex. DATE -> heltals-år (flugter med
# tng_date_to_interval). Genbruger .year_int fra 04-match.R.
our_attr_frame <- function(person, dates) {
  births <- dates[dates$faktatype == "fødsel", ]
  deaths <- dates[dates$faktatype == "død", ]
  parts <- lapply(seq_len(nrow(person)), function(i) {
    p <- person[i, ]
    b <- births[births$person_id == p$id, ]
    d <- deaths[deaths$person_id == p$id, ]
    data.frame(
      person_id = as.integer(p$id),
      birth_min = if (nrow(b)) .year_int(b$date_min) else NA_integer_,
      birth_max = if (nrow(b)) .year_int(b$date_max) else NA_integer_,
      death_min = if (nrow(d)) .year_int(d$date_min) else NA_integer_,
      death_max = if (nrow(d)) .year_int(d$date_max) else NA_integer_,
      koen = p$koen, stringsAsFactors = FALSE)
  })
  do.call(rbind, parts)
}

# Reshape rå tng_children (familyID/personID) -> (child, far, mor) via join til
# tng_families: far = husband, mor = wife. Tom streng -> NA.
reshape_tng_children <- function(tng_children, tng_families) {
  fam <- tng_families[, c("familyID", "husband", "wife")]
  m   <- merge(tng_children[, c("personID", "familyID")], fam, by = "familyID", all.x = TRUE)
  nz  <- function(x) ifelse(!is.na(x) & nzchar(x), x, NA_character_)
  data.frame(child_tng = m$personID, father_tng = nz(m$husband),
             mother_tng = nz(m$wife), stringsAsFactors = FALSE)
}

our_spouse_pairs <- function(family, family_member) {
  partners <- family_member[family_member$rolle == "partner", ]
  out <- data.frame(person_id = integer(0), spouse_id = integer(0))
  for (fid in unique(partners$family_id)) {
    ps <- partners$person_id[partners$family_id == fid]
    if (length(ps) >= 2)
      for (a in ps) for (b in ps) if (a != b)
        out <- rbind(out, data.frame(person_id = a, spouse_id = b))
  }
  unique(out)
}

compare_marriages <- function(our_pairs, tng_families, xwalk) {
  to_tng <- function(pid) xwalk$tng_id[match(pid, xwalk$person_id)]
  rows <- list()
  # our edges -> is there a TNG family with the matched pair?
  tng_set <- rbind(
    data.frame(a = tng_families$husband, b = tng_families$wife, stringsAsFactors = FALSE),
    data.frame(a = tng_families$wife, b = tng_families$husband, stringsAsFactors = FALSE)
  )
  for (i in seq_len(nrow(our_pairs))) {
    pid <- our_pairs$person_id[i]; sid <- our_pairs$spouse_id[i]
    t_p <- to_tng(pid); t_s <- to_tng(sid)
    if (is.na(t_p) || is.na(t_s)) {
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = NA_character_,
        kategori = "uden_for_scope", detalje = "ægtefælle ikke matchet")
      next
    }
    hit <- any(tng_set$a == t_p & tng_set$b == t_s)
    rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = t_p,
      kategori = if (hit) "enig" else "ekstra_hos_os",
      detalje = sprintf("vores: %d—%d", pid, sid))
  }
  # TNG edges where our matched person has a spouse in TNG we lack
  our_set <- rbind(
    data.frame(a = our_pairs$person_id, b = our_pairs$spouse_id),
    data.frame(a = our_pairs$spouse_id, b = our_pairs$person_id)
  )
  for (i in seq_len(nrow(tng_families))) {
    h <- tng_families$husband[i]; w <- tng_families$wife[i]
    p_h <- xwalk$person_id[match(h, xwalk$tng_id)]
    p_w <- xwalk$person_id[match(w, xwalk$tng_id)]
    if (is.na(p_h) || is.na(p_w)) {
      known <- if (!is.na(p_h)) p_h else if (!is.na(p_w)) p_w else NA_integer_
      if (!is.na(known))
        rows[[length(rows)+1]] <- data.frame(person_id = known, tng_id = if (!is.na(p_h)) h else w,
          kategori = "uden_for_scope", detalje = "TNG-ægtefælle uden for vores scope")
      next
    }
    has <- any(our_set$a == p_h & our_set$b == p_w)
    if (!has)
      rows[[length(rows)+1]] <- data.frame(person_id = p_h, tng_id = h,
        kategori = "mangler_hos_os", detalje = sprintf("TNG: %s—%s", h, w))
  }
  if (length(rows)) do.call(rbind, rows) else
    data.frame(person_id = integer(0), tng_id = character(0),
               kategori = character(0), detalje = character(0), stringsAsFactors = FALSE)
}

compare_parent_child <- function(our_pc, tng_children, xwalk) {
  # our_pc: data.frame(child_id, parent_id, rolle) ; rolle %in% c("fader","moder","ukendt")
  # tng_children: data.frame(child_tng, father_tng, mother_tng)
  to_tng  <- function(pid) xwalk$tng_id[match(pid, xwalk$person_id)]
  to_ours <- function(tid) xwalk$person_id[match(tid, xwalk$tng_id)]
  rows <- list()
  # ---- our edges -> TNG (per-parent) ----
  for (i in seq_len(nrow(our_pc))) {
    c_t <- to_tng(our_pc$child_id[i]); p_t <- to_tng(our_pc$parent_id[i])
    if (is.na(c_t) || is.na(p_t)) {
      rows[[length(rows) + 1]] <- data.frame(child_id = our_pc$child_id[i], tng_id = NA_character_,
        kategori = "uden_for_scope", detalje = "barn/forælder ikke matchet", stringsAsFactors = FALSE)
      next
    }
    tc <- tng_children[tng_children$child_tng == c_t, ]
    rolle <- our_pc$rolle[i]
    tng_parent <- if (identical(rolle, "fader")) tc$father_tng
                  else if (identical(rolle, "moder")) tc$mother_tng
                  else c(tc$father_tng, tc$mother_tng)
    hit <- nrow(tc) > 0 && (p_t %in% tng_parent)
    rows[[length(rows) + 1]] <- data.frame(child_id = our_pc$child_id[i], tng_id = c_t,
      kategori = if (hit) "enig" else "ekstra_hos_os",
      detalje = sprintf("vores %s %d", rolle, our_pc$parent_id[i]), stringsAsFactors = FALSE)
  }
  # ---- TNG edges -> ours (mangler_hos_os), per-parent, scope-guarded ----
  our_set <- paste(our_pc$child_id, our_pc$parent_id, sep = "-")
  for (i in seq_len(nrow(tng_children))) {
    c_t <- tng_children$child_tng[i]; c_o <- to_ours(c_t)
    if (is.na(c_o)) next
    for (slot in c("father_tng", "mother_tng")) {
      pt <- tng_children[[slot]][i]
      if (is.na(pt) || !nzchar(pt)) next
      p_o <- to_ours(pt)
      if (is.na(p_o)) {
        rows[[length(rows) + 1]] <- data.frame(child_id = c_o, tng_id = c_t,
          kategori = "uden_for_scope", detalje = sprintf("TNG-%s uden for scope", slot), stringsAsFactors = FALSE)
        next
      }
      if (!(paste(c_o, p_o, sep = "-") %in% our_set))
        rows[[length(rows) + 1]] <- data.frame(child_id = c_o, tng_id = c_t,
          kategori = "mangler_hos_os", detalje = sprintf("TNG %s: %s", slot, pt), stringsAsFactors = FALSE)
    }
  }
  if (length(rows)) do.call(rbind, rows) else
    data.frame(child_id = integer(0), tng_id = character(0),
               kategori = character(0), detalje = character(0), stringsAsFactors = FALSE)
}

compare_dates_sex <- function(our_attr, tng_people, xwalk) {
  # our_attr: data.frame(person_id, birth_min,birth_max,death_min,death_max, koen)
  rows <- list()
  for (i in seq_len(nrow(our_attr))) {
    pid <- our_attr$person_id[i]; tid <- xwalk$tng_id[match(pid, xwalk$person_id)]
    if (is.na(tid)) next
    tp <- tng_people[tng_people$personID == tid, ]
    if (!nrow(tp)) next
    tb <- tng_date_to_interval(tp$birthdatetr[1]); td <- tng_date_to_interval(tp$deathdatetr[1])
    if (!intervals_overlap(c(our_attr$birth_min[i], our_attr$birth_max[i]), tb))
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = tid, kategori = "dato_uenig",
        detalje = sprintf("fødsel: vores [%s,%s] vs TNG %s", our_attr$birth_min[i], our_attr$birth_max[i], tp$birthdatetr[1]))
    if (!intervals_overlap(c(our_attr$death_min[i], our_attr$death_max[i]), td))
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = tid, kategori = "dato_uenig",
        detalje = sprintf("død: vores [%s,%s] vs TNG %s", our_attr$death_min[i], our_attr$death_max[i], tp$deathdatetr[1]))
    if (normalize_sex(our_attr$koen[i]) != normalize_sex(tp$sex[1]) &&
        normalize_sex(tp$sex[1]) != "ukendt" && normalize_sex(our_attr$koen[i]) != "ukendt")
      rows[[length(rows)+1]] <- data.frame(person_id = pid, tng_id = tid, kategori = "køn_uenig",
        detalje = sprintf("vores %s vs TNG %s", our_attr$koen[i], tp$sex[1]))
  }
  if (length(rows)) do.call(rbind, rows) else
    data.frame(person_id = integer(0), tng_id = character(0), kategori = character(0), detalje = character(0))
}
