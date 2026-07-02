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
  grepl("does not exist|42P01", msg %||% "", ignore.case = TRUE)
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
