## Shared, pure, DB-free primitives for the 1939 v50 C3 export family.
## No `source()` calls live in this file (no reliable `__file__` inside a
## sourced file); every entry point (a runnable script or a test script)
## sources this file directly, alongside any task-specific helpers file.
## This file must never accept or emit narrative prose.

.c3_common_stop <- function(token) stop(token, call. = FALSE)

.c3_common_require_columns <- function(rows, required, token) {
  if (!is.data.frame(rows) || length(setdiff(required, names(rows))) > 0L)
    .c3_common_stop(token)
}

.c3_common_valid_ids <- function(values, allow_empty = FALSE) {
  if (!is.numeric(values) || (!allow_empty && length(values) == 0L)) return(FALSE)
  if (length(values) == 0L) return(TRUE)
  all(!is.na(values) & is.finite(values) & values > 0 & values == floor(values))
}

.c3_common_scalar_string <- function(value, pattern = NULL) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value))
    return(FALSE)
  is.null(pattern) || grepl(pattern, value, perl = TRUE)
}

.c3_common_optional_strings <- function(values) {
  is.character(values) && all(is.na(values) | nzchar(values))
}

## Generalized CLI flag parser: exactly `2 * length(allowed)` arguments,
## alternating `--flag value`, no unknown flags, no duplicate flags, no
## empty values. Returns a named list keyed by the flag names in `allowed`.
.c3_common_parse_flags <- function(args, allowed, token) {
  if (length(args) != 2L * length(allowed) ||
      any(seq_along(args) %% 2L == 0L & grepl("^--", args)) ||
      any(seq_along(args) %% 2L == 1L & !grepl("^--", args)))
    .c3_common_stop(token)
  flags <- args[seq.int(1L, length(args), by = 2L)]
  values <- args[seq.int(2L, length(args), by = 2L)]
  if (anyDuplicated(flags) || !setequal(flags, allowed) || any(!nzchar(values)))
    .c3_common_stop(token)
  stats::setNames(as.list(values), flags)[allowed]
}

## Refuse a pre-existing output path before any work begins. Not itself
## race-free against a concurrent creator (R has no dir_fd API to close that
## window); the atomic-link publish step downstream still fails safely on a
## genuine race, it just cannot distinguish EEXIST from other link errors as
## precisely as a descriptor-relative implementation could.
.c3_common_refuse_existing_output <- function(output_path, token) {
  if (file.exists(output_path)) .c3_common_stop(token)
}

## All-five-or-none PG environment variables, with SUPABASE_* fallback per
## variable. Returns a list(dbname/host/port/user/password, local = TRUE/FALSE)
## once port has been validated, or stops with `token` on any invalid shape.
.c3_common_pg_connection_values <- function(token_env, token_connection) {
  pg_names <- c("PGDATABASE", "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD")
  pg_set <- nzchar(Sys.getenv(pg_names))
  if (any(pg_set) && !all(pg_set)) .c3_common_stop(token_env)
  local_pg <- all(pg_set)
  env_or <- function(primary, fallback) {
    result <- Sys.getenv(primary)
    if (nzchar(result)) result else Sys.getenv(fallback)
  }
  values <- list(
    dbname = env_or("PGDATABASE", "SUPABASE_DB"),
    host = env_or("PGHOST", "SUPABASE_HOST"),
    port = env_or("PGPORT", "SUPABASE_PORT"),
    user = env_or("PGUSER", "SUPABASE_USER"),
    password = env_or("PGPASSWORD", "SUPABASE_PASSWORD")
  )
  port <- suppressWarnings(as.integer(values$port))
  if (any(!nzchar(unlist(values, use.names = FALSE))) ||
      is.na(port) || port < 1L || port > 65535L)
    .c3_common_stop(token_connection)
  list(dbname = values$dbname, host = values$host, port = port,
       user = values$user, password = values$password, local = local_pg)
}

## Read a whole file as raw bytes, failing closed with `token` on any read
## error or a non-positive/unreadable size. Mirrors the existing C3
## current-state exporter's input-reading discipline exactly.
.c3_common_read_regular_raw <- function(path, token) {
  tryCatch({
    size <- file.info(path)$size
    if (length(size) != 1L || is.na(size) || size <= 0) stop("invalid")
    readBin(path, what = "raw", n = size)
  }, error = function(e) .c3_common_stop(token))
}

## Publish `rendered` (a character scalar) to `output_path` durably and
## exclusively: write to a sibling temp file, hard-link it into place, then
## remove the temp name. Fails closed with `exists_token` if the destination
## already exists at link time, or `write_token` on any other failure.
.c3_common_publish_exclusive <- function(rendered, output_path, exists_token,
                                          write_token) {
  temporary <- tempfile(pattern = ".c3-export-", tmpdir = dirname(output_path))
  on.exit(unlink(temporary), add = TRUE)
  tryCatch(writeBin(charToRaw(enc2utf8(rendered)), temporary),
           error = function(e) .c3_common_stop(write_token))
  if (!isTRUE(file.link(temporary, output_path))) {
    if (file.exists(output_path)) .c3_common_stop(exists_token)
    .c3_common_stop(write_token)
  }
  unlink(temporary)
  invisible(TRUE)
}
