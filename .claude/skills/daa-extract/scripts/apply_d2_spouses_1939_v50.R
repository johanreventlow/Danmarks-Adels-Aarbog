#!/usr/bin/env Rscript
## CLI: Rscript apply_d2_spouses_1939_v50.R --selection PATH --jeg-mener-det
##   [--expect-sha256 HEX]
##
## SKRIVER TIL PRODUKTION. Kalder red_publicer_personer EEN gang med
## person-id'erne fra eksporten. Ingen retry: gaar det galt, stopper vi og
## undersoeger.
##
## --jeg-mener-det er obligatorisk, og ukendte flag afvises. Baggrund: i fase
## D1 blev et opfundet --dryrun ignoreret, og 68 personer blev publiceret uden
## godkendelse.
##
## Alt skrivearbejde sker i EEN transaktion, og efterkontrollen koerer inde i
## den: afviger et tal, rulles der tilbage. Planen lagde efterkontrollen efter
## commit, hvor den kun kunne melde en allerede sket aendring.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_d2_spouses_1939_v50_helpers.R"))

parsed <- d2_parse_apply_args(args)
if (!file.exists(parsed$selection)) stop("D2_APPLY_SELECTION_MISSING", call. = FALSE)
if (!is.na(parsed$expect_sha256)) {
  ## file= hasher filens bytes og matcher derfor `shasum -a 256` fra eksporten.
  ## digest(<streng>, serialize=FALSE) ville hashe indholdet som streng og
  ## kunne afvige paa afsluttende newline -- brug IKKE den form her.
  actual <- digest::digest(file = parsed$selection, algo = "sha256")
  if (!identical(actual, parsed$expect_sha256))
    stop("D2_APPLY_SELECTION_SHA_MISMATCH", call. = FALSE)
}
doc <- jsonlite::fromJSON(parsed$selection, simplifyVector = FALSE)

## red_publicer_personer gates paa current_rolle()='redaktion', som udledes af
## profiles WHERE id = auth.uid(). Over en direkte forbindelse er auth.uid()
## NULL -> rollen bliver 'medlem' og RPC'en kaster. Aktoeren saettes derfor
## inde i transaktionen, praecis som fase B's og D1's apply-SQL, og rollen
## verificeres mod profiles foer der skrives.
REDAKTOER_UUID <- "ba4ce28d-42a0-48af-a47c-773c26934236"

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

taellinger <- function() {
  r <- DBI::dbGetQuery(con, "
    SELECT (SELECT count(*) FROM person WHERE staged) AS staged,
           (SELECT count(*) FROM person)              AS person,
           (SELECT count(*) FROM fact)                AS fact,
           (SELECT count(*) FROM relation)            AS relation,
           (SELECT count(*) FROM narrative)           AS narrative")
  list(staged = r$staged[[1L]], person = r$person[[1L]], fact = r$fact[[1L]],
       relation = r$relation[[1L]], narrative = r$narrative[[1L]])
}

live_valgte_sql <- "
  SELECT count(*) AS n FROM person p
   WHERE p.staged AND EXISTS (
     SELECT 1 FROM family_member f1
       JOIN family_member f2 ON f2.family_id=f1.family_id
                            AND f2.person_id<>p.id AND f2.rolle='partner'
       JOIN person a ON a.id=f2.person_id
      WHERE f1.person_id=p.id AND f1.rolle='partner' AND NOT a.staged)"

## Rollback er EKSPLICIT i en tryCatch frem for on.exit: on.exit paa et
## scripts topniveau har ingen funktions-frame at haenge paa. Postgres ville
## ganske vist rulle tilbage ved en brat disconnect, men vi vil ikke laene os
## op ad det naar transaktionen skriver til prod.
DBI::dbBegin(con)
resultat <- tryCatch({
  foer <- taellinger()
  live_valgte <- DBI::dbGetQuery(con, live_valgte_sql)$n[[1L]]
  plan <- d2_plan_apply(doc, list(staged_i_alt = foer$staged, valgte = live_valgte))

  ## Alle valgte SKAL stadig vaere staged; ellers er eksporten foraeldet.
  stadig_staged <- DBI::dbGetQuery(con,
    "SELECT count(*) AS n FROM person WHERE staged AND id = ANY($1::bigint[])",
    params = list(d2_pg_bigint_array(plan$ids)))$n[[1L]]
  if (!identical(as.numeric(stadig_staged), as.numeric(length(plan$ids))))
    stop("D2_APPLY_SELECTION_NOT_STAGED", call. = FALSE)

  DBI::dbExecute(con, "SELECT set_config('request.jwt.claim.sub', $1, true)",
                 params = list(REDAKTOER_UUID))
  rolle <- DBI::dbGetQuery(con, "SELECT rolle FROM profiles WHERE id = $1::uuid",
                           params = list(REDAKTOER_UUID))
  if (nrow(rolle) != 1L || !identical(rolle$rolle[[1L]], "redaktion"))
    stop("D2_APPLY_ACTOR_NOT_REDAKTION", call. = FALSE)

  rpc <- DBI::dbGetQuery(con,
    "SELECT red_publicer_personer($1::bigint[])::text AS resultat",
    params = list(d2_pg_bigint_array(plan$ids)))

  efter <- taellinger()
  d2_check_postcheck(foer, efter, plan$forventet_bagefter)

  ## change_set-id'et hoerer i changelog'en; hentes mens vi stadig er i
  ## transaktionen, saa det er RPC'ens eget og ikke en senere koersels.
  cs <- DBI::dbGetQuery(con, "SELECT max(id) AS id FROM change_set")$id[[1L]]

  DBI::dbCommit(con)
  list(rpc = rpc$resultat[[1L]], foer = foer$staged, efter = efter$staged, change_set = cs)
}, error = function(e) {
  try(DBI::dbRollback(con), silent = TRUE)
  stop(conditionMessage(e), call. = FALSE)
})

cat(resultat$rpc, "\n")
cat(sprintf("change_set=%s\n", resultat$change_set))
cat(sprintf("OK: staged %d -> %d (person/fact/relation/narrative uaendret)\n",
            resultat$foer, resultat$efter))
