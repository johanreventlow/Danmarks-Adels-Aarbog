## #153 Task 4D.  The client-side preflight deliberately has no private
## database access.  Authorize/apply remeasure private state in PostgreSQL.

ssr_v3_stop <- function(code) stop(code, call. = FALSE)

ssr_v3_sha256 <- function(value) {
  is.character(value) && length(value) == 1L &&
    grepl("^[0-9a-f]{64}$", value)
}

ssr_v3_uuid <- function(value) {
  is.character(value) && length(value) == 1L &&
    grepl("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", value)
}

ssr_v3_validate_preflight_manifest <- function(manifest) {
  fields <- c(
    "manifest_semantic_sha256", "dry_run_semantic_sha256",
    "ownership_semantic_sha256", "deployment_id", "deployment_sha256"
  )
  if (!is.list(manifest) || !identical(sort(names(manifest)), sort(fields)) ||
      !all(vapply(manifest[fields[c(1L, 2L, 3L, 5L)]], ssr_v3_sha256, logical(1L))) ||
      !ssr_v3_uuid(manifest$deployment_id)) {
    ssr_v3_stop("SOURCE_SCOPED_REPLACE_MANIFEST_INVALID")
  }
  manifest[fields]
}

ssr_v3_preflight <- function(gateway, manifest) {
  if (!is.list(gateway) || !is.function(gateway$execute)) {
    ssr_v3_stop("SOURCE_SCOPED_EVIDENCE_V3_GATEWAY_INVALID")
  }
  checked <- ssr_v3_validate_preflight_manifest(manifest)
  gateway$execute("BEGIN READ ONLY")
  committed <- FALSE
  on.exit({
    if (!committed) gateway$execute("ROLLBACK")
  }, add = TRUE)
  gateway$execute("COMMIT")
  committed <- TRUE
  checked
}
