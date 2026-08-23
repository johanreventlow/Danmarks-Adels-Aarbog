# Fund H4 (Task 9, Step 0): load_daa.R and post_load_fixup.R must take the SAME
# global production-writer advisory lock that Task 6/7's C3 apply/reversal RPCs
# take as their FIRST lock -- otherwise a production import can overlap a C3
# apply or reversal. The lock must come BEFORE samme_som_mutation and BEFORE any
# table lock, i.e. the exact order the RPCs use; an inversion trades one race for
# a deadlock.
#
# This test does three things, in this order:
#   1. SOURCE CONTRACT  -- reads both R scripts and asserts the statement order.
#   2. MUTUAL EXCLUSION -- real two-session runs against a real database, in BOTH
#      start orders, for BOTH scripts, against BOTH apply and reversal.
#      The script side executes the statements EXTRACTED FROM THE SCRIPT SOURCE,
#      not a hand-written copy, so a drifted lock key fails here too.
#   3. POWER CONTROL    -- the same scenario with the writer-lock statement
#      REMOVED from the extracted sequence (i.e. the pre-fix shape) must show the
#      two overlapping. This is the RED proof, kept permanently: it shows that
#      step 2's blocking comes from the writer lock and from nothing else.
#
# No assertion raises immediately: every failure is collected so one run reports
# every overlap, and so a pre-fix run still produces the full empirical evidence.
#
# The C3 side runs the REAL deployed RPCs. With an authorization id that cannot
# validate, the RPC's only observable database interaction before it raises is
# the writer advisory lock (step 1 precedes the role gate at step 2 and the
# authorization SELECT ... FOR UPDATE at step 2.5), which isolates exactly the
# property under test without rebuilding the manifest/approval chain.
#
# Run from the repository root against a disposable local database only:
#   PGDATABASE=daa1939_... PGHOST=/tmp PGPORT=5432 PGUSER=$USER PGPASSWORD= \
#     Rscript tests/integration/test-1939-v50-c3-writer-lock-order.R

required_pg <- c("PGDATABASE","PGHOST","PGPORT","PGUSER","PGPASSWORD")
pg <- setNames(lapply(required_pg,function(k) Sys.getenv(k,unset=NA_character_)),required_pg)
if (any(vapply(pg,function(v) length(v)!=1L || is.na(v),logical(1))))
  stop("C3_WRITER_LOCK_REQUIRES_ALL_FIVE_PG_VARIABLES",call.=FALSE)
if (!grepl("^daa1939_",pg$PGDATABASE))
  stop("C3_WRITER_LOCK_REQUIRES_NAMED_DISPOSABLE_DATABASE",call.=FALSE)

WRITER_LOCK_SQL <- "SELECT pg_advisory_xact_lock(hashtextextended('daa-1939-v50-production-writer',0))"
scripts <- ".claude/skills/daa-extract/scripts"
failures <- character(0)
note_failure <- function(tag) failures[[length(failures)+1L]] <<- tag

# ---- source extraction --------------------------------------------------------
# The point of extracting rather than transcribing: the sequence executed below
# is the sequence the production scripts execute. A changed key, a dropped
# statement or a reordered one changes this test's behaviour, not just its
# source assertions.
sql_literal <- function(line,tag) {
  m <- regmatches(line,regexpr('"[^"]*"',line))
  if (length(m)!=1L) stop(paste0("C3_WRITER_LOCK_SQL_LITERAL_UNREADABLE_",tag),call.=FALSE)
  substr(m,2L,nchar(m)-1L)
}
first_or_na <- function(idx) if (length(idx)) idx[[1L]] else NA_integer_
# Pure comment lines are not statements: the scripts explain their lock order in
# prose right above it, and that prose must not read as a lock being taken.
code_only <- function(v) v[!grepl("^\\s*#",v)]

loader_src <- readLines(file.path(scripts,"load_daa.R"),warn=FALSE)
l_begin  <- first_or_na(grep("^dbBegin\\(con\\)$",loader_src))
l_writer <- first_or_na(grep("pg_advisory_xact_lock\\(hashtextextended\\(",loader_src))
l_table  <- first_or_na(grep("LOCK TABLE \", paste\\(id_tables",loader_src))
if (is.na(l_begin) || is.na(l_table)) stop("C3_WRITER_LOCK_LOADER_SOURCE_SHAPE_CHANGED",call.=FALSE)
if (is.na(l_writer)) {
  note_failure("C3_LOADER_MISSING_GLOBAL_WRITER_LOCK")
} else {
  if (!(l_begin < l_writer && l_writer < l_table)) note_failure("C3_LOADER_WRITER_LOCK_ORDER_INVERTED")
  if (!identical(sql_literal(loader_src[[l_writer]],"loader"),WRITER_LOCK_SQL))
    note_failure("C3_LOADER_WRITER_LOCK_STATEMENT_DRIFT")
  # nothing may take a lock between the transaction start and the writer lock
  if (l_writer > l_begin+1L &&
      any(grepl("LOCK TABLE|advisory|FOR UPDATE|FOR SHARE",code_only(loader_src[(l_begin+1L):(l_writer-1L)]))))
    note_failure("C3_LOADER_LOCK_BEFORE_WRITER_LOCK")
}
# id_tables is a literal vector in the source; evaluating it keeps the table list
# and its canonical order bound to the loader rather than duplicated here.
it_start <- first_or_na(grep("^id_tables <- c\\(",loader_src))
if (is.na(it_start)) stop("C3_WRITER_LOCK_LOADER_ID_TABLES_UNREADABLE",call.=FALSE)
it_end <- it_start; while (!grepl("\\)\\s*$",loader_src[[it_end]])) it_end <- it_end + 1L
id_tables <- local(eval(parse(text=paste(loader_src[it_start:it_end],collapse="\n"))))
loader_sequence <- c(
  if (!is.na(l_writer)) sql_literal(loader_src[[l_writer]],"loader"),
  paste0("LOCK TABLE ",paste(id_tables,collapse=", ")," IN EXCLUSIVE MODE"))

post_src <- readLines(file.path(scripts,"post_load_fixup.R"),warn=FALSE)
p_begin  <- first_or_na(grep("^dbBegin\\(con\\)$",post_src))
p_writer <- first_or_na(grep("pg_advisory_xact_lock\\(hashtextextended\\(",post_src))
p_samme  <- first_or_na(grep("pg_advisory_xact_lock\\(hashtext\\('samme_som_mutation'\\)",post_src))
p_guard  <- first_or_na(grep("guard_identity_mutation_snapshot",post_src))
p_table  <- first_or_na(grep("LOCK TABLE lineage",post_src))
if (is.na(p_begin) || is.na(p_samme) || is.na(p_guard) || is.na(p_table))
  stop("C3_WRITER_LOCK_POST_LOAD_SOURCE_SHAPE_CHANGED",call.=FALSE)
if (!(p_begin < p_samme && p_samme < p_guard && p_guard < p_table))
  note_failure("C3_POST_LOAD_IDENTITY_LOCK_ORDER_INVERTED")
if (is.na(p_writer)) {
  note_failure("C3_POST_LOAD_MISSING_GLOBAL_WRITER_LOCK")
} else {
  if (!(p_begin < p_writer && p_writer < p_samme)) note_failure("C3_POST_LOAD_WRITER_LOCK_ORDER_INVERTED")
  if (!identical(sql_literal(post_src[[p_writer]],"post_load"),WRITER_LOCK_SQL))
    note_failure("C3_POST_LOAD_WRITER_LOCK_STATEMENT_DRIFT")
  if (p_writer > p_begin+1L &&
      any(grepl("LOCK TABLE|advisory|FOR UPDATE|FOR SHARE",code_only(post_src[(p_begin+1L):(p_writer-1L)]))))
    note_failure("C3_POST_LOAD_LOCK_BEFORE_WRITER_LOCK")
}
post_sequence <- c(
  if (!is.na(p_writer)) sql_literal(post_src[[p_writer]],"post_load"),
  sql_literal(post_src[[p_samme]],"post_load_samme_som"),
  sql_literal(post_src[[p_guard]],"post_load_guard"),
  sql_literal(post_src[[p_table]],"post_load_tables"))

# ---- connections and fixtures -------------------------------------------------
connect <- function() DBI::dbConnect(RPostgres::Postgres(),dbname=pg$PGDATABASE,
  host=pg$PGHOST,port=pg$PGPORT,user=pg$PGUSER,password=pg$PGPASSWORD,bigint="integer")
q <- function(c,s,p=list()) if (length(p)) DBI::dbGetQuery(c,s,params=p) else DBI::dbGetQuery(c,s)
x <- function(c,s,p=list()) invisible(if (length(p)) DBI::dbExecute(c,s,params=p) else DBI::dbExecute(c,s))

actor   <- "19390000-0000-4000-8000-000000000095"
auth_id <- "19390000-0000-4000-8000-0000000000a5"
controller <- connect(); holder <- connect(); blocker <- connect()
on.exit(try(DBI::dbDisconnect(controller),silent=TRUE),add=TRUE)
on.exit(try(DBI::dbDisconnect(holder),silent=TRUE),add=TRUE)
on.exit(try(DBI::dbDisconnect(blocker),silent=TRUE),add=TRUE)
x(controller,"CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions")
x(controller,"INSERT INTO auth.users(id,email) VALUES($1,'c3-writer-lock@test.invalid') ON CONFLICT DO NOTHING",list(actor))
x(controller,"INSERT INTO public.profiles(id,email,rolle) VALUES($1,'c3-writer-lock@test.invalid','redaktion') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'",list(actor))
x(controller,"INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'Danmarks Adels Aarbog','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING")
# An authorization row that exists but can never validate: the RPCs reach it only
# after taking the writer lock, and every call below fails on it by design.
x(controller,"DELETE FROM private.reimport_case_authorization WHERE id=$1",list(auth_id))
x(controller,"INSERT INTO private.reimport_case_authorization
   (id,source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,decisions_sha256,
    state_sha256,text_bundle_sha256,database_name,system_identifier,expected_counts,authorized_elements,
    principal_id,nonce,expires_at)
   VALUES ($1,3,'c3','apply',repeat('0',64),repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),
    repeat('5',64),current_database(),'0','{}'::jsonb,'{}'::jsonb,$2,gen_random_uuid(),
    clock_timestamp()+interval '1 hour')",list(auth_id,actor))
cleanup <- function() {
  try(x(controller,"DELETE FROM private.reimport_case_authorization WHERE id=$1",list(auth_id)),silent=TRUE)
  try(x(controller,"DELETE FROM public.profiles WHERE id=$1",list(actor)),silent=TRUE)
  try(x(controller,"DELETE FROM auth.users WHERE id=$1",list(actor)),silent=TRUE)
}
on.exit(cleanup(),add=TRUE)

# The writer lock's pg_locks identity, measured rather than computed: taking the
# lock here and reading our own row avoids reimplementing hashtextextended's
# 64-bit split, and lets every assertion below compare waiter against holder.
DBI::dbBegin(controller); invisible(q(controller,WRITER_LOCK_SQL))
key <- q(controller,"SELECT classid,objid,objsubid FROM pg_locks
                      WHERE locktype='advisory' AND pid=pg_backend_pid() AND granted")
DBI::dbRollback(controller)
if (nrow(key)!=1L) stop("C3_WRITER_LOCK_IDENTITY_UNREADABLE",call.=FALSE)

conninfo <- paste(paste0("dbname=",pg$PGDATABASE),paste0("host=",pg$PGHOST),
                  paste0("port=",pg$PGPORT),paste0("user=",pg$PGUSER),paste0("password=",pg$PGPASSWORD))
remotes <- c(c3="c3_writer_lock_rpc",script="c3_writer_lock_script")
for (n in remotes) invisible(q(controller,"SELECT extensions.dblink_connect($1,$2)",list(n,conninfo)))
on.exit(for (n in remotes) {
  try(q(controller,"SELECT extensions.dblink_exec($1,'ROLLBACK')",list(n)),silent=TRUE)
  try(q(controller,"SELECT extensions.dblink_disconnect($1)",list(n)),silent=TRUE)
},add=TRUE)
rexec <- function(n,s) invisible(q(controller,"SELECT extensions.dblink_exec($1,$2)",list(n,s)))
send  <- function(n,s) if (q(controller,"SELECT extensions.dblink_send_query($1,$2) sent",list(n,s))$sent[[1L]]!=1L)
  stop("C3_WRITER_LOCK_SEND_FAILED",call.=FALSE)
pid <- vapply(remotes,function(n)
  q(controller,"SELECT * FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)",list(n))$pid[[1L]],
  integer(1))
begin_remote <- function(n,timeout="20s") {
  rexec(n,"ROLLBACK"); rexec(n,"BEGIN")
  rexec(n,paste0("SET LOCAL request.jwt.claim.sub='",actor,"'"))
  rexec(n,paste0("SET LOCAL statement_timeout='",timeout,"'"))
  rexec(n,"SET LOCAL app.change_set_id TO ''")
}
finish <- function(n,deadline_s=25) {
  deadline <- Sys.time()+deadline_s
  repeat {
    if (q(controller,"SELECT extensions.dblink_is_busy($1) busy",list(n))$busy[[1L]]==0L) break
    if (Sys.time()>=deadline) stop(paste0("C3_WRITER_LOCK_REMOTE_TIMEOUT_",n),call.=FALSE)
    Sys.sleep(.01)
  }
  r <- suppressWarnings(try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(n)),silent=TRUE))
  suppressWarnings(try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(n)),silent=TRUE))
  rexec(n,"ROLLBACK")   # this test never commits anything
  r
}
advisory_rows <- function(p,granted) q(controller,
  "SELECT count(*)::integer n FROM pg_locks WHERE pid=$1 AND locktype='advisory'
    AND classid=$2 AND objid=$3 AND objsubid=$4 AND granted=$5",
  list(p,key$classid[[1L]],key$objid[[1L]],key$objsubid[[1L]],granted))$n[[1L]]
holds_writer <- function(p) advisory_rows(p,TRUE)==1L
waits_writer <- function(p) advisory_rows(p,FALSE)==1L
is_blocked   <- function(p) { s <- q(controller,"SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1",list(p))
  nrow(s)==1L && identical(s$wait_event_type[[1L]],"Lock") }
table_locks  <- function(p) q(controller,
  "SELECT count(*)::integer n FROM pg_locks WHERE pid=$1 AND locktype='relation' AND mode='ExclusiveLock'",list(p))$n[[1L]]
wait_until <- function(pred,tag,timeout_s=4) {
  deadline <- Sys.time()+timeout_s
  repeat { if (isTRUE(pred())) return(invisible(TRUE))
           if (Sys.time()>=deadline) stop(tag,call.=FALSE); Sys.sleep(.01) }
}
sql_quote <- function(s) paste0("'",gsub("'","''",s,fixed=TRUE),"'")
install_prologue <- function(n,seq) rexec(n,paste0(
  "CREATE OR REPLACE FUNCTION pg_temp.c3_script_prologue() RETURNS text LANGUAGE plpgsql AS $daa$ ",
  "DECLARE s text; BEGIN FOREACH s IN ARRAY ARRAY[",paste(vapply(seq,sql_quote,character(1)),collapse=","),
  "]::text[] LOOP EXECUTE s; END LOOP; RETURN 'ok'; END $daa$"))

rpc_sql <- list(
  apply    = sprintf("SELECT public.red_apply_reimport_cases('%s'::uuid,repeat('a',64),repeat('b',64))::text",auth_id),
  reversal = sprintf("SELECT public.red_reverse_reimport_cases('%s'::uuid,gen_random_uuid())::text",auth_id))
expect_authorization_error <- function(r,tag) {
  txt <- as.character(r)
  if (grepl("lock timeout",txt,fixed=TRUE) || grepl("55P03",txt,fixed=TRUE))
    stop(paste0("C3_RPC_DIED_ON_LOCK_TIMEOUT_",tag),call.=FALSE)
  if (grepl("deadlock detected",txt,fixed=TRUE)) stop(paste0("C3_RPC_DEADLOCK_",tag),call.=FALSE)
  if (!inherits(r,"try-error") || !grepl("REIMPORT_CASE_AUTHORIZATION_INVALID",txt,fixed=TRUE))
    stop(paste0("C3_RPC_UNEXPECTED_OUTCOME_",tag,": ",substr(txt,1,240)),call.=FALSE)
}

# Every scenario runs even if an earlier one failed: one run, one full picture.
scenario <- function(tag,expr) {
  err <- tryCatch({force(expr); NULL},error=function(e) conditionMessage(e))
  try(DBI::dbRollback(holder),silent=TRUE)
  try(DBI::dbRollback(blocker),silent=TRUE)
  for (n in remotes) { try(finish(n,deadline_s=25),silent=TRUE); try(rexec(n,"ROLLBACK"),silent=TRUE) }
  if (!is.null(err)) { note_failure(err); cat("FAIL ",tag,": ",err,"\n",sep="") } else cat("ok   ",tag,"\n",sep="")
}

# ---- scenario 1: script holds first, the C3 RPC must wait ---------------------
script_first <- function(seq,rpc,tag) {
  DBI::dbBegin(holder); for (s in seq) invisible(q(holder,s))
  begin_remote(remotes[["c3"]])
  send(remotes[["c3"]],rpc_sql[[rpc]])
  wait_until(function() waits_writer(pid[["c3"]]),paste0("C3_RPC_DID_NOT_BLOCK_ON_WRITER_LOCK_",tag))
  DBI::dbRollback(holder)
  expect_authorization_error(finish(remotes[["c3"]]),tag)
}

# ---- scenario 2: the C3 RPC holds first, the script must wait -----------------
# The RPC is parked mid-transaction -- past the writer lock, blocked on the
# authorization row -- so the script meets a genuinely held C3 lock.
c3_first <- function(seq,rpc,tag) {
  DBI::dbBegin(blocker)
  invisible(q(blocker,"SELECT id FROM private.reimport_case_authorization WHERE id=$1 FOR UPDATE",list(auth_id)))
  begin_remote(remotes[["c3"]])
  send(remotes[["c3"]],rpc_sql[[rpc]])
  wait_until(function() holds_writer(pid[["c3"]]) && is_blocked(pid[["c3"]]),
             paste0("C3_RPC_DID_NOT_HOLD_WRITER_LOCK_",tag))
  install_prologue(remotes[["script"]],seq)
  begin_remote(remotes[["script"]])
  send(remotes[["script"]],"SELECT pg_temp.c3_script_prologue()")
  wait_until(function() waits_writer(pid[["script"]]),paste0("SCRIPT_DID_NOT_BLOCK_ON_WRITER_LOCK_",tag))
  # The script must block BEFORE it holds any table lock -- that is what keeps
  # this a wait instead of a deadlock.
  if (table_locks(pid[["script"]])!=0L) stop(paste0("SCRIPT_HELD_TABLE_LOCK_WHILE_WAITING_",tag),call.=FALSE)
  DBI::dbCommit(blocker)
  expect_authorization_error(finish(remotes[["c3"]]),tag)
  r <- finish(remotes[["script"]])
  if (inherits(r,"try-error") || nrow(r)!=1L || !identical(r$value[[1L]],"ok"))
    stop(paste0("SCRIPT_PROLOGUE_DID_NOT_COMPLETE_",tag,": ",substr(as.character(r),1,240)),call.=FALSE)
}

# ---- scenario 3: power control -- without the writer lock they overlap --------
overlap_without_writer_lock <- function(seq,rpc,tag) {
  legacy <- setdiff(seq,WRITER_LOCK_SQL)
  if (length(legacy)==length(seq)) stop(paste0("POWER_CONTROL_SEQUENCE_HAD_NO_WRITER_LOCK_",tag),call.=FALSE)
  DBI::dbBegin(holder); for (s in legacy) invisible(q(holder,s))
  begin_remote(remotes[["c3"]])
  send(remotes[["c3"]],rpc_sql[[rpc]])
  r <- finish(remotes[["c3"]],deadline_s=8)
  blocked_on_writer <- waits_writer(pid[["c3"]])
  DBI::dbRollback(holder)
  if (blocked_on_writer) stop(paste0("POWER_CONTROL_UNEXPECTEDLY_BLOCKED_",tag),call.=FALSE)
  expect_authorization_error(r,paste0("power_control_",tag))
}

for (rpc in c("apply","reversal")) {
  scenario(paste0("loader holds first, ",rpc," waits"),
           script_first(loader_sequence,rpc,paste0("loader_first_",rpc)))
  scenario(paste0("post_load holds first, ",rpc," waits"),
           script_first(post_sequence,rpc,paste0("post_load_first_",rpc)))
  scenario(paste0(rpc," holds first, loader waits"),
           c3_first(loader_sequence,rpc,paste0("c3_first_loader_",rpc)))
  scenario(paste0(rpc," holds first, post_load waits"),
           c3_first(post_sequence,rpc,paste0("c3_first_post_load_",rpc)))
}
if (!is.na(l_writer) && !is.na(p_writer)) {
  for (rpc in c("apply","reversal")) {
    scenario(paste0("power control: loader without writer lock overlaps ",rpc),
             overlap_without_writer_lock(loader_sequence,rpc,paste0("loader_",rpc)))
    scenario(paste0("power control: post_load without writer lock overlaps ",rpc),
             overlap_without_writer_lock(post_sequence,rpc,paste0("post_load_",rpc)))
  }
} else cat("skip  power control (no writer lock in source yet)\n")
if (length(failures))
  stop(paste0("C3_WRITER_LOCK_ORDER_FAILED (",length(failures),"): ",paste(failures,collapse=" | ")),call.=FALSE)
cat("PASS load_daa.R, post_load_fixup.R and the C3 apply/reversal RPCs share one global writer lock\n")
