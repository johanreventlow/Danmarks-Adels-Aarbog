# Levende feed — fase 1: dynamik & uendelig scroll · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed'en er ny ved hvert besøg (seeded sampling), kan scrolles med ægte dosering
til et ærligt slutkort, får tidslige kort (på denne dag / dagens person / dag-præcise
jubilæer), og kører på **én delt motor** (`@daa/feed`) for mobil og web — uden
backend-ændringer.

**Architecture:** Ny workspace-pakke `packages/feed` (afhænger af `@daa/core`) med en ren
pipeline: kandidat-pool (builders uden caps) → scoring (forklarlige faktorer) → seeded
vægtet trækning uden tilbagelægning m. rytme-regler → færdig ordning, doseret af et tyndt
strøm-API. Mobil og web renderer strømmen hver med deres egne kort-views. Set-hukommelse
(AsyncStorage/localStorage) giver friskhed på tværs af dage. Livsdatoer (dag-præcision)
hentes klientside fra fact→conclusion→assertion og joines i en ren, delt helper.

**Tech Stack:** TypeScript, vitest (`packages/feed`), React Native/Expo 56 + jest (mobil),
React/Vite + vitest + Playwright (web), Supabase PostgREST (kun eksisterende tabeller/RLS).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-18-levende-feed-fase1-design.md` (autoritativ for alle regler)
- Koncept: `docs/design/2026-07-18-levende-feed-koncept.md` (§4 motor, §10 fase 1)
- Eksisterende motor: `mobile/src/data/buildFeed.ts` + `feedHash.ts` + `__tests__/buildFeed.test.ts`
- Pakke-forbillede: `packages/core/` (source-only, egen vitest, CI-job — review 27 #13 / F-16)
- Web-forside: `web/src/components/HomeView.tsx`, `web/src/data/home.ts`, `web/src/data/model.ts`

## Global Constraints

- **Ingen backend-ændringer:** intet nyt skema, ingen nye RPC'er; kun læsninger af
  eksisterende tabeller under eksisterende RLS. Cache-felter (`visning_*`, `koen`) læses kun.
- **Motoren er ren:** ingen `Math.random`/`Date.now`/`new Date()` i `packages/feed` —
  `seed` og `todayISO` injiceres. Tilfældighed er tilladt KUN i app-lagets seed-valg.
- **Determinisme:** samme (model, aux, inputs) → identisk ordning. Alle tests injicerer seed/dato.
- **Portrait/citat-disjunkthed** bevares (ingen person som begge; citat-slot uden sætning
  falder helt ud). `dagensperson` er også disjunkt fra begge.
- **Alle person-id'er i bogmærker/seen/livsdato er kanoniske** (`canonicalIdById`).
- **Ingen nye farver/fonte:** mobil styler fra `mobile/src/theme/tokens.ts`, web fra
  `web/src/theme.ts` + `primitives.tsx`.
- Hver task holder relevant typecheck + suite grøn: `packages/feed` → `npx vitest run` (fra
  `packages/feed/`), mobil → `npx tsc --noEmit && npm test` (fra `mobile/`), web →
  `npm run test` (fra `web/`).
- Commit-beskeder på dansk, `feat(feed): …`-stil; brug din egen sessions Claude-Session-footer.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `packages/feed/{package.json,tsconfig.json,vitest.config.ts}` | Pakke-skelet (spejl af core) | 1 |
| `packages/feed/src/prng.ts` | `mulberry32` + genbrugt `stableHash`/`interleave` (flyttet) | 1 |
| `packages/feed/src/types.ts` | `FeedCard` (11 kinds), `FeedAux`, `FeedInputs`, `LivsdatoBy` | 2 |
| `packages/feed/src/pool.ts` | Alle kandidat-builders (portede, uden caps) + `buildPool` | 2 |
| `packages/feed/src/temporal.ts` | `paadennedag`/`dagensperson`/jubilæums-opgradering + `buildLivsdatoBy` | 3 |
| `packages/feed/src/score.ts` | `BASE`-vægte + `score(card, inputs)` | 4 |
| `packages/feed/src/order.ts` | Vægtet trækning + rytme R1–R3 + positionslåse + terminal → `buildFeedOrder` | 4 |
| `packages/feed/src/stream.ts` | `createFeedStream` + `resumeStream` | 5 |
| `packages/feed/src/index.ts` | Offentligt API | 1–5 |
| `packages/feed/src/__tests__/*` | Vitest for alt ovenstående (inkl. porterede v3-tests) | 1–5 |
| `.github/workflows/*` | CI-job for feed-pakken (spejl af core-typecheck/-test) | 1 |
| `mobile/src/data/livsdato.ts` | Tolerant fetch af fact/conclusion/assertion-rækker | 6 |
| `mobile/src/lib/seenCards.ts` (+ test) | Set-hukommelse: lager, LRU, decay-vægte | 7 |
| `mobile/src/app/(tabs)/index.tsx` | Strøm-dosering, seed, pull-to-refresh, ægte footer | 8 |
| `web/src/data/feedAux.ts` (+ test) | `buildWebFeedAux` + bio-hentning + livsdato-fetch | 9 |
| `web/src/data/seenCards.ts` (+ test) | localStorage-udgave af set-hukommelsen | 9 |
| `web/src/components/feed/*` | `FeedStreamView` + web-kort-views + sentinel | 10 |
| `web/src/components/HomeView.tsx` | Feed monteret under hero | 10 |
| Playwright e2e | Røgtest af forside-feed | 11 |
| `mobile/src/data/buildFeed.ts`/`feedHash.ts` | SLETTES (oprydning) | 12 |

---

## Task 1: Pakke-skelet + prng (`packages/feed`)

**Files:**
- Create: `packages/feed/package.json`, `tsconfig.json`, `vitest.config.ts` — kopiér
  `packages/core`s filer og ret navn til `@daa/feed`; tilføj `@daa/core` som dependency
  (samme source-only-mekanisme som web/mobils import af core — verificér i rod-`package.json`
  workspaces + core's `package.json` hvordan `main`/`exports` peger på `src/`).
- Create: `packages/feed/src/prng.ts`, `packages/feed/src/index.ts`,
  `packages/feed/src/__tests__/prng.test.ts`.
- Modify: rod-`package.json` (workspace-medlem hvis ikke `packages/*`-glob), CI-workflow
  (nyt job: feed-typecheck + vitest — spejl core-jobbet fra F-16).

**Interfaces:**
- Produces: `mulberry32(seed: number): () => number` (deterministisk PRNG, output [0,1)),
  `stableHash(s: string): number` og `interleave<T>(groups: T[][]): T[]` (flyttet 1:1 fra
  `mobile/src/data/feedHash.ts` — kopiér implementering + eksisterende tests).

- [ ] **Step 1: Skriv de fejlende tests**

```ts
// packages/feed/src/__tests__/prng.test.ts
import { describe, expect, it } from 'vitest';
import { mulberry32, stableHash, interleave } from '../prng';

describe('mulberry32', () => {
  it('er deterministisk pr. seed', () => {
    const a = mulberry32(42); const b = mulberry32(42);
    expect([a(), a(), a()]).toEqual([b(), b(), b()]);
  });
  it('forskellige seeds → forskellige sekvenser', () => {
    expect(mulberry32(1)()).not.toBe(mulberry32(2)());
  });
  it('output i [0,1)', () => {
    const r = mulberry32(7);
    for (let i = 0; i < 1000; i++) { const v = r(); expect(v).toBeGreaterThanOrEqual(0); expect(v).toBeLessThan(1); }
  });
});
// + portér stableHash/interleave-tests fra mobile buildFeed.test.ts uændret
```

- [ ] **Step 2: Kør — verificér FAIL** (`npx vitest run` fra `packages/feed/`)

- [ ] **Step 3: Implementér**

```ts
// packages/feed/src/prng.ts
// Rene, deterministiske hjælpere til feed-motoren. Ingen Math.random/Date.now.
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
// stableHash + interleave: flyt implementeringen ordret fra mobile/src/data/feedHash.ts
```

- [ ] **Step 4: Kør — verificér PASS**; kør også `npx tsc --noEmit` i pakken.
- [ ] **Step 5: Tilføj CI-jobbet** (feed-typecheck + vitest, spejl core-jobbet) og commit.

```bash
git add packages/feed .github/workflows package.json package-lock.json
git commit -m "feat(feed): @daa/feed-pakkeskelet + mulberry32/stableHash/interleave (skive 1)"
```

---

## Task 2: Typer + kandidat-pool (`types.ts`, `pool.ts`)

**Files:**
- Create: `packages/feed/src/types.ts`, `packages/feed/src/pool.ts`,
  `packages/feed/src/__tests__/pool.test.ts`.

**Interfaces:**
- Produces (`types.ts`):
  - `FeedCard` = de 9 eksisterende varianter fra `mobile/src/data/buildFeed.ts`
    (kopiér union'en ordret) **plus** to nye:

```ts
| { kind: 'paadennedag'; id: string; personId: string; name: string; years: string;
    aarstal: number; hvad: 'født' | 'død'; praecision: 'dag' | 'maaned'; kicker: string }
| { kind: 'dagensperson'; id: string; personId: string; name: string; years: string;
    initials: string; title: string | null; bio: string; kicker: string }
```

  - `FeedAux` (spec §3.1): `{ godsListe; vaabenListe; officesBy }` — feltformer som
    mobilens `Aux` (`mobile/src/data/types.ts:116-129`), men KUN de tre felter.
  - `FeedInputs` (spec §3.2): `seed`, `todayISO`, `meId`, `focusId`, `bookmarkedIds?`,
    `seenWeights?`, `livsdatoBy?`, `overrides?` (no-op).
  - `FuzzyDato = { min: string | null; max: string | null; qualifier: string | null }`,
    `LivsdatoBy = Record<string, { foedt?: FuzzyDato; doed?: FuzzyDato }>`.
  - `bookmarkPersonId(card)` — flyt ordret fra mobil (dækker automatisk de to nye kinds
    via `'personId' in card`).
- Produces (`pool.ts`): builders porteret fra `mobile/src/data/buildFeed.ts` **uden
  caps** (`FEED_CAPS` og `cap()` porteres IKKE): `buildPortraitAndCitat` (+ ny parameter
  `excludeId: string | null` — dagens person udelades, se task 3), `buildGods`,
  `buildForbundet`, `buildEmbeder`, `buildJubilaeer` (udvides i task 3), `buildVaaben`,
  `buildSlaegt`, `firstQuotableSentence`. Model-typen importeres fra `@daa/core` —
  builders er allerede kun afhængige af `Model`-felter (verificér: mobilens `Model` er
  core's `buildModel`-output; ret importen).
- Samlet: `buildPool(model, aux, inputs): FeedCard[]` — alle kandidater, stabilt
  id-sorteret pr. type (terminal-`samle` og positionslåste kort bygges i task 4).

- [ ] **Step 1:** Portér de eksisterende buildFeed-tests der vedrører builders
  (partition-disjunkthed, jubilæumstærskel, forbundet-/slaegt-guards, tom model,
  `firstQuotableSentence`) til `pool.test.ts` (vitest-syntaks). Tilføj: `buildPool` med
  tom `FeedAux`-felter → ingen kort af de typer; ingen caps (60 bio-personer → ~45
  portrætter, ikke 12).
- [ ] **Step 2: Kør — verificér FAIL.**
- [ ] **Step 3:** Flyt koden; fjern caps; behold alle udeladelses-regler og kommentarer
  (dual-review-referencerne DS1–4/NEW1–2 følger med).
- [ ] **Step 4: Kør — verificér PASS.**
- [ ] **Step 5: Commit** — `feat(feed): typer + kandidat-pool uden caps (skive 1)`.

---

## Task 3: Tidslige kort + livsdato-join (`temporal.ts`)

**Files:**
- Create: `packages/feed/src/temporal.ts`, `packages/feed/src/__tests__/temporal.test.ts`.
- Modify: `packages/feed/src/pool.ts` (jubilæums-opgradering + dagensperson-eksklusion).

**Interfaces:**
- `buildLivsdatoBy(facts, conclusions, assertions, canonicalIdById): LivsdatoBy` — REN
  JS-join (spec §6.1): fact-rækker `{id, subjekt_id, faktatype}` (kun 'fødsel'/'død'),
  conclusion-rækker `{target_id, valgt_assertion_id}`, assertion-rækker
  `{id, date_min, date_max, date_qualifier}`. Person-id kanoniseres. Fetch bor i
  app-lagene (task 6/9) — pakken forbliver netværksfri.
- `buildPaaDenneDag(model, livsdatoBy, todayISO): FeedCard[]` — kandidat når
  `qualifier === 'exact'` og `date_min`s `MM-DD` == `todayISO`s. Id:
  `paadennedag:${pid}:${hvad}:${aarstal}`. **Måneds-fallback:** hvis 0 dag-træf,
  returnér måneds-træf med `praecision:'maaned'` og kicker `'I denne måned'`
  (dag-træf: kicker `'På denne dag'`).
- `pickDagensPerson(model, todayISO): string | null` — `stableHash(todayISO) % N` over
  den stabilt id-sorterede bio-population (`bio.trim() !== ''`); null ved tom population.
- `buildDagensPersonCard(model, personId): FeedCard | null` — portræt-felterne, kind
  `'dagensperson'`, kicker `'Dagens person'`.
- `buildJubilaeer` udvides: signatur `(model, todayYear, livsdatoBy, todayISO)`; uændret
  års-regel, men når personens eksakte dato matcher dagens `MM-DD`, sættes
  `sub = '… — på dagen'`-varianten og kortet markeres `paaDagen: true` (tilføj feltet
  `paaDagen?: boolean` på jubilæums-varianten i `types.ts` — bruges af scoring).
- `buildPortraitAndCitat(model, excludeId)`: personen med `excludeId` springes over
  (disjunkthed med dagensperson).

- [ ] **Step 1: Skriv de fejlende tests** (injiceret `todayISO`, fixture-`livsdatoBy`):
  dag-match → `paadennedag` m. kicker 'På denne dag'; kun måneds-match → fallback-kort m.
  `praecision:'maaned'`; `qualifier:'about'` → aldrig kort; tom `livsdatoBy` → `[]`;
  `buildLivsdatoBy` joiner + kanoniserer (alias-id → kanonisk); `pickDagensPerson`
  deterministisk pr. dato og skifter mellem datoer; dagensperson-id optræder ikke i
  portræt-/citat-output; jubilæum får `paaDagen` kun ved dag-match.
- [ ] **Step 2: FAIL** → **Step 3: Implementér** → **Step 4: PASS.**
- [ ] **Step 5: Commit** — `feat(feed): tidslige kort + livsdato-join (skive 4-kerne)`.

---

## Task 4: Scoring + seeded ordning (`score.ts`, `order.ts`)

**Files:**
- Create: `packages/feed/src/score.ts`, `packages/feed/src/order.ts`,
  `packages/feed/src/__tests__/order.test.ts`.

**Interfaces:**
- `BASE: Record<FeedCard['kind'], number>` — spec §3.4-værdierne (portrait 1.0,
  paadennedag 1.0, dagensperson 1.0, jubilaeum 0.9, slaegt 0.8, gods 0.6, embede 0.6,
  forbundet 0.5, citat 0.4, vaaben 0.3, samle 0 — terminal scorer ikke).
- `score(card, inputs): number` = `BASE[kind] × timeliness × personal × seen`:
  - timeliness ×4: `paadennedag` m. `praecision==='dag'`, eller `jubilaeum` m. `paaDagen`.
  - personal ×1.5: kortets `personId` ∈ `inputs.bookmarkedIds`.
  - seen: `inputs.seenWeights?.[card.id] ?? 1`.
- `buildFeedOrder(model, aux, inputs): FeedCard[]` — hele pipelinen:

```
pool = buildPool(...) minus dagensperson-ekskl.; temporal-kort tilføjes
rng = mulberry32(inputs.seed)
trækning: vægtet uden tilbagelægning (kumulativ-sum-scan over resterende kandidater):
  pr. slot op til 20 forsøg:
    R1: kandidatens kind ≠ forrige korts kind
    R2: kandidatens personId ikke blandt de sidste 8 korts personId'er
    R3 (forcing, ikke afvisning): hvis de sidste 5 kort er uden portrait/dagensperson
        og portræt-kandidater findes → begræns DETTE træk til portræt-kandidater
  efter 20 forfejlede forsøg lempes i rækkefølge: først R2, så R1 (fast, testet rækkefølge)
positionslåse (efter hovedtrækningen, seed-drevet):
  dagensperson-kortet indsættes på position floor(rng()*3)      (0–2)
  slaegt-kortet (maks. 1) indsættes på position 3 + floor(rng()*7)  (3–9), hvis det findes
terminal: samle-kortet ('…og N flere personer i registeret', N = personer uden eget
  person-kort i ORDNINGEN) appendes sidst
```

- [ ] **Step 1: Skriv de fejlende tests:**
  - Determinisme: to kald m. samme inputs → dyb lighed; to seeds → forskellig rækkefølge,
    samme kort-mængde (sammenlign sorterede id-lister).
  - R1: ingen to nabo-kort med samme kind (normal fixture).
  - R2: samme personId aldrig inden for 8 positioner (fixture m. få personer, mange korttyper).
  - R3: i enhver 6-korts-rude findes ≥1 portrait/dagensperson (fixture m. rigelige portrætter).
  - Lempelse: degenereret fixture (kun citat-kort) → komplet ordning, ingen uendelig løkke.
  - Positionslåse: dagensperson-index ∈ [0,2]; slaegt-index ∈ [3,9]; samle sidst.
  - Vægt-effekt: `seenWeights[id]=0` → kortet udelades reelt (vægt 0 trækkes aldrig —
    definér: kandidater med score ≤ 0 filtreres fra poolen FØR trækning, undtagen samle);
    bookmarked person kommer i gennemsnit tidligere over 20 faste seeds end ikke-bookmarked
    (statistisk assert på gennemsnits-index).
  - Tom model → `[]`.
- [ ] **Step 2: FAIL** → **Step 3: Implementér** → **Step 4: PASS** (+ mikro-benchmark i
  test: ordning af 3.000-korts fixture < 250 ms i CI — rummeligt loft; det reelle
  <50 ms-budget måles på device i task 8).
- [ ] **Step 5: Commit** — `feat(feed): scoring + seeded ordning med rytme-regler (skive 1)`.

---

## Task 5: Strøm-API (`stream.ts`)

**Files:**
- Create: `packages/feed/src/stream.ts`, `packages/feed/src/__tests__/stream.test.ts`.
- Modify: `packages/feed/src/index.ts` (eksportér det samlede offentlige API: typer,
  `buildFeedOrder`, `createFeedStream`, `resumeStream`, `buildLivsdatoBy`,
  `bookmarkPersonId`, `pickDagensPerson`, `mulberry32`, `stableHash`).

**Interfaces (spec §4):**

```ts
export interface FeedStream { next(n: number): FeedCard[]; done(): boolean; total(): number }
export function createFeedStream(model, aux: FeedAux, inputs: FeedInputs): FeedStream;
// Genoptag efter pool-udvidelse (webs bio-ankomst): ny strøm der springer allerede viste over.
export function resumeStream(stream: FeedStream, shownIds: ReadonlySet<string>): FeedStream;
```

`createFeedStream` = tynd cursor over én `buildFeedOrder`-beregning. `resumeStream`
returnerer en strøm hvis `next` trækker fra den underliggende og kasserer kort med id i
`shownIds` (dedup-garanti ved genbyg).

- [ ] **Step 1: Tests:** `next(5)`+`next(5)` ≡ `next(10)`; `[]`+`done()` efter udtømning;
  `total()`; `resumeStream` leverer aldrig et id fra `shownIds` og bevarer indbyrdes
  rækkefølge af resten.
- [ ] **Step 2–4:** FAIL → implementér → PASS.
- [ ] **Step 5: Commit** — `feat(feed): strøm-API med next-stabilitet + resumeStream (skive 2)`.

---

## Task 6: Mobil — livsdato-fetch (`mobile/src/data/livsdato.ts`)

**Files:**
- Create: `mobile/src/data/livsdato.ts`, `mobile/src/data/__tests__/livsdato.test.ts`.
- Modify: `mobile/src/store/useStore.ts` (nyt felt `livsdatoBy`, hentes i `load()`s
  parallelle batch — den er lille: 3 queries, ~2 fakta × ~920 personer).

**Interfaces:**
- `fetchLivsdatoRows(): Promise<{facts; conclusions; assertions}>` — mønster fra
  `fetchParentsUnknownRows` (`web/src/data/model.ts:192-216`, mobil har tilsvarende):
  1) `fact`: `id,subjekt_id,faktatype` · `subjekt_type='person'` ·
     `.in('faktatype', ['fødsel','død'])` · `.order('id')`
  2) `conclusion`: `target_id,valgt_assertion_id` · `target_type='fact'` ·
     `.in('target_id', factIds)` (chunk `.in` ved >200 id'er — genbrug eksisterende
     chunk-helper hvis en findes i `load.ts`, ellers lav én)
  3) `assertion`: `id,date_min,date_max,date_qualifier` · `.in('id', valgte)`
  **Tolerant:** enhver fejl → tomme rækker + `console.warn` (aldrig brud på load).
- Store: `livsdatoBy = buildLivsdatoBy(rows…, canonicalIdById)` efter collapse.

- [ ] **Step 1:** Jest-tests med mockede queries: join-kæden, chunking, fejl → `{}`.
- [ ] **Step 2–4:** FAIL → implementér → PASS; `npx tsc --noEmit && npm test` grøn.
- [ ] **Step 5: Commit** — `feat(feed): livsdato-load (fødsel/død-konklusionsdatoer) mobil (skive 4)`.

---

## Task 7: Mobil — set-hukommelse (`mobile/src/lib/seenCards.ts`)

**Files:**
- Create: `mobile/src/lib/seenCards.ts`, `mobile/src/lib/__tests__/seenCards.test.ts`.

**Interfaces (spec §5.3):**
- Nøgle `daa_feed_seen`; format `Record<string, number>` (kort-id → epoch-dag).
- `createSeenStore()`: `load(): Promise<Record<string, number>>`,
  `markSeen(ids: string[], epochDay: number): void` (debounced batch-skriv, fejl sluges,
  LRU-cap 300 — ældste epoch-dage ryger først).
- `toSeenWeights(seen, todayEpochDay): Record<string, number>` — REN: <3 dage → 0.25;
  <7 → 0.5; <14 → 0.75; ellers udeladt.
- Terminal-/`slaegt`-/`dagensperson`-kort må ikke markeres (filtrér på kind i kalderen, task 8).

- [ ] **Step 1:** Tests: decay-tærskler, LRU-cap, debounce (fake timers), skrivefejl →
  ingen crash, korrupt lagerindhold → `{}` (spejl bogmærke-suitens robusthedscases).
- [ ] **Step 2–4:** FAIL → implementér → PASS.
- [ ] **Step 5: Commit** — `feat(feed): set-hukommelse med decay-vægte (skive 3)`.

---

## Task 8: Mobil — strøm-dosering i forsiden

**Files:**
- Modify: `mobile/src/app/(tabs)/index.tsx`.
- Modify: `mobile/src/data/buildFeed.ts` → reducér til re-eksport fra `@daa/feed`
  (`export { buildFeedOrder as buildFeed, bookmarkPersonId, … } from '@daa/feed'`) så
  andre imports ikke knækker; fuld sletning sker i task 12.

**Trin:**

- [ ] **Step 1: Seed + dato ét sted.** Ny lille helper (fx `mobile/src/lib/feedSession.ts`):
  `todayISO()` (lokal dato som 'YYYY-MM-DD') og `newSeed(todayISO: string): number` =
  `stableHash(todayISO + ':' + Math.random().toString(36).slice(2))`. Dette er det ENESTE
  sted `Math.random` må optræde. `CURRENT_YEAR`-konstanten udgår (todayYear udledes af
  `todayISO`).
- [ ] **Step 2: Byg strømmen.** I `HomeScreen`: state `seed` (init `newSeed(...)`),
  `shown: FeedCard[]`; `stream = useMemo(() => model && aux ? createFeedStream(model,
  toFeedAux(aux), { seed, todayISO, meId, focusId, bookmarkedIds: [...bookmarkIds],
  seenWeights, livsdatoBy }) : null, [model, aux, seed, …])` — `toFeedAux` er en triviel
  strukturel pick af de tre felter. Ved ny strøm: `setShown(stream.next(12))`.
  `seenWeights` læses ÉN gang ved mount (frys i ref — determinisme i sessionen).
- [ ] **Step 3: Dosering.** `FlatList onEndReached={() => setShown(s => [...s,
  ...stream.next(12)])}` (threshold 0.6; guard mod dobbelt-append med en in-flight-ref).
  Footer: tre tilstande — spinner-variant under append, «Du har mødt hele slægten i dag —
  udforsk registeret» når `stream.done()`, ellers den eksisterende tekst. Dekorations-
  varianten uden funktion fjernes.
- [ ] **Step 4: Pull-to-refresh.** `refreshControl` → `setSeed(newSeed(todayISO()))` +
  `setShown([])` (effekt fylder igen fra ny strøm).
- [ ] **Step 5: Viewability → seen.** `onViewableItemsChanged` (config: ≥60 % synlig,
  `minimumViewTime: 500`) → `markSeen(ids der ikke er slaegt/dagensperson/samle,
  todayEpochDay)`.
- [ ] **Step 6: Mål ordningens beregningstid** på simulator/device (log én gang):
  budget <50 ms for prod-datasættet. Overskrides det: notér i changelog og opret
  opfølgnings-issue (inkrementel trækning bag samme API) — bloker ikke tasken.
- [ ] **Step 7:** `npx tsc --noEmit && npm test` grøn; simulator-verifikation: nyt feed pr.
  app-genstart OG pr. pull-to-refresh; scroll appender reelt; slut-tilstand nås på lille
  testdata; bogmærke-toggle virker fortsat på alle person-kort (inkl. de to nye kinds).
- [ ] **Step 8: Commit** — `feat(feed): seeded strøm-dosering + ægte footer + reseed (skive 3)`.

---

## Task 9: Web — datalag (aux-adapter, bio-hentning, livsdato, seen)

**Files:**
- Create: `web/src/data/feedAux.ts` + `__tests__/feedAux.test.ts`,
  `web/src/data/seenCards.ts` + test, `web/src/data/livsdato.ts` (fetch-del, deler
  join-helperen fra `@daa/feed`).

**Interfaces:**
- `buildWebFeedAux(estates: EstateItem[], arms: ArmsItem[]): FeedAux` — `godsListe` ←
  estates (felterne matcher allerede), `vaabenListe` ← arms (`{id, blasonering, note}`),
  `officesBy: {}` (**bevidst**: web-publikum indlæser ikke embeder — noteres i changelog).
- `fetchFeedBios(): Promise<Record<string, string>>` — ÉN pagineret, tolerant query:
  `narrative` · `subjekt_id,source_id,tekst` · `subjekt_type='person'` (getAll-mønstret);
  pr. person vælges tekst med `pickPreferredBio` fra `@daa/core` (**verificér signaturen**
  i `packages/core/src/pickPreferredBio.ts` og tilpas kaldet); id'er kanoniseres.
  **Mål payload** (log `JSON.stringify`-længde én gang); >2,5 MB → skift til chunket
  `.in('subjekt_id', …)`-hentning af det seed-ordnede præfiks (spec §7.3) — men implementér
  simpel-varianten først.
- `withFeedBios(model, bios): Model` — REN kopi: `persons` mappes med bio sat (og `byId`
  gen-peges); modellen i øvrigt urørt.
- `web/src/data/seenCards.ts`: samme kontrakt som mobilens task 7, localStorage-backend
  (synkron `load`; genbrug `toSeenWeights` fra `@daa/feed`? — nej: hold `toSeenWeights` i
  pakken kun hvis den blev lagt der i task 7; ellers duplikér IKKE — flyt den rene
  decay-funktion til `@daa/feed` og lad begge apps importere den).
- Livsdato-fetch: samme tre queries som task 6 (kopiér mønstret ind i webbens idiom med
  `getAll` fra `@daa/core`).

- [ ] **Step 1:** Vitest: adapter-mapping + tomme input; `withFeedBios` (bio stemplet,
  original urørt, `byId`-konsistens); bios-fletning med flere udgaver → foretrukken;
  seen-lager (decay/LRU/korrupt-data) mod localStorage-mock.
- [ ] **Step 2–4:** FAIL → implementér → PASS (`npm run test` i `web/`).
- [ ] **Step 5: Commit** — `feat(feed): web-datalag — aux-adapter, feed-bios, livsdato, seen (skive 5)`.

---

## Task 10: Web — FeedStreamView + kort-views + HomeView-montering

**Files:**
- Create: `web/src/components/feed/FeedStreamView.tsx`, `web/src/components/feed/FeedCardViews.tsx`.
- Modify: `web/src/components/HomeView.tsx`.

**Regler:**
- Én kolonne, `maxWidth: 680`, centreret under den eksisterende hero + "Redaktionen
  foreslår"-sektion (som bevares urørt). Styling KUN fra `theme.ts`/`primitives.tsx` —
  visuel reference for kort-idiom: mobilens `FeedCardView.tsx` + webbens eksisterende
  kort (`HomeView`, `DetailPanel`). Kort-sæt på web = alle kinds minus `embede`
  (adapterens tomme `officesBy` klarer det automatisk).
- Gem-ikon iff `bookmarkPersonId(card) !== null`; toggle via `web/src/data/bookmarks.ts`
  (localStorage, kanoniske id'er — eksisterende kontrakt).
- Kort-navigation: genbrug webbens eksisterende navigations-mekanisme (se hvordan
  `HomeView`/`Folgesvend.tsx` sætter mode/fokus — fx person-kort → samme handler som
  `curatedFounders`-kortene; gods → godsdetalje; vaaben → våben-view; slaegt → relate
  med A/B forudfyldt).
- **Flow:** ved mount: `Promise.all([fetchEstates, fetchArms, livsdato])` → byg strøm
  UDEN bio-population (gods/våben/forbundet/tidslige kort vises straks) → når
  `fetchFeedBios` resolver: `withFeedBios` + ny strøm med SAMME seed +
  `resumeStream(nyStrøm, viseteIds)` — allerede viste kort står urørt, nye appendes.
- **Uendelig scroll:** én sentinel-`div` nederst + `IntersectionObserver` → `next(12)`.
  Slut-tilstand + spinner som mobil (§task 8).

- [ ] **Step 1:** Implementér views + montering (ingen unit-test af ren JSX; logikken —
  resume-flowet — ligger i allerede testede helpers).
- [ ] **Step 2:** `npm run build && npm run test` grønne; manuel browser-verifikation:
  hero intakt, feed under, scroll appender, reseed ved reload, bogmærker toggler.
- [ ] **Step 3: Commit** — `feat(feed): web-forsidefeed med uendelig scroll (skive 5)`.

---

## Task 11: Web — Playwright-røgtest

**Files:**
- Create/Modify: webbens eksisterende Playwright-opsætning (find e2e-mappen/конfig; følg
  eksisterende testmønster).

- [ ] **Step 1:** Test: forsiden viser hero + ≥5 feed-kort; scroll til sentinel udløser
  flere kort; ingen console-errors. Mod dev-server m. testdata (samme kilde som øvrige
  e2e — genbrug eksisterende fixtures/mocks; opfind ikke ny seed-infrastruktur).
- [ ] **Step 2:** Kør e2e grønt; commit — `test(feed): e2e-røgtest af web-feed (skive 5)`.

---

## Task 12: Oprydning & afstemning

- [ ] **Step 1:** Slet `mobile/src/data/buildFeed.ts` + `feedHash.ts` +
  `mobile/src/data/__tests__/buildFeed.test.ts` (alle tests er porteret til pakken i
  task 2–5 — verificér dækningen FØR sletning ved at sammenholde `it(...)`-navnene).
  Ret alle imports til `@daa/feed` (søg: `from './buildFeed'`, `from '../data/buildFeed'`,
  `feedHash`).
- [ ] **Step 2:** Verificér at `FEED_CAPS`/`interleave` ikke længere er offentligt API
  (interleave må overleve internt i pakken hvis lempelses-fallbacken bruger den).
- [ ] **Step 3:** Tilføj øverst i `docs/superpowers/specs/2026-07-05-folgesvend-v3-feed-drawer-bogmaerker-design.md`:
  `> **Status 2026-…:** §3 (feed-datamodellen) er afløst af fase 1-spec'en
  (2026-07-18-levende-feed-fase1-design.md); §4–7 er fortsat gældende historik.`
- [ ] **Step 4:** Fuld verifikation: `packages/feed` vitest + `packages/core` vitest +
  mobil `tsc`+jest + web vitest+build + e2e — alt grønt. CI-jobbet for feed-pakken kører.
- [ ] **Step 5:** Opdater `docs/changelog.md` (implementerings-post med hvad der er
  testet vs. simulator-verificeret) + status-linje i `docs/README.md`-design-sektionen
  ("fase 1 implementeret").
- [ ] **Step 6: Commit** — `chore(feed): oprydning — buildFeed flyttet til @daa/feed, v3-spec afløst (skive 6)`.

---

## Verifikation (afsluttende, spec §10)

- [ ] To app-åbninger samme dag → forskellig rækkefølge; samme seed i test → identisk (vitest).
- [ ] Scroll henter reelt flere kort på mobil OG web; slut-tilstand ærlig; ingen dekorativ footer.
- [ ] "På denne dag"/"Dagens person" skifter med injiceret dato i test; feed intakt uden livsdato-data.
- [ ] Web viser hero + feed fra samme motor; `@daa/feed` har grøn vitest-suite + CI-job.
- [ ] Ingen backend-ændringer (diff rører ikke `schema.sql`/`db-*.sql`).

## Self-review-noter (udført ved skrivning)

- **Spec-dækning:** §3 → task 1–4; §4 → task 5; §5 → task 7–8; §6 → task 3+6; §7 → task
  9–11; §8 → task 12. Alle spec-testkrav (§3.6, §4, §5.4, §6.4, §7.4) er fordelt på tasks.
- **Bevidste implementer-verifikationer** (markeret i tasks): core-pakkens
  export-mekanisme (task 1), `Aux`-feltformer (task 2), `pickPreferredBio`-signatur
  (task 9), webbens navigations-handlers (task 10), Playwright-opsætningens placering
  (task 11) — slå efter i koden frem for at gætte.
- **Kendt afvigelse fra v3-planens stil:** UI-tasks (8, 10) giver flow + regler frem for
  fuld JSX, fordi den autoritative visuelle kilde er de eksisterende komponenter
  (mobilens `FeedCardView`, webbens idiom) — oversæt derfra.
