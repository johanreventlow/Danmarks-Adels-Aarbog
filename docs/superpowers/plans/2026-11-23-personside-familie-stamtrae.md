# Personside og stamtræ: fire justeringer — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personsiden og stamtræet viser livsdatoer med \*/†, vielsesdato med ⚭, »kun i«-børn som grå tekst uden for
deres udgave, og stamtræets børn i bogens rækkefølge.

**Architecture:** To rene funktioner i den delte kerne (`packages/core`: livsdato-formattering og vielses-formattering)
og én sortering i stamtræets kolonnebygger (kernen, så web og mobil får den). Web: en lille læsefunktion for
vielsesdatoer (fact → conclusion → assertion, eksisterende RLS-læsning), og PersonSide's familieliste bruger dem.

**Tech Stack:** TypeScript, React 18, Vitest (core + web), Jest (mobil), Supabase JS.

**Spec:** `docs/superpowers/specs/2026-11-23-personside-familie-stamtrae-design.md`

## Global Constraints
- Ingen DB-ændring, ingen ny RPC. Læsning sker via tabellerne `fact`/`conclusion`/`assertion`, som anon og
  authenticated må læse (RLS `entitet_offentlig`).
- Livsdato-former (præcis): `* 1671 † 1738` · `* 1640` · `† 1708` · `† ung` · `* 1688 † lille`; floruit uændret
  (`Nævnes 1671`). Ét almindeligt mellemrum mellem tegn og værdi og mellem de to dele.
- Vielses-former (præcis): `⚭ 18. nov. 1670` (dato kendt) · `⚭ 1670` (kun året) · intet (ukendt).
  Månedsnavne: `jan.`, `feb.`, `marts`, `april`, `maj`, `juni`, `juli`, `aug.`, `sept.`, `okt.`, `nov.`, `dec.`
- Kommentarer, testnavne og commit-beskeder på dansk; Conventional Commits (`type(scope): kort beskrivelse`).
- Commit pr. task; ingen push før hele planen er færdig og verificeret.

## Review Focus
1. **Livsdato med præfiks i rå data** (`visning_doed = '† ung'`, `visning_foedt = '* 1640'`): ét tegn, aldrig `† † ung`
   → testet i Task 1.
2. **Vielse med upræcist interval** (`date_min` 1652-01-01, `date_max` 1652-12-31; eller to forskellige år; eller
   `date_min` null — 22 af 472 i prod): år hhv. intet, aldrig en forkert dag → testet i Task 3.
3. **Ægtefælle uden person-id** (kun navn, `sp.id` null) eller ægteskab uden vielsesfakta: ingen ⚭, intet crash →
   testet i Task 4.
4. **Udgavevælger mangler** (personen findes kun i én udgave): »kun i«-barn er stadig et link → testet i Task 5.
5. **Barn uden bognummer i stamtræet** (ægtefælles barn, ingen `bogNrBy`): falder tilbage til eksisterende
   `sorterBoernEfterBogen`-fallback, ingen undtagelse → testet i Task 2.

---

### Task 1: \* og † i livsdatoer (kerne)

**Files:**
- Modify: `packages/core/src/fields.ts:19-28` (`fmtYears`)
- Test: `packages/core/src/__tests__/fields.test.ts`
- Modify (forventninger der låser den gamle form): tests i `packages/core`, `web/src`, `mobile/src`, der indeholder
  `'–'` mellem to livsår fra `fmtYears`/`fmtVisningsAar` — find dem ved at køre suiterne.

**Interfaces:**
- Produces: `fmtYears(f: string | null | undefined, d: string | null | undefined): string` (samme signatur, ny form).
  `fmtVisningsAar` kalder den uændret.

- [ ] **Step 1: Skriv de fejlende tests** i `fields.test.ts` (`describe('fmtYears — * og †')`):
  ```ts
  expect(fmtYears('1671', '1738')).toBe('* 1671 † 1738');
  expect(fmtYears('21. juni 1671', '1. okt. 1738')).toBe('* 21. juni 1671 † 1. okt. 1738');
  expect(fmtYears('1640', null)).toBe('* 1640');
  expect(fmtYears(null, '1708')).toBe('† 1708');
  expect(fmtYears(null, '† ung')).toBe('† ung');
  expect(fmtYears('1688', '† lille')).toBe('* 1688 † lille');
  expect(fmtYears('* 1640', '† 1708')).toBe('* 1640 † 1708');
  expect(fmtYears(null, null)).toBe('');
  expect(fmtVisningsAar(null, null, '1671')).toBe('Nævnes 1671');
  ```
- [ ] **Step 2:** `npm run test -w @daa/core -- fields` → FAIL (`1671–1738` ≠ `* 1671 † 1738`).
- [ ] **Step 3:** Ret `fmtYears`: begge → `'* ' + F + ' † ' + D`; ellers som i dag.
- [ ] **Step 4:** `npm run test -w @daa/core` → PASS. Kør derefter `npm run test -w web` og `npm test -w mobile`;
  opdatér kun forventninger, der låser den gamle livsdato-form (ikke andre fejl).
- [ ] **Step 5: Commit** — `feat(core): livsdatoer vises med * og † i stedet for bindestreg`

### Task 2: Stamtræets børn i bogens rækkefølge (kerne)

**Files:**
- Modify: `packages/core/src/tree.ts:145` (`buildDirection`)
- Test: `packages/core/src/__tests__/tree.test.ts`

**Interfaces:**
- Consumes: `sorterBoernEfterBogen(boern, foraelderId, model.bogNrBy, model.udgaver)` fra `./bogensOrden`.
- Produces: `buildBidirectionalColumns` uændret signatur; efterkommer-kolonnernes `people` står i bogens orden.

- [ ] **Step 1: Skriv den fejlende test** `'efterkommere står i bogens rækkefølge, også børn uden fødselsår'`: model
  med forælder P og tre børn, hvor `childIdx` indsætter dem i rækkefølgen C(born 1671, nr 3), A(born null, nr 2),
  B(born 1690, nr 4) og `bogNrBy` giver nr 2, 3, 4 i samme udgave; forvent første efterkommer-kolonnes
  `people.map(p => p.id)` = `['A','C','B']`. Anden test: uden `bogNrBy` → ingen undtagelse, orden = fallback.
- [ ] **Step 2:** `npm run test -w @daa/core -- tree` → FAIL.
- [ ] **Step 3:** I `buildDirection`: for `kind === 'descendant'` send `traverse(model, cur)` gennem
  `sorterBoernEfterBogen(…, cur, model.bogNrBy, model.udgaver)` før `.filter`; aner-retningen uændret.
- [ ] **Step 4:** `npm run test -w @daa/core` → PASS; `npm run test -w web -- TreeView` og
  `npm test -w mobile -- tree` → PASS.
- [ ] **Step 5: Commit** — `fix(core): stamtræets børn følger Aarbogens rækkefølge`

### Task 3: Vielses-formattering (kerne)

**Files:**
- Create: `packages/core/src/vielse.ts`
- Modify: `packages/core/src/index.ts` (eksport)
- Test: `packages/core/src/__tests__/vielse.test.ts`

**Interfaces:**
- Produces: `fmtVielse(dateMin: string | null, dateMax: string | null): string` — ISO-datoer (`YYYY-MM-DD`) ind;
  `'⚭ 18. nov. 1670'`, `'⚭ 1670'` eller `''`.

- [ ] **Step 1: Skriv de fejlende tests:**
  ```ts
  expect(fmtVielse('1670-11-18', '1670-11-18')).toBe('⚭ 18. nov. 1670');
  expect(fmtVielse('1681-05-01', '1681-05-01')).toBe('⚭ 1. maj 1681');
  expect(fmtVielse('1754-09-12', '1754-09-12')).toBe('⚭ 12. sept. 1754');
  expect(fmtVielse('1652-01-01', '1652-12-31')).toBe('⚭ 1652');
  expect(fmtVielse('1652-03-01', '1653-02-28')).toBe('');
  expect(fmtVielse(null, null)).toBe('');
  expect(fmtVielse('1670-11-18', null)).toBe('');
  ```
- [ ] **Step 2:** `npm run test -w @daa/core -- vielse` → FAIL (modul findes ikke).
- [ ] **Step 3:** Implementér: ens datoer → `⚭ D. <måned> ÅÅÅÅ` (dag uden foranstillet nul, månedsnavne fra Global
  Constraints); samme år → `⚭ ÅÅÅÅ`; ellers `''`. Parse ISO-strengen direkte (ingen `Date`, undgår tidszone).
- [ ] **Step 4:** `npm run test -w @daa/core` → PASS.
- [ ] **Step 5: Commit** — `feat(core): fmtVielse formaterer vielsesdato med ⚭`

### Task 4: ⚭ ved ægtefællen på personsiden (web)

**Files:**
- Create: `web/src/data/vielser.ts`
- Test: `web/src/data/__tests__/vielser.test.ts`
- Modify: `web/src/components/PersonSide.tsx:206-220` (»Gift med«)
- Test: `web/src/components/__tests__/PersonSide.test.tsx`

**Interfaces:**
- Consumes: `fmtVielse` (Task 3); `familieIderForPerson(model.indexes, focusId).aegteskaber`
  (`{ spouseId: string | null; familyId: string }[]`, `packages/core/src/familieKilder.ts`).
- Produces: `hentVielsesDatoer(familyIds: string[]): Promise<Record<string, string>>` — nøgle = family-id, værdi =
  færdig tekst fra `fmtVielse` (tomme udeladt). Tre læsninger: `fact` (`subjekt_type='family'`,
  `faktatype='vielse'`, `subjekt_id in familyIds`) → `conclusion` (`target_type='fact'`, `status in
  ('afklaret','omstridt')`, `valgt_assertion_id`) → `assertion` (`id,date_min,date_max`). Ingen kald ved tom liste.
  Enhver fejl → `{}` (siden viser bare ingen ⚭; familien er stadig korrekt).

- [ ] **Step 1: Skriv de fejlende data-tests** (mock `../../supabase` som i `haendelser.test.ts`):
  `'returnerer ⚭-tekst pr. familie'` (to familier → `{ '265': '⚭ 21. juli 1667', '266': '⚭ 1. maj 1681' }`),
  `'tom liste kalder ikke databasen'`, `'fejl giver tomt resultat'`.
- [ ] **Step 2:** `npm run test -w web -- vielser` → FAIL.
- [ ] **Step 3:** Implementér `hentVielsesDatoer` i `web/src/data/vielser.ts`.
- [ ] **Step 4: Skriv de fejlende komponent-tests** i `PersonSide.test.tsx`: med en ægtefælle, hvis familie har
  vielse, vises `⚭ 21. juli 1667` efter ægtefællens livsdatoer; ægtefælle uden id og ægteskab uden vielse viser
  ingen `⚭` og intet crash.
- [ ] **Step 5:** Implementér i `PersonSide`: `useEffect` på familie-id'erne fra `familieIderForPerson` → state
  `Record<familyId, string>`; vis teksten i samme mono-stil som årstallet efter `PersonLink`/navnet for den
  ægtefælle, hvis `spouseId` matcher (navne-ægtefælle uden id: match ikke, vis intet).
- [ ] **Step 6:** `npm run test -w web` → PASS.
- [ ] **Step 7: Commit** — `feat(web): vielsesdato med ⚭ ved ægtefællen på personsiden`

### Task 5: »Kun i«-barn er grå uden for sin udgave (web)

**Files:**
- Modify: `web/src/data/kunIAeldre.ts` (`KunIAeldreTekst` + `kunISourceIds`)
- Test: `web/src/data/__tests__/kunIAeldre.test.ts`
- Modify: `web/src/components/PersonSide.tsx:235` (børnelisten) og `:386-396` (`PersonLink`)
- Test: `web/src/components/__tests__/PersonSide.udgaver.test.tsx`

**Interfaces:**
- Produces: `KunIAeldreTekst = { maerke: string; forklaring: string; linje: string; kunISourceIds: string[] }`;
  `PersonLink` får prop `aktiv?: boolean` (standard `true`). `aktiv=false` → navnet som `<span>` i `T.inkMuted`,
  ingen `Link`, mærket står stadig med `title={kunI.forklaring}`.
- Regel: barnet er aktivt, hvis det ikke har `kunI`, eller hvis siden ingen udgavevælger har (`v.aktivChip` mangler),
  eller hvis `kunI.kunISourceIds.includes(v.aktivChip.sourceId)`.

- [ ] **Step 1: Skriv de fejlende tests:** `kunIAeldre.test.ts`: resultatet bærer `kunISourceIds: ['3']`.
  `PersonSide.udgaver.test.tsx` (Conrad-fixturen med et 1939-only barn): med 2018-20 valgt er barnets navn ikke et
  link (`queryByRole('link', { name: … })` er null) og mærket »Kun i DAA 1939« står; efter klik på 1939-chippen er
  navnet et link. Uden vælger (person i én udgave) er barnet et link.
- [ ] **Step 2:** `npm run test -w web -- kunIAeldre PersonSide.udgaver` → FAIL.
- [ ] **Step 3:** Implementér `kunISourceIds` og `aktiv` efter reglen ovenfor.
- [ ] **Step 4:** `npm run test -w web` → PASS.
- [ ] **Step 5: Commit** — `feat(web): et barn, der kun står i en anden udgave, er grå tekst uden for den`

### Task 6: Samlet verifikation

- [ ] **Step 1:** Hele node-jobbet lokalt som i CI: `npm ci` (rod), `npm run test -w @daa/core`, `-w @daa/feed`,
  `-w @daa/theme`, `-w web`, `npm test -w mobile`, `npx tsc --noEmit -p mobile`, `npm run build -w web` — alle exit 0.
- [ ] **Step 2:** Vercel-preview (efter push af grenen): person 392 viser `* 1600 † 1664` ved faren,
  `⚭ 21. juli 1667` og `⚭ 1. maj 1681` ved hustruerne, Charlotte Amalie grå med »Kun i DAA 1939« i 2018-20 og link i
  1939, og stamtræets børn i rækkefølgen V-2…V-17. Stamtræets kort og søgeresultater knækker ikke med de længere
  livsdatoer (tjek ved smal skærm).
