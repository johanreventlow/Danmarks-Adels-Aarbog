# Design: TNG-kvalitetssikring via crosswalk

> Status: godkendt-til-plan · 2026-06-29 · branch `feat/tng-qa-crosswalk`
> Revideret efter Codex-review 2026-06-29 (se §"Codex-review-fund indarbejdet").

## Formål

Brug `jr_tng_reventlow.sql` (TNG-genealogi-dump, ~25.745 personer) som
**sammenlignings-reference** til at kvalitetssikre relationerne i vores egen
Supabase-base (925 personer, loadet fra DAA-PDF). Konkret afsløre kandidat-fejl i
**ægteskaber**, **forældre-barn-relationer**, **datoer** og **køn**.

**TNG er IKKE et facit.** Dumpets kilder er blandede (web-sites, tredjeparts-GEDCOM,
trykte værker — `docs/tng-reventlow-analyse.md:118`). Uenigheder klassificeres som
**uafklarede** til manuel afgørelse, ikke som "vores fejl". Reference, ikke dom.

**Eksplicit ikke-mål (denne iteration):** oprette/redigere personer/relationer i vores
base. Pipelinen er **read-only** mod Supabase. Output: rapport + genbrugbar crosswalk.
Auto-skrivning (fx til `suggestion`) er bevidst udskudt.

## Baggrund / nuværende tilstand

- **Vores base** (Supabase Postgres): `person` (id, koen, visning_*, **levende/privat**),
  `person_external_id` (DAA linje/nr per source), `family` (type ∈ vielse/partnerskab/
  ugift union) + `family_member` (rolle ∈ partner/barn/adopteret_barn/plejebarn/
  stedbarn, ordinal, konfidens), evidenslag (`assertion`, `conclusion.valgt_assertion_id`).
- **TNG-dump** (MySQL, git-ignoreret, levende-persondata): `tng_people` (personID `I<n>`,
  firstname/lastname, `birthdatetr`/`deathdatetr`, `sex`, `famc`, **`living`/`private`**),
  `tng_families` (husband/wife, marrdatetr), `tng_children` (familyID/personID +
  `frel`/`mrel` = forhold til hhv. far/mor). Fuld beskrivelse i
  `docs/tng-reventlow-analyse.md`.
- **Ingen direkte join-nøgle** → matching er fuzzy record-linkage.

## Centrale beslutninger

1. **Matchings-tilgang A — attribut-baseret scored record-linkage.** Match KUN på
   person-attributter (navn + datoer + køn), aldrig på relationer.
   **Ikke-cirkularitet:** relationer er det vi QA'er; byggede matching på dem, ville en
   forkert relation blokere matchen og skjule fejlen. Struktur-enighed må højst være et
   *transparent flag* i review-køen, aldrig match-nøgle.
2. **Implicit "Reventlow" er en SVAG, proveniens-afhængig hypotese — ikke automatisk.**
   Tomt efternavn kan betyde (a) Reventlow (TNG-konvention), (b) en **indgiftet ægtefælle**
   (som typisk IKKE er Reventlow), (c) NN/ukendt, (d) parse-fejl, (e) privacy-suppression.
   Implicit Reventlow tilføjer kun et svagt match-signal og kun hvor proveniensen støtter
   det (fx personen er i en Reventlow-gren som barn, ikke som indgiftet partner). Aldrig
   nok til `auto` alene.
3. **Crosswalk er injektiv (global 1:1).** To af vores personer må aldrig pege på samme
   TNG-personID. Tildeling løses globalt (ikke grådigt per-person), så tvetydige
   dobbelt-claims fanges → `review`, ikke silent.
4. **`auto`-tier kræver attribut-entydighed.** Et par auto-accepteres kun hvis
   attribut-kombinationen (normaliseret navn + dato-interval + køn) er ~entydig i TNG —
   beregn kandidat-tæthed først. Mange "Conrad Reventlow" m. overlappende årtier → tvinges
   til `review` uanset score.
5. **Kant-sammenligning kun når BEGGE endepunkter er matchet 1:1.** Asymmetri (925 vs.
   25.745): en matchet persons TNG-ægtefælle/forælder/barn kan være uden for vores scope.
   Sammenlign en relation kun hvis begge dens personer har accepteret match; ellers
   rapportér `uden-for-scope/ukendt` — aldrig "mangler hos os".
6. **Tre-tier matching:** `auto` / `review` / `none`. Kun review-køen kræver manuelt arbejde.
7. **Crosswalk = lokal git-ignored fil** (mapper også til levende → GDPR-følsom; ikke i
   Supabase, ikke i git).
8. **TNG → lokal DuckDB** (dumpet er bare INSERTs → ingen MySQL-server).
9. **Sprog: R** (DBI/RPostgres/duckdb).
10. **Read-only, least-privilege DB-adgang.** Pipelinen bruger en dedikeret SELECT-only
    rolle/forbindelse (ikke den fulde load-bruger fra `supabase_load.R`), read-only
    transaktion, og validerer ved opstart at den ikke kan skrive. RLS er kun slået til på
    profiles/suggestion (`schema.sql:140`), så person-data er ubeskyttet på DB-niveau →
    least-privilege-rollen er værnet.

## Arkitektur — pipeline-trin

Hvert trin er en isoleret, gen-kørbar R-funktion. Pipelinen er **idempotent**.

### Trin 1 — Extract TNG-subset → DuckDB
Parser INSERT-rækker for `tng_people`, `tng_families`, `tng_children`,
`tng_associations` → `data/tng.duckdb` (git-ignored). Bevarer **`living`/`private`**
(nødvendigt for redaktion i trin 6). Logger checksum (SHA-256) af dump-filen.

### Trin 2 — Pull vores data (read-only, least-privilege)
SELECT fra `person` (inkl. **levende/privat**), `person_external_id`, `family`,
`family_member`, samt `conclusion`+`assertion`+`fact` for fødsel/død (via
`conclusion.valgt_assertion_id` — den blåstemplede værdi, ikke vilkårlig assertion).
Fail fast ved manglende creds/forbindelse.

### Trin 3 — Normalisér begge baser
- **Navn:** parse til (fornavne, partikler, efternavn); håndtér patronymer, navne-
  partikler (von/til/af), pige-/giftenavn, aliaser, "NN/ukendt"; implicit Reventlow
  per beslutning #2; strip titler/prædikater (greve, lensgreve, til …); **diakritik
  BEVARES** (æøå/accenter — aldrig ASCII-folding); lowercase kun til sammenligning;
  rå form bevares til rapport.
- **Dato:** vores datoer fra `conclusion`-valgte assertions (date_min/max + qualifier,
  bevar usikkerhed); fallback `visning_*`-tekst-parse. TNG `*tr`-date → interval.
  Sammenligning på interval-overlap, ikke punkt.
- **Køn:** `koen` (mand/kvinde/ukendt) vs. TNG `sex` (M/F) → fælles vokabular.

### Trin 4 — Blok + score → tiers
- **Blokering:** kandidat-par hvor fødselsår-interval overlapper (±N år) ELLER fornavn-
  initial matcher (undgår 925×25.745).
- **Score:** vægtet Jaro-Winkler(navn) + dato-overlap + køn-enighed.
- **Tier-tildeling:** `auto` kun ved høj score **OG** attribut-entydighed (#4) **OG**
  injektiv tildeling (#3); flertydige/dobbelt-claimede → `review`; rest → `none`.
- **Output:** `data/tng-crosswalk.csv` + `data/tng-review-queue.csv`.
- **Kvalitets-eval:** et lille **håndlabelt facit-sæt** (kendte sande/falske par)
  bruges til at måle precision/recall og kalibrere tærskler/vægte — ikke kun ad-hoc tests.

### Trin 5 — Manuel review (idempotent)
Du udfylder `tng-review-queue.csv` (`afgoerelse` ∈ bekræft/afvis/ny-id). Gen-kørsel
fletter bekræftede permanent ind; afviste huskes (dukker ikke op igen). Crosswalk-rækker
bærer **proveniens**: dump-checksum, config-version, reviewer, tidsstempel. Skifter dump-
checksum eller normaliserings-config → berørte auto-afgørelser invalideres til ny review.

### Trin 6 — Sammenlign relationer → diskrepans-rapport
For hvert par hvor begge endepunkter er matchet 1:1 (#5):
- **Ægteskaber:** partner-sæt + **marrdate** + `family.type` (vielse/partnerskab/union)
  vs. `tng_families`. Kategorier: mangler/ekstra/uenig (kun når begge i scope).
- **Forældre-barn:** **per-forælder** (TNG `frel` vs. far, `mrel` vs. mor) mod vores
  family→barn-kanter; biologisk vs. adopteret/plejebarn ↔ vores rolle-subtyper.
- **Datoer:** fødsel/død hvor begge har værdi; uenighed = ikke-overlappende intervaller.
- **Køn:** koen vs. sex.

Hver diskrepans: årsag kan være (a) vores fejl, (b) TNG-reference-fejl, (c) fejl-match.
Rapporten **dømmer ikke** — lister til din afgørelse, med linje/nr-labels.

## Outputs

| Fil | Indhold | Skæbne |
|---|---|---|
| `data/tng.duckdb` | TNG-subset + living/private | git-ignored |
| `data/tng-crosswalk.csv` | person_id ↔ personID ↔ tier ↔ score ↔ proveniens | git-ignored (levende-data) |
| `data/tng-review-queue.csv` | tvivlsmatches + afgørelses-kolonne | git-ignored |
| `docs/reviews/tng-qa-rapport-YYYY-MM-DD.md` | diskrepanser per dimension | committes — **kun efter PII-gate** |

## GDPR / PII (kritisk)

- Committed rapport må **ikke** indeholde levende-PII. `person_id` + DAA linje/nr er
  re-identificerbart → ikke nok at undlade navne.
- **Regel:** kanter/personer hvor enten vores `levende`/`privat` ELLER TNG `living`/
  `private` er sat, udelades fra den committede rapport (eller aggregeres uden
  identifikatorer). Derfor bæres begge baser's flag gennem pipelinen (#trin 1+2).
- **Pre-commit PII-gate:** automatisk test der afviser commit hvis rapporten indeholder
  identifikatorer for en levende/privat person. Crosswalk/review-kø/duckdb er git-ignored
  og forlader aldrig disken.

## Fejlhåndtering

- Manglende creds/forbindelse → fail fast.
- Person uden parsbar dato → matches på navn+køn alene, lav konfidens (→ review/none).
- Dangling TNG famc/child-personID → springes over, logges.
- Tomt efternavn → svag hypotese (#2), ikke automatisk Reventlow.

## Test (risiko-baseret)

- **Navne-normalisering:** golden cases — implicit Reventlow (inkl. indgiftet-undtagelse),
  titel-strip, diakritik-bevarelse, patronym/partikel/pigenavn/alias/NN, fornavn-varianter.
- **Dato-parsing:** golden cases fra `visning_*` + conclusion-assertions + TNG.
- **Match:** facit-sæt m. precision/recall + tier-forventninger (sand/falsk/tvetydig).
- **Injektivitet:** test at dobbelt-claim → review, ikke silent.
- **Scope-guard:** test at uden-for-scope-endepunkt → `ukendt`, ikke "mangler".
- **Relations-sammenligning:** syntetiske mini-baser m. kendte diskrepanser.
- **PII-gate:** test at levende-person-identifikator i rapport → commit afvist.
- Manuel ende-til-ende mod lille udsnit før fuld kørsel.

## Risici / åbne punkter

- **Tærskler** (blokerings-vindue N, score-vægte, cutoffs) kalibreres mod facit-sættet.
- **Identitets-tvetydighed:** mange "Conrad Reventlow" → stor review-kø forventet;
  attribut-entydigheds-gaten (#4) styrer det.
- **TNG-reference-kvalitet:** blandede kilder → uenigheder er uafklarede, ikke domme.

## Codex-review-fund indarbejdet (2026-06-29)

Critical: PII-gate + bær begge baser's levende/privat-flag (§GDPR, trin 1+2).
High: least-privilege read-only rolle (#10); scope-guard på kanter (#5); injektiv 1:1
crosswalk (#3); attribut-entydighed før auto (#4); implicit-Reventlow som svag hypotese
(#2); TNG som reference ikke facit (§Formål); per-forælder frel/mrel-sammenligning (trin 6).
Medium: dato fra conclusion.valgt_assertion_id + bevar qualifier (trin 3); marriage-QA
inkl. dato+family.type (trin 6); facit-sæt m. precision/recall (trin 4). Low: crosswalk-
proveniens + stale-invalidation (trin 5).
