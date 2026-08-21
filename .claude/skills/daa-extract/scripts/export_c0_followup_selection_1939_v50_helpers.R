## Ren transformation: DB-raekker -> eksportdokument for C0's efterkoersel.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme moenster som
## export_d2_spouse_selection_1939_v50_helpers.R).

## De ni koblinger. Person 1017 er BEVIDST udeladt: dens kobling ville slette
## 149 tegn, hvoraf de foerste ~92 ikke findes noget andet sted -- person 1021
## er halen af dens afsnit B). Sagen er en C3-sammenlaegning.
C0F_PERSON_IDS <- c(963, 967, 978, 991, 992, 1296, 1297, 1298, 1299)

C0F_SHA_RE <- "^[0-9a-f]{64}$"

## En fail-closed gate der spoerger "er nogen af dem private?" svarer FALSE,
## naar kolonnen slet ikke findes: any(logical(0)) er FALSE. Fravaer af data
## ville altsaa ligne fravaer af problem. Derfor kraeves felterne foerst.
c0f_kraev_kolonner <- function(df, navne) {
  mangler <- setdiff(navne, names(df))
  if (length(mangler) > 0L)
    stop(paste0("C0F_SELECTION_KOLONNE_MANGLER:", paste(mangler, collapse = ",")),
         call. = FALSE)
}

## Spaerrer ved TRUE OG ved NA: publicering skal kraeve bevis, ikke fravaer af
## modbevis. any(c(NA)) er NA og ville faa `if` til at fejle uklart.
c0f_spaerrer <- function(x) any(is.na(x) | as.logical(x))

build_c0_followup_selection_1939_v50 <- function(rows, database_name,
                                                 database_identity, generator) {
  c0f_kraev_kolonner(rows, c("person_id", "narrative_id", "old_sha256",
                             "privat", "side"))
  if (!identical(as.numeric(nrow(rows)), as.numeric(length(C0F_PERSON_IDS))))
    stop("C0F_SELECTION_COUNT_INVALID", call. = FALSE)
  if (!identical(sort(as.numeric(rows$person_id)), sort(C0F_PERSON_IDS)))
    stop("C0F_SELECTION_IDS_INVALID", call. = FALSE)
  if (c0f_spaerrer(rows$privat)) stop("C0F_SELECTION_PRIVAT", call. = FALSE)
  if (any(is.na(rows$narrative_id)))
    stop("C0F_SELECTION_NARRATIVE_MISSING", call. = FALSE)
  if (!all(grepl(C0F_SHA_RE, as.character(rows$old_sha256))))
    stop("C0F_SELECTION_SHA_INVALID", call. = FALSE)

  selected <- lapply(order(rows$person_id), function(i) list(
    person_id    = as.numeric(rows$person_id[[i]]),
    narrative_id = as.numeric(rows$narrative_id[[i]]),
    old_sha256   = as.character(rows$old_sha256[[i]]),
    privat       = as.logical(rows$privat[[i]]),
    side         = if (is.na(rows$side[[i]])) NA else as.character(rows$side[[i]])
  ))
  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       selected = selected)
}
