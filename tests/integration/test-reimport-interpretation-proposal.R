# Disponerbar #196 proposal-integration: dry-run, apply, projektion før/efter,
# comparator-match, replay med ny autorisation, replay-match, receipt-mutation,
# negative snapshot-/rolle-skemaer med kildemutanter og R→PostgreSQL-grænsematrix.
#
# Kører KUN mod en disponerbar base (PG*-variablerne). Den opretter først et nyt,
# syntetisk #148-klausulgrundlag i en separat R-proces; at `source()` den fixture
# direkte gav RPostgres `bad_weak_ptr`, fordi dens DBI-forbindelse var afsluttet.
#
# Roller: autorisationer udstedes på kortlivede forbindelser med
# `SET LOCAL ROLE service_role`; operationsforbindelsen kører med
# `SET LOCAL ROLE <DAA_REIMPORT_TEST_ROLE, default authenticated>` via gatewayens
# transaction_setup — aldrig en sessionsbred rolle.
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(jsonlite); library(digest) })

`%||%` <- function(x, y) if (is.null(x)) y else x
root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(), value = TRUE)[1L])), "../.."), mustWork = TRUE)
scripts <- file.path(root, ".claude/skills/daa-extract/scripts")
source(file.path(scripts, "apply_reimport_helpers.R"))
stopifnot(nzchar(Sys.getenv("PGHOST")), nzchar(Sys.getenv("PGPORT")),
  nzchar(Sys.getenv("PGDATABASE")), nzchar(Sys.getenv("PGUSER")))
python <- Sys.getenv("DAA_PYTHON", "python3")
operation_role <- Sys.getenv("DAA_REIMPORT_TEST_ROLE", "authenticated")
stopifnot(operation_role %in% c("authenticated"))
# Ejerforbindelsen (fixtures, projektion) bruger PG*. Operation og autorisation kan
# køre som egne logins (CI: ikke-superuser, NOINHERIT, medlem af hhv. authenticated og
# service_role); lokalt falder de tilbage til PGUSER.
login <- function(kind) {
  prefix <- paste0("DAA_PROPOSAL_", kind, "_PG")
  list(user = Sys.getenv(paste0(prefix, "USER"), Sys.getenv("PGUSER")),
    password = Sys.getenv(paste0(prefix, "PASSWORD"), Sys.getenv("PGPASSWORD")))
}
connect_as <- function(credentials) dbConnect(Postgres(), dbname = Sys.getenv("PGDATABASE"),
  host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
  user = credentials$user, password = credentials$password)
connect <- function() connect_as(login("OWNER"))
connect_operation <- function() connect_as(login("OPERATION"))
connect_authorizer <- function() connect_as(login("AUTHORIZER"))
con <- connect(); on.exit(dbDisconnect(con), add = TRUE)
if (identical(Sys.getenv("DAA_PROPOSAL_STRICT_LOGINS"), "1")) {
  for (kind in c("OPERATION", "AUTHORIZER")) {
    probe <- connect_as(login(kind))
    super <- dbGetQuery(probe, "SELECT rolsuper FROM pg_roles WHERE rolname=session_user")$rolsuper[[1L]]
    dbDisconnect(probe)
    if (!isFALSE(super)) stop("INTEGRATION_LOGIN_SUPERUSER:", kind)
  }
}
q <- function(sql, params = list())
  if (length(params)) dbGetQuery(con, sql, params = params) else dbGetQuery(con, sql)
e <- function(sql, params = list())
  invisible(if (length(params)) dbExecute(con, sql, params = params) else dbExecute(con, sql))
count1 <- function(sql, params = list()) as.integer(q(sql, params)[[1L]][[1L]])

private_dir <- tempfile("daa196-"); dir.create(private_dir, mode = "0700")
on.exit(unlink(private_dir, recursive = TRUE), add = TRUE)
write_private <- function(name, text) {
  path <- file.path(private_dir, name)
  stopifnot(!file.exists(path))
  writeLines(text, path, useBytes = TRUE); Sys.chmod(path, "0600")
  path
}
run_cmd <- function(command, args) {
  out <- suppressWarnings(system2(command, args, stdout = TRUE, stderr = TRUE))
  list(status = as.integer(attr(out, "status") %||% 0L), out = paste(out, collapse = "\n"))
}
psql_file <- function(path, vars = character())
  run_cmd("psql", c("-X", "-At", "-q", "-v", "ON_ERROR_STOP=1",
    if (length(vars)) as.vector(rbind("-v", vars)) else character(), "-f", shQuote(path)))

# ---- 1. Syntetisk klausulgrundlag -----------------------------------------------------
clause_fixture <- file.path(root, "tests/integration/test-reimport-clause-evidence.R")
clause_out <- suppressWarnings(system2("Rscript", shQuote(clause_fixture), stdout = TRUE, stderr = TRUE))
if (!is.null(attr(clause_out, "status")) || !any(clause_out == "clause_evidence integration OK")) {
  stop("syntetisk clause-fixture fejlede: ", paste(clause_out, collapse = "\n"))
}
seed <- q(paste(
  "SELECT batch.source_id,event.source_record_key,profile.profile_id,profile.profile_sha256,profile.writer_config::text AS writer_config",
  "FROM private.reimport_event event",
  "JOIN private.reimport_batch batch ON batch.id=event.batch_id",
  "JOIN private.reimport_writer_profile profile ON profile.source_id=batch.source_id AND profile.profile_id=batch.profile_id AND profile.profile_sha256=batch.profile_sha256",
  "WHERE event.operation='clause_evidence' ORDER BY event.id DESC LIMIT 1"))
stopifnot(nrow(seed) == 1L)
source_id <- as.integer(seed$source_id[[1L]])
key_dead <- as.character(seed$source_record_key[[1L]])
clauses <- q(paste(
  "SELECT observation.clause_ordinal AS ordinal,encode(extensions.digest(convert_to(observation.verbatim_text,'UTF8'),'sha256'),'hex') AS verbatim_sha256",
  "FROM private.source_observation observation",
  "JOIN private.source_record_anchor_current anchor ON anchor.occurrence_id=observation.occurrence_id AND anchor.decision_status='accepted'",
  "JOIN private.source_record record ON record.id=anchor.source_record_id",
  "WHERE record.source_id=$1 AND record.record_key=$2 AND observation.parent_observation_id IS NOT NULL",
  "ORDER BY observation.clause_ordinal"), list(source_id, key_dead))
stopifnot(nrow(clauses) == 2L, identical(as.integer(clauses$ordinal), 1:2))

actor <- "14900000-0000-4000-8000-000000000003"
Sys.setenv(DAA_REIMPORT_ACTOR_ID = actor)
run_nonce <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), sample.int(.Machine$integer.max, 1L))
run_hash <- function(tag) digest::digest(paste(run_nonce, tag), algo = "sha256", serialize = FALSE)

proposal_profile_id <- paste0(seed$profile_id[[1L]], "-proposal-", substr(run_hash("profile"), 1L, 12L))
e("INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config) VALUES($1,$2,'interpretation-proposal-v1',$3,$4::jsonb) ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING",
  list(source_id, proposal_profile_id, seed$profile_sha256[[1L]], seed$writer_config[[1L]]))

# ---- 2. Roller: transaktionslokale sømme ---------------------------------------------
set_local_actor <- function(run) {
  run("SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
}
sql_seen <- character()
operation_setup <- function(db) {
  db$execute(paste("SET LOCAL ROLE", operation_role))
  set_local_actor(db$query)
  who <- db$query("SELECT current_user AS u, current_setting('request.jwt.claim.sub',true) AS sub")
  if (!identical(who$u[[1L]], operation_role) || !identical(who$sub[[1L]], actor))
    stop("INTEGRATION_OPERATION_ROLE_INVALID")
}
operation_gateway <- function() new_reimport_dbi_gateway(connect_operation,
  sql_observer = function(sql) sql_seen <<- c(sql_seen, sql), transaction_setup = operation_setup)

authorize_as_service_role <- function(manifest, preview_sha) {
  auth_con <- connect_authorizer(); on.exit(dbDisconnect(auth_con), add = TRUE)
  dbBegin(auth_con)
  dbExecute(auth_con, "SET LOCAL ROLE service_role")
  dbGetQuery(auth_con, "SELECT set_config('request.jwt.claim.sub',$1,true)", params = list(actor))
  who <- dbGetQuery(auth_con, "SELECT current_user AS u, current_setting('request.jwt.claim.sub',true) AS sub")
  stopifnot(identical(who$u[[1L]], "service_role"), identical(who$sub[[1L]], actor))
  identity <- dbGetQuery(auth_con, "SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS identity")$identity[[1L]]
  id <- dbGetQuery(auth_con, paste(
    "SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,",
    "gen_random_uuid(),clock_timestamp()+interval '10 minutes') AS id"),
    params = list(manifest$manifest_content_sha256, preview_sha, identity,
      manifest$source$id, manifest$source$profile_id, manifest$source$profile_sha256,
      jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
      reimport_authorized_payloads_json(manifest)))$id[[1L]]
  dbCommit(auth_con)
  id
}

# Livscyklus: efter COMMIT og ROLLBACK er rollen og de lokale claims væk igen.
for (finish in c("COMMIT", "ROLLBACK")) {
  life <- connect_operation()
  dbBegin(life)
  operation_setup(list(execute = function(sql, params = list()) dbExecute(life, sql),
    query = function(sql, params = list()) if (length(params)) dbGetQuery(life, sql, params = params) else dbGetQuery(life, sql)))
  if (identical(finish, "COMMIT")) dbCommit(life) else dbRollback(life)
  after <- dbGetQuery(life, "SELECT current_user=session_user AS same, coalesce(current_setting('request.jwt.claim.sub',true),'') AS sub")
  dbDisconnect(life)
  stopifnot(isTRUE(after$same[[1L]]), identical(after$sub[[1L]], ""))
}
# Operationsrollen må ikke udstede autorisationer.
denied <- tryCatch({
  c2 <- connect_operation(); on.exit(dbDisconnect(c2), add = TRUE); dbBegin(c2)
  dbExecute(c2, paste("SET LOCAL ROLE", operation_role))
  dbGetQuery(c2, "SELECT public.red_authorize_reimport(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)")
  "allowed"
}, error = function(err) conditionMessage(err))
stopifnot(grepl("permission denied", denied))
# Autorisatorrollen må ikke skrive proposals.
denied <- tryCatch({
  c3 <- connect_authorizer(); on.exit(dbDisconnect(c3), add = TRUE); dbBegin(c3)
  dbExecute(c3, "SET LOCAL ROLE service_role")
  dbGetQuery(c3, "SELECT public.red_apply_reimport_interpretation_proposal(NULL,NULL,NULL)")
  "allowed"
}, error = function(err) conditionMessage(err))
stopifnot(grepl("permission denied", denied))

# ---- 3. Manifest med provenance og ægte indholdshash ---------------------------------
claim <- function(id, value, cited, role = "other") list(
  claim_id = id, predicate = "person.name", interpretation_kind = "property",
  value = value, confidence = 0.9, cited_clauses = cited, persona_role = role)
citation <- function(i) list(ordinal = as.integer(clauses$ordinal[[i]]), verbatim_sha256 = clauses$verbatim_sha256[[i]])
build_manifest <- function(operations, tag) {
  manifest <- list(
    manifest_content_sha256 = strrep("0", 64L),
    source = list(id = source_id, profile_id = proposal_profile_id, profile_sha256 = seed$profile_sha256[[1L]]),
    expected_counts = list(source_evidence = 0L, person_creates = 0L, canonical_delta = 0L,
      interpretation_proposals = length(operations)),
    operations = operations,
    provenance = list(
      schema_version = "interpretation-proposal-manifest-1.0",
      runner_manifest_sha256 = run_hash(paste0("runner-", tag)),
      eligibility_ledger_sha256 = run_hash(paste0("ledger-", tag)),
      cache_files = setNames(list(), character()),
      predicates_sha256 = run_hash(paste0("predicates-", tag)),
      runner_contract_version = "fixture-contract-v1", denylist_version = "fixture-denylist-v1",
      persona_role_map_version = "fixture-role-map-v1",
      regnskab = list(raa_claims = 0L, kontrakt_afviste = 0L, h1_afviste = 0L, dubletter = 0L,
        ukendt_rolle = 0L, ingestible = 0L),
      h1_afviste = list(), dublet_claims = list(), ukendt_rolle_claims = list(),
      usage = list(input_tokens = 0L, output_tokens = 0L, reasoning_output_tokens = 0L,
        cached_input_tokens = 0L, cache_write_input_tokens = 0L)))
  draft <- write_private(paste0("manifest-draft-", tag, ".json"), reimport_proposal_json(manifest))
  printed <- run_cmd(python, c(shQuote(file.path(scripts, "compare_interpretation_proposal_projection.py")),
    "--print-manifest-sha256", shQuote(draft)))
  if (printed$status != 0L) stop("manifest-hash fejlede: ", printed$out)
  manifest$manifest_content_sha256 <- trimws(printed$out)
  stopifnot(reimport_hash(manifest$manifest_content_sha256))
  validate_reimport_manifest(manifest)
  list(manifest = manifest, path = write_private(paste0("manifest-", tag, ".json"), reimport_proposal_json(manifest)))
}
operation <- function(record_key, tag, claims) list(
  element_id = paste0("interpretation-proposal:", record_key),
  dependency_class = "interpretation_proposal", source_record_key = record_key,
  runner_manifest_sha256 = run_hash(paste0("runner-", tag)), model_version = "fixture-model-v1",
  prompt_version = "fixture-prompt-v1", claims = claims)

# Planens fixture: to claims; begge citerer klausul 1, og `other`-claimet også klausul 2.
built <- build_manifest(list(operation(key_dead, "proposal", list(
  claim(substr(run_hash("claim-a"), 1L, 32L), "Fixture navn", list(citation(1L)), role = "other"),
  claim(substr(run_hash("claim-b"), 1L, 32L), "Anden aktør", list(citation(1L), citation(2L)), role = "other")))),
  "proposal")
proposal_manifest <- built$manifest
preview_sha <- run_hash("preview-proposal")

# ---- 4. Projektion, target og comparator ---------------------------------------------
projection <- function() {
  result <- psql_file(file.path(scripts, "interpretation_proposal_projection.psql"),
    paste0("source_id=", source_id))
  if (result$status != 0L) stop("projektion fejlede: ", result$out)
  lines <- strsplit(result$out, "\n", fixed = TRUE)[[1L]]
  stopifnot(length(lines) == 1L)
  lines
}
target <- psql_file(file.path(scripts, "interpretation_proposal_target_identity.sql"))
stopifnot(target$status == 0L, reimport_hash(target$out))
comparator <- function(args) run_cmd(python,
  c(shQuote(file.path(scripts, "compare_interpretation_proposal_projection.py")), args))
compare_fresh <- function(before, after, report) comparator(c("--mode", "fresh",
  "--manifest", shQuote(built$path), "--before", shQuote(before), "--after", shQuote(after),
  "--expect-target-sha256", target$out, "--report", shQuote(file.path(private_dir, report))))
compare_replay <- function(after, replayed, authorization_id, report) comparator(c("--mode", "replay",
  "--after", shQuote(after), "--replayed", shQuote(replayed),
  "--replay-authorization-id", authorization_id,
  "--expect-target-sha256", target$out, "--report", shQuote(file.path(private_dir, report))))

# ---- 5. Dry-run (ekstern autorisation) ændrer intet -----------------------------------
before_events <- count1("SELECT count(*) FROM private.reimport_event WHERE operation='interpretation_proposal'")
dry_authorization <- authorize_as_service_role(proposal_manifest, preview_sha)
pre_dry <- projection()
dry <- execute_reimport(proposal_manifest, preview_sha, "dry-run", operation_gateway(),
  list(id = dry_authorization), authorization_policy = "external")
stopifnot(identical(dry$status, "finalized"), isFALSE(dry$committed),
  count1("SELECT count(*) FROM private.reimport_event WHERE operation='interpretation_proposal'") == before_events)
before_text <- projection()
stopifnot(identical(before_text, pre_dry))
before_path <- write_private("before.json", before_text)

# ---- 6. Apply og match ---------------------------------------------------------------
apply_authorization <- authorize_as_service_role(proposal_manifest, preview_sha)
applied <- execute_reimport(proposal_manifest, preview_sha, "apply", operation_gateway(),
  list(id = apply_authorization), authorization_policy = "external")
stopifnot(identical(applied$status, "finalized"), isTRUE(applied$committed))
after_path <- write_private("after.json", projection())
matched <- compare_fresh(before_path, after_path, "apply-match.json")
if (matched$status != 0L || !grepl('"status": "match"', matched$out, fixed = TRUE))
  stop("apply-comparator gav ikke match: ", matched$out)
stopifnot(identical(file.info(file.path(private_dir, "apply-match.json"))$mode, as.octmode("600")))
# Ingen rå værdi eller kildetekst i projektionen.
after_raw <- paste(readLines(after_path, warn = FALSE), collapse = "\n")
stopifnot(!grepl("Fixture navn", after_raw, fixed = TRUE), !grepl("Anden aktør", after_raw, fixed = TRUE))

# ---- 7. Receipt-mutation -------------------------------------------------------------
mutated <- jsonlite::fromJSON(after_raw, simplifyVector = FALSE)
events <- mutated$proposal_events
last <- length(events)
events[[last]]$result_receipt$claims[[1L]]$row_sha256 <- strrep("f", 64L)
mutated$proposal_events <- events
mutated_path <- write_private("after-mutated.json", reimport_proposal_json(mutated))
mutation <- compare_fresh(before_path, mutated_path, "mutation.json")
if (mutation$status == 0L || !grepl("INTERPRETATION_PROJECTION_RECEIPT_INVALID", mutation$out, fixed = TRUE))
  stop("receipt-mutation blev ikke afvist med RECEIPT_INVALID: ", mutation$out)

# ---- 8. Replay med ny autorisation ---------------------------------------------------
replay_authorization <- authorize_as_service_role(proposal_manifest, preview_sha)
replay <- execute_reimport(proposal_manifest, preview_sha, "apply", operation_gateway(),
  list(id = replay_authorization), authorization_policy = "external")
stopifnot(identical(replay$status, "already_applied"))
replayed_path <- write_private("replayed.json", projection())
replay_match <- compare_replay(after_path, replayed_path, replay_authorization, "replay-match.json")
if (replay_match$status != 0L || !grepl('"status": "match"', replay_match$out, fixed = TRUE))
  stop("replay-comparator gav ikke match: ", replay_match$out)
# Replay-rapporten er kædet til fresh-rapporten via byte-hashen af den samme after-fil.
report_json <- function(name) jsonlite::fromJSON(file.path(private_dir, name), simplifyVector = FALSE)
after_file_sha <- digest::digest(file = after_path, algo = "sha256")
stopifnot(identical(report_json("apply-match.json")$input_file_sha256$after, after_file_sha),
  identical(report_json("replay-match.json")$input_file_sha256$after, after_file_sha),
  identical(report_json("replay-match.json")$input_file_sha256$replayed,
    digest::digest(file = replayed_path, algo = "sha256")))
wrong_replay <- compare_replay(after_path, replayed_path, dry_authorization, "replay-wrong.json")
stopifnot(wrong_replay$status != 0L)

# Ingen sessionsbred rolleskift i operationens SQL.
stopifnot(!any(grepl("^\\s*SET\\s+(SESSION\\s+)?ROLE\\b", sql_seen, ignore.case = TRUE, perl = TRUE)),
  any(sql_seen == paste("SET LOCAL ROLE", operation_role)))

# ---- 9. Negative snapshot-/rolleskemaer + kildemutanter ------------------------------
sql_copy <- file.path(private_dir, "sql"); dir.create(sql_copy, mode = "0700")
sql_files <- c("interpretation_proposal_projection.sql", "interpretation_proposal_anon_projection.sql",
  "interpretation_proposal_projection.psql")
settings <- paste("SET LOCAL TimeZone TO 'UTC'; SET LOCAL DateStyle TO 'ISO, YMD';",
  "SET LOCAL IntervalStyle TO 'postgres'; SET LOCAL extra_float_digits TO 1;",
  "SET LOCAL bytea_output TO 'hex';")
set_source <- sprintf("SELECT set_config('daa.interpretation_projection_source_id','%d',true);", source_id)
driver_text <- paste(readLines(file.path(scripts, "interpretation_proposal_projection.psql")), collapse = "\n")
split_driver <- sub("SET LOCAL ROLE anon;", paste0("COMMIT;\nSELECT txid_current();\n",
  "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;\n", settings, "\nSET LOCAL ROLE anon;"),
  driver_text, fixed = TRUE)
stopifnot(!identical(split_driver, driver_text))
schedules <- list(
  read_write = list(code = "INTERPRETATION_PROJECTION_NOT_READ_ONLY", script = c(
    "BEGIN ISOLATION LEVEL REPEATABLE READ;", settings, set_source,
    "\\ir interpretation_proposal_projection.sql", "ROLLBACK;")),
  read_committed = list(code = "INTERPRETATION_PROJECTION_NOT_REPEATABLE_READ", script = c(
    "BEGIN ISOLATION LEVEL READ COMMITTED, READ ONLY;", settings, set_source,
    "\\ir interpretation_proposal_projection.sql", "ROLLBACK;")),
  anon_as_owner = list(code = "INTERPRETATION_PROJECTION_NOT_ANON", script = c(
    "BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;",
    "\\ir interpretation_proposal_anon_projection.sql", "ROLLBACK;")),
  owner_as_anon = list(code = "INTERPRETATION_PROJECTION_NOT_OWNER", script = c(
    "BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;", settings, set_source, "SET LOCAL ROLE anon;",
    "\\ir interpretation_proposal_projection.sql", "ROLLBACK;")),
  split_snapshot = list(code = "INTERPRETATION_PROJECTION_SNAPSHOT_MISMATCH", script = split_driver,
    vars = paste0("source_id=", source_id)))
reset_sql_copy <- function() for (f in sql_files) file.copy(file.path(scripts, f), file.path(sql_copy, f), overwrite = TRUE)
run_schedule <- function(name) {
  schedule <- schedules[[name]]
  path <- file.path(sql_copy, paste0("schedule-", name, ".psql"))
  writeLines(schedule$script, path)
  psql_file(path, schedule$vars %||% character())
}
reset_sql_copy()
for (name in names(schedules)) {
  result <- run_schedule(name)
  if (result$status == 0L || !grepl(schedules[[name]]$code, result$out, fixed = TRUE) ||
      grepl("daa-interpretation-proposal-projection-v1", result$out, fixed = TRUE))
    stop("negativt skema ", name, " gav ikke ", schedules[[name]]$code, ": ", result$out)
}
# Kildemutanter: prædikatet slås fra, men literal/kommentar står tilbage, så en ren
# statisk strengkontrol ville stadig bestå. Kørslen skal miste sin navngivne afvisning.
mutants <- list(
  list(file = "interpretation_proposal_projection.sql", schedule = "read_write",
    from = "WHEN current_setting('transaction_read_only') <> 'on'"),
  list(file = "interpretation_proposal_projection.sql", schedule = "read_committed",
    from = "WHEN current_setting('transaction_isolation') <> 'repeatable read'"),
  list(file = "interpretation_proposal_anon_projection.sql", schedule = "anon_as_owner",
    from = "WHEN current_user <> 'anon'"),
  list(file = "interpretation_proposal_projection.sql", schedule = "owner_as_anon",
    from = "WHEN NOT has_schema_privilege('private', 'USAGE')\n    OR NOT has_table_privilege('private.interpretation', 'SELECT')"),
  list(file = "interpretation_proposal_projection.psql", schedule = "split_snapshot",
    from = "WHEN (:'projection')::jsonb->>'snapshot_sha256' IS DISTINCT FROM"))
for (mutant in mutants) {
  reset_sql_copy()
  text <- paste(readLines(file.path(sql_copy, mutant$file)), collapse = "\n")
  stopifnot(grepl(mutant$from, text, fixed = TRUE))
  replacement <- sub("WHEN ", "WHEN false AND (", mutant$from, fixed = TRUE)
  replacement <- paste0(replacement, ")")
  mutated_text <- sub(mutant$from, replacement, text, fixed = TRUE)
  stopifnot(!identical(mutated_text, text))
  writeLines(mutated_text, file.path(sql_copy, mutant$file))
  if (identical(mutant$schedule, "split_snapshot")) schedules$split_snapshot$script <-
    sub("SET LOCAL ROLE anon;", paste0("COMMIT;\nSELECT txid_current();\n",
      "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;\n", settings, "\nSET LOCAL ROLE anon;"),
      mutated_text, fixed = TRUE)
  result <- run_schedule(mutant$schedule)
  if (grepl(schedules[[mutant$schedule]]$code, result$out, fixed = TRUE))
    stop("mutant uden guard gav stadig ", schedules[[mutant$schedule]]$code, " — testen beviser ikke runtime-guarden")
  schedules$split_snapshot$script <- split_driver
}
reset_sql_copy()

# ---- 10. R→PostgreSQL-modtagergrænse --------------------------------------------------
# Syntetisk manifest UDEN for 4.3b-builderens succesvej: indlejrede tal i en event-værdi.
# Den rigtige objektform for ikke-tekst-prædikater er {raw, normalized?} (evidence_extract).
boundary_value <- jsonlite::fromJSON(paste0('{"raw":"grænse","normalized":"grænse","n":[9007199254740991,',
  '-9007199254740991,1.0,1e0,-0,{"k":[1.0]}]}'), simplifyVector = FALSE)
expected_token <- '{"raw":"grænse","normalized":"grænse","n":[9007199254740991,-9007199254740991,1,1,0,{"k":[1]}]}'
stopifnot(identical(as.character(reimport_proposal_json(boundary_value)), expected_token))
boundary_claim <- list(claim_id = substr(run_hash("claim-boundary"), 1L, 32L), predicate = "event.travel",
  interpretation_kind = "event", value = boundary_value, confidence = 0.75,
  cited_clauses = list(citation(2L)), persona_role = "other")
boundary <- build_manifest(list(operation(key_dead, "boundary", list(boundary_claim))), "boundary")
boundary_preview <- run_hash("preview-boundary")
boundary_applied <- execute_reimport(boundary$manifest, boundary_preview, "apply", operation_gateway(),
  list(id = authorize_as_service_role(boundary$manifest, boundary_preview)), authorization_policy = "external")
stopifnot(identical(boundary_applied$status, "finalized"))
stored <- q(paste("SELECT value::text AS value, private.interpretation_proposal_canonical_json_sha256(value) AS sha,",
  "confidence::text AS confidence FROM private.interpretation",
  "WHERE source_id=$1 AND predicate='event.travel' ORDER BY created_at DESC LIMIT 1"), list(source_id))
stopifnot(nrow(stored) == 1L, identical(stored$confidence[[1L]], "0.75"))
# Python læser præcis de bytes, serializeren sendte til databasen.
value_path <- write_private("boundary-value.json", reimport_proposal_json(boundary_value))
python_sha <- run_cmd(python, c("-c", shQuote(paste0(
  "import sys; sys.path.insert(0,", deparse(scripts), "); ",
  "import compare_interpretation_proposal_projection as cp; ",
  "v=cp.strict_json_loads(open(", deparse(value_path), ",encoding='utf-8').read()); ",
  "print(cp.proposal_canonical_sha256(cp.normalize_interpretation_proposal_claim_value(v)))"))))
stopifnot(python_sha$status == 0L, identical(trimws(python_sha$out), stored$sha[[1L]]))
stopifnot(identical(jsonlite::fromJSON(stored$value[[1L]], simplifyVector = FALSE)$n[[1L]], 9007199254740991))
rejected_tokens <- c("9007199254740992", "-9007199254740992", "9223372036854775807",
  "-9223372036854775808", "0.5", "1e400", '{"k":[2.5]}')
for (token in rejected_tokens) {
  bad <- boundary$manifest
  bad$operations[[1L]]$claims[[1L]]$value <- jsonlite::fromJSON(
    sprintf('{"raw":"x","n":[%s]}', token), simplifyVector = FALSE)
  touched <- 0L
  counting <- list(call = function(name, ...) { touched <<- touched + 1L; NULL })
  err <- tryCatch({ execute_reimport(bad, boundary_preview, "dry-run", counting,
    list(id = apply_authorization), authorization_policy = "external"); "accepted" },
    error = function(error) conditionMessage(error))
  if (!identical(err, "REIMPORT_MANIFEST_PROPOSAL_VALUE_INVALID") || touched != 0L)
    stop("grænseværdi ", token, " blev ikke afvist i R før gateway: ", err)
}

# Sanitiserede kvitteringer (kun id'er, hashes, tællinger) til rehearsal-ledgeren.
cat("apply-match:", gsub("\\s+", " ", matched$out), "\n")
cat("replay-match:", gsub("\\s+", " ", replay_match$out), "\n")
cat("receipt-mutation:", regmatches(mutation$out, regexpr("INTERPRETATION_PROJECTION_[A-Z_]+", mutation$out)), "\n")
cat("interpretation_proposal integration OK\n")
