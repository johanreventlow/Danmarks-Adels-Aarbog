required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg <- setNames(lapply(required_pg, function(key) Sys.getenv(key, unset = NA_character_)), required_pg)
if (any(vapply(pg, function(value) length(value) != 1L || is.na(value), logical(1)))) {
  stop("IDENTITY_CONCURRENCY_REQUIRES_ALL_FIVE_PG_VARIABLES", call. = FALSE)
}
if (!grepl("^daa1939_c3_identity_task2_", pg$PGDATABASE)) {
  stop("IDENTITY_CONCURRENCY_REQUIRES_NAMED_DISPOSABLE_DATABASE", call. = FALSE)
}

connect <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = pg$PGDATABASE,
    host = pg$PGHOST,
    port = pg$PGPORT,
    user = pg$PGUSER,
    password = pg$PGPASSWORD
  )
}

query <- function(connection, sql, params = list()) {
  if (length(params)) DBI::dbGetQuery(connection, sql, params = params) else DBI::dbGetQuery(connection, sql)
}

execute <- function(connection, sql, params = list()) {
  if (length(params)) DBI::dbExecute(connection, sql, params = params) else DBI::dbExecute(connection, sql)
}

actor <- "19390000-0000-4000-8000-000000000003"
writer_change_set <- -1939503999
set_actor <- function(connection) {
  invisible(query(connection, "SELECT set_config('request.jwt.claim.sub',$1,false)", list(actor)))
}
set_writer_context <- function(connection) {
  set_actor(connection)
  invisible(query(connection, "SELECT set_config('app.change_set_id',$1,false)", list(as.character(writer_change_set))))
  invisible(query(connection, "SELECT set_config('app.change_seq','0',false)"))
}

controller <- connect()
on.exit(try(DBI::dbDisconnect(controller), silent = TRUE), add = TRUE)
if (!identical(query(controller, "SELECT current_database() name")$name[[1L]], pg$PGDATABASE)) {
  stop("IDENTITY_CONCURRENCY_DATABASE_IDENTITY_MISMATCH", call. = FALSE)
}
invisible(execute(controller, "CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions"))
invisible(execute(controller, paste0(
  "INSERT INTO auth.users(id,email) VALUES($1,'c3-identity-concurrency@test.invalid') ",
  "ON CONFLICT (id) DO NOTHING"
), list(actor)))
invisible(execute(controller, paste0(
  "INSERT INTO public.profiles(id,email,rolle,navn) ",
  "VALUES($1,'c3-identity-concurrency@test.invalid','redaktion','C3 identity concurrency test') ",
  "ON CONFLICT (id) DO UPDATE SET rolle='redaktion',navn='C3 identity concurrency test'"
), list(actor)))
invisible(execute(controller, paste0(
  "INSERT INTO public.change_set(id,actor_id,actor_navn,actor_rolle,operation,summary) ",
  "VALUES($1,$2,'C3 identity concurrency test','redaktion','test_context','Committed test writer context') ",
  "ON CONFLICT (id) DO NOTHING"
), list(writer_change_set, actor)))

seed_people <- function(ids) {
  for (id in ids) {
    execute(controller, paste0(
      "INSERT INTO public.person(id,levende,koen) VALUES($1,false,'ukendt') ",
      "ON CONFLICT (id) DO NOTHING"
    ), list(id))
  }
}

call_identity <- function(connection, writer, left, right) {
  sql <- switch(writer,
    samme_som = "SELECT public.red_samme_som($1,$2) value",
    ikke_samme_som = "SELECT public.red_ikke_samme_som($1,$2) value",
    stop("IDENTITY_CONCURRENCY_UNKNOWN_WRITER", call. = FALSE)
  )
  query(connection, sql, list(left, right))$value[[1L]]
}

helper_lock_schedule <- function(low, high) {
  seed_people(c(low, high))
  holder <- connect()
  contender <- connect()
  on.exit(try(DBI::dbDisconnect(holder), silent = TRUE), add = TRUE)
  on.exit(try(DBI::dbDisconnect(contender), silent = TRUE), add = TRUE)
  DBI::dbBegin(holder)
  set_actor(holder)
  query(holder, "SELECT private.lock_identity_people(ARRAY[$1,$2,$2,NULL]::bigint[])", list(high, low))

  DBI::dbBegin(contender)
  set_actor(contender)
  execute(contender, "SET LOCAL lock_timeout='300ms'")
  blocked <- suppressWarnings(try(
    execute(contender, "UPDATE public.person SET staged=staged WHERE id=$1", list(low)),
    silent = TRUE
  ))
  suppressWarnings(try(DBI::dbRollback(contender), silent = TRUE))
  DBI::dbRollback(holder)
  if (!inherits(blocked, "try-error") ||
      !grepl("canceling statement due to lock timeout", as.character(blocked), fixed = TRUE, useBytes = TRUE)) {
    stop("IDENTITY_LOCK_HELPER_DID_NOT_LOCK_DEDUPED_LOW_ENDPOINT", call. = FALSE)
  }
}

identity_first_schedule <- function(writer, left, right) {
  seed_people(c(left, right))
  holder <- connect()
  contender <- connect()
  on.exit(try(DBI::dbDisconnect(holder), silent = TRUE), add = TRUE)
  on.exit(try(DBI::dbDisconnect(contender), silent = TRUE), add = TRUE)
  DBI::dbBegin(holder)
  set_writer_context(holder)
  call_identity(holder, writer, left, right)

  DBI::dbBegin(contender)
  set_actor(contender)
  execute(contender, "SET LOCAL lock_timeout='300ms'")
  blocked <- suppressWarnings(try(
    query(contender, "SELECT public.red_slet_person($1)", list(left)),
    silent = TRUE
  ))
  suppressWarnings(try(DBI::dbRollback(contender), silent = TRUE))
  DBI::dbRollback(holder)

  if (!inherits(blocked, "try-error") ||
      !grepl("canceling statement due to lock timeout", as.character(blocked), fixed = TRUE, useBytes = TRUE)) {
    stop(sprintf("IDENTITY_DELETE_DID_NOT_BLOCK_%s: %s", writer, paste(blocked, collapse = " ")), call. = FALSE)
  }
  remaining <- query(controller, "SELECT count(*) n FROM public.person WHERE id IN ($1,$2)", list(left, right))$n[[1L]]
  if (remaining != 2) stop(sprintf("IDENTITY_DELETE_PASSED_%s", writer), call. = FALSE)
}

top_level_identity_first_schedule <- function(left, right) {
  seed_people(c(left, right))
  holder <- connect()
  contender <- connect()
  on.exit(try(DBI::dbDisconnect(holder), silent = TRUE), add = TRUE)
  on.exit(try(DBI::dbDisconnect(contender), silent = TRUE), add = TRUE)
  DBI::dbBegin(holder)
  set_actor(holder)
  query(holder, "SELECT set_config('app.change_set_id','',false)")
  call_identity(holder, "samme_som", left, right)
  allocated <- query(holder, paste0(
    "SELECT nullif(current_setting('app.change_set_id',true),'')::bigint value"
  ))$value[[1L]]

  DBI::dbBegin(contender)
  set_actor(contender)
  query(contender, "SELECT set_config('app.change_set_id','',false)")
  execute(contender, "SET LOCAL lock_timeout='300ms'")
  blocked <- suppressWarnings(try(
    query(contender, "SELECT public.red_slet_person($1)", list(left)),
    silent = TRUE
  ))
  suppressWarnings(try(DBI::dbRollback(contender), silent = TRUE))
  DBI::dbRollback(holder)

  if (is.na(allocated) || allocated == writer_change_set) {
    stop("IDENTITY_TOP_LEVEL_WRITER_DID_NOT_ALLOCATE_CHANGE_SET", call. = FALSE)
  }
  if (!inherits(blocked, "try-error") ||
      !grepl("canceling statement due to lock timeout", as.character(blocked), fixed = TRUE, useBytes = TRUE)) {
    stop("IDENTITY_TOP_LEVEL_DELETE_DID_NOT_BLOCK", call. = FALSE)
  }
}

dblink_conninfo <- paste(
  paste0("dbname=", pg$PGDATABASE),
  paste0("host=", pg$PGHOST),
  paste0("port=", pg$PGPORT),
  paste0("user=", pg$PGUSER),
  if (nzchar(pg$PGPASSWORD)) paste0("password=", pg$PGPASSWORD) else NULL
)

dblink_scalar <- function(name, column = "value bigint") {
  query(controller, sprintf(
    "SELECT * FROM extensions.dblink_get_result('%s',true) AS t(%s)", name, column
  ))
}

wait_until_remote_blocks <- function(pid, label) {
  deadline <- Sys.time() + 5
  repeat {
    state <- query(controller, paste0(
      "SELECT wait_event_type,state FROM pg_stat_activity WHERE pid=$1"
    ), list(pid))
    if (nrow(state) == 1L && identical(state$wait_event_type[[1L]], "Lock")) return(invisible(TRUE))
    if (Sys.time() >= deadline) stop(paste0("IDENTITY_REMOTE_WRITER_NOT_BLOCKED_", label), call. = FALSE)
    Sys.sleep(0.01)
  }
}

wait_until_remote_finishes <- function(name, label) {
  deadline <- Sys.time() + 8
  repeat {
    busy <- query(controller, "SELECT extensions.dblink_is_busy($1) busy", list(name))$busy[[1L]]
    if (busy == 0) return(invisible(TRUE))
    if (Sys.time() >= deadline) stop(paste0("IDENTITY_REMOTE_WRITER_DID_NOT_FINISH_", label), call. = FALSE)
    Sys.sleep(0.01)
  }
}

reverse_schedule <- function(writer, left, right, connection_name) {
  seed_people(c(left, right))
  deleter <- connect()
  on.exit(try(DBI::dbDisconnect(deleter), silent = TRUE), add = TRUE)
  DBI::dbBegin(deleter)
  set_actor(deleter)
  query(deleter, "SELECT public.red_slet_person($1)", list(left))

  query(controller, "SELECT extensions.dblink_connect($1,$2)", list(connection_name, dblink_conninfo))
  connected <- TRUE
  on.exit({
    if (connected) {
      try(query(controller, "SELECT extensions.dblink_exec($1,'ROLLBACK')", list(connection_name)), silent = TRUE)
      try(query(controller, "SELECT extensions.dblink_disconnect($1)", list(connection_name)), silent = TRUE)
    }
  }, add = TRUE)
  query(controller, "SELECT extensions.dblink_exec($1,'BEGIN')", list(connection_name))
  query(controller, "SELECT extensions.dblink_exec($1,$2)", list(
    connection_name, paste0("SET request.jwt.claim.sub = '", actor, "'")
  ))
  query(controller, "SELECT extensions.dblink_exec($1,$2)", list(
    connection_name, paste0("SET app.change_set_id = '", writer_change_set, "'")
  ))
  query(controller, "SELECT extensions.dblink_exec($1,'SET app.change_seq = ''0''')", list(connection_name))
  remote_pid <- query(controller, paste0(
    "SELECT pid FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)"
  ), list(connection_name))$pid[[1L]]
  remote_sql <- if (identical(writer, "samme_som")) {
    sprintf("SELECT public.red_samme_som(%s,%s)", left, right)
  } else {
    sprintf("SELECT public.red_ikke_samme_som(%s,%s)", left, right)
  }
  sent <- query(controller, "SELECT extensions.dblink_send_query($1,$2) sent", list(connection_name, remote_sql))$sent[[1L]]
  if (sent != 1) stop(paste0("IDENTITY_DBLINK_SEND_FAILED_", writer), call. = FALSE)
  wait_until_remote_blocks(remote_pid, writer)

  DBI::dbCommit(deleter)
  result <- try(dblink_scalar(connection_name), silent = TRUE)
  try(dblink_scalar(connection_name), silent = TRUE)
  query(controller, "SELECT extensions.dblink_exec($1,'ROLLBACK')", list(connection_name))
  query(controller, "SELECT extensions.dblink_disconnect($1)", list(connection_name))
  connected <- FALSE

  orphan_count <- query(controller, paste0(
    "SELECT count(*) n FROM public.relation r ",
    "WHERE r.rolle IN ('samme_som','ikke_samme_som') ",
    "AND ((r.subjekt_type='person' AND NOT EXISTS ",
    "      (SELECT 1 FROM public.person p WHERE p.id=r.subjekt_id)) ",
    "  OR (r.objekt_type='person' AND NOT EXISTS ",
    "      (SELECT 1 FROM public.person p WHERE p.id=r.objekt_id)))"
  ))$n[[1L]]
  list(result = result, orphan_count = orphan_count)
}

undo_delete_schedule <- function(left, original_right, replacement_right) {
  seed_people(c(left, original_right, replacement_right))
  assertion_id <- -1939503998
  DBI::dbBegin(controller)
  set_actor(controller)
  query(controller, "SELECT set_config('app.change_set_id','',true)")
  relation_id <- query(
    controller, "SELECT public.red_ikke_samme_som($1,$2) value", list(left, original_right)
  )$value[[1L]]
  query(controller, "SELECT set_config('app.change_set_id','',true)")
  query(controller, "SELECT public.red_fjern_ikke_samme_som($1)", list(relation_id))
  removal_change_set <- query(controller, paste0(
    "SELECT nullif(current_setting('app.change_set_id',true),'')::bigint value"
  ))$value[[1L]]
  query(controller, "SELECT set_config('app.change_set_id','',true)")
  execute(controller, paste0(
    "INSERT INTO public.relation(id,subjekt_type,subjekt_id,rolle,objekt_type,objekt_id) ",
    "VALUES($1,'person',$2,'ikke_samme_som','person',$3)"
  ), list(relation_id, left, replacement_right))
  execute(controller, paste0(
    "INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst) ",
    "VALUES($1,'relation',$2,'replacement assertion')"
  ), list(assertion_id, relation_id))
  DBI::dbCommit(controller)

  blocker <- connect()
  on.exit(try(DBI::dbDisconnect(blocker), silent = TRUE), add = TRUE)
  DBI::dbBegin(blocker)
  query(blocker, "SELECT id FROM public.assertion WHERE id=$1 FOR UPDATE", list(assertion_id))

  deleter_name <- "identity_undo_delete"
  undo_name <- "identity_undo_restore"
  for (name in c(deleter_name, undo_name)) {
    query(controller, "SELECT extensions.dblink_connect($1,$2)", list(name, dblink_conninfo))
  }
  connected <- c(deleter_name, undo_name)
  on.exit({
    for (name in connected) {
      try(query(controller, "SELECT extensions.dblink_exec($1,'ROLLBACK')", list(name)), silent = TRUE)
      try(query(controller, "SELECT extensions.dblink_disconnect($1)", list(name)), silent = TRUE)
    }
  }, add = TRUE)
  for (name in connected) {
    query(controller, "SELECT extensions.dblink_exec($1,'BEGIN')", list(name))
    query(controller, "SELECT extensions.dblink_exec($1,$2)", list(
      name, paste0("SET request.jwt.claim.sub = '", actor, "'")
    ))
    query(controller, "SELECT extensions.dblink_exec($1,'SET statement_timeout = ''7s''')", list(name))
  }
  query(controller, "SELECT extensions.dblink_exec($1,$2)", list(
    deleter_name, paste0("SET app.change_set_id = '", writer_change_set, "'")
  ))
  query(controller, "SELECT extensions.dblink_exec($1,'SET app.change_seq = ''0''')", list(deleter_name))
  deleter_pid <- query(controller, paste0(
    "SELECT pid FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)"
  ), list(deleter_name))$pid[[1L]]
  undo_pid <- query(controller, paste0(
    "SELECT pid FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)"
  ), list(undo_name))$pid[[1L]]

  sent <- query(controller, "SELECT extensions.dblink_send_query($1,$2) sent", list(
    deleter_name, sprintf("SELECT public.red_slet_person(%s)::text", left)
  ))$sent[[1L]]
  if (sent != 1) stop("IDENTITY_UNDO_DELETE_SEND_FAILED", call. = FALSE)
  wait_until_remote_blocks(deleter_pid, "undo_delete_assertion")

  sent <- query(controller, "SELECT extensions.dblink_send_query($1,$2) sent", list(
    undo_name, sprintf("SELECT public.red_fortryd_change_set(%s,true)::text", removal_change_set)
  ))$sent[[1L]]
  if (sent != 1) stop("IDENTITY_UNDO_RESTORE_SEND_FAILED", call. = FALSE)
  wait_until_remote_blocks(undo_pid, "undo_restore_identity_lock")
  DBI::dbCommit(blocker)

  wait_until_remote_finishes(deleter_name, "undo_delete")
  delete_result <- try(dblink_scalar(deleter_name, "value text"), silent = TRUE)
  try(dblink_scalar(deleter_name, "value text"), silent = TRUE)
  query(controller, "SELECT extensions.dblink_exec($1,$2)", list(
    deleter_name, if (inherits(delete_result, "try-error")) "ROLLBACK" else "COMMIT"
  ))
  wait_until_remote_finishes(undo_name, "undo_restore")
  undo_result <- try(dblink_scalar(undo_name, "value text"), silent = TRUE)
  try(dblink_scalar(undo_name, "value text"), silent = TRUE)
  query(controller, "SELECT extensions.dblink_exec($1,$2)", list(
    undo_name, if (inherits(undo_result, "try-error")) "ROLLBACK" else "COMMIT"
  ))
  for (name in connected) query(controller, "SELECT extensions.dblink_disconnect($1)", list(name))
  connected <- character()

  orphan_count <- query(controller, paste0(
    "SELECT count(*) n FROM public.relation r ",
    "WHERE r.rolle IN ('samme_som','ikke_samme_som') ",
    "AND ((r.subjekt_type='person' AND NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=r.subjekt_id)) ",
    "OR (r.objekt_type='person' AND NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=r.objekt_id)))"
  ))$n[[1L]]
  list(delete_result = delete_result, undo_result = undo_result, orphan_count = orphan_count)
}

helper_lock_schedule(-1939503099, -1939503100)
identity_first_schedule("ikke_samme_som", -1939503101, -1939503102)
identity_first_schedule("samme_som", -1939503103, -1939503104)
top_level_identity_first_schedule(-1939503109, -1939503110)

reverse_same <- reverse_schedule("samme_som", -1939503105, -1939503106, "identity_reverse_same")
reverse_different <- reverse_schedule("ikke_samme_som", -1939503107, -1939503108, "identity_reverse_different")
undo_delete <- undo_delete_schedule(-1939503111, -1939503112, -1939503113)

failures <- character()
reverse_results <- list(samme_som = reverse_same, ikke_samme_som = reverse_different)
for (writer in names(reverse_results)) {
  entry <- reverse_results[[writer]]
  if (!inherits(entry$result, "try-error") ||
      !grepl("IDENTITY_PERSON_NOT_FOUND", as.character(entry$result), fixed = TRUE, useBytes = TRUE)) {
    failures <- c(failures, sprintf(
      "IDENTITY_WRITER_DID_NOT_FAIL_NOT_FOUND_%s: %s",
      writer, paste(entry$result, collapse = " ")
    ))
  }
  if (entry$orphan_count != 0) {
    failures <- c(failures, sprintf("IDENTITY_ORPHAN_ENDPOINT_%s: %s", writer, entry$orphan_count))
  }
}

if (inherits(undo_delete$delete_result, "try-error")) {
  failures <- c(failures, paste0("IDENTITY_UNDO_DELETE_DID_NOT_COMPLETE: ", undo_delete$delete_result))
}
if (!inherits(undo_delete$undo_result, "try-error") ||
    !grepl("IDENTITY_PERSON_NOT_FOUND", as.character(undo_delete$undo_result), fixed = TRUE, useBytes = TRUE) ||
    grepl("deadlock detected", as.character(undo_delete$undo_result), fixed = TRUE, useBytes = TRUE)) {
  failures <- c(failures, paste0(
    "IDENTITY_UNDO_RESTORE_DID_NOT_FAIL_CLOSED_WITHOUT_DEADLOCK: ", undo_delete$undo_result
  ))
}
if (undo_delete$orphan_count != 0) {
  failures <- c(failures, paste0("IDENTITY_UNDO_DELETE_ORPHANS: ", undo_delete$orphan_count))
}

global_orphans <- query(controller, paste0(
  "SELECT count(*) n FROM public.relation r ",
  "WHERE r.rolle IN ('samme_som','ikke_samme_som') ",
  "AND ((r.subjekt_type='person' AND NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=r.subjekt_id)) ",
  "  OR (r.objekt_type='person' AND NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=r.objekt_id)))"
))$n[[1L]]
if (global_orphans != 0) failures <- c(failures, paste0("IDENTITY_GLOBAL_ORPHANS: ", global_orphans))

if (length(failures)) stop(paste(failures, collapse = "\n"), call. = FALSE)
cat("PASS C3 identity writers serialize with person deletion\n")
