script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "preview_narrative_publication_1939_v50_helpers.R"))

ok <- 0L
expect <- function(value, message = "expectation failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
  ok <<- ok + 1L
}
expect_error <- function(expr, pattern) {
  got <- tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
  expect(grepl(pattern, got, fixed = TRUE), paste(pattern, got))
}

fixture_manifest <- function() {
  value <- list(
    schema_version = "1939-v50-narrative-publication-manifest-v1",
    generator_version = "test",
    database_identity = "7642734024280108049",
    source_batch_id = "560c39f8-5c87-4c0d-a768-025d97fa2974",
    completion_batch_id = "0b0055f6-9ad4-4f09-8f23-b8976d8f1996",
    input_hashes = list(
      cutover_preview_sha256 = "8ab606f55f28e763786568bfa9bb9def829f19bd724c53d4ce6cd560465b63c7",
      name_completion_verification_sha256 = "b452983d3488b2517da1e404855a5b1da2fbb107a54cee57f056f4f25b7b56db"
    ),
    bindings = publication_locked_rows,
    counts = list(bindings = 8L),
    expected_changes = list(bindings_published = 8L, persons_activated = 0L,
      persons_created = 0L, facts_created = 0L, relations_created = 0L,
      families_created = 0L),
    production_authorized = FALSE,
    cutover_authorized = FALSE
  )
  value$manifest_content_sha256 <- canonical_publication_sha256(value)
  value
}

fake_gateway <- function(fail_at = NULL, preflight = NULL, verify = NULL) {
  log <- character()
  published <- list()
  call <- function(name, ...) {
    args <- list(...)
    log <<- c(log, name)
    if (identical(name, fail_at)) stop(paste0("FAIL_AT_", name), call. = FALSE)
    if (identical(name, "preflight")) return(if (is.null(preflight)) list(
      database_name = "postgres", system_identifier = "7642734024280108049",
      matched_bindings = 8L, draft_bindings = 8L
    ) else preflight)
    if (identical(name, "publish")) {
      published <<- c(published, list(args[[1L]]))
      return(args[[1L]]$binding_id)
    }
    if (identical(name, "verify")) return(if (is.null(verify)) list(
      published_bindings = 8L,
      binding_ids = vapply(publication_locked_rows, `[[`, "", "binding_id"),
      record_refs = vapply(publication_locked_rows, `[[`, "", "record_ref")
    ) else verify)
    invisible(NULL)
  }
  list(call = call, log = function() log, published = function() published)
}

manifest <- fixture_manifest()
validate_publication_manifest(manifest)
expect(TRUE)
published_rows <- data.frame(
  binding_id=vapply(publication_locked_rows,`[[`,"","binding_id"),
  narrative_id=vapply(publication_locked_rows,`[[`,integer(1),"narrative_id"),
  person_id=vapply(publication_locked_rows,`[[`,integer(1),"person_id"),
  source_record_id=vapply(publication_locked_rows,`[[`,"","source_record_id"),
  record_key=vapply(publication_locked_rows,`[[`,"","record_key"),
  record_ref=vapply(publication_locked_rows,`[[`,"","record_ref"),
  record_label=vapply(publication_locked_rows,`[[`,"","record_label"),
  citation_label=vapply(publication_locked_rows,`[[`,"","citation_label"),
  page=vapply(publication_locked_rows,`[[`,"","page"),
  expected_status=rep("published",8L),stringsAsFactors=FALSE)
expect(publication_rows_match(published_rows,manifest,"published"))

g <- fake_gateway()
result <- execute_publication_preview(manifest, paste(rep("a", 64L), collapse = ""), g)
expect(identical(result$committed, FALSE) && identical(result$status, "dry_run_complete"))
expect(identical(g$log(), c("connect", "begin", "preflight", rep("publish", 8L),
  "verify", "rollback")))
expect(length(g$published()) == 8L &&
  identical(vapply(g$published(), `[[`, "", "binding_id"),
    vapply(publication_locked_rows, `[[`, "", "binding_id")))

g <- fake_gateway(preflight=list(database_name="daa1939_local_restore",
  system_identifier="7657242220770903427",matched_bindings=8L,draft_bindings=8L))
local_result <- execute_publication_preview(manifest,paste(rep("a",64L),collapse=""),g)
expect(identical(local_result$database_identity,"7657242220770903427") &&
  identical(local_result$committed,FALSE))

bad <- fixture_manifest(); bad$bindings[[1L]]$record_label <- "drift";
bad$manifest_content_sha256 <- NULL; bad$manifest_content_sha256 <- canonical_publication_sha256(bad)
expect_error(validate_publication_manifest(bad), "NARRATIVE_PUBLICATION_1939_BINDING_INVALID")
bad <- fixture_manifest(); bad$bindings <- rev(bad$bindings)
expect_error(validate_publication_manifest(bad), "NARRATIVE_PUBLICATION_1939_BINDING_INVALID")
bad <- fixture_manifest(); bad$unexpected <- TRUE
expect_error(validate_publication_manifest(bad), "NARRATIVE_PUBLICATION_1939_MANIFEST_INVALID")
bad <- fixture_manifest(); bad$manifest_content_sha256 <- paste(rep("f",64L),collapse="")
expect_error(validate_publication_manifest(bad), "NARRATIVE_PUBLICATION_1939_CONTENT_HASH_INVALID")
expect_error(execute_publication_preview(manifest, "bad-hash", fake_gateway()),
  "NARRATIVE_PUBLICATION_1939_MANIFEST_HASH_INVALID")

g <- fake_gateway(preflight = list(database_name = "postgres", system_identifier = "wrong",
  matched_bindings = 8L, draft_bindings = 8L))
expect_error(execute_publication_preview(manifest, paste(rep("a",64L),collapse=""), g),
  "NARRATIVE_PUBLICATION_1939_PREFLIGHT_INVALID")
expect(identical(tail(g$log(),1L), "rollback"))
g <- fake_gateway(verify = list(published_bindings = 7L,
  binding_ids = vapply(publication_locked_rows, `[[`, "", "binding_id"),
  record_refs = vapply(publication_locked_rows, `[[`, "", "record_ref")))
expect_error(execute_publication_preview(manifest, paste(rep("a",64L),collapse=""), g),
  "NARRATIVE_PUBLICATION_1939_VERIFY_INVALID")
expect(identical(tail(g$log(),1L), "rollback"))
for (stage in c("preflight","publish","verify")) {
  g <- fake_gateway(fail_at = stage)
  expect_error(execute_publication_preview(manifest, paste(rep("a",64L),collapse=""), g),
    paste0("FAIL_AT_",stage))
  expect(identical(tail(g$log(),1L), "rollback"))
}

manifest_path <- tempfile("narrative-publication-manifest-",fileext=".json")
output_path <- tempfile("narrative-publication-output-",fileext=".json")
on.exit(unlink(c(manifest_path,output_path)),add=TRUE)
writeLines(jsonlite::toJSON(manifest,auto_unbox=TRUE,pretty=FALSE),manifest_path,useBytes=TRUE)
cli <- file.path(script_dir,"preview_narrative_publication_1939_v50.R")
cli_result <- suppressWarnings(system2("Rscript",c(cli,"--manifest",manifest_path,
  "--manifest-sha256",paste(rep("f",64L),collapse=""),"--output",output_path),
  stdout=TRUE,stderr=TRUE))
expect(identical(as.integer(attr(cli_result,"status")),1L) &&
  any(grepl("NARRATIVE_PUBLICATION_1939_MANIFEST_HASH_INVALID",cli_result,fixed=TRUE)))

cat(sprintf("PASS %d assertions\n", ok))
