#!/usr/bin/env Rscript
# Rapport-first oprydning af mediedatabasen og Supabase Storage.
#
# Brug fra repo-roden:
#   Rscript R/media-janitor.R [--slet] [--frist-dage N] [--backfill-sha]
#
# Uden flag er scriptet read-only. --slet omfatter kun gamle strandede uploads og
# gamle forældreløse Storage-objekter. --backfill-sha er et separat skrive-opt-in.

MEDIA_JANITOR_BUCKET <- "media"
MEDIA_JANITOR_REPORT_COLUMNS <- c(
  "kategori", "bucket", "media_id", "sti", "alder_dage", "anbefalet_handling"
)

empty_media_janitor_report <- function() {
  data.frame(
    kategori = character(), bucket = character(), media_id = numeric(), sti = character(),
    alder_dage = numeric(), anbefalet_handling = character(),
    stringsAsFactors = FALSE
  )
}

parse_media_janitor_args <- function(args) {
  out <- list(slet = FALSE, frist_dage = 7L, backfill_sha = FALSE)
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--slet")) {
      out$slet <- TRUE
    } else if (identical(arg, "--backfill-sha")) {
      out$backfill_sha <- TRUE
    } else if (identical(arg, "--frist-dage")) {
      if (i == length(args)) stop("--frist-dage kræver et heltal.", call. = FALSE)
      raw <- args[[i + 1L]]
      if (!grepl("^[0-9]+$", raw)) {
        if (grepl("^-", raw)) stop("--frist-dage skal være et ikke-negativt heltal.", call. = FALSE)
        stop("--frist-dage kræver et heltal.", call. = FALSE)
      }
      value <- suppressWarnings(as.numeric(raw))
      if (!is.finite(value) || value > .Machine$integer.max) {
        stop("--frist-dage kræver et gyldigt heltal.", call. = FALSE)
      }
      out$frist_dage <- as.integer(value)
      i <- i + 1L
    } else {
      stop("Ukendt flag: ", arg, call. = FALSE)
    }
    i <- i + 1L
  }
  out
}

parse_iso8601_utc <- function(x) {
  values <- as.character(x)
  result <- rep(as.POSIXct(NA, tz = "UTC"), length(values))
  pattern <- paste0(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:",
    "[0-9]{2}(?:\\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})$"
  )
  valid <- !is.na(values) & grepl(pattern, values, perl = TRUE)
  if (any(valid)) {
    normalized <- sub("Z$", "+0000", values[valid])
    normalized <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", normalized, perl = TRUE)
    parsed <- suppressWarnings(strptime(
      normalized, format = "%Y-%m-%dT%H:%M:%OS%z", tz = "UTC"
    ))
    result[valid] <- as.POSIXct(parsed, tz = "UTC")
  }
  result
}

as_utc_time <- function(x) {
  if (inherits(x, "POSIXt")) return(as.POSIXct(x, tz = "UTC"))
  values <- as.character(x)
  result <- parse_iso8601_utc(values)
  date_only <- !is.na(values) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", values)
  result[date_only] <- as.POSIXct(strptime(values[date_only], "%Y-%m-%d", tz = "UTC"))
  plain <- !is.na(values) & grepl(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?$",
    values, perl = TRUE
  )
  result[plain] <- as.POSIXct(strptime(
    values[plain], "%Y-%m-%d %H:%M:%OS", tz = "UTC"
  ))
  result
}

age_days <- function(created_at, now = Sys.time()) {
  created <- as_utc_time(created_at)
  current <- as_utc_time(now)
  floor(as.numeric(difftime(current, created, units = "days")))
}

eligible_by_age <- function(created_at, now = Sys.time(), frist_dage = 7L) {
  created <- as_utc_time(created_at)
  cutoff <- as_utc_time(now) - as.numeric(frist_dage) * 86400
  !is.na(created) & created < cutoff
}

known_storage_paths <- function(media, variants) {
  paths <- c(
    if ("storage_path" %in% names(media)) as.character(media$storage_path) else character(),
    if ("storage_path" %in% names(variants)) as.character(variants$storage_path) else character()
  )
  sort(unique(paths[!is.na(paths) & nzchar(paths)]))
}

janitor_storage_buckets <- function(media = NULL) MEDIA_JANITOR_BUCKET

assert_media_janitor_bucket <- function(bucket) {
  if (length(bucket) != 1L || is.na(bucket) || bucket != MEDIA_JANITOR_BUCKET) {
    stop("Media-janitor må kun tilgå bucket 'media'.", call. = FALSE)
  }
  invisible(bucket)
}

find_orphan_objects <- function(objects, media, variants) {
  if (!"bucket" %in% names(objects)) objects$bucket <- MEDIA_JANITOR_BUCKET
  objects <- objects[objects$bucket == MEDIA_JANITOR_BUCKET, , drop = FALSE]
  if (!nrow(objects)) return(objects)
  if (!"bucket" %in% names(media)) media$bucket <- MEDIA_JANITOR_BUCKET
  scoped_media <- media[
    !is.na(media$bucket) & media$bucket == MEDIA_JANITOR_BUCKET, , drop = FALSE
  ]
  scoped_variants <- if ("id" %in% names(scoped_media) && "media_id" %in% names(variants)) {
    variants[variants$media_id %in% scoped_media$id, , drop = FALSE]
  } else {
    variants
  }
  known <- known_storage_paths(scoped_media, scoped_variants)
  out <- objects[!is.na(objects$name) & nzchar(objects$name) & !(objects$name %in% known), , drop = FALSE]
  out[order(out$bucket, out$name, method = "radix"), , drop = FALSE]
}

storage_path_exists <- function(bucket, path, bucket_paths) {
  if (is.na(path) || !nzchar(path)) return(FALSE)
  if (is.data.frame(bucket_paths)) {
    if (!all(c("bucket", "name") %in% names(bucket_paths))) {
      stop("bucket_paths skal have kolonnerne bucket og name.", call. = FALSE)
    }
    return(any(bucket_paths$bucket == bucket & bucket_paths$name == path, na.rm = TRUE))
  }
  path %in% bucket_paths
}

build_report_row <- function(kategori, media_id = NA_real_, sti = NA_character_,
                             created_at = as.POSIXct(NA), now = Sys.time(),
                             anbefalet_handling, bucket = MEDIA_JANITOR_BUCKET) {
  data.frame(
    kategori = as.character(kategori),
    bucket = as.character(bucket),
    media_id = if (length(media_id) && !is.na(media_id)) as.numeric(media_id) else NA_real_,
    sti = if (length(sti) && !is.na(sti)) as.character(sti) else NA_character_,
    alder_dage = if (length(created_at) && !is.na(created_at)) age_days(created_at, now) else NA_real_,
    anbefalet_handling = as.character(anbefalet_handling),
    stringsAsFactors = FALSE
  )[, MEDIA_JANITOR_REPORT_COLUMNS, drop = FALSE]
}

sort_media_janitor_report <- function(report) {
  if (!nrow(report)) return(empty_media_janitor_report())
  category_order <- c("a_strandet", "b_forældreløs", "c_variant_hul",
                      "d_sha_backfill", "d_ægte_dublet", "x_fremmed_bucket")
  category_rank <- match(report$kategori, category_order)
  category_rank[is.na(category_rank)] <- length(category_order) + 1L
  id_rank <- report$media_id
  id_rank[is.na(id_rank)] <- Inf
  path_rank <- ifelse(is.na(report$sti), "", report$sti)
  idx <- order(category_rank, report$bucket, id_rank, path_rank, report$anbefalet_handling,
               method = "radix", na.last = TRUE)
  rownames(report) <- NULL
  out <- report[idx, MEDIA_JANITOR_REPORT_COLUMNS, drop = FALSE]
  rownames(out) <- NULL
  out
}

classify_media_findings <- function(media, variants, bucket_paths,
                                    now = Sys.time(), frist_dage = 7L) {
  media <- media[order(media$id), , drop = FALSE]
  if (!"bucket" %in% names(media)) media$bucket <- MEDIA_JANITOR_BUCKET
  in_scope <- !is.na(media$bucket) & media$bucket == MEDIA_JANITOR_BUCKET
  foreign <- media[!in_scope, , drop = FALSE]
  scoped <- media[in_scope, , drop = FALSE]
  stranded <- scoped[scoped$upload_status %in% c("kladde", "fejlet"), , drop = FALSE]
  stranded_out <- data.frame(
    media_id = as.numeric(stranded$id),
    bucket = as.character(stranded$bucket),
    sti = as.character(stranded$storage_path),
    created_at = as_utc_time(stranded$created_at),
    sletbar = eligible_by_age(stranded$created_at, now, frist_dage),
    stringsAsFactors = FALSE
  )

  holes <- list()
  ready <- scoped[scoped$upload_status == "klar", , drop = FALSE]
  for (i in seq_len(nrow(ready))) {
    media_id <- ready$id[[i]]
    bucket <- if ("bucket" %in% names(ready)) as.character(ready$bucket[[i]]) else "media"
    own <- variants[variants$media_id == media_id, , drop = FALSE]
    for (tier in c("thumb", "medium")) {
      variant <- own[own$tier == tier, , drop = FALSE]
      if (!nrow(variant)) {
        holes[[length(holes) + 1L]] <- data.frame(
          media_id = as.numeric(media_id), bucket = bucket, tier = tier, sti = tier,
          created_at = as_utc_time(ready$created_at[[i]]), stringsAsFactors = FALSE
        )
      } else {
        path <- as.character(variant$storage_path[[1]])
        if (!storage_path_exists(bucket, path, bucket_paths)) {
          holes[[length(holes) + 1L]] <- data.frame(
            media_id = as.numeric(media_id), bucket = bucket, tier = tier, sti = path,
            created_at = as_utc_time(ready$created_at[[i]]), stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  variant_holes <- if (length(holes)) do.call(rbind, holes) else data.frame(
    media_id = integer(), bucket = character(), tier = character(), sti = character(),
    created_at = as.POSIXct(character(), tz = "UTC"), stringsAsFactors = FALSE
  )
  if (nrow(variant_holes)) {
    variant_holes <- variant_holes[order(variant_holes$media_id, variant_holes$tier), , drop = FALSE]
    rownames(variant_holes) <- NULL
  }

  sha_path_exists <- vapply(seq_len(nrow(scoped)), function(i) {
    storage_path_exists(
      as.character(scoped$bucket[[i]]), as.character(scoped$storage_path[[i]]), bucket_paths
    )
  }, logical(1))
  sha <- scoped[
    scoped$upload_status %in% c("klar", "fjernet") &
      (is.na(scoped$sha256) | !nzchar(scoped$sha256)) &
      !is.na(scoped$storage_path) & nzchar(scoped$storage_path) &
      sha_path_exists,
    , drop = FALSE
  ]
  sha_candidates <- data.frame(
    media_id = as.numeric(sha$id),
    bucket = if ("bucket" %in% names(sha)) as.character(sha$bucket) else rep("media", nrow(sha)),
    sti = as.character(sha$storage_path), created_at = as_utc_time(sha$created_at),
    stringsAsFactors = FALSE
  )

  foreign_bucket <- data.frame(
    media_id = as.numeric(foreign$id), bucket = as.character(foreign$bucket),
    sti = as.character(foreign$storage_path), created_at = as_utc_time(foreign$created_at),
    sletbar = rep(FALSE, nrow(foreign)), stringsAsFactors = FALSE
  )

  list(stranded = stranded_out, variant_holes = variant_holes,
       sha_candidates = sha_candidates, foreign_bucket = foreign_bucket)
}

encode_storage_path <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) stop("Storage-stien er tom.", call. = FALSE)
  if (startsWith(path, "/")) stop("Storage-stien skal være relativ.", call. = FALSE)
  parts <- strsplit(enc2utf8(path), "/", fixed = TRUE)[[1]]
  if (any(parts %in% c("", ".", ".."))) stop("Storage-stien indeholder et ugyldigt sti-segment.", call. = FALSE)
  paste(vapply(parts, utils::URLencode, character(1), reserved = TRUE), collapse = "/")
}

storage_objects_to_df <- function(objects) {
  if (is.null(objects) || !length(objects)) {
    return(data.frame(name = character(), created_at = as.POSIXct(character(), tz = "UTC"),
                      stringsAsFactors = FALSE))
  }
  rows <- lapply(objects, function(object) {
    data.frame(
      name = as.character(object$name %||% NA_character_),
      created_at = as_utc_time(object$created_at %||% NA_character_),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

`%||%` <- function(x, fallback) if (is.null(x) || !length(x)) fallback else x

list_storage_objects <- function(bucket, list_page, page_size = 1000L) {
  if (page_size < 1L || page_size > 1000L) stop("page_size skal være 1..1000.", call. = FALSE)
  pages <- list()
  cursor <- NULL
  seen <- character()
  repeat {
    page <- list_page(bucket = bucket, cursor = cursor, limit = as.integer(page_size))
    pages[[length(pages) + 1L]] <- storage_objects_to_df(page$objects)
    has_next <- isTRUE(page$hasNext)
    if (!has_next) break
    next_cursor <- page$nextCursor %||% ""
    if (!nzchar(next_cursor)) stop("Storage list-v2 returnerede hasNext uden nextCursor.", call. = FALSE)
    if (next_cursor %in% seen) stop("Storage list-v2 returnerede en gentaget cursor.", call. = FALSE)
    seen <- c(seen, next_cursor)
    cursor <- next_cursor
  }
  out <- do.call(rbind, pages)
  if (!nrow(out)) return(storage_objects_to_df(NULL))
  out <- out[order(out$name, method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}

decide_sha_backfill <- function(media_id, sha, known_sha) {
  own <- known_sha[known_sha$id == media_id & known_sha$sha256 == sha, , drop = FALSE]
  if (nrow(own)) return(list(action = "already_set", duplicate_media_id = NA_integer_))
  duplicate <- known_sha[known_sha$id != media_id & known_sha$sha256 == sha, , drop = FALSE]
  if (nrow(duplicate)) {
    return(list(action = "duplicate", duplicate_media_id = as.integer(min(duplicate$id))))
  }
  list(action = "update", duplicate_media_id = NA_integer_)
}

backfill_one_sha <- function(media_id, bucket, path, known_sha, download, update,
                             temp_path = tempfile("media-janitor-"), do_update = TRUE) {
  on.exit(if (file.exists(temp_path)) unlink(temp_path), add = TRUE)
  download(bucket, path, temp_path)
  sha <- digest::digest(file = temp_path, algo = "sha256", serialize = FALSE)
  decision <- decide_sha_backfill(media_id, sha, known_sha)
  if (identical(decision$action, "update") && isTRUE(do_update)) {
    update(media_id, sha)
    decision$action <- "updated"
  }
  decision$sha256 <- sha
  decision
}

execute_janitor_mutations <- function(options, stranded, orphans, sha_candidates, ops) {
  results <- list(stranded = list(), orphans = list(), sha = list())
  if (isTRUE(options$slet)) {
    eligible_stranded <- stranded[!is.na(stranded$sletbar) & stranded$sletbar, , drop = FALSE]
    eligible_orphans <- orphans[!is.na(orphans$sletbar) & orphans$sletbar, , drop = FALSE]
    for (i in seq_len(nrow(eligible_stranded))) {
      results$stranded[[length(results$stranded) + 1L]] <- ops$delete_stranded(eligible_stranded[i, , drop = FALSE])
    }
    for (i in seq_len(nrow(eligible_orphans))) {
      results$orphans[[length(results$orphans) + 1L]] <- ops$delete_orphan(eligible_orphans[i, , drop = FALSE])
    }
  }
  if (isTRUE(options$backfill_sha)) {
    for (i in seq_len(nrow(sha_candidates))) {
      results$sha[[length(results$sha) + 1L]] <- ops$backfill_sha(sha_candidates[i, , drop = FALSE])
    }
  }
  invisible(results)
}

run_after_initial_report <- function(report, write_report, mutate) {
  write_report(report)
  mutate()
}

db_error_sqlstate <- function(error) {
  if (grepl("MEDIA_JANITOR_SQLSTATE_23503", conditionMessage(error), fixed = TRUE)) {
    return("23503")
  }
  candidates <- c(error$sqlstate %||% character(), error$code %||% character(),
                  attr(error, "sqlstate") %||% character())
  hit <- candidates[grepl("^[0-9A-Z]{5}$", candidates)]
  if (length(hit)) hit[[1]] else NA_character_
}

relation_block_for_media <- function(relations, media_id) {
  if (!nrow(relations)) {
    return(list(
      blocked = FALSE, expected_relation_ids = numeric(),
      unexpected_relation_ids = numeric(), evidenced_relation_ids = numeric()
    ))
  }
  touching <- relations[relations$media_id == media_id, , drop = FALSE]
  expected <- !is.na(touching$rolle) & touching$rolle == "afbildet" &
    !is.na(touching$subjekt_type) & touching$subjekt_type == "person" &
    !is.na(touching$objekt_type) & touching$objekt_type == "media" &
    !is.na(touching$objekt_id) & touching$objekt_id == media_id
  unexpected_ids <- sort(as.numeric(touching$relation_id[!expected]))
  evidence_unknown_or_present <- is.na(touching$has_evidence) | touching$has_evidence
  evidenced_ids <- sort(as.numeric(
    touching$relation_id[expected & evidence_unknown_or_present]
  ))
  list(
    blocked = length(unexpected_ids) > 0L || length(evidenced_ids) > 0L,
    expected_relation_ids = sort(as.numeric(touching$relation_id[expected])),
    unexpected_relation_ids = unexpected_ids,
    evidenced_relation_ids = evidenced_ids
  )
}

default_janitor_db_ops <- function() {
  list(
    begin = DBI::dbBegin,
    execute = function(con, sql, params) DBI::dbExecute(con, sql, params = params),
    delete_media = function(con, media_id) {
      id <- as.numeric(media_id)
      if (length(id) != 1L || is.na(id) || !is.finite(id) || id < 0 || id != floor(id)) {
        stop("Ugyldigt media-id ved sletning.", call. = FALSE)
      }
      # RPostgres 1.4.10 reducerer serverfejl til simpleError og eksponerer ikke
      # SQLSTATE. Fang derfor den konkrete PostgreSQL-condition server-side og
      # oversæt KUN foreign_key_violation (23503) til en stabil intern sentinel.
      sql <- paste0(
        "DO $media_janitor$ BEGIN ",
        "DELETE FROM media WHERE id=", format(id, scientific = FALSE, trim = TRUE), "; ",
        "IF NOT FOUND THEN RAISE EXCEPTION 'MEDIA_JANITOR_ROW_NOT_FOUND'; END IF; ",
        "EXCEPTION WHEN foreign_key_violation THEN ",
        "RAISE EXCEPTION 'MEDIA_JANITOR_SQLSTATE_23503'; ",
        "END $media_janitor$"
      )
      DBI::dbExecute(con, sql)
      1L
    },
    commit = DBI::dbCommit,
    rollback = DBI::dbRollback
  )
}

delete_stranded_media_row <- function(con, media_id, bucket, paths,
                                      relation_ids = numeric(), has_evidence = logical(),
                                      db_ops = default_janitor_db_ops(), storage_delete,
                                      has_unexpected_relation = FALSE) {
  if (length(bucket) != 1L || is.na(bucket) || bucket != MEDIA_JANITOR_BUCKET) {
    return(list(status = "manuel", detail = "fremmed bucket"))
  }
  if (isTRUE(has_unexpected_relation)) {
    return(list(status = "manuel", detail = "uventet relation til media"))
  }
  if (length(has_evidence) && any(is.na(has_evidence) | has_evidence)) {
    return(list(status = "manuel", detail = "relation har evidens"))
  }
  committed <- FALSE
  db_ops$begin(con)
  tryCatch({
    for (relation_id in sort(as.numeric(relation_ids))) {
      # Samme FK-orden som _delete_relation_evidence. Hvert DELETE er betinget af,
      # at HELE evidenssættet stadig er tomt; en samtidig evidensrække bliver derfor
      # aldrig slettet af janitoren, og relationens affected-row-check stopper rækken.
      evidence_empty <- paste0(
        "NOT EXISTS (SELECT 1 FROM assertion a WHERE a.target_type='relation' AND a.target_id=$1) ",
        "AND NOT EXISTS (SELECT 1 FROM conclusion c WHERE c.target_type='relation' AND c.target_id=$1) ",
        "AND NOT EXISTS (SELECT 1 FROM note n WHERE n.target_type='relation' AND n.target_id=$1)"
      )
      db_ops$execute(con, paste0(
        "DELETE FROM citation WHERE assertion_id IN (",
        "SELECT a.id FROM assertion a WHERE a.target_type='relation' AND a.target_id=$1 AND ", evidence_empty, ")"
      ), list(relation_id))
      db_ops$execute(con, paste0(
        "DELETE FROM conclusion WHERE target_type='relation' AND target_id=$1 AND ", evidence_empty
      ), list(relation_id))
      db_ops$execute(con, paste0(
        "DELETE FROM assertion WHERE target_type='relation' AND target_id=$1 AND ", evidence_empty
      ), list(relation_id))
      db_ops$execute(con, paste0(
        "DELETE FROM note WHERE target_type='relation' AND target_id=$1 AND ", evidence_empty
      ), list(relation_id))
      deleted <- db_ops$execute(con, paste0(
        "DELETE FROM relation WHERE id=$1 AND ", evidence_empty
      ), list(relation_id))
      if (!identical(as.integer(deleted), 1L)) {
        stop(structure(list(message = "relation fik evidens under sletning", sqlstate = "MJ001"),
                       class = c("media_janitor_manual", "error", "condition")))
      }
    }
    db_ops$execute(con, "DELETE FROM media_variant WHERE media_id=$1", list(media_id))
    deleted_media <- if (is.function(db_ops$delete_media)) {
      db_ops$delete_media(con, media_id)
    } else {
      db_ops$execute(con, "DELETE FROM media WHERE id=$1", list(media_id))
    }
    if (!identical(as.integer(deleted_media), 1L)) stop("Media-rækken fandtes ikke ved sletning.")
    db_ops$commit(con)
    committed <- TRUE
  }, error = function(error) {
    if (!committed) try(db_ops$rollback(con), silent = TRUE)
    sqlstate <- db_error_sqlstate(error)
    if (identical(sqlstate, "23503") || inherits(error, "media_janitor_manual")) {
      return(structure(list(error = error), class = "media_janitor_caught"))
    }
    stop(error)
  }) -> transaction_result

  if (inherits(transaction_result, "media_janitor_caught")) {
    state <- db_error_sqlstate(transaction_result$error)
    detail <- if (identical(state, "23503")) {
      "SQLSTATE 23503: manuel afgørelse krævet"
    } else {
      conditionMessage(transaction_result$error)
    }
    return(list(status = "manuel", detail = detail))
  }

  clean_paths <- sort(unique(as.character(paths[!is.na(paths) & nzchar(paths)])))
  if (length(clean_paths)) {
    storage_error <- tryCatch({
      storage_delete(bucket, clean_paths)
      NULL
    }, error = identity)
    if (!is.null(storage_error)) {
      return(list(status = "db_slettet_storage_fejlet",
                  detail = conditionMessage(storage_error), paths = clean_paths))
    }
  }
  list(status = "slettet", detail = "DB og Storage slettet", paths = clean_paths)
}

storage_api_context <- function() {
  key <- Sys.getenv("SUPABASE_SERVICE_ROLE")
  if (!nzchar(key)) stop("Sæt SUPABASE_SERVICE_ROLE i ~/.Renviron.", call. = FALSE)
  base_url <- Sys.getenv("SUPABASE_URL")
  if (!nzchar(base_url)) {
    host <- Sys.getenv("SUPABASE_HOST")
    match <- regexec("^db\\.([a-z0-9]+)\\.supabase\\.co$", host)
    parts <- regmatches(host, match)[[1]]
    if (length(parts) != 2L) {
      stop("Sæt SUPABASE_URL i ~/.Renviron (kan ikke udlede projekt-URL af SUPABASE_HOST).",
           call. = FALSE)
    }
    base_url <- paste0("https://", parts[[2]], ".supabase.co")
  }
  list(base_url = sub("/+$", "", base_url), key = key)
}

storage_api_request <- function(context, method, endpoint, body = NULL) {
  request <- httr2::request(paste0(context$base_url, "/storage/v1/", endpoint)) |>
    httr2::req_method(method) |>
    httr2::req_headers(
      apikey = context$key,
      Authorization = paste("Bearer", context$key)
    )
  if (!is.null(body)) request <- httr2::req_body_json(request, body, auto_unbox = TRUE)
  httr2::req_perform(request)
}

make_storage_list_page <- function(context) {
  function(bucket, cursor, limit) {
    assert_media_janitor_bucket(bucket)
    body <- list(prefix = "", limit = as.integer(limit), with_delimiter = FALSE,
                 sortBy = list(column = "name", order = "asc"))
    if (!is.null(cursor)) body$cursor <- cursor
    response <- storage_api_request(
      context, "POST", paste0("object/list-v2/", encode_storage_path(bucket)), body
    )
    httr2::resp_body_json(response, simplifyVector = FALSE)
  }
}

make_storage_delete <- function(context) {
  function(bucket, paths) {
    assert_media_janitor_bucket(bucket)
    paths <- sort(unique(paths))
    for (start in seq.int(1L, length(paths), by = 1000L)) {
      batch <- paths[start:min(start + 999L, length(paths))]
      storage_api_request(
        context, "DELETE", paste0("object/", encode_storage_path(bucket)),
        list(prefixes = unname(as.list(batch)))
      )
    }
    invisible(paths)
  }
}

make_storage_download <- function(context) {
  function(bucket, path, dest) {
    assert_media_janitor_bucket(bucket)
    response <- storage_api_request(
      context, "GET",
      paste0("object/", encode_storage_path(bucket), "/", encode_storage_path(path))
    )
    writeBin(httr2::resp_body_raw(response), dest)
    invisible(dest)
  }
}

connect_media_janitor_db <- function() {
  host <- Sys.getenv("SUPABASE_HOST")
  user <- Sys.getenv("SUPABASE_USER")
  password <- Sys.getenv("SUPABASE_PASSWORD")
  if (!nzchar(host) || !nzchar(user) || !nzchar(password)) {
    stop("Sæt SUPABASE_HOST/USER/PASSWORD i ~/.Renviron.", call. = FALSE)
  }
  DBI::dbConnect(
    RPostgres::Postgres(), host = host,
    port = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
    dbname = Sys.getenv("SUPABASE_DB", "postgres"), user = user,
    password = password, sslmode = Sys.getenv("SUPABASE_SSLMODE", "require"),
    bigint = "numeric"
  )
}

fetch_media_janitor_snapshot <- function(con) {
  media <- DBI::dbGetQuery(con, paste(
    "SELECT id, bucket, storage_path, sha256, upload_status, created_at",
    "FROM media ORDER BY id"
  ))
  variants <- DBI::dbGetQuery(con, paste(
    "SELECT id, media_id, tier, storage_path",
    "FROM media_variant ORDER BY media_id, tier, id"
  ))
  relations <- DBI::dbGetQuery(con, paste(
    "WITH touching AS (",
    " SELECT r.*, r.subjekt_id AS media_id FROM relation r WHERE r.subjekt_type='media'",
    " UNION",
    " SELECT r.*, r.objekt_id AS media_id FROM relation r WHERE r.objekt_type='media'",
    ")",
    "SELECT r.id AS relation_id, r.subjekt_type, r.subjekt_id,",
    "r.objekt_type, r.objekt_id, r.rolle,",
    "r.media_id,",
    "(EXISTS (SELECT 1 FROM assertion a WHERE a.target_type='relation' AND a.target_id=r.id)",
    " OR EXISTS (SELECT 1 FROM conclusion c WHERE c.target_type='relation' AND c.target_id=r.id)",
    " OR EXISTS (SELECT 1 FROM note n WHERE n.target_type='relation' AND n.target_id=r.id)) AS has_evidence",
    "FROM touching r",
    "ORDER BY media_id, relation_id"
  ))
  list(media = media, variants = variants, relations = relations)
}

make_report_before_mutation <- function(snapshot, objects, findings, orphans, now, frist_dage) {
  rows <- list()
  relations <- snapshot$relations
  for (i in seq_len(nrow(findings$stranded))) {
    item <- findings$stranded[i, , drop = FALSE]
    relation_block <- relation_block_for_media(relations, item$media_id)
    recommendation <- if (length(relation_block$unexpected_relation_ids)) {
      "manuel afgørelse krævet: uventet relation til media"
    } else if (length(relation_block$evidenced_relation_ids)) {
      "manuel afgørelse krævet: relation har evidens"
    } else if (is.na(item$created_at)) {
      "vurdér manuelt"
    } else if (isTRUE(item$sletbar)) {
      "sletbar med --slet"
    } else {
      "afvent frist"
    }
    rows[[length(rows) + 1L]] <- build_report_row(
      "a_strandet", item$media_id, item$sti, item$created_at, now, recommendation,
      bucket = item$bucket
    )
  }
  if (nrow(findings$foreign_bucket)) {
    for (i in seq_len(nrow(findings$foreign_bucket))) {
      item <- findings$foreign_bucket[i, , drop = FALSE]
      rows[[length(rows) + 1L]] <- build_report_row(
        "x_fremmed_bucket", item$media_id, item$sti, item$created_at, now,
        "manuel afgørelse krævet: fremmed bucket", bucket = item$bucket
      )
    }
  }
  if (nrow(orphans)) {
    for (i in seq_len(nrow(orphans))) {
      recommendation <- if (isTRUE(orphans$sletbar[[i]])) "sletbar med --slet" else if (
        is.na(orphans$created_at[[i]])
      ) "vurdér manuelt" else "afvent frist"
      rows[[length(rows) + 1L]] <- build_report_row(
        "b_forældreløs", NA, orphans$name[[i]], orphans$created_at[[i]], now, recommendation,
        bucket = orphans$bucket[[i]]
      )
    }
  }
  if (nrow(findings$variant_holes)) {
    for (i in seq_len(nrow(findings$variant_holes))) {
      item <- findings$variant_holes[i, , drop = FALSE]
      rows[[length(rows) + 1L]] <- build_report_row(
        "c_variant_hul", item$media_id, item$sti, item$created_at, now,
        "regenerér variant manuelt", bucket = item$bucket
      )
    }
  }
  if (!length(rows)) empty_media_janitor_report() else sort_media_janitor_report(do.call(rbind, rows))
}

write_media_janitor_report <- function(report, path = "work/media-janitor-rapport.csv") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(report[, MEDIA_JANITOR_REPORT_COLUMNS, drop = FALSE], path,
                   row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(path)
}

run_media_janitor <- function(args = commandArgs(trailingOnly = TRUE), now = Sys.time()) {
  options <- parse_media_janitor_args(args)
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RPostgres", quietly = TRUE) ||
      !requireNamespace("httr2", quietly = TRUE) || !requireNamespace("digest", quietly = TRUE)) {
    stop("Task 9 kræver DBI, RPostgres, httr2 og digest.", call. = FALSE)
  }

  con <- connect_media_janitor_db()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  storage <- storage_api_context()
  list_page <- make_storage_list_page(storage)
  storage_delete <- make_storage_delete(storage)
  storage_download <- make_storage_download(storage)

  snapshot <- fetch_media_janitor_snapshot(con)
  buckets <- janitor_storage_buckets(snapshot$media)
  bucket_objects <- lapply(buckets, function(bucket) {
    out <- list_storage_objects(bucket, list_page)
    out$bucket <- bucket
    out
  })
  objects <- do.call(rbind, bucket_objects)
  orphans <- find_orphan_objects(objects, snapshot$media, snapshot$variants)
  orphans$sletbar <- eligible_by_age(orphans$created_at, now, options$frist_dage)
  orphans <- orphans[order(orphans$bucket, orphans$name), , drop = FALSE]

  # Mediemodellen bruger aktuelt én media-bucket. Bucket-aware anti-join ovenfor er
  # autoritativ; klassifikatoren får de stier, der faktisk findes for media-rækkerne.
  findings <- classify_media_findings(
    snapshot$media, snapshot$variants, objects[, c("bucket", "name"), drop = FALSE],
    now, options$frist_dage
  )
  report <- make_report_before_mutation(snapshot, objects, findings, orphans, now, options$frist_dage)

  sha_known <- snapshot$media[
    !is.na(snapshot$media$sha256) & nzchar(snapshot$media$sha256), c("id", "sha256"), drop = FALSE
  ]
  sha_results <- list()
  update_sha <- function(media_id, sha) {
    affected <- DBI::dbExecute(
      con, "UPDATE media SET sha256=$2 WHERE id=$1 AND sha256 IS NULL",
      params = list(media_id, sha)
    )
    if (!identical(as.integer(affected), 1L)) stop("sha-backfill mistede sin række for media ", media_id)
  }
  for (i in seq_len(nrow(findings$sha_candidates))) {
    item <- findings$sha_candidates[i, , drop = FALSE]
    result <- backfill_one_sha(
      item$media_id, item$bucket, item$sti, sha_known,
      storage_download, update_sha, do_update = FALSE
    )
    if (identical(result$action, "update")) {
      recommendation <- "backfill med --backfill-sha"
      category <- "d_sha_backfill"
    } else if (identical(result$action, "duplicate")) {
      recommendation <- paste0("ægte dublet af media ", result$duplicate_media_id, "; flet manuelt")
      category <- "d_ægte_dublet"
    } else {
      recommendation <- "sha256 allerede sat under kørslen"
      category <- "d_sha_backfill"
    }
    report <- rbind(report, build_report_row(
      category, item$media_id, item$sti, item$created_at, now, recommendation,
      bucket = item$bucket
    ))
    sha_known <- rbind(sha_known, data.frame(id = item$media_id, sha256 = result$sha256))
    sha_results[[as.character(item$media_id)]] <- result
  }

  relation_rows <- split(snapshot$relations, snapshot$relations$media_id)
  variant_rows <- split(snapshot$variants, snapshot$variants$media_id)
  ops <- list(
    delete_stranded = function(item) {
      id <- as.character(item$media_id[[1]])
      rel <- relation_rows[[id]] %||% data.frame(relation_id = numeric(), has_evidence = logical())
      relation_block <- relation_block_for_media(rel, item$media_id[[1]])
      vars <- variant_rows[[id]] %||% data.frame(storage_path = character())
      media_row <- snapshot$media[snapshot$media$id == item$media_id[[1]], , drop = FALSE]
      paths <- c(media_row$storage_path, vars$storage_path)
      result <- delete_stranded_media_row(
        con, item$media_id[[1]], media_row$bucket[[1]], paths,
        relation_block$expected_relation_ids,
        rel$has_evidence[rel$relation_id %in% relation_block$expected_relation_ids],
        storage_delete = storage_delete,
        has_unexpected_relation = length(relation_block$unexpected_relation_ids) > 0L
      )
      if (!identical(result$status, "slettet")) {
        idx <- report$kategori == "a_strandet" & report$media_id == item$media_id[[1]]
        report$anbefalet_handling[idx] <<- if (identical(result$status, "manuel")) {
          paste0("manuel afgørelse krævet: ", result$detail)
        } else {
          paste0("DB slettet; Storage retry krævet: ", result$detail)
        }
      } else {
        idx <- report$kategori == "a_strandet" & report$media_id == item$media_id[[1]]
        report$anbefalet_handling[idx] <<- "slettet"
      }
      result
    },
    delete_orphan = function(item) {
      result <- tryCatch({
        storage_delete(item$bucket[[1]], item$name[[1]])
        list(status = "slettet")
      }, error = function(error) list(status = "fejlet", detail = conditionMessage(error)))
      idx <- report$kategori == "b_forældreløs" & report$sti == item$name[[1]]
      report$anbefalet_handling[idx] <<- if (identical(result$status, "slettet")) {
        "slettet"
      } else {
        paste0("Storage retry krævet: ", result$detail)
      }
      result
    },
    backfill_sha = function(item) {
      id <- as.character(item$media_id[[1]])
      result <- sha_results[[id]]
      if (identical(result$action, "update")) {
        update_sha(item$media_id[[1]], result$sha256)
        idx <- report$kategori == "d_sha_backfill" & report$media_id == item$media_id[[1]]
        report$anbefalet_handling[idx] <<- "sha256 backfillet"
        result$action <- "updated"
      }
      result
    }
  )
  report <- sort_media_janitor_report(report)
  run_after_initial_report(
    report,
    write_report = write_media_janitor_report,
    mutate = function() execute_janitor_mutations(
      options, findings$stranded, orphans, findings$sha_candidates, ops
    )
  )

  report <- sort_media_janitor_report(report)
  path <- write_media_janitor_report(report)
  counts <- table(factor(report$kategori, levels = c(
    "a_strandet", "b_forældreløs", "c_variant_hul", "d_sha_backfill", "d_ægte_dublet",
    "x_fremmed_bucket"
  )))
  mode <- paste(c(if (options$slet) "SLET" else "RAPPORT",
                  if (options$backfill_sha) "BACKFILL-SHA"), collapse = "+")
  message("== media-janitor: ", mode, "; frist ", options$frist_dage, " dage ==")
  message(paste(names(counts), as.integer(counts), sep = "=", collapse = ", "))
  message("Rapport: ", path)
  invisible(report)
}

if (sys.nframe() == 0L) run_media_janitor()
