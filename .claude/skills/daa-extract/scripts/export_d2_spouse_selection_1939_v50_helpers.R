## Ren transformation: DB-raekker -> eksportdokument for fase D2.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme moenster som
## export_d1_staged_selection_1939_v50_helpers.R).
##
## Dokumentet er D2's grundlag: de staged gift-ind-aegtefaeller hvis partner
## allerede er synlig. Alle fem kontroltal valideres HER, saa en raadden
## maaling ikke kan naa frem til apply-trinnet.

## Spaerrer ved TRUE OG ved NA. NA betyder "ikke bevist afdoed/offentlig",
## og en publicering skal kraeve bevis, ikke fravaer af modbevis. Skrevet som
## en eksplicit vektor frem for any(x), fordi any(c(NA)) er NA og ville faa
## `if` til at fejle med en uklar meddelelse i stedet for at spaerre.
spaerrer <- function(x) any(is.na(x) | as.logical(x))

## En fail-closed gate der spoerger "er nogen af dem levende?" svarer FALSE,
## naar kolonnen slet ikke findes: any(logical(0)) er FALSE. Fravaer af data
## ville altsaa ligne fravaer af problem -- praecis den omvendte fejlretning.
## Derfor kraeves felterne til stede, FOER de bruges.
kraev_kolonner <- function(df, navne) {
  mangler <- setdiff(navne, names(df))
  if (length(mangler) > 0L)
    stop(paste0("D2_SELECTION_KOLONNE_MANGLER:", paste(mangler, collapse = ",")),
         call. = FALSE)
}

build_d2_spouse_selection_1939_v50 <- function(selected_rows, counts,
                                               database_name, database_identity,
                                               generator) {
  kraev_kolonner(selected_rows, c("person_id", "visning_navn", "levende",
                                  "privat", "partner_id", "har_samme_som"))
  n <- nrow(selected_rows)
  if (n == 0L) stop("D2_SELECTION_EMPTY", call. = FALSE)
  if (anyDuplicated(selected_rows$person_id))
    stop("D2_SELECTION_DUPLICATE_PERSON", call. = FALSE)
  if (!identical(as.numeric(counts$valgte), as.numeric(n)))
    stop("D2_SELECTION_COUNT_MISMATCH", call. = FALSE)
  ## RPC'ens medrivnings-praedikat filtrerer IKKE paa rolle: et staged barn i
  ## samme familie ville ogsaa blive afstaget. Er tallet ikke 0, publicerer vi
  ## nogen vi ikke har set paa.
  if (!identical(as.numeric(counts$ekstra_medrevne), 0))
    stop("D2_SELECTION_EXTRA_SWEPT", call. = FALSE)
  if (!identical(as.numeric(counts$overlap_c0), 0))
    stop("D2_SELECTION_C0_OVERLAP", call. = FALSE)
  if (!identical(as.numeric(counts$staged_i_alt) - as.numeric(counts$valgte),
                 as.numeric(counts$staged_bagefter)))
    stop("D2_SELECTION_REMAINDER_MISMATCH", call. = FALSE)
  ## Invariant 8 (GDPR): publicering goer personen synlig for anonyme laesere.
  ## En levende eller privatmarkeret person maa aldrig med, og en person uden
  ## navn ville blive en tom raekke i fladen. Praedikatet i SQL'en filtrerer
  ## kun paa staged + synlig partner, saa gaten hoerer her.
  if (spaerrer(selected_rows$levende) || spaerrer(selected_rows$privat))
    stop("D2_SELECTION_NOT_PUBLIC_SAFE", call. = FALSE)
  if (any(is.na(selected_rows$visning_navn)) ||
      any(!nzchar(trimws(as.character(selected_rows$visning_navn)))))
    stop("D2_SELECTION_MISSING_NAME", call. = FALSE)

  selected <- lapply(order(selected_rows$person_id), function(i) list(
    person_id     = as.numeric(selected_rows$person_id[[i]]),
    visning_navn  = as.character(selected_rows$visning_navn[[i]]),
    levende       = as.logical(selected_rows$levende[[i]]),
    privat        = as.logical(selected_rows$privat[[i]]),
    partner_id    = as.numeric(selected_rows$partner_id[[i]]),
    har_samme_som = as.logical(selected_rows$har_samme_som[[i]])
  ))

  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       counts = counts, selected = selected)
}
