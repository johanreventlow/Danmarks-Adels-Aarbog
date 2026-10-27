script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_name_completion_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

locked_rows <- list(
  list("record-3766faae-ae21-412a-8cfb-745a19ac77f0", 1846L, "Ditlev", 503L),
  list("record-43d4974a-0532-421d-a3fb-8e7c575a67e7", 1847L, "Gerhard (Gherardus de Reventlow)", 506L),
  list("record-80180a6e-2cc6-4968-81ca-004b6662d8ce", 1848L, "Henning", 506L),
  list("record-89a932c8-7b52-4f5c-9e00-0f2b62ee4422", 1849L, "Henning Reventlow", 508L),
  list("record-8f346104-cf3c-465f-bfa3-efb78be436b2", 1850L, "Iven (Ywanus de Reuentlo)", 506L),
  list("record-a1f4547d-16cc-4110-ad1b-fa3ff1c59a58", 1851L, "Henning", 508L),
  list("record-b626f5ff-f2fb-4061-bfce-988dbddec846", 1852L, "Henrik", 506L),
  list("record-c731fc5a-7e4c-45b8-9bfc-d6eba9f62e5d", 1853L, "Margrethe", 517L)
)

sha <- function(letter) paste(rep(letter, 64L), collapse = "")

canonical_test_value <- function(value) {
  if (!is.list(value)) return(value)
  value_names <- names(value)
  if (is.null(value_names)) return(lapply(value, canonical_test_value))
  if (anyNA(value_names) || anyDuplicated(value_names)) stop("TEST_CANONICAL_INVALID", call. = FALSE)
  result <- lapply(sort(value_names, method = "radix"), function(name) canonical_test_value(value[[name]]))
  names(result) <- sort(value_names, method = "radix")
  result
}

canonical_test_sha256 <- function(value) {
  digest::digest(enc2utf8(jsonlite::toJSON(canonical_test_value(value), auto_unbox = TRUE,
    null = "null", pretty = FALSE)), algo = "sha256", serialize = FALSE)
}

rehash_manifest <- function(manifest) {
  manifest$manifest_content_sha256 <- NULL
  manifest$manifest_content_sha256 <- canonical_test_sha256(manifest)
  manifest
}

authorization_fixture <- function(database_name = "name_completion_1939",
                                  system_identifier = "test-system-identifier") {
  list(authorization_id = "9f7a80dc-7566-45dc-8a98-9d3c4ea7a312",
    database_name = database_name, system_identifier = system_identifier)
}

fixture_manifest <- function() {
  operations <- lapply(seq_along(locked_rows), function(index) {
    row <- locked_rows[[index]]
    text <- paste0(row[[3L]], " source text")
    list(
      element_id = paste0("name-completion:", row[[1L]]),
      source_batch_id = "560c39f8-5c87-4c0d-a768-025d97fa2974",
      source_person_create_element_id = paste0("person-create:", row[[1L]]),
      person_id = row[[2L]], source_id = 3L, edition = "1939",
      source_record_key = row[[1L]], source_persona_id = paste0("persona-", row[[2L]]),
      name = row[[3L]], source_span = list(char_from = index, char_to = index + 10L),
      page_evidence = list(page_from = row[[4L]], page_to = row[[4L]]),
      verbatim_text = text, verbatim_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE),
      source_payload_sha256 = sha(c("b", "c", "d", "e", "f", "a", "b", "c")[[index]]),
      expected_before = list(staged = TRUE, name_cache_empty = TRUE, name_facts = 0L),
      expected_after = list(name_fact = 1L, selected_assertion = 1L,
        daa_1939_citation = 1L, conclusion = 1L)
    )
  })
  rehash_manifest(list(
    schema_version = "1939-v50-name-completion-manifest-v1",
    generator_version = "test", input_hashes = list(
      production_manifest_sha256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f",
      production_apply_sha256 = sha("b"), post_apply_audit_sha256 = sha("c")
    ), source = list(edition = "1939", source_id = 3L),
    source_batch_id = "560c39f8-5c87-4c0d-a768-025d97fa2974",
    source_manifest_bytes_sha256 = "8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f",
    source_manifest_content_sha256 = "8c6a9f56af7f1e75e1b961f561cc2118478ac4d9e08f838c9e5279938c545f03",
    operations = operations, counts = list(name_completions = 8L, operations = 8L),
    expected_changes = list(facts_created = 8L, assertions_created = 8L,
      citations_created = 8L, conclusions_created = 8L, persons_created = 0L,
      persons_activated = 0L, relations_changed = 0L, families_changed = 0L),
    production_authorized = FALSE, cutover_authorized = FALSE
  ))
}

fake_gateway <- function(fail_at = NULL, preflight_result = NULL,
                         authorization_envelope = authorization_fixture(),
                         resolved_authorization = NULL) {
  log <- character()
  preflight_args <- NULL
  name_completion_args <- list()
  call <- function(name, ...) {
    args <- list(...)
    log <<- c(log, name)
    if (identical(name, fail_at)) stop(paste0("FAIL_AT_", name), call. = FALSE)
    if (identical(name, "preflight")) {
      preflight_args <<- args
      source_batch <- if (length(args) >= 3L) args[[1L]] else args[[1L]]$source_batch_id
      manifest_sha256 <- args[[2L]]
      envelope <- if (!is.null(resolved_authorization)) resolved_authorization else authorization_envelope
      response <- if (is.null(preflight_result)) list(valid = TRUE,
        database_name = envelope$database_name, system_identifier = envelope$system_identifier,
        source_batch_id = source_batch, manifest_sha256 = manifest_sha256) else preflight_result
      return(list(authorization = envelope, preflight = response))
    }
    if (identical(name, "name_completion")) name_completion_args <<- c(name_completion_args, list(args))
    if (identical(name, "begin_batch")) return("completion-batch")
    if (identical(name, "finalize")) {
      fixture <- fixture_manifest()
      result_map <- lapply(seq_along(fixture$operations), function(index) list(
        person_id = fixture$operations[[index]]$person_id, fact_id = index,
        assertion_id = index + 10L, citation_id = index + 20L, conclusion_id = index + 30L))
      names(result_map) <- vapply(fixture$operations, function(op) op$element_id, character(1))
      return(list(status = "finalized", batch_id = "completion-batch",
        counts = list(name_completions = 8L, operations = 8L), result_map = result_map))
    }
    invisible(NULL)
  }
  list(call = call, log = function() log, preflight_args = function() preflight_args,
    name_completion_args = function() name_completion_args)
}

manifest <- fixture_manifest()
manifest_sha <- sha("e")
expect(identical(canonical_name_completion_sha256(list(z = 1L, a = "ø",
  nested = list(y = FALSE, x = NULL))),
  "a198893d41f5f54b5fa8f9a4c4f53937ee4974749fce01ddb8b649c240a96c18"))
validate_name_completion_manifest(manifest)
expect(TRUE)
payloads <- authorized_name_payloads(manifest)
expect(identical(names(payloads), vapply(manifest$operations, `[[`, "", "element_id")))
expect(length(payloads) == 8L && is.null(payloads[[1L]]$element_id))

g <- fake_gateway()
result <- execute_name_completion(manifest, manifest_sha, "dry-run", g)
expect(identical(result$status, "finalized") && identical(result$committed, FALSE))
expect(length(result$result_map) == 8L &&
  identical(names(result$result_map), vapply(manifest$operations, `[[`, "", "element_id")) &&
  identical(names(result$result_map[[1L]]),
    c("person_id", "fact_id", "assertion_id", "citation_id", "conclusion_id")))
expect(identical(g$log(), c("connect", "begin", "advisory_lock", "preflight", "begin_batch",
  rep("name_completion", 8L), "finalize", "rollback")))
expect(length(g$preflight_args()) == 6L && is.null(g$preflight_args()[[4L]]) &&
  identical(g$preflight_args()[[6L]], "dry-run"))
disposable_envelope <- authorization_fixture("name_completion_rehearsal", "rehearsal-system")
g <- fake_gateway(authorization_envelope = disposable_envelope)
result <- execute_name_completion(manifest, manifest_sha, "dry-run", g)
expect(identical(result$authorization, disposable_envelope) &&
  identical(result$authorization$database_name, "name_completion_rehearsal"))

bad <- fixture_manifest(); bad$operations[[1L]]$verbatim_text <- "tampered text"
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_OPERATION_INVALID")
bad <- fixture_manifest(); bad$generator_version <- "tampered generator"
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_CONTENT_HASH_INVALID")
raw_manifest_path <- tempfile("name-completion-manifest-", fileext = ".json")
raw_output_path <- tempfile("name-completion-output-", fileext = ".json")
on.exit(unlink(c(raw_manifest_path, raw_output_path)), add = TRUE)
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = FALSE), raw_manifest_path,
  useBytes = TRUE)
raw_cli <- file.path(script_dir, "apply_name_completion_1939_v50.R")
raw_result <- suppressWarnings(system2("Rscript", c(raw_cli, "--manifest", raw_manifest_path,
  "--manifest-sha256", sha("f"), "--mode", "dry-run", "--output", raw_output_path),
  stdout = TRUE, stderr = TRUE))
expect(identical(as.integer(attr(raw_result, "status")), 1L) &&
  any(grepl("NAME_COMPLETION_1939_MANIFEST_HASH_INVALID", raw_result, fixed = TRUE)))
bad <- fixture_manifest(); bad$operations[[1L]]$verbatim_text <- "rehashable text"
bad$operations[[1L]]$verbatim_sha256 <- digest::digest(bad$operations[[1L]]$verbatim_text,
  algo = "sha256", serialize = FALSE)
bad <- rehash_manifest(bad)
validate_name_completion_manifest(bad)
g <- fake_gateway(preflight_result = list(valid = FALSE))
expect_error(execute_name_completion(bad, manifest_sha, "dry-run", g),
  "NAME_COMPLETION_1939_PREFLIGHT_INVALID")
expect(identical(tail(g$log(), 1L), "rollback"))
g <- fake_gateway(preflight_result = list(valid = TRUE, database_name = "wrong",
  system_identifier = "test-system-identifier", source_batch_id = manifest$source_batch_id,
  manifest_sha256 = manifest_sha))
expect_error(execute_name_completion(manifest, manifest_sha, "dry-run", g),
  "NAME_COMPLETION_1939_PREFLIGHT_INVALID")
expect(identical(tail(g$log(), 1L), "rollback"))
g <- fake_gateway(preflight_result = list(valid = TRUE, database_name = "name_completion_1939",
  system_identifier = "wrong", source_batch_id = manifest$source_batch_id,
  manifest_sha256 = manifest_sha))
expect_error(execute_name_completion(manifest, manifest_sha, "dry-run", g),
  "NAME_COMPLETION_1939_PREFLIGHT_INVALID")
expect(identical(tail(g$log(), 1L), "rollback"))
bad <- fixture_manifest(); bad$operations[[1L]]$source_payload_sha256 <- sha("f")
bad <- rehash_manifest(bad)
validate_name_completion_manifest(bad)
g <- fake_gateway(preflight_result = list(valid = FALSE))
expect_error(execute_name_completion(bad, manifest_sha, "dry-run", g),
  "NAME_COMPLETION_1939_PREFLIGHT_INVALID")
bad <- fixture_manifest(); bad$operations[[1L]]$source_persona_id <- "persona-rebound"
bad <- rehash_manifest(bad)
validate_name_completion_manifest(bad)
g <- fake_gateway(preflight_result = list(valid = FALSE))
expect_error(execute_name_completion(bad, manifest_sha, "dry-run", g),
  "NAME_COMPLETION_1939_PREFLIGHT_INVALID")
g <- fake_gateway()
invisible(execute_name_completion(manifest, manifest_sha, "dry-run", g))
expect(identical(g$preflight_args()[[1L]], manifest$source_batch_id) &&
  identical(g$preflight_args()[[2L]], manifest_sha) &&
  identical(g$preflight_args()[[3L]], authorized_name_payloads(manifest)) &&
  is.null(g$preflight_args()[[4L]]) && identical(g$preflight_args()[[5L]], manifest) &&
  identical(g$preflight_args()[[6L]], "dry-run"))
expect(length(g$name_completion_args()) == 8L && all(vapply(seq_along(manifest$operations),
  function(index) identical(g$name_completion_args()[[index]][[3L]],
    strip_transport(manifest$operations[[index]])), logical(1))))

g <- fake_gateway()
result <- execute_name_completion(manifest, manifest_sha, "apply", g, authorization_fixture())
expect(identical(result$committed, TRUE) && identical(tail(g$log(), 1L), "commit"))
expect(identical(g$preflight_args()[[4L]], authorization_fixture()$authorization_id))
g <- fake_gateway(resolved_authorization = authorization_fixture("another_database",
  "test-system-identifier"))
expect_error(execute_name_completion(manifest, manifest_sha, "apply", g, authorization_fixture()),
  "NAME_COMPLETION_1939_PREFLIGHT_INVALID")
expect(identical(tail(g$log(), 1L), "rollback"))
expect_error(execute_name_completion(manifest, manifest_sha, "apply", fake_gateway()),
  "NAME_COMPLETION_1939_AUTHORIZATION_REQUIRED")
for (bad_authorization in list(
    list(authorization_id = "9f7a80dc-7566-45dc-8a98-9d3c4ea7a312",
      database_name = "name_completion_1939"),
    c(authorization_fixture(), list(unexpected = TRUE)),
    list(authorization_id = "not-a-uuid", database_name = "name_completion_1939",
      system_identifier = "test-system-identifier"))) {
  expect_error(execute_name_completion(manifest, manifest_sha, "apply", fake_gateway(),
    bad_authorization), "NAME_COMPLETION_1939_AUTHORIZATION_INVALID")
}

for (stage in c("preflight", "begin_batch", "name_completion", "finalize")) {
  g <- fake_gateway(stage)
  expect_error(execute_name_completion(manifest, manifest_sha, "dry-run", g), paste0("FAIL_AT_", stage))
  expect(identical(tail(g$log(), 1L), "rollback"))
}

bad <- fixture_manifest(); bad$schema_version <- "other"
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$manifest_content_sha256 <- "not-a-hash"
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_HASH_INVALID")
bad <- fixture_manifest(); bad$operations <- rev(bad$operations)
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_ORDER_INVALID")
bad <- fixture_manifest(); bad$operations[[2L]]$person_id <- bad$operations[[1L]]$person_id
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_BINDING_INVALID")
bad <- fixture_manifest(); bad$operations[[2L]]$source_record_key <- bad$operations[[1L]]$source_record_key
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_BINDING_INVALID")
bad <- fixture_manifest(); bad$counts$name_completions <- 7L
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_COUNTS_INVALID")
bad <- fixture_manifest(); bad$expected_changes$persons_created <- 1L
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_EXPECTED_CHANGES_INVALID")
bad <- fixture_manifest(); bad$unknown <- TRUE
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$production_authorized <- TRUE
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$source_batch_id <- "wrong"
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_SOURCE_BATCH_INVALID")
bad <- fixture_manifest(); bad$source$source_id <- 4L
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_DATABASE_IDENTITY_INVALID")
bad <- fixture_manifest(); bad$source$source_id <- 3.5
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_DATABASE_IDENTITY_INVALID")
bad <- fixture_manifest(); bad$operations[[1L]]$person_id <- 1846.5
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_BINDING_INVALID")
bad <- fixture_manifest(); bad$operations[[1L]]$unknown <- TRUE
expect_error(validate_name_completion_manifest(bad), "NAME_COMPLETION_1939_OPERATION_INVALID")
expect_error(execute_name_completion(manifest, "not-a-hash", "dry-run", fake_gateway()),
  "NAME_COMPLETION_1939_MANIFEST_HASH_INVALID")
expect(identical(names(formals(execute_name_completion)),
  c("manifest", "manifest_sha256", "mode", "gateway", "authorization")))

gateway_body <- paste(deparse(body(new_name_completion_dbi_gateway)), collapse = "\n")
expect(!grepl("pg_advisory_xact_lock|current_database|pg_control_system|gen_random_uuid", gateway_body))
for (rpc in c("red_lock_1939_v50_name_completion($1)",
    "red_preflight_1939_v50_name_completion($1,$2,$3,$4::jsonb)",
    "red_authorize_1939_v50_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)",
    "red_begin_1939_v50_name_completion($1,$2,$3)",
    "red_apply_1939_v50_name_completion($1,$2,$3::jsonb)",
    "red_finalize_1939_v50_name_completion($1)"))
  expect(grepl(rpc, gateway_body, fixed = TRUE), rpc)
expect(grepl("red_authorize_1939_v50_name_completion($1,$2,$3,$4,$5::jsonb,$6::jsonb)::text AS value",
  gateway_body, fixed = TRUE))
expect(!grepl("authorization <- args[[4L]]", gateway_body, fixed = TRUE))

cat(sprintf("PASS %d assertions\n", ok))
