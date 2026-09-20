## Reproducerbar (script-baseret, ikke ad hoc) READ-ONLY eksport af
## nuværende narrativ-tilstand for source_id=3 (DAA 1939), person-narrativer.
## Task 2's oprindelige v1-eksport blev genereret ad hoc via en manuel
## psql-session (se .superpowers/sdd/.../task-2-report.md) og kun
## person_id+narrative_sha256. Task 5's rehearsal fandt at replay-værnet
## afviste to gamle importfejl (person 975/986: forkert `side` i DB) -- den
## ret krævede at `side`+`privat` også indgår i eksporten, så
## build_narrative_replacement_manifest_1939_v50.py kan udlede
## expected_old_side/expected_old_privat og de dokumenterede
## side_corrections pr. operation. Denne fil er den REPRODUCERBARE
## erstatning for den ad hoc-forespørgsel; se export_narrative_old_sha_1939_v50.R
## for CLI'et der kalder den mod en rigtig DBI-forbindelse.

export_narrative_old_sha_hash_re <- "^[0-9a-f]{64}$"

stop_export_narrative_old_sha <- function(code) stop(code, call. = FALSE)

## rows: data.frame(person_id, narrative_sha256, side, privat) -- én række pr.
## eksisterende narrativ. `side` må være NA (SQL NULL); `privat` må IKKE være
## NA (fail-closed -- se test for begrundelse). Sorteres deterministisk til
## stigende person_id, uafhængigt af SQL'ens leveringsrækkefølge.
build_narrative_old_sha_export_1939_v50 <- function(rows, database_name, database_identity,
                                                      generator, sql_text) {
  if (!is.data.frame(rows) ||
      !identical(names(rows), c("person_id", "narrative_sha256", "side", "privat")) ||
      !is.numeric(rows$person_id) || !is.character(rows$narrative_sha256) ||
      !is.character(rows$side) || !is.logical(rows$privat))
    stop_export_narrative_old_sha("EXPORT_NARRATIVE_OLD_SHA_1939_ROWS_INVALID")

  is_scalar_nonempty_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  if (!is_scalar_nonempty_string(database_name) || !is_scalar_nonempty_string(database_identity) ||
      !is_scalar_nonempty_string(generator) || !is_scalar_nonempty_string(sql_text))
    stop_export_narrative_old_sha("EXPORT_NARRATIVE_OLD_SHA_1939_METADATA_INVALID")

  if (anyDuplicated(rows$person_id))
    stop_export_narrative_old_sha("EXPORT_NARRATIVE_OLD_SHA_1939_DUPLICATE_PERSON_ID")

  if (nrow(rows) > 0L) {
    valid_pid <- !is.na(rows$person_id) & rows$person_id %% 1 == 0 & rows$person_id > 0
    if (!all(valid_pid))
      stop_export_narrative_old_sha("EXPORT_NARRATIVE_OLD_SHA_1939_PERSON_ID_INVALID")
    valid_sha <- !is.na(rows$narrative_sha256) & grepl(export_narrative_old_sha_hash_re, rows$narrative_sha256)
    if (!all(valid_sha))
      stop_export_narrative_old_sha("EXPORT_NARRATIVE_OLD_SHA_1939_SHA_INVALID")
    if (anyNA(rows$privat))
      stop_export_narrative_old_sha("EXPORT_NARRATIVE_OLD_SHA_1939_PRIVAT_INVALID")
  }

  ordered <- rows[order(rows$person_id), , drop = FALSE]
  row_list <- lapply(seq_len(nrow(ordered)), function(i) {
    list(
      person_id = as.integer(ordered$person_id[[i]]),
      narrative_sha256 = ordered$narrative_sha256[[i]],
      side = ordered$side[[i]],
      privat = isTRUE(ordered$privat[[i]])
    )
  })

  list(
    schema_version = "1939-v50-narrative-old-sha-export-v2",
    generator = generator,
    database = list(database_identity = database_identity, database_name = database_name),
    query = list(sql = sql_text, source_id = 3L, subjekt_type = "person"),
    row_count = as.integer(nrow(ordered)),
    rows = row_list
  )
}
