testthat::test_that("narrative-replacement writer R contract passes direct assertions", {
  root <- normalizePath(file.path(getwd(), "..", ".."))
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(file.path(root, ".claude", "skills", "daa-extract", "scripts"))
  testthat::expect_no_error(source("test_apply_narrative_replacement_1939_v50.R", local = TRUE))
})
