# Disponerbar #196 proposal-fixture.  Den opretter først et nyt, syntetisk
# #148-klausulgrundlag i en separat R-proces. Det undgår, at `source()`
# genbruger den forrige fixtures afsluttede DBI external pointer.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite); library(digest) })

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"))
stopifnot(nzchar(Sys.getenv("PGHOST")), nzchar(Sys.getenv("PGPORT")),
  nzchar(Sys.getenv("PGDATABASE")), nzchar(Sys.getenv("PGUSER")))
connect <- function() dbConnect(Postgres(), dbname = Sys.getenv("PGDATABASE"),
  host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
  user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
con <- connect(); on.exit(dbDisconnect(con), add = TRUE)
q <- function(sql, params = list())
  if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
e <- function(sql, params = list())
  invisible(if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql))

clause_fixture <- file.path(root, "tests/integration/test-reimport-clause-evidence.R")
clause_out <- suppressWarnings(system2("Rscript", shQuote(clause_fixture), stdout = TRUE, stderr = TRUE))
if (!is.null(attr(clause_out, "status")) || !any(clause_out == "clause_evidence integration OK")) {
  stop("syntetisk clause-fixture fejlede: ", paste(clause_out, collapse = "\n"))
}

seed <- q(paste(
  "SELECT batch.source_id,event.source_record_key,profile.profile_id,profile.profile_sha256,profile.writer_config::text AS writer_config",
  "FROM private.reimport_event event",
  "JOIN private.reimport_batch batch ON batch.id=event.batch_id",
  "JOIN private.reimport_writer_profile profile ON profile.source_id=batch.source_id AND profile.profile_id=batch.profile_id AND profile.profile_sha256=batch.profile_sha256",
  "WHERE event.operation='clause_evidence' ORDER BY event.id DESC LIMIT 1"))
stopifnot(nrow(seed) == 1L)
source_id <- as.integer(seed$source_id[[1L]])
key_dead <- as.character(seed$source_record_key[[1L]])
ce_profile_id <- as.character(seed$profile_id[[1L]])
ce_sha <- as.character(seed$profile_sha256[[1L]])
ce_config <- as.character(seed$writer_config[[1L]])
clauses <- q(paste(
  "SELECT observation.clause_ordinal AS ordinal,encode(extensions.digest(convert_to(observation.verbatim_text,'UTF8'),'sha256'),'hex') AS verbatim_sha256",
  "FROM private.source_observation observation",
  "JOIN private.source_record_anchor_current anchor ON anchor.occurrence_id=observation.occurrence_id AND anchor.decision_status='accepted'",
  "JOIN private.source_record record ON record.id=anchor.source_record_id",
  "WHERE record.source_id=$1 AND record.record_key=$2 AND observation.parent_observation_id IS NOT NULL",
  "ORDER BY observation.clause_ordinal"), list(source_id, key_dead))
stopifnot(nrow(clauses) == 2L, identical(as.integer(clauses$ordinal), 1:2))

actor <- "14900000-0000-4000-8000-000000000003"
e("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)
env_gateway <- function() new_reimport_dbi_gateway(connect)
database_identity <- q("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS identity")$identity[[1L]]
authorize <- function(manifest, preview_sha) q(paste(
  "SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
  "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
  list(manifest$manifest_content_sha256, preview_sha, database_identity,
    manifest$source$id, manifest$source$profile_id, manifest$source$profile_sha256,
    jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
    jsonlite::toJSON(reimport_authorized_payloads(manifest), auto_unbox = TRUE, null = "null")))$id[[1L]]
run_nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
run_hash <- function(tag) digest::digest(paste(run_nonce, tag), algo = "sha256", serialize = FALSE)
count1 <- function(sql, params = list()) as.integer(q(sql, params)[[1L]][[1L]])

proposal_profile_id <- paste0(ce_profile_id, "-proposal-", substr(run_hash("profile"), 1L, 12L))
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'interpretation-proposal-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, proposal_profile_id, ce_sha, ce_config))

claim <- function(id, value, cited) list(
  claim_id = id, predicate = "person.name", interpretation_kind = "property",
  value = value, confidence = 0.9, cited_clauses = cited, persona_role = "other")
proposal_manifest <- list(
  manifest_content_sha256 = run_hash("manifest-proposal"),
  source = list(id = source_id, profile_id = proposal_profile_id, profile_sha256 = ce_sha),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L,
    interpretation_proposals = 1L),
  operations = list(list(
    element_id = paste0("interpretation-proposal:", key_dead),
    dependency_class = "interpretation_proposal", source_record_key = key_dead,
    runner_manifest_sha256 = run_hash("runner-proposal"), model_version = "fixture-model-v1",
    prompt_version = "fixture-prompt-v1", claims = list(
      claim("11111111111111111111111111111111", "Fixture navn", list(
        list(ordinal = as.integer(clauses$ordinal[[1L]]), verbatim_sha256 = clauses$verbatim_sha256[[1L]]))),
      claim("22222222222222222222222222222222", "Anden aktør", list(
        list(ordinal = as.integer(clauses$ordinal[[1L]]), verbatim_sha256 = clauses$verbatim_sha256[[1L]]),
        list(ordinal = as.integer(clauses$ordinal[[2L]]), verbatim_sha256 = clauses$verbatim_sha256[[2L]])))
    ))))

validate_reimport_manifest(proposal_manifest)
preview_sha <- run_hash("preview-proposal")
before_events <- count1("SELECT count(*) FROM private.reimport_event WHERE operation='interpretation_proposal'")
dry <- execute_reimport(proposal_manifest, preview_sha, "dry-run", env_gateway(), NULL)
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
  count1("SELECT count(*) FROM private.reimport_event WHERE operation='interpretation_proposal'") == before_events)

applied <- execute_reimport(proposal_manifest, preview_sha, "apply", env_gateway(),
  list(id = authorize(proposal_manifest, preview_sha)), authorization_policy = "external")
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))

event <- q("SELECT payload::text AS payload,after_sha256 FROM private.reimport_event WHERE operation='interpretation_proposal' AND source_record_key=$1 ORDER BY id DESC LIMIT 1", list(key_dead))
stopifnot(nrow(event) == 1L)
payload <- jsonlite::fromJSON(event$payload[[1L]], simplifyVector = FALSE)
receipt <- payload$result_receipt
stopifnot(identical(sort(names(receipt)), c("claims", "clause_dispositions", "schema_version")),
  identical(receipt$schema_version, "interpretation-proposal-result-v1"),
  length(receipt$claims) == 2L, length(receipt$clause_dispositions) == 2L,
  identical(event$after_sha256[[1L]], q("SELECT private.interpretation_proposal_canonical_json_sha256($1::jsonb) AS hash", list(jsonlite::toJSON(receipt, auto_unbox = TRUE, null = "null")))$hash[[1L]]))
stopifnot(all(vapply(receipt$claims, function(x) identical(sort(names(x)), sort(c(
  "claim_id", "interpretation_id", "interpretation_key", "version", "value_sha256",
  "key_material_sha256", "row_sha256", "extraction_run_id", "observations"))), logical(1))))
stopifnot(count1("SELECT count(*) FROM private.clause_disposition_current d JOIN private.source_observation o ON o.id=d.observation_id WHERE o.parent_observation_id IS NOT NULL AND d.disposition='afventer_identitet'") >= 2L)
cat("interpretation_proposal receipt integration OK\n")
