root <- normalizePath(file.path(getwd(), "..", ".."))
old <- getwd(); on.exit(setwd(old),add=TRUE)
setwd(file.path(root,".claude","skills","daa-extract","scripts"))
source("test_apply_reimport_1939_v50.R",local=TRUE)
