# Trin 3: normalisering. Rene funktioner. Diakritik bevares ALTID.

.lower <- function(s) stringi::stri_trans_tolower(s, locale = "da_DK")

strip_titles <- function(s) {
  if (is.na(s)) return(s)
  pat <- "\\b(lensgreve|lensgrevinde|greve|grevinde|baron|baronesse|friherre|til|von|af)\\b"
  out <- gsub(pat, "", s, ignore.case = TRUE, perl = TRUE)
  trimws(gsub("\\s+", " ", out))
}

normalize_sex <- function(x) {
  x <- .lower(trimws(ifelse(is.na(x), "", x)))
  if (x %in% c("m", "mand", "male")) "mand"
  else if (x %in% c("f", "k", "kvinde", "female")) "kvinde"
  else "ukendt"
}

normalize_name <- function(first, last, married_in = FALSE) {
  first <- ifelse(is.na(first), "", first)
  last  <- ifelse(is.na(last), "", last)
  given <- trimws(strip_titles(first))
  surname_raw <- trimws(strip_titles(last))
  implicit <- FALSE
  if (surname_raw == "" && !married_in) { surname_raw <- "Reventlow"; implicit <- TRUE }
  key <- trimws(gsub("\\s+", " ", paste(.lower(given), .lower(surname_raw))))
  list(given = given, surname = .lower(surname_raw), key = key, implicit_surname = implicit)
}

parse_year_interval <- function(text) {
  if (is.na(text) || !nzchar(trimws(text))) return(c(NA_integer_, NA_integer_))
  t <- .lower(text)
  yrs <- as.integer(regmatches(t, gregexpr("\\d{3,4}", t))[[1]])
  if (!length(yrs)) return(c(NA_integer_, NA_integer_))
  if (grepl("\\d{3,4}\\s*[-–]\\s*\\d{3,4}", t) && length(yrs) >= 2)
    return(c(min(yrs), max(yrs)))
  if (grepl("\\b(ca\\.?|omkring|c\\.)\\b", t)) return(c(yrs[1] - 5L, yrs[1] + 5L))
  if (grepl("\\b(før|inden)\\b", t)) return(c(NA_integer_, yrs[1]))
  if (grepl("\\b(efter)\\b", t)) return(c(yrs[1], NA_integer_))
  c(yrs[1], yrs[1])
}

tng_date_to_interval <- function(d) {
  if (is.na(d) || !grepl("^\\d{4}-\\d{2}-\\d{2}$", d) || startsWith(d, "0000"))
    return(c(NA_integer_, NA_integer_))
  y <- as.integer(substr(d, 1, 4))
  c(y, y)
}

intervals_overlap <- function(a, b) {
  amin <- if (is.na(a[1])) -Inf else a[1]; amax <- if (is.na(a[2]))  Inf else a[2]
  bmin <- if (is.na(b[1])) -Inf else b[1]; bmax <- if (is.na(b[2]))  Inf else b[2]
  amin <= bmax && bmin <= amax
}
