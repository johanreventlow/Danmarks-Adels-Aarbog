# PII-gate + markdown-render. Committed rapport må aldrig indeholde levende-PII.

filter_living <- function(discrepancies, living_person_ids) {
  discrepancies[!(discrepancies$person_id %in% living_person_ids), , drop = FALSE]
}

assert_no_living_pii <- function(report_text, living_person_ids) {
  for (id in living_person_ids) {
    if (grepl(sprintf("\\b%d\\b", id), report_text))
      stop(sprintf("PII-gate: levende person_id %d optræder i rapporten — commit afvist.", id))
  }
  invisible(TRUE)
}

.label <- function(pid, ext_id) {
  r <- ext_id[ext_id$person_id == pid, ]
  if (nrow(r)) sprintf("%s-%s", r$linje[1], r$nr[1]) else sprintf("p%d", pid)
}

render_report <- function(discrepancies, ext_id, living_person_ids, date) {
  d <- filter_living(discrepancies, living_person_ids)
  lines <- c(sprintf("# TNG-QA-rapport %s", date),
             "",
             "> TNG = sammenlignings-reference, ikke facit. Uenighed = uafklaret til afgørelse.",
             "")
  for (kat in unique(d$kategori)) {
    lines <- c(lines, sprintf("## %s", kat), "")
    sub <- d[d$kategori == kat, ]
    for (i in seq_len(nrow(sub)))
      lines <- c(lines, sprintf("- **%s** (%s): %s",
                                .label(sub$person_id[i], ext_id), sub$tng_id[i], sub$detalje[i]))
    lines <- c(lines, "")
  }
  txt <- paste(lines, collapse = "\n")
  assert_no_living_pii(txt, living_person_ids)
  txt
}
