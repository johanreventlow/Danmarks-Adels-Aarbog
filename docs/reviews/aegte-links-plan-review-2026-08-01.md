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

---

## Codex adversarial-review konsekvens (2026-08-01)

**Verdict: needs-attention** — én blocker, to HIGH, alle reproduceret.

Baseline før ændringer, kørt i worktreet: **55 testfiler, 637 tests, alle grønne.**

### Bekræftet (verificeret empirisk)

**B1 [BLOCKER] — `Link` stopper propagation for sent.** Planens snippet returnerer ved
modifier-klik *før* `stopPropagation()`. I `TreeView`, `BookmarksView` og `PersonFeedCardView`
ligger ankeret inde i et kort med egen `onClick`: et cmd-klik lader browseren åbne ny fane **og**
lader kortet navigere den aktuelle fane. Samme sker ved `defaultPrevented`.

Reproduktion (sonde `web/src/__tests__/tmp-blocker.test.tsx`, slettet igen — begge tests grønne):

```
✓ cmd-klik på navnet i et kort med egen onClick fyrer OGSÅ kortets navigation
✓ rettet udgave: stopPropagation FØR early-return holder forælderen urørt
```

Første test asserterer `expect(kortNavigerer).toHaveBeenCalledTimes(1)` — altså at fejlen er der.
Anden asserterer `not.toHaveBeenCalled()` med rettelsen. **Fix:** kald `e.stopPropagation()` som
allerførste sætning når proppen er sat, før `isModifiedClick`-tjekket.

**B2 [HIGH] — Planens påstand om uændret grøn suite er falsk.** Tre eksisterende tests forudsætter
rollen `button` på elementer planen gør til ankre:

- `components/__tests__/PersonFeedCardView.test.tsx:40` — `getByRole('button', { name: 'Åbn profil for Anna Reventlow' })`
  og forventer **3** aktiveringer (klik + Enter + Space). Et anker har rollen `link`, og **Space
  aktiverer ikke et anker** → tælleren bliver 2.
- `components/__tests__/PersonFeedCardView.test.tsx:97` — samme `getByRole('button', …)` for arkivkortet.
- `components/__tests__/OcrKildepanel.test.tsx:302` — `getByRole('button', { name: 'Åbn person' })`.

**Fix:** opdatér til `getByRole('link')`, assertér `href`, test klik + Enter, fjern Space-forventningen.

**B3 [HIGH] — Seks oversete kaldesteder med adresserbare mål.** Alle verificeret til stede:

| Sted | Handling i dag | Sti |
|---|---|---|
| `Folgesvend.tsx:427` | `navigateTree(meCanon)` (brugerens egen avatar) | `/person/<id>` |
| `HomeView.tsx:98` | `onOpenEstate(gods.id)` ("Månedens gods") | `/estate/<id>` |
| `PresensView.tsx:61` | `onPick(id)` ("Se fuld profil") | `/person/<id>` |
| `PersonKvalitetsark.tsx:339` | `onOpenPerson(row.personId)` | `/redaktion/person/<id>` |
| `Redaktion.tsx:2449` | `onOpen(String(r.personId))` (forældre-konflikt-rækker) | `/redaktion/person/<id>` |
| `RelateView.tsx:87` | `onPickStep(st.id)` (`focusOnly`, ingen navigation) | `/person/<id>` |

`RelateView` er særligt inkonsistent: speccens egen afgrænsning lover at `focusOnly`-links får et
`href`, men planen konverterer dem aldrig.

`OverviewMapView.tsx:46` navigerer via kort-rendererens `onPointPress`-callback og kan ikke levere
ankre — dokumenteres som teknisk undtagelse.

**B4 [MEDIUM] — P1 rekalibreret, men skærpet.** Codex' pointe om at `data/redaktionRead.ts` ikke er
et neutralt hjem holder — og er stærkere end antaget. `web/src/supabase.ts:7` kaster ved modul-load
uden `VITE_SUPABASE_*`, og worktreet har ingen `.env.local` (gitignoreret, følger ikke med):

```
FAIL  src/data/__tests__/redaktionRead.foraeldre.test.ts
Error: Mangler VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY.
 ❯ src/supabase.ts:8:9
 ❯ src/data/redaktionRead.ts:1:1
```

Efter kopiering af `web/.env.local` fra hovedmappen: 3/3 grønne. **Fix:** læg `sammeSomEtiket` i et
nyt Supabase-frit modul `web/src/data/sammeSom.ts`; tilføj `.env.local`-kopiering som trin 0.

**B5 [MEDIUM] — samme_som-forklaringen lover en foldning der kan udeblive.** Verificeret i
`Redaktion.tsx:2117-2119`:

```tsx
⚠ Foldes ikke endnu — {preview.grund}. Linket oprettes, men personerne vises separat
til konflikten er løst.
```

Et link kan altså eksistere uden foldning. Planens tekst "den post du redigerer foldes ind i denne"
er derfor for kategorisk. **Fix:** behold `KANONISK`/`ALIAS`, men skriv relationen frem for
resultatet: "den post du redigerer er markeret som alias for denne" / "markeret som alias for den
post du redigerer". Codex bekræftede desuden selve retnings-tabellen som korrekt.

**B6 [LOW] — linjedrift.** Uafhængig bekræftelse af mit eget P6: 917 / 1765 / 1806-1814 / 2047.
Codex bekræftede samtidig at `listRow` kun har en ikke-interaktiv `privat`-`span` som tail (hele
rækken må lovligt være anker), og at intet eksisterende `linkRow`-kald brydes af et valgfrit 6. argument.

**B7 [LOW] — Task 4's overskriftslinjer peger på de ydre kort** (139/166/185/206/215/230/249), mens
Step 5's linjer rammer navnene (142/170/188/208/219/234/251). Kun navnene må være ankre.

**B8 [LOW] — feed-testfixtures bruger `as never`**, hvilket skjuler fixturefejl, og `forbundet`
testes ikke. Codex bekræftede at switchens 13 cases er udtømmende mod `FeedCard`-unionen
(`packages/feed/src/types.ts:49`), og at `null` er korrekt for `slaegt`/`samle`/`forbundet`.

### Afvist

- **P2** (`React.CSSProperties` → TS2686): Codex nåede uafhængigt samme konklusion som min egen
  fase 1b. Mit oprindelige fund var forkert.
- **P3** (beregnet modifier-nøgle): Codex fandt at `@testing-library/dom` typer event-options som
  `{}`, ikke `MouseEventInit` (`types/events.d.ts:94`) — udtrykket typechecker. Dertil kommer min
  egen observation at `web/tsconfig.json` ekskluderer `src/**/__tests__/**` helt. To uafhængige
  grunde til at fundet ikke holder.

### Inferred (plausibelt, ikke reproduceret)

- **`target`-attributten:** props-typen tillader ikke `target` i dag, så scenariet er hypotetisk.
  Forslaget om at basere props på `AnchorHTMLAttributes<HTMLAnchorElement>` er alligevel en
  forenkling (fjerner den håndlistede `title`/`aria-label`-flade), og guarden er én linje. Tages med
  som design-forbedring, ikke som fejlrettelse.

### Impact-buckets (verificerede fund)

| Bucket | Antal | Hvilke |
|---|---|---|
| Hard runtime-crash | 0 | — |
| Semantisk fejl / forkert adfærd | 2 | B1 (dobbelt-navigation), B5 (lover foldning) |
| Falsk tryghed / proces | 3 | B2 (påstået grøn suite), B4 (test kan ikke køre), B6 (linjedrift) |
| Manglende dækning | 1 | B3 (seks kaldesteder) |
| Sub-optimalt / oprydning | 2 | B7, B8 |

### Læring

**En anker-primitiv har to klik-veje, ikke én.** Det rene venstreklik er det man designer og tester;
modifier-vejen er den man glemmer — og netop dér er `stopPropagation` stadig nødvendig, selv om
appen ikke selv navigerer. Enhver "afgiv klikket til browseren"-tidlig-returnering skal spørge:
hvad gør de omsluttende handlers imens?
