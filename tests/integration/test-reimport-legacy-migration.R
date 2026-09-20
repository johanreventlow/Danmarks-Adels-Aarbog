# Disponerbar #166 149b legacy-migration-integration ende til ende. Hver identitet,
# hash og tekst nedenfor er syntetisk; der oprettes intet historisk kildeindhold.
# Kæden: 149a-lignende source_evidence-batch -> legacy-migration-manifest gennem
# R-gatewayen (dry-run, apply, replay) -> batch-fortrydelse gennem Task 9b's
# reverse_reimport_legacy_migration_helpers.R (dry-run, apply, gentagelse afvist).
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"))
source(file.path(root, ".claude/skills/daa-extract/scripts/reverse_reimport_legacy_migration_helpers.R"))

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
sha <- function(letter) paste(rep(letter, 64L), collapse = "")
count1 <- function(sql, params = list()) as.integer(q(sql, params)[[1L]][[1L]])
text1 <- function(sql, params = list()) {
  rows <- q(sql, params)
  if (!nrow(rows)) NA_character_ else as.character(rows[[1L]][[1L]])
}

# Pr.-kørsel-nonce: source_id, record_keys og manifest-hashes skal være unikke,
# ellers møder anden kørsel mod samme base sin egen tidligere fixture og batch.
run_nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
run_hash <- function(tag) digest::digest(paste(run_nonce, tag), algo = "sha256", serialize = FALSE)
run_key <- paste0("H", substr(run_hash("key"), 1L, 6L))
source_id <- 149500000L + (strtoi(substr(run_hash("source"), 1L, 6L), base = 16L) %% 100000L)

stopifnot(q("SELECT public.narrative_record_contract_version() v")$v[[1L]] == 2L)

actor <- "14900000-0000-4000-8000-000000000003"
profile_id <- "fixture-legacy-migration-v1"
writer_config <- paste0('{"citation_label_template":"Synthetic side {page_from}",',
  '"extractor_version":"fixture-v1","observation_extraction_method":"deterministic_segment_v1",',
  '"rendition_key":"fixture-pdftotext-r1","rendition_kind":"pdf_text_layer",',
  '"rendition_metadata":{"edition":"fixture","pdf_sha256":"', sha("a"),
  '","pdftotext_version":"fixture 0.0"},"run_key_prefix":"reimport-source-evidence:",',
  '"schema_version":"source-evidence-manifest-v1"}')

e("INSERT INTO auth.users(id,email) VALUES($1,'149b-writer@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'149b-writer@example.invalid','redaktion','Task 149b writer') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Fixture','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING", list(source_id))
profile_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(writer_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'source-evidence-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, profile_id, profile_sha, writer_config))
e("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)
env_gateway <- function() new_reimport_dbi_gateway(connect)
database_identity <- q("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text i")$i[[1L]]
authorize <- function(manifest, preview_sha) q(paste(
  "SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
  "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
  list(manifest$manifest_content_sha256, preview_sha, database_identity,
    manifest$source$id, manifest$source$profile_id, manifest$source$profile_sha256,
    jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
    jsonlite::toJSON(reimport_authorized_payloads(manifest), auto_unbox = TRUE, null = "null")))$id[[1L]]

# ---- 149a-lignende source_evidence-batch: D1 (afdød) og L1 (levende) ----------
operation <- function(key, char_to, page, text) list(
  element_id = paste0("source-evidence:", key), dependency_class = "source_evidence",
  source_record_key = key, source_id = source_id, category = "person_post",
  disposition = "retain_source_only", rendition_content_sha256 = sha("c"),
  source_span = list(char_from = 0L, char_to = char_to),
  page_evidence = list(page_from = page, page_to = page),
  verbatim_text = text,
  verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  anchor_method = "deterministic-segment", segment_version = "segment.py@fixture-v1")
key_dead <- paste0(run_key, "-D1")
key_living <- paste0(run_key, "-L1")
text_dead <- paste0("Alfa ", run_key, " Bravo, f. 1801, d. 1860.")
text_living <- paste0("Charlie ", run_key, " Delta, f. 1990.")
manifest_se <- list(
  manifest_content_sha256 = run_hash("manifest-se"),
  source = list(id = source_id, profile_id = profile_id, profile_sha256 = profile_sha),
  expected_counts = list(source_evidence = 2L, person_creates = 0L, canonical_delta = 0L),
  operations = list(
    operation(key_dead, nchar(text_dead), 10L, text_dead),
    operation(key_living, nchar(text_living), 11L, text_living)))
validate_reimport_manifest(manifest_se)
preview_sha_se <- run_hash("preview-se")
applied_se <- execute_reimport(manifest_se, preview_sha_se, "apply", env_gateway(),
  list(id = authorize(manifest_se, preview_sha_se)))
stopifnot(identical(applied_se$status, "finalized"), isTRUE(applied_se$committed))

# ---- personer, narrativer og grandfathered ledger (som SQL-gatens task3_fixture) ----
person_dead <- as.integer(q("INSERT INTO public.person(levende,privat,staged) VALUES(false,false,false) RETURNING id")$id[[1L]])
person_living <- as.integer(q("INSERT INTO public.person(levende,privat,staged) VALUES(true,false,false) RETURNING id")$id[[1L]])
e("INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES($1,$2,$3)", list(person_dead, source_id, key_dead))
e("INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES($1,$2,$3)", list(person_living, source_id, key_living))
narrative_dead <- as.integer(q("INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES('person',$1,$2,'10',$3,false) RETURNING id",
  list(person_dead, source_id, text_dead))$id[[1L]])
narrative_living <- as.integer(q("INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES('person',$1,$2,'11',$3,false) RETURNING id",
  list(person_living, source_id, text_living))$id[[1L]])

e(paste("INSERT INTO public.change_set(actor_navn,actor_rolle,operation,summary,subjekt_synlighed)",
  "SELECT 'fixture','system','fixture','fixture','offentlig'",
  "WHERE NOT EXISTS (SELECT 1 FROM public.change_set)"))
legacy_ref <- q("SELECT gen_random_uuid()::text AS r")$r[[1L]]
legacy_row <- q(paste(
  "SELECT private.narrative_legacy_candidate_publication_state($1,$2,$3::uuid) AS state,",
  "encode(extensions.digest(private.narrative_legacy_candidate_publication_state($1,$2,$3::uuid)::text,'sha256'),'hex')",
  "AS baseline_sha256"), list(narrative_dead, source_id, legacy_ref))
legacy_state <- legacy_row$state[[1L]]
legacy_baseline_sha256 <- legacy_row$baseline_sha256[[1L]]
e(paste("INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,",
  "source_id,baseline_state,baseline_sha256,status)",
  "VALUES($1::uuid,$2,$3,$4::jsonb,$5,'grandfathered_publication')"),
  list(legacy_ref, narrative_dead, source_id, legacy_state, legacy_baseline_sha256))
# Baseline-event + latest_event_id: bound_published-grenen kræver, at
# private.narrative_legacy_state(ref,true) rapporterer publication_status='published'
# og baseline_matches (spec §6.3), og det forudsætter en event-stream.
e(paste("INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,",
  "event_type,narrative_id,source_id,legacy_publication_ref,decision_basis,before_state,after_state,",
  "before_state_sha256,after_state_sha256,decided_by_name)",
  "VALUES((SELECT max(id) FROM public.change_set),$1::uuid,1,'baseline',$2,$3,$1::uuid,'fixture',",
  "$4::jsonb,$4::jsonb,$5,$5,'fixture')"),
  list(legacy_ref, narrative_dead, source_id, legacy_state, legacy_baseline_sha256))
e("UPDATE private.narrative_legacy_publication SET latest_event_id=(SELECT id FROM private.narrative_publication_event WHERE stream_ref=$1::uuid) WHERE legacy_publication_ref=$1::uuid",
  list(legacy_ref))

# ---- legacy-migration-profil og -manifest -------------------------------------
lm_profile_id <- paste0(profile_id, "-lm")
lm_config <- paste0('{"citation_label_template":"Synthetic side {page_from}",',
  '"extractor_version":"legacy-migration-v1","observation_extraction_method":"none",',
  '"rendition_key":"fixture-pdftotext-r1","rendition_kind":"pdf_text_layer",',
  '"rendition_metadata":{"edition":"fixture","pdf_sha256":"', sha("a"),
  '","pdftotext_version":"fixture 0.0"},"run_key_prefix":"reimport-legacy-migration:",',
  '"schema_version":"legacy-migration-manifest-v1"}')
lm_profile_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(lm_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'legacy-migration-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, lm_profile_id, lm_profile_sha, lm_config))

# normalized_text_sha256 = digest(tekst): fixturens narrativ er byte-lig med
# forekomstens verbatim_text, så normaliseringen er identitet her.
lm_op <- function(key, person_id, narrative_id, disposition, text, ref = NULL, baseline = NULL) list(
  element_id = paste0("legacy-migration:", key), dependency_class = "legacy_migration",
  source_record_key = key, source_id = source_id, person_id = person_id,
  narrative_id = narrative_id, disposition = disposition,
  narrative_text_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  occurrence_verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  normalized_text_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  legacy_publication_ref = ref, legacy_baseline_sha256 = baseline, persona_key = key)
legacy_manifest <- list(
  manifest_content_sha256 = run_hash("manifest-lm"),
  source = list(id = source_id, profile_id = lm_profile_id, profile_sha256 = lm_profile_sha),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L,
    legacy_migrations = 2L),
  dispositions = list(
    list(record_key = key_dead, disposition = "bound_published"),
    list(record_key = key_living, disposition = "bound_draft")),
  operations = list(
    lm_op(key_dead, person_dead, narrative_dead, "bound_published", text_dead,
      legacy_ref, legacy_baseline_sha256),
    lm_op(key_living, person_living, narrative_living, "bound_draft", text_living)))
validate_reimport_manifest(legacy_manifest)
preview_sha_lm <- run_hash("preview-lm")

# ---- måleflader ---------------------------------------------------------------
aggregate_hash <- function(sql) as.character(q(sprintf(paste(
  "SELECT coalesce(encode(sha256(convert_to(string_agg(row_text, chr(10) ORDER BY row_text),",
  "'UTF8')),'hex'),'empty') AS h FROM (%s) s"), sql))$h[[1L]])
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
ledger_status <- function() text1(
  "SELECT status FROM private.narrative_legacy_publication WHERE legacy_publication_ref=$1::uuid",
  list(legacy_ref))
binding_status <- function(narrative_id) text1(
  "SELECT status FROM private.narrative_record_publication WHERE narrative_id=$1", list(narrative_id))
v2_rows <- function(person_id, kind = NULL) {
  if (is.null(kind))
    count1("SELECT count(*) FROM public.public_person_bio_source_versions_v2(ARRAY[$1::bigint])",
      list(person_id))
  else
    count1(paste("SELECT count(*) FROM public.public_person_bio_source_versions_v2(ARRAY[$1::bigint])",
      "WHERE provenance_kind=$2"), list(person_id, kind))
}
lm_batches <- function() count1(
  "SELECT count(*) FROM private.reimport_batch WHERE source_id=$1 AND profile_id=$2", list(source_id, lm_profile_id))

anon_before <- anon_state()
stopifnot(identical(ledger_status(), "grandfathered_publication"),
  is.na(binding_status(narrative_dead)), is.na(binding_status(narrative_living)),
  v2_rows(person_dead) == 1L, v2_rows(person_dead, "legacy_narrative") == 1L,
  v2_rows(person_living) == 0L, lm_batches() == 0L)
cat("PASS (0) fixturen er grandfathered og ubundet\n")

# ---- (1) dry-run skriver intet ------------------------------------------------
dry <- execute_reimport(legacy_manifest, preview_sha_lm, "dry-run", env_gateway())
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
  identical(ledger_status(), "grandfathered_publication"),
  is.na(binding_status(narrative_dead)), is.na(binding_status(narrative_living)),
  lm_batches() == 0L, identical(anon_state(), anon_before))
cat("PASS (1) dry-run finaliserer uden at skrive\n")

# ---- (2) apply ----------------------------------------------------------------
applied <- execute_reimport(legacy_manifest, preview_sha_lm, "apply", env_gateway(),
  list(id = authorize(legacy_manifest, preview_sha_lm)))
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed),
  identical(ledger_status(), "migrated"),
  identical(binding_status(narrative_dead), "published"),
  identical(binding_status(narrative_living), "draft"),
  v2_rows(person_dead) == 1L, v2_rows(person_dead, "source_record") == 1L,
  v2_rows(person_living) == 0L,
  identical(anon_state(), anon_before), lm_batches() == 1L)
cat("PASS (2) apply migrerer ledger og binding uden at ændre anon-fladen\n")

# ---- (3) replay -----------------------------------------------------------------
replayed <- execute_reimport(legacy_manifest, preview_sha_lm, "apply", env_gateway(),
  list(id = authorize(legacy_manifest, preview_sha_lm)))
stopifnot(identical(replayed$status, "already_applied"), identical(ledger_status(), "migrated"),
  identical(binding_status(narrative_dead), "published"),
  identical(binding_status(narrative_living), "draft"),
  identical(anon_state(), anon_before))
cat("PASS (3) replay svarer already_applied\n")

# ---- (4) batch-fortrydelse gennem Task 9b's script-helper -----------------------
batch_id <- q(paste("SELECT id FROM private.reimport_batch WHERE source_id=$1 AND profile_id=$2",
  "AND status='finalized' ORDER BY finalized_at DESC LIMIT 1"),
  list(source_id, lm_profile_id))$id[[1L]]
reversal_authorization <- q(paste("SELECT public.red_authorize_reimport_reversal($1,gen_random_uuid(),",
  "clock_timestamp()+interval '10 minutes') AS id"), list(batch_id))$id[[1L]]
reversal_events <- function() count1(
  "SELECT count(*) FROM private.reimport_event WHERE batch_id=$1 AND operation='reversal'", list(batch_id))
authorization_status <- function() text1(
  "SELECT status FROM private.reimport_authorization WHERE id=$1", list(reversal_authorization))

dry_reversal <- execute_legacy_reversal(batch_id, reversal_authorization, "dry-run",
  new_legacy_reversal_dbi_gateway(connect))
stopifnot(isFALSE(dry_reversal$committed), dry_reversal$reversed_elements == 2L,
  identical(dry_reversal$element_ids,
    c(paste0("legacy-migration:", key_living), paste0("legacy-migration:", key_dead))),
  identical(ledger_status(), "migrated"),
  identical(binding_status(narrative_dead), "published"),
  identical(binding_status(narrative_living), "draft"),
  reversal_events() == 0L, identical(authorization_status(), "issued"),
  v2_rows(person_dead, "source_record") == 1L, identical(anon_state(), anon_before))
cat("PASS (4) fortrydelsens dry-run ruller hele kæden tilbage\n")

# Samme (stadig udstedte) autorisation bruges nu til apply — beviset på, at
# dry-run'ens forbrug også blev rullet tilbage.
applied_reversal <- execute_legacy_reversal(batch_id, reversal_authorization, "apply",
  new_legacy_reversal_dbi_gateway(connect))
stopifnot(isTRUE(applied_reversal$committed), applied_reversal$reversed_elements == 2L,
  identical(ledger_status(), "grandfathered_publication"),
  identical(binding_status(narrative_dead), "withdrawn"),
  identical(binding_status(narrative_living), "withdrawn"),
  reversal_events() == 1L, identical(authorization_status(), "consumed"),
  identical(text1("SELECT status FROM private.reimport_batch WHERE id=$1", list(batch_id)), "finalized"),
  count1(paste("SELECT count(*) FROM private.reimport_event WHERE batch_id=$1",
    "AND element_id='legacy-migration-reversal:'||$2::text"),
    list(batch_id, reversal_authorization)) == 1L,
  v2_rows(person_dead) == 1L, v2_rows(person_dead, "legacy_narrative") == 1L,
  v2_rows(person_dead, "source_record") == 0L, v2_rows(person_living) == 0L,
  identical(anon_state(), anon_before))
cat("PASS (5) fortrydelsens apply giver legacy-rækken tilbage og trækker bindingerne\n")

# ---- (6) en batch kan kun fortrydes én gang -------------------------------------
again <- try(execute_legacy_reversal(batch_id, reversal_authorization, "apply",
  new_legacy_reversal_dbi_gateway(connect)), silent = TRUE)
stopifnot(inherits(again, "try-error"),
  grepl("LEGACY_REVERSAL_ALREADY_RECORDED", as.character(again), fixed = TRUE),
  reversal_events() == 1L, identical(ledger_status(), "grandfathered_publication"),
  identical(anon_state(), anon_before))
cat("PASS (6) gentagen fortrydelse afvises med LEGACY_REVERSAL_ALREADY_RECORDED\n")

# ---- (7) manifestet svarer stadig already_applied efter fortrydelsen -------------
after_reversal <- execute_reimport(legacy_manifest, preview_sha_lm, "apply", env_gateway(),
  list(id = authorize(legacy_manifest, preview_sha_lm)))
stopifnot(identical(after_reversal$status, "already_applied"),
  identical(ledger_status(), "grandfathered_publication"), reversal_events() == 1L)
cat("PASS (7) replay efter fortrydelse aabner ikke en ny batch\n")

cat("PASS legacy migration integration\n")
