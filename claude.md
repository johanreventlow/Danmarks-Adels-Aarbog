# Handoff — Danmarks Adelsforening / Reventlow-følgesvend
**Fra datamodel-design (ført i chat) til implementering (Claude Code)**

> Læs `datamodel-oversigt.md` for den autoritative, fulde modelbeskrivelse. Dette dokument orienterer dig hurtigt og samler beslutninger, tilstand og næste skridt. Kan ligge som `CLAUDE.md` i repo-roden, så Claude Code læser den som projektkontekst (se Claude Code-docs: https://docs.claude.com/en/docs/claude-code/overview).

---

## 1. Projektet

En **digital følgesvend til Danmarks Adels Aarbog** — et levende, multimedie- og slægtskabs­søgende *supplement* til det trykte værk, ikke en konkurrent. Gratis for foreningens medlemmer, abonnement for forskere/genealoger/historikere. Appen er broen mellem de trykte udgaver og kan samtidig fungere som indsamlingsmotor for næste udgave.

**Proof of concept** er afgrænset til **familien Reventlow** (familien kører i forvejen TNG-genealogi). Lykkes PoC'en, er målet adgang til foreningens samlede data.

Kernefunktionen er **"er vi i familie?"** — slægtskabssøgning på tværs af slægterne.

---

## 2. Besluttet arkitektur (rør ikke uden god grund)

- **Backend:** Supabase (managed Postgres + Auth + Storage + Row Level Security + auto-API). **EU-region** (persondata om levende). Skemaet er allerede deployet.
- **Frontend:** **TypeScript + React**, web + **PWA** først (skal føles native på mobil). React Native/Expo senere, hvis app-store-apps ønskes — samme TS/React-fundament.
- **Datapipeline / ETL / analyse:** **R** (DBI/RPostgres/dbplyr). *Ikke* Python — Python-filerne er kun reference.
- **Interoperabilitet:** **GEDCOM 7** som import/eksport-standard; intern model er rigere end GEDCOM og fladgøres ved eksport.

---

## 3. Datamodellens invarianter (SKAL respekteres)

1. **Evidensbaseret.** Et forhold deles i **påstande** (én kildes udsagn, *uforanderlige*, kildebundne) og en **konklusion** (den blåstemplede, foranderlige vurdering ovenpå). Gælder både fakta *og* relationer. Påstande overskrives aldrig; fortolkning lægges ovenpå.
2. **Lille fast entitetssæt + én generisk relation.** Relationen bærer rolle + periode + kilde + konfidens og er polymorf (enhver entitet → enhver entitet). Nye behov bliver nye *rolletyper/faktatyper* (data), ikke nye tabeller.
3. **Alt er et faktum.** Events/attributter modelleres som `fact` på enhver entitet (ikke kun person/familie — også sted, ejendom, våben har egne tidslinjer).
4. **Arbejdsværdi-cache er en envejs-projektion.** `person.visning_*` og `person.koen` afledes af konklusioner, **redigeres aldrig direkte**, regenereres når en konklusion ændres. Konkurrerer ikke med evidenslaget.
5. **Fuzzy datoer** = `(date_min, date_max)`-interval + kvalifikator + rå tekst. Floruit = dokumenteret-aktiv span, distinkt fra levetid. Gem altid den oprindelige tekst.
6. **Narrativ vs. struktureret.** Lang biografisk prosa bevares ordret i `narrative` (substrat, fuldtekstsøgbar); strukturerede fakta udtrækkes *selektivt* — kun hvor de bærer rygrad, forbindelse eller funktion. Resten bliver i prosaen og kan forfremmes senere.
7. **Konfidens på links.** `family_member.konfidens` (sikker/sandsynlig/formodet/omstridt) flager ubekræftede slægtskaber; reelt omstridte hypoteser med kilder ligger i evidenslaget. Slægtskabsfinderen skal vise usikkerhed, ikke skjule den.
8. **GDPR indbygget.** `person.levende` styrer synlighed: afdøde relativt åbne, levende kræver samtykke. Opdelingen er *også* forretningsmodellen (historisk arkiv til forskere; levende netværk til medlemmer) og kortlægges på RLS.
9. **Kontrolleret vokabular.** `slags`/`type`/`rolle`/`dekoration`/`koen` trækker på `vocab`-tabellen, så "samme slags"-forespørgsler er pålidelige.

---

## 4. Artefakter (medbring til repo'et)

| Fil | Hvad |
|---|---|
| `datamodel-oversigt.md` | **Autoritativ** modelbeskrivelse — læs først. |
| `schema.sql` | Konkret skema (PostgreSQL/Supabase + DuckDB). **Source of truth** for skemaet. |
| `diagram-1-strukturlag.mermaid` | ER-diagram: entiteter + generisk relation. |
| `diagram-2-evidenslag.mermaid` | ER-diagram: påstand/konklusion/citation. |
| `supabase_load.R` | **Primær** loader: seeder et Reventlow-udsnit (holstenske linje 1.-3. slægtled + ét omstridt-dato-tilfælde). |
| `supabase_load.py`, `import_test.py` | Python-pendant + lokal DuckDB-prøve. Reference; R er det fremadrettede sprog. |

---

## 5. Aktuel tilstand

- Skemaet er **deployet i Supabase**. Den levende base bygges fra `schema.sql` plus
  inkrementelle ALTER'er. **Alle migrationer samles nu idempotent i `db-migrations.sql`**
  (koen, konfidens, samt 2026-06-15-tilføjelserne fra TNG-analysen: citat_tekst/citat_dato,
  privat-flag på person/note/narrative, repository.adresse). `schema.sql` er source of
  truth; kør `db-migrations.sql` for at afstemme en allerede deployet base. Se også
  `docs/tng-reventlow-analyse.md`.
- **Aktuel tilstand (2026-06-16):** Hele Reventlow-stamtavlen er loadet (591 poster →
  934 personer) via `/daa-extract`. App-skive med klikbar slægtskabs-visning kører
  (web/). Nær families ægtefæller beriget. Se `docs/changelog.md` + `docs/decisions.md`.
  Parsere: `/daa-extract` (stamtavle), `/daa-presens` (præsensliste).
- **Endnu ikke lavet:** rigtigt RLS-lag (kritisk før multi-bruger — nulevende-data i
  basen nu), ægtefælle-rygrad for HELE slægten (kun nær familie pt.), dekorations-nøgle
  (fra anden DAA-udgave), rigtig GEDCOM/TNG-import (enrichment), multimedie/Storage.
- **Load:** `supabase_load.R` er erstattet af `/daa-extract`'s `load_daa.R` (bulk, ~14 sek).

---

## 6. Næste skridt (foreslået rækkefølge)

To spor — **data (R)** og **app (TS)** — bundet af RLS:

1. **Seed basen:** kør `supabase_load.R` og bekræft rækker i Supabase Table Editor.
2. **Første tynde app-skive:** TS/React + Supabase-side der læser én person og viser de lagdelte data (navn, floruit, omstridt dødsdato m. konklusion). Validerer stacken.
3. **RLS:** levende vs. afdøde, medlem vs. forsker som Postgres-politikker (ikke skrevet endnu).
4. **Slægtskabsfinderen:** graf-traversal over stamtræet (fælles ane / MRCA, kusin-grad); vis konfidens på stien.
5. **Rigtig import:** R-pipeline fra TNG/GEDCOM-eksport (og/eller selektiv DAA-parsing → narrative + udtrukne fakta).
6. **Multimedie (Storage), DAA-krydsreferencer, abonnementstier.**

---

## 7. Konventioner & faldgruber

- **Hemmeligheder** i `~/.Renviron` / miljøvariabler — aldrig i kode eller git. (`.env` → `.gitignore`.)
- **Supabase:** brug *Session pooler* (IPv4), `sslmode=require`, EU-region. Gratis-tier pauser efter 7 dages inaktivitet (hold varm før en live-demo) og har ingen backup (hold et dump i repo'et).
- **Cache-felter** (`visning_*`, `koen`): skriv aldrig direkte — regenerér fra konklusioner.
- **Påstande er uforanderlige.** Rettelser sker som nye påstande + ny konklusion.
- **Datoer:** gem både struktureret interval *og* rå tekst.
- **Hver trykt DAA-udgave er en selvstændig kilde** (`source`), så modstridende udgaver håndteres indfødt.

---

## 8. Sådan starter du i Claude Code

1. Læg artefakterne fra afsnit 4 i et repo (gerne denne fil som `CLAUDE.md`).
2. Bekræft forbindelsen: kør `supabase_load.R` mod Supabase og se seed-data i Table Editor.
3. Bed Claude Code om at stilladsere **trin 2** (første app-skive) — en minimal TS/React + `@supabase/supabase-js`-side der renderer én person fra basen. Hold dig til invarianterne i afsnit 3.
4. For setup-specifikt (installation, konfiguration) se de officielle docs: https://docs.claude.com/en/docs/claude-code/overview

---

## 9. Bevidst udskudt / åbne punkter

- **RLS-politikker** er ikke skrevet endnu (skitse mangler).
- **Slægtslinje som førsteklasses entitet** — pt. kun en linje-label på `person_external_id`; kan promoveres, hvis branch-niveau-udsagn ønskes.
- **Embede som egen entitet** — kun hvor succession er interessant; ellers en rolle ind i en organisation.
- **Fuld GEDCOM/TNG-importsti** — kun et håndtransskriberet udsnit findes nu.
- **Fuldtekstindeks på `narrative`** — Postgres-only blok, kommenteret i `schema.sql`; afkommentér ved brug.
- **Identitetssammenkædning** (er to kilders person den samme?) holdes pragmatisk i PoC.
