# Præsensliste-visning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beregnet, anker-baseret præsensliste-læsevisning (web + mobil), redaktion-gated, jf. `docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md`.

**Architecture:** Ren kerneberegning i `packages/core` (`presensLabels.ts` + `presensListe.ts`) over den eksisterende collapsede `Model` + et let "grundlag" (levende-flag + overhoved-fakta) hentet af et nyt tyndt data-modul pr. app. Overhoveder udpeges som fakta (faktatype `overhoved`, vokabular-seed — ingen skemaændring) via de eksisterende fact-flows i person-editoren. UI er tynd rendering: ny Mode `praesens` i web-Følgesvenden + ny route i mobil-draweren.

**Tech Stack:** TypeScript, vitest (core+web), jest (mobil), React (web), React Native/Expo (mobil), Supabase JS.

## Global Constraints

- Dansk i al UI-tekst, kommentarer og commits (Conventional Commits, dansk beskrivelse).
- Ingen skemaændring, ingen ny RLS-flade, ingen ny RPC (spec §2.3 + §4). Kun vokabular-DATA.
- Kernen er rene funktioner uden DOM/RN/fetch (packages/core-kontrakten; source-only-pakke).
- Person-id'er er ALTID strenge i app-laget (core types.ts linje 6).
- Kernen kører på den collapsede model med kanoniske id'er — kald `kanoniserPresensGrundlag` før `buildPresensListe`.
- Ingen skrivning udløses nogensinde af visningen eller advarslerne (spec §7).
- Prod-apply af `db-migrations.sql` er bruger-gated — denne plan opdaterer kun filerne.
- PR oprettes ALTID `--draft`; ingen push/merge uden eksplicit aftale.
- @testing-library/react-native virker IKKE i dette repo — mobil-tests er rene data-/funktionstests.
- Kør fra repo-roden medmindre andet står; testkommandoer angiver selv katalog.

## Forudsætning: branch

Opret feature-branch før Task 1 (fra opdateret `main`):

```bash
git checkout -b feat/praesensliste
```

---

### Task 1: Vokabular-seed `overhoved` (schema + migration + verify)

**Files:**
- Modify: `schema.sql` (append efter de eksisterende `INSERT INTO vocab`-blokke, fx efter story-seedet omkring linje 534)
- Modify: `db-migrations.sql` (append i bunden, følg filens idempotente mønster)
- Modify: `db-verify.sql` (append assert i bunden)

**Interfaces:**
- Produces: vokabular-rækken `('faktatype','overhoved',…)` — værdi-formatet `"<ROMERTAL> linje[, <N>. gren]"` som Task 2's parser forstår.

- [ ] **Step 1: Tilføj seed til `schema.sql`**

Find den sidste `INSERT INTO vocab`-blok (story_status/story_oprindelse, ca. linje 527-534) og tilføj derefter:

```sql
-- Præsensliste: linje-/gren-overhoved udpeges som redaktionelt fakta (spec
-- docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md §4).
-- Værdi-format: '<ROMERTAL> linje' eller '<ROMERTAL> linje, <N>. gren' — fx 'II linje, 1. gren'.
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','overhoved','Linje-/gren-overhoved — anker for præsenslisten')
ON CONFLICT (scheme, code) DO NOTHING;
```

- [ ] **Step 2: Tilføj idempotent migration til `db-migrations.sql`**

Append i bunden af filen (samme SQL — den er idempotent via `ON CONFLICT DO NOTHING`), med dateret sektionsoverskrift i filens stil:

```sql
-- ============================================================
-- 2026-07-22: Præsensliste — faktatype 'overhoved' (vokabular-seed)
-- Ingen skemaændring. Se docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md §4.
-- ============================================================
INSERT INTO vocab (scheme, code, label) VALUES
  ('faktatype','overhoved','Linje-/gren-overhoved — anker for præsenslisten')
ON CONFLICT (scheme, code) DO NOTHING;
```

- [ ] **Step 3: Tilføj assert til `db-verify.sql`**

Append i bunden, i filens assert-stil:

```sql
-- Præsensliste: vokabular-seed for overhoved-faktatypen
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='overhoved') THEN
    RAISE EXCEPTION 'FEJL: vocab mangler (faktatype, overhoved) — kør db-migrations.sql';
  END IF;
END $$;
```

- [ ] **Step 4: Verificér mod lokal testbase hvis den kører — ellers markér sprunget**

Hvis den lokale prod-kopi (brew postgresql@17-setup, se memory `lokal-db-testbase`) er oppe:

```bash
psql "$LOKAL_DAA_DB" -f db-migrations.sql && psql "$LOKAL_DAA_DB" -f db-verify.sql
```

Expected: ingen fejl; verify-asserts grønne. Kører basen ikke, rapportér eksplicit "SQL-verifikation sprunget (ingen lokal base)" — prod-apply er under alle omstændigheder bruger-gated.

- [ ] **Step 5: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(presens): vokabular-seed for faktatype 'overhoved'"
```

---

### Task 2: Core — `presensLabels.ts` (anker-parse + overskrift-generator)

**Files:**
- Create: `packages/core/src/presensLabels.ts`
- Create: `packages/core/src/__tests__/presensLabels.test.ts`
- Modify: `packages/core/src/index.ts` (eksport)

**Interfaces:**
- Consumes: `Koen` fra `./types`.
- Produces (bruges af Task 3-4 + app-lagene):
  - `type PresensAnker = { personId: string; linje: string; gren: number | null; raaVaerdi: string }`
  - `parseOverhovedVaerdi(personId: string, vaerdi: string): PresensAnker | null`
  - `sortAnkre(ankre: PresensAnker[]): PresensAnker[]`
  - `type SoeskendeSammensaetning = { maend: number; kvinder: number; ukendt: number }`
  - `type PresensTerminal = { slags: 'soeskende'; sammensaetning: SoeskendeSammensaetning } | { slags: 'foraelder'; koen: Koen } | { slags: 'enke' }`
  - `stiOverskrift(kaede: Koen[], terminal: PresensTerminal): string`

- [ ] **Step 1: Skriv de fejlende tests**

`packages/core/src/__tests__/presensLabels.test.ts`:

```ts
import { parseOverhovedVaerdi, sortAnkre, stiOverskrift } from '../presensLabels';

describe('parseOverhovedVaerdi', () => {
  test('linje + gren', () => {
    expect(parseOverhovedVaerdi('42', 'II linje, 1. gren')).toEqual({ personId: '42', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' });
  });
  test('kun linje', () => {
    expect(parseOverhovedVaerdi('7', 'I linje')).toEqual({ personId: '7', linje: 'I', gren: null, raaVaerdi: 'I linje' });
  });
  test('tolerant for kasse/mellemrum', () => {
    expect(parseOverhovedVaerdi('9', '  ii Linje ,  3 . gren ')?.gren).toBe(3);
  });
  test('ugyldig værdi → null', () => {
    expect(parseOverhovedVaerdi('1', 'hovedlinjen')).toBeNull();
    expect(parseOverhovedVaerdi('1', '')).toBeNull();
    expect(parseOverhovedVaerdi('1', 'XIIX linje')).toBeNull();
  });
});

describe('sortAnkre', () => {
  test('romertals-orden, så gren-nummer', () => {
    const a = (personId: string, linje: string, gren: number | null) => ({ personId, linje, gren, raaVaerdi: '' });
    const sorted = sortAnkre([a('c', 'II', 2), a('b', 'II', 1), a('d', 'I', null)]);
    expect(sorted.map((x) => x.personId)).toEqual(['d', 'b', 'c']);
  });
});

describe('stiOverskrift — søskende-terminaler', () => {
  const s = (maend: number, kvinder: number, ukendt = 0) => ({ slags: 'soeskende' as const, sammensaetning: { maend, kvinder, ukendt } });
  test('ankerens egne søskende: ental/flertal/blandet', () => {
    expect(stiOverskrift([], s(0, 1))).toBe('Søster');
    expect(stiOverskrift([], s(0, 2))).toBe('Søstre');
    expect(stiOverskrift([], s(1, 0))).toBe('Bror');
    expect(stiOverskrift([], s(2, 0))).toBe('Brødre');
    expect(stiOverskrift([], s(1, 1))).toBe('Søskende');
    expect(stiOverskrift([], s(1, 0, 1))).toBe('Søskende'); // ukendt køn → neutral
  });
  test('fars niveau: farbror-komposit, fars søster uden komposit', () => {
    expect(stiOverskrift(['mand'], s(1, 0))).toBe('Farbror');
    expect(stiOverskrift(['mand'], s(2, 0))).toBe('Farbrødre');
    expect(stiOverskrift(['mand'], s(0, 1))).toBe('Fars søster');
    expect(stiOverskrift(['mand'], s(0, 2))).toBe('Fars søstre');
    expect(stiOverskrift(['mand'], s(1, 1))).toBe('Fars søskende');
    expect(stiOverskrift(['kvinde'], s(1, 0))).toBe('Morbror');
  });
  test('længere kæder: chunk-par + genitiv (bogens FARFARS BROR / FARFARS FARBROR)', () => {
    expect(stiOverskrift(['mand', 'mand'], s(1, 0))).toBe('Farfars bror');
    expect(stiOverskrift(['mand', 'mand', 'mand'], s(1, 0))).toBe('Farfars farbror');
    expect(stiOverskrift(['mand', 'kvinde'], s(0, 1))).toBe('Farmors søster');
    expect(stiOverskrift(['kvinde', 'mand'], s(1, 1))).toBe('Morfars søskende');
  });
  test('kønssymmetri via mor-linjen', () => {
    expect(stiOverskrift(['kvinde', 'kvinde', 'mand'], s(1, 0))).toBe('Mormors farbror');
  });
  test('ukendt køn i kæden → neutralt led', () => {
    expect(stiOverskrift([null], s(1, 0))).toBe('Forælders bror');
  });
});

describe('stiOverskrift — forælder- og enke-terminaler', () => {
  test('gift-ind-forælder', () => {
    expect(stiOverskrift([], { slags: 'foraelder', koen: 'kvinde' })).toBe('Mor');
    expect(stiOverskrift([], { slags: 'foraelder', koen: 'mand' })).toBe('Far');
    expect(stiOverskrift(['mand'], { slags: 'foraelder', koen: 'kvinde' })).toBe('Farmor');
  });
  test('enke efter blodforfader', () => {
    expect(stiOverskrift(['mand'], { slags: 'enke' })).toBe('Fars enke');
    expect(stiOverskrift(['mand', 'mand'], { slags: 'enke' })).toBe('Farfars enke');
  });
});
```

- [ ] **Step 2: Kør testene — de skal fejle**

```bash
cd packages/core && npx vitest run src/__tests__/presensLabels.test.ts
```

Expected: FAIL — "Cannot find module '../presensLabels'".

- [ ] **Step 3: Implementér `presensLabels.ts`**

```ts
// Præsensliste: anker-parse + sti→overskrift-generator (spec 2026-07-22 §4-§5).
// Rene funktioner. Genererer ALTID moderne former (FARBROR, FARS SØSTER) — bogens
// arkaiske varianter gengives ikke; original-proveniens er en senere påbygning.
import type { Koen } from './types';

export type PresensAnker = { personId: string; linje: string; gren: number | null; raaVaerdi: string };

const ROMER: Record<string, number> = { I: 1, II: 2, III: 3, IV: 4, V: 5, VI: 6, VII: 7, VIII: 8, IX: 9, X: 10 };

// 'II linje' / 'II linje, 1. gren' — tolerant for kasse og mellemrum; alt andet → null
// (fail-closed: en uparsebar udpegning bliver aldrig et gættet anker).
export function parseOverhovedVaerdi(personId: string, vaerdi: string): PresensAnker | null {
  const m = /^\s*([ivx]+)\s*\.?\s*linje\s*(?:,\s*(\d+)\s*\.?\s*gren)?\s*$/i.exec(vaerdi ?? '');
  if (!m) return null;
  const linje = m[1].toUpperCase();
  if (!(linje in ROMER)) return null;
  return { personId, linje, gren: m[2] != null ? Number(m[2]) : null, raaVaerdi: vaerdi.trim() };
}

export function sortAnkre(ankre: PresensAnker[]): PresensAnker[] {
  return [...ankre].sort(
    (a, b) => ROMER[a.linje] - ROMER[b.linje] || (a.gren ?? 0) - (b.gren ?? 0) || (a.personId < b.personId ? -1 : a.personId > b.personId ? 1 : 0),
  );
}

export type SoeskendeSammensaetning = { maend: number; kvinder: number; ukendt: number };
export type PresensTerminal =
  | { slags: 'soeskende'; sammensaetning: SoeskendeSammensaetning }
  | { slags: 'foraelder'; koen: Koen }
  | { slags: 'enke' };

const ET: Record<'mand' | 'kvinde', string> = { mand: 'far', kvinde: 'mor' };
const PAR: Record<string, string> = { 'mand|mand': 'farfar', 'mand|kvinde': 'farmor', 'kvinde|mand': 'morfar', 'kvinde|kvinde': 'mormor' };

// Kæden chunks parvis fra ankeret: [far,far,far] → ['farfar','far'] — så komposit-reglen
// nedenfor giver bogens 'farfars farbror' frem for 'fars fars fars bror'.
function kaedeOrd(kaede: Koen[]): string[] {
  const ord: string[] = [];
  let i = 0;
  while (i < kaede.length) {
    const a = kaede[i];
    const b = kaede[i + 1];
    if (a != null && b != null) { ord.push(PAR[`${a}|${b}`]); i += 2; }
    else if (a != null) { ord.push(ET[a]); i += 1; }
    else { ord.push('forælder'); i += 1; } // ukendt køn chunkes ikke
  }
  return ord;
}

// Genitiv-s på alle led undtagen det sidste: ['farfar','farbror'] → 'farfars farbror'.
const genitivJoin = (ord: string[]): string => ord.map((o, i) => (i < ord.length - 1 ? o + 's' : o)).join(' ');
const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

function soeskendeOrd(s: SoeskendeSammensaetning): { ord: string; art: 'bror' | 'soester' | 'soeskende' } {
  if (s.ukendt === 0 && s.kvinder === 0 && s.maend > 0) return { ord: s.maend > 1 ? 'brødre' : 'bror', art: 'bror' };
  if (s.ukendt === 0 && s.maend === 0 && s.kvinder > 0) return { ord: s.kvinder > 1 ? 'søstre' : 'søster', art: 'soester' };
  return { ord: 'søskende', art: 'soeskende' };
}

// kaede = køn for forfaderleddene fra ankeret og OP (uden terminalleddet).
// UI'et versaliserer selv (typografisk slægtskab med bogen); her returneres 'Farfars farbror'.
export function stiOverskrift(kaede: Koen[], terminal: PresensTerminal): string {
  if (terminal.slags === 'foraelder') return cap(genitivJoin(kaedeOrd([...kaede, terminal.koen])));
  if (terminal.slags === 'enke') return cap(genitivJoin([...kaedeOrd(kaede), 'enke']));
  const ord = kaedeOrd(kaede);
  const s = soeskendeOrd(terminal.sammensaetning);
  const sidste = ord[ord.length - 1];
  // Komposit KUN for brødre efter enkelt forælder-led (bogen: FARBROR, men FARS SØSTER).
  if (s.art === 'bror' && (sidste === 'far' || sidste === 'mor')) {
    const komposit = (sidste === 'far' ? 'farbr' : 'morbr') + (terminal.sammensaetning.maend > 1 ? 'ødre' : 'or');
    return cap(genitivJoin([...ord.slice(0, -1), komposit]));
  }
  return cap(genitivJoin([...ord, s.ord]));
}
```

- [ ] **Step 4: Eksportér fra `index.ts`**

Tilføj i `packages/core/src/index.ts` efter `export * from './matchUdgaver';`:

```ts
export * from './presensLabels';
```

- [ ] **Step 5: Kør testene — de skal bestå**

```bash
cd packages/core && npx vitest run src/__tests__/presensLabels.test.ts
```

Expected: PASS (alle).

- [ ] **Step 6: Typecheck + commit**

```bash
cd packages/core && npx tsc --noEmit && cd ../.. \
  && git add packages/core/src/presensLabels.ts packages/core/src/__tests__/presensLabels.test.ts packages/core/src/index.ts \
  && git commit -m "feat(presens): anker-parse + overskrift-generator i core"
```

---

### Task 3: Core — `presensListe.ts` del 1: beskæring (`pruneUndertrae`)

**Files:**
- Create: `packages/core/src/presensListe.ts`
- Create: `packages/core/src/__tests__/presensListe.test.ts`
- Modify: `packages/core/src/index.ts` (eksport)

**Interfaces:**
- Consumes: `Model`, `Konfidens`, `KONFIDENS_RANK` fra `./types`; `PresensAnker`, `stiOverskrift`, `sortAnkre`, `SoeskendeSammensaetning` fra `./presensLabels` (Task 2); `buildModel` (kun i tests).
- Produces (bruges af Task 4 + UI):
  - `type LevendeById = Record<string, boolean>`
  - `type PresensPartner = { id: string; levende: boolean }`
  - `type PresensNode = { id: string; levende: boolean; forbindelsesled: boolean; partnere: PresensPartner[]; boern: PresensNode[]; usikker: boolean }`
  - `pruneUndertrae(model: Model, levendeById: LevendeById, id: string, edgeKonfidens?: Konfidens, seen?: Set<string>): PresensNode | null`

- [ ] **Step 1: Skriv de fejlende tests**

`packages/core/src/__tests__/presensListe.test.ts` (fixture-hjælpere genbruges af Task 4-5 — læg dem øverst):

```ts
import { buildModel } from '../buildModel';
import { pruneUndertrae } from '../presensListe';
import type { Db, Koen } from '../types';

// Fixture-hjælpere (deles med klatrings- og facit-testene i denne fil).
export const mk = (id: string, koen: Koen = 'mand', born: number | null = null, died: number | null = null) =>
  ({ id, name: 'P' + id, born, died, years: '', title: '', bio: '', privat: false, koen });
export const union = (id: string, p1: string, p2: string | null = null) => ({ id, p1, p2, p2_name: null, year: null });
export const pc = (child: string, parent: string, unionId: string, konfidens?: 'sikker' | 'sandsynlig' | 'formodet' | 'omstridt') =>
  ({ child, parent, union: unionId, ...(konfidens ? { konfidens } : {}) });

describe('pruneUndertrae — bogens s.15-beskæring', () => {
  // A(død) ─ B(død) ─ C(levende);  A ─ D(død, ingen levende under sig)
  const db: Db = {
    persons: [mk('A'), mk('B'), mk('C'), mk('D')],
    unions: [union('fA', 'A'), union('fB', 'B')],
    parentChild: [pc('B', 'A', 'fA'), pc('D', 'A', 'fA'), pc('C', 'B', 'fB')],
  };
  const model = buildModel(db);

  test('afdød med levende barnebarn består som forbindelsesled; gren uden levende beskæres', () => {
    const node = pruneUndertrae(model, { C: true }, 'A');
    expect(node).not.toBeNull();
    expect(node!.forbindelsesled).toBe(true);
    expect(node!.boern.map((b) => b.id)).toEqual(['B']); // D beskåret
    expect(node!.boern[0].boern[0]).toMatchObject({ id: 'C', levende: true, forbindelsesled: false });
  });

  test('afdød uden levende under sig → null', () => {
    expect(pruneUndertrae(model, {}, 'D')).toBeNull();
  });

  test('afdød med efterlevende ægtefælle består (enke-mønstret inline i undertræer)', () => {
    const db2: Db = {
      persons: [mk('X', 'mand'), mk('E', 'kvinde')],
      unions: [{ id: 'fX', p1: 'X', p2: 'E', p2_name: null, year: null }],
      parentChild: [],
    };
    const m2 = buildModel(db2);
    const node = pruneUndertrae(m2, { E: true }, 'X');
    expect(node).not.toBeNull();
    expect(node!.partnere).toEqual([{ id: 'E', levende: true }]);
  });

  test('svag konfidens på kanten markerer barnet usikkert', () => {
    const db3: Db = {
      persons: [mk('A'), mk('B')],
      unions: [union('fA', 'A')],
      parentChild: [pc('B', 'A', 'fA', 'formodet')],
    };
    const m3 = buildModel(db3);
    const node = pruneUndertrae(m3, { A: true, B: true }, 'A');
    expect(node!.boern[0].usikker).toBe(true);
    expect(node!.usikker).toBe(false); // roden selv har ingen kant op
  });

  test('børn sorteres deterministisk på fødselsår', () => {
    const db4: Db = {
      persons: [mk('A'), mk('B', 'mand', 1980), mk('C', 'kvinde', 1977)],
      unions: [union('fA', 'A')],
      parentChild: [pc('B', 'A', 'fA'), pc('C', 'A', 'fA')],
    };
    const m4 = buildModel(db4);
    const node = pruneUndertrae(m4, { A: true, B: true, C: true }, 'A');
    expect(node!.boern.map((b) => b.id)).toEqual(['C', 'B']);
  });
});
```

- [ ] **Step 2: Kør testene — de skal fejle**

```bash
cd packages/core && npx vitest run src/__tests__/presensListe.test.ts
```

Expected: FAIL — "Cannot find module '../presensListe'".

- [ ] **Step 3: Implementér beskæringen**

`packages/core/src/presensListe.ts`:

```ts
// Præsensliste-kernen: bottom-up-beskæring + anker-klatring (spec 2026-07-22 §5).
// Rene funktioner på den COLLAPSEDE model (kanoniske id'er — kald kanoniserPresensGrundlag først).
import { KONFIDENS_RANK } from './types';
import type { Konfidens, Model } from './types';

export type LevendeById = Record<string, boolean>;
export type PresensPartner = { id: string; levende: boolean };
export type PresensNode = {
  id: string;
  levende: boolean;
  forbindelsesled: boolean; // afdød, kun medtaget fordi noget levende hænger under (bogens s.15-regel)
  partnere: PresensPartner[];
  boern: PresensNode[];
  usikker: boolean; // formodet/omstridt konfidens på kanten OP til denne node (invariant 7)
};

const svag = (k: Konfidens): boolean => k != null && KONFIDENS_RANK[k] <= KONFIDENS_RANK.formodet;

function edgeKonf(model: Model, child: string, parent: string): Konfidens {
  return model.indexes.konfByEdge[`${child}|${parent}`] ?? null;
}

function partnereAf(model: Model, levendeById: LevendeById, id: string): PresensPartner[] {
  return (model.indexes.spousesBy[id] ?? [])
    .map((s) => s.id)
    .filter((sid): sid is string => sid != null)
    .map((sid) => ({ id: sid, levende: levendeById[sid] === true }));
}

function sortNodes(model: Model, ns: PresensNode[]): void {
  ns.sort((a, b) => (model.byId[a.id]?.born ?? 9999) - (model.byId[b.id]?.born ?? 9999) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

// Beskæring bottom-up: levende medtages; afdøde kun med levende under sig eller efterlevende
// ægtefælle. GDPR-bemærkning: `levende` kommer fra person.levende — RLS afgør hvad klienten
// overhovedet kan se; denne funktion tilføjer ingen eksponering.
export function pruneUndertrae(
  model: Model,
  levendeById: LevendeById,
  id: string,
  edgeKonfidens: Konfidens = null,
  seen: Set<string> = new Set(),
): PresensNode | null {
  if (seen.has(id)) return null; // cyklus-/dobbeltvej-vagt
  seen.add(id);
  const levende = levendeById[id] === true;
  const boern = [...(model.indexes.childIdx[id] ?? new Set<string>())]
    .map((cid) => pruneUndertrae(model, levendeById, cid, edgeKonf(model, cid, id), seen))
    .filter((n): n is PresensNode => n != null);
  sortNodes(model, boern);
  const partnere = partnereAf(model, levendeById, id);
  const efterlevendePartner = !levende && partnere.some((p) => p.levende);
  if (!levende && boern.length === 0 && !efterlevendePartner) return null;
  return { id, levende, forbindelsesled: !levende, partnere, boern, usikker: svag(edgeKonfidens) };
}
```

Og i `packages/core/src/index.ts`, efter presensLabels-eksporten:

```ts
export * from './presensListe';
```

- [ ] **Step 4: Kør testene — de skal bestå**

```bash
cd packages/core && npx vitest run src/__tests__/presensListe.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/core/src/presensListe.ts packages/core/src/__tests__/presensListe.test.ts packages/core/src/index.ts
git commit -m "feat(presens): bottom-up-beskæring af undertræer (pruneUndertrae)"
```

---

### Task 4: Core — `presensListe.ts` del 2: klatring, grupper, partitionering, advarsler

**Files:**
- Modify: `packages/core/src/presensListe.ts` (append)
- Modify: `packages/core/src/__tests__/presensListe.test.ts` (append)

**Interfaces:**
- Consumes: Task 2-3-produkterne.
- Produces (bruges af UI-tasks 7-9):
  - `type PresensGruppe = { overskrift: string; niveau: number; art: 'soeskende' | 'foraelder' | 'enke'; roedder: PresensNode[]; usikker: boolean }`
  - `type PresensGren = { anker: PresensAnker; ankerBlok: PresensNode; grupper: PresensGruppe[] }`
  - `type PresensAdvarsel = { art: 'levende_uden_gren' | 'dobbelt_naaet' | 'anker_konflikt'; personId: string | null; besked: string }`
  - `type PresensListe = { grene: PresensGren[]; advarsler: PresensAdvarsel[] }`
  - `buildPresensListe(model: Model, ankre: PresensAnker[], levendeById: LevendeById): PresensListe`
  - `kanoniserPresensGrundlag(model: Model, ankre: PresensAnker[], levendeById: LevendeById): { ankre: PresensAnker[]; levendeById: LevendeById }`

- [ ] **Step 1: Skriv de fejlende tests (append i `presensListe.test.ts`)**

```ts
import { buildPresensListe, kanoniserPresensGrundlag } from '../presensListe';
import type { PresensAnker } from '../presensLabels';

const anker = (personId: string, linje = 'II', gren: number | null = 1): PresensAnker =>
  ({ personId, linje, gren, raaVaerdi: `${linje} linje${gren != null ? `, ${gren}. gren` : ''}` });

describe('buildPresensListe — klatring og grupper', () => {
  // FF(død) ─┬─ Far(død) ─┬─ ANKER(levende) ─ barn K1(levende)
  //          │            ├─ Søster S1(levende), Søster S2(levende)
  //          │            └─ (Mor(levende) er gift-ind: partner i Fars union, uden op-kobling)
  //          └─ Farbror FB(død) ─ FBdatter(levende)
  const db: Db = {
    persons: [
      mk('FF', 'mand'), mk('Far', 'mand'), mk('Mor', 'kvinde'), mk('ANKER', 'mand'),
      mk('K1', 'kvinde'), mk('S1', 'kvinde', 1946), mk('S2', 'kvinde', 1948),
      mk('FB', 'mand'), mk('FBdatter', 'kvinde'),
    ],
    unions: [
      union('fFF', 'FF'),
      { id: 'fFar', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
      union('fANKER', 'ANKER'), union('fFB', 'FB'),
    ],
    parentChild: [
      pc('Far', 'FF', 'fFF'), pc('FB', 'FF', 'fFF'),
      pc('ANKER', 'Far', 'fFar'), pc('ANKER', 'Mor', 'fFar'),
      pc('S1', 'Far', 'fFar'), pc('S1', 'Mor', 'fFar'),
      pc('S2', 'Far', 'fFar'), pc('S2', 'Mor', 'fFar'),
      pc('K1', 'ANKER', 'fANKER'), pc('FBdatter', 'FB', 'fFB'),
    ],
  };
  const model = buildModel(db);
  const levende = { ANKER: true, K1: true, S1: true, S2: true, Mor: true, FBdatter: true };

  test('ankerblok + SØSTRE + MOR + FARBROR i bogens rækkefølge', () => {
    const liste = buildPresensListe(model, [anker('ANKER')], levende);
    expect(liste.grene).toHaveLength(1);
    const g = liste.grene[0];
    expect(g.ankerBlok.id).toBe('ANKER');
    expect(g.ankerBlok.boern.map((b) => b.id)).toEqual(['K1']);
    expect(g.grupper.map((x) => x.overskrift)).toEqual(['Søstre', 'Mor', 'Farbror']);
    expect(g.grupper.map((x) => x.niveau)).toEqual([1, 1, 2]);
    // FB er død forbindelsesled med levende datter under sig
    const fb = g.grupper[2].roedder[0];
    expect(fb).toMatchObject({ id: 'FB', forbindelsesled: true });
    expect(fb.boern[0].id).toBe('FBdatter');
  });

  test('død mor → ingen MOR-gruppe; levende enke efter far → FARS ENKE', () => {
    // Far død, Mor død, men Far har en efterlevende 2. hustru E2
    const db2: Db = {
      persons: [mk('Far', 'mand'), mk('Mor', 'kvinde'), mk('E2', 'kvinde'), mk('ANKER', 'mand')],
      unions: [
        { id: 'f1', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
        { id: 'f2', p1: 'Far', p2: 'E2', p2_name: null, year: null },
      ],
      parentChild: [pc('ANKER', 'Far', 'f1'), pc('ANKER', 'Mor', 'f1')],
    };
    const m2 = buildModel(db2);
    const g = buildPresensListe(m2, [anker('ANKER')], { ANKER: true, E2: true }).grene[0];
    expect(g.grupper.map((x) => x.overskrift)).toEqual(['Fars enke']);
    expect(g.grupper[0].roedder[0].id).toBe('E2');
  });

  test('anker-partitionering: sidegren med eget anker springes over', () => {
    // FF ─┬─ Far ─ ANKER1;  FF ─┴─ Onkel ─ ANKER2 (eget gren-overhoved)
    const db3: Db = {
      persons: [mk('FF', 'mand'), mk('Far', 'mand'), mk('Onkel', 'mand'), mk('ANKER1', 'mand'), mk('ANKER2', 'mand')],
      unions: [union('fFF', 'FF'), union('fFar', 'Far'), union('fO', 'Onkel')],
      parentChild: [pc('Far', 'FF', 'fFF'), pc('Onkel', 'FF', 'fFF'), pc('ANKER1', 'Far', 'fFar'), pc('ANKER2', 'Onkel', 'fO')],
    };
    const m3 = buildModel(db3);
    const liste = buildPresensListe(m3, [anker('ANKER1', 'II', 1), anker('ANKER2', 'II', 2)], { ANKER1: true, ANKER2: true });
    const g1 = liste.grene[0];
    // Onkel-sidegrenen indeholder ANKER2 → ingen FARBROR-gruppe i gren 1
    expect(g1.grupper).toHaveLength(0);
    expect(liste.grene[1].ankerBlok.id).toBe('ANKER2');
  });

  test('advarsler: levende uden gren + anker-konflikt + dobbelt nået', () => {
    const db4: Db = {
      persons: [mk('A', 'mand'), mk('Loes', 'kvinde')],
      unions: [union('fA', 'A')],
      parentChild: [],
    };
    const m4 = buildModel(db4);
    const liste = buildPresensListe(m4, [anker('A', 'I', 1), anker('A', 'I', 1)], { A: true, Loes: true });
    expect(liste.advarsler.some((x) => x.art === 'anker_konflikt')).toBe(true);
    expect(liste.advarsler.some((x) => x.art === 'levende_uden_gren' && x.personId === 'Loes')).toBe(true);
    expect(liste.advarsler.some((x) => x.art === 'dobbelt_naaet' && x.personId === 'A')).toBe(true);
  });

  test('determinisme: samme input → identisk output', () => {
    const a = buildPresensListe(model, [anker('ANKER')], levende);
    const b = buildPresensListe(model, [anker('ANKER')], levende);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});

describe('kanoniserPresensGrundlag', () => {
  test('alias-id'er foldes; levende OR-semantik over komponenten', () => {
    const db: Db = { persons: [mk('1'), mk('2')], unions: [], parentChild: [] };
    const model = { ...buildModel(db), canonicalIdById: { '2': '1', '1': '1' } };
    const r = kanoniserPresensGrundlag(model, [anker('2')], { '2': true, '1': false });
    expect(r.ankre[0].personId).toBe('1');
    expect(r.levendeById['1']).toBe(true);
  });
});
```

- [ ] **Step 2: Kør — nye tests skal fejle**

```bash
cd packages/core && npx vitest run src/__tests__/presensListe.test.ts
```

Expected: FAIL — `buildPresensListe` ikke eksporteret.

- [ ] **Step 3: Implementér klatring + advarsler (append i `presensListe.ts`)**

```ts
import { sortAnkre, stiOverskrift } from './presensLabels';
import type { PresensAnker, SoeskendeSammensaetning } from './presensLabels';
import type { Koen } from './types';

export type PresensGruppe = {
  overskrift: string;
  niveau: number; // generationsafstand: 1 = søskende/mor-plan, 2 = fars niveau …
  art: 'soeskende' | 'foraelder' | 'enke';
  roedder: PresensNode[];
  usikker: boolean;
};
export type PresensGren = { anker: PresensAnker; ankerBlok: PresensNode; grupper: PresensGruppe[] };
export type PresensAdvarsel = {
  art: 'levende_uden_gren' | 'dobbelt_naaet' | 'anker_konflikt';
  personId: string | null;
  besked: string;
};
export type PresensListe = { grene: PresensGren[]; advarsler: PresensAdvarsel[] };

// Søskende af p: børn af p's forældre, minus p selv.
function soeskendeAf(model: Model, p: string): string[] {
  const ud = new Set<string>();
  for (const par of model.indexes.parentsByChild[p] ?? [])
    for (const c of model.indexes.childIdx[par] ?? new Set<string>()) if (c !== p) ud.add(c);
  return [...ud];
}

// Blod- vs gift-ind-forælder (spec §3): gift-ind-personer står typisk uden op-kobling i
// grafen (deres forældre er kun parentes-noter) — blodforælderen er den med egen op-kobling.
// Tie-break: mand først (DAA er patrilineær i PoC-data), dernæst laveste id. HEURISTIK,
// dokumenteret i spec §5 — fejlklassifikation giver en forkert-benævnt gruppe, aldrig datatab.
function blodOgGiftInd(model: Model, cur: string): { blod: string | null; giftInd: string | null } {
  const par = model.indexes.parentsByChild[cur] ?? [];
  if (par.length === 0) return { blod: null, giftInd: null };
  if (par.length === 1) return { blod: par[0], giftInd: null };
  const score = (p: string): number =>
    ((model.indexes.parentsByChild[p] ?? []).length > 0 || soeskendeAf(model, p).length > 0 ? 2 : 0) +
    (model.byId[p]?.koen === 'mand' ? 1 : 0);
  const sorted = [...par].sort((a, b) => score(b) - score(a) || (a < b ? -1 : a > b ? 1 : 0));
  return { blod: sorted[0], giftInd: sorted[1] ?? null };
}

// Er et af de andre ankre i rootId's undertræ (inkl. rootId selv)? → sidegrenen har sin egen
// gren-sektion og springes over (spec §5 trin 6: grenene partitionerer sig selv).
function indeholderAnker(model: Model, rootId: string, andreAnkre: Set<string>): boolean {
  const queue = [rootId];
  const seen = new Set<string>(queue);
  let head = 0;
  while (head < queue.length) {
    const cur = queue[head++];
    if (andreAnkre.has(cur)) return true;
    for (const c of model.indexes.childIdx[cur] ?? new Set<string>())
      if (!seen.has(c)) { seen.add(c); queue.push(c); }
  }
  return false;
}

function koenSammensaetning(model: Model, ids: string[]): SoeskendeSammensaetning {
  const s: SoeskendeSammensaetning = { maend: 0, kvinder: 0, ukendt: 0 };
  for (const id of ids) {
    const k = model.byId[id]?.koen;
    if (k === 'mand') s.maend++; else if (k === 'kvinde') s.kvinder++; else s.ukendt++;
  }
  return s;
}

// Enkelt-person-node uden undertræ (gift-ind-forælder, enke, nød-anker).
function blad(model: Model, levendeById: LevendeById, id: string): PresensNode {
  const levende = levendeById[id] === true;
  return { id, levende, forbindelsesled: !levende, partnere: partnereAf(model, levendeById, id), boern: [], usikker: false };
}

const ART_ORDEN: Record<PresensGruppe['art'], number> = { soeskende: 0, foraelder: 1, enke: 2 };

function buildGren(model: Model, levendeById: LevendeById, anker: PresensAnker, andreAnkre: Set<string>): PresensGren {
  // Ankeret medtages ALTID — også hvis beskæringen ellers ville fjerne det.
  const ankerBlok = pruneUndertrae(model, levendeById, anker.personId) ?? blad(model, levendeById, anker.personId);
  const grupper: PresensGruppe[] = [];
  const kaede: Koen[] = [];
  let cur = anker.personId;
  const beskyt = new Set<string>([anker.personId]); // mod umulige forfader-cyklusser
  for (let guard = 0; guard < 50; guard++) {
    const { blod, giftInd } = blodOgGiftInd(model, cur);
    const niveau = kaede.length + 1;
    // 1) Søskende-sidegrene: blodforfaderens øvrige børn.
    if (blod != null) {
      const roedder = [...(model.indexes.childIdx[blod] ?? new Set<string>())]
        .filter((c) => c !== cur && !indeholderAnker(model, c, andreAnkre))
        .map((c) => pruneUndertrae(model, levendeById, c, edgeKonf(model, c, blod)))
        .filter((n): n is PresensNode => n != null);
      sortNodes(model, roedder);
      if (roedder.length > 0) {
        grupper.push({
          art: 'soeskende', niveau,
          overskrift: stiOverskrift(kaede, { slags: 'soeskende', sammensaetning: koenSammensaetning(model, roedder.map((r) => r.id)) }),
          roedder,
          usikker: svag(edgeKonf(model, cur, blod)) || roedder.some((r) => r.usikker),
        });
      }
    }
    // 2) Levende gift-ind-forælder: MOR / FAR / FARMOR …
    if (giftInd != null && levendeById[giftInd] === true) {
      grupper.push({
        art: 'foraelder', niveau,
        overskrift: stiOverskrift(kaede, { slags: 'foraelder', koen: model.byId[giftInd]?.koen ?? null }),
        roedder: [blad(model, levendeById, giftInd)],
        usikker: svag(edgeKonf(model, cur, giftInd)),
      });
    }
    // 3) Enke efter afdød blodforfader (som ikke er gift-ind-forælderen — hun har egen gruppe).
    if (blod != null && levendeById[blod] !== true) {
      const enker = partnereAf(model, levendeById, blod).filter((p) => p.levende && p.id !== giftInd);
      if (enker.length > 0) {
        grupper.push({
          art: 'enke', niveau,
          overskrift: stiOverskrift([...kaede, model.byId[blod]?.koen ?? null], { slags: 'enke' }),
          roedder: enker.map((p) => blad(model, levendeById, p.id)),
          usikker: false,
        });
      }
    }
    if (blod == null || beskyt.has(blod)) break;
    beskyt.add(blod);
    kaede.push(model.byId[blod]?.koen ?? null);
    cur = blod;
  }
  grupper.sort((a, b) => a.niveau - b.niveau || ART_ORDEN[a.art] - ART_ORDEN[b.art] || (a.overskrift < b.overskrift ? -1 : a.overskrift > b.overskrift ? 1 : 0));
  return { anker, ankerBlok, grupper };
}

function samlIds(n: PresensNode, ud: Set<string>): void {
  ud.add(n.id);
  for (const p of n.partnere) ud.add(p.id);
  for (const b of n.boern) samlIds(b, ud);
}

export function buildPresensListe(model: Model, ankre: PresensAnker[], levendeById: LevendeById): PresensListe {
  const advarsler: PresensAdvarsel[] = [];
  const sorteret = sortAnkre(ankre);
  const set = new Map<string, PresensAnker>();
  for (const a of sorteret) {
    const key = `${a.linje}|${a.gren ?? ''}`;
    const anden = set.get(key);
    if (anden) advarsler.push({ art: 'anker_konflikt', personId: a.personId, besked: `To overhoveder udpeget for "${a.raaVaerdi}" (person ${anden.personId} og ${a.personId})` });
    else set.set(key, a);
  }
  const ankerIds = new Set(sorteret.map((a) => a.personId));
  const grene = sorteret.map((a) =>
    buildGren(model, levendeById, a, new Set([...ankerIds].filter((id) => id !== a.personId))),
  );
  // Dæknings-advarsler (spec §7): rapportering, aldrig skrivning.
  const naaet = new Map<string, number>();
  for (const g of grene) {
    const ids = new Set<string>();
    samlIds(g.ankerBlok, ids);
    for (const gr of g.grupper) for (const r of gr.roedder) samlIds(r, ids);
    for (const id of ids) naaet.set(id, (naaet.get(id) ?? 0) + 1);
  }
  for (const [id, n] of naaet)
    if (n > 1) advarsler.push({ art: 'dobbelt_naaet', personId: id, besked: `${model.byId[id]?.name ?? id} optræder i ${n} grene — muligt identitets-dublet eller overlappende ankre` });
  for (const p of model.persons)
    if (levendeById[p.id] === true && !naaet.has(p.id))
      advarsler.push({ art: 'levende_uden_gren', personId: p.id, besked: `${p.name} er levende, men indgår i ingen gren — hul i ankersættet eller manglende slægtskabskant` });
  advarsler.sort((a, b) => a.art.localeCompare(b.art) || String(a.personId).localeCompare(String(b.personId)));
  return { grene, advarsler };
}

// Fold rå id'er til kanoniske (samme_som-collapse). Levende = OR over komponentens medlemmer.
export function kanoniserPresensGrundlag(
  model: Model,
  ankre: PresensAnker[],
  levendeById: LevendeById,
): { ankre: PresensAnker[]; levendeById: LevendeById } {
  const canon = model.canonicalIdById ?? {};
  const levende: LevendeById = {};
  for (const [id, lv] of Object.entries(levendeById)) {
    const cid = canon[id] ?? id;
    levende[cid] = levende[cid] === true || lv === true;
  }
  const ud = new Map<string, PresensAnker>();
  for (const a of ankre) {
    const cid = canon[a.personId] ?? a.personId;
    if (!ud.has(cid)) ud.set(cid, { ...a, personId: cid });
  }
  return { ankre: [...ud.values()], levendeById: levende };
}
```

- [ ] **Step 4: Kør hele core-suiten — alt skal bestå**

```bash
cd packages/core && npx vitest run && npx tsc --noEmit
```

Expected: PASS (alle filer, også de eksisterende).

- [ ] **Step 5: Commit**

```bash
git add packages/core/src/presensListe.ts packages/core/src/__tests__/presensListe.test.ts
git commit -m "feat(presens): anker-klatring, relationsgrupper, partitionering og advarsler"
```

---

### Task 5: Core — facitliste-test (II linje, 1. gren, DAA 2012-14)

**Files:**
- Create: `packages/core/src/__tests__/presensFacit.test.ts`

**Interfaces:**
- Consumes: `buildPresensListe`, `mk`/`union`/`pc`-hjælperne fra `presensListe.test.ts` (de er eksporteret dér).

- [ ] **Step 1: Skriv facit-testen (den skal BESTÅ direkte — det er en regressionsfacit mod bogen)**

Fixturen gengiver strukturen fra PDF-side 362 (forenklet men strukturtro — 4 forfaderled, FARFARS FARBROR som dødt forbindelsesled med levende efterkommere):

```ts
import { buildModel } from '../buildModel';
import { buildPresensListe } from '../presensListe';
import { mk, union, pc } from './presensListe.test';
import type { Db } from '../types';

// Facit: DAA 2012-14, II LINJE 1. GREN (PDF s. 362). Anker = Christian Ditlev Ludvig (CDL).
// Bogens grupper: SØSTRE (Alette, Sybille) og FARFARS FARBROR (Ludvig, †1916, hvis
// efterkommere via Iven m.fl. lever). Far og mor er begge døde → ingen MOR-gruppe.
const db: Db = {
  persons: [
    // Blodlinjen op: CDL ← Far (Christian Benedict, †) ← Farfar (†) ← FarfarsFar (†)
    mk('CDL', 'mand', 1950), mk('Far', 'mand', 1915, 1984), mk('Mor', 'kvinde', 1921, 2012),
    mk('Farfar', 'mand', 1885, 1970), mk('FarfarsFar', 'mand', 1855, 1930),
    mk('FFFFar', 'mand', 1820, 1890), // farfars fars far — fælles ane for FARFARS FARBROR-gruppen
    // Ankerets familie
    mk('Anni', 'kvinde', 1951), mk('JohanM', 'mand', 1977), mk('Julie', 'kvinde', 1980), mk('AndreasC', 'mand', 1985),
    mk('FrederikJ', 'mand', 2013),
    // Søstrene
    mk('Alette', 'kvinde', 1946), mk('Sybille', 'kvinde', 1948),
    // FARFARS FARBROR-sidegrenen: Ludvig (†1916) ─ Otto (†) ─ Iven (levende)
    mk('Ludvig', 'mand', 1848, 1916), mk('Otto', 'mand', 1886, 1929), mk('Iven', 'mand', 1926),
  ],
  unions: [
    { id: 'fFFFFar', p1: 'FFFFar', p2: null, p2_name: null, year: null },
    union('fFarfarsFar', 'FarfarsFar'), union('fFarfar', 'Farfar'),
    { id: 'fFar', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
    { id: 'fCDL', p1: 'CDL', p2: 'Anni', p2_name: null, year: null },
    union('fLudvig', 'Ludvig'), union('fOtto', 'Otto'),
  ],
  parentChild: [
    pc('FarfarsFar', 'FFFFar', 'fFFFFar'), pc('Ludvig', 'FFFFar', 'fFFFFar'),
    pc('Farfar', 'FarfarsFar', 'fFarfarsFar'),
    pc('Far', 'Farfar', 'fFarfar'),
    pc('CDL', 'Far', 'fFar'), pc('CDL', 'Mor', 'fFar'),
    pc('Alette', 'Far', 'fFar'), pc('Alette', 'Mor', 'fFar'),
    pc('Sybille', 'Far', 'fFar'), pc('Sybille', 'Mor', 'fFar'),
    pc('JohanM', 'CDL', 'fCDL'), pc('Julie', 'CDL', 'fCDL'), pc('AndreasC', 'CDL', 'fCDL'),
    pc('FrederikJ', 'JohanM', 'fJM'), // union oprettes implicit ikke — se union-listen note nedenfor
    pc('Otto', 'Ludvig', 'fLudvig'), pc('Iven', 'Otto', 'fOtto'),
  ],
};
// NB: 'fJM' skal med i unions-listen for at kanten er gyldig:
db.unions.push(union('fJM', 'JohanM'));

const model = buildModel(db);
const levende = { CDL: true, Anni: true, JohanM: true, Julie: true, AndreasC: true, FrederikJ: true, Alette: true, Sybille: true, Iven: true };

test('facit: II linje 1. gren reproducerer bogens gruppestruktur', () => {
  const liste = buildPresensListe(model, [{ personId: 'CDL', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' }], levende);
  const g = liste.grene[0];
  // Ankerblok: CDL + ægtefælle + tre børn + barnebarn under Johan Martin
  expect(g.ankerBlok.id).toBe('CDL');
  expect(g.ankerBlok.partnere.map((p) => p.id)).toContain('Anni');
  expect(g.ankerBlok.boern.map((b) => b.id)).toEqual(['JohanM', 'Julie', 'AndreasC']);
  expect(g.ankerBlok.boern[0].boern.map((b) => b.id)).toEqual(['FrederikJ']);
  // Bogens grupper, i bogens rækkefølge — og INGEN Mor-gruppe (hun er død):
  expect(g.grupper.map((x) => x.overskrift)).toEqual(['Søstre', 'Farfars farbror']);
  expect(g.grupper[0].roedder.map((r) => r.id)).toEqual(['Alette', 'Sybille']);
  // Ludvig er dødt forbindelsesled; kæden ned til levende Iven bevaret, død-uden-levende beskåret undervejs findes ikke
  const ludvig = g.grupper[1].roedder[0];
  expect(ludvig).toMatchObject({ id: 'Ludvig', forbindelsesled: true });
  expect(ludvig.boern[0].id).toBe('Otto');
  expect(ludvig.boern[0].boern[0]).toMatchObject({ id: 'Iven', levende: true });
  // Ingen advarsler om levende uden gren i denne lukkede fixture
  expect(liste.advarsler.filter((a) => a.art === 'levende_uden_gren')).toHaveLength(0);
});
```

- [ ] **Step 2: Kør facit-testen**

```bash
cd packages/core && npx vitest run src/__tests__/presensFacit.test.ts
```

Expected: PASS. Fejler den, er det en algoritmefejl (gruppedannelse, rækkefølge eller label) — ret KERNEN (Task 2-4), aldrig facit (bogen er facit). Bemærk: `mk`/`union`/`pc` importeres fra testfilen fra Task 3 — tjek at `export`-nøgleordene står der.

- [ ] **Step 3: Commit**

```bash
git add packages/core/src/__tests__/presensFacit.test.ts
git commit -m "test(presens): facitliste-regression mod DAA 2012-14 II linje 1. gren"
```

---

### Task 6: Web — data-lag (`presens.ts`: levende-flag + overhoved-fakta)

**Files:**
- Create: `web/src/data/presens.ts`
- Create: `web/src/data/__tests__/presens.test.ts`

**Interfaces:**
- Consumes: `supabase` fra `../supabase`; `getAll`, `parseOverhovedVaerdi` fra `@daa/core`.
- Produces (bruges af Task 8):
  - `type PresensGrundlag = { ankre: PresensAnker[]; levendeById: Record<string, boolean> }`
  - `mapPresensGrundlag(...)` (ren, testbar)
  - `fetchPresensGrundlag(): Promise<PresensGrundlag>`

- [ ] **Step 1: Skriv den fejlende test for den rene mapper**

`web/src/data/__tests__/presens.test.ts`:

```ts
import { mapPresensGrundlag } from '../presens';

test('mapPresensGrundlag: joiner fact→konklusion→assertion og parser værdier', () => {
  const r = mapPresensGrundlag(
    [{ id: 1, levende: true }, { id: 2, levende: false }, { id: 3, levende: null }],
    [{ id: 10, subjekt_id: 1 }, { id: 11, subjekt_id: 2 }],
    [{ target_id: 10, valgt_assertion_id: 100 }, { target_id: 11, valgt_assertion_id: 101 }],
    [{ id: 100, vaerdi_tekst: 'II linje, 1. gren' }, { id: 101, vaerdi_tekst: 'ukendt format' }],
  );
  expect(r.levendeById).toEqual({ '1': true, '2': false, '3': false });
  // fact 11's værdi kan ikke parses → droppes fail-closed (ingen gættede ankre)
  expect(r.ankre).toEqual([{ personId: '1', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' }]);
});

test('mapPresensGrundlag: fact uden afklaret konklusion droppes', () => {
  const r = mapPresensGrundlag([{ id: 1, levende: true }], [{ id: 10, subjekt_id: 1 }], [], []);
  expect(r.ankre).toEqual([]);
});
```

- [ ] **Step 2: Kør — skal fejle**

```bash
cd web && npx vitest run src/data/__tests__/presens.test.ts
```

Expected: FAIL — modulet findes ikke.

- [ ] **Step 3: Implementér `web/src/data/presens.ts`**

Fetch-mønstret følger `fetchParentsUnknownRows` i `web/src/data/model.ts:192-204` (fact → afklaret konklusion → assertion):

```ts
// Præsensliste-grundlag: levende-flag + overhoved-fakta. RLS afgør hvad klienten ser —
// anon/medlem får ingen levende rækker (fail-closed), redaktør-JWT ser alt. Visningen
// tilføjer altså ingen eksponering (spec 2026-07-22 §8).
import { supabase } from '../supabase';
import { getAll, parseOverhovedVaerdi } from '@daa/core';
import type { PresensAnker } from '@daa/core';

export type PresensGrundlag = { ankre: PresensAnker[]; levendeById: Record<string, boolean> };

type RawLevende = { id: number | string; levende: boolean | null };
type RawOverhovedFact = { id: number | string; subjekt_id: number | string };
type RawKonkl = { target_id: number | string; valgt_assertion_id: number | string | null };
type RawAssert = { id: number | string; vaerdi_tekst: string | null };

export function mapPresensGrundlag(
  persons: RawLevende[],
  facts: RawOverhovedFact[],
  conclusions: RawKonkl[],
  assertions: RawAssert[],
): PresensGrundlag {
  const levendeById: Record<string, boolean> = {};
  for (const p of persons) levendeById[String(p.id)] = p.levende === true;
  const assertById = new Map(assertions.map((a) => [String(a.id), a.vaerdi_tekst]));
  const valgtByFact = new Map(conclusions.map((c) => [String(c.target_id), c.valgt_assertion_id]));
  const ankre: PresensAnker[] = [];
  for (const f of facts) {
    const valgt = valgtByFact.get(String(f.id));
    if (valgt == null) continue; // ingen afklaret konklusion → intet anker
    const vaerdi = assertById.get(String(valgt));
    if (vaerdi == null) continue;
    const anker = parseOverhovedVaerdi(String(f.subjekt_id), vaerdi);
    if (anker) ankre.push(anker); // uparsebar værdi droppes fail-closed
  }
  return { ankre, levendeById };
}

export async function fetchPresensGrundlag(): Promise<PresensGrundlag> {
  const persons = await getAll<RawLevende>(() => supabase.from('person').select('id,levende'));
  const facts = await getAll<RawOverhovedFact>(() =>
    supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'overhoved').order('id'));
  if (!facts.length) return mapPresensGrundlag(persons, [], [], []);
  const factIds = facts.map((f) => f.id);
  const conclusions = await getAll<RawKonkl>(() =>
    supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'));
  const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
  const assertions = assertionIds.length
    ? await getAll<RawAssert>(() => supabase.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'))
    : [];
  return mapPresensGrundlag(persons, facts, conclusions, assertions);
}
```

- [ ] **Step 4: Kør — skal bestå**

```bash
cd web && npx vitest run src/data/__tests__/presens.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/src/data/presens.ts web/src/data/__tests__/presens.test.ts
git commit -m "feat(presens): web-datalag for levende-flag og overhoved-ankre"
```

---

### Task 7: Web + mobil — `overhoved` som redigerbart felt i person-editoren

**Files:**
- Modify: `web/src/data/redaktionWrite.ts:13-16` (`FELT_FAKTATYPE`)
- Modify: `web/src/Redaktion.tsx:79-82` (`FELT_DEFS`)
- Modify: `mobile/src/data/redaktionWrite.ts` (samme `FELT_FAKTATYPE`-map, ca. samme linjer)
- Modify: `mobile/src/app/redaktion/person/[id].tsx:58-62` (`FELTER` + `FELT_LABEL`)
- Test: `web/src/data/__tests__/redaktionWrite.test.ts` + `mobile/src/data/__tests__/redaktionWrite.test.ts` (append)

**Interfaces:**
- Produces: redaktøren kan oprette/redigere `overhoved`-fakta via det EKSISTERENDE `red_upsert_fakta`-flow (web: art `'fakta'`; mobil: art `'opretFakta'`). Ingen ny RPC (spec §4).

- [ ] **Step 1: Skriv de fejlende mapping-tests**

Append i `web/src/data/__tests__/redaktionWrite.test.ts` (følg filens eksisterende mønster for art `'fakta'` — find et eksisterende testcase som skabelon for kaldskonventionen, typisk `toRpc`/`buildRpc`-style; behold præcis samme konvention):

```ts
test('fakta-art med felt overhoved mapper til red_upsert_fakta med faktatype overhoved', () => {
  // Brug filens eksisterende hjælpefunktion til at bygge Change→RPC (samme som navn/titel-testene).
  // Forventning: fn 'red_upsert_fakta', args.p_faktatype === 'overhoved',
  // args.p_vaerdi === 'II linje, 1. gren', ingen p_date_raw (overhoved er IKKE et datofelt).
});
```

Tilsvarende i `mobile/src/data/__tests__/redaktionWrite.test.ts` for art `'opretFakta'` → `red_opret_fakta` med `p_faktatype: 'overhoved'`. Skriv testene konkret ud fra filens faktiske hjælper (den findes — navn/titel-felterne er testet på samme måde).

- [ ] **Step 2: Kør — skal fejle**

```bash
cd web && npx vitest run src/data/__tests__/redaktionWrite.test.ts
cd ../mobile && npx jest src/data/__tests__/redaktionWrite.test.ts
```

Expected: FAIL (felt ukendt → mapper returnerer null/udelader kaldet).

- [ ] **Step 3: Tilføj feltet alle fire steder**

`web/src/data/redaktionWrite.ts` — udvid `FELT_FAKTATYPE`:

```ts
export const FELT_FAKTATYPE: Record<string, string> = {
  navn: 'navn', foedt: 'fødsel', doed: 'død', titel: 'titel',
  daab: 'dåb', begravelse: 'begravelse', floruit: 'floruit', naturalisering: 'naturalisering',
  overhoved: 'overhoved', // præsensliste-anker: 'II linje, 1. gren' (spec 2026-07-22 §4)
};
```

`web/src/Redaktion.tsx` — udvid `FELT_DEFS`:

```ts
const FELT_DEFS: [string, string][] = [
  ['navn', 'Navn'], ['foedt', 'Født'], ['doed', 'Død'], ['titel', 'Titel/rang'],
  ['daab', 'Dåb'], ['begravelse', 'Begravelse'], ['floruit', 'Floruit'], ['naturalisering', 'Naturalisation'],
  ['overhoved', 'Overhoved (linje/gren)'],
];
```

`mobile/src/data/redaktionWrite.ts` — samme `overhoved: 'overhoved'`-linje i dens `FELT_FAKTATYPE`.

`mobile/src/app/redaktion/person/[id].tsx`:

```ts
const FELTER = ['navn', 'foedt', 'doed', 'titel', 'daab', 'begravelse', 'floruit', 'naturalisering', 'overhoved'];
const FELT_LABEL: Record<string, string> = {
  navn: 'navn', foedt: 'født', doed: 'død', titel: 'titel',
  daab: 'dåb', begravelse: 'begravelse', floruit: 'floruit', naturalisering: 'naturalisation',
  overhoved: 'overhoved (linje/gren)',
};
```

Bemærk: `FAKTATYPE_FELT` i begge `redaktionRead.ts` afledes af `FELT_FAKTATYPE` — eksisterende overhoved-fakta bliver automatisk synlige/redigerbare uden yderligere ændring. `overhoved` må IKKE tilføjes `DATE_FELT`.

- [ ] **Step 4: Kør — skal bestå (+ fuld web- og mobil-suite for regression)**

```bash
cd web && npx vitest run && cd ../mobile && npx jest
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/src/data/redaktionWrite.ts web/src/Redaktion.tsx mobile/src/data/redaktionWrite.ts "mobile/src/app/redaktion/person/[id].tsx" web/src/data/__tests__/redaktionWrite.test.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(presens): overhoved-felt i person-editoren (web+mobil)"
```

---

### Task 8: Web — Mode `praesens`, PresensView, gating og person-genvej

**Files:**
- Modify: `web/src/data/nav.ts` (Mode + THEMES + MODE_PATH)
- Create: `web/src/components/PresensView.tsx`
- Modify: `web/src/Folgesvend.tsx` (center-switch + DetailPanel-genvej)
- Modify: `web/src/components/DetailPanel.tsx` (genvejs-link, optional prop)
- Test: `web/src/components/__tests__/PresensView.test.tsx` + evt. eksisterende nav-test

**Interfaces:**
- Consumes: `buildPresensListe`, `kanoniserPresensGrundlag`, typerne fra core; `fetchPresensGrundlag` (Task 6); `currentSession` fra `web/src/data/auth.ts` (rolle `'redaktion'`); `Model` + `navigate`.
- Produces: rute `/praesens`; `PresensView`-komponent; eksporteret ren under-komponent `PresensGrenSektion` til test.

- [ ] **Step 1: Udvid nav-grammatikken**

I `web/src/data/nav.ts`:
- `Mode`-typen: tilføj `'praesens'`.
- `THEMES` under `'slaegten'`: tilføj `{ label: 'Præsensliste', mode: 'praesens' }` efter `Slægtskab`.
- `MODE_PATH`: tilføj `praesens: '/praesens'`.

Findes en nav-test (søg `parseFolgesvendPath` i `web/src`-tests), tilføj asserts: `parseFolgesvendPath('/praesens').mode === 'praesens'` og `pathForMode('praesens') === '/praesens'`; ellers opret `web/src/data/__tests__/nav.presens.test.ts` med præcis de to asserts.

- [ ] **Step 2: Skriv fejlende komponent-test for gren-sektionen (ren rendering)**

`web/src/components/__tests__/PresensView.test.tsx` (følg mønsteret i naboliggende komponent-tests — vitest + @testing-library/react er opsat i web):

```tsx
import { render, screen } from '@testing-library/react';
import { PresensGrenSektion } from '../PresensView';
import type { PresensGren } from '@daa/core';

const gren: PresensGren = {
  anker: { personId: 'A', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' },
  ankerBlok: { id: 'A', levende: true, forbindelsesled: false, partnere: [{ id: 'P', levende: true }], boern: [
    { id: 'B', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false },
  ], usikker: false },
  grupper: [
    { overskrift: 'Søstre', niveau: 1, art: 'soeskende', usikker: false, roedder: [
      { id: 'S', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: true },
    ] },
  ],
};
const navnAf = (id: string) => ({ A: 'Anker Person', P: 'Partner Person', B: 'Barn Person', S: 'Søster Person' }[id] ?? id);
const aarAf = () => '';

test('gren-sektion viser overskrift, ankerblok, gruppe og usikkerheds-markering', () => {
  render(<PresensGrenSektion gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('II linje, 1. gren')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
  expect(screen.getByText('Søstre')).toBeTruthy();
  expect(screen.getByText('Søster Person')).toBeTruthy();
  expect(screen.getByTitle(/usikkert slægtskab/i)).toBeTruthy(); // konfidens-markering (invariant 7)
});
```

Kør: `cd web && npx vitest run src/components/__tests__/PresensView.test.tsx` → Expected: FAIL (modul findes ikke).

- [ ] **Step 3: Implementér `PresensView.tsx`**

Krav (design-spec §6 — brug `theme.ts`-tokens `T` som de øvrige views; kig på `BookmarksView.tsx` for stil-idiom, men koden her er selvbærende):

```tsx
// Præsensliste-læsefladen (spec 2026-07-22 §6). Redaktion-gated i v1: klient-gaten er UX —
// RLS er sikkerhedsgrænsen (§8). Beregningen er en ren projektion; ingen skrivninger.
import { useEffect, useMemo, useState } from 'react';
import { buildPresensListe, kanoniserPresensGrundlag } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode } from '@daa/core';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
import { currentSession, type RedSession } from '../data/auth';
import { T } from '../theme';

// Ren gren-sektion — eksporteret til test. navnAf/aarAf holder Model ude af renderingen.
export function PresensGrenSektion(props: {
  gren: PresensGren;
  navnAf: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  fokusId?: string | null;
}) {
  const { gren, navnAf, aarAf, onPick, fokusId } = props;
  const renderNode = (n: PresensNode, dybde: number) => (
    <div key={n.id} style={{ marginLeft: dybde * 18, marginBottom: 2 }}>
      <span
        data-person-id={n.id}
        onClick={() => onPick(n.id)}
        title={n.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
        style={{
          cursor: 'pointer',
          fontStyle: n.forbindelsesled ? 'italic' : 'normal', // bogens kursiv for afdøde forbindelsesled
          color: n.forbindelsesled ? T.muted3 : T.ink,
          background: fokusId === n.id ? 'rgba(128,0,32,.08)' : 'transparent',
        }}
      >
        {navnAf(n.id)} {aarAf(n.id)}{n.usikker ? ' ⚠' : ''}
      </span>
      {n.partnere.filter((p) => p.levende || !n.forbindelsesled).map((p) => (
        <span key={p.id} style={{ color: T.muted3 }}>
          {' '}· g. m. <span data-person-id={p.id} onClick={() => onPick(p.id)} style={{ cursor: 'pointer' }}>{navnAf(p.id)}</span>
        </span>
      ))}
      {n.boern.map((b) => renderNode(b, dybde + 1))}
    </div>
  );
  return (
    <section style={{ marginBottom: 34 }}>
      <h2 style={{ fontFamily: T.sans, fontSize: 13, letterSpacing: 1.5, textTransform: 'uppercase', color: T.bordeaux }}>
        {gren.anker.raaVaerdi}
      </h2>
      {renderNode(gren.ankerBlok, 0)}
      {gren.grupper.map((gr) => (
        <div key={gr.overskrift + gr.niveau} style={{ marginTop: 16 }}>
          <h3
            title={gr.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
            style={{ fontFamily: T.sans, fontSize: 11.5, letterSpacing: 2, textTransform: 'uppercase', color: T.muted3 }}
          >
            {gr.overskrift}{gr.usikker ? ' ⚠' : ''}
          </h3>
          {gr.roedder.map((r) => renderNode(r, 1))}
        </div>
      ))}
    </section>
  );
}

export default function PresensView(props: { model: Model | null; onPickPerson: (id: string) => void }) {
  const { model, onPickPerson } = props;
  const [session, setSession] = useState<RedSession | null | 'henter'>('henter');
  const [grundlag, setGrundlag] = useState<PresensGrundlag | null>(null);
  const [fejl, setFejl] = useState<string | null>(null);
  const fokusId = (window.history.state as { fokusId?: string } | null)?.fokusId ?? null;

  useEffect(() => { currentSession().then(setSession).catch(() => setSession(null)); }, []);
  useEffect(() => {
    if (session === 'henter' || session?.role !== 'redaktion') return;
    fetchPresensGrundlag().then(setGrundlag).catch((e) => setFejl(String(e?.message ?? e)));
  }, [session]);

  const liste: PresensListe | null = useMemo(() => {
    if (!model || !grundlag) return null;
    const k = kanoniserPresensGrundlag(model, grundlag.ankre, grundlag.levendeById);
    return buildPresensListe(model, k.ankre, k.levendeById);
  }, [model, grundlag]);

  if (session === 'henter') return <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>;
  if (session?.role !== 'redaktion')
    return <div style={{ padding: 40, color: T.muted3, fontFamily: T.sans }}>
      Præsenslisten kræver redaktør-login (v1 er redaktion-only). Log ind via <a href="/redaktion">Redaktion</a> og vend tilbage.
    </div>;
  if (fejl) return <div style={{ padding: 40, color: T.bordeaux }}>Kunne ikke hente grundlaget: {fejl}</div>;
  if (!liste) return <div style={{ padding: 40, color: T.muted3 }}>Henter…</div>;
  if (liste.grene.length === 0)
    return <div style={{ padding: 40, color: T.muted3, fontFamily: T.sans }}>
      Ingen overhoveder udpeget endnu. Udpeg et linje-/gren-overhoved via person-editorens felt
      "Overhoved (linje/gren)" (værdi fx "II linje, 1. gren").
      {Object.values(grundlag?.levendeById ?? {}).every((v) => !v) && (
        <div style={{ marginTop: 10 }}>Bemærk: modellen indeholder ingen levende personer — er du logget ind som redaktør, så genindlæs siden, så data hentes med dit login.</div>
      )}
    </div>;

  const navnAf = (id: string) => model!.byId[id]?.name ?? `person ${id}`;
  const aarAf = (id: string) => model!.byId[id]?.years ?? '';
  return (
    <div style={{ padding: '28px 40px', maxWidth: 780 }}>
      <h1 style={{ fontFamily: T.sans, fontSize: 18 }}>Præsensliste</h1>
      {liste.advarsler.length > 0 && (
        <details style={{ margin: '10px 0 20px', fontFamily: T.sans, fontSize: 12, color: T.muted3 }}>
          <summary>{liste.advarsler.length} redaktionelle advarsler (rapportering — udløser aldrig ændringer)</summary>
          <ul>{liste.advarsler.slice(0, 200).map((a, i) => <li key={i}>{a.besked}</li>)}</ul>
        </details>
      )}
      {liste.grene.map((g) => (
        <PresensGrenSektion key={g.anker.personId} gren={g} navnAf={navnAf} aarAf={aarAf} onPick={onPickPerson} fokusId={fokusId} />
      ))}
    </div>
  );
}
```

Efter mount med `fokusId`: scroll via `document.querySelector('[data-person-id="..."]')?.scrollIntoView({ block: 'center' })` i en `useEffect` gated på at `liste` er sat (tilføj den — tre linjer).

VIGTIGT (kendt begrænsning, dokumenteres i changelog): `Model` indlæses ved app-start; er brugeren logget ind som redaktør EFTER load, mangler levende personer i modellen indtil reload. Tom-tilstanden ovenfor forklarer det.

- [ ] **Step 4: Wire ind i Folgesvend + DetailPanel**

I `web/src/Folgesvend.tsx`-center-switchen (efter `mode === 'kort'`-grenen, ca. linje 485):

```tsx
: mode === 'praesens' ? <PresensView model={model} onPickPerson={navigateTree} />
```

(+ `import PresensView from './components/PresensView';` i toppen). tsc's exhaustive-tjek af `Mode` fanger manglende gren.

I `web/src/components/DetailPanel.tsx`: tilføj optional prop `onVisPraesens?: () => void`; render nederst i panelet, kun når sat:

```tsx
{props.onVisPraesens && (
  <div onClick={props.onVisPraesens} style={{ cursor: 'pointer', fontFamily: T.sans, fontSize: 12, color: T.bordeaux, marginTop: 10 }}>
    Vis i præsensliste ↗
  </div>
)}
```

I Folgesvend, hvor `DetailPanel` renderes (ca. linje 492), tilføj:

```tsx
onVisPraesens={() => navigate('/praesens', { state: { fokusId: focusId } })}
```

- [ ] **Step 5: Kør tests + tsc + manuel røgtest**

```bash
cd web && npx vitest run && npx tsc --noEmit
```

Expected: PASS begge. Manuel røgtest: `cd web && npm run dev` → åbn `/praesens` uindlogget (gate-besked) og som redaktør (tom-tilstand eller liste). Rapportér hvad der blev set.

- [ ] **Step 6: Commit**

```bash
git add web/src/data/nav.ts web/src/components/PresensView.tsx web/src/components/__tests__/PresensView.test.tsx web/src/Folgesvend.tsx web/src/components/DetailPanel.tsx web/src/data/__tests__/
git commit -m "feat(presens): præsensliste-læseflade i web-Følgesvenden (redaktion-gated)"
```

---

### Task 9: Mobil — data-lag, route og drawer-punkt

**Files:**
- Create: `mobile/src/data/presens.ts` (spejl af web-modulet)
- Create: `mobile/src/data/__tests__/presens.test.ts` (spejl af web-testen)
- Create: `mobile/src/app/praesens.tsx`
- Modify: `mobile/src/components/MenuDrawer.tsx` (NAV-listen)

**Interfaces:**
- Consumes: `useStore((s) => s.model)` (mobile-store, felt `model: Model | null`); `fetchProfile`/auth-helpers fra `mobile/src/lib/auth.ts` (`Profile.rolle === 'redaktion'`); supabase fra `mobile/src/lib/supabase.ts` (NB: kan være `null` i mobil — guard som i `lib/auth.ts:15`).
- Produces: route `/praesens` + drawer-punkt `09 Præsensliste`.

- [ ] **Step 1: Data-lag + test (spejl)**

`mobile/src/data/presens.ts`: samme indhold som `web/src/data/presens.ts` (Task 6 Step 3) med to ændringer: import af supabase fra `../lib/supabase`, og en `if (!supabase) return { ankre: [], levendeById: {} };`-guard øverst i `fetchPresensGrundlag`. `mapPresensGrundlag` er identisk.

`mobile/src/data/__tests__/presens.test.ts`: identisk med web-testen fra Task 6 Step 1 (jest og vitest deler expect-syntaks her).

```bash
cd mobile && npx jest src/data/__tests__/presens.test.ts
```

Expected: FAIL før implementering, PASS efter.

- [ ] **Step 2: Skærm `mobile/src/app/praesens.tsx`**

Følg de eksisterende skærmes idiom (se `mobile/src/app/bogmaerker.tsx` for TopBar/ScrollView-skelet og theme-brug — genbrug dets imports). Kernen i skærmen:

```tsx
// Præsensliste (spec 2026-07-22 §6) — redaktion-gated læsevisning, spejler webbens PresensView.
import { useEffect, useMemo, useState } from 'react';
import { ScrollView, Text, View, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { buildPresensListe, kanoniserPresensGrundlag } from '@daa/core';
import type { PresensGren, PresensNode } from '@daa/core';
import { useStore } from '../store/useStore';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
// + auth: hent aktuel profil-rolle via lib/auth (samme kald redaktions-fanen bruger — genbrug
//   dens hook/selector hvis en findes i store'ns redaktions-slice; ellers fetchProfile ved mount).

export default function PraesensScreen() {
  const model = useStore((s) => s.model);
  const router = useRouter();
  const [grundlag, setGrundlag] = useState<PresensGrundlag | null>(null);
  const [rolle, setRolle] = useState<string | null>(null);
  // mount: slå rolle op (lib/auth), og hvis 'redaktion': fetchPresensGrundlag().then(setGrundlag)
  const liste = useMemo(() => {
    if (!model || !grundlag) return null;
    const k = kanoniserPresensGrundlag(model, grundlag.ankre, grundlag.levendeById);
    return buildPresensListe(model, k.ankre, k.levendeById);
  }, [model, grundlag]);

  const Node = ({ n, dybde }: { n: PresensNode; dybde: number }) => (
    <View style={{ marginLeft: dybde * 16 }}>
      <Pressable onPress={() => router.push(`/person/${n.id}` as never)}>
        <Text style={{ fontStyle: n.forbindelsesled ? 'italic' : 'normal', opacity: n.forbindelsesled ? 0.55 : 1 }}>
          {model?.byId[n.id]?.name ?? n.id} {model?.byId[n.id]?.years ?? ''}{n.usikker ? ' ⚠' : ''}
        </Text>
      </Pressable>
      {n.boern.map((b) => <Node key={b.id} n={b} dybde={dybde + 1} />)}
    </View>
  );

  // render: rolle !== 'redaktion' → gate-tekst; ellers grene med versal-overskrifter
  // (Text med textTransform:'uppercase' og letterSpacing) — spejl webbens struktur.
  ...
}
```

Udfyld gate-/tom-/liste-tilstandene med samme tekster som web (Task 8 Step 3). Person-navigation: `router.push('/person/' + id)`.

- [ ] **Step 3: Drawer-punkt**

I `mobile/src/components/MenuDrawer.tsx` NAV-listen (linje 18-25), tilføj:

```ts
{ no: '09', title: 'Præsensliste', sub: 'Levende medlemmer efter linje og gren', href: '/praesens' },
```

- [ ] **Step 4: Kør mobil-suiten + tsc + røgtest på device hvis muligt**

```bash
cd mobile && npx jest && npx tsc --noEmit
```

Expected: PASS. (U+2028-læringen: mobil-tsc SKAL køres — den fanger hvad jest ikke gør.) On-device-røgtest (expo mod fysisk enhed) er ønskelig men kan udestå til brugerens næste device-session — rapportér eksplicit hvis sprunget.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/presens.ts mobile/src/data/__tests__/presens.test.ts mobile/src/app/praesens.tsx mobile/src/components/MenuDrawer.tsx
git commit -m "feat(presens): præsensliste-skærm og drawer-punkt i mobil-appen"
```

---

### Task 10: Dokumentation + draft-PR

**Files:**
- Modify: `docs/decisions.md` (beslutningsnotat)
- Modify: `docs/changelog.md` (dateret entry)
- Modify: `docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md` (status → "Implementeret (v1)")

**Interfaces:** ingen kode.

- [ ] **Step 1: `docs/decisions.md` — nyt afsnit (følg filens format)**

Indhold (omskriv til filens stil): (1) Præsensliste beregnes fra slægtsgrafen — bogens opstilling lagres ikke (mulighed A; C er fremtidig påbygning). (2) Overhoveder udpeges som fakta, faktatype `overhoved`, værdi-format `"<ROMERTAL> linje[, <N>. gren]"`, kontrakt i core `parseOverhovedVaerdi`. (3) Blod-vs-gift-ind-heuristikken (op-kobling + patrilineær tie-break) er en dokumenteret PoC-pragmatik. (4) V1 er redaktion-gated; medlems-eksponering venter på authenticated-tier + samtykke. (5) Kendt begrænsning: model kræver reload efter frisk redaktør-login før levende data indgår.

- [ ] **Step 2: `docs/changelog.md` — dateret entry (2026-07-XX, implementeringsdatoen)**

Kort: hvad er bygget (core-kerne + web/mobil-flader + overhoved-felt + vokabular-seed), teststatus (core/web/mobil-suiter grønne, facitliste-test mod DAA 2012-14), hvad der udestår (prod-apply af vokabular-seed er bruger-gated; overhoved-udpegning af din far som II linje/1. gren-anker sker redaktionelt i UI; device-røgtest hvis sprunget).

- [ ] **Step 3: Spec-status + commit + draft-PR**

```bash
git add docs/decisions.md docs/changelog.md docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md
git commit -m "docs(presens): beslutninger + changelog for præsensliste v1"
gh pr create --draft --title "feat(presens): beregnet præsensliste-visning (web+mobil)" --body "$(cat <<'EOF'
## Summary
- Beregnet, anker-baseret præsensliste (spec docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md)
- Core: beskæring + klatring + overskrift-generator + advarsler (fuld TDD, facitliste mod DAA 2012-14)
- Web: Mode 'praesens' i Følgesvenden (redaktion-gated) + person-genvej; Mobil: /praesens + drawer
- Overhoved-udpegning som fakta via eksisterende editor-flows; vokabular-seed (prod-apply udestår, bruger-gated)

## Test plan
- [x] packages/core: vitest (presensLabels/presensListe/presensFacit)
- [x] web: vitest + tsc
- [x] mobile: jest + tsc
- [ ] Manuel: udpeg overhoved i editor → gren vises korrekt (kræver prod-vokabular-seed)
- [ ] Device-røgtest mobil
EOF
)"
```

(PR oprettes kun hvis branchen må pushes — push kræver eksplicit aftale med brugeren; ellers stop efter commit og rapportér.)

---

## Self-review (udført ved planskrivning)

- **Spec-dækning:** §4 vokabular→Task 1+7; §5 algoritme→Task 2-4; §5-facit→Task 5; §6 UI web→Task 8, mobil→Task 9; §7 advarsler→Task 4+8; §8 GDPR→ingen kodeopgave (kommentarer + gate i Task 8-9); §9 test→Task 2-9; §10 fravalg respekteret (ingen redigering af listen, ingen proveniens, ingen medlems-tier); §11 filliste matcher.
- **Kendte bevidste afvigelser fra "komplet kode"-reglen:** Task 7 Step 1 og Task 9 Step 2 refererer eksisterende filers hjælpe-idiomer (redaktionWrite-testhjælper; mobil-skærm-skelet) i stedet for at gengive dem — de SKAL læses i målfilen ved implementering, fordi de to filer er app-specifikke og planen ellers ville fastfryse en gættet signatur. Alt andet er fuld kode.
- **Typekonsistens:** `PresensAnker`/`PresensNode`/`PresensGruppe`/`PresensGren`/`PresensListe`/`PresensAdvarsel`/`LevendeById` er defineret i Task 2-4 og forbruges med samme navne i Task 6-9; `mk`/`union`/`pc` eksporteres i Task 3 og importeres i Task 5.
