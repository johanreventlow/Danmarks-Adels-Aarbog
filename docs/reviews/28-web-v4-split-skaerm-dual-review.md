# Review 28 — Web v4 slice 3: §5 split-skærm (træ + detalje)

**Dato:** 2026-07-10
**Scope:** uncommitteret §5-diff i `web/src/` — detalje-panelet gøres URL-drevet: `/person/:id` =
detalje åben (~50/50 med træet), `/stamtrae` = fuldt-bredt træ uden detalje; luk navigerer til
`/stamtrae` (`replace`). Følger UX-review 26 anbefaling 6 ("URL'en ER split-tilstanden"). Bevarer
begge træ-varianter (§5.5) og relate's egen detalje (§5.6).

**Ændrede filer:** `data/nav.ts` (ny `detailOpenFor`-helper), `Folgesvend.tsx` (URL-drevet gate,
`closeDetail`/`treePick`/Escape, path-sync centrum-bevaring, `DetailPanel.onClose` + × Luk),
`components/Lightbox.tsx` (`data-overlay`-markør), `__tests__/nav.test.ts` (detailOpenFor).

---

## Phase 1 — Claude review (code-analyzer, fokuseret bug-hunt)

**2 reelle Medium-fund; begge fra én ubetinget window-Escape-listener — RETTET + verificeret.**

- **M6 (relate-eject — RETTET):** Escape kaldte `closeDetail` uanset mode → i Slægtskab
  navigerede Escape til `/stamtrae` og kastede brugeren ud af relate (selvom × korrekt er skjult
  for relate). **Fix:** gate Escape-effekten på `mode === 'tree'` (spejler `onClose`-proppen).
  Verificeret: Escape i `/relate` bliver i relate.
- **M5 (Escape over-lukker — RETTET):** window-Escape-listeneren koordinerede ikke med (a) billede-
  `Lightbox` (eget `zIndex:300`-overlay med egen Escape, renderet inde i DetailPanel — Escape lukkede
  BÅDE billedet og hele detaljen) eller (b) tekstfelter (Escape i tree-søgefeltet lukkede detaljen).
  **Fix:** handler bail'er hvis `e.target` er `INPUT`/`TEXTAREA`, og hvis et `[data-overlay]` er åbent
  (markør tilføjet på Lightbox-roden). Verificeret empirisk: Escape i søgefelt → detalje bliver;
  regression (Escape uden overlay/felt) → lukker. Lightbox-grenen verificeret ved konstruktion
  (`querySelector('[data-overlay]')`-guard + markør, tsc-bekræftet) — kunne ikke udøves empirisk da
  testpersonerne mangler rigtige medier.

**Verificeret rent (1-4):** cold start (`focusId` null-guardet i TreeView + DetailPanel-gate);
luk bevarer centrum (`setFocusId(cur => cur ?? startFokus)`); `treePick`-toggle (`canon(id) ===
focusId`, kun TreeViews onPick — panelets relations-klik navigerer stadig); mode/path-lag benignt
(én frame, samme mønster som den eksisterende center-switch).

## Phase 2 — Codex-trigger: **SKIP**

Ingen trigger (ingen recipe/contract/CI-gate/byte-race/repeated-failure/clinical-data). M5/M6 er
React-event-koordinering, rettet og verificeret empirisk/ved konstruktion — ikke claims der kræver
Codex' recipe-verifikation. Default-on ville være overhead uden ROI.

## /simplify

Fokuseret four-angle self-review af de ~40 linjer (proportionalt til scope): **ren, intet anvendt.**
`detailOpenFor` bor ved routingen i `nav.ts`; `closeDetail` genbruger `pathForMode`; ingen redundant
state (detailOpen afledes); × Luk-glyfen er et pre-eksisterende ad-hoc luk-mønster (ingen delt primitiv).

## Empirisk verifikation (Playwright mod prod-Supabase)

Alle grønne: `/stamtrae` fuldt-bredt træ uden detalje → klik person → `/person/:id` + ~50/50 detalje →
× Luk / Escape / klik-valgt-igen → `/stamtrae`, detalje væk, træet bliver stående; deep-link
`/person/:id` åbner med detalje; søge-resultater fuld bredde når lukket; relate uændret; M5/M6-fixes.
`tsc` + **243/243 vitest** + `build` grønne.

## Udestår (fast-follows)
- Mega-menu klik/keyboard-aktivering (review 26 anbef. 2, HØJ — bruger-udskudt til egen slice).
- Konto-klynge med Bogmærker-indgang (review 26 anbef. 3 / review 24 M2).
- Smal/touch-browser stak-fallback (§5.4).
