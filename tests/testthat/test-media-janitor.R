root <- normalizePath(file.path(getwd(), "..", ".."))
source(file.path(root, "R", "media-janitor.R"))

utc <- function(x) as.POSIXct(x, tz = "UTC")

test_that("parse_media_janitor_args er report-only som default", {
  expect_equal(
    parse_media_janitor_args(character()),
    list(slet = FALSE, frist_dage = 7L, backfill_sha = FALSE)
  )
  expect_equal(
    parse_media_janitor_args(c("--slet", "--frist-dage", "14", "--backfill-sha")),
    list(slet = TRUE, frist_dage = 14L, backfill_sha = TRUE)
  )
})

test_that("parse_media_janitor_args afviser ukendte, manglende og ugyldige flag", {
  expect_error(parse_media_janitor_args("--ukendt"), "Ukendt flag")
  expect_error(parse_media_janitor_args("--frist-dage"), "kræver et heltal")
  expect_error(parse_media_janitor_args(c("--frist-dage", "-1")), "ikke-negativt")
  expect_error(parse_media_janitor_args(c("--frist-dage", "2.5")), "heltal")
  expect_error(parse_media_janitor_args(c("--frist-dage", "syv")), "heltal")
})

test_that("frist-logik er streng og fail-safe ved ukendt alder", {
  now <- utc("2026-07-20 12:00:00")
  created <- utc(c("2026-07-12 11:59:59", "2026-07-13 12:00:00",
                   "2026-07-14 12:00:00", NA))
  expect_equal(eligible_by_age(created, now, 7), c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(age_days(created, now), c(8, 7, 6, NA_real_))
})

test_that("ISO8601 bevarer klokkeslæt, brøksekunder og offset ved fristgrænsen", {
  now <- parse_iso8601_utc("2026-07-20T18:00:00.000Z")
  created <- c(
    "2026-07-13T18:00:00.000Z",
    "2026-07-13T17:59:59.999Z",
    "2026-07-13T20:00:00.000+02:00",
    "2026-07-13T12:30:00.250-05:30",
    "ikke-en-dato"
  )
  parsed <- parse_iso8601_utc(created)

  expect_equal(as.numeric(parsed[1]), as.numeric(now - 7 * 86400))
  expect_lt(as.numeric(parsed[2]), as.numeric(parsed[1]))
  expect_equal(as.numeric(parsed[3]), as.numeric(parsed[1]))
  expect_equal(as.numeric(parsed[4]), as.numeric(parsed[1]) + 0.25)
  expect_true(is.na(parsed[5]))
  expect_equal(eligible_by_age(created, now, 7), c(FALSE, TRUE, FALSE, FALSE, FALSE))
})

test_that("sti-anti-join kender både large- og variantstier", {
  objects <- data.frame(
    name = c("large/aa/known.jpg", "thumb/bb/variant.webp", "orphan/x.png"),
    created_at = utc(c("2026-07-01", "2026-07-02", "2026-07-03")),
    stringsAsFactors = FALSE
  )
  media <- data.frame(storage_path = "large/aa/known.jpg")
  variants <- data.frame(storage_path = "thumb/bb/variant.webp")

  out <- find_orphan_objects(objects, media, variants)
  expect_equal(out$name, "orphan/x.png")
})

test_that("sti-anti-join er bucket-aware og varianter arver forælderens bucket", {
  objects <- data.frame(
    bucket = "media", name = c("same/path", "thumb/known", "orphan/path"),
    created_at = utc(c("2026-07-01", "2026-07-01", "2026-07-01")),
    stringsAsFactors = FALSE
  )
  media <- data.frame(
    id = c(1L, 2L), bucket = c("shared", "media"),
    storage_path = c("same/path", "large/known"), stringsAsFactors = FALSE
  )
  variants <- data.frame(
    media_id = 2L, storage_path = "thumb/known", stringsAsFactors = FALSE
  )
  out <- find_orphan_objects(objects, media, variants)
  expect_equal(out$name, c("orphan/path", "same/path"))
  expect_true(all(out$bucket == "media"))
})

test_that("medier klassificeres i strandet, variant-hul og sha-backfill", {
  now <- utc("2026-07-20 12:00:00")
  media <- data.frame(
    id = 1:5,
    upload_status = c("kladde", "fejlet", "klar", "klar", "fjernet"),
    created_at = utc(c("2026-07-01", NA, "2026-07-10", "2026-07-10", "2026-07-10")),
    storage_path = c("draft/a", "draft/b", "large/c", "large/d", "large/e"),
    sha256 = c(NA, NA, "has-sha", NA, NA),
    stringsAsFactors = FALSE
  )
  variants <- data.frame(
    media_id = c(3L, 3L, 4L),
    tier = c("thumb", "medium", "thumb"),
    storage_path = c("thumb/c", "medium/c", "thumb/d"),
    stringsAsFactors = FALSE
  )
  paths <- c("draft/a", "draft/b", "large/c", "thumb/c", "medium/c",
             "large/d", "thumb/d", "large/e")

  out <- classify_media_findings(media, variants, paths, now, 7)

  expect_equal(out$stranded$media_id, c(1L, 2L))
  expect_equal(out$stranded$sletbar, c(TRUE, FALSE))
  expect_equal(out$variant_holes$media_id, 4L)
  expect_equal(out$variant_holes$sti, "medium")
  expect_equal(out$sha_candidates$media_id, c(4L, 5L))
})

test_that("manglende registreret variantsti rapporteres som hul", {
  media <- data.frame(
    id = 9L, upload_status = "klar", created_at = utc("2026-07-01"),
    storage_path = "large/9", sha256 = "abc", stringsAsFactors = FALSE
  )
  variants <- data.frame(
    media_id = c(9L, 9L), tier = c("thumb", "medium"),
    storage_path = c("thumb/9", "medium/9"), stringsAsFactors = FALSE
  )
  out <- classify_media_findings(media, variants, c("large/9", "thumb/9"),
                                 utc("2026-07-20"), 7)
  expect_equal(out$variant_holes$sti, "medium/9")
})

test_that("sti-eksistens er bucket-afgrænset", {
  media <- data.frame(
    id = 10L, bucket = "media", upload_status = "klar",
    created_at = utc("2026-07-01"), storage_path = "large/samme",
    sha256 = NA_character_, stringsAsFactors = FALSE
  )
  variants <- data.frame(
    media_id = c(10L, 10L), tier = c("thumb", "medium"),
    storage_path = c("thumb/samme", "medium/samme"), stringsAsFactors = FALSE
  )
  bucket_paths <- data.frame(
    bucket = c("media", "media", "media-b"),
    name = c("large/samme", "thumb/samme", "medium/samme"),
    stringsAsFactors = FALSE
  )
  out <- classify_media_findings(media, variants, bucket_paths, utc("2026-07-20"), 7)
  expect_equal(out$variant_holes$sti, "medium/samme")
  expect_equal(out$sha_candidates$media_id, 10L)
})

test_that("janitor scanner kun allowlistet media-bucket og parkerer fremmede rækker", {
  media <- data.frame(
    id = c(20L, 21L), bucket = c("shared", "media"),
    upload_status = c("fejlet", "fejlet"),
    created_at = utc(c("2026-07-01", "2026-07-01")),
    storage_path = c("shared/object", "media/object"),
    sha256 = NA_character_, stringsAsFactors = FALSE
  )
  variants <- data.frame(media_id = numeric(), tier = character(), storage_path = character())
  objects <- data.frame(bucket = "media", name = "media/object", stringsAsFactors = FALSE)

  expect_identical(janitor_storage_buckets(media), "media")
  out <- classify_media_findings(media, variants, objects, utc("2026-07-20"), 7)
  expect_equal(out$stranded$media_id, 21L)
  expect_equal(out$foreign_bucket$media_id, 20L)
  expect_false(any(out$sha_candidates$media_id == 20L))

  deleted <- numeric()
  execute_janitor_mutations(
    parse_media_janitor_args("--slet"), out$stranded,
    data.frame(name = character(), sletbar = logical()), out$sha_candidates,
    list(
      delete_stranded = function(item) deleted <<- c(deleted, item$media_id),
      delete_orphan = function(item) stop("må ikke kaldes"),
      backfill_sha = function(item) stop("må ikke kaldes")
    )
  )
  expect_equal(deleted, 21L)

  touched <- FALSE
  result <- delete_stranded_media_row(
    NULL, 20L, "shared", "shared/object", numeric(), logical(),
    db_ops = list(begin = function(con) touched <<- TRUE),
    storage_delete = function(...) touched <<- TRUE
  )
  expect_false(touched)
  expect_equal(result$status, "manuel")
  expect_match(result$detail, "fremmed bucket")

  context <- list(base_url = "http://skal-ikke-kaldes.invalid", key = "ikke-en-hemmelighed")
  expect_error(make_storage_list_page(context)("shared", NULL, 10L), "kun tilgå bucket")
  expect_error(make_storage_delete(context)("shared", "x"), "kun tilgå bucket")
  expect_error(make_storage_download(context)("shared", "x", tempfile()), "kun tilgå bucket")
})

test_that("rapportrækker har eksakte kolonner og sikre anbefalinger", {
  now <- utc("2026-07-20 12:00:00")
  eligible <- build_report_row("a_strandet", 12, "large/12", utc("2026-07-01"), now,
                               "sletbar med --slet")
  unknown <- build_report_row("a_strandet", 13, "large/13", as.POSIXct(NA), now,
                              "vurdér manuelt")

  expect_identical(names(eligible), MEDIA_JANITOR_REPORT_COLUMNS)
  expect_equal(eligible$bucket, "media")
  expect_equal(eligible$alder_dage, 19)
  expect_true(is.na(unknown$alder_dage))
  expect_equal(unknown$anbefalet_handling, "vurdér manuelt")
})

test_that("rapporten sorteres deterministisk efter kategori, id og sti", {
  rows <- rbind(
    build_report_row("d_sha_backfill", 20, "z", utc("2026-07-01"), utc("2026-07-20"), "x"),
    build_report_row("a_strandet", 2, "b", utc("2026-07-01"), utc("2026-07-20"), "x"),
    build_report_row("a_strandet", 1, "c", utc("2026-07-01"), utc("2026-07-20"), "x"),
    build_report_row("b_forældreløs", NA, "a", utc("2026-07-01"), utc("2026-07-20"), "x")
  )
  out1 <- sort_media_janitor_report(rows)
  out2 <- sort_media_janitor_report(rows[c(4, 2, 1, 3), ])
  expect_identical(out1, out2)
  expect_equal(out1$kategori, c("a_strandet", "a_strandet", "b_forældreløs", "d_sha_backfill"))
  expect_equal(out1$media_id[1:2], c(1, 2))
})

test_that("objektstier URL-enkodes segmentvist uden at tabe mapper", {
  expect_equal(
    encode_storage_path("mappe med æ/fil #1.jpg"),
    "mappe%20med%20%C3%A6/fil%20%231.jpg"
  )
  expect_error(encode_storage_path("../hemmelig"), "ugyldigt sti-segment")
  expect_error(encode_storage_path("/absolut"), "relativ")
})

test_that("list-v2 følger cursor til slut uden OFFSET og returnerer fulde stier", {
  calls <- list()
  pages <- list(
    first = list(
      objects = list(list(name = "large/a", created_at = "2026-07-01T00:00:00Z")),
      folders = list(), hasNext = TRUE, nextCursor = "opaque-2"
    ),
    `opaque-2` = list(
      objects = list(list(name = "thumb/b", created_at = "2026-07-02T00:00:00Z")),
      folders = list(), hasNext = FALSE
    )
  )
  list_page <- function(bucket, cursor, limit) {
    calls[[length(calls) + 1L]] <<- list(
      bucket = bucket,
      cursor = if (is.null(cursor)) NA_character_ else cursor,
      limit = limit
    )
    pages[[if (is.null(cursor)) "first" else cursor]]
  }

  out <- list_storage_objects("media", list_page = list_page, page_size = 500L)
  expect_equal(out$name, c("large/a", "thumb/b"))
  expect_equal(vapply(calls, `[[`, character(1), "cursor"), c(NA_character_, "opaque-2"))
  expect_true(all(vapply(calls, `[[`, integer(1), "limit") == 500L))
})

test_that("list-v2 fejler ved manglende eller gentaget cursor", {
  missing <- function(bucket, cursor, limit) list(objects = list(), hasNext = TRUE)
  expect_error(list_storage_objects("media", missing), "nextCursor")

  repeated <- function(bucket, cursor, limit) {
    list(objects = list(), hasNext = TRUE, nextCursor = "samme")
  }
  expect_error(list_storage_objects("media", repeated), "gentaget cursor")
})

test_that("sha-beslutning skriver kun unik hash og rapporterer ægte dublet", {
  known <- data.frame(id = c(1L, 8L), sha256 = c("aaaa", "bbbb"), stringsAsFactors = FALSE)
  expect_equal(decide_sha_backfill(2L, "cccc", known)$action, "update")
  duplicate <- decide_sha_backfill(2L, "bbbb", known)
  expect_equal(duplicate$action, "duplicate")
  expect_equal(duplicate$duplicate_media_id, 8L)
  expect_equal(decide_sha_backfill(8L, "bbbb", known)$action, "already_set")
})

test_that("defaultkørsel udfører nul DB- og Storage-mutationer", {
  mutations <- character()
  ops <- list(
    delete_stranded = function(...) mutations <<- c(mutations, "db_delete"),
    delete_orphan = function(...) mutations <<- c(mutations, "storage_delete"),
    backfill_sha = function(...) mutations <<- c(mutations, "sha_update")
  )
  execute_janitor_mutations(
    options = parse_media_janitor_args(character()),
    stranded = data.frame(media_id = 1L, sletbar = TRUE),
    orphans = data.frame(name = "orphan", sletbar = TRUE),
    sha_candidates = data.frame(media_id = 2L),
    ops = ops
  )
  expect_length(mutations, 0L)
})

test_that("planrapporten persisteres før første mutation", {
  events <- character()
  report <- build_report_row(
    "a_strandet", 1L, "large/1", utc("2026-07-01"), utc("2026-07-20"),
    "sletbar med --slet", bucket = "media"
  )
  run_after_initial_report(
    report,
    write_report = function(report) {
      expect_identical(names(report), MEDIA_JANITOR_REPORT_COLUMNS)
      events <<- c(events, paste0("rapport:", report$bucket, ":", report$kategori))
    },
    mutate = function() events <<- c(events, "mutation")
  )
  expect_equal(events, c("rapport:media:a_strandet", "mutation"))
})

test_that("sletteflag rører kun sletbare a+b og backfill er separat", {
  mutations <- character()
  ops <- list(
    delete_stranded = function(x) mutations <<- c(mutations, paste0("a", x$media_id)),
    delete_orphan = function(x) mutations <<- c(mutations, paste0("b", x$name)),
    backfill_sha = function(x) mutations <<- c(mutations, paste0("d", x$media_id))
  )
  execute_janitor_mutations(
    options = parse_media_janitor_args("--slet"),
    stranded = data.frame(media_id = c(1L, 2L), sletbar = c(TRUE, FALSE)),
    orphans = data.frame(name = c("old", "young"), sletbar = c(TRUE, FALSE)),
    sha_candidates = data.frame(media_id = 3L), ops = ops
  )
  expect_equal(mutations, c("a1", "bold"))
})

test_that("strandet rækkes DB-sletning følger FK-orden og HTTP sker efter commit", {
  events <- character()
  db_ops <- list(
    begin = function(con) events <<- c(events, "begin"),
    execute = function(con, sql, params) {
      token <- if (grepl("DELETE FROM citation", sql, fixed = TRUE)) "citation"
      else if (grepl("DELETE FROM conclusion", sql, fixed = TRUE)) "conclusion"
      else if (grepl("DELETE FROM assertion", sql, fixed = TRUE)) "assertion"
      else if (grepl("DELETE FROM note", sql, fixed = TRUE)) "note"
      else if (grepl("DELETE FROM relation", sql, fixed = TRUE)) "relation"
      else if (grepl("DELETE FROM media_variant", sql, fixed = TRUE)) "variant"
      else if (grepl("DELETE FROM media", sql, fixed = TRUE)) "media"
      else stop("uventet SQL")
      events <<- c(events, token)
      1L
    },
    commit = function(con) events <<- c(events, "commit"),
    rollback = function(con) events <<- c(events, "rollback")
  )
  storage_delete <- function(bucket, paths) events <<- c(events, "storage")

  result <- delete_stranded_media_row(
    con = NULL, media_id = 7L, bucket = "media", paths = c("large/7", "thumb/7"),
    relation_ids = c(31L, 32L), has_evidence = c(FALSE, FALSE),
    db_ops = db_ops, storage_delete = storage_delete
  )

  expect_equal(events, c("begin", rep(c("citation", "conclusion", "assertion", "note", "relation"), 2),
                         "variant", "media", "commit", "storage"))
  expect_equal(result$status, "slettet")
})

test_that("relation med evidens medfører nul mutationer", {
  touched <- FALSE
  result <- delete_stranded_media_row(
    con = NULL, media_id = 7L, bucket = "media", paths = "large/7",
    relation_ids = 31L, has_evidence = TRUE,
    db_ops = list(begin = function(con) touched <<- TRUE),
    storage_delete = function(...) touched <<- TRUE
  )
  expect_false(touched)
  expect_equal(result$status, "manuel")

  touched <- FALSE
  unknown <- delete_stranded_media_row(
    con = NULL, media_id = 8L, bucket = "media", paths = "large/8",
    relation_ids = 32L, has_evidence = NA,
    db_ops = list(begin = function(con) touched <<- TRUE),
    storage_delete = function(...) touched <<- TRUE
  )
  expect_false(touched)
  expect_equal(unknown$status, "manuel")
})

test_that("uventet polymorf relation i begge retninger blokerer hele medierækken", {
  relations <- data.frame(
    relation_id = c(31L, 32L, 33L), media_id = 7L,
    subjekt_type = c("person", "estate", "media"),
    subjekt_id = c(1L, 2L, 7L),
    objekt_type = c("media", "media", "person"),
    objekt_id = c(7L, 7L, 3L),
    rolle = c("afbildet", "ejer", "skabt_af"),
    has_evidence = FALSE, stringsAsFactors = FALSE
  )
  block <- relation_block_for_media(relations, 7L)
  expect_true(block$blocked)
  expect_equal(block$unexpected_relation_ids, c(32L, 33L))

  touched <- FALSE
  result <- delete_stranded_media_row(
    NULL, 7L, "media", "large/7", 31L, FALSE,
    db_ops = list(begin = function(con) touched <<- TRUE),
    storage_delete = function(...) touched <<- TRUE,
    has_unexpected_relation = TRUE
  )
  expect_false(touched)
  expect_equal(result$status, "manuel")
  expect_match(result$detail, "uventet relation")
})

test_that("normal person→media afbildet-relation er tilladt", {
  relations <- data.frame(
    relation_id = 31L, media_id = 7L,
    subjekt_type = "person", subjekt_id = 1L,
    objekt_type = "media", objekt_id = 7L,
    rolle = "afbildet", has_evidence = FALSE, stringsAsFactors = FALSE
  )
  block <- relation_block_for_media(relations, 7L)
  expect_false(block$blocked)
  expect_equal(block$expected_relation_ids, 31L)
})

test_that("fremmed bucket og uventet relation rapporteres som manuel afgørelse", {
  now <- utc("2026-07-20")
  media <- data.frame(
    id = c(7L, 8L), bucket = c("media", "shared"),
    upload_status = "fejlet", created_at = utc("2026-07-01"),
    storage_path = c("large/7", "shared/8"), sha256 = NA_character_,
    stringsAsFactors = FALSE
  )
  variants <- data.frame(media_id = numeric(), tier = character(), storage_path = character())
  findings <- classify_media_findings(
    media, variants, data.frame(bucket = "media", name = "large/7"), now, 7
  )
  relations <- data.frame(
    relation_id = 41L, media_id = 7L,
    subjekt_type = "estate", subjekt_id = 2L,
    objekt_type = "media", objekt_id = 7L,
    rolle = "ejer", has_evidence = FALSE, stringsAsFactors = FALSE
  )
  snapshot <- list(media = media, variants = variants, relations = relations)
  report <- make_report_before_mutation(
    snapshot, data.frame(), findings,
    data.frame(name = character(), created_at = as.POSIXct(character()), sletbar = logical()),
    now, 7
  )

  expect_match(report$anbefalet_handling[report$media_id == 7L], "uventet relation")
  expect_match(report$anbefalet_handling[report$media_id == 8L], "fremmed bucket")
  expect_equal(report$bucket[report$media_id == 8L], "shared")
})

test_that("SQLSTATE 23503 rollbackes pr række og Storage røres ikke", {
  events <- character()
  fk <- structure(list(message = "fk", sqlstate = "23503"),
                  class = c("PqResultError", "error", "condition"))
  db_ops <- list(
    begin = function(con) events <<- c(events, "begin"),
    execute = function(con, sql, params) stop(fk),
    commit = function(con) events <<- c(events, "commit"),
    rollback = function(con) events <<- c(events, "rollback")
  )
  result <- delete_stranded_media_row(
    NULL, 7L, "media", "large/7", numeric(), logical(), db_ops,
    storage_delete = function(...) events <<- c(events, "storage")
  )
  expect_equal(events, c("begin", "rollback"))
  expect_equal(result$status, "manuel")
  expect_match(result$detail, "23503")
})

test_that("server-side 23503-sentinel genkendes trods RPostgres' simpleError", {
  error <- simpleError("MEDIA_JANITOR_SQLSTATE_23503")
  expect_equal(db_error_sqlstate(error), "23503")
})

test_that("andre DB-fejl rollbackes og fejler højt", {
  events <- character()
  db_ops <- list(
    begin = function(con) events <<- c(events, "begin"),
    execute = function(con, sql, params) stop("boom"),
    commit = function(con) events <<- c(events, "commit"),
    rollback = function(con) events <<- c(events, "rollback")
  )
  expect_error(
    delete_stranded_media_row(NULL, 7L, "media", "large/7", numeric(), logical(),
                              db_ops, function(...) events <<- c(events, "storage")),
    "boom"
  )
  expect_equal(events, c("begin", "rollback"))
})

test_that("fejlet Storage-sletning maskerer ikke gennemført DB-sletning", {
  db_ops <- list(
    begin = function(con) NULL,
    execute = function(con, sql, params) 1L,
    commit = function(con) NULL,
    rollback = function(con) NULL
  )
  result <- delete_stranded_media_row(
    NULL, 7L, "media", "large/7", numeric(), logical(), db_ops,
    storage_delete = function(...) stop("storage nede")
  )
  expect_equal(result$status, "db_slettet_storage_fejlet")
  expect_match(result$detail, "storage nede")
})

test_that("sha-download og hashing sker før den korte DB-opdatering", {
  events <- character()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  download <- function(bucket, path, dest) {
    events <<- c(events, "download")
    writeBin(charToRaw("abc"), dest)
  }
  update <- function(media_id, sha) {
    events <<- c(events, "update")
    expect_equal(sha, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }
  result <- backfill_one_sha(4L, "media", "large/4", data.frame(id = integer(), sha256 = character()),
                             download, update, temp_path = tmp)
  expect_equal(events, c("download", "update"))
  expect_equal(result$action, "updated")
})
