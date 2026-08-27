#!/usr/bin/env Rscript
## CLI: Rscript export_c0_followup_selection_1939_v50.R --output PATH
##   [--expect-database-name NAME]
##
## READ-ONLY. Henter de ni koblingspersoners nuvaerende 1939-narrativ:
## id, tekst-hash, privat-flag og side. Skriver aldrig; kalder ingen RPC.
args <- commandArgs(trailingOnly = TRUE)
allowed <- c("--output", "--expect-database-name")
flags <- args[grepl("^--", args)]
if (any(!flags %in% allowed) || anyDuplicated(flags))
  stop("C0F_EXPORT_CLI_INVALID", call. = FALSE)
if (!("--output" %in% flags)) stop("C0F_EXPORT_CLI_INVALID", call. = FALSE)
value <- function(flag) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
    stop("C0F_EXPORT_CLI_INVALID", call. = FALSE)
  args[[index + 1L]]
}
output <- value("--output")
if (file.exists(output)) stop("C0F_EXPORT_OUTPUT_EXISTS", call. = FALSE)
expect_database_name <- if ("--expect-database-name" %in% flags)
  value("--expect-database-name") else NA_character_

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "export_c0_followup_selection_1939_v50_helpers.R"))

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

identity <- DBI::dbGetQuery(con,
  "SELECT current_database() AS database_name,
          (pg_control_system()).system_identifier::text AS database_identity")
database_name <- identity$database_name[[1L]]
if (!is.na(expect_database_name) && !identical(database_name, expect_database_name))
  stop(paste0("C0F_EXPORT_DATABASE_MISMATCH:observed=", database_name,
              ":expected=", expect_database_name), call. = FALSE)

## extensions.digest: skema-kvalificeret, som fase B laerte (search_path
## gaelder ikke i alle kontekster).
rows <- DBI::dbGetQuery(con, "
  SELECT n.subjekt_id AS person_id, n.id AS narrative_id,
         encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS old_sha256,
         n.privat, n.side
    FROM narrative n
   WHERE n.subjekt_type='person' AND n.source_id=3
     AND n.subjekt_id = ANY('{963,967,978,991,992,1296,1297,1298,1299}'::bigint[])
   ORDER BY n.subjekt_id")

doc <- build_c0_followup_selection_1939_v50(
  rows, database_name, identity$database_identity[[1L]],
  "export_c0_followup_selection_1939_v50.R")

writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE, null = "null"), output)
cat(sprintf("valgte=%d privat=%d\n", length(doc$selected),
            sum(vapply(doc$selected, function(r) isTRUE(r$privat), logical(1)))))
