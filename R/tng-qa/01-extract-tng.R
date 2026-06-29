# Trin 1: TNG-dump (MySQL) -> lokal DuckDB. Kun funktions-definitioner.

# Konverter mysqldump-escaping til DuckDB-kompatibel SQL.
fix_mysql_literals <- function(s) {
  SENT <- "\001BSLASH\001"                            # sentinel, optræder ikke i dumps
  s <- gsub("\\\\\\\\", SENT, s, perl = TRUE)         # \\  -> sentinel
  s <- gsub("\\\\'", "''", s, perl = TRUE)          # \'  -> ''
  s <- gsub('\\\\"', '"', s, perl = TRUE)           # \"  -> "
  s <- gsub(SENT, "\\", s, fixed = TRUE)                # sentinel -> single backslash
  s <- gsub("`", '"', s, fixed = TRUE)              # backtick-identifiers -> double quotes
  s
}

tng_create_columns <- function(dump_path, table) {
  lines <- readLines(dump_path, warn = FALSE)
  start <- grep(sprintf("^CREATE TABLE `%s`", table), lines)
  if (!length(start)) stop(sprintf("CREATE TABLE `%s` ikke fundet", table))
  end <- grep("^\\)", lines)
  end <- end[end > start[1]][1]
  body <- lines[(start[1] + 1):(end - 1)]
  col_lines <- grep("^\\s+`", body, value = TRUE)
  sub("^\\s+`([^`]+)`.*$", "\\1", col_lines)
}

load_tng_table <- function(con, dump_path, table) {
  cols <- tng_create_columns(dump_path, table)
  DBI::dbExecute(con, sprintf('DROP TABLE IF EXISTS "%s"', table))
  coldef <- paste(sprintf('"%s" VARCHAR', cols), collapse = ", ")
  DBI::dbExecute(con, sprintf('CREATE TABLE "%s" (%s)', table, coldef))
  lines <- readLines(dump_path, warn = FALSE)
  ins <- grep(sprintf("^INSERT INTO `%s` VALUES", table), lines, value = TRUE)
  n <- 0L
  for (stmt in ins) {
    fixed <- fix_mysql_literals(stmt)
    DBI::dbExecute(con, fixed)
  }
  DBI::dbGetQuery(con, sprintf('SELECT COUNT(*) AS n FROM "%s"', table))$n
}

build_tng_duckdb <- function(dump_path, db_path,
                             tables = c("tng_people", "tng_families",
                                        "tng_children", "tng_associations")) {
  if (file.exists(db_path)) unlink(db_path)
  con <- DBI::dbConnect(duckdb::duckdb(), db_path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  for (t in tables) {
    n <- load_tng_table(con, dump_path, t)
    message(sprintf("TNG %s: %d rækker", t, n))
  }
  db_path
}
