required_pg <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
pg <- setNames(lapply(required_pg, function(x) Sys.getenv(x, unset = NA_character_)), required_pg)
if (any(vapply(pg, function(x) length(x) != 1L || is.na(x), logical(1))))
  stop("IDENTITY_MVCC_REQUIRES_ALL_FIVE_PG_VARIABLES", call. = FALSE)
if (!grepl("^daa1939_c3_identity_task2_", pg$PGDATABASE))
  stop("IDENTITY_MVCC_REQUIRES_NAMED_DISPOSABLE_DATABASE", call. = FALSE)

connect <- function() DBI::dbConnect(RPostgres::Postgres(), dbname=pg$PGDATABASE,
  host=pg$PGHOST, port=pg$PGPORT, user=pg$PGUSER, password=pg$PGPASSWORD)
q <- function(con, sql, params=list()) if (length(params)) DBI::dbGetQuery(con,sql,params=params) else DBI::dbGetQuery(con,sql)
x <- function(con, sql, params=list()) if (length(params)) DBI::dbExecute(con,sql,params=params) else DBI::dbExecute(con,sql)

actor <- "19390000-0000-4000-8000-000000000093"
controller_change_set <- -1939510999
winner_change_set <- -1939510998
stale_change_set <- -1939510997
controller <- connect(); winner <- connect()
on.exit(try(DBI::dbDisconnect(controller),silent=TRUE),add=TRUE)
on.exit(try(DBI::dbDisconnect(winner),silent=TRUE),add=TRUE)
x(controller,"CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions")
x(controller,"INSERT INTO auth.users(id,email) VALUES($1,'identity-mvcc@test.invalid') ON CONFLICT DO NOTHING",list(actor))
x(controller,"INSERT INTO public.profiles(id,email,rolle,navn) VALUES($1,'identity-mvcc@test.invalid','redaktion','Identity MVCC') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'",list(actor))
for (cs in c(controller_change_set,winner_change_set,stale_change_set))
  x(controller,"INSERT INTO public.change_set(id,actor_id,actor_navn,actor_rolle,operation,summary) VALUES($1,$2,'Identity MVCC','redaktion','test_context','Identity MVCC') ON CONFLICT DO NOTHING",list(cs,actor))
set_actor <- function(con, change_set=controller_change_set) {
  invisible(q(con,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor)))
  invisible(q(con,"SELECT set_config('app.change_set_id',$1,false)",list(as.character(change_set))))
  invisible(q(con,"SELECT set_config('app.change_seq','0',false)"))
}
set_actor(controller); set_actor(winner,winner_change_set)

conninfo <- paste(paste0("dbname=",pg$PGDATABASE),paste0("host=",pg$PGHOST),
  paste0("port=",pg$PGPORT),paste0("user=",pg$PGUSER),paste0("password=",pg$PGPASSWORD))
remote <- "identity_mvcc_stale"
q(controller,"SELECT extensions.dblink_connect($1,$2)",list(remote,conninfo))
on.exit({
  try(q(controller,"SELECT extensions.dblink_exec($1,'ROLLBACK')",list(remote)),silent=TRUE)
  try(q(controller,"SELECT extensions.dblink_disconnect($1)",list(remote)),silent=TRUE)
},add=TRUE)

remote_exec <- function(sql) q(controller,"SELECT extensions.dblink_exec($1,$2)",list(remote,sql))
remote_begin <- function(snapshot_sql) {
  remote_exec("ROLLBACK")
  remote_exec("BEGIN ISOLATION LEVEL REPEATABLE READ")
  remote_exec(paste0("SET request.jwt.claim.sub='",actor,"'"))
  remote_exec(paste0("SET app.change_set_id='",stale_change_set,"'"))
  remote_exec("SET app.change_seq='0'")
  remote_exec("SET statement_timeout='7s'")
  q(controller,"SELECT * FROM extensions.dblink($1,$2) AS t(n bigint)",list(remote,snapshot_sql))
}
remote_pid <- q(controller,"SELECT * FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)",list(remote))$pid[[1L]]
wait_blocked <- function() {
  deadline <- Sys.time()+5
  repeat {
    s <- q(controller,"SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1",list(remote_pid))
    if (nrow(s)==1L && identical(s$wait_event_type[[1L]],"Lock")) return(invisible())
    if (Sys.time()>=deadline) stop("IDENTITY_MVCC_STALE_WRITER_DID_NOT_WAIT",call.=FALSE)
    Sys.sleep(.01)
  }
}
finish_stale <- function(sql, require_wait=TRUE) {
  sent <- q(controller,"SELECT extensions.dblink_send_query($1,$2) sent",list(remote,sql))$sent[[1L]]
  if (sent != 1) stop("IDENTITY_MVCC_SEND_FAILED",call.=FALSE)
  if (require_wait) {
    wait_blocked()
  } else {
    deadline <- Sys.time()+2
    repeat {
      s <- q(controller,"SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1",list(remote_pid))
      busy <- q(controller,"SELECT extensions.dblink_is_busy($1) busy",list(remote))$busy[[1L]]
      if ((nrow(s)==1L && identical(s$wait_event_type[[1L]],"Lock")) || busy==0 || Sys.time()>=deadline) break
      Sys.sleep(.01)
    }
  }
  DBI::dbCommit(winner)
  result <- try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(remote)),silent=TRUE)
  try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(remote)),silent=TRUE)
  remote_exec("ROLLBACK")
  if (!inherits(result,"try-error") || !grepl("could not serialize access",as.character(result),fixed=TRUE))
    stop(paste("IDENTITY_MVCC_EXPECTED_40001",paste(result,collapse=" ")),call.=FALSE)
}

base <- -1939510000L
people <- base-(1:12)
people_sql <- paste(people,collapse=",")
x(controller,sprintf("DELETE FROM public.relation WHERE (subjekt_type='person' AND subjekt_id IN (%s)) OR (objekt_type='person' AND objekt_id IN (%s))",people_sql,people_sql))
x(controller,sprintf("DELETE FROM public.person WHERE id IN (%s)",people_sql))
for (id in people) x(controller,"INSERT INTO public.person(id,levende,koen) VALUES($1,false,'ukendt')",list(id))

# Top-level same-vs-different and duplicate-same schedules.
for (duplicate in c(FALSE,TRUE)) {
  a <- if (duplicate) people[3] else people[1]; b <- if (duplicate) people[4] else people[2]
  remote_begin("SELECT count(*)::bigint FROM public.relation")
  DBI::dbBegin(winner); set_actor(winner,winner_change_set)
  if (duplicate) q(winner,"SELECT public.red_samme_som($1,$2)",list(a,b)) else q(winner,"SELECT public.red_ikke_samme_som($1,$2)",list(a,b))
  finish_stale(sprintf("SELECT public.red_samme_som(%s,%s)::text",a,b))
}

# Raw INSERT must participate in the same generation guard.
a <- people[5]; b <- people[6]
remote_begin("SELECT count(*)::bigint FROM public.relation")
DBI::dbBegin(winner); set_actor(winner,winner_change_set); q(winner,"SELECT public.red_ikke_samme_som($1,$2)",list(a,b))
finish_stale(sprintf("INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES('person',%s,'person',%s,'samme_som') RETURNING id::text",a,b))

# A raw UPDATE through the mandatory exact prelock helper must fail on its stale snapshot.
a <- people[7]; b <- people[8]
ordinary <- q(controller,"INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES('person',$1,'person',$2,'bekendt_med') RETURNING id",list(a,b))$id[[1L]]
remote_begin("SELECT count(*)::bigint FROM public.relation")
DBI::dbBegin(winner); set_actor(winner,winner_change_set); q(winner,"SELECT public.red_samme_som($1,$2)",list(a,b))
target <- sprintf("jsonb_build_object('id',id,'rolle','ikke_samme_som','subjekt_type','person','subjekt_id',%s,'objekt_type','person','objekt_id',%s)",a,b)
finish_stale(sprintf("WITH r AS (SELECT to_jsonb(x) old_row,%s new_row FROM public.relation x WHERE id=%s), p AS (SELECT private.prelock_identity_relation_update(old_row,new_row) FROM r) UPDATE public.relation SET rolle='ikke_samme_som' FROM p WHERE id=%s RETURNING public.relation.id::text",target,ordinary,ordinary))

# Real undo/_version_upsert_row restore races a committed same_som write.
a <- people[9]; b <- people[10]
DBI::dbBegin(controller); set_actor(controller)
q(controller,"SELECT set_config('app.change_set_id','',true)")
rid <- q(controller,"SELECT public.red_ikke_samme_som($1,$2) id",list(a,b))$id[[1L]]
q(controller,"SELECT set_config('app.change_set_id','',true)")
q(controller,"SELECT public.red_fjern_ikke_samme_som($1)",list(rid))
undo_cs <- q(controller,"SELECT nullif(current_setting('app.change_set_id',true),'')::bigint::text id")$id[[1L]]
DBI::dbCommit(controller)
remote_begin("SELECT count(*)::bigint FROM public.relation")
DBI::dbBegin(winner); set_actor(winner,winner_change_set); q(winner,"SELECT public.red_samme_som($1,$2)",list(a,b))
finish_stale(sprintf("SELECT public.red_fortryd_change_set(%s,true)::text",undo_cs),require_wait=FALSE)

contradictions <- q(controller,"SELECT count(*) n FROM public.relation s JOIN public.relation d ON s.subjekt_id=d.subjekt_id AND s.objekt_id=d.objekt_id WHERE s.rolle='samme_som' AND d.rolle='ikke_samme_som'")$n[[1L]]
duplicates <- q(controller,"SELECT count(*) n FROM (SELECT subjekt_id,objekt_id,count(*) FROM public.relation WHERE rolle='samme_som' GROUP BY 1,2 HAVING count(*)>1) q")$n[[1L]]
if (contradictions != 0 || duplicates != 0) stop("IDENTITY_MVCC_INVALID_FINAL_GRAPH",call.=FALSE)
cat("PASS C3 identity RR stale predicates fail with 40001\n")
