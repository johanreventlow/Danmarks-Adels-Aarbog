#!/usr/bin/env Rscript
# =====================================================================
#  load_daa.R — loader VALIDERET DAA-udtræk (clean.json) til Supabase.
#  Erstatter det håndtransskriberede udsnit i supabase_load.R.
#
#  Brug:  Rscript load_daa.R clean.json [udgave] --import-key=<stabil nøgle> [--reset]
#         Legacy: Rscript load_daa.R clean.json [udgave] --legacy-import
#         udgave default "DAA 2018-20".
#  Login fra ~/.Renviron (samme som supabase_load.R).
#
#  APPEND-mode som default (review 12, 2026-07-02 — matcher load_presens.R's mønster):
#  id'er allokeres fra MAX(id) i basen, ingen TRUNCATE. --reset tømmer model-tabellerne
#  først (kun hvis du vil starte forfra — cascade-sletter ALT afledt data, inkl.
#  redaktionel historik/change_set). Tidligere var reset default med --no-reset som
#  opt-out; en glemt flag destruerede da redaktionsarbejde. Nu kræver destruktion et
#  eksplicit --reset.
#
#  Loader pr. post: narrative (fuld prosa) + fact/assertion/conclusion/
#  citation for rygraden + family/family_member for slægtskab + relation
#  for godser/embeder/begivenheder. Alt under én source = DAA-udgaven.
#
#  Børn knyttes via boern.nr_range til den KORREKTE union: ved 2+ ægteskaber
#  matches hvert barns eget aegteskab_kontekst til rette union (match_barn_union,
#  load_helpers.R — partnernavn primær, ordenstal kryds-tjek). Uafklarede
#  (tom/tvetydig kontekst el. ikke-registreret forbindelse) parkeres på en
#  dedikeret union for forælderen frem for at fejl-tilknyttes 1. ægteskab.
#  Opslag der ikke matcher et løbenummer i forælderens egen linje (heller ikke
#  via en 15a/15b-variant) logges i work/load-unresolved.csv frem for at droppes.
# =====================================================================
suppressMessages({library(DBI); library(jsonlite)})
# load_helpers.R: rene, DB-frie hjælpere (buffer_counts m.fl.) — path er repo-root-relativ,
# samme konvention som seed_vocab()'s vocab.json/forkortelser.json nedenfor (scriptet
# forudsætter Rscript køres fra repo-roden, jf. skillets Quick-run).
source(".claude/skills/daa-extract/scripts/load_helpers.R")

args <- parse_load_daa_args(commandArgs(trailingOnly = TRUE))
path <- args$path
udgave <- args$udgave
IMPORT_KEY <- args$import_key
LEGACY_IMPORT <- args$legacy_import
RESET <- args$reset
FORCE_RESET <- args$force_reset  # tilsidesæt RESET-guarden bevidst (sletter change_set-arbejde)
REPLACE <- isTRUE(args$replace)  # source-scoped replace: bevar person-id'er (replay-design #123)
REGISTER_PATH <- args$register
DRY_RUN <- args$dry_run
# --staged (K2-kuratering): markér ALLE personer denne kørsel opretter som staged=TRUE →
# skjult for anon (person_offentlig) indtil redaktør har matchet dem mod eksisterende udgaver.
# Ryddes samlet med red_publicer_udgave(source_id) når match-gennemgangen er færdig.
STAGED <- args$staged

# source.aar = tidsserie-aksen (schema.sql:37). Konvention: SIDSTE dækkede år; fail-closed ved
# uparsebar udgave (præsens-tidsserie-spec Problem 1 §3.2). Samme lille helper som load_presens.R
# (bevidst duplikeret — de to loadere er uafhængige skill-scripts uden delt lib).
parse_aar <- function(u) {
  m <- regmatches(u, regexec("([0-9]{4})\\s*-\\s*([0-9]{2})(?![0-9])", u, perl = TRUE))[[1]]
  if (length(m) == 3) {
    base4 <- as.integer(m[2]); aar <- (base4 %/% 100L) * 100L + as.integer(m[3])
    if (aar < base4) aar <- aar + 100L
    return(aar)
  }
  yrs <- as.integer(unlist(regmatches(u, gregexpr("\\b[0-9]{4}\\b", u))))
  if (!length(yrs)) stop(sprintf("Kan ikke udlede årstal af udgave='%s' — sæt en parsebar udgave (fail-closed).", u))
  max(yrs)
}
aar <- parse_aar(udgave)

# Én rå læsning af artefaktet: samme bytes bruges til både parse og hash, så
# gate-manifestets hash-kontrakt ("bytes på disk") holdes uden dobbelt fil-I/O.
raw_bytes <- readBin(path, "raw", n = file.info(path)$size)
clean <- fromJSON(rawToChar(raw_bytes), simplifyVector = FALSE)
if (!length(clean)) stop("clean.json er tom — intet at loade.")

# ---- gate-manifest (#126): valideringsresultat SKAL følge artefaktet ----
# validate.py skriver <clean>.manifest.json (sha256 + gate-tal). Uden manifest,
# ved hash-mismatch eller rød gate afvises load fail-closed; --force-gate er den
# bevidste override (samme mønster som --force-reset). --legacy-import er
# undtaget: de gamle 2018-20-artefakter er fra før manifest-kontrakten.
if (!LEGACY_IMPORT) {
  manifest_path <- paste0(path, ".manifest.json")
  res <- if (!file.exists(manifest_path)) {
    list(ok = FALSE, grund = sprintf("manifest mangler (%s) — kør validate.py igen, den skriver det nu", manifest_path))
  } else {
    if (!requireNamespace("digest", quietly = TRUE))
      stop("Gate-manifestet kræver R-pakken 'digest' til sha256 — install.packages(\"digest\").")
    verify_gate_manifest(fromJSON(manifest_path, simplifyVector = TRUE),
                         digest::digest(raw_bytes, algo = "sha256", serialize = FALSE))
  }
  if (res$ok) {
    message("Gate-manifest: ", res$grund)
  } else if (!args$force_gate) {
    stop("LOAD afvist (#126): ", res$grund, ". Tilføj --force-gate for bevidst at loade alligevel.")
  } else {
    message("ADVARSEL: --force-gate tilsidesætter gate-manifestet — ", res$grund)
  }
}

# ---- forbindelse ----
host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
# sslmode defaulter til "require" (Supabase-kravet). Kun en lokal engangsdatabase uden
# TLS må sætte SUPABASE_SSLMODE=disable — aldrig mod en fjernvært.
sslmode <- Sys.getenv("SUPABASE_SSLMODE", "require")
if (sslmode != "require" && !(host %in% c("127.0.0.1", "localhost", "::1")))
  stop("SUPABASE_SSLMODE != require er kun tilladt mod en lokal vært; fik host=", host)
con <- dbConnect(RPostgres::Postgres(), host = host,
                 port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
                 dbname = Sys.getenv("SUPABASE_DB", "postgres"),
                 user = user, password = pw, sslmode = sslmode, bigint = "integer")

ex <- function(sql, params = list()) if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql)
model_tables <- loader_model_tables()
# Tabeller denne loader selv allokerer id'er til via nid() (dvs. har egen bigint id-kolonne
# OG bruges af scriptet — person_external_id/family_member er komposit-nøgle-junction-tabeller
# uden id-kolonne; coat_of_arms/media populeres ikke af denne loader).
# KANONISK LÅSEORDEN (Codex-review 2026-07-31 restfund 5): alle scripts der
# LOCKer flere af disse tabeller SKAL bruge denne rækkefølge — forældre-først
# og relation FØR assertion (RPC'ernes naturlige skriveorden, fx red_samme_som:
# relation→assertion→conclusion). Inversion mellem to samtidige transaktioner
# = deadlock. Samme orden i load_presens.R og post_load_fixup.R.
id_tables <- c("source","person","place","estate","organisation","historical_event",
               "family","note","narrative","fact","relation","assertion","citation","conclusion")

# id-allokering: start fra max(id) i basen (eller 0 efter --reset). seed_seq() SKAL køres
# efter en evt. RESET-TRUNCATE (samme transaktion), ellers ses de gamle id'er stadig —
# og i append-mode (default) er den den eneste ting der forhindrer PK-kollision mod
# eksisterende slægters data. review 12 (2026-07-02): kommentaren her hævdede "start fra
# max(id)" uden at koden nogensinde læste basen — nid() startede altid fra 1, hvilket gjorde
# append (dengang --no-reset) reelt ubrugeligt (crashede på PK-kollision mod enhver befolket
# base). Mønsteret er porteret fra load_presens.R's fungerende seed_seq().
.seq <- new.env(parent = emptyenv())
seed_seq <- function() for (t in id_tables) {
  m <- dbGetQuery(con, sprintf("SELECT COALESCE(MAX(id),0) m FROM %s", t))$m[1]
  .seq[[t]] <- as.integer(m)
}
nid <- function(t) { v <- (if (is.null(.seq[[t]])) 0L else .seq[[t]]) + 1L; .seq[[t]] <- v; v }

# ---- BULK-INSERT: akkumulér rækker i hukommelsen, COPY per tabel til sidst ----
# (én lang single-row-transaktion over pooleren er både langsom OG skrøbelig —
#  forbindelsen dropper. Vi laver ingen DB-kald under passene; flush_all() skriver
#  hver tabel med dbAppendTable/COPY i FK-rækkefølge i én kort transaktion.)
.buf <- new.env(parent = emptyenv())
.unresolved <- new.env(parent = emptyenv()); .unresolved$rows <- list()
push <- function(tbl, row) { .buf[[tbl]] <- c(.buf[[tbl]], list(row)); invisible() }
rows_to_df <- function(rows, tbl = NA_character_) {
  cols <- names(rows[[1]])
  data <- lapply(cols, function(cn)
    unlist(lapply(rows, function(r) { v <- r[[cn]]; if (is.null(v)) NA else v }), use.names = FALSE))
  names(data) <- cols
  assert_buffer_columns(data, length(rows), tbl)
  as.data.frame(data, stringsAsFactors = FALSE, optional = TRUE)
}
flush_all <- function() {
  flush_buffer_in_dependency_order(.buf, function(tbl, rows) {
    dbAppendTable(con, tbl, rows_to_df(rows, tbl))
  })
}

add_person <- function(koen = NA) { id <- nid("person"); push("person", list(id=id, levende=FALSE, staged=STAGED, koen=koen)); id }
add_extid <- function(pid, sid, linje, nr, record_key)
  push("person_external_id", external_id_buffer_row(pid, sid, linje, nr, record_key))
add_narr <- function(pid, sid, side, tekst) push("narrative", list(id=nid("narrative"), subjekt_type="person", subjekt_id=pid, source_id=sid, side=side, tekst=tekst))
add_fact <- function(sid_, ft, sted_id=NA, st="person") { id <- nid("fact"); push("fact", list(id=id, subjekt_type=st, subjekt_id=sid_, faktatype=ft, sted_id=sted_id)); id }
# objekt_type/objekt_id (Problem 2): en påstands VÆRDI kan være en entitet (forældrefamilie-slot).
# ALTID med i list()'en (NA-default) — rows_to_df bygger kolonner fra første række, så objekt-data
# på en senere slot-assertion ville ellers tabes.
# cal defaulter til 'gregoriansk' (= DB-DEFAULT) så vi ALDRIG skriver NULL og dermed nuller
# kalender-default'en; parseren sender 'juliansk' for konverterede kirkelige mærkedage.
# certainty (læse-sikkerhed) er NA→NULL default = 'ikke vurderet' (≈certain).
add_assertion <- function(tt, tid, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA, objekt_type=NA, objekt_id=NA, cal="gregoriansk", certainty=NA) { id <- nid("assertion")
  push("assertion", list(id=id, target_type=tt, target_id=tid, vaerdi_tekst=vaerdi, date_min=dmin, date_max=dmax, date_qualifier=qual, date_raw=raw, objekt_type=objekt_type, objekt_id=objekt_id, calendar=cal, date_certainty=certainty)); id }
add_citation <- function(aid, sid, side=NA, kval="primær", citat=NA) push("citation", list(id=nid("citation"), assertion_id=aid, source_id=sid, side=side, citat_tekst=citat, kvalitet=kval))
add_conclusion <- function(tt, tid, chosen, status="afklaret", by=current_by) push("conclusion", list(id=nid("conclusion"), target_type=tt, target_id=tid, valgt_assertion_id=chosen, status=status, blaastemplet_af=by))
add_note <- function(tt, tid, indhold) {
  if (is.null(indhold) || is.na(indhold) || !nzchar(trimws(indhold))) return(invisible())
  push("note", list(id=nid("note"), target_type=tt, target_id=tid, indhold=indhold)) }
.cache <- new.env(parent = emptyenv())
# Preload .cache med EKSISTERENDE fælles-entiteter (Codex dual-review, review 14, 2026-07-02):
# uden dette genkender get_place/get_or_create ikke en allerede-indlæst slægts "Clausholm" i
# append-mode (.cache starter tom hver kørsel) og opretter en DUPLIKAT-række med nyt id i
# stedet for at genbruge den eksisterende — stille semantisk datakorruption af fælles-
# entiteter på tværs af slægter. No-op i RESET-mode (tomme tabeller). Skal køre EFTER en evt.
# RESET-TRUNCATE, samme sted som seed_seq() (bruger samme MAX(id)-timing-krav).
preload_cache <- function() {
  for (tabel in c("place", "estate", "organisation", "historical_event")) {
    rows <- dbGetQuery(con, sprintf("SELECT id, navn FROM %s", tabel))
    if (nrow(rows)) for (i in seq_len(nrow(rows)))
      assign(paste0(tabel, "::", tolower(trimws(rows$navn[i]))), rows$id[i], envir=.cache)
  }
}
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
fact_value <- function(pid, ft, vaerdi=NA, dmin=NA, dmax=NA, qual=NA, raw=NA, sid, side, sted=NA, st="person", span=NA, cal="gregoriansk", certainty=NA) {
  fid <- add_fact(pid, ft, get_place(sted), st)
  aid <- add_assertion("fact", fid, vaerdi, iso(dmin), iso(dmax), qual, raw, cal=cal, certainty=certainty)
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
# Slot-tripel for en 'barn'-family_member-række (Problem 2, spec §5): forældrefamilie-fact +
# assertion (objekt=familien) + citation (udgaven som primærkilde, forælder-postens side) +
# afklaret conclusion. Gør hver loadet barn-række evidens-komplet, så en fremtidig udgave lander
# born-evidens-komplet og aldrig genindfører to-regime-tilstanden (barn-række uden slot).
# Kræver at DB'en har migreret assertion.objekt_type/objekt_id + faktatype 'forældrefamilie'.
member_evidence <- function(fid, pid, sid, side=NA) {
  slot <- add_fact(pid, "forældrefamilie")
  aid  <- add_assertion("fact", slot, vaerdi="barn", objekt_type="family", objekt_id=fid)
  add_citation(aid, sid, side); add_conclusion("fact", slot, aid); invisible(slot) }
# relation MED evidenslag (invariant #4: gælder også relationer)
rel_value <- function(st, sid_, ot, oid_, rolle, raw=NA, em=NA, sid) {
  rid <- add_relation(st, sid_, ot, oid_, rolle, raw, em)
  aid <- add_assertion("relation", rid, vaerdi=rolle, raw=raw)
  add_citation(aid, sid); add_conclusion("relation", rid, aid); invisible(rid) }
# NB: jsonlite er asymmetrisk — JSON-null læses som NULL, men skrives tilbage som {},
# der læses som en tom liste. is.null() fanger ikke den tomme liste, og en nul-længde-
# værdi ville derefter blive droppet af unlist() i rows_to_df og korrumpere kolonnen.
g <- function(x, k, d=NA) { v <- x[[k]]; if (is.null(v) || length(v) == 0L) d else v }
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
  # IDENTITY-kontrakten (Codex-review 2026-07-31 fund 1): loaderen allokerer
  # eksplicitte id'er fra MAX(id) — uden lås kan en samtidig RPC's nextval få
  # præcis samme id, og slut-sync kan ikke reparere en PK-kollision der
  # allerede er sket. EXCLUSIVE MODE blokerer andre skrivere (RPC'er venter
  # til commit) men lader alle læsere passere. Låsen SKAL tages før seed_seq().
  ex(paste0("LOCK TABLE ", paste(id_tables, collapse = ", "), " IN EXCLUSIVE MODE"))
  if (RESET) {
    cs <- tryCatch(
      dbGetQuery(con, "SELECT operation FROM change_set"),
      error = function(e) {
        if (is_missing_table_error(conditionMessage(e))) {
          message("change_set-tabellen findes ikke — antager ingen redaktionelle rækker.")
          data.frame(operation = character(0))
        } else {
          stop("RESET (--reset) afvist: kunne ikke verificere change_set (",
               conditionMessage(e), "). Fejler lukket for at beskytte evt. redaktionelt arbejde.")
        }
      })
    if (has_reset_blocking_editorial_changes(cs) && !FORCE_RESET)
      stop("RESET (--reset) afvist: basen har andre redaktionelle change_set-rækker end den genafspillelige red_ret_ocr_felt. Kør uden --reset (append) eller tilføj --force-reset for bevidst at slette dem.")
    if (has_reset_blocking_editorial_changes(cs) && FORCE_RESET)
      message("ADVARSEL: --force-reset tilsidesætter RESET-guarden — redaktionelle change_set-rækker slettes.")
    message("RESET: tømmer model-tabeller + versioneringshistorik…")
    ex(paste0("TRUNCATE ", paste(c(model_tables, loader_versioning_tables()), collapse=", "), " CASCADE;"))
  }

  seed_seq()      # skal køre EFTER en evt. TRUNCATE, og under alle omstændigheder før nid()
  preload_cache() # samme timing-krav — før get_place()/get_or_create() bruges

  seed_vocab()

  if (REPLACE) {
    # ---- REPLACE (replay-design #123, trin 3: person-scoped) ----
    # Genbrug den EKSISTERENDE source-række: narrativer/citations peger på den,
    # og dens import_key er journalens nøgle (OCR-rettelser replayes dermed).
    src_rows <- dbGetQuery(con, "SELECT id, import_key FROM source WHERE udgave = $1", list(udgave))
    if (nrow(src_rows) != 1)
      stop(sprintf("--replace: source '%s' gav %d kandidater (fail-closed).", udgave, nrow(src_rows)))
    src <- as.integer(src_rows$id[1])
    IMPORT_KEY <- src_rows$import_key[1]
    if (is.na(IMPORT_KEY)) stop("--replace: eksisterende source har ingen import_key (legacy) — replace kræver journal-nøgle.")

    reg_poster <- fromJSON(REGISTER_PATH, simplifyVector = FALSE)$poster
    reg_aktiv <- vapply(Filter(function(r) r$status == "aktiv", reg_poster), `[[`, "", "book_post_id")
    reg_tomb  <- vapply(Filter(function(r) r$status == "tombstone", reg_poster), `[[`, "", "book_post_id")
    prod_map <- dbGetQuery(con, "SELECT person_id, record_key FROM person_external_id WHERE source_id = $1 AND record_key IS NOT NULL", list(src))

    # Klassificér HVER artefaktpost — fail-closed på alt der ikke er entydigt/tombstonet.
    art_keys <- vapply(clean, function(r) { v <- record_key_of(r); if (is.na(v)) NA_character_ else v }, character(1))
    if (anyNA(art_keys)) stop(sprintf("--replace: %d poster uden record_key — replace kræver fuld nøgledækning.", sum(is.na(art_keys))))
    nye <- setdiff(art_keys, c(reg_aktiv, reg_tomb))
    if (length(nye)) stop(sprintf("--replace: %d record_keys ukendt af registeret (fx %s) — mint id'er via reconcile FØR load.",
                                  length(nye), nye[1]))
    kun_register <- setdiff(intersect(art_keys, reg_aktiv), prod_map$record_key)
    if (length(kun_register)) stop(sprintf("--replace: %d aktive registerposter uden prod-person (fx %s) — hul der kræver forklaring.",
                                           length(kun_register), kun_register[1]))
    replace_tomb <- intersect(art_keys, reg_tomb)
    match_keys <- intersect(art_keys, prod_map$record_key)
    replace_pid <- setNames(as.list(prod_map$person_id[match(match_keys, prod_map$record_key)]), match_keys)
    ids_sql <- paste(unlist(replace_pid), collapse = ",")
    stopifnot(grepl("^[0-9,]+$", ids_sql))
    bortfaldne <- setdiff(prod_map$record_key, art_keys)

    # Slette-kandidater: source-ejede person-fakta. Forældrefamilie-fakta er
    # familie-grafens (trin 4) og røres IKKE. Guards er BLOKERENDE:
    # (1) red-spor = konflikt-klassen (empirisk tom 2026-07-31, men skal STOPPE
    #     hvis den opstår — flette-logik er bevidst udeladt af v1);
    # (2) evidens fra andre sources på samme fact = kryds-source-fact, rør ikke;
    # (3) haendelse/story-FK'er på kandidater = forbrugslag peger på rækken.
    kandidat_sql <- sprintf(
      "SELECT f.id FROM fact f WHERE f.subjekt_type='person' AND f.subjekt_id IN (%s)
         AND f.faktatype <> 'forældrefamilie'
         AND NOT EXISTS (SELECT 1 FROM assertion a JOIN citation c ON c.assertion_id=a.id
                         WHERE a.target_type='fact' AND a.target_id=f.id AND c.source_id <> %d)", ids_sql, src)
    konflikt <- dbGetQuery(con, sprintf(
      "SELECT count(*) n FROM change_event ce WHERE ce.tabel='fact' AND (ce.row_pk->>'id')::bigint IN (%s)", kandidat_sql))$n
    if (konflikt > 0) stop(sprintf("--replace: %d slette-kandidater har redaktionelt spor (konflikt-klassen) — v1 STOPPER; kræver flette-design.", konflikt))
    fk_haendelse <- dbGetQuery(con, sprintf("SELECT count(*) n FROM haendelse WHERE fact_id IN (%s)", kandidat_sql))$n
    fk_story     <- dbGetQuery(con, sprintf("SELECT count(*) n FROM story WHERE fact_id IN (%s)", kandidat_sql))$n
    if (fk_haendelse + fk_story > 0)
      stop(sprintf("--replace: %d hændelser/%d stories refererer slette-kandidater — håndtér forbrugslaget først.", fk_haendelse, fk_story))

    # Før-tælling af det der SKAL være invariant (verificeres efter flush).
    replace_invarianter <- dbGetQuery(con, sprintf(
      "SELECT (SELECT count(*) FROM relation WHERE rolle IN ('samme_som','ikke_samme_som')) samme_som,
              (SELECT count(*) FROM change_set) cs, (SELECT count(*) FROM change_event) ce,
              (SELECT count(*) FROM family_member) fm, (SELECT count(*) FROM person) pers,
              (SELECT count(*) FROM narrative WHERE source_id=%d) narr", src))

    # Pre-delete i FK-orden (citation → conclusion → assertion → fact).
    n_slettet <- c(
      citation   = ex(sprintf("DELETE FROM citation WHERE assertion_id IN (SELECT a.id FROM assertion a WHERE a.target_type='fact' AND a.target_id IN (%s))", kandidat_sql)),
      conclusion = ex(sprintf("DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (%s)", kandidat_sql)),
      assertion  = ex(sprintf("DELETE FROM assertion WHERE target_type='fact' AND target_id IN (%s)", kandidat_sql)),
      fact       = ex(sprintf("DELETE FROM fact WHERE id IN (%s)", kandidat_sql)))
    message(sprintf("REPLACE: %d matchede, %d tombstonede (skippes), %d bortfaldne (røres ikke); slettet source-ejet: %s",
                    length(match_keys), length(replace_tomb), length(bortfaldne),
                    paste(names(n_slettet), n_slettet, sep = "=", collapse = ", ")))
    replace_narr <- list(); replace_koen <- list()
  } else {
    src <- nid("source")
    ex("INSERT INTO source (id, slags, titel, udgave, aar, ekstern, import_key) VALUES ($1,'DAA-udgave',$2,$3,$4,FALSE,$5)",
       list(src, paste("Dansk Adels Aarbog –", udgave), udgave, aar, IMPORT_KEY))
  }

  # Én læsning pr. import. Journalen har ingen FK til de regenererbare model-id'er
  # og står derfor uden for model_tables/TRUNCATE. Legacy-importer har ingen nøgle og
  # kan bevidst ikke have rettelser at genafspille.
  corrections <- if (is.null(IMPORT_KEY)) list() else dbGetQuery(
    con,
    "SELECT id, import_key, record_key, felt, input_fingerprint, korrigeret, status FROM import_korrektion WHERE import_key = $1",
    params = list(IMPORT_KEY)
  )
  correction_index <- index_import_corrections(corrections)
  stale_results <- list()

  pmap <- new.env(parent = emptyenv())          # (linje-nr_label) -> person_id
  umap <- new.env(parent = emptyenv())          # (linje-nr_label) -> usikker (TRUE/FALSE)
  recmap <- new.env(parent = emptyenv())        # (linje-nr_label) -> rec (til barnets aegteskab_kontekst)
  key  <- function(linje, lbl) paste0(linje, "-", lbl)
  lbl_of <- function(rec) g(rec, "nr_label", as.character(rec$nr))

  # ---- pass 1: personer, external_id, narrative, fakta ----
  for (rec in clean) {
    current_by <- if (isTRUE(rec[["_escalated"]])) "Opus-escalated" else udgave
    record_key <- record_key_of(rec)
    persisted_record_key <- if (LEGACY_IMPORT) NA_character_ else record_key
    k <- if (is.na(record_key)) key(rec$linje, lbl_of(rec)) else record_key
    side <- g(rec, "sider", g(rec, "side"))

    # Navn og køn skal være rettet FØR titel-split/person-bufferen bygges.
    # Narrativen er den uændrede OCR-kontekst for top-level-navnet.
    navn_context <- g(rec, "navn_kilde_span", g(rec, "narrative", NA_character_))
    navn_overlay <- apply_import_correction(IMPORT_KEY, record_key, "navn", rec$navn,
                                            navn_context, correction_index)
    if (identical(navn_overlay$status, "stale"))
      stale_results <- c(stale_results, list(navn_overlay))
    navn <- if (identical(navn_overlay$status, "anvendt"))
      correction_scalar(fromJSON(navn_overlay$value, simplifyVector = FALSE)$value) else rec$navn

    koen_overlay <- apply_import_correction(IMPORT_KEY, record_key, "koen", g(rec, "koen"),
                                            NA_character_, correction_index)
    if (identical(koen_overlay$status, "stale"))
      stale_results <- c(stale_results, list(koen_overlay))
    koen <- if (identical(koen_overlay$status, "anvendt"))
      correction_scalar(fromJSON(koen_overlay$value, simplifyVector = FALSE)$value) else g(rec, "koen")

    if (REPLACE) {
      if (record_key %in% reg_tomb) next   # tombstonet identitet genopstår ALDRIG
      pid <- replace_pid[[record_key]]      # person-id BEVARES — det er hele pointen
      # person-rækken og external_id består; koen og narrativ opdateres EFTER
      # flush (passene er DB-frie per design). Narrativ-UPDATE bevarer
      # narrative.id (narrativ-undtagelsen: source-ejet uanset red-spor).
      replace_koen[[length(replace_koen) + 1]] <- list(pid = pid, koen = koen)
      replace_narr[[length(replace_narr) + 1]] <- list(pid = pid, side = side, tekst = rec$narrative)
      assign(k, pid, envir = pmap); assign(k, isTRUE(rec$usikker), envir = umap)
      assign(k, rec, envir = recmap)
    } else {
      pid <- add_person(koen)
      assign(k, pid, envir = pmap); assign(k, isTRUE(rec$usikker), envir = umap)
      assign(k, rec, envir = recmap)
      add_extid(pid, src, rec$linje, rec$nr, persisted_record_key)
      add_narr(pid, src, side, rec$narrative)
    }
    tp <- split_title(navn)
    fact_value(pid, "navn", vaerdi = tp$rest, sid = src, side = side, span = navn_context)
    # bevar titel som fakta hvis den var bagt ind i navnet og ikke allerede findes
    if (!is.na(tp$titel) && !any(vapply(g(rec, "facts", list()), function(f) identical(f$faktatype, "titel"), logical(1))))
      fact_value(pid, "titel", vaerdi = tp$titel, sid = src, side = side)
    if (!is.null(rec$tilnavn) && !is.na(rec$tilnavn))
      fact_value(pid, "tilnavn", vaerdi = rec$tilnavn, sid = src, side = side)
    for (f in g(rec, "facts", list())) {
      if (f$faktatype %in% c("erhverv", "uddannelse")) next   # foreløbig IKKE rygrad — bliver i narrativen
      felt <- switch(f$faktatype, "fødsel" = "foedsel", "død" = "doed", NULL)
      if (!is.null(felt)) {
        imported_date <- list(raw = g(f, "date_raw"), min = g(f, "date_min"),
                              max = g(f, "date_max"), qualifier = g(f, "date_qualifier"),
                              calendar = g(f, "calendar", "gregoriansk"),
                              certainty = g(f, "date_certainty"))
        date_overlay <- apply_import_correction(IMPORT_KEY, record_key, felt, imported_date,
                                                g(f, "kilde_span"), correction_index)
        if (identical(date_overlay$status, "stale"))
          stale_results <- c(stale_results, list(date_overlay))
        if (identical(date_overlay$status, "anvendt")) {
          corrected_date <- fromJSON(date_overlay$value, simplifyVector = FALSE)
          f$date_raw <- correction_scalar(corrected_date$raw)
          f$date_min <- correction_scalar(corrected_date$min)
          f$date_max <- correction_scalar(corrected_date$max)
          f$date_qualifier <- correction_scalar(corrected_date$qualifier)
          f$calendar <- correction_scalar(corrected_date$calendar)
          f$date_certainty <- correction_scalar(corrected_date$certainty)
        }
      }
      fact_value(pid, f$faktatype, vaerdi = g(f,"vaerdi"), dmin = g(f,"date_min"),
                 dmax = g(f,"date_max"), qual = g(f,"date_qualifier"), raw = g(f,"date_raw"),
                 sid = src, side = side, sted = g(f,"sted"), span = g(f,"kilde_span"),
                 cal = g(f,"calendar","gregoriansk"), certainty = g(f,"date_certainty"))
    }
  }

  # ---- pass 2: slægtskab + relationer ----
  # REPLACE v1 springer pass 2 over: familie-grafen (unions, gift-ind-stubs,
  # børne-kanter, godser/begivenheder) er trin 4 i replay-designet og røres
  # ikke — de eksisterende familie-strukturer består uændret.
  for (rec in (if (REPLACE) list() else clean)) {
    current_by <- if (isTRUE(rec[["_escalated"]])) "Opus-escalated" else udgave
    pid <- get(key(rec$linje, lbl_of(rec)), envir = pmap)
    side <- g(rec, "sider", g(rec, "side"))

    # ægteskaber: familie pr. union; partner oprettes minimalt hvis navngivet.
    # Vielse/skilsmisse loades som FAMILIE-fakta (m. evidenslag); note bevares.
    fams <- list()
    for (a in g(rec, "aegteskaber", list())) {
      fam <- add_family(g(a, "type", "union"))
      add_member(fam, pid, "partner", ordinal = g(a, "ordinal"))
      ref <- parse_intern_ref(g(a, "partner_ekstern_ref"), rec$linje)
      existing_key <- if (!is.null(ref)) key(ref$linje, ref$nr) else NULL
      ref_afvist <- FALSE
      brug_ref <- !is.null(existing_key) && exists(existing_key, envir = pmap, inherits = FALSE)
      if (brug_ref) {
        # partner_ekstern_ref pegede internt på en person der allerede findes i
        # denne kilde (fx "se nr. 97") — link den eksisterende i stedet for at
        # oprette en dublet-stub. MEN kun hvis ref og partner_navn er enige
        # (#125): mis-opløste refs skabte spøgelses-unioner (barn gift m. ane).
        ref_rec <- get0(existing_key, envir = recmap, inherits = FALSE)
        if (isFALSE(partner_ref_navn_enige(g(a, "partner_navn"), g(ref_rec, "navn")))) {
          ref_afvist <- TRUE; brug_ref <- FALSE
          message(sprintf("navn≠ref: partner_navn '%s' ~ ref-person '%s' (%s) er uenige — ref-link afvist, partner oprettes fra navnet",
                          a$partner_navn, g(ref_rec, "navn", "?"), a$partner_ekstern_ref))
        }
      }
      if (brug_ref) {
        add_member(fam, get(existing_key, envir = pmap), "partner", ordinal = g(a, "ordinal"))
      } else if (!is.null(a$partner_navn) && !is.na(a$partner_navn)) {
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
        add_note("family", fam, paste0("partner ekstern ref",
                                       if (ref_afvist) " AFVIST (navn≠ref)" else "",
                                       ": ", a$partner_ekstern_ref))
      fams[[length(fams) + 1]] <- fam
    }
    # børn: knyt til den KORREKTE union via barnets eget aegteskab_kontekst.
    b <- rec[["boern"]]                       # direkte opslag: NULL hvis fraværende
    if (is.list(b) && !is.null(b$nr_range)) {
      # 0-1 ægteskaber: ingen tvetydighed — behold enkelt-union (uændret adfærd).
      # 2+ ægteskaber: match hvert barn til den union barnets `aegteskab_kontekst`
      # udpeger (match_barn_union: partnernavn primær, ordenstal kryds-tjek). Børn
      # hvis kontekst er tom/tvetydig/navngiver en ikke-registreret forbindelse
      # parkeres på en dedikeret union for forælderen (aldrig fejl-tilknyttet 1.
      # ægteskab) og logges, jf. review 11's princip om ingen tavse fejl-links.
      default_fam <- if (length(fams)) fams[[1]] else add_family("union")
      if (!length(fams)) add_member(default_fam, pid, "partner")
      multi <- length(fams) >= 2
      park_fam <- NULL
      park_union <- function() {               # lazy: kun oprettet hvis et barn faktisk parkeres
        if (is.null(park_fam)) { park_fam <<- add_family("union"); add_member(park_fam, pid, "partner") }
        park_fam
      }
      log_unres <- function(n, aarsag)
        .unresolved$rows <- c(.unresolved$rows, list(list(
          forael_linje = rec$linje, forael_nr = lbl_of(rec),
          barn_nr = as.character(n), aarsag = aarsag)))
      rng <- b$nr_range
      pk  <- ls(pmap)                          # pmap er fuldt bygget i pass 1; konstant her
      # Match UDELUKKENDE inden for forælderens egen linje (børn bliver i grenen); ingen
      # forurenet stated-linje-fallback (jf. review 11 / 163-rækkers-buggen). 15a/15b-børn
      # nås via resolve_barn_keys. Uopløste opslag logges frem for at droppes tavst.
      for (n in seq(rng[[1]], rng[[2]])) {
        keys <- resolve_barn_keys(rec$linje, n, pk)
        if (!length(keys)) { log_unres(n, barn_lookup_reason(keys)); next }
        for (ck in keys) {
          fam <- default_fam
          if (multi) {
            crec <- get0(ck, envir = recmap, inherits = FALSE)
            mu <- match_barn_union(if (is.null(crec)) NA else crec[["aegteskab_kontekst"]], rec$aegteskaber)
            if (!is.na(mu$idx)) {
              fam <- fams[[mu$idx]]
            } else {
              fam <- park_union()
              log_unres(n, paste0("union_", mu$reason))
            }
          }
          konf <- if (isTRUE(get0(ck, envir = umap, inherits = FALSE))) "formodet" else NA
          barn_pid <- get(ck, envir = pmap)
          add_member(fam, barn_pid, "barn", konfidens = konf)
          member_evidence(fam, barn_pid, src, side)  # evidens-komplet barn-række (Problem 2)
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

  if (REPLACE) {
    # Narrativ-UPDATE (bevarer narrative.id og dermed evt. haendelse-FK'er) +
    # koen-opdatering på de bevarede person-rækker.
    for (u in replace_narr) {
      n <- ex("UPDATE narrative SET tekst=$1, side=$2 WHERE subjekt_type='person' AND subjekt_id=$3 AND source_id=$4",
              list(u$tekst, u$side, u$pid, src))
      if (n != 1) stop(sprintf("--replace: narrativ-UPDATE ramte %d rækker for person %d (forventet 1) — fail-closed.", n, u$pid))
    }
    for (u in replace_koen)
      ex("UPDATE person SET koen=$1 WHERE id=$2", list(u$koen, u$pid))

    # EFTERVERIFIKATION (blokerende, jf. designdok): alt redaktionelt og al
    # struktur uden for replace-scope SKAL være uændret. Person-antal uændret
    # (ingen nye personer i replace v1 — pass 2 er skippet).
    efter <- dbGetQuery(con, sprintf(
      "SELECT (SELECT count(*) FROM relation WHERE rolle IN ('samme_som','ikke_samme_som')) samme_som,
              (SELECT count(*) FROM change_set) cs, (SELECT count(*) FROM change_event) ce,
              (SELECT count(*) FROM family_member) fm, (SELECT count(*) FROM person) pers,
              (SELECT count(*) FROM narrative WHERE source_id=%d) narr", src))
    for (kol in names(replace_invarianter)) {
      if (!identical(as.integer(efter[[kol]]), as.integer(replace_invarianter[[kol]])))
        stop(sprintf("--replace: invariant '%s' ændrede sig (%s → %s) — ROLLBACK.",
                     kol, replace_invarianter[[kol]], efter[[kol]]))
    }
    message("REPLACE: alle invarianter uændrede (samme_som/change_set/change_event/family_member/person/narrativ-antal).")
  }

  # Først efter en vellykket buffer-flush må en ændret kilde markere journalen stale.
  # Én samlet UPDATE bevarer den atomare load-transaktion; fejl længere nede ruller også
  # denne statusændring tilbage.
  stale_ids <- stale_correction_ids(stale_results)
  if (length(stale_ids))
    ex(sprintf("UPDATE import_korrektion SET status='stale' WHERE id IN (%s)",
               paste(as.integer(stale_ids), collapse = ",")))

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

  # ---- levende: GDPR-cache (invariant #8), afledt — redigeres ALDRIG manuelt.
  # Regel: født inden for seneste 100 år (ift. load-dato) UDEN død/begravelse/
  # dødsårsag-fakta og uden visning_doed => levende. Fail-closed: ukendt fødselsår
  # => FALSE (de udaterede er tidlige aner). Styrer RLS-synlighed (db-rls.sql).
  ref_aar <- as.integer(format(Sys.Date(), "%Y"))
  ex("UPDATE person SET levende = FALSE")
  ex(sprintf("UPDATE person p SET levende = TRUE
     WHERE EXISTS (SELECT 1 FROM conclusion c
            JOIN assertion a ON a.id=c.valgt_assertion_id
            JOIN fact f ON f.id=c.target_id AND c.target_type='fact'
           WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='fødsel'
             AND COALESCE(EXTRACT(YEAR FROM a.date_min),EXTRACT(YEAR FROM a.date_max)) >= %d)
       AND NOT EXISTS (SELECT 1 FROM fact f
           WHERE f.subjekt_type='person' AND f.subjekt_id=p.id
             AND f.faktatype IN ('død','begravelse','dødsårsag'))
       AND COALESCE(TRIM(p.visning_doed),'') = ''", ref_aar - 100L))

  if (DRY_RUN) {
    message("DRY-RUN: ingen commit. Bufret pr. tabel:")
    print(buffer_counts(.buf))
    dbRollback(con)
  } else {
    # IDENTITY-kontrakten (db-migrations 2026-07-31): nid() indsætter eksplicitte
    # id'er uden om sekvenserne — synk dem FØR commit, ellers kolliderer næste
    # DEFAULT-insert (RPC'erne) med loaderens rækker. FAIL-CLOSED (Codex-review
    # fund 1): en sync-fejl på en identity-tabel skal vælte transaktionen, ikke
    # logges — ellers committes data med desynket sekvens. Tabeller uden
    # identity (fx lokal testbase før migration) springes eksplicit over via
    # NULL-sekvens-tjekket; det er den eneste lovlige undtagelse.
    for (t in id_tables) {
      seq_navn <- dbGetQuery(con,
        sprintf("SELECT pg_get_serial_sequence('%s','id') s", t))$s[1]
      if (is.na(seq_navn) || is.null(seq_navn)) {
        message(sprintf("sekvens-sync: %s har ingen identity-sekvens (base før migration) — sprunget over", t))
      } else {
        ex(sprintf(
          "SELECT setval('%s', (SELECT coalesce(max(id),0)+1 FROM %s), false)",
          seq_navn, t))
      }
    }
    dbCommit(con); message(sprintf("Indlæst %d poster (udgave %s).", length(clean), udgave))
  }
}, error = function(e) { dbRollback(con); dbDisconnect(con)
  stop("Load fejlede, rullet tilbage: ", conditionMessage(e)) })

if (length(.unresolved$rows)) {
  ur <- do.call(rbind, lapply(.unresolved$rows, function(r) as.data.frame(r, stringsAsFactors = FALSE)))
  write.csv(ur, "work/load-unresolved.csv", row.names = FALSE)
  message(sprintf("BEMÆRK: %d uopløste barn-opslag — se work/load-unresolved.csv", nrow(ur)))
}

counts <- dbGetQuery(con, "SELECT 'person' t, count(*) n FROM person
  UNION ALL SELECT 'fact', count(*) FROM fact
  UNION ALL SELECT 'family_member', count(*) FROM family_member
  UNION ALL SELECT 'relation', count(*) FROM relation
  UNION ALL SELECT 'narrative', count(*) FROM narrative ORDER BY 1")
cat("\nRækker pr. tabel:\n"); print(counts, row.names = FALSE)
dbDisconnect(con)
