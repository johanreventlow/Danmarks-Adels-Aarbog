library(testthat)

root <- normalizePath(file.path(getwd(), "../.."), mustWork = TRUE)
source(file.path(root, ".claude/skills/daa-extract/scripts/reverse_reimport_legacy_migration_helpers.R"),
  local = TRUE)

uuid <- function(nibble) sprintf("%s-%s-4%s-8%s-%s",
  strrep(nibble, 8L), strrep(nibble, 4L), strrep(nibble, 3L), strrep(nibble, 3L),
  strrep(nibble, 12L))
hash <- function(letter) strrep(letter, 64L)

batch_id <- uuid("1")
authorization_id <- uuid("2")

published_element <- function(key = "legacy-migration:B") list(
  element_id = key, person_id = 11L, source_id = 149001L, source_record_key = "B",
  narrative_id = 21L, disposition = "bound_published",
  binding_id = uuid("3"), draft_event_id = uuid("4"), published_event_id = uuid("5"),
  legacy_event_id = uuid("6"), legacy_publication_ref = uuid("7"))
draft_element <- function(key = "legacy-migration:A") list(
  element_id = key, person_id = 12L, source_id = 149001L, source_record_key = "A",
  narrative_id = 22L, disposition = "bound_draft",
  binding_id = uuid("8"), draft_event_id = uuid("9"), published_event_id = NULL,
  legacy_event_id = NULL, legacy_publication_ref = NULL)

# Mock-gateway: registrerer kaldsrækkefølgen og svarer med den samme form, som de
# rigtige RPC'er giver, så helperens kæde kan afprøves uden database.
mock_gateway <- function(elements = list(draft_element(), published_element()),
                         batch = NULL, authorization = NULL, fail_at = NULL) {
  calls <- list()
  reversals <- 0L
  gateway <- list(call = function(name, ...) {
    args <- list(...)
    calls[[length(calls) + 1L]] <<- list(name = name, args = args)
    if (identical(name, fail_at)) stop("MOCK_FAILURE", call. = FALSE)
    switch(name,
      connect = invisible(NULL), begin = invisible(NULL),
      advisory_lock = invisible(NULL),
      actor = uuid("a"),
      batch = batch %||% list(source_id = 149001L, profile_id = "fixture-lm",
        status = "finalized", legacy_migrations = length(elements),
        foreign_operations = 0L, reversal_events = 0L),
      authorization = authorization %||% list(operation = "reversal", status = "issued",
        database_identity = paste0("batch:", batch_id),
        principal_matches_actor = TRUE, expired = FALSE, batch_matches = TRUE),
      elements = elements,
      record_state = hash("b"),
      reverse_event = {
        reversals <<- reversals + 1L
        event <- args[[1L]]
        status <- if (identical(event, published_element()$published_event_id)) "draft"
          else if (identical(event, published_element()$legacy_event_id)) "published"
          else "withdrawn"
        list(event_id = uuid(as.character(reversals)), status = status,
          state_sha256 = hash("c"))
      },
      discard_record = list(event_id = uuid("d"), status = "withdrawn",
        state_sha256 = hash("e")),
      legacy_state = list(state_sha256 = hash("f"), ledger_status = "migrated",
        latest_event_id = published_element()$legacy_event_id,
        latest_event_type = "legacy_migrated"),
      record_reversal = list(batch_id = batch_id, authorization_id = authorization_id,
        batch_status = "finalized", reversed_elements = length(elements),
        receipts_sha256 = hash("0")),
      rollback = invisible(NULL), commit = invisible(NULL),
      stop("unexpected gateway operation: ", name, call. = FALSE))
  })
  list(gateway = gateway, names = function() vapply(calls, `[[`, "", "name"),
    calls = function() calls)
}
`%||%` <- function(x, y) if (is.null(x)) y else x

test_that("CLI accepterer kun de tre flag og kræver gyldige UUID'er", {
  parsed <- parse_legacy_reversal_cli(c("--batch-id", batch_id,
    "--authorization", authorization_id, "--apply"))
  expect_identical(parsed, list(batch_id = batch_id,
    authorization_id = authorization_id, mode = "apply"))
  expect_identical(parse_legacy_reversal_cli(c("--dry-run", "--batch-id", batch_id,
    "--authorization", authorization_id))$mode, "dry-run")
  # ukendt flag
  expect_error(parse_legacy_reversal_cli(c("--batch-id", batch_id, "--authorization",
    authorization_id, "--apply", "--force")), "LEGACY_REVERSAL_CLI_INVALID")
  # begge tilstande
  expect_error(parse_legacy_reversal_cli(c("--batch-id", batch_id, "--authorization",
    authorization_id, "--apply", "--dry-run")), "LEGACY_REVERSAL_CLI_INVALID")
  # ingen tilstand
  expect_error(parse_legacy_reversal_cli(c("--batch-id", batch_id, "--authorization",
    authorization_id)), "LEGACY_REVERSAL_CLI_INVALID")
  # manglende autorisation
  expect_error(parse_legacy_reversal_cli(c("--batch-id", batch_id, "--apply")),
    "LEGACY_REVERSAL_CLI_INVALID")
  # gentaget flag
  expect_error(parse_legacy_reversal_cli(c("--batch-id", batch_id, "--batch-id",
    batch_id, "--authorization", authorization_id, "--apply")),
    "LEGACY_REVERSAL_CLI_INVALID")
  # ikke-UUID
  expect_error(parse_legacy_reversal_cli(c("--batch-id", "nope", "--authorization",
    authorization_id, "--apply")), "LEGACY_REVERSAL_CLI_INVALID")
  # positionel rest
  expect_error(parse_legacy_reversal_cli(c("--batch-id", batch_id, "--authorization",
    authorization_id, "--apply", "extra")), "LEGACY_REVERSAL_CLI_INVALID")
  expect_error(parse_legacy_reversal_cli(character(0)), "LEGACY_REVERSAL_CLI_INVALID")
})

test_that("kvitteringen serialiseres med reversal_event_ids som array også ved ét id", {
  receipt <- build_legacy_reversal_receipt(uuid("5"))
  expect_identical(receipt$final_binding_status, "withdrawn")
  expect_null(receipt$final_ledger_status)
  rendered <- jsonlite::toJSON(receipt, auto_unbox = TRUE, null = "null")
  expect_match(as.character(rendered), '"reversal_event_ids":\\["', perl = TRUE)
  expect_match(as.character(rendered), '"final_ledger_status":null', fixed = TRUE)
  three <- build_legacy_reversal_receipt(c(uuid("5"), uuid("6"), uuid("7")),
    "grandfathered_publication")
  expect_length(three$reversal_event_ids, 3L)
  expect_identical(three$final_ledger_status, "grandfathered_publication")
  expect_error(build_legacy_reversal_receipt(character(0)), "LEGACY_REVERSAL_RECEIPT_INVALID")
  expect_error(build_legacy_reversal_receipt(c(uuid("5"), uuid("5"))),
    "LEGACY_REVERSAL_RECEIPT_INVALID")
  expect_error(build_legacy_reversal_receipt(uuid("5"), "withdrawn"),
    "LEGACY_REVERSAL_RECEIPT_INVALID")
})

test_that("elementer fortrydes i omvendt element_id-orden", {
  ordered <- order_legacy_reversal_elements(list(draft_element(), published_element()))
  expect_identical(vapply(ordered, `[[`, "", "element_id"),
    c("legacy-migration:B", "legacy-migration:A"))
  expect_error(order_legacy_reversal_elements(list()), "LEGACY_REVERSAL_BATCH_EMPTY")
})

test_that("et bound_draft-element uden published/legacy-felter kræves konsistent", {
  bad <- draft_element(); bad$legacy_event_id <- uuid("6")
  expect_error(order_legacy_reversal_elements(list(bad)), "LEGACY_REVERSAL_ELEMENT_INVALID")
  bad2 <- published_element(); bad2$legacy_publication_ref <- NULL
  expect_error(order_legacy_reversal_elements(list(bad2)), "LEGACY_REVERSAL_ELEMENT_INVALID")
})

test_that("dry-run kører hele kæden og ruller tilbage", {
  mock <- mock_gateway()
  result <- execute_legacy_reversal(batch_id, authorization_id, "dry-run", mock$gateway)
  expect_false(result$committed)
  expect_identical(result$reversed_elements, 2L)
  expect_identical(result$element_ids, c("legacy-migration:B", "legacy-migration:A"))
  names <- mock$names()
  expect_true("record_reversal" %in% names)
  expect_true("rollback" %in% names)
  expect_false("commit" %in% names)
  # bound_published: fortryd -> kasser -> fortryd; bound_draft: fortryd
  expect_identical(names[names %in% c("reverse_event", "discard_record")],
    c("reverse_event", "discard_record", "reverse_event", "reverse_event"))
})

test_that("apply committer og sender én kvittering pr. element", {
  mock <- mock_gateway()
  result <- execute_legacy_reversal(batch_id, authorization_id, "apply", mock$gateway)
  expect_true(result$committed)
  expect_true("commit" %in% mock$names())
  expect_false("rollback" %in% mock$names())
  receipts <- Filter(function(call) identical(call$name, "record_reversal"), mock$calls())[[1L]]$args[[3L]]
  expect_identical(sort(names(receipts)), c("legacy-migration:A", "legacy-migration:B"))
  expect_length(receipts[["legacy-migration:B"]]$reversal_event_ids, 3L)
  expect_identical(receipts[["legacy-migration:B"]]$final_ledger_status,
    "grandfathered_publication")
  expect_length(receipts[["legacy-migration:A"]]$reversal_event_ids, 1L)
  expect_null(receipts[["legacy-migration:A"]]$final_ledger_status)
})

test_that("en allerede registreret fortrydelse afvises før nogen skrivning", {
  mock <- mock_gateway(batch = list(source_id = 149001L, profile_id = "fixture-lm",
    status = "finalized", legacy_migrations = 2L, foreign_operations = 0L,
    reversal_events = 1L))
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply", mock$gateway),
    "LEGACY_REVERSAL_ALREADY_RECORDED")
  expect_false(any(c("reverse_event", "record_reversal", "commit") %in% mock$names()))
  expect_true("rollback" %in% mock$names())
})

test_that("en forbrugt eller fremmed autorisation stopper før første fortrydelse", {
  consumed <- mock_gateway(authorization = list(operation = "reversal",
    status = "consumed", database_identity = paste0("batch:", batch_id),
    principal_matches_actor = TRUE, expired = FALSE, batch_matches = TRUE))
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply", consumed$gateway),
    "REIMPORT_WRITER_REVERSAL_INVALID")
  expect_false("reverse_event" %in% consumed$names())
  foreign <- mock_gateway(authorization = list(operation = "reversal", status = "issued",
    database_identity = paste0("batch:", uuid("e")),
    principal_matches_actor = TRUE, expired = FALSE, batch_matches = TRUE))
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply", foreign$gateway),
    "REIMPORT_WRITER_REVERSAL_INVALID")
  expect_false("reverse_event" %in% foreign$names())
})

test_that("en batch med fremmede operationer eller forkert status afvises", {
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply",
    mock_gateway(batch = list(source_id = 149001L, profile_id = "p", status = "finalized",
      legacy_migrations = 2L, foreign_operations = 1L, reversal_events = 0L))$gateway),
    "REIMPORT_WRITER_REVERSAL_INVALID")
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply",
    mock_gateway(batch = list(source_id = 149001L, profile_id = "p", status = "activated",
      legacy_migrations = 2L, foreign_operations = 0L, reversal_events = 0L))$gateway),
    "REIMPORT_WRITER_REVERSAL_INVALID")
})

test_that("en fejl midt i kæden ruller tilbage uden at registrere noget", {
  mock <- mock_gateway(fail_at = "discard_record")
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply", mock$gateway),
    "MOCK_FAILURE")
  expect_false(any(c("record_reversal", "commit") %in% mock$names()))
  expect_true("rollback" %in% mock$names())
})

test_that("en uventet ledger-tilstand stopper fortrydelsen", {
  mock <- mock_gateway()
  original <- mock$gateway$call
  mock$gateway$call <- function(name, ...) {
    if (identical(name, "legacy_state"))
      return(list(state_sha256 = hash("f"), ledger_status = "grandfathered_publication",
        latest_event_id = published_element()$legacy_event_id,
        latest_event_type = "baseline"))
    original(name, ...)
  }
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply", mock$gateway),
    "LEGACY_REVERSAL_LEGACY_STATE_UNEXPECTED")
})

test_that("en gateway uden call-funktion afvises før forbindelsen åbnes", {
  expect_error(execute_legacy_reversal(batch_id, authorization_id, "apply", list()),
    "LEGACY_REVERSAL_GATEWAY_INVALID")
  expect_error(execute_legacy_reversal("ikke-en-uuid", authorization_id, "apply",
    mock_gateway()$gateway), "LEGACY_REVERSAL_CLI_INVALID")
})
