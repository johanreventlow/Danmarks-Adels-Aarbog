#!/usr/bin/env Rscript
# Record-scoped runner-input til dagsværk 4.3b (plan Task 0 Step 8, spec §6.1).
#
# Producerer præcis det objekt, `run_record_guarded` modtager: pr. record
# helposten og dens klausuler som (ordinal, verbatim_text, verbatim_sha256),
# plus personaen.
#
# `post_verbatim_text` er ankeret for `evidence_runner.canonical_record_input`
# og SKAL være helpostens ordrette tekst — samme felt, som eligibility-eksporten
# hasher. Divergerer de to, afviser værnet alt (eller bliver omgået).
# Trin 6a: begge læser helpostens GÆLDENDE tekst gennem private.helpost_text_current
# (tekstversionen efter en kildetekst-revision, ellers basisteksten). Klausulerne er
# det aktuelle sæt, og sættet skal være skåret af netop den tekst (text_id), ellers
# er de ikke delstrenge af posten (EXPORT_CLAUSE_SET_TEXT_MISMATCH).
#
# OUTPUTTET INDEHOLDER BIOGRAFITEKST. Filen skrives 0600 i en privat mappe uden
# for repoet og må aldrig committes.

suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
allowed <- c("--source-id", "--output-dir")
if (any(!flags %in% allowed) || anyDuplicated(flags) || !all(allowed %in% flags)) {
  stop("EXPORT_CLI_INVALID", call. = FALSE)
}
value <- function(flag) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args) || grepl("^--", args[[i + 1L]])) stop("EXPORT_CLI_INVALID", call. = FALSE)
  args[[i + 1L]]
}
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])))
source(file.path(script_dir, "export_legacy_migration_candidates_helpers.R"))

source_id <- suppressWarnings(as.integer(value("--source-id")))
if (is.na(source_id) || source_id <= 0L) stop("EXPORT_CLI_INVALID", call. = FALSE)
output_dir <- lmc_validate_output_dir(value("--output-dir"))
out_path <- file.path(output_dir, "runner-input-v1.json")
if (file.exists(out_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)

con <- DBI::dbConnect(RPostgres::Postgres(),
                      dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
                      port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"),
                      password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")

# Helposten: parent_observation_id IS NULL. Samme afgrænsning som
# eligibility-eksporten bruger til sin hash — de to SKAL følges ad.
posts <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, ob.id AS post_id, cur.verbatim_text AS post_text, cur.text_id::text AS text_id,
         COALESCE(sp.id::text, '') AS persona_id
    FROM private.source_record sr
    JOIN private.source_record_anchor_current a ON a.source_record_id = sr.id
                                               AND a.decision_status = 'accepted'
    JOIN private.source_observation ob ON ob.occurrence_id = a.occurrence_id
                                      AND ob.parent_observation_id IS NULL
    CROSS JOIN LATERAL private.helpost_text_current(ob.id) cur
    -- Personaen kobles på `persona_key`, som for 2018-20 ER record-nøglen (målt:
    -- 587 af 587 matcher). Der er ingen FK fra source_persona til source_record.
    -- FIRE records har ingen persona — 149b's `unresolved_text`. De får tom
    -- persona_id, og preflighten afviser dem, fordi et person.*-claim så ikke kan
    -- bindes til nogen.
    LEFT JOIN LATERAL (
      SELECT p.id FROM private.source_persona p
       WHERE p.source_id = sr.source_id AND p.persona_key = sr.record_key
       ORDER BY p.id LIMIT 1
    ) sp ON TRUE
   WHERE sr.source_id = $1
   ORDER BY sr.record_key COLLATE \"C\"", params = list(source_id))

clauses <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, ob.clause_ordinal AS ordinal, ob.verbatim_text,
         encode(extensions.digest(ob.verbatim_text, 'sha256'), 'hex') AS verbatim_sha256,
         ob.parent_text_id::text AS parent_text_id
    FROM private.source_record sr
    JOIN private.source_record_anchor_current a ON a.source_record_id = sr.id
                                               AND a.decision_status = 'accepted'
    JOIN private.source_observation parent ON parent.occurrence_id = a.occurrence_id
                                          AND parent.parent_observation_id IS NULL
    JOIN private.clause_observation_current ob ON ob.parent_observation_id = parent.id
   WHERE sr.source_id = $1
   ORDER BY sr.record_key COLLATE \"C\", ob.clause_ordinal", params = list(source_id))

DBI::dbExecute(con, "ROLLBACK")
if (nrow(posts) == 0L) stop("EXPORT_NO_ROWS", call. = FALSE)

records <- list()
for (i in seq_len(nrow(posts))) {
  key <- posts$record_key[i]
  own <- clauses[clauses$record_key == key, , drop = FALSE]
  # Sættet skal være bundet til den eksporterede tekstversion (NA = basisteksten på begge sider).
  if (!all(vapply(own$parent_text_id, identical, logical(1), posts$text_id[i])))
    stop("EXPORT_CLAUSE_SET_TEXT_MISMATCH", call. = FALSE)
  cl <- lapply(seq_len(nrow(own)), function(j) list(
    ordinal = jsonlite::unbox(as.integer(own$ordinal[j])),
    verbatim_text = jsonlite::unbox(own$verbatim_text[j]),
    verbatim_sha256 = jsonlite::unbox(own$verbatim_sha256[j])))
  records[[key]] <- list(
    record_key = jsonlite::unbox(key),
    persona_id = jsonlite::unbox(posts$persona_id[i]),
    post_verbatim_text = jsonlite::unbox(posts$post_text[i]),
    clauses = cl)
}

writeLines(jsonlite::toJSON(list(
  schema_version = jsonlite::unbox("runner-input-1.0"),
  source_id = jsonlite::unbox(source_id),
  records = records), auto_unbox = FALSE, pretty = TRUE), out_path)
Sys.chmod(out_path, "0600")

cat(sprintf("RUNNER_INPUT_OK records=%d klausuler=%d uden_klausuler=%d\n",
            length(records), nrow(clauses),
            sum(vapply(records, function(r) length(r$clauses) == 0L, logical(1)))))
