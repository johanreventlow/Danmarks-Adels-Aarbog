# Ren logik bag den interaktive review-app (review-app.R). Ingen Shiny-
# afhængighed her — kun data.frame-ind/ud, testbart uden en kørende app.
# Samme CSV-skema som merge_review_decisions() (05-review.R) forventer.

load_review_queue <- function(path) {
  if (!file.exists(path))
    stop(sprintf("Review-kø ikke fundet: %s (kør R/tng-qa/run-pipeline.R først)", path))
  read.csv(path, stringsAsFactors = FALSE, encoding = "UTF-8")
}

write_review_queue <- function(rq, path) {
  write.csv(rq, path, row.names = FALSE)
  invisible(rq)
}

# Opdaterer afgoerelse/ny_tng_id for ÉN specifik (person_id,tng_id)-kandidat.
# Validerer mod samme vokabular som merge_review_decisions() forstår.
set_decision <- function(rq, person_id, tng_id, afgoerelse, ny_tng_id = "") {
  gyldige <- c("", "bekræft", "afvis", "ny-id")
  if (!afgoerelse %in% gyldige)
    stop(sprintf("Ugyldig afgoerelse '%s' — skal være en af: %s",
                 afgoerelse, paste(gyldige, collapse = ", ")))
  if (identical(afgoerelse, "ny-id") && !nzchar(trimws(ny_tng_id)))
    stop("ny-id kræver et udfyldt ny_tng_id")
  row <- which(rq$person_id == person_id & rq$tng_id == tng_id)
  if (!length(row))
    stop(sprintf("Intet review-par for person_id=%s, tng_id=%s", person_id, tng_id))
  rq$afgoerelse[row] <- afgoerelse
  rq$ny_tng_id[row]  <- if (identical(afgoerelse, "ny-id")) ny_tng_id else ""
  rq
}

review_progress <- function(rq) {
  total     <- nrow(rq)
  besluttet <- sum(nzchar(rq$afgoerelse))
  list(total = total, besluttet = besluttet, resterende = total - besluttet)
}
