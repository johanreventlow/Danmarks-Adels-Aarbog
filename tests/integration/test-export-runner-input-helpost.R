# Trin 6c-1, Task 4: runner-inputtet (export_43b_runner_input.R) vælger helposten med writerens regel
# (private.record_helpost_status, slagsen fra --writer-profile) og personaen gennem helpostens primære mention.
# Alt syntetisk; outputfilerne ligger i en privat temp-mappe, og indholdet printes aldrig.
#
#   A  2018-20-lignende kilde (helpost-slags person_post, én forankring pr. record): outputtet er byte-ens med
#      det, scriptet på main (før Task 4) gav på samme fixture (hardkodet sha nedenfor).
#   B  1939-lignende kilde (helpost-slags person, flere forankringer): helposten og dens klausuler vælges uafhængigt
#      af forankringernes rækkefølge, og personaen er helpostens primære mention (ikke en lokal underforekomsts).
#   C  fejlkoder: ingen/flere helposter (EXPORT_HELPOST_NOT_UNIQUE), flere primære personas
#      (EXPORT_PRIMARY_PERSONA_NOT_UNIQUE), ukendt profil (EXPORT_WRITER_PROFILE_UNKNOWN).
#
# Kræver en base som kildetekst-revisions-integrationen (schema + db-rls). Testen committer syntetiske fixtures;
# kilde A bruger et fast id (outputtet indeholder source_id), så testen kan kun køres én gang pr. base.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite) })

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
scripts_dir <- file.path(root, ".claude/skills/daa-extract/scripts")
stopifnot(nzchar(Sys.getenv("PGHOST")), nzchar(Sys.getenv("PGPORT")),
  nzchar(Sys.getenv("PGDATABASE")), nzchar(Sys.getenv("PGUSER")))
Sys.setenv(R_ENVIRON_USER = "/dev/null")
con <- dbConnect(Postgres(), dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
  port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD"))
on.exit(dbDisconnect(con), add = TRUE)
q <- function(sql, params = list()) if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
e <- function(sql, params = list()) invisible(if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql))
run <- function(cmd, args) {
  out <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"), out = paste(out, collapse = "\n"))
}

# sha256 af runner-input-v1.json for kilde A, produceret af main's script (før Task 4) på præcis denne fixture.
EXPECTED_A_SHA <- "d53bbe9b9ab6fcbc6caf1a8649ea775d75abcab54336993852c9a10f1ad05709"
SOURCE_A <- 166140001L

actor <- "6c140000-0000-4000-8000-000000000004"
e("INSERT INTO auth.users(id,email) VALUES($1,'6c1-4-export@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'6c1-4-export@example.invalid','redaktion','Trin 6c-1 export') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))

nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
rand_source <- function() 166150000L + sample.int(800000L, 1L)
dig <- function(tag) digest::digest(paste(nonce, tag), algo = "sha256", serialize = FALSE)

new_source <- function(source_id, profile_id, helpost_kind) {
  e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Syntetisk eksport','synthetic','DAA-udgave')", list(source_id))
  run_id <- q("INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,$2,'fixture','fixture','fixture',$3,'{}') RETURNING id",
    list(source_id, paste0("6c14-", source_id), strrep("1", 64L)))$id[[1L]]
  rend <- q("INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES($1,'syntetisk-r1','pdf_text_layer',$2,'{}') RETURNING id",
    list(source_id, strrep("2", 64L)))$id[[1L]]
  # Writerprofilen: 2018-20's har ingen helpost-nøgle (default person_post); 1939's har `person`.
  cfg <- sprintf(paste0('{"citation_label_template":"Syntetisk side {page_from}","extractor_version":"fixture",',
    '"observation_extraction_method":"clause_segment_v1","rendition_key":"syntetisk-r1","rendition_kind":"pdf_text_layer",',
    '"rendition_metadata":{},"run_key_prefix":"fixture:","schema_version":"fixture-v1"%s}'),
    if (is.null(helpost_kind)) "" else sprintf(',"helpost_observation_kind":"%s"', helpost_kind))
  sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(cfg))$h[[1L]]
  e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'fixture',$3,$4::jsonb)",
    list(source_id, profile_id, sha, cfg))
  list(id = source_id, run = run_id, rend = rend)
}

# occs: liste af list(key, from, kind, text, helpost = TRUE/FALSE); rækkefølgen er indsættelsesrækkefølgen.
# primary: liste af list(on = occurrence-key, persona = persona-nøgle, persona_id = uuid eller NULL).
new_record <- function(s, record_key, occs, primary = list(), clause = TRUE) {
  dbBegin(con)
  rec <- q("INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES($1,$2,'person_post',$3) RETURNING id",
    list(s$id, record_key, s$run))$id[[1L]]
  obs <- list()
  for (o in occs) {
    to <- o$from + nchar(o$text)
    occ <- q("INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,$2,10,10,$3,$4,$5,$6,$7,$8) RETURNING id",
      list(s$rend, paste0(record_key, "-", o$key), o$from, to, o$text, strrep("3", 64L), strrep("4", 64L), s$run))$id[[1L]]
    e("INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2,'accepted','{\"fixture\":\"6c14\"}'::jsonb,1,$3,'fixture')",
      list(occ, rec, actor))
    ob <- q("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,$2,10,10,$3,$4,$5,'clear','fixture',$6) RETURNING id",
      list(occ, o$kind, o$from, to, o$text, s$run))$id[[1L]]
    obs[[o$key]] <- ob
    if (isTRUE(o$helpost) && clause)
      e("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq) VALUES($1,'clause',10,10,$2,$3,$4,'clear','clause_segment_v1',$5,$6,0,$7,1,'record_text','[]'::jsonb,1)",
        list(occ, o$from, to, o$text, s$run, ob, nchar(o$text)))
  }
  for (p in primary) {
    pid <- p$persona_id %||% q("SELECT gen_random_uuid()::text i")$i[[1L]]
    e("INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES($1::uuid,$2,$3,$4)", list(pid, s$id, p$persona, s$run))
    txt <- occs[[which(vapply(occs, `[[`, "", "key") == p$on)]]$text
    m <- q("INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) VALUES($1,'person_name',0,$2,$3,$4) RETURNING id",
      list(obs[[p$on]], 4L, substr(txt, 1L, 4L), s$run))$id[[1L]]
    e("INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES($1::uuid,$2::uuid,'primary',1)", list(pid, m))
  }
  dbCommit(con)
  invisible(rec)
}
`%||%` <- function(x, y) if (is.null(x)) y else x

work_dir <- tempfile("export-helpost-"); dir.create(work_dir, mode = "0700")
on.exit(unlink(work_dir, recursive = TRUE), add = TRUE)
export <- function(script, source_id, profile, tag) {
  d <- file.path(work_dir, tag); dir.create(d, mode = "0700")
  r <- run("Rscript", c(shQuote(file.path(scripts_dir, script)), "--source-id", source_id,
    "--writer-profile", profile, "--output-dir", shQuote(d)))
  c(r, list(path = file.path(d, "runner-input-v1.json"), dir = d))
}
expect_fail <- function(r, code) {
  if (r$status == 0L) stop("forventede fejl ", code, ", men eksporten lykkedes")
  if (!grepl(code, r$out, fixed = TRUE)) stop("forventede ", code, ", fik: ", substr(r$out, 1L, 200L))
  if (grepl("Syntetisk|Alfa|Bravo", r$out)) stop("fejlbeskeden indeholder posttekst")
  stopifnot(length(list.files(r$dir)) == 0L)
}

# ==== A: 2018-20-lignende, én forankring pr. record, personaens nøgle = record_key ===================
sa <- new_source(SOURCE_A, "daa-2018-20-interpretation-proposal-v1", NULL)
txt_a <- function(k) paste0("Syntetisk post ", k, " Alfa Bravo, f. 1801 i Prøvested.")
for (k in c("I-1", "I-2", "I-3")) {
  pid <- sprintf("6c140000-0000-4000-8000-0000000000a%d", match(k, c("I-1", "I-2", "I-3")))
  new_record(sa, k, list(list(key = "h", from = 0L, kind = "person_post", text = txt_a(k), helpost = TRUE)),
    primary = if (k == "I-3") list() else list(list(on = "h", persona = k, persona_id = pid)))
}
ra <- export("export_43b_runner_input.R", SOURCE_A, "daa-2018-20-interpretation-proposal-v1", "a")
if (ra$status != 0L) stop("eksport A fejlede: ", substr(ra$out, 1L, 300L))
stopifnot(grepl("RUNNER_INPUT_OK records=3 klausuler=3 uden_klausuler=0", ra$out, fixed = TRUE))
sha_a <- digest::digest(file = ra$path, algo = "sha256")
if (!identical(sha_a, EXPECTED_A_SHA)) stop("2018-20-outputtet er ikke byte-ens med main (sha ", sha_a, ")")
rec_a <- jsonlite::fromJSON(ra$path, simplifyVector = FALSE)$records
stopifnot(identical(rec_a[["I-1"]]$persona_id, "6c140000-0000-4000-8000-0000000000a1"), identical(rec_a[["I-3"]]$persona_id, ""))

# ==== B: 1939-lignende, flere forankringer ===========================================================
sb <- new_source(rand_source(), "daa-1939-interpretation-proposal-v1", "person")
hp <- function(k) paste0("Syntetisk helpost ", k, " Alfa Bravo, f. 1801; gift med Charlie Delta; barn Echo Foxtrot.")
sub1 <- function(k) list(key = "s1", from = 10L, kind = "name", text = "Alfa Bravo", helpost = FALSE)
sub2 <- function(k) list(key = "s2", from = 40L, kind = "name", text = "Charlie Delta", helpost = FALSE)
# I-1: helposten først; I-2: helposten sidst + en lokal primær mention på en underforekomst (skal ignoreres).
new_record(sb, "I-1", list(list(key = "h", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE), sub1(), sub2()),
  primary = list(list(on = "h", persona = "1939:I-1")))
new_record(sb, "I-2", list(sub1(), sub2(), list(key = "h", from = 0L, kind = "person", text = hp("I-2"), helpost = TRUE)),
  primary = list(list(on = "h", persona = "1939:I-2"), list(on = "s1", persona = "1939:I-2-lokal")))
# I-3: ingen persona -> tom persona_id.
new_record(sb, "I-3", list(list(key = "h", from = 0L, kind = "person", text = hp("I-3"), helpost = TRUE), sub1()))
rb <- export("export_43b_runner_input.R", sb$id, "daa-1939-interpretation-proposal-v1", "b")
if (rb$status != 0L) stop("eksport B fejlede: ", substr(rb$out, 1L, 300L))
stopifnot(grepl("RUNNER_INPUT_OK records=3 klausuler=3 uden_klausuler=0", rb$out, fixed = TRUE))
rec_b <- jsonlite::fromJSON(rb$path, simplifyVector = FALSE)$records
stopifnot(identical(sort(names(rec_b)), c("I-1", "I-2", "I-3")))
for (k in names(rec_b)) {
  stopifnot(identical(rec_b[[k]]$post_verbatim_text, hp(k)), length(rec_b[[k]]$clauses) == 1L,
    identical(rec_b[[k]]$clauses[[1L]]$verbatim_text, hp(k)))
}
want <- q("SELECT sr.record_key k, p.id::text i FROM private.source_persona p JOIN private.source_record sr ON sr.source_id=p.source_id AND '1939:'||sr.record_key=p.persona_key WHERE p.source_id=$1", list(sb$id))
for (i in seq_len(nrow(want))) stopifnot(identical(rec_b[[want$k[i]]]$persona_id, want$i[i]))
stopifnot(identical(rec_b[["I-3"]]$persona_id, ""))

# ==== C: fejlkoder ====================================================================================
expect_fail(export("export_43b_runner_input.R", sb$id, "findes-ikke", "c0"), "EXPORT_WRITER_PROFILE_UNKNOWN")
# Slagsen følger profilen: 1939-posterne har ingen `person_post`-helpost, hvis profilen siger det.
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) SELECT source_id,'default-kind','fixture',private.reimport_canonical_json_sha256(writer_config - 'helpost_observation_kind'),writer_config - 'helpost_observation_kind' FROM private.reimport_writer_profile WHERE source_id=$1 AND profile_id='daa-1939-interpretation-proposal-v1'", list(sb$id))
expect_fail(export("export_43b_runner_input.R", sb$id, "default-kind", "c1"), "EXPORT_HELPOST_NOT_UNIQUE")

fail_source <- function(tag, build, code) {
  s <- new_source(rand_source(), "p", "person")
  build(s)
  expect_fail(export("export_43b_runner_input.R", s$id, "p", tag), code)
}
# To uafhængige helposter i samme record -> ambiguous.
fail_source("c2", function(s) new_record(s, "I-1", list(
  list(key = "h1", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE),
  list(key = "h2", from = 200L, kind = "person", text = hp("I-1"), helpost = TRUE))), "EXPORT_HELPOST_NOT_UNIQUE")
# En underforekomst uden for helpostens spænd -> outside.
fail_source("c3", function(s) new_record(s, "I-1", list(
  list(key = "h", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE),
  list(key = "x", from = 500L, kind = "name", text = "Alfa Bravo", helpost = FALSE))), "EXPORT_HELPOST_NOT_UNIQUE")
# Ingen helpost af slagsen.
fail_source("c4", function(s) new_record(s, "I-1", list(
  list(key = "x", from = 0L, kind = "name", text = hp("I-1"), helpost = FALSE))), "EXPORT_HELPOST_NOT_UNIQUE")
# To primære personas på helposten.
fail_source("c5", function(s) new_record(s, "I-1",
  list(list(key = "h", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE)),
  primary = list(list(on = "h", persona = "1939:I-1"), list(on = "h", persona = "1939:I-1-b"))), "EXPORT_PRIMARY_PERSONA_NOT_UNIQUE")

cat("TEST_EXPORT_RUNNER_INPUT_HELPOST_OK\n")
