#!/usr/bin/env Rscript
# =====================================================================
#  load_daa.R — loader VALIDERET DAA-udtræk (clean.json) til Supabase.
#  Erstatter det håndtransskriberede udsnit i supabase_load.R.
#
#  Brug:  Rscript load_daa.R clean.json [udgave] [--no-reset]
#         udgave default "DAA 2018-20".
#  Login fra ~/.Renviron (samme som supabase_load.R).
#
#  Loader pr. post: narrative (fuld prosa) + fact/assertion/conclusion/
#  citation for rygraden + family/family_member for slægtskab + relation
#  for godser/embeder/begivenheder. Alt under én source = DAA-udgaven.
#
#  KENDT v1-forenkling: børn knyttes til forælderens familie via boern.nr_range
#  (ikke per-ægteskab-gruppering). Forfines i review/senere iteration.
# =====================================================================
suppressMessages({library(DBI); library(jsonlite)})

argv    <- commandArgs(trailingOnly = TRUE)
if (length(argv) < 1) stop("brug: load_daa.R clean.json [udgave] [--no-reset]")
path    <- argv[1]
udgave  <- if (length(argv) >= 2 && !startsWith(argv[2], "--")) argv[2] else "DAA 2018-20"
RESET   <- !("--no-reset" %in% argv)

clean <- fromJSON(path, simplifyVector = FALSE)
if (!length(clean)) stop("clean.json er tom — intet at loade.")

# ---- forbindelse ----
host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require", bigint = "integer")

ex <- function(sql, params = list()) if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql)
model_tables <- c("note","citation","conclusion","assertion","relation","fact",
                  "family_member","family","person_external_id","narrative","person",
                  "coat_of_arms","historical_event","media","estate","organisation","place","source")

# id-allokering: start fra max(id) i basen (eller 0 efter reset)
.seq <- new.env(parent = emptyenv())
nid <- function(t) { v <- (if (is.null(.seq[[t]])) 0L else .seq[[t]]) + 1L; .seq[[t]] <- v; v }

# ---- helpers (samme mønster som supabase_load.R) ----
add_person <- function(koen = NA) { pid <- nid("person")
  ex("INSERT INTO person (id, levende, koen) VALUES ($1, FALSE, $2)", list(pid, koen)); pid }
add_extid <- function(pid, sid, linje, nr)
  ex("INSERT INTO person_external_id (person_id, source_id, linje, nr) VALUES ($1,$2,$3,$4)", list(pid, sid, linje, nr))
add_narr <- function(pid, sid, side, tekst)
  ex("INSERT INTO narrative (id, subjekt_type, subjekt_id, source_id, side, tekst) VALUES ($1,'person',$2,$3,$4,$5)",
     list(nid("narrative"), pid, sid, side, tekst))
add_fact <- function(pid, ft) { fid <- nid("fact")
  ex("INSERT INTO fact (id, subjekt_type, subjekt_id, faktatype) VALUES ($1,'person',$2,$3)", list(fid, pid, ft)); fid }
add_assertion <- function(tt, tid, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA) { aid <- nid("assertion")
  ex(paste("INSERT INTO assertion (id,target_type,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw)",
           "VALUES ($1,$2,$3,$4,$5,$6,$7,$8)"), list(aid, tt, tid, vaerdi, dmin, dmax, qual, raw)); aid }
add_citation <- function(aid, sid, side=NA, kval="primær")
  ex("INSERT INTO citation (id, assertion_id, source_id, side, kvalitet) VALUES ($1,$2,$3,$4,$5)",
     list(nid("citation"), aid, sid, side, kval))
add_conclusion <- function(tt, tid, chosen, status="afklaret", by=udgave)
  ex(paste("INSERT INTO conclusion (id,target_type,target_id,valgt_assertion_id,status,blaastemplet_af)",
           "VALUES ($1,$2,$3,$4,$5,$6)"), list(nid("conclusion"), tt, tid, chosen, status, by))
fact_value <- function(pid, ft, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA, sid, side) {
  fid <- add_fact(pid, ft); aid <- add_assertion("fact", fid, vaerdi, iso(dmin), iso(dmax), qual, raw)
  add_citation(aid, sid, side); add_conclusion("fact", fid, aid); invisible(fid) }
add_family <- function(type="union") { fid <- nid("family"); ex("INSERT INTO family (id,type) VALUES ($1,$2)", list(fid,type)); fid }
add_member <- function(fid, pid, rolle, ordinal=NA, konfidens=NA)
  ex("INSERT INTO family_member (family_id,person_id,rolle,ordinal,konfidens) VALUES ($1,$2,$3,$4,$5)",
     list(fid, pid, rolle, ordinal, konfidens))
add_estate <- function(navn) { eid <- nid("estate"); ex("INSERT INTO estate (id,navn) VALUES ($1,$2)", list(eid,navn)); eid }
add_org <- function(navn) { oid <- nid("organisation"); ex("INSERT INTO organisation (id,navn) VALUES ($1,$2)", list(oid,navn)); oid }
add_event <- function(navn) { hid <- nid("historical_event"); ex("INSERT INTO historical_event (id,navn) VALUES ($1,$2)", list(hid,navn)); hid }
add_relation <- function(st, sid_, ot, oid_, rolle, raw=NA, em=NA) { rid <- nid("relation")
  ex(paste("INSERT INTO relation (id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,erhvervelsesmaade,periode_raw)",
           "VALUES ($1,$2,$3,$4,$5,$6,$7,$8)"), list(rid, st, sid_, ot, oid_, rolle, em, raw)); invisible(rid) }
g <- function(x, k, d=NA) if (!is.null(x[[k]])) x[[k]] else d
# normalisér delvise datoer til ISO (DB-kolonnen er DATE). "1240"->"1240-01-01",
# "1240-05"->"1240-05-01". Ugyldigt (fx span "1240-1245") -> NA; date_raw bevares altid.
iso <- function(d) {
  if (is.null(d) || length(d) == 0 || is.na(d) || d == "") return(NA)
  d <- as.character(d)
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", d)) return(d)
  if (grepl("^[0-9]{4}-[0-9]{2}$", d)) return(paste0(d, "-01"))
  if (grepl("^[0-9]{4}$", d)) return(paste0(d, "-01-01"))
  NA
}

# ================= LOAD (én transaktion) =================
dbBegin(con)
tryCatch({
  if (RESET) { message("RESET: tømmer model-tabeller…")
    ex(paste0("TRUNCATE ", paste(model_tables, collapse=", "), " CASCADE;")) }

  src <- nid("source")
  ex("INSERT INTO source (id, slags, titel, udgave, ekstern) VALUES ($1,'DAA-udgave',$2,$3,FALSE)",
     list(src, paste("Dansk Adels Aarbog –", udgave), udgave))

  pmap <- new.env(parent = emptyenv())          # (linje-nr_label) -> person_id
  umap <- new.env(parent = emptyenv())          # (linje-nr_label) -> usikker (TRUE/FALSE)
  key  <- function(linje, lbl) paste0(linje, "-", lbl)
  lbl_of <- function(rec) g(rec, "nr_label", as.character(rec$nr))

  # ---- pass 1: personer, external_id, narrative, fakta ----
  for (rec in clean) {
    pid <- add_person(g(rec, "koen"))
    k <- key(rec$linje, lbl_of(rec))
    assign(k, pid, envir = pmap); assign(k, isTRUE(rec$usikker), envir = umap)
    add_extid(pid, src, rec$linje, rec$nr)        # ekstern-id bærer basenr (heltal)
    side <- g(rec, "sider", g(rec, "side"))
    add_narr(pid, src, side, rec$narrative)
    fact_value(pid, "navn", vaerdi = rec$navn, sid = src, side = side)
    if (!is.null(rec$tilnavn) && !is.na(rec$tilnavn))
      fact_value(pid, "tilnavn", vaerdi = rec$tilnavn, sid = src, side = side)
    for (f in g(rec, "facts", list())) {
      fact_value(pid, f$faktatype, vaerdi = g(f,"vaerdi"), dmin = g(f,"date_min"),
                 dmax = g(f,"date_max"), qual = g(f,"date_qualifier"), raw = g(f,"date_raw"),
                 sid = src, side = side)
    }
  }

  # ---- pass 2: slægtskab + relationer ----
  for (rec in clean) {
    pid <- get(key(rec$linje, lbl_of(rec)), envir = pmap)
    side <- g(rec, "sider", g(rec, "side"))

    # ægteskaber: familie pr. union; partner oprettes minimalt hvis navngivet
    fams <- list()
    for (a in g(rec, "aegteskaber", list())) {
      fam <- add_family(g(a, "type", "union"))
      add_member(fam, pid, "partner", ordinal = g(a, "ordinal"))
      if (!is.null(a$partner_navn) && !is.na(a$partner_navn)) {
        sp <- add_person(); fact_value(sp, "navn", vaerdi = a$partner_navn, sid = src, side = side)
        add_member(fam, sp, "partner", ordinal = g(a, "ordinal"))
      }
      fams[[length(fams) + 1]] <- fam
    }
    # børn: knyt til første union (v1-forenkling), opret familie hvis ingen ægteskab
    b <- rec[["boern"]]                       # direkte opslag: NULL hvis fraværende (g() ville give NA -> $ fejler)
    if (is.list(b) && !is.null(b$nr_range)) {
      fam <- if (length(fams)) fams[[1]] else add_family("union")
      if (!length(fams)) add_member(fam, pid, "partner")
      lin <- g(b, "linje", rec$linje); rng <- b$nr_range
      for (n in seq(rng[[1]], rng[[2]])) {
        ck <- key(lin, as.character(n))
        if (exists(ck, envir = pmap, inherits = FALSE)) {
          konf <- if (isTRUE(get0(ck, envir = umap, inherits = FALSE))) "formodet" else NA
          add_member(fam, get(ck, envir = pmap), "barn", konfidens = konf)
        }
      }
    }

    # godser -> estate + relation 'ejer'
    for (gd in g(rec, "godser", list())) {
      eid <- add_estate(gd$navn)
      add_relation("person", pid, "estate", eid, "ejer", raw = g(gd, "periode_raw"), em = "født/arvet")
    }
    # embeder -> organisation + relation (rolle)
    for (em in g(rec, "embeder", list())) {
      oid <- add_org(g(em, "organisation", em$rolle))
      add_relation("person", pid, "organisation", oid, em$rolle, raw = g(em, "dato_raw"))
    }
    # begivenheder -> historical_event + relation
    for (bv in g(rec, "begivenheder", list())) {
      hid <- add_event(bv$navn)
      add_relation("person", pid, "historical_event", hid, bv$rolle, raw = g(bv, "dato_raw"))
    }
  }

  # ---- visnings-cache (envejs-projektion fra konklusioner) ----
  ex("
    UPDATE person p SET
      visning_navn = (SELECT a.vaerdi_tekst FROM conclusion c
        JOIN assertion a ON a.id = c.valgt_assertion_id
        JOIN fact f ON f.id = c.target_id AND c.target_type='fact'
        WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='navn'),
      visning_doed = (SELECT a.date_raw FROM conclusion c
        JOIN assertion a ON a.id = c.valgt_assertion_id
        JOIN fact f ON f.id = c.target_id AND c.target_type='fact'
        WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='død')")

  dbCommit(con); message(sprintf("Indlæst %d poster (udgave %s).", length(clean), udgave))
}, error = function(e) { dbRollback(con); dbDisconnect(con)
  stop("Load fejlede, rullet tilbage: ", conditionMessage(e)) })

counts <- dbGetQuery(con, "SELECT 'person' t, count(*) n FROM person
  UNION ALL SELECT 'fact', count(*) FROM fact
  UNION ALL SELECT 'family_member', count(*) FROM family_member
  UNION ALL SELECT 'relation', count(*) FROM relation
  UNION ALL SELECT 'narrative', count(*) FROM narrative ORDER BY 1")
cat("\nRækker pr. tabel:\n"); print(counts, row.names = FALSE)
dbDisconnect(con)
