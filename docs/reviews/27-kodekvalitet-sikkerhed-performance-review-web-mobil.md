# Review 27 — Kodekvalitet, sikkerhed, performance, test & robusthed: web + mobil

**Dato:** 2026-07-09
**Scope:** Hele `web/` og `mobile/` som de står (inkl. ukommitterede v4-ændringer i
web). Emner: kodekvalitet/arkitektur, sikkerhed (klientlag), performance,
testdækning, fejlhåndtering/robusthed. **Ikke** dækket her: UX/navigation
(review 26), DB-laget/RLS (reviewede separat, bl.a. review 12 + get_advisors),
den kendte redaktør-crash på mobil (separat spor).
**Metode:** 5 parallelle read-only review-agenter (web-kvalitet, mobil-kvalitet,
sikkerhed, performance, test+robusthed), syntetiseret og dedupliceret. Ingen
kodeændringer foretaget. Fund er markeret `verificeret` (læst/målt i kode) hvor
agenten har angivet det; performance-effekter uden måling er markeret `antaget`.

---

## 0. Samlet vurdering

**Korrekthedsrisikoen er lav, strukturgælden er reel og koncentreret.** Den
funktionelle kerne (rene datafunktioner, nav-grammatik, collapse-logik) er
gennemtestet og velkommenteret i begge produkter; sikkerhedsbilledet i
klientkoden er godt (ingen KRITISK/HØJ). De væsentlige fund samler sig om fire
rodårsager:

1. **Web↔mobil-duplikering uden delingsmekanisme** (~15 spejlede moduler, drift
   allerede påbegyndt) — forklarer samtidig testhullerne på web-siden.
2. **Ingen CI** — 565 eksisterende tests håndhæves ikke af noget.
3. **To monolit-filer** (`web/src/Folgesvend.tsx` 1326 l., `mobile/src/app/redaktion/person/[id].tsx` 859 l.).
4. **Tavse fejl-mønstre** i enkelte fetch-lag (`.catch(() => {})`, manglende
   `.error`-tjek) — den eneste kategori med reel adfærdspåvirkning i dag.

---

## 1. Top-10 på tværs (prioriteret efter effekt/indsats)

| # | Fund | Kategori | Alvor | Indsats |
|---|---|---|---|---|
| 1 | **Ingen CI** — hverken `.github/` workflows eller hooks; 565 tests gates intet (Vercel kører kun `tsc`+`build`) | Test | HØJ | Lav (én workflow-fil) |
| 2 | **Web↔mobil: ~15 spejlede moduler uden delingsmekanisme**; `buildModel.ts` og `fields.ts` er allerede divergeret, og kun mobil-kopierne er testet | Arkitektur | HØJ | Mellem |
| 3 | **GeoMap-WebView (mobil): script-injection-flade** — `JSON.stringify(points)` interpoleres rå i `<script>`; `</script>`-breakout muligt via stednavne (`mobile/src/components/GeoMap.tsx:39`) | Sikkerhed | MELLEM | Minutter (escape `<`) |
| 4 | **Web-bundle: maplibre-gl (276 KB gzip, 63 % af chunken) loades statisk ved start** men bruges kun i kort-views (`GeoMap.tsx:5`, målt på dist) | Performance | HØJ | Lav (React.lazy) |
| 5 | **Tavse fetch-fejl**: `fetchPersonDetail`/`fetchEstateInfo` tjekker ikke `.error` (`web/src/data/public.ts:93-98,137-147`); `.catch(() => {})` i `web/src/Redaktion.tsx:171-173` og 5 steder i mobil-redaktørens person-editor | Robusthed | HØJ | Lav |
| 6 | **`privat`-narrativer filtreres klient-side i `fetchAbout`** (`web/src/data/public.ts:202-212`) — private rækker ligger i netværkssvaret hvis RLS ikke gater dem; egne memory-læring: klient-guards er illusoriske | Sikkerhed | MELLEM | Lav + RLS-verifikation |
| 7 | **`Folgesvend.tsx`-monolitten** — 8 views + app-shell + ~26 useState i én fil | Kodekvalitet | HØJ (vedligehold) | Mellem |
| 8 | **Mobil: `meId`-kanoniserings-race** — kanoniseres ved læsning i `person/[id].tsx:60` men rå `meId` bruges i `tree.tsx:380,257,279`, `relate.tsx:48`, `(tabs)/index.tsx:47`; parallel `hydrateMe()`/`load()` kan misse alias-gemte id'er → "★ DIG"/wayfinder/feed svigter | Korrekthed | MELLEM | Lav (én selector) |
| 9 | **Ingen persistent model-cache** — mobil: fuldt netværks-load (17 queries) ved hver kold start; web: ~16-20 requests hvor geo-kæden (place ~6,8k rækker) dominerer men kun bruges til kort | Performance | MELLEM | Mellem (SWR-cache + lazy geo) |
| 10 | **Webbens fejlskærm ved Supabase-pause** — free-tier-pause (kendt driftsvilkår) viser rå "Failed to fetch" uden retry-knap (`Folgesvend.tsx:288`); mobilens offline-seed-fallback er forbilledet | Robusthed | MELLEM | Lav |

Detaljer pr. område nedenfor. Fund der IKKE nåede top-10 står i deres sektion.

---

## 2. Tværgående: web↔mobil-delingen (rodårsag for #2, dele af #1 og #7)

**Fund (verificeret):** Identiske filpar uden mekanisme til at holde dem i sync:
`collapseSameAs.ts` (300/300 linjer identisk), `relationship.ts` (327/327),
`generations.ts` (51/51), plus `sammeSomPreflight`, `pickPreferredBio`,
`buildGeo`, `geoSelectors`, `collation`, `mentions`, `NarrativRenderer`,
`GeoMap`, `Lightbox`, `SlaegtPicker`, `redaktionRead/Write`, media-laget.
**Driften er begyndt:** `fields.ts` divergerer (24 vs. 22 linjer), `buildModel.ts`
divergerer (5375 vs. 5518 bytes) — og i begge tilfælde er **kun mobil-kopien
testet**. En bugfix i én kopi når ikke automatisk den anden (jf. memory-læringen
fra web-v2-porten: tjek delt-vs-specifik FØR fix).

**Anbefaling (vælg ét af to niveauer):**
- **Fuldt fix:** npm-workspace (`packages/core`) med den rene, DOM-frie logik —
  begge apps importerer samme kode, tests bor ét sted. Størst engangsinvestering,
  eliminerer problemklassen.
- **Minimalt værn (kan gøres nu):** en `parity.test.ts` der asserter at de
  bevidst spejlede filer er byte-identiske (eller eksplicit undtaget med
  begrundelse) + kopiér mobilens `buildModel`/`load`-tests til web. Gør tavs
  divergens til en rød test. (En sådan test findes allerede i en umerged
  worktree — genbrug den.)

Anbefalet: start med værnet (sammen med CI, #1), tag workspace-pakken som
selvstændig beslutning — det er en arkitekturændring, der fortjener sit eget spor.

---

## 3. Kodekvalitet — web

**HØJ · W-K1: `Folgesvend.tsx` er en 8-i-1-monolit** (1326 l.). 8 view-komponenter
(TreeView, TreeSearch, RelateView, DetailPanel, EstatesView, OverviewMapView,
ArmsView, AboutView) + app-shell med ~26 `useState` (auth/login-modal, bogmærker,
søge-, relate-, estate- og mega-menu-state) i én fil. Udtræknings-mønstret findes
allerede (HomeView/BookmarksView bor i `components/`, TreeView testes eksternt) —
snittet er modent. Forslag: flyt views til `components/`, udtræk derefter 2-3
hooks af shell'en (`useLoginSession`, `useEstateData`, `useTreeSearchState`).
Context er ikke nødvendig endnu (`TreeSearchBundle` tæmmer prop-drilling pænt).

**MELLEM · W-K2: URL-afledt state dubleres som useState** (`Folgesvend.tsx:57,107,
224-229,238-259`). `mode`/`estateId` er rene afledninger af path men holdes som
state med to skrivekilder (`goToMode`/`navigateTree` OG path-effekten). Fungerer,
men hver ny navigationssti skal huske begge sider. Forslag:
`useMemo(() => parseFolgesvendPath(path), [path])`; kun `focusId` behøver state.

**MELLEM · W-K3: Redaktion.tsx duplikerer theme-tokens + font-hook**
(`Redaktion.tsx:34-40,88-99` vs. `theme.ts`/`Folgesvend.tsx:34-44`) — en
farvejustering skal laves to steder. Udvid `theme.ts`, del font-hooken.

**MELLEM · W-K4: Hårdkodede farve-literaler udenom theme** — 38× `rgba(34,31,26,.1)`,
37× `#3d382f` m.fl.; samme border+radius+shadow gentages i ~15 kort-renderinger.
Forslag: `T.border`/`T.inkSoft`/rose-tokens + en `Card`-primitiv.

**LAV:** forældet kommentar over `LinjeChip` (`:1298`); ubrugte exports
(`Kicker`/`H1` i `primitives.tsx:9-14`); `parseFolgesvendPath(window.location…)`
kørt hver render men kun brugt i initializers (`:56`).

---

## 4. Kodekvalitet — mobil

**HØJ · M-K1:** web↔mobil-duplikeringen — se §2.

**HØJ · M-K2: `redaktion/person/[id].tsx` (859 l.) med blandet ansvar** — ~8
inline sheets/forms, 6 fetch-effects, pending-change-maskine og layout i én fil.
Forslag: flyt sheets til `components/redaktion/` (mønstret findes —
SletBekraeftSheet bor der allerede) + saml fetches i én
`usePersonEditorData(id)`-hook med samlet refresh.

**MELLEM · M-K3: `meId`-kanoniserings-race** (top-10 #8, verificeret). Forslag:
kanonisér ét sted — i `hydrateMe`/`setMe` eller en `selectMeId`-selector, som
alle skærme bruger. Eneste reelle korrekthedsrisiko i mobil-fundene.

**MELLEM · M-K4: Tavse fejl i redaktørens fetches**
(`redaktion/person/[id].tsx:275-315`: `.catch(() => {})` ×5) — netværksfejl =
permanent tomme sektioner; redaktøren kan tro fakta/familie ikke findes. Ingen
stale-guard/abort ved id-skift. Konflikt-køen gør det rigtigt
(`(red-tabs)/index.tsx:27-29`) — genbrug mønstret + `let alive = true`-guards.

**MELLEM · M-K5: 9 `as never`-casts omgår typedRoutes** (typedRoutes er slået
til i `app.json:48`). 8 af 9 peger på redaktions-ruter — netop dér hvor manglende
route-registrering (kendt fund) ikke fanges af compileren. Forslag: én typed
helper `gotoRedaktionPerson(id)` indtil route-typerne genereres korrekt.

**MELLEM · M-K6: afledt lokal state** — `privat`-toggle som
`useState` + sync-effect (`redaktion/person/[id].tsx:268-269`); re-fetch under
pending dry-run nulstiller togglen visuelt. Render direkte fra `person.privat`.

**LAV:** direkte `useStore.setState({relA})` udenom action (`person/[id].tsx:289`);
VariantC's rute-farvelogik er ren, testbar logik placeret utestet i komponenten
(`tree.tsx:282-305` → flyt til `data/selectors.ts`); `setTimeout(60)`-scroll-hack
(`tree.tsx:145-160` → `onContentSizeChange`).

---

## 5. Sikkerhed (klientlag)

**Ingen KRITISK eller HØJ fund i produktions-klientkoden.**

**MELLEM · S1: GeoMap-WebView script-injection (mobil)** — top-10 #3
(`GeoMap.tsx:39`, `originWhitelist={['*']}`). Udnyttelse kræver skriveadgang til
stednavne (redaktør/DB-kompromittering), derfor MELLEM. Fix er én linje:
`JSON.stringify(points).replace(/</g, '\\u003c')` (+ evt. ` `/` `).
Positivt: SRI-hashes på CDN-load er allerede på plads.

**MELLEM · S2: `fetchAbout` filtrerer `privat` i JS, ikke i queryen** — top-10 #6
(`public.ts:202-212`). Person-narrativ-queries samme fil gør det rigtigt
(`.eq`-filter i query). Fix: `.eq('privat', false)` + **verificér empirisk** at
narrative-RLS gater `privat` for anon (jf. [[koer-get-advisors-efter-ddl]]-læringen:
migration-success lyver).

**LAV:** dev-tooling-sårbarheder (web: 0 i prod-deps, 5 i dev-kæden — vitest UI
CRITICAL/vite dev-server HIGH, rammer kun udviklermaskinen; mobil: 12 moderate,
alle Expo-build-tooling — følger med næste SDK-bump). Session-JWT i
localStorage/AsyncStorage (supabase-js-default; accepteret restrisiko da ingen
XSS-sinks fundet — mobil kan hærdes med `expo-secure-store`). Deep-link-scheme
`"mobile"` er generisk og kan opsnappes af anden app — omdøb til fx
`daafolgesvend` **før distribution**.

**Bekræftet sikre mønstre (verificeret):** ingen `dangerouslySetInnerHTML`/`innerHTML`
overhovedet — narrativer renderes via egen token-parser med escape-håndtering;
kun anon-nøgler i klient-env (gitignoret, `git check-ignore`-verificeret), ingen
service_role nogen steder; eneste strenginterpolerede PostgREST-filter er
`Number()`-coerced (injection-neutral); klient-rollen bruges kun til routing —
den reelle gate er RPC/RLS; storage-stier er app-genererede, bucket privat med
kortlivede signed URLs; ingen open-redirect-sinks.

---

## 6. Performance

**HØJ · P1: maplibre-gl statisk i web-bundlen** — top-10 #4. Målt: chunk 1,6 MB
(439 KB gzip), heraf maplibre 276 KB gzip (63 %), loadet ved kold start men kun
brugt i kort-views. `React.lazy` på GeoMap+MapLightbox → initial ~163 KB gzip
(ca. −60 %). Bedste enkeltstående performance-ROI i repoet.

**HØJ · P2: browse-grid uden virtualisering, re-render pr. tastetryk** —
"Gennemse hele slægten" renderer ~920 `PersonCard` (≈4-5k DOM-noder), og al
søge-state bor i app-roden, så hvert tastetryk re-renderer hele appen
(`Folgesvend.tsx:486,544-553`; render-tid antaget 50-150 ms/keystroke).
Billigste fix: `contentVisibility:'auto'` + `containIntrinsicSize` på
bogstav-grupperne; alternativt windowing/"vis flere".

**MELLEM · P3: intet persistent model-cache (begge)** — top-10 #9. Mobil: 17
parallelle queries ved hver kold start, kun `meId` caches. Web: geo-kæden
(`place` ~6,8k rækker = 7 sekventielle sider + `fact`) dominerer opstarten men
bruges kun til kort; `estate` hentes desuden dobbelt (`model.ts:85` +
`public.ts:44`). Fix: (a) udskyd place/fact til første kort-brug, (b) versioneret
stale-while-revalidate-cache i localStorage/AsyncStorage, (c) genbrug estate-data.

**MELLEM · P4: `mobile/src/data/load.ts:128/148` henter `family`-tabellen og
kasserer resultatet** (tomt destructure-slot) — ét dødt round-trip i den kritiske
start-batch. Slet queryen (minutter).

**MELLEM · P5: `buildBidirectionalColumns` uden `useMemo` på web**
(`Folgesvend.tsx:637`) — beregnes pr. TreeView-render i variant B, også pr.
tastetryk. Mobilens pendant ER memoiseret (`tree.tsx:137-140`). Effekt antaget
lille (<10 ms), men fixet er én linje.

**LAV:** SectionList uden `getItemLayout` trods fast rækkehøjde
(`search.tsx:84-106`); fonte injiceret i `useEffect` → sen FOUT (flyt `<link>` +
preconnect til `index.html`); `lifeJourney()` kaldt to gange pr.
DetailPanel-render (`:965,968`).

**Bekræftet sundt:** `useBookmarks` race-hærdet; `bmDep`-guarden forhindrer
browse-rekørsel ved bogmærke-toggle; `buildFeed` memoiseret med korttyper-lofter;
Zustand-selectors granulære (ingen re-render-kaskader); `expo-image` +
`keyExtractor` konsekvent.

---

## 7. Test & CI

Talt statisk: **web 234 test-cases (27 filer), mobil 331 (27 filer)** — i alt 565.

**HØJ · T1: Ingen CI** — top-10 #1. Intet `.github/`, ingen hooks; Vercel kører
kun `tsc -b && vite build`. Én GitHub Actions-workflow der kører `vitest run` +
`jest` på PR er den billigste høj-effekt-rettelse i hele reviewet.

**HØJ · T2: Kritiske paths kun testet på mobil-siden** — `buildModel` (utestet
på web OG divergeret), `relationship`, `fields` (kun mobil-kopien testet);
web `model.ts` (fetch/degraderingslag) utestet mens mobilens `load.ts` ER testet.
Jf. §2 — paritetstest + testkopiering lukker hullet.

**MELLEM:** `paginate.ts`/`getAll` utestet begge steder (1000-rækkers
.range()-paginering er data-load-kritisk, kun empirisk verificeret én gang);
`mobile/src/store/useStore.ts` utestet (kan drives headless uden RTL —
RTL@14-begrænsningen undskylder ikke store-tests); web `mediaUpload`/`auth`
(redaktør-skriveveje).

**Dækket godt:** al ren domænelogik i begge apps (collapse, tree, browse, nav,
feed, redaktionRead/Write), tomme tilstande (tom/whitespace-søgning testet),
mobilens fetch-lag. Skærm-/komponentlag på mobil er udækket (kendt
RTL@14-blokering) — Playwright-flowet på web er manuelt, ikke i CI.

---

## 8. Fejlhåndtering & robusthed

**HØJ · R1: Tavse fejl-mønstre** (top-10 #5), tre beslægtede fund:
- `fetchPersonDetail`/`fetchEstateInfo` tjekker ikke `.error` på direkte
  supabase-kald (`public.ts:93-98,137-147`) — supabase-js kaster ikke, så en
  RLS-/grant-fejl bliver tavst til tom biografi, og filens eget
  "breakage er ikke HELT tavst"-kontrakt-udsagn holdes ikke. Fix: lille
  `orThrow(res)`-helper brugt konsekvent (mønstret findes i `fetchAbout` og
  `paginate.ts:15`).
- `Redaktion.tsx:171,173` sluger session- og model-fejl (`.catch(() => {})`) —
  fejlet model-load efterlader formentlig evig loading.
- Mobil-redaktørens 5 tavse catches (M-K4, §4).

**MELLEM · R2: Webbens fejlskærm ved pauset Supabase** (top-10 #10) — free-tier-
pause er et *kendt* driftsvilkår (jf. CLAUDE.md §7), men giver rå "Failed to
fetch" uden retry-knap; `describeErr`-hintet dækker kun RLS/JWT-mønstre
(`Folgesvend.tsx:288,1322-1325`). Fix: retry-knap + "basen kan være i dvale"-tekst.
Mobilens LoadGate + offline-seed-fallback ("Offline-visning · begrænset
seed-data") er forbilledet — bedste robusthed i repoet.

**MELLEM · R3: Ingen ErrorBoundary i nogen af apps** (grep: 0 hits) —
render-crash på web = hvid skærm. Én boundary omkring hovedindholdet med
"Genindlæs"-knap. Mobil: expo-routers default-boundary er *antaget*, ikke
konfigureret eksplicit.

**LAV · R4: Bogmærke-fejl uden brugerfeedback** — `list()` sluger fejl → ligner
"ingen bogmærker" (`bookmarks.ts:19-20`, begge apps); optimistisk toggle ruller
korrekt tilbage ved fejl men flaget "hopper bare tilbage" uden forklaring.

**Bekræftet sundt:** degraderingsmønstret per-tabel (`.catch` → tom liste +
navngivet `console.warn`) er bevidst og velkommenteret; redaktør-RPC-fejl
oversættes pænt i UI (`oversaetFejl`); tomme tilstande håndteret; konsol-hygiejne
ren (alle 19 hits er bevidste, taggede warns).

---

## 9. Anbefalet angrebsrækkefølge

**Bølge 1 — timer, ikke dage (kan tages umiddelbart):**
1. CI-workflow (T1) · 2. GeoMap-escape (S1) · 3. Død family-query (P4) ·
4. `orThrow` i public.ts + de 7 tavse catches (R1) · 5. `fetchAbout`-queryfilter
(S2, + RLS-verifikation via psql/get_advisors).

**Bølge 2 — enkeltdags-opgaver:**
6. Lazy-load maplibre (P1) · 7. Paritetstest + kopiér buildModel/load-tests til
web (T2) · 8. `selectMeId`-kanonisering (M-K3) · 9. Retry-knap/dvale-tekst +
ErrorBoundary (R2+R3) · 10. content-visibility på browse-grid (P2).

**Bølge 3 — strukturspor (egne beslutninger/PRs):**
11. Folgesvend.tsx-opsplitning (W-K1, naturligt sammen med §5-split-skiven) ·
12. Mobil person-editor-opsplitning (M-K2, naturligt sammen med crash-fixet) ·
13. Workspace-pakke `packages/core` (§2 — beslutning først) · 14. Model-cache/
lazy geo (P3).

---

## 10. Det, der er gjort godt (bevar mønstrene)

- **Ren, testet funktionel kerne i begge apps** — domænelogik som DOM-/fetch-frie
  rene funktioner med egne tests; skærme som tynd komposition over selectors.
- **Kommentarkultur i særklasse:** ikke-trivielle beslutninger bærer "hvorfor" +
  review-reference; tidligere fund er sporbare i koden.
- **TS-hygiejne:** strict overalt; 2 (web) hhv. 4 (mobil) dokumenterede escape
  hatches i alt.
- **Sikkerhedsarkitekturen:** RLS som eneste reelle gate, klient-rolle kun til
  routing, ingen HTML-injection-sinks, korrekt secrets-disciplin.
- **Mobilens offline-degradering** (seed-fallback + banner) — portér idéen til web.
- **Bevidste degraderings- og guard-mønstre** (per-tabel catch, in-flight-guard i
  `load()`, write-generation-guard i bookmarks, `bmDep`-memo-guard).

---

*Grundlag: 5 read-only agent-reviews 2026-07-09 (kodekvalitet web/mobil,
sikkerhed, performance, test+robusthed) over arbejdstræet inkl. ukommitteret
web-v4. Fund dedupliceret; alvor harmoniseret på tværs. Ingen kode ændret.*
