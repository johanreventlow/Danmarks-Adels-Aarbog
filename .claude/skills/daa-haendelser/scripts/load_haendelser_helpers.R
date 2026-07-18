# Rene, DB-frie helpers til load_haendelser.R.

normaliser_date_raw <- function(x) {
  if (is.null(x) || length(x) == 0L || is.na(x) || !nzchar(trimws(x))) return(NA_character_)
  tolower(trimws(gsub("\\s+", " ", as.character(x))))
}

genberegn_span <- function(tekst, klausul, brugte_offsets = integer()) {
  if (is.null(tekst) || is.null(klausul) || is.na(tekst) || is.na(klausul) || !nzchar(klausul))
    return(list(start = NA_integer_, laengde = NA_integer_, brugte_offsets = brugte_offsets))
  hits <- gregexpr(klausul, tekst, fixed = TRUE)[[1]]
  if (length(hits) == 1L && hits[[1]] == -1L)
    return(list(start = NA_integer_, laengde = NA_integer_, brugte_offsets = brugte_offsets))
  offsets <- as.integer(hits - 1L) # JS/Python/DB-kontrakten bruger 0-baserede tegn-offsets.
  ledig <- offsets[!offsets %in% brugte_offsets]
  if (!length(ledig))
    return(list(start = NA_integer_, laengde = NA_integer_, brugte_offsets = brugte_offsets))
  valgt <- ledig[[1]]
  list(start = valgt, laengde = nchar(klausul, type = "chars"),
       brugte_offsets = c(brugte_offsets, valgt))
}

.unique_match_id <- function(h, kandidater) {
  if (is.null(kandidater) || !nrow(kandidater)) return(NA_real_)
  dmin <- h$date_min %||% NA_character_
  dmax <- h$date_max %||% NA_character_
  draw <- normaliser_date_raw(h$date_raw %||% NA_character_)
  pair_match <- rep(FALSE, nrow(kandidater))
  raw_match <- rep(FALSE, nrow(kandidater))
  if (!is.na(dmin) && !is.na(dmax) && all(c("date_min", "date_max") %in% names(kandidater))) {
    pair_match <- !is.na(kandidater$date_min) & !is.na(kandidater$date_max) &
      as.character(kandidater$date_min) == as.character(dmin) &
      as.character(kandidater$date_max) == as.character(dmax)
  }
  if (!is.na(draw) && "date_raw" %in% names(kandidater)) {
    raw_match <- vapply(kandidater$date_raw, function(x) {
      nx <- normaliser_date_raw(x); !is.na(nx) && identical(nx, draw)
    }, logical(1))
  }
  ids <- unique(kandidater$id[pair_match | raw_match])
  if (length(ids) == 1L) ids[[1]] else NA_real_
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

match_rygrad <- function(haendelse, valgte_fakta_df, relationer_df) {
  fact_id <- .unique_match_id(haendelse, valgte_fakta_df)
  # Fejl til den billige side: når et faktum matcher entydigt, søges ikke samtidig
  # en relation med samme dato. Én hændelse får højst ét rygradsanker.
  relation_id <- if (is.na(fact_id)) .unique_match_id(haendelse, relationer_df) else NA_real_
  list(fact_id = fact_id, relation_id = relation_id)
}

.empty_rows <- function() data.frame(stringsAsFactors = FALSE)
.bind_rows <- function(rows) {
  if (!length(rows)) return(.empty_rows())
  out <- do.call(rbind, lapply(rows, function(x) as.data.frame(x, stringsAsFactors = FALSE)))
  rownames(out) <- NULL
  out
}

.same_secondary <- function(old, new) {
  same_category <- (is.na(old$kategori) && is.na(new$kategori)) ||
    (!is.na(old$kategori) && !is.na(new$kategori) && identical(as.character(old$kategori), as.character(new$kategori)))
  dates_known <- !is.na(old$date_min) && !is.na(old$date_max) &&
    !is.na(new$date_min) && !is.na(new$date_max)
  same_category && dates_known &&
    identical(as.character(old$date_min), as.character(new$date_min)) &&
    identical(as.character(old$date_max), as.character(new$date_max))
}

plan_merge <- function(eksisterende_df, nye_df) {
  eksisterende <- eksisterende_df
  nye <- nye_df
  if (!nrow(eksisterende) && !nrow(nye)) return(list(
    updates=.empty_rows(), inserts=.empty_rows(), deletes=.empty_rows(),
    overfoerte=.empty_rows(), mistede=.empty_rows(), untouched=.empty_rows()))

  required <- c("narrative_id", "noegle")
  if (nrow(eksisterende) && !all(c(required, "id", "feed_status") %in% names(eksisterende)))
    stop("eksisterende_df mangler narrative_id/noegle/id/feed_status")
  if (nrow(nye) && !all(required %in% names(nye))) stop("nye_df mangler narrative_id/noegle")

  # Helperen kan kaldes på flere narrativer, men loaderen kalder den pr. narrativ.
  input_ids <- if (nrow(nye)) unique(nye$narrative_id) else unique(eksisterende$narrative_id)
  scope <- if (nrow(eksisterende)) eksisterende[eksisterende$narrative_id %in% input_ids, , drop=FALSE] else eksisterende
  untouched <- if (nrow(eksisterende)) eksisterende[!eksisterende$narrative_id %in% input_ids, , drop=FALSE] else eksisterende

  old_key <- if (nrow(scope)) paste(scope$narrative_id, scope$noegle, sep="::") else character()
  new_key <- if (nrow(nye)) paste(nye$narrative_id, nye$noegle, sep="::") else character()
  if (anyDuplicated(old_key) || anyDuplicated(new_key)) stop("dublet (narrative_id,noegle) i merge-input")

  old_exact <- match(new_key, old_key)
  new_exact <- which(!is.na(old_exact))
  matched_old <- unique(old_exact[new_exact])
  updates <- if (length(new_exact)) {
    x <- nye[new_exact, , drop=FALSE]
    x$id <- scope$id[old_exact[new_exact]]
    if ("feed_status" %in% names(x)) x$feed_status <- NULL
    x
  } else .empty_rows()

  unmatched_new_idx <- setdiff(seq_len(nrow(nye)), new_exact)
  orphan_idx <- setdiff(seq_len(nrow(scope)), matched_old)
  orphans <- if (length(orphan_idx)) scope[orphan_idx, , drop=FALSE] else .empty_rows()
  insert_rows <- if (length(unmatched_new_idx)) nye[unmatched_new_idx, , drop=FALSE] else .empty_rows()
  if (nrow(insert_rows)) insert_rows$feed_status <- "kandidat"

  marked_idx <- if (nrow(orphans)) which(orphans$feed_status != "kandidat") else integer()
  candidate_matrix <- matrix(FALSE, nrow=length(marked_idx), ncol=nrow(insert_rows))
  if (length(marked_idx) && nrow(insert_rows)) {
    for (i in seq_along(marked_idx)) for (j in seq_len(nrow(insert_rows)))
      candidate_matrix[i,j] <- .same_secondary(orphans[marked_idx[i],,drop=FALSE], insert_rows[j,,drop=FALSE])
  }
  transferable <- which(rowSums(candidate_matrix) == 1L)
  pairs <- list()
  if (length(transferable)) {
    for (i in transferable) {
      j <- which(candidate_matrix[i,])
      if (colSums(candidate_matrix)[j] == 1L) pairs[[length(pairs)+1L]] <- c(old=i, new=j)
    }
  }

  transferred_old <- integer()
  overfoerte <- list()
  for (pair in pairs) {
    oi <- marked_idx[pair[["old"]]]; nj <- pair[["new"]]
    insert_rows$feed_status[nj] <- orphans$feed_status[oi]
    transferred_old <- c(transferred_old, oi)
    overfoerte[[length(overfoerte)+1L]] <- list(
      gammel_id=orphans$id[oi], gammel_noegle=orphans$noegle[oi],
      ny_noegle=insert_rows$noegle[nj], status=orphans$feed_status[oi])
  }
  mistede_idx <- setdiff(marked_idx, transferred_old)

  list(
    updates=updates,
    inserts=insert_rows,
    deletes=orphans,
    overfoerte=.bind_rows(overfoerte),
    mistede=if (length(mistede_idx)) orphans[mistede_idx,,drop=FALSE] else .empty_rows(),
    untouched=untouched
  )
}
