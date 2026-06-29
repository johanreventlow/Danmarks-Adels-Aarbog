# Trin 2: read-only pull fra Supabase. Kun funktions-definitioner.

connect_readonly <- function() {
  host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER")
  pw   <- Sys.getenv("SUPABASE_PASSWORD")
  if (host == "" || user == "" || pw == "")
    stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron (read-only rolle anbefales).")
  con <- DBI::dbConnect(RPostgres::Postgres(), host = host, user = user, password = pw,
                        dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                        port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                        sslmode = "require")
  DBI::dbExecute(con, "SET default_transaction_read_only = on")
  con
}

assert_readonly <- function(con) {
  ok <- tryCatch({
    DBI::dbExecute(con, "CREATE TEMP TABLE _ro_probe(x int)"); FALSE
  }, error = function(e) TRUE)
  if (!ok) stop("Forbindelsen er IKKE read-only — afbryd (least-privilege krav).")
  invisible(TRUE)
}

ours_birth_death_sql <- function() {
  paste(
    "SELECT f.subjekt_id AS person_id, f.faktatype,",
    "       a.date_min, a.date_max, a.date_raw",
    "FROM fact f",
    "JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id",
    "JOIN assertion  a ON a.id=c.valgt_assertion_id",
    "WHERE f.subjekt_type='person' AND f.faktatype IN ('fødsel','død')"
  )
}

pull_ours <- function(con) {
  q <- function(s) DBI::dbGetQuery(con, s)
  list(
    person        = q("SELECT id, koen, visning_navn, visning_foedt, visning_doed, levende, privat FROM person"),
    external_id   = q("SELECT person_id, source_id, linje, nr FROM person_external_id"),
    family        = q("SELECT id, type FROM family"),
    family_member = q("SELECT family_id, person_id, rolle, ordinal, konfidens FROM family_member"),
    dates         = q(ours_birth_death_sql())
  )
}
