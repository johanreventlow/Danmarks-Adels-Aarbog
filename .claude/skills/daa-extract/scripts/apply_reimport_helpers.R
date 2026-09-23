reimport_hash_re <- "^[0-9a-f]{64}$"
reimport_uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

stop_reimport <- function(code) stop(code, call. = FALSE)

reimport_hash <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl(reimport_hash_re, value)
}

reimport_uuid <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl(reimport_uuid_re, value)
}

reimport_named <- function(value, expected) {
  is.list(value) && identical(sort(names(value)), sort(expected))
}

validate_reimport_manifest <- function(manifest) {
  required <- c("manifest_content_sha256", "source", "expected_counts", "operations")
  # "provenance" (#148 4.1c) er en ikke-autoriserende blok, der binder manifestet til
  # ledgerfilens og renditionens hashes. Den sendes aldrig til databasen; den gør det
  # muligt at se, hvilket artefakt et manifest er bygget af.
  optional <- c("dispositions", "provenance")
  if (!is.list(manifest) || !all(required %in% names(manifest)) ||
      !all(names(manifest) %in% c(required, optional)) || anyDuplicated(names(manifest)) ||
      !reimport_hash(manifest$manifest_content_sha256) ||
      !reimport_named(manifest$source, c("id", "profile_id", "profile_sha256")) ||
      !is.integer(manifest$source$id) || length(manifest$source$id) != 1L ||
      is.na(manifest$source$id) || manifest$source$id <= 0L ||
      !is.character(manifest$source$profile_id) || length(manifest$source$profile_id) != 1L ||
      is.na(manifest$source$profile_id) || !nzchar(manifest$source$profile_id) ||
      !reimport_hash(manifest$source$profile_sha256))
    stop_reimport("REIMPORT_MANIFEST_PROFILE_INVALID")
  count_names <- names(manifest$expected_counts)
  base_counts <- c("source_evidence", "person_creates", "canonical_delta")
  if (!is.list(manifest$expected_counts) ||
      !(identical(sort(count_names), sort(base_counts)) ||
        identical(sort(count_names), sort(c(base_counts, "legacy_migrations"))) ||
        identical(sort(count_names), sort(c(base_counts, "clause_evidence"))) ||
        identical(sort(count_names), sort(c(base_counts, "interpretation_proposals")))) ||
      any(!vapply(manifest$expected_counts, function(value) is.integer(value) && length(value) == 1L &&
        !is.na(value) && value >= 0L, logical(1))) || !is.list(manifest$operations))
    stop_reimport("REIMPORT_MANIFEST_COUNTS_INVALID")
  if (!all(vapply(manifest$operations, function(operation)
    is.list(operation) && is.character(operation$element_id) && length(operation$element_id) == 1L &&
      nzchar(operation$element_id) &&
      operation$dependency_class %in% c("source_evidence", "person_create", "legacy_migration",
                                        "clause_evidence", "interpretation_proposal"),
    logical(1))) || anyDuplicated(vapply(manifest$operations, `[[`, "", "element_id")))
    stop_reimport("REIMPORT_MANIFEST_OPERATIONS_INVALID")
  counts <- c(
    source_evidence = sum(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "source_evidence"), logical(1))),
    person_creates = sum(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "person_create"), logical(1))),
    canonical_delta = 0L
  )
  has_legacy_migration_ops <- any(vapply(manifest$operations, function(operation)
    identical(operation$dependency_class, "legacy_migration"), logical(1)))
  if ("legacy_migrations" %in% count_names) {
    counts[["legacy_migrations"]] <- sum(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "legacy_migration"), logical(1)))
  } else if (has_legacy_migration_ops) {
    stop_reimport("REIMPORT_MANIFEST_COUNTS_INVALID")
  }
  has_clause_evidence_ops <- any(vapply(manifest$operations, function(operation)
    identical(operation$dependency_class, "clause_evidence"), logical(1)))
  if ("clause_evidence" %in% count_names) {
    counts[["clause_evidence"]] <- sum(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "clause_evidence"), logical(1)))
  } else if (has_clause_evidence_ops) {
    stop_reimport("REIMPORT_MANIFEST_COUNTS_INVALID")
  }
  has_proposal_ops <- any(vapply(manifest$operations, function(operation)
    identical(operation$dependency_class, "interpretation_proposal"), logical(1)))
  if ("interpretation_proposals" %in% count_names) {
    counts[["interpretation_proposals"]] <- sum(vapply(manifest$operations, function(operation)
      identical(operation$dependency_class, "interpretation_proposal"), logical(1)))
  } else if (has_proposal_ops) {
    stop_reimport("REIMPORT_MANIFEST_COUNTS_INVALID")
  }
  if (!all(vapply(names(counts), function(name)
    identical(manifest$expected_counts[[name]], counts[[name]]), logical(1))))
    stop_reimport("REIMPORT_MANIFEST_COUNTS_INVALID")
  if (!is.null(manifest$dispositions) && !is.list(manifest$dispositions))
    stop_reimport("REIMPORT_MANIFEST_DISPOSITIONS_INVALID")
  for (operation in manifest$operations) {
    if (identical(operation$dependency_class, "interpretation_proposal") &&
        (!is.list(operation$claims) || !all(vapply(operation$claims, reimport_proposal_claim_valid, logical(1)))))
      stop_reimport("REIMPORT_MANIFEST_PROPOSAL_VALUE_INVALID")
  }
  invisible(manifest)
}

# Modtagergrænsen for proposal-claims (#196). Ethvert tal i en claim-værdi skal være et
# helt tal i JSON-safe-intervallet, så R, jsonlite og SQL bærer præcis samme token.
reimport_json_safe_max <- 9007199254740991

reimport_proposal_value_valid <- function(value) {
  if (is.null(value)) return(TRUE)
  if (is.list(value)) return(all(vapply(value, reimport_proposal_value_valid, logical(1))))
  if (is.character(value) || is.logical(value) || is.integer(value)) return(!anyNA(value))
  if (is.double(value)) return(all(is.finite(value)) && all(value == trunc(value)) &&
    all(abs(value) <= reimport_json_safe_max))
  FALSE
}

reimport_proposal_claim_valid <- function(claim) {
  is.list(claim) && reimport_proposal_value_valid(claim$value)
}

# Den ENE serializer for proposal-payloads. Hele tal skrives som fulde base-10-tokens
# (aldrig eksponent), andre tal med korteste round-trip-repræsentation. jsonlite's
# digits=17 er bevidst fravalgt: den skriver 0.9 som 0.90000000000000002.
reimport_proposal_json_number <- function(x) {
  if (!is.finite(x)) stop_reimport("REIMPORT_PROPOSAL_SERIALIZATION_INVALID")
  if (x == trunc(x)) {
    if (abs(x) > reimport_json_safe_max) stop_reimport("REIMPORT_PROPOSAL_SERIALIZATION_INVALID")
    return(structure(if (x == 0) "0" else sprintf("%.0f", x), class = "json"))
  }
  for (digits in 15:17) {
    token <- sprintf(paste0("%.", digits, "g"), x)
    if (as.numeric(token) == x) break
  }
  structure(token, class = "json")
}

reimport_proposal_json_prepare <- function(value) {
  if (is.list(value)) {
    prepared <- lapply(value, reimport_proposal_json_prepare)
    attributes(prepared) <- attributes(value)
    return(prepared)
  }
  if (is.double(value)) {
    tokens <- lapply(value, reimport_proposal_json_number)
    return(if (length(value) == 1L) tokens[[1L]] else tokens)
  }
  value
}

reimport_proposal_json <- function(value) {
  jsonlite::toJSON(reimport_proposal_json_prepare(value), auto_unbox = TRUE, null = "null",
    json_verbatim = TRUE, digits = NA)
}

reimport_authorized_payloads_json <- function(manifest) {
  payloads <- reimport_authorized_payloads(manifest)
  if ("interpretation_proposals" %in% names(manifest$expected_counts))
    reimport_proposal_json(payloads)
  else jsonlite::toJSON(payloads, auto_unbox = TRUE, null = "null")
}

reimport_authorized_payloads <- function(manifest) {
  validate_reimport_manifest(manifest)
  payloads <- lapply(manifest$operations, function(operation) {
    operation$element_id <- NULL
    operation$dependency_class <- NULL
    operation
  })
  names(payloads) <- vapply(manifest$operations, `[[`, "", "element_id")
  payloads
}

reimport_writer_expected_counts <- function(manifest) {
  validate_reimport_manifest(manifest)
  manifest$expected_counts[intersect(
    c("person_creates", "source_evidence", "legacy_migrations", "clause_evidence",
      "interpretation_proposals"), names(manifest$expected_counts))]
}

validate_reimport_preflight <- function(preflight, manifest) {
  required <- c("database_identity", "actor_id", "transaction_read_only", "source", "locked_payload_count")
  if (!reimport_named(preflight, required) ||
      !is.character(preflight$database_identity) || length(preflight$database_identity) != 1L ||
      is.na(preflight$database_identity) || !nzchar(preflight$database_identity) ||
      !reimport_uuid(preflight$actor_id) ||
      !identical(preflight$transaction_read_only, "off") ||
      !identical(preflight$source, manifest$source) ||
      !is.integer(preflight$locked_payload_count) || length(preflight$locked_payload_count) != 1L ||
      !identical(preflight$locked_payload_count, as.integer(length(manifest$operations))))
    stop_reimport("REIMPORT_DATABASE_PROFILE_MISMATCH")
  invisible(preflight)
}

validate_reimport_authorization <- function(authorization) {
  if (!is.list(authorization) || !reimport_uuid(authorization$id))
    stop_reimport("REIMPORT_AUTHORIZATION_REQUIRED")
  invisible(authorization)
}

validate_reimport_authorization_binding <- function(binding, authorization, manifest, preview_sha256, database_identity) {
  required <- c("authorization_id", "database_identity", "source", "manifest_sha256", "preview_sha256")
  if (!reimport_named(binding, required) || !reimport_uuid(binding$authorization_id) ||
      !identical(binding$authorization_id, authorization$id) ||
      !identical(binding$database_identity, database_identity) ||
      !identical(binding$source, manifest$source) ||
      !identical(binding$manifest_sha256, manifest$manifest_content_sha256) ||
      !identical(binding$preview_sha256, preview_sha256))
    stop_reimport("REIMPORT_AUTHORIZATION_BINDING_INVALID")
  invisible(binding)
}

validate_reimport_batch_result <- function(result, batch_id) {
  required <- c("batch_id", "status", "replayed", "person_id_map")
  if (!reimport_named(result, required) || !identical(result$batch_id, batch_id) ||
      !is.character(result$status) || length(result$status) != 1L || is.na(result$status) ||
      !result$status %in% c("open", "finalized") || !is.logical(result$replayed) ||
      length(result$replayed) != 1L || is.na(result$replayed) || !is.list(result$person_id_map))
    stop_reimport("REIMPORT_BATCH_RESULT_INVALID")
  map_names <- names(result$person_id_map)
  if (length(result$person_id_map) && (is.null(map_names) || any(!nzchar(map_names)) ||
      anyDuplicated(map_names) || any(!vapply(result$person_id_map, function(value)
        (is.integer(value) || is.numeric(value)) && length(value) == 1L && !is.na(value) && value > 0 &&
          identical(value, as.integer(value)), logical(1)))))
    stop_reimport("REIMPORT_BATCH_RESULT_INVALID")
  if (identical(result$status, "open") && (isTRUE(result$replayed) || length(result$person_id_map)))
    stop_reimport("REIMPORT_BATCH_RESULT_INVALID")
  if (identical(result$status, "finalized") && !isTRUE(result$replayed))
    stop_reimport("REIMPORT_BATCH_RESULT_INVALID")
  invisible(result)
}

execute_reimport <- function(manifest, preview_sha256, mode = c("dry-run", "apply"), gateway,
                             authorization = NULL,
                             authorization_policy = c("auto_dry_run", "external"),
                             transaction_entry = NULL) {
  mode <- match.arg(mode)
  authorization_policy <- match.arg(authorization_policy)
  validate_reimport_manifest(manifest)
  if (!reimport_hash(preview_sha256)) stop_reimport("REIMPORT_PREVIEW_HASH_INVALID")
  if (!is.list(gateway) || !is.function(gateway$call)) stop_reimport("REIMPORT_GATEWAY_INVALID")
  if (!is.null(transaction_entry) && !is.function(transaction_entry))
    stop_reimport("REIMPORT_TRANSACTION_ENTRY_INVALID")
  if (identical(mode, "apply") || identical(authorization_policy, "external"))
    validate_reimport_authorization(authorization)
  call <- gateway$call
  connected <- FALSE
  rolled_back <- FALSE
  rollback_once <- function() {
    if (connected && !rolled_back) {
      rolled_back <<- TRUE
      call("rollback")
    }
  }
  tryCatch({
    call("connect")
    connected <- TRUE
    call("begin")
    call("advisory_lock", manifest$source)
    if (!is.null(transaction_entry)) transaction_entry()
    server_preflight <- call("preflight", manifest)
    validate_reimport_preflight(server_preflight, manifest)
    resolved_authorization <- if (identical(authorization_policy, "external")) authorization else
      call("authorize", manifest, preview_sha256, mode, authorization)
    validate_reimport_authorization(resolved_authorization)
    validate_reimport_authorization_binding(
      call("preflight_authorization", resolved_authorization, manifest, preview_sha256),
      resolved_authorization, manifest, preview_sha256, server_preflight$database_identity)
    batch_id <- call("begin_batch", resolved_authorization, manifest, preview_sha256)
    if (!reimport_uuid(batch_id)) stop_reimport("REIMPORT_BATCH_RESULT_INVALID")
    batch_result <- call("batch_result", resolved_authorization, batch_id)
    validate_reimport_batch_result(batch_result, batch_id)
    if (identical(batch_result$status, "finalized")) {
      person_id_map <- batch_result$person_id_map
      if (identical(mode, "dry-run")) rollback_once() else call("commit")
      return(list(mode = mode, status = "already_applied", person_id_map = person_id_map,
        authorization = resolved_authorization, committed = identical(mode, "apply")))
    }
    person_id_map <- list()
    for (operation in manifest$operations) {
      payload <- operation
      payload$element_id <- NULL
      payload$dependency_class <- NULL
      if (identical(operation$dependency_class, "source_evidence")) {
        call("source_evidence", batch_id, operation$element_id, payload)
      } else if (identical(operation$dependency_class, "legacy_migration")) {
        call("legacy_migration", batch_id, operation$element_id, payload)
      } else if (identical(operation$dependency_class, "clause_evidence")) {
        call("clause_evidence", batch_id, operation$element_id, payload)
      } else if (identical(operation$dependency_class, "interpretation_proposal")) {
        # Writeren returnerer interpretations_written pr. element. Batchens
        # expected_counts tæller kun ELEMENTER, så et tabt claim ville slippe
        # igennem serverens finalize. Denne kontrol er den eneste, der er på
        # claim-niveau.
        written <- call("interpretation_proposal", batch_id, operation$element_id, payload)
        if (!identical(as.integer(written$interpretations_written), length(operation$claims)))
          stop_reimport("REIMPORT_WRITER_INTERPRETATION_COUNT_MISMATCH")
      } else {
        person_id_map[[operation$source_record_key]] <- call("person_create", batch_id, operation$element_id, payload)
      }
    }
    final <- call("finalize", batch_id)
    if (identical(mode, "dry-run")) rollback_once() else call("commit")
    list(mode = mode, status = final$status, person_id_map = person_id_map,
      authorization = resolved_authorization, committed = identical(mode, "apply"))
  }, error = function(error) {
    rollback_once()
    stop(conditionMessage(error), call. = FALSE)
  })
}

new_reimport_dbi_gateway <- function(connection_factory, sql_observer = NULL, transaction_setup = NULL) {
  if (!is.null(transaction_setup) && !is.function(transaction_setup))
    stop_reimport("REIMPORT_TRANSACTION_SETUP_INVALID")
  con <- NULL
  server_identity <- NULL
  query <- function(sql, params = list()) {
    if (is.function(sql_observer)) sql_observer(sql)
    if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
  }
  execute <- function(sql, params = list()) {
    if (is.function(sql_observer)) sql_observer(sql)
    if (length(params)) DBI::dbExecute(con, sql, params = params) else DBI::dbExecute(con, sql)
  }
  list(call = function(name, ...) {
    args <- list(...)
    switch(name,
      connect = { con <<- connection_factory(); invisible(NULL) },
      begin = {
        DBI::dbBegin(con)
        # Transaktionslokal opsætning (fx SET LOCAL ROLE + lokale claims); ses af sql_observer.
        if (!is.null(transaction_setup)) transaction_setup(list(query = query, execute = execute))
        invisible(NULL)
      },
      advisory_lock = {
        source <- args[[1L]]
        query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", list(
          paste("daa-reimport", source$id, source$profile_id, sep = ":")))
        invisible(NULL)
      },
      preflight = {
        manifest <- args[[1L]]
        actor <- Sys.getenv("DAA_REIMPORT_ACTOR_ID")
        if (!reimport_uuid(actor)) stop_reimport("REIMPORT_ACTOR_REQUIRED")
        query("SELECT set_config('request.jwt.claim.sub',$1,true)", list(actor))
        state <- query("SELECT jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text AS database_identity, current_setting('request.jwt.claim.sub',true) AS actor_id, current_setting('transaction_read_only') AS transaction_read_only")
        server_identity <<- state$database_identity[[1L]]
        list(database_identity = state$database_identity[[1L]], actor_id = state$actor_id[[1L]],
          transaction_read_only = state$transaction_read_only[[1L]], source = manifest$source,
          locked_payload_count = as.integer(length(manifest$operations)))
      },
      authorize = {
        manifest <- args[[1L]]
        preview_sha256 <- args[[2L]]
        mode <- args[[3L]]
        supplied <- args[[4L]]
        if (identical(mode, "apply")) return(supplied)
        nonce <- query("SELECT gen_random_uuid() AS id")$id[[1L]]
        id <- query("SELECT public.red_authorize_reimport($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9,clock_timestamp()+interval '10 minutes') AS id",
          list(manifest$manifest_content_sha256, preview_sha256, server_identity, manifest$source$id,
            manifest$source$profile_id, manifest$source$profile_sha256,
            jsonlite::toJSON(reimport_writer_expected_counts(manifest), auto_unbox = TRUE),
            reimport_authorized_payloads_json(manifest), nonce))$id[[1L]]
        list(id = id)
      },
      preflight_authorization = {
        authorization <- args[[1L]]
        jsonlite::fromJSON(query("SELECT public.red_preflight_reimport_authorization($1,$2,$3)::text AS value", list(
          authorization$id, args[[2L]]$manifest_content_sha256, args[[3L]]))$value[[1L]], simplifyVector = FALSE)
      },
      begin_batch = {
        query("SELECT public.red_begin_reimport($1,$2,$3) AS id", list(
          args[[1L]]$id, args[[2L]]$manifest_content_sha256, args[[3L]]))$id[[1L]]
      },
      batch_result = jsonlite::fromJSON(query("SELECT public.red_reimport_batch_result($1,$2)::text AS value", list(
        args[[1L]]$id, args[[2L]]))$value[[1L]], simplifyVector = FALSE),
      source_evidence = { execute("SELECT public.red_apply_reimport_source_evidence($1,$2,$3::jsonb)", list(
        args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null"))); invisible(NULL) },
      person_create = {
        id <- query("SELECT public.red_apply_reimport_person_create($1,$2,$3::jsonb) AS id", list(
          args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))$id[[1L]]
        query("SELECT set_config('app.change_set_id','',true)")
        id
      },
      legacy_migration = {
        result <- query("SELECT public.red_apply_reimport_legacy_migration($1,$2,$3::jsonb)::text AS value", list(
          args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))$value[[1L]]
        query("SELECT set_config('app.change_set_id','',true)")
        jsonlite::fromJSON(result, simplifyVector = FALSE)
      },
      clause_evidence = {
        result <- query("SELECT public.red_apply_reimport_clause_evidence($1,$2,$3::jsonb)::text AS value", list(
          args[[1L]], args[[2L]], jsonlite::toJSON(args[[3L]], auto_unbox = TRUE, null = "null")))$value[[1L]]
        query("SELECT set_config('app.change_set_id','',true)")
        jsonlite::fromJSON(result, simplifyVector = FALSE)
      },
      interpretation_proposal = {
        result <- query("SELECT public.red_apply_reimport_interpretation_proposal($1,$2,$3::jsonb)::text AS value", list(
          args[[1L]], args[[2L]], reimport_proposal_json(args[[3L]])))$value[[1L]]
        query("SELECT set_config('app.change_set_id','',true)")
        jsonlite::fromJSON(result, simplifyVector = FALSE)
      },
      finalize = jsonlite::fromJSON(query("SELECT public.red_finalize_reimport($1)::text AS value", list(args[[1L]]))$value[[1L]], simplifyVector = FALSE),
      rollback = { DBI::dbRollback(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      commit = { DBI::dbCommit(con); DBI::dbDisconnect(con); con <<- NULL; invisible(NULL) },
      stop_reimport("REIMPORT_GATEWAY_OPERATION_INVALID")
    )
  })
}

new_default_reimport_dbi_gateway <- function() {
  new_reimport_dbi_gateway(function() DBI::dbConnect(RPostgres::Postgres(),
    dbname = Sys.getenv("PGDATABASE"), host = Sys.getenv("PGHOST"), port = Sys.getenv("PGPORT"),
    user = Sys.getenv("PGUSER"), password = Sys.getenv("PGPASSWORD")))
}
