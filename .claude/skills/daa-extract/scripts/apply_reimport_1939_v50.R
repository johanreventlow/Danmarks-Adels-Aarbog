#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly=TRUE)
allowed <- c("--manifest","--manifest-sha256","--preview-sha256","--dry-run","--apply","--authorization")
if (any(!args[grepl("^--",args)] %in% allowed)) stop("REIMPORT_1939_CLI_INVALID",call.=FALSE)
value <- function(flag) { i<-match(flag,args); if(is.na(i)||i==length(args)) stop("REIMPORT_1939_CLI_INVALID",call.=FALSE); args[[i+1L]] }
mode <- if("--dry-run" %in% args) "dry-run" else if("--apply" %in% args) "apply" else stop("REIMPORT_1939_CLI_INVALID",call.=FALSE)
if (all(c("--dry-run","--apply") %in% args) || (mode=="dry-run" && "--authorization" %in% args)) stop("REIMPORT_1939_CLI_INVALID",call.=FALSE)
script_arg <- grep("^--file=",commandArgs(),value=TRUE)[1]; script_dir <- dirname(normalizePath(sub("^--file=","",script_arg)))
source(file.path(script_dir,"apply_reimport_1939_v50_helpers.R"))
raw <- readBin(value("--manifest"),"raw",n=file.info(value("--manifest"))$size)
if (!identical(digest::digest(raw,algo="sha256",serialize=FALSE),value("--manifest-sha256"))) stop("REIMPORT_1939_MANIFEST_HASH_INVALID",call.=FALSE)
manifest <- jsonlite::fromJSON(rawToChar(raw),simplifyVector=FALSE)
authorization <- if(mode=="apply") jsonlite::fromJSON(value("--authorization"),simplifyVector=FALSE) else NULL
gateway <- new_default_reimport_dbi_gateway()
result <- execute_reimport(manifest,value("--preview-sha256"),mode,gateway,authorization)
cat(jsonlite::toJSON(result,auto_unbox=TRUE,pretty=TRUE),"\n")
