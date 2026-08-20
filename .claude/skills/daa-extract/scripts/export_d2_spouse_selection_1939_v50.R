#!/usr/bin/env Rscript
## CLI: Rscript export_d2_spouse_selection_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY udvaelgelse af fase D2: de staged gift-ind-aegtefaeller hvis
## partner allerede er synlig.
##
## Udvaelgelsen bygger paa ET objektivt praedikat, aldrig paa navne:
##   person.staged AND der findes en partner i samme family som IKKE er staged.
## Navnematchning er bevidst udeladt: i en adelsslaegt genbruges fornavne i
## hver generation.
##
## Skriver aldrig til databasen; kalder ingen RPC.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("D2_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("D2_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("D2_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("D2_EXPORT_SELECTION_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags)
  value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_d2_spouse_selection_1939_v50_helpers.R"))

## C0's uafklarede person-id'er pr. 2026-08-19 -- samme liste som D1's
## eksportoer. En af dem i udvalget ville betyde at D2 publicerer noget, en
## anden fase endnu ikke har afgjort.
C0_UAFKLAREDE <- c(929, 930, 974, 977, 991, 1013, 1014, 1017, 1021, 1028,
                   1138, 1220, 1239, 1241, 1243, 1291)

## Postgres array-literal. En laengde-n R-vektor bundet til ÉN placeholder
## bliver af DBI/RPostgres laest som n PARAMETERSAET, ikke som én array-vaerdi
## -- derfor bygges literalen som tekst og bindes som én skalar. Samme moenster
## som narrative_replacement_pg_bigint_array.
d2_pg_bigint_array <- function(x) paste0("{", paste(as.integer(x), collapse = ","), "}")

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable"
            else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE")
            else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

## Samme identitets-udtryk som D1's eksportoer. current_setting('cluster_name')
## er NULL paa Supabase, saa md5-varianten ville give `null` i JSON'en.
identity <- DBI::dbGetQuery(con,
  "SELECT current_database() AS database_name,
          (pg_control_system()).system_identifier::text AS database_identity")
database_name <- identity$database_name[[1L]]
if (!is.na(expect_database_name) && !identical(database_name, expect_database_name))
  stop(paste0("D2_EXPORT_SELECTION_DATABASE_MISMATCH:observed=", database_name,
              ":expected=", expect_database_name), call. = FALSE)

selection_sql <- "
WITH s AS (
  SELECT p.id AS person_id, p.visning_navn,
         (SELECT min(f2.person_id) FROM family_member f1
            JOIN family_member f2 ON f2.family_id=f1.family_id
                                 AND f2.person_id<>p.id AND f2.rolle='partner'
            JOIN person a ON a.id=f2.person_id AND NOT a.staged
           WHERE f1.person_id=p.id AND f1.rolle='partner') AS partner_id
    FROM person p
   WHERE p.staged AND EXISTS (
     SELECT 1 FROM family_member f1
       JOIN family_member f2 ON f2.family_id=f1.family_id
                            AND f2.person_id<>p.id AND f2.rolle='partner'
       JOIN person a ON a.id=f2.person_id
      WHERE f1.person_id=p.id AND f1.rolle='partner' AND NOT a.staged)
)
SELECT s.person_id, s.visning_navn, s.partner_id,
       EXISTS (SELECT 1 FROM relation r
                WHERE r.rolle='samme_som'
                  AND ((r.subjekt_type='person' AND r.subjekt_id=s.person_id)
                    OR (r.objekt_type='person'  AND r.objekt_id =s.person_id))) AS har_samme_som
  FROM s ORDER BY s.person_id"
selected_rows <- DBI::dbGetQuery(con, selection_sql)
if (nrow(selected_rows) == 0L) stop("D2_SELECTION_EMPTY", call. = FALSE)

## Simulér RPC'ens EGEN WHERE-klausul, saa 'ekstra medrevne' kan maales foer
## apply. Praedikatet filtrerer bevidst ikke paa rolle -- det goer RPC'en heller
## ikke, og det er netop faelden vi vil se.
ids <- selected_rows$person_id
swept <- DBI::dbGetQuery(con, "
  SELECT count(*) AS n FROM person p
   WHERE p.staged = true
     AND (p.id = ANY($1::bigint[])
       OR EXISTS (SELECT 1 FROM family_member fm1
                    JOIN family_member fm2 ON fm2.family_id = fm1.family_id
                   WHERE fm1.person_id = p.id AND fm2.person_id = ANY($1::bigint[])))",
  params = list(d2_pg_bigint_array(ids)))

staged_total <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM person WHERE staged")$n[[1L]]

counts <- list(
  valgte          = as.numeric(nrow(selected_rows)),
  staged_i_alt    = as.numeric(staged_total),
  staged_bagefter = as.numeric(staged_total) - as.numeric(swept$n[[1L]]),
  ekstra_medrevne = as.numeric(swept$n[[1L]]) - as.numeric(nrow(selected_rows)),
  overlap_c0      = as.numeric(length(intersect(ids, C0_UAFKLAREDE))))

doc <- build_d2_spouse_selection_1939_v50(
  selected_rows, counts, database_name, identity$database_identity[[1L]],
  "export_d2_spouse_selection_1939_v50.R")

writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE, null = "null"), output)
cat(sprintf("valgte=%d staged_i_alt=%d staged_bagefter=%d ekstra_medrevne=%d overlap_c0=%d\n",
            counts$valgte, counts$staged_i_alt, counts$staged_bagefter,
            counts$ekstra_medrevne, counts$overlap_c0))
