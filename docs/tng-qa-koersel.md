# TNG-QA pipeline — kørselsanvisning

Pipelinen sammenligner vores Supabase-base med en lokal TNG-dump og
producerer en crosswalk-CSV, en review-kø og en Markdown-rapport. Alle
trin er idempotente: kør igen efter at have udfyldt review-kø-afgørelser.

---

## Forudsætninger

### R-pakker

```r
install.packages(c("DBI", "duckdb", "RPostgres", "stringi", "stringdist",
                   "testthat"))
```

### TNG-dump

Placér `jr_tng_reventlow.sql` i repo-roden (MySQL-format; git-ignoreret —
indeholder potentielt levende-persondata, se GDPR-afsnittet nedenfor).

### Miljøvariabler

Sæt i `~/.Renviron` (genstart R efter ændringer):

```
SUPABASE_HOST=<din-host>       # Session Pooler (IPv4), EU-region
SUPABASE_USER=<brugernavn>     # Se anbefaling om SELECT-only rolle nedenfor
SUPABASE_PASSWORD=<kodeord>

# Valgfri (defaults: postgres / 5432)
SUPABASE_DB=postgres
SUPABASE_PORT=5432
```

**Anbefalet:** brug en dedikeret `SELECT`-only rolle (`GRANT SELECT ON ALL
TABLES IN SCHEMA public TO qa_reader`). Pipelinen sætter
`default_transaction_read_only = on` og verificerer det via
`current_setting('transaction_read_only')` (GUC) ved opstart — en
skriveaktiv forbindelse afbryder med fejl.

---

## Kør pipelinen

```bash
Rscript R/tng-qa/run-pipeline.R
```

Kørsel fra repo-roden (vigtigt — stier er relative til roden).

---

## Trin 3-4: blokering + score (kalibrering påkrævet)

Orkestratoren (`R/tng-qa/run-pipeline.R`) har trin 3-4 som et
kommentar-skelet. Blok-konstruktionen og score-beregningerne er
fuldt testede byggeklodser (T4-T7, 59 tests), men **tærskler og
blok-parametre kalibreres empirisk** inden prod-kørsel:

1. **Håndlabel et facit-sæt** (~30-50 personer med kendte TNG-IDs).
2. Byg `scored`-tabellen (se kommentar-skeletons i `run-pipeline.R`
   trin 3-4) og kald `eval_precision_recall(crosswalk, truth)`.
3. Justér `cfg$auto_cutoff` / `cfg$review_cutoff` / `year_window` i
   `default_cfg()` (se `R/tng-qa/04-match.R`) til ønsket præcision/recall.
4. Fjern kommentar-hash fra `crosswalk <- assign_tiers(scored, cfg)` og
   løb pipelinen igen mod facit-sættet til tilfredsstillende metrics.

### `scored`-tabel-struktur

```
person_id    integer   — vores person.id
tng_id       character — TNG personID
name_sim     numeric   — Jaro-Winkler-lighed på normalize_name()-nøglen
birth_overlap logical  — intervals_overlap(vores fødsel, TNG fødsel)
death_overlap logical  — intervals_overlap(vores død, TNG død)
sex_eq        logical  — normalize_sex(vores) == normalize_sex(TNG)
unique_block  logical  — TNG-kandidaten er ENESTE i blokken
```

`assign_tiers()` udleder `tier` ∈ `{auto, review, none}` og sikrer injektivitet
(1:1 mapping, ingen delt TNG-ID).

---

## Review-kø-workflow

Efter første kørsel indeholder `data/tng-review-queue.csv` rækker med
`tier == "review"`. Udfyld kolonnen `afgoerelse`:

| Værdi    | Betydning                              |
|----------|----------------------------------------|
| `bekræft` | Acceptér match som-er                 |
| `afvis`   | Afvis match (markeres `afvist`)       |
| `ny-id`   | Brug `ny_tng_id`-kolonnen i stedet   |

Gem filen og kør pipelinen igen. **Vigtig caveat:** afgørelse-persistens
på tværs af fulde genakørsler er IKKE endnu implementeret. `run-pipeline.R`
genbygger `crosswalk` fra bunden ved hver kørsel og skriver kun
`person_id,tng_id,score,tier` til crosswalk-CSV — bekræftede/afviste
afgørelser fra review-kø-CSV tabes ved næste genakørsel. `merge_review_decisions()`
muterer kun `tier` in-memory inden trin 5 (der ændringer ej persisteres til
CSV mellem kørsler). Løsning: se "Pre-prod-run follow-ups" nedenfor.

---

## Output-filer

Alle tre filer er **git-ignorerede** (GDPR — indeholder eller afledede af
levende-persondata jf. invariant §8):

| Fil                        | Indhold                                                |
|----------------------------|--------------------------------------------------------|
| `data/tng.duckdb`          | Lokal kopi af TNG-dump (MySQL → DuckDB)               |
| `data/tng-crosswalk.csv`   | Mapping `person_id ↔ tng_id` med `score` og `tier`   |
| `data/tng-review-queue.csv`| Subset af crosswalk med `tier == "review"`             |

Kommittable rapport-filer skrives til `docs/reviews/tng-qa-rapport-DATO.md`
(se GDPR PII-gate nedenfor).

---

## GDPR PII-gate (KENDT BEGRÆNSNING)

`render_report()` i trin 6 kalder `assert_no_living_pii()`, der scanner
rapport-teksten for rå numeriske `person_id`-værdier på levende/private
personer. Gaten **fejler lukket** — hele rapporten blokeres hvis *én*
`detalje`-streng indeholder et sådant ID.

**Konsekvens:** `compare_marriages()`, `compare_parent_child()` og
`compare_dates_sex()` skriver `person_id`-numre direkte i `detalje`-feltet
(fx `"vores: 42—99"`, `"TNG father_tng: P1234"`). Hvis `42` eller `99`
er levende, blokeres rapporten.

**Løsning inden trin 6 aktiveres:**

```r
# Kortlæg alle person_id-referencer i detalje til DAA linje/nr-labels
# (brug .label()-hjælperen eller en streng-erstatning mod ours$external_id),
# ELLER filtrer rækker med levende-relatives fra disc, FØR render_report().
```

Funktionen `filter_living()` fjerner rækker, hvor `disc$person_id` er
levende — men den dækker ikke levende ID'er der optræder i `detalje`-teksten
for afdøde. Kortlægningen er den sikre løsning.

---

## Idempotens-garanti

- **`build_tng_duckdb()`** sletter og genskaber `data/tng.duckdb` ved hver
  kørsel.
- **`merge_review_decisions()`** er idempotent: kør igen med samme
  `tng-review-queue.csv` — resultatet er uændret.
- **Crosswalk-CSV** overskrives; rapport-filer navngives med dato og
  overskrives ikke.

---

## Kørte / sprungne dele (første kørsel)

| Trin | Status |
|------|--------|
| Trin 1: TNG → DuckDB | Kørbar (kræver `jr_tng_reventlow.sql`) |
| Trin 2: Supabase pull | Kørbar (kræver env-vars + forbindelse) |
| Trin 3-4: normalisér + match | **Skelet** — kalibreres mod facit-sæt |
| Trin 5: review-merge + write | Stopper med actionabel besked hvis `crosswalk` mangler |
| Trin 6: sammenlign + rapport | **Skelet** — aktiveres efter PII-gate-løsning |

Fuld e2e-kørsel er en manuel procedure; ingen automatiseret CI-gate kobles
på prod-data.

---

## Pre-prod-run follow-ups (fra final whole-branch review 2026-06-29)

Bindende opgaver før prod-kørsler (opdateret efter dual-review cycle 07, Codex 2026-06-29):

- [ ] Færdiggør trin 3-4-glue (`scored` → `crosswalk`) og kalibrér blok-vindue/score-vægte/tier-cutoffs mod et håndlabelt facit-sæt.
- [ ] **PII-gate (recalibreret, H1):** tekst-scan er IKKE tilstrækkelig primær-kontrol — `\b<id>\b` har false-negatives (`p123`, `I123`, bogstav-tilstødende id). Modellér i stedet hver refereret vores/TNG-person STRUKTURELT, join BEGGE privacy-flag (vores `levende/privat` + TNG `living/private` — sidstnævnte bæres ind i DuckDB men læses ikke endnu), afvis ukendt privacy-state, og filtrér FØR formatering. Behold tekst-scan kun som defense-in-depth. Map relaterede `person_id` i `detalje` til DAA linje/nr-labels.
- [ ] Ret review-kø-persistens (H2): bevar bekræft/afvis/ny-id-afgørelser på tværs af fulde gen-kørsler (crosswalk genbygges nu fra bunden hver gang → afgørelser tabes; afviste "huskes" ikke).
- [ ] **Validér injektivitet ved accept (M2):** efter `merge_review_decisions` skal duplikat `tng_id` (eller `person_id`) afvises — ellers vælger `match()` silently FØRSTE og fejl-attribuerer relationer i `06-compare.R`. Verificeret: `match("I9", c("I9","I9"))` → 1.
- [ ] Implementér `tng_children`-reshape (rå `familyID/personID + frel/mrel` → `child_tng/father_tng/mother_tng` via join til `tng_families`: far=husband, mor=wife) med test før trin-6 aktiveres.
- [ ] **mysqldump-escapes (H0-rest):** `fix_mysql_literals` oversætter ikke `\n \r \t \0 \Z` (efterlades literalt). Backtick-i-værdi-korruption er FIXET (cycle07, quote-aware). Escape-oversættelse udestår — lav impact på de konsumerede kolonner (navne/datoer/id), men implementér hvis fritekst-felter (fx birthplace) senere konsumeres.
