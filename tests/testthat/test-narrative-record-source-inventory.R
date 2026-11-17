root <- normalizePath(file.path(getwd(), "..", ".."))

read_repo <- function(path) readLines(file.path(root, path), warn = FALSE)

last_function_block <- function(sql, schema_name, function_name) {
  qualification <- if (identical(schema_name, "public")) "(?:public\\.)?" else "private\\."
  pattern <- paste0(
    "CREATE(?: OR REPLACE)? FUNCTION ", qualification, function_name, "\\("
  )
  starts <- gregexpr(pattern, sql, perl = TRUE)[[1]]
  starts <- starts[starts > 0L]
  expect_true(length(starts) > 0L, info = paste(schema_name, function_name))
  start <- tail(starts, 1L)
  remainder <- substring(sql, start + 1L)
  next_start <- regexpr("\\nCREATE(?: OR REPLACE)? FUNCTION ", remainder, perl = TRUE)[1]
  end <- if (next_start < 0L) nchar(sql) else start + next_start - 1L
  substring(sql, start, end)
}

acl_statements <- function(sql, prefix, signature) {
  statements <- trimws(strsplit(gsub("[[:space:]]+", " ", sql), ";", fixed = TRUE)[[1]])
  statements[
    grepl(prefix, statements, fixed = TRUE) & grepl(signature, statements, fixed = TRUE)
  ]
}

expect_acl <- function(sql, prefix, signature, principal_clause) {
  statements <- acl_statements(sql, prefix, signature)
  expect_true(length(statements) > 0L, info = paste(prefix, signature))
  expect_true(any(grepl(principal_clause, statements, fixed = TRUE)),
              info = paste(signature, principal_clause))
}

sql_text_array <- function(block, name) {
  assignment <- regmatches(
    block,
    regexec(
      paste0("(?s)\\b", name, "\\s+text\\[\\]\\s*:=\\s*ARRAY\\[(.*?)\\];"),
      block,
      perl = TRUE
    )
  )[[1]]
  expect_true(length(assignment) == 2L, info = name)
  if (length(assignment) != 2L) return(character())
  quoted <- regmatches(
    assignment[[2L]],
    gregexpr("'[^']+'", assignment[[2L]], perl = TRUE)
  )[[1]]
  expect_true(length(quoted) > 0L && !identical(quoted, ""), info = name)
  substring(quoted, 2L, nchar(quoted) - 1L)
}

direct_narrative_sql_writers <- function(path) {
  lines <- read_repo(path)
  starts <- grep("^CREATE(?: OR REPLACE)? FUNCTION[[:space:]]+", lines, perl = TRUE)
  expect_true(length(starts) > 0L, info = path)
  definitions <- data.frame(
    signature = character(), line = integer(), writes_narrative = logical()
  )
  for (index in seq_along(starts)) {
    start <- starts[[index]]
    end <- if (index == length(starts)) length(lines) else starts[[index + 1L]] - 1L
    block <- paste(lines[start:end], collapse = "\n")
    writes_narrative <- grepl(
      "(?is)\\b(?:INSERT\\s+INTO|UPDATE|DELETE\\s+FROM|MERGE\\s+INTO)\\s+(?:public\\.)?narrative\\b",
      block,
      perl = TRUE
    )
    header <- paste(lines[start:min(end, start + 8L)], collapse = " ")
    matched <- regmatches(
      header,
      regexec(
        "^CREATE(?: OR REPLACE)? FUNCTION[[:space:]]+((?:public\\.|private\\.)?[a-zA-Z0-9_]+)",
        header,
        perl = TRUE
      )
    )[[1]]
    expect_true(length(matched) == 2L, info = paste(path, start))
    name <- matched[[2L]]
    if (!grepl("\\.", name)) name <- paste0("public.", name)
    arguments <- sub(
      "(?is)^CREATE(?: OR REPLACE)? FUNCTION[[:space:]]+(?:public\\.|private\\.)?[a-zA-Z0-9_]+[[:space:]]*\\((.*?)\\)[[:space:]]*RETURNS.*$",
      "\\1",
      header,
      perl = TRUE
    )
    expect_false(identical(arguments, header), info = paste(path, name, start))
    types <- if (!nzchar(trimws(arguments))) character() else vapply(
      strsplit(arguments, ",", fixed = TRUE)[[1]],
      function(argument) {
        without_default <- sub("[[:space:]]+DEFAULT[[:space:]].*$", "", trimws(argument),
                               ignore.case = TRUE)
        gsub("[[:space:]]+", " ", sub("^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+", "",
                                      without_default))
      },
      character(1)
    )
    definitions <- rbind(
      definitions,
      data.frame(
        signature = paste0(name, "(", paste(types, collapse = ","), ")"),
        line = start,
        writes_narrative = writes_narrative
      )
    )
  }
  # Migration history may redefine or explicitly drop an old overload. Model
  # the effective final DDL: keep only the latest definition of each exact
  # signature, and exclude it if a matching DROP follows with no later CREATE.
  latest <- definitions[!duplicated(definitions$signature, fromLast = TRUE), ]
  active <- vapply(seq_len(nrow(latest)), function(index) {
    row <- latest[index, ]
    if (row$line >= length(lines)) return(TRUE)
    statements <- trimws(strsplit(
      paste(lines[(row$line + 1L):length(lines)], collapse = "\n"),
      ";", fixed = TRUE
    )[[1]])
    normalized_signature <- gsub(
      "[[:space:]]+", "", sub("^public\\.", "", row$signature)
    )
    normalized_statements <- gsub("[[:space:]]+", "", statements)
    !any(
      grepl("DROP FUNCTION", statements, fixed = TRUE) &
        grepl(normalized_signature, normalized_statements, fixed = TRUE)
    )
  }, logical(1))
  sort(latest$signature[latest$writes_narrative & active])
}

direct_narrative_r_writers <- function() {
  files <- c(
    list.files(file.path(root, "R"), "\\.R$", recursive = TRUE, full.names = TRUE),
    list.files(
      file.path(root, ".claude", "skills", "daa-extract", "scripts"),
      "\\.R$", recursive = TRUE, full.names = TRUE
    )
  )
  hits <- vapply(files, function(path) {
    grepl(
      "(?is)\\b(?:INSERT\\s+INTO|UPDATE|DELETE\\s+FROM|MERGE\\s+INTO)\\s+(?:public\\.)?narrative\\b",
      paste(readLines(path, warn = FALSE), collapse = "\n"),
      perl = TRUE
    )
  }, logical(1))
  sort(sub(paste0("^", root, "/"), "", files[hits]))
}

test_that("Task 6 pins every legacy SQL writer and its cutover classification", {
  sql_files <- c("schema.sql", "db-migrations.sql")
  gate <- "pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0))"
  legacy_disabled <- c(
    "red_publicer_narrative_record", "red_tilbagetraek_narrative_record",
    "red_authorize_reimport_cases", "red_apply_reimport_cases",
    "red_authorize_reimport_case_reversal", "red_reverse_reimport_cases"
  )
  # #153 deliberately keeps these exact public signatures for one transition
  # version. They are thin adapters; the generic target owns the v2 gate and
  # mutation path, so requiring the old disabled token in the adapter would
  # contradict the approved compatibility contract.
  legacy_1939_adapters <- c(
    red_authorize_1939_v50_reimport = "red_authorize_reimport",
    red_begin_1939_v50_reimport = "red_begin_reimport",
    red_apply_1939_v50_source_evidence = "red_apply_reimport_source_evidence",
    red_apply_1939_v50_person_create = "red_apply_reimport_person_create",
    red_apply_1939_v50_canonical_delta = "red_apply_reimport_canonical_delta",
    red_finalize_1939_v50_reimport = "red_finalize_reimport",
    red_authorize_1939_v50_reversal = "red_authorize_reimport_reversal",
    red_reverse_1939_v50_reimport = "red_reverse_reimport",
    red_authorize_1939_v50_cutover = "red_authorize_reimport_cutover",
    red_activate_1939_v50_batch = "red_activate_reimport_batch"
  )
  participates_without_disable <- c("red_slet_person", "red_fortryd_change_set")
  read_only <- c("red_preview_reimport_cases")
  private_read_only <- c("reimport_case_receipt", "reimport_case_reversal_plan")
  v2_facade_authenticated <- c(
    "public.red_begin_1939_v50_reimport(uuid,text,text)",
    "public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)",
    "public.red_apply_1939_v50_person_create(uuid,text,jsonb)",
    "public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)",
    "public.red_finalize_1939_v50_reimport(uuid)",
    "public.red_reverse_1939_v50_reimport(uuid,uuid)",
    "public.red_activate_1939_v50_batch(uuid,uuid)",
    "public.red_lock_1939_v50_name_completion(text)",
    "public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)",
    "public.red_begin_1939_v50_name_completion(uuid,text,uuid)",
    "public.red_apply_1939_v50_name_completion(uuid,text,jsonb)",
    "public.red_finalize_1939_v50_name_completion(uuid)"
  )
  v2_facade_service <- c(
    "public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)",
    "public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)",
    "public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)",
    "public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)"
  )

  for (path in sql_files) {
    sql <- paste(read_repo(path), collapse = "\n")
    for (name in legacy_disabled) {
      block <- last_function_block(sql, "public", name)
      expect_match(block, gate, fixed = TRUE, info = paste(path, name))
      expect_match(block, "NARRATIVE_RECORD_LEGACY_WRITER_DISABLED", fixed = TRUE,
                   info = paste(path, name))
    }
    for (name in names(legacy_1939_adapters)) {
      target <- legacy_1939_adapters[[name]]
      adapter <- last_function_block(sql, "public", name)
      expect_match(adapter, paste0("public.", target, "("), fixed = TRUE,
                   info = paste(path, name, "delegates to", target))
      expect_false(grepl("NARRATIVE_RECORD_LEGACY_WRITER_DISABLED", adapter, fixed = TRUE),
                   info = paste(path, name))

      target_block <- last_function_block(sql, "public", target)
      expect_match(target_block, gate, fixed = TRUE,
                   info = paste(path, name, "inherits gate from", target))
      expect_match(target_block, "narrative_record_contract_version()<>2", fixed = TRUE,
                   info = paste(path, name, "inherits v2 contract from", target))
    }
    for (name in participates_without_disable) {
      block <- last_function_block(sql, "public", name)
      expect_match(gsub("[[:space:]]+", "", block), gate, fixed = TRUE,
                   info = paste(path, name))
      expect_match(block, "narrative_record_contract_version()", fixed = TRUE,
                   info = paste(path, name))
      expect_false(grepl("NARRATIVE_RECORD_LEGACY_WRITER_DISABLED", block, fixed = TRUE))
    }
    upsert <- last_function_block(sql, "public", "red_upsert_narrativ")
    expect_match(upsert, gate, fixed = TRUE, info = path)
    expect_match(upsert, "NARRATIVE_RECORD_REQUIRED", fixed = TRUE, info = path)

    helper <- last_function_block(sql, "private", "write_reimport_case_narrative")
    expect_match(helper, gate, fixed = TRUE, info = path)
    expect_match(helper, "NARRATIVE_RECORD_LEGACY_WRITER_DISABLED", fixed = TRUE, info = path)

    for (name in read_only) {
      block <- last_function_block(sql, "public", name)
      expect_false(grepl(gate, block, fixed = TRUE), info = paste(path, name))
    }
    for (name in private_read_only) {
      block <- last_function_block(sql, "private", name)
      expect_false(grepl(gate, block, fixed = TRUE), info = paste(path, name))
    }

    authenticated <- c(
      "red_publicer_narrative_record(bigint,uuid,text,text)",
      "red_tilbagetraek_narrative_record(bigint)",
      "public.red_preview_reimport_cases(bigint,text,jsonb)",
      "public.red_apply_reimport_cases(uuid,text,text)",
      "public.red_reverse_reimport_cases(uuid,uuid)"
    )
    service_role <- c(
      "public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)",
      "public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)"
    )
    for (signature in authenticated) {
      expect_acl(sql, "GRANT EXECUTE ON FUNCTION", signature, "TO authenticated")
    }
    for (signature in service_role) {
      expect_acl(sql, "GRANT EXECUTE ON FUNCTION", signature, "TO service_role")
    }
    acl <- last_function_block(sql, "private", "apply_narrative_record_contract_acl")
    expect_setequal(
      sql_text_array(acl, "v_v2_facade_authenticated"),
      v2_facade_authenticated
    )
    expect_setequal(
      sql_text_array(acl, "v_v2_facade_service"),
      v2_facade_service
    )
    for (signature in c(
      "private.reimport_case_receipt(uuid)",
      "private.reimport_case_reversal_plan(uuid)",
      "private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)"
    )) {
      expect_acl(sql, "REVOKE ALL ON FUNCTION", signature,
                 "FROM PUBLIC,anon,authenticated,service_role")
    }
  }

  # The generic editor RPCs are classified by the exact signature-aware RLS
  # allow-list; the later purpose-specific blocks above narrow the v50/C3 split.
  rls <- paste(read_repo("db-rls.sql"), collapse = "\n")
  allow_start <- regexpr("DO $redaction_rpc_allow_list$", rls, fixed = TRUE)[1]
  allow_marker <- "$redaction_rpc_allow_list$;"
  allow_end <- regexpr(allow_marker, rls, fixed = TRUE)[1]
  expect_true(allow_start > 0L && allow_end > allow_start)
  allow_list <- substring(rls, allow_start, allow_end + nchar(allow_marker) - 1L)
  expect_match(allow_list,
               "EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',v_signature)",
               fixed = TRUE)
  for (signature in c(
    "public.red_upsert_narrativ(text,bigint,text,boolean,bigint,text)",
    "public.red_slet_person(bigint)",
    "public.red_fortryd_change_set(bigint,boolean)"
  )) {
    expect_match(allow_list, paste0("'", signature, "'"), fixed = TRUE)
  }
})

test_that("Task 6 pins loader, updater and historical gated consumers", {
  direct_scripts <- c(
    ".claude/skills/daa-extract/scripts/load_daa.R",
    "R/update-1939-narratives.R",
    "R/update-2018-narratives.R"
  )
  for (path in direct_scripts) {
    text <- paste(read_repo(path), collapse = "\n")
    expect_match(text, "daa-narrative-record-contract", fixed = TRUE, info = path)
    expect_match(text, "narrative_record_contract_version", fixed = TRUE, info = path)
    expect_match(text, "NARRATIVE_RECORD_LOADER_MIGRATION_REQUIRED", fixed = TRUE, info = path)
  }

  generic_adapter <- paste(
    read_repo(".claude/skills/daa-extract/scripts/apply_reimport_1939_v50_helpers.R"),
    collapse = "\n"
  )
  expect_match(generic_adapter, "apply_reimport_helpers.R", fixed = TRUE)
  expect_match(generic_adapter, "execute_reimport_generic", fixed = TRUE)
  expect_false(grepl("red_apply_1939_v50_canonical_delta", generic_adapter, fixed = TRUE))

  gated_consumers <- c(
    ".claude/skills/daa-extract/scripts/apply_phase_a_1939_v50_helpers.R" = "red_apply_1939_v50_source_evidence"
  )
  for (path in names(gated_consumers)) {
    expect_match(paste(read_repo(path), collapse = "\n"), gated_consumers[[path]], fixed = TRUE,
                 info = path)
  }
  c0 <- paste(read_repo(".claude/skills/daa-extract/scripts/apply_c0_followup_1939_v50.R"), collapse = "\n")
  expect_match(c0, "daa-1939-v50-production-writer", fixed = TRUE,
               info = "historical one-shot C0 consumer classification")
})

test_that("Task 7 pins the atomic cutover, receipt, sequence and ACL source of truth", {
  for (path in c("schema.sql", "db-migrations.sql")) {
    sql <- paste(read_repo(path), collapse = "\n")
    kernel <- last_function_block(sql, "private", "apply_narrative_record_cutover")
    expect_match(
      kernel,
      "pg_advisory_xact_lock(hashtextextended('daa-narrative-record-contract',0))",
      fixed = TRUE, info = path
    )
    for (name in c(
      "record_candidates_sha256", "legacy_candidates_sha256",
      "record_manifest_sha256", "legacy_manifest_sha256",
      "inventory_sha256", "approval_sha256"
    )) expect_match(kernel, name, fixed = TRUE, info = paste(path, name))
    expect_match(kernel, "LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE",
                 fixed = TRUE, info = path)
    expect_match(kernel, "ALTER SEQUENCE %s RESTART WITH %s", fixed = TRUE, info = path)
    expect_false(grepl("setval\\(", kernel), info = path)
    acl_position <- regexpr("apply_narrative_record_contract_acl(2)", kernel, fixed = TRUE)[1]
    version_position <- regexpr("SET version=2", kernel, fixed = TRUE)[1]
    expect_true(acl_position > 0L && version_position > acl_position, info = path)
    expect_match(kernel, "Version is deliberately the final write", fixed = TRUE, info = path)

    acl <- last_function_block(sql, "private", "apply_narrative_record_contract_acl")
    expect_match(acl, "IF p_version=1", fixed = TRUE, info = path)
    expect_match(acl, "GRANT EXECUTE ON FUNCTION %s TO authenticated", fixed = TRUE,
                 info = path)
    expect_match(acl, "GRANT EXECUTE ON FUNCTION %s TO service_role", fixed = TRUE,
                 info = path)
    expect_match(acl, "REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role",
                 fixed = TRUE, info = path)

    receipt_guard <- last_function_block(
      sql, "private", "reject_narrative_record_cutover_receipt_mutation"
    )
    expect_match(receipt_guard, "NARRATIVE_RECORD_CUTOVER_RECEIPT_APPEND_ONLY",
                 fixed = TRUE, info = path)
    expect_acl(
      sql, "REVOKE ALL ON FUNCTION",
      "private.apply_narrative_record_cutover( text,text,text,text,text,text,uuid,text,text )",
      "FROM PUBLIC,anon,authenticated,service_role"
    )
  }

  rls <- paste(read_repo("db-rls.sql"), collapse = "\n")
  expect_match(
    gsub("[[:space:]]+", " ", rls),
    "PERFORM private.apply_narrative_record_contract_acl( public.narrative_record_contract_version() );",
    fixed = TRUE
  )
  expect_match(rls, "$narrative_contract_acl_if_complete$", fixed = TRUE)
  expect_match(rls, "$reimport_1939_v2_facade_acl$", fixed = TRUE)
  verify <- paste(read_repo("db-verify.sql"), collapse = "\n")
  expect_match(verify, "VERIFY_NARRATIVE_RECORD_NEW_WRITER_ACL_INVALID", fixed = TRUE)
  expect_match(verify, "VERIFY_NARRATIVE_RECORD_LEGACY_AUTH_ACL_INVALID", fixed = TRUE)
})

test_that("direct narrative mutation sources remain an exact closed inventory", {
  # A new direct table writer must be classified here before this test can pass.
  # The effective legacy entries are gated by Task 6; record-native entries are
  # the version-2 owners installed by Tasks 3/4.
  expected_sql <- sort(c(
    "private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)",
    "private.reverse_narrative_publication_event(uuid,text)",
    "private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)",
    "public.red_slet_person(bigint)",
    # Fuld personsletning (decisions 2026-11-14): sletter P's narrativer efter manifestet, uden ny historik.
    "public.red_slet_person_helt(bigint,text)",
    "public.red_upsert_narrativ(text,bigint,text,boolean,bigint,text)"
  ))
  for (path in c("schema.sql", "db-migrations.sql")) {
    expect_identical(direct_narrative_sql_writers(path), expected_sql, info = path)
    sql <- paste(read_repo(path), collapse = "\n")
    for (name in c(
      "mutate_person_narrative_record",
      "reverse_narrative_publication_event"
    )) {
      block <- last_function_block(sql, "private", name)
      expect_match(block, "daa-narrative-record-contract", fixed = TRUE,
                   info = paste(path, name))
      expect_match(block, "NARRATIVE_RECORD_CONTRACT_INACTIVE", fixed = TRUE,
                   info = paste(path, name))
    }
  }

  expect_identical(direct_narrative_r_writers(), sort(c(
    ".claude/skills/daa-extract/scripts/load_daa.R",
    "R/update-1939-narratives.R",
    "R/update-2018-narratives.R"
  )))
})

test_that("direct narrative readers remain an explicit closed inventory", {
  # Task 8 moves the three public person-text readers to the gated v1/v2
  # RPCs.  The remaining direct reads are deliberately classified here:
  # about/presens are non-person controls, haendelser is RLS-gated metadata,
  # and the generic redaction readers remain Task 9's editor-RPC migration.
  source_files <- c(
    list.files(file.path(root, "web", "src"), "\\.(ts|tsx)$", recursive = TRUE, full.names = TRUE),
    list.files(file.path(root, "mobile", "src"), "\\.(ts|tsx)$", recursive = TRUE, full.names = TRUE)
  )
  hits <- vapply(source_files, function(path) {
    any(grepl("\\.from\\(['\"]narrative['\"]\\)", readLines(path, warn = FALSE)))
  }, logical(1))
  actual <- sort(sub(paste0("^", root, "/"), "", source_files[hits]))
  expected <- sort(c(
    "mobile/src/data/about.ts", "mobile/src/data/haendelser.ts",
    "mobile/src/data/presensLinjer.ts", "mobile/src/data/redaktionRead.ts",
    "web/src/data/haendelser.ts", "web/src/data/presensLinjer.ts",
    "web/src/data/public.ts", "web/src/data/redaktionRead.ts"
  ))
  expect_identical(actual, expected)
})


test_that("person purge outbox RPCs do not mutate narratives", {
  signatures <- c("public.red_person_purge_udbakke()", "public.red_person_purge_udbakke_kvitter(text,text)")
  for (path in c("schema.sql", "db-migrations.sql")) {
    expect_false(any(signatures %in% direct_narrative_sql_writers(path)), info = path)
    sql <- paste(read_repo(path), collapse = "\n")
    for (name in c("red_person_purge_udbakke", "red_person_purge_udbakke_kvitter")) {
      block <- last_function_block(sql, "public", name)
      expect_match(block, "private.person_purge_udbakke", fixed = TRUE, info = path)
    }
  }
})
