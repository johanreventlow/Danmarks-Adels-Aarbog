# .claude/skills/daa-extract/scripts/load_helpers.R
# Rene, DB-frie hjælpere til load_daa.R — unit-testbare i testthat (ingen DB-I/O, ingen <<-).

# Tæller rækker pr. tabel i en buffer (enten en list — testthat-fixture — eller det
# rigtige .buf-environment fra load_daa.R). NB: names() bruges frem for ls() — ls()
# alfabetiserer, hvilket ikke matcher indsættelsesrækkefølgen for en list() og giver
# et positions-mismatch i expect_equal() mod en named vector i anden rækkefølge.
buffer_counts <- function(buf) {
  tbls <- names(buf)
  vapply(setNames(tbls, tbls), function(t) length(buf[[t]]), integer(1))
}

# Redaktionelle change_set-rækker (operation 'red_%') markerer arbejde der ikke må
# TRUNCATE'es. Import/load-changes gør ikke. Ren funktion; cs = data.frame m. 'operation'.
has_editorial_changes <- function(cs) {
  if (is.null(cs) || !nrow(cs)) return(FALSE)
  any(grepl("^red_", cs$operation))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# Er en DB-fejlbesked et "relation findes ikke"-signal (Postgres 42P01)? Så er
# change_set-tabellen fraværende (umigreret base) -> sikkert at antage 0 redaktionelle
# rækker. Alle andre fejl er usikre og skal fejle lukket.
is_missing_table_error <- function(msg) {
  grepl("relation .* does not exist|42P01", msg %||% "", ignore.case = TRUE)
}

# Intern reference = "se nr. N" / "nr. N" / "… linje, nr. N" i SAMME kilde.
# Ekstern (anden DAA-udgave, "DAA 1937, II, 122") -> NULL: stub oprettes stadig.
parse_intern_ref <- function(ref, default_linje) {
  if (is.null(ref) || length(ref) == 0 || is.na(ref)) return(NULL)
  if (grepl("DAA|\\b1[89]\\d\\d\\b", ref)) return(NULL)   # ekstern udgave
  linje <- default_linje
  lm <- regmatches(ref, regexpr("\\b(I{1,3}V?|VI{0,3})\\b(?=\\.?\\s*Den|,\\s*nr)", ref, perl=TRUE))
  if (length(lm) && nzchar(lm)) linje <- lm
  nm <- regmatches(ref, regexpr("nr\\.?\\s*(\\d+)", ref, perl=TRUE))
  if (!length(nm) || !nzchar(nm)) return(NULL)
  nr <- sub(".*?(\\d+).*", "\\1", nm)
  list(linje = linje, nr = nr)
}

# Nøgler i pmap der matcher et barn-basenr. Foretræk eksakt "linje-nr"; ellers
# 15a/15b-varianter (barn af en 15a/15b-forælder registreres under labels, ikke basenr).
resolve_barn_keys <- function(linje, nr, pmap_keys) {
  eksakt <- paste0(linje, "-", nr)
  if (eksakt %in% pmap_keys) return(eksakt)
  grep(sprintf("^%s-%d[a-z]$", linje, nr), pmap_keys, value = TRUE)
}
# Diagnostisk årsag til et barn-opslag, ud fra de resolverede nøgler.
barn_lookup_reason <- function(keys) if (length(keys) > 0) "ok" else "nr_ikke_i_forael_linje"

# Danske ordenstals-ord -> tal. Returnerer ét entydigt tal, ellers NA (flere
# distinkte ord => tvetydigt). Fixed-substring (ikke \\b) fordi æ/ø/å ikke er
# pålidelige word-chars i R's regex-motor.
.dk_ordinal_tal <- function(low) {
  ord <- c("første"=1L, "anden"=2L, "andet"=2L, "tredje"=3L,
           "fjerde"=4L, "femte"=5L, "sjette"=6L, "syvende"=7L)
  traf <- ord[vapply(names(ord), function(w) grepl(w, low, fixed = TRUE), logical(1))]
  vals <- unique(unname(traf))
  if (length(vals) == 1L) vals else NA_integer_
}

# match_barn_union: knyt et barns fritekst-`aegteskab_kontekst` til ét af
# forælderens ægteskaber. `aegteskaber` er rec$aegteskaber (samme rækkefølge som
# loaderens `fams`-liste), hvert element en liste m. $ordinal + $partner_navn.
#
# Primær anker: PARTNERNAVN (positions-uafhængigt, entydigt når navne adskiller
# sig). Kryds-tjek: ordenstals-ord mappet til det ægteskab hvis $ordinal *er lig*
# tallet (ikke positionelt — nogle rækker kan have ordinal=NA). Er begge til
# stede og uenige => NA (log, gæt aldrig). Navngiver konteksten en partner der
# ikke er blandt ægteskaberne (fx et barn af en ikke-registreret forbindelse)
# => NA m. reason 'ukendt_partner', så kalderen kan parkere frem for at fejl-
# tilknytte til 1. ægteskab.
#
# Retur: list(idx=<1-baseret indeks i aegteskaber, el. NA>, reason, via).
match_barn_union <- function(ctx, aegteskaber) {
  na_res <- function(reason) list(idx = NA_integer_, reason = reason, via = NA_character_)
  n <- length(aegteskaber)
  if (n == 0L) return(na_res("ingen_aegteskaber"))
  if (is.null(ctx) || length(ctx) == 0L || is.na(ctx) || !nzchar(trimws(ctx)))
    return(na_res("tom_kontekst"))
  low <- tolower(ctx)

  # --- primær: partnernavn (fuldt navn som substring; ellers distinkt efternavn) ---
  pnames <- vapply(aegteskaber, function(a) {
    v <- a[["partner_navn"]]
    if (is.null(v) || length(v) == 0L || is.na(v)) "" else tolower(trimws(v))
  }, character(1))
  partner_hits <- which(vapply(seq_len(n), function(i) {
    pn <- pnames[i]
    if (!nzchar(pn)) return(FALSE)
    if (grepl(pn, low, fixed = TRUE)) return(TRUE)          # fuldt navn nævnt
    toks <- strsplit(pn, "\\s+")[[1]]
    efternavn <- toks[length(toks)]                          # "von Qualen" -> "qualen"
    nchar(efternavn) >= 4L && grepl(efternavn, low, fixed = TRUE)
  }, logical(1)))

  # --- kryds-tjek: ordenstals-ord -> ægteskab hvis $ordinal matcher tallet ---
  ord_num <- .dk_ordinal_tal(low)
  ordinal_hits <- if (!is.na(ord_num)) {
    which(vapply(aegteskaber, function(a) {
      o <- a[["ordinal"]]
      !is.null(o) && length(o) && !is.na(o) && suppressWarnings(as.integer(o)) == ord_num
    }, logical(1)))
  } else integer(0)

  up <- unique(partner_hits); uo <- unique(ordinal_hits)
  if (length(up) == 1L && length(uo) == 1L) {
    if (up == uo) return(list(idx = up, reason = "ok", via = "begge"))
    return(na_res("konflikt_partner_vs_ordenstal"))
  }
  if (length(up) == 1L) return(list(idx = up, reason = "ok", via = "partner"))
  if (length(uo) == 1L) return(list(idx = uo, reason = "ok", via = "ordenstal"))
  if (length(up) > 1L)  return(na_res("flertydigt_partnernavn"))
  na_res("ukendt_partner")   # partner nævnt men ikke blandt ægteskaberne, el. intet spor
}
