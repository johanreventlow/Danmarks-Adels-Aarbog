# Minimumskrav til forsidens personer — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forsiden viser kun forsideværdige, sikkert døde personer, højst ét kort pr. person, og ingen »Nævnt i Aarbogen«-kort.

**Architecture:** Et nyt, valgfrit flag `FeedInputs.forsideKrav` i den delte feed-motor (`packages/feed`). Med flaget udtynder `buildFeedOrder` den sikkert-døde model til forsideværdige personer (ny `forside.ts`) og beholder kun første kort pr. person i den prioritetssorterede pulje. Uden flaget er motoren byte-for-byte uændret, så ekvivalenstesten mod den frosne `orderReference.ts` fortsat gælder. Web og mobil sætter flaget.

**Tech Stack:** TypeScript, vitest (`packages/feed`, `web`), jest (`mobile`).

**Spec:** `docs/superpowers/specs/2026-11-24-forside-minimumskrav-design.md`

## Global Constraints

- `packages/feed/src/__tests__/orderReference.ts` må ALDRIG ændres; `order.ekvivalens.test.ts` skal være grøn uændret.
- Uden `forsideKrav` (eller `false`) må `buildFeedOrder`'s output og rng-forbrug ikke ændres.
- Tærskler: biografi ≥ 200 tegn; voksen = alder ≥ 15; død ≥ 25 år; uden dødsår: født ≤ i år − 145.
- Navneregel (case-insensitiv, på navnets start): `^\(\s*(søn|datter|barn|dreng|pige)\s*\)` og `^N\.\s?N\.`.
- Dødstekst-regel: `doedTekst` matcher `/\b(ung|lille|spæd)\b/i` → ikke voksen.
- Hændelse tæller kun uden rygrad (`!item.rygrad`).
- Commits: Conventional Commits på dansk, ingen Claude-attribution, kun på grenen `feat/forside-minimumskrav`.

## Review Focus

1. Web genopbygger strømmen, når data ankommer sent (`resumeStream`): en allerede vist person må ikke komme igen med et andet kort-id.
2. En person med dødsspænd »† 1999/2003« (`doedSpaend: [1999, 2003]`): reglen om 25 år bruger 2003.
3. Redaktørens fastgjorte kort (pin) for person X: X's øvrige kort falder fra; selve pinnet bliver.
4. Kort uden person (gods, våben, forbundet, samle) berøres ikke af »ét kort pr. person«.
5. Mobilens model mangler `doedTekst`/`doedSpaend`: reglerne falder tilbage på `died`/`born` uden at kaste.

---

### Task 1: `forside.ts` — hvem er forsideværdig

**Files:**
- Create: `packages/feed/src/forside.ts`
- Modify: `packages/feed/src/index.ts` (eksportér `./forside`)
- Test: `packages/feed/src/__tests__/forside.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export const FORSIDE_MIN_BIO = 200;
  export const FORSIDE_MIN_ALDER = 15;
  export const FORSIDE_MIN_AAR_DOED = 25;
  export type ForsideKontekst = {
    dagsAar: number;
    haendelserBy: HaendelserBy;
    officesBy: FeedAux['officesBy'];
    personerMedBillede?: ReadonlySet<string>;
  };
  export function harRigtigtNavn(name: string): boolean;
  export function blevVoksen(p: ModelPerson): boolean;
  export function doedForLaengeSiden(p: ModelPerson, dagsAar: number): boolean;
  export function harIndhold(p: ModelPerson, k: ForsideKontekst): boolean;
  export function erForsideVaerdig(p: ModelPerson, k: ForsideKontekst): boolean; // alle fire
  export function kunForsideVaerdige(model: Model, k: ForsideKontekst): Model;   // som kunSikkertDoede: persons+byId, indexes urørt
  ```
  (`ModelPerson` = `Model['persons'][number]`.)

- [ ] **Step 1: Skriv de fejlende tests** i `forside.test.ts` (person-hjælper som i `order.test.ts`, `died: 1700` som standard):
  - `harRigtigtNavn`: `false` for `'(Søn) Reventlow'`, `'( datter ) Reventlow'`, `'N. N. von Lützow'`, `'N.N. Lunov eller Anne Juel af Aabjærg'`; `true` for `'(Anna?) von Ahlefeldt'`, `'Christian Ditlev Reventlow'`, `'Nanna Reventlow'`.
  - `blevVoksen`: `false` for born 1700/died 1700, born 1700/died 1714; `true` for born 1700/died 1715; `true` for born null/died 1700; `false` for `doedTekst: '† ung'`, `'lille'`, `'+ ung'`, `'† ung.'` selv med born null; `true` for `doedTekst: '† 1750'`.
  - `doedForLaengeSiden` med dagsAar 2026: died 2001 → `true`; died 2002 → `false`; died 1990 med `doedSpaend: [1990, 2005]` → `false`; died null/born 1881 → `true`; died null/born 1882 → `false`; died null/born null → `false`.
  - `harIndhold`: bio 199 tegn → `false`; bio 200 → `true`; `title: 'Kammerherre'` → `true`; kun rygrad-hændelse → `false`; én ikke-rygrad-hændelse → `true`; `officesBy[id]` med ét embede → `true`; `personerMedBillede` med id → `true`; intet → `false`.
  - `kunForsideVaerdige`: udtynder `persons` og `byId`, `indexes` er samme objekt (`toBe`).
- [ ] **Step 2: Kør** `npm run test -w @daa/feed -- forside` — Expected: FAIL (modulet findes ikke).
- [ ] **Step 3: Implementér** `forside.ts` efter Interfaces og Global Constraints. `doedForLaengeSiden`: dødsår = `p.doedSpaend?.[1] ?? p.died`; uden dødsår kræves `p.born != null && dagsAar - p.born >= LEVENDE_ALDERSGRAENSE + FORSIDE_MIN_AAR_DOED` (importér `LEVENDE_ALDERSGRAENSE` fra `./levende`). `blevVoksen`: dødstekst-regel først; derefter alder kun når `born` og `died` begge kendes. Kun `import type` fra `@daa/core`.
- [ ] **Step 4: Kør** `npm run test -w @daa/feed -- forside` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(feed): regler for hvem der er forsideværdig`.

### Task 2: `buildFeedOrder` med `forsideKrav` + `resumeStream` over personer

**Files:**
- Modify: `packages/feed/src/types.ts` (`FeedInputs`)
- Modify: `packages/feed/src/order.ts` (`buildFeedOrder`)
- Modify: `packages/feed/src/stream.ts` (`resumeStream`)
- Test: `packages/feed/src/__tests__/forside.test.ts` (ny `describe`), `packages/feed/src/__tests__/stream.test.ts`

**Interfaces:**
- Consumes: `kunForsideVaerdige`, `ForsideKontekst` (Task 1).
- Produces:
  ```ts
  // FeedInputs, nye valgfrie felter:
  forsideKrav?: boolean;                      // forsidens minimumskrav (spec 2026-11-24)
  personerMedBillede?: ReadonlySet<string>;   // krav 4's billed-gren; web sender det først med spor 2
  // stream.ts:
  export function resumeStream(stream: FeedStream, shownIds: ReadonlySet<string>, shownPersonIds?: ReadonlySet<string>): FeedStream;
  ```

- [ ] **Step 1: Skriv de fejlende tests** (todayISO `'2026-11-24'`, `disabledKinds: new Set()`):
  - `'forsideKrav udelader ikke-forsideværdige'`: model med `(Søn) X` (lang bio), en voksen med lang bio, et barn (born 1700/died 1701, lang bio) → kun den voksnes kort har `personId`.
  - `'forsideKrav giver højst ét kort pr. person'`: én person med lang bio, titel, eksakt fødsel 1750-11-03 og død 1800-11-20 i `livsdatoBy` → `cards.filter(c => bookmarkPersonId(c) === id).length === 1`, for seeds 1..50.
  - `'fastgjort kort vinder over personens øvrige kort'`: samme person, `pins: [{ kortNoegle: 'portrait:<id>', handling: 'pin' }]` → personens eneste kort er `portrait:<id>` (sæt `disabledKinds: new Set(['citat'])`, så portrættet findes).
  - `'kort uden person berøres ikke'`: `aux.godsListe` med 3 godser + forsideKrav → 3 `gods`-kort.
  - `'uden forsideKrav er output uændret'`: for seeds 1..20 er `buildFeedOrder(m, aux, inputs)` deep-equal med `buildFeedOrder(m, aux, { ...inputs, forsideKrav: false })`, og et barn med lang bio optræder stadig.
  - `stream.test.ts`: `'resumeStream springer allerede viste personer over'`: en strøm med `portrait:1`, `paadennedag:1:født:1750`, `portrait:2`; `resumeStream(s, new Set(['paadennedag:1:født:1750']), new Set(['1'])).next(10)` → kun `portrait:2`.
- [ ] **Step 2: Kør** `npm run test -w @daa/feed -- forside stream` — Expected: FAIL.
- [ ] **Step 3: Implementér.** I `buildFeedOrder`: lige efter `safeModel` → `const feedModel = inputs.forsideKrav ? kunForsideVaerdige(safeModel, { dagsAar: todayYear, haendelserBy, officesBy: aux.officesBy, personerMedBillede: inputs.personerMedBillede }) : safeModel;` og brug `feedModel` i stedet for `safeModel` i alle efterfølgende builders. Efter `pool`-sorteringen (før `new RangPulje(pool)`), kun med flaget: fjern kort hvis `bookmarkPersonId` er i sættet af personer fra `pinnedBlock` + `lockedDagensPerson`/`lockedSlaegt`'s kort, og behold derudover kun første kort pr. person. `R`ng-kald før og efter er uændrede. `resumeStream`: spring også kort over, hvis `bookmarkPersonId(card)` er i `shownPersonIds`.
- [ ] **Step 4: Kør** `npm run test -w @daa/feed` — Expected: alle grønne, inkl. `order.ekvivalens.test.ts` uændret.
- [ ] **Step 5: Commit** `feat(feed): forsideKrav udtynder modellen og giver højst ét kort pr. person`.

### Task 3: Slå »Nævnt i Aarbogen« fra

**Files:**
- Modify: `packages/feed/src/score.ts` (`TEMP_DISABLED_KINDS` + `'naevnt'`)
- Modify: `packages/feed/src/__tests__/naevnt.test.ts`, `packages/feed/src/__tests__/orderGenerator.ts` (web-form = `TEMP_DISABLED_KINDS` uden `'naevnt'`, så naevnt-grenene stadig dækkes)
- Test: `packages/feed/src/__tests__/naevnt.test.ts`

- [ ] **Step 1: Skriv den fejlende test** i `naevnt.test.ts`: `'TEMP_DISABLED_KINDS slår naevnt fra (projektejeren 24/11)'` → `expect(TEMP_DISABLED_KINDS.has('naevnt')).toBe(true)`.
- [ ] **Step 2: Kør** `npm run test -w @daa/feed -- naevnt` — Expected: FAIL på den nye test.
- [ ] **Step 3: Implementér:** tilføj `'naevnt'` til sættet med en kommentar (»projektejeren 24/11: strider mod forsidens krav om indhold; tænd igen ved at fjerne den«). I `naevnt.test.ts` og `orderGenerator.ts` erstattes brugen af `TEMP_DISABLED_KINDS` som »web-form med naevnt« af `new Set([...TEMP_DISABLED_KINDS].filter((k) => k !== 'naevnt'))` (navngiv konstanten `UDEN_NAEVNT_SLAAET_FRA` lokalt). Testen `'disabledKinds kan slå typen fra'` bruger fortsat et sæt med `'naevnt'`.
- [ ] **Step 4: Kør** `npm run test -w @daa/feed` — Expected: alle grønne, inkl. ekvivalenstestens gren-dækning (`grene`).
- [ ] **Step 5: Commit** `feat(feed): slå »Nævnt i Aarbogen«-kortene fra på forsiden`.

### Task 4: Web og mobil slår kravene til + dokumentation

**Files:**
- Modify: `web/src/components/feed/FeedStreamView.tsx` (`createFeedStream`-input + `resumeStream`-kald)
- Modify: `mobile/src/app/(tabs)/index.tsx` (`createFeedStream`-input)
- Modify: `web/src/components/__tests__/FeedStreamView.test.tsx`
- Modify: `docs/decisions.md` (ny post øverst, 2026-11-24), `docs/changelog.md`

**Interfaces:**
- Consumes: `FeedInputs.forsideKrav`, `resumeStream(stream, shownIds, shownPersonIds)` (Task 2).

- [ ] **Step 1: Skriv den fejlende test** i `FeedStreamView.test.tsx`: `'forsiden beder motoren om forsidens minimumskrav'` → `streamMocks.createFeedStream` kaldt med et tredje argument, der indeholder `forsideKrav: true`.
- [ ] **Step 2: Kør** `npx vitest run src/components/__tests__/FeedStreamView.test.tsx` (i `web/`) — Expected: FAIL.
- [ ] **Step 3: Implementér:** web og mobil sender `forsideKrav: true`. Web's resume-kald: `resumeStream(built, new Set(preserved.map((c) => c.id)), new Set(preserved.map(bookmarkPersonId).filter((id): id is string => id != null)))`. `decisions.md`: »BESLUTTET: minimumskrav til forsidens personer« med de 8 punkter fra spec'en i kort form + »Nævnt slået fra« + »billeder med spor 2«. `changelog.md`: én dateret linje.
- [ ] **Step 4: Kør hele node-jobbet som CI:** `npm run test -w @daa/core && npm run test -w @daa/feed && (cd web && npx tsc --noEmit -p . && npm run lint && npx vitest run) && (cd mobile && npx tsc --noEmit && npx jest)` — Expected: alt grønt.
- [ ] **Step 5: Commit** `feat(web,mobil): forsiden bruger forsidens minimumskrav`.
