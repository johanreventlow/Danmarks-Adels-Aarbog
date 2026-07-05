# Design: Generations-browser v2 — bidirektionel + slægtled-naboer + kombinerede labels

**Dato:** 2026-07-05
**Status:** Design — afventer bruger-review
**Bygger på:** v1 (`2026-07-05-generations-reparation-design.md`, PROD-LIVE + merget PR #19)
**Branch:** `feat/generations-browser-v2`
**Anledning:** empirisk UI-test af v1 afdækkede 3 sammenhængende punkter (bruger, 2026-07-05).

---

## 1. Mål

Gør v1's aner-hul-reparation til en fuld **generations-browser**: `N−1 ← [N: fokus + naboer] → N+1`.
Tre ændringer, alle på den delte, dual-reviewede træ-bygger (`buildDirection`/`fallbackAncestorRing`
+ labels, web `tree.ts` + mobil `selectors.ts`, byte-identisk) og de to UI-lag.

## 2. Invarianter (uændret fra v1)

- Fallback-ringe (aner OG efterkommer) + slægtled-naboer er **rene read-time projektioner**. Klik
  **re-ankrer** (web `onFocus`, mobil `setFocus`) — skriver ALDRIG en `relation`/`fact`/`visning_*`.
- `web/mobile` `generations.ts` + `fallbackAncestorRing`-familien forbliver **byte-identiske**.
- Fail-closed founder-hop bevares. TDD; ingen regression på v1-tests.

## 3. Ændring A — efterkommer-fallback (symmetrisk)

Når efterkommer-ringen (`childrenOf`) er tom, byg en **efterkommer-fallback-ring** = alle personer
ved `slaegtled_lokal = G+1` i den aktive linje (spejl af aner-fallback'en).

- **Ingen særlig "ned-hop":** en gren-stamfar optræder allerede i BEGGE linjer via `samme_som`
  (fx Conrad = III-lokal-12 = V-lokal-1). Så same-line G+1 inkluderer naturligt de founders der
  fører linjen videre; at klikke en founder re-ankrer, hvorefter dens anden linje-koordinat overtager.
  Cross-line-nedstigning kræver derfor ingen egen hop-regel i v2. (Symmetrisk til at multi-niveau
  aner-hop blev udskudt — samme begrundelse.)
- Delt kerne: generaliser `previousAncestorGen` → en retnings-parametriseret
  `adjacentGen(coords, linje, lokal, dir)` hvor `dir=-1` (aner, med founder-hop) og `dir=+1`
  (efterkommer, ren G+1 i linjen). `fallbackAncestorRing` generaliseres tilsvarende til
  `fallbackRing(model, genCoords, anchorId, cur, depth, dir)` og bygges i BEGGE retninger i
  `buildDirection` (kun når den beviste ring er tom).

## 4. Ændring B — slægtled-naboer i fokus-kolonnen

Fokus-kolonnen (`anchor:0`) viser i dag kun fokus-personen. Udvid til: **fokus dominant + alle andre
personer i samme slægtled (aktiv linje) som dæmpede sekundære kort**, der kan klikkes (re-ankrer).

- **Aktiv koordinat:** en person kan have flere linje-koordinater (founder). Vælg deterministisk den
  med lavest `lokal` som "aktiv" (samme valg som fallback-ringen bruger), så naboer, fallback-retning
  og labels alle er drevet af ÉN konsistent linje-kontekst. (Fuld "husk ankomst-linje ved drill" er en
  senere polish — noteret.)
- **Naboer:** `model.persons` filtreret til samme `(sourceId, lineageId, lokal)` som fokus' aktive
  koordinat, minus fokus selv. `TreeColumn.people` for ankeret bliver `[fokus, ...naboer]`;
  `selectedId = fokus`. Nyt felt `TreeColumn.peers?: ModelPerson[]` ELLER `focusId` så UI kan
  rendere fokus dominant og naboer dæmpet. (Vælg `focusId: string` på ankeret + behold alle i
  `people`; UI styrer dominans via `p.id === col.focusId`.)
- **Tom-tilfælde:** hvis fokus ingen aktiv koordinat har (spouse/NULL), er `peers` tom → kolonnen
  opfører sig som i dag (kun fokus). Ingen regression.

## 5. Ændring C — kombinerede kolonne-overskrifter

Én gennemgående akse (slægtled) + intuitivt slægtskabs-cue nær fokus.

- **Ankeret:** `"<slægtled>. slægtled · <linje>-linjen"` (fokus' aktive koordinat).
- **Bevist aner/efterkommer-kolonne ved dybde d:** `"<slægtskab> · <slægtled>. slægtled"` hvor
  `<slægtskab>` = eksisterende relative ord (Forældre/Bedsteforældre/Oldeforældre/Tipoldeforældre |
  Børn/Børnebørn/Oldebørn/Tipoldebørn) for d≤4, og **droppes** for d≥5 → bare `"<slægtled>. slægtled"`
  (afskaffer "N× Tipoldeforældre").
- **Slægtled pr. kolonne:** læs det FAKTISKE slægtled fra kolonnens personers `genCoords` (aktiv linje,
  delt generation); fald tilbage til `anker_slægtled ∓ d` hvis ukendt; fald tilbage til rent
  slægtskabs-ord hvis anker-slægtled også er ukendt (fuld v1-kompatibilitet når ingen generation-data).
- **Fallback-kolonne:** `"muligt · <slægtled>. slægtled · <linje>-linjen"` (som v1, men "muligt"-prefix
  gør ubevist-status eksplicit i samme format).
- Ren helper `columnLabel(kind, depth, slaegtled, linje, fallback)` — testbar isoleret, spejlet
  web+mobil.

## 6. Filer der røres

- `web/src/data/generations.ts` + `mobile/…` (byte-identisk): `adjacentGen` (retnings-generaliseret).
- `web/src/data/tree.ts` + `mobile/src/data/selectors.ts` (byte-identisk fallback/label-kerne):
  `fallbackRing` (bidirektionel), anker-peers, `columnLabel`, `TreeColumn` (+`focusId?`,
  behold `fallback/genLabel/kuldGroups`).
- `web/src/Folgesvend.tsx` + `mobile/src/app/(tabs)/tree.tsx`: render dæmpede peer-kort +
  kombinations-labels; efterkommer-fallback-styling (genbrug aner-fallback-stil).
- Ingen DB-ændring (al data findes fra v1).

## 7. Åbne/udskudte

- "Husk ankomst-linje" (aktiv koordinat = den linje man drillede via, ikke bare lavest lokal) — polish.
- Multi-niveau aner-hop + cross-line efterkommer-hop — fortsat v-næste (ureachable i single-source).

## 8. Test

Rene enheder: `adjacentGen` begge retninger + founder-hop; `columnLabel` alle grene (d≤4, d≥5,
fallback, ukendt slægtled → kinship-only); `fallbackRing` efterkommer-retning; anker-peers (inkl.
tom-tilfælde). Web+mobil spejlet. v1-tests skal forblive grønne. Empirisk: browser + enhed.
