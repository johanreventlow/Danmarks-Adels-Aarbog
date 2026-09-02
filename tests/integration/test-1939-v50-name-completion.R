script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), "../.."))
source(file.path(root, ".claude/skills/daa-extract/scripts/apply_name_completion_1939_v50_helpers.R"))

actor <- "11111111-1111-4111-8111-111111111111"
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)
source_batch <- "560c39f8-5c87-4c0d-a768-025d97fa2974"
source_auth <- "560c39f8-5c87-4c0d-a768-025d97fa2973"
source_run <- "560c39f8-5c87-4c0d-a768-025d97fa2972"
manifest_sha <- paste(rep("1", 64L), collapse = "")
sha <- function(letter) paste(rep(letter, 64L), collapse = "")
source_preview_sha <- name_completion_source_manifest_bytes_sha256
profile_id <- "daa-1939-v50-production-write-v1"
profile_sha <- sha("a")

connect <- function(statement_timeout = NULL) {
  con <- DBI::dbConnect(RPostgres::Postgres(), dbname = Sys.getenv("PGDATABASE"),
    host = Sys.getenv("PGHOST", "localhost"), port = Sys.getenv("PGPORT", "5432"),
    user = Sys.getenv("PGUSER", "postgres"), password = Sys.getenv("PGPASSWORD"))
  DBI::dbGetQuery(con, "SELECT set_config('request.jwt.claim.sub',$1,false)", params = list(actor))
  if (!is.null(statement_timeout))
    DBI::dbExecute(con, paste0("SET statement_timeout = '", as.integer(statement_timeout), "ms'"))
  con
}

query <- function(con, sql, params = list()) {
  if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
}

locked_rows <- list(
  list("record-3766faae-ae21-412a-8cfb-745a19ac77f0", 1846L, "Ditlev", 503L),
  list("record-43d4974a-0532-421d-a3fb-8e7c575a67e7", 1847L, "Gerhard (Gherardus de Reventlow)", 506L),
  list("record-80180a6e-2cc6-4968-81ca-004b6662d8ce", 1848L, "Henning", 506L),
  list("record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422", 1849L, "Henning Reventlow", 508L),
  list("record-8f346104-cf3c-465f-bfa3-efb78be436b2", 1850L, "Iven (Ywanus de Reuentlo)", 506L),
  list("record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58", 1851L, "Henning", 508L),
  list("record-b626f5ff-f2fb-4061-bfce-988dbddec846", 1852L, "Henrik", 506L),
  list("record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d", 1853L, "Margrethe", 517L)
)

build_fixture <- function() {
  source_payloads <- vector("list", length(locked_rows))
  operations <- lapply(seq_along(locked_rows), function(index) {
    row <- locked_rows[[index]]
    persona <- sprintf("00000000-0000-4000-8000-%012d", index)
    text <- paste0(row[[3L]], " source text")
    source_payload <- list(
      source_record_key = row[[1L]], source_id = 3L, edition = "1939",
      source_persona_id = persona,
      source_span = list(char_from = as.integer(index), char_to = as.integer(index + 10L)),
      page_evidence = list(page_from = row[[4L]], page_to = row[[4L]]),
      verbatim_text = text,
      verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
      staged = TRUE, name = row[[3L]], facts = list(), relations = list(), families = list()
    )
    source_payloads[[index]] <<- source_payload
    list(
      element_id = paste0("name-completion:", row[[1L]]),
      source_batch_id = source_batch,
      source_person_create_element_id = paste0("person-create:", row[[1L]]),
      person_id = row[[2L]], source_id = 3L, edition = "1939",
      source_record_key = row[[1L]], source_persona_id = persona, name = row[[3L]],
      source_span = source_payload$source_span, page_evidence = source_payload$page_evidence,
      verbatim_text = text, verbatim_sha256 = source_payload$verbatim_sha256,
      source_payload_sha256 = canonical_name_completion_sha256(source_payload),
      expected_before = list(staged = TRUE, name_cache_empty = TRUE, name_facts = 0L),
      expected_after = list(name_fact = 1L, selected_assertion = 1L,
        daa_1939_citation = 1L, conclusion = 1L)
    )
  })
  manifest <- list(
    schema_version = "1939-v50-name-completion-manifest-v1", generator_version = "integration-fixture",
    input_hashes = list(
      production_manifest_sha256 = name_completion_source_manifest_bytes_sha256,
      production_apply_sha256 = sha("b"), post_apply_audit_sha256 = sha("c")
    ),
    source = list(edition = "1939", source_id = 3L), source_batch_id = source_batch,
    source_manifest_bytes_sha256 = name_completion_source_manifest_bytes_sha256,
    source_manifest_content_sha256 = name_completion_source_manifest_content_sha256,
    operations = operations, counts = list(name_completions = 8L, operations = 8L),
    expected_changes = list(facts_created = 8L, assertions_created = 8L,
      citations_created = 8L, conclusions_created = 8L, persons_created = 0L,
      persons_activated = 0L, relations_changed = 0L, families_changed = 0L),
    production_authorized = FALSE, cutover_authorized = FALSE
  )
  manifest$manifest_content_sha256 <- canonical_name_completion_sha256(manifest)
  list(manifest = manifest, source_payloads = source_payloads)
}

fixture <- build_fixture()
manifest <- fixture$manifest
payloads <- authorized_name_payloads(manifest)
expected_names <- vapply(locked_rows, function(row) row[[3L]], character(1))

con <- connect()
on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
DBI::dbBegin(con)
DBI::dbExecute(con, "INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES($1,3,'name-completion-r-integration','fixture','fixture','fixture',$2,'{}')",
  params = list(source_run, sha("a")))
DBI::dbExecute(con, "INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES(3,$1,'fixture-v2',$2,$3::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  params = list(profile_id, profile_sha, '{\"run_key_prefix\":\"reimport-1939-v50:\",\"schema_version\":\"1939-v50-production-write-manifest-v1\",\"extractor_version\":\"production-writer-v1\",\"rendition_key\":\"daa-1939-calamari-r6-clean\",\"rendition_kind\":\"ocr_text\",\"rendition_metadata\":{\"edition\":\"1939\"},\"observation_extraction_method\":\"fixture\",\"citation_label_template\":\"DAA 1939 side {page_from}\"}'))
source_counts <- jsonlite::toJSON(list(person_creates = 8L, source_evidence = 0L), auto_unbox = TRUE)
DBI::dbExecute(con, "INSERT INTO private.reimport_authorization(id,operation,manifest_sha256,preview_sha256,database_identity,source_id,profile_id,profile_sha256,expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at) VALUES($1,'reimport',$2,$3,current_database(),3,$4,$5,$6::jsonb,'{}',$7,gen_random_uuid(),clock_timestamp()+interval '1 hour','consumed',clock_timestamp())",
  params = list(source_auth, name_completion_source_manifest_content_sha256,
    source_preview_sha,
    profile_id, profile_sha, source_counts, actor))
DBI::dbExecute(con, "INSERT INTO private.reimport_batch(id,authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,status,expected_counts,observed_counts,finalized_at) VALUES($1,$2,$3,$4,3,$5,$6,$7,'finalized',$8::jsonb,$8::jsonb,clock_timestamp())",
  params = list(source_batch, source_auth, name_completion_source_manifest_content_sha256,
    source_preview_sha, profile_id, profile_sha, actor, source_counts))

for (index in seq_along(locked_rows)) {
  row <- locked_rows[[index]]
  persona <- manifest$operations[[index]]$source_persona_id
  record_id <- sprintf("10000000-0000-4000-8000-%012d", index)
  DBI::dbExecute(con, "INSERT INTO public.person(id,staged) VALUES($1,true)", params = list(row[[2L]]))
  DBI::dbExecute(con, "INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES($1,3,$2,'person',$3)", params = list(record_id, row[[1L]], source_run))
  DBI::dbExecute(con, "INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES($1,3,$2,$3)", params = list(persona, paste0("1939:", row[[1L]]), source_run))
  DBI::dbExecute(con, "INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) VALUES($1,$2,'accepted',1,'{\"fixture\":true}',$3,'Writer CI',clock_timestamp())",
    params = list(persona, row[[2L]], actor))
  DBI::dbExecute(con, "INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at FROM private.source_persona_identity WHERE source_persona_id=$1",
    params = list(persona))
  event_payload <- fixture$source_payloads[[index]]
  event_payload$authorized_payload_sha256 <- manifest$operations[[index]]$source_payload_sha256
  DBI::dbExecute(con, "INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256) VALUES($1,$2,'person_create',$3,$4,$5::jsonb,$6)",
    params = list(source_batch, paste0("person-create:", row[[1L]]), row[[1L]], row[[2L]],
      jsonlite::toJSON(event_payload, auto_unbox = TRUE, null = "null"), sha("d")))
}
DBI::dbCommit(con)

protected_counts <- function(connection) query(connection, paste(
  "SELECT (SELECT count(*) FROM public.fact) facts,",
  "(SELECT count(*) FROM public.assertion) assertions,",
  "(SELECT count(*) FROM public.citation) citations,",
  "(SELECT count(*) FROM public.conclusion) conclusions,",
  "(SELECT count(*) FROM private.reimport_1939_name_completion_result) results,",
  "(SELECT count(*) FROM private.reimport_1939_write_event WHERE operation='canonical_delta') completion_events,",
  "(SELECT count(*) FROM private.reimport_1939_authorization WHERE operation='name_completion') completion_authorizations,",
  "(SELECT count(*) FROM private.reimport_1939_write_batch WHERE authorization_id IN",
  " (SELECT id FROM private.reimport_1939_authorization WHERE operation='name_completion')) completion_batches"
))

gateway <- function(timeout = NULL) new_name_completion_dbi_gateway(function() connect(timeout))
before <- protected_counts(con)

cli_manifest <- tempfile("name-completion-cli-manifest-", fileext = ".json")
cli_outputs <- tempfile(c("name-completion-cli-missing-", "name-completion-cli-wrong-",
  "name-completion-cli-correct-"), fileext = ".json")
on.exit(unlink(c(cli_manifest, cli_outputs)), add = TRUE)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
  cli_manifest, useBytes = TRUE)
cli_manifest_sha <- digest::digest(file = cli_manifest, algo = "sha256", serialize = FALSE)
cli_script <- file.path(root, ".claude/skills/daa-extract/scripts/apply_name_completion_1939_v50.R")
run_cli <- function(actor_value, output) suppressWarnings(system2("Rscript", c(cli_script,
  "--manifest", cli_manifest, "--manifest-sha256", cli_manifest_sha,
  "--mode", "dry-run", "--output", output),
  env = paste0("DAA_REIMPORT_ACTOR_ID=", actor_value), stdout = TRUE, stderr = TRUE))

missing_actor <- run_cli("", cli_outputs[[1L]])
stopifnot(identical(as.integer(attr(missing_actor, "status")), 1L),
  any(grepl("NAME_COMPLETION_1939_ACTOR_REQUIRED", missing_actor, fixed = TRUE)),
  !file.exists(cli_outputs[[1L]]), identical(protected_counts(con), before))
wrong_actor <- run_cli("22222222-2222-4222-8222-222222222222", cli_outputs[[2L]])
stopifnot(identical(as.integer(attr(wrong_actor, "status")), 1L),
  any(grepl("REIMPORT_WRITER_ROLE_FORBIDDEN", wrong_actor, fixed = TRUE)),
  !file.exists(cli_outputs[[2L]]), identical(protected_counts(con), before))
correct_actor <- run_cli(actor, cli_outputs[[3L]])
stopifnot(is.null(attr(correct_actor, "status")), file.exists(cli_outputs[[3L]]),
  identical(protected_counts(con), before))
cli_result <- jsonlite::fromJSON(cli_outputs[[3L]], simplifyVector = FALSE)
stopifnot(identical(cli_result$mode, "dry-run"), identical(cli_result$committed, FALSE),
  length(cli_result$result_map) == 8L)

DBI::dbDisconnect(con); con <- NULL
dry <- execute_name_completion(manifest, manifest_sha, "dry-run", gateway())
stopifnot(!dry$committed)
con <- connect(); stopifnot(identical(protected_counts(con), before))

for (failure_index in seq_len(8L)) {
  real <- gateway(); seen <- 0L
  injected <- list(call = function(name, ...) {
    value <- real$call(name, ...)
    if (identical(name, "name_completion")) {
      seen <<- seen + 1L
      if (seen == failure_index) stop(paste0("INJECT_AFTER_ELEMENT_", failure_index), call. = FALSE)
    }
    value
  })
  failed <- try(execute_name_completion(manifest, manifest_sha, "dry-run", injected), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(protected_counts(con), before))
}
real <- gateway()
injected <- list(call = function(name, ...) {
  value <- real$call(name, ...)
  if (identical(name, "finalize")) stop("INJECT_AFTER_FINALIZE", call. = FALSE)
  value
})
failed <- try(execute_name_completion(manifest, manifest_sha, "dry-run", injected), silent = TRUE)
stopifnot(inherits(failed, "try-error"), identical(protected_counts(con), before))

holder <- connect(); DBI::dbBegin(holder)
DBI::dbExecute(holder, "LOCK TABLE public.fact IN SHARE ROW EXCLUSIVE MODE")
blocked <- try(execute_name_completion(manifest, manifest_sha, "dry-run", gateway(250L)), silent = TRUE)
DBI::dbRollback(holder); DBI::dbDisconnect(holder)
stopifnot(inherits(blocked, "try-error"), grepl("statement timeout", as.character(blocked), fixed = TRUE),
  identical(protected_counts(con), before))

generic_manifest <- as_generic_name_completion_manifest(manifest)
generic_payloads <- jsonlite::toJSON(name_completion_payloads(generic_manifest), auto_unbox = TRUE, null = "null")
authorization <- jsonlite::fromJSON(query(con,
  "SELECT public.red_authorize_reimport_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)::text value",
  list(manifest_sha, source_batch, name_completion_source_manifest_bytes_sha256,
    name_completion_source_manifest_content_sha256,
    jsonlite::toJSON(generic_manifest$expected_counts, auto_unbox = TRUE),
    generic_payloads))$value[[1L]], simplifyVector = FALSE)
DBI::dbDisconnect(con); con <- NULL
applied <- execute_name_completion(manifest, manifest_sha, "apply", gateway(), authorization)
stopifnot(applied$committed, length(applied$result_map) == 8L)

con <- connect()
names_after <- query(con, "SELECT id,visning_navn,staged FROM public.person WHERE id BETWEEN 1846 AND 1853 ORDER BY id")
stopifnot(identical(names_after$visning_navn, expected_names), all(names_after$staged))
completion <- query(con, "SELECT (SELECT count(*) FROM private.reimport_1939_name_completion_result) results,(SELECT count(*) FROM private.reimport_1939_write_event WHERE operation='canonical_delta') events")
stopifnot(completion$results[[1L]] == 8, completion$events[[1L]] == 8)

replay_authorization <- try(query(con,
  "SELECT public.red_authorize_reimport_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)::text value",
  list(manifest_sha, source_batch, name_completion_source_manifest_bytes_sha256,
    name_completion_source_manifest_content_sha256,
    jsonlite::toJSON(generic_manifest$expected_counts, auto_unbox = TRUE),
    generic_payloads)), silent = TRUE)
stopifnot(inherits(replay_authorization, "try-error"), grepl("REIMPORT_NAME_COMPLETION_INVALID",
  as.character(replay_authorization), fixed = TRUE))

for (role in c("anon", "authenticated")) {
  DBI::dbExecute(con, paste("SET ROLE", role))
  private_read <- try(DBI::dbGetQuery(con, "SELECT count(*) FROM private.reimport_1939_name_completion_result"), silent = TRUE)
  DBI::dbExecute(con, "RESET ROLE")
  stopifnot(inherits(private_read, "try-error"), grepl("permission denied", as.character(private_read), fixed = TRUE))
}
DBI::dbExecute(con, "SET ROLE authenticated")
self_authorize <- try(query(con,
  "SELECT public.red_authorize_1939_v50_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)",
  list(manifest_sha, source_batch, name_completion_source_manifest_bytes_sha256,
    name_completion_source_manifest_content_sha256,
    jsonlite::toJSON(manifest$counts, auto_unbox = TRUE),
    jsonlite::toJSON(payloads, auto_unbox = TRUE, null = "null"))), silent = TRUE)
DBI::dbExecute(con, "RESET ROLE")
stopifnot(inherits(self_authorize, "try-error"),
  grepl("permission denied for function red_authorize_1939_v50_name_completion",
    as.character(self_authorize), fixed = TRUE))

completion_batch <- query(con, "SELECT id FROM private.reimport_1939_write_batch WHERE manifest_sha256=$1 AND status='finalized'", list(manifest_sha))$id[[1L]]
reversal_auth <- query(con, "SELECT public.red_authorize_1939_v50_reversal($1,gen_random_uuid(),clock_timestamp()+interval '5 minutes') id", list(source_batch))$id[[1L]]
reversed <- try(query(con, "SELECT public.red_reverse_1939_v50_reimport($1,$2)::text value", list(source_batch, reversal_auth)), silent = TRUE)
stopifnot(inherits(reversed, "try-error"), grepl("REIMPORT_1939_REVERSAL_INVALID",
  as.character(reversed), fixed = TRUE))
after_reversal <- query(con, "SELECT id,visning_navn,staged,status FROM public.person WHERE id BETWEEN 1846 AND 1853 ORDER BY id")
stopifnot(identical(after_reversal$visning_navn, expected_names), all(after_reversal$staged),
  all(is.na(after_reversal$status)))
stopifnot(query(con, "SELECT count(*) n FROM public.fact WHERE subjekt_type='person' AND subjekt_id BETWEEN 1846 AND 1853 AND faktatype='navn'")$n[[1L]] == 8)
stopifnot(query(con, "SELECT status FROM private.reimport_1939_write_batch WHERE id=$1", list(completion_batch))$status[[1L]] == "finalized")

DBI::dbDisconnect(con); con <- NULL
cat("PASS DAA 1939 v50 name completion PostgreSQL integration\n")
