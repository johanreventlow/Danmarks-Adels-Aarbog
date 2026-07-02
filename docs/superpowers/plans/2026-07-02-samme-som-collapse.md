# samme_som-collapse — Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vis en person der optræder som flere DB-poster (via `samme_som`-relationer) som ÉN person i web+mobile — søgning, person-visning og slægtskabsfinder — via en valideret, reversibel identitets-projektion FØR `buildModel`.

**Architecture:** En ren funktion `collapseSameAs(rawDb, edges, ext, visibility)` grupperer `samme_som`-linkede id'er (union-find), vælger en kanonisk id pr. gruppe, validerer (karantænerer konflikter), fletter person-posterne og omskriver alle graf-kanter til kanoniske id'er. `buildModel` + `relationship.ts` (slægtskabs-motoren) forbliver URØRT. Spejles i web (vitest, state i `Folgesvend.tsx`) og mobile (jest, Zustand-store) — de har allerede duplikerede `buildModel.ts`/`relationship.ts`.

**Tech Stack:** TypeScript. Web: vitest (`cd web && npm test`). Mobile: jest (`cd mobile && npm test`). Supabase (`@supabase/supabase-js`).

**Spec:** `docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md` (dual-reviewet).

## Global Constraints

- **Motoren urørt:** `relationship.ts` og `buildModel.ts` ændres IKKE. Projektionen sker før `buildModel`.
- **Reversibel, ikke lossy:** returnér `canonicalIdById` (ethvert medlems-id → kanonisk) + `mergedFrom` + `quarantined`. Rå-data bevares.
- **Kanonisk = unik sink:** `samme_som` er retningsbestemt (`subjekt`=alias, `objekt`=kanonisk). Kanonisk = medlem med alias-outdegree 0. Ingen unik sink / manglende endpoint / ufuldstændig komponent → **karantæne** (foldes ikke).
- **Kun `afklaret` links foldes** (redaktionelt blåstemplet).
- **GDPR = completeness + RLS:** fold kun grupper hvor ALLE medlemmer + ALLE kanter er til stede i de hentede data. Ingen klient-side `privat`-guard. Synlighed afhænger af `levende` OG `privat` (RLS håndterer). `privat=OR` ved merge for robusthed.
- **Konflikt-karantæne på KOMBINERET graf FØR drop:** self-edge, global cyklus, konkurrerende ikke-tomme forældre, tvetydig kanonisk, hard vital/køn-konflikt.
- **`years` regenereres** fra coalescede `born/died` (bruges af sti-visning; forkert år kan lydløst fjerne parent-child-kant i `buildModel`).
- **Aux: ALLE person-id-strukturer kanoniseres** (`linjeByPerson`→`string[]`, `ownersByEstate[].personId`, `linjeList.headId`, `meId`, narrativ-union).
- **Private data må aldrig coalesces ind i publikums-projektionen** (RLS sikrer for anon/medlem; redaktions-model separat).
- **AppPerson-felter:** `{id, name, born, died, years, title, bio, privat, koen?}`. `Db = {persons: AppPerson[], unions: Union[], parentChild: ParentChild[]}`. `ParentChild = {child, parent, union, konfidens?}`. `Union = {id, p1, p2, p2_name, year}`.
- **Commits:** Conventional Commits (dansk), ingen Claude-attribution, slut med `Claude-Session: https://claude.ai/code/session_01Ws352N6tioJs1Qf5VuVbia`.

---

## Fil-struktur

| Fil | Ansvar |
|---|---|
| `mobile/src/data/collapseSameAs.ts` (ny) | Kerne: gruppering + validering + merge (ren) |
| `mobile/src/data/__tests__/collapseSameAs.test.ts` (ny) | Jest-tests af kernen |
| `mobile/src/data/load.ts` (mod) | Fetch `samme_som` + kald `collapseSameAs` før `buildModel`; returnér alias-map |
| `mobile/src/data/buildAux.ts` (mod) | Kanonisér id-strukturer; `linjeByPerson`→multi; narrativ-union |
| `mobile/src/data/types.ts` (mod) | `SameAsEdge`, `Provenance`, `CollapseResult`, `linjeByPerson: Record<string,string[]>`, `ModelPerson.mergedFrom?` |
| `mobile/src/store/useStore.ts` (mod) | Gem `canonicalIdById`/`mergedFrom`; resolv `meId` |
| `mobile/src/app/person/[id].tsx` (mod) | Alias-resolution + proveniens-badge |
| `web/src/data/collapseSameAs.ts` (ny) | Spejl af mobile-kernen |
| `web/src/data/__tests__/collapseSameAs.test.ts` (ny) | Vitest-port af kerne-tests |
| `web/src/data/model.ts` (mod) | Fetch + kald før `buildModel`; returnér alias-map |
| `web/src/data/public.ts` (mod) | Person-detalje for alle medlems-id'er + narrativ-union |
| `web/src/data/types.ts` (mod) | Spejl af type-tilføjelser |
| `web/src/Folgesvend.tsx` (mod) | Thread alias-map gennem state; resolv `meId`/fokus; badge |

---

## FASE A — Kerne-motor (mobile først; bedst test-infra)

### Task 1: Gruppering + kanonisk sink

**Files:**
- Create: `mobile/src/data/collapseSameAs.ts`
- Modify: `mobile/src/data/types.ts` (tilføj typer)
- Test: `mobile/src/data/__tests__/collapseSameAs.test.ts`

**Interfaces:**
- Produces: `type SameAsEdge = { alias: string; canonical: string }`. `type Provenance = { personId: string; linje: string | null; nr: number | null }`. `type QuarantineNote = { members: string[]; reason: string }`. `groupSameAs(edges: SameAsEdge[], knownIds: Set<string>): { groups: Map<string, string[]>; quarantined: QuarantineNote[] }` — `groups` mapper kanonisk-id → medlems-id'er (inkl. kanonisk selv). Grupper uden unik sink / med ukendt endpoint returneres i `quarantined`, ikke `groups`.

- [ ] **Step 1: Tilføj typer til `mobile/src/data/types.ts`**

```ts
export type SameAsEdge = { alias: string; canonical: string };
export type Provenance = { personId: string; linje: string | null; nr: number | null };
export type QuarantineNote = { members: string[]; reason: string };
```

- [ ] **Step 2: Skriv de fejlende tests**

`mobile/src/data/__tests__/collapseSameAs.test.ts`:
```ts
import { groupSameAs } from '../collapseSameAs';

const known = (...ids: string[]) => new Set(ids);

describe('groupSameAs', () => {
  it('par: objekt = kanonisk', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }], known('A', 'B'));
    expect(quarantined).toEqual([]);
    expect([...groups.entries()]).toEqual([['B', expect.arrayContaining(['A', 'B'])]]);
  });
  it('kæde A→B, B→C → C kanonisk', () => {
    const { groups } = groupSameAs([{ alias: 'A', canonical: 'B' }, { alias: 'B', canonical: 'C' }], known('A', 'B', 'C'));
    expect([...groups.keys()]).toEqual(['C']);
    expect(groups.get('C')!.sort()).toEqual(['A', 'B', 'C']);
  });
  it('tvetydig sink A→B, A→C → karantæne', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }, { alias: 'A', canonical: 'C' }], known('A', 'B', 'C'));
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/sink/i);
  });
  it('retnings-cyklus A→B, B→A → karantæne', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }, { alias: 'B', canonical: 'A' }], known('A', 'B'));
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/sink|cyklus/i);
  });
  it('ufuldstændig komponent (endpoint mangler) → karantæne', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }], known('B'));
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/ufuldstændig|mangler/i);
  });
  it('duplikerede kanter normaliseres', () => {
    const { groups } = groupSameAs([{ alias: 'A', canonical: 'B' }, { alias: 'A', canonical: 'B' }], known('A', 'B'));
    expect(groups.get('B')!.sort()).toEqual(['A', 'B']);
  });
});
```

- [ ] **Step 3: Kør — fejler**

Run: `cd mobile && npx jest collapseSameAs`
Expected: FAIL — `Cannot find module '../collapseSameAs'`.

- [ ] **Step 4: Implementér `groupSameAs`**

`mobile/src/data/collapseSameAs.ts`:
```ts
import type { SameAsEdge, QuarantineNote } from './types';

// Union-find over samme_som-kanter → grupper. Kanonisk = unik sink (alias-outdegree 0).
// Karantæne hvis: ingen unik sink, retnings-cyklus, eller endpoint ukendt (ufuldstændig
// komponent — RLS kan have skjult en tvilling). Reversibel: kalder får medlems-lister.
export function groupSameAs(
  edges: SameAsEdge[],
  knownIds: Set<string>,
): { groups: Map<string, string[]>; quarantined: QuarantineNote[] } {
  // Normalisér: fjern dubletter + self-loops.
  const norm = new Map<string, SameAsEdge>();
  for (const e of edges) {
    if (e.alias === e.canonical) continue;
    norm.set(`${e.alias}->${e.canonical}`, e);
  }
  const edgeList = [...norm.values()];

  // Union-find (uden retning) → komponenter.
  const parent = new Map<string, string>();
  const find = (x: string): string => {
    parent.set(x, parent.get(x) ?? x);
    let r = x; while (parent.get(r) !== r) r = parent.get(r)!;
    while (parent.get(x) !== r) { const n = parent.get(x)!; parent.set(x, r); x = n; }
    return r;
  };
  const union = (a: string, b: string) => { parent.set(find(a), find(b)); };
  for (const e of edgeList) { find(e.alias); find(e.canonical); union(e.alias, e.canonical); }

  // Komponent-medlemmer + alias-outdegree (antal kanter hvor noden er alias).
  const members = new Map<string, Set<string>>();
  const isAlias = new Map<string, boolean>();
  for (const id of parent.keys()) {
    const r = find(id);
    (members.get(r) ?? members.set(r, new Set()).get(r)!).add(id);
    if (!isAlias.has(id)) isAlias.set(id, false);
  }
  for (const e of edgeList) isAlias.set(e.alias, true);

  const groups = new Map<string, string[]>();
  const quarantined: QuarantineNote[] = [];
  for (const [, mem] of members) {
    const ids = [...mem];
    const missing = ids.filter((id) => !knownIds.has(id));
    if (missing.length) { quarantined.push({ members: ids, reason: `ufuldstændig komponent (mangler ${missing.join(',')})` }); continue; }
    const sinks = ids.filter((id) => !isAlias.get(id)); // aldrig alias = sink-kandidat
    if (sinks.length !== 1) { quarantined.push({ members: ids, reason: `ingen unik sink (kandidater: ${sinks.join(',') || 'ingen'})` }); continue; }
    groups.set(sinks[0], ids);
  }
  return { groups, quarantined };
}
```

- [ ] **Step 5: Kør — grøn**

Run: `cd mobile && npx jest collapseSameAs`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/collapseSameAs.ts mobile/src/data/types.ts mobile/src/data/__tests__/collapseSameAs.test.ts
git commit -m "feat(mobile): samme_som gruppering + kanonisk sink (collapseSameAs Task 1)"
```

---

### Task 2: Validering + karantæne på kombineret graf

**Files:**
- Modify: `mobile/src/data/collapseSameAs.ts`
- Test: `mobile/src/data/__tests__/collapseSameAs.test.ts`

**Interfaces:**
- Consumes: `groupSameAs` (Task 1); `Db`, `AppPerson`, `ParentChild` fra `types.ts`.
- Produces: `validateGroups(groups: Map<string,string[]>, rawDb: Db): { accepted: Map<string,string[]>; quarantined: QuarantineNote[] }`. Validerer på den KOMBINEREDE projicerede forældre-graf (alle grupper anvendt): selv-forælder, global cyklus, konkurrerende ikke-tomme forældre, hard vital/køn-konflikt. Kanoniser-map bygges internt fra `groups`.

- [ ] **Step 1: Skriv de fejlende tests**

Tilføj til `collapseSameAs.test.ts`:
```ts
import { validateGroups } from '../collapseSameAs';
import type { Db, AppPerson } from '../types';

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o });
const db = (persons: AppPerson[], parentChild: Db['parentChild']): Db => ({ persons, unions: [], parentChild });

describe('validateGroups', () => {
  it('Conrad: tomt + ikke-tomt forældre-sæt → accepteret', () => {
    const g = new Map([['V1', ['III58', 'V1']]]);
    const d = db([P('III58'), P('V1'), P('far')], [{ child: 'III58', parent: 'far', union: 'f1' }]);
    const { accepted, quarantined } = validateGroups(g, d);
    expect(quarantined).toEqual([]);
    expect(accepted.has('V1')).toBe(true);
  });
  it('konkurrerende ikke-tomme forældre → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A'), P('B'), P('p1'), P('p2')], [{ child: 'A', parent: 'p1', union: 'f1' }, { child: 'B', parent: 'p2', union: 'f2' }]);
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/konkurrerende forældre/i);
  });
  it('selv-forælder efter merge → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A'), P('B')], [{ child: 'A', parent: 'B', union: 'f1' }]); // A barn af B; A=B → selv-forælder
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/selv/i);
  });
  it('global cyklus via uberørt node → karantæne', () => {
    // X barn af Y; Y barn af B; A barn af X; A=B (merge) → B er ane til sig selv gennem X,Y
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A'), P('B'), P('X'), P('Y')], [
      { child: 'X', parent: 'Y', union: 'f1' }, { child: 'Y', parent: 'B', union: 'f2' }, { child: 'A', parent: 'X', union: 'f3' }]);
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/cyklus/i);
  });
  it('kendt-forskelligt køn → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A', { koen: 'mand' }), P('B', { koen: 'kvinde' })], []);
    const { quarantined } = validateGroups(g, d);
    expect(quarantined[0].reason).toMatch(/køn/i);
  });
  it('ikke-overlappende levetider → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A', { born: 1600, died: 1650 }), P('B', { born: 1700, died: 1750 })], []);
    const { quarantined } = validateGroups(g, d);
    expect(quarantined[0].reason).toMatch(/levetid|vital/i);
  });
});
```

- [ ] **Step 2: Kør — fejler**

Run: `cd mobile && npx jest collapseSameAs`
Expected: FAIL — `validateGroups` ikke eksporteret.

- [ ] **Step 3: Implementér `validateGroups`**

Tilføj til `collapseSameAs.ts`:
```ts
import type { Db, AppPerson, QuarantineNote } from './types';

const canonMap = (groups: Map<string, string[]>): Map<string, string> => {
  const m = new Map<string, string>();
  for (const [canon, ids] of groups) for (const id of ids) m.set(id, canon);
  return m;
};
const cid = (m: Map<string, string>, id: string) => m.get(id) ?? id;

export function validateGroups(
  groups: Map<string, string[]>,
  rawDb: Db,
): { accepted: Map<string, string[]>; quarantined: QuarantineNote[] } {
  const cm = canonMap(groups);
  const personById = new Map(rawDb.persons.map((p) => [p.id, p]));
  const quarantined: QuarantineNote[] = [];
  const rejected = new Set<string>();
  const rej = (canon: string, reason: string) => { rejected.add(canon); quarantined.push({ members: groups.get(canon)!, reason }); };

  // Vital/køn-konflikt pr. gruppe (defense-in-depth).
  for (const [canon, ids] of groups) {
    const ps = ids.map((id) => personById.get(id)).filter(Boolean) as AppPerson[];
    const koen = [...new Set(ps.map((p) => p.koen).filter((k) => k && k !== 'ukendt'))];
    if (koen.length > 1) { rej(canon, `kendt-forskelligt køn (${koen.join(',')})`); continue; }
    const born = ps.map((p) => p.born).filter((b): b is number => b != null);
    const died = ps.map((p) => p.died).filter((d): d is number => d != null);
    if (born.length && died.length && Math.min(...born) > Math.max(...died) + 1) { rej(canon, 'ikke-overlappende levetider (vital-konflikt)'); continue; }
    // Konkurrerende ikke-tomme forældre-sæt: forældre pr. medlem (rå), kanoniseret.
    const parentSets = ids.map((id) => new Set(rawDb.parentChild.filter((pc) => pc.child === id).map((pc) => cid(cm, pc.parent))));
    const nonEmpty = parentSets.filter((s) => s.size > 0);
    if (nonEmpty.length > 1) {
      const first = [...nonEmpty[0]].sort().join(',');
      if (nonEmpty.some((s) => [...s].sort().join(',') !== first)) { rej(canon, 'konkurrerende forældre (forskellige ikke-tomme sæt)'); continue; }
    }
  }

  // Byg KOMBINERET projiceret forældre-graf (kun ikke-afviste grupper) → selv-forælder + global cyklus.
  const accepted0 = new Map([...groups].filter(([c]) => !rejected.has(c)));
  const cm2 = canonMap(accepted0);
  const childToParents = new Map<string, Set<string>>();
  for (const pc of rawDb.parentChild) {
    const c = cid(cm2, pc.child), p = cid(cm2, pc.parent);
    if (c === p) { const canon = cm2.get(pc.child) ?? cm2.get(pc.parent); if (canon && accepted0.has(canon)) rej(canon, 'selv-forælder efter merge'); continue; }
    (childToParents.get(c) ?? childToParents.set(c, new Set()).get(c)!).add(p);
  }
  // Global cyklus-detektion (DFS opad). Marker gruppen der lukker cyklen.
  const WHITE = 0, GRAY = 1, BLACK = 2; const color = new Map<string, number>();
  const stack: string[] = [];
  const dfs = (n: string): string | null => {
    color.set(n, GRAY); stack.push(n);
    for (const p of childToParents.get(n) ?? []) {
      const c = color.get(p) ?? WHITE;
      if (c === GRAY) return p; // cyklus
      if (c === WHITE) { const hit = dfs(p); if (hit) return hit; }
    }
    color.set(n, BLACK); stack.pop(); return null;
  };
  for (const n of childToParents.keys()) {
    if ((color.get(n) ?? WHITE) === WHITE) {
      const hit = dfs(n);
      if (hit) {
        // find en accepteret gruppe involveret i cyklus-stakken
        const canon = [...stack, hit].map((x) => cm2.get(x)).find((c) => c && accepted0.has(c));
        if (canon && !rejected.has(canon)) rej(canon, 'cyklus i forældre-graf efter merge');
        color.clear(); stack.length = 0; // genstart konservativt
      }
    }
  }
  const accepted = new Map([...groups].filter(([c]) => !rejected.has(c)));
  return { accepted, quarantined };
}
```

- [ ] **Step 4: Kør — grøn**

Run: `cd mobile && npx jest collapseSameAs`
Expected: PASS (12 tests). Hvis cyklus-testen er flaky pga. genstart-logik, verificér at `hit`-gruppen faktisk karantæneres.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/collapseSameAs.ts mobile/src/data/__tests__/collapseSameAs.test.ts
git commit -m "feat(mobile): konflikt-validering + karantæne på kombineret graf (collapseSameAs Task 2)"
```

---

### Task 3: Merge + kant-omskrivning → fuld `collapseSameAs`

**Files:**
- Modify: `mobile/src/data/collapseSameAs.ts`, `mobile/src/data/types.ts`
- Test: `mobile/src/data/__tests__/collapseSameAs.test.ts`

**Interfaces:**
- Consumes: `groupSameAs`, `validateGroups`.
- Produces: `type CollapseResult = { db: Db; canonicalIdById: Record<string,string>; mergedFrom: Record<string, Provenance[]>; quarantined: QuarantineNote[] }`. `collapseSameAs(rawDb: Db, edges: SameAsEdge[], ext: Map<string, {linje:string|null;nr:number|null}>): CollapseResult`. Fletter accepterede grupper, regenererer `years`, `privat=OR`, omskriver unions/parentChild til kanoniske id'er, dedup familie-bevidst.

- [ ] **Step 1: Tilføj `CollapseResult` til `types.ts` + `ModelPerson.mergedFrom?`**

```ts
export type CollapseResult = {
  db: Db;
  canonicalIdById: Record<string, string>;
  mergedFrom: Record<string, Provenance[]>;
  quarantined: QuarantineNote[];
};
```
Og i `ModelPerson`-typen tilføj: `mergedFrom?: Provenance[];`

- [ ] **Step 2: Skriv de fejlende tests**

```ts
import { collapseSameAs } from '../collapseSameAs';

describe('collapseSameAs (fuld)', () => {
  const ext = new Map([['III58', { linje: 'III', nr: 58 }], ['V1', { linje: 'V', nr: 1 }], ['far', { linje: 'III', nr: 40 }]]);
  it('Conrad: fletter datoer + arver forælder + mergedFrom + regen years', () => {
    const rawDb: Db = {
      persons: [P('III58', { name: 'Conrad', born: null }), P('V1', { name: 'Conrad de Reventlow', born: 1644, died: 1708 }), P('far', { name: 'Iwan' })],
      unions: [],
      parentChild: [{ child: 'III58', parent: 'far', union: 'f1' }],
    };
    const r = collapseSameAs(rawDb, [{ alias: 'III58', canonical: 'V1' }], ext);
    expect(r.canonicalIdById['III58']).toBe('V1');
    const v1 = r.db.persons.find((p) => p.id === 'V1')!;
    expect(v1.born).toBe(1644);                       // coalesce
    expect(v1.years).toContain('1644');               // regenereret
    expect(r.db.persons.some((p) => p.id === 'III58')).toBe(false); // foldet væk
    expect(r.db.parentChild.find((pc) => pc.child === 'V1')?.parent).toBe('far'); // arvet forælder
    expect(r.mergedFrom['V1']).toEqual(expect.arrayContaining([
      expect.objectContaining({ linje: 'III', nr: 58 }), expect.objectContaining({ linje: 'V', nr: 1 })]));
  });
  it('privat = OR', () => {
    const rawDb: Db = { persons: [P('A', { privat: false }), P('B', { privat: true })], unions: [], parentChild: [] };
    const r = collapseSameAs(rawDb, [{ alias: 'A', canonical: 'B' }], new Map());
    expect(r.db.persons.find((p) => p.id === 'B')!.privat).toBe(true);
  });
  it('kant-dedup familie-bevidst: samme (forælder,barn,familie) → én; forskellig familie bevares', () => {
    const rawDb: Db = { persons: [P('A'), P('B'), P('c')], unions: [],
      parentChild: [{ child: 'c', parent: 'A', union: 'f1' }, { child: 'c', parent: 'B', union: 'f1' }, { child: 'c', parent: 'B', union: 'f2' }] };
    const r = collapseSameAs(rawDb, [{ alias: 'A', canonical: 'B' }], new Map());
    const cEdges = r.db.parentChild.filter((pc) => pc.child === 'c' && pc.parent === 'B');
    expect(cEdges.map((e) => e.union).sort()).toEqual(['f1', 'f2']); // f1 deduplikeret, f2 bevaret
  });
  it('karantæneret gruppe foldes ikke (begge poster forbliver)', () => {
    const rawDb: Db = { persons: [P('A'), P('B'), P('C')], unions: [], parentChild: [] };
    const r = collapseSameAs(rawDb, [{ alias: 'A', canonical: 'B' }, { alias: 'A', canonical: 'C' }], new Map());
    expect(r.db.persons.map((p) => p.id).sort()).toEqual(['A', 'B', 'C']);
    expect(r.quarantined.length).toBe(1);
  });
});
```

- [ ] **Step 3: Kør — fejler**

Run: `cd mobile && npx jest collapseSameAs`
Expected: FAIL — `collapseSameAs` ikke eksporteret.

- [ ] **Step 4: Implementér `collapseSameAs` + `regenYears`-helper**

Tilføj til `collapseSameAs.ts`:
```ts
import type { CollapseResult, Provenance } from './types';

// Regenerér display-streng fra born/died (matcher AppPerson.years-formatet).
function regenYears(born: number | null, died: number | null): string {
  if (born != null && died != null) return `${born}–${died}`;
  if (born != null) return `* ${born}`;
  if (died != null) return `† ${died}`;
  return '';
}

export function collapseSameAs(
  rawDb: Db,
  edges: SameAsEdge[],
  ext: Map<string, { linje: string | null; nr: number | null }>,
): CollapseResult {
  const known = new Set(rawDb.persons.map((p) => p.id));
  const { groups, quarantined: q1 } = groupSameAs(edges, known);
  const { accepted, quarantined: q2 } = validateGroups(groups, rawDb);
  const quarantined = [...q1, ...q2];

  const canonicalIdById: Record<string, string> = {};
  for (const [canon, ids] of accepted) for (const id of ids) canonicalIdById[id] = canon;
  const cid = (id: string) => canonicalIdById[id] ?? id;

  // Flet personer.
  const personById = new Map(rawDb.persons.map((p) => [p.id, p]));
  const mergedFrom: Record<string, Provenance[]> = {};
  const mergedPersons: AppPerson[] = [];
  const droppedAlias = new Set<string>();
  for (const [canon, ids] of accepted) {
    const primary = personById.get(canon)!;
    const others = ids.filter((id) => id !== canon).map((id) => personById.get(id)!).filter(Boolean);
    const coalesce = <K extends keyof AppPerson>(k: K): AppPerson[K] =>
      (primary[k] ?? others.find((o) => o[k] != null)?.[k]) as AppPerson[K];
    const born = coalesce('born'); const died = coalesce('died');
    mergedPersons.push({
      ...primary,
      born, died, years: regenYears(born as number | null, died as number | null),
      title: primary.title || others.find((o) => o.title)?.title || '',
      koen: primary.koen ?? others.find((o) => o.koen && o.koen !== 'ukendt')?.koen,
      privat: ids.some((id) => personById.get(id)?.privat), // OR
    });
    mergedFrom[canon] = ids.map((id) => ({ personId: id, linje: ext.get(id)?.linje ?? null, nr: ext.get(id)?.nr ?? null }));
    for (const id of ids) if (id !== canon) droppedAlias.add(id);
  }
  const persons = rawDb.persons.filter((p) => !accepted.has(p.id) && !droppedAlias.has(p.id)).concat(mergedPersons);

  // Omskriv unions (familie-bevidst dedup: unik på id).
  const seenUnion = new Set<string>();
  const unions = rawDb.unions.map((u) => ({ ...u, p1: u.p1 == null ? u.p1 : cid(u.p1), p2: u.p2 == null ? u.p2 : cid(u.p2) }))
    .filter((u) => { if (seenUnion.has(u.id)) return false; seenUnion.add(u.id); return true; });

  // Omskriv parentChild (dedup på kanonisk-forælder|kanonisk-barn|familie).
  const seenPc = new Set<string>();
  const parentChild = rawDb.parentChild.map((pc) => ({ ...pc, child: cid(pc.child), parent: cid(pc.parent) }))
    .filter((pc) => { const k = `${pc.parent}|${pc.child}|${pc.union}`; if (seenPc.has(k)) return false; seenPc.add(k); return true; });

  return { db: { persons, unions, parentChild }, canonicalIdById, mergedFrom, quarantined };
}
```

- [ ] **Step 5: Kør — grøn (hele kerne-suiten)**

Run: `cd mobile && npx jest collapseSameAs`
Expected: PASS (alle kerne-tests).

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/collapseSameAs.ts mobile/src/data/types.ts mobile/src/data/__tests__/collapseSameAs.test.ts
git commit -m "feat(mobile): merge + kant-omskrivning → fuld collapseSameAs (Task 3)"
```

---

## FASE B — Mobile integration

### Task 4: Fetch samme_som + wire i load.ts + store

**Files:**
- Modify: `mobile/src/data/load.ts:101-190` (fetch + kald før buildModel), `mobile/src/store/useStore.ts`
- Test: `mobile/src/data/__tests__/load.test.ts`

**Interfaces:**
- Consumes: `collapseSameAs` (Task 3).
- Produces: `LoadResult` udvides med `canonicalIdById: Record<string,string>` + `mergedFrom: Record<string, Provenance[]>`. Store eksponerer `canonicalId(id): string`.

- [ ] **Step 1: Skriv den fejlende test**

I `load.test.ts`, tilføj (mock-baseret, følg eksisterende stil i filen):
```ts
it('collapser samme_som før buildModel: alias resolver til kanonisk', async () => {
  // Arranger en fixture med to person-rækker + en godkendt samme_som (III58->V1)
  // og assertér at resultatets model.byId ikke har III58, og canonicalIdById['III58']==='V1'.
  // (Brug filens eksisterende supabase-mock-mønster; se toppen af load.test.ts.)
});
```
(Følg `load.test.ts`'s eksisterende mock-setup for `supabase.from(...)`. Tilføj en `relation`-mock der returnerer `[{subjekt_id:'III58', objekt_id:'V1'}]` for `rolle='samme_som'` + en `conclusion`-mock der markerer den `afklaret`.)

- [ ] **Step 2: Kør — fejler**

Run: `cd mobile && npx jest load`
Expected: FAIL (III58 stadig i model / canonicalIdById udefineret).

- [ ] **Step 3: Fetch godkendte samme_som-kanter**

I `loadFromSupabase` (`load.ts`), tilføj til Promise.all-blokken (~linje 108-134) en fetch af godkendte identitets-links. Godkendt = `relation.rolle='samme_som'` med en `conclusion.status='afklaret'` på relationen:
```ts
getAll<{ subjekt_id: number; objekt_id: number }>(() => sb
  .from('relation')
  .select('subjekt_id,objekt_id,conclusion!inner(status)')
  .eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person')
  .eq('conclusion.status', 'afklaret')).catch(() => [] as { subjekt_id: number; objekt_id: number }[]),
```
(Verificér join-syntaksen mod `conclusion.target_type='relation' AND target_id=relation.id`. Hvis PostgREST-embed er besværligt, hent `samme_som`-relationer + `conclusion` separat og filtrér i JS på `target_type='relation'` + `status='afklaret'`.)

- [ ] **Step 4: Kald collapseSameAs før buildModel**

Efter `db` er bygget (~linje 187, før `buildModel(db)`):
```ts
const edges = sameAsRows.map((r) => ({ alias: String(r.subjekt_id), canonical: String(r.objekt_id) }));
const extMap = new Map(extIds.map((x) => [String(x.person_id), { linje: x.linje, nr: x.nr }]));
const collapsed = collapseSameAs(db, edges, extMap);
if (collapsed.quarantined.length) console.warn('[samme_som] karantæne:', collapsed.quarantined);
const model = buildModel(collapsed.db);
// mergedFrom påføres model-personerne (til badge):
for (const [canon, prov] of Object.entries(collapsed.mergedFrom)) if (model.byId[canon]) model.byId[canon].mergedFrom = prov;
return { ...rest, model, aux, canonicalIdById: collapsed.canonicalIdById, mergedFrom: collapsed.mergedFrom };
```
Opdatér `LoadResult`-typen med de to nye felter.

- [ ] **Step 5: Store — gem alias-map + `canonicalId`-selector**

I `useStore.ts`: tilføj `canonicalIdById: Record<string,string>` til state (sat i load-action), og en selector `canonicalId: (id) => get().canonicalIdById[id] ?? id`. Ved `meId`-load (linje ~157): resolv gennem `canonicalId` så et gemt alias-`meId` peger på den kanoniske.

- [ ] **Step 6: Kør tests + commit**

Run: `cd mobile && npx jest load` → PASS. `cd mobile && npm test` → hele suiten grøn.
```bash
git add mobile/src/data/load.ts mobile/src/store/useStore.ts mobile/src/data/__tests__/load.test.ts
git commit -m "feat(mobile): fetch godkendte samme_som + collapse før buildModel + alias-map i store (Task 4)"
```

---

### Task 5: Mobile Aux-projektion

**Files:**
- Modify: `mobile/src/data/buildAux.ts` (linjeByPerson→multi, ownersByEstate/headId kanoniser, narrativ-union), `mobile/src/data/types.ts` (`linjeByPerson: Record<string,string[]>`)
- Test: `mobile/src/data/__tests__/buildAux.test.ts`

**Interfaces:**
- Consumes: `canonicalIdById` fra collapse (Task 4). `buildAux` modtager det som ny parameter `canonicalIdById: Record<string,string>` (default `{}` for bagudkompat i eksisterende tests).
- Produces: `Aux.linjeByPerson: Record<string, string[]>` (flere linjer pr. person). Alle person-id'er i aux kanoniseret.

- [ ] **Step 1: Skriv de fejlende tests**

Tilføj til `buildAux.test.ts`:
```ts
it('linjeByPerson samler flere linjer for collapsed person', () => {
  // III58 (linje III) + V1 (linje V), canonicalIdById III58->V1 → linjeByPerson['V1'] indeholder III OG V.
});
it('ownersByEstate.personId + linjeList.headId kanoniseres', () => {
  // en estate-owner-relation på III58 → owner.personId === 'V1'; linjeList.headId for en linje hvis head var III58 → 'V1'.
});
```
(Byg fixtures i filens eksisterende stil.)

- [ ] **Step 2: Kør — fejler**

Run: `cd mobile && npx jest buildAux`
Expected: FAIL (linjeByPerson er stadig single-string / personId ukanoniseret).

- [ ] **Step 3: Ret `types.ts` + `buildAux.ts`**

- `types.ts:153`: `linjeByPerson: Record<string, string>` → `Record<string, string[]>`.
- `buildAux.ts`: tilføj parameter `canonicalIdById: Record<string,string> = {}`; helper `const cid = (id: string) => canonicalIdById[id] ?? id;`.
  - Linje ~71: `linjeByPerson[String(x.person_id)] = x.linje;` → push til array under `cid(String(x.person_id))` (dedup).
  - Linje ~87: `headId: linjeHead[l]?.id ?? null` → `cid(...)`.
  - Linje ~110: `personId: pid` → `cid(pid)`.
  - Narrativ-opslag: hvis `buildAux` samler narrativer pr. person, saml under `cid(...)` som union.
- Opdatér alle læsere af `linjeByPerson` (nu array) — søg `linjeByPerson[` i `mobile/src`.

- [ ] **Step 4: Kør tests + commit**

Run: `cd mobile && npx jest buildAux` → PASS. `cd mobile && npm test` → grøn (ret evt. brudte læsere af `linjeByPerson`).
```bash
git add mobile/src/data/buildAux.ts mobile/src/data/types.ts mobile/src/data/__tests__/buildAux.test.ts
git commit -m "feat(mobile): Aux-id-projektion + multi-linje for collapsed personer (Task 5)"
```

---

### Task 6: Mobile person-visning — alias-resolution + proveniens-badge

**Files:**
- Modify: `mobile/src/app/person/[id].tsx`
- Test: manuel (Expo) — ingen ren enhedstest for skærmen; verificér mod devicen/simulator.

**Interfaces:**
- Consumes: `canonicalId`-selector (Task 4), `model.byId[id].mergedFrom` (Task 4), `linjeByPerson[]` (Task 5).

- [ ] **Step 1: Resolv rute-id til kanonisk**

I `person/[id].tsx` (~linje 42, hvor `id` bruges til opslag): `const cid = useStore((s) => s.canonicalId); const personId = cid(String(routeId));` og brug `personId` til ALLE opslag (person, buildAux-data, relationer).

- [ ] **Step 2: Vis proveniens-badge**

Hvor navn/linje vises: hvis `model.byId[personId]?.mergedFrom?.length > 1`, render en badge/note der lister kilderne, fx: `Optræder i DAA i {mergedFrom.map(m => `${lineageName(m.linje)} (${m.linje}-${m.nr})`).join(' og ')}`. Brug `linjeByPerson[personId]` (nu array) til at vise flere linjer.

- [ ] **Step 3: Verificér i Expo (manuelt)**

Kør appen mod simulator; naviger til både III-58's og V-1's rute → begge lander på samme samlede Conrad med badge der viser begge kilder + begge linjer. Notér resultatet i commit-beskeden (ingen automatisk test for skærmen).

- [ ] **Step 4: Commit**

```bash
git add mobile/src/app/person/[id].tsx
git commit -m "feat(mobile): person-visning alias-resolution + proveniens-badge (Task 6)"
```

---

## FASE C — Web spejl + integration

### Task 7: Spejl collapseSameAs til web (vitest)

**Files:**
- Create: `web/src/data/collapseSameAs.ts`, `web/src/data/__tests__/collapseSameAs.test.ts`
- Modify: `web/src/data/types.ts` (samme type-tilføjelser som mobile)

**Interfaces:**
- Produces: identisk API som mobile (`groupSameAs`, `validateGroups`, `collapseSameAs`, samme typer).

- [ ] **Step 1: Kopiér kernen + typerne**

Kopiér `mobile/src/data/collapseSameAs.ts` → `web/src/data/collapseSameAs.ts` uændret (ren TS, ingen platform-afhængigheder). Tilføj `SameAsEdge`/`Provenance`/`QuarantineNote`/`CollapseResult` + `ModelPerson.mergedFrom?` til `web/src/data/types.ts` (verbatim fra mobile).

- [ ] **Step 2: Port testene til vitest**

Kopiér `mobile/.../collapseSameAs.test.ts` → `web/src/data/__tests__/collapseSameAs.test.ts`. Vitest bruger samme `describe/it/expect`-API; ret kun import-stier hvis nødvendigt. (Web bruger `vitest run`.)

- [ ] **Step 3: Kør — grøn**

Run: `cd web && npx vitest run collapseSameAs`
Expected: PASS (samme antal tests som mobile).

- [ ] **Step 4: Commit**

```bash
git add web/src/data/collapseSameAs.ts web/src/data/types.ts web/src/data/__tests__/collapseSameAs.test.ts
git commit -m "feat(web): spejl collapseSameAs-kerne + vitest-tests (Task 7)"
```

---

### Task 8: Wire i web loadModel + Folgesvend-state

**Files:**
- Modify: `web/src/data/model.ts:47-102` (fetch + kald før buildModel), `web/src/Folgesvend.tsx`
- Test: `web/src/data/__tests__/` (ny `model.test.ts` hvis muligt; ellers verificér via browse/relationship efter collapse)

**Interfaces:**
- Consumes: `collapseSameAs` (Task 7).
- Produces: `loadModel(): Promise<{ model: Model; canonicalIdById: Record<string,string>; mergedFrom: Record<string, Provenance[]> }>` (ændret return-type — opdatér kalderen i `Folgesvend.tsx:63`).

- [ ] **Step 1: Fetch godkendte samme_som + kald før buildModel**

I `model.ts` `loadModel` (Promise.all ~linje 47-58): tilføj samme godkendte-samme_som-fetch som mobile Task 4 Step 3. Efter `db` (linje 101), før `buildModel(db)`:
```ts
const edges = sameAsRows.map((r) => ({ alias: String(r.subjekt_id), canonical: String(r.objekt_id) }));
const extMap = new Map(extIdRows.map((x) => [String(x.person_id), { linje: x.linje, nr: x.nr }]));
const collapsed = collapseSameAs(db, edges, extMap);
const model = buildModel(collapsed.db);
for (const [canon, prov] of Object.entries(collapsed.mergedFrom)) if (model.byId[canon]) model.byId[canon].mergedFrom = prov;
return { model, canonicalIdById: collapsed.canonicalIdById, mergedFrom: collapsed.mergedFrom };
```

- [ ] **Step 2: Opdatér `Folgesvend.tsx`-kalderen**

`Folgesvend.tsx:63` `loadModel().then((m) => setModel(m))` → destrukturér `{ model, canonicalIdById }`; gem `canonicalIdById` i state. `meId`-resolution (linje 50 + 178): resolv gennem `canonicalIdById[meId] ?? meId`. Fokus/navigation (`navigateTo`, `focusId`, relate-slots `relA/relB`): resolv indgående id gennem alias-map før opslag i `model.byId`.

- [ ] **Step 3: Kør tests**

Run: `cd web && npm test`
Expected: eksisterende vitest-suite grøn (browse/lineage/sources upåvirket; collapse ny). Tilføj en `model.test.ts` der verificerer at et alias-id resolver til kanonisk hvis mock-infra tillader det; ellers dokumentér manuel web-verifikation.

- [ ] **Step 4: Commit**

```bash
git add web/src/data/model.ts web/src/Folgesvend.tsx web/src/data/__tests__/
git commit -m "feat(web): collapse i loadModel + alias-resolution i Folgesvend-state (Task 8)"
```

---

### Task 9: Web person-detalje Aux-projektion + badge

**Files:**
- Modify: `web/src/data/public.ts:101-133` (person-detalje for alle medlems-id'er + narrativ-union), `web/src/Folgesvend.tsx` (detalje-panel badge)

**Interfaces:**
- Consumes: `canonicalIdById` + `mergedFrom` (Task 8).

- [ ] **Step 1: Person-detalje for alle medlems-id'er**

`public.ts` `loadPersonDetail(id)` (~linje 101): modtag også gruppens medlems-id'er (fra `mergedFrom[cid]` via kalderen, eller slå `canonicalIdById` op omvendt). Hent narrativ/relationer for ALLE medlems-id'er og unionér (narrativ = alle, ikke `.maybeSingle()`/første). Kald-stedet i `Folgesvend.tsx` sender de rå medlems-id'er.

- [ ] **Step 2: Proveniens-badge i detalje-panelet**

I `Folgesvend.tsx`-detalje-panelet (v2-port'ens "Kilde i Aarbogen"-sektion er et naturligt sted): hvis `model.byId[focusId]?.mergedFrom?.length > 1`, vis badge med kilderne + brug lineage-navnene (`web/src/data/lineage.ts`) til at vise "Den mecklenburgske linje (III-58) og Den grevelige linje af 1673 (V-1)".

- [ ] **Step 3: Kør tests + manuel web-verifikation**

Run: `cd web && npm test` → grøn. Kør web-appen (`cd web && npm run dev`), naviger til Conrad via både III-58 og V-1 → samme samlede person + badge + union af narrativ/kilder.

- [ ] **Step 4: Commit**

```bash
git add web/src/data/public.ts web/src/Folgesvend.tsx
git commit -m "feat(web): person-detalje Aux-union + proveniens-badge (Task 9)"
```

---

## Self-review-noter

- **Spec-dækning:** §2 (hook+kontrakt)→Task 4/8; §3 (kanonisk sink/completeness)→Task 1; §4 (kun afklaret)→Task 4/8 fetch; §5 (GDPR completeness)→Task 1 (manglende endpoint=karantæne) + fetch-filter; §6 (validering/karantæne)→Task 2; §7 (merge/years/dedup)→Task 3; §8 (Aux+badge)→Task 5/6/9; §10 (tests)→Task 1-3 + integration. Alle spec-testcases fra §10 er fordelt på Task 1-3.
- **RLS-integrationstest** (§10): dækkes af Task 1's "manglende endpoint→karantæne" (RLS-trunkering simuleret ved at udelade endpoint fra `knownIds`) + Task 4's fetch (godkendte+synlige kun). En ægte live-RLS-e2e er manuel (mobile Task 6 / web Task 9 verifikation).
- **Type-konsistens:** `collapseSameAs`/`groupSameAs`/`validateGroups`/`CollapseResult`/`canonicalIdById`/`mergedFrom` ens i web+mobile (Task 7 kopierer verbatim). `linjeByPerson: Record<string,string[]>` ændret begge steder (mobile Task 5; web-læsere i Task 8/9 hvis relevant).
- **Kendt begrænsning:** web har p.t. ingen `buildModel`/`relationship` unit-tests (kun mobile) — web-collapse verificeres via kerne-tests (Task 7) + manuel app-verifikation (Task 9). Kryds-synligheds-broer (Beke) er uden for scope (server-side privacy).
