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
