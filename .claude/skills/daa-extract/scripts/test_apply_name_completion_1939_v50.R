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
      verbatim_text = text, verbatim_sha256 = sha(c("a", "b", "c", "d", "e", "f", "a", "b")[[index]]),
      source_payload_sha256 = sha(c("b", "c", "d", "e", "f", "a", "b", "c")[[index]]),
      expected_before = list(staged = TRUE, name_cache_empty = TRUE, name_facts = 0L),
      expected_after = list(name_fact = 1L, selected_assertion = 1L,
        daa_1939_citation = 1L, conclusion = 1L)
    )
  })
  list(
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
    production_authorized = FALSE, cutover_authorized = FALSE,
    manifest_content_sha256 = sha("d")
  )
}

fake_gateway <- function(fail_at = NULL) {
  log <- character()
  call <- function(name, ...) {
    log <<- c(log, name)
    if (identical(name, fail_at)) stop(paste0("FAIL_AT_", name), call. = FALSE)
    if (identical(name, "begin_batch")) return("completion-batch")
    if (identical(name, "finalize")) return(list(status = "finalized", batch_id = "completion-batch"))
    invisible(NULL)
  }
  list(call = call, log = function() log)
}

manifest <- fixture_manifest()
manifest_sha <- sha("e")
validate_name_completion_manifest(manifest)
expect(TRUE)
payloads <- authorized_name_payloads(manifest)
expect(identical(names(payloads), vapply(manifest$operations, `[[`, "", "element_id")))
expect(length(payloads) == 8L && is.null(payloads[[1L]]$element_id))

g <- fake_gateway()
result <- execute_name_completion(manifest, manifest_sha, "dry-run", g)
expect(identical(result$status, "finalized") && identical(result$committed, FALSE))
expect(identical(g$log(), c("connect", "begin", "advisory_lock", "preflight", "begin_batch",
  rep("name_completion", 8L), "finalize", "rollback")))

g <- fake_gateway()
result <- execute_name_completion(manifest, manifest_sha, "apply", g, list(id = "authorization"))
expect(identical(result$committed, TRUE) && identical(tail(g$log(), 1L), "commit"))
expect_error(execute_name_completion(manifest, manifest_sha, "apply", fake_gateway()),
  "NAME_COMPLETION_1939_AUTHORIZATION_REQUIRED")

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

cat(sprintf("PASS %d assertions\n", ok))
