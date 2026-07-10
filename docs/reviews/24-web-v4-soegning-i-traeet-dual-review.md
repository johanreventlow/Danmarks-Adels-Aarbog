# Review 24 — Web v4 slice 2: §4 søgning flyttet ind i stamtræet

**Dato:** 2026-07-09
**Scope:** uncommitteret §4-diff i `web/src/` — person-søgning flyttet fra en modal drawer ind i
stamtræet (søgefelt + universel-klart fane-bånd + browse-værktøjer + personkort-resultater), samme
`TreeSearch` genbrugt i Slægtskab (relate) til A/B-valg, drawer retireret. Implementerer §4 (+ §5.6-
integrationen) af `docs/design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md`.

**Ændrede filer:** `Folgesvend.tsx` (ny `TreeSearch` + `TreeSearchBundle`, drawer-fjernelse, RelateView-
integration, `clearSearch`-helper, bmOnly-browse-filter), `data/browse.ts` (`showSearchResults`),
`components/primitives.tsx` (fjernet ubrugt `SidebarMiniRow`), `__tests__/treeSearch.test.ts` (ny).

---

## Phase 1 — Claude review (code-analyzer, fokuseret bug-hunt)

**2 fund; kernen (søge-/relate-flow, gating, memo) ren.**

- **M1 (reel bug — RETTET + verificeret):** søgefeltet auto-fokuserede ved *enhver* tree/relate-entry
  efter første brug af header-⌕. Rodårsag: `searchFocusToken` er en monoton tæller (>0 permanent), og
  `TreeSearch` re-mountes ved hvert mode-skift → mount-effekten `if (focusToken > 0) focus()` stjal
  fokus selv når brugeren blot klikkede "Find slægtskab". **Fix: consume-and-reset** — fokusér ved et
  bump og nulstil straks tokenet (`resetFocus` i bundlet). Empirisk verificeret (Playwright, SPA-
  history-nav): fokus KUN ved ⌕ (frisk load / SPA→relate uden ⌕ / SPA-re-entry efter ⌕ = ingen fokus;
  ⌕ genudløser korrekt).
- **M2 (design, ikke bug — BEVIDST pr. planen):** standalone `BookmarksView`/`mode='bookmarks'` er nu
  kun URL-tilgængelig (bmQuick-indgangen forsvandt med draweren). Dette er den **planlagte** tilstand:
  bogmærke-adgang sker nu via bmFilter-chippen i tree-søgningen (§9.e), og den dedikerede liste gen-
  hjemmes i en fremtidig konto-klynge (§7). Ingen handling; ikke dødt (URL virker).

**Verificeret rent:** RelateView-fragment-gating (3 rel-paneler i én `{!showResults && (<>…</>)}`, A/B-kort
+ TreeSearch uden for gaten) balanceret; relate-flow (pick A→clear→pick B→sti) uden stuck-state; browse-
memo (`bmDep = bmOnly ? bookmarkIds : null`) uden stale-filter; mega-panel `pointerEvents:none` når lukket
(ingen klik-opsnapning); ingen rest-referencer til fjernede drawer-symboler.

## Phase 2 — Codex-trigger: **SKIP**

Ingen trigger opfyldt: ingen executable recipe, cross-package-contract, CI-gate, empirisk byte/race-claim,
repeated-failure-pattern eller clinical-data. M1 (React-fokus-bug) og M2 (planlagt design) er begge
verificeret/afklaret empirisk hhv. mod planen — ikke claims der kræver Codex' fix-recipe-verifikation. At
køre Codex ville være default-on-overhead uden ROI.

## /simplify-runde (4 parallelle agenter) — anvendt

`clearSearch()`-helper (fjernede tredoblet, drivende reset i navigateTree/pickPerson/X-knap — højeste ROI);
RelateViews 3 `!showResults`-gates → én wrapper; bogmærke-filter-chip bruger nu den kanoniske
`BookmarkFlag`-ribbon-form (var en divergerende inline-SVG); browse-memo `bmDep` (bogmærke-toggles re-kører
ikke browse når filteret er slukket); fjernet ubrugt `SidebarMiniRow` + forældede kommentarer.
**Skippet (pre-eksisterende/uden for scope):** ekstraktion af segmented-control/alfabet-hop til delt primitiv;
flyt `LinjeChip` → primitives (defer); `onPick` til render-sites (kræver plumbing af fillSlot ind i RelateView).

## Empirisk verifikation (Playwright mod prod-Supabase)

Alle grønne: søg i træ → personkort-resultater (træ-body skjult) → vælg kort → `/person/:id` + søgning ryddet
+ træ tilbage; "Gennemse hele slægten" → 850 kort m. A–Å/Født/alfabet/linje-chip; header-⌕ + forside-hero →
tree-søgning fokuseret; relate: søg → 16 kort → vælg → A-plads fyldt + søgning ryddet; M1 consume-and-reset.
`tsc` + **240/240 vitest** + `build` grønne (før og efter /simplify + M1-fix).

## Udestår (næste slice)
§5 split-skærm træ+detalje. "Kommer"-faner i fane-båndet (Godser/Steder/Artikler-søgning) er kun placeholders.
