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
- **Aktuel tilstand (2026-06-17):** Hele Reventlow-stamtavlen loadet (591 poster →
  **925 personer**: 591 hoved + 334 ægtefæller) via `/daa-extract`. App-skive med
  klikbar slægtskabs-visning kører (web/). **Ægtefælle-rygrad for HELE slægten** gjort.
  `boern` udledes nu deterministisk i `validate.py`. Se `docs/changelog.md` +
  `docs/decisions.md`. Parsere: `/daa-extract` (stamtavle), `/daa-presens` (præsensliste).
- **Endnu ikke lavet:** deterministisk aegteskaber-udtræk (~9% LLM-miss); dekorations-nøgle
  (fra anden DAA-udgave); rigtig GEDCOM/TNG-import (enrichment); multimedie/Storage.
  (era-tie-break/kryds-gren-boern viste sig at være samme rodårsag som
  flere-forældrepar-fejlen nedenfor og er løst som sideeffekt — mobil-guard i
  `buildModel.ts` er formentlig overflødig, men ikke fjernet.)
- **Load:** `supabase_load.R` er erstattet af `/daa-extract`'s `load_daa.R` (bulk, ~14 sek).
- **Versionering + hyperlinks (DB-lag) LIVE i prod (2026-06-30):** fortryd-bar redaktionel
  ændringshistorik (`change_set`/`change_event` + generisk `log_change`-trigger på 22 tabeller +
  `red_fortryd_change_set`-restore) og hyperlinks (`[[type:id|tekst]]` → `parse_mentions` +
  `text_mention`-indeks). Append-baseret `red_edit_oplysning` (void→jsonb). Dual-reviewet
  (Claude+Codex+code-analyzer), 24 verify-asserts grønne, applied atomisk. Se `docs/reviews/09-*.md`
  + `docs/superpowers/plans/2026-06-30-versionering-hyperlinks-db-lag.md`.
  Deferrede review-punkter (TOCTOU, parse_mentions open-token, `red_doede_links` 3/10 typer).
- **Versionering + hyperlinks (App-lag, RN/Expo) — merget til main + pushet (2026-06-30):**
  `mentions.ts` (token-parser/encoder) + `NarrativRenderer` + `MentionPicker` (@-vælger) +
  redaktionel historik-skærm m. fortryd (ruter gennem `SkrivePreviewSheet`-dry-run/LIVE-flow).
  Dual-reviewet (Claude+Codex, cycle 10: H1 escape-asymmetri, H2 omvendt `reverteret`-semantik,
  M3 fejl-svælgning) + `/simplify`. `tsc`/jest grøn (197/197). **Expo-verificeret mod iOS-
  simulator + rigtig prod-Supabase** (`idb`-baserede taps, redaktør-login af bruger, én godkendt
  LIVE-testskrivning): token-rendering/navigation, bio-klamp, MentionPicker insert-at-cursor,
  fortryd-flow og redo-knap på reversal-post ALLE konfirmeret empirisk. Konflikt-retry
  (item 5, kræver konstrueret B9-divergens) forbliver utestet. Fandt undervejs: (1) omvendt
  dry-run-toggle-polaritet i person-editoren (UI-bug, rettet), (2) `_version_upsert_row`
  manglede eksklusion af `GENERATED ALWAYS`-kolonner — gjorde fortryd strukturelt knækket for
  enhver tabel med en sådan kolonne (`narrative.fts` i praksis); migration anvendt til prod +
  schema.sql/db-migrations.sql. Se `docs/reviews/10-app-lag-hyperlinks.md`.
- **TNG-QA-pipeline komplet (2026-06-30):** read-only R-pipeline (`R/tng-qa/`, Trin 1-6)
  matcher vores personer mod et TNG-dump (auto-tier margin-kalibreret) og producerer en
  GDPR-sikker rapport (`docs/reviews/tng-qa-rapport-<dato>.md`, input-gating PII-gate) der
  lister relations-/dato-uenigheder til review. Udestår: håndlabelt facit-sæt, `review_cutoff`-
  kalibrering, review-kø-persistens. Se `docs/tng-qa-koersel.md`.
- **Flere-forældrepar datafix (2026-07-01):** 90 personer havde beviseligt modstridende
  forældrepar (163 fejlagtige `barn`-links af 559) pga. et upålideligt LLM-felt der blev
  afprøvet FØR forælderens egen linje i `load_daa.R`'s child-matching. Rettet i loaderen
  (rækkefølge byttet) + prod-data korrigeret via versioneret SQL-sletning (`change_set` #3,
  fortrydbart). 4 personer uden linje-match + 46 nu-forældreløse personer kræver manuel
  opfølgning. Se `docs/reviews/11-flere-foraeldre-datafix.md`.
- **DAA-reimport Etape 1+2 + data-tab-genopretning (2026-07-02):** Loader/validate hærdet
  (Etape 1, merget+pushet: ekstern_ref-dedup, 15a/15b-børn, deterministiske datoer, RESET-guard,
  `--force-reset`, frossen prompt). Live-basen var i tidligere session overskrevet til 3
  test-personer; **reset-reloadet til 922 personer** via `clean-v2.json` + `--force-reset`.
  Redaktør-profil + lineage-navne genoprettet i idempotent `post_load_fixup.R` (reload-sikkert).
  **TNG-QA: manglende links 125→10** (92% genindvundet). Grundlægger-dubletter (Conrad III-58↔V-1,
  Detlef III-104↔IV-1) linket via `samme_som`. Se changelog 2026-07-02.
- **samme_som-collapse IMPLEMENTERET (web+mobile, branch `feat/samme-som-collapse`, ikke pushet):**
  frontend identitets-projektion så en person med flere DB-poster vises som én. Ren `collapseSameAs`
  FØR `buildModel` (motoren urørt): union-find → kanonisk = unik sink; fixed-point-validering +
  karantæne (self-forælder/-ægtefælle/cyklus/konkurrerende forældre/vital-køn); merge m. years-regen
  + konfidens-stærkeste dedup. Integration: fetch af afklarede `samme_som` + collapse, alias-map i
  state (`meId` kanoniseret ved read-site), Aux-id-projektion (`linjeByPerson`→`string[]`),
  proveniens-badge; redaktion collapser IKKE. Dual-reviewet (Claude+Codex, `docs/reviews/16`+`17`,
  Codex opgraderede 2 defers til silent-corruption) + /simplify + empirisk prod-valideret
  (Conrad/Detlef folder rent) + ende-til-ende gennem slægtskabs-motoren (spec §10). Mobile 240,
  web 88. **Udestår:** manuel skærm-verifikation + merge/push.

---

## 6. Næste skridt (foreslået rækkefølge)

To spor — **data (R)** og **app (TS)** — bundet af RLS:

1. **Seed basen:** kør `supabase_load.R` og bekræft rækker i Supabase Table Editor.
2. **Første tynde app-skive:** TS/React + Supabase-side der læser én person og viser de lagdelte data (navn, floruit, omstridt dødsdato m. konklusion). Validerer stacken.
3. **RLS:** levende vs. afdøde, medlem vs. forsker som Postgres-politikker — **gjort** (`db-rls.sql`, verificeret af `db-verify.sql`). Anon/authenticated/redaktion-lag inkl. media afbildet-gating. Udestår: samtykke-granularitet pr. levende person + forsker/medlem-tier (skitse i `db-rls.sql` §FREMTID).
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

- **RLS-politikker** — **skrevet** (`db-rls.sql` + `db-verify.sql`): anon (afdøde/ikke-private), authenticated (medlem ser levende, ej private), redaktion (ser alt), staging-politikker, og media afbildet-gating via SECURITY DEFINER-helpere. **Udestår:** samtykke-granularitet pr. levende person (`samtykke_offentlig`) og forsker- vs. medlem-tier — skitseret i `db-rls.sql` §FREMTID, designes når auth-laget bygges.
- **Slægtslinje som førsteklasses entitet** — **trin (a) gjort (2026-06-23):** `lineage`-tabel `(id, source_id, kode, navn)` giver linjerne navne (se `docs/decisions.md`). **Trin (b) skema gjort (2026-06-30):** additive kolonner `parent_lineage_id` (forgrening) + `status` på `lineage` (schema.sql + db-migrations.sql, verificeret af db-verify.sql Task 9); adling/medlemskab/eget våben rider på de polymorfe `fact`/`relation`-tabeller (rolle `gren_af`, `person→lineage` m. konfidens) — ingen skema-ændring. **Udestår:** app-surfacing (redaktør-UI til at sætte forgrening/status + offentlig visning af linje-hierarkiet).
- **Embede som egen entitet** — kun hvor succession er interessant; ellers en rolle ind i en organisation.
- **Fuld GEDCOM/TNG-importsti** — kun et håndtransskriberet udsnit findes nu.
- **Fuldtekstindeks på `narrative`** — Postgres-only blok, kommenteret i `schema.sql`; afkommentér ved brug.
- **Identitetssammenkædning** (er to kilders person den samme?) holdes pragmatisk i PoC.
