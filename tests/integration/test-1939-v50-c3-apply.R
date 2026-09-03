## Task 9 integration contract for C3 apply/reversal.
required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg <- setNames(lapply(required_pg, function(key) {
  Sys.getenv(key, unset = NA_character_)
}), required_pg)
if (any(vapply(pg, function(value) {
  length(value) != 1L || is.na(value)
}, logical(1)))) {
  stop("C3_APPLY_INTEGRATION_REQUIRES_ALL_FIVE_PG_VARIABLES", call. = FALSE)
}
if (!grepl("^daa1939_c3_task9_", pg$PGDATABASE)) {
  stop("C3_APPLY_INTEGRATION_REQUIRES_NAMED_DISPOSABLE_DATABASE",
       call. = FALSE)
}

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
root <- normalizePath(file.path(
  dirname(sub("^--file=", "", script_arg)), "../.."))
source(file.path(
  root, ".claude/skills/daa-extract/scripts/c3_export_shared_1939_v50_helpers.R"))
source(file.path(
  root, ".claude/skills/daa-extract/scripts/apply_c3_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, token) {
  if (!isTRUE(value)) stop(token, call. = FALSE)
  ok <<- ok + 1L
  invisible(TRUE)
}
expect_token <- function(expr, token) {
  observed <- tryCatch({ force(expr); "" }, error = conditionMessage)
  expect(identical(observed, token), paste0(
    "C3_APPLY_INTEGRATION_ERROR_MISMATCH:", token, ":", observed))
}
without_open_result_warning <- function(expr) withCallingHandlers(
  force(expr), warning = function(warning) {
    if (identical(conditionMessage(warning),
                  "Closing open result set, cancelling previous query")) {
      invokeRestart("muffleWarning")
    }
  })
try_cleanup <- function(expr) without_open_result_warning(
  try(force(expr), silent = TRUE))
sha_raw <- function(raw) digest::digest(raw, algo = "sha256", serialize = FALSE)
sha_text <- function(text) sha_raw(charToRaw(enc2utf8(text)))
raw_of <- function(value) charToRaw(enc2utf8(as.character(jsonlite::toJSON(
  value, auto_unbox = TRUE, null = "null", digits = NA))))
uuid <- function(tail) paste0("19390000-0000-4c39-8000-00000000", tail)

connect <- function() DBI::dbConnect(
  RPostgres::Postgres(), dbname = pg$PGDATABASE, host = pg$PGHOST,
  port = as.integer(pg$PGPORT), user = pg$PGUSER, password = pg$PGPASSWORD,
  bigint = "integer")
close_connection <- function(connection) invisible(
  try_cleanup(DBI::dbDisconnect(connection)))
query <- function(connection, sql, params = list()) {
  if (length(params)) DBI::dbGetQuery(connection, sql, params = params)
  else DBI::dbGetQuery(connection, sql)
}
execute <- function(connection, sql, params = list()) {
  invisible(if (length(params)) DBI::dbExecute(connection, sql, params = params)
            else DBI::dbExecute(connection, sql))
}
with_connection <- function(callback) {
  connection <- connect()
  on.exit(close_connection(connection), add = TRUE)
  callback(connection)
}

actor <- uuid("a001")
source_id <- 3L
run_id <- uuid("a010")
rendition_id <- uuid("a011")
person_ids <- 1939101:1939110
record_ids <- vapply(1:6, function(index) uuid(sprintf("a1%02d", index)),
                     character(1))
occurrence_ids <- vapply(1:6, function(index) uuid(sprintf("a2%02d", index)),
                         character(1))
narrative_ids <- c(1939201L, 1939202L, 1939203L, 1939205L)
spare_narrative_id <- 1939299L
case_ids <- paste0("T9CASE", 1:5)
assign_indices <- c(1L, 2L, 3L, 5L)
source_texts <- paste("SYNTHETIC TASK9 SOURCE", 1:6)
normalized_texts <- paste("SYNTHETIC TASK9 NORMALIZED", 1:6)
display_names <- paste("SYNTHETIC TASK9 PERSON", person_ids)

## The test owns a fixed namespace inside an explicitly named disposable DB.
## Refuse reuse instead of deleting potentially unrelated rows.
with_connection(function(connection) {
  actual <- query(connection,
                  "SELECT current_database() database_name, (pg_control_system()).system_identifier::text system_identifier")
  expect(identical(actual$database_name[[1L]], pg$PGDATABASE),
         "C3_APPLY_INTEGRATION_DATABASE_IDENTITY_MISMATCH")
  occupied <- query(connection, paste(
    "SELECT (EXISTS(SELECT 1 FROM auth.users WHERE id=$1::uuid)",
    "OR EXISTS(SELECT 1 FROM public.person WHERE id=$2::bigint)",
    "OR EXISTS(SELECT 1 FROM private.source_record WHERE id=$3::uuid)) occupied"),
    list(actor, person_ids[[1L]], record_ids[[1L]]))$occupied[[1L]]
  expect(!isTRUE(occupied), "C3_APPLY_INTEGRATION_FIXTURE_ALREADY_EXISTS")
})

## -------------------------------------------------------------------------
## Synthetic five-case fixture: the real phase shape is 5/5/4/2.
## -------------------------------------------------------------------------
with_connection(function(connection) {
  DBI::dbBegin(connection)
  committed <- FALSE
  on.exit(if (!committed) try_cleanup(DBI::dbRollback(connection)),
          add = TRUE)
  execute(connection,
          "INSERT INTO auth.users(id,email) VALUES($1,'c3-task9@test.invalid')",
          list(actor))
  execute(connection, paste(
    "INSERT INTO public.profiles(id,email,rolle)",
    "VALUES($1,'c3-task9@test.invalid','redaktion')"), list(actor))
  execute(connection, paste(
    "INSERT INTO public.source(id,slags,titel,udgave,aar)",
    "VALUES($1,'DAA-udgave','DAA 1939 Task 9 fixture','1939',1939)"),
    list(source_id))
  execute(connection, paste(
    "INSERT INTO private.extraction_run(",
    "id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)",
    "VALUES($1,$2,'c3-task9','1','synthetic','synthetic',repeat('a',64),'{}')"),
    list(run_id, source_id))
  execute(connection, paste(
    "INSERT INTO private.source_rendition(",
    "id,source_id,rendition_key,rendition_kind,content_sha256)",
    "VALUES($1,$2,'c3-task9-rendition','ocr_text',repeat('b',64))"),
    list(rendition_id, source_id))
  for (index in seq_along(person_ids)) {
    execute(connection, paste(
      "INSERT INTO public.person(id,levende,privat,staged,visning_navn)",
      "VALUES($1,false,false,false,$2)"),
      list(person_ids[[index]], display_names[[index]]))
  }
  for (index in 1:6) {
    execute(connection, paste(
      "INSERT INTO private.source_record(",
      "id,source_id,record_key,record_kind,created_run_id)",
      "VALUES($1,$2,$3,'person_entry',$4)"),
      list(record_ids[[index]], source_id, paste0("t9-record-", index), run_id))
    execute(connection, paste(
      "INSERT INTO private.source_record_occurrence(",
      "id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,",
      "verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)",
      "VALUES($1,$2,$3,$4,$4,$5,$6,$7,$8,$9,$10)"),
      list(occurrence_ids[[index]], rendition_id, paste0("t9-occurrence-", index),
           500L + index, index * 100L, index * 100L + 50L,
           source_texts[[index]], paste0("t9-pf-", index),
           paste0("t9-sf-", index), run_id))
    execute(connection, paste(
      "INSERT INTO private.source_record_anchor_event(",
      "occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)",
      "VALUES($1,$2,'accepted','{\"fixture\":true}'::jsonb,1,$3,'Task 9')"),
      list(occurrence_ids[[index]], record_ids[[index]], actor))
  }
  for (offset in seq_along(assign_indices)) {
    index <- assign_indices[[offset]]
    execute(connection, paste(
      "INSERT INTO public.narrative(",
      "id,subjekt_type,subjekt_id,source_id,tekst,side,privat)",
      "VALUES($1,'person',$2,$3,$4,$5,false)"),
      list(narrative_ids[[offset]], person_ids[[2L * index - 1L]], source_id,
           paste("SYNTHETIC TASK9 OLD", index), as.character(500L + index)))
  }
  execute(connection, paste(
    "INSERT INTO public.narrative(",
    "id,subjekt_type,subjekt_id,source_id,tekst,side,privat)",
    "VALUES($1,'person',$2,$3,'SYNTHETIC TASK9 SPARE','599',false)"),
    list(spare_narrative_id, person_ids[[10L]], source_id))
  DBI::dbCommit(connection)
  committed <- TRUE
})

selection_cases <- lapply(1:5, function(case_index) {
  record_indices <- if (case_index == 4L) 4L else case_index
  if (case_index == 5L) record_indices <- c(5L, 6L)
  records <- lapply(record_indices, function(record_index) {
    action <- if (record_index %in% assign_indices) "assign" else "no_publication"
    result <- list(
      rid = sprintf("T9R%02d", record_index),
      record_key = paste0("t9-record-", record_index), action = action)
    if (identical(action, "assign")) {
      result$target_person_id <- person_ids[[2L * record_index - 1L]]
      result$raw_sha256 <- sha_text(source_texts[[record_index]])
      result$normalized_sha256 <- sha_text(normalized_texts[[record_index]])
    }
    result
  })
  list(case_id = case_ids[[case_index]],
       identity_pair = list(person_ids = c(
         person_ids[[2L * case_index - 1L]], person_ids[[2L * case_index]])),
       records = records)
})
selection <- list(schema_version = "1939-v50-c3-apply-selection-v1",
                  cases = selection_cases)
selection_json <- .c3_apply_json(selection)

set_actor <- function(connection) {
  query(connection,
        "SELECT set_config('request.jwt.claim.sub',$1,true) jwt_subject",
        list(actor))
  invisible(NULL)
}
preview_text <- function() with_connection(function(connection) {
  DBI::dbBegin(connection)
  on.exit(try_cleanup(DBI::dbRollback(connection)), add = TRUE)
  set_actor(connection)
  result <- query(connection, paste(
    "SELECT public.red_preview_reimport_cases(",
    "$1::bigint,'c3',$2::jsonb)::text result"),
    list(source_id, selection_json))$result[[1L]]
  DBI::dbRollback(connection)
  result
})

initial_preview_text <- preview_text()
preview <- jsonlite::fromJSON(initial_preview_text, simplifyVector = FALSE)
database_name <- preview$database_name
system_identifier <- preview$system_identifier
expect(identical(database_name, pg$PGDATABASE),
       "C3_APPLY_INTEGRATION_PREVIEW_DATABASE_DRIFT")
expect(length(preview$identity_pairs) == 5L &&
       length(preview$source_records) == 6L &&
       length(preview$target_narratives) == 4L &&
       length(preview$bindings) == 6L,
       "C3_APPLY_INTEGRATION_PREVIEW_SHAPE_DRIFT")

find_row <- function(rows, key, value, token) {
  matched <- Filter(function(row) identical(as.character(row[[key]]),
                                             as.character(value)), rows)
  if (length(matched) != 1L) stop(token, call. = FALSE)
  matched[[1L]]
}
manifest_cases <- lapply(1:5, function(case_index) {
  case_id <- case_ids[[case_index]]
  identity <- find_row(preview$identity_pairs, "case_id", case_id,
                       "C3_APPLY_INTEGRATION_IDENTITY_PREVIEW_JOIN")
  record_indices <- if (case_index == 4L) 4L else case_index
  if (case_index == 5L) record_indices <- c(5L, 6L)
  events <- lapply(record_indices, function(record_index) {
    rid <- sprintf("T9R%02d", record_index)
    record_key <- paste0("t9-record-", record_index)
    source_record <- find_row(preview$source_records, "rid", rid,
                              "C3_APPLY_INTEGRATION_SOURCE_PREVIEW_JOIN")
    binding <- find_row(preview$bindings, "record_key", record_key,
                        "C3_APPLY_INTEGRATION_BINDING_PREVIEW_JOIN")
    before_source <- list(
      match_count = as.integer(source_record$match_count),
      verbatim_sha256 = source_record$verbatim_sha256,
      side = source_record$side)
    before_binding <- list(status = binding$status,
                           binding_person_id = binding$binding_person_id)
    if (record_index %in% assign_indices) {
      target <- find_row(preview$target_narratives, "rid", rid,
                         "C3_APPLY_INTEGRATION_TARGET_PREVIEW_JOIN")
      target_person_id <- person_ids[[2L * record_index - 1L]]
      list(
        element_id = paste0("case:", case_id, ":rid:", rid), rid = rid,
        record_key = record_key, action = "assign",
        after_state = list(
          target_person_id = target_person_id,
          target_display_name = display_names[[2L * record_index - 1L]],
          source_text = source_texts[[record_index]],
          raw_sha256 = sha_text(source_texts[[record_index]]),
          normalized_text = normalized_texts[[record_index]],
          normalized_sha256 = sha_text(normalized_texts[[record_index]]),
          normalization_version = "narrative_norm_v1",
          normalization_flags = list(),
          expected_narrative = list(
            privat = FALSE, side = as.character(500L + record_index),
            record_label = record_key,
            citation_label = paste("DAA 1939 side", 500L + record_index))),
        before_state = list(
          source_record = before_source,
          target_narrative = list(
            person_id = as.integer(target$person_id),
            narrative_id = as.integer(target$narrative_id),
            privat = target$privat, old_sha256 = target$old_sha256),
          binding = before_binding))
    } else {
      list(
        element_id = paste0("case:", case_id, ":rid:", rid), rid = rid,
        record_key = record_key, action = "no_publication",
        after_state = structure(list(), names = character(0)),
        before_state = list(source_record = before_source,
                            binding = before_binding))
    }
  })
  list(
    element_id = paste0("case:", case_id), case_id = case_id,
    after_state = list(action = "different", person_ids = as.integer(
      unlist(identity$person_ids, use.names = FALSE))),
    before_state = list(component_overlap = identity$component_overlap,
                        existing_rejection = identity$existing_rejection),
    events = events)
})

manifest_core <- list(
  schema_version = "1939-v50-c3-apply-manifest-v1",
  input_hashes = list(
    candidate_raw_sha256 = sha_text(selection_json),
    preview_raw_sha256 = sha_text(initial_preview_text),
    candidate_canonical_content_sha256 = sha_text(paste0("candidate:", selection_json)),
    before_state_canonical_sha256 = sha_text(initial_preview_text)),
  database = list(database_name = database_name,
                  system_identifier = system_identifier),
  counts = list(cases = 5L, identity_events = 5L, assign_events = 4L,
                no_publication_events = 2L, events = 11L),
  cases = manifest_cases)
manifest <- manifest_core
manifest$canonical_content_sha256 <- sha_raw(raw_of(manifest_core))
manifest_raw <- raw_of(manifest)
manifest_sha256 <- sha_raw(manifest_raw)
assign_element_ids <- unlist(lapply(manifest_cases, function(case) {
  vapply(Filter(function(event) identical(event$action, "assign"), case$events),
         `[[`, character(1), "element_id")
}), use.names = FALSE)
text_bundle <- lapply(manifest_cases, function(case) lapply(case$events,
  function(event) if (identical(event$action, "assign")) event$after_state else NULL))
approval <- list(
  schema_version = "1939-v50-c3-apply-approvals-decisions-v1",
  approvals_raw_sha256 = sha_text("synthetic-task9-approval-sheet"),
  manifest_raw_sha256 = manifest_sha256,
  manifest_canonical_content_sha256 = manifest$canonical_content_sha256,
  text_bundle_sha256 = sha_raw(raw_of(text_bundle)),
  decisions = lapply(assign_element_ids, function(element_id) list(
    element_id = element_id, status = "approved")),
  counts = list(decisions = 4L, approved = 4L, unresolved = 0L))
approval_raw <- raw_of(approval)
bundle <- build_c3_apply_authorization(manifest_raw, approval_raw)
expect(identical(bundle$hashes$state_sha256, sha_text(initial_preview_text)),
       "C3_APPLY_INTEGRATION_STATE_HASH_DRIFT")

gateway_connect <- function() {
  connection <- connect()
  list(
    query = function(sql, params = NULL) {
      if (is.null(params) || !length(params)) query(connection, sql)
      else query(connection, sql, params)
    },
    execute = function(sql, params = NULL) {
      if (is.null(params) || !length(params)) execute(connection, sql)
      else execute(connection, sql, params)
    },
    close = function() close_connection(connection))
}
options_for <- function(nonce) list(nonce = nonce, actor_id = actor)

domain_snapshot <- function() with_connection(function(connection) {
  person_state <- query(connection, paste(
    "SELECT coalesce(jsonb_agg(jsonb_build_object(",
    "'id',id,'levende',levende,'privat',privat,'staged',staged,'visning_navn',visning_navn)",
    "ORDER BY id),'[]'::jsonb)::text value FROM public.person",
    "WHERE id BETWEEN 1939101 AND 1939110"))$value[[1L]]
  narrative_state <- query(connection, paste(
    "SELECT coalesce(jsonb_agg(jsonb_build_object(",
    "'id',id,'person_id',subjekt_id,'tekst',tekst,'side',side,'privat',privat)",
    "ORDER BY id),'[]'::jsonb)::text value FROM public.narrative",
    "WHERE source_id=3 AND subjekt_type='person'",
    "AND subjekt_id BETWEEN 1939101 AND 1939110"))$value[[1L]]
  relation_state <- query(connection, paste(
    "SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.id),'[]'::jsonb)::text value",
    "FROM public.relation r WHERE r.rolle IN ('samme_som','ikke_samme_som')",
    "AND ((r.subjekt_type='person' AND r.subjekt_id BETWEEN 1939101 AND 1939110)",
    "OR (r.objekt_type='person' AND r.objekt_id BETWEEN 1939101 AND 1939110))"))$value[[1L]]
  binding_state <- query(connection, paste(
    "SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]'::jsonb)::text value",
    "FROM private.narrative_record_publication p",
    "JOIN private.source_record s ON s.id=p.source_record_id",
    "WHERE s.record_key LIKE 't9-record-%'"))$value[[1L]]
  sha_text(paste(person_state, narrative_state, relation_state, binding_state,
                 sep = "\n"))
})
ledger_counts <- function() with_connection(function(connection) query(
  connection, paste(
    "SELECT",
    "(SELECT count(*)::integer FROM private.reimport_case_authorization WHERE source_id=3 AND phase='c3') authorizations,",
    "(SELECT count(*)::integer FROM private.reimport_case_batch WHERE source_id=3 AND phase='c3') batches,",
    "(SELECT count(*)::integer FROM private.reimport_case_event WHERE source_id=3 AND phase='c3') events")))
assert_zero_ledger <- function(token) {
  counts <- ledger_counts()
  expect(counts$authorizations[[1L]] == 0L && counts$batches[[1L]] == 0L &&
         counts$events[[1L]] == 0L, token)
}

initial_domain <- domain_snapshot()
rehearsal <- without_open_result_warning(c3_apply_run(
  "rehearse-rollback", bundle, options_for(uuid("b001")), gateway_connect)
)
expect(identical(rehearsal$outcome, "rehearsed"),
       "C3_APPLY_INTEGRATION_REHEARSAL_FAILED")
expect(identical(domain_snapshot(), initial_domain),
       "C3_APPLY_INTEGRATION_REHEARSAL_DOMAIN_RESIDUE")
assert_zero_ledger("C3_APPLY_INTEGRATION_REHEARSAL_LEDGER_RESIDUE")

## Every case position fails before the first mutation. Moving the same live
## guard through cases 1..5 proves a late failure cannot leave earlier cases.
for (case_index in 1:5) {
  drift_person <- person_ids[[2L * case_index - 1L]]
  with_connection(function(connection) execute(
    connection, "UPDATE public.person SET staged=true WHERE id=$1", list(drift_person)))
  drifted_domain <- domain_snapshot()
  expect_token(without_open_result_warning(c3_apply_run(
    "apply", bundle, options_for(uuid(sprintf("c%03d", case_index))),
    gateway_connect)), "C3_APPLY_PERSON_NOT_PUBLISHABLE")
  expect(identical(domain_snapshot(), drifted_domain), paste0(
    "C3_APPLY_INTEGRATION_PARTIAL_DOMAIN_CASE_", case_index))
  assert_zero_ledger(paste0(
    "C3_APPLY_INTEGRATION_PARTIAL_LEDGER_CASE_", case_index))
  with_connection(function(connection) execute(
    connection, "UPDATE public.person SET staged=false WHERE id=$1", list(drift_person)))
  expect(identical(domain_snapshot(), initial_domain), paste0(
    "C3_APPLY_INTEGRATION_RESTORE_DRIFT_CASE_", case_index))
}

## -------------------------------------------------------------------------
## Real two-session schedules through dblink.
## -------------------------------------------------------------------------
controller <- connect()
on.exit(close_connection(controller), add = TRUE)
execute(controller, "CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions")
conninfo <- paste(
  paste0("dbname=", pg$PGDATABASE), paste0("host=", pg$PGHOST),
  paste0("port=", pg$PGPORT), paste0("user=", pg$PGUSER),
  if (nzchar(pg$PGPASSWORD)) paste0("password=", pg$PGPASSWORD) else NULL)
remote_exec <- function(name, sql) invisible(without_open_result_warning(query(
  controller, "SELECT extensions.dblink_exec($1,$2)", list(name, sql))))
remote_connect <- function(name) {
  query(controller, "SELECT extensions.dblink_connect($1,$2)", list(name, conninfo))
  remote_exec(name, "BEGIN")
  remote_exec(name, paste0("SET LOCAL request.jwt.claim.sub='", actor, "'"))
  remote_exec(name, "SET LOCAL statement_timeout='20s'")
  remote_exec(name, "SET LOCAL lock_timeout='5s'")
  remote_exec(name, "SET LOCAL app.change_set_id TO ''")
  query(controller, paste(
    "SELECT pid FROM extensions.dblink($1,'SELECT pg_backend_pid()')",
    "AS t(pid integer)"), list(name))$pid[[1L]]
}
remote_send_apply <- function(name, authorization_id) {
  sql <- sprintf(
    "SELECT public.red_apply_reimport_cases('%s'::uuid,'%s','%s')::text",
    authorization_id, bundle$hashes$manifest_sha256,
    bundle$hashes$approval_sha256)
  sent <- query(controller,
                "SELECT extensions.dblink_send_query($1,$2) sent",
                list(name, sql))$sent[[1L]]
  expect(sent == 1L, "C3_APPLY_INTEGRATION_DBLINK_SEND_FAILED")
}
wait_until <- function(predicate, token, timeout = 6) {
  deadline <- Sys.time() + timeout
  repeat {
    if (isTRUE(predicate())) return(invisible(TRUE))
    if (Sys.time() >= deadline) stop(token, call. = FALSE)
    Sys.sleep(0.01)
  }
}
remote_waiting <- function(pid) {
  state <- query(controller, paste(
    "SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1"), list(pid))
  nrow(state) == 1L && identical(state$wait_event_type[[1L]], "Lock")
}
remote_finish <- function(name) {
  wait_until(function() query(
    controller, "SELECT extensions.dblink_is_busy($1) busy",
    list(name))$busy[[1L]] == 0L,
    paste0("C3_APPLY_INTEGRATION_REMOTE_TIMEOUT_", name), timeout = 25)
  result <- without_open_result_warning(query(controller, paste(
    "SELECT receipt FROM extensions.dblink_get_result($1,true)",
    "AS t(receipt text)"), list(name)))$receipt[[1L]]
  ## libpq keeps one final empty result after an asynchronous query. Drain it
  ## before issuing COMMIT/ROLLBACK on the same dblink connection; otherwise
  ## PostgreSQL correctly reports "another command is already in progress".
  suppressWarnings(try(without_open_result_warning(query(controller, paste(
    "SELECT receipt FROM extensions.dblink_get_result($1,true)",
    "AS t(receipt text)"), list(name))), silent = TRUE))
  result
}
remote_close <- function(name) {
  connected <- query(controller, paste(
    "SELECT $1 = ANY(coalesce(extensions.dblink_get_connections(),",
    "ARRAY[]::text[])) connected"), list(name))$connected[[1L]]
  if (!isTRUE(connected)) return(invisible(NULL))
  try_cleanup(remote_exec(name, "ROLLBACK"))
  try_cleanup(query(controller, "SELECT extensions.dblink_disconnect($1)",
                    list(name)))
  invisible(NULL)
}
authorize <- function(nonce) with_connection(function(connection) {
  DBI::dbBegin(connection)
  committed <- FALSE
  on.exit(if (!committed) try_cleanup(DBI::dbRollback(connection)),
          add = TRUE)
  set_actor(connection)
  authorization_id <- as.character(query(
    connection, .c3_apply_sql$authorize, list(
      source_id, "c3", "apply", bundle$hashes$manifest_sha256,
      bundle$hashes$preview_sha256, bundle$hashes$approval_sha256,
      bundle$hashes$decisions_sha256, bundle$hashes$state_sha256,
      bundle$hashes$text_bundle_sha256, bundle$database$database_name,
      bundle$database$system_identifier, bundle$expected_counts_json,
      bundle$authorized_elements_json, nonce))$authorization_id[[1L]])
  DBI::dbCommit(connection)
  committed <- TRUE
  authorization_id
})
delete_issued_authorization <- function(authorization_id) with_connection(
  function(connection) execute(connection, paste(
    "DELETE FROM private.reimport_case_authorization",
    "WHERE id=$1::uuid AND status='issued'"), list(authorization_id)))

writer_scenario <- function(tag, nonce, writer) {
  before <- domain_snapshot()
  authorization_id <- authorize(nonce)
  holder <- connect()
  remote_name <- paste0("c3_task9_", tag)
  on.exit(close_connection(holder), add = TRUE)
  on.exit(remote_close(remote_name), add = TRUE)
  DBI::dbBegin(holder)
  set_actor(holder)
  query(holder, "SELECT set_config('app.change_set_id','',true)")
  writer(holder)
  pid <- remote_connect(remote_name)
  remote_send_apply(remote_name, authorization_id)
  wait_until(function() remote_waiting(pid), paste0(
    "C3_APPLY_INTEGRATION_WRITER_DID_NOT_BLOCK_", tag))
  DBI::dbRollback(holder)
  receipt <- without_open_result_warning(remote_finish(remote_name))
  .c3_apply_verify_receipt(receipt, bundle, "apply", authorization_id)
  remote_exec(remote_name, "ROLLBACK")
  remote_close(remote_name)
  delete_issued_authorization(authorization_id)
  expect(identical(domain_snapshot(), before), paste0(
    "C3_APPLY_INTEGRATION_WRITER_RESIDUE_", tag))
  assert_zero_ledger(paste0("C3_APPLY_INTEGRATION_WRITER_LEDGER_", tag))
}

writer_scenario("identity", uuid("d001"), function(connection) {
  query(connection, "SELECT public.red_ikke_samme_som($1,$2)",
        list(person_ids[[1L]], person_ids[[2L]]))
})
writer_scenario("publication", uuid("d002"), function(connection) {
  query(connection, paste(
    "SELECT public.red_publicer_narrative_record(",
    "$1::bigint,$2::uuid,'synthetic','synthetic')"),
    list(spare_narrative_id, record_ids[[1L]]))
})
writer_scenario("delete", uuid("d003"), function(connection) {
  query(connection, "SELECT public.red_slet_person($1)",
        list(person_ids[[1L]]))
})

## Two identical committed calls with the same authorization: call 1 is held
## at the source-record lock while call 2 demonstrably waits on the global
## advisory lock. Both must return the same receipt and create one batch only.
apply_nonce <- uuid("e001")
authorization_id <- authorize(apply_nonce)
blocker <- connect()
on.exit(close_connection(blocker), add = TRUE)
DBI::dbBegin(blocker)
invisible(query(
  blocker, "SELECT id FROM private.source_record WHERE id=$1::uuid FOR UPDATE",
  list(record_ids[[1L]])))
pid1 <- remote_connect("c3_task9_apply_1")
pid2 <- remote_connect("c3_task9_apply_2")
on.exit(remote_close("c3_task9_apply_1"), add = TRUE)
on.exit(remote_close("c3_task9_apply_2"), add = TRUE)
remote_send_apply("c3_task9_apply_1", authorization_id)
wait_until(function() remote_waiting(pid1),
           "C3_APPLY_INTEGRATION_FIRST_APPLY_DID_NOT_BLOCK")
remote_send_apply("c3_task9_apply_2", authorization_id)
wait_until(function() {
  query(controller, paste(
    "SELECT count(*)::integer n FROM pg_locks",
    "WHERE pid=$1 AND locktype='advisory' AND NOT granted"),
    list(pid2))$n[[1L]] == 1L
}, "C3_APPLY_INTEGRATION_SECOND_APPLY_DID_NOT_WAIT_ON_WRITER_LOCK")
DBI::dbRollback(blocker)
receipt1 <- remote_finish("c3_task9_apply_1")
remote_exec("c3_task9_apply_1", "COMMIT")
receipt2 <- remote_finish("c3_task9_apply_2")
remote_exec("c3_task9_apply_2", "COMMIT")
remote_close("c3_task9_apply_1")
remote_close("c3_task9_apply_2")
verified1 <- .c3_apply_verify_receipt(receipt1, bundle, "apply", authorization_id)
verified2 <- .c3_apply_verify_receipt(receipt2, bundle, "apply", authorization_id)
expect(identical(receipt1, receipt2) &&
       identical(verified1$batch_id, verified2$batch_id),
       "C3_APPLY_INTEGRATION_CONCURRENT_RECEIPT_DRIFT")
counts_after_apply <- ledger_counts()
expect(counts_after_apply$authorizations[[1L]] == 1L &&
       counts_after_apply$batches[[1L]] == 1L &&
       counts_after_apply$events[[1L]] == 11L,
       "C3_APPLY_INTEGRATION_CONCURRENT_DUPLICATED")

status <- without_open_result_warning(c3_apply_run(
  "status", bundle, options_for(apply_nonce), gateway_connect))
expect(identical(status$outcome, "committed") &&
       identical(status$batch_id, verified1$batch_id),
       "C3_APPLY_INTEGRATION_STATUS_NOT_COMMITTED")
replayed <- without_open_result_warning(c3_apply_run(
  "apply", bundle, options_for(apply_nonce), gateway_connect))
expect(identical(replayed$outcome, "applied") &&
       identical(replayed$batch_id, verified1$batch_id),
       "C3_APPLY_INTEGRATION_IDEMPOTENT_REPLAY_FAILED")
counts_after_replay <- ledger_counts()
expect(identical(counts_after_apply, counts_after_replay),
       "C3_APPLY_INTEGRATION_IDEMPOTENT_REPLAY_DUPLICATED")

nonce_drift <- tryCatch(with_connection(function(connection) {
  DBI::dbBegin(connection)
  on.exit(try_cleanup(DBI::dbRollback(connection)), add = TRUE)
  set_actor(connection)
  query(connection, .c3_apply_sql$authorize, list(
    source_id, "c3", "apply", paste(rep("9", 64L), collapse = ""),
    bundle$hashes$preview_sha256, bundle$hashes$approval_sha256,
    bundle$hashes$decisions_sha256, bundle$hashes$state_sha256,
    bundle$hashes$text_bundle_sha256, bundle$database$database_name,
    bundle$database$system_identifier, bundle$expected_counts_json,
    bundle$authorized_elements_json, apply_nonce))
  ""
}), error = conditionMessage)
expect(grepl("REIMPORT_CASE_NONCE_CONFLICT", nonce_drift, fixed = TRUE),
       "C3_APPLY_INTEGRATION_NONCE_DRIFT_ACCEPTED")

reverse <- without_open_result_warning(c3_apply_run(
  "reverse", bundle,
  c(options_for(apply_nonce), list(batch_id = verified1$batch_id,
                                   reversal_nonce = uuid("e002"))),
  gateway_connect))
expect(identical(reverse$outcome, "reversed_batch"),
       "C3_APPLY_INTEGRATION_REVERSAL_FAILED")
expect(identical(domain_snapshot(), initial_domain),
       "C3_APPLY_INTEGRATION_REVERSAL_DOMAIN_DRIFT")
reversed_status <- without_open_result_warning(c3_apply_run(
  "status", bundle, options_for(apply_nonce), gateway_connect))
expect(identical(reversed_status$outcome, "reversed"),
       "C3_APPLY_INTEGRATION_REVERSED_STATUS_DRIFT")
final_counts <- ledger_counts()
expect(final_counts$authorizations[[1L]] == 2L &&
       final_counts$batches[[1L]] == 2L &&
       final_counts$events[[1L]] == 22L,
       "C3_APPLY_INTEGRATION_REVERSAL_LEDGER_DRIFT")

cat(sprintf(paste0(
  "PASS C3 Task 9 integration: %d assertions; five failure positions; ",
  "three writer schedules; concurrent apply; idempotence; exact reversal\n"), ok))
