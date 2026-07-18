# Én person i søgning + udgave-versionsvælger på profilen — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Efter 1939-genindlæsningen optræder samme fysiske person som to søgeresultater (1939- og 2018-20-posten), selv efter redaktøren har bekræftet matchet i "Sammenlign udgaver". (A) Redaktøren skal have synlig feedback om hvorfor et bekræftet link ikke folder offentligt (karantæne), og (B) personprofilen skal vise den nyeste DAA-udgaves biografi som standard med en versionsvælger til ældre udgaver — i stedet for dagens sammenkædning.

**Status:** Del A og B implementeret 2026-07-18 (denne session); Del C udeladt (se derunder). Ikke endnu manuelt verificeret mod en rigtig Supabase-instans (intet DB-adgang i sessionen) — se Verifikation-afsnittet.

## Analyse (verificeret i koden 2026-07-18)

Fold-infrastrukturen findes allerede og virker:

- Bekræft-knappen i `web/src/components/SammenlignUdgaver.tsx` skriver via RPC `red_samme_som` (`schema.sql:1013`): `relation(rolle='samme_som')` + `assertion` + `conclusion(status='afklaret')`.
- Offentlig web folder afklarede links til ÉN kanonisk person FØR søgning/stamtræ: `collapseSameAs` (`packages/core/src/collapseSameAs.ts`), kaldt i `web/src/data/model.ts:140`. Redaktionen folder bevidst IKKE (`web/src/Redaktion.tsx:185`, `collapse:false`) — dubletter dér er by design.
- **Rodårsag til vedvarende offentlige dubletter:** `validateGroups` karantænerer grupper med konflikt — vigtigst *konkurrerende forældre* (`collapseSameAs.ts:160-171`). Før forældrene i de to udgaver også er matchet, kanoniserer forældre-sættene ikke ens, og barnet foldes ikke. Karantænen logges KUN i browser-konsollen (`model.ts:141`); redaktøren får ingen feedback ved Bekræft.
- Den rådgivende preflight `previewSammeSom` (`packages/core/src/sammeSomPreflight.ts`) findes og er eksporteret fra `@daa/core` — men er **ikke koblet på noget UI**.
- Profil-hullet: `fetchPersonDetail` (`web/src/data/public.ts:140-193`) vælger nyeste DAA-bio PR. MEDLEM (`pickPreferredBio`) men sammenkæder derefter alle medlemmers tekster — ikke "nyeste + vælg ældre".

## Global Constraints

- **Motoren urørt:** `collapseSameAs`, `buildModel`, `relationship.ts` ændres IKKE. Karantæne-reglerne (inkl. konkurrerende forældre) er korrekte og bevares — vi gør dem synlige, vi slækker dem ikke.
- **Preflight er rådgivende:** `previewSammeSom` kører på redaktions-datasættet; offentlig visning kan afvige pga. RLS/completeness (jf. header i `sammeSomPreflight.ts`). UI-tekst skal afspejle det.
- **`pickPreferredBio`-determinismen genbruges:** samme `BIO_SLAGS`-gate og sortering (`aar DESC NULLS LAST, sourceId DESC`) — gaten eksporteres, dupliker den ikke.
- **Bagudkompatibelt:** `PersonDetailData.bio` bevares (= nyeste versions tekst). Mobile er bevidst UDENFOR scope i denne omgang (bio bæres dér på personen via collapse-union).
- **Commits:** Conventional Commits (dansk), ingen Claude-attribution, slut med `Claude-Session: https://claude.ai/code/session_0173wh8BpUpToPEtWKiKbBX3`.

## Fil-struktur

| Fil | Ansvar |
|---|---|
| `packages/core/src/bioVersions.ts` (ny) | Ren selector: narrativ-kandidater → udgave-versioner, nyeste først |
| `packages/core/src/__tests__/bioVersions.test.ts` (ny) | Vitest af selectoren |
| `packages/core/src/pickPreferredBio.ts` (mod) | Eksportér `BIO_SLAGS`-gaten til genbrug |
| `packages/core/src/index.ts` (mod) | Eksportér `buildBioVersions` |
| `web/src/data/public.ts` (mod) | `fetchPersonDetail`: byg `bioVersions`; `bio` = nyeste |
| `web/src/components/DetailPanel.tsx` (mod) | Versionsvælger-chips over biografien (kun ved >1 version) |
| `web/src/components/SammenlignUdgaver.tsx` (mod) | Preflight-hint ved Bekræft + karantæne-oversigt |
| `packages/core/src/buildFamilyGraph.ts` (ny, ikke oprindeligt planlagt) | Ren aggregering `family_member`-rækker → unions+parentChild, delt af den nye redaktions-fetch |
| `packages/core/src/__tests__/buildFamilyGraph.test.ts` (ny) | Vitest af aggregeringen |
| `web/src/data/redaktionRead.ts` (mod, ikke oprindeligt planlagt) | Ny `fetchFamilyGraph()` — leverer parentChild/unions til preflight-Db'en |
| `web/src/Folgesvend.tsx` (mod, mekanisk) | `PersonDetailData`-fallback i catch-grenen udvidet med `bioVersions: []` |

## Del A — Synlig karantæne-feedback i redaktionen ✅ implementeret

- [x] **A1. Delt kant-henter — realiseret anderledes end planlagt:** i stedet for at udtrække `model.ts`s relation+conclusion-join, genbruges `linkede`-state'en som `SammenlignUdgaver.tsx` allerede hentede via `fetchSammeSomPar` (kun `relation.rolle='samme_som'`, uden conclusion-join). Dette er funktionelt identisk: `red_samme_som`-RPC'en (schema.sql:1013) indsætter ALTID relation+conclusion(afklaret) atomisk i samme transaktion — der findes ingen skrive-vej der opretter et samme_som-link uden en afklaret konklusion. At bygge en ny query ville have dupliceret data model.ts allerede validerer. `model.ts` er IKKE rørt (motor-invarianten holdt).
  Til selve `Db`-graf-tjekket (konkurrerende forældre kræver parentChild) var der intet eksisterende sted der leverede hele familie-grafen til redaktionen uden for `loadModel`. Løst med en ny delt, ren funktion `buildFamilyGraph` i `@daa/core` (aggregerer `family_member` → unions+parentChild, uden far-før-mor-sortering — ordenen er uden betydning for karantæne-tjek) + `fetchFamilyGraph()` i `redaktionRead.ts`. `rawDb.persons` bygges af den allerede-hentede `personer` (`RedMatchPerson[]` fra `fetchMatchPersoner`).
- [x] **A2. Preflight-hint pr. kandidat** (udvidet ift. planen: vises for BÅDE ubekræftede kandidater og allerede-bekræftede links, ikke kun "ved klik"): `foldHint(aId, bId, linket)` — for et bekræftet par slås karantæne-status op i `karantaeneByPersonId` (afledt af én samlet `collapseSameAs`-kørsel, se A3); for et ubekræftet par køres `previewSammeSom(rawDb, existingEdges, {alias, canonical})` direkte, så redaktøren ser konsekvensen FØR de klikker Bekræft. Tekst: "→ vil folde offentligt" / "→ vil IKKE folde: {grund}" (ubekræftet) og "✓ foldes offentligt til én person" / "✓ bekræftet — foldes IKKE endnu offentligt: {grund}" (bekræftet).
- [x] **A3. Karantæne-oversigt:** `<details>`-panel over arbejdslisten, viser `foldPreview.quarantined` (fra ÉN `collapseSameAs`-kørsel over ALLE bekræftede kanter — samme kørsel som A2 slår op i, ingen dobbelt-beregning) med personnavne via `visning(byId.get(id))` og karantæne-grunden.

## Del B — Profil: nyeste udgave + versionsvælger ✅ implementeret

- [x] **B1. Core-selector:** `buildBioVersions` i `packages/core/src/bioVersions.ts`, `BIO_SLAGS` eksporteret fra `pickPreferredBio.ts` og genbrugt (ikke duplikeret). 5 vitest-cases: sortering, `version[0]` matcher `pickPreferredBio`s valg, gate-filtrering, multi-medlem-samme-udgave-dedup, tom input.
- [x] **B2. Data-lag:** `fetchPersonDetail` (`web/src/data/public.ts`) bygger nu ÉT flat `NarrativeCand[]` (kanonisk medlem først) over alle `memberIds` og kalder `buildBioVersions`; `PersonDetailData.bioVersions` tilføjet, `bio = bioVersions[0]?.tekst ?? ''`.
- [x] **B3. UI:** `DetailPanel.tsx` — chip-række (samme visuelle stil som linje-badges) vises kun når `bioVersions.length > 1`; lokal `useState(bioVersionIdx)` nulstillet via `useEffect` på `focusId`-skift (ellers lækker et ældre-udgave-valg over på næste person); "Tidligere udgave"-label når et ikke-nyeste chip er valgt.

## Del C (valgfri, lille) — udeladt

- [ ] **C1.** Badge "⇒ samme som #id" i redaktionens personliste — udeladt denne runde (ikke kritisk for brugerens oplevede problem; kan tages senere som selvstændig lille opgave).

## Verifikation

1. **Kørt i sessionen:** `packages/core`: `npm test` → 19 filer/264 tests grønne (inkl. 5 nye bioVersions- + 5 nye buildFamilyGraph-tests). `web`: `npx tsc -b` ren; `npm test` (med en lokal, ikke-committet `.env.local` — påkrævet af `supabase.ts` for at modulet kan loade i test) → 21 filer/161 tests grønne, ingen regressioner.
2. **IKKE kørt (intet Supabase-adgang i sessionen) — mangler manuel verifikation:**
   (a) i "Sammenlign udgaver": bekræft et match hvor forældrene i de to udgaver IKKE selv er matchet → forvent "→ vil IKKE folde: konkurrerende forældre (…)" / "✓ bekræftet — foldes IKKE endnu offentligt: …" og en linje i karantæne-oversigten; match forældrene → hint og oversigt opdateres ved næste `refresh` og bliver "folder offentligt";
   (b) offentlig søgning viser herefter ÉN bedstefar, ikke to;
   (c) profilen viser 2018-20-biografien som standard med et "1939"-chip der skifter til 1939-teksten.
3. Kendt afgrænsning: mobile (`mobile/src/`) er urørt — `bioVersions` findes kun i web's `PersonDetailData`; mobilens person-bio bæres stadig via `collapseSameAs`-narrativ-unionen som i dag.
