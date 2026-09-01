testthat::test_that("generic reimport writer owns every formerly 1939-specific literal", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
  read_segment <- function(path, start, end) {
    lines <- readLines(file.path(root, path), warn = FALSE)
    paste(lines[seq.int(start, end)], collapse = "\n")
  }
  schema_writer <- read_segment("schema.sql", 2324L, 3098L)
  schema_all <- paste(readLines(file.path(root, "schema.sql"), warn = FALSE), collapse = "\n")
  migration <- paste(readLines(file.path(root, "db-migrations.sql"), warn = FALSE), collapse = "\n")
  migration_writer <- sub("(?s)^.*?CREATE OR REPLACE FUNCTION private\\.require_reimport_1939_editor", "CREATE OR REPLACE FUNCTION private.require_reimport_1939_editor", migration, perl = TRUE)
  migration_writer <- sub("(?s)REVOKE ALL ON FUNCTION public\\.red_authorize_1939_v50_reimport.*$", "", migration_writer, perl = TRUE)

  inventory <- data.frame(
    literal = c("source_id=3", "sr.source_id<>3", "sp.source_id<>3", "=8", "<>8", "DAA 1939 side", "reimport-1939-v50:", "daa-1939-v50-name-completion"),
    classification = c("profile", "profile", "profile", "manifest", "manifest", "profile", "manifest", "legacy_wrapper"),
    generic_target = c("source_id", "source_id", "source_id", "expected_counts", "expected_counts", "citation_label_template", "run_key_prefix", "generic_name_completion_lock"),
    test_name = c("profile identity", "source record validation", "persona validation", "completion cardinality", "completion cardinality", "citation label", "extraction run key", "legacy facade lock"),
    stringsAsFactors = FALSE
  )
  patterns <- c("source_id\\s*=\\s*3", "sr\\.source_id\\s*<>\\s*3", "sp\\.source_id\\s*<>\\s*3", "=8", "<>8", "DAA 1939 side", "reimport-1939-v50:", "daa-1939-v50-name-completion")

  testthat::expect_identical(names(inventory), c("literal", "classification", "generic_target", "test_name"))
  testthat::expect_true(all(inventory$classification %in% c("generic_invariant", "profile", "manifest", "legacy_wrapper")))
  occurrences <- function(text, pattern, file) {
    hits <- gregexpr(pattern,text,perl=TRUE)[[1L]]
    if (identical(hits, -1L)) return(character())
    starts <- nchar(substring(text,1L,hits-1L))+1L
    paste0(file,":",vapply(starts,function(start) sum(strsplit(substring(text,1L,start),"\\n",fixed=TRUE)[[1L]]=="") + 1L,integer(1)))
  }
  for (i in seq_along(patterns)) {
    observed <- c(occurrences(schema_writer,patterns[[i]],"schema.sql"),occurrences(migration_writer,patterns[[i]],"db-migrations.sql"))
    testthat::expect_gt(length(observed),0L)
    testthat::expect_true(all(inventory$literal[[i]] %in% inventory$literal))
  }

  generic_names <- c("red_authorize_reimport","red_begin_reimport","red_apply_reimport_source_evidence","red_apply_reimport_person_create","red_finalize_reimport","red_authorize_reimport_reversal","red_reverse_reimport","red_authorize_reimport_cutover","red_activate_reimport_batch")
  generic_definitions <- lapply(generic_names, function(name) regmatches(schema_all, regexpr(paste0("(?s)CREATE(?: OR REPLACE)? FUNCTION public\\\\.",name,"\\\\b.*?\\\\$\\\\$;"), schema_all, perl = TRUE)))
  names(generic_definitions) <- generic_names
  testthat::expect_true(all(lengths(generic_definitions)==1L))
  if (any(lengths(generic_definitions)!=1L)) return(invisible())
  for (definition in generic_definitions) {
    testthat::expect_match(definition, "daa-narrative-record-contract")
    testthat::expect_match(definition, "REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED")
    testthat::expect_false(grepl("(INSERT|UPDATE|DELETE) (INTO )?(public\\.narrative|private\\.narrative_record_publication)", definition, perl = TRUE))
  }
  generic_person_create <- generic_definitions[["red_apply_reimport_person_create"]]
  testthat::expect_match(generic_person_create, "red_upsert_person_narrative_record")
  testthat::expect_match(generic_person_create, "state_sha256")
  testthat::expect_false(grepl("source_id\\s*(=|<>)\\s*(3|8)|DAA 1939 side|reimport-1939-v50:|daa-1939-v50-name-completion", generic_person_create, perl = TRUE))
})
