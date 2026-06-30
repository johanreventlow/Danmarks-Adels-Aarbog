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

## Trin 3-4: blokering + score (BOOTSTRAP-kalibreret 2026-06-30)

Trin 3-4-glue'en (`our_match_frame`/`tng_match_frame`/`build_scored`) er
implementeret; pipelinen kører ende-til-ende. `auto`-kriteriet er
**bootstrap-kalibreret** (uden håndlabelt facit-sæt) — se `R/tng-qa/calibrate.R`:

- **auto** = score ≥ `auto_cutoff` (0.90) **OG** bedste kandidat er ≥
  `ambiguity_margin` (0.05) foran nr. 2. (Det uniforme "Reventlow" gjorde den
  oprindelige `unique_block`-gate ubrugelig — alle har mange ens-navngivne
  kandidater — så `auto` var altid 0. Margin-gaten erstatter den.)
- **Dato-evidens (vigtig):** `birth_overlap`/`death_overlap` som SCORING-signal
  tæller kun som TRUE når BEGGE sider har en dato OG de overlapper
  (`.overlap_evidence`). Ukendt dato = manglende evidens, ikke enighed. (Ellers
  fik dato-løse par 0.3 "gratis" vægt og kunne auto-promoteres på navn alene — fx
  `franziska reventlow → franciska christensen`.) Konsekvens: **auto kræver nu reel
  fødselsårs-korroboration** (et rent navne-match maxer på 0.7 < auto_cutoff).
  Blokerings-vinduet beholder dog fortsat dato-løse kandidater.
- **Kalibrering:** de ENTYDIGE EKSAKTE matches (navn ≥ 0.98 + eksakt fødsel + død +
  køn) bruges som bootstrap-"truth". Margin 0.05 → **100% anker-recall**. Resultat
  på fuld base: **auto≈347, review≈658, none≈8604** (af 963 personer m. kandidat;
  par-tal). Review faldt fra ~6580 til ~658 efter dato-evidens-fixet — nu reelt
  gennemgåeligt manuelt.

**ÆRLIGE begrænsninger (ikke endeligt kalibreret):**
- Anker-recall er IKKE en uafhængig præcisions-måling (ankrene er korrekte pr.
  konstruktion). Den reelle kontrol er `calibrate.R`'s liste over **non-anker-auto**.
  Øjen-kontrol 2026-06-30: alle auto har dato-evidens; non-anker-auto er
  stavevarianter (detlev/detlef, sophie/sophia, christina/christine) m. matchende
  år, samt eksakt-navn + fødselsår for nulevende uden dødsår.
- **Dato-fattige personer** (de ~300 uden fødselsår) får nu sjældent forslag —
  et navne-only-match er for svagt til auto/review. Ærlig konsekvens af uniform
  efternavn; kræver datoer for at matche pålideligt.
- `review_cutoff` (0.70) er ikke kalibreret, og et **endeligt håndlabelt facit-sæt**
  (inkl. tvetydige/negative cases) er stadig det rigtige næste skridt; kald
  `eval_precision_recall(crosswalk, truth)`.

Genkør kalibrering: `Rscript R/tng-qa/calibrate.R` (sweep over auto_cutoff × margin
+ non-anker-auto spot-check-liste).

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

## GDPR PII-gate (LØST — input-gating)

**Primær kontrol = INPUT-gating** (`gate_inputs()` i `07-report.R`): ALLE
sammenlignings-input filtreres til afdøde-ikke-private på BEGGE sider FØR
sammenligning. Ingen levende/privat person kan så komme ind i `disc` — heller
ikke som relateret/2.-endepunkt. Det reducerer garantien til ÉN kontrollerbar
invariant ("begge input-sæt indeholder kun afdøde-ikke-private") frem for
"hver refereret id på hver række blev tjekket".

- **Begge privacy-kilder:** vores `safe_our_ids()` (`levende=false AND privat
  ikke true`) + TNG `safe_tng_ids()` (`living="0" AND private="0"`). **Fail-closed:**
  ukendt state ⇒ ikke sikker.
- **Begge sider filtreres:** `our_pairs/our_pc/our_attr` + `tng_families/tng_children`
  (+ crosswalk). Filtreres KUN vores side, ville en afdød P gift med levende L
  stadig give en `mangler_hos_os`-række der navngiver L — derfor gates TNG også.
- **`assert_no_living_pii()` er nu KUN en backstop**, ikke den primære garanti
  (den svækkes når id'er mappes til labels). Primær person mappes til DAA
  linje/nr-label; relaterede afdøde-id'er i `detalje` er ikke GDPR-PII.

Rapporten detaljerer kun de 4 handlingsorienterede kategorier; `enig`/
`uden_for_scope` opsummeres som tal. Verificeret 2026-06-30: 0 af 70 levende
person-id i den genererede rapport.

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
| Trin 3-4: normalisér + match | **Aktiv** — auto bootstrap-kalibreret (margin); review bred |
| Trin 5: review-merge + write | Aktiv — skriver udfyldelig review-kø; tåler gen-kørsel |
| Trin 6: sammenlign + rapport | **Aktiv** — input-gating PII-gate; skriver `docs/reviews/tng-qa-rapport-<dato>.md` |

Fuld e2e-kørsel er en manuel procedure; ingen automatiseret CI-gate kobles
på prod-data.

---

## Pre-prod-run follow-ups (fra final whole-branch review 2026-06-29)

Bindende opgaver før prod-kørsler (opdateret efter dual-review cycle 07, Codex 2026-06-29):

- [x] **Trin 3-4-glue + kalibrering (2026-06-30):** glue implementeret; auto bootstrap-kalibreret (margin-baseret, dato-evidens). Håndlabelt facit-sæt + `review_cutoff`-kalibrering udestår stadig.
- [x] **PII-gate (H1) LØST (2026-06-30):** input-gating på begge sider (afdøde-ikke-private, fail-closed) — se §"GDPR PII-gate" ovenfor. Verificeret 0 levende-id i rapporten.
- [ ] Ret review-kø-persistens (H2): bevar bekræft/afvis/ny-id-afgørelser på tværs af fulde gen-kørsler (crosswalk genbygges nu fra bunden hver gang → afgørelser tabes; afviste "huskes" ikke). (Trin 5-crash på frisk kø er fixet; persistens udestår.)
- [ ] **Validér injektivitet ved accept (M2):** efter `merge_review_decisions` skal duplikat `tng_id` (eller `person_id`) afvises — ellers vælger `match()` silently FØRSTE og fejl-attribuerer relationer i `06-compare.R`. Verificeret: `match("I9", c("I9","I9"))` → 1.
- [x] **`tng_children`-reshape (2026-06-30):** implementeret som `reshape_tng_children()` (far=husband, mor=wife) + brugt i Trin 6.
- [ ] **mysqldump-escapes (H0-rest):** `fix_mysql_literals` oversætter ikke `\n \r \t \0 \Z` (efterlades literalt). Backtick-i-værdi-korruption er FIXET (cycle07, quote-aware). Escape-oversættelse udestår — lav impact på de konsumerede kolonner (navne/datoer/id), men implementér hvis fritekst-felter (fx birthplace) senere konsumeres.
