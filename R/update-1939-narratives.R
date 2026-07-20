#!/usr/bin/env Rscript

# Transactional, fail-closed updater for the already loaded DAA 1939 narratives
# (staged or already selectively published via red_publicer_personer — §7.20).
# Dry-run is the default. This script never creates persons, families, facts,
# links, sources, or narratives; it only updates tekst+side on the existing
# one-to-one source-1939 narrative rows.

suppressPackageStartupMessages({
  library(DBI)
  library(jsonlite)
  library(RPostgres)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)

parse_update_1939_args <- function(args) {
  value_after <- function(prefix, default = NULL) {
    hit <- args[startsWith(args, paste0(prefix, "="))]
    if (!length(hit)) return(default)
    sub(paste0("^", prefix, "="), "", hit[[1]])
  }
  positional <- args[!startsWith(args, "--")]
  list(
    artifact = if (length(positional)) positional[[1]] else
      "work_1939_stamtavle/clean_1939.json",
    apply = "--apply" %in% args,
    allow_local = "--allow-local" %in% args,
    expected_project_ref = value_after(
      "--expected-project-ref", Sys.getenv("EXPECTED_SUPABASE_PROJECT_REF")),
    expected_source_id = as.integer(value_after("--expected-source-id", "3"))
  )
}

load_1939_narrative_patch <- function(path) {
  if (!file.exists(path)) stopf("Artefakt findes ikke: %s", path)
  records <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!is.list(records) || length(records) != 539L) {
    stopf("Artefakt skal have præcis 539 poster; fandt %s", length(records))
  }
  side_of <- function(record) {
    value <- record$sider %||% NA_character_
    if (is.na(value) || !nzchar(trimws(as.character(value)))) NA_character_
    else as.character(value)
  }
  patch <- data.frame(
    nr = vapply(records, function(x) as.integer(x$nr), integer(1)),
    tekst = vapply(records, function(x) as.character(x$narrative %||% ""), character(1)),
    side = vapply(records, side_of, character(1)),
    stringsAsFactors = FALSE
  )
  if (anyNA(patch$nr) || !identical(sort(patch$nr), seq_len(539L))) {
    stop("Artefaktets nr skal være unikke 1..539", call. = FALSE)
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

connect_update_1939 <- function(config) {
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

source_1939 <- function(con, expected_source_id) {
  rows <- dbGetQuery(
    con,
    "SELECT id, udgave, aar, slags FROM public.source WHERE aar=1939 ORDER BY id"
  )
  if (nrow(rows) != 1L) stopf("Forventede én source med aar=1939; fandt %s", nrow(rows))
  if (as.integer(rows$id[[1]]) != expected_source_id ||
      rows$udgave[[1]] != "DAA 1939" || rows$slags[[1]] != "DAA-udgave") {
    stop("1939-source matcher ikke forventet id/udgave/slags", call. = FALSE)
  }
  as.integer(rows$id[[1]])
}

read_1939_mapping <- function(con, source_id) {
  rows <- dbGetQuery(
    con,
    paste(
      "SELECT pe.nr, pe.person_id, n.id AS narrative_id, n.tekst, n.side,",
      "       p.staged, p.levende, p.privat",
      "FROM public.person_external_id pe",
      "JOIN public.person p ON p.id=pe.person_id",
      "JOIN public.narrative n",
      "  ON n.subjekt_type='person' AND n.subjekt_id=pe.person_id",
      " AND n.source_id=pe.source_id",
      "WHERE pe.source_id=$1 ORDER BY pe.nr"
    ),
    params = list(source_id)
  )
  if (nrow(rows) != 539L || length(unique(rows$person_id)) != 539L ||
      length(unique(rows$narrative_id)) != 539L ||
      !identical(as.integer(rows$nr), seq_len(539L))) {
    stop("Prod-mapping er ikke 539 entydige nr/person/narrative-rækker", call. = FALSE)
  }
  # Tolererer bevidst BLANDET staged-status (§7.20 selektiv publicering, red_publicer_personer):
  # redaktøren kan have publiceret nogle 1939-personer (bekræftet samme_som) mens resten stadig
  # afventer. UPDATE'en nedenfor er staged-agnostisk (opdaterer tekst/side uanset synlighed) —
  # dette er blot en oplysende note, ikke en gate.
  n_publiceret <- sum(!rows$staged)
  if (n_publiceret > 0L) {
    message(sprintf(
      "%d af 539 1939-hovedpersoner er allerede publiceret (staged=false) — deres narrativer opdateres direkte i den offentlige visning.",
      n_publiceret
    ))
  }
  rows
}

different_text <- function(old, new) old != new

different_nullable <- function(old, new) {
  xor(is.na(old), is.na(new)) | (!is.na(old) & !is.na(new) & old != new)
}

plan_1939_update <- function(mapping, patch) {
  merged <- merge(mapping, patch, by = "nr", all = TRUE, sort = TRUE,
                  suffixes = c("_old", "_new"))
  if (nrow(merged) != nrow(patch) || nrow(mapping) != nrow(patch) ||
      anyNA(merged$narrative_id)) {
    stop("Artefakt og DB kunne ikke joines 1:1 på nr", call. = FALSE)
  }
  text_changed <- different_text(merged$tekst_old, merged$tekst_new)
  side_changed <- different_nullable(merged$side_old, merged$side_new)
  merged$text_changed <- text_changed
  merged$side_changed <- side_changed
  merged$changed <- text_changed | side_changed
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
    "%s: 539 matches; %d tekstændringer; %d sideændringer; %d rækker i alt ændres.",
    if (apply) "APPLY" else "DRY-RUN",
    sum(plan$text_changed), sum(plan$side_changed), sum(plan$changed)
  ))
}

apply_1939_update <- function(con, source_id, plan, patch) {
  changed <- patch[patch$nr %in% plan$nr[plan$changed], , drop = FALSE]
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
      "'bulk_update_1939_narratives',",
      "'Regenererede 1939-narrativer efter deterministisk kvalitetsrettelse',",
      "NULL, NULL) AS id"
    )
  )$id[[1]]

  dbExecute(con, "CREATE TEMP TABLE narrative_1939_patch (nr integer PRIMARY KEY, tekst text NOT NULL, side text)")
  dbAppendTable(con, "narrative_1939_patch", changed)
  updated <- dbGetQuery(
    con,
    paste(
      "UPDATE public.narrative n SET tekst=x.tekst, side=x.side",
      "FROM public.person_external_id pe",
      "JOIN narrative_1939_patch x ON x.nr=pe.nr",
      "WHERE pe.source_id=$1 AND n.subjekt_type='person'",
      "  AND n.subjekt_id=pe.person_id AND n.source_id=pe.source_id",
      "  AND (n.tekst IS DISTINCT FROM x.tekst OR n.side IS DISTINCT FROM x.side)",
      "RETURNING n.id"
    ),
    params = list(source_id)
  )
  events <- dbGetQuery(
    con, "SELECT count(*) AS n FROM public.change_event WHERE change_set_id=$1",
    params = list(change_set_id)
  )$n[[1]]
  list(updated = nrow(updated), change_set_id = change_set_id, events = events)
}

run_update_1939 <- function(config) {
  patch <- load_1939_narrative_patch(config$artifact)
  con <- connect_update_1939(config)
  on.exit(dbDisconnect(con), add = TRUE)
  dbBegin(con)
  committed <- FALSE
  on.exit(if (!committed && dbIsValid(con)) try(dbRollback(con), silent = TRUE), add = TRUE)
  dbExecute(con, if (config$apply)
    "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE"
  else "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
  dbExecute(con, "SET LOCAL lock_timeout='10s'")
  dbExecute(con, "SET LOCAL statement_timeout='120s'")

  source_id <- source_1939(con, config$expected_source_id)
  mapping <- read_1939_mapping(con, source_id)
  plan <- plan_1939_update(mapping, patch)
  before <- core_snapshot(con)
  print_plan(plan, config$apply)

  if (!config$apply) {
    dbRollback(con)
    committed <- TRUE
    message("DRY-RUN færdig; ingen DB-ændringer.")
    return(invisible(list(plan = plan, before = before)))
  }

  result <- apply_1939_update(con, source_id, plan, patch)
  if (result$updated != sum(plan$changed)) {
    stopf("UPDATE ramte %s rækker; forventede %s", result$updated, sum(plan$changed))
  }
  after_mapping <- read_1939_mapping(con, source_id)
  after_plan <- plan_1939_update(after_mapping, patch)
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

main_update_1939 <- function(args = commandArgs(trailingOnly = TRUE)) {
  run_update_1939(parse_update_1939_args(args))
}

if (sys.nframe() == 0L) main_update_1939()
