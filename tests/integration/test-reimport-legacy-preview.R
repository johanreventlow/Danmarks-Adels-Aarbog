# Disponerbar #149b legacy-migration-preview-integration. Hver identitet, hash og
# tekst nedenfor er syntetisk; der oprettes intet historisk kildeindhold.
# Dækker preview_legacy_before_counts og preview_legacy_ledger_coverage (findes 6.2,
# review-fund I-1): en genfundet før-billede-gate skal blokere apply af et forældet
# eller manipuleret legacy-migration-manifest.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_reimport_helpers.R"))
source(file.path(root, ".claude/skills/daa-extract/scripts/export_reimport_preview_helpers.R"))

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

# Pr.-kørsel-nonce: source_id/record_keys/manifest-hashes skal være unikke, ellers
# møder en gentagen kørsel mod samme base sin egen tidligere fixture.
run_nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
run_hash <- function(tag) digest::digest(paste(run_nonce, tag), algo = "sha256", serialize = FALSE)
run_key <- paste0("G", substr(run_hash("key"), 1L, 6L))
source_id <- 149400000L + (strtoi(substr(run_hash("source"), 1L, 6L), base = 16L) %% 100000L)

stopifnot(q("SELECT public.narrative_record_contract_version() v")$v[[1L]] == 2L)

actor <- "14900000-0000-4000-8000-000000000002"
profile_id <- "fixture-legacy-preview-v1"
writer_config <- paste0('{"citation_label_template":"Synthetic side {page_from}",',
  '"extractor_version":"fixture-v1","observation_extraction_method":"deterministic_segment_v1",',
  '"rendition_key":"fixture-pdftotext-r1","rendition_kind":"pdf_text_layer",',
  '"rendition_metadata":{"edition":"fixture","pdf_sha256":"', sha("a"),
  '","pdftotext_version":"fixture 0.0"},"run_key_prefix":"reimport-source-evidence:",',
  '"schema_version":"source-evidence-manifest-v1"}')

e("INSERT INTO auth.users(id,email) VALUES($1,'149b-preview@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'149b-preview@example.invalid','redaktion','Task 149b preview') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Fixture','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING", list(source_id))
profile_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(writer_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'source-evidence-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, profile_id, profile_sha, writer_config))
e("SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor))

# 149a-lignende source_evidence-batch for to poster: D1 (afdød, senere bound_published)
# og L1 (levende, senere bound_draft).
operation <- function(key, char_from, char_to, page_from, page_to, text) list(
  element_id = paste0("source-evidence:", key), dependency_class = "source_evidence",
  source_record_key = key, source_id = source_id, category = "person_post",
  disposition = "retain_source_only", rendition_content_sha256 = sha("c"),
  source_span = list(char_from = char_from, char_to = char_to),
  page_evidence = list(page_from = page_from, page_to = page_to),
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
    operation(key_dead, 0L, nchar(text_dead), 10L, 10L, text_dead),
    operation(key_living, 0L, nchar(text_living), 11L, 11L, text_living)))
validate_reimport_manifest(manifest_se)
preview_sha_se <- run_hash("preview-se")

database_identity <- q("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text i")$i[[1L]]
env_gateway <- function() new_reimport_dbi_gateway(connect)
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)
authorization_id_se <- q(paste("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
  "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
  list(manifest_se$manifest_content_sha256, preview_sha_se, database_identity, source_id,
    profile_id, profile_sha,
    jsonlite::toJSON(reimport_writer_expected_counts(manifest_se), auto_unbox = TRUE),
    jsonlite::toJSON(reimport_authorized_payloads(manifest_se), auto_unbox = TRUE, null = "null")))$id[[1L]]
applied_se <- execute_reimport(manifest_se, preview_sha_se, "apply", env_gateway(), list(id = authorization_id_se))
stopifnot(identical(applied_se$status, "finalized"), isTRUE(applied_se$committed))

# Person + narrativ (149b's writer opretter dem ikke — 149a's person_create gør, men
# den kæde er ude af scope her; direkte INSERT, samme mønster som
# tests/sql/test-reimport-legacy-migration.sql's task3_fixture).
person_dead <- as.integer(q("INSERT INTO public.person(levende,privat,staged) VALUES(false,false,false) RETURNING id")$id[[1L]])
person_living <- as.integer(q("INSERT INTO public.person(levende,privat,staged) VALUES(true,false,false) RETURNING id")$id[[1L]])
e("INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES($1,$2,$3)", list(person_dead, source_id, key_dead))
e("INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES($1,$2,$3)", list(person_living, source_id, key_living))
narrative_dead <- as.integer(q("INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES('person',$1,$2,'10',$3,false) RETURNING id",
  list(person_dead, source_id, text_dead))$id[[1L]])
narrative_living <- as.integer(q("INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES('person',$1,$2,'11',$3,false) RETURNING id",
  list(person_living, source_id, text_living))$id[[1L]])

# Grandfathered ledger-række for den døde. latest_event_id forbliver NULL: triggeren
# (trg_narrative_legacy_publication_validate) kræver kun et matchende event, når
# latest_event_id er sat — preview'en under test læser aldrig events.
legacy_ref <- q("SELECT gen_random_uuid()::text AS r")$r[[1L]]
legacy_row <- q(paste(
  "SELECT private.narrative_legacy_candidate_publication_state($1,$2,$3::uuid) AS state,",
  "encode(extensions.digest(private.narrative_legacy_candidate_publication_state($1,$2,$3::uuid)::text,'sha256'),'hex')",
  "AS baseline_sha256"),
  list(narrative_dead, source_id, legacy_ref))
legacy_state <- legacy_row$state[[1L]]
legacy_baseline_sha256 <- legacy_row$baseline_sha256[[1L]]
insert_ledger <- function(ref, narrative_id, state, baseline_sha256) e(paste(
  "INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,",
  "source_id,baseline_state,baseline_sha256,status)",
  "VALUES($1::uuid,$2,$3,$4::jsonb,$5,'grandfathered_publication')"),
  list(ref, narrative_id, source_id, state, baseline_sha256))
insert_ledger(legacy_ref, narrative_dead, legacy_state, legacy_baseline_sha256)

# Legacy-migration-profil + håndskrevet manifest (bound_published + bound_draft).
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

lm_op <- function(key, person_id, narrative_id, disposition, text, ref = NULL, baseline = NULL) list(
  element_id = paste0("legacy-migration:", key), dependency_class = "legacy_migration",
  source_record_key = key, source_id = source_id, person_id = person_id, narrative_id = narrative_id,
  disposition = disposition,
  narrative_text_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  occurrence_verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
  normalized_text_sha256 = digest::digest(paste0("norm:", text), algo = "sha256", serialize = FALSE),
  legacy_publication_ref = ref, legacy_baseline_sha256 = baseline, persona_key = key)
legacy_manifest <- list(
  manifest_content_sha256 = run_hash("manifest-lm"),
  source = list(id = source_id, profile_id = lm_profile_id, profile_sha256 = lm_profile_sha),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L, legacy_migrations = 2L),
  dispositions = list(
    list(record_key = key_dead, disposition = "bound_published"),
    list(record_key = key_living, disposition = "bound_draft")),
  operations = list(
    lm_op(key_dead, person_dead, narrative_dead, "bound_published", text_dead, legacy_ref, legacy_baseline_sha256),
    lm_op(key_living, person_living, narrative_living, "bound_draft", text_living)))
validate_reimport_manifest(legacy_manifest)
preview_sha_lm <- run_hash("preview-lm")

run_preview <- function() {
  pcon <- connect()
  on.exit(dbDisconnect(pcon), add = TRUE)
  dbExecute(pcon, "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
  pq <- function(sql, params = list())
    if (length(params)) dbGetQuery(pcon, sql, params = params) else dbGetQuery(pcon, sql)
  result <- tryCatch(build_reimport_preview(pq, legacy_manifest, preview_sha_lm),
    error = function(err) conditionMessage(err))
  dbExecute(pcon, "ROLLBACK")
  result
}

# (a) konsistent: legacy_before_counts har de forventede tal, ledger-dækningen er ok.
preview_ok <- run_preview()
stopifnot(is.list(preview_ok), !is.null(preview_ok$legacy_before_counts))
counts <- preview_ok$legacy_before_counts
stopifnot(counts$grandfathered >= 1L, counts$migrated == 0L, counts$withdrawn == 0L,
  counts$bound_published == 0L, counts$bound_draft == 0L)
cat("PASS (a) konsistent preview\n")

# (b) ledger-rækken sættes withdrawn -> PREVIEW_LEGACY_LEDGER_INCONSISTENT.
e("UPDATE private.narrative_legacy_publication SET status='withdrawn' WHERE legacy_publication_ref=$1::uuid", list(legacy_ref))
result_b <- run_preview()
stopifnot(identical(result_b, "PREVIEW_LEGACY_LEDGER_INCONSISTENT"))
e("UPDATE private.narrative_legacy_publication SET status='grandfathered_publication' WHERE legacy_publication_ref=$1::uuid", list(legacy_ref))
cat("PASS (b) withdrawn ledger-status afvises\n")

# (c) ledger-rækken for den døde fjernes -> samme fejl.
e("DELETE FROM private.narrative_legacy_publication WHERE legacy_publication_ref=$1::uuid", list(legacy_ref))
result_c <- run_preview()
stopifnot(identical(result_c, "PREVIEW_LEGACY_LEDGER_INCONSISTENT"))
insert_ledger(legacy_ref, narrative_dead, legacy_state, legacy_baseline_sha256)
cat("PASS (c) manglende ledger-række for bound_published afvises\n")

# (d) den levende (bound_draft) får en ledger-række -> samme fejl.
living_ref <- q("SELECT gen_random_uuid()::text AS r")$r[[1L]]
living_row <- q(paste(
  "SELECT private.narrative_legacy_candidate_publication_state($1,$2,$3::uuid) AS state,",
  "encode(extensions.digest(private.narrative_legacy_candidate_publication_state($1,$2,$3::uuid)::text,'sha256'),'hex')",
  "AS baseline_sha256"),
  list(narrative_living, source_id, living_ref))
insert_ledger(living_ref, narrative_living, living_row$state[[1L]], living_row$baseline_sha256[[1L]])
result_d <- run_preview()
stopifnot(identical(result_d, "PREVIEW_LEGACY_LEDGER_INCONSISTENT"))
e("DELETE FROM private.narrative_legacy_publication WHERE legacy_publication_ref=$1::uuid", list(living_ref))
cat("PASS (d) uventet ledger-række på bound_draft afvises\n")

# Ryd op tilbage til (a)'s konsistente tilstand og bekræft, at gaten igen lukker
# preview'en igennem (viser at (b)/(c)/(d) ikke har efterladt basen i en falsk-positiv
# tilstand).
final_ok <- run_preview()
stopifnot(is.list(final_ok), identical(final_ok$legacy_before_counts$grandfathered >= 1L, TRUE))

cat("PASS legacy migration preview integration\n")
