# Disponerbar #148 4.1c clause_evidence-integration ende til ende. Alt syntetisk.
# Kæden: 149a-lignende source_evidence-batch for én record -> clause_evidence-manifest
# gennem R-gatewayen (dry-run, apply, replay).
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

# ---- 149a-lignende source_evidence-batch for én record -----------------------
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
text_dead <- paste0("Alfa ", run_key, " Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie.")
manifest_se <- list(
  manifest_content_sha256 = run_hash("manifest-se"),
  source = list(id = source_id, profile_id = profile_id, profile_sha256 = profile_sha),
  expected_counts = list(source_evidence = 1L, person_creates = 0L, canonical_delta = 0L),
  operations = list(operation(key_dead, nchar(text_dead), 11L, text_dead)))
validate_reimport_manifest(manifest_se)
preview_sha_se <- run_hash("preview-se")
applied_se <- execute_reimport(manifest_se, preview_sha_se, "apply", env_gateway(),
  list(id = authorize(manifest_se, preview_sha_se)))
stopifnot(identical(applied_se$status, "finalized"), isTRUE(applied_se$committed))

# ---- clause_evidence: manifest fra en syntetisk ledger -----------------------
ce_profile_id <- paste0(profile_id, "-ce")
ce_config <- sub('"run_key_prefix":"reimport-source-evidence:"', '"run_key_prefix":"reimport-clause-evidence:"',
  sub('"schema_version":"source-evidence-manifest-v1"', '"schema_version":"clause-evidence-manifest-v1"',
  sub('"observation_extraction_method":"deterministic_segment_v1"', '"observation_extraction_method":"clause_segment_v1"', writer_config)))
ce_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(ce_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'clause-evidence-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, ce_profile_id, ce_sha, ce_config))

sha_text <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
# Datadrevet skæring ved ". Gift" (regexpr er 1-baseret og peger på punktummet).
p <- regexpr(". Gift", text_dead, fixed = TRUE)[[1L]]; stopifnot(p > 0L)
c1 <- substr(text_dead, 1L, p); c2 <- substr(text_dead, p + 2L, nchar(text_dead))

# Helpostens rå spænd i denne fixture er lineært (source_span 0..nchar), så de
# renditions-absolutte offsets er lig de post-relative. I den rigtige rendition
# er de IKKE lig hinanden — dér kommer tallene fra manifest-builderens offset-kort.
parent_from <- 0L
clauses <- list(
  list(ordinal = 1L, char_from = 0L, char_to = p,
       rendition_char_from = parent_from, rendition_char_to = parent_from + p,
       classification = "record_text", flags = list(), verbatim_sha256 = sha_text(c1)),
  list(ordinal = 2L, char_from = p + 1L, char_to = nchar(text_dead),
       rendition_char_from = parent_from + p + 1L, rendition_char_to = parent_from + nchar(text_dead),
       classification = "record_text", flags = list(), verbatim_sha256 = sha_text(c2)))

manifest_ce <- list(
  manifest_content_sha256 = run_hash("manifest-ce"),
  source = list(id = source_id, profile_id = ce_profile_id, profile_sha256 = ce_sha),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L, clause_evidence = 1L),
  operations = list(list(element_id = paste0("clause-evidence:", key_dead), dependency_class = "clause_evidence",
    source_record_key = key_dead, rendition_content_sha256 = sha("c"),
    rendition_projection_sha256 = sha("e"), parent_verbatim_sha256 = sha_text(text_dead),
    clause_rules_version = "clause-rules-fixture-v1", segmenter_version = "clause_segment.py@v1",
    ledger_sha256 = sha("d"), gap_charset = list(" "), clauses = clauses)))

# ---- klausul-projektion (spec §11.1, vej C, #195) ---------------------------
scripts_dir <- file.path(root, ".claude/skills/daa-extract/scripts")
comparator <- file.path(scripts_dir, "compare_clause_evidence_projection.py")
proj_dir <- tempfile("klausul-projektion-"); dir.create(proj_dir, mode = "0700")
write_private <- function(name, text) {
  path <- file.path(proj_dir, name); stopifnot(!file.exists(path))
  writeLines(text, path); Sys.chmod(path, "0600"); path
}
manifest_json <- function(m) as.character(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null", digits = NA))
manifest_ce$manifest_content_sha256 <- NULL
unhashed_path <- write_private("manifest-unhashed.json", manifest_json(manifest_ce))
manifest_ce$manifest_content_sha256 <- system2("python3", c(shQuote(comparator), "--print-manifest-sha256",
  shQuote(unhashed_path)), stdout = TRUE)
stopifnot(grepl("^[0-9a-f]{64}$", manifest_ce$manifest_content_sha256))
manifest_path <- write_private("manifest.json", manifest_json(manifest_ce))

projection <- function() {
  out <- suppressWarnings(system2("psql", c("-X", "-At", "-q", "-v", "ON_ERROR_STOP=1",
    "-v", paste0("source_id=", source_id), "-f", shQuote(file.path(scripts_dir, "clause_evidence_projection.psql"))),
    stdout = TRUE, stderr = TRUE, env = paste0("DAA_PROJECTION_SQL_DIR=", shQuote(scripts_dir))))
  if (!is.null(attr(out, "status"))) stop("projektion fejlede: ", paste(out, collapse = "\n"))
  stopifnot(length(out) == 1L)
  out
}
sql_text <- function(name) paste(readLines(file.path(scripts_dir, name), warn = FALSE), collapse = "\n")
guard_error <- function(sql, read_only, setup = character()) {
  pc <- connect(); on.exit(dbDisconnect(pc), add = TRUE)
  dbBegin(pc); on.exit(try(dbRollback(pc), silent = TRUE), add = TRUE, after = FALSE)
  if (read_only) dbExecute(pc, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
  dbGetQuery(pc, "SELECT set_config('daa.projection_source_id', $1, true)", params = list(as.character(source_id)))
  for (statement in setup) dbExecute(pc, statement)
  tryCatch({ dbGetQuery(pc, sql); "ingen fejl" }, error = function(err) conditionMessage(err))
}
stopifnot(grepl("CLAUSE_PROJECTION_NOT_READ_ONLY", guard_error(sql_text("clause_evidence_projection.sql"), FALSE), fixed = TRUE))
stopifnot(grepl("CLAUSE_PROJECTION_NOT_ANON", guard_error(sql_text("clause_evidence_anon_projection.sql"), TRUE), fixed = TRUE))
# Alle andre gengivelsesindstillinger er korrekte; kun bytea_output afviger. Begge
# guards hasher x::text og skal derfor afvise sessionen.
escape_session <- c("SET LOCAL TimeZone TO 'UTC'", "SET LOCAL DateStyle TO 'ISO, YMD'",
  "SET LOCAL IntervalStyle TO 'postgres'", "SET LOCAL extra_float_digits TO 1",
  "SET LOCAL bytea_output TO 'escape'")
stopifnot(grepl("CLAUSE_PROJECTION_SESSION_SETTINGS_INVALID",
  guard_error(sql_text("clause_evidence_projection.sql"), TRUE, escape_session), fixed = TRUE))
stopifnot(grepl("CLAUSE_PROJECTION_SESSION_SETTINGS_INVALID",
  guard_error(sql_text("clause_evidence_anon_projection.sql"), TRUE, c(escape_session, "SET LOCAL ROLE anon")), fixed = TRUE))
target_sha <- q(sql_text("clause_evidence_target_identity.sql"))$database_target_sha256[[1L]]
stopifnot(grepl("^[0-9a-f]{64}$", target_sha))
run_comparator <- function(before_path, after_path, report_name, target = target_sha) {
  out <- suppressWarnings(system2("python3", c(shQuote(comparator),
    "--manifest", shQuote(manifest_path), "--before", shQuote(before_path), "--after", shQuote(after_path),
    "--expect-target-sha256", target, "--report", shQuote(file.path(proj_dir, report_name)),
    "--allow-empty", "narrative_bindings,narrative_sha256,persons"), stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}

validate_reimport_manifest(manifest_ce)

preview_sha_ce <- run_hash("preview-ce")
before <- q("SELECT count(*) n FROM private.source_observation WHERE observation_kind='clause'")$n[[1L]]
dry <- execute_reimport(manifest_ce, preview_sha_ce, "dry-run", env_gateway(), NULL)
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
  q("SELECT count(*) n FROM private.source_observation WHERE observation_kind='clause'")$n[[1L]] == before)
before_path <- write_private("before.json", projection())
applied <- execute_reimport(manifest_ce, preview_sha_ce, "apply", env_gateway(),
  list(id = authorize(manifest_ce, preview_sha_ce)))
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))
stopifnot(q("SELECT count(*) n FROM private.source_observation WHERE observation_kind='clause'")$n[[1L]] == before + 2L)
stopifnot(count1("SELECT count(*) FROM private.clause_disposition_current d JOIN private.source_observation o ON o.id=d.observation_id WHERE o.observation_kind='clause' AND d.disposition='afventer_fortolkning'") >= 2L)

after_text <- projection()
after_path <- write_private("after.json", after_text)
matched <- run_comparator(before_path, after_path, "report-match.json")
if (matched$status != 0L) stop("klausul-projektion ikke match: ", matched$out)
stopifnot(grepl('"status": "match"', matched$out, fixed = TRUE))

tampered <- sub('"disposition": "afventer_fortolkning"', '"disposition": "strukturel"', after_text, fixed = TRUE)
stopifnot(!identical(tampered, after_text))
drift <- run_comparator(before_path, write_private("after-tampered.json", tampered), "report-tampered.json")
stopifnot(drift$status == 1L, grepl("CLAUSE_PROJECTION_DRIFT", drift$out, fixed = TRUE))

wrong_target <- run_comparator(before_path, after_path, "report-target.json", strrep("0", 64L))
stopifnot(wrong_target$status == 1L, grepl("CLAUSE_PROJECTION_TARGET_UNEXPECTED", wrong_target$out, fixed = TRUE))

replay <- execute_reimport(manifest_ce, preview_sha_ce, "apply", env_gateway(),
  list(id = authorize(manifest_ce, preview_sha_ce)))
stopifnot(identical(replay$status, "already_applied"))

# Replay må ikke efterlade spor i projektionen.
stopifnot(identical(projection(), after_text))

# ---- clause_revision: omsegmentering af samme post (spec 2026-09-27) -----------
# Kun flaget på klausul 2 ændres. Det er en rigtig revision (sæt-hashen ser flag), og
# det aktuelle sæt har stadig ordinal 1-2, som forslags-integrationen bygger videre på.
cr_profile_id <- paste0(profile_id, "-cr")
cr_config <- sub('"run_key_prefix":"reimport-clause-evidence:"', '"run_key_prefix":"reimport-clause-revision:"',
  sub('"schema_version":"clause-evidence-manifest-v1"', '"schema_version":"clause-revision-manifest-v1"', ce_config))
cr_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(cr_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'clause-revision-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, cr_profile_id, cr_sha, cr_config))
before_rev_path <- write_private("before-revision.json", after_text)
# Det erstattede sæt læses af projektionen med byggerens egen funktion.
current <- system2("python3", c("-c", shQuote(paste0(
  "import json,sys; sys.path.insert(0,", deparse(scripts_dir), "); import build_clause_evidence_manifest as B; ",
  "print(json.dumps(B.current_sets_from_projection(json.load(open(", deparse(before_rev_path), ")))[", deparse(key_dead), "]))"))),
  stdout = TRUE)
current <- jsonlite::fromJSON(current)
stopifnot(identical(as.integer(current$clause_set_seq), 1L), grepl("^[0-9a-f]{64}$", current$clause_set_sha256))
revised_clauses <- clauses
revised_clauses[[2L]]$flags <- list("uncertain_marker")
manifest_cr <- list(
  source = list(id = source_id, profile_id = cr_profile_id, profile_sha256 = cr_sha),
  expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L, clause_revisions = 1L),
  operations = list(list(element_id = paste0("clause-revision:", key_dead), dependency_class = "clause_revision",
    source_record_key = key_dead, rendition_content_sha256 = sha("c"),
    rendition_projection_sha256 = sha("e"), parent_verbatim_sha256 = sha_text(text_dead),
    clause_rules_version = "clause-rules-fixture-v1", segmenter_version = "clause_segment.py@v1",
    ledger_sha256 = sha("d"), gap_charset = list(" "), clauses = revised_clauses,
    replaces_clause_set_seq = 1L, replaces_clause_set_sha256 = current$clause_set_sha256)))
unhashed_cr <- write_private("manifest-cr-unhashed.json", manifest_json(manifest_cr))
manifest_cr$manifest_content_sha256 <- system2("python3", c(shQuote(comparator), "--print-manifest-sha256",
  shQuote(unhashed_cr)), stdout = TRUE)
stopifnot(grepl("^[0-9a-f]{64}$", manifest_cr$manifest_content_sha256))
manifest_path <- write_private("manifest-cr.json", manifest_json(manifest_cr))
validate_reimport_manifest(manifest_cr)
preview_sha_cr <- run_hash("preview-cr")
dry_cr <- execute_reimport(manifest_cr, preview_sha_cr, "dry-run", env_gateway(), NULL)
stopifnot(identical(dry_cr$status, "finalized"), isFALSE(dry_cr$committed), identical(projection(), after_text))
applied_cr <- execute_reimport(manifest_cr, preview_sha_cr, "apply", env_gateway(),
  list(id = authorize(manifest_cr, preview_sha_cr)))
stopifnot(identical(applied_cr$status, "finalized"), isTRUE(applied_cr$committed))
after_rev_text <- projection()
after_rev_path <- write_private("after-revision.json", after_rev_text)
matched_rev <- run_comparator(before_rev_path, after_rev_path, "report-revision.json")
if (matched_rev$status != 0L) stop("revisions-projektion ikke match: ", matched_rev$out)
stopifnot(grepl('"status": "match"', matched_rev$out, fixed = TRUE))
report_rev <- jsonlite::fromJSON(file.path(proj_dir, "report-revision.json"))
stopifnot(identical(report_rev$scope, "clause-revision-delta-v1"),
  identical(as.integer(report_rev$counts$clauses_written), 2L), identical(as.integer(report_rev$counts$clauses_replaced), 2L))
tampered_rev <- sub('"disposition": "erstattet"', '"disposition": "afventer_fortolkning"', after_rev_text, fixed = TRUE)
stopifnot(!identical(tampered_rev, after_rev_text))
drift_rev <- run_comparator(before_rev_path, write_private("after-revision-tampered.json", tampered_rev), "report-revision-tampered.json")
stopifnot(drift_rev$status == 1L)
# Samme manifest igen er en genafspilning, ikke en ny revision — og efterlader intet spor.
replay_cr <- execute_reimport(manifest_cr, preview_sha_cr, "apply", env_gateway(),
  list(id = authorize(manifest_cr, preview_sha_cr)))
stopifnot(identical(replay_cr$status, "already_applied"), identical(projection(), after_rev_text))

# ---- klausuleksport: helposten vælges af basens regel (trin 6a, Task 11) ------
# Egen kilde, så eksporten kun ser fixturens records. Tre ok-records (én med underforekomst, én med revideret
# tekstversion), én uden helpost (none). Bagefter en outside-record, som stopper eksporten.
exp_source <- source_id + 1L
e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Eksport-fixture','synthetic','DAA-udgave') ON CONFLICT(id) DO NOTHING", list(exp_source))
exp_run <- q("INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,$2,'fixture','fixture','fixture',$3,'{}') RETURNING id",
  list(exp_source, paste0("export-", run_nonce), sha("1")))$id[[1L]]
exp_rend <- q("INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES($1,'exp-r1','pdf_text_layer',$2,'{}') RETURNING id",
  list(exp_source, sha("2")))$id[[1L]]
mk_record <- function(key) q("INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES($1,$2,'person',$3) RETURNING id",
  list(exp_source, key, exp_run))$id[[1L]]
mk_occ <- function(rec, okey, from, to, kind, text) {
  occ <- q("INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,$2,1,1,$3,$4,$5,$6,$7,$8) RETURNING id",
    list(exp_rend, okey, from, to, text, sha("3"), sha("4"), exp_run))$id[[1L]]
  obs <- q("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,$2,1,1,$3,$4,$5,'clear','fixture',$6) RETURNING id",
    list(occ, kind, from, to, text, exp_run))$id[[1L]]
  e("INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2,'accepted','{\"fixture\":true}'::jsonb,1,gen_random_uuid(),'fixture')",
    list(occ, rec))
  obs
}
txt_a <- "Alfa Bravo, f. 1801, d. 1860. Gift 1830 m. Charlie."
txt_b <- "Delta Echo, f. 1810. Gift 1840 m. Foxtrot."
txt_b_rev <- "Delta Echo, f. 1810. Gift 1841 m. Foxtrot."
txt_c <- "Golf Hotel, f. 1820."
rec_a <- mk_record("EXP-A"); mk_occ(rec_a, "exp-a1", 100L, 100L + nchar(txt_a), "person_post", txt_a)
rec_b <- mk_record("EXP-B"); obs_b <- mk_occ(rec_b, "exp-b1", 300L, 300L + nchar(txt_b), "person_post", txt_b)
mk_occ(rec_b, "exp-b2", 310L, 320L, "fact", "sub")   # underforekomst inde i helposten
rec_c <- mk_record("EXP-C"); mk_occ(rec_c, "exp-c1", 600L, 600L + nchar(txt_c), "person_post", txt_c)
rec_n <- mk_record("EXP-N"); mk_occ(rec_n, "exp-n1", 700L, 720L, "fact", "ingen helpost")
rev_text_id <- q("INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to,is_preferred) VALUES($1,$2,1,$3,300,$4,true) RETURNING id",
  list(obs_b, exp_rend, txt_b_rev, 300L + nchar(txt_b_rev)))$id[[1L]]

export_script <- file.path(scripts_dir, "export_clause_source_texts.R")
run_export <- function(kind, out_dir) {
  args <- c(shQuote(export_script), "--source-id", exp_source, "--output-dir", shQuote(out_dir))
  if (!is.null(kind)) args <- c(args, "--helpost-kind", shQuote(kind))
  out <- suppressWarnings(system2("Rscript", args, stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}
new_out_dir <- function() { d <- tempfile("klausul-eksport-"); dir.create(d, mode = "0700"); d }
stopifnot(grepl("EXPORT_CLI_INVALID", run_export(NULL, new_out_dir())$out, fixed = TRUE))
stopifnot(grepl("EXPORT_CLI_INVALID", run_export("", new_out_dir())$out, fixed = TRUE))

exp_dir <- new_out_dir()
exported <- run_export("person_post", exp_dir)
if (exported$status != 0L) stop("klausuleksport fejlede: ", exported$out)
summary_out <- jsonlite::fromJSON(exported$out)
stopifnot(identical(as.integer(summary_out$records_ok), 3L), identical(as.integer(summary_out$no_helpost), 1L),
  grepl("^[0-9a-f]{64}$", summary_out$texts_sha256), !grepl("Alfa|Delta|Golf", exported$out))
texts_file <- file.path(exp_dir, "clause-source-texts-v1.json")
index_file <- file.path(exp_dir, "clause-source-index-v1.json")
stopifnot(identical(bitwAnd(as.integer(file.info(texts_file)$mode), 511L), 384L))
exp_rows <- jsonlite::fromJSON(texts_file, simplifyVector = FALSE)
stopifnot(length(exp_rows) == 4L,
  identical(vapply(exp_rows, function(r) r$record_key, ""), c("EXP-A", "EXP-B", "EXP-C", "EXP-N")))
by_key <- setNames(exp_rows, vapply(exp_rows, function(r) r$record_key, ""))
# ok-rækker: helpostens tekst, hash over den og text_id (kun revideret tekst har et).
stopifnot(identical(by_key[["EXP-A"]]$verbatim_text, txt_a), identical(by_key[["EXP-A"]]$verbatim_sha256, sha_text(txt_a)),
  identical(by_key[["EXP-C"]]$verbatim_text, txt_c), identical(by_key[["EXP-B"]]$occurrence_key, "exp-b1"))
stopifnot(identical(by_key[["EXP-B"]]$verbatim_text, txt_b_rev), identical(by_key[["EXP-B"]]$verbatim_sha256, sha_text(txt_b_rev)),
  identical(by_key[["EXP-B"]]$text_id, rev_text_id))
# no_helpost-rækken står i tekstfilen med null i alle felter undtagen record_key.
n_row <- by_key[["EXP-N"]]
stopifnot(identical(sort(names(n_row)), sort(names(by_key[["EXP-A"]]))))
for (k in setdiff(names(n_row), "record_key")) stopifnot(is.null(n_row[[k]]))
index <- jsonlite::fromJSON(index_file, simplifyVector = FALSE)
stopifnot(length(index$records) == 3L, length(index$no_helpost) == 1L,
  identical(index$no_helpost[[1L]]$record_key, "EXP-N"), identical(index$no_helpost[[1L]]$status, "none"),
  !any(vapply(index$records, function(r) "verbatim_text" %in% names(r), NA)))
stopifnot(grepl("EXPORT_OUTPUT_EXISTS", run_export("person_post", exp_dir)$out, fixed = TRUE))
# Python-ledgeren tæller null-rækken som »ingen helpost« i sit summary.
ledger_dir <- new_out_dir()
ledger <- suppressWarnings(system2("python3", c(shQuote(file.path(scripts_dir, "build_clause_ledger.py")),
  "--profile", "daa-2018-20-v1", "--texts", shQuote(texts_file), "--output-dir", shQuote(ledger_dir)), stdout = TRUE, stderr = TRUE))
if (!is.null(attr(ledger, "status"))) stop("ledger fejlede: ", paste(ledger, collapse = "\n"))
ledger_summary <- jsonlite::fromJSON(file.path(ledger_dir, "clause-ledger-summary.json"))
stopifnot(identical(as.integer(ledger_summary$records), 3L), identical(as.integer(ledger_summary$no_helpost$records), 1L),
  identical(ledger_summary$no_helpost$record_keys, "EXP-N"))

# ambiguous: to accepterede person_post-forekomster med hver sin helpost-observation.
rec_d <- mk_record("EXP-D"); mk_occ(rec_d, "exp-d1", 1000L, 1020L, "person_post", "Ambiguous et")
mk_occ(rec_d, "exp-d2", 1100L, 1120L, "person_post", "Ambiguous to")
amb_dir <- new_out_dir()
amb <- run_export("person_post", amb_dir)
stopifnot(amb$status != 0L, grepl("EXPORT_HELPOST_INVALID", amb$out, fixed = TRUE), length(list.files(amb_dir)) == 0L)

# En underforekomst udenfor helposten gør recorden til outside: eksporten stopper uden at skrive filer.
mk_occ(rec_c, "exp-c2", 900L, 910L, "fact", "udenfor")
# Begge dårlige records er nu i basen; bevis at hver har sin egen status (så ingen maskerer den anden).
stopifnot(identical(q("SELECT status FROM private.record_helpost_status($1::uuid,'person_post')", list(rec_c))$status, "outside"),
  identical(q("SELECT status FROM private.record_helpost_status($1::uuid,'person_post')", list(rec_d))$status, "ambiguous"))
bad_dir <- new_out_dir()
bad <- run_export("person_post", bad_dir)
stopifnot(bad$status != 0L, grepl("EXPORT_HELPOST_INVALID", bad$out, fixed = TRUE), length(list.files(bad_dir)) == 0L)

cat("clause_evidence integration OK\n")
