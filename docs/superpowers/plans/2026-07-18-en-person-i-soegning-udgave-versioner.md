# Én person i søgning + udgave-versionsvælger på profilen — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Efter 1939-genindlæsningen optræder samme fysiske person som to søgeresultater (1939- og 2018-20-posten), selv efter redaktøren har bekræftet matchet i "Sammenlign udgaver". (A) Redaktøren skal have synlig feedback om hvorfor et bekræftet link ikke folder offentligt (karantæne), og (B) personprofilen skal vise den nyeste DAA-udgaves biografi som standard med en versionsvælger til ældre udgaver — i stedet for dagens sammenkædning.

**Status:** Planlagt (endnu ikke påbegyndt). Noteret 2026-07-18 efter analyse i session.

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
| `web/src/data/model.ts` (evt. mod) | Udtræk delt henter af afklarede samme_som-kanter (genbrug af l. 74-79-mønstret) |

## Del A — Synlig karantæne-feedback i redaktionen

- [ ] **A1. Delt kant-henter:** udtræk hentningen af afklarede `samme_som`-kanter (relation `rolle='samme_som'` person→person + `conclusion(status='afklaret', target_type='relation')`, matchet i JS) fra `web/src/data/model.ts:74-79,132-138` til en genbrugelig hjælper i `web/src/data/`, så Sammenlign udgaver kan hente samme kantsæt.
- [ ] **A2. Preflight-hint ved Bekræft:** i `SammenlignUdgaver.tsx`, kald `previewSammeSom(rawDb, existingEdges, {alias, canonical})` når et match bekræftes (rawDb bygges af redaktions-modellen, `collapse:false`). Vis inline: "✓ bekræftet — foldes offentligt" eller "✓ bekræftet — foldes IKKE endnu: {grund}" + handlingsanvisning ("Match forældrene i de to udgaver, så foldes denne automatisk."). Markér at hintet er rådgivende.
- [ ] **A3. Karantæne-oversigt:** panel øverst i fanen der kører `collapseSameAs` på redaktions-datasættet med ALLE afklarede kanter og lister `result.quarantined` (medlemmer med navne fra den ukollapsede model + grund) — arbejdslisten "disse bekræftede links venter på X".

## Del B — Profil: nyeste udgave + versionsvælger

- [ ] **B1. Core-selector:** `buildBioVersions(cands: NarrativeCand[]): BioVersion[]` med `BioVersion = { sourceId, aar, udgave, tekst }`. Filtrér på eksporteret `BIO_SLAGS` + ikke-tom tekst; gruppér pr. `sourceId` (flere medlemmer i samme udgave → dedup'et sammenføjning, kanonisk medlem først — kalderen leverer rækkefølgen); sortér `aar DESC NULLS LAST, sourceId DESC`. Tests: gruppering, sortering, gate, multi-medlem-samme-udgave, tom input.
- [ ] **B2. Data-lag:** `fetchPersonDetail` samler alle `NarrativeCand` på tværs af `memberIds` (data hentes allerede i dag), kalder `buildBioVersions` og udvider `PersonDetailData` med `bioVersions: BioVersion[]`; `bio` sættes til `bioVersions[0]?.tekst ?? ''`.
- [ ] **B3. UI:** i `DetailPanel.tsx:110`: ved `bioVersions.length <= 1` uændret visning; ved `>1` chip-række over biografien med udgave-labels (`udgave` eller `aar`), nyeste valgt som standard, lokal `useState` skifter vist tekst gennem `NarrativRenderer`. Genbrug linje-badge-stilen (`DetailPanel.tsx:84-86`). Diskret markering "tidligere udgave" når en ældre version er valgt.

## Del C (valgfri, lille)

- [ ] **C1.** Badge "⇒ samme som #id" i redaktionens personliste for personer der er alias i et afklaret link — kun hvis billigt; ellers udelades.

## Verifikation

1. `packages/core`: `npm test` — nye bioVersions-tests + eksisterende `collapseSameAs.test.ts` uændret grønne.
2. Web: typecheck/build + eksisterende vitest.
3. Manuel (kræver Supabase-adgang): (a) bekræft et match hvis forældre IKKE er matchet → se "foldes IKKE endnu: konkurrerende forældre"; match forældrene → karantæne-oversigten tømmes og offentlig søgning viser ÉN person; (b) profilen viser 2018-20-biografien med chip til 1939-versionen.
4. Uden DB-adgang: dæk preflight-integrationen og versionsvælgeren med unit-/komponenttests; dokumentér den manuelle test i PR-beskrivelsen.
