#!/usr/bin/env Rscript

# Transactional, fail-closed updater for DAA 2018-20-narrativer (source aar=2020).
# Dry-run er default. Rører KUN narrative.tekst for de rækker der er navngivet i
# artefaktet, matchet på (linje, nr) — modsat 1939-scriptet er dette IKKE en fuld
# 591-posters genkørsel, men en målrettet patch af de poster hvor en efterfølgende
# slaegtled-/kuld-overskrift blødte ind i forrige posts narrativ (audit 2026-07-26,
# segment.py's SLGT_RE/ROMAN_RE håndterer det korrekt i dag — bug'en sad kun i det
# allerede indlæste artefakt). Opretter aldrig personer, familier, fakta, links,
# kilder eller narrativer.

suppressPackageStartupMessages({
  library(DBI)
  library(jsonlite)
  library(RPostgres)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)

parse_update_2018_args <- function(args) {
  value_after <- function(prefix, default = NULL) {
    hit <- args[startsWith(args, paste0(prefix, "="))]
    if (!length(hit)) return(default)
    sub(paste0("^", prefix, "="), "", hit[[1]])
  }
  positional <- args[!startsWith(args, "--")]
  list(
    artifact = if (length(positional)) positional[[1]] else
      "work/patch_2018_slaegtled_bleed.json",
    apply = "--apply" %in% args,
    allow_local = "--allow-local" %in% args,
    expected_project_ref = value_after(
      "--expected-project-ref", Sys.getenv("EXPECTED_SUPABASE_PROJECT_REF")),
    expected_source_id = as.integer(value_after("--expected-source-id", "1"))
  )
}

load_2018_narrative_patch <- function(path) {
  if (!file.exists(path)) stopf("Artefakt findes ikke: %s", path)
  records <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!is.list(records) || length(records) == 0L) {
    stop("Artefaktet er tomt", call. = FALSE)
  }
  patch <- data.frame(
    linje = vapply(records, function(x) as.character(x$linje), character(1)),
    nr = vapply(records, function(x) as.integer(x$nr), integer(1)),
    tekst = vapply(records, function(x) as.character(x$narrative %||% ""), character(1)),
    stringsAsFactors = FALSE
  )
  if (anyNA(patch$linje) || !all(nzchar(patch$linje))) {
    stop("Artefaktet mangler linje på mindst én post", call. = FALSE)
  }
  if (anyNA(patch$nr)) stop("Artefaktet mangler nr på mindst én post", call. = FALSE)
  key <- paste(patch$linje, patch$nr, sep = "|")
  if (anyDuplicated(key)) {
    stop("Artefaktet har duplikerede (linje, nr)-nøgler", call. = FALSE)
  }
  if (any(!nzchar(trimws(patch$tekst)))) {
    stop("Artefaktet indeholder tomme narrativer", call. = FALSE)
  }
  patch
}

is_local_host <- function(host) {
  host %in% c("", "localhost", "127.0.0.1", "::1") || startsWith(host, "/")
}

assert_connection_target <- function(config, host, port, user) {
  if (config$allow_local) {
    if (!is_local_host(host)) stop("--allow-local kræver lokal DB-host", call. = FALSE)
    return(invisible(TRUE))
  }
  ref <- config$expected_project_ref
  if (!nzchar(ref)) {
    stop("Prod-kørsel kræver --expected-project-ref=<ref>", call. = FALSE)
  }
  if (!grepl(ref, paste(host, user), fixed = TRUE)) {
    stopf("Forbindelsen matcher ikke forventet project ref %s", ref)
  }
  if (port != 5432L) stopf("Prod kræver session-pooler port 5432; fandt %s", port)
  invisible(TRUE)
}

connect_update_2018 <- function(config) {
  host <- Sys.getenv("SUPABASE_HOST")
  user <- Sys.getenv("SUPABASE_USER")
  pw <- Sys.getenv("SUPABASE_PASSWORD")
  port <- as.integer(Sys.getenv("SUPABASE_PORT", "5432"))
  dbname <- Sys.getenv("SUPABASE_DB", "postgres")
  if (!nzchar(user) || (!config$allow_local && !nzchar(pw))) {
    stop("SUPABASE_USER/PASSWORD mangler", call. = FALSE)
  }
  assert_connection_target(config, host, port, user)
  args <- list(drv = RPostgres::Postgres(), dbname = dbname, user = user,
               bigint = "numeric")
  if (nzchar(pw)) args$password <- pw
  if (nzchar(host)) args$host <- host
  if (nzchar(Sys.getenv("SUPABASE_PORT"))) args$port <- port
  if (!config$allow_local) args$sslmode <- "require"
  do.call(DBI::dbConnect, args)
}

source_2018 <- function(con, expected_source_id) {
  rows <- dbGetQuery(
    con,
    "SELECT id, aar, slags FROM public.source WHERE aar=2020 ORDER BY id"
  )
  if (nrow(rows) != 1L) stopf("Forventede én source med aar=2020; fandt %s", nrow(rows))
  if (as.integer(rows$id[[1]]) != expected_source_id || rows$slags[[1]] != "DAA-udgave") {
    stop("2018-20-source matcher ikke forventet id/slags", call. = FALSE)
  }
  as.integer(rows$id[[1]])
}

# Kun de (linje,nr)-nøgler artefaktet navngiver — IKKE alle 591 poster (modsat 1939).
# Fail-closed på flertydighed: (linje,nr) er IKKE globalt unikt i denne udgave
# (under-litererede poster som I-15a/b/c deler basenr) — matches derfor kun rækker
# der er entydige i DB'en.
#
# jsonb_to_recordset() af ÉT json-parameter i stedet for en CREATE TEMP TABLE:
# sidstnævnte er DDL og fejler i en READ ONLY-transaktion (dry-run). Et flerværdi-
# array som separat bind-parameter er også fravalgt — RPostgres tolker et vektor-
# parameter blandet med skalar-parametre som (fejlslagen) batch-udførsel, ikke som
# ét array-typed bind. Ét JSON-parameter virker uændret i begge transaktions-tilstande.
read_2018_mapping <- function(con, source_id, patch) {
  keys_json <- jsonlite::toJSON(patch[, c("linje", "nr")], dataframe = "rows")
  rows <- dbGetQuery(
    con,
    paste(
      "SELECT pe.linje, pe.nr, pe.person_id, n.id AS narrative_id, n.tekst,",
      "       p.staged, count(*) OVER (PARTITION BY pe.linje, pe.nr) AS n_match",
      "FROM jsonb_to_recordset($2::jsonb) AS k(linje text, nr int)",
      "JOIN public.person_external_id pe ON pe.source_id=$1 AND pe.linje=k.linje AND pe.nr=k.nr",
      "JOIN public.person p ON p.id=pe.person_id",
      "JOIN public.narrative n",
      "  ON n.subjekt_type='person' AND n.subjekt_id=pe.person_id AND n.source_id=pe.source_id"
    ),
    params = list(source_id, as.character(keys_json))
  )
  tvetydige <- unique(rows[rows$n_match > 1L, c("linje", "nr")])
  if (nrow(tvetydige)) {
    stop(sprintf(
      "%d (linje,nr)-nøgle(r) er flertydige i DB'en (delt basenr, fx a/b/c-under-numre): %s",
      nrow(tvetydige), paste(sprintf("%s-%d", tvetydige$linje, tvetydige$nr), collapse = ", ")
    ), call. = FALSE)
  }
  if (nrow(rows) != nrow(patch)) {
    stopf("Fandt %d af %d navngivne (linje,nr)-rækker i DB'en", nrow(rows), nrow(patch))
  }
  rows$n_match <- NULL
  rows
}

plan_2018_update <- function(mapping, patch) {
  merged <- merge(mapping, patch, by = c("linje", "nr"), all = TRUE, sort = TRUE,
                  suffixes = c("_old", "_new"))
  if (nrow(merged) != nrow(patch) || anyNA(merged$narrative_id)) {
    stop("Artefakt og DB kunne ikke joines 1:1 på (linje, nr)", call. = FALSE)
  }
  merged$changed <- merged$tekst_old != merged$tekst_new
  merged
}

core_snapshot <- function(con) {
  row <- dbGetQuery(con, paste(
    "SELECT",
    "(SELECT count(*) FROM public.person) AS persons,",
    "(SELECT count(*) FROM public.narrative) AS narratives,",
    "(SELECT count(*) FROM public.source) AS sources,",
    "(SELECT count(*) FROM public.person_external_id) AS external_ids,",
    "(SELECT count(*) FROM public.family_member) AS family_members,",
    "(SELECT count(*) FROM public.family_member WHERE rolle='barn') AS child_links,",
    "(SELECT count(*) FROM public.fact) AS facts,",
    "(SELECT count(*) FROM public.assertion) AS assertions,",
    "(SELECT count(*) FROM public.relation) AS relations,",
    "(SELECT count(*) FROM public.person WHERE staged) AS staged"
  ))
  vapply(row, as.character, character(1))
}

print_plan <- function(plan, apply) {
  message(sprintf(
    "%s: %d navngivne poster; %d tekstændringer.",
    if (apply) "APPLY" else "DRY-RUN", nrow(plan), sum(plan$changed)
  ))
}

apply_2018_update <- function(con, source_id, plan, patch) {
  changed <- merge(patch, plan[plan$changed, c("linje", "nr")], by = c("linje", "nr"))
  if (!nrow(changed)) return(list(updated = 0L, change_set_id = NA_real_, events = 0L))

  dbExecute(
    con,
    "LOCK TABLE public.source, public.person, public.person_external_id IN SHARE MODE"
  )
  dbExecute(
    con,
    paste(
      "LOCK TABLE public.narrative, public.text_mention, public.change_set,",
      "public.change_event IN SHARE ROW EXCLUSIVE MODE"
    )
  )
  change_set_id <- dbGetQuery(
    con,
    paste(
      "SELECT public.begin_change_set(",
      "'targeted_update_2018_narratives',",
      "'Rettede slaegtled-/kuld-overskrift der bloedte ind i forrige posts narrativ',",
      "NULL, NULL) AS id"
    )
  )$id[[1]]

  changed_json <- jsonlite::toJSON(changed[, c("linje", "nr", "tekst")], dataframe = "rows")
  updated <- dbGetQuery(
    con,
    paste(
      "UPDATE public.narrative n SET tekst=x.tekst",
      "FROM public.person_external_id pe",
      "JOIN jsonb_to_recordset($2::jsonb) AS x(linje text, nr int, tekst text)",
      "  ON x.linje=pe.linje AND x.nr=pe.nr",
      "WHERE pe.source_id=$1 AND n.subjekt_type='person'",
      "  AND n.subjekt_id=pe.person_id AND n.source_id=pe.source_id",
      "  AND n.tekst IS DISTINCT FROM x.tekst",
      "RETURNING n.id"
    ),
    params = list(source_id, as.character(changed_json))
  )
  events <- dbGetQuery(
    con, "SELECT count(*) AS n FROM public.change_event WHERE change_set_id=$1",
    params = list(change_set_id)
  )$n[[1]]
  list(updated = nrow(updated), change_set_id = change_set_id, events = events)
}

run_update_2018 <- function(config) {
  patch <- load_2018_narrative_patch(config$artifact)
  con <- connect_update_2018(config)
  on.exit(dbDisconnect(con), add = TRUE)
  dbBegin(con)
  committed <- FALSE
  on.exit(if (!committed && dbIsValid(con)) try(dbRollback(con), silent = TRUE), add = TRUE)
  dbExecute(con, if (config$apply)
    "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE"
  else "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
  dbExecute(con, "SET LOCAL lock_timeout='10s'")
  dbExecute(con, "SET LOCAL statement_timeout='120s'")

  source_id <- source_2018(con, config$expected_source_id)
  mapping <- read_2018_mapping(con, source_id, patch)
  plan <- plan_2018_update(mapping, patch)
  before <- core_snapshot(con)
  print_plan(plan, config$apply)

  if (!config$apply) {
    dbRollback(con)
    committed <- TRUE
    message("DRY-RUN færdig; ingen DB-ændringer.")
    return(invisible(list(plan = plan, before = before)))
  }

  result <- apply_2018_update(con, source_id, plan, patch)
  if (result$updated != sum(plan$changed)) {
    stopf("UPDATE ramte %s rækker; forventede %s", result$updated, sum(plan$changed))
  }
  after_mapping <- read_2018_mapping(con, source_id, patch)
  after_plan <- plan_2018_update(after_mapping, patch)
  if (any(after_plan$changed)) stop("Post-update artefaktdiff er ikke nul", call. = FALSE)
  after <- core_snapshot(con)
  if (!identical(before, after)) {
    stop("Kerneinvarianter ændrede sig under narrative-only update", call. = FALSE)
  }
  dbCommit(con)
  committed <- TRUE
  message(sprintf(
    "COMMIT OK: %d narrativer; change_set=%s; %s audit-events.",
    result$updated, as.character(result$change_set_id), as.character(result$events)
  ))
  invisible(list(plan = plan, before = before, after = after, result = result))
}

main_update_2018 <- function(args = commandArgs(trailingOnly = TRUE)) {
  run_update_2018(parse_update_2018_args(args))
}

if (sys.nframe() == 0L) main_update_2018()
