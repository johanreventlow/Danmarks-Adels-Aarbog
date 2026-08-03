# Tynder wrapper så Task 14-kontrakten faktisk indgår i Rscript run-tests.R.
root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(root, ".claude", "skills", "daa-extract", "scripts", "test_project_evidence.R"), local = TRUE)
