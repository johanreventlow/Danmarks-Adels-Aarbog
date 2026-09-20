script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- if (!is.na(script_arg) && !identical(script_arg, "--file=-e")) {
  dirname(normalizePath(sub("^--file=", "", script_arg)))
} else {
  getwd()
}
source(file.path(script_dir, "apply_source_scoped_evidence_v3_helpers.R"))
apply_script <- file.path(script_dir, "apply_source_scoped_evidence_v3.R")
if (!file.exists(apply_script)) {
  stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_MISSING", call. = FALSE)
}
source(apply_script)

expect <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(error) conditionMessage(error))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

manifest <- list(
  manifest_semantic_sha256 = paste(rep("a", 64L), collapse = ""),
  dry_run_semantic_sha256 = paste(rep("b", 64L), collapse = ""),
  ownership_semantic_sha256 = paste(rep("c", 64L), collapse = ""),
  deployment_id = "00000000-0000-0000-0000-000000000153",
  deployment_sha256 = paste(rep("d", 64L), collapse = "")
)

fake_gateway <- function() {
  calls <- character()
  list(
    execute = function(sql, params = list()) {
      calls <<- c(calls, sql)
      if (identical(sql, "BEGIN READ ONLY")) return(invisible(NULL))
      if (identical(sql, "ROLLBACK")) return(invisible(NULL))
      if (identical(sql, "COMMIT")) return(invisible(NULL))
      stop("SOURCE_SCOPED_EVIDENCE_GATEWAY_UNEXPECTED_SQL", call. = FALSE)
    },
    query_one = function(sql, params = list()) stop("SOURCE_SCOPED_EVIDENCE_GATEWAY_PRIVATE_QUERY", call. = FALSE),
    calls = function() calls
  )
}

gateway <- fake_gateway()
preflight <- ssr_v3_preflight(gateway, manifest)
expect(identical(preflight$manifest_semantic_sha256, manifest$manifest_semantic_sha256),
       "SOURCE_SCOPED_EVIDENCE_V3_PREFLIGHT_MANIFEST_INVALID")
expect(identical(gateway$calls(), c("BEGIN READ ONLY", "COMMIT")),
       "SOURCE_SCOPED_EVIDENCE_V3_PREFLIGHT_NOT_READ_ONLY")

bad_manifest <- manifest
bad_manifest$deployment_id <- "not-a-uuid"
expect_error(ssr_v3_preflight(fake_gateway(), bad_manifest), "SOURCE_SCOPED_REPLACE_MANIFEST_INVALID")

expect(!any(grepl("dbAppendTable", readLines(file.path(script_dir, "apply_source_scoped_evidence_v3_helpers.R")), fixed = TRUE)),
       "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_DIRECT_MODEL_WRITER")

apply_request <- list(
  database_name = "daa153_test",
  system_identifier = "0000000000000000",
  deployment_id = manifest$deployment_id,
  actor_id = "00000000-0000-0000-0000-000000000154",
  nonce = "00000000-0000-0000-0000-000000000155",
  manifest_json = "{\"schema\":\"source-scoped-replace-v3-semantic-v1\"}",
  manifest_semantic_sha256 = manifest$manifest_semantic_sha256,
  dry_run_semantic_sha256 = manifest$dry_run_semantic_sha256,
  ownership_semantic_sha256 = manifest$ownership_semantic_sha256,
  artifact_sha256 = paste(rep("e", 64L), collapse = ""),
  expires_at = "2026-09-02T12:00:00Z",
  deployment_sha256 = manifest$deployment_sha256
)

receipt <- list(
  schema = "source-scoped-evidence-v3-apply-receipt-v1",
  authorization_id = "00000000-0000-0000-0000-000000000156",
  batch_id = "00000000-0000-0000-0000-000000000157",
  terminal_status = "applied",
  manifest_semantic_sha256 = manifest$manifest_semantic_sha256,
  observed_counts = list(
    source_operations = 1,
    content_revisions = 1,
    tombstone_revisions = 0,
    facts = 1,
    assertions = 1,
    citations = 1,
    narrative_operations = 0
  ),
  verified_state = list(
    schema = "source-scoped-evidence-v3-verified-state-v1",
    source_operations = list(),
    narrative_operations = list()
  )
)

verify_response <- list(
  receipt = receipt,
  apply_state = receipt$verified_state,
  publication_state = list(
    schema = "source-scoped-evidence-v3-publication-state-v1",
    chains = list()
  )
)

apply_gateway <- function(
  apply_response = list(replayed = FALSE, receipt = receipt),
  verify_result = verify_response
) {
  rpc_calls <- list()
  list(
    execute = fake_gateway()$execute,
    rpc = function(name, params) {
      rpc_calls[[length(rpc_calls) + 1L]] <<- list(name = name, params = params)
      if (identical(name, "public.red_authorize_source_scoped_replace_v3")) {
        return(list(id = "00000000-0000-0000-0000-000000000156"))
      }
      if (identical(name, "public.red_apply_source_scoped_replace_v3")) {
        return(apply_response)
      }
      if (identical(name, "public.red_verify_source_scoped_replace_v3")) {
        return(verify_result)
      }
      stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_UNEXPECTED_RPC", call. = FALSE)
    },
    rpc_calls = function() rpc_calls
  )
}

gateway <- apply_gateway()
result <- ssr_apply_v3(gateway, apply_request)
expect(identical(result$authorization_id, "00000000-0000-0000-0000-000000000156"),
       "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_AUTHORIZATION_INVALID")
expect(identical(result$apply$replayed, FALSE),
       "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_APPLY_RESPONSE_INVALID")
expect(identical(vapply(gateway$rpc_calls(), `[[`, "", "name"), c(
  "public.red_authorize_source_scoped_replace_v3",
  "public.red_apply_source_scoped_replace_v3",
  "public.red_verify_source_scoped_replace_v3"
)), "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_RPC_ALLOWLIST_INVALID")
expect(!any(grepl("dbAppendTable", readLines(apply_script), fixed = TRUE)),
       "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_DIRECT_MODEL_WRITER")

expect_error(
  ssr_apply_v3(apply_gateway(list(status = "applied")), apply_request),
  "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_APPLY_INVALID"
)
expect_error(
  ssr_apply_v3(apply_gateway(verify_result = list(apply_state = list())), apply_request),
  "SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_VERIFY_INVALID"
)

cat("PASS source-scoped evidence V3 gateway preflight\n")
