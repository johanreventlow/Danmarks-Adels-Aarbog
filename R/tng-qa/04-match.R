# Trin 4: blokering + score + injektive tiers. Matching ALDRIG på relationer.

default_cfg <- function() list(
  year_window = 5L, w_name = 0.6, w_birth = 0.2, w_death = 0.1, w_sex = 0.1,
  # auto kræver score >= auto_cutoff OG at bedste kandidat er mindst
  # ambiguity_margin foran nr. 2 (kalibreret mod bootstrap-ankre 2026-06-30:
  # margin 0.05 -> 86% af de entydige eksakte matches auto-promoteres). Den
  # uniforme "Reventlow" gør unique_block ubrugelig som auto-gate -> margin i stedet.
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
  # Per-person: ambiguitets-margin (bedste - næstbedste score) + flag for personens
  # TOP-kandidat. margin=Inf hvis kun én kandidat (ingen tvetydighed).
  scored$margin <- NA_real_
  scored$is_top <- FALSE
  for (idx in split(seq_len(nrow(scored)), scored$person_id)) {
    o <- idx[order(-scored$score[idx])]
    scored$margin[idx]  <- if (length(o) < 2L) Inf else scored$score[o[1]] - scored$score[o[2]]
    scored$is_top[o[1]] <- TRUE
  }
  scored <- scored[order(-scored$score), ]
  used_tng <- character(0); assigned_person <- integer(0)
  scored$tier <- "none"
  for (i in seq_len(nrow(scored))) {
    pid <- scored$person_id[i]; tid <- scored$tng_id[i]; sc <- scored$score[i]
    if (pid %in% assigned_person || tid %in% used_tng) { scored$tier[i] <- "none"; next }
    # auto KUN på personens top-kandidat: hvis nr. 1 er claimet af en anden,
    # falder personen til review — aldrig auto på et ringere 2.-valg.
    if (sc >= cfg$auto_cutoff && scored$margin[i] >= cfg$ambiguity_margin && scored$is_top[i]) {
      scored$tier[i] <- "auto"; used_tng <- c(used_tng, tid); assigned_person <- c(assigned_person, pid)
    } else if (sc >= cfg$review_cutoff) {
      scored$tier[i] <- "review"
    }
  }
  scored[, c("person_id", "tng_id", "score", "tier")]
}

# ---- Trin 3-4-glue: byg `scored` fra ours + tng_people --------------------
# Blok-skemaet er en bevidst UDVIDELSE af doc'ens "efternavn-initial +
# fødselsdekade": efternavnet er næsten altid "Reventlow" (ubrugeligt som
# blok), så vi blokerer på FORNAVNS-initial og filtrerer kandidater på
# fødselsår-vindue KUN når begge år kendes (de 300 uden år falder tilbage på
# rent navne-match). Tærskler/vægte er IKKE kalibreret (intet facit-sæt endnu).

.year_int <- function(d) {
  if (length(d) == 0L || is.na(d[1])) return(NA_integer_)
  suppressWarnings(as.integer(format(as.Date(d[1]), "%Y")))
}

# Vektoriseret intervals_overlap: ÉT skalar-interval a mod VEKTORER b (samme
# NA->±Inf-semantik som intervals_overlap, men uden R-closure pr. element —
# afgørende for ydelse over ~millioner kandidat-par).
.overlap_vec <- function(amin, amax, bmin, bmax) {
  amin <- if (is.na(amin)) -Inf else amin
  amax <- if (is.na(amax))  Inf else amax
  bmin <- ifelse(is.na(bmin), -Inf, bmin)
  bmax <- ifelse(is.na(bmax),  Inf, bmax)
  amin <= bmax & bmin <= amax
}

# Overlap som SCORING-EVIDENS: TRUE kun når BEGGE sider har en dato OG de
# overlapper. Ukendt dato = manglende evidens, ikke enighed -> FALSE (ellers
# fik dato-løse par 0.3 "gratis" vægt og kunne fejlagtigt auto-promoteres).
# Bruges KUN til score-signalet; blokerings-vinduet beholder fortsat dato-løse
# kandidater (en ægte match må ikke tabes fordi datoen mangler).
.overlap_evidence <- function(amin, amax, bmin, bmax) {
  a_known <- !is.na(amin) | !is.na(amax)
  b_known <- !is.na(bmin) | !is.na(bmax)
  a_known & b_known & .overlap_vec(amin, amax, bmin, bmax)
}

# Normalisér VORES folk til match-rammen. visning_navn er kun fornavne for
# Reventlow'er -> normalize_name(last="") tilføjer implicit "Reventlow", så
# nøglen flugter med TNG's firstname+lastname="Reventlow".
our_match_frame <- function(person, dates) {
  births <- dates[dates$faktatype == "fødsel", ]
  deaths <- dates[dates$faktatype == "død", ]
  parts <- lapply(seq_len(nrow(person)), function(i) {
    p  <- person[i, ]
    nm <- normalize_name(p$visning_navn, last = "", married_in = FALSE)
    b  <- births[births$person_id == p$id, ]
    d  <- deaths[deaths$person_id == p$id, ]
    data.frame(
      # bigint -> integer64 fra Postgres; data.frame recycler ikke en
      # integer64-skalar mod længere kolonner -> tving plain integer.
      person_id   = as.integer(p$id),
      name_key    = nm$key,
      block       = substr(nm$key, 1, 1),
      birth_min   = if (nrow(b)) .year_int(b$date_min) else NA_integer_,
      birth_max   = if (nrow(b)) .year_int(b$date_max) else NA_integer_,
      death_min   = if (nrow(d)) .year_int(d$date_min) else NA_integer_,
      death_max   = if (nrow(d)) .year_int(d$date_max) else NA_integer_,
      sex         = normalize_sex(p$koen),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, parts)
}

# Normalisér TNG-folk analogt. birthdatetr/deathdatetr er allerede "YYYY-MM-DD"
# (0000-00-00 = ukendt), præcis hvad tng_date_to_interval forventer.
tng_match_frame <- function(tp) {
  keys <- vapply(seq_len(nrow(tp)), function(i)
    normalize_name(tp$firstname[i], tp$lastname[i], married_in = FALSE)$key,
    character(1))
  bi <- lapply(tp$birthdatetr, tng_date_to_interval)
  di <- lapply(tp$deathdatetr, tng_date_to_interval)
  data.frame(
    tng_id    = tp$personID,
    name_key  = keys,
    block     = substr(keys, 1, 1),
    birth_min = vapply(bi, `[`, integer(1), 1L),
    birth_max = vapply(bi, `[`, integer(1), 2L),
    death_min = vapply(di, `[`, integer(1), 1L),
    death_max = vapply(di, `[`, integer(1), 2L),
    sex       = vapply(tp$sex, normalize_sex, character(1)),
    stringsAsFactors = FALSE
  )
}

# Byg kandidat-par-tabellen. unique_block = vores-person har præcis ÉN
# TNG-kandidat efter blokering+vindue (broadcastes på personens rækker).
build_scored <- function(our_norm, tng_norm, cfg) {
  tng_by_blk <- split(seq_len(nrow(tng_norm)), tng_norm$block)
  # Tabsfri navne-floor: et par kan kun nå review_cutoff hvis name_sim er mindst
  # (review_cutoff - max bonus)/w_name. Par derunder er GARANTERET tier "none",
  # så de prunes — holder `scored` lille (assign_tiers er O(n) R-loop) og gør
  # unique_block = "præcis én PLAUSIBEL kandidat".
  name_floor <- max(0, (cfg$review_cutoff - (cfg$w_birth + cfg$w_death + cfg$w_sex)) / cfg$w_name)
  empty <- data.frame(person_id = integer(), tng_id = character(),
                      name_sim = numeric(), birth_overlap = logical(),
                      death_overlap = logical(), sex_eq = logical(),
                      unique_block = logical(), stringsAsFactors = FALSE)
  parts <- vector("list", nrow(our_norm))
  for (i in seq_len(nrow(our_norm))) {
    idx <- tng_by_blk[[ our_norm$block[i] ]]
    if (is.null(idx)) next
    cand <- tng_norm[idx, , drop = FALSE]

    # Fødselsår-vindue: kun når VORES år kendes; behold kandidat hvis dens år
    # er ukendt eller overlapper vores [min-w, max+w].
    obmin <- our_norm$birth_min[i]; obmax <- our_norm$birth_max[i]
    if (!is.na(obmin) || !is.na(obmax)) {
      w  <- cfg$year_window
      lo <- if (is.na(obmin)) NA_integer_ else obmin - w
      hi <- if (is.na(obmax)) NA_integer_ else obmax + w
      keep <- .overlap_vec(lo, hi, cand$birth_min, cand$birth_max)
      cand <- cand[keep, , drop = FALSE]
    }
    if (!nrow(cand)) next

    # name_sim på FULD nøgle (fornavn + efternavn). Efternavnet er kritisk:
    # det skiller Reventlow'er fra ægtefæller/aner af anden slægt i TNG (kun-
    # fornavn gav tværfamilie-falske match, fx "hinrich reventlow" -> "hinrich
    # dethlefsen"). KALIBRERINGS-NOTE: det uniforme "Reventlow" komprimerer JW-
    # spændet til ~0.7-1.0, så review oversvømmes ved cutoff 0.70 — justér
    # review_cutoff mod et facit-sæt (se docs/tng-qa-koersel.md § "Trin 3-4").
    sims <- name_similarity(our_norm$name_key[i], cand$name_key)
    sims[is.na(sims)] <- 0                      # tom nøgle -> JW NaN -> 0
    plausible <- sims >= name_floor             # tabsfri prune (se name_floor ovenfor)
    if (!any(plausible)) next
    cand <- cand[plausible, , drop = FALSE]; sims <- sims[plausible]
    n_plausible <- nrow(cand)                   # driver unique_block (ægte unikhed)

    bo <- .overlap_evidence(obmin, obmax, cand$birth_min, cand$birth_max)
    do <- .overlap_evidence(our_norm$death_min[i], our_norm$death_max[i],
                            cand$death_min, cand$death_max)
    # ukendt køn tæller ikke som match (undgår gratis w_sex-vægt).
    se <- our_norm$sex[i] == cand$sex & our_norm$sex[i] != "ukendt"

    # Top-K-cap: assign_tiers vælger alligevel kun den bedste pr. person
    # (injektivt) og er en O(rækker) R-loop -> behold kun de K bedste pr.
    # person, så `scored` forbliver lille. Rangér efter FAKTISK score, IKKE
    # name_sim alene: ligenavngivne (Otto, Detlev...) har alle name_sim~1.0,
    # og fødselsår-overlap er diskriminatoren — så cap'en skal se den, ellers
    # kan det fødsels-korrekte match tabe til et ligenavngivet ved vilkårlig
    # tie-break. unique_block beregnes FØR cap (ægte unikhed bevares).
    K <- if (is.null(cfg$top_k)) 10L else cfg$top_k
    if (n_plausible > K) {
      sc  <- score_pair(sims, bo, do, se, cfg)
      ord <- order(-sc)[seq_len(K)]
      cand <- cand[ord, , drop = FALSE]
      sims <- sims[ord]; bo <- bo[ord]; do <- do[ord]; se <- se[ord]
    }

    parts[[i]] <- data.frame(
      person_id = our_norm$person_id[i], tng_id = cand$tng_id,
      name_sim = sims, birth_overlap = bo, death_overlap = do,
      sex_eq = se, unique_block = (n_plausible == 1L), stringsAsFactors = FALSE)
  }
  parts <- Filter(Negate(is.null), parts)
  if (!length(parts)) return(empty)
  do.call(rbind, parts)
}

eval_precision_recall <- function(crosswalk, truth) {
  m <- merge(crosswalk, truth, by = "person_id", suffixes = c("_cw", "_truth"))
  correct <- sum(m$tng_id_cw == m$tng_id_truth)
  list(precision = correct / nrow(crosswalk), recall = correct / nrow(truth))
}
