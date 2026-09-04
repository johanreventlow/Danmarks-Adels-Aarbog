# #166 149b Task 9b: batch-fortrydelse af en ren legacy-migration-batch (spec §8).
#
# Selve fortrydelsen sker per narrativ gennem #152's dedikerede RPC'er — der findes
# ingen samlet "rul batchen tilbage"-writer for legacy_migration, og der skal ikke
# findes en: red_reverse_reimport hører til person_create-kæden og kræver en
# aktiveret batch med en name_completion-child.  Dette script kæder derfor de
# dedikerede fortrydelser i den rigtige rækkefølge og registrerer resultatet
# gennem private.record_reimport_legacy_reversal, som efterprøver kvitteringen mod
# databasen og forbruger reversal-autorisationen.
#
# Hele batchen fortrydes i ÉN transaktion: enten er alle elementer fortrudt og
# registreret, eller intet er.  --dry-run kører nøjagtig samme kæde og ruller
# tilbage til sidst.

legacy_reversal_uuid_re <-
  "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
legacy_reversal_hash_re <- "^[0-9a-f]{64}$"

stop_legacy_reversal <- function(code) stop(code, call. = FALSE)

legacy_reversal_uuid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl(legacy_reversal_uuid_re, value)
}

legacy_reversal_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl(legacy_reversal_hash_re, value)
}

legacy_reversal_scalar <- function(value) {
  (is.character(value) || is.numeric(value)) && length(value) == 1L && !is.na(value)
}

# --- CLI ------------------------------------------------------------------
# Kun de tre flag findes; ukendte eller gentagne flag afvises fail-closed, så en
# tastefejl aldrig kan blive til en utilsigtet apply.
parse_legacy_reversal_cli <- function(args) {
  if (!is.character(args)) stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  allowed <- c("--batch-id", "--authorization", "--dry-run", "--apply")
  flags <- args[grepl("^--", args)]
  if (!length(flags) || any(!flags %in% allowed) || anyDuplicated(flags))
    stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
      stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
    args[[index + 1L]]
  }
  if (!all(c("--batch-id", "--authorization") %in% flags))
    stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  if (sum(c("--dry-run", "--apply") %in% flags) != 1L)
    stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  batch_id <- value("--batch-id")
  authorization_id <- value("--authorization")
  if (!legacy_reversal_uuid(batch_id) || !legacy_reversal_uuid(authorization_id))
    stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  # Positionelle rester (fx en glemt værdi til --dry-run) er også en fejl.
  consumed <- sort(c(match("--batch-id", args), match("--batch-id", args) + 1L,
    match("--authorization", args), match("--authorization", args) + 1L,
    which(args %in% c("--dry-run", "--apply"))))
  if (!identical(consumed, seq_along(args)))
    stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  list(batch_id = batch_id, authorization_id = authorization_id,
    mode = if ("--apply" %in% flags) "apply" else "dry-run")
}

# --- kvittering -----------------------------------------------------------
# Formen er låst af private.record_reimport_legacy_reversal: præcis tre nøgler,
# reversal_event_ids ALTID et array (as.list, ellers ville jsonlite unboxe et
# enkelt id til en streng og udløse REIMPORT_LEGACY_REVERSAL_RECEIPT_MISMATCH),
# og final_ledger_status = NULL for bound_draft (renderes som JSON null).
build_legacy_reversal_receipt <- function(event_ids, final_ledger_status = NULL) {
  ids <- unlist(event_ids, use.names = FALSE)
  if (!length(ids) || !all(vapply(ids, legacy_reversal_uuid, logical(1))) ||
      anyDuplicated(ids))
    stop_legacy_reversal("LEGACY_REVERSAL_RECEIPT_INVALID")
  if (!is.null(final_ledger_status) &&
      !identical(final_ledger_status, "grandfathered_publication"))
    stop_legacy_reversal("LEGACY_REVERSAL_RECEIPT_INVALID")
  list(reversal_event_ids = as.list(as.character(ids)),
    final_binding_status = "withdrawn",
    final_ledger_status = final_ledger_status)
}

legacy_reversal_element_required <- c("element_id", "person_id", "source_id",
  "source_record_key", "narrative_id", "disposition", "binding_id", "draft_event_id")

validate_legacy_reversal_element <- function(element) {
  if (!is.list(element) || !all(legacy_reversal_element_required %in% names(element)) ||
      !is.character(element$element_id) || length(element$element_id) != 1L ||
      !nzchar(element$element_id) ||
      !legacy_reversal_scalar(element$person_id) ||
      !legacy_reversal_scalar(element$source_id) ||
      !legacy_reversal_scalar(element$narrative_id) ||
      !is.character(element$source_record_key) ||
      length(element$source_record_key) != 1L || !nzchar(element$source_record_key) ||
      !element$disposition %in% c("bound_published", "bound_draft") ||
      !legacy_reversal_uuid(element$binding_id) ||
      !legacy_reversal_uuid(element$draft_event_id))
    stop_legacy_reversal("LEGACY_REVERSAL_ELEMENT_INVALID")
  published <- identical(element$disposition, "bound_published")
  if (published != legacy_reversal_uuid(element$published_event_id) ||
      published != legacy_reversal_uuid(element$legacy_event_id) ||
      published != legacy_reversal_uuid(element$legacy_publication_ref))
    stop_legacy_reversal("LEGACY_REVERSAL_ELEMENT_INVALID")
  invisible(element)
}

# Omvendt element_id-orden (spec §8): fortrydelsen spejler den rækkefølge,
# writeren skrev elementerne i.
order_legacy_reversal_elements <- function(elements) {
  if (!is.list(elements) || !length(elements))
    stop_legacy_reversal("LEGACY_REVERSAL_BATCH_EMPTY")
  keys <- vapply(elements, function(element) {
    validate_legacy_reversal_element(element)
    element$element_id
  }, "")
  if (anyDuplicated(keys)) stop_legacy_reversal("LEGACY_REVERSAL_ELEMENT_INVALID")
  elements[order(keys, method = "radix", decreasing = TRUE)]
}

validate_legacy_reversal_authorization <- function(authorization, batch_id, actor) {
  if (!is.list(authorization) ||
      !identical(authorization$operation, "reversal") ||
      !identical(authorization$status, "issued") ||
      !identical(authorization$database_identity, paste0("batch:", batch_id)) ||
      !isTRUE(authorization$principal_matches_actor) ||
      !isTRUE(authorization$batch_matches) ||
      isTRUE(authorization$expired))
    stop_legacy_reversal("REIMPORT_WRITER_REVERSAL_INVALID")
  invisible(authorization)
}

validate_legacy_reversal_batch <- function(batch) {
  if (!is.list(batch) || !identical(batch$status, "finalized") ||
      !legacy_reversal_scalar(batch$source_id) ||
      !is.character(batch$profile_id) || length(batch$profile_id) != 1L ||
      as.integer(batch$foreign_operations) != 0L ||
      as.integer(batch$legacy_migrations) < 1L)
    stop_legacy_reversal("REIMPORT_WRITER_REVERSAL_INVALID")
  if (as.integer(batch$reversal_events) > 0L)
    stop_legacy_reversal("LEGACY_REVERSAL_ALREADY_RECORDED")
  invisible(batch)
}

# --- kæden ----------------------------------------------------------------
# Fortryd-kæden pr. narrativ (spec §8, revideret):
#   bound_published: fortryd(published) -> kasser(record) -> fortryd(legacy_migrated)
#   bound_draft:     fortryd(draft_created)
# draft_created kan IKKE fortrydes efter en published-fortrydelse: reversal-eventet
# er da streamens seneste (#152 NARRATIVE_PUBLICATION_EVENT_NOT_LATEST).  Den
# redaktionelle vej til en inaktiv binding er discard, og draft_discarded tæller
# med i kvitteringen på lige fod med de to reversals.
reverse_legacy_migration_element <- function(element, call) {
  ids <- character(0)
  ledger_status <- NULL
  if (identical(element$disposition, "bound_published")) {
    state <- call("record_state", element$person_id, element$source_id,
      element$source_record_key)
    if (!legacy_reversal_hash(state)) stop_legacy_reversal("LEGACY_REVERSAL_RECORD_STATE_INVALID")
    reversed <- call("reverse_event", element$published_event_id, state)
    if (!identical(reversed$status, "draft"))
      stop_legacy_reversal("LEGACY_REVERSAL_UNEXPECTED_BINDING_STATUS")
    ids <- c(ids, reversed$event_id)
    discarded <- call("discard_record", element$person_id, element$source_id,
      element$source_record_key, reversed$state_sha256)
    if (!identical(discarded$status, "withdrawn"))
      stop_legacy_reversal("LEGACY_REVERSAL_UNEXPECTED_BINDING_STATUS")
    ids <- c(ids, discarded$event_id)
    legacy <- call("legacy_state", element$legacy_publication_ref)
    if (!identical(legacy$ledger_status, "migrated") ||
        !identical(legacy$latest_event_type, "legacy_migrated") ||
        !identical(legacy$latest_event_id, element$legacy_event_id))
      stop_legacy_reversal("LEGACY_REVERSAL_LEGACY_STATE_UNEXPECTED")
    legacy_reversed <- call("reverse_event", element$legacy_event_id, legacy$state_sha256)
    ids <- c(ids, legacy_reversed$event_id)
    ledger_status <- "grandfathered_publication"
  } else {
    state <- call("record_state", element$person_id, element$source_id,
      element$source_record_key)
    if (!legacy_reversal_hash(state)) stop_legacy_reversal("LEGACY_REVERSAL_RECORD_STATE_INVALID")
    reversed <- call("reverse_event", element$draft_event_id, state)
    if (!identical(reversed$status, "withdrawn"))
      stop_legacy_reversal("LEGACY_REVERSAL_UNEXPECTED_BINDING_STATUS")
    ids <- c(ids, reversed$event_id)
  }
  build_legacy_reversal_receipt(ids, ledger_status)
}

execute_legacy_reversal <- function(batch_id, authorization_id,
                                    mode = c("dry-run", "apply"), gateway) {
  mode <- match.arg(mode)
  if (!legacy_reversal_uuid(batch_id) || !legacy_reversal_uuid(authorization_id))
    stop_legacy_reversal("LEGACY_REVERSAL_CLI_INVALID")
  if (!is.list(gateway) || !is.function(gateway$call))
    stop_legacy_reversal("LEGACY_REVERSAL_GATEWAY_INVALID")
  call <- gateway$call
  connected <- FALSE
  finished <- FALSE
  rollback_once <- function() {
    if (connected && !finished) {
      finished <<- TRUE
      call("rollback")
    }
  }
  tryCatch({
    call("connect")
    connected <- TRUE
    call("begin")
    actor <- call("actor")
    if (!legacy_reversal_uuid(actor)) stop_legacy_reversal("REIMPORT_ACTOR_REQUIRED")
    batch <- call("batch", batch_id)
    validate_legacy_reversal_batch(batch)
    call("advisory_lock", batch$source_id, batch$profile_id)
    authorization <- call("authorization", authorization_id, batch_id)
    validate_legacy_reversal_authorization(authorization, batch_id, actor)
    elements <- order_legacy_reversal_elements(call("elements", batch_id))
    if (length(elements) != as.integer(batch$legacy_migrations))
      stop_legacy_reversal("REIMPORT_WRITER_REVERSAL_INVALID")
    receipts <- list()
    for (element in elements)
      receipts[[element$element_id]] <- reverse_legacy_migration_element(element, call)
    recorded <- call("record_reversal", batch_id, authorization_id, receipts)
    if (!identical(as.integer(recorded$reversed_elements), length(elements)) ||
        !identical(recorded$batch_status, "finalized"))
      stop_legacy_reversal("LEGACY_REVERSAL_RECORD_MISMATCH")
    if (identical(mode, "dry-run")) {
      rollback_once()
    } else {
      finished <- TRUE
      call("commit")
    }
    list(mode = mode, batch_id = batch_id, authorization_id = authorization_id,
      reversed_elements = length(elements),
      element_ids = vapply(elements, `[[`, "", "element_id"),
      receipts_sha256 = recorded$receipts_sha256,
      committed = identical(mode, "apply"))
  }, error = function(error) {
    rollback_once()
    stop(conditionMessage(error), call. = FALSE)
  })
}

# --- DBI-gateway ----------------------------------------------------------
# Kaldes på en privilegeret forbindelse (samme som SQL-gaten og de øvrige
# integrationstests): private.legacy_migration_reversal_state og
# private.record_reimport_legacy_reversal er REVOKED for alle klientroller, og
# #152's fortryd-RPC'er ligeledes.  Aktøren sættes som request.jwt.claim.sub.
new_legacy_reversal_dbi_gateway <- function(connection_factory, sql_observer = NULL) {
  con <- NULL
  query <- function(sql, params = list()) {
    if (is.function(sql_observer)) sql_observer(sql)
    if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  }
  json <- function(sql, params = list())
    jsonlite::fromJSON(query(sql, params)$value[[1L]], simplifyVector = FALSE)
  clear_change_set <- function() query("SELECT set_config('app.change_set_id','',true)")
  list(call = function(name, ...) {
    args <- list(...)
    switch(name,
      connect = { con <<- connection_factory(); invisible(NULL) },
      begin = { DBI::dbBegin(con); invisible(NULL) },
      actor = {
        actor <- Sys.getenv("DAA_REIMPORT_ACTOR_ID")
        if (!legacy_reversal_uuid(actor)) stop_legacy_reversal("REIMPORT_ACTOR_REQUIRED")
        query("SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
        actor
      },
      batch = {
        row <- query(paste(
          "SELECT b.source_id, b.profile_id, b.status,",
          " (SELECT count(*) FROM private.reimport_event e",
          "   WHERE e.batch_id=b.id AND e.operation='legacy_migration') AS legacy_migrations,",
          " (SELECT count(*) FROM private.reimport_event e",
          "   WHERE e.batch_id=b.id AND e.operation NOT IN ('legacy_migration','reversal')) AS foreign_operations,",
          " (SELECT count(*) FROM private.reimport_event e",
          "   WHERE e.batch_id=b.id AND e.operation='reversal') AS reversal_events",
          "FROM private.reimport_batch b WHERE b.id=$1"), list(args[[1L]]))
        if (!nrow(row)) stop_legacy_reversal("REIMPORT_WRITER_REVERSAL_INVALID")
        list(source_id = as.integer(row$source_id[[1L]]),
          profile_id = as.character(row$profile_id[[1L]]),
          status = as.character(row$status[[1L]]),
          legacy_migrations = as.integer(row$legacy_migrations[[1L]]),
          foreign_operations = as.integer(row$foreign_operations[[1L]]),
          reversal_events = as.integer(row$reversal_events[[1L]]))
      },
      advisory_lock = {
        query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
          list(paste("daa-reimport", args[[1L]], args[[2L]], sep = ":")))
        invisible(NULL)
      },
      authorization = {
        row <- query(paste(
          "SELECT a.operation, a.status, a.database_identity,",
          " (a.principal_id::text = current_setting('request.jwt.claim.sub',true)) AS principal_matches_actor,",
          " (a.expires_at <= clock_timestamp()) AS expired,",
          " (a.source_id = b.source_id AND a.profile_id = b.profile_id",
          "  AND a.profile_sha256 = b.profile_sha256 AND a.manifest_sha256 = b.manifest_sha256",
          "  AND a.preview_sha256 = b.preview_sha256) AS batch_matches",
          "FROM private.reimport_authorization a, private.reimport_batch b",
          "WHERE a.id=$1 AND b.id=$2"), list(args[[1L]], args[[2L]]))
        if (!nrow(row)) stop_legacy_reversal("REIMPORT_WRITER_REVERSAL_INVALID")
        list(operation = as.character(row$operation[[1L]]),
          status = as.character(row$status[[1L]]),
          database_identity = as.character(row$database_identity[[1L]]),
          principal_matches_actor = isTRUE(row$principal_matches_actor[[1L]]),
          expired = isTRUE(row$expired[[1L]]),
          batch_matches = isTRUE(row$batch_matches[[1L]]))
      },
      elements = {
        rows <- query(paste(
          "SELECT e.element_id, e.payload->>'person_id' AS person_id,",
          " e.payload->>'source_id' AS source_id, e.source_record_key,",
          " e.payload->>'narrative_id' AS narrative_id, e.payload->>'disposition' AS disposition,",
          " e.payload->>'binding_id' AS binding_id, e.payload->>'draft_event_id' AS draft_event_id,",
          " e.payload->>'published_event_id' AS published_event_id,",
          " e.payload->>'legacy_event_id' AS legacy_event_id,",
          " e.payload->>'legacy_publication_ref' AS legacy_publication_ref",
          "FROM private.reimport_event e",
          "WHERE e.batch_id=$1 AND e.operation='legacy_migration'",
          "ORDER BY e.element_id"), list(args[[1L]]))
        lapply(seq_len(nrow(rows)), function(index) {
          field <- function(name) {
            value <- rows[[name]][[index]]
            if (is.na(value)) NULL else as.character(value)
          }
          list(element_id = as.character(rows$element_id[[index]]),
            person_id = as.integer(field("person_id")),
            source_id = as.integer(field("source_id")),
            source_record_key = as.character(rows$source_record_key[[index]]),
            narrative_id = as.integer(field("narrative_id")),
            disposition = field("disposition"),
            binding_id = field("binding_id"),
            draft_event_id = field("draft_event_id"),
            published_event_id = field("published_event_id"),
            legacy_event_id = field("legacy_event_id"),
            legacy_publication_ref = field("legacy_publication_ref"))
        })
      },
      record_state = {
        rows <- query(paste(
          "SELECT r.state_sha256 FROM public.red_person_narrative_records($1) r",
          "WHERE r.source_id=$2 AND r.record_key=$3 AND r.provenance_kind='source_record'"),
          list(args[[1L]], args[[2L]], args[[3L]]))
        if (nrow(rows) != 1L) stop_legacy_reversal("LEGACY_REVERSAL_RECORD_STATE_AMBIGUOUS")
        as.character(rows$state_sha256[[1L]])
      },
      reverse_event = {
        result <- json("SELECT public.red_fortryd_person_narrative_publication_event($1,$2)::text AS value",
          list(args[[1L]], args[[2L]]))
        clear_change_set()
        result
      },
      discard_record = {
        result <- json("SELECT public.red_kasser_person_narrative_record($1,$2,$3,$4)::text AS value",
          list(args[[1L]], args[[2L]], args[[3L]], args[[4L]]))
        clear_change_set()
        result
      },
      legacy_state = json("SELECT private.legacy_migration_reversal_state($1)::text AS value",
        list(args[[1L]])),
      record_reversal = json("SELECT private.record_reimport_legacy_reversal($1,$2,$3::jsonb)::text AS value",
        list(args[[1L]], args[[2L]],
          jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null"))),
      rollback = { DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      commit = { DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      stop_legacy_reversal("LEGACY_REVERSAL_GATEWAY_OPERATION_INVALID")
    )
  })
}

new_default_legacy_reversal_dbi_gateway <- function()
  new_legacy_reversal_dbi_gateway(function() DBI::dbConnect(RPostgres::Postgres(),
    dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"),
    port = Sys.getenv("PGPORT"), user = Sys.getenv("PGUSER"),
    password = Sys.getenv("PGPASSWORD")))
