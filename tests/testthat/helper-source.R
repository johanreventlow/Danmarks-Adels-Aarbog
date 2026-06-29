# Sources all pipeline modules so tests see their functions.
# testthat sets wd to tests/testthat during test_dir(); repo root = ../..
local({
  root <- normalizePath(file.path(getwd(), "..", ".."))
  qa <- file.path(root, "R", "tng-qa")
  files <- list.files(qa, pattern = "^[0-9].*\\.R$", full.names = TRUE)
  for (f in files) source(f)
})
