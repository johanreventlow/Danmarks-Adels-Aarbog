# DB-frie guards for promotion-requests. De returnerer kun eksplicitte
# assertion-mål og har ingen funktion, der kan skrive kanonisk genealogi.

evidence_nonempty <- function(value) {
  !is.null(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(as.character(value)))
}

promotion_request_reason <- function(row) {
  if (!is.list(row) || !evidence_nonempty(row$interpretation_id)) {
    return("EVIDENCE_PROMOTION_INTERPRETATION_INVALID")
  }
  if (!identical(row$target_type, "assertion") || is.null(row$target_id) ||
      length(row$target_id) != 1L || is.na(row$target_id) || !is.numeric(row$target_id) ||
      row$target_id < 1L || row$target_id != floor(row$target_id)) {
    return("EVIDENCE_PROMOTION_TARGET_INVALID")
  }
  NA_character_
}

build_promotion_requests <- function(rows) {
  if (!is.list(rows)) stop("EVIDENCE_PROMOTION_INPUT_INVALID")
  reasons <- vapply(rows, promotion_request_reason, character(1), USE.NAMES = FALSE)
  invalid <- which(!is.na(reasons) & nzchar(reasons))
  if (length(invalid)) stop(reasons[[invalid[[1L]]]])

  requests <- lapply(rows, function(row) {
    list(
      interpretation_id = trimws(as.character(row$interpretation_id)),
      target_type = "assertion",
      target_id = as.integer(row$target_id)
    )
  })
  order_key <- vapply(requests, `[[`, character(1), "interpretation_id")
  requests[order(order_key, method = "radix")]
}

summarize_promotion_requests <- function(rows) {
  if (!is.list(rows)) stop("EVIDENCE_PROMOTION_INPUT_INVALID")
  reasons <- lapply(rows, promotion_request_reason)
  valid_rows <- rows[is.na(unlist(reasons, use.names = FALSE))]
  rejected <- lapply(which(!is.na(unlist(reasons, use.names = FALSE))), function(index) {
    list(index = as.integer(index), reason = reasons[[index]])
  })
  requests <- if (length(valid_rows)) build_promotion_requests(valid_rows) else list()
  list(
    valid_count = as.integer(length(requests)),
    rejected_count = as.integer(length(rejected)),
    requests = requests,
    rejected = rejected
  )
}
