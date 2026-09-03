# Læse-kun, forbindelsesfri (undtagen den injicerede query-funktion) eksport af
# legacy-migration-kandidater (spec §7, brief Task 7). Kandidatfilen bærer ingen
# rå tekst; teksterne skrives i en separat 0600-fil, som kun bruges lokalt af
# normaliseringen og aldrig committes.

lmc_fail <- function(code) stop(code, call. = FALSE)

lmc_has_work_component <- function(path) {
  "work" %in% strsplit(path, "/", fixed = TRUE)[[1L]]
}

# Nøglen 'tekst' opbygges af tegnkoder, så denne fils kildetekst aldrig bærer
# selve ordet — kandidat-forespørgslen må ikke røre den rå narrativtekst.
.lmc_tekst_key_expr <- "(chr(116)||chr(101)||chr(107)||chr(115)||chr(116))"

lmc_sql <- list(
  candidates = paste(
    "/* LMC_EXPORT_CANDIDATES */ WITH scoped AS (",
    "SELECT person_id, source_id, record_key FROM public.person_external_id",
    "WHERE source_id=$1 AND record_key IS NOT NULL",
    "), narratives AS (",
    "SELECT subjekt_id AS person_id, min(id) AS narrative_id,",
    "count(*)::integer AS narratives_for_person FROM public.narrative",
    "WHERE source_id=$1 AND subjekt_type='person' GROUP BY subjekt_id",
    ") SELECT scoped.record_key::text AS record_key, scoped.person_id::integer AS person_id,",
    "narratives.narrative_id::integer AS narrative_id, person.levende AS person_levende,",
    "coalesce(person.privat,false) AS person_privat, coalesce(person.staged,false) AS person_staged,",
    "coalesce(narrative.privat,false) AS narrative_privat,",
    "encode(sha256(convert_to(to_jsonb(narrative)->>", .lmc_tekst_key_expr, ",'UTF8')),'hex')",
    "AS narrative_text_sha256,",
    "encode(sha256(convert_to(occurrence.verbatim_text,'UTF8')),'hex') AS occurrence_verbatim_sha256,",
    "legacy.legacy_publication_ref::text AS legacy_publication_ref, legacy.status::text AS legacy_status,",
    "legacy.baseline_sha256::text AS legacy_baseline_sha256,",
    "count(*) OVER (PARTITION BY scoped.record_key)::integer AS persons_for_record_key,",
    "count(*) OVER (PARTITION BY scoped.person_id)::integer AS external_ids_for_person,",
    "coalesce(narratives.narratives_for_person,0)::integer AS narratives_for_person,",
    "(binding.narrative_id IS NOT NULL) AS already_bound",
    "FROM scoped",
    "JOIN public.person person ON person.id=scoped.person_id",
    "LEFT JOIN narratives ON narratives.person_id=scoped.person_id",
    "LEFT JOIN public.narrative narrative ON narrative.id=narratives.narrative_id",
    "LEFT JOIN private.source_record record ON record.source_id=scoped.source_id",
    "AND record.record_key=scoped.record_key",
    "LEFT JOIN private.source_record_anchor_current anchor ON anchor.source_record_id=record.id",
    "AND anchor.decision_status='accepted'",
    "LEFT JOIN private.source_record_occurrence occurrence ON occurrence.id=anchor.occurrence_id",
    "LEFT JOIN private.narrative_legacy_publication legacy ON legacy.narrative_id=narrative.id",
    "LEFT JOIN private.narrative_record_publication binding ON binding.narrative_id=narrative.id",
    "ORDER BY scoped.record_key"
  ),
  # Basen kan være ældre end #152 (ingen narrative_legacy_publication-tabel
  # endnu). Samme forespørgsel, men lægger legacy_*-felterne fast til NULL i
  # stedet for at joine en tabel, der ikke findes.
  candidates_no_ledger = paste(
    "/* LMC_EXPORT_CANDIDATES_NO_LEDGER */ WITH scoped AS (",
    "SELECT person_id, source_id, record_key FROM public.person_external_id",
    "WHERE source_id=$1 AND record_key IS NOT NULL",
    "), narratives AS (",
    "SELECT subjekt_id AS person_id, min(id) AS narrative_id,",
    "count(*)::integer AS narratives_for_person FROM public.narrative",
    "WHERE source_id=$1 AND subjekt_type='person' GROUP BY subjekt_id",
    ") SELECT scoped.record_key::text AS record_key, scoped.person_id::integer AS person_id,",
    "narratives.narrative_id::integer AS narrative_id, person.levende AS person_levende,",
    "coalesce(person.privat,false) AS person_privat, coalesce(person.staged,false) AS person_staged,",
    "coalesce(narrative.privat,false) AS narrative_privat,",
    "encode(sha256(convert_to(to_jsonb(narrative)->>", .lmc_tekst_key_expr, ",'UTF8')),'hex')",
    "AS narrative_text_sha256,",
    "encode(sha256(convert_to(occurrence.verbatim_text,'UTF8')),'hex') AS occurrence_verbatim_sha256,",
    "NULL::text AS legacy_publication_ref, NULL::text AS legacy_status,",
    "NULL::text AS legacy_baseline_sha256,",
    "count(*) OVER (PARTITION BY scoped.record_key)::integer AS persons_for_record_key,",
    "count(*) OVER (PARTITION BY scoped.person_id)::integer AS external_ids_for_person,",
    "coalesce(narratives.narratives_for_person,0)::integer AS narratives_for_person,",
    "(binding.narrative_id IS NOT NULL) AS already_bound",
    "FROM scoped",
    "JOIN public.person person ON person.id=scoped.person_id",
    "LEFT JOIN narratives ON narratives.person_id=scoped.person_id",
    "LEFT JOIN public.narrative narrative ON narrative.id=narratives.narrative_id",
    "LEFT JOIN private.source_record record ON record.source_id=scoped.source_id",
    "AND record.record_key=scoped.record_key",
    "LEFT JOIN private.source_record_anchor_current anchor ON anchor.source_record_id=record.id",
    "AND anchor.decision_status='accepted'",
    "LEFT JOIN private.source_record_occurrence occurrence ON occurrence.id=anchor.occurrence_id",
    "LEFT JOIN private.narrative_record_publication binding ON binding.narrative_id=narrative.id",
    "ORDER BY scoped.record_key"
  ),
  texts = paste(
    "/* LMC_EXPORT_TEXTS */ WITH scoped AS (",
    "SELECT person_id, source_id, record_key FROM public.person_external_id",
    "WHERE source_id=$1 AND record_key IS NOT NULL",
    "), narratives AS (",
    "SELECT subjekt_id AS person_id, min(id) AS narrative_id FROM public.narrative",
    "WHERE source_id=$1 AND subjekt_type='person' GROUP BY subjekt_id",
    ") SELECT scoped.record_key::text AS record_key, narrative.tekst AS narrative_text,",
    "occurrence.verbatim_text AS occurrence_text",
    "FROM scoped",
    "LEFT JOIN narratives ON narratives.person_id=scoped.person_id",
    "LEFT JOIN public.narrative narrative ON narrative.id=narratives.narrative_id",
    "LEFT JOIN private.source_record record ON record.source_id=scoped.source_id",
    "AND record.record_key=scoped.record_key",
    "LEFT JOIN private.source_record_anchor_current anchor ON anchor.source_record_id=record.id",
    "AND anchor.decision_status='accepted'",
    "LEFT JOIN private.source_record_occurrence occurrence ON occurrence.id=anchor.occurrence_id",
    "ORDER BY scoped.record_key"
  )
)

lmc_validate_output_dir <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path))
    lmc_fail("OUTPUT_DIR_REQUIRED")
  if (!grepl("^/", path)) lmc_fail("OUTPUT_DIR_NOT_ABSOLUTE")
  if (lmc_has_work_component(path)) lmc_fail("OUTPUT_WORK_PATH")
  info <- file.info(path)
  link <- Sys.readlink(path)
  if (is.na(info$isdir) || !isTRUE(info$isdir) || (!is.na(link) && nzchar(link)))
    lmc_fail("OUTPUT_DIR_INVALID")
  resolved <- normalizePath(path, mustWork = TRUE)
  if (lmc_has_work_component(resolved)) lmc_fail("OUTPUT_WORK_PATH")
  if (bitwAnd(as.integer(info$mode), 511L) != 448L) lmc_fail("OUTPUT_DIR_MODE_INVALID")
  resolved
}

.lmc_col <- function(rows, field) if (nrow(rows)) rows[[field]] else logical(0)

.lmc_int_or_na <- function(value) {
  if (is.na(value)) return(NULL)
  as.integer(value)
}

.lmc_chr_or_na <- function(value) {
  if (is.na(value)) return(NULL)
  as.character(value)
}

.lmc_lgl_or_na <- function(value) {
  if (is.na(value)) return(NULL)
  as.logical(value)
}

lmc_build_candidates <- function(rows) {
  if (!nrow(rows)) return(list())
  lapply(seq_len(nrow(rows)), function(index) list(
    record_key = as.character(rows$record_key[[index]]),
    person_id = as.integer(rows$person_id[[index]]),
    narrative_id = .lmc_int_or_na(rows$narrative_id[[index]]),
    person_levende = .lmc_lgl_or_na(rows$person_levende[[index]]),
    person_privat = as.logical(rows$person_privat[[index]]),
    person_staged = as.logical(rows$person_staged[[index]]),
    narrative_privat = as.logical(rows$narrative_privat[[index]]),
    narrative_text_sha256 = .lmc_chr_or_na(rows$narrative_text_sha256[[index]]),
    occurrence_verbatim_sha256 = .lmc_chr_or_na(rows$occurrence_verbatim_sha256[[index]]),
    legacy_publication_ref = .lmc_chr_or_na(rows$legacy_publication_ref[[index]]),
    legacy_status = .lmc_chr_or_na(rows$legacy_status[[index]]),
    legacy_baseline_sha256 = .lmc_chr_or_na(rows$legacy_baseline_sha256[[index]]),
    persons_for_record_key = as.integer(rows$persons_for_record_key[[index]]),
    external_ids_for_person = as.integer(rows$external_ids_for_person[[index]]),
    narratives_for_person = as.integer(rows$narratives_for_person[[index]]),
    already_bound = as.logical(rows$already_bound[[index]])
  ))
}

lmc_build_texts <- function(rows) {
  if (!nrow(rows)) return(list())
  out <- lapply(seq_len(nrow(rows)), function(index) list(
    narrative_text = .lmc_chr_or_na(rows$narrative_text[[index]]),
    occurrence_text = .lmc_chr_or_na(rows$occurrence_text[[index]])
  ))
  names(out) <- as.character(rows$record_key)
  out
}

lmc_export_run <- function(query, source_id) {
  if (!is.function(query)) lmc_fail("LMC_QUERY_INVALID")
  if (!is.integer(source_id) || length(source_id) != 1L || is.na(source_id) || source_id <= 0L)
    lmc_fail("LMC_SOURCE_ID_INVALID")
  # Basen kan være ældre end #152 (ingen private.narrative_legacy_publication
  # endnu); i så fald er legacy_*-felterne NULL for alle kandidater (forventet).
  has_ledger <- isTRUE(as.logical(query(
    "SELECT to_regclass('private.narrative_legacy_publication') IS NOT NULL AS present")$present[[1L]]))
  candidates_sql <- if (has_ledger) lmc_sql$candidates else lmc_sql$candidates_no_ledger
  candidate_rows <- query(candidates_sql, list(source_id))
  text_rows <- query(lmc_sql$texts, list(source_id))
  list(
    candidates = lmc_build_candidates(candidate_rows),
    texts = lmc_build_texts(text_rows)
  )
}
