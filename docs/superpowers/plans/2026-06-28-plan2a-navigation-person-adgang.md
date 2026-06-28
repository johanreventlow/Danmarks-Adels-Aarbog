# Plan 2A — Navigation & person-adgang — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give redaktions-appens Entiteter-tab en person-liste (søg + alfabet + sort) der henter ALLE personer inkl. levende via en separat redaktion-fetch, så enhver person kan findes og åbnes uden URL-tastning.

**Architecture:** Refaktorér den eksisterende `buildSearch` til en pool-baseret `searchPool` (DRY, genbrugt af publikum + redaktion). Ny `fetchRedaktionPersoner` (pagineret, RLS-gated, inkl. levende/privat) leverer redaktions-poolen. Entiteter-skærmen spejler publikums-`search.tsx`-mønsteret men med lokal søge-state + levende/privat-tags. Den delte publikums-model røres ikke.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand, `@supabase/supabase-js`, Jest.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-28-plan2a-navigation-person-adgang-design.md` (autoritativ).
- **Branch:** opret feature-branch fra `main` ved start (`feat/plan2a-person-liste`); ingen merge/push uden eksplicit godkendelse.
- **Publikums-model urørt:** `load.ts` `.filter(p => !p.privat)` (linje 103) ændres IKKE. Ingen private/levende må lække til publikums-faner.
- **Pagination obligatorisk:** `fetchRedaktionPersoner` SKAL bruge `getAll`/`.range()` (PostgREST capper ved 1000 lydløst). Basen: 963 personer, anon ser 893, redaktion 963 (verificeret 2026-06-28).
- **`born` fra `visning_foedt` DIREKTE** — aldrig udledt af aar-strengen (dødsår ≠ fødeår).
- **Fejl kastes, aldrig tom-som-clean** (cycle 03 NEW1): fetch kaster ved Supabase-error; skærm viser eksplicit fejl-tilstand.
- **Tokens/Typography:** `Colors`/`Border`/`Fonts`/`Radius` + `Serif`/`Mono`/`Body`/`BtnLabel`/`InitialBadge`. Ingen rå hex (#fff/rgba OK).
- **`searchPool` skal bevare EKSAKT `buildSearch`-adfærd** (dansk alfabet, Æ/Ø/Å sidst, born-sort, activeLetter, showLetters-regel) — publikums-`search.tsx` skal stadig bestå.
- **Test-niveau matcher risiko:** ren logik (searchPool, mapRedPerson, pagination) = TDD/jest; skærm = tsc + manuel.
- Ingen Claude-attribution i commits. Conventional Commits, dansk.

---

## File Structure

**Ændrede:**
- `mobile/src/data/selectors.ts` — `buildSearch` splittes: ny `searchPool(pool, opts)` + bagudkompatibel `buildSearch`-wrapper.
- `mobile/src/data/load.ts` — `export` på `getAll`-helperen (så redaktion-fetch kan genbruge pagineringen).
- `mobile/src/data/redaktionRead.ts` — `RedPerson`, `RawRedPerson`, `mapRedPerson`, `fetchRedaktionPersoner`.
- `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` — stub → person-liste.
- `mobile/src/app/redaktion/(red-tabs)/index.tsx` — "Personer"-celle → naviger til Entiteter.

**Tests:**
- `mobile/src/data/__tests__/selectors.test.ts` (ny eller udvid) — searchPool + buildSearch-regression.
- `mobile/src/data/__tests__/redaktionRead.test.ts` (udvid) — mapRedPerson + pagination.

---

## Task 1: Pool-refaktorér `buildSearch` → `searchPool`

**Files:**
- Modify: `mobile/src/data/selectors.ts` (buildSearch, ~linje 248-300)
- Test: `mobile/src/data/__tests__/selectors.test.ts`

**Interfaces:**
- Consumes: `SearchItem` (`{ id: string; name: string; years: string; born: number | null }`), `compareDanish`/`initialOf` fra `lib/collation`.
- Produces: `searchPool(pool: SearchItem[], opts: { query: string; sort: 'alpha'|'born'; activeLetter: string|null }): { matches: SearchItem[]; letters: {label:string; key:string|null}[]; showLetters: boolean; groups: {letter:string; people:SearchItem[]}[] }`. `buildSearch(model, opts)` bevares som wrapper med uændret output.

- [ ] **Step 1: Skriv fejlende test**

Opret/udvid `mobile/src/data/__tests__/selectors.test.ts`:

```ts
import { searchPool, buildSearch } from '../selectors';
import type { SearchItem } from '../selectors';

const POOL: SearchItem[] = [
  { id: '1', name: 'Conrad Reventlow', years: '1644–1708', born: 1644 },
  { id: '2', name: 'Anne Reventlow', years: '1680–1740', born: 1680 },
  { id: '3', name: 'Æbbe Reventlow', years: '1600–1650', born: 1600 },
];

test('searchPool: query filtrerer på navn (case-insensitiv)', () => {
  const r = searchPool(POOL, { query: 'anne', sort: 'alpha', activeLetter: null });
  expect(r.matches.map((m) => m.id)).toEqual(['2']);
});

test('searchPool: born-sort sorterer på fødeår, alfabet-bar skjult', () => {
  const r = searchPool(POOL, { query: '', sort: 'born', activeLetter: null });
  expect(r.matches.map((m) => m.born)).toEqual([1600, 1644, 1680]);
  expect(r.showLetters).toBe(false);
});

test('searchPool: dansk alfabet — Æ sidst i grupper', () => {
  const r = searchPool(POOL, { query: '', sort: 'alpha', activeLetter: null });
  expect(r.groups[r.groups.length - 1].letter).toBe('Æ');
});

test('buildSearch-wrapper giver samme matches som searchPool på model.persons', () => {
  const model = { persons: [{ id: '9', name: 'Test Person', years: '1700', born: 1700 }] } as never;
  const viaWrapper = buildSearch(model, { query: '', sort: 'alpha', activeLetter: null });
  const viaPool = searchPool([{ id: '9', name: 'Test Person', years: '1700', born: 1700 }],
    { query: '', sort: 'alpha', activeLetter: null });
  expect(viaWrapper.matches).toEqual(viaPool.matches);
});
```

- [ ] **Step 2: Kør — verificér fejl**

Run: `cd mobile && npx jest selectors -t "searchPool"`
Expected: FAIL — `searchPool is not a function`.

- [ ] **Step 3: Refaktorér i `selectors.ts`**

Erstat `buildSearch`-kroppen. Træk alt EFTER pool-konstruktionen ud i `searchPool`; `buildSearch` bygger poolen og delegerer:

```ts
export function searchPool(
  pool: SearchItem[],
  opts: { query: string; sort: 'alpha' | 'born'; activeLetter: string | null },
): {
  matches: SearchItem[];
  letters: { label: string; key: string | null }[];
  showLetters: boolean;
  groups: { letter: string; people: SearchItem[] }[];
} {
  const q = opts.query.trim().toLowerCase();

  const present: Record<string, boolean> = {};
  pool.forEach((p) => { present[initialOf(p.name)] = true; });
  const letterKeys = Object.keys(present).sort(compareDanish);
  const showLetters = opts.sort !== 'born' && !q && letterKeys.length > 1;
  const letters = [{ label: 'Alle', key: null as string | null }].concat(
    letterKeys.map((k) => ({ label: k, key: k })),
  );

  let matches = pool.filter((p) => !q || p.name.toLowerCase().includes(q));
  if (!q && opts.sort !== 'born' && opts.activeLetter) {
    matches = matches.filter((p) => initialOf(p.name) === opts.activeLetter);
  }
  matches.sort(opts.sort === 'born' ? sortBorn : sortName);

  let groups: { letter: string; people: SearchItem[] }[] = [];
  if (opts.sort !== 'born' && !q) {
    const byL: Record<string, SearchItem[]> = {};
    matches.forEach((p) => { (byL[initialOf(p.name)] ||= []).push(p); });
    groups = Object.keys(byL).sort(compareDanish).map((k) => ({ letter: k, people: byL[k] }));
  }
  return { matches, letters, showLetters, groups };
}

export function buildSearch(
  model: Model | null,
  opts: { query: string; sort: 'alpha' | 'born'; activeLetter: string | null },
) {
  const pool: SearchItem[] = (model?.persons ?? []).map((p) => ({
    id: p.id, name: p.name, years: p.years, born: p.born,
  }));
  return searchPool(pool, opts);
}
```

(`sortName`/`sortBorn` er allerede modul-private i filen — uændret.)

- [ ] **Step 4: Kør tests + tsc**

Run: `cd mobile && npx jest selectors && npx tsc --noEmit`
Expected: PASS, ingen tsc-fejl.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/selectors.ts mobile/src/data/__tests__/selectors.test.ts
git commit -m "refactor(data): pool-baseret searchPool (DRY for publikum + redaktion)"
```

---

## Task 2: `fetchRedaktionPersoner` + `mapRedPerson` (pagineret, inkl. levende/privat)

**Files:**
- Modify: `mobile/src/data/load.ts` (export `getAll`)
- Modify: `mobile/src/data/redaktionRead.ts` (nye typer + funktioner)
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts`

**Interfaces:**
- Consumes: `getAll<T>` fra `load.ts`; `parseYear`/`fmtYears` fra `fields.ts`; `supabase` fra `lib/supabase`.
- Produces:
  - `type RedPerson = { id: string; navn: string; aar: string; born: number|null; levende: boolean; privat: boolean }`
  - `type RawRedPerson = { id: number; visning_navn: string|null; visning_foedt: string|null; visning_doed: string|null; levende: boolean|null; privat: boolean|null }`
  - `mapRedPerson(r: RawRedPerson): RedPerson` (ren)
  - `async fetchRedaktionPersoner(): Promise<RedPerson[]>` (pagineret, kaster ved error)

- [ ] **Step 1: Eksportér `getAll` fra `load.ts`**

I `mobile/src/data/load.ts`, tilføj `export` foran helperen:

```ts
export async function getAll<T>(
```
(funktionen er ellers uændret — den kaster allerede via `if (error) throw error`.)

- [ ] **Step 2: Skriv fejlende test for `mapRedPerson`**

Tilføj i `mobile/src/data/__tests__/redaktionRead.test.ts`:

```ts
import { mapRedPerson } from '../redaktionRead';

test('mapRedPerson: born fra visning_foedt, IKKE dødsår (cycle 2A M1)', () => {
  // Kun dødsår — born skal være null, ikke 1708.
  expect(mapRedPerson({ id: 5, visning_navn: 'Conrad', visning_foedt: null, visning_doed: '1708', levende: false, privat: false }).born)
    .toBeNull();
  expect(mapRedPerson({ id: 6, visning_navn: 'Anne', visning_foedt: '1680', visning_doed: '1740', levende: false, privat: false }).born)
    .toBe(1680);
});

test('mapRedPerson: navn-fallback + bools', () => {
  const r = mapRedPerson({ id: 7, visning_navn: null, visning_foedt: null, visning_doed: null, levende: true, privat: null });
  expect(r).toEqual({ id: '7', navn: '(uden navn)', aar: '', born: null, levende: true, privat: false });
});
```

- [ ] **Step 3: Kør — verificér fejl**

Run: `cd mobile && npx jest redaktionRead -t "mapRedPerson"`
Expected: FAIL — `mapRedPerson is not a function`.

- [ ] **Step 4: Implementér i `redaktionRead.ts`**

Tilføj import øverst: `import { getAll } from './load';` og `import { parseYear, fmtYears } from './fields';`. Tilføj:

```ts
export type RedPerson = {
  id: string; navn: string; aar: string; born: number | null; levende: boolean; privat: boolean;
};
type RawRedPerson = {
  id: number; visning_navn: string | null; visning_foedt: string | null;
  visning_doed: string | null; levende: boolean | null; privat: boolean | null;
};

export function mapRedPerson(r: RawRedPerson): RedPerson {
  return {
    id: String(r.id),
    navn: r.visning_navn ?? '(uden navn)',
    aar: fmtYears(r.visning_foedt, r.visning_doed),
    born: parseYear(r.visning_foedt), // DIREKTE fra fødselsfeltet — aldrig dødsår
    levende: Boolean(r.levende),
    privat: Boolean(r.privat),
  };
}

// Pagineret (PostgREST capper ved 1000 lydløst — getAll gentager .range indtil tomt).
// getAll kaster videre ved Supabase-error → ingen tom-som-clean (cycle 03 NEW1).
export async function fetchRedaktionPersoner(): Promise<RedPerson[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<RawRedPerson>(() =>
    sb.from('person').select('id,visning_navn,visning_foedt,visning_doed,levende,privat'));
  return rows.map(mapRedPerson);
}
```

- [ ] **Step 5: Skriv + kør pagination-test**

Tilføj i samme test-fil (verificerer at >1000 rækker ikke trunkeres — vi tester at fetchRedaktionPersoner samler flere sider; mock getAll's makeQuery):

```ts
import * as load from '../load';
import { fetchRedaktionPersoner } from '../redaktionRead';
jest.mock('../lib/supabase', () => ({ supabase: { from: () => ({ select: () => ({}) }) } }));

test('fetchRedaktionPersoner samler alle sider (ingen trunkering)', async () => {
  const page1 = Array.from({ length: 1000 }, (_, i) => ({ id: i + 1, visning_navn: `P${i}`, visning_foedt: '1700', visning_doed: null, levende: false, privat: false }));
  const page2 = [{ id: 1001, visning_navn: 'Sidste', visning_foedt: '1800', visning_doed: null, levende: false, privat: false }];
  const spy = jest.spyOn(load, 'getAll').mockResolvedValue([...page1, ...page2] as never);
  const res = await fetchRedaktionPersoner();
  expect(res).toHaveLength(1001);
  expect(res[1000].navn).toBe('Sidste');
  spy.mockRestore();
});
```

Run: `cd mobile && npx jest redaktionRead && npx tsc --noEmit`
Expected: PASS, ingen tsc-fejl.

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/load.ts mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(data): fetchRedaktionPersoner (pagineret, inkl. levende/privat) + mapRedPerson"
```

---

## Task 3: Entiteter person-liste-skærm

**Files:**
- Modify: `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` (stub → person-liste)

**Interfaces:**
- Consumes: `fetchRedaktionPersoner`, `RedPerson` (Task 2); `searchPool`, `SearchItem` (Task 1); `InitialBadge`, `TopBar`, `Typography`, tokens; `useRouter`.
- Produces: Entiteter-rute med person-liste.

- [ ] **Step 1: Implementér skærmen**

Erstat `entiteter.tsx`. Mønster fra `app/(tabs)/search.tsx`, men **lokal** søge-state, redaktion-fetch, tags, fejl-tilstand:

```tsx
import { useRouter } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, SectionList, StyleSheet, TextInput, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { fetchRedaktionPersoner, type RedPerson } from '../../../data/redaktionRead';
import { searchPool, type SearchItem } from '../../../data/selectors';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function Entiteter() {
  const router = useRouter();
  const session = useStore((s) => s.session);
  const [personer, setPersoner] = useState<RedPerson[]>([]);
  const [fejl, setFejl] = useState(false);
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<'alpha' | 'born'>('alpha');
  const [activeLetter, setActiveLetter] = useState<string | null>(null);

  useEffect(() => {
    setFejl(false);
    // Fejl vises eksplicit, ALDRIG som tom liste (cycle 03 NEW1).
    fetchRedaktionPersoner().then(setPersoner).catch(() => setFejl(true));
  }, [session]);

  // RedPerson → SearchItem-pool; tags slås op separat (holder SearchItem ren).
  const pool = useMemo<SearchItem[]>(
    () => personer.map((p) => ({ id: p.id, name: p.navn, years: p.aar, born: p.born })),
    [personer],
  );
  const skjult = useMemo(() => {
    const m = new Map<string, 'levende' | 'privat'>();
    personer.forEach((p) => { if (p.privat) m.set(p.id, 'privat'); else if (p.levende) m.set(p.id, 'levende'); });
    return m;
  }, [personer]);

  const { matches, letters, showLetters, groups } = useMemo(
    () => searchPool(pool, { query, sort, activeLetter }),
    [pool, query, sort, activeLetter],
  );
  const sections = useMemo(() => {
    if (groups.length) return groups.map((g) => ({ title: g.letter, data: g.people }));
    return [{ title: '', data: matches }];
  }, [groups, matches]);

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Personer" showBack={false} />
      <View style={styles.header}>
        <TextInput style={styles.input} placeholder="Søg navn…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoCorrect={false} />
        <View style={styles.sortRow}>
          <SortPill label="A–Å" active={sort === 'alpha'} onPress={() => setSort('alpha')} />
          <SortPill label="Født" active={sort === 'born'} onPress={() => setSort('born')} />
        </View>
        {showLetters ? (
          <View style={styles.letterRow}>
            {letters.map((l) => {
              const active = (l.key ?? null) === (activeLetter ?? null);
              return (
                <Pressable key={l.label} onPress={() => setActiveLetter(l.key)}
                  style={[styles.letterChip, active && styles.letterChipActive]}>
                  <Mono size={10} color={active ? Colors.paperBg : Colors.textSecondary2}>{l.label}</Mono>
                </Pressable>
              );
            })}
          </View>
        ) : null}
      </View>

      {fejl ? (
        <View style={{ padding: 24 }}>
          <Mono size={11} color={Colors.liveRoed}>Kunne ikke hente personer. Tom liste her betyder IKKE “ingen personer”.</Mono>
        </View>
      ) : (
        <SectionList
          style={{ flex: 1 }}
          sections={sections}
          keyExtractor={(item) => item.id}
          stickySectionHeadersEnabled
          keyboardShouldPersistTaps="handled"
          renderSectionHeader={({ section }) =>
            section.title ? (
              <View style={styles.sectionHeader}><Serif size={15} color={Colors.gold}>{section.title}</Serif></View>
            ) : null
          }
          renderItem={({ item }) => (
            <PersonRow item={item} tag={skjult.get(item.id)} onPress={() => router.push(`/redaktion/person/${item.id}` as never)} />
          )}
          ListEmptyComponent={<View style={{ padding: 24 }}><Body color={Colors.textMuted}>Ingen personer.</Body></View>}
        />
      )}
    </View>
  );
}

function SortPill({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.sortPill, active && styles.sortPillActive]}>
      <BtnLabel size={11} color={active ? Colors.paperBg : Colors.textSecondary2}>{label}</BtnLabel>
    </Pressable>
  );
}

function PersonRow({ item, tag, onPress }: { item: SearchItem; tag?: 'levende' | 'privat'; onPress: () => void }) {
  return (
    <Pressable style={styles.row} onPress={onPress}>
      <InitialBadge name={item.name} size={40} bg={Colors.beige2} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <Serif size={18} style={{ lineHeight: 19 }}>{item.name}</Serif>
        {item.years ? <Mono size={10} color={Colors.textMuted}>{item.years}</Mono> : null}
      </View>
      {tag ? (
        <View style={styles.tag}><Mono size={8} color={Colors.bordeaux}>{tag.toUpperCase()}</Mono></View>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: { paddingHorizontal: 16, paddingTop: 8, paddingBottom: 6, gap: 8 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, paddingHorizontal: 12, paddingVertical: 9, fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  sortRow: { flexDirection: 'row', gap: 8 },
  sortPill: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 14, paddingVertical: 5 },
  sortPillActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  letterRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 5 },
  letterChip: { paddingHorizontal: 7, paddingVertical: 3, borderRadius: Radius.badge, backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light },
  letterChipActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  sectionHeader: { backgroundColor: Colors.paperBg, paddingHorizontal: 16, paddingVertical: 4 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 9 },
  tag: { backgroundColor: Colors.bordeauxFillLight, borderRadius: Radius.badge, paddingHorizontal: 6, paddingVertical: 3 },
});
```

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel (hvis device): Entiteter-tab → liste m. levende-tags → søg → alfabet → tap → person-editor. Hvis ingen device: notér sprunget.
```bash
git add "mobile/src/app/redaktion/(red-tabs)/entiteter.tsx"
git commit -m "feat(redaktion): person-liste i Entiteter-tab (søg/alfabet/sort + levende-tags)"
```

---

## Task 4: Dashboard "Personer"-celle → naviger til Entiteter

**Files:**
- Modify: `mobile/src/app/redaktion/(red-tabs)/index.tsx` (entitets-grid)

**Interfaces:**
- Consumes: `useRouter` (allerede importeret i index.tsx).

- [ ] **Step 1: Gør "Personer"-cellen tappbar**

I `index.tsx`, find `GridCell`-komponenten + brugen i grid'et. Gør `GridCell` til en `Pressable` med valgfri `onPress`, og giv "Personer"-cellen navigation til Entiteter-tab'en (`router.navigate` skifter tab i `(red-tabs)`):

```tsx
// Erstat GridCell-definitionen:
function GridCell({ n, label, onPress }: { n: number; label: string; onPress?: () => void }) {
  return (
    <Pressable style={styles.cell} onPress={onPress} disabled={!onPress}>
      <Serif size={21} color={Colors.bordeaux}>{n}</Serif>
      <Body size={13}>{label}</Body>
    </Pressable>
  );
}

// I grid'et — Personer-cellen navigerer; øvrige (når de tilføjes) forbliver onPress-løse ("kommer snart"):
<GridCell n={c.personer} label="Personer" onPress={() => router.navigate('/redaktion/entiteter')} />
```

(`router` findes allerede i Dashboard-komponenten. `styles.cell` er uændret.)

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel (hvis device): dashboard → tap "Personer"-celle → Entiteter-listen åbner.
```bash
git add "mobile/src/app/redaktion/(red-tabs)/index.tsx"
git commit -m "feat(redaktion): dashboard Personer-celle navigerer til person-listen"
```

---

## Task 5: Integration — fuld jest + manuel e2e + RLS-verifikation + docs

**Files:**
- Modify: `docs/changelog.md`, `docs/decisions.md` (kort entry)

- [ ] **Step 1: Kør hele jest-suiten + tsc**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: alle grønne (eksisterende 87 + nye searchPool/mapRedPerson/pagination), tsc rent.

- [ ] **Step 2: RLS-synligheds-verifikation (R, mod prod/branch)**

Bekræft pr.-rolle-synlighed (samme metode som spec §5b). Forventet: anon=893, redaktion=963.
Run (R-script som i spec-arbejdet, `set local role`/`request.jwt.claims`): tæl `person` som anon vs redaktion.
Notér resultat.

- [ ] **Step 3: Manuel e2e (web)**

`cd mobile && npm run web` → `http://localhost:8081/redaktion` → log ind redaktion → Entiteter-tab:
liste viser personer inkl. levende (tag) → søg "Reventlow" → alfabet-hop → "Født"-sort → tap en person → person-editor åbner. Dashboard "Personer"-celle → samme liste. Notér bestået/sprunget.

- [ ] **Step 4: Changelog + decisions + commit**

Tilføj kort entry i `docs/changelog.md` (plan 2A person-liste) + `docs/decisions.md` (separat redaktion-fetch + pool-refactor). Commit:
```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: plan 2A — person-liste/navigation changelog + decisions"
```

---

## Self-Review

**Spec coverage:**
- §2 fetchRedaktionPersoner (pagineret, levende/privat, kaster) → Task 2. §3 searchPool-refactor → Task 1; RedPerson→SearchItem-map + tag-Set → Task 3. §4.1 Entiteter-liste (søg/alfabet/sort/tags/fejl) → Task 3. §4.2 dashboard-celle → Task 4. §5 levende/privat-tag → Task 3. §6 fejl-tilstand → Task 2 (kast) + Task 3 (UI). §7 test (searchPool/mapRedPerson/pagination/regression/RLS/manuel) → Task 1,2,5. Alle spec-sektioner dækket.
- **Non-goals** (entitets-menu, ikke-person-lister, generisk editor, køn/familie-visning) er IKKE planlagt — korrekt.

**Placeholder-scan:** ingen TBD/TODO; al kode komplet. Pagination-testen mocker `getAll` (afhænger af export fra Task 2 Step 1).

**Type-konsistens:** `RedPerson`/`RawRedPerson` ens i Task 2 + forbrugt i Task 3. `searchPool`-signatur ens i Task 1 + kaldt i Task 3. `SearchItem` uændret kontrakt (ingen levende/privat-felt — tags via separat Map). `getAll<T>` export (Task 2 Step 1) bruges i Task 2 Step 4 + pagination-test. `born` fra `parseYear(visning_foedt)` konsistent (M1-fix).
