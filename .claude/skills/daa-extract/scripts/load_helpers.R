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
