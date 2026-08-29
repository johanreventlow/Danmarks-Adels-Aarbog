#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !identical(args[[1L]], "--output-dir")) {
  stop("USAGE: export_narrative_record_cutover.R --output-dir ABSOLUTE_0700_DIRECTORY", call. = FALSE)
}

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
source(file.path(dirname(script_path), "export_narrative_record_cutover_helpers.R"))

required <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
profile <- Sys.getenv(required, unset = NA_character_)
names(profile) <- required
profile <- nrk_validate_pg_profile(profile)

connection <- DBI::dbConnect(
  RPostgres::Postgres(), dbname = profile$PGDATABASE, host = profile$PGHOST,
  port = as.integer(profile$PGPORT), user = profile$PGUSER,
  password = profile$PGPASSWORD
)
on.exit(DBI::dbDisconnect(connection), add = TRUE)
active <- FALSE
gateway <- list(
  begin = function() {
    DBI::dbBegin(connection)
    active <<- TRUE
  },
  query = function(sql, params = list()) {
    if (startsWith(trimws(sql), "SET ")) {
      DBI::dbExecute(connection, sql)
      return(data.frame())
    }
    if (length(params)) DBI::dbGetQuery(connection, sql, params = params)
    else DBI::dbGetQuery(connection, sql)
  },
  commit = function() {
    DBI::dbCommit(connection)
    active <<- FALSE
  },
  rollback = function() {
    DBI::dbRollback(connection)
    active <<- FALSE
  },
  active = function() active
)

result <- nrk_export_run(gateway, args[[2L]])
writeLines(jsonlite::toJSON(list(
  status = "published", database = result$database, hashes = result$hashes
), auto_unbox = TRUE, pretty = TRUE))
