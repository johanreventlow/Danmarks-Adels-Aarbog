# Kontrakttests for den fail-closed promotion-adapter. Ingen test giver en
# accepteret fortolkning lov til at oprette eller ændre kanonisk genealogi.
root <- normalizePath(getwd())
while (!file.exists(file.path(root, ".git")) && dirname(root) != root) root <- dirname(root)
helpers <- file.path(root, ".claude", "skills", "daa-extract", "scripts", "project_evidence_helpers.R")
script <- file.path(root, ".claude", "skills", "daa-extract", "scripts", "project_evidence.R")
source(helpers)

testthat::test_that("promotion requests kræver eksplicit assertion-mål", {
  testthat::expect_equal(
    build_promotion_requests(list(
      list(interpretation_id = "i-2", target_type = "assertion", target_id = 42L),
      list(interpretation_id = "i-1", target_type = "assertion", target_id = 41L)
    )),
    list(
      list(interpretation_id = "i-1", target_type = "assertion", target_id = 41L),
      list(interpretation_id = "i-2", target_type = "assertion", target_id = 42L)
    )
  )
  testthat::expect_error(
    build_promotion_requests(list(list(interpretation_id = "i-1", target_type = "person", target_id = 41L))),
    "EVIDENCE_PROMOTION_TARGET_INVALID"
  )
  testthat::expect_error(
    build_promotion_requests(list(list(interpretation_id = "i-1", target_type = "assertion"))),
    "EVIDENCE_PROMOTION_TARGET_INVALID"
  )
})

testthat::test_that("accepteret status alene kan ikke blive til en person", {
  testthat::expect_error(
    build_promotion_requests(list(list(interpretation_id = "i-1", status = "accepted"))),
    "EVIDENCE_PROMOTION_TARGET_INVALID"
  )
})

testthat::test_that("dry-run rapporterer kun requests og afviser skrivevej", {
  input <- tempfile(fileext = ".json")
  on.exit(unlink(input), add = TRUE)
  jsonlite::write_json(list(
    list(interpretation_id = "i-1", target_type = "assertion", target_id = 41L),
    list(interpretation_id = "i-2", target_type = "person", target_id = 42L)
  ), input, auto_unbox = TRUE)

  dry_run <- system2("Rscript", c(script, "--dry-run", input), stdout = TRUE, stderr = TRUE)
  testthat::expect_equal(attr(dry_run, "status"), NULL)
  report <- jsonlite::fromJSON(paste(dry_run, collapse = "\n"), simplifyVector = FALSE)
  testthat::expect_equal(report$valid_count, 1L)
  testthat::expect_equal(report$rejected_count, 1L)
  testthat::expect_equal(report$requests, list(list(interpretation_id = "i-1", target_type = "assertion", target_id = 41L)))

  blocked <- suppressWarnings(system2("Rscript", c(script, input), stdout = TRUE, stderr = TRUE))
  testthat::expect_equal(attr(blocked, "status"), 1L)
  testthat::expect_match(paste(blocked, collapse = "\n"), "EVIDENCE_PROJECTOR_PROMOTION_RPC_REQUIRED")
})
