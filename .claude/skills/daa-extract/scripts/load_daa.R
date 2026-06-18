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

# ---- BULK-INSERT: akkumulér rækker i hukommelsen, COPY per tabel til sidst ----
# (én lang single-row-transaktion over pooleren er både langsom OG skrøbelig —
#  forbindelsen dropper. Vi laver ingen DB-kald under passene; flush_all() skriver
#  hver tabel med dbAppendTable/COPY i FK-rækkefølge i én kort transaktion.)
.buf <- new.env(parent = emptyenv())
push <- function(tbl, row) { .buf[[tbl]] <- c(.buf[[tbl]], list(row)); invisible() }
rows_to_df <- function(rows) {
  cols <- names(rows[[1]])
  data <- lapply(cols, function(cn)
    unlist(lapply(rows, function(r) { v <- r[[cn]]; if (is.null(v)) NA else v }), use.names = FALSE))
  names(data) <- cols
  as.data.frame(data, stringsAsFactors = FALSE, optional = TRUE)
}
flush_all <- function() {
  ord <- c("place","person","person_external_id","estate","organisation","historical_event",
           "fact","assertion","citation","conclusion","family","family_member","relation","note","narrative")
  for (tbl in ord) { rows <- .buf[[tbl]]; if (length(rows)) dbAppendTable(con, tbl, rows_to_df(rows)) }
}

add_person <- function(koen = NA) { id <- nid("person"); push("person", list(id=id, levende=FALSE, koen=koen)); id }
add_extid <- function(pid, sid, linje, nr) push("person_external_id", list(person_id=pid, source_id=sid, linje=linje, nr=nr))
add_narr <- function(pid, sid, side, tekst) push("narrative", list(id=nid("narrative"), subjekt_type="person", subjekt_id=pid, source_id=sid, side=side, tekst=tekst))
add_fact <- function(sid_, ft, sted_id=NA, st="person") { id <- nid("fact"); push("fact", list(id=id, subjekt_type=st, subjekt_id=sid_, faktatype=ft, sted_id=sted_id)); id }
add_assertion <- function(tt, tid, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA) { id <- nid("assertion")
  push("assertion", list(id=id, target_type=tt, target_id=tid, vaerdi_tekst=vaerdi, date_min=dmin, date_max=dmax, date_qualifier=qual, date_raw=raw)); id }
add_citation <- function(aid, sid, side=NA, kval="primær", citat=NA) push("citation", list(id=nid("citation"), assertion_id=aid, source_id=sid, side=side, citat_tekst=citat, kvalitet=kval))
add_conclusion <- function(tt, tid, chosen, status="afklaret", by=current_by) push("conclusion", list(id=nid("conclusion"), target_type=tt, target_id=tid, valgt_assertion_id=chosen, status=status, blaastemplet_af=by))
add_note <- function(tt, tid, indhold) {
  if (is.null(indhold) || is.na(indhold) || !nzchar(trimws(indhold))) return(invisible())
  push("note", list(id=nid("note"), target_type=tt, target_id=tid, indhold=indhold)) }
.cache <- new.env(parent = emptyenv())
# get-or-create på navn: sted/ejendom/org/begivenhed er FÆLLES entiteter (datamodel §5).
get_place <- function(navn) {
  if (is.null(navn) || length(navn)==0 || is.na(navn) || !nzchar(trimws(navn))) return(NA)
  k <- paste0("place::", tolower(trimws(navn)))
  if (exists(k, envir=.cache, inherits=FALSE)) return(get(k, envir=.cache))
  id <- nid("place"); push("place", list(id=id, navn=navn)); assign(k, id, envir=.cache); id }
get_or_create <- function(tabel, navn, sted=NA) {
  k <- paste0(tabel, "::", tolower(trimws(navn)))
  if (exists(k, envir=.cache, inherits=FALSE)) return(get(k, envir=.cache))
  id <- nid(tabel)
  if (tabel == "estate") push("estate", list(id=id, navn=navn, sted_id=get_place(sted)))
  else push(tabel, list(id=id, navn=navn))
  assign(k, id, envir=.cache); id }
add_estate <- function(navn, sted=NA) get_or_create("estate", navn, sted)
add_org    <- function(navn) get_or_create("organisation", navn)
add_event  <- function(navn) get_or_create("historical_event", navn)
add_relation <- function(st, sid_, ot, oid_, rolle, raw=NA, em=NA) { id <- nid("relation")
  push("relation", list(id=id, subjekt_type=st, subjekt_id=sid_, objekt_type=ot, objekt_id=oid_, rolle=rolle, erhvervelsesmaade=em, periode_raw=raw)); id }
fact_value <- function(pid, ft, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA, sid, side, sted=NA, st="person", span=NA) {
  fid <- add_fact(pid, ft, get_place(sted), st)
  aid <- add_assertion("fact", fid, vaerdi, iso(dmin), iso(dmax), qual, raw)
  add_citation(aid, sid, side, citat=span); add_conclusion("fact", fid, aid); invisible(fid) }
# Ægtefælle-dato kan komme STRUKTURERET (list m. date_min/max/raw/sted) ELLER
# som rå STRING ("* 26. sept. 1687") — udtrækket er inkonsistent. Begge -> fakta;
# raw bevares altid (display bruger date_raw). String: kun raw, ingen ISO-dato.
sp_date <- function(sp, ft, val, sid, side) {
  if (is.null(val)) return(invisible())
  if (is.list(val))
    fact_value(sp, ft, dmin=g(val,"date_min"), dmax=g(val,"date_max"), raw=g(val,"date_raw"), sted=g(val,"sted"), sid=sid, side=side)
  else if (is.character(val) && nzchar(trimws(val)))
    fact_value(sp, ft, raw=val, sid=sid, side=side)
}
add_family <- function(type="union") { id <- nid("family"); push("family", list(id=id, type=type)); id }
add_member <- function(fid, pid, rolle, ordinal=NA, konfidens=NA)
  push("family_member", list(family_id=fid, person_id=pid, rolle=rolle, ordinal=ordinal, konfidens=konfidens))
# relation MED evidenslag (invariant #4: gælder også relationer)
rel_value <- function(st, sid_, ot, oid_, rolle, raw=NA, em=NA, sid) {
  rid <- add_relation(st, sid_, ot, oid_, rolle, raw, em)
  aid <- add_assertion("relation", rid, vaerdi=rolle, raw=raw)
  add_citation(aid, sid); add_conclusion("relation", rid, aid); invisible(rid) }
g <- function(x, k, d=NA) if (!is.null(x[[k]])) x[[k]] else d
# Adskil ledende adelstitel fra navnet (titel != navn, datamodel §5). Nogle
# udtræk bager titlen ind i navnet -> ryddes her, så navn-fakta er rent.
.titler <- c("lensgrevinde","lensgreve","rigsgrevinde","rigsgreve","grevinde","komtesse",
             "greve","friherreinde","friherre","baronesse","baron","hertuginde","hertug",
             "prinsesse","prins","fyrstinde","fyrste")
split_title <- function(navn) {
  if (is.null(navn) || length(navn)==0 || is.na(navn)) return(list(titel=NA, rest=navn))
  w <- strsplit(trimws(navn), "\\s+")[[1]]
  if (length(w) >= 2 && tolower(w[1]) %in% .titler)
    return(list(titel=w[1], rest=paste(w[-1], collapse=" ")))
  list(titel=NA, rest=navn)
}
# Seed kontrolleret vokabular (invariant #9) fra vocab.json — idempotent.
seed_vocab <- function() {
  vp <- ".claude/skills/daa-extract/references/vocab.json"
  if (!file.exists(vp)) return(invisible())
  v <- fromJSON(vp, simplifyVector = TRUE)
  schemes <- c(koen="koen", faktatype="faktatype", relation_rolle="rolle",
               familie_rolle="familie_rolle", slaegtskab_rolle="slaegtskab",
               embede_eksempler="embede")
  for (key in names(schemes)) for (code in v[[key]])
    ex("INSERT INTO vocab (scheme,code,label) VALUES ($1,$2,$3) ON CONFLICT (scheme,code) DO NOTHING",
       list(unname(schemes[key]), code, code))
  # forkortelsesnøgle fra bogens bagstof (kode -> betydning)
  fp <- ".claude/skills/daa-extract/references/forkortelser.json"
  if (file.exists(fp)) { fk <- fromJSON(fp, simplifyVector = TRUE)
    for (code in names(fk))
      ex("INSERT INTO vocab (scheme,code,label) VALUES ('forkortelse',$1,$2) ON CONFLICT (scheme,code) DO NOTHING",
         list(code, fk[[code]])) }
}
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

current_by <- udgave   # konklusions-proveniens; sættes per record

# ================= LOAD (én transaktion) =================
dbBegin(con)
tryCatch({
  if (RESET) { message("RESET: tømmer model-tabeller…")
    ex(paste0("TRUNCATE ", paste(model_tables, collapse=", "), " CASCADE;")) }

  seed_vocab()

  src <- nid("source")
  ex("INSERT INTO source (id, slags, titel, udgave, ekstern) VALUES ($1,'DAA-udgave',$2,$3,FALSE)",
     list(src, paste("Dansk Adels Aarbog –", udgave), udgave))

  pmap <- new.env(parent = emptyenv())          # (linje-nr_label) -> person_id
  umap <- new.env(parent = emptyenv())          # (linje-nr_label) -> usikker (TRUE/FALSE)
  key  <- function(linje, lbl) paste0(linje, "-", lbl)
  lbl_of <- function(rec) g(rec, "nr_label", as.character(rec$nr))

  # ---- pass 1: personer, external_id, narrative, fakta ----
  for (rec in clean) {
    current_by <- if (isTRUE(rec[["_escalated"]])) "Opus-escalated" else udgave
    pid <- add_person(g(rec, "koen"))
    k <- key(rec$linje, lbl_of(rec))
    assign(k, pid, envir = pmap); assign(k, isTRUE(rec$usikker), envir = umap)
    add_extid(pid, src, rec$linje, rec$nr)        # ekstern-id bærer basenr (heltal)
    side <- g(rec, "sider", g(rec, "side"))
    add_narr(pid, src, side, rec$narrative)
    tp <- split_title(rec$navn)
    fact_value(pid, "navn", vaerdi = tp$rest, sid = src, side = side)
    # bevar titel som fakta hvis den var bagt ind i navnet og ikke allerede findes
    if (!is.na(tp$titel) && !any(vapply(g(rec, "facts", list()), function(f) identical(f$faktatype, "titel"), logical(1))))
      fact_value(pid, "titel", vaerdi = tp$titel, sid = src, side = side)
    if (!is.null(rec$tilnavn) && !is.na(rec$tilnavn))
      fact_value(pid, "tilnavn", vaerdi = rec$tilnavn, sid = src, side = side)
    for (f in g(rec, "facts", list())) {
      if (f$faktatype %in% c("erhverv", "uddannelse")) next   # foreløbig IKKE rygrad — bliver i narrativen
      fact_value(pid, f$faktatype, vaerdi = g(f,"vaerdi"), dmin = g(f,"date_min"),
                 dmax = g(f,"date_max"), qual = g(f,"date_qualifier"), raw = g(f,"date_raw"),
                 sid = src, side = side, sted = g(f,"sted"), span = g(f,"kilde_span"))
    }
  }

  # ---- pass 2: slægtskab + relationer ----
  for (rec in clean) {
    current_by <- if (isTRUE(rec[["_escalated"]])) "Opus-escalated" else udgave
    pid <- get(key(rec$linje, lbl_of(rec)), envir = pmap)
    side <- g(rec, "sider", g(rec, "side"))

    # ægteskaber: familie pr. union; partner oprettes minimalt hvis navngivet.
    # Vielse/skilsmisse loades som FAMILIE-fakta (m. evidenslag); note bevares.
    fams <- list()
    for (a in g(rec, "aegteskaber", list())) {
      fam <- add_family(g(a, "type", "union"))
      add_member(fam, pid, "partner", ordinal = g(a, "ordinal"))
      if (!is.null(a$partner_navn) && !is.na(a$partner_navn)) {
        sp <- add_person(); sp_t <- split_title(a$partner_navn)
        fact_value(sp, "navn", vaerdi = sp_t$rest, sid = src, side = side)
        if (!is.na(sp_t$titel)) fact_value(sp, "titel", vaerdi = sp_t$titel, sid = src, side = side)
        # gift-ind ægtefælles rygrad som RIGTIGE fakta på hende (ingen egen post)
        sp_date(sp, "fødsel", a[["partner_foedsel"]], src, side)
        sp_date(sp, "dåb",    a[["partner_daab"]],    src, side)
        sp_date(sp, "død",    a[["partner_doed"]],    src, side)
        # ægtefælle har ingen narrativ -> forældre + erhverv/udd. samles i en bio-note.
        # Noten lægges på FAMILIEN (ikke personen): appen viser gift-ind ægtefælles
        # bio via familie-noter i relations-visningen (jf. relations.ts).
        sp_parts <- c()
        spf <- g(a, "partner_foraeldre", NULL); if (!is.null(spf) && !is.na(spf)) sp_parts <- c(sp_parts, spf)
        sp_erh <- g(a, "partner_erhverv", list()); if (length(sp_erh)) sp_parts <- c(sp_parts, paste("Erhverv/udd.:", paste(unlist(sp_erh), collapse=", ")))
        if (length(sp_parts)) add_note("family", fam, paste(sp_parts, collapse=" — "))
        add_member(fam, sp, "partner", ordinal = g(a, "ordinal"))
      }
      if (!is.null(a$dato_raw) || !is.null(a$date_min) || !is.null(a[["sted"]]))
        fact_value(fam, "vielse", dmin = g(a,"date_min"), dmax = g(a,"date_max"),
                   raw = g(a,"dato_raw"), sted = g(a,"sted"), sid = src, side = side,
                   st = "family", span = g(a,"kilde_span"))
      if (isTRUE(a$skilt))
        fact_value(fam, "skilsmisse", raw = "skilt", sid = src, side = side, st = "family")
      add_note("family", fam, g(a, "note", NULL))
      if (!is.null(a$partner_ekstern_ref) && !is.na(a$partner_ekstern_ref))
        add_note("family", fam, paste("partner ekstern ref:", a$partner_ekstern_ref))
      fams[[length(fams) + 1]] <- fam
    }
    # børn: knyt til første union (v1-forenkling), opret familie hvis ingen ægteskab
    b <- rec[["boern"]]                       # direkte opslag: NULL hvis fraværende (g() ville give NA -> $ fejler)
    if (is.list(b) && !is.null(b$nr_range)) {
      fam <- if (length(fams)) fams[[1]] else add_family("union")
      if (!length(fams)) add_member(fam, pid, "partner")
      stated <- g(b, "linje", rec$linje); rng <- b$nr_range
      for (n in seq(rng[[1]], rng[[2]])) {
        # boern.linje er ofte forurenet (kuld-markør forvekslet med linje). Stol
        # kun på den hvis den faktisk har barnets nr; ellers brug forælderens linje
        # (børn bliver i grenen). Bevarer ægte kryds-linje (stated linje har nr'et).
        ck <- NULL
        for (cand in c(stated, rec$linje)) {
          k2 <- key(cand, as.character(n))
          if (exists(k2, envir = pmap, inherits = FALSE)) { ck <- k2; break }
        }
        if (!is.null(ck)) {
          konf <- if (isTRUE(get0(ck, envir = umap, inherits = FALSE))) "formodet" else NA
          add_member(fam, get(ck, envir = pmap), "barn", konfidens = konf)
        }
      }
    }

    # godser -> estate (m. sted) + relation 'ejer' MED evidenslag
    for (gd in g(rec, "godser", list())) {
      eid <- add_estate(gd$navn, g(gd, "sted"))
      rel_value("person", pid, "estate", eid, "ejer", raw = g(gd, "periode_raw"), em = "født/arvet", sid = src)
    }
    # embeder -> organisation + relation MED evidenslag
    for (em in g(rec, "embeder", list())) {
      oid <- add_org(g(em, "organisation", em$rolle))
      rel_value("person", pid, "organisation", oid, em$rolle, raw = g(em, "dato_raw"), sid = src)
    }
    # begivenheder -> historical_event + relation MED evidenslag
    # Skip poster uden navn (kun dato); brug "deltager" som fallback-rolle
    for (bv in g(rec, "begivenheder", list())) {
      if (is.null(bv$navn) || is.na(bv$navn) || !nzchar(trimws(bv$navn))) next
      rolle <- if (!is.null(bv$rolle) && !is.na(bv$rolle) && nzchar(trimws(bv$rolle))) bv$rolle else "deltager"
      hid <- add_event(bv$navn)
      rel_value("person", pid, "historical_event", hid, rolle, raw = g(bv, "dato_raw"), sid = src)
    }
  }

  # ---- skriv alle akkumulerede rækker (bulk COPY, FK-rækkefølge) ----
  flush_all()

  # ---- visnings-cache: ALLE fire felter regenereres fra konklusioner ----
  # (invariant #4: envejs-projektion). LIMIT 1 da en person kan have flere
  # titel/navn-fakta; vælg vilkårlig blåstemplet.
  vexpr <- function(faktatype, kol) sprintf(
    "(SELECT a.%s FROM conclusion c
        JOIN assertion a ON a.id = c.valgt_assertion_id
        JOIN fact f ON f.id = c.target_id AND c.target_type='fact'
        WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='%s' LIMIT 1)",
    kol, faktatype)
  ex(sprintf("UPDATE person p SET visning_navn=%s, visning_foedt=%s, visning_doed=%s, visning_titel=%s",
             vexpr("navn", "vaerdi_tekst"), vexpr("fødsel", "date_raw"),
             vexpr("død", "date_raw"), vexpr("titel", "vaerdi_tekst")))

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
