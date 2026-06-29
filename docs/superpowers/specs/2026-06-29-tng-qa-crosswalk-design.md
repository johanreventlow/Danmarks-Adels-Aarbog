# Design: TNG-kvalitetssikring via crosswalk

> Status: godkendt-til-plan · 2026-06-29 · branch `feat/tng-qa-crosswalk`

## Formål

Brug `jr_tng_reventlow.sql` (TNG-genealogi-dump, ~25.745 personer, bedre
relations-kvalitet) som **facit** til at kvalitetssikre relationerne i vores
egen Supabase-base (925 personer, loadet fra DAA-PDF). Konkret afsløre fejl-loadede
**ægteskaber**, **forældre-barn-relationer**, **datoer** og **køn**.

**Eksplicit ikke-mål (denne iteration):** oprette eller redigere personer/relationer
i vores base. Pipelinen er **read-only** mod Supabase. Output er en rapport til
manuel afgørelse + en genbrugbar crosswalk. Auto-skrivning (fx til `suggestion`)
er bevidst udskudt.

## Baggrund / nuværende tilstand

- **Vores base** (Supabase Postgres): `person` (id, koen, visning_navn/foedt/doed,
  privat/levende), `person_external_id` (DAA linje/nr per source), `family` +
  `family_member` (rolle ∈ partner/barn/adopteret_barn/plejebarn/stedbarn, ordinal,
  konfidens), evidenslag (`assertion` m. date_min/date_max for fødsel/død-fakta).
- **TNG-dump** (MySQL, git-ignoreret, indeholder levende-persondata): `tng_people`
  (personID `I<n>`, firstname/lastname, struktureret `birthdatetr`/`deathdatetr`,
  `sex`, `famc`), `tng_families` (husband/wife/marrdatetr), `tng_children`
  (familyID/personID + `frel`/`mrel` = forhold til far/mor). Analysen i
  `docs/tng-reventlow-analyse.md` (read-only, 2026-06-15) beskriver dumpet fuldt.
- **Ingen direkte join-nøgle** mellem de to baser → matching er fuzzy.

## Centrale beslutninger

1. **Matchings-tilgang A — attribut-baseret scored record-linkage.** Match KUN på
   person-attributter (navn + datoer + køn), aldrig på relationer.
   **Begrundelse (ikke-cirkularitet):** TNG's relationer er facit. Hvis matching
   byggede på relationer, ville en forkert relation hos os blokere matchen og dermed
   skjule netop den fejl vi leder efter. Struktur-enighed må højst optræde som et
   *transparent flag* i review-køen, aldrig som match-nøgle.
2. **Implicit "Reventlow"-efternavn.** TNG udelader ofte efternavnet (hele træet
   ER Reventlow). Navne-normalisering indsætter implicit "Reventlow" når efternavn
   mangler/er tomt — i BEGGE baser — før sammenligning.
3. **Tre-tier matching:** `auto` (entydig, navn+dato enige), `review` (tvivl eller
   flertydig), `none`. Kun review-køen kræver manuel gennemgang.
4. **Crosswalk er en lokal git-ignored fil.** Den mapper også til levende personer →
   GDPR-følsom. Den lever IKKE i Supabase og committes IKKE til git.
5. **TNG indlæses i lokal DuckDB** (dumpet er bare INSERTs → ingen MySQL-server).
6. **Sprog: R** (projekt-standard ETL: DBI/RPostgres/duckdb).

## Arkitektur — pipeline-trin

Hvert trin er en isoleret R-funktion/script med veldefineret input/output, så det
kan testes og gen-køres uafhængigt. Pipelinen er **idempotent**.

### Trin 1 — Extract TNG-subset → DuckDB
- **Input:** `jr_tng_reventlow.sql`
- **Gør:** parser INSERT-rækker for KUN `tng_people`, `tng_families`,
  `tng_children`, `tng_associations` → lokal DuckDB-fil (`data/tng.duckdb`,
  git-ignored). MySQL-specifik syntaks (backticks, ENGINE-clauses) ignoreres;
  kun de fire tabellers kolonner + rækker udtrækkes.
- **Output:** DuckDB med fire tabeller.
- **Note:** kun de kolonner vi bruger behøver bevares (personID, navne, datoer,
  sex, famc, husband/wife, familyID, frel/mrel).

### Trin 2 — Pull vores data fra Supabase
- **Input:** Supabase-forbindelse (Session pooler, sslmode=require; creds i
  `~/.Renviron`).
- **Gør:** SELECT (read-only) fra `person`, `person_external_id`, `family`,
  `family_member`, og `assertion`+`fact` for fødsel/død-datoer.
- **Output:** R-data-frames.

### Trin 3 — Normalisér begge baser
- **Navn:** parse til (fornavne, efternavn); indsæt implicit "Reventlow" hvor
  efternavn mangler; strip titler/prædikater (greve, lensgreve, til …);
  diakritik BEVARES (æøå, accenter — aldrig ASCII-folding af danske tegn);
  lowercase til sammenligning; behold rå form til rapport.
- **Dato:** vores `visning_foedt`/`visning_doed` (tekst) parses til (år_min, år_max);
  fallback til `assertion.date_min/date_max` hvis tekst ikke parser. TNG
  `birthdatetr`/`deathdatetr` (date) → år. Fuzzy: interval, ikke punkt.
- **Køn:** vores `koen` (mand/kvinde/ukendt) vs. TNG `sex` (M/F) → fælles vokabular.

### Trin 4 — Blok + score → tiers
- **Blokering:** kandidat-par hvor fødselsår overlapper (±N års vindue, N angives
  i plan) ELLER fornavn-initial matcher — for at undgå 925×25.745 fuld-kryds.
- **Score:** vægtet sum af Jaro-Winkler(navn) + dato-enighed (fødsel+død) +
  køn-enighed. Tærskler (angives i plan) → `auto`/`review`/`none`.
  Entydighed: hvis flere TNG-kandidater scorer højt for samme vores-person →
  tving `review` (aldrig auto ved tvetydighed).
- **Output:** `data/tng-crosswalk.csv` (vores person_id, TNG personID, tier, score,
  match-begrundelse) + `data/tng-review-queue.csv` (kun `review`-tier).

### Trin 5 — Manuel review (idempotent gen-kørsel)
- Du udfylder `tng-review-queue.csv` (kolonne `afgoerelse` ∈ bekræft/afvis/ny-id).
- Gen-kørsel læser bekræftede afgørelser → flettes permanent ind i crosswalk;
  afviste markeres så de ikke dukker op igen. Allerede-afgjorte par genstilles ikke.

### Trin 6 — Sammenlign relationer → diskrepans-rapport
For hvert matchet par (auto + bekræftet review):
- **Ægteskaber:** vores partner-sæt (via `family_member` rolle=partner) mappet gennem
  crosswalk vs. TNG `tng_families` husband/wife. Rapportér: mangler-hos-os,
  ekstra-hos-os, uenig-partner.
- **Forældre-barn:** vores barn-links vs. TNG `tng_children`, inkl. `frel`/`mrel`
  (biologisk vs. adopteret/plejebarn ↔ vores rolle-subtyper). Rapportér samme tre
  kategorier + relationstype-uenighed.
- **Datoer:** fødsel/død hvor BEGGE har værdi; uenighed > tolerance (interval-overlap).
- **Køn:** koen vs. sex-uenighed.

Hver diskrepans annoteres med, at årsagen kan være (a) vores fejl, (b) TNG-fejl,
(c) fejl-match — rapporten **dømmer ikke**, men lister til din afgørelse, med
linje/nr-labels for hurtig opslag i vores base.

## Outputs

| Fil | Indhold | Skæbne |
|---|---|---|
| `data/tng.duckdb` | TNG-subset (fire tabeller) | git-ignored, lokal cache |
| `data/tng-crosswalk.csv` | person_id ↔ TNG personID ↔ tier ↔ score | git-ignored (levende-data), genbrugbar |
| `data/tng-review-queue.csv` | tvivlsmatches til manuel afgørelse | git-ignored |
| `docs/reviews/tng-qa-rapport-YYYY-MM-DD.md` | diskrepanser per dimension | committes (skal være fri for levende-PII — kun afdøde/anonymiserede labels; se risici) |

## Fejlhåndtering

- Manglende Supabase-creds / forbindelse → fail fast med klar besked.
- Person uden parsbar dato → indgår i matching på navn+køn alene, markeres
  lav-konfidens (typisk `review`/`none`).
- TNG-personID der ikke findes (dangling famc/child) → springes over, logges.
- Tom/manglende efternavn begge steder → implicit Reventlow (beslutning #2).

## Test (risiko-baseret)

- **Navne-normalisering:** unit-tests m. golden cases — implicit Reventlow,
  titel-strip, diakritik-bevarelse, fornavn-varianter (Conrad/Conradt).
- **Dato-parsing:** golden cases fra vores `visning_*`-formater + TNG-datoer.
- **Match-scoring:** håndlavede par med kendt facit (samme person / forskellig
  person / tvetydig) → forventet tier.
- **Relations-sammenligning:** syntetiske mini-baser med kendte diskrepanser →
  forventet rapport-output.
- Manuel ende-til-ende-kørsel mod et lille udsnit før fuld kørsel.

## Risici / åbne punkter

- **GDPR i rapporten:** diskrepans-rapporten committes til git → den må IKKE
  indeholde levende-PII. Mitigering: rapporten bruger person_id + DAA linje/nr som
  labels (ikke navne på levende), eller filtrerer levende fra rapport-teksten.
  Afklares i plan-fasen (præcis label-strategi).
- **Match-tærskler** (blokerings-vindue N, score-vægte, tier-cutoffs) fastlægges
  empirisk i plan/implementering mod et stikprøve-udsnit.
- **DAA-grene i TNG:** TNG dækker langt mere end Reventlow-DAA-udsnittet; matching
  går fra vores 925 → TNG, så TNG-overskud er uskadeligt (ingen scope-filter nødvendig).
- **Identitets-tvetydighed:** gentagne navne+årtier (mange "Conrad Reventlow") →
  forventet stor review-kø; struktur-flag (ikke-match-nøgle) kan hjælpe manuelt.
