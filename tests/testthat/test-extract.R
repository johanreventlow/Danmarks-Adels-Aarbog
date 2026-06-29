test_that("fix_mysql_literals converts escaping to DuckDB form", {
  expect_equal(fix_mysql_literals("INSERT INTO `t` VALUES (1,'O\\'Brien')"),
               'INSERT INTO "t" VALUES (1,\'O\'\'Brien\')')
  expect_equal(fix_mysql_literals("(1,'a\\\\b')"), "(1,'a\\b')")  # \\ -> \
  expect_equal(fix_mysql_literals("(1,'s3\\\"x')"), "(1,'s3\"x')") # \" -> "
})
