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
# Trin 6c-1: helposten vælges med writerens regel (--writer-profile bestemmer slagsen), og personaen er
# helpostens primære mention.
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
allowed <- c("--source-id", "--output-dir", "--writer-profile")
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
writer_profile <- value("--writer-profile")
out_path <- file.path(output_dir, "runner-input-v1.json")
if (file.exists(out_path)) stop("EXPORT_OUTPUT_EXISTS", call. = FALSE)

con <- DBI::dbConnect(RPostgres::Postgres(),
                      dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
                      port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"),
                      password = Sys.getenv("PGPASSWORD"))
on.exit(DBI::dbDisconnect(con), add = TRUE)
DBI::dbExecute(con, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")

# Helpost-slagsen læses fra writerprofilen (private.writer_config_helpost_kind), aldrig hardkodet:
# 2018-20 er `person_post`, 1939 er `person`. Ukendt profil på kilden stopper eksporten.
kinds <- DBI::dbGetQuery(con, "
  SELECT DISTINCT private.writer_config_helpost_kind(writer_config) AS kind
    FROM private.reimport_writer_profile
   WHERE source_id = $1 AND profile_id = $2", params = list(source_id, writer_profile))
if (nrow(kinds) != 1L) stop("EXPORT_WRITER_PROFILE_UNKNOWN", call. = FALSE)
helpost_kind <- kinds$kind[[1L]]

# Helposten vælges som writeren gør det (trin 6a/6c-1): private.record_helpost_status(record, slags).
# En record kan have flere accepterede forekomster; helposten er den ene, hvis eneste topobservation har
# helpost-slagsen. Rækkefølge og antal forankringer påvirker ikke valget. Kun records med mindst én
# accepteret forankring eksporteres (som før). Status none udelader recorden (talt i
# uden_helpost); ambiguous/outside (writerens RECORD_HELPOST_AMBIGUOUS / RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE)
# giver EXPORT_HELPOST_NOT_UNIQUE.
# Personaen er helpostens `primary`-mention (som writeren); den samlede persona_id-liste tælles i R. Flere primære
# personas udelader recorden (talt i uden_entydig_persona; final-review F6): 1939-ledgeren udelukker den alligevel
# (no_published_persona), så hele eksporten skal ikke stoppe for den.
# NB: eksporten tager DISTINCT persona, mens writeren tæller primær-mention-rækker (nuller ved <> 1 række); de kan
# afvige, hvis samme persona har to primære mentions på helposten (udskudt, Task 4 minor 2).
posts <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, h.status, h.observation_id AS post_id,
         cur.verbatim_text AS post_text, cur.text_id::text AS text_id,
         COALESCE((SELECT string_agg(DISTINCT spm.persona_id::text, ',')
                     FROM private.source_mention sm
                     JOIN private.source_persona_mention spm ON spm.mention_id = sm.id
                                                            AND spm.mention_role = 'primary'
                    WHERE sm.observation_id = h.observation_id), '') AS persona_ids
    FROM private.source_record sr
    CROSS JOIN LATERAL private.record_helpost_status(sr.id, $2) h
    LEFT JOIN LATERAL private.helpost_text_current(h.observation_id) cur ON TRUE
   WHERE sr.source_id = $1
     AND EXISTS (SELECT 1 FROM private.source_record_anchor_current a
                  WHERE a.source_record_id = sr.id AND a.decision_status = 'accepted')
   ORDER BY sr.record_key COLLATE \"C\"", params = list(source_id, helpost_kind))

# Klausulerne er det aktuelle sæt under den valgte helpost (ikke under alle rodobservationer).
clauses <- DBI::dbGetQuery(con, "
  SELECT sr.record_key, ob.clause_ordinal AS ordinal, ob.verbatim_text,
         encode(extensions.digest(ob.verbatim_text, 'sha256'), 'hex') AS verbatim_sha256,
         ob.parent_text_id::text AS parent_text_id
    FROM private.source_record sr
    CROSS JOIN LATERAL private.record_helpost_status(sr.id, $2) h
    JOIN private.clause_observation_current ob ON ob.parent_observation_id = h.observation_id
   WHERE sr.source_id = $1 AND h.status = 'ok'
   ORDER BY sr.record_key COLLATE \"C\", ob.clause_ordinal", params = list(source_id, helpost_kind))

DBI::dbExecute(con, "ROLLBACK")
if (nrow(posts) == 0L) stop("EXPORT_NO_ROWS", call. = FALSE)

records <- list()
n_no_helpost <- 0L
n_ambiguous_persona <- 0L
for (i in seq_len(nrow(posts))) {
  key <- posts$record_key[i]
  # `none`: ingen helpost af profilens slags (fx strukturkontekst/krydshenvisning) -> ikke en modelpost; udeladt
  # og talt (eligibility-ledgeren dækker stadig alle records). ambiguous/outside afvises (fail-closed).
  if (identical(posts$status[i], "none")) { n_no_helpost <- n_no_helpost + 1L; next }
  if (!identical(posts$status[i], "ok")) stop("EXPORT_HELPOST_NOT_UNIQUE", call. = FALSE)
  pids <- strsplit(posts$persona_ids[i], ",", fixed = TRUE)[[1L]]
  if (length(pids) > 1L) { n_ambiguous_persona <- n_ambiguous_persona + 1L; next }
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
    persona_id = jsonlite::unbox(if (length(pids) == 1L) pids[[1L]] else ""),
    post_verbatim_text = jsonlite::unbox(posts$post_text[i]),
    clauses = cl)
}

writeLines(jsonlite::toJSON(list(
  schema_version = jsonlite::unbox("runner-input-1.0"),
  source_id = jsonlite::unbox(source_id),
  records = records), auto_unbox = FALSE, pretty = TRUE), out_path)
Sys.chmod(out_path, "0600")

cat(sprintf("RUNNER_INPUT_OK records=%d klausuler=%d uden_klausuler=%d uden_helpost=%d uden_entydig_persona=%d\n",
            length(records), sum(vapply(records, function(r) length(r$clauses), integer(1))),
            sum(vapply(records, function(r) length(r$clauses) == 0L, logical(1))),
            n_no_helpost, n_ambiguous_persona))
