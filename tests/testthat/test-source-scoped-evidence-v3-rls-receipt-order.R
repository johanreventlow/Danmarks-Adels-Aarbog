root <- normalizePath(file.path(getwd(), "..", ".."))

test_that("Task 4C checks its receipt before receipt-bound RLS ACL resets", {
  rls <- paste(readLines(file.path(root, "db-rls.sql"), warn = FALSE), collapse = "\n")
  marker <- "DO $source_scoped_evidence_v3_task4c_preflight_receipt$"
  preflight_positions <- gregexpr(marker, rls, fixed = TRUE)[[1]]
  preflight_positions <- preflight_positions[preflight_positions > 0L]

  expect_length(preflight_positions, 1L)
  expect_true(
    preflight_positions[[1]] < regexpr(
      "revoke execute on all functions in schema private from public, anon, authenticated;",
      rls,
      fixed = TRUE
    )[[1]],
    info = "Task 4C must reject receipt drift before the private-function ACL reset"
  )
  expect_true(
    preflight_positions[[1]] < regexpr(
      "grant select on table public.fact to anon;",
      rls,
      fixed = TRUE
    )[[1]],
    info = "Task 4C must reject receipt drift before fact/assertion/citation RLS is replaced"
  )
  expect_true(
    preflight_positions[[1]] < regexpr(
      "DO $redaction_rpc_allow_list$",
      rls,
      fixed = TRUE
    )[[1]],
    info = "Task 4C must reject receipt drift before the redaction RPC ACL reset"
  )
})
