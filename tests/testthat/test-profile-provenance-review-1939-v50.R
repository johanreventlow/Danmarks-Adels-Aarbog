root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(
  root, ".claude", "skills", "daa-extract", "scripts",
  "test_profile_provenance_review_1939_v50.R"
), local = TRUE)
