# Review 23 — Web v4 slice 1: mega-menu-navigation (§3) + forside (§6)

**Dato:** 2026-07-09
**Scope:** uncommitteret diff i `web/src/` — ny mega-menu-navigation + forside-landing +
routing-omlægning. Implementerer de to første dele af design-briefet
`docs/design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md` og mockuppen
`Reventlow-web-v4.dc.html`. §4 (søgning-i-træ) og §5 (split-skærm) er bevidst udskudt.

**Ændrede filer:**
- `data/nav.ts` (NY) — `Mode`, `THEMES`, `themeOfMode`/`labelOfMode`, `parseFolgesvendPath`/`pathForMode`. Nøgleændring: `/` → `home` (var `tree`); `/stamtrae` = tree-uden-fokus; ukendt sti → `home`.
- `data/home.ts` (NY) — `curatedFounders`, `pickMaanedensGods` (rene, unit-testede).
- `components/HomeView.tsx` (NY) — forsiden.
- `components/primitives.tsx` — nye `PersonCard`, `SearchIcon`, `Crest`.
- `Folgesvend.tsx` — flad `NAV` → mega-menu-header (hover + intent-delay); ny `home`-gren; logo → forside.

---

## Phase 1 — Claude review (code-analyzer, fokuseret bug-hunt)

**Verdict: ingen correctness-bugs.** Alle 5 undersøgte risiko-områder rene:

1. **Routing cold-start & loops — REN.** `/` → `home` ved mount-init + path-sync-effekt.
   Home-guard (`if (p.mode !== 'tree') return`) sætter aldrig fokus-person. Invalid-id-
   redirect (`navigate(pathForMode('tree'))` → `/stamtrae` → `startFokus`) er et stabilt
   fixpunkt uden loop (alias→kanonisk er idempotent). Back/forward mellem `/`, `/stamtrae`,
   `/person/:id` holder mode+focusId konsistent.
2. **Hooks-regler — REN.** Begge `useMemo` i HomeView er ubetingede før `if (!model) return`.
   `activeTheme` er et plain funktionskald (ikke en hook) efter `if (err) return`. `megaOpen`/
   `megaTimer`/cleanup-effekt er ubetingede; timer-logikken er leak-sikker.
3. **State-konsistens — REN.** `goToMode('home')` navigerer korrekt + lukker mega. Live
   mega-punkter router + lukker; kommer-punkter er inerte. Søge-drawer/me-cirkel/login virker
   fra home; `DetailPanel` korrekt gated på `['tree','relate']`. Ingen rest-referencer til den
   fjernede `NAV` eller `'/'===tree`-antagelser.
4. **Deep-link-regression — REN.** `/person/:id`, `/estate/:id`, `Redaktion ↗` uændrede.
5. **`data/home.ts` edge-cases — REN.** `lineage` undefined, manglende `childIdx`, tom
   `persons`, null/tom `estates` — ingen crash; sikre fallbacks.

**Minor note (ikke en bug):** detalje-fetch (`Folgesvend.tsx:163`) fyrer på `focusId` uanset
mode → et spildt `fetchPersonDetail` hvis man har en bevaret `focusId` og går til `home`.
Nul brugereffekt (DetailPanel renderes ikke i home). Pre-eksisterende mønster.

---

## Phase 2 — Codex-trigger-beslutning: **SKIP**

Ingen trigger opfyldt: ingen executable recipe (R/bash/YAML), ingen cross-package-contract,
ingen CI-gate, ingen empirisk byte/race-claim, intet repeated-failure-pattern, ingen
clinical-data-semantik. **0 correctness-fund.** Routing-kontrakten (`/` = forside) er desuden
allerede verificeret **empirisk** (Playwright, se nedenfor), ikke kun argumenteret. At køre
Codex her ville være default-on-overhead uden ROI (skill-anti-pattern "Default-on Codex hver
cycle").

---

## Empirisk verifikation (Playwright mod prod-Supabase)

Alle grønne: (1) cold load `/` → forside m. hero + 4 kuraterede kort + "Nyt i arkivet";
(2) hover header → mega-menu m. tema-kolonner + live ✓ / kommer; (3) klik kurateret kort →
`/person/:id` (tree+detalje); (4) logo → tilbage til `/` forside; (5) deep-link `/person/:id`
lander i træet (ingen hero); (6) `/stamtrae` lander i træet. `tsc` + 235/235 vitest + `build`
grønne (før og efter /simplify).

## /simplify-runde (4 parallelle agenter) — anvendt

`SearchIcon`+`Crest`-primitiver (fjernede duplikeret SVG), `NytCard`-helper (fjernede
copy-paste-kort), `activeTheme`-hoist, `useMemo` i HomeView, `pathForMode('tree')` frem for
magic-string.

## Bevidste skips (med begrundelse)
- **Redundant-sort-nit** i `pickMaanedensGods` (estates ankommer sorteret): helperen er
  bevidst afkoblet fra upstream-sorteringsrækkefølge + unit-testet; O(n log n) over få godser
  er triviel.
- **`pathForLocation`-generalisering** (forward-path for `/person`+`/estate`): rører
  pre-eksisterende scattered literaler uden for slice-scope.
- **Detalje-fetch-guard** (minor note ovenfor): ville tilføje `mode` til dep-array og ændre
  fetch-timing (detalje-reload-flash ved retur til træet) for at spare et usynligt netværkskald.

## Udestår (næste slice)
§4 søgning-flyttet-ind-i-træet · §5 split-skærm træ+detalje. Se briefet §4-5.
