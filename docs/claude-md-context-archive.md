# claude.md kontekst-arkiv

> Arkiveret 2026-07-10 af `/doctor`-slankningen (genanvendt efter sync m. PR #26). §5
> (Aktuel tilstand) og §9 (Bevidst udskudt / åbne punkter) blev flyttet ud af den altid-
> residente `claude.md` for at spare kontekst-tokens. Fuld, løbende historik lever i
> `docs/changelog.md` og `docs/decisions.md`; dette er et ordret øjebliksbillede af de to
> sektioner (inkl. PR #26's §9-backlog-noter), som de stod ved arkiveringen.

---

## Arkiveret §5 — Aktuel tilstand (pr. 2026-07-10)


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
- **Web v3 Slice 1 — læsning + bogmærker (MERGET TIL MAIN + PUSHET, 2026-07-03):**
  localStorage-bogmærker (kanonisk via samme_som-collapse, async re-normalisering),
  ctx-kontekst-quicknav ("I fokus" i tree-mode), bmQuick-sidebar + fuld `BookmarksView`, `SlaegtPicker`-
  modal på slægt-chippen. Codex-dual-reviewet spec + egen /simplify-cyklus (delte UI-primitiver i
  `components/primitives.tsx`, memoization, `parentsOf`-genbrug). Bogmærke-ikonet er en rigtig SVG
  bogmærke-ribbon (bruger-feedback: den oprindelige ⚑/⚐-glyf lignede et flag). TDD (147/147
  web-tests), empirisk browser-verificeret mod prod (Playwright: toggle-flag→bmQuick→"Se alle"→
  bogmærke-række navigerer atomisk tilbage til tree-mode; slægt-picker backdrop/Escape).
  Se `docs/superpowers/specs/2026-07-03-web-v3-slice1-*`.
- **Udledt slægtsnavn — DB-lag PROD-LIVE + web/mobile reader-adoption (MERGET TIL MAIN + PUSHET,
  2026-07-03):** afledt families-efternavn for fødte medlemmer uden efternavn i DAA
  (`lineage.slaegtsnavn` fortrydbar kilde + `person.visning_efternavn`/`visning_fuldt_navn` envejs-
  cache på skip-listen). `regen_person_visning()` udvidet (fan-out-sikker CTE, suffiks-token-match,
  tvetydig-karantæne); cyklus-sikre `lineage_ancestors`/`lineage_descendants` genbruges skrive+
  læse-tid; to nye invalidation-triggere. `post_load_fixup.R` gjort reload-durabel. 3× Codex-
  reviewet spec + egen implementeringsplan + dual-review-cyklus (review 19: 2 HIGH-fund — trigger
  fyrede kun på UPDATE ikke INSERT, `red_slet_person` manglede karantæne-oprydning — begge rettet +
  anvendt til prod) + /simplify (fjernet dobbelt fan-out-beregning i `regen_person_visning`).
  **Verificeret LOKALT** FØR prod: `db-migrations.sql` kørt mod en GAMMEL (prod-svarende) skema-
  kopi (den reelle delta-sti) — alle asserts grønne. **Bruger godkendte alle 3 prod-trin
  (2026-07-03) — ANVENDT TIL PROD:** migration → `post_load_fixup.R` (cascade-regen af 580 linje-
  medlemmer) → fuld `regen_person_visning`-sweep for de resterende 343. Prod-tal bekræftede lokal
  test 1:1 (591 fødte/580 fik efternavn/11 sprunget over/0 karantæne). `get_advisors` fandt EFTER
  migrationen 2 huller (karantæne-tabel uden RLS + 2 funktioner uden `search_path`) — rettet +
  anvendt (bruger-godkendt) samme dag. Web+mobile læsere skiftet til `visning_fuldt_navn` (fallback
  `visning_navn`); redaktør-badge "efternavn afledt af linje". Se memory
  `udledt-slaegtsnavn-db-lag-lokalt-verificeret`, `docs/reviews/19-udledt-slaegtsnavn-dual-review.md`.
- **TNG-analyse opfølgning + backlog-prioritering (2026-07-03, ren dokumentation, ingen kode):**
  fuld gennemgang af `jr_tng_reventlow.sql` (37 tabeller + reelle rækketal) fandt nyt ift.
  juni-analysen: foto-region-tagging/albums/event-scoped medielink, per-forælder barnerelation,
  gemte rapporter (193 reelt brugte). Bruger-prioritering: **DNA afvist**; foto/medier udskudt
  SAMLET til én design-session; **gemte rapporter/smart-lister = næste fokus**; navnepartikel
  ("von"/"af") udskudt; **nyt ikke-designet krav:** flersproget stamtræ (ty/sv/no/en). Se §9 +
  `docs/decisions.md` + `docs/tng-reventlow-analyse.md` §7-8 (git-ignoreret).

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
- **Geografisk kort-markering (punkter + evt. arealer) — udskudt, ikke designet.**
  Brainstorm påbegyndt 2026-07-03, standset af bruger før designet blev skrevet
  ("projekt til senere lejlighed"). Datakilde-beslutning taget inden pause: hvis/når
  arbejdet genoptages, importér punkter fra TNG's `tng_places` (6.788 rækker,
  lat/lon, fritekst-hierarki) — IKKE DIGDAG. TNG har KUN punkter, ingen polygondata;
  areal-visning (fx et grevskabs historiske udstrækning) mangler stadig en
  datakilde — DIGDAG (digdag.dk, Rigsarkivets historiske grænseatlas) blev foreslået
  men ikke besluttet. `place` (schema.sql) har allerede `lat`/`lon`, ingen polygon-
  kolonne. Se memory `tng-backlog-prioritering`.
  **Ny vinkel (2026-07-04, kun planlægning):** bruger forestiller sig en
  kortoversigt "à la Google Maps" — landmarks/steder knyttet til personer vist på
  et kort, inkl. landmarks i brugerens egen geografiske nærhed (kræver enhedens
  live GPS-position, ikke kun statiske historiske koordinater). Ubesvarede
  spørgsmål til brainstorm-genoptagelsen: hvilke entiteter er "landmarks" (kun
  `place`, eller også `estate`/`coat_of_arms`-lokationer?); nærheds-søgning kræver
  location-permission-flow (mobile-only, ikke web); kort-bibliotek (`react-native-
  maps`/MapKit vs. web-Leaflet — to platforme, mulig delt abstraktion à la
  `buildBidirectionalColumns`-mønsteret).
- **Del personprofil (fx via SMS) til en anden person — nyt, ikke designet
  (2026-07-04, kun planlægning).** Sandsynlig løsning: nativ share-sheet
  (`expo-sharing`/React Native `Share`) fra persondetalje-skærmen, ikke en
  SMS-specifik integration — SMS bliver blot én af share-sheetets indbyggede
  muligheder. Ubesvarede spørgsmål: deles et link til `web/`s persondetalje-side
  (universelt, virker uden app) eller et app-deep-link (kræver Universal Links-
  opsætning)? Og hvordan opfører et delt link sig for en modtager der ikke er logget
  ind — respekterer det samme anon-RLS-gating (kun afdøde/ikke-private) som resten
  af appen, eller kræver det login for at åbne overhovedet?
- **Bogmærker i mobile/ — nyt, ikke designet (2026-07-04, kun planlægning).**
  Findes allerede i `web/` (Web v3 Slice 1, se `web/src/data/bookmarks.ts` +
  `BookmarksView.tsx`): `localStorage`-baseret, kanoniske person-id'er (samme_som-
  collapset), egen kommentar i koden markerer det bevidst som en PoC-grænse —
  en rigtig bruger-scoped/synkroniseret backend-store er udskudt til en senere
  "Slice 2". Mobile mangler både lagring og en find-mine-bogmærker-skærm; mest
  oplagte tilgang er at spejle web's kontrakt men med `@react-native-async-
  storage/async-storage` (allerede en dependency i `mobile/package.json`) i stedet
  for `localStorage`. Hænger sammen med den nye Konto-fane (login for medlem/
  redaktion, se `docs/changelog.md` 2026-07-04): en logget-ind bruger kunne på
  sigt få bogmærker synkroniseret på tværs af enheder i stedet for kun lokalt —
  ikke besluttet, kræver egen brainstorm om scope (kun lokal-per-enhed, eller
  konto-bundet).
- **Slægtskabs-felt A/B UX-bug + "det er mig"-knap for fremtrædende — RETTET
  (2026-07-04, commit `66dbe74`).** (a) "Sæt mig"-genvejen på slægtskabs-siden
  overskrev altid felt A (ødelagde den person man kom fra via en profils
  "Slægtskab"-knap). Rettet med ren helper `chooseMeSlot` (`mobile/src/lib/
  relateSlot.ts` + 6 unit-tests): fyld A hvis tomt, ellers B; skjul genvejen hvis
  "mig" allerede sidder i et felt; label tilpasses ("som første/anden person").
  (b) "Det er mig i slægten"-knappen vises nu kun når intet "mig" er sat, eller
  på ens egen markerede profil (guard i `person/[id].tsx`); ny "Hvem er du i
  slægten"-kontrol tilføjet på Konto-fanen (`(tabs)/konto.tsx`, genbruger
  `PersonPicker`) til direkte valg/skift. Verificeret: tsc + 264/264 jest +
  empirisk i iOS-simulator mod prod-data. **Fast-follow (ikke gjort):** web
  (`Folgesvend.tsx` `RelateView`) har strukturelt samme "Sæt mig"-overskrivnings-
  bug i sin egen lokale `useState`-udgave — samme rettelses-logik bør porteres.
- **Billeder i narrativer + slægts/linje-narrativ-editor (Slice C, web+mobile,
  branch `feat/narrativ-billeder`, 2026-07-05) — IMPLEMENTERET + LIVE-VERIFICERET,
  afventer merge.** `NarrativRenderer` omskrevet til blok-niveau (overskrift/
  afsnit/billede) på begge platforme via en delt `groupBlocks`-tokenisering
  (`mentions.ts`); indsæt-billede-UI i person- og den nye slægts/linje-editor
  (`subjekt_type='slaegt'` fast sentinel-id 1, eller `'lineage'`); udgave-fane-
  mønsteret (flere DAA-udgaver pr. narrativ) generaliseret fra person-only til
  ethvert subjekt på begge platforme; "Om slægten" viser nu linje-navne som
  overskrifter + rig blok-rendering i stedet for rå tekst. `/simplify`-kørt
  (4 parallelle reviews). Bruger-verificeret LIVE mod prod (overskrift + rigtigt
  billede via vilkårligt medie-id + dødt medie-token, alle korrekte på "Om
  slægten"). **Kendt, bevidst begrænsning (samme regel som person-bio'er):**
  kun narrativer på en DAA-udgave-kilde (`source.slags='DAA-udgave'`) vises
  offentligt — en TNG-kilde-narrativ gemmes men vises aldrig (`pickPreferredBio`).
  **Nyt, udskudt ønske (2026-07-05, ikke hastende):** rigere tekstformattering —
  flere overskriftniveauer, titler, kursiv, evt. fuldt markdown. Nuværende
  omfang er bevidst minimalt (kun `##`/`###` + linjeskift, ingen bibliotek,
  se plan-dok `docs/superpowers/plans/2026-07-05-billedstoerrelser-artikler-
  lightbox.md` §7.1d) — en udvidelse bør genoverveje samme afvejning (nyt
  bibliotek vs. håndrullet, kollision med `[[type:id|label]]`-syntaksen).
- **Redaktør: redigér/slet ægteskaber — nyt, ikke designet (2026-07-06).** Redaktøren har i dag
  ingen flade til at rette eller slette en `family`/`family_member`-relation (ægteskab/union).
  Konkret motiveret af et fundet OG RETTET data-fejl-tilfælde: person 1 (Gottschalk, 1.
  slægtled, linje I) var fejlagtigt registreret som "gift med" sit eget barnebarn person 104
  (Hartwich, 3. slægtled) i familie 74 — loader-fejl fra den oprindelige indlæsning, aldrig rørt
  af redaktør-redigering. Bogtekst for Hartwich: "Gift med NN" (ukendt hustru), ingen omtale af
  Gottschalk. **Rettet mod prod 2026-07-06** via en manuelt forfattet, fortrydbar `change_set`
  (id 30, `DELETE family_member WHERE family_id=74 AND person_id=1 AND rolle='partner'`) — familie
  74 har nu kun Hartwich (104) som partner + Iwan (44) som barn, matcher enkelt-partner-mønsteret
  der allerede findes andre steder i basen (7 lignende ægteskaber m. ukendt ægtefælle). Verificeret
  ingen flere spøgelse-par tilbage (bred søgning: partner-par ≥2 slægtled fra hinanden i samme
  linje, ikke udtømmende). **Selve fladen mangler stadig:** lige nu kræver enhver lignende fejl en
  direkte, manuel SQL-`change_set` — ikke bæredygtigt hvis flere findes. Kræver design af:
  slet-hele-familien vs. fjern-én-partner, konfidens-nedgradering som alternativ til hård
  sletning, og hvordan børnenes forældre-links håndteres når en union slettes.
- **Mobilapp crasher ved åbning af person i redaktør-delen — BUG, ikke undersøgt endnu
  (rapporteret 2026-07-06).** Bruger rapporterer at appen crasher HVER GANG man forsøger at åbne
  en person-detalje i redaktør-fladen (`mobile/src/app/redaktion/person/[id].tsx`). Ingen
  root-cause-analyse lavet endnu — kræver reproduktion (device/simulator-log) før fix.
