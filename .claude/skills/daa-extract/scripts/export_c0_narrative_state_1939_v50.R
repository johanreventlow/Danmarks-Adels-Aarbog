#!/usr/bin/env Rscript
## CLI: Rscript export_c0_narrative_state_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY eksport af hele source_id=3 (DAA 1939) person-narrativbestanden
## -- tekst, metadata og record-binding -- som fase C0's sammenligningsgrundlag.
## build_c0_record_linkage_1939_v50.py konsumerer den.
##
## `har_record_binding` er C0's proxy for »teksten er stadig gammel«: fase B
## gav hver erstattet biografi en binding i private.narrative_record_publication.
## Proxyen SKAL efterproeves mod den empiriske gammel-tekst-liste, foer
## lukningen bygges paa den (planens Task 1, step 6b).
##
## Skriver aldrig til databasen; kalder ingen RPC; ingen actor/JWT-kontekst
## noedvendig (en almindelig SELECT, ikke en autentificeret skrivevej).
##
## `--expect-database-name` er en valgfri sikkerhedskontrol: er den angivet,
## afbrydes scriptet FOER forespoergslen, hvis `current_database()` ikke
## matcher -- vaern mod at pege denne mod en forkert lokal Postgres.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("C0_EXPORT_NARRATIVE_STATE_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("C0_EXPORT_NARRATIVE_STATE_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("C0_EXPORT_NARRATIVE_STATE_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("C0_EXPORT_NARRATIVE_STATE_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags) value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_c0_narrative_state_1939_v50_helpers.R"))

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
  stop(paste0("C0_EXPORT_NARRATIVE_STATE_DATABASE_MISMATCH:observed=", database_name,
    ":expected=", expect_database_name), call. = FALSE)

## sha256() er ukvalificeret med vilje: den er indbygget i PG 17, i modsaetning
## til digest(), som fase B maatte skema-kvalificere fordi prods search_path
## mangler `extensions`.
sql_text <- paste(
  "SELECT n.subjekt_id AS person_id, p.visning_navn, p.staged,",
  "n.side, n.privat, n.tekst,",
  "encode(sha256(convert_to(n.tekst,'UTF8')),'hex') AS tekst_sha256,",
  "(b.narrative_id IS NOT NULL) AS har_record_binding,",
  "b.status AS binding_status",
  "FROM narrative n",
  "JOIN person p ON p.id = n.subjekt_id",
  "LEFT JOIN private.narrative_record_publication b ON b.narrative_id = n.id",
  "WHERE n.subjekt_type='person' AND n.source_id=3 ORDER BY n.subjekt_id"
)
rows <- DBI::dbGetQuery(con, sql_text)
rows$person_id <- as.numeric(rows$person_id)
rows$visning_navn <- as.character(rows$visning_navn)
rows$staged <- as.logical(rows$staged)
rows$side <- as.character(rows$side)
rows$privat <- as.logical(rows$privat)
rows$tekst <- as.character(rows$tekst)
rows$tekst_sha256 <- as.character(rows$tekst_sha256)
rows$har_record_binding <- as.logical(rows$har_record_binding)
rows$binding_status <- as.character(rows$binding_status)

doc <- build_c0_narrative_state_export_1939_v50(
  rows, database_name = database_name, database_identity = identity$system_identifier[[1L]],
  generator = "export_c0_narrative_state_1939_v50.R:v1", sql_text = sql_text
)
writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE), output, useBytes = TRUE)
