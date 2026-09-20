## Ren transformation: DB-raekker -> eksportdokument for fase D1.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme mønster som
## export_c0_narrative_state_1939_v50_helpers.R).
##
## Dokumentet er D1's beslutningsgrundlag: de staged probander der opfylder
## alle tre objektive kriterier, plus de partner-stubs som
## red_publicer_personer vil trække med sig.

## Parser en komma-separeret id-streng til en talvektor. NA/tom -> numeric(0),
## saa "ingen partnere" og "ukendt" ikke kan forveksles i JSON'en.
##
## I() er IKKE kosmetik: jsonlite::toJSON(auto_unbox=TRUE) skriver en
## ét-element-vektor som en SKALAR (1467 i stedet for [1467]), og Python ville
## saa laese én partner som et tal frem for en liste. I() tvinger array-form
## uanset laengde.
.d1_parse_ids <- function(text) {
  if (length(text) != 1L || is.na(text) || !nzchar(text)) return(I(numeric(0)))
  I(as.numeric(strsplit(text, ",", fixed = TRUE)[[1L]]))
}

build_d1_staged_selection_1939_v50 <- function(selected_rows, partner_rows, counts,
                                               database_name, database_identity,
                                               generator) {
  if (anyDuplicated(selected_rows$person_id))
    stop("D1_SELECTION_DUPLICATE_PERSON", call. = FALSE)
  if (nrow(partner_rows) > 0L && anyDuplicated(partner_rows$person_id))
    stop("D1_SELECTION_DUPLICATE_PARTNER", call. = FALSE)
  ## En forudsagt partner maa ikke ogsaa vaere valgt: ellers taelles personen
  ## to gange, og efterkontrollens forventede antal bliver forkert.
  if (nrow(partner_rows) > 0L &&
      length(intersect(selected_rows$person_id, partner_rows$person_id)) > 0L)
    stop("D1_SELECTION_PARTNER_OVERLAP", call. = FALSE)

  selected <- lapply(order(selected_rows$person_id), function(i) list(
    person_id = as.numeric(selected_rows$person_id[[i]]),
    visning_navn = as.character(selected_rows$visning_navn[[i]]),
    # NA (ikke NULL) -> jsonlite skriver `null`; NULL ville blive `{}`.
    side = if (is.na(selected_rows$side[[i]])) NA else as.character(selected_rows$side[[i]]),
    fakta = as.numeric(selected_rows$fakta[[i]]),
    samme_som_2020 = as.logical(selected_rows$samme_som_2020[[i]]),
    partner_ids = .d1_parse_ids(selected_rows$partner_ids[[i]])
  ))
  partners <- if (nrow(partner_rows) == 0L) list() else
    lapply(order(partner_rows$person_id), function(i) list(
      person_id = as.numeric(partner_rows$person_id[[i]]),
      visning_navn = as.character(partner_rows$visning_navn[[i]]),
      via_person_ids = .d1_parse_ids(partner_rows$via_person_ids[[i]])
    ))

  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       counts = counts, selected = selected, predicted_partners = partners)
}
