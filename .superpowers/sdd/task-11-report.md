# Task 11 rapport — pipeline-orkestrator + brugsanvisning

**Dato:** 2026-06-29  
**Branch:** feat/tng-qa-pipeline

## Commits

| SHA | Emne |
|-----|------|
| 59feaf8 | feat(tng-qa): pipeline-orkestrator + brugsanvisning |
| c2193df | fix(tng-qa): load_tng_table håndterer kolonne-liste multi-linje INSERT |

## Status: DONE

## Oprettede / ændrede filer

| Fil | Handling |
|-----|----------|
| `R/tng-qa/run-pipeline.R` | **Ny** — orkestrerer trin 1-6; trin 3-4 og trin 6 er kommentar-skeletter der kalibreres empirisk mod facit-sæt inden prod-kørsel |
| `docs/tng-qa-koersel.md` | **Ny** — brugsanvisning: env-vars, SELECT-only-rolle, review-kø-workflow, git-ignorerede filer, transaction_read_only-GUC-guard, kalibreringsprocedure, GDPR PII-gate begrænsning |
| `R/tng-qa/01-extract-tng.R` | **Rettet** — `load_tng_table` håndterer nu kolonne-liste multi-linje INSERT (faktisk mysqldump-format) |
| `tests/testthat/test-extract.R` | **Udvidet** — ny test for kolonne-liste-format |
| `tests/testthat/fixtures/mini-tng-collist.sql` | **Ny** — fixture der låser multi-linje INSERT-stien |
| `tests/testthat/helper-source.R` | **Rettet** — pattern `^[0-9].*\.R$` (som orkestratoren) så `run-pipeline.R` ikke eksekveres ved `source()` under test |

## Verificering

| Check | Resultat |
|-------|----------|
| Parse (`run-pipeline.R`) | **parse OK** |
| Test-suite | **PASS 62** (59 eksisterende + 3 nye) |
| Røgtest tng_people | **25 745 rækker** |
| Røgtest tng_families | **10 016 rækker** |
| Røgtest tng_children | **18 995 rækker** |

## Kendte begrænsninger (dokumenteret i brugsanvisning)

1. **Trin 3-4 er kommentar-skelet** — kalibreres mod håndlabelt facit-sæt; `scored`-tabel + blokerings-glue færdiggøres inden prod-kørsel.
2. **GDPR PII-gate** — `detalje`-strenge i `disc` indeholder rå person_id på relaterede personer; kortlæg til DAA linje/nr-labels inden `render_report()` så rapporten er committable.
3. **Trin 3-4 pseudo-kode note** — `visning_navn` bruges som `first`-arg til `normalize_name()` som illustration; implementøren skal korrekt splitte fornavn/efternavn fra `visning_*`-felterne.

---

## Fix 2026-06-29: Guard mod undefined `crosswalk`

**Problem:** Orkestratoren havde trin 3-4 som kommentar-skelet, men trin 5-6 refererede `crosswalk` uden at blive bygget — script fejlede med uhjælpsomt `Error: object 'crosswalk' not found`.

**Løsning:** Indsæt eksplicit guard efter trin 3-4-skelet:
```r
if (!exists("crosswalk")) stop(
  "Trin 3-4 (scored -> crosswalk) er en kalibrerings-skeleton der endnu ikke er ",
  "færdiggjort. Byg `scored` fra ours+tng_people og afkommentér ",
  "`crosswalk <- assign_tiers(scored, cfg)` før trin 5-6 kan køre. ",
  "Se docs/tng-qa-koersel.md (kalibrering mod facit-sæt)."
)
```

**Commit:** `5bfeea9` — fix(tng-qa): orkestrator stopper med actionable besked når trin 3-4-glue mangler

**Verificering:**
- Parse: `Rscript -e 'invisible(parse("R/tng-qa/run-pipeline.R")); cat("parse OK\n")'` → **parse OK**
- Test: `Rscript run-tests.R` → **PASS 62** (ingen regression)

---

## Docs-korrektion 2026-06-29: afgørelse-persistens-påstand + pre-prod follow-ups

**Commit:** `23dd760` — docs(tng-qa): ret review-kø-persistens-påstand + bindende pre-prod follow-ups. Korrekte og dokumenterer 4 bindende pre-prod opgaver.
