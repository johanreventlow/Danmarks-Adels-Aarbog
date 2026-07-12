# Design: Generations-browser v2 — bidirektionel + slægtled-naboer + kombinerede labels

**Dato:** 2026-07-05
**Status:** Design — Codex-reviewet (3 HIGH + 3 MEDIUM + 1 LOW indarbejdet, §9); afventer bruger-review
**Bygger på:** v1 (`2026-07-05-generations-reparation-design.md`, PROD-LIVE + merget PR #19)
**Branch:** `feat/generations-browser-v2`
**Anledning:** empirisk UI-test af v1 (bruger, 2026-07-05).

---

## 1. Mål

Gør v1's aner-hul-reparation til en fuld **generations-browser**: `N−1 ← [N: fokus + naboer] → N+1`,
med konsistente slægtled-overskrifter. Tre ændringer, alle på den delte træ-bygger + de to UI-lag.

## 2. Nøglebeslutning: aktiv linje bæres i navigations-state (Codex HIGH-2)

En person kan have flere linje-koordinater (en founder er fx III/G12 **og** V/G1). "Lavest lokal"
er IKKE et pålideligt valg: ankommer man via en III-fallback og lander på en founder, ville lavest-
lokal skifte konteksten til V og gøre naboer/labels/næste-ring vildledende.

Derfor bærer træet en **aktiv koordinat** i state: `activeCoord = { sourceId, lineageId, lokal } | null`.
- **Sættes ved re-ankring fra et kort:** = det klikkede korts koordinat i DEN linje man klikkede
  igennem (fallback-kort bærer `prev.linje`+`lokal`; peer/proven-kort bærer deres egen aktiv-linje-coord).
- **Direkte navigation** (søgning/link/"det er mig"): default = personens koordinat med lavest `lokal`
  (deterministisk), eller `null` hvis ingen (spouse/NULL).
- `activeCoord` driver **naboer (§4), fallback-retning (§3) OG labels (§5)** — én konsistent linje-
  kontekst. Threades ved siden af `anchorId`/`up`/`down` (web `useState`, mobil zustand).

## 3. Ændring A — efterkommer-fallback (symmetrisk, ærlig dødende)

Når efterkommer-ringen (`childrenOf`) er tom, byg en **efterkommer-fallback-ring** = personer ved
`slaegtled_lokal = activeCoord.lokal + 1` i `activeCoord`-linjen.

- **Ingen syntetisk ned-hop.** Kryds-linje-fortsættelse dækkes KUN hvor gren-stamfaren er dobbelt-
  listet i den aktive linje (Reventlow-konvention: founder optræder som `<parentlinje>/G(n)` OG
  `<nylinje>/G1`, collapset via `samme_som`) — så same-line G+1 finder dobbelt-listnings-posten,
  og et klik re-ankrer + sætter `activeCoord` til den valgte linje-coord (klikker man founderens
  ny-linje-videreførelse, fortsætter browsingen dér). **Hvor bogen ikke har en G+1-post (linjen slutter,
  ELLER en founder ikke er dobbelt-listet): ingen ring — ærlig dødende** (samme ærlighed som aner).
  Fuld kryds-linje-nedstigning uden dobbelt-listning er eksplicit UDEN for v2 (§7).
- Delt kerne: retnings-generaliser `previousAncestorGen` → `adjacentGen(coords, sourceId, lineageId,
  lokal, dir)`: `dir=-1` = aner **med** founder-krydshop (uændret v1-logik); `dir=+1` = efterkommer,
  **ren** `lokal+1` i samme `(sourceId,lineageId)`, INGEN hop. `fallbackAncestorRing` →
  `fallbackRing(model, genCoords, anchorId, cur, depth, dir)`; bygges i begge retninger i
  `buildDirection` når den beviste ring er tom. **v1's source+lineage-scoped kandidat-match bevares
  i begge retninger** (Codex MEDIUM-4).

## 4. Ændring B — slægtled-naboer i fokus-kolonnen

Fokus-kolonnen viser **fokus dominant + andre personer i samme slægtled (aktiv linje) som dæmpede
sekundære kort**.

- **Naboer:** `model.persons` filtreret til samme `(activeCoord.sourceId, lineageId, lokal)` som fokus,
  minus fokus. Tom hvis `activeCoord = null` → kun fokus (v1-adfærd, ingen regression).
- **`TreeColumn.focusId: string`** (nyt) markerer det dominante kort; ankerets `people = [fokus,
  ...naboer]`. **Styling/interaktion keyes fra `focusId`, IKKE `selectedId`** (Codex MEDIUM-5) — v1's
  "selectedId driver næste ring"-kontrakt forbliver intakt for de øvrige kolonner.
- **Cap/gruppering (Codex MEDIUM-6):** et 40-personers slægtled må ikke begrave fokus. Vis fokus +
  op til **K=7** naboer sorteret (fx efter navn/kuld); resten som ét "+N flere i slægtledet"-kort der
  folder ud på klik. (Genbrug kuld-grupperings-mønsteret fra v1's fallback hvor `kuld` findes.)
- **Klik på et peer-kort:** re-ankrer til peer'en + sætter `activeCoord` til peer'ens coord i den
  aktive linje (så man bliver i samme linje-kontekst). **Mobil:** anker-kort får en tryk-handler
  (v1-hul hvor anker ikke var trykbart, Codex MEDIUM-5).

## 5. Ændring C — kombinerede kolonne-overskrifter

- **Kolonne-slægtled = `activeCoord.lokal ∓ depth`** (deterministisk, bundet til den browsede linje).
  Det løser mixed-kolonne-problemet (Codex HIGH-3): en bevist børn-kolonne kan indeholde en kryds-
  linje-founder med et andet lokalt tal, men headeren afspejler **den aktive linjes** generation, ikke
  et sammenblandet skalar. (Kryds-linje-medlemmer vises stadig som beviste børn; de får bare ikke et
  modstridende per-kort-tal.)
- **Format:** `"<slægtskab> · <N>. slægtled"` for `depth≤4` (Forældre/Bedsteforældre/Oldeforældre/
  Tipoldeforældre | Børn/Børnebørn/Oldebørn/Tipoldebørn); **`"<N>. slægtled"` for `depth≥5`** (afskaffer
  "N× Tipoldeforældre"). Anker: `"<N>. slægtled · <linje>-linjen"`. Fallback: `"muligt · <N>. slægtled
  · <linje>-linjen"`.
- **Fallback til v1-adfærd:** hvis `activeCoord = null` (ingen generation-data) → rent slægtskabs-ord
  som i dag (inkl. det gamle "N× Tipoldeforældre"), så personer uden slægtled er uændrede.
- Ren helper `columnLabel({ kind, depth, slaegtled, linje, fallback })` — testbar isoleret.

## 6. Filer + delt-kode-grænse (Codex LOW-7)

**Eksplicit delt kerne (SKAL være tegn-for-tegn identisk web↔mobil):** funktionerne `adjacentGen`
(i `generations.ts`), samt `fallbackRing`, `buildAnchorPeers`, `columnLabel` (i `tree.ts`/`selectors.ts`).
En **paritets-test** i begge suiter læser de fire funktioners kilde-tekst fra begge platform-filer og
asserter lighed (fanger drift mekanisk, ikke kun ved review).

- `web/src/data/generations.ts` + `mobile/src/data/generations.ts`: `adjacentGen`.
- `web/src/data/tree.ts` + `mobile/src/data/selectors.ts`: `fallbackRing` (bidirektionel),
  `buildAnchorPeers`, `columnLabel`, `TreeColumn` (+`focusId`, behold `fallback/genLabel/kuldGroups`).
- Tilstand: `web/src/Folgesvend.tsx` (`useState` + `activeCoord`), `mobile/src/store/useStore.ts` +
  `mobile/src/app/(tabs)/tree.tsx` (zustand + `activeCoord`, anker-tryk-handler).
- UI: dæmpede peer-kort + "+N flere", efterkommer-fallback-styling (genbrug aner-stil),
  kombinations-labels. Ingen DB-ændring.

## 7. Eksplicit UDEN for v2

- Kryds-linje efterkommer-nedstigning UDEN dobbelt-listet founder (ægte kryds-gren uden bro) →
  ærlig dødende nu; egen brainstorm hvis data kræver det.
- Multi-niveau aner-hop (bedstemoderlinje uden mellem-coord) — som v1.

## 8. Test

Rene enheder: `adjacentGen` begge retninger (dir−1 founder-hop bevaret + **v1-regressionstests:
source/lineage-exakt-match, fail-closed ambiguøs hop**; dir+1 ren G+1 + ærlig-dødende); `columnLabel`
alle grene (d≤4, d≥5, anker, fallback, `activeCoord=null` → kinship-only); `buildAnchorPeers` (naboer,
cap/"+N flere", tom ved null); `fallbackRing` efterkommer-retning; **paritets-test** (delt-kode-grænse).
Web+mobil spejlet; v1-tests forbliver grønne. Empirisk: browser (bidirektionel browse + naboer +
labels + Conrad-linje-kontekst-bevarelse) + fysisk enhed.

## 9. Codex-review-fund og hvordan de er adresseret

1. **HIGH — "ingen ned-hop" strukturelt falsk:** samme_som forbinder identiteter, ikke forælder→distinkt
   founder. → §3: dækning kun via dobbelt-listede founders; ellers **ærlig dødende**; ingen "ALLE"-claim.
2. **HIGH — aktiv-linje-kontekst load-bearing:** lavest-lokal vildleder efter fallback-klik. → §2: bær
   `activeCoord` i state, sæt fra klikket kort; driver naboer/fallback/labels.
3. **HIGH — mixed proven-kolonne-label udefineret:** → §5: kolonne-slægtled = `activeCoord.lokal ∓ depth`
   (aktiv-linjes generation), ikke per-kort-sammenblanding.
4. **MEDIUM — regressions-risiko ved generalisering:** → §3+§8: bevar source/lineage-match + fail-closed
   hop; eksplicitte v1-regressionstests.
5. **MEDIUM — peers bryder selectedId-kontrakt + mobil-anker ikke trykbart:** → §4: `focusId` styrer
   dominans/interaktion; mobil-anker får tryk-handler.
6. **MEDIUM — ubegrænset peer/fallback-kardinalitet:** → §4: cap K=7 + "+N flere"-udfold.
7. **LOW — "byte-identisk" upræcist:** → §6: navngiv de 4 delte funktioner + mekanisk paritets-test.
