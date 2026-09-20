#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || !identical(arguments[[1L]], "--dry-run")) {
  stop("EVIDENCE_PROJECTOR_PROMOTION_RPC_REQUIRED")
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_argument) != 1L) stop("EVIDENCE_PROJECTOR_SCRIPT_PATH_INVALID")
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument[[1L]])))
source(file.path(script_dir, "project_evidence_helpers.R"))

rows <- jsonlite::fromJSON(arguments[[2L]], simplifyVector = FALSE)
report <- summarize_promotion_requests(rows)
cat(jsonlite::toJSON(report, auto_unbox = TRUE, null = "null"), "\n", sep = "")
