## Ren logik bag fase D2's apply: CLI-gaten og guarden mod at basen har
## flyttet sig siden eksporten. Ingen DB-adgang, saa begge kan testes uden
## forbindelse.

## Fail-closed argument-parser. Et ukendt flag er en FEJL, ikke noget der
## ignoreres: i fase D1 blev et opfundet --dryrun stiltiende slugt, og 68
## personer blev publiceret i prod uden godkendelse.
d2_parse_apply_args <- function(args) {
  allowed <- c("--selection", "--expect-sha256", "--backup", "--jeg-mener-det")
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
  ## Hash-laasen er obligatorisk: uden den kan et haandredigeret dokument
  ## saette sin egen forventning til efterkontrollen, som saa "bekraefter" den.
  if (!("--expect-sha256" %in% flags)) stop("D2_APPLY_SHA_REQUIRED", call. = FALSE)
  expect_sha256 <- value("--expect-sha256")
  ## Basen koerer paa free tier UDEN automatisk backup. At tage en dump er en
  ## instruktion i planen; her bliver det en betingelse. Wrapperen kan ikke
  ## vide om dumpen er god, men den kan naegte at koere uden at én er udpeget.
  if (!("--backup" %in% flags)) stop("D2_APPLY_BACKUP_REQUIRED", call. = FALSE)
  backup <- value("--backup")
  ## Bekraeftelsen tjekkes SIDST, saa en malformet kommandolinje aldrig kan
  ## fremstaa som "manglede bare bekraeftelsen".
  if (!("--jeg-mener-det" %in% flags))
    stop("D2_APPLY_CONFIRMATION_REQUIRED", call. = FALSE)
  list(selection = selection, expect_sha256 = expect_sha256, backup = backup)
}

## Sammenligner eksportdokumentet med basen som den ser ud NU.
##
## Guarden sammenligner ID-MAENGDEN, ikke antallet. Samme antal med andre
## mennesker er netop det farlige tilfaelde: mister en valgt person sin
## synlige partner (men forbliver staged) mens en anden staged person faar
## én, er der stadig 21 kandidater og 28 staged -- og en antals-guard ville
## lade os publicere nogen der ikke laengere opfylder D2-kriteriet.
## SHA-laasen fanger det ikke: filen er aegte, bare foraeldet paa en maade
## der bevarer antallet.
##
## `live` skal maales INDE i skrive-transaktionen; ellers staar vinduet
## mellem maaling og skrivning aabent (TOCTOU).
d2_plan_apply <- function(doc, live) {
  ids <- vapply(doc$selected, function(r) as.numeric(r$person_id), numeric(1))
  if (length(ids) == 0L) stop("D2_APPLY_EMPTY", call. = FALSE)
  if (!identical(doc$schema_version, "1.0"))
    stop("D2_APPLY_SCHEMA_UNKNOWN", call. = FALSE)

  ## Dokumentets egne gate-tal genlaeses her. Eksporten haandhaevede dem, men
  ## apply maa ikke stole paa at filen kom derfra -- den kan vaere haandbygget.
  if (!identical(as.numeric(doc$counts$ekstra_medrevne), 0))
    stop("D2_APPLY_EXTRA_SWEPT", call. = FALSE)
  if (!identical(as.numeric(doc$counts$overlap_c0), 0))
    stop("D2_APPLY_C0_OVERLAP", call. = FALSE)
  if (!identical(as.numeric(doc$counts$valgte), as.numeric(length(ids))))
    stop("D2_APPLY_COUNT_MISMATCH", call. = FALSE)

  ## En eksport fra en ANDEN base ville ellers passere alt oevrigt.
  if (!identical(as.character(doc$database_name), as.character(live$database_name)) ||
      !identical(as.character(doc$database_identity), as.character(live$database_identity)))
    stop("D2_APPLY_DATABASE_MISMATCH", call. = FALSE)

  if (!identical(as.numeric(live$staged_i_alt), as.numeric(doc$counts$staged_i_alt)))
    stop("D2_APPLY_STAGED_DRIFT", call. = FALSE)
  if (!identical(sort(as.numeric(live$valgte_ids)), sort(ids)))
    stop("D2_APPLY_SELECTION_DRIFT", call. = FALSE)

  list(ids = sort(ids),
       forventet_bagefter = as.numeric(doc$counts$staged_bagefter))
}

## Efterkontrol: D2 roerer UDELUKKENDE person.staged. Koeres INDE i
## transaktionen, saa en afvigelse ruller tilbage frem for blot at melde.
## `before` og `after` er navngivne taellinger fra samme forespoergsel.
d2_check_postcheck <- function(before, after, forventet_bagefter) {
  ## Samme faelde som i eksportens gates: identical(as.numeric(NULL),
  ## as.numeric(NULL)) er TRUE, saa en taelling der tabte et felt ville
  ## passere nul-delta uden at melde noget.
  felter <- c("staged", "person", "fact", "relation", "narrative")
  if (length(setdiff(felter, names(before))) > 0L ||
      length(setdiff(felter, names(after))) > 0L)
    stop("D2_APPLY_TAELLING_MANGLER", call. = FALSE)
  if (!identical(as.numeric(after$staged), as.numeric(forventet_bagefter)))
    stop("D2_APPLY_POSTCHECK_MISMATCH", call. = FALSE)
  for (felt in c("person", "fact", "relation", "narrative")) {
    if (!identical(as.numeric(before[[felt]]), as.numeric(after[[felt]])))
      stop("D2_APPLY_DELTA_NOT_ZERO", call. = FALSE)
  }
  invisible(TRUE)
}
