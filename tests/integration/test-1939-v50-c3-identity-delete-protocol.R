required_pg <- c("PGDATABASE","PGHOST","PGPORT","PGUSER","PGPASSWORD")
pg <- setNames(lapply(required_pg,function(k) Sys.getenv(k,unset=NA_character_)),required_pg)
if (any(vapply(pg,function(v) length(v)!=1L||is.na(v),logical(1)))) stop("IDENTITY_DELETE_REQUIRES_ALL_FIVE_PG_VARIABLES",call.=FALSE)
if (!grepl("^daa1939_c3_identity_task2_",pg$PGDATABASE)) stop("IDENTITY_DELETE_REQUIRES_DISPOSABLE_DATABASE",call.=FALSE)
connect <- function() DBI::dbConnect(RPostgres::Postgres(),dbname=pg$PGDATABASE,host=pg$PGHOST,port=pg$PGPORT,user=pg$PGUSER,password=pg$PGPASSWORD)
q <- function(c,s,p=list()) if(length(p)) DBI::dbGetQuery(c,s,params=p) else DBI::dbGetQuery(c,s)
x <- function(c,s,p=list()) if(length(p)) DBI::dbExecute(c,s,params=p) else DBI::dbExecute(c,s)
actor <- "19390000-0000-4000-8000-000000000095"
controller<-connect(); blocker<-connect()
on.exit(try(DBI::dbDisconnect(controller),silent=TRUE),add=TRUE); on.exit(try(DBI::dbDisconnect(blocker),silent=TRUE),add=TRUE)
x(controller,"CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions")
x(controller,"INSERT INTO auth.users(id,email) VALUES($1,'identity-delete@test.invalid') ON CONFLICT DO NOTHING",list(actor))
x(controller,"INSERT INTO public.profiles(id,email,rolle) VALUES($1,'identity-delete@test.invalid','redaktion') ON CONFLICT(id) DO UPDATE SET rolle='redaktion'",list(actor))
set_actor<-function(c) invisible(q(c,"SELECT set_config('request.jwt.claim.sub',$1,false)",list(actor)))
set_actor(controller); set_actor(blocker)
conninfo<-paste(paste0("dbname=",pg$PGDATABASE),paste0("host=",pg$PGHOST),paste0("port=",pg$PGPORT),paste0("user=",pg$PGUSER),paste0("password=",pg$PGPASSWORD))
names<-c("identity_delete_mutator","identity_delete_writer")
for(n in names) q(controller,"SELECT extensions.dblink_connect($1,$2)",list(n,conninfo))
on.exit(for(n in names){try(q(controller,"SELECT extensions.dblink_exec($1,'ROLLBACK')",list(n)),silent=TRUE);try(q(controller,"SELECT extensions.dblink_disconnect($1)",list(n)),silent=TRUE)},add=TRUE)
rexec<-function(n,s) q(controller,"SELECT extensions.dblink_exec($1,$2)",list(n,s))
begin_remote<-function(n,rr=FALSE){rexec(n,"ROLLBACK");rexec(n,if(rr)"BEGIN ISOLATION LEVEL REPEATABLE READ" else "BEGIN");rexec(n,paste0("SET request.jwt.claim.sub='",actor,"'"));rexec(n,"SET statement_timeout='8s'")}
pid<-setNames(vapply(names,function(n)q(controller,"SELECT * FROM extensions.dblink($1,'SELECT pg_backend_pid()') AS t(pid integer)",list(n))$pid[[1L]],integer(1)),names)
send<-function(n,s){if(q(controller,"SELECT extensions.dblink_send_query($1,$2) sent",list(n,s))$sent[[1L]]!=1)stop("IDENTITY_DELETE_SEND_FAILED",call.=FALSE)}
wait_lock<-function(n,tag){deadline<-Sys.time()+5;repeat{s<-q(controller,"SELECT state,wait_event_type,wait_event,query FROM pg_stat_activity WHERE pid=$1",list(pid[[n]]));if(nrow(s)==1L&&identical(s$wait_event_type[[1L]],"Lock"))return();if(Sys.time()>=deadline)stop(paste0("IDENTITY_DELETE_NOT_BLOCKED_",tag,"_",n,": ",paste(s[1L,],collapse=" | ")),call.=FALSE);Sys.sleep(.01)}}
finish<-function(n){deadline<-Sys.time()+8;repeat{if(q(controller,"SELECT extensions.dblink_is_busy($1) busy",list(n))$busy[[1L]]==0)break;if(Sys.time()>=deadline)stop("IDENTITY_DELETE_TIMEOUT",call.=FALSE);Sys.sleep(.01)};result<-suppressWarnings(try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(n)),silent=TRUE));suppressWarnings(try(q(controller,"SELECT * FROM extensions.dblink_get_result($1,true) AS t(value text)",list(n)),silent=TRUE));result}
seed<-function(a,b){for(id in c(a,b))x(controller,"INSERT INTO public.person(id,levende,koen) VALUES($1,false,'ukendt') ON CONFLICT DO NOTHING",list(id));old<-q(controller,"SELECT id FROM relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person' AND subjekt_id=$1 AND objekt_id=$2",list(a,b));if(nrow(old))q(controller,"SELECT public.red_slet_relation($1)",list(old$id[[1L]]));q(controller,"SELECT set_config('app.change_set_id','',false)");r<-q(controller,"SELECT public.red_samme_som($1,$2) id",list(a,b));list(id=r$id[[1L]],cs=q(controller,"SELECT cs.id::text FROM change_set cs JOIN change_event ce ON ce.change_set_id=cs.id WHERE ce.tabel='relation' AND ce.op='INSERT' AND (ce.row_pk->>'id')::bigint=$1 ORDER BY cs.created_at DESC,cs.id DESC LIMIT 1",list(r$id[[1L]]))$id[[1L]])}

run_schedule<-function(kind,isolation,a,b){created<-seed(a,b);rid<-created$id
  DBI::dbBegin(blocker);q(blocker,"SELECT id FROM relation WHERE id=$1 FOR UPDATE",list(rid))
  begin_remote(names[1]); mutation<-if(kind=="generic")sprintf("SELECT public.red_slet_relation(%s)::text",rid) else sprintf("SELECT public.red_fortryd_change_set(%s,true)::text",created$cs);send(names[1],mutation);wait_lock(names[1],paste(kind,isolation,sep="_"))
  begin_remote(names[2],isolation=="RR");if(isolation=="RR")q(controller,"SELECT * FROM extensions.dblink($1,$2) AS t(n bigint)",list(names[2],sprintf("SELECT count(*)::bigint FROM relation WHERE id=%s",rid)))
  send(names[2],sprintf("SELECT public.red_samme_som(%s,%s)::text",a,b));if(isolation=="RR")wait_lock(names[2],paste(kind,isolation,sep="_"))
  DBI::dbCommit(blocker);mut<-finish(names[1]);rexec(names[1],if(inherits(mut,"try-error"))"ROLLBACK" else "COMMIT")
  wr<-finish(names[2]);rexec(names[2],if(inherits(wr,"try-error"))"ROLLBACK" else "COMMIT")
  writer_id<-if(inherits(wr,"try-error"))NA_real_ else suppressWarnings(as.numeric(wr$value[[1L]]))
  exists<-if(is.na(writer_id))FALSE else q(controller,"SELECT EXISTS(SELECT 1 FROM relation WHERE id=$1) value",list(writer_id))$value[[1L]]
  pair<-q(controller,"SELECT count(*)::integer n FROM relation WHERE subjekt_type='person' AND objekt_type='person' AND subjekt_id=$1 AND objekt_id=$2 AND rolle='samme_som'",list(a,b))$n[[1L]]
  contradiction<-q(controller,"SELECT count(*)::integer n FROM relation WHERE subjekt_type='person' AND objekt_type='person' AND subjekt_id=least($1::bigint,$2::bigint) AND objekt_id=greatest($1::bigint,$2::bigint) AND rolle='ikke_samme_som'",list(a,b))$n[[1L]]
  if(isolation=="RC"&&(inherits(wr,"try-error")||!exists||pair!=1L||contradiction!=0L))stop(sprintf("IDENTITY_DELETE_RETURNED_ABSENT_%s: %s",kind,paste(wr,collapse=" ")),call.=FALSE)
  if(isolation=="RR"&&(!inherits(wr,"try-error")||!grepl("could not serialize access",as.character(wr),fixed=TRUE)))stop(sprintf("IDENTITY_DELETE_RR_EXPECTED_40001_%s: %s",kind,paste(wr,collapse=" ")),call.=FALSE)
  if(isolation=="RR"&&(pair!=0L||contradiction!=0L))stop(sprintf("IDENTITY_DELETE_RR_FINAL_GRAPH_%s",kind),call.=FALSE)
}
run_schedule("generic","RC",-1939515001,-1939515002)
run_schedule("generic","RR",-1939515003,-1939515004)
run_schedule("undo","RC",-1939515005,-1939515006)
run_schedule("undo","RR",-1939515007,-1939515008)
cat("PASS generic delete and real undo obey identity mutation protocol\n")
