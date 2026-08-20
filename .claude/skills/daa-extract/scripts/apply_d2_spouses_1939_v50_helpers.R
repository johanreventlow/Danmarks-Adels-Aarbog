## Ren logik bag fase D2's apply: CLI-gaten og guarden mod at basen har
## flyttet sig siden eksporten. Ingen DB-adgang, saa begge kan testes uden
## forbindelse.

## Fail-closed argument-parser. Et ukendt flag er en FEJL, ikke noget der
## ignoreres: i fase D1 blev et opfundet --dryrun stiltiende slugt, og 68
## personer blev publiceret i prod uden godkendelse.
d2_parse_apply_args <- function(args) {
  allowed <- c("--selection", "--expect-sha256", "--jeg-mener-det")
  flags <- args[grepl("^--", args)]
  if (any(!flags %in% allowed) || anyDuplicated(flags))
    stop("D2_APPLY_CLI_INVALID", call. = FALSE)
  if (!("--selection" %in% flags)) stop("D2_APPLY_CLI_INVALID", call. = FALSE)
  value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
      stop("D2_APPLY_CLI_INVALID", call. = FALSE)
    args[[index + 1L]]
  }
  selection <- value("--selection")
  expect_sha256 <- if ("--expect-sha256" %in% flags) value("--expect-sha256") else NA_character_
  ## Bekraeftelsen tjekkes SIDST, saa en malformet kommandolinje aldrig kan
  ## fremstaa som "manglede bare bekraeftelsen".
  if (!("--jeg-mener-det" %in% flags))
    stop("D2_APPLY_CONFIRMATION_REQUIRED", call. = FALSE)
  list(selection = selection, expect_sha256 = expect_sha256)
}

## Sammenligner eksportens tal med basen som den ser ud NU.
d2_plan_apply <- function(doc, live_counts) {
  ids <- vapply(doc$selected, function(r) as.numeric(r$person_id), numeric(1))
  if (length(ids) == 0L) stop("D2_APPLY_EMPTY", call. = FALSE)
  if (!identical(as.numeric(live_counts$staged_i_alt),
                 as.numeric(doc$counts$staged_i_alt)))
    stop("D2_APPLY_STAGED_DRIFT", call. = FALSE)
  if (!identical(as.numeric(live_counts$valgte), as.numeric(doc$counts$valgte)))
    stop("D2_APPLY_SELECTION_DRIFT", call. = FALSE)
  list(ids = sort(ids),
       forventet_bagefter = as.numeric(doc$counts$staged_bagefter))
}

## Efterkontrol: D2 roerer UDELUKKENDE person.staged. Koeres INDE i
## transaktionen, saa en afvigelse ruller tilbage frem for blot at melde.
## `before` og `after` er navngivne taellinger fra samme forespoergsel.
d2_check_postcheck <- function(before, after, forventet_bagefter) {
  if (!identical(as.numeric(after$staged), as.numeric(forventet_bagefter)))
    stop("D2_APPLY_POSTCHECK_MISMATCH", call. = FALSE)
  for (felt in c("person", "fact", "relation", "narrative")) {
    if (!identical(as.numeric(before[[felt]]), as.numeric(after[[felt]])))
      stop("D2_APPLY_DELTA_NOT_ZERO", call. = FALSE)
  }
  invisible(TRUE)
}
