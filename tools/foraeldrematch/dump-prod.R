#!/usr/bin/env Rscript
# Read-only dump af de tre datasæt collapseSameAs har brug for, så den RIGTIGE
# implementering kan køres mod prod-data i stedet for at blive genimplementeret
# i SQL. Skriver til tmp/ (gitignoreret). Rører intet i basen.

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(jsonlite)
})

con <- DBI::dbConnect(
  RPostgres::Postgres(),
  dbname = Sys.getenv("SUPABASE_DB", "postgres"),
  user = Sys.getenv("SUPABASE_USER"),
  password = Sys.getenv("SUPABASE_PASSWORD"),
  host = Sys.getenv("SUPABASE_HOST"),
  port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
  sslmode = "require"
)
on.exit(DBI::dbDisconnect(con), add = TRUE)

aar <- function(col) sprintf(
  "nullif(substring(%s from '(\\d{4})'), '')::int", col)

persons <- DBI::dbGetQuery(con, sprintf("
  select id::text as id,
         coalesce(visning_navn,'') as name,
         %s as born,
         %s as died,
         case when koen in ('mand','kvinde') then koen else null end as koen,
         coalesce(privat,false) as privat,
         coalesce(levende,false) as levende,
         coalesce(visning_foedt,'') as vis_foedt,
         coalesce(visning_doed,'') as vis_doed,
         coalesce(visning_titel,'') as vis_titel
  from person", aar("visning_foedt"), aar("visning_doed")))

members <- DBI::dbGetQuery(con, "
  select family_id::text as family_id, person_id::text as person_id, rolle
  from family_member")

sammesom <- DBI::dbGetQuery(con, "
  select subjekt_id::text as fra, objekt_id::text as til
  from relation
  where rolle='samme_som' and subjekt_type='person' and objekt_type='person'")

kilde <- DBI::dbGetQuery(con, "
  select person_id::text as person_id, source_id,
         coalesce(linje,'') as linje, nr
  from person_external_id where source_id in (1,3)")

out <- list(persons = persons, members = members,
            sammesom = sammesom, kilde = kilde)
jsonlite::write_json(out, "tmp/collapse-input.json", auto_unbox = TRUE, null = "null")

cat(sprintf("personer=%d family_member=%d samme_som=%d kilde-rækker=%d\n",
            nrow(persons), nrow(members), nrow(sammesom), nrow(kilde)))
