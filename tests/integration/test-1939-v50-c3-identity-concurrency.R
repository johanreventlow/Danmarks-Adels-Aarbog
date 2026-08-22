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

helper_lock_schedule(-1939503099, -1939503100)
identity_first_schedule("ikke_samme_som", -1939503101, -1939503102)
identity_first_schedule("samme_som", -1939503103, -1939503104)

reverse_same <- reverse_schedule("samme_som", -1939503105, -1939503106, "identity_reverse_same")
reverse_different <- reverse_schedule("ikke_samme_som", -1939503107, -1939503108, "identity_reverse_different")

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

global_orphans <- query(controller, paste0(
  "SELECT count(*) n FROM public.relation r ",
  "WHERE r.rolle IN ('samme_som','ikke_samme_som') ",
  "AND ((r.subjekt_type='person' AND NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=r.subjekt_id)) ",
  "  OR (r.objekt_type='person' AND NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=r.objekt_id)))"
))$n[[1L]]
if (global_orphans != 0) failures <- c(failures, paste0("IDENTITY_GLOBAL_ORPHANS: ", global_orphans))

if (length(failures)) stop(paste(failures, collapse = "\n"), call. = FALSE)
cat("PASS C3 identity writers serialize with person deletion\n")
