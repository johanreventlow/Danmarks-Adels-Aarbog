#!/usr/bin/env Rscript
# Markering-bevarende merge af validerede hændelser. Kør fra repo-roden.
suppressMessages({library(DBI); library(jsonlite); library(RPostgres)})
source(".claude/skills/daa-haendelser/scripts/load_haendelser_helpers.R")

argv <- commandArgs(trailingOnly = TRUE)
if (!length(argv)) stop("brug: load_haendelser.R clean.json [--dry-run]")
path <- argv[[1]]
DRY_RUN <- "--dry-run" %in% argv
unknown_flags <- argv[startsWith(argv, "--") & argv != "--dry-run"]
if (length(unknown_flags)) stop("Ukendte flag: ", paste(unknown_flags, collapse=", "))

clean <- fromJSON(path, simplifyVector = FALSE)
if (!is.list(clean)) stop("clean.json skal være en liste")
narrative_ids <- unique(vapply(clean, function(x) as.numeric(x$narrative_id), numeric(1)))
if (any(!is.finite(narrative_ids) | narrative_ids %% 1 != 0)) stop("Ugyldigt narrative_id i clean.json")

host <- Sys.getenv("SUPABASE_HOST"); user <- Sys.getenv("SUPABASE_USER"); pw <- Sys.getenv("SUPABASE_PASSWORD")
if (host == "" || user == "" || pw == "") stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.")
con <- dbConnect(
  RPostgres::Postgres(), host=host, port=as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
  dbname=Sys.getenv("SUPABASE_DB", "postgres"), user=user, password=pw,
  sslmode=Sys.getenv("SUPABASE_SSLMODE", "require"), bigint="integer64"
)
on.exit(if (dbIsValid(con)) dbDisconnect(con), add=TRUE)

id_sql <- function(ids) paste(format(ids, scientific=FALSE, trim=TRUE), collapse=",")
scalar_chr <- function(x) if (is.null(x) || !length(x) || is.na(x)) NA_character_ else as.character(x)
scalar_num <- function(x) if (is.null(x) || !length(x) || is.na(x)) NA_real_ else as.numeric(x)
empty_new <- function() data.frame(
  subjekt_type=character(), subjekt_id=numeric(), narrative_id=numeric(), noegle=character(),
  span_start=integer(), span_laengde=integer(), klausul=character(), kategori=character(),
  date_min=character(), date_max=character(), date_qualifier=character(), date_raw=character(),
  fact_id=numeric(), relation_id=numeric(), pass_version=character(), stringsAsFactors=FALSE)
bind_rows <- function(rows) {
  if (!length(rows)) return(empty_new())
  out <- do.call(rbind, lapply(rows, function(x) as.data.frame(x, stringsAsFactors=FALSE)))
  rownames(out) <- NULL; out
}

unresolved <- list(); lost <- list()
counts <- c(updates=0L,inserts=0L,deletes=0L,overfoerte=0L,mistede=0L,uoploeste=0L)

dbBegin(con)
tryCatch({
  # Samme MAX(id)-konvention som DAA-loaderen; låsen serialiserer samtidige pipeline-loads.
  dbExecute(con, "LOCK TABLE haendelse IN SHARE ROW EXCLUSIVE MODE")
  next_id <- as.numeric(dbGetQuery(con, "SELECT coalesce(max(id),0) AS id FROM haendelse")$id[[1]])
  nid <- function() { next_id <<- next_id + 1; next_id }

  if (length(narrative_ids)) {
    narratives <- dbGetQuery(con, sprintf(
      "SELECT id,subjekt_type,subjekt_id,tekst FROM narrative WHERE id IN (%s)", id_sql(narrative_ids)))
    existing <- dbGetQuery(con, sprintf(
      paste0("SELECT id,subjekt_type,subjekt_id,narrative_id,noegle,span_start,span_laengde,klausul,",
             "kategori,date_min::text,date_max::text,date_qualifier,date_raw,feed_status,",
             "fact_id,relation_id,pass_version FROM haendelse WHERE narrative_id IN (%s)"),
      id_sql(narrative_ids)))
  } else {
    narratives <- data.frame(); existing <- data.frame()
  }
  subject_ids <- unique(narratives$subjekt_id[narratives$subjekt_type == "person"])
  if (length(subject_ids)) {
    facts <- dbGetQuery(con, sprintf(paste0(
      "SELECT f.id,f.subjekt_id,a.date_min::text,a.date_max::text,a.date_raw ",
      "FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id ",
      "AND c.status='afklaret' JOIN assertion a ON a.id=c.valgt_assertion_id ",
      "WHERE f.subjekt_type='person' AND f.subjekt_id IN (%s)"), id_sql(subject_ids)))
    relations <- dbGetQuery(con, sprintf(paste0(
      "SELECT r.id,r.subjekt_id,coalesce(a.date_min,r.start_min)::text AS date_min,",
      "coalesce(a.date_max,r.end_max,r.start_max)::text AS date_max,",
      "coalesce(a.date_raw,r.periode_raw) AS date_raw ",
      "FROM relation r JOIN conclusion c ON c.target_type='relation' AND c.target_id=r.id ",
      "AND c.status='afklaret' JOIN assertion a ON a.id=c.valgt_assertion_id ",
      "WHERE r.subjekt_type='person' AND r.subjekt_id IN (%s)"), id_sql(subject_ids)))
  } else {
    facts <- data.frame(); relations <- data.frame()
  }

  for (record in clean) {
    narrative_id <- as.numeric(record$narrative_id)
    nr <- narratives[narratives$id == narrative_id, , drop=FALSE]
    if (nrow(nr) != 1L || nr$subjekt_type[[1]] != "person") {
      unresolved[[length(unresolved)+1L]] <- list(narrative_id=narrative_id,noegle=NA,
        klausul=NA,grund="narrativ mangler eller er ikke et person-narrativ")
      next
    }
    text <- nr$tekst[[1]]; used <- integer(); rows <- list()
    fact_rows <- if (nrow(facts)) facts[facts$subjekt_id == nr$subjekt_id[[1]],,drop=FALSE] else facts
    relation_rows <- if (nrow(relations)) relations[relations$subjekt_id == nr$subjekt_id[[1]],,drop=FALSE] else relations
    for (event in record$haendelser %||% list()) {
      clause <- scalar_chr(event$klausul)
      span <- genberegn_span(text, clause, used)
      if (is.na(span$start)) {
        unresolved[[length(unresolved)+1L]] <- list(narrative_id=narrative_id,
          noegle=scalar_chr(event$noegle),klausul=clause,
          grund="klausul findes ikke længere ordret i narrative.tekst")
        next
      }
      used <- span$brugte_offsets
      normalized <- list(date_min=scalar_chr(event$date_min),date_max=scalar_chr(event$date_max),
                         date_raw=scalar_chr(event$date_raw))
      backbone <- match_rygrad(normalized, fact_rows, relation_rows)
      rows[[length(rows)+1L]] <- list(
        subjekt_type="person", subjekt_id=as.numeric(nr$subjekt_id[[1]]), narrative_id=narrative_id,
        noegle=scalar_chr(event$noegle), span_start=span$start, span_laengde=span$laengde,
        klausul=clause, kategori=scalar_chr(event$kategori), date_min=normalized$date_min,
        date_max=normalized$date_max, date_qualifier=scalar_chr(event$date_qualifier),
        date_raw=normalized$date_raw, fact_id=backbone$fact_id,
        relation_id=backbone$relation_id, pass_version=scalar_chr(event$pass_version))
    }
    new_rows <- bind_rows(rows)
    old_rows <- if (nrow(existing)) existing[existing$narrative_id == narrative_id,,drop=FALSE] else existing
    plan <- plan_merge(old_rows, new_rows)

    if (nrow(plan$updates)) for (i in seq_len(nrow(plan$updates))) {
      x <- plan$updates[i,,drop=FALSE]
      dbExecute(con, paste0(
        "UPDATE haendelse SET subjekt_type=$1,subjekt_id=$2,narrative_id=$3,noegle=$4,",
        "span_start=$5,span_laengde=$6,klausul=$7,kategori=$8,date_min=$9::date,date_max=$10::date,",
        "date_qualifier=$11,date_raw=$12,fact_id=$13,relation_id=$14,pass_version=$15 WHERE id=$16"),
        params=unname(list(x$subjekt_type,x$subjekt_id,x$narrative_id,x$noegle,x$span_start,
          x$span_laengde,x$klausul,x$kategori,x$date_min,x$date_max,x$date_qualifier,x$date_raw,
          x$fact_id,x$relation_id,x$pass_version,x$id)))
    }
    if (nrow(plan$inserts)) for (i in seq_len(nrow(plan$inserts))) {
      x <- plan$inserts[i,,drop=FALSE]
      dbExecute(con, paste0(
        "INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,span_start,span_laengde,",
        "klausul,kategori,date_min,date_max,date_qualifier,date_raw,feed_status,fact_id,relation_id,pass_version) ",
        "VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::date,$11::date,$12,$13,$14,$15,$16,$17)"),
        params=unname(list(nid(),x$subjekt_type,x$subjekt_id,x$narrative_id,x$noegle,x$span_start,
          x$span_laengde,x$klausul,x$kategori,x$date_min,x$date_max,x$date_qualifier,x$date_raw,
          x$feed_status,x$fact_id,x$relation_id,x$pass_version)))
    }
    if (nrow(plan$deletes)) for (id in plan$deletes$id)
      dbExecute(con, "DELETE FROM haendelse WHERE id=$1", params=list(id))

    if (nrow(plan$mistede)) for (i in seq_len(nrow(plan$mistede))) {
      x <- plan$mistede[i,,drop=FALSE]
      lost[[length(lost)+1L]] <- list(narrative_id=narrative_id,haendelse_id=x$id,
        noegle=x$noegle,status=x$feed_status,klausul=x$klausul)
    }
    counts <- counts + c(updates=nrow(plan$updates),inserts=nrow(plan$inserts),
      deletes=nrow(plan$deletes),overfoerte=nrow(plan$overfoerte),mistede=nrow(plan$mistede),uoploeste=0L)
  }
  counts[["uoploeste"]] <- length(unresolved)
  if (DRY_RUN) {
    dbRollback(con)
    message("DRY-RUN: transaktionen er rullet tilbage.")
  } else {
    dbCommit(con)
  }
}, error=function(e) {
  try(dbRollback(con), silent=TRUE)
  stop("Hændelses-load fejlede; transaktionen er rullet tilbage: ", conditionMessage(e))
})

dir.create("work/haendelser", recursive=TRUE, showWarnings=FALSE)
unresolved_df <- if (length(unresolved)) .bind_rows(unresolved) else
  data.frame(narrative_id=numeric(),noegle=character(),klausul=character(),grund=character())
lost_df <- if (length(lost)) .bind_rows(lost) else
  data.frame(narrative_id=numeric(),haendelse_id=numeric(),noegle=character(),status=character(),klausul=character())
write.csv(unresolved_df,"work/haendelser/load-unresolved.csv",row.names=FALSE,na="")
write.csv(lost_df,"work/haendelser/mistede-markeringer.csv",row.names=FALSE,na="")
message(paste(sprintf("%s=%d",names(counts),counts),collapse=", "))
if (counts[["mistede"]] > 0L) message("BEMÆRK: mistede markeringer er logget i work/haendelser/mistede-markeringer.csv")
