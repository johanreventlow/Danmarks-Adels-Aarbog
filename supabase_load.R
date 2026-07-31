#!/usr/bin/env Rscript
# RETIRED 2026-07-31 (Codex-review restfund 6): dette script er historisk og
# opfylder IKKE IDENTITY-kontrakten (eksplicitte id'er uden lås/sekvens-sync,
# RESET uden guards). Brug skill-loaderne (.claude/skills/daa-*/scripts/).
stop("supabase_load.R er retired — brug load_daa.R (skill). Kørsel mod enhver base er blokeret.")
# =====================================================================
#  Supabase-loader (R) for Reventlow-datamodellen
#
#  Loader det SAMME udsnit som Python-versionen (holstenske linje
#  1.-3. slægtled + ét omstridt-dato-tilfælde) ind i din Supabase-Postgres.
#
#  FORUDSÆTNINGER
#   1. schema.sql er allerede kørt i Supabase (tabellerne findes).
#   2. install.packages(c("DBI", "RPostgres"))
#   3. Læg dine login i ~/.Renviron — ALDRIG i koden, ALDRIG i git.
#      Hentes i Supabase: knappen "Connect" -> "Session pooler" (IPv4).
#      Tilføj disse linjer i ~/.Renviron og genstart R bagefter:
#
#        SUPABASE_HOST=aws-0-<region>.pooler.supabase.com
#        SUPABASE_PORT=5432
#        SUPABASE_DB=postgres
#        SUPABASE_USER=postgres.<ref>
#        SUPABASE_PASSWORD=din_database_kode
#
#  KØR:  Rscript supabase_load.R     (eller source() i RStudio)
# =====================================================================

library(DBI)

RESET <- TRUE   # tømmer model-tabellerne først, så scriptet kan køres igen.

tables <- c("note", "citation", "conclusion", "assertion", "relation", "fact",
            "family_member", "family", "person_external_id", "person",
            "coat_of_arms", "historical_event", "media", "estate",
            "organisation", "place", "source", "repository", "vocab")

# ---- forbindelse (login fra miljøvariabler) ----
host <- Sys.getenv("SUPABASE_HOST")
user <- Sys.getenv("SUPABASE_USER")
pw   <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "")
  stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron først (se toppen af filen).")

con <- dbConnect(RPostgres::Postgres(),
                 host     = host,
                 port     = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname   = Sys.getenv("SUPABASE_DB", "postgres"),
                 user     = user,
                 password = pw,
                 sslmode  = "require",   # Supabase kræver SSL
                 bigint   = "integer")

# ---- små hjælpere ----
.seq <- new.env(parent = emptyenv())
nid <- function(t) {
  v <- if (is.null(.seq[[t]])) 0L else .seq[[t]]
  v <- v + 1L; .seq[[t]] <- v; v
}
D  <- function(y, m = 1, d = 1) as.Date(sprintf("%04d-%02d-%02d", y, m, d))
ex <- function(sql, params = list()) {
  if (length(params)) dbExecute(con, sql, params = params)
  else dbExecute(con, sql)            # parameterløse queries (TRUNCATE/UPDATE) må ikke binde
}

add_person <- function(levende = FALSE, status = NA) {
  pid <- nid("person")
  ex("INSERT INTO person (id, levende, status) VALUES ($1,$2,$3)",
     list(pid, levende, status)); pid
}
add_extid <- function(pid, source_id, linje, nr)
  ex("INSERT INTO person_external_id (person_id, source_id, linje, nr) VALUES ($1,$2,$3,$4)",
     list(pid, source_id, linje, nr))

add_fact <- function(st, sid, ft) {
  fid <- nid("fact")
  ex("INSERT INTO fact (id, subjekt_type, subjekt_id, faktatype) VALUES ($1,$2,$3,$4)",
     list(fid, st, sid, ft)); fid
}
add_assertion <- function(tt, tid, vaerdi = NA, dmin = NA, dmax = NA, qual = NA, raw = NA) {
  aid <- nid("assertion")
  ex(paste("INSERT INTO assertion (id, target_type, target_id, vaerdi_tekst,",
           "date_min, date_max, date_qualifier, date_raw)",
           "VALUES ($1,$2,$3,$4,$5,$6,$7,$8)"),
     list(aid, tt, tid, vaerdi, dmin, dmax, qual, raw)); aid
}
add_citation <- function(aid, source_id, side = NA, kvalitet = NA)
  ex("INSERT INTO citation (id, assertion_id, source_id, side, kvalitet) VALUES ($1,$2,$3,$4,$5)",
     list(nid("citation"), aid, source_id, side, kvalitet))

add_conclusion <- function(tt, tid, chosen, status, by, naar = NA)
  ex(paste("INSERT INTO conclusion (id, target_type, target_id, valgt_assertion_id,",
           "status, blaastemplet_af, blaastemplet_naar) VALUES ($1,$2,$3,$4,$5,$6,$7)"),
     list(nid("conclusion"), tt, tid, chosen, status, by, naar))

fact_with_value <- function(pid, ft, vaerdi = NA, dmin = NA, dmax = NA, qual = NA,
                            raw = NA, source_id = 1, kval = "primær",
                            endorse = TRUE, status = "afklaret", by = "DAA 2018-20") {
  fid <- add_fact("person", pid, ft)
  aid <- add_assertion("fact", fid, vaerdi, dmin, dmax, qual, raw)
  add_citation(aid, source_id, kvalitet = kval)
  if (endorse) add_conclusion("fact", fid, aid, status, by)
  invisible(fid)
}
add_family <- function(t) { fid <- nid("family"); ex("INSERT INTO family (id, type) VALUES ($1,$2)", list(fid, t)); fid }
add_member <- function(fid, pid, rolle, ordinal = NA, konfidens = NA)
  ex("INSERT INTO family_member (family_id, person_id, rolle, ordinal, konfidens) VALUES ($1,$2,$3,$4,$5)",
     list(fid, pid, rolle, ordinal, konfidens))

# ================= LOAD (i én transaktion) =================
dbBegin(con)
tryCatch({

  if (RESET) {
    message("Rydder model-tabellerne (RESET=TRUE)…")
    ex(paste0("TRUNCATE ", paste(tables, collapse = ", "), " CASCADE;"))
  }

  # Kilder
  ex("INSERT INTO source (id, slags, titel, udgave, ekstern) VALUES ($1,$2,$3,$4,$5)",
     list(1, "DAA-udgave", "Danmarks Adels Aarbog – Reventlow (særudgave)", "DAA 2018-20", FALSE))
  ex("INSERT INTO source (id, slags, titel, udgave, ekstern) VALUES ($1,$2,$3,$4,$5)",
     list(2, "diplomsamling", "Schleswig-Holsteinische Regesten und Urkunden", NA, TRUE))

  # Personer (holstenske linje, 1.-3. slægtled)
  gottschalk <- add_person(); add_extid(gottschalk, 1, "I", 1)
  elisabeth  <- add_person()
  eler       <- add_person(); add_extid(eler, 1, "I", 2)
  hartwich3  <- add_person(); add_extid(hartwich3, 1, "I", 3)
  hinrich    <- add_person(); add_extid(hinrich, 1, "I", 4)
  iwan5      <- add_person(); add_extid(iwan5, 1, "I", 5)
  hartwich7  <- add_person(); add_extid(hartwich7, 1, "I", 7)
  iwan9      <- add_person(); add_extid(iwan9, 1, "I", 9)

  # Navne (partikler / tilnavn / NN)
  fact_with_value(gottschalk, "navn", "Gottschalk von Reventlow")
  fact_with_value(elisabeth,  "navn", "Elisabeth NN")
  fact_with_value(eler,       "navn", "Eler von Reventlow")
  fact_with_value(eler,       "tilnavn", "kaldet Kale (den Skaldede)")
  fact_with_value(hartwich3,  "navn", "Hartwich von Reventlow")
  fact_with_value(hinrich,    "navn", "Hinrich von Reventlow")
  fact_with_value(iwan5,      "navn", "Iwan von Reventlow")
  fact_with_value(hartwich7,  "navn", "Hartwich von Reventlow")
  fact_with_value(iwan9,      "navn", "Iwan von Reventlow")

  # Floruit (dokumenteret-aktiv span)
  fact_with_value(gottschalk, "floruit", dmin = D(1223,5,31),  dmax = D(1247,2,22),  qual = "floruit", raw = "-1223-1247-")
  fact_with_value(eler,       "floruit", dmin = D(1240),       dmax = D(1247,2,22),  qual = "floruit", raw = "-ca.1240-1247-")
  fact_with_value(hartwich3,  "floruit", dmin = D(1257,12,11), dmax = D(1300,12,31), qual = "floruit", raw = "-1257-[ca.1300]-")
  fact_with_value(hinrich,    "floruit", dmin = D(1261,8,22),  dmax = D(1272,12,31), qual = "floruit", raw = "-1261-1272-")
  fact_with_value(iwan5,      "floruit", dmin = D(1248,2,1),   dmax = D(1255,5,7),   qual = "floruit", raw = "-1248-1255-")
  fact_with_value(hartwich7,  "floruit", dmin = D(1315,10,15), dmax = D(1331,2,24),  qual = "floruit", raw = "-1315-1331-")
  fact_with_value(iwan9,      "floruit", dmin = D(1316),       dmax = D(1347),       qual = "floruit", raw = "-1316-1347-")

  # Dødsdatoer
  fact_with_value(iwan5,     "død", dmax = D(1261,8,22), qual = "before",  raw = "† før 1261 (22. aug.)")
  fact_with_value(hartwich7, "død", dmin = D(1353,1,1),  dmax = D(1356,12,31), qual = "between", raw = "† 1353/1356")

  # Familier (forældre/barn)
  f1 <- add_family("vielse")
  add_member(f1, gottschalk, "partner", 1)
  add_member(f1, elisabeth,  "partner", 1)
  for (b in c(eler, hartwich3, hinrich, iwan5)) add_member(f1, b, "barn")
  f2 <- add_family("union")
  add_member(f2, iwan5, "partner", 1)
  for (b in c(hartwich7, iwan9)) add_member(f2, b, "barn", konfidens = "formodet")   # bogens "3 sønner?"

  # Generisk relation + historisk begivenhed
  ex("INSERT INTO historical_event (id, navn) VALUES ($1,$2)",
     list(1, "Mordet på greve Adolph af Holsten (Segeberg, 1315)"))
  ex(paste("INSERT INTO relation (id, subjekt_type, subjekt_id, objekt_type, objekt_id,",
           "rolle, start_min, start_max, period_type, periode_raw, konfidens)",
           "VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)"),
     list(nid("relation"), "person", hartwich7, "historical_event", 1, "gerningsmand",
          D(1315,10,1), D(1315,10,15), "closed", "før 15. okt. 1315", "sikker"))

  # Omstridt dødsdato (s. 209): to konkurrerende påstande + konklusion
  stolberg <- add_person()
  fact_with_value(stolberg, "navn", "Christian greve zu Stolberg-Stolberg")
  doed <- add_fact("person", stolberg, "død")
  a1 <- add_assertion("fact", doed, dmin = D(1821,1,18), dmax = D(1821,1,18), qual = "exact", raw = "† 18. jan. 1821")
  add_citation(a1, 1, side = "209", kvalitet = "primær")
  a2 <- add_assertion("fact", doed, dmin = D(1820,1,1), dmax = D(1820,1,1), qual = "about", raw = "(1. jan. 1820?)")
  add_citation(a2, 1, side = "209", kvalitet = "tvivlsom")
  add_conclusion("fact", doed, a1, "afklaret (alternativ noteret)", "DAA 2018-20")

  # Afledt visnings-cache (envejs-projektion fra konklusionerne)
  ex("
    UPDATE person p SET
      visning_navn = (SELECT a.vaerdi_tekst FROM conclusion c
        JOIN assertion a ON a.id = c.valgt_assertion_id
        JOIN fact f ON f.id = c.target_id AND c.target_type = 'fact'
        WHERE f.subjekt_type = 'person' AND f.subjekt_id = p.id AND f.faktatype = 'navn'),
      visning_doed = (SELECT a.date_raw FROM conclusion c
        JOIN assertion a ON a.id = c.valgt_assertion_id
        JOIN fact f ON f.id = c.target_id AND c.target_type = 'fact'
        WHERE f.subjekt_type = 'person' AND f.subjekt_id = p.id AND f.faktatype = 'død')")

  dbCommit(con)
  message("Indlæst og committet.")

}, error = function(e) {
  dbRollback(con)
  dbDisconnect(con)
  stop("Indlæsning fejlede og blev rullet tilbage: ", conditionMessage(e))
})

# ---- verifikation ----
counts <- dbGetQuery(con, paste(
  "SELECT 'person' AS tabel, count(*) AS n FROM person",
  "UNION ALL SELECT 'fact', count(*) FROM fact",
  "UNION ALL SELECT 'assertion', count(*) FROM assertion",
  "UNION ALL SELECT 'conclusion', count(*) FROM conclusion",
  "UNION ALL SELECT 'relation', count(*) FROM relation",
  "ORDER BY 1"))
cat("\nRækker pr. tabel:\n"); print(counts, row.names = FALSE)
cat("\nKig nu i Supabase -> Table Editor -> person (visning_navn er udfyldt).\n")

dbDisconnect(con)
