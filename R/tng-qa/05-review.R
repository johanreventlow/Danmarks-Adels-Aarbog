# Trin 5: flet manuelle review-afgørelser ind. Idempotent.

merge_review_decisions <- function(crosswalk, decisions) {
  cw <- crosswalk
  # Robust mod en review-kø UDEN udfyldte afgørelser (fx en frisk kø fra forrige
  # run): mangler `afgoerelse`-kolonnen helt -> intet at flette.
  if (is.null(decisions[["afgoerelse"]])) return(cw)
  for (i in seq_len(nrow(decisions))) {
    a <- decisions$afgoerelse[i]
    if (is.na(a) || !nzchar(trimws(a))) next   # tom/uudfyldt afgørelse -> spring over
    pid <- decisions$person_id[i]
    row <- which(cw$person_id == pid)
    if (!length(row)) next
    if (a == "bekræft") cw$tier[row] <- "accepted"
    else if (a == "afvis") cw$tier[row] <- "afvist"
    else if (a == "ny-id") { cw$tng_id[row] <- decisions$ny_tng_id[i]; cw$tier[row] <- "accepted" }
  }
  cw
}

accepted_crosswalk <- function(crosswalk) {
  crosswalk[crosswalk$tier %in% c("auto", "accepted"), c("person_id", "tng_id")]
}
