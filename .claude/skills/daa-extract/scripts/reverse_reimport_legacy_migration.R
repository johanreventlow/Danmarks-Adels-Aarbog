#!/usr/bin/env Rscript
# #166 149b Task 9b: fortryd en hel legacy-migration-batch (spec §8).
#
#   Rscript reverse_reimport_legacy_migration.R \
#     --batch-id UUID --authorization UUID (--dry-run|--apply)
#
# Autorisationen udstedes på forhånd med
# public.red_authorize_reimport_reversal(batch_id, nonce, expiry) af samme aktør,
# som scriptet kører som (DAA_REIMPORT_ACTOR_ID).  --dry-run kører hele kæden og
# ruller tilbage; --apply committer.  Databaseforbindelsen skal være privilegeret:
# fortryd-RPC'erne og de to private 149b-hjælpere er REVOKED for alle klientroller.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(script_dir, "reverse_reimport_legacy_migration_helpers.R"))

cli <- parse_legacy_reversal_cli(args)
result <- execute_legacy_reversal(cli$batch_id, cli$authorization_id, cli$mode,
  new_default_legacy_reversal_dbi_gateway())
cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), "\n")
