# Følgesvend v3 — feed, menu-drawer & bogmærker · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring mobil-appen (`mobile/`) op til v3-designet: et redaktionelt forsidefeed, en menu-drawer, og bogmærker — uden backend-/model-ændringer.

**Architecture:** En ren `buildFeed`-selector udleder en typet `FeedCard[]` af den eksisterende `Model`/`Aux`. Forsiden rendrer feedet i en `FlatList` med ét komponent pr. korttype. En AsyncStorage-baseret bogmærke-hook (async-lager + synkron render-state) spejler web-kontrakten. En `Modal`-baseret drawer bærer den nummererede nav-liste, som flyttes ud af forsiden.

**Tech Stack:** TypeScript, React Native (Expo 56), expo-router, Zustand, `@react-native-async-storage/async-storage` 2.2.0, jest / jest-expo.

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-05-folgesvend-v3-feed-drawer-bogmaerker-design.md`
- Dual-review: `docs/reviews/20-folgesvend-v3-spec-dual-review.md`
- Design (markup-kilde, i design-projektet): `Reventlow-folgesvend-v3.dc.html`
- Web-referencekontrakt: `web/src/data/bookmarks.ts`, `web/src/data/__tests__/bookmarks.test.ts`

## Global Constraints

- **Ingen backend-/DB-ændringer.** Ingen ændring af `buildModel` eller slægtskabs-motoren. Feedet er ren læsning.
- **Ingen nye farver/fonte.** Al styling fra `mobile/src/theme/tokens.ts` (`Colors`, `Fonts`, `Radius`, `Shadow`, `Border`, `Motion`).
- **Cache-felter må aldrig skrives** (`visning_*`, `koen`) — kun læses.
- **Determinisme i `buildFeed`:** ingen `Math.random`/`Date.now`; `today` injiceres.
- **Alle bogmærke-id'er er kanoniske** (samme_som-collapset via `store.canonicalIdById`).
- Hver task holder `npx tsc --noEmit` grøn og hele eksisterende jest-suite (264+) grøn.
- Kør fra `mobile/`. Test: `npm test -- <sti>`. Typecheck: `npx tsc --noEmit`.
- Commit-footer: `Claude-Session: https://claude.ai/code/session_01PZZJVb6BPSXe9zVFdsn6PR`. Ingen Claude-attribution-footers.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `mobile/src/data/feedHash.ts` | Ren `stableHash` (FNV-1a) + `interleave` | 1 |
| `mobile/src/data/buildFeed.ts` | `FeedCard`-union, `FeedOptions`, `firstQuotableSentence`, `buildFeed` | 2–5 |
| `mobile/src/data/__tests__/buildFeed.test.ts` | Unit-tests for alt ovenstående | 2–5 |
| `mobile/src/lib/bookmarks.ts` | Async `BookmarkStore` + `useBookmarks`-hook | 6 |
| `mobile/src/lib/__tests__/bookmarks.test.ts` | Store + hook + async/race-tests | 6 |
| `mobile/src/app/bogmaerker.tsx` | Bogmærker-skærm | 7 |
| `mobile/src/components/feed/*.tsx` | Ét komponent pr. korttype + `FeedCardView`-switch | 8 |
| `mobile/src/components/HomeTopBar.tsx` | Top-bar (hamburger + brand-på-scroll + bogmærke-badge) | 9 |
| `mobile/src/components/MenuDrawer.tsx` | Venstre slide-in nav-drawer | 10 |
| `mobile/src/app/(tabs)/index.tsx` | Omskrevet forside (top-bar + hero + feed) | 11 |
| Diverse eksisterende skærme | Afgrænset visuel afstemning | 12 |

---

## Task 1: Rene feed-hjælpere (`feedHash.ts`)

**Files:**
- Create: `mobile/src/data/feedHash.ts`
- Test: `mobile/src/data/__tests__/buildFeed.test.ts` (opret filen her; udvides i task 2–5)

**Interfaces:**
- Produces:
  - `stableHash(s: string): number` — deterministisk usigneret 32-bit FNV-1a-hash.
  - `interleave<T>(groups: T[][]): T[]` — fletter grupper round-robin: tag element 0 fra hver ikke-tom gruppe i rækkefølge, så element 1, osv. Bevarer intern gruppe-rækkefølge.

- [ ] **Step 1: Skriv de fejlende tests**

```ts
// mobile/src/data/__tests__/buildFeed.test.ts
import { stableHash, interleave } from '../feedHash';

describe('stableHash', () => {
  it('er deterministisk og usigneret', () => {
    expect(stableHash('p1')).toBe(stableHash('p1'));
    expect(stableHash('p1')).toBeGreaterThanOrEqual(0);
    expect(stableHash('p1')).not.toBe(stableHash('p2'));
  });
});

describe('interleave', () => {
  it('fletter grupper round-robin og springer tomme over', () => {
    expect(interleave([['a1', 'a2', 'a3'], ['b1'], [], ['c1', 'c2']]))
      .toEqual(['a1', 'b1', 'c1', 'a2', 'c2', 'a3']);
  });
  it('tom input → tom liste', () => {
    expect(interleave([])).toEqual([]);
    expect(interleave([[], []])).toEqual([]);
  });
});
```

- [ ] **Step 2: Kør testen — verificér FAIL**

Run: `npm test -- data/__tests__/buildFeed.test.ts`
Expected: FAIL — `Cannot find module '../feedHash'`.

- [ ] **Step 3: Implementér**

```ts
// mobile/src/data/feedHash.ts
// Rene, deterministiske hjælpere til feed-generatoren (buildFeed). Ingen Math.random/Date.now.

// FNV-1a 32-bit → usigneret. Bruges til stabil partition (portrait/citat) + seed-fri ordning.
export function stableHash(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

// Round-robin-fletning af grupper: element 0 fra hver ikke-tom gruppe, så element 1, osv.
export function interleave<T>(groups: T[][]): T[] {
  const out: T[] = [];
  const max = groups.reduce((m, g) => Math.max(m, g.length), 0);
  for (let i = 0; i < max; i++) {
    for (const g of groups) {
      if (i < g.length) out.push(g[i]);
    }
  }
  return out;
}
```

- [ ] **Step 4: Kør testen — verificér PASS**

Run: `npm test -- data/__tests__/buildFeed.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/feedHash.ts mobile/src/data/__tests__/buildFeed.test.ts
git commit -m "feat(feed): rene stableHash + interleave-hjælpere (skive 1)"
```

---

## Task 2: FeedCard-typer + citat-uddrag (`buildFeed.ts`)

**Files:**
- Create: `mobile/src/data/buildFeed.ts`
- Modify: `mobile/src/data/__tests__/buildFeed.test.ts`

**Interfaces:**
- Consumes: `Model`, `Aux` fra `./types`.
- Produces:
  - `FeedCard` (diskrimineret union, se kode) + `FeedOptions` + `FeedOverride`.
  - `firstQuotableSentence(bio: string): string | null` — første sætning på 40–180 tegn, ellers `null`.

- [ ] **Step 1: Skriv den fejlende test**

```ts
// tilføj til buildFeed.test.ts
import { firstQuotableSentence } from '../buildFeed';

describe('firstQuotableSentence', () => {
  it('vælger første sætning i 40–180 tegn', () => {
    const bio = 'Kort. Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke. Mere.';
    expect(firstQuotableSentence(bio)).toBe(
      'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke.',
    );
  });
  it('returnerer null når intet passer', () => {
    expect(firstQuotableSentence('Kort. For lidt.')).toBeNull();
    expect(firstQuotableSentence('')).toBeNull();
  });
});
```

- [ ] **Step 2: Kør — verificér FAIL**

Run: `npm test -- data/__tests__/buildFeed.test.ts`
Expected: FAIL — `firstQuotableSentence` er ikke eksporteret.

- [ ] **Step 3: Implementér typer + citat-hjælper**

```ts
// mobile/src/data/buildFeed.ts
// Ren feed-generator (spec §3). Udleder et redaktionelt FeedCard[] af den eksisterende
// Model/Aux. Ingen backend, ingen Math.random/Date.now — today injiceres.
import type { Model, Aux } from './types';
import { computeRelationship } from './relationship';
import { stableHash, interleave } from './feedHash';

export type FeedCard =
  | { kind: 'portrait'; id: string; personId: string; name: string; years: string;
      initials: string; title: string | null; bio: string; kicker: string }
  | { kind: 'citat'; id: string; personId: string; quote: string; source: string; kicker: string }
  | { kind: 'gods'; id: string; estateId: string; navn: string; meta: string;
      ownerDots: number; kicker: string }
  | { kind: 'forbundet'; id: string; aName: string; bName: string; aInit: string;
      bInit: string; marBottom: string; kicker: string }
  | { kind: 'slaegt'; id: string; aId: string; bId: string; aName: string; bName: string;
      rel: string; foot: string; kicker: string }
  | { kind: 'embede'; id: string; personId: string; label: string; name: string;
      period: string; init: string; kicker: string }
  | { kind: 'jubilaeum'; id: string; personId: string; num: number; name: string;
      sub: string; kicker: string }
  | { kind: 'vaaben'; id: string; armsId: string; blazon: string; foot: string; kicker: string }
  | { kind: 'samle'; id: string; count: number; tail: string; kicker: string };

export type FeedOverride = { pin?: string[]; hide?: string[] };
export interface FeedOptions {
  meId: string | null;
  focusId: string | null;
  today: number;
  overrides?: FeedOverride[];
}

export const FEED_CAPS: Record<FeedCard['kind'], number> = {
  portrait: 12, citat: 4, gods: Infinity, forbundet: 6,
  embede: 6, jubilaeum: 6, vaaben: Infinity, slaegt: 1, samle: 1,
};

const initialsOf = (name: string): string => (name.trim()[0] ?? '?').toUpperCase();

// Første sætning på 40–180 tegn (undgå fragmenter/løb). null hvis intet passer.
export function firstQuotableSentence(bio: string): string | null {
  const parts = bio.split(/(?<=[.!?])\s+/);
  for (const raw of parts) {
    const s = raw.trim();
    if (s.length >= 40 && s.length <= 180) return s;
  }
  return null;
}
```

- [ ] **Step 4: Kør — verificér PASS**

Run: `npm test -- data/__tests__/buildFeed.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/buildFeed.ts mobile/src/data/__tests__/buildFeed.test.ts
git commit -m "feat(feed): FeedCard-typer + firstQuotableSentence (skive 1)"
```

---

## Task 3: Person-kort — portrait/citat-partition

**Files:**
- Modify: `mobile/src/data/buildFeed.ts`, `mobile/src/data/__tests__/buildFeed.test.ts`

**Interfaces:**
- Produces (interne, ikke eksporteret): `buildPortraitAndCitat(model, today): { portraits: FeedCard[]; citater: FeedCard[] }`. En bio-person optræder i højst én af listerne (spec §3.3a).

- [ ] **Step 1: Skriv den fejlende test**

```ts
// tilføj til buildFeed.test.ts
import { buildFeed, type FeedCard } from '../buildFeed';
import type { Model, Aux } from '../types';

// Minimal fixtures. Udvid byId/persons efter behov.
function mkModel(persons: any[]): Model {
  const byId: Record<string, any> = {};
  for (const p of persons) byId[p.id] = p;
  return { persons, byId, indexes: { unionById: {}, spousesBy: {}, childIdx: {},
    parentsByChild: {}, childrenByUnion: {}, konfByEdge: {} } } as unknown as Model;
}
const EMPTY_AUX = { godsListe: [], officesBy: {}, ownersByEstate: {}, vaabenListe: {} ? [] : [],
  estateList: [], estateById: {}, sourcesBy: {}, estatesBy: {}, mediaBy: {}, linjeByPerson: {},
  linjeList: [], linjeNavn: {}, kildeListe: [], orgListe: [], medieListe: [], vaabenListe2: [] } as unknown as Aux;

const LONG_BIO = 'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke her.';
const opts = { meId: null, focusId: null, today: 2026 };

it('samme person bliver ALDRIG både portrait og citat', () => {
  const persons = Array.from({ length: 20 }, (_, i) => ({
    id: 'p' + i, name: 'Person ' + i, born: null, died: null, years: '', title: '', bio: LONG_BIO, privat: false,
  }));
  const cards = buildFeed(mkModel(persons), EMPTY_AUX as Aux, opts);
  const portraitIds = new Set(cards.filter((c) => c.kind === 'portrait').map((c: any) => c.personId));
  const citatIds = cards.filter((c) => c.kind === 'citat').map((c: any) => c.personId);
  for (const id of citatIds) expect(portraitIds.has(id)).toBe(false);
});

it('person uden bio giver intet person-kort', () => {
  const cards = buildFeed(mkModel([{ id: 'x', name: 'Tom', born: null, died: null, years: '', title: '', bio: '   ', privat: false }]), EMPTY_AUX as Aux, opts);
  expect(cards.filter((c) => c.kind === 'portrait' || c.kind === 'citat')).toHaveLength(0);
});
```

> **Bemærk til implementer:** ret `EMPTY_AUX` så den matcher den reelle `Aux`-type i `types.ts` (felterne `godsListe`, `officesBy`, `ownersByEstate`, `vaabenListe` osv.). Ovenstående er en skitse — brug `npx tsc --noEmit` til at få den præcise form. `buildFeed` selv defineres i task 5, men importeres allerede her; testen vil fejle på det indtil task 5. Kør derfor kun de rene dele nu (se step 2).

- [ ] **Step 2: Kør de nye person-partition-asserts isoleret**

For at holde TDD-cyklussen ren: implementér `buildPortraitAndCitat` nu og test den direkte (eksportér den midlertidigt eller test via `buildFeed` i task 5). Anbefaling: eksportér `buildPortraitAndCitat` og skriv en direkte test nu; behold også `buildFeed`-testene (de grønnes i task 5).

Run: `npm test -- data/__tests__/buildFeed.test.ts -t "portrait"`
Expected: FAIL indtil step 3.

- [ ] **Step 3: Implementér partition**

```ts
// tilføj i buildFeed.ts
function buildPortraitAndCitat(
  model: Model,
  _today: number,
): { portraits: FeedCard[]; citater: FeedCard[] } {
  const bioPersons = model.persons
    .filter((p) => p.bio.trim() !== '')
    .sort((a, b) => a.id.localeCompare(b.id));
  const portraits: FeedCard[] = [];
  const citater: FeedCard[] = [];
  for (const p of bioPersons) {
    const isCitatSlot = stableHash(p.id) % 4 === 0; // §3.3a: ~25% citat-kandidater
    if (isCitatSlot) {
      const quote = firstQuotableSentence(p.bio);
      if (quote == null) continue; // falder HELT ud — bliver ikke portræt (undgå overlap)
      citater.push({
        kind: 'citat', id: 'citat:' + p.id, personId: p.id, quote,
        source: p.years ? `${p.name}, ${p.years}` : p.name, kicker: 'Fra Aarbogen',
      });
    } else {
      portraits.push({
        kind: 'portrait', id: 'portrait:' + p.id, personId: p.id, name: p.name,
        years: p.years, initials: initialsOf(p.name), title: p.title !== '' ? p.title : null,
        bio: p.bio, kicker: 'Portræt',
      });
    }
  }
  return { portraits, citater };
}
```

- [ ] **Step 4: Kør — verificér PASS** (de direkte partition-tests)

Run: `npm test -- data/__tests__/buildFeed.test.ts -t "portrait"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/buildFeed.ts mobile/src/data/__tests__/buildFeed.test.ts
git commit -m "feat(feed): portrait/citat disjunkt partition (skive 1)"
```

---

## Task 4: Øvrige korttyper — gods/forbundet/embede/jubilaeum/vaaben/slaegt/samle

**Files:**
- Modify: `mobile/src/data/buildFeed.ts`, `mobile/src/data/__tests__/buildFeed.test.ts`

**Interfaces:**
- Produces (interne): rene bygge-funktioner pr. type, hver returnerer `FeedCard[]` stabilt sorteret efter `id`. Alle udeladelses-regler fra spec §3.2.

- [ ] **Step 1: Skriv de fejlende tests** (jubilæum-tærskel + forbundet-guard + slaegt-guard)

```ts
// tilføj til buildFeed.test.ts
it('jubilæum: 100/150 år → kort; 99 → intet', () => {
  const persons = [
    { id: 'j1', name: 'Hundrede', born: 1926, died: null, years: '', title: '', bio: '', privat: false },
    { id: 'j2', name: 'Nioghalvfems', born: 1927, died: null, years: '', title: '', bio: '', privat: false },
  ];
  const cards = buildFeed(mkModel(persons), EMPTY_AUX as Aux, { meId: null, focusId: null, today: 2026 });
  const jub = cards.filter((c) => c.kind === 'jubilaeum') as any[];
  expect(jub.map((c) => c.personId)).toContain('j1');
  expect(jub.map((c) => c.personId)).not.toContain('j2');
});

it('slaegt-kort kun når både meId og focusId sat og distinkte', () => {
  const persons = [
    { id: 'a', name: 'A', born: null, died: null, years: '', title: '', bio: '', privat: false },
    { id: 'b', name: 'B', born: null, died: null, years: '', title: '', bio: '', privat: false },
  ];
  const m = mkModel(persons);
  expect(buildFeed(m, EMPTY_AUX as Aux, { meId: null, focusId: 'b', today: 2026 })
    .some((c) => c.kind === 'slaegt')).toBe(false);
  // med begge sat kaldes computeRelationship — hvis found:false udelades kortet også (verificér ingen crash)
  expect(() => buildFeed(m, EMPTY_AUX as Aux, { meId: 'a', focusId: 'b', today: 2026 })).not.toThrow();
});
```

- [ ] **Step 2: Kør — verificér FAIL**

Run: `npm test -- data/__tests__/buildFeed.test.ts -t "jubilæum"`
Expected: FAIL indtil task 5 samler `buildFeed`.

- [ ] **Step 3: Implementér bygge-funktionerne**

```ts
// tilføj i buildFeed.ts

// Runde jubilæer: num delelig med 50 og ≥100 (spec: 100/150/200…). Både fødsel og død.
function buildJubilaeer(model: Model, today: number): FeedCard[] {
  const out: FeedCard[] = [];
  for (const p of model.persons) {
    for (const [year, hvad] of [[p.born, 'født'], [p.died, 'død']] as const) {
      if (year == null) continue;
      const num = today - year;
      if (num >= 100 && num % 50 === 0) {
        out.push({
          kind: 'jubilaeum', id: `jubilaeum:${p.id}:${hvad}:${num}`, personId: p.id, num,
          name: p.name, sub: `${num} år siden ${p.name} blev ${hvad}`, kicker: 'Jubilæum',
        });
      }
    }
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

function buildGods(aux: Aux): FeedCard[] {
  return aux.godsListe
    .map((g): FeedCard => ({
      kind: 'gods', id: 'gods:' + g.id, estateId: String(g.id), navn: g.navn,
      meta: g.ownerCount > 0 ? `${g.slags || 'Gods'} · ${g.ownerCount} ejere` : (g.slags || 'Gods'),
      ownerDots: Math.min(g.ownerCount, 7), kicker: 'Gods',
    }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

function buildForbundet(model: Model): FeedCard[] {
  const out: FeedCard[] = [];
  for (const u of Object.values(model.indexes.unionById)) {
    if (u.p2 == null) continue;
    const a = model.byId[u.p1];
    const b = model.byId[u.p2];
    if (!a || !b) continue; // begge personer skal findes (dual-review DS2/NEW1)
    out.push({
      kind: 'forbundet', id: 'forbundet:' + u.id, aName: a.name, bName: b.name,
      aInit: initialsOf(a.name), bInit: initialsOf(b.name),
      marBottom: u.year ? `gift ${u.year}` : 'gift', kicker: 'Forbundet',
    });
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

function buildEmbeder(model: Model, aux: Aux): FeedCard[] {
  const out: FeedCard[] = [];
  for (const [pid, offices] of Object.entries(aux.officesBy)) {
    const p = model.byId[pid];
    if (!p) continue;
    for (const o of offices) {
      out.push({
        kind: 'embede', id: `embede:${pid}:${o.label}:${o._y}`, personId: pid,
        label: o.label, name: p.name, period: o.period, init: initialsOf(p.name), kicker: 'Embede',
      });
    }
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

function buildVaaben(aux: Aux): FeedCard[] {
  return aux.vaabenListe
    .map((v): FeedCard => ({
      kind: 'vaaben', id: 'vaaben:' + v.id, armsId: String(v.id),
      blazon: v.blasonering && v.blasonering.trim() !== '' ? v.blasonering
        : 'Blasoneringen indlæses fra Aarbogen, når våbenet knyttes.',
      foot: 'Se slægtens våben ›', kicker: 'Våben',
    }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

function buildSlaegt(model: Model, meId: string | null, focusId: string | null): FeedCard[] {
  if (!meId || !focusId || meId === focusId) return [];
  const a = model.byId[meId];
  const b = model.byId[focusId];
  if (!a || !b) return [];
  const rel = computeRelationship(model, meId, focusId);
  if (!rel.found) return [];
  return [{
    kind: 'slaegt', id: `slaegt:${meId}:${focusId}`, aId: meId, bId: focusId,
    aName: a.name, bName: b.name, rel: rel.label, foot: 'Se slægtskabet ›', kicker: 'Er I i familie?',
  }];
}
```

- [ ] **Step 4: Kør** — testene grønnes først i task 5 (buildFeed samler dem). Kør `npx tsc --noEmit` for at bekræfte typerne holder.

Run: `npx tsc --noEmit`
Expected: ingen fejl.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/buildFeed.ts mobile/src/data/__tests__/buildFeed.test.ts
git commit -m "feat(feed): gods/forbundet/embede/jubilaeum/vaaben/slaegt-udledning (skive 1)"
```

---

## Task 5: Saml `buildFeed` — caps + interleave + determinisme

**Files:**
- Modify: `mobile/src/data/buildFeed.ts`, `mobile/src/data/__tests__/buildFeed.test.ts`

**Interfaces:**
- Produces: `buildFeed(model: Model, aux: Aux, opts: FeedOptions): FeedCard[]` — offentligt API.

- [ ] **Step 1: Skriv determinisme- + tom-data-testen**

```ts
// tilføj til buildFeed.test.ts
it('er deterministisk: samme input → identisk output', () => {
  const persons = Array.from({ length: 30 }, (_, i) => ({
    id: 'p' + i, name: 'P' + i, born: 1900 + i, died: null, years: '', title: '', bio: LONG_BIO, privat: false,
  }));
  const m = mkModel(persons);
  const a = buildFeed(m, EMPTY_AUX as Aux, opts);
  const b = buildFeed(m, EMPTY_AUX as Aux, opts);
  expect(a).toEqual(b);
});

it('tom model → tom liste', () => {
  expect(buildFeed(mkModel([]), EMPTY_AUX as Aux, opts)).toEqual([]);
});

it('portrait-cap = 12', () => {
  const persons = Array.from({ length: 60 }, (_, i) => ({
    id: 'p' + i, name: 'P' + i, born: null, died: null, years: '', title: '', bio: LONG_BIO, privat: false,
  }));
  const cards = buildFeed(mkModel(persons), EMPTY_AUX as Aux, opts);
  expect(cards.filter((c) => c.kind === 'portrait').length).toBeLessThanOrEqual(12);
});
```

- [ ] **Step 2: Kør — verificér FAIL**

Run: `npm test -- data/__tests__/buildFeed.test.ts`
Expected: FAIL — `buildFeed` ikke defineret.

- [ ] **Step 3: Implementér samlingen**

```ts
// tilføj i buildFeed.ts
function cap(cards: FeedCard[], kind: FeedCard['kind']): FeedCard[] {
  const n = FEED_CAPS[kind];
  return n === Infinity ? cards : cards.slice(0, n);
}

export function buildFeed(model: Model, aux: Aux, opts: FeedOptions): FeedCard[] {
  if (model.persons.length === 0) return [];
  const { portraits, citater } = buildPortraitAndCitat(model, opts.today);
  const groups: FeedCard[][] = [
    cap(portraits, 'portrait'),
    cap(buildGods(aux), 'gods'),
    cap(buildForbundet(model), 'forbundet'),
    cap(citater, 'citat'),
    cap(buildEmbeder(model, aux), 'embede'),
    cap(buildJubilaeer(model, opts.today), 'jubilaeum'),
    cap(buildVaaben(aux), 'vaaben'),
    cap(buildSlaegt(model, opts.meId, opts.focusId), 'slaegt'),
  ];
  const cards = interleave(groups);
  // 'samle'-kort til sidst hvis der overhovedet er indhold (spec §3.2). Overrides anvendes her
  // i en fremtidig redaktionel version (opts.overrides er tom nu).
  return cards;
}
```

> **Bemærk:** `samle`-kortet og `overrides`-anvendelsen er bevidst minimal nu (PoC). Tilføj et `samle`-kort kun hvis produktet ønsker "…og N flere"-blokken; ellers udelad. Hold `opts.overrides` som en no-op indtil den redaktionelle kilde bygges.

- [ ] **Step 4: Kør — verificér PASS (hele filen)**

Run: `npm test -- data/__tests__/buildFeed.test.ts`
Expected: PASS (alle buildFeed-tests, inkl. task 3-4's).

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/buildFeed.ts mobile/src/data/__tests__/buildFeed.test.ts
git commit -m "feat(feed): saml buildFeed — caps + interleave + determinisme (skive 1)"
```

---

## Task 6: Bogmærke-lager + hook (`lib/bookmarks.ts`)

**Files:**
- Create: `mobile/src/lib/bookmarks.ts`, `mobile/src/lib/__tests__/bookmarks.test.ts`

**Interfaces:**
- Consumes: `@react-native-async-storage/async-storage` (default export `AsyncStorage`), `Model` fra `../data/types`.
- Produces:
  - `BOOKMARKS_KEY = 'daa_bookmarks'`.
  - `createLocalBookmarkStore(): { list(): Promise<string[]>; toggle(id: string): Promise<string[]> }`.
  - `useBookmarks(canonicalIdById: Record<string,string>): { ids: Set<string>; has(id: string): boolean; toggle(id: string): void; count: number }`.

- [ ] **Step 1: Konfigurér AsyncStorage-jest-mock**

AsyncStorage 2.2.0 leverer en mock. Tilføj i `mobile/jest.config.js` (eller test-setup) om nødvendigt:

```js
// jest.config.js — sikr at mocken bruges (jest-expo klarer typisk dette; hvis ikke:)
setupFiles: ['<rootDir>/node_modules/@react-native-async-storage/async-storage/jest/async-storage-mock.js'],
```

Verificér først om det allerede virker uden (jest-expo preset). Kør step 2's test; tilføj kun setup hvis mocken mangler.

- [ ] **Step 2: Skriv de fejlende tests (inkl. async/race — dual-review NEW3)**

```ts
// mobile/src/lib/__tests__/bookmarks.test.ts
import { renderHook, act, waitFor } from '@testing-library/react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createLocalBookmarkStore, useBookmarks, BOOKMARKS_KEY } from '../bookmarks';

beforeEach(async () => { await AsyncStorage.clear(); });

describe('createLocalBookmarkStore', () => {
  it('toggle tilføjer nyeste-først og fjerner igen', async () => {
    const s = createLocalBookmarkStore();
    expect(await s.toggle('a')).toEqual(['a']);
    expect(await s.toggle('b')).toEqual(['b', 'a']);
    expect(await s.toggle('a')).toEqual(['b']);
  });
});

describe('useBookmarks', () => {
  it('hydrerer fra lageret og eksponerer has() synkront', async () => {
    await AsyncStorage.setItem(BOOKMARKS_KEY, JSON.stringify(['x']));
    const { result } = renderHook(() => useBookmarks({ x: 'x' }));
    await waitFor(() => expect(result.current.has('x')).toBe(true));
    expect(result.current.count).toBe(1);
  });

  it('canonicaliserer via mappet (alias → kanonisk)', async () => {
    await AsyncStorage.setItem(BOOKMARKS_KEY, JSON.stringify(['alias1']));
    const { result } = renderHook(() => useBookmarks({ alias1: 'canon1' }));
    await waitFor(() => expect(result.current.has('alias1')).toBe(true));
    expect(result.current.has('canon1')).toBe(true);
    expect([...result.current.ids]).toEqual(['canon1']);
  });

  it('hurtige toggles taber ikke bogmærker (seneste-vinder)', async () => {
    const { result } = renderHook(() => useBookmarks({}));
    await act(async () => { result.current.toggle('a'); result.current.toggle('b'); });
    await waitFor(() => expect(result.current.ids.size).toBe(2));
  });
});
```

- [ ] **Step 3: Kør — verificér FAIL**

Run: `npm test -- lib/__tests__/bookmarks.test.ts`
Expected: FAIL — modul findes ikke.

- [ ] **Step 4: Implementér lager + hook**

```ts
// mobile/src/lib/bookmarks.ts
// Bogmærke-lager (spec §6). Async AsyncStorage-repo + synkron render-state-hook. Spejler
// web/src/data/bookmarks.ts, men async — se dual-review 20 (BM1/BM2).
import { useEffect, useMemo, useRef, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

export const BOOKMARKS_KEY = 'daa_bookmarks';

async function safeRead(): Promise<string[]> {
  try {
    const raw = await AsyncStorage.getItem(BOOKMARKS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((x): x is string => typeof x === 'string') : [];
  } catch { return []; }
}
async function safeWrite(ids: string[]): Promise<void> {
  try { await AsyncStorage.setItem(BOOKMARKS_KEY, JSON.stringify(ids)); } catch { /* ikke-kritisk */ }
}

export function createLocalBookmarkStore() {
  return {
    list: () => safeRead(),
    toggle: async (id: string): Promise<string[]> => {
      const cur = await safeRead();
      const next = cur.includes(id) ? cur.filter((x) => x !== id) : [id, ...cur];
      await safeWrite(next);
      return next;
    },
  };
}

// Nyeste-først dedup til kanoniske id'er (første forekomst vinder).
function canonicalize(raw: string[], canon: (id: string) => string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of raw) {
    const cid = canon(id);
    if (!seen.has(cid)) { seen.add(cid); out.push(cid); }
  }
  return out;
}

export function useBookmarks(canonicalIdById: Record<string, string>): {
  ids: Set<string>; has(id: string): boolean; toggle(id: string): void; count: number;
} {
  const storeRef = useRef<ReturnType<typeof createLocalBookmarkStore> | null>(null);
  if (!storeRef.current) storeRef.current = createLocalBookmarkStore();
  const store = storeRef.current;

  const [idsList, setIdsList] = useState<string[]>([]);
  // Memoiseret canon udledt af MAPPET (ikke en funktionsreference) — dual-review BM2/D.
  const canon = useMemo(() => (id: string) => canonicalIdById[id] ?? id, [canonicalIdById]);

  // Hydrering + re-normalisering: kør når mappet skifter identitet (recollapse).
  useEffect(() => {
    let alive = true;
    void store.list().then((raw) => {
      if (!alive) return;
      const norm = canonicalize(raw, canon);
      setIdsList((prev) => (sameOrder(prev, norm) ? prev : norm));
    });
    return () => { alive = false; };
  }, [store, canon]);

  const ids = useMemo(() => new Set(idsList), [idsList]);

  const toggle = (id: string) => {
    const cid = canon(id);
    // Optimistisk state-opdatering (seneste-vinder); persistér async.
    setIdsList((prev) => {
      const next = prev.includes(cid) ? prev.filter((x) => x !== cid) : [cid, ...prev];
      void safeWrite(next);
      return next;
    });
  };

  return { ids, has: (id) => ids.has(canon(id)), toggle, count: idsList.length };
}

function sameOrder(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}
```

> **Bemærk race-sikkerhed:** `toggle` skriver via den funktionelle `setIdsList`-updater, så samtidige toggles bygger oven på hinandens seneste state (ingen tabt opdatering). `safeWrite(next)` persisterer den nyeste liste; sidste skrivning vinder. Hydrerings-effekten skriver aldrig oven i en igangværende toggle, fordi den kun sætter state når `sameOrder` er falsk og kører på mount/recollapse.

- [ ] **Step 5: Kør — verificér PASS**

Run: `npm test -- lib/__tests__/bookmarks.test.ts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/src/lib/bookmarks.ts mobile/src/lib/__tests__/bookmarks.test.ts mobile/jest.config.js
git commit -m "feat(bogmaerker): async bogmærke-lager + useBookmarks-hook (skive 4)"
```

---

## Task 7: Bogmærker-skærm (`app/bogmaerker.tsx`)

**Files:**
- Create: `mobile/src/app/bogmaerker.tsx`

**Interfaces:**
- Consumes: `useBookmarks`, `useStore` (`model`, `canonicalIdById`), `InitialBadge`, `Typography`, `LoadGate`.

- [ ] **Step 1: Implementér skærmen** (markup-mønster fra design `isSaved`-blok)

```tsx
// mobile/src/app/bogmaerker.tsx
// Bogmærker-skærm (spec §6.3). Person-rækker fra gemte kanoniske id'er.
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { InitialBadge } from '../components/InitialBadge';
import { LoadGate } from '../components/LoadGate';
import { Body, Serif } from '../components/Typography';
import { useBookmarks } from '../lib/bookmarks';
import { useStore } from '../store/useStore';
import { Border, Colors } from '../theme/tokens';

export default function BogmaerkerScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const canonMap = useStore((s) => s.canonicalIdById);
  const { ids } = useBookmarks(canonMap);

  const people = model ? [...ids].map((id) => model.byId[id]).filter(Boolean) : [];

  return (
    <LoadGate>
      <ScrollView style={{ flex: 1, backgroundColor: Colors.paperBg }}
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: 18, paddingBottom: 30 }}>
        {people.length === 0 ? (
          <Body size={13} color={Colors.textSecondary2} style={{ marginTop: 20 }}>
            Du har endnu ikke gemt nogen blade. Tryk bogmærke-ikonet på et kort i feedet.
          </Body>
        ) : (
          <>
            <Body size={13} color={Colors.textSecondary2} style={{ marginBottom: 14 }}>
              Blade du har gemt fra feedet.
            </Body>
            {people.map((p) => (
              <Pressable key={p.id}
                onPress={() => router.push(`/person/${p.id}`)}
                style={{ flexDirection: 'row', alignItems: 'center', gap: 13, paddingVertical: 12,
                  borderBottomWidth: 1, borderBottomColor: Border.faint }}>
                <InitialBadge letter={p.name[0]?.toUpperCase() ?? '?'} size={42} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={18} style={{ lineHeight: 19 }}>{p.name}</Serif>
                  {p.years ? <Body size={11.5} color={Colors.textSecondary2}>{p.years}</Body> : null}
                </View>
                <Serif size={18} color="#bcae93">›</Serif>
              </Pressable>
            ))}
          </>
        )}
      </ScrollView>
    </LoadGate>
  );
}
```

> **Bemærk:** verificér `InitialBadge`-prop-navnene mod `components/InitialBadge.tsx` (kan hedde `letter`/`size` eller andet) og ret kaldet. Registrér ruten i router om nødvendigt (expo-router file-based — `app/bogmaerker.tsx` giver ruten `/bogmaerker` automatisk; sikr at `_layout.tsx` ikke skjuler den).

- [ ] **Step 2: Typecheck + smoke**

Run: `npx tsc --noEmit`
Expected: ingen fejl.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/app/bogmaerker.tsx
git commit -m "feat(bogmaerker): bogmærker-skærm med gemte person-rækker (skive 4)"
```

---

## Task 8: Feed-kort-komponenter (`components/feed/`)

**Files:**
- Create: `mobile/src/components/feed/FeedCardView.tsx` (switch på `card.kind`) + ét komponent pr. type.

**Interfaces:**
- Consumes: `FeedCard` fra `../../data/buildFeed`; `tokens.ts`; eksisterende `InitialBadge`, `StripedPlaceholder`, `Typography`.
- Produces: `FeedCardView({ card, onOpen, onSave, bookmarked }: { card: FeedCard; onOpen: (card: FeedCard) => void; onSave: (personId: string) => void; bookmarked: boolean }): JSX.Element`.

**Regel:** gem-ikonet rendres **iff `'personId' in card`** (portrait/citat/embede/jubilaeum). Markup pr. type tages 1:1 fra design-filens `sc-if card.isXxx`-blokke — oversæt inline-CSS til RN-styles med `tokens.ts`-værdier (farverne matcher allerede).

- [ ] **Step 1: Byg `FeedCardView` + ét eksemplar-kort (PortraitCard) fuldt**

```tsx
// mobile/src/components/feed/FeedCardView.tsx
import { Pressable, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import type { FeedCard } from '../../data/buildFeed';
import { Body, Kicker, Mono, Serif } from '../Typography';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';

function SaveIcon({ filled, onPress }: { filled: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} hitSlop={8}>
      <Svg width={15} height={17} viewBox="0 0 17 19">
        <Path d="M3 2.2h11a1 1 0 0 1 1 1V16.4a.6.6 0 0 1-.94.5L8.5 13.4l-4.56 3.5A.6.6 0 0 1 3 16.4V3.2a1 1 0 0 1 1-1Z"
          fill={filled ? Colors.bordeaux : 'none'} stroke={filled ? Colors.bordeaux : '#7a7060'} strokeWidth={1.3} />
      </Svg>
    </Pressable>
  );
}

export function FeedCardView({ card, onOpen, onSave, bookmarked }:
  { card: FeedCard; onOpen: (c: FeedCard) => void; onSave: (personId: string) => void; bookmarked: boolean }) {
  const save = 'personId' in card ? (
    <SaveIcon filled={bookmarked} onPress={() => onSave((card as any).personId)} />
  ) : null;

  switch (card.kind) {
    case 'portrait':
      return (
        <View style={{ backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
          borderRadius: Radius.card, padding: 15, ...Shadow.card }}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
            <Kicker size={8.5} color={Colors.bordeaux}>{card.kicker}</Kicker>
            {save}
          </View>
          <Serif size={24} style={{ marginTop: 5, lineHeight: 24 }}>{card.name}</Serif>
          <Mono size={10} color={Colors.textMuted2} style={{ marginTop: 4 }}>{card.years}</Mono>
          {card.title ? <Body size={12} color={Colors.bordeaux} style={{ marginTop: 4, fontFamily: Fonts.sansMedium }}>{card.title}</Body> : null}
          <Body size={13} color={Colors.textSecondary} numberOfLines={5} style={{ marginTop: 11, lineHeight: 20 }}>{card.bio}</Body>
          <Pressable onPress={() => onOpen(card)} style={{ paddingVertical: 10 }}>
            <Body size={12.5} color={Colors.bordeaux} style={{ fontFamily: Fonts.sansSemi }}>Læs mere ›</Body>
          </Pressable>
        </View>
      );
    // TODO(implementer): citat, gods, forbundet, slaegt, embede, jubilaeum, vaaben, samle —
    // ét case pr. type, markup fra design-filens sc-if card.isXxx-blok, styles fra tokens.ts.
    default:
      return null;
  }
}
```

- [ ] **Step 2: Implementér de resterende 8 cases**

Oversæt hver `sc-if card.isXxx`-blok fra `Reventlow-folgesvend-v3.dc.html` til et RN-`case`. Felt-mapping (design-binding → `FeedCard`-felt):

| kind | design-bindinger → kort-felter |
|---|---|
| `citat` | `card.quote`→`quote`, `card.citSource`→`source`; mørkt kort (`Colors.ink`-bg), gem-ikon lyst |
| `gods` | `card.godsName`→`navn`, `card.godsMeta`→`meta`, `card.dots`→`ownerDots` (render N prikker); helt kort `onOpen` |
| `forbundet` | `card.aName/bName/aInit/bInit`, `card.marBottom`; beige-kort, to avatarer m. `&` |
| `slaegt` | `card.slA/slB/slRel`→`aName/bName/rel`, `card.slFoot`→`foot`; mørkt kort; `onOpen` |
| `embede` | `card.eLabel/eName/ePeriod/eInit`→`label/name/period/init`; `onOpen` |
| `jubilaeum` | `card.jNum/jName/jSub`→`num/name/sub`; venstre stor tal-kolonne |
| `vaaben` | `card.blazon/vFoot`→`blazon/foot` + `StripedPlaceholder` for skjold; `onOpen` |
| `samle` | `card.samleCount/samleTail`→`count/tail`; stiplet kort |

Ingen ny test her (UI); verifikation via `tsc` + simulator (task 12/verifikation).

- [ ] **Step 3: Typecheck**

Run: `npx tsc --noEmit`
Expected: ingen fejl.

- [ ] **Step 4: Commit**

```bash
git add mobile/src/components/feed/
git commit -m "feat(feed): kort-komponenter for alle 9 korttyper (skive 2)"
```

---

## Task 9: HomeTopBar (`components/HomeTopBar.tsx`)

**Files:**
- Create: `mobile/src/components/HomeTopBar.tsx`

**Interfaces:**
- Produces: `HomeTopBar({ onMenu, onBookmarks, savedCount, showBrand }: { onMenu: () => void; onBookmarks: () => void; savedCount: number; showBrand: boolean })`.

- [ ] **Step 1: Implementér** (markup fra design `isHome`-topbar-blok: hamburger venstre, kompakt brand midt (fader ind når `showBrand`), bogmærke-ikon + badge højre).

Brug `Colors`, `Fonts`; badge vises kun når `savedCount > 0`. Brand-opacity styres af `showBrand` (Animated valgfrit; en simpel `opacity: showBrand ? 1 : 0` med `Animated.timing` er nok).

- [ ] **Step 2: Typecheck + commit**

Run: `npx tsc --noEmit`

```bash
git add mobile/src/components/HomeTopBar.tsx
git commit -m "feat(feed): HomeTopBar med hamburger, brand-på-scroll, bogmærke-badge (skive 2)"
```

---

## Task 10: MenuDrawer (`components/MenuDrawer.tsx`)

**Files:**
- Create: `mobile/src/components/MenuDrawer.tsx`

**Interfaces:**
- Consumes: `useRouter`, `useStore` (auth-state til konto-footer), `CrestRing`, `SlaegtPicker`.
- Produces: `MenuDrawer({ visible, onClose }: { visible: boolean; onClose: () => void })`.

- [ ] **Step 1: Implementér** venstre slide-in (design `drawerX`-blok):
  - `Modal transparent visible={visible}` + scrim `Pressable` (lukker) + `Animated.View` width 314, `translateX` fra `-314`→`0`.
  - Header: `CrestRing` + "Slægt / Reventlow" + "Skift slægt ▾" (åbner `SlaegtPicker`).
  - Nav-liste (nummereret, samme 01–08 som forsiden i dag PLUS Bogmærker): hvert punkt `router.push(href)` + `onClose`. Ruter: `/tree`, `/about`, `/estates`, `/kort`, `/arms`, `/relate`, `/search`, `/konto`, `/bogmaerker`.
  - Konto-footer: logget ind → navn + log ud; ellers "Log ind" → `/konto`.

- [ ] **Step 2: Typecheck + commit**

Run: `npx tsc --noEmit`

```bash
git add mobile/src/components/MenuDrawer.tsx
git commit -m "feat(drawer): venstre menu-drawer med nav-liste + konto-footer (skive 3)"
```

---

## Task 11: Omskriv forsiden (`app/(tabs)/index.tsx`)

**Files:**
- Modify: `mobile/src/app/(tabs)/index.tsx` (erstat body; **fjern** 01–08 udforsk-listen — den bor nu i drawer'en)

**Interfaces:**
- Consumes: `buildFeed`, `useBookmarks`, `FeedCardView`, `HomeTopBar`, `MenuDrawer`, `useStore`.

- [ ] **Step 1: Implementér** ny forside:
  - Lokal state: `drawerOpen`, scroll-offset (til brand-på-scroll + hero-kollaps).
  - `const cards = useMemo(() => model && aux ? buildFeed(model, aux, { meId, focusId, today: new Date().getFullYear() }) : [], [model, aux, meId, focusId])`.
  - `const { has, toggle, count } = useBookmarks(canonicalIdById)`.
  - `<FlatList data={cards} keyExtractor={c => c.id} ListHeaderComponent={<Hero/>} ListFooterComponent={<LoaderFooter/>} renderItem={({item}) => <View style={{paddingHorizontal:16, paddingTop:13}}><FeedCardView card={item} bookmarked={'personId' in item ? has(item.personId) : false} onSave={toggle} onOpen={openCard}/></View>} />`.
  - `openCard(card)`: switch på `kind` → `router.push`. For `slaegt`: `setRelA(card.aId); setRelB(card.bId); router.push('/relate')`. For `gods`: `/estate/${card.estateId}`. For `vaaben`: `/arms`. For person-kort: `/person/${card.personId}`.
  - `<HomeTopBar onMenu={() => setDrawerOpen(true)} onBookmarks={() => router.push('/bogmaerker')} savedCount={count} showBrand={scrollY > 120}/>`.
  - `<MenuDrawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />`.
  - Behold hero (logo, "Slægten Reventlow", tællere, "skift slægt ▾") som `ListHeaderComponent`.

- [ ] **Step 2: Kør fuld suite + typecheck**

Run: `npx tsc --noEmit && npm test`
Expected: tsc rent; alle tests grønne (264+ plus de nye buildFeed/bookmarks).

- [ ] **Step 3: Commit**

```bash
git add mobile/src/app/(tabs)/index.tsx
git commit -m "feat(feed): omskriv forside til feed + top-bar + drawer (skive 2/3)"
```

---

## Task 12: Visuel afstemning (afgrænset)

**Files:**
- Modify: eksisterende skærme efter behov (about/estates/estate/arms/tree/person/search/relate)

- [ ] **Step 1:** Åbn appen i iOS-simulator mod prod-data (jf. memory `mobil-fysisk-enhed-setup` / `mobil-sim-rn-fetch-1005`). Sammenlign hver skærm mod `Reventlow-folgesvend-v3.dc.html`.
- [ ] **Step 2:** Ret KUN klare, små afvigelser (top-bar-titelfont, tilbageknap-stil, afstande, kicker-casing). Alt der kræver reel genopbygning: notér i `docs/changelog.md` som opfølgning, byg ikke her.
- [ ] **Step 3:** `npx tsc --noEmit && npm test`; commit pr. logisk rettelse.

---

## Verifikation (afsluttende)

- [ ] `npx tsc --noEmit` rent.
- [ ] `npm test` — hele suiten grøn (264 eksisterende + buildFeed + bookmarks).
- [ ] iOS-simulator mod prod: forside rendrer feed; kort navigerer korrekt (person/gods/arms/relate); slaegt-kort sætter relate-slots; hamburger åbner drawer; drawer-nav navigerer; gem-ikon toggler + badge opdaterer; Bogmærker-skærm viser gemte; genstart bevarer bogmærker (AsyncStorage).
- [ ] Opdater `docs/changelog.md` + `docs/decisions.md` + relevant memory.

---

## Self-review-noter (udført ved skrivning)

- **Spec-dækning:** §3 (feed) → task 1-5; §4 (forside) → task 8-11; §5 (drawer) → task 10; §6 (bogmærker) → task 6-7; §7 (visuel) → task 12. Alle dual-review-fund (DS1-4, A-D, BM1-2, NEW1-3) er indarbejdet i task-koden.
- **Type-konsistens:** `FeedCard`-felter defineret i task 2 bruges uændret i task 3-5 + 8 + 11. `useBookmarks(canonicalIdById)`-signaturen er ens i task 6, 7, 11.
- **Kendt approksimation:** UI-tasks (8-11) giver ét fuldt eksemplar + præcis felt-mapping frem for fuld RN-kode for hver blok, fordi design-HTML'en er den autoritative markup-kilde; implementer oversætter blok-for-blok. Dette er bevidst for at undgå divergens mellem plan og design.
