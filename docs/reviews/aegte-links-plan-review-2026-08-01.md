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
