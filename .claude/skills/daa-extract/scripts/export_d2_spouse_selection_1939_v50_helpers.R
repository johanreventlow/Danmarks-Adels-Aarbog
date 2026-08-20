## Ren transformation: DB-raekker -> eksportdokument for fase D2.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme moenster som
## export_d1_staged_selection_1939_v50_helpers.R).
##
## Dokumentet er D2's grundlag: de staged gift-ind-aegtefaeller hvis partner
## allerede er synlig. Alle fem kontroltal valideres HER, saa en raadden
## maaling ikke kan naa frem til apply-trinnet.

build_d2_spouse_selection_1939_v50 <- function(selected_rows, counts,
                                               database_name, database_identity,
                                               generator) {
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

  selected <- lapply(order(selected_rows$person_id), function(i) list(
    person_id     = as.numeric(selected_rows$person_id[[i]]),
    visning_navn  = as.character(selected_rows$visning_navn[[i]]),
    partner_id    = as.numeric(selected_rows$partner_id[[i]]),
    har_samme_som = as.logical(selected_rows$har_samme_som[[i]])
  ))

  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       counts = counts, selected = selected)
}
