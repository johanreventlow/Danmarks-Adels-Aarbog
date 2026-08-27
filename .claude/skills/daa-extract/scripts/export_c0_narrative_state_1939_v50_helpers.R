## Ren transformation: DB-raekker -> eksportdokument for fase C0.
## Ingen DB-adgang, saa den kan testes uden forbindelse (samme mønster som
## export_narrative_old_sha_1939_v50_helpers.R).
##
## Dokumentet er C0's sammenligningsgrundlag: hele prods
## source_id=3-narrativbestand med tekst, metadata og record-binding.
build_c0_narrative_state_export_1939_v50 <- function(rows, database_name,
                                                     database_identity,
                                                     generator, sql_text) {
  if (anyDuplicated(rows$person_id))
    stop("C0_EXPORT_DUPLICATE_PERSON", call. = FALSE)
  if (any(!grepl("^[0-9a-f]{64}$", rows$tekst_sha256)))
    stop("C0_EXPORT_SHA_INVALID", call. = FALSE)
  order_index <- order(rows$person_id)
  out <- lapply(order_index, function(i) {
    list(
      person_id = as.numeric(rows$person_id[[i]]),
      visning_navn = as.character(rows$visning_navn[[i]]),
      staged = as.logical(rows$staged[[i]]),
      # NA (ikke NULL) -> jsonlite skriver `null`; NULL ville blive `{}`,
      # som Python laeser som en truthy tom dict.
      side = if (is.na(rows$side[[i]])) NA else as.character(rows$side[[i]]),
      privat = as.logical(rows$privat[[i]]),
      tekst = as.character(rows$tekst[[i]]),
      tekst_sha256 = as.character(rows$tekst_sha256[[i]]),
      har_record_binding = as.logical(rows$har_record_binding[[i]]),
      binding_status = if (is.na(rows$binding_status[[i]])) NA
                       else as.character(rows$binding_status[[i]])
    )
  })
  list(schema_version = "1.0", database_name = database_name,
       database_identity = database_identity, generator = generator,
       sql_text = sql_text, row_count = length(out), rows = out)
}
