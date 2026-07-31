#!/usr/bin/env Rscript
# RETIRED 2026-07-31 (Codex-review restfund 6): engangs-korrektionen er udført
# (change_set 1, 2026-07-01) og scriptet opfylder ikke IDENTITY-kontrakten
# (MAX(id)+1 på family uden lås/sync). Bevaret som dokumentation; skal det
# nogensinde genbruges, kræves lås+sync-kontrakten fra load_daa.R først.
stop("fix_boern_multi_union.R er retired — korrektionen er allerede udført (change_set 1).")
# =====================================================================
#  fix_boern_multi_union.R — ENGANGS, VERSIONERET prod-korrektion.
#
#  Baggrund: load_daa.R hang tidligere ALLE børn af en flergift forælder på
#  forælderens FØRSTE union (fams[[1]]). Loaderen er nu rettet (match_barn_union,
#  load_helpers.R), men den allerede-loadede prod-base bærer stadig fejlen: børn
#  af 2./3./4. ægteskab sidder fejlagtigt på 1. ægteskab.
#
#  Dette script flytter hvert fejlplaceret barn til den union barnets eget
#  `aegteskab_kontekst` udpeger — via PRÆCIS SAMME matcher som loaderen, så de
#  ikke kan divergere. Kun ikke-første-ægteskabs-børn berøres (1.-ægteskabs-børn
#  sidder allerede rigtigt). Uafklarede børn (tom/tvetydig kontekst el. en
#  ikke-registreret forbindelse) parkeres på en partnerløs union for forælderen
#  — aldrig efterladt på et forkert ægteskab — og rapporteres.
#
#  Fortrydbart: hele korrektionen kører i ÉN transaktion under ÉT change_set
#  (begin_change_set). Rul tilbage med red_fortryd_change_set(<id>).
#  Flytning = DELETE gammel family_member-række + INSERT ny (undgår PK-muterende
#  UPDATE på (family_id,person_id,rolle)); konfidens bevares.
#
#  Brug:  Rscript .claude/skills/daa-extract/scripts/fix_boern_multi_union.R work/clean-v2.json [--apply]
#         uden --apply = DRY-RUN (viser plan, rører intet). Login fra ~/.Renviron.
# =====================================================================
suppressMessages({library(DBI); library(jsonlite)})
source(".claude/skills/daa-extract/scripts/load_helpers.R")

argv  <- commandArgs(trailingOnly = TRUE)
if (length(argv) < 1) stop("brug: fix_boern_multi_union.R clean.json [--apply]")
path  <- argv[1]
APPLY <- "--apply" %in% argv
clean <- fromJSON(path, simplifyVector = FALSE)

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require", bigint = "integer")
on.exit(dbDisconnect(con), add = TRUE)
q <- function(sql, ...) { p <- list(...); if (length(p)) dbGetQuery(con, sql, params = p) else dbGetQuery(con, sql) }

# ---- DAA-stamtavle-kilden: den source der bærer flest romerske linje-external_ids ----
src_id <- q("SELECT source_id FROM person_external_id
             WHERE linje ~ '^(I|II|III|IV|V)$' GROUP BY source_id
             ORDER BY count(*) DESC LIMIT 1")$source_id[1]
if (is.na(src_id)) stop("Fandt ingen DAA-source via linje-external_ids.")

pid_of <- function(linje, nr) {
  r <- q("SELECT person_id FROM person_external_id WHERE source_id=$1 AND linje=$2 AND nr=$3",
         src_id, linje, as.integer(nr))
  if (nrow(r) == 1) r$person_id[1] else NA_integer_        # 0 el. >1 => uafgjort, springes
}
# ordinal -> family_id for forælderens partner-medlemskaber
fam_by_ordinal <- function(pid) {
  r <- q("SELECT ordinal, family_id FROM family_member WHERE person_id=$1 AND rolle='partner'", pid)
  setNames(as.list(r$family_id), as.character(r$ordinal))
}
# barnets nuværende barn-medlemskab (family_id + konfidens) inden for et sæt familier.
# fam_ids er heltal fra basen (ingen injektions-risiko) => IN-liste frem for array-param.
barn_row <- function(child_pid, fam_ids) {
  ids <- as.integer(unlist(fam_ids))
  if (!length(ids)) return(NULL)
  r <- q(sprintf("SELECT family_id, konfidens FROM family_member
                  WHERE person_id=$1 AND rolle='barn' AND family_id IN (%s)",
                 paste(ids, collapse = ",")),
         child_pid)
  if (nrow(r) >= 1) list(family_id = r$family_id[1], konfidens = r$konfidens[1]) else NULL
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
multi <- Filter(function(r) length(r$aegteskaber %||% list()) >= 2 && !is.null(r$boern$nr_range), clean)

moves <- list()      # list(child_pid, fra_fam, til_fam, konfidens, hvem, aarsag)
parks <- list()      # uafklarede: list(parent_pid, child_pid, fra_fam, konfidens, hvem, reason)
skips <- list()      # diagnostik: barn uden entydig pid el. uden nuværende barn-række

for (r in multi) {
  L <- r$linje; parent_pid <- pid_of(L, r$nr)
  if (is.na(parent_pid)) { skips[[length(skips)+1]] <- list(hvem=sprintf("%s-%s", L, r$nr), grund="forael_pid_uafgjort"); next }
  ordmap <- fam_by_ordinal(parent_pid)
  fam_ids <- unlist(ordmap, use.names = FALSE)
  rng <- r$boern$nr_range
  for (n in seq(rng[[1]], rng[[2]])) {
    cpid <- pid_of(L, n)
    if (is.na(cpid)) next                                  # a/b-variant el. ukendt nr — ikke i denne fix' scope
    cur <- barn_row(cpid, fam_ids)
    if (is.null(cur)) next                                 # barnet er ikke barn i forælderens familier (fx eget opslag)
    # find barnets record for aegteskab_kontekst
    crec <- Filter(function(x) identical(x$linje, L) && identical(x$nr, n), clean)
    ctx  <- if (length(crec)) crec[[1]]$aegteskab_kontekst else NA
    mu   <- match_barn_union(ctx, r$aegteskaber)
    hvem <- sprintf("%s-%d %s", L, n, (if (length(crec)) crec[[1]]$navn else "?") %||% "?")
    if (is.na(mu$idx)) {
      parks[[length(parks)+1]] <- list(parent_pid=parent_pid, child_pid=cpid, fra_fam=cur$family_id,
                                       konfidens=cur$konfidens, hvem=hvem, reason=mu$reason)
      next
    }
    target_ord <- r$aegteskaber[[mu$idx]]$ordinal %||% mu$idx
    til_fam <- ordmap[[as.character(target_ord)]]
    if (is.null(til_fam)) { skips[[length(skips)+1]] <- list(hvem=hvem, grund=paste0("ingen_prod_familie_ordinal_", target_ord)); next }
    if (!identical(cur$family_id, til_fam)) {
      moves[[length(moves)+1]] <- list(child_pid=cpid, fra_fam=cur$family_id, til_fam=til_fam,
                                       konfidens=cur$konfidens, hvem=hvem, via=mu$via)
    }
  }
}

cat(sprintf("\n=== KORREKTIONSPLAN (source_id=%s) ===\n", src_id))
cat(sprintf("Flergifte forældre m. børn: %d\n", length(multi)))
cat(sprintf("Børn der FLYTTES (ikke-1.-ægteskab, forkert placeret): %d\n", length(moves)))
cat(sprintf("Børn der PARKERES (uafklaret kontekst): %d\n", length(parks)))
cat(sprintf("Sprunget (uden for scope/uafgjort): %d\n\n", length(skips)))
for (m in moves) cat(sprintf("  FLYT  %-34s fam %s -> %s  (via %s, konf=%s)\n",
                             m$hvem, m$fra_fam, m$til_fam, m$via, m$konfidens %||% "NA"))
for (p in parks) cat(sprintf("  PARK  %-34s fra fam %s  (%s)\n", p$hvem, p$fra_fam, p$reason))
for (s in skips) cat(sprintf("  SKIP  %-34s %s\n", s$hvem, s$grund))

if (!APPLY) { cat("\n[DRY-RUN] Intet ændret. Kør med --apply for at anvende (versioneret).\n"); quit(status = 0) }

# ---- idempotens-guard: dette er et ENGANGS-fix. Er det allerede anvendt, så afvis
# (park-stien er ikke idempotent — en gentaget kørsel ville minte en NY park-union). ----
already <- q("SELECT id FROM change_set WHERE operation='fix_boern_multi_union' ORDER BY id LIMIT 1")
if (nrow(already)) stop(sprintf(
  "Allerede anvendt som change_set %s. Fortryd først (SELECT red_fortryd_change_set(%s)) hvis du vil køre igen.",
  already$id[1], already$id[1]))

# ---- ANVEND: én transaktion, ét change_set ----
cat("\n[APPLY] Åbner change_set og udfører flytninger...\n")
dbBegin(con)
ok <- tryCatch({
  cs <- dbGetQuery(con, "SELECT begin_change_set('fix_boern_multi_union',
        'Flyt børn af flergifte forældre til korrekt union (aegteskab_kontekst)', NULL, NULL) AS id")$id[1]

  move_row <- function(child_pid, fra, til, konf) {
    dbExecute(con, "DELETE FROM family_member WHERE family_id=$1 AND person_id=$2 AND rolle='barn'",
              params = list(as.integer(fra), as.integer(child_pid)))
    # INSERT ny på målfamilien; ON CONFLICT: barnet var allerede der (idempotens)
    dbExecute(con, "INSERT INTO family_member (family_id, person_id, rolle, ordinal, konfidens)
                    VALUES ($1,$2,'barn',NULL,$3)
                    ON CONFLICT (family_id, person_id, rolle) DO NOTHING",
              params = list(as.integer(til), as.integer(child_pid), konf))
  }
  for (m in moves) move_row(m$child_pid, m$fra_fam, m$til_fam, m$konfidens)

  # parkér uafklarede: partnerløs union pr. forælder (som loaderens park_union)
  park_fam_cache <- new.env()
  for (p in parks) {
    kf <- as.character(p$parent_pid)
    if (!exists(kf, envir = park_fam_cache, inherits = FALSE)) {
      nfid <- dbGetQuery(con, "SELECT coalesce(max(id),0)+1 AS id FROM family")$id[1]
      dbExecute(con, "INSERT INTO family (id, type) VALUES ($1,'union')", params = list(as.integer(nfid)))
      dbExecute(con, "INSERT INTO family_member (family_id, person_id, rolle) VALUES ($1,$2,'partner')",
                params = list(as.integer(nfid), as.integer(p$parent_pid)))
      assign(kf, nfid, envir = park_fam_cache)
    }
    pf <- get(kf, envir = park_fam_cache)
    move_row(p$child_pid, p$fra_fam, pf, p$konfidens)
  }
  cs
}, error = function(e) { dbRollback(con); stop("FEJL — rullet tilbage: ", conditionMessage(e)) })
dbCommit(con)
cat(sprintf("[APPLY] Færdig. change_set id=%s (fortryd: SELECT red_fortryd_change_set(%s);)\n", ok, ok))

# ---- ACCEPTANCE-GATE ----
cat("\n=== ACCEPTANCE-GATE ===\n")
# 1) Anna Sophie (V-14 og V-17) skal nu sidde på Hahn (Conrads 2. ægteskab, fam m. ordinal 2)
gate1 <- q("
  WITH conrad AS (SELECT person_id AS pid FROM person_external_id WHERE source_id=$1 AND linje='V' AND nr=1),
       hahn_fam AS (SELECT family_id FROM family_member fm, conrad
                    WHERE fm.person_id=conrad.pid AND fm.rolle='partner' AND fm.ordinal=2)
  SELECT x.nr, (SELECT count(*) FROM family_member fb, hahn_fam
                WHERE fb.person_id=x.person_id AND fb.rolle='barn' AND fb.family_id=hahn_fam.family_id) AS paa_hahn
  FROM person_external_id x WHERE x.source_id=$1 AND x.linje='V' AND x.nr IN (14,17)", src_id)
cat("  Anna Sophie V-14/V-17 på Hahn (ordinal 2)?\n"); print(gate1)
ok1 <- all(gate1$paa_hahn == 1)
cat(sprintf("  => %s\n", if (ok1) "OK" else "FEJL"))

cat(sprintf("\nResultat: %d flyttet, %d parkeret. Gate: %s\n",
            length(moves), length(parks), if (ok1) "GRØN" else "RØD"))
