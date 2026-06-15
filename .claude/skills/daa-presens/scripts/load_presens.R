#!/usr/bin/env Rscript
# =====================================================================
#  load_presens.R — loader VALIDERET præsensliste-udtræk (clean.json).
#
#  Brug:  Rscript load_presens.R clean.json [udgave] [--reset]
#         udgave default "DAA 2012-2014".
#  Login fra ~/.Renviron.
#
#  APPEND-mode som default: præsenslisten er en NY source der sameksisterer
#  med stamtavle-data — id'er allokeres fra MAX(id) i basen, ingen TRUNCATE.
#  --reset tømmer model-tabellerne først (kun hvis du vil starte forfra).
#
#  Loader pr. person: person (levende=TRUE) + fakta (navn/fødsel/død/erhverv/
#  bopæl/titel) + forælder-barn- og ægtefælle-familier + kollateral-relation
#  til gren-hoved. Alt under source = præsensliste-udgaven.
# =====================================================================
suppressMessages({library(DBI); library(jsonlite)})

argv   <- commandArgs(trailingOnly = TRUE)
if (length(argv) < 1) stop("brug: load_presens.R clean.json [udgave] [--reset]")
path   <- argv[1]
udgave <- if (length(argv) >= 2 && !startsWith(argv[2], "--")) argv[2] else "DAA 2012-2014"
RESET  <- "--reset" %in% argv

clean <- fromJSON(path, simplifyVector = FALSE)
if (!length(clean)) stop("clean.json er tom.")

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = "require", bigint = "integer")

ex <- function(sql, params = list()) if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql)
id_tables <- c("source","person","fact","assertion","conclusion","citation",
               "relation","family","narrative","place","estate","organisation")
model_tables <- c("note","citation","conclusion","assertion","relation","fact",
                  "family_member","family","person_external_id","narrative","person",
                  "estate","organisation","place","source")

.seq <- new.env(parent = emptyenv())
seed_seq <- function() for (t in id_tables) {
  m <- dbGetQuery(con, sprintf("SELECT COALESCE(MAX(id),0) m FROM %s", t))$m[1]
  .seq[[t]] <- as.integer(m)
}
nid <- function(t) { v <- (if (is.null(.seq[[t]])) 0L else .seq[[t]]) + 1L; .seq[[t]] <- v; v }
g <- function(x, k, d = NA) if (!is.null(x[[k]])) x[[k]] else d

add_person <- function(koen = NA) { pid <- nid("person")
  ex("INSERT INTO person (id, levende, koen) VALUES ($1, TRUE, $2)", list(pid, koen)); pid }
add_fact <- function(pid, ft) { fid <- nid("fact")
  ex("INSERT INTO fact (id, subjekt_type, subjekt_id, faktatype) VALUES ($1,'person',$2,$3)", list(fid, pid, ft)); fid }
add_assertion <- function(tid, vaerdi=NA, dmin=NA, dmax=NA, raw=NA) { aid <- nid("assertion")
  ex(paste("INSERT INTO assertion (id,target_type,target_id,vaerdi_tekst,date_min,date_max,date_raw)",
           "VALUES ($1,'fact',$2,$3,$4,$5,$6)"), list(aid, tid, vaerdi, dmin, dmax, raw)); aid }
add_citation <- function(aid, sid) ex("INSERT INTO citation (id, assertion_id, source_id, kvalitet) VALUES ($1,$2,$3,'primær')",
  list(nid("citation"), aid, sid))
add_conclusion <- function(tid, chosen) ex(paste("INSERT INTO conclusion (id,target_type,target_id,valgt_assertion_id,status,blaastemplet_af)",
  "VALUES ($1,'fact',$2,$3,'afklaret',$4)"), list(nid("conclusion"), tid, chosen, udgave))
fact_value <- function(pid, ft, vaerdi=NA, dmin=NA, dmax=NA, raw=NA, sid) {
  fid <- add_fact(pid, ft); aid <- add_assertion(fid, vaerdi, dmin, dmax, raw)
  add_citation(aid, sid); add_conclusion(fid, aid); invisible(fid) }
add_family <- function() { fid <- nid("family"); ex("INSERT INTO family (id,type) VALUES ($1,'vielse')", list(fid)); fid }
add_member <- function(fid, pid, rolle, ordinal=NA) ex(
  "INSERT INTO family_member (family_id,person_id,rolle,ordinal) VALUES ($1,$2,$3,$4)", list(fid, pid, rolle, ordinal))
add_relation <- function(sid_, oid_, rolle) { rid <- nid("relation")
  ex(paste("INSERT INTO relation (id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)",
           "VALUES ($1,'person',$2,'person',$3,$4)"), list(rid, sid_, oid_, rolle)); invisible(rid) }
add_extid <- function(pid, sid, linje) ex(
  "INSERT INTO person_external_id (person_id, source_id, linje) VALUES ($1,$2,$3)", list(pid, sid, linje))

dd <- function(d, k) { v <- if (is.list(d)) d[[k]] else NULL; if (is.null(v)) NA else v }

dbBegin(con)
tryCatch({
  if (RESET) { message("RESET: tømmer model-tabeller…")
    ex(paste0("TRUNCATE ", paste(model_tables, collapse=", "), " CASCADE;")) }
  seed_seq()

  src <- nid("source")
  ex("INSERT INTO source (id, slags, titel, udgave, ekstern) VALUES ($1,'præsensliste',$2,$3,FALSE)",
     list(src, paste("Dansk Adels Aarbog (præsensliste) –", udgave), udgave))

  total <- 0
  for (blk in clean) {
    lmap <- new.env(parent = emptyenv())     # lokal_id -> person_id
    head_pid <- NULL
    # pass A: personer + fakta
    for (p in blk$personer) {
      pid <- add_person(g(p, "koen"))
      assign(p$lokal_id, pid, envir = lmap)
      add_extid(pid, src, blk$linje)
      navn <- if (!is.null(p$titel) && !is.na(p$titel)) paste(p$titel, p$navn) else p$navn
      fact_value(pid, "navn", vaerdi = navn, sid = src)
      f <- p[["foedsel"]]; if (is.list(f)) fact_value(pid, "fødsel", dmin=dd(f,"date_min"), dmax=dd(f,"date_max"), raw=dd(f,"date_raw"), sid=src)
      d <- p[["doed"]];    if (is.list(d)) fact_value(pid, "død",    dmin=dd(d,"date_min"), dmax=dd(d,"date_max"), raw=dd(d,"date_raw"), sid=src)
      for (e in g(p, "erhverv", list())) fact_value(pid, "erhverv", vaerdi = e, sid = src)
      if (!is.null(p$bopael) && !is.na(p$bopael)) fact_value(pid, "bopæl", vaerdi = p$bopael, sid = src)
      if (is.null(p$foraelder_lokal_id) && is.null(p$relation_til_hoved) && is.null(head_pid)) head_pid <- pid
      total <- total + 1
    }
    # pass B: relationer (forælder-barn, ægtefælle, kollateral)
    for (p in blk$personer) {
      pid <- get(p$lokal_id, envir = lmap)
      # ægtefælle-familier
      fams <- list()
      for (a in g(p, "aegteskaber", list())) {
        fam <- add_family(); add_member(fam, pid, "partner", ordinal = g(a, "ordinal"))
        if (!is.null(a$partner_navn) && !is.na(a$partner_navn)) {
          sp <- add_person(); fact_value(sp, "navn", vaerdi = a$partner_navn, sid = src)
          add_member(fam, sp, "partner", ordinal = g(a, "ordinal"))
        }
        fams[[length(fams)+1]] <- fam
      }
      # forælder-barn: dette barns forælder -> familie (genbrug forælderens 1. ægteskab hvis muligt)
      par <- p[["foraelder_lokal_id"]]
      if (!is.null(par) && exists(par, envir = lmap, inherits = FALSE)) {
        ppid <- get(par, envir = lmap)
        fam <- nid("family"); ex("INSERT INTO family (id,type) VALUES ($1,'vielse')", list(fam))
        add_member(fam, ppid, "partner"); add_member(fam, pid, "barn")
      }
      # kollateral -> relation til gren-hoved
      if (!is.null(p$relation_til_hoved) && !is.na(p$relation_til_hoved) && !is.null(head_pid) && pid != head_pid)
        add_relation(pid, head_pid, p$relation_til_hoved)
    }
  }

  ex("UPDATE person p SET visning_navn = (SELECT a.vaerdi_tekst FROM conclusion c
        JOIN assertion a ON a.id=c.valgt_assertion_id JOIN fact f ON f.id=c.target_id AND c.target_type='fact'
        WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='navn')
      WHERE p.visning_navn IS NULL")
  dbCommit(con); message(sprintf("Indlæst %d personer fra præsensliste (%s).", total, udgave))
}, error = function(e) { dbRollback(con); dbDisconnect(con)
  stop("Load fejlede, rullet tilbage: ", conditionMessage(e)) })

print(dbGetQuery(con, "SELECT slags, count(*) OVER () FROM source WHERE slags='præsensliste' LIMIT 1"), row.names = FALSE)
dbDisconnect(con)
