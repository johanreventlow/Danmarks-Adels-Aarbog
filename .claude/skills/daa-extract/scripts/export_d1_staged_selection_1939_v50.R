#!/usr/bin/env Rscript
## CLI: Rscript export_d1_staged_selection_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY udvaelgelse af fase D1's staged probander + forudsigelse af de
## partner-stubs som red_publicer_personer vil traekke med sig.
##
## Udvaelgelsen bygger paa TRE OBJEKTIVE KRITERIER, aldrig paa navne:
##   1. person.staged
##   2. har et 1939-narrativ (source_id=3)
##   3. narrativet har en 'published' binding i
##      private.narrative_record_publication (= fase A/B's kilderegnskab har
##      anerkendt posten)
## Navnematchning er bevidst udeladt: staged person 927 hedder »Henrik« og
## deler navn med otte synlige personer -- i en adelsslaegt genbruges fornavne
## i hver generation.
##
## Partner-forudsigelsen spejler RPC'ens EGEN WHERE-klausul (db-migrations.sql
## 2026-07-20), saa det forventede antal kan verificeres foer apply.
##
## Skriver aldrig til databasen; kalder ingen RPC.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("D1_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("D1_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("D1_EXPORT_SELECTION_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("D1_EXPORT_SELECTION_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags) value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_d1_staged_selection_1939_v50_helpers.R"))

## C0's uafklarede person-id'er pr. 2026-08-19 (kandidater i klasserne
## sammenlaegning / for_kort / gennemgang). En af dem i udvalget ville betyde
## at D1 publicerer noget, en anden fase endnu ikke har afgjort.
C0_UAFKLAREDE <- c(929, 930, 974, 977, 991, 1013, 1014, 1017, 1021, 1028,
                   1138, 1220, 1239, 1241, 1243, 1291)

env_or <- function(primary, fallback) {
  result <- Sys.getenv(primary)
  if (nzchar(result)) result else Sys.getenv(fallback)
}
con <- DBI::dbConnect(RPostgres::Postgres(),
  dbname = env_or("PGDATABASE", "SUPABASE_DB"), host = env_or("PGHOST", "SUPABASE_HOST"),
  port = as.integer(env_or("PGPORT", "SUPABASE_PORT")), user = env_or("PGUSER", "SUPABASE_USER"),
  password = env_or("PGPASSWORD", "SUPABASE_PASSWORD"),
  sslmode = if (nzchar(Sys.getenv("PGDATABASE"))) "disable" else if (nzchar(Sys.getenv("SUPABASE_SSLMODE"))) Sys.getenv("SUPABASE_SSLMODE") else "require",
  bigint = "integer")
on.exit(DBI::dbDisconnect(con), add = TRUE)

identity <- DBI::dbGetQuery(con,
  "SELECT current_database() AS database_name,(pg_control_system()).system_identifier::text AS system_identifier")
database_name <- identity$database_name[[1L]]
if (!is.na(expect_database_name) && !identical(database_name, expect_database_name))
  stop(paste0("D1_EXPORT_SELECTION_DATABASE_MISMATCH:observed=", database_name,
    ":expected=", expect_database_name), call. = FALSE)

sql_selected <- paste(
  "SELECT p.id AS person_id, p.visning_navn, n.side,",
  "(SELECT count(*) FROM fact f WHERE f.subjekt_type='person' AND f.subjekt_id=p.id) AS fakta,",
  "EXISTS (SELECT 1 FROM relation r JOIN person q",
  "        ON q.id = CASE WHEN r.subjekt_id=p.id THEN r.objekt_id ELSE r.subjekt_id END",
  "        WHERE r.rolle='samme_som'",
  "          AND ((r.subjekt_type='person' AND r.subjekt_id=p.id)",
  "            OR (r.objekt_type='person' AND r.objekt_id=p.id))",
  "          AND EXISTS (SELECT 1 FROM narrative n2 JOIN source s ON s.id=n2.source_id",
  "                      WHERE n2.subjekt_type='person' AND n2.subjekt_id=q.id",
  "                        AND s.aar=2020)) AS samme_som_2020,",
  "(SELECT string_agg(DISTINCT x.id::text, ',' ORDER BY x.id::text)",
  "   FROM family_member fm1 JOIN family_member fm2 ON fm2.family_id=fm1.family_id",
  "   JOIN person x ON x.id=fm2.person_id",
  "  WHERE fm1.person_id=p.id AND x.id<>p.id AND x.staged) AS partner_ids",
  "FROM person p",
  "JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "JOIN private.narrative_record_publication b",
  "  ON b.narrative_id=n.id AND b.status='published'",
  "WHERE p.staged ORDER BY p.id")

sql_partners <- paste(
  "WITH valgte AS (",
  "  SELECT p.id FROM person p",
  "  JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "  JOIN private.narrative_record_publication b",
  "    ON b.narrative_id=n.id AND b.status='published'",
  "  WHERE p.staged)",
  "SELECT p.id AS person_id, p.visning_navn,",
  "  (SELECT string_agg(DISTINCT v.id::text, ',' ORDER BY v.id::text)",
  "     FROM family_member fm1 JOIN family_member fm2 ON fm2.family_id=fm1.family_id",
  "     JOIN valgte v ON v.id=fm2.person_id WHERE fm1.person_id=p.id) AS via_person_ids",
  "FROM person p",
  "WHERE p.staged AND p.id NOT IN (SELECT id FROM valgte)",
  "  AND EXISTS (SELECT 1 FROM family_member fm1",
  "              JOIN family_member fm2 ON fm2.family_id=fm1.family_id",
  "              WHERE fm1.person_id=p.id AND fm2.person_id IN (SELECT id FROM valgte))",
  "ORDER BY p.id")

sql_counts <- paste(
  "SELECT (SELECT count(*) FROM person WHERE staged) AS staged_total,",
  "(SELECT count(*) FROM person p",
  "   JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "   LEFT JOIN private.narrative_record_publication b ON b.narrative_id=n.id",
  "  WHERE p.staged AND b.narrative_id IS NULL) AS blocked_no_binding,",
  "(SELECT count(DISTINCT p.id) FROM person p JOIN family_member fm ON fm.person_id=p.id",
  "  WHERE p.staged",
  "    AND NOT EXISTS (SELECT 1 FROM narrative n WHERE n.subjekt_type='person'",
  "                      AND n.subjekt_id=p.id AND n.source_id=3)",
  "    AND EXISTS (SELECT 1 FROM family_member fm2 JOIN person q ON q.id=fm2.person_id",
  "                WHERE fm2.family_id=fm.family_id AND q.id<>p.id AND NOT q.staged))",
  "  AS spouses_visible_partner")

## Kontrol: RPC'ens EGEN WHERE-klausul, koert mod udvalget. Beviser at
## forudsigelsen er aekvivalent med det UPDATE'et faktisk vil ramme -- i
## stedet for at antage det.
sql_rpc_effect <- paste(
  "WITH valgte AS (",
  "  SELECT p.id FROM person p",
  "  JOIN narrative n ON n.subjekt_type='person' AND n.subjekt_id=p.id AND n.source_id=3",
  "  JOIN private.narrative_record_publication b",
  "    ON b.narrative_id=n.id AND b.status='published'",
  "  WHERE p.staged),",
  "ids AS (SELECT array_agg(id) AS a FROM valgte)",
  "SELECT count(*) AS rpc_ville_afstage FROM person p, ids",
  "WHERE p.staged = true",
  "  AND (p.id = ANY(ids.a)",
  "    OR EXISTS (SELECT 1 FROM family_member fm1",
  "               JOIN family_member fm2 ON fm2.family_id = fm1.family_id",
  "               WHERE fm1.person_id = p.id AND fm2.person_id = ANY(ids.a)))")

selected <- DBI::dbGetQuery(con, sql_selected)
partners <- DBI::dbGetQuery(con, sql_partners)
counts_row <- DBI::dbGetQuery(con, sql_counts)
rpc_effect <- DBI::dbGetQuery(con, sql_rpc_effect)$rpc_ville_afstage[[1L]]

overlap <- intersect(selected$person_id, C0_UAFKLAREDE)
if (length(overlap) > 0L)
  stop(paste0("D1_EXPORT_SELECTION_C0_OVERLAP:", paste(overlap, collapse = ",")),
       call. = FALSE)

## Forudsigelsen SKAL matche RPC'ens egen klausul. Afviger de, er der en
## familie-kant vi ikke kender, og apply ville publicere personer ingen har
## godkendt.
predicted_total <- nrow(selected) + nrow(partners)
if (!identical(as.integer(rpc_effect), as.integer(predicted_total)))
  stop(paste0("D1_EXPORT_SELECTION_RPC_EFFECT_MISMATCH:rpc=", rpc_effect,
    ":forudsagt=", predicted_total), call. = FALSE)

counts <- list(
  staged_total = as.integer(counts_row$staged_total[[1L]]),
  selected = nrow(selected),
  predicted_partners = nrow(partners),
  expected_unstaged_total = as.integer(predicted_total),
  rpc_effect_verified = as.integer(rpc_effect),
  blocked_no_binding = as.integer(counts_row$blocked_no_binding[[1L]]),
  spouses_visible_partner = as.integer(counts_row$spouses_visible_partner[[1L]])
)

doc <- build_d1_staged_selection_1939_v50(
  selected, partners, counts,
  database_name = database_name, database_identity = identity$system_identifier[[1L]],
  generator = "export_d1_staged_selection_1939_v50.R:v1")
writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE), output, useBytes = TRUE)
