# Review: spec + plan for ægte links (feat/aegte-links)

**Dato:** 2026-08-01 · **Genstand:** `docs/superpowers/specs/2026-08-01-aegte-links-og-samme-person-design.md` +
`docs/superpowers/plans/2026-08-01-aegte-links-og-samme-person.md` · **Ingen kode skrevet endnu.**

Fase 1 (egen gennemgang) nedenfor; Codex adversarial-review og reconcile følger.

## P1 [HIGH] — `sammeSomEtiket` i `Redaktion.tsx` gør enhedstesten upraktisk

**Lokation:** plan Task 3, Step 1 + Step 3.

**Symptom:** Planen eksporterer `sammeSomEtiket` fra `web/src/Redaktion.tsx` og importerer den i en
ny testfil. `Redaktion.tsx` trækker hele data-laget (auth, Supabase-klient, ~20 fetch-funktioner)
ind ved modul-load.

**Verifikation:** `web/src/__tests__/Redaktion.kvalitetsark.test.tsx:14-40`:

```tsx
const mocks = vi.hoisted(() => ({
  currentSession: vi.fn(), signIn: vi.fn(), signOut: vi.fn(),
  fetchRedaktionPersoner: vi.fn(), fetchSources: vi.fn(), fetchPersonEvidence: vi.fn(),
  … 20 funktioner …
}));
vi.mock('../data/auth', () => ({ … }));
```

Enhver test der importerer `Redaktion` må gentage den mock-blok.

**Konsekvens:** En 12-linjers ren enhedstest ville kræve ~40 linjers mock-stillads — eller ende
med at ramme prod-Supabase.

**Foreslået fix:** Læg `sammeSomEtiket` i `web/src/data/redaktionRead.ts` umiddelbart efter
`mapSammeSomLinks` (linje 711-720) — samme domæne, samme `retning`-vokabular. Modulet importeres
allerede direkte af tests (`data/__tests__/redaktionRead.foraeldre.test.ts`). Testen lægges i
`web/src/data/__tests__/redaktionRead.sammesom.test.ts` efter samme navnekonvention.

## P2 [MEDIUM] — `React.CSSProperties` i `TreeView.tsx` uden React-navnerum

**Lokation:** plan Task 4, Step 5 (`navnLink`-hjælperen).

**Symptom:** Hjælperen typer sit `style`-argument som `React.CSSProperties`, men `TreeView.tsx:7`
importerer kun hooks:

```tsx
import { useLayoutEffect, useEffect, useMemo, useRef, useState } from 'react';
```

Der er ingen `React`-binding i filen, og projektet bruger den automatiske JSX-runtime.

**Konsekvens:** `error TS2686: 'React' refers to a UMD global, but the current file is a module`.

**Foreslået fix:** `import type { CSSProperties } from 'react';` og brug `CSSProperties`.

## P3 [MEDIUM] — `it.each` med beregnet modifier-nøgle kan ikke type-checkes

**Lokation:** plan Task 1, Step 1.

**Symptom:**

```tsx
fireEvent.click(screen.getByText('Navn'), { [modifier]: true });
```

`modifier` er en `string` fra `it.each`, så objekt-literalen får typen `{ [x: string]: boolean }`.

**Konsekvens:** Risiko for typefejl mod `MouseEventInit`; testfilen indgår i `tsc --noEmit`.

**Foreslået fix:** Skriv de fire modifier-tilfælde eksplicit (`{ metaKey: true }`, `{ ctrlKey: true }`,
`{ shiftKey: true }`, `{ altKey: true }`). Fire linjers gentagelse er billigere end en type-gymnastik.

## P4 [LOW] — Forventet jsdom-støj i modifier-testene

**Lokation:** plan Task 1, Step 1 + Step 4.

**Symptom:** Når `preventDefault()` bevidst IKKE kaldes, følger jsdom hyperlinket og skriver
`Not implemented: navigation (except hash changes)` til konsollen.

**Konsekvens:** Ingen — testen består. Men en implementer der ikke ved det, jagter et fantom.

**Foreslået fix:** Én kommentarlinje i testfilen der siger at støjen er forventet og beviser at
browseren fik klikket.

## P5 [LOW] — Planen dækker feed-kort, som speccen ikke nævner

**Lokation:** plan Task 6 vs. spec §3.

**Symptom:** Speccens konverteringsliste stopper ved `EstatesView`; planen tilføjer forsidens
feed-kort (`components/feed/`).

**Konsekvens:** Scope-udvidelse ift. det godkendte design — brugeren bør bekræfte, ikke opdage det.

**Foreslået fix:** Nævn udvidelsen eksplicit ved fremlæggelse; Task 6 kan droppes uden at røre
Task 1-5.

---

## Fase 1b — empirisk verifikation (2026-08-01, kørt i worktreet)

### P6 [HIGH] — Alle `Redaktion.tsx`-linjenumre stammer fra den beskidte hovedmappe

**Symptom:** Spec og plan blev skrevet ud fra `/Users/johanreventlow/TypeScript/danmarksadelsaarbog`,
hvor en parallel session har ucommittede ændringer i `web/src/Redaktion.tsx` (branch
`feat/union-redigering`). Branchen `feat/aegte-links` er brancet fra `origin/main` — samme fil,
andre linjenumre.

**Verifikation:** `grep -n` i worktreet mod `grep -n` i hovedmappen:

| Element | plan (beskidt træ) | `origin/main` |
|---|---|---|
| `listRow` | 921-930 | **917-926** |
| `linkRow` | 1769-1781 | **1765-1777** |
| partner-navn | 1795 | **1791** |
| børne-rækkens `linkRow`-kald | 1823/1831 | **1806/1814** |
| forældre-navn | 1841 | **1824** |
| "Samme person"-blok | 1862-1867 | **1845-1850** |
| beslutnings-link (`<a href={decision.route}`) | 2065 | **2047** |
| narrativ-preview | 1308 | 1308 (uændret) |

Alle øvrige filer (`Folgesvend.tsx:429`, `OcrKildepanel.tsx:280`, `DetailPanel.tsx:111/170/181`,
`EstatesView.tsx:62/104`, `BookmarksView.tsx:55`, `HomeView.tsx:90`) er urørte af den parallelle
session og har de linjenumre planen angiver.

**Konsekvens:** Implementeren rammer forkerte linjer i den ene fil hvor præcision betyder mest —
og det er samme fil den parallelle session vil skulle merge med.

**Fix:** Erstat tabellens venstre kolonne med højre i både spec og plan.

### P2 — AFVIST (min egen fejl)

Påstanden var at `React.CSSProperties` i `TreeView.tsx` ville give `TS2686`. Forkert: TS2686 rammer
kun **værdi**-referencer til en UMD-global. I typeposition er det lovligt, og kodebasen gør det
allerede uden React-import — `components/primitives.tsx:92` (`style?: React.CSSProperties`) og
`Redaktion.tsx:2283` (`const inp: React.CSSProperties`). `import type { CSSProperties }` er
stadig at foretrække (`TreeSearch.tsx:6` gør det), men det er stil, ikke fejl.

### P3 — REKALIBRERET til LOW

`web/tsconfig.json` har `"exclude": ["src/**/__tests__/**"]` — testfiler typecheckes slet ikke af
`tsc --noEmit`, og vitest/esbuild typechecker heller ikke. Den beregnede modifier-nøgle kan altså
ikke fejle nogen gate. Fire eksplicitte tilfælde er stadig tydeligere at læse.

### P4 — BEKRÆFTET, ordlyd rettet

Sonde kørt i worktreet (`web/src/__tests__/tmp-probe.test.tsx`, slettet igen):

```
✓ src/__tests__/tmp-probe.test.tsx (3 tests) 34ms
stderr | src/__tests__/tmp-probe.test.tsx
Not implemented: navigation to another Document
```

Den præcise ordlyd er `Not implemented: navigation to another Document` (ikke
"navigation (except hash changes)").

### Verificerede antagelser bag Task 1's testsuite

Samme sonde bekræftede alle tre præmisser empirisk:

1. `fireEvent.click(el)` returnerer **`false`** når `preventDefault()` blev kaldt og **`true`** når
   det ikke blev — som testene i Task 1 antager.
2. `fireEvent.click(el, { metaKey: true })` når frem til handleren med flaget sat.
3. `fireEvent.click(el, { button: 1 })` når frem med `e.button === 1`.

### Infrastruktur-note

Worktreet manglede `node_modules`; `npm ci` kørt (1248 pakker, 20 s). Uden det fejler enhver
`npm run test -w web` i worktreet med en uløselig `@testing-library/react`-import. Bør stå som
trin 0 i planen.
