#!/usr/bin/env Rscript
# =====================================================================
#  post_load_fixup.R — idempotente efter-load-korrektioner der IKKE bor i
#  load_daa.R's automatiske pipeline, men som ellers går tabt ved næste reload
#  (lineage-navne, redaktør-profil, identitets-links). Kør EFTER load_daa.R.
#
#  Brug:  Rscript .claude/skills/daa-extract/scripts/post_load_fixup.R
#  Login fra ~/.Renviron. Alt er idempotent (ON CONFLICT / eksistens-guards),
#  så gentagne kørsler er sikre. Par-opslag sker på (linje, nr) — IKKE på
#  person-id — så scriptet er reload-sikkert (id'er skifter ved reload).
#
#  Baggrund: en tidligere --reset kaskaderede gennem lineage + profiles; og
#  slægtslinje-grundlæggere optræder i DAA to gange (i oprindelses-linjen OG
#  som rod af den linje de grundlagde). De to poster er samme person og
#  forbindes med en 'samme_som'-relation (link, ikke merge — datamodel §9).
#  NB (app-lag): slægtskabsfinderen skal TRAVERSERE samme_som for at behandle
#  de to poster som én identitet — DB-kanten alene er ikke selv-eksekverende.
# =====================================================================
suppressMessages({library(DBI); library(jsonlite)})

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require", bigint = "integer")
ex <- function(sql, p = list()) if (length(p)) dbExecute(con, sql, params = p) else dbExecute(con, sql)
one <- function(sql, p = list()) { r <- if (length(p)) dbGetQuery(con, sql, params = p) else dbGetQuery(con, sql); if (nrow(r)) r[[1]][1] else NA }
nid <- function(t) as.integer(one(sprintf("SELECT COALESCE(MAX(id),0)+1 FROM %s", t)))

# Fail-closed source-resolution (Leverance 0, tværudgave-spec §7): ved 2+ DAA-udgaver må
# (linje,nr)-opslag og grundlægger-links IKKE ramme forkert udgaves person. Resolvér den
# specifikke udgave EKSPLICIT og STOP ved 0 eller 2+ kandidater (i stedet for ORDER BY id
# LIMIT 1, som stille valgte en vilkårlig udgave). Udgave kan overstyres som 1. argument.
udgave_arg <- commandArgs(TRUE)
udgave <- if (length(udgave_arg) >= 1 && !startsWith(udgave_arg[1], "--")) udgave_arg[1] else "DAA 2018-20"
src_rows <- dbGetQuery(con, "SELECT id FROM source WHERE udgave = $1", params = list(udgave))
if (nrow(src_rows) == 0) stop(sprintf("Ingen source med udgave='%s' — kør load_daa.R først.", udgave))
if (nrow(src_rows) > 1) stop(sprintf("Flere sources (%d) med udgave='%s' — tvetydigt, afbryder (fail-closed).", nrow(src_rows), udgave))
src <- as.integer(src_rows$id[1])
message(sprintf("post_load_fixup: source '%s' (id %s)", udgave, src))

dbBegin(con)
tryCatch({
  # IDENTITY-kontrakt (2026-07-31): nid() slår MAX(id)+1 op pr. kald — kræver
  # eksklusiv skrive-lås på de tabeller der allokeres til, ellers kan en
  # samtidig RPC's nextval tage samme id. Sync før commit nedenfor.
  # Rækkefølgen følger den KANONISKE låseorden (se load_daa.R id_tables):
  # lineage (forælder) → relation FØR assertion → citation → conclusion.
  ex("LOCK TABLE lineage, relation, assertion, citation, conclusion IN EXCLUSIVE MODE")
  # ---- 1) lineage-navne + families-efternavn (idempotent) ----
  # slaegtsnavn driver den udledte visning_efternavn/visning_fuldt_navn-cache (regen_person_visning,
  # udledt-slægtsnavn-design). Alle 5 linjer er Reventlow i dag — ingen forgrening (parent_lineage_id
  # er NULL for alle), så ét fælles efternavn er korrekt. Skift til pr.-linje-værdi hvis/når en gren
  # adles til et andet navn (jf. spec §6 gren-variant, bevidst udskudt).
  lineage <- list(I="Den holstenske linje", II="Linjen Gallentin", III="Den mecklenburgske linje",
                  IV="Den lensgrevelige linje af 1767", V="Den grevelige linje af 1673")
  for (kode in names(lineage))
    ex("INSERT INTO lineage (id, source_id, kode, navn, slaegtsnavn) VALUES ($1,$2,$3,$4,'Reventlow')
        ON CONFLICT (source_id, kode) DO UPDATE SET navn=EXCLUDED.navn, slaegtsnavn=EXCLUDED.slaegtsnavn",
       list(nid("lineage"), src, kode, lineage[[kode]]))

  # ---- 2) redaktør-profil (idempotent) ----
  ex("INSERT INTO profiles (id, rolle, email)
      VALUES ('ba4ce28d-42a0-48af-a47c-773c26934236','redaktion','johan@reventlow.dk')
      ON CONFLICT (id) DO UPDATE SET rolle='redaktion', email=EXCLUDED.email")

  # ---- 3) 'samme_som'/'ikke_samme_som'-roller i vokabular (idempotent) ----
  ex("INSERT INTO vocab (scheme, code, label) VALUES ('rolle','samme_som','samme person som')
      ON CONFLICT (scheme, code) DO NOTHING")
  ex("INSERT INTO vocab (scheme, code, label) VALUES ('rolle','ikke_samme_som','bekræftet forskellig person fra')
      ON CONFLICT (scheme, code) DO NOTHING")

  # ---- 4) grundlægger-identitets-links (evidenslag, idempotent) ----
  # Par: (oprindelse i linje III, grundlægger som rod af ny linje). Opslag på
  # (linje, nr) -> aktuelt person-id. Bekræftet via TNG-crosswalk (samme tng_id).
  # source-filtreret (Leverance 0): ved 2+ udgaver kan (linje,nr) matche forkert udgaves
  # person — bind opslaget til den resolverede udgaves source_id.
  pid_of <- function(linje, nr) one(
    "SELECT person_id FROM person_external_id WHERE linje=$1 AND nr=$2 AND source_id=$3", list(linje, nr, src))
  link_samme_som <- function(a_linje, a_nr, b_linje, b_nr, hvem) {
    a <- pid_of(a_linje, a_nr); b <- pid_of(b_linje, b_nr)
    if (is.na(a) || is.na(b)) { message(sprintf("  SPRING OVER %s: mangler %s-%s el. %s-%s", hvem, a_linje, a_nr, b_linje, b_nr)); return(invisible()) }
    # idempotens: findes en samme_som-relation allerede mellem de to (i en retning)?
    findes <- one("SELECT 1 FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
                   AND ((subjekt_id=$1 AND objekt_id=$2) OR (subjekt_id=$2 AND objekt_id=$1)) LIMIT 1", list(a, b))
    if (!is.na(findes)) { message(sprintf("  %s: link findes allerede (id%s<->id%s)", hvem, a, b)); return(invisible()) }
    rid <- nid("relation")
    ex("INSERT INTO relation (id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
        VALUES ($1,'person',$2,'person',$3,'samme_som')", list(rid, a, b))
    aid <- nid("assertion")
    ex("INSERT INTO assertion (id, target_type, target_id, vaerdi_tekst) VALUES ($1,'relation',$2,'samme_som')", list(aid, rid))
    ex("INSERT INTO citation (id, assertion_id, source_id, kvalitet, citat_tekst)
        VALUES ($1,$2,$3,'primær',$4)", list(nid("citation"), aid, src,
        sprintf("Grundlægger af ny linje; optræder i DAA både i oprindelses-linjen (%s-%s) og som rod (%s-%s). Bekræftet via TNG.", a_linje, a_nr, b_linje, b_nr)))
    ex("INSERT INTO conclusion (id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af)
        VALUES ($1,'relation',$2,$3,'afklaret','redaktionel identitetssammenkædning')", list(nid("conclusion"), rid, aid))
    message(sprintf("  %s: linket id%s (%s-%s) <-> id%s (%s-%s)", hvem, a, a_linje, a_nr, b, b_linje, b_nr))
  }
  message("grundlægger-links:")
  link_samme_som("III","58","V","1",  "Conrad de Reventlow (grundl. linje V)")
  link_samme_som("III","104","IV","1","Detlef de Reventlou (grundl. linje IV)")

  # Fail-closed sekvens-sync før commit (IDENTITY-kontrakt): tabeller uden
  # identity-sekvens (base før migrationen) er eneste lovlige undtagelse.
  for (t in c("lineage","relation","assertion","citation","conclusion")) {
    s <- one(sprintf("SELECT pg_get_serial_sequence('%s','id')", t))
    if (is.na(s) || is.null(s)) message(sprintf("sekvens-sync: %s uden identity — sprunget over", t))
    else ex(sprintf("SELECT setval('%s', (SELECT coalesce(max(id),0)+1 FROM %s), false)", s, t))
  }
  dbCommit(con); message("post_load_fixup: OK")
}, error = function(e) { dbRollback(con); dbDisconnect(con); stop("fixup fejlede, rullet tilbage: ", conditionMessage(e)) })

# ---- 5) generations-backfill (reload-durabel, SUBPROCES-ISOLERET) ----
# slægtled+kuld på person_external_id tømmes ved --force-reset (kolonnerne findes, men
# er NULL). Kør backfill_slaegtled.R som separat proces (egen forbindelse + change_set-
# transaktion) så en fejl her ALDRIG kan rulle post_load_fixup's egen commit ovenfor
# tilbage — den samme delte-transaktions-fælde som gjorde standalone-change_set-guarden
# uegnet (dual-review 2026-07-05, [[flere-foraeldre-datafix]]-mønster). Pre-check på den
# allerede-åbne forbindelse springer subprocessen over når data allerede er udfyldt.
tryCatch({
  already <- one("SELECT count(*) FROM person_external_id WHERE slaegtled_lokal IS NOT NULL")
  if (!is.na(already) && already > 0) {
    message(sprintf("  generations-backfill: allerede anvendt (%s rækker) — sprunget over", already))
  } else {
    script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
    seg_script <- file.path(script_dir, "segment.py")
    backfill   <- file.path(script_dir, "backfill_slaegtled.R")
    repo_root  <- normalizePath(file.path(script_dir, "..", "..", "..", ".."), mustWork = FALSE)
    raw_txt    <- Sys.getenv("DAA_RAW_FULL", unset = file.path(repo_root, "work", "raw_full.txt"))
    seg_json   <- file.path(tempdir(), "seg-generations.json")
    if (!file.exists(raw_txt)) {
      message(sprintf("  generations-backfill SPRUNGET OVER: bogtekst ikke fundet (%s) — sæt DAA_RAW_FULL el. kør backfill_slaegtled.R manuelt", raw_txt))
    } else {
      if (system2("python3", c(shQuote(seg_script), shQuote(raw_txt)), stdout = seg_json, stderr = FALSE) != 0 || !file.exists(seg_json))
        stop("segment.py fejlede")
      rc <- system2("Rscript", c(shQuote(backfill), shQuote(seg_json)))
      if (rc != 0) stop(sprintf("backfill_slaegtled.R exit %s", rc))
      message("  generations-backfill: anvendt")
    }
  }
}, error = function(e) message(sprintf("  generations-backfill fejlede (post_load_fixup uberørt): %s", conditionMessage(e))))

cat("\n=== verifikation ===\n")
print(dbGetQuery(con, "SELECT count(*) lineage FROM lineage"))
print(dbGetQuery(con, "SELECT count(*) samme_som_links FROM relation WHERE rolle='samme_som'"))
dbDisconnect(con)
