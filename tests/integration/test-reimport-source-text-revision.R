# Trin 6a, Task 12: kildetekst-revisionen ende til ende gennem R-kæden. Alt syntetisk (ingen bogtekst).
#
# Del A — det faktiske manifestformat: en syntetisk rendition med tre poster, ankret i basen som v1 (støjreglen
#   anywhere) med ét klausulsæt og et forslag på post I-1. Kæden er den, ceremonien kører:
#   klausuleksport (export_clause_source_texts.R) → byggerens kandidatnøgler → afhængighedsfilen
#   (source_text_revision_dependencies.sql) → manifest-byggeren → execute_reimport (dry-run med rollback,
#   apply, genafspilning). I-1 revideres (samme spænd); I-2's nye spænd går ud over helposten og bliver en
#   disposition (span_outside), ikke en operation. Bagefter: en genbygning afvises (TEXT_REVISION_V1_MISMATCH),
#   og det gamle manifest i en ny batch afvises af writeren (TEXT_REVISION_BASE_DRIFT) uden skrivninger.
# Del B — afhængighedsfilen mod 5b/2a-fixturen med bindinger (assertion og family): filens nøgler og bindinger
#   er præcis pg_temp.t5_expected, som writerens SQL-tests autoriserer med.
#
# Kræver en base som klausul-writer-integrationen (kontrakt v2). Testen committer syntetiske fixtures.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
scripts_dir <- file.path(root, ".claude/skills/daa-extract/scripts")
source(file.path(scripts_dir, "apply_reimport_helpers.R"))

stopifnot(nzchar(Sys.getenv("PGHOST")), nzchar(Sys.getenv("PGPORT")),
  nzchar(Sys.getenv("PGDATABASE")), nzchar(Sys.getenv("PGUSER")))
# Under-processer (Rscript-eksporten) må ikke læse en brugers ~/.Renviron (den kan pege på prod).
Sys.setenv(R_ENVIRON_USER = "/dev/null")
connect <- function() dbConnect(Postgres(), dbname = Sys.getenv("PGDATABASE"),
  host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
  user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
con <- connect(); on.exit(dbDisconnect(con), add = TRUE)
q <- function(sql, params = list())
  if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
e <- function(sql, params = list())
  invisible(if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql))
sha_text <- function(x) digest::digest(enc2utf8(x), algo = "sha256", serialize = FALSE)
count1 <- function(sql, params = list()) as.integer(q(sql, params)[[1L]][[1L]])
run <- function(cmd, args, env = character()) {
  out <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE, env = env))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}
expect_error_code <- function(expr, code) {
  msg <- tryCatch({ force(expr); "ingen fejl" }, error = function(err) conditionMessage(err))
  if (!grepl(code, msg, fixed = TRUE)) stop("forventede ", code, ", fik: ", msg, call. = FALSE)
}

stopifnot(q("SELECT public.narrative_record_contract_version() v")$v[[1L]] == 2L)

run_nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
run_hash <- function(tag) digest::digest(paste(run_nonce, tag), algo = "sha256", serialize = FALSE)
source_id <- 166120000L + (strtoi(substr(run_hash("source"), 1L, 6L), base = 16L) %% 100000L)

actor <- "6a120000-0000-4000-8000-000000000012"
e("INSERT INTO auth.users(id,email) VALUES($1,'6a-12-writer@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'6a-12-writer@example.invalid','redaktion','Trin 6a writer') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))
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
    reimport_authorized_payloads_json(manifest)))$id[[1L]]

work_dir <- tempfile("kildetekst-revision-"); dir.create(work_dir, mode = "0700")
new_dir <- function(name) { d <- file.path(work_dir, name); dir.create(d, mode = "0700"); Sys.chmod(d, "0700"); d }
write_private <- function(path, text) {
  stopifnot(!file.exists(path)); file.create(path); Sys.chmod(path, "0600")
  con_f <- file(path, open = "wb"); on.exit(close(con_f)); writeBin(charToRaw(enc2utf8(text)), con_f); path
}

# ==== Del A ====================================================================================
rendition <- paste0("### PAGE 10 ###\n", "I\n", "DEN PRØVESKE LINJE\n",
  "1.  Alfa Bravo, f. 1801. Gift 1830\n", "von Revisor prøvelinje\n", "m. Charlie Delta.\n",
  "2.  Echo Foxtrot, f. 1802.\n", "von Revisor halelinje\n",
  "### PAGE 11 ###\n", "von Revisor sidehoved\n", "3.  Golf Hotel, f. 1803.\n")
rendition_path <- write_private(file.path(work_dir, "rendition.txt"), rendition)
rendition_sha <- digest::digest(file = rendition_path, algo = "sha256")

writer_config <- paste0('{"citation_label_template":"Syntetisk side {page_from}",',
  '"extractor_version":"source-text-revision-v1","helpost_observation_kind":"person_post",',
  '"observation_extraction_method":"clause_segment_v1","rendition_key":"syntetisk-r1",',
  '"rendition_kind":"pdf_text_layer","rendition_metadata":{"edition":"syntetisk","pdf_sha256":"',
  strrep("a", 64L), '","pdftotext_version":"syntetisk 0.0"},',
  '"run_key_prefix":"reimport-source-text-revision:","schema_version":"source-text-revision-manifest-v1",',
  '"text_form":"folded_projection@page_header"}')
profile_id <- "syntetisk-source-text-revision-v1"
segmenter_version <- run("python3", c("-c", shQuote(paste0("import sys; sys.path.insert(0,", deparse(scripts_dir),
  "); import build_clause_ledger as b; print(b.segmenter_version())"))))$out
stopifnot(grepl("^clause_segment.py@sha256:[0-9a-f]{16}$", segmenter_version))
profile_path <- file.path(work_dir, "profile.json")
writeLines(as.character(jsonlite::toJSON(list(
  profile_schema_version = "reimport-source-text-revision-profile-v1", source_id = source_id,
  profile_id = profile_id, profile_version = "source-text-revision-v1",
  writer_config = jsonlite::fromJSON(writer_config, simplifyVector = FALSE),
  raw_text_sha256 = rendition_sha, segment_profile_before = "2018-20", segment_profile_after = "2018-20-v2",
  clause_rules_version = "clause-rules-2018-20-v3", segmenter_version = segmenter_version,
  expected_counts = list(source_text_revision = 1L)), auto_unbox = TRUE, pretty = TRUE)), profile_path)
builder <- file.path(scripts_dir, "build_source_text_revision_manifest.py")

# v1-posterne og deres spænd, som 149a ankrede dem (byggerens egne funktioner, støjreglen anywhere).
v1 <- jsonlite::fromJSON(run("python3", c("-c", shQuote(paste0(
  "import sys,json; sys.path.insert(0,", deparse(scripts_dir), "); ",
  "import build_source_text_revision_manifest as B, build_source_evidence_manifest as sem; ",
  "t=open(", deparse(rendition_path), ",encoding='utf-8').read(); ",
  "posts=B._segment(t,'2018-20'); _,_,s=B._spans(t,posts,'anywhere'); ",
  "print(json.dumps([{'key':sem.record_key_of(p),'text':p['raw_text'],'from':s[sem.record_key_of(p)][2],",
  "'to':s[sem.record_key_of(p)][3]} for p in posts]))"))))$out, simplifyVector = FALSE)
stopifnot(length(v1) == 3L, identical(vapply(v1, `[[`, "", "key"), c("I-1", "I-2", "I-3")))

# Kilden, renditionen, profilen og de tre poster med hver sit klausulsæt (én klausul = hele v1-teksten).
e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Syntetisk revision','synthetic','DAA-udgave')", list(source_id))
run_id <- q("INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,$2,'fixture','fixture','fixture',$3,'{}') RETURNING id",
  list(source_id, paste0("6a12-", run_nonce), strrep("1", 64L)))$id[[1L]]
rend_id <- q("INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES($1,'syntetisk-r1','pdf_text_layer',$2,'{}') RETURNING id",
  list(source_id, rendition_sha))$id[[1L]]
profile_sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(writer_config))$h[[1L]]
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'source-text-revision-v1',$3,$4::jsonb)",
  list(source_id, profile_id, profile_sha, writer_config))
post <- list()
for (p in v1) {
  dbBegin(con)
  rec <- q("INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES($1,$2,'person_post',$3) RETURNING id",
    list(source_id, p$key, run_id))$id[[1L]]
  occ <- q("INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,$2,10,10,$3,$4,$5,$6,$7,$8) RETURNING id",
    list(rend_id, paste0("occ-", p$key), p$from, p$to, p$text, strrep("3", 64L), strrep("4", 64L), run_id))$id[[1L]]
  e("INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2,'accepted','{\"fixture\":\"6a12\"}'::jsonb,1,$3,'fixture')",
    list(occ, rec, actor))
  help <- q("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,'person_post',10,10,$2,$3,$4,'clear','fixture',$5) RETURNING id",
    list(occ, p$from, p$to, p$text, run_id))$id[[1L]]
  clause <- q("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq) VALUES($1,'clause',10,10,$2,$3,$4,'clear','clause_segment_v1',$5,$6,0,$7,1,'record_text','[]'::jsonb,1) RETURNING id",
    list(occ, p$from, p$to, p$text, run_id, help, nchar(p$text)))$id[[1L]]
  dbCommit(con)
  post[[p$key]] <- list(record = rec, helpost = help, clause = clause, text = p$text)
}
# Et forslag (proposed) på I-1's klausul: revisionen skal forælde det.
interp_key <- q("SELECT gen_random_uuid()::text k")$k[[1L]]
dbBegin(con)
interp_id <- q("INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id) VALUES(gen_random_uuid(),$1,1,$2,NULL,'relation','relation.marriage','{\"raw\":\"syntetisk\",\"normalized\":\"syntetisk\"}'::jsonb,'fixture','model_inference',0.9,'proposed','fixture',$3) RETURNING id",
  list(interp_key, source_id, run_id))$id[[1L]]
e("INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal) VALUES($1,$2,'supporting',1)",
  list(interp_id, post[["I-1"]]$clause))
dbCommit(con)

# Klausuleksporten (helpostens gældende tekst pr. record).
export_texts <- function(tag) {
  d <- new_dir(tag)
  r <- run("Rscript", c(shQuote(file.path(scripts_dir, "export_clause_source_texts.R")), "--source-id", source_id,
    "--helpost-kind", "person_post", "--output-dir", shQuote(d)))
  if (r$status != 0L) stop("klausuleksport fejlede: ", r$out)
  file.path(d, "clause-source-texts-v1.json")
}
# Kandidatnøglerne (ingen tekst) og afhængighedsfilen for dem.
listed <- run("python3", c(shQuote(builder), "--profile", shQuote(profile_path), "--rendition", shQuote(rendition_path),
  "--list-changed-keys"))
if (listed$status != 0L) stop("kandidatnøgler fejlede: ", listed$out)
stopifnot(!grepl("Alfa|Echo|Revisor", listed$out))
changed <- jsonlite::fromJSON(listed$out)
stopifnot(identical(changed$record_keys, c("I-1", "I-2")))
dependencies <- function(tag, keys = changed$record_keys) {
  r <- run("psql", c("-X", "-At", "-v", "ON_ERROR_STOP=1", "-v", paste0("source_id=", source_id),
    "-v", paste0("profile_id=", profile_id), "-v", shQuote(paste0("record_keys=", jsonlite::toJSON(keys))),
    "-f", shQuote(file.path(scripts_dir, "source_text_revision_dependencies.sql"))))
  if (r$status != 0L) stop("afhængighedsfil fejlede: ", r$out)
  stopifnot(!grepl("Alfa|Echo|Revisor", r$out))
  write_private(file.path(work_dir, paste0("deps-", tag, ".json")), r$out)
}
build <- function(tag, texts_path, deps_path) {
  out <- new_dir(paste0("manifest-", tag))
  r <- run("python3", c(shQuote(builder), "--profile", shQuote(profile_path), "--rendition", shQuote(rendition_path),
    "--texts", shQuote(texts_path), "--dependencies", shQuote(deps_path), "--output", shQuote(out)))
  c(r, list(dir = out))
}

texts_path <- export_texts("export-1")
deps_path <- dependencies("1")
deps <- jsonlite::fromJSON(deps_path, simplifyVector = FALSE)
stopifnot(identical(deps$profile_sha256, profile_sha), length(deps$records) == 2L)
d1 <- deps$records[[1L]]
stopifnot(identical(d1$record_key, "I-1"), identical(d1$helpost_status, "ok"),
  identical(d1$before_text_sha256, sha_text(post[["I-1"]]$text)), identical(as.integer(d1$clause_set_seq), 1L),
  identical(d1$expected_superseded_keys, list(interp_key)), length(d1$expected_binding_loss) == 0L)

built <- build("1", texts_path, deps_path)
if (built$status != 0L) stop("manifest-bygning fejlede: ", built$out)
stopifnot(!grepl("Alfa|Echo|Revisor", built$out))
manifest_path <- file.path(built$dir, "source-text-revision-manifest-v1.json")
index_path <- file.path(built$dir, "source-text-revision-index-v1.json")
stopifnot(identical(bitwAnd(as.integer(file.info(manifest_path)$mode), 511L), 384L),
  identical(bitwAnd(as.integer(file.info(index_path)$mode), 511L), 384L))
index_text <- paste(readLines(index_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
stopifnot(!grepl("verbatim_text|Alfa|Echo|Revisor", index_text))
manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
validate_reimport_manifest(manifest)
stopifnot(identical(vapply(manifest$operations, `[[`, "", "element_id"), "source-text-revision:I-1"),
  identical(manifest$dispositions[[1L]]$record_key, "I-2"), identical(manifest$dispositions[[1L]]$code, "span_outside"),
  identical(manifest$expected_counts$source_text_revision, 1L))
new_text <- manifest$operations[[1L]]$verbatim_text
stopifnot(grepl("prøvelinje", new_text, fixed = TRUE), !identical(new_text, post[["I-1"]]$text))

state <- function() q(paste(
  "SELECT (SELECT count(*) FROM private.source_observation_text t JOIN private.source_observation o ON o.id=t.observation_id",
  "          JOIN private.source_record_occurrence oc ON oc.id=o.occurrence_id WHERE oc.rendition_id=$1) AS texts,",
  "       (SELECT count(*) FROM private.source_observation o JOIN private.source_record_occurrence oc ON oc.id=o.occurrence_id",
  "         WHERE oc.rendition_id=$1 AND o.observation_kind='clause') AS clauses,",
  "       (SELECT count(*) FROM private.interpretation WHERE interpretation_key=$2::uuid) AS interp_versions,",
  "       (SELECT count(*) FROM private.reimport_event WHERE operation='source_text_revision' AND source_record_key IN ('I-1','I-2')",
  "          AND batch_id IN (SELECT b.id FROM private.reimport_batch b WHERE b.source_id=$3)) AS events"),
  list(rend_id, interp_key, source_id))
before <- state()
stopifnot(before$texts == 0L, before$clauses == 3L, before$interp_versions == 1L, before$events == 0L)

# Rollback: dry-run gennemløber hele kæden og efterlader intet.
preview_sha <- run_hash("preview-1")
dry <- execute_reimport(manifest, preview_sha, "dry-run", env_gateway(), NULL)
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed), identical(state(), before))

# Apply.
applied <- execute_reimport(manifest, preview_sha, "apply", env_gateway(), list(id = authorize(manifest, preview_sha)))
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))
after <- state()
n_new <- length(manifest$operations[[1L]]$clauses)
stopifnot(after$texts == 1L, after$clauses == 3L + n_new, after$interp_versions == 2L, after$events == 1L)
current <- q("SELECT text_id::text, verbatim_text FROM private.helpost_text_current($1::uuid)", list(post[["I-1"]]$helpost))
stopifnot(identical(current$verbatim_text, new_text), !is.na(current$text_id))
stopifnot(count1("SELECT count(*) FROM private.source_observation WHERE parent_observation_id=$1::uuid AND clause_set_seq=2 AND parent_text_id=$2::uuid",
  list(post[["I-1"]]$helpost, current$text_id)) == n_new)
stopifnot(identical(q("SELECT disposition FROM private.clause_disposition_current WHERE observation_id=$1::uuid", list(post[["I-1"]]$clause))$disposition, "erstattet"))
superseded <- q("SELECT ic.status, ic.decision_evidence->>'basis' AS basis FROM private.interpretation_current ic WHERE ic.interpretation_key=$1::uuid",
  list(interp_key))
stopifnot(identical(superseded$status, "superseded"), identical(superseded$basis, "source_text_revision"))
event <- q("SELECT payload::text AS p FROM private.reimport_event WHERE operation='source_text_revision' AND source_record_key='I-1' AND batch_id IN (SELECT b.id FROM private.reimport_batch b WHERE b.source_id=$1)",
  list(source_id))$p[[1L]]
stopifnot(!grepl("verbatim_text", event, fixed = TRUE), !grepl("Alfa", event, fixed = TRUE))
# I-2 (span_outside) er urørt.
stopifnot(count1("SELECT count(*) FROM private.source_observation_text WHERE observation_id=$1::uuid", list(post[["I-2"]]$helpost)) == 0L)

# Genafspilning af samme manifest: already_applied, intet nyt.
replay <- execute_reimport(manifest, preview_sha, "apply", env_gateway(), list(id = authorize(manifest, preview_sha)))
stopifnot(identical(replay$status, "already_applied"), identical(state(), after))

# ==== Task 13: scriptlæserne ser helpostens gældende tekst (I-1 revideret; I-2 og I-3 urørte) ============
# (a) 4.3b's runner-input: post_verbatim_text er den gældende tekst, og klausulerne er det aktuelle sæt, skåret af
#     netop den tekst (evidence_runner.check_clauses_within_post kræver delstrenge).
runner_dir <- new_dir("runner-input")
r <- run("Rscript", c(shQuote(file.path(scripts_dir, "export_43b_runner_input.R")), "--source-id", source_id,
  "--writer-profile", profile_id, "--output-dir", shQuote(runner_dir)))
if (r$status != 0L) stop("runner-input fejlede: ", r$out)
stopifnot(!grepl("Alfa|Echo|Golf|Revisor", r$out))
runner <- jsonlite::fromJSON(file.path(runner_dir, "runner-input-v1.json"), simplifyVector = FALSE)$records
stopifnot(identical(sort(names(runner)), c("I-1", "I-2", "I-3")))
if (!identical(runner[["I-1"]]$post_verbatim_text, new_text)) stop("runner-input: I-1 viser ikke den gældende tekst")
for (k in c("I-2", "I-3")) stopifnot(identical(runner[[k]]$post_verbatim_text, post[[k]]$text))
stopifnot(length(runner[["I-1"]]$clauses) == n_new)
for (k in names(runner)) for (cl in runner[[k]]$clauses)
  if (!grepl(cl$verbatim_text, runner[[k]]$post_verbatim_text, fixed = TRUE)) stop("runner-input: klausul uden for posten (", k, ")")
# (b) Eligibility-ledgeren: input_sha er hashen af den gældende tekst, og den følger runner-inputtet.
elig_dir <- new_dir("eligibility")
r <- run("Rscript", c(shQuote(file.path(scripts_dir, "export_model_eligibility.R")), "--source-id", source_id,
  "--output-dir", shQuote(elig_dir), "--restore-identity", "t6a13-fixture"))
if (r$status != 0L) stop("eligibility fejlede: ", r$out)
stopifnot(!grepl("Alfa|Echo|Golf|Revisor", r$out))
ledger <- jsonlite::fromJSON(file.path(elig_dir, "eligibility-ledger-v1.json"), simplifyVector = FALSE)$records
if (!identical(ledger[["I-1"]]$record_input_sha256, sha_text(new_text))) stop("eligibility: I-1's input_sha er ikke den gældende teksts")
for (k in c("I-2", "I-3")) stopifnot(identical(ledger[[k]]$record_input_sha256, sha_text(post[[k]]$text)))
for (k in names(runner)) stopifnot(identical(ledger[[k]]$record_input_sha256, sha_text(runner[[k]]$post_verbatim_text)))
# (c) Klausul-projektionen: parent_verbatim_sha256 er hashen af den tekst, klausulens SÆT er skåret af — sæt 1 af
#     basisteksten, sæt 2 af tekstversionen (ikke den gældende tekst for alle sæt).
clause_projection <- run("psql", c("-X", "-At", "-q", "-v", "ON_ERROR_STOP=1", "-v", paste0("source_id=", source_id),
  "-f", shQuote(file.path(scripts_dir, "clause_evidence_projection.psql"))),
  env = paste0("DAA_PROJECTION_SQL_DIR=", shQuote(scripts_dir)))
if (clause_projection$status != 0L) stop("klausul-projektion fejlede: ", clause_projection$out)
stopifnot(!grepl("Alfa|Echo|Golf|Revisor", clause_projection$out))
projected <- jsonlite::fromJSON(clause_projection$out, simplifyVector = FALSE)$clauses
parent_sha <- function(k, seq) unique(vapply(Filter(function(c) identical(c$record_key, k) && c$clause_set_seq == seq, projected),
  function(c) c$parent_verbatim_sha256, ""))
stopifnot(identical(parent_sha("I-1", 1L), sha_text(post[["I-1"]]$text)))
if (!identical(parent_sha("I-1", 2L), sha_text(new_text))) stop("klausul-projektion: sæt 2 hasher ikke sin tekstversion")
for (k in c("I-2", "I-3")) stopifnot(identical(parent_sha(k, 1L), sha_text(post[[k]]$text)))

# Genkørsel efter gennemført apply afvises:
# (1) byggeren: helpostens gældende tekst er nu revisionens, ikke v1-teksten.
rebuilt <- build("2", export_texts("export-2"), dependencies("2"))
stopifnot(rebuilt$status != 0L, grepl("TEXT_REVISION_V1_MISMATCH", rebuilt$out, fixed = TRUE),
  length(list.files(rebuilt$dir)) == 0L)
# (2) writeren: det gamle manifest i en ny batch (nyt indholdshash) møder en anden før-tekst.
stale <- manifest
stale$provenance$genkoersel <- TRUE
stale$manifest_content_sha256 <- NULL
stale_unhashed <- write_private(file.path(work_dir, "stale-unhashed.json"),
  as.character(jsonlite::toJSON(stale, auto_unbox = TRUE, null = "null", digits = NA)))
stale$manifest_content_sha256 <- run("python3", c("-c", shQuote(paste0("import sys,json; sys.path.insert(0,",
  deparse(scripts_dir), "); import build_source_text_revision_manifest as B; ",
  "print(B._canonical_sha256(json.load(open(", deparse(stale_unhashed), ",encoding='utf-8'))))"))))$out
stopifnot(grepl("^[0-9a-f]{64}$", stale$manifest_content_sha256), !identical(stale$manifest_content_sha256, manifest$manifest_content_sha256))
validate_reimport_manifest(stale)
stale_preview <- run_hash("preview-stale")
expect_error_code(execute_reimport(stale, stale_preview, "apply", env_gateway(), list(id = authorize(stale, stale_preview))),
  "TEXT_REVISION_BASE_DRIFT")
stopifnot(identical(state(), after))

# Task 13: en tekstversion uden et klausulsæt bundet til den (lagt direkte af tabelejeren, ingen writer gør det)
# gør klausulerne til andet end delstrenge af posten; runner-eksporten stopper i stedet for at levere dem.
e(paste("INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to,is_preferred)",
  "SELECT o.id,$2,1,o.verbatim_text||' x',o.char_from,o.char_to,true FROM private.source_observation o WHERE o.id=$1::uuid"),
  list(post[["I-3"]]$helpost, rend_id))
unbound <- run("Rscript", c(shQuote(file.path(scripts_dir, "export_43b_runner_input.R")), "--source-id", source_id,
  "--writer-profile", profile_id, "--output-dir", shQuote(new_dir("runner-input-unbound"))))
stopifnot(unbound$status != 0L, grepl("EXPORT_CLAUSE_SET_TEXT_MISMATCH", unbound$out, fixed = TRUE),
  !grepl("Alfa|Echo|Golf|Revisor", unbound$out), length(list.files(file.path(work_dir, "runner-input-unbound"))) == 0L)

# ==== Del B: afhængighedsfilen = writerens mængder på en post med bindinger ============================
fixture_files <- file.path(root, "tests", "sql", "fixtures", c("relation-5b.sql", "relation-2a.sql", "source-text-revision.sql"))
psql_value <- function(sql) {
  r <- run("psql", c("-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", as.vector(rbind("-f", shQuote(fixture_files))), "-c", shQuote(sql)),
    env = "PGOPTIONS='-c client_min_messages=warning'")
  if (r$status != 0L) stop("fixture fejlede: ", r$out)
  lines <- strsplit(trimws(r$out), "\n", fixed = TRUE)[[1L]]
  lines[[length(lines)]]
}
base <- -(66120000L + 2L * (strtoi(substr(run_hash("base"), 1L, 6L), base = 16L) %% 400000L))
fx <- jsonlite::fromJSON(psql_value(sprintf("SELECT pg_temp.t5_post(%d,'%s',false,true)::text", base,
  "6a120000-0000-4000-8000-0000000000b1")), simplifyVector = FALSE)
expected <- jsonlite::fromJSON(psql_value(sprintf("SELECT pg_temp.t5_expected('%s')::text", fx$helpost)), simplifyVector = FALSE)
stopifnot(length(expected$keys) == 3L, length(expected$bindings) == 2L)
r <- run("psql", c("-X", "-At", "-v", "ON_ERROR_STOP=1", "-v", paste0("source_id=", base),
  "-v", paste0("profile_id=", fx$profile$profile_id), "-v", shQuote(paste0("record_keys=", jsonlite::toJSON(list(fx$record_key), auto_unbox = TRUE))),
  "-f", shQuote(file.path(scripts_dir, "source_text_revision_dependencies.sql"))))
if (r$status != 0L) stop("afhængighedsfil (del B) fejlede: ", r$out)
deps_b <- jsonlite::fromJSON(r$out, simplifyVector = FALSE)
rec_b <- deps_b$records[[1L]]
ordered <- function(bindings) lapply(bindings, function(b) b[c("promotion_id", "target_type")])
stopifnot(identical(rec_b$helpost_status, "ok"), identical(rec_b$expected_superseded_keys, expected$keys),
  identical(ordered(rec_b$expected_binding_loss), ordered(expected$bindings)),
  identical(rec_b$before_text_sha256, sha_text(fx$text)), identical(as.integer(rec_b$clause_set_seq), 1L),
  identical(rec_b$clause_set_sha256, q("SELECT private.clause_set_sha256($1::uuid,1) h", list(fx$helpost))$h[[1L]]),
  identical(deps_b$profile_sha256, fx$profile$profile_sha256))
# Bindingerne er objekter med præcis {promotion_id,target_type} i writerens sortering.
stopifnot(all(vapply(rec_b$expected_binding_loss, function(b) identical(sort(names(b)), c("promotion_id", "target_type")), NA)),
  identical(vapply(rec_b$expected_binding_loss, `[[`, "", "promotion_id"), sort(vapply(rec_b$expected_binding_loss, `[[`, "", "promotion_id"), method = "radix")))

cat("source_text_revision integration OK\n")
