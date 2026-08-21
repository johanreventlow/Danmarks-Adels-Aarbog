## Ren logik bag C0-efterkoerslens apply: CLI-gaten, guarden mod at basen har
## flyttet sig, og efterkontrollen. Ingen DB-adgang.

## Fail-closed argument-parser. Et ukendt flag er en FEJL: i fase D1 blev et
## opfundet --dryrun stiltiende slugt, og 68 personer blev publiceret i prod.
c0f_parse_apply_args <- function(args) {
  allowed <- c("--manifest", "--expect-sha256", "--backup", "--jeg-mener-det")
  flags <- args[grepl("^--", args)]
  if (any(!flags %in% allowed) || anyDuplicated(flags))
    stop("C0F_APPLY_CLI_INVALID", call. = FALSE)
  if (!("--manifest" %in% flags)) stop("C0F_APPLY_CLI_INVALID", call. = FALSE)
  value <- function(flag) {
    index <- match(flag, args)
    if (is.na(index) || index == length(args) || grepl("^--", args[[index + 1L]]))
      stop("C0F_APPLY_CLI_INVALID", call. = FALSE)
    args[[index + 1L]]
  }
  manifest <- value("--manifest")
  if (!("--expect-sha256" %in% flags)) stop("C0F_APPLY_SHA_REQUIRED", call. = FALSE)
  expect_sha256 <- value("--expect-sha256")
  ## Basen koerer paa free tier UDEN automatisk backup. At tage en dump er en
  ## instruktion i planen; her er det en betingelse for at koere.
  if (!("--backup" %in% flags)) stop("C0F_APPLY_BACKUP_REQUIRED", call. = FALSE)
  backup <- value("--backup")
  ## Bekraeftelsen tjekkes SIDST, saa en malformet kommandolinje aldrig kan
  ## fremstaa som "manglede bare bekraeftelsen".
  if (!("--jeg-mener-det" %in% flags))
    stop("C0F_APPLY_CONFIRMATION_REQUIRED", call. = FALSE)
  list(manifest = manifest, expect_sha256 = expect_sha256, backup = backup)
}

c0f_spaerrer <- function(x) any(is.na(x) | as.logical(x))

## Sammenligner manifestet med basen som den ser ud NU. `live` skal maales
## INDE i skrive-transaktionen; ellers staar vinduet mellem maaling og
## skrivning aabent (TOCTOU).
c0f_plan_apply <- function(manifest, live) {
  if (!identical(manifest$schema_version, "1939-v50-c0-followup-manifest-v1"))
    stop("C0F_APPLY_SCHEMA_UNKNOWN", call. = FALSE)
  ## Et manifest bygget mod rehearsal-basen maa ALDRIG kunne koeres mod prod.
  ## env_or falder tilbage per variabel, saa en manglende PGHOST sender
  ## scriptet mod produktionen -- dette er spaerringen for netop det.
  if (!identical(as.character(manifest$database_name), as.character(live$database_name)) ||
      !identical(as.character(manifest$database_identity), as.character(live$database_identity)))
    stop("C0F_APPLY_DATABASE_MISMATCH", call. = FALSE)
  ops <- manifest$operations
  if (length(ops) == 0L) stop("C0F_APPLY_EMPTY", call. = FALSE)

  forventet_narr <- vapply(ops, function(o) as.numeric(o$narrative_id), numeric(1))
  if (!identical(sort(as.numeric(live$narrative_ids)), sort(forventet_narr)))
    stop("C0F_APPLY_NARRATIVE_DRIFT", call. = FALSE)
  ## Replay-vaern: er teksten aendret siden eksporten, gaelder beslutningerne
  ## en anden tekst end den vi er ved at overskrive.
  if (!identical(as.character(live$old_shas),
                 vapply(ops, function(o) as.character(o$expected_old_narrative_sha256),
                        character(1))))
    stop("C0F_APPLY_OLD_SHA_MISMATCH", call. = FALSE)
  ## GDPR (invariant 8): writeren sender altid p_privat=false, saa en privat
  ## post ville blive tavst afprivatiseret.
  if (c0f_spaerrer(live$privat)) stop("C0F_APPLY_PRIVAT", call. = FALSE)
  ## Identitetskontrol: beviser at recorden og narrativet er samme trykte post.
  if (!identical(as.character(live$sider),
                 vapply(ops, function(o) as.character(o$page_from), character(1))))
    stop("C0F_APPLY_SIDE_MISMATCH", call. = FALSE)
  ## red_publicer_narrative_record kaster SOURCE_RECORD_PUBLICATION_ALREADY_BOUND
  ## halvvejs igennem; vi vil hellere stoppe foer noget er skrevet.
  if (!identical(as.numeric(live$bindinger), 0))
    stop("C0F_APPLY_ALREADY_BOUND", call. = FALSE)

  list(operations = ops, forventet_bindinger = as.numeric(length(ops)))
}

## Efterkontrol: fasen aendrer narrativ-TEKST og tilfoejer bindinger. Antallet
## af narrativer, personer, fakta og relationer skal staa stille.
##
## Dette er et NETTO-tjek: det beviser at bindingstallet steg med det rette
## antal og at intet andet rykkede sig i mangde. Det beviser IKKE at det er
## de RIGTIGE ni bindinger, der blev oprettet, eller at maal-narrativerne
## faktisk baerer manifestets new_text_sha256 -- en samtidig transaktion der
## sletter een binding og opretter en anden ville give netto +9 og passere
## her. Se c0f_check_write_identity for den kontrol.
c0f_check_postcheck <- function(before, after, forventet_bindinger) {
  felter <- c("bindinger", "narrativer", "personer", "fakta", "relationer")
  if (length(setdiff(felter, names(before))) > 0L ||
      length(setdiff(felter, names(after))) > 0L)
    stop("C0F_APPLY_TAELLING_MANGLER", call. = FALSE)
  if (!identical(as.numeric(after$bindinger) - as.numeric(before$bindinger),
                 as.numeric(forventet_bindinger)))
    stop("C0F_APPLY_POSTCHECK_MISMATCH", call. = FALSE)
  for (felt in c("narrativer", "personer", "fakta", "relationer")) {
    if (!identical(as.numeric(before[[felt]]), as.numeric(after[[felt]])))
      stop("C0F_APPLY_DELTA_NOT_ZERO", call. = FALSE)
  }
  invisible(TRUE)
}

## Mangde-tjek, ikke antal-tjek: beviser at det skrevne ER det tilsigtede.
## For hver operation: (a) maal-narrativets NUVAERENDE tekst-hash matcher
## manifestets new_text_sha256 praecis, og (b) der findes PRAECIS EEN binding
## for det narrative_id, med det source_record_id vi selv slog op og skrev.
## `operations` er manifestets operationer, hver udvidet med det faktiske
## `source_record_id` skriveren brugte. `narrative_shas` er en liste noeglet
## paa as.character(narrative_id) -> observeret sha256-hex. `bindings` er
## list(narrative_id=, source_record_id=) -- een raekke per fundet binding
## for de paagaeldende narrative_id'er.
c0f_check_write_identity <- function(operations, narrative_shas, bindings) {
  for (op in operations) {
    nid_chr <- as.character(op$narrative_id)
    actual_sha <- narrative_shas[[nid_chr]]
    if (is.null(actual_sha)) stop("C0F_APPLY_TEXT_HASH_MISSING", call. = FALSE)
    if (!identical(as.character(actual_sha), as.character(op$new_text_sha256)))
      stop("C0F_APPLY_TEXT_HASH_MISMATCH", call. = FALSE)

    treff <- which(as.character(bindings$narrative_id) == nid_chr)
    if (length(treff) != 1L)
      stop("C0F_APPLY_BINDING_COUNT_MISMATCH", call. = FALSE)
    if (!identical(as.character(bindings$source_record_id[[treff]]),
                   as.character(op$source_record_id)))
      stop("C0F_APPLY_BINDING_SOURCE_MISMATCH", call. = FALSE)
  }
  invisible(TRUE)
}
