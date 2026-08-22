required_pg <- c("PGDATABASE","PGHOST","PGPORT","PGUSER","PGPASSWORD")
pg <- setNames(lapply(required_pg,function(k) Sys.getenv(k,unset=NA_character_)),required_pg)
if (any(vapply(pg,function(v) length(v)!=1L || is.na(v),logical(1))))
  stop("POST_LOAD_LOCK_ORDER_REQUIRES_ALL_FIVE_PG_VARIABLES",call.=FALSE)
if (!grepl("^daa1939_c3_identity_task2_",pg$PGDATABASE))
  stop("POST_LOAD_LOCK_ORDER_REQUIRES_NAMED_DISPOSABLE_DATABASE",call.=FALSE)

script <- readLines(".claude/skills/daa-extract/scripts/post_load_fixup.R",warn=FALSE)
advisory_line <- grep("pg_advisory_xact_lock\\(hashtext",script)[1]
table_line <- grep("LOCK TABLE lineage, relation",script)[1]
if (is.na(advisory_line) || is.na(table_line) || advisory_line >= table_line)
  stop("POST_LOAD_SOURCE_LOCK_ORDER_INVERTED",call.=FALSE)

connect <- function() DBI::dbConnect(RPostgres::Postgres(),dbname=pg$PGDATABASE,
  host=pg$PGHOST,port=pg$PGPORT,user=pg$PGUSER,password=pg$PGPASSWORD)
q <- function(c,s,p=list()) if(length(p)) DBI::dbGetQuery(c,s,params=p) else DBI::dbGetQuery(c,s)
x <- function(c,s,p=list()) if(length(p)) DBI::dbExecute(c,s,params=p) else DBI::dbExecute(c,s)
actor <- "19390000-0000-4000-8000-000000000094"
controller <- connect(); loader <- connect(); writer <- connect()
on.exit(try(DBI::dbDisconnect(controller),silent=TRUE),add=TRUE)
on.exit(try(DBI::dbDisconnect(loader),silent=TRUE),add=TRUE)
on.exit(try(DBI::dbDisconnect(writer),silent=TRUE),add=TRUE)
x(controller,"CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions")
x(controller,"INSERT INTO auth.users(id,email) VALUES($1,'post-load-lock@test.invalid') ON CONFLICT DO NOTHING",list(actor))
x(controller,"INSERT INTO public.profiles(id,email,rolle) VALUES($1,'post-load-lock@test.invalid','redaktion') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'",list(actor))
for (id in -1939513001:-1939513004) x(controller,"INSERT INTO public.person(id,levende,koen) VALUES($1,false,'ukendt') ON CONFLICT DO NOTHING",list(id))
set_actor <- function(c) invisible(q(c,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor)))
set_actor(writer)
conninfo <- paste(paste0("dbname=",pg$PGDATABASE),paste0("host=",pg$PGHOST),paste0("port=",pg$PGPORT),paste0("user=",pg$PGUSER),paste0("password=",pg$PGPASSWORD))
remote <- "post_load_lock_remote"
q(controller,"SELECT extensions.dblink_connect($1,$2)",list(remote,conninfo))
on.exit({try(q(controller,"SELECT extensions.dblink_exec($1,'ROLLBACK')",list(remote)),silent=TRUE);try(q(controller,"SELECT extensions.dblink_disconnect($1)",list(remote)),silent=TRUE)},add=TRUE)
remote_exec <- function(sql) q(controller,"SELECT extensions.dblink_exec($1,$2)",list(remote,sql))
remote_exec("BEGIN"); remote_exec(paste0("SET request.jwt.claim.sub='",actor,"'")); remote_exec("SET statement_timeout='7s'")
remote_pid <- q(controller,"SELECT * FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)",list(remote))$pid[[1L]]
wait_lock <- function() { deadline<-Sys.time()+5; repeat { s<-q(controller,"SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1",list(remote_pid)); if(nrow(s)==1L && identical(s$wait_event_type[[1L]],"Lock")) return(); if(Sys.time()>=deadline) stop("POST_LOAD_REMOTE_DID_NOT_BLOCK",call.=FALSE); Sys.sleep(.01) } }
finish <- function() { deadline<-Sys.time()+8; repeat { if(q(controller,"SELECT extensions.dblink_is_busy($1) busy",list(remote))$busy[[1L]]==0) break; if(Sys.time()>=deadline) stop("POST_LOAD_REMOTE_TIMEOUT",call.=FALSE); Sys.sleep(.01) }; results<-character(); for(i in 1:6) { r<-suppressWarnings(try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(remote)),silent=TRUE)); results<-c(results,as.character(r)); if(inherits(r,"try-error") && grepl("no query results",as.character(r),fixed=TRUE)) break }; if(any(grepl("deadlock detected",results,fixed=TRUE))) stop("POST_LOAD_DEADLOCK",call.=FALSE); invisible(results) }

# Post-load first: writer waits at advisory, never while holding relation table locks.
DBI::dbBegin(loader); q(loader,"SELECT pg_advisory_xact_lock(hashtext('samme_som_mutation'))"); q(loader,"SELECT private.guard_identity_mutation_snapshot()"); x(loader,"LOCK TABLE public.lineage,public.relation,public.assertion,public.citation,public.conclusion IN EXCLUSIVE MODE")
q(controller,"SELECT extensions.dblink_send_query($1,$2)",list(remote,"SELECT public.red_samme_som(-1939513001,-1939513002)::text")); wait_lock(); DBI::dbCommit(loader); finish(); remote_exec("ROLLBACK")

# Writer first: post-load waits before taking any table lock, so no lock cycle forms.
remote_exec("BEGIN"); remote_exec("SET statement_timeout='7s'")
DBI::dbBegin(writer); set_actor(writer); q(writer,"SELECT public.red_samme_som(-1939513003,-1939513004)")
loader_sql <- "SELECT pg_advisory_xact_lock(hashtext('samme_som_mutation'))::text; SELECT private.guard_identity_mutation_snapshot()::text; LOCK TABLE public.lineage,public.relation,public.assertion,public.citation,public.conclusion IN EXCLUSIVE MODE; SELECT 'ok'::text"
q(controller,"SELECT extensions.dblink_send_query($1,$2)",list(remote,loader_sql)); wait_lock(); DBI::dbRollback(writer); finish(); remote_exec("ROLLBACK")
cat("PASS post_load_fixup and identity writers share one deadlock-free lock order\n")
