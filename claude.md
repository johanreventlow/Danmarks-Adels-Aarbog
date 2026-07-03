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
- **Børn af flergifte forældre → korrekt union (merget til main via `e79c821`, 2026-07-03):**
  loaderen hang alle børn på 1. union; nu delt matcher `match_barn_union` (`load_helpers.R`:
  partnernavn primær, ordenstal kryds-tjek, NA-frem-for-gæt) wired i `load_daa.R` (34 tests,
  dry-run mod alle 591 records). Prod-data rettet: 64 flyttet/1 parkeret i `change_set 1`
  (fortrydbart), verificeret (Conrad Gabel 6/Hahn 10, Anna Sophie nu på Hahn). Se
  `fix_boern_multi_union.R` + changelog/decisions 2026-07-03. III-85 (Detlef) efterfølgende
  løst (`change_set 2`): parkeringen var falsk-negativ pga. ekstraktionsfejl i `aegteskab_kontekst`
  — bogen siger 1. ægteskab (Catharina von Brockdorff); flyttet tilbage + kildefelt rettet.
- **TNG-QA Etape 3+4 + spøgelses-union-oprydning (prod, 2026-07-03):** Etape 3 = vores 5 datoer stod
  fast (bogen bekræfter; TNG forkert) → TNG oprettet som `source` (id 2) + 5 konkurrerende dato-
  assertions (`change_set 3`, konklusion uændret). Etape 4 = 8/10 falske positiver (samme_som/stub).
  Afdækkede systematisk **spøgelses-union-fejl**: 26 barnløse unioner hvor et barn var fejl-"gift"
  med sin far/ane (mor-heading "med X (se nr. Y)" → fake-aegteskab, navn≠ref). Oprydt: V-121-dedup
  (`cs4`), I-103-gren genopbygget m. Maria Elisabeth + 10 børn (`cs5`), 26 spøgelser slettet (`cs6+7`).
  fam 11 bruger-bekræftet ægte, bevaret. **UDESTÅR:** loader-guard (afvis intern-ref-link ved navne-
  mismatch) — ellers gen-skaber reload de 26. Se changelog/decisions/[[tng-qa-etape-3-4-spoegelses-unioner]].
- **samme_som-collapse IMPLEMENTERET (web+mobile — merget til main via PR #14, 2026-07-03):**
  frontend identitets-projektion så en person med flere DB-poster vises som én. Ren `collapseSameAs`
  FØR `buildModel` (motoren urørt): union-find → kanonisk = unik sink; fixed-point-validering +
  karantæne (self-forælder/-ægtefælle/cyklus/konkurrerende forældre/vital-køn); merge m. years-regen
  + konfidens-stærkeste dedup. Integration: fetch af afklarede `samme_som` + collapse, alias-map i
  state (`meId` kanoniseret ved read-site), Aux-id-projektion (`linjeByPerson`→`string[]`),
  proveniens-badge; redaktion collapser IKKE. Dual-reviewet (Claude+Codex, `docs/reviews/16`+`17`,
  Codex opgraderede 2 defers til silent-corruption) + /simplify + empirisk prod-valideret
  (Conrad/Detlef folder rent) + ende-til-ende gennem slægtskabs-motoren (spec §10). Mobile 240,
  web 88. **Merget til main** via PR #14 (collapseSameAs.ts på origin/main pr. 2026-07-03).
- **Redaktør-web-cohesion (web, merget til main via PR #14, 2026-07-03):**
  redaktør-fladen bragt i tråd med web-v2. (a) Header: DAF-logo-lockup + "Danmarks Adels Aarbog" + mono
  "Redaktion · Dansk Adels Forening" + slægt-chip (crest-ring + "Reventlow ▾") + 66px-mål; ført både i
  design-mockuppen og `Redaktion.tsx`. (b) Person-liste spejler Følgesvend §9.1/§9.2: A–Å + alfabet-hop,
  sortér navn/fødeår, linje-filter-chips (filtrerer kun — intet stamtræ). `buildBrowse` generaliseret
  (`BrowsePerson`) så én motor driver både `ModelPerson` og `RedPerson`; driver af skrive-autoritativ
  `persons` (ikke `model.persons`) — se `docs/decisions.md`. /simplify anvendt. tsc + 94/94 web-tests +
  build grønne. **Udestår:** visuel/runtime-verifikation i browser (ingen browser-driver i repo'et).
- **Stamtræ Kolonner-visning + bidirektionel aner/efterkommere IMPLEMENTERET (web+mobile, branch
  `feat/stamtrae-kolonner`) (2026-07-03):** lukker item 8 (Kolonner) fra web-v2-porten OG udvider
  visningen til begge retninger. Fokus er et fast anker; aner folder ud til venstre (Forældre →
  Bedsteforældre → … → `N× Tipoldeforældre`), efterkommere til højre. Delt retnings-parametriseret
  bygger (`buildBidirectionalColumns`, visited-cyklusguard + `kind:depth`-keys) spejlet web
  (`data/tree.ts`) + mobile (`data/selectors.ts`); web parentsOf tilføjet. Tilstand: web lokal
  `useState` m. frontier-reset; mobile zustand (`path`→`anchorId`/`up`/`down`, mutator-reset). Drill
  via historik-fri `onFocus`. Design Codex-reviewet (1 BLOCKER: frontier- ikke medlemskabs-reset,
  + 5 SHOULD-FIX indarbejdet; `docs/superpowers/specs/2026-07-03-*`). **Verificeret:** web tsc+109
  tests+build (bruger-bekræftet visuelt), mobile tsc+249 tests + **iOS-simulator-verificeret mod prod**
  (idb: bidirektionel drill/labels/chevrons/up-scroll + collapse gennem traversering). Variant A/C urørt.
- **Redaktør: klikbar familie-navigation + fødsels/dødsår (web+mobile, merget til main `bffdfc2`,
  2026-07-03):** partnere/børn/forældre i redaktør-familieoversigten er nu klikbare (åbner deres
  editor — web `setRecordId`, mobile `router.push`, genbruger `PersonRad`-primitiven); børn+partnere
  viser årstal fra `model.byId.years` (ingen ekstra query, nyt `aar`-felt i `mapFamilieRows`, spejlet
  web+mobile). Modellen urørt (navigation=læsning; edit/slet gik i forvejen gennem append/fortrydbare
  `red_*`-RPC'er) — se `docs/decisions.md`. Web 112/112 + mobile 249/249 + tsc grønne. **Runtime-verifik.
  udskudt til fysisk enhed** pga. RN-fetch-sim-bug (-1005; host+sim-Safari når Supabase, app ej) — se
  memory `mobil-sim-rn-fetch-1005`.
- **Flere narrativer pr. person — udgave-nøglede narrativer (web+mobile, MERGET TIL MAIN `3537d13`
  + PROD-LIVE, 2026-07-03):** en person kan bære én biografi pr. DAA-udgave (`source`).
  `red_upsert_narrativ` nøgles nu på `(subjekt_type, subjekt_id, source_id)`; additiv `source.aar`
  bærer udgave-kronologi; `red_opret_kilde` udvidet m. `p_aar`; gamle 4-arg-signaturer droppet.
  Delt ren `pickPreferredBio` (spejlet web+mobil, nyeste DAA-udgave, DAA-only fallback) driver begge
  læsere. Web-redaktør: udgave-faner + "+ Ny udgave" (via `submitChange`-flow). Mobil-redaktør:
  minimal source-korrekt skrivevej (RPC-DROP var cross-client breaking). Cutover-orden **DB-først →
  merge → push** (nye læsers source-embed matcher basen; ingen offentlig breakage). Dual-reviewet
  (Codex, `docs/reviews/18`) + `/simplify` + advisor-gate; web 124/124, mobil 257/257. **Udestår:**
  udgave-byline i læseren + fulde udgave-faner i mobil. Se `docs/superpowers/{specs,plans}/2026-07-03-
  flere-narrativer-per-person*` + memory `flere-narrativer-per-person`.
- **Web v3 Slice 1 — læsning + bogmærker (branch `feat/web-v3-laesning-bogmaerker`, IKKE merget/pushet,
  2026-07-03):** localStorage-bogmærker (kanonisk via samme_som-collapse, async re-normalisering),
  ctx-kontekst-quicknav ("I fokus" i tree-mode), bmQuick-sidebar + fuld `BookmarksView`, `SlaegtPicker`-
  modal på slægt-chippen. Codex-dual-reviewet spec, TDD (147/147 web-tests), empirisk browser-verificeret
  mod prod (Playwright: toggle-flag→bmQuick→"Se alle"→bogmærke-række navigerer atomisk tilbage til
  tree-mode; slægt-picker backdrop/Escape). Se `docs/superpowers/specs/2026-07-03-web-v3-slice1-*`.
- **Udledt slægtsnavn — DB-lag PROD-LIVE, reader-adoption på branch (2026-07-03):** afledt
  families-efternavn for fødte medlemmer uden efternavn i DAA (`lineage.slaegtsnavn` fortrydbar
  kilde + `person.visning_efternavn`/`visning_fuldt_navn` envejs-cache på skip-listen).
  `regen_person_visning()` udvidet (fan-out-sikker CTE, suffiks-token-match, tvetydig-karantæne);
  cyklus-sikre `lineage_ancestors`/`lineage_descendants` genbruges skrive+læse-tid; to nye
  invalidation-triggere. `post_load_fixup.R` gjort reload-durabel. 3× Codex-reviewet spec + egen
  implementeringsplan (`docs/superpowers/plans/2026-07-03-udledt-slaegtsnavn.md`). **Verificeret
  LOKALT** (pg_dump read-only prod-kopi, brugergodkendt) FØR prod: `db-migrations.sql` kørt mod en
  GAMMEL (prod-svarende) skema-kopi (den reelle delta-sti) — alle asserts grønne, empirisk
  backfill-dry-run matchede spec §2 eksakt. **Bruger godkendte alle 3 prod-trin (2026-07-03) —
  ANVENDT TIL PROD:** migration → `post_load_fixup.R` (cascade-regen af 580 linje-medlemmer) →
  fuld `regen_person_visning`-sweep for de resterende 343. Prod-tal bekræftede lokal test 1:1
  (591 fødte/580 fik efternavn/11 sprunget over/0 karantæne, 0/923 mangler `visning_fuldt_navn`).
  `get_advisors` fandt EFTER migrationen 2 huller i det nye (karantæne-tabel uden RLS + 2 funktioner
  uden `search_path`) — rettet + anvendt (bruger-godkendt) samme dag, begge bekræftet lukkede.
  Web+mobile læsere (branch `feat/udledt-slaegtsnavn-v2`, IKKE merget/pushet) skiftet til
  `visning_fuldt_navn` (fallback `visning_navn`); redaktør-badge "efternavn afledt af linje".
  web tsc+124/124, mobile tsc+258/258. Se memory `udledt-slaegtsnavn-db-lag-lokalt-verificeret`.
- **TNG-analyse opfølgning + backlog-prioritering (2026-07-03, ren dokumentation, ingen kode):**
  fuld gennemgang af `jr_tng_reventlow.sql` (37 tabeller + reelle rækketal) fandt nyt ift.
  juni-analysen: foto-region-tagging/albums/event-scoped medielink, per-forælder barnerelation,
  gemte rapporter (193 reelt brugte). Bruger-prioritering: **DNA afvist**; foto/medier udskudt
  SAMLET til én design-session; **gemte rapporter/smart-lister = næste fokus**; navnepartikel
  ("von"/"af") udskudt; **nyt ikke-designet krav:** flersproget stamtræ (ty/sv/no/en). Se §9 +
  `docs/decisions.md` + `docs/tng-reventlow-analyse.md` §7-8 (git-ignoreret).

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
- **TNG-inspireret backlog (2026-07-03, se `docs/tng-reventlow-analyse.md` §7-8):**
  DNA-slægtskabsdata **afvist** (ikke en del af modellen). Foto/medie-rigdom
  (region-tagging, albums, event-scoped medielink, medie-proveniens) **udskudt men
  ønsket** — samlet design-session, ikke stykvis. Navnekomponentering/adelspartikel
  ("von"/"af") **udskudt**. **Gemte rapporter/smart-lister er næste fokus** (TNG
  har 193 reelt brugte — datakvalitets-/medlemsforespørgsels-værktøj til
  redaktøren; byg som parametriserede forespørgsler, ikke rå SQL).
- **Flersproget stamtræ (tysk/svensk/norsk/engelsk) — nyt, ikke designet.** Kræver
  egen brainstorm: UI-i18n vs. indholds-i18n af navne/titler/stednavne/narrativ, og
  hvor oversættelse lander i evidenslaget (ny assertion vs. visningslag vs. flere
  narrative-rækker pr. kilde-sprog). Se `docs/tng-reventlow-analyse.md` §8.
