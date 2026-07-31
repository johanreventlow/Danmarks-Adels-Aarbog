#!/usr/bin/env Rscript
# Backfill af slægtled (lokal+gennemgående) + kuld til person_external_id.
# Join-nøgle: (source_id, linje, nr). NULL/ukendt linje karantænes (ikke matchet).
# Fortrydbart: ét change_set (operation='backfill_slaegtled'). Fortryd: red_fortryd_change_set(<id>).
# Kør EFTER db-migrations.sql (kolonner skal findes). Idempotent via guard.
suppressMessages({library(DBI); library(RPostgres); library(jsonlite)})

args <- commandArgs(trailingOnly = TRUE)
seg_path <- if (length(args)) args[[1]] else "/tmp/seg.json"
posts <- fromJSON(seg_path, simplifyDataFrame = TRUE)

# F4: eksplicit source-id-pin (2. arg, evt. "--source-id=<id>"). Fail-closed
# hvis udeladt og mere end én kilde kvalificerer (se resolution nedenfor).
source_id_arg <- NULL
if (length(args) >= 2) {
  raw <- args[[2]]
  if (grepl("^--source-id=", raw)) raw <- sub("^--source-id=", "", raw)
  source_id_arg <- suppressWarnings(as.integer(raw))
  if (is.na(source_id_arg)) stop(sprintf("Ugyldig --source-id/2. arg: '%s' er ikke et heltal.", args[[2]]))
}

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require", bigint = "integer")
on.exit(dbDisconnect(con), add = TRUE)
q  <- function(sql, p = list()) if (length(p)) dbGetQuery(con, sql, params = p) else dbGetQuery(con, sql)

# F4: Resolvér DAA-stamtavle-kilden fail-closed. Pinnet eksplicit vinder;
# ellers kun automatisk hvis PRÆCIS én source_id rent faktisk bruger de
# romerske linje-koder (I-V) dette backfill angår — "flest external_id-
# rækker" var upålideligt (en dominerende senere kilde ville stille
# overskrive DENNE udgaves generationer på dens (linje,nr)-rækker).
if (!is.null(source_id_arg)) {
  sid <- source_id_arg
  cat(sprintf("[backfill] source_id=%s (eksplicit pinnet via CLI)\n", sid))
} else {
  candidates <- q("SELECT DISTINCT source_id FROM person_external_id
                    WHERE linje ~ '^(I|II|III|IV|V)$' ORDER BY source_id")$source_id
  if (length(candidates) == 0) {
    stop("Ingen source_id bruger romerske linje-koder (I-V) — kan ikke resolve automatisk. Angiv --source-id eksplicit.")
  }
  if (length(candidates) > 1) {
    stop(sprintf("Flere source_id'er bruger romerske linje-koder (I-V): %s. Angiv --source-id eksplicit for at undgå at skrive denne udgaves generationer til forkert kilde.",
                 paste(candidates, collapse = ", ")))
  }
  sid <- candidates[[1]]
  cat(sprintf("[backfill] source_id=%s\n", sid))
}

# Byg (linje,nr) -> (lokal,gennem,kuld); kun rækker med linje != NA og lokal != NA.
rows <- posts[!is.na(posts$linje) & !is.na(posts$slaegtled_lokal),
              c("linje","nr","slaegtled_lokal","slaegtled_gennem","kuld")]
quarantined <- sum(is.na(posts$linje) & !is.na(posts$slaegtled_lokal))
cat(sprintf("[backfill] %d rækker med linje+lokal; %d karantænet (NULL linje)\n", nrow(rows), quarantined))

# F5.1: suffiks-varianter (fx 15a/15b, samme linje+nr) SKAL være enige om
# generation (design §5.4). Assertér på det parsede input, før noget rammer DB'en.
key <- paste(rows$linje, rows$nr, sep = ":")
gen_key <- paste(rows$slaegtled_lokal, rows$slaegtled_gennem, sep = "|")
conflicts <- names(Filter(function(x) length(unique(x)) > 1, split(gen_key, key)))
if (length(conflicts)) {
  stop(sprintf("Modstridende generationer for suffiks-varianter (linje:nr) — %s. Ret input FØR backfill (samme (linje,nr) skal have samme slaegtled_lokal/slaegtled_gennem).",
               paste(conflicts, collapse = ", ")))
}

# F6: DATA-aware idempotens-guard (IKKE change_set-eksistens).
# BEGRUNDELSE (dual-review 2026-07-05, opdateret #124 2026-07-30): en guard
# på change_set-EKSISTENS er skrøbelig over for reset-semantikken (før #124
# overlevede change_set en reset; efter #124 tømmes den med) — mens
# slaegtled_lokal/slaegtled_gennem/kuld altid nulstilles til NULL ved reload.
# En eksistens-guard ville før #124 BLOKERE gen-anvendelse efter reset-reload
# selvom generationsdataen reelt var væk — featuren forsvinder tavst.
# Tjek i stedet om generationsdata FAKTISK findes for den
# resolverede source_id; spring kun over (stop) hvis data allerede er der.
# change_set oprettes stadig ved anvendelse (bevarer fortryd-evnen).
# NOTE: wiring ind i post_load_fixup.R (med dens egen transaktions-isolation)
# er UDSKUDT til et separat trin — dette script gøres her blot reload-sikkert
# som standalone.
existing <- q(sprintf(
  "SELECT count(*) AS n FROM person_external_id WHERE source_id=%d AND slaegtled_lokal IS NOT NULL",
  sid))$n[[1]]
if (existing > 0) {
  stop(sprintf("Generationsdata findes allerede for source_id=%s (%d rækker med slaegtled_lokal sat). Spring over, eller fortryd relevant change_set først.",
               sid, existing))
}

dbBegin(con)
ok <- tryCatch({
  cs <- dbGetQuery(con, "SELECT begin_change_set('backfill_slaegtled', 'Slægtled+kuld fra DAA-stamtavle')")[[1]]
  matched <- 0
  # F5.2: track pr. INPUT-nøgle (linje,nr), ikke kun total. Én input-nøgle
  # kan matche FLERE db-rækker (15a+15b deler nr=15, men er separate
  # person_external_id-rækker) — så `matched` (sum af påvirkede db-rækker)
  # kan OVERSTIGE nrow(rows), hvilket maskerede reelle misses i den gamle
  # `matched < nrow(rows)`-advarsel. Den reelle mis-signal er en nøgle der
  # matchede NUL rækker (typisk forkert source_id-opløsning).
  key_matched <- setNames(rep(0L, length(unique(key))), unique(key))
  for (i in seq_len(nrow(rows))) {
    n <- dbExecute(con,
      "UPDATE person_external_id
          SET slaegtled_lokal=$1, slaegtled_gennem=$2, kuld=$3
        WHERE source_id=$4 AND linje=$5 AND nr=$6",
      params = list(rows$slaegtled_lokal[i],
                    rows$slaegtled_gennem[i],
                    rows$kuld[i],
                    sid, rows$linje[i], rows$nr[i]))
    matched <- matched + n
    key_matched[key[i]] <- key_matched[key[i]] + n
  }
  cat(sprintf("[backfill] %d person_external_id-rækker opdateret\n", matched))
  zero_keys <- names(key_matched)[key_matched == 0]
  if (length(zero_keys)) {
    preview <- paste(head(zero_keys, 10), collapse = ", ")
    cat(sprintf("[backfill] ADVARSEL: %d (linje,nr)-nøgler matchede ingen rækker — tjek source_id-opløsning (%s%s)\n",
                length(zero_keys), preview, if (length(zero_keys) > 10) ", ..." else ""))
  }
  cs
}, error = function(e) { dbRollback(con); stop(e) })
dbCommit(con)
cat(sprintf("[backfill] Færdig. change_set id=%s (fortryd: SELECT red_fortryd_change_set(%s);)\n", ok, ok))
