# PII-gate + markdown-render. Committed rapport må aldrig indeholde levende-PII.

# ---- PRIMÆR PII-kontrol: INPUT-gating (afdøde-ikke-private på BEGGE sider) --
# Filtrér ALLE sammenlignings-input til afdøde-ikke-private FØR sammenligning,
# så ingen levende/privat person kan komme ind i `disc` per konstruktion (også
# som relateret/2.-endepunkt). Fail-closed: ukendt privacy-state => ikke sikker.
# assert_no_living_pii nedenfor er KUN en backstop, ikke den primære garanti.

safe_our_ids <- function(person) {
  lev_ok  <- !is.na(person$levende) & person$levende == FALSE  # NULL levende => skjult
  priv_ok <- is.na(person$privat) | person$privat == FALSE     # NULL privat => ikke-privat (jf. RLS)
  as.integer(person$id[lev_ok & priv_ok])
}

safe_tng_ids <- function(tng_people) {
  ok <- !is.na(tng_people$living)  & tng_people$living  == "0" &
        !is.na(tng_people$private) & tng_people$private == "0"
  tng_people$personID[ok]
}

# Returnerer de gatede input. Efter dette refererer enhver disc-række KUN
# afdøde-ikke-private personer (begge sider).
gate_inputs <- function(xwalk, our_pairs, our_pc, our_attr,
                        tng_families, tng_children, safe_our, safe_tng) {
  so <- function(v) v %in% safe_our
  st <- function(v) v %in% safe_tng
  tc <- tng_children[st(tng_children$child_tng), , drop = FALSE]  # barn skal være sikkert
  tc$father_tng[!st(tc$father_tng)] <- NA_character_              # usikker forælder -> skjul slot
  tc$mother_tng[!st(tc$mother_tng)] <- NA_character_
  list(
    xwalk        = xwalk[so(xwalk$person_id) & st(xwalk$tng_id), , drop = FALSE],
    our_pairs    = our_pairs[so(our_pairs$person_id) & so(our_pairs$spouse_id), , drop = FALSE],
    our_pc       = our_pc[so(our_pc$child_id) & so(our_pc$parent_id), , drop = FALSE],
    our_attr     = our_attr[so(our_attr$person_id), , drop = FALSE],
    tng_families = tng_families[st(tng_families$husband) & st(tng_families$wife), , drop = FALSE],
    tng_children = tc
  )
}

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
  d <- filter_living(discrepancies, living_person_ids)  # backstop (input-gating er primær)
  actionable <- c("ekstra_hos_os", "mangler_hos_os", "dato_uenig", "køn_uenig")
  tab <- table(factor(d$kategori, levels = unique(c(actionable, d$kategori))))
  lines <- c(sprintf("# TNG-QA-rapport %s", date), "",
             "> TNG = sammenlignings-reference, ikke facit. Uenighed = uafklaret til afgørelse.", "",
             "## Oversigt", "")
  for (k in names(tab)) lines <- c(lines, sprintf("- %s: %d", k, tab[[k]]))
  lines <- c(lines, "")
  # Detaljér KUN de handlingsorienterede kategorier; enig/uden_for_scope er kun tal.
  for (kat in actionable) {
    sub <- d[d$kategori == kat, ]
    if (!nrow(sub)) next
    lines <- c(lines, sprintf("## %s (%d)", kat, nrow(sub)), "")
    for (i in seq_len(nrow(sub)))
      lines <- c(lines, sprintf("- **%s** (%s): %s",
                                .label(sub$person_id[i], ext_id), sub$tng_id[i], sub$detalje[i]))
    lines <- c(lines, "")
  }
  txt <- paste(lines, collapse = "\n")
  assert_no_living_pii(txt, living_person_ids)
  txt
}
