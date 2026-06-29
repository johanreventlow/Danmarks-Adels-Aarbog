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
