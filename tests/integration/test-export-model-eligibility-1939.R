# Trin 6c-1, Task 5: eligibility-ledgeren (export_model_eligibility.R) har en politik pr. udgave (--policy), og
# helposten vælges med writerens regel (--writer-profile, private.record_helpost_status). Alt syntetisk; ledgerne
# ligger i en privat temp-mappe, og posttekst printes aldrig.
#
#   A  2018-20-lignende kilde, `exclusion-2018-20-v1`: afgørelser, årsager og input_sha pr. record er de samme, som
#      scriptet på main (før Task 5) gav på præcis denne fixture (hardkodet projektions-sha nedenfor; lokalt kan
#      main's script køres direkte med ELIGIBILITY_MAIN_SCRIPT=<sti>, se nederst i afsnit A).
#   B  1939-lignende kilde, `exclusion-1939-v1`: hver regel giver præcis sin årsag; årstalsreglen (streng og
#      OCR-tolerant); fail-closed for NULL; en post med flere forankringer giver ÉN række, hvis input_sha er sha256 af
#      runner-inputtets post_verbatim_text for samme fixture.
#   C  fejlkoder: ukendt politik (EXPORT_POLICY_UNKNOWN), ukendt profil (EXPORT_WRITER_PROFILE_UNKNOWN), flere/udenfor-
#      helposter (EXPORT_HELPOST_NOT_UNIQUE), manglende flag (EXPORT_CLI_INVALID); to primære personas = udelukket.
#
# Kræver en base som runner-input-integrationen (schema + db-rls); registrerer sine egne writerprofiler.
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
`%||%` <- function(x, y) if (is.null(x)) y else x
sha_text <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
ZERO <- strrep("0", 64L)
PII <- "Syntetisk|Alfa|Bravo|Proevested"

# Projektion af ledgerens records: nøgle, status, årsager og input_sha (ikke regelfilens sha). Sorteret i C-orden.
EXPECTED_A_PROJECTION_SHA <- "799c25c8952bca4badceae6d54f306195d77bcb4a17061475fe59d843eaccf45"

actor <- "6c150000-0000-4000-8000-000000000005"
e("INSERT INTO auth.users(id,email) VALUES($1,'6c1-5-elig@example.invalid') ON CONFLICT(id) DO NOTHING", list(actor))
e("INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'6c1-5-elig@example.invalid','redaktion','Trin 6c-1 eligibility') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'", list(actor))

rand_source <- function() 166950000L + sample.int(800000L, 1L)

# edition: writerprofilens rendition_metadata.edition (politikken er bundet til den); NULL = ingen udgave.
new_source <- function(profile_id, helpost_kind, edition) {
  repeat { source_id <- rand_source(); if (nrow(q("SELECT 1 FROM public.source WHERE id=$1", list(source_id))) == 0L) break }
  e("INSERT INTO public.source(id,titel,udgave,slags) VALUES($1,'Syntetisk eligibility','synthetic','DAA-udgave')", list(source_id))
  run_id <- q("INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,$2,'fixture','fixture','fixture',$3,'{}') RETURNING id",
    list(source_id, paste0("6c15-", source_id), strrep("1", 64L)))$id[[1L]]
  rend <- q("INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES($1,'syntetisk-r1','pdf_text_layer',$2,'{}') RETURNING id",
    list(source_id, strrep("2", 64L)))$id[[1L]]
  cfg <- sprintf(paste0('{"citation_label_template":"Syntetisk side {page_from}","extractor_version":"fixture",',
    '"observation_extraction_method":"clause_segment_v1","rendition_key":"syntetisk-r1","rendition_kind":"pdf_text_layer",',
    '"rendition_metadata":%s,"run_key_prefix":"fixture:","schema_version":"fixture-v1"%s}'),
    if (is.null(edition)) "{}" else sprintf('{"edition":"%s"}', edition),
    if (is.null(helpost_kind)) "" else sprintf(',"helpost_observation_kind":"%s"', helpost_kind))
  sha <- q("SELECT private.reimport_canonical_json_sha256($1::jsonb) h", list(cfg))$h[[1L]]
  e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'fixture',$3,$4::jsonb)",
    list(source_id, profile_id, sha, cfg))
  list(id = source_id, run = run_id, rend = rend)
}

# occs: liste af list(key, from, kind, text, helpost); rækkefølgen er indsættelsesrækkefølgen.
# primary: liste af list(on = occurrence-key, persona = persona-nøgle). Returnerer record-id og persona-id'erne.
new_record <- function(s, record_key, occs, primary = list()) {
  dbBegin(con)
  rec <- q("INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES($1,$2,'person_post',$3) RETURNING id::text",
    list(s$id, record_key, s$run))$id[[1L]]
  obs <- list()
  for (o in occs) {
    to <- o$from + nchar(o$text)
    occ <- q("INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES($1,$2,10,10,$3,$4,$5,$6,$7,$8) RETURNING id",
      list(s$rend, paste0(record_key, "-", o$key), o$from, to, o$text, strrep("3", 64L), strrep("4", 64L), s$run))$id[[1L]]
    e("INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES($1,$2::uuid,'accepted','{\"fixture\":\"6c15\"}'::jsonb,1,$3,'fixture')",
      list(occ, rec, actor))
    ob <- q("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES($1,$2,10,10,$3,$4,$5,'clear','fixture',$6) RETURNING id",
      list(occ, o$kind, o$from, to, o$text, s$run))$id[[1L]]
    obs[[o$key]] <- ob
    if (isTRUE(o$helpost))
      e("INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,clause_set_seq) VALUES($1,'clause',10,10,$2,$3,$4,'clear','clause_segment_v1',$5,$6,0,$7,1,'record_text','[]'::jsonb,1)",
        list(occ, o$from, to, o$text, s$run, ob, nchar(o$text)))
  }
  pids <- character(0)
  for (p in primary) {
    pid <- q("SELECT gen_random_uuid()::text i")$i[[1L]]
    e("INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES($1::uuid,$2,$3,$4)", list(pid, s$id, p$persona, s$run))
    txt <- occs[[which(vapply(occs, `[[`, "", "key") == p$on)]]$text
    m <- q("INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) VALUES($1,'person_name',0,4,$2,$3) RETURNING id",
      list(obs[[p$on]], substr(txt, 1L, 4L), s$run))$id[[1L]]
    e("INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES($1::uuid,$2::uuid,'primary',1)", list(pid, m))
    pids <- c(pids, pid)
  }
  dbCommit(con)
  invisible(list(id = rec, personas = pids))
}

# person: levende/privat/staged; NA skrives som NULL (fail-closed: NULL tæller som et hit).
new_person <- function(levende = FALSE, privat = FALSE, staged = FALSE) {
  q("INSERT INTO public.person(levende,privat,staged) VALUES($1,$2,$3) RETURNING id",
    list(levende, privat, staged))$id[[1L]]
}
publish <- function(s, rec, person_id, status = "published") {
  n <- q("INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES('person',$1,$2,'1','x') RETURNING id",
    list(person_id, s$id))$id[[1L]]
  e("INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status) VALUES($1,$2::uuid,'L','C',$3)",
    list(n, rec$id, status))
}
new_family <- function(members) {  # members: list(list(person, rolle))
  f <- q("INSERT INTO public.family(type) VALUES('vielse') RETURNING id")$id[[1L]]
  for (m in members) e("INSERT INTO public.family_member(family_id,person_id,rolle) VALUES($1,$2,$3)", list(f, m[[1L]], m[[2L]]))
  invisible(f)
}
samme_som <- function(alias, canonical) {
  e("INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES('person',$1,'person',$2,'samme_som')",
    list(alias, canonical))
}

work_dir <- tempfile("export-eligibility-"); dir.create(work_dir, mode = "0700")
on.exit(unlink(work_dir, recursive = TRUE), add = TRUE)
eligibility <- function(source_id, policy, profile, tag, script = file.path(scripts_dir, "export_model_eligibility.R"),
                        extra = NULL) {
  d <- file.path(work_dir, tag); dir.create(d, mode = "0700")
  a <- c(shQuote(script), "--source-id", source_id, "--output-dir", shQuote(d), "--restore-identity", "t6c1-5-fixture")
  if (!is.null(policy)) a <- c(a, "--policy", policy)
  if (!is.null(profile)) a <- c(a, "--writer-profile", profile)
  r <- run("Rscript", c(a, extra))
  p <- file.path(d, "eligibility-ledger-v1.json")
  if (r$status == 0L) {
    raw <- paste(readLines(p, warn = FALSE), collapse = "\n")
    if (grepl(PII, raw) || grepl(PII, r$out)) stop("ledger eller stdout indeholder posttekst (", tag, ")")
  }
  c(r, list(path = p, dir = d))
}
expect_fail <- function(r, code) {
  if (r$status == 0L) stop("forventede fejl ", code, ", men eksporten lykkedes")
  if (!grepl(code, r$out, fixed = TRUE)) stop("forventede ", code, ", fik: ", substr(r$out, 1L, 200L))
  if (grepl(PII, r$out)) stop("fejlbeskeden indeholder posttekst")
  stopifnot(length(list.files(r$dir)) == 0L)
}
ledger_of <- function(r) jsonlite::fromJSON(r$path, simplifyVector = FALSE)
projection <- function(records) {
  keys <- names(records)[order(names(records), method = "radix")]
  paste(vapply(keys, function(k) paste(k, records[[k]]$status, paste(unlist(records[[k]]$reasons), collapse = ","),
    records[[k]]$record_input_sha256, sep = "|"), ""), collapse = "\n")
}

# ==== A: 2018-20, exclusion-2018-20-v1 er uændret =====================================================
P18 <- "daa-2018-20-interpretation-proposal-v1"
sa <- new_source(P18, NULL, "2018-20")
txt_a <- function(k, extra = "") paste0("Syntetisk post ", k, " Alfa Bravo, f. 1801 i Proevested", extra, ".")
a_rec <- function(k, extra = "") new_record(sa, k, list(list(key = "h", from = 0L, kind = "person_post", text = txt_a(k, extra), helpost = TRUE)),
  primary = list(list(on = "h", persona = k)))
ext_id <- function(k, person) e("INSERT INTO public.person_external_id(person_id,source_id,record_key) VALUES($1,$2,$3)", list(person, sa$id, k))
a_rec("I-1"); p <- new_person(); ext_id("I-1", p)                                   # tilladt
a_rec("I-2"); ext_id("I-2", new_person(levende = TRUE))                               # principal_living
a_rec("I-3")                                                                         # uden person -> principal_living
a_rec("I-4"); p4 <- new_person(); ext_id("I-4", p4)
new_family(list(list(p4, "partner"), list(new_person(levende = TRUE), "barn")))       # relative_living
a_rec("I-5"); p5 <- new_person(); ext_id("I-5", p5)
new_family(list(list(p5, "partner"), list(new_person(), "partner")))                  # spouse_undated_marriage
a_rec("I-6", ", f. 12. Maj 1955"); ext_id("I-6", new_person())                       # eligible: main's regel fanger IKKE
# denne form ('12.' er cifre, som [^0-9]{0,20} ikke tillader) — eksisterende adfærd, bevaret for identitet med main.
new_record(sa, "I-7", list()); ext_id("I-7", new_person())                     # ingen forankring -> intet input
new_record(sa, "I-8", list())                                                        # ingen forankring, ingen person
a_rec("I-9", ", f. 1950"); ext_id("I-9", new_person(levende = NA))                    # flere årsager

ra <- eligibility(sa$id, "exclusion-2018-20-v1", P18, "a")
if (ra$status != 0L) stop("eksport A fejlede: ", substr(ra$out, 1L, 300L))
la <- ledger_of(ra)
stopifnot(identical(la$policy_version, "exclusion-2018-20-v1"), length(la$records) == 9L)
proj_a <- projection(la$records)
if (nzchar(Sys.getenv("ELIGIBILITY_MAIN_SCRIPT"))) {
  # Lokalt: kør main's script (git show main:… sammen med export_legacy_migration_candidates_helpers.R i samme mappe).
  rm <- eligibility(sa$id, NULL, NULL, "a-main", script = Sys.getenv("ELIGIBILITY_MAIN_SCRIPT"))
  if (rm$status != 0L) stop("main's eksport fejlede: ", substr(rm$out, 1L, 300L))
  if (!identical(projection(ledger_of(rm)$records), proj_a)) stop("2018-20-afgørelserne afviger fra main's")
  cat("A: main's script live-sammenlignet: ens\n")
}
if (!identical(sha_text(proj_a), EXPECTED_A_PROJECTION_SHA))
  stop("2018-20-ledgeren afviger fra main's (projektions-sha ", sha_text(proj_a), ")")
stopifnot(identical(la$records[["I-1"]]$status, "eligible"),
  identical(la$records[["I-1"]]$record_input_sha256, sha_text(txt_a("I-1"))),
  identical(unlist(la$records[["I-9"]]$reasons), c("principal_living", "birth_year_text_filter")))

# ==== B: 1939, exclusion-1939-v1 =======================================================================
P39 <- "daa-1939-interpretation-proposal-v1"
sb <- new_source(P39, "person", "1939")
hp <- function(k, extra = "") paste0("Syntetisk helpost ", k, " Alfa Bravo, f. 1801 i Proevested; gift 1830", extra, ".")
b_post <- function(k, extra = "", primary = TRUE) new_record(sb, k,
  list(list(key = "h", from = 0L, kind = "person", text = hp(k, extra), helpost = TRUE)),
  primary = if (primary) list(list(on = "h", persona = paste0("1939:", k))) else list())
# b_bound: en post med published binding til en (afdød, ikke-privat) person, medmindre andet angives.
b_bound <- function(k, extra = "", status = "published", ...) {
  r <- b_post(k, extra); pp <- new_person(...); publish(sb, r, pp, status); invisible(list(rec = r, person = pp))
}
expect_b <- list()
# 1. Flere forankringer, helposten sidst, en lokal primær mention på en underforekomst; afdød familie og samme_som-partner.
ok <- new_record(sb, "B-ok", list(
  list(key = "s1", from = 10L, kind = "name", text = "Alfa Bravo", helpost = FALSE),
  list(key = "s2", from = 40L, kind = "name", text = "Charlie Delta", helpost = FALSE),
  list(key = "h", from = 0L, kind = "person", text = hp("B-ok"), helpost = TRUE)),
  primary = list(list(on = "h", persona = "1939:B-ok"), list(on = "s1", persona = "1939:B-ok-lokal")))
p_ok <- new_person(); publish(sb, ok, p_ok)
q_ok <- new_person(); samme_som(q_ok, p_ok)
new_family(list(list(p_ok, "partner"), list(new_person(), "partner"), list(new_person(), "barn")))
new_family(list(list(q_ok, "barn"), list(new_person(), "partner")))
expect_b[["B-ok"]] <- character(0)
# 2. Årstalsreglen.
b_bound("B-1914", "; f. 1914");               expect_b[["B-1914"]] <- character(0)          # 1914 alene udelukker ikke
# Grænsen 1915 for hver del alene: klistret (kun den strenge) og OCR-tolerant (kun den tolerante).
b_bound("B-limit-glued", "; Kbh1915");        expect_b[["B-limit-glued"]] <- "text_year_ge_1915"
b_bound("B-limit-ocr", "; f. l9l5");          expect_b[["B-limit-ocr"]] <- "text_year_ge_1915"
b_bound("B-under-ocr", "; f. l9l4");          expect_b[["B-under-ocr"]] <- character(0)
b_bound("B-ocr-B", "; f. I9lB");             expect_b[["B-ocr-B"]] <- "text_year_ge_1915"   # B -> 8: 1918
b_bound("B-ocr-S", "; f. l9lS");             expect_b[["B-ocr-S"]] <- "text_year_ge_1915"   # S -> 5: 1915
b_bound("B-ocr-o", "; f. I9o5");             expect_b[["B-ocr-o"]] <- character(0)          # o -> 0: 1905
b_bound("B-19O5", "; f. 19O5");               expect_b[["B-19O5"]] <- character(0)          # 19O5 -> 1905
b_bound("B-s1923", "; se s. 1923");           expect_b[["B-s1923"]] <- "text_year_ge_1915"  # sidehenvisning tæller
b_bound("B-l923", "; f. l923");               expect_b[["B-l923"]] <- "text_year_ge_1915"   # l923 -> 1923
b_bound("B-I92O", "; f. I92O");               expect_b[["B-I92O"]] <- "text_year_ge_1915"   # kun den tolerante læsning
b_bound("B-glued", "; Kbh1950erne");          expect_b[["B-glued"]] <- "text_year_ge_1915"  # klistret til et ord
# 3. Hovedpersonen (fail-closed: NULL tæller).
b_bound("B-lev", levende = TRUE);             expect_b[["B-lev"]] <- "principal_living"
b_bound("B-levnull", levende = NA);           expect_b[["B-levnull"]] <- "principal_living"
b_bound("B-priv", privat = TRUE);             expect_b[["B-priv"]] <- "principal_living"
b_bound("B-privnull", privat = NA);           expect_b[["B-privnull"]] <- "principal_living"
b_bound("B-staged", staged = TRUE);           expect_b[["B-staged"]] <- "principal_living"
# 4. samme_som-partnere, begge retninger.
# Partneren selv er ikke en »anden« slægtning (regel 3): kun same_as_partner_living, selv om den har en family.
x <- b_bound("B-same-fwd"); q_fwd <- new_person(levende = TRUE); samme_som(x$person, q_fwd)
new_family(list(list(q_fwd, "partner"), list(new_person(), "partner")))
expect_b[["B-same-fwd"]] <- "same_as_partner_living"
x <- b_bound("B-same-rev"); samme_som(new_person(privat = TRUE), x$person)
expect_b[["B-same-rev"]] <- "same_as_partner_living"
# Hele samme_som-gruppen: A (hovedpersonen) -> B <- C; kun C (to led væk) er levende.
x <- b_bound("B-same-group"); b_mid <- new_person(); samme_som(x$person, b_mid); samme_som(new_person(levende = TRUE), b_mid)
expect_b[["B-same-group"]] <- "same_as_partner_living"
# ... og en slægtning til C (to led væk) tæller under regel 3.
x <- b_bound("B-rel-group"); b_mid <- new_person(); c_far <- new_person(); samme_som(x$person, b_mid); samme_som(c_far, b_mid)
new_family(list(list(c_far, "partner"), list(new_person(levende = TRUE), "barn")))
expect_b[["B-rel-group"]] <- "relative_living"
# 5. Slægtninge: direkte, og gennem samme_som-partnerens family (NULL tæller).
x <- b_bound("B-rel"); new_family(list(list(x$person, "partner"), list(new_person(levende = TRUE), "barn")))
expect_b[["B-rel"]] <- "relative_living"
x <- b_bound("B-rel-same"); qq <- new_person(); samme_som(qq, x$person)
new_family(list(list(qq, "partner"), list(new_person(levende = NA), "partner")))
expect_b[["B-rel-same"]] <- "relative_living"
x <- b_bound("B-rel-priv"); new_family(list(list(x$person, "partner"), list(new_person(privat = TRUE), "barn")))
expect_b[["B-rel-priv"]] <- character(0)                                                     # regel 3 læser kun levende
# 6. Ingen published binding.
b_bound("B-draft", status = "draft");         expect_b[["B-draft"]] <- "no_published_persona"
b_bound("B-withdrawn", status = "withdrawn"); expect_b[["B-withdrawn"]] <- "no_published_persona"
b_post("B-nobind");                           expect_b[["B-nobind"]] <- "no_published_persona"
b_post("B-nopersona", primary = FALSE);       expect_b[["B-nopersona"]] <- "no_published_persona"
b_post("B-nobind-year", "; f. 1950");         expect_b[["B-nobind-year"]] <- c("no_published_persona", "text_year_ge_1915")
new_record(sb, "B-nohelpost", list(list(key = "x", from = 0L, kind = "structural_context", text = hp("B-nohelpost"), helpost = FALSE)))
expect_b[["B-nohelpost"]] <- "no_published_persona"
new_record(sb, "B-noanchor", list());         expect_b[["B-noanchor"]] <- "no_published_persona"
# 7. Alle årsager bæres med.
x <- b_bound("B-multi", "; f. 1950", levende = TRUE)
samme_som(new_person(levende = TRUE), x$person)
new_family(list(list(x$person, "partner"), list(new_person(levende = TRUE), "barn")))
expect_b[["B-multi"]] <- c("principal_living", "same_as_partner_living", "relative_living", "text_year_ge_1915")

rb <- eligibility(sb$id, "exclusion-1939-v1", P39, "b")
if (rb$status != 0L) stop("eksport B fejlede: ", substr(rb$out, 1L, 300L))
lb <- ledger_of(rb)
stopifnot(identical(lb$policy_version, "exclusion-1939-v1"), nchar(lb$rules_script_sha256) == 64L)
n_records <- q("SELECT count(*)::int n FROM private.source_record WHERE source_id=$1", list(sb$id))$n[[1L]]
if (length(lb$records) != n_records || anyDuplicated(names(lb$records))) stop("ledgeren har ikke præcis én række pr. record")
stopifnot(identical(sort(names(lb$records)), sort(names(expect_b))))
for (k in names(expect_b)) {
  got <- unlist(lb$records[[k]]$reasons) %||% character(0)
  if (!identical(got, expect_b[[k]])) stop("B ", k, ": årsager ", paste(got, collapse = ","), " != ", paste(expect_b[[k]], collapse = ","))
  want_status <- if (length(expect_b[[k]])) "excluded" else "eligible"
  if (!identical(lb$records[[k]]$status, want_status)) stop("B ", k, ": status ", lb$records[[k]]$status)
}
for (k in c("B-nohelpost", "B-noanchor")) stopifnot(identical(lb$records[[k]]$record_input_sha256, ZERO))
cat("B:", grep("pr. regel", strsplit(rb$out, "\n", fixed = TRUE)[[1L]], value = TRUE), "\n")
stopifnot(grepl("ELIGIBILITY_LEDGER_OK records=", rb$out, fixed = TRUE),
  grepl("text_strict=", rb$out, fixed = TRUE), grepl("text_tolerant=", rb$out, fixed = TRUE))

# Samme helpost og samme tekst som runner-inputtet (helpost-reglen, Task 4), også for posten med flere forankringer.
ri_dir <- file.path(work_dir, "b-runner"); dir.create(ri_dir, mode = "0700")
ri <- run("Rscript", c(shQuote(file.path(scripts_dir, "export_43b_runner_input.R")), "--source-id", sb$id,
  "--writer-profile", P39, "--output-dir", shQuote(ri_dir)))
if (ri$status != 0L) stop("runner-input B fejlede: ", substr(ri$out, 1L, 300L))
runner <- jsonlite::fromJSON(file.path(ri_dir, "runner-input-v1.json"), simplifyVector = FALSE)$records
stopifnot("B-ok" %in% names(runner), identical(runner[["B-ok"]]$post_verbatim_text, hp("B-ok")))
for (k in names(runner))
  if (!identical(lb$records[[k]]$record_input_sha256, sha_text(runner[[k]]$post_verbatim_text)))
    stop("B ", k, ": ledgerens input_sha er ikke runner-inputtets")
stopifnot(identical(sort(setdiff(names(lb$records), names(runner))), sort(c("B-nohelpost", "B-noanchor"))))

# ==== C: fejlkoder =====================================================================================
expect_fail(eligibility(sb$id, "exclusion-1939-v2", P39, "c-policy"), "EXPORT_POLICY_UNKNOWN")
expect_fail(eligibility(sb$id, "", P39, "c-policy-empty"), "EXPORT_CLI_INVALID")
expect_fail(eligibility(sb$id, NULL, P39, "c-policy-missing"), "EXPORT_CLI_INVALID")
expect_fail(eligibility(sb$id, "exclusion-1939-v1", NULL, "c-profile-missing"), "EXPORT_CLI_INVALID")
expect_fail(eligibility(sb$id, "exclusion-1939-v1", "findes-ikke", "c-profile"), "EXPORT_WRITER_PROFILE_UNKNOWN")
# Politikken er bundet til profilens udgave: en anden udgaves politik, eller en profil uden udgave, afvises.
expect_fail(eligibility(sb$id, "exclusion-2018-20-v1", P39, "c-other-policy"), "EXPORT_POLICY_EDITION_MISMATCH")
expect_fail(eligibility(sa$id, "exclusion-1939-v1", P18, "c-other-policy-18"), "EXPORT_POLICY_EDITION_MISMATCH")
for (ed in list(NULL, "syntetisk")) {
  sx <- new_source("p", "person", ed)
  b <- new_record(sx, "I-1", list(list(key = "h", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE)))
  expect_fail(eligibility(sx$id, "exclusion-1939-v1", "p", paste0("c-edition-", ed %||% "none")), "EXPORT_POLICY_EDITION_MISMATCH")
}

fail_source <- function(tag, build, code) {
  s <- new_source("p", "person", "1939")
  build(s)
  expect_fail(eligibility(s$id, "exclusion-1939-v1", "p", tag), code)
}
fail_source("c-ambiguous", function(s) new_record(s, "I-1", list(
  list(key = "h1", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE),
  list(key = "h2", from = 200L, kind = "person", text = hp("I-1"), helpost = TRUE))), "EXPORT_HELPOST_NOT_UNIQUE")
fail_source("c-outside", function(s) new_record(s, "I-1", list(
  list(key = "h", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE),
  list(key = "x", from = 500L, kind = "name", text = "Alfa Bravo", helpost = FALSE))), "EXPORT_HELPOST_NOT_UNIQUE")
# To primære personas på helposten: ingen entydig hovedperson -> udelukket (ikke en fejl i ledgeren).
sc <- new_source("p", "person", "1939")
two <- new_record(sc, "I-1", list(list(key = "h", from = 0L, kind = "person", text = hp("I-1"), helpost = TRUE)),
  primary = list(list(on = "h", persona = "1939:I-1"), list(on = "h", persona = "1939:I-1-b")))
publish(sc, two, new_person())
rc <- eligibility(sc$id, "exclusion-1939-v1", "p", "c-two")
stopifnot(rc$status == 0L, identical(unlist(ledger_of(rc)$records[["I-1"]]$reasons), "no_published_persona"))

cat("TEST_EXPORT_MODEL_ELIGIBILITY_1939_OK\n")
