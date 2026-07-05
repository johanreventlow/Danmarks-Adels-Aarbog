#!/usr/bin/env Rscript
# Backfill af slægtled (lokal+gennemgående) + kuld til person_external_id.
# Join-nøgle: (source_id, linje, nr). NULL/ukendt linje karantænes (ikke matchet).
# Fortrydbart: ét change_set (operation='backfill_slaegtled'). Fortryd: red_fortryd_change_set(<id>).
# Kør EFTER db-migrations.sql (kolonner skal findes). Idempotent via guard.
suppressMessages({library(DBI); library(RPostgres); library(jsonlite)})

args <- commandArgs(trailingOnly = TRUE)
seg_path <- if (length(args)) args[[1]] else "/tmp/seg.json"
posts <- fromJSON(seg_path, simplifyDataFrame = TRUE)

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require")
on.exit(dbDisconnect(con), add = TRUE)
q  <- function(sql, p = list()) if (length(p)) dbGetQuery(con, sql, params = p) else dbGetQuery(con, sql)

# Resolvér DAA-stamtavle-kilden (den som person_external_id-rækkerne hovedsageligt bruger).
sid <- q("SELECT source_id, count(*) n FROM person_external_id
          GROUP BY source_id ORDER BY n DESC LIMIT 1")$source_id[[1]]
cat(sprintf("[backfill] source_id=%s\n", sid))

# Byg (linje,nr) -> (lokal,gennem,kuld); kun rækker med linje != NA og lokal != NA.
rows <- posts[!is.na(posts$linje) & !is.na(posts$slaegtled_lokal),
              c("linje","nr","slaegtled_lokal","slaegtled_gennem","kuld")]
quarantined <- sum(is.na(posts$linje) & !is.na(posts$slaegtled_lokal))
cat(sprintf("[backfill] %d rækker med linje+lokal; %d karantænet (NULL linje)\n", nrow(rows), quarantined))

# Idempotens-guard.
already <- q("SELECT id FROM change_set WHERE operation='backfill_slaegtled' ORDER BY id LIMIT 1")
if (nrow(already)) stop(sprintf("Allerede anvendt som change_set %s. Fortryd først (red_fortryd_change_set(%s)).",
                                already$id[[1]], already$id[[1]]))

dbBegin(con)
ok <- tryCatch({
  cs <- dbGetQuery(con, "SELECT begin_change_set('backfill_slaegtled', 'Slægtled+kuld fra DAA-stamtavle')")[[1]]
  matched <- 0
  for (i in seq_len(nrow(rows))) {
    n <- dbExecute(con,
      "UPDATE person_external_id
          SET slaegtled_lokal=$1, slaegtled_gennem=$2, kuld=$3
        WHERE source_id=$4 AND linje=$5 AND nr=$6",
      params = list(rows$slaegtled_lokal[i],
                    if (is.na(rows$slaegtled_gennem[i])) NA else rows$slaegtled_gennem[i],
                    if (is.na(rows$kuld[i])) NA else rows$kuld[i],
                    sid, rows$linje[i], rows$nr[i]))
    matched <- matched + n
  }
  cat(sprintf("[backfill] %d person_external_id-rækker opdateret\n", matched))
  cs
}, error = function(e) { dbRollback(con); stop(e) })
dbCommit(con)
cat(sprintf("[backfill] Færdig. change_set id=%s (fortryd: SELECT red_fortryd_change_set(%s);)\n", ok, ok))
