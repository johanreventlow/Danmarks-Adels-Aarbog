# Review 07 — TNG-QA crosswalk-pipeline (R/tng-qa/)

> Dual-review-cycle 2026-06-29. Branch `feat/tng-qa-pipeline` (isoleret worktree).
> Phase 1 = konsolideret Claude-review (11 task-reviews + opus whole-branch).
> 62 testthat-tests grønne. TNG-extract verificeret mod ægte dump (25745/10016/18995).

Pipeline: `01-extract-tng.R` (mysqldump→DuckDB) · `02-pull-ours.R` (read-only Supabase)
· `03-normalize.R` (navn/dato/køn) · `04-match.R` (blok+score+injektive tiers) ·
`05-review.R` (idempotent review-merge) · `06-compare.R` (relations-sammenligning) ·
`07-report.R` (PII-gate+markdown) · `run-pipeline.R` (orkestrator, trin-3-4/6 = skeleton).

## Invarianter (Claude-verdict: holder i shipped/eksekverbar tilstand)

1. Read-only Supabase — `connect_readonly` sætter `default_transaction_read_only=on`;
   `assert_readonly` verificerer `current_setting('transaction_read_only')=="on"`
   (`02-pull-ours.R`). Ingen DML nogen steder; `pull_ours` er ren SELECT.
2. Matching kun på person-attributter (ikke-cirkularitet) — `score_pair` bruger
   `name_sim/birth_overlap/death_overlap/sex_eq`; `assign_tiers` + `unique_block`.
   Ingen relations-kolonne i scoring (`04-match.R`).
3. Injektiv crosswalk (auto-tier) — `used_tng`/`assigned_person` efter global score-sort
   (`04-match.R`). **Caveat:** review-tier ikke injektiv-guardet; `merge_review_decisions`
   re-tjekker intet.
4. Kant kun sammenlignet når begge endepunkter matchet — `compare_marriages` +
   `compare_parent_child` reverse-loop NA-guarder før `mangler_hos_os` (`06-compare.R`).
5. **PII-gate fail-closed men HALV-håndhævet** — `assert_no_living_pii` kaster på vores-side
   levende `person_id` i tekst (`07-report.R`). MEN spec kræver ekskludering hvor ENTEN
   vores `levende/privat` ELLER TNG `living/private` er sat. Kun vores-side; TNG
   `living/private` bæres ind i DuckDB men læses ALDRIG. (Vacuously safe: `render_report`
   nås ikke i shipped pga. trin-3-4-guard.)
6. Diakritik bevaret — `.lower` = `stri_trans_tolower(locale="da_DK")`; ingen ASCII-fold.
7. TNG = reference ikke facit — rapport-header + kategorier `*_uenig`/`uden_for_scope`.
8. Følsomme filer git-ignored — `data/tng.duckdb`, `tng-crosswalk.csv`, `tng-review-queue.csv`.

## H1 [MEDIUM] — PII-gate håndhæver kun vores-side levende, ikke TNG-side
**Lokation:** `R/tng-qa/07-report.R` (`filter_living`, `assert_no_living_pii`); TNG
`living/private` loades i `01-extract-tng.R` men konsumeres ingen steder.
**Symptom:** Spec §GDPR kræver udeladelse hvor vores `levende/privat` ELLER TNG
`living/private` er sat. Kun vores-side numerisk `person_id` gates.
**Konsekvens:** En levende TNG-persons `tng_id` (fx `"TNG: I1—I9"`) passerer gaten.
Cross-namespace (TNG-ID ≠ vores numeriske id) så ingen direkte re-identifikation, men
spec-invariant er ikke fuldt implementeret.
**Status:** Unreachable i shipped (bag trin-3-4-guard). Follow-up før trin-6 wires.
**Foreslået fix:** `filter_living` + gate skal også droppe/blokere rækker hvor matchet
TNG-person har `living=1`/`private=1`; bær TNG-flag gennem crosswalk til rapport.

## H2 [MEDIUM] — Review-kø-persistens brudt
**Lokation:** `R/tng-qa/run-pipeline.R` (trin 5: læser `rq_csv` som decisions, overskriver
derefter `rq_csv` med `crosswalk[tier=="review",]` uden `afgoerelse`/`ny_tng_id`);
`05-review.R` `merge_review_decisions` muterer kun `tier`.
**Symptom:** `crosswalk` genbygges fra bunden hver kørsel → bekræftede/afviste afgørelser
tabes; spec trin-5 "afviste huskes (dukker ikke op igen)" ikke honoreret. Anden kørsel
fodrer `decisions$afgoerelse == NULL` → length-0 `if`-fejl.
**Status:** Unreachable bag trin-3-4-guard. Doc-påstand allerede rettet (commit 23dd760).
**Foreslået fix:** Persistér afgørelser (separat decisions-fil ELLER merge mod eksisterende
crosswalk-CSV) før crosswalk-genbygning.

## H3 [LOW] — tng_children-reshape mangler (i skeleton)
**Lokation:** `R/tng-qa/06-compare.R` `compare_parent_child` forventer
`child_tng/father_tng/mother_tng`; rå dump-tabel er `familyID/personID + frel/mrel`.
**Symptom:** Reshape (join `tng_families`: far=husband, mor=wife) lever kun i den
udkommenterede trin-6-glue → `compare_parent_child` kan ikke fodres direkte fra
`dbGetQuery("SELECT * FROM tng_children")`.
**Konsekvens:** Trin-6 ikke kørbar før reshape implementeres+testes. Konsistent m. skeleton.

## M1 [LOW] — strip_titles strippper partikler fra fornavne
**Lokation:** `R/tng-qa/03-normalize.R` `strip_titles` anvendt på `first`-arg.
**Symptom:** "von/af/til" word-bounded fjernes også fra fornavne → "Anna von …" mister token.
**Konsekvens:** Match-præcision, ikke invariant. Kalibreres mod facit-sæt.

## M2 [LOW] — review-tier ikke injektiv-guardet
Se invariant 3-caveat. To review-rækker kan pege på samme `tng_id`; menneske-gated, men
`merge_review_decisions` håndhæver ikke injektivitet ved accept.

## Cleanup (ekskluderet fra ROI-tally)
- `01-extract-tng.R`: dead `n <- 0L`; ét `on.exit` uden `add=TRUE`; dump læst 2× per tabel;
  collist-fixture stress-tester ikke `fix_mysql_literals` på multi-linje-stien.
- `04-match.R`: `ambiguity_margin` markeret RESERVERET (ubrugt).
- `05-review.R`: tom-empty path ej testet. `02-pull-ours.R`: `connect_readonly` ingen
  on.exit-cleanup; `assert_readonly` ej testet (kræver live PG). `07-report.R`: `.label`
  bruger `%s` på numerisk `nr`.

## Bevidst udskudt
- bio-vs-adopteret (frel/mrel) i forældre-barn (spec trin-6 nævner det; kræver vores
  rolle-subtyper plumbed i trin-6-glue).
- trin-3-4 score/blok-glue: kalibreres empirisk mod håndlabelt facit-sæt.
