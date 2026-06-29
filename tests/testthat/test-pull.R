test_that("connect_readonly fails fast without creds", {
  withr::with_envvar(c(SUPABASE_HOST = "", SUPABASE_USER = "", SUPABASE_PASSWORD = ""), {
    expect_error(connect_readonly(), "SUPABASE_")
  })
})

test_that("ours_birth_death_sql selects via conclusion.valgt_assertion_id", {
  sql <- ours_birth_death_sql()
  expect_match(sql, "valgt_assertion_id")
  expect_match(sql, "fødsel|foedsel")
})
