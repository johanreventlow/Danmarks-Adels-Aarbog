#!/usr/bin/env Rscript
suppressMessages({library(DBI); library(jsonlite); library(RPostgres)})

argv <- commandArgs(trailingOnly = TRUE)
out_path <- if (length(argv)) argv[[1]] else "work/haendelser/narrativer.json"

host <- Sys.getenv("SUPABASE_HOST")
user <- Sys.getenv("SUPABASE_USER")
pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") {
  stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
}

con <- dbConnect(
  RPostgres::Postgres(), host = host,
  port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
  dbname = Sys.getenv("SUPABASE_DB", "postgres"),
  user = user, password = pw, sslmode = Sys.getenv("SUPABASE_SSLMODE", "require"),
  bigint = "integer64"
)
on.exit(dbDisconnect(con), add = TRUE)

eligible_sql <- "
SELECT n.id AS narrative_id, n.subjekt_id, n.source_id, n.side, n.tekst,
       s.udgave, p.visning_navn
FROM narrative n
JOIN person p ON p.id = n.subjekt_id
LEFT JOIN source s ON s.id = n.source_id
WHERE n.subjekt_type = 'person'
  AND coalesce(n.privat, false) = false
  AND p.levende = false
  AND coalesce(p.privat, false) = false
  AND coalesce(p.staged, false) = false
ORDER BY n.id"

rows <- dbGetQuery(con, eligible_sql)
eligible_count <- dbGetQuery(con, paste0("SELECT count(*) AS n FROM (", eligible_sql, ") q"))$n[[1]]
if (nrow(rows) != eligible_count) stop("Eksporttælling afviger fra GDPR-queryens tælling.")

# Hård, uafhængig re-query af præcis outputmængden. Id'erne kommer fra DB som tal.
bad_count <- 0L
if (nrow(rows)) {
  ids <- paste(as.character(rows$narrative_id), collapse = ",")
  bad_sql <- sprintf(
    paste(
      "SELECT count(*) AS n FROM narrative n",
      "LEFT JOIN person p ON p.id=n.subjekt_id",
      "WHERE n.id IN (%s) AND (",
      "n.subjekt_type IS DISTINCT FROM 'person' OR coalesce(n.privat,false)",
      "OR p.id IS NULL OR p.levende IS DISTINCT FROM false",
      "OR coalesce(p.privat,false) OR coalesce(p.staged,false))"
    ), ids
  )
  bad_count <- dbGetQuery(con, bad_sql)$n[[1]]
}
if (bad_count != 0L) stop(sprintf("GDPR-SELVKONTROL FEJLEDE: %s forbudte narrativer i output.", bad_count))

dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
write_json(rows, out_path, dataframe = "rows", pretty = TRUE, auto_unbox = TRUE, na = "null")
message(sprintf("[export] %d offentlige afdøde-narrativer -> %s", nrow(rows), out_path))
