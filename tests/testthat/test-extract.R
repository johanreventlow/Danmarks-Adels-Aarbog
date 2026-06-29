test_that("fix_mysql_literals converts escaping to DuckDB form", {
  expect_equal(fix_mysql_literals("INSERT INTO `t` VALUES (1,'O\\'Brien')"),
               'INSERT INTO "t" VALUES (1,\'O\'\'Brien\')')
  expect_equal(fix_mysql_literals("(1,'a\\\\b')"), "(1,'a\\b')")  # \\ -> \
  expect_equal(fix_mysql_literals("(1,'s3\\\"x')"), "(1,'s3\"x')") # \" -> "
})

test_that("build_tng_duckdb loads people with columns and escaping", {
  dump <- testthat::test_path("fixtures", "mini-tng.sql")
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)
  build_tng_duckdb(dump, db, tables = "tng_people")
  con <- DBI::dbConnect(duckdb::duckdb(), db)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  ppl <- DBI::dbGetQuery(con, 'SELECT * FROM tng_people ORDER BY "personID"')
  expect_equal(nrow(ppl), 2L)
  expect_equal(ppl$firstname, c("Conrad", "O'Hara"))
  expect_equal(ppl$living, c("0", "0"))
})

test_that("build_tng_duckdb loads column-list multi-line INSERT (real dump format)", {
  dump <- testthat::test_path("fixtures", "mini-tng-collist.sql")
  db <- tempfile(fileext = ".duckdb")
  on.exit(unlink(db), add = TRUE)
  build_tng_duckdb(dump, db, tables = "tng_people")
  con <- DBI::dbConnect(duckdb::duckdb(), db)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  ppl <- DBI::dbGetQuery(con, 'SELECT * FROM tng_people ORDER BY "personID"')
  expect_equal(nrow(ppl), 2L)
  expect_equal(ppl$personID, c("I1", "I2"))
  expect_equal(ppl$firstname, c("Conrad", "Sophie"))
})
