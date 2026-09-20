#!/usr/bin/env Rscript

# Real PostgreSQL 17 concurrency proof for issue #152.
#
# The test intentionally uses clean independent R processes. Each process
# creates its own RPostgres connection, so no libpq state or connection is
# inherited or shared.

required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg_values <- Sys.getenv(required_pg, unset = NA_character_)
if (anyNA(pg_values) || any(!nzchar(pg_values))) {
  stop(
    "NARRATIVE_RECORD_TASK12_ALL_FIVE_PG_VARIABLES_REQUIRED: ",
    paste(required_pg, collapse = ", "),
    call. = FALSE
  )
}

if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("RPostgres", quietly = TRUE) ||
    !requireNamespace("processx", quietly = TRUE) ||
    !requireNamespace("bit64", quietly = TRUE) ||
    !requireNamespace("jsonlite", quietly = TRUE) ||
    !requireNamespace("digest", quietly = TRUE)) {
  stop("NARRATIVE_RECORD_TASK12_R_PACKAGES_REQUIRED", call. = FALSE)
}

pg <- as.list(stats::setNames(pg_values, required_pg))
pg$PGPORT <- as.integer(pg$PGPORT)

connect <- function(application_name = NULL) {
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = pg$PGDATABASE,
    host = pg$PGHOST,
    port = pg$PGPORT,
    user = pg$PGUSER,
    password = pg$PGPASSWORD
  )
  if (!is.null(application_name)) {
    DBI::dbGetQuery(
      con,
      "SELECT set_config('application_name',$1,false)",
      params = list(application_name)
    )
  }
  DBI::dbExecute(con, "SET statement_timeout='12s'")
  con
}

scalar <- function(con, sql, params = list()) {
  result <- if (length(params)) {
    DBI::dbGetQuery(con, sql, params = params)
  } else {
    DBI::dbGetQuery(con, sql)
  }
  if (nrow(result) != 1L || ncol(result) != 1L) {
    stop("NARRATIVE_RECORD_TASK12_SCALAR_QUERY_SHAPE_INVALID", call. = FALSE)
  }
  result[[1L]][[1L]]
}

assertions <- 0L
expect_true <- function(value, code) {
  assertions <<- assertions + 1L
  if (!isTRUE(value)) stop(code, call. = FALSE)
  invisible(TRUE)
}

# Regression for the production-shaped multi-source exporter. RPostgres returns
# bigint columns as bit64::integer64. Base anyDuplicated() compares their raw
# double payloads and can report distinct negative bigint values as duplicates.
source(file.path(
  ".claude", "skills", "daa-extract", "scripts",
  "export_narrative_record_cutover_helpers.R"
))

export_hash <- paste(rep("a", 64L), collapse = "")
export_records <- data.frame(
  binding_id = "00000000-0000-4000-8000-000000000001",
  narrative_id = bit64::as.integer64("-91521301"),
  person_id = bit64::as.integer64("-91521101"),
  source_id = bit64::as.integer64("-91521299"),
  source_kind = "DAA-udgave",
  source_record_id = "00000000-0000-4000-8000-000000000101",
  record_key = "task12-export-record",
  status = "draft",
  record_label = "Synthetic Task 12 record",
  citation_label = "Synthetic Task 12 citation",
  publication_state_sha256 = export_hash,
  narrative_text_sha256 = export_hash,
  binding_match_count = 1L,
  stringsAsFactors = FALSE
)
export_legacy <- data.frame(
  legacy_publication_ref = c(
    "00000000-0000-4000-8000-000000000201",
    "00000000-0000-4000-8000-000000000202"
  ),
  narrative_id = bit64::as.integer64(c("-91521303", "-91521302")),
  person_id = bit64::as.integer64(c("-91521101", "-91521101")),
  source_id = bit64::as.integer64(c("-91521201", "-91521201")),
  source_kind = c("DAA-udgave", "DAA-udgave"),
  narrative_text_sha256 = c(export_hash, export_hash),
  baseline_sha256 = c(export_hash, export_hash),
  binding_match_count = c(0L, 0L),
  stringsAsFactors = FALSE
)
export_counts <- data.frame(
  source_id = bit64::as.integer64(c("-91521299", "-91521201")),
  record_candidates = c(1L, 0L),
  legacy_candidates = c(0L, 2L)
)
export_identity <- data.frame(
  accepted_identity_count = 1L,
  identity_blocked_record_count = 0L
)
export_database <- list(
  database_name = "daa_narrative_152_task12_disposable",
  system_identifier = "7000000000000000001"
)

build_export_bundle <- function(counts = export_counts, legacy = export_legacy) {
  nrk_export_build_bundle(
    export_records, legacy, counts, export_identity, export_database
  )
}

expect_export_failure <- function(code, case, counts = export_counts,
                                  legacy = export_legacy) {
  observed <- tryCatch(
    {
      build_export_bundle(counts, legacy)
      "NO_ERROR"
    },
    error = function(error) conditionMessage(error)
  )
  expect_true(identical(observed, code), paste0(
    "NARRATIVE_RECORD_TASK12_EXPORT_FAILURE_MISMATCH (", case, "): expected ", code,
    ", got ", observed
  ))
}

expect_true(
  length(nrk_export_new_legacy_refs(export_legacy$narrative_id)) == 2L,
  "NARRATIVE_RECORD_TASK12_INTEGER64_LEGACY_REF_IDS_REJECTED"
)
expect_true(
  is.list(build_export_bundle()),
  "NARRATIVE_RECORD_TASK12_INTEGER64_MULTI_SOURCE_EXPORT_REJECTED"
)
duplicate_export_legacy <- export_legacy
duplicate_export_legacy$narrative_id[[2L]] <- duplicate_export_legacy$narrative_id[[1L]]
expect_export_failure(
  "DUPLICATE_LEGACY_CANDIDATE", "duplicate integer64 legacy ID",
  legacy = duplicate_export_legacy
)
expect_export_failure(
  "LEGACY_CANDIDATE_ORDER", "descending integer64 legacy IDs",
  legacy = export_legacy[2:1, , drop = FALSE]
)
duplicate_export_counts <- export_counts
duplicate_export_counts$source_id[[2L]] <- duplicate_export_counts$source_id[[1L]]
expect_export_failure(
  "COUNTS_BY_SOURCE_ORDER", "duplicate integer64", counts = duplicate_export_counts
)
expect_export_failure(
  "COUNTS_BY_SOURCE_ORDER", "descending integer64",
  counts = export_counts[2:1, , drop = FALSE]
)

extract_code <- function(message) {
  match <- regexpr(
    "(?:NARRATIVE_RECORD|CUTOVER)_[A-Z0-9_]+",
    message,
    perl = TRUE
  )
  if (match[[1L]] < 0L) return("UNCLASSIFIED_DATABASE_ERROR")
  regmatches(message, match)
}

set_actor <- function(con, actor_id) {
  scalar(
    con,
    "SELECT set_config('request.jwt.claim.sub',$1,false)",
    list(actor_id)
  )
  invisible(TRUE)
}

worker_call <- function(application_name, sql, actor_id = NULL, fetch = TRUE) {
  con <- connect(application_name)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!is.null(actor_id)) set_actor(con, actor_id)
  tryCatch(
    {
      value <- if (fetch) {
        result <- DBI::dbGetQuery(con, sql)
        if (nrow(result) == 1L && ncol(result) == 1L) {
          as.character(result[[1L]][[1L]])
        } else {
          paste(capture.output(print(result)), collapse = "\n")
        }
      } else {
        as.character(DBI::dbExecute(con, sql))
      }
      list(code = "OK", value = value)
    },
    error = function(error) {
      message <- conditionMessage(error)
      list(code = extract_code(message), message = message)
    }
  )
}

worker_program <- paste0(
  "args<-commandArgs(trailingOnly=TRUE);",
  "application_name<-args[[1L]];sql<-args[[2L]];actor_id<-args[[3L]];",
  "fetch<-identical(args[[4L]],'true');",
  "con<-DBI::dbConnect(RPostgres::Postgres(),",
  "dbname=Sys.getenv('PGDATABASE'),host=Sys.getenv('PGHOST'),",
  "port=as.integer(Sys.getenv('PGPORT')),user=Sys.getenv('PGUSER'),",
  "password=Sys.getenv('PGPASSWORD'));",
  "on.exit(DBI::dbDisconnect(con),add=TRUE);",
  "DBI::dbGetQuery(con,\"SELECT set_config('application_name',$1,false)\",",
  "params=list(application_name));",
  "DBI::dbExecute(con,\"SET statement_timeout='12s'\");",
  "if(nzchar(actor_id)) DBI::dbGetQuery(con,",
  "\"SELECT set_config('request.jwt.claim.sub',$1,false)\",params=list(actor_id));",
  "code<-tryCatch({if(fetch) DBI::dbGetQuery(con,sql) else DBI::dbExecute(con,sql);",
  "'OK'},error=function(error){message<-conditionMessage(error);",
  "cat('TASK12_DB_ERROR:',gsub('[\\r\\n]+',' | ',message),'\\n',file=stderr(),sep='');",
  "match<-regexpr('(?:NARRATIVE_RECORD|CUTOVER)_[A-Z0-9_]+',message,perl=TRUE);",
  "if(match[[1L]]<0L)'UNCLASSIFIED_DATABASE_ERROR' else regmatches(message,match)});",
  "cat('TASK12_RESULT_CODE:',code,'\\n',sep='')"
)

launch_worker <- function(application_name, sql, actor_id = NULL, fetch = TRUE) {
  worker_env <- c(
    PGDATABASE = pg$PGDATABASE,
    PGHOST = pg$PGHOST,
    PGPORT = as.character(pg$PGPORT),
    PGUSER = pg$PGUSER,
    PGPASSWORD = pg$PGPASSWORD
  )
  inherited_library_env <- Sys.getenv(
    c("R_LIBS", "R_LIBS_USER", "R_LIBS_SITE"),
    unset = NA_character_
  )
  inherited_library_env <- inherited_library_env[
    !is.na(inherited_library_env) & nzchar(inherited_library_env)
  ]

  processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    args = c(
      "--vanilla", "-e", worker_program,
      application_name, sql, if (is.null(actor_id)) "" else actor_id,
      if (fetch) "true" else "false"
    ),
    env = c(worker_env, inherited_library_env),
    stdout = "|",
    stderr = "|",
    cleanup_tree = TRUE
  )
}

collect_workers <- function(jobs, timeout = 15) {
  deadline <- Sys.time() + timeout
  while (any(vapply(jobs, function(job) job$is_alive(), logical(1)))) {
    if (Sys.time() > deadline) {
      for (job in jobs) try(job$kill(), silent = TRUE)
      stop("NARRATIVE_RECORD_TASK12_WORKER_TIMEOUT_OR_DEADLOCK", call. = FALSE)
    }
    Sys.sleep(0.02)
  }
  lapply(jobs, function(job) {
    output <- paste(job$read_all_output(), job$read_all_error(), sep = "\n")
    marker <- regexec("TASK12_RESULT_CODE:([A-Z0-9_]+)", output, perl = TRUE)
    fields <- regmatches(output, marker)[[1L]]
    if (length(fields) != 2L) {
      stop(
        "NARRATIVE_RECORD_TASK12_WORKER_RESULT_INVALID: ",
        paste0("exit=", job$get_exit_status(), "; output=", output),
        call. = FALSE
      )
    }
    list(code = fields[[2L]], output = output)
  })
}

wait_for_blockers <- function(con, application_names, blocker_pid, timeout = 15,
                              jobs = NULL) {
  deadline <- Sys.time() + timeout
  repeat {
    blocked <- vapply(
      application_names,
      function(application_name) {
        isTRUE(scalar(
          con,
          paste0(
            "SELECT coalesce(bool_or($2::integer=ANY(pg_blocking_pids(pid))),false) ",
            "FROM pg_stat_activity ",
            "WHERE datname=current_database() AND application_name=$1"
          ),
          list(application_name, blocker_pid)
        ))
      },
      logical(1)
    )
    if (all(blocked)) return(invisible(TRUE))
    if (Sys.time() > deadline) {
      details <- DBI::dbGetQuery(
        con,
        paste0(
          "SELECT application_name,pid,state,wait_event_type,wait_event,",
          "pg_blocking_pids(pid)::text AS blockers ",
          "FROM pg_stat_activity ",
          "WHERE datname=current_database() ",
          "AND application_name LIKE 'task12_%' ORDER BY application_name"
        )
      )
      job_details <- if (is.null(jobs)) {
        NULL
      } else {
        lapply(jobs, function(job) {
          alive <- job$is_alive()
          list(
            pid = job$get_pid(),
            alive = alive,
            exit_status = job$get_exit_status(),
            stdout = job$read_all_output(),
            stderr = job$read_all_error()
          )
        })
      }
      stop(
        "NARRATIVE_RECORD_TASK12_EXPECTED_LOCK_WAIT_NOT_OBSERVED: ",
        paste(capture.output(dput(list(sessions = details, jobs = job_details))),
              collapse = " "),
        call. = FALSE
      )
    }
    Sys.sleep(0.02)
  }
}

uuid_for <- function(value) sprintf("15212000-0000-0000-0000-%012d", value)

actor_id <- uuid_for(99)
person_id <- -91521201L
source_id <- -91521201L
old_person_id <- -91521299L
old_source_id <- -91521299L
run_id <- uuid_for(1)
rendition_id <- uuid_for(2)
scheme_entry_id <- -91521201L

seed_record <- function(con, index, record_key, page) {
  record_id <- uuid_for(100 + index)
  occurrence_id <- uuid_for(200 + index)
  anchor_id <- uuid_for(300 + index)
  observation_id <- uuid_for(400 + index)
  persona_id <- uuid_for(500 + index)
  mention_id <- uuid_for(600 + index)
  record_placement_id <- uuid_for(700 + index)
  persona_placement_id <- uuid_for(800 + index)
  identity_event_id <- uuid_for(900 + index)

  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_record(",
      "id,source_id,record_key,record_kind,created_run_id",
      ") VALUES ($1,$2,$3,'person',$4)"
    ),
    params = list(record_id, source_id, record_key, run_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_record_occurrence(",
      "id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,",
      "verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id",
      ") VALUES ($1,$2,$3,$4,$4,0,20,$5,$6,$7,$8)"
    ),
    params = list(
      occurrence_id, rendition_id, record_key, page,
      paste("Task 12 synthetic occurrence", index),
      paste0("task12-physical-", index),
      paste0("task12-structural-", index), run_id
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_record_anchor_event(",
      "id,occurrence_id,source_record_id,decision_status,evidence,version,",
      "decided_by,decided_by_name",
      ") VALUES ($1,$2,$3,'accepted',jsonb_build_object('basis','Task 12 synthetic'),",
      "1,$4,'Task 12 synthetic actor')"
    ),
    params = list(anchor_id, occurrence_id, record_id, actor_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_observation(",
      "id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,",
      "verbatim_text,quality_status,extraction_method,extraction_run_id",
      ") VALUES ($1,$2,'header',$3,$3,0,20,$4,'clear','task12-test',$5)"
    ),
    params = list(
      observation_id, occurrence_id, page,
      paste("Task 12 synthetic observation", index), run_id
    )
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) ",
      "VALUES ($1,$2,$3,$4)"
    ),
    params = list(persona_id, source_id, paste0("task12-persona-", index), run_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_mention(",
      "id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id",
      ") VALUES ($1,$2,'person_name',0,4,'Task',$3)"
    ),
    params = list(mention_id, observation_id, run_id)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES ($1,$2,'primary',1)",
    params = list(persona_id, mention_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_record_placement(",
      "id,source_record_id,scheme_entry_id,header_observation_id,initial_status",
      ") VALUES ($1,$2,$3,$4,'accepted')"
    ),
    params = list(record_placement_id, record_id, scheme_entry_id, observation_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_record_placement_decision(",
      "placement_id,version,decision_status,evidence,decision_origin,decided_by_name",
      ") VALUES ($1,1,'accepted',jsonb_build_object('basis','Task 12 synthetic'),",
      "'migration','Task 12 synthetic actor')"
    ),
    params = list(record_placement_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_persona_placement(",
      "id,source_persona_id,record_placement_id,placement_role,",
      "basis_observation_id,initial_status",
      ") VALUES ($1,$2,$3,'principal_member',$4,'accepted')"
    ),
    params = list(persona_placement_id, persona_id, record_placement_id, observation_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_persona_placement_decision(",
      "placement_id,version,decision_status,evidence,decision_origin,decided_by_name",
      ") VALUES ($1,1,'accepted',jsonb_build_object('basis','Task 12 synthetic'),",
      "'migration','Task 12 synthetic actor')"
    ),
    params = list(persona_placement_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_persona_identity_event(",
      "id,source_persona_id,canonical_person_id,decision_status,version,evidence,",
      "decided_by,decided_by_name,decided_at",
      ") VALUES ($1,$2,$3,'accepted',1,jsonb_build_object('basis','Task 12 synthetic'),",
      "$4,'Task 12 synthetic actor',transaction_timestamp())"
    ),
    params = list(identity_event_id, persona_id, person_id, actor_id)
  )
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO private.source_persona_identity(",
      "source_persona_id,canonical_person_id,decision_status,version,evidence,",
      "decided_by,decided_by_name,decided_at",
      ") VALUES ($1,$2,'accepted',1,jsonb_build_object('basis','Task 12 synthetic'),",
      "$3,'Task 12 synthetic actor',transaction_timestamp())"
    ),
    params = list(persona_id, person_id, actor_id)
  )
  record_id
}

controller <- connect("task12_controller")
on.exit(DBI::dbDisconnect(controller), add = TRUE)
observer <- connect("task12_observer")
on.exit(DBI::dbDisconnect(observer), add = TRUE)

server_version <- as.integer(scalar(controller, "SHOW server_version_num"))
expect_true(server_version >= 170000L && server_version < 180000L,
            "NARRATIVE_RECORD_TASK12_POSTGRES_17_REQUIRED")
actual_database <- scalar(controller, "SELECT current_database()")
expect_true(identical(actual_database, pg$PGDATABASE),
            "NARRATIVE_RECORD_TASK12_DATABASE_ENV_MISMATCH")
expect_true(
  grepl("(task12|test|ci|disposable)", actual_database, ignore.case = TRUE) &&
    !identical(actual_database, "postgres") &&
    pg$PGHOST %in% c("127.0.0.1", "localhost", "::1"),
  "NARRATIVE_RECORD_TASK12_DISPOSABLE_LOCAL_DATABASE_REQUIRED"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT public.narrative_record_contract_version()"
  )), 1L),
  "NARRATIVE_RECORD_TASK12_INITIAL_VERSION_NOT_ONE"
)

DBI::dbBegin(controller)
DBI::dbExecute(
  controller,
  "INSERT INTO auth.users(id,email) VALUES ($1,'task12-concurrency@test.invalid')",
  params = list(actor_id)
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO public.profiles(id,rolle,email,navn) ",
    "VALUES ($1,'redaktion','task12-concurrency@test.invalid','Task 12 synthetic actor')"
  ),
  params = list(actor_id)
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO public.person(id,levende,privat,staged,visning_navn) VALUES ",
    "($1,false,false,false,'Task 12 record person'),",
    "($2,false,false,false,'Task 12 old-writer person')"
  ),
  params = list(person_id, old_person_id)
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO public.source(id,slags,titel,udgave,aar,import_key) VALUES ",
    "($1,'DAA-udgave','Task 12 record source','Task 12 synthetic',1939,'task12:record'),",
    "($2,'DAA-udgave','Task 12 old source','Task 12 synthetic old',1939,'task12:old')"
  ),
  params = list(source_id, old_source_id)
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO private.extraction_run(",
    "id,source_id,run_key,schema_version,extractor_version,profile_version,",
    "input_sha256,manifest",
    ") VALUES ($1,$2,'task12-run','1','task12','task12',$3,'{}')"
  ),
  params = list(run_id, source_id, paste(rep("1", 64L), collapse = ""))
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO private.source_rendition(",
    "id,source_id,rendition_key,rendition_kind,content_sha256,metadata",
    ") VALUES ($1,$2,'task12-rendition','text_layer',$3,'{}')"
  ),
  params = list(rendition_id, source_id, paste(rep("2", 64L), collapse = ""))
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) ",
    "VALUES ($1,'Task 12 slægt','Task 12 slægt','task12-slaegt')"
  ),
  params = list(source_id)
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) ",
    "VALUES ($1,$1,$1,'stamtavle','Task 12 scheme')"
  ),
  params = list(source_id)
)
DBI::dbExecute(
  controller,
  paste0(
    "INSERT INTO public.lineage_scheme_entry(",
    "id,scheme_id,slaegt_id,code,label,sort_order",
    ") VALUES ($1,$1,$1,'A','Linje A',1)"
  ),
  params = list(scheme_entry_id)
)
record_one_id <- seed_record(controller, 1L, "task12-record-a", 4L)
record_two_id <- seed_record(controller, 2L, "task12-record-b", 7L)
DBI::dbCommit(controller)

set_actor(controller, actor_id)

record_state_sha <- function(con, record_key) {
  scalar(
    con,
    paste0(
      "SELECT private.narrative_record_state($1,$2,$3,false)->>'state_sha256'"
    ),
    list(person_id, source_id, record_key)
  )
}

record_writer_sql <- function(record_key, text, state_sha) {
  sprintf(
    paste0(
      "SELECT public.red_upsert_person_narrative_record(%d,%d,%s,%s,false,%s)"
    ),
    person_id,
    source_id,
    DBI::dbQuoteString(controller, record_key),
    DBI::dbQuoteString(controller, text),
    DBI::dbQuoteString(controller, state_sha)
  )
}

build_empty_cutover_artifacts <- function(con) {
  database_row <- DBI::dbGetQuery(con, .nrk_export_sql$identity)
  database <- list(
    database_name = database_row$database_name[[1L]],
    system_identifier = database_row$system_identifier[[1L]]
  )
  bundle <- nrk_export_build_bundle(
    DBI::dbGetQuery(con, .nrk_export_sql$record_candidates),
    DBI::dbGetQuery(con, .nrk_export_sql$legacy_candidates),
    DBI::dbGetQuery(con, .nrk_export_sql$counts_by_source),
    DBI::dbGetQuery(con, .nrk_export_sql$identity_counts),
    database
  )
  record_raw <- bundle[[.nrk_record_candidates_name]]
  legacy_raw <- bundle[[.nrk_legacy_candidates_name]]
  inventory_raw <- bundle[[.nrk_inventory_name]]
  record_document <- jsonlite::fromJSON(
    rawToChar(record_raw), simplifyVector = FALSE
  )
  legacy_document <- jsonlite::fromJSON(
    rawToChar(legacy_raw), simplifyVector = FALSE
  )
  if (length(record_document$rows) || length(legacy_document$rows)) {
    stop("NARRATIVE_RECORD_TASK12_INITIAL_CUTOVER_SET_NOT_EMPTY", call. = FALSE)
  }
  record_manifest_raw <- nrk_canonical_raw(list(
    database = database,
    record_candidates_sha256 = nrk_sha_raw(record_raw),
    rows = list(),
    schema_version = "narrative-record-baseline-manifest-v1"
  ))
  legacy_manifest_raw <- nrk_canonical_raw(list(
    database = database,
    legacy_candidates_sha256 = nrk_sha_raw(legacy_raw),
    rows = list(),
    schema_version = "narrative-legacy-baseline-manifest-v1"
  ))
  approval_raw <- nrk_canonical_raw(list(
    counts = list(
      legacy_candidates = 0L, legacy_hide = 0L, legacy_keep = 0L,
      record_approved = 0L
    ),
    database = database,
    input_hashes = list(
      approval_decisions_sha256 = strrep("a", 64L),
      inventory_sha256 = nrk_sha_raw(inventory_raw),
      legacy_candidates_sha256 = nrk_sha_raw(legacy_raw),
      legacy_manifest_sha256 = nrk_sha_raw(legacy_manifest_raw),
      record_candidates_sha256 = nrk_sha_raw(record_raw),
      record_manifest_sha256 = nrk_sha_raw(record_manifest_raw)
    ),
    legacy_hide_ids = list(),
    legacy_hide_rows = list(),
    legacy_keep_ids = list(),
    legacy_keep_rows = list(),
    record_approved_ids = list(),
    record_approved_rows = list(),
    schema_version = "narrative-record-cutover-approval-v1"
  ))
  list(
    record = record_raw,
    legacy = legacy_raw,
    record_manifest = record_manifest_raw,
    legacy_manifest = legacy_manifest_raw,
    inventory = inventory_raw,
    approval = approval_raw,
    database = database
  )
}

cutover_kernel_sql <- function(con, artifacts, nonce) {
  quote_text <- function(value) {
    as.character(DBI::dbQuoteString(con, value))
  }
  raw_arguments <- vapply(
    artifacts[c(
      "record", "legacy", "record_manifest", "legacy_manifest", "inventory", "approval"
    )],
    function(raw) quote_text(rawToChar(raw)),
    character(1)
  )
  paste0(
    "SELECT private.apply_narrative_record_cutover(",
    paste(c(
      raw_arguments,
      paste0(quote_text(nonce), "::uuid"),
      quote_text(artifacts$database$database_name),
      quote_text(artifacts$database$system_identifier)
    ), collapse = ","),
    ")"
  )
}

cutover_artifacts <- build_empty_cutover_artifacts(controller)

initial_record_state <- record_state_sha(controller, "task12-record-a")
inactive_result <- worker_call(
  "task12_new_v1",
  record_writer_sql("task12-record-a", "must not write at v1", initial_record_state),
  actor_id
)
expect_true(identical(inactive_result$code, "NARRATIVE_RECORD_CONTRACT_INACTIVE"),
            "NARRATIVE_RECORD_TASK12_NEW_WRITER_V1_CODE_INVALID")
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM private.narrative_record_publication WHERE source_record_id=$1",
    list(record_one_id)
  )), 0L),
  "NARRATIVE_RECORD_TASK12_NEW_WRITER_V1_WROTE"
)

# Lock order A: the production cutover kernel owns exclusive first; the old
# writer queues, wakes under committed version 2, and fails before its audit or
# narrative write.
cutover <- connect("task12_cutover_a")
on.exit(DBI::dbDisconnect(cutover), add = TRUE)
DBI::dbBegin(cutover)
cutover_a_nonce <- "15212000-0000-4000-8000-000000001201"
cutover_a_result <- scalar(
  cutover, cutover_kernel_sql(cutover, cutover_artifacts, cutover_a_nonce)
)
expect_true(
  identical(jsonlite::fromJSON(cutover_a_result)$contract_version_after, 2L),
  "NARRATIVE_RECORD_TASK12_ORDER_A_KERNEL_RESULT_INVALID"
)
cutover_pid <- as.integer(scalar(cutover, "SELECT pg_backend_pid()"))
old_a_sql <- sprintf(
  "SELECT public.red_upsert_narrativ('person',%d,'blocked by cutover',false,%d,NULL)",
  old_person_id,
  old_source_id
)
old_a_job <- launch_worker("task12_old_a", old_a_sql, actor_id)
wait_for_blockers(
  observer,
  "task12_old_a",
  cutover_pid,
  jobs = list(old_a = old_a_job)
)
DBI::dbCommit(cutover)
old_a_result <- collect_workers(list(old_a = old_a_job))[[1L]]
expect_true(identical(old_a_result$code, "NARRATIVE_RECORD_REQUIRED"),
            "NARRATIVE_RECORD_TASK12_ORDER_A_CODE_INVALID")
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM public.narrative WHERE subjekt_type='person' AND subjekt_id=$1 AND source_id=$2",
    list(old_person_id, old_source_id)
  )), 0L),
  "NARRATIVE_RECORD_TASK12_ORDER_A_OLD_WRITER_WROTE"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM public.change_set WHERE subjekt_type='person' AND subjekt_id=$1",
    list(old_person_id)
  )), 0L),
  "NARRATIVE_RECORD_TASK12_ORDER_A_AUDIT_WROTE"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM private.narrative_record_cutover_receipt WHERE nonce=$1::uuid",
    list(cutover_a_nonce)
  )), 1L),
  "NARRATIVE_RECORD_TASK12_ORDER_A_REAL_KERNEL_RECEIPT_MISSING"
)

DBI::dbBegin(cutover)
scalar(
  cutover,
  "SELECT pg_advisory_xact_lock(hashtextextended('daa-narrative-record-contract',0))"
)
DBI::dbExecute(cutover, "SELECT private.apply_narrative_record_contract_acl(1)")
DBI::dbExecute(
  cutover,
  "UPDATE private.narrative_record_contract SET version=1,changed_at=clock_timestamp() WHERE singleton AND version=2"
)
DBI::dbCommit(cutover)

# Lock order B: the old v1 writer owns shared first. The production cutover
# kernel must wait, re-read every exact live set after wakeup, and reject on
# drift without changing contract version or grants.
acl_manifest <- scalar(
  controller,
  paste0(
    "SELECT md5(string_agg(n.nspname||'.'||p.proname||coalesce(p.proacl::text,''),",
    "',' ORDER BY n.nspname,p.proname,p.oid)) ",
    "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace ",
    "WHERE p.proname LIKE 'red_%narrative_record%' ",
    "OR p.proname='narrative_record_contract_version'"
  )
)
old_writer <- connect("task12_old_b")
on.exit(DBI::dbDisconnect(old_writer), add = TRUE)
set_actor(old_writer, actor_id)
DBI::dbBegin(old_writer)
scalar(old_writer, sprintf(
  "SELECT public.red_upsert_narrativ('person',%d,'order B committed',false,%d,'1')",
  old_person_id,
  old_source_id
))
old_writer_pid <- as.integer(scalar(old_writer, "SELECT pg_backend_pid()"))
cutover_b_nonce <- "15212000-0000-4000-8000-000000001202"
cutover_b_sql <- cutover_kernel_sql(
  controller, cutover_artifacts, cutover_b_nonce
)
cutover_b_job <- launch_worker("task12_cutover_b", cutover_b_sql, fetch = FALSE)
wait_for_blockers(
  observer,
  "task12_cutover_b",
  old_writer_pid,
  jobs = list(cutover_b = cutover_b_job)
)
DBI::dbCommit(old_writer)
cutover_b_result <- collect_workers(list(cutover_b = cutover_b_job))[[1L]]
expect_true(identical(cutover_b_result$code, "CUTOVER_LEGACY_LIVE_SET_DRIFT"),
            "NARRATIVE_RECORD_TASK12_ORDER_B_CODE_INVALID")
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT public.narrative_record_contract_version()"
  )), 1L),
  "NARRATIVE_RECORD_TASK12_ORDER_B_CHANGED_VERSION"
)
expect_true(
  identical(scalar(
    controller,
    paste0(
      "SELECT md5(string_agg(n.nspname||'.'||p.proname||coalesce(p.proacl::text,''),",
      "',' ORDER BY n.nspname,p.proname,p.oid)) ",
      "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace ",
      "WHERE p.proname LIKE 'red_%narrative_record%' ",
      "OR p.proname='narrative_record_contract_version'"
    )
  ), acl_manifest),
  "NARRATIVE_RECORD_TASK12_ORDER_B_CHANGED_ACL"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM private.narrative_record_cutover_receipt WHERE nonce=$1::uuid",
    list(cutover_b_nonce)
  )), 0L),
  "NARRATIVE_RECORD_TASK12_ORDER_B_REAL_KERNEL_RECEIPT_WROTE"
)

# Activate v2 under the real exclusive gate. The following create and update
# races then exercise the production record writer with two real DBI sessions.
DBI::dbBegin(cutover)
scalar(
  cutover,
  "SELECT pg_advisory_xact_lock(hashtextextended('daa-narrative-record-contract',0))"
)
DBI::dbExecute(cutover, "SELECT private.apply_narrative_record_contract_acl(2)")
DBI::dbExecute(
  cutover,
  "UPDATE private.narrative_record_contract SET version=2,changed_at=clock_timestamp() WHERE singleton AND version=1"
)
DBI::dbCommit(cutover)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT public.narrative_record_contract_version()"
  )), 2L),
  "NARRATIVE_RECORD_TASK12_V2_ACTIVATION_FAILED"
)

initial_record_state <- record_state_sha(controller, "task12-record-a")
DBI::dbBegin(controller)
scalar(
  controller,
  "SELECT id::text FROM private.source_record WHERE id=$1 FOR UPDATE",
  list(record_one_id)
)
controller_pid <- as.integer(scalar(controller, "SELECT pg_backend_pid()"))
create_a <- launch_worker(
  "task12_create_a",
  record_writer_sql("task12-record-a", "Concurrent create A", initial_record_state),
  actor_id
)
wait_for_blockers(
  observer,
  "task12_create_a",
  controller_pid,
  jobs = list(create_a = create_a)
)
create_b_value <- DBI::dbGetQuery(
  controller,
  record_writer_sql("task12-record-a", "Concurrent create B", initial_record_state)
)[[1L]][[1L]]
DBI::dbCommit(controller)
create_results <- c(
  collect_workers(list(create_a = create_a)),
  list(create_b = list(code = "OK", value = as.character(create_b_value)))
)
create_codes <- unname(sort(vapply(create_results, `[[`, character(1), "code")))
expect_true(
  identical(create_codes, sort(c("OK", "NARRATIVE_RECORD_STATE_STALE"))),
  paste0(
    "NARRATIVE_RECORD_TASK12_CREATE_WINNER_LOSER_INVALID: ",
    paste(create_codes, collapse = ",")
  )
)
expect_true(
  identical(as.integer(scalar(
    controller,
    paste0(
      "SELECT count(*) FROM private.narrative_record_publication ",
      "WHERE source_record_id=$1 AND status IN ('draft','published')"
    ),
    list(record_one_id)
  )), 1L),
  "NARRATIVE_RECORD_TASK12_CREATE_DUPLICATE_ACTIVE_BINDING"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM private.narrative_publication_event WHERE source_record_id=$1",
    list(record_one_id)
  )), 1L),
  "NARRATIVE_RECORD_TASK12_CREATE_EVENT_COUNT_INVALID"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(DISTINCT stream_version) FROM private.narrative_publication_event WHERE source_record_id=$1",
    list(record_one_id)
  )), 1L),
  "NARRATIVE_RECORD_TASK12_CREATE_EVENT_VERSION_DUPLICATE"
)

draft_state <- record_state_sha(controller, "task12-record-a")
DBI::dbBegin(controller)
scalar(
  controller,
  "SELECT id::text FROM private.source_record WHERE id=$1 FOR UPDATE",
  list(record_one_id)
)
update_a <- launch_worker(
  "task12_update_a",
  record_writer_sql("task12-record-a", "Concurrent update A", draft_state),
  actor_id
)
wait_for_blockers(
  observer,
  "task12_update_a",
  controller_pid,
  jobs = list(update_a = update_a)
)
update_b_value <- DBI::dbGetQuery(
  controller,
  record_writer_sql("task12-record-a", "Concurrent update B", draft_state)
)[[1L]][[1L]]
DBI::dbCommit(controller)
update_results <- c(
  collect_workers(list(update_a = update_a)),
  list(update_b = list(code = "OK", value = as.character(update_b_value)))
)
update_codes <- unname(sort(vapply(update_results, `[[`, character(1), "code")))
expect_true(
  identical(update_codes, sort(c("OK", "NARRATIVE_RECORD_STATE_STALE"))),
  paste0(
    "NARRATIVE_RECORD_TASK12_UPDATE_WINNER_LOSER_INVALID: ",
    paste(update_codes, collapse = ",")
  )
)
expect_true(
  identical(as.integer(scalar(
    controller,
    "SELECT count(*) FROM private.narrative_publication_event WHERE source_record_id=$1",
    list(record_one_id)
  )), 2L),
  "NARRATIVE_RECORD_TASK12_UPDATE_EVENT_COUNT_INVALID"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    paste0(
      "SELECT count(*) FROM (",
      "SELECT stream_ref,stream_version FROM private.narrative_publication_event ",
      "WHERE source_record_id=$1 GROUP BY stream_ref,stream_version HAVING count(*)>1",
      ") duplicate_versions"
    ),
    list(record_one_id)
  )), 0L),
  "NARRATIVE_RECORD_TASK12_UPDATE_DUPLICATE_STREAM_VERSION"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    paste0(
      "SELECT max(stream_version) FROM private.narrative_publication_event ",
      "WHERE source_record_id=$1"
    ),
    list(record_one_id)
  )), 2L),
  "NARRATIVE_RECORD_TASK12_UPDATE_STREAM_VERSION_INVALID"
)
final_text <- scalar(
  controller,
  paste0(
    "SELECT narrative.tekst FROM public.narrative narrative ",
    "JOIN private.narrative_record_publication binding ",
    "ON binding.narrative_id=narrative.id ",
    "WHERE binding.source_record_id=$1 AND binding.status='draft'"
  ),
  list(record_one_id)
)
expect_true(
  final_text %in% c("Concurrent update A", "Concurrent update B"),
  "NARRATIVE_RECORD_TASK12_UPDATE_LOST_OR_MERGED_TEXT"
)

# A second source record for the same person/source remains independent and
# gets its own active binding/stream.
record_two_state <- record_state_sha(controller, "task12-record-b")
record_two_result <- worker_call(
  "task12_record_two",
  record_writer_sql("task12-record-b", "Independent record B", record_two_state),
  actor_id
)
expect_true(identical(record_two_result$code, "OK"),
            "NARRATIVE_RECORD_TASK12_SECOND_RECORD_CREATE_FAILED")
expect_true(
  identical(as.integer(scalar(
    controller,
    paste0(
      "SELECT count(*) FROM private.narrative_record_publication ",
      "WHERE source_record_id IN ($1,$2) AND status='draft'"
    ),
    list(record_one_id, record_two_id)
  )), 2L),
  "NARRATIVE_RECORD_TASK12_TWO_RECORD_BINDINGS_NOT_INDEPENDENT"
)
expect_true(
  identical(as.integer(scalar(
    controller,
    paste0(
      "SELECT count(DISTINCT stream_ref) FROM private.narrative_publication_event ",
      "WHERE source_record_id IN ($1,$2)"
    ),
    list(record_one_id, record_two_id)
  )), 2L),
  "NARRATIVE_RECORD_TASK12_TWO_RECORD_STREAMS_NOT_INDEPENDENT"
)

cat(sprintf(
  paste0(
    "OK: Task 12 real multi-session DBI concurrency proof ",
    "(%d assertions; create/update stale losers; lock orders A/B; v1/v2 gate)\n"
  ),
  assertions
))
