# Rene, DB-frie beslutninger for den nye evidensprojektion. Den egentlige
# loader må kun skrive den plan, som disse guards har accepteret.

evidence_nonempty <- function(value) {
  !is.null(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(as.character(value)))
}

build_evidence_projection_plan <- function(persona_states) {
  if (!is.list(persona_states)) stop("EVIDENCE_PROJECTION_INPUT_INVALID")
  accepted <- Filter(function(state) identical(state$status, "accepted"), persona_states)
  if (!length(accepted)) return(list(canonical_person_ids = integer(), provenance = list()))

  by_persona <- split(accepted, vapply(accepted, function(state) as.character(state$source_persona_id), character(1)))
  for (persona_id in names(by_persona)) {
    states <- by_persona[[persona_id]]
    targets <- unique(vapply(states, function(state) as.integer(state$canonical_person_id), integer(1)))
    if (!evidence_nonempty(persona_id) || length(targets) != 1L || is.na(targets) || targets < 1L)
      stop("EVIDENCE_PROJECTION_IDENTITY_CONFLICT")
  }

  provenance <- lapply(accepted, function(state) {
    if (!evidence_nonempty(state$source_persona_id) || !is.numeric(state$source_id) || length(state$source_id) != 1L ||
        is.na(state$source_id) || state$source_id < 1L || !evidence_nonempty(state$record_key) ||
        is.null(state$canonical_person_id) || is.na(state$canonical_person_id) || state$canonical_person_id < 1L)
      stop("EVIDENCE_PROJECTION_PROVENANCE_REQUIRED")
    list(source_persona_id = as.character(state$source_persona_id), source_id = as.integer(state$source_id),
         record_key = as.character(state$record_key), canonical_person_id = as.integer(state$canonical_person_id))
  })
  list(canonical_person_ids = sort(unique(vapply(provenance, `[[`, integer(1), "canonical_person_id"))), provenance = provenance)
}

# Transaktionsrammen er med vilje afhængighedsinjiceret. Den kan dermed testes
# uden database, mens den konkrete RPostgres-writer senere blot leverer de fire
# callbacks. En fejl efter BEGIN kan aldrig ende i et delvist commit.
project_evidence_batch <- function(persona_states, begin, write, commit, rollback) {
  plan <- build_evidence_projection_plan(persona_states)
  begin()
  committed <- FALSE
  tryCatch({
    for (row in plan$provenance) write(row)
    commit()
    committed <- TRUE
  }, error = function(error) {
    rollback()
    stop(error)
  })
  if (!committed) stop("EVIDENCE_PROJECTION_COMMIT_REQUIRED")
  plan
}
