# geo-enrich — koordinat-berigelse af `place.lat/lon`

Fylder de tomme `place.lat`/`place.lon` i Supabase, så kort-funktionen kan tegne markører.
Rygraden er TNG's `tng_places` (~6.788 punkter med lat/lon); Nominatim-geokodning er et
valgfrit fallback for steder TNG ikke dækker. Deterministisk + tiered + review-CSV — samme
mønster som `R/tng-qa/`.

> **Status: UDKAST.** Kan ikke køres i denne sandbox (R ej installeret, ingen TNG-dump / Supabase-
> credentials). Kør og verificér lokalt. De rene match-hjælpere er dækket af
> `tests/testthat/test-geo-enrich.R`.

## Forudsætninger

- `jr_tng_reventlow.sql` i repo-rod (git-ignoreret MySQL-dump — samme fil som `R/tng-qa` bruger).
- `~/.Renviron`: `SUPABASE_HOST`, `SUPABASE_USER`, `SUPABASE_PASSWORD` (+ evt. `SUPABASE_DB`,
  `SUPABASE_PORT`). Byg-crosswalken er read-only; **`--apply` kræver en skrive-rolle.**
- Pakker: `DBI`, `duckdb`, `RPostgres`, `stringi`, `stringdist` (geokodning også: `httr2`, `jsonlite`).

## Kør

```sh
# 1) Byg crosswalk (dry-run, ingen skrivning). Skriver data/geo-crosswalk.csv.
Rscript R/geo-enrich/run-geo-enrich.R

# 2) Gennemgå data/geo-crosswalk.csv:
#    - tier=auto  -> anvend=TRUE  (eksakt, entydigt navn+punkt)
#    - tier=review-> anvend=""    (fuzzy ELLER samme navn/flere punkter — sæt TRUE/FALSE selv)
#    - tier=none  -> anvend=FALSE (intet TNG-match; kandidat til geokodning)

# 3) (valgfrit) Geokod tier=none via Nominatim. Skriver review-kandidater.
Rscript R/geo-enrich/03-geocode.R
#    Flet godkendte rækker fra data/geo-geocode-candidates.csv ind i geo-crosswalk.csv.

# 4) Skriv koordinaterne (kun anvend=TRUE + gyldige coords).
Rscript R/geo-enrich/run-geo-enrich.R --apply

# 5) Test de rene hjælpere.
Rscript run-tests.R
```

## Sikkerhed / idempotens

- `UPDATE place SET lat,lon WHERE id=? AND (lat IS NULL OR lon IS NULL)` — skriver kun tomme
  felter, overskriver **aldrig** et manuelt kurateret punkt, og gentagne kørsler er sikre.
- Hele skrivningen kører i én transaktion med `dbRollback` ved fejl (som `post_load_fixup.R`).
- Matcher kun place-rækker der mangler koordinater; berigede rører den ikke.
- `data/`-outputs (crosswalk, DuckDB, geokode-cache) er git-ignorerede.

## Filer

| Fil | Rolle |
|-----|-------|
| `geo_helpers.R` | Rene, testbare match-/normaliserings-hjælpere (ingen DB/net). |
| `run-geo-enrich.R` | Orkestrator: tng_places→DuckDB, match, crosswalk, `--apply`. |
| `03-geocode.R` | Valgfrit Nominatim-fallback for tier=none (review-kandidater). |
| `../../tests/testthat/test-geo-enrich.R` | Enhedstests for hjælperne. |

## Kendte usikkerheder (verificér ved kørsel)

- **TNG-kolonnenavne:** `tng_places` kan hedde `place`/`latitude`/`longitude` (default) eller
  variant; `pick_col()` prøver flere og fejler klart. Inspicér med
  `tng_create_columns("jr_tng_reventlow.sql", "tng_places")` hvis den fejler.
- **Match-tærskler:** `default_geo_cfg()$fuzzy_review_sim` (0.92) er ikke kalibreret mod facit —
  juster efter at have set review-tier'ens støj (som tng-qa's `calibrate.R`-tilgang).
- **DAWA:** højere DK-præcision end Nominatim, men ikke wiret (kræver egen endpoint-tuning).
