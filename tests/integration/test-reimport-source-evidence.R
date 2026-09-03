# Disponerbar #149a source_evidence-integration.  Hver identitet, hash og
# tekst nedenfor er syntetisk; der oprettes intet historisk kildeindhold.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

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
  if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql)
sha <- function(letter) paste(rep(letter, 64L), collapse = "")
# Pr.-kørsel-nonce: manifest-/preview-hash og record_keys skal være unikke, ellers
# møder anden kørsel mod samme base sin egen finaliserede batch (already_applied)
# og record_keys fra første kørsel.  Replay-beviset ligger inde i kørslen.
run_nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
run_hash <- function(tag) digest::digest(paste(run_nonce, tag), algo = "sha256", serialize = FALSE)
run_key <- paste0("F", substr(run_hash("key"), 1L, 6L))

stopifnot(q("SELECT public.narrative_record_contract_version() v")$v[[1L]] == 2L)

actor <- "14900000-0000-4000-8000-000000000001"
source_id <- 149001L
profile_id <- "fixture-source-evidence-v1"
writer_config <- paste0('{"citation_label_template":"Synthetic side {page_from}",',
  '"extractor_version":"fixture-v1","observation_extraction_method":"deterministic_segment_v1",',
  '"rendition_key":"fixture-pdftotext-r1","rendition_kind":"pdf_text_layer",',
  '"rendition_metadata":{"edition":"fixture","pdf_sha256":"', sha("a"),
  '","pdftotext_version":"fixture 0.0"},"run_key_prefix":"reimport-source-evidence:",',
  '"schema_version":"source-evidence-manifest-v1"}')

e("INSERT INTO auth.users(id,email) VALUES($1,'149a@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'149a@example.invalid','redaktion','Task 149a') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Fixture','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING", list(source_id))
profile_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(writer_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'source-evidence-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, profile_id, profile_sha, writer_config))
e("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))

rendition_sha <- sha("c")
operation <- function(key, char_from, char_to, page_from, page_to, text) list(
  element_id = paste0("source-evidence:", key), dependency_class = "source_evidence",
  source_record_key = key, source_id = source_id, category = "person_post",
  disposition = "retain_source_only", rendition_content_sha256 = rendition_sha,
  source_span = list(char_from = char_from, char_to = char_to),
  page_evidence = list(page_from = page_from, page_to = page_to),
  verbatim_text = text,
  verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  anchor_method = "deterministic-segment", segment_version = "segment.py@fixture-v1")
manifest <- list(
  manifest_content_sha256 = run_hash("manifest"),
  source = list(id = source_id, profile_id = profile_id, profile_sha256 = profile_sha),
  expected_counts = list(source_evidence = 2L, person_creates = 0L, canonical_delta = 0L),
  operations = list(
    operation(paste0(run_key, "-1"), 0L, 10L, 10L, 10L, "Alfa Bravo"),
    operation(paste0(run_key, "-2a"), 20L, 33L, 10L, 11L, "Charlie Delta")))
validate_reimport_manifest(manifest)
preview_sha <- run_hash("preview")

aggregate_hash <- function(sql) as.character(q(sprintf(paste(
  "SELECT coalesce(encode(sha256(convert_to(string_agg(row_text, chr(10) ORDER BY row_text),",
  "'UTF8')),'hex'),'empty') AS h FROM (%s) s"), sql))$h[[1L]])
canonical_state <- function() list(
  person = aggregate_hash("SELECT p::text AS row_text FROM public.person p"),
  fact = aggregate_hash("SELECT f::text AS row_text FROM public.fact f"),
  family_member = aggregate_hash("SELECT m::text AS row_text FROM public.family_member m"),
  narrative = aggregate_hash("SELECT n::text AS row_text FROM public.narrative n"),
  narrative_record_publication = aggregate_hash(
    "SELECT b::text AS row_text FROM private.narrative_record_publication b"))
anon_state <- function() {
  dbBegin(con); e("SET LOCAL ROLE anon")
  state <- list(
    person = aggregate_hash("SELECT p::text AS row_text FROM public.person p"),
    person_external_id = aggregate_hash("SELECT x::text AS row_text FROM public.person_external_id x"),
    narrative = aggregate_hash("SELECT n::text AS row_text FROM public.narrative n"),
    fact = aggregate_hash("SELECT f::text AS row_text FROM public.fact f"),
    citation = aggregate_hash("SELECT c::text AS row_text FROM public.citation c"),
    conclusion = aggregate_hash("SELECT c::text AS row_text FROM public.conclusion c"),
    assertion = aggregate_hash("SELECT a::text AS row_text FROM public.assertion a"),
    family_member = aggregate_hash("SELECT m::text AS row_text FROM public.family_member m"))
  dbRollback(con); state
}

canonical_before <- canonical_state(); anon_before <- anon_state()
env_gateway <- function() new_reimport_dbi_gateway(connect)
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)

evidence_counts <- function() {
  counts <- q(paste(
    "SELECT (SELECT count(*) FROM private.source_rendition WHERE source_id=$1) AS renditions,",
    "(SELECT count(*) FROM private.source_record WHERE source_id=$1) AS records,",
    "(SELECT count(*) FROM private.source_record_occurrence o JOIN private.source_rendition r",
    " ON r.id=o.rendition_id WHERE r.source_id=$1) AS occurrences,",
    "(SELECT count(*) FROM private.source_record_anchor_event a JOIN private.source_record sr",
    " ON sr.id=a.source_record_id WHERE sr.source_id=$1 AND a.decision_status='accepted') AS anchors"),
    list(source_id))
  list(renditions = as.integer(counts$renditions[[1L]]), records = as.integer(counts$records[[1L]]),
       occurrences = as.integer(counts$occurrences[[1L]]), anchors = as.integer(counts$anchors[[1L]]))
}
evidence_before <- evidence_counts()
dry <- execute_reimport(manifest, preview_sha, "dry-run", env_gateway())
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed))
stopifnot(identical(evidence_counts(), evidence_before))

database_identity <- q("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text i")$i[[1L]]
authorization_id <- q(paste("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
  "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
  list(manifest$manifest_content_sha256, preview_sha, database_identity, source_id,
    profile_id, profile_sha,
    jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
    jsonlite::toJSON(reimport_authorized_payloads(manifest), auto_unbox = TRUE, null = "null")))$id[[1L]]

applied <- execute_reimport(manifest, preview_sha, "apply", env_gateway(),
  list(id = authorization_id))
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))

counts <- evidence_counts()
stopifnot(counts$renditions == 1L, counts$records == evidence_before$records + 2L,
          counts$occurrences == evidence_before$occurrences + 2L,
          counts$anchors == evidence_before$anchors + 2L)
stopifnot(q("SELECT count(*) n FROM private.source_record WHERE source_id=$1 AND record_kind<>'person_post'", list(source_id))$n[[1L]] == 0L)
stopifnot(identical(canonical_state(), canonical_before))
stopifnot(identical(anon_state(), anon_before))
stopifnot(q("SELECT count(*) n FROM private.reimport_authorization WHERE source_id=$1 AND profile_id=$2 AND operation='name_completion'", list(source_id, profile_id))$n[[1L]] == 0L)

replay_authorization <- q(paste("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
  "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
  list(manifest$manifest_content_sha256, preview_sha, database_identity, source_id,
    profile_id, profile_sha,
    jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
    jsonlite::toJSON(reimport_authorized_payloads(manifest), auto_unbox = TRUE, null = "null")))$id[[1L]]
replayed <- execute_reimport(manifest, preview_sha, "apply", env_gateway(),
  list(id = replay_authorization))
stopifnot(identical(replayed$status, "already_applied"))
stopifnot(identical(canonical_state(), canonical_before))

batch_id <- q("SELECT id FROM private.reimport_batch WHERE source_id=$1 AND profile_id=$2 AND status='finalized' ORDER BY finalized_at DESC LIMIT 1",
  list(source_id, profile_id))$id[[1L]]
reversal_authorization <- q("SELECT public.red_authorize_reimport_reversal($1,gen_random_uuid(),clock_timestamp()+interval '5 minutes') AS id",
  list(batch_id))$id[[1L]]
reversal <- try(q("SELECT public.red_reverse_reimport($1,$2)",
  list(batch_id, reversal_authorization)), silent = TRUE)
stopifnot(inherits(reversal, "try-error"),
  grepl("REIMPORT_WRITER_REVERSAL_INVALID", as.character(reversal), fixed = TRUE))
stopifnot(identical(canonical_state(), canonical_before))

cat("PASS source_evidence reimport integration\n")
