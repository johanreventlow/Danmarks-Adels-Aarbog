#!/usr/bin/env Rscript
## CLI: Rscript apply_c0_followup_1939_v50.R --manifest PATH
##   --expect-sha256 HEX --backup DUMP --jeg-mener-det
##
## SKRIVER TIL PRODUKTION. Erstatter narrativtekst og opretter bindinger for
## de accepterede koblinger. EEN transaktion, ingen retry.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "apply_c0_followup_1939_v50_helpers.R"))

parsed <- c0f_parse_apply_args(args)
if (!file.exists(parsed$manifest)) stop("C0F_APPLY_MANIFEST_MISSING", call. = FALSE)
{
  ## file= hasher filens bytes og matcher `shasum -a 256`.
  actual <- digest::digest(file = parsed$manifest, algo = "sha256")
  if (!identical(actual, parsed$expect_sha256))
    stop("C0F_APPLY_MANIFEST_SHA_MISMATCH", call. = FALSE)
}
if (!file.exists(parsed$backup)) stop("C0F_APPLY_BACKUP_MISSING", call. = FALSE)
if (file.info(parsed$backup)$size < 1e6) stop("C0F_APPLY_BACKUP_TOO_SMALL", call. = FALSE)
backup_sha <- digest::digest(file = parsed$backup, algo = "sha256")
manifest <- jsonlite::fromJSON(parsed$manifest, simplifyVector = FALSE)

## Begge RPC'er gates paa current_rolle()='redaktion', som udledes af
## profiles WHERE id = auth.uid(). Over en direkte forbindelse er auth.uid()
## NULL -> rollen bliver 'medlem' og kaldet kastes.
REDAKTOER_UUID <- "ba4ce28d-42a0-48af-a47c-773c26934236"
ADVISORY_LOCK_KEY <- "daa-1939-v50-production-writer"

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

pg_bigint_array <- function(x) paste0("{", paste(as.integer(x), collapse = ","), "}")
ids <- vapply(manifest$operations, function(o) as.integer(o$person_id), integer(1))

taellinger <- function() {
  r <- DBI::dbGetQuery(con, "
    SELECT (SELECT count(*) FROM private.narrative_record_publication) AS bindinger,
           (SELECT count(*) FROM narrative) AS narrativer,
           (SELECT count(*) FROM person)    AS personer,
           (SELECT count(*) FROM fact)      AS fakta,
           (SELECT count(*) FROM relation)  AS relationer")
  list(bindinger = r$bindinger[[1L]], narrativer = r$narrativer[[1L]],
       personer = r$personer[[1L]], fakta = r$fakta[[1L]], relationer = r$relationer[[1L]])
}

## Rollback er EKSPLICIT i en tryCatch frem for on.exit: on.exit paa et
## scripts topniveau har ingen funktions-frame at haenge paa.
DBI::dbBegin(con)
resultat <- tryCatch({
  ## Advisory lock: samme noegle som fase B, saa to writers ikke kan koere
  ## samtidig mod den samme bestand.
  laas <- DBI::dbGetQuery(con, "SELECT pg_try_advisory_xact_lock(hashtext($1)) AS ok",
                          params = list(ADVISORY_LOCK_KEY))
  if (!isTRUE(laas$ok[[1L]])) stop("C0F_APPLY_LOCK_BUSY", call. = FALSE)

  foer <- taellinger()
  live_rows <- DBI::dbGetQuery(con, "
    SELECT n.subjekt_id AS person_id, n.id AS narrative_id,
           encode(extensions.digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex') AS old_sha,
           n.privat, n.side,
           (SELECT count(*) FROM private.narrative_record_publication b
             WHERE b.narrative_id = n.id) AS bundet
      FROM narrative n
     WHERE n.subjekt_type='person' AND n.source_id=3
       AND n.subjekt_id = ANY($1::bigint[])
     ORDER BY n.subjekt_id", params = list(pg_bigint_array(ids)))

  ident <- DBI::dbGetQuery(con,
    "SELECT current_database() AS database_name,
            (pg_control_system()).system_identifier::text AS database_identity")
  plan <- c0f_plan_apply(manifest, list(
    narrative_ids = live_rows$narrative_id, old_shas = live_rows$old_sha,
    privat = live_rows$privat, sider = live_rows$side,
    bindinger = sum(as.numeric(live_rows$bundet)),
    database_name = ident$database_name[[1L]],
    database_identity = ident$database_identity[[1L]]))

  DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub', $1, true)",
                  params = list(REDAKTOER_UUID))
  rolle <- DBI::dbGetQuery(con, "SELECT rolle FROM profiles WHERE id = $1::uuid",
                           params = list(REDAKTOER_UUID))
  if (nrow(rolle) != 1L || !identical(rolle$rolle[[1L]], "redaktion"))
    stop("C0F_APPLY_ACTOR_NOT_REDAKTION", call. = FALSE)
  ## Ovenstaaende beviser kun at profiles-rækken findes og siger 'redaktion'
  ## -- ikke at set_config rent faktisk naaede auth.uid() i DENNE transaktion.
  ## current_rolle() er den samme funktion RPC'erne selv gater paa.
  gate <- DBI::dbGetQuery(con, "SELECT current_rolle() AS rolle")
  if (nrow(gate) != 1L || !identical(gate$rolle[[1L]], "redaktion"))
    stop("C0F_APPLY_GATE_NOT_OPEN", call. = FALSE)

  for (op in plan$operations) {
    ## p_side = NULL: RPC'ens UPDATE-gren skriver side = COALESCE(p_side, side),
    ## saa NULL bevarer det eksisterende. Efterkoerslen retter tekst, ikke sidetal.
    nid <- DBI::dbGetQuery(con,
      "SELECT red_upsert_narrativ('person', $1::bigint, $2::text, false, 3, NULL) AS id",
      params = list(as.integer(op$person_id), op$new_text))$id[[1L]]
    if (!identical(as.numeric(nid), as.numeric(op$narrative_id)))
      stop(paste0("C0F_APPLY_NARRATIVE_ID_DRIFT:", op$person_id), call. = FALSE)

    src <- DBI::dbGetQuery(con,
      "SELECT id FROM private.source_record WHERE record_key = $1",
      params = list(op$source_record_key))
    if (nrow(src) != 1L)
      stop(paste0("C0F_APPLY_SOURCE_RECORD_MISSING:", op$source_record_key), call. = FALSE)

    DBI::dbGetQuery(con,
      "SELECT red_publicer_narrative_record($1::bigint, $2::uuid, $3::text, $4::text) AS id",
      params = list(as.integer(op$narrative_id), src$id[[1L]],
                    op$source_record_key,
                    sprintf("DAA 1939 side %d", as.integer(op$page_from))))
  }

  efter <- taellinger()
  c0f_check_postcheck(foer, efter, plan$forventet_bindinger)
  cs <- DBI::dbGetQuery(con, "SELECT max(id) AS id FROM change_set")$id[[1L]]

  ## Taber vi forbindelsen EFTER commit, men foer svaret naar frem, er
  ## tilstanden UKENDT -- ikke delvis, men uafgjort.
  tryCatch(DBI::dbCommit(con), error = function(e)
    stop(paste0("C0F_APPLY_COMMIT_UKENDT: prod kan VAERE aendret. ",
                "Verificer bindings-antallet foer du overvejer at koere igen. ",
                "Underliggende: ", conditionMessage(e)), call. = FALSE))
  list(n = length(plan$operations), foer = foer$bindinger, efter = efter$bindinger,
       change_set = cs)
}, error = function(e) {
  if (!grepl("C0F_APPLY_COMMIT_UKENDT", conditionMessage(e), fixed = TRUE))
    try(DBI::dbRollback(con), silent = TRUE)
  stop(conditionMessage(e), call. = FALSE)
})

cat(sprintf("change_set=%s\n", resultat$change_set))
cat(sprintf("backup=%s sha256=%s\n", parsed$backup, backup_sha))
cat(sprintf("OK: %d koblinger; bindinger %d -> %d\n",
            resultat$n, resultat$foer, resultat$efter))
