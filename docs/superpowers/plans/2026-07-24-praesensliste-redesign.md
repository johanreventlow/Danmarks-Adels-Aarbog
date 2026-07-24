# Præsensliste — visuel redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the read-only `PresensView` web page (Følgesvend "Præsens" tab) to match
the approved Claude Design mockup (`Reventlow-praesens.dc.html`) — titelblad, sticky
left index, intro text, per-linje sections with coat of arms, per-gren sections — while
reusing the already-implemented, already-tested `@daa/core` anchor/pruning algorithm
unchanged.

**Architecture:** Two new pure functions (`groupByLinje` in `@daa/core`, `mapPresensLinjer`/
`pickPresensIntro` in a new web data file) feed a two-level component split
(`PresensLinjeSektion` wraps the existing `PresensGrenSektion`). No changes to
`presensListe.ts`'s pruning/labelling logic, no changes to RLS (the touched tables —
`lineage`, `coat_of_arms`, `relation`, `narrative` — are already public-readable
reference tables per `db-rls.sql`).

**Tech Stack:** TypeScript, React 18, Vitest + @testing-library/react, Supabase-js,
npm workspaces (`packages/core`, `web`).

## Global Constraints

- No new column on `lineage` — `lineage.navn` already holds the descriptive line title
  (verified via `docs/changelog.md:1750-51` and
  `docs/superpowers/specs/2026-07-03-udledt-slaegtsnavn-design.md:38`); `lineage.slaegtsnavn`
  already holds the spelling-variant surname.
- The "antal levende/forbindelsesled pr. gren" summary is explicitly **out of scope**
  (dropped after user feedback — reads as morbid).
- Mobile (`mobile/src/app/praesens.tsx`) is **out of scope** for this plan.
- Redaktør-only access gate stays exactly as-is (`session?.role !== 'redaktion'` check in
  `PresensView.tsx`) — do not touch it.
- `pickPreferredBio` (`packages/core/src/pickPreferredBio.ts`) is NOT reused for the
  présens-intro text — it gates on `BIO_SLAGS = new Set(['DAA-udgave'])` and would silently
  reject a `slags='præsens-intro'` narrative. Use a separate, simpler selector (Task 2).
- Every new Supabase query follows the existing `getAll<T>` pagination helper from
  `@daa/core` (matches `web/src/data/presens.ts`'s own convention) — do not hand-roll
  `.select()` + manual `{data,error}` destructuring.
- Relation direction for media→coat_of_arms is `subjekt_type='media', objekt_type='coat_of_arms',
  rolle='afbildet'` — this already exists and is used by `fetchObjectMedia()`
  (`web/src/data/media.ts`). Do not invent a different direction/role for that hop.

---

## File Structure

- **Modify** `packages/core/src/presensListe.ts` — add `groupByLinje`.
- **Modify** `packages/core/src/index.ts` — no change needed (already `export * from
  './presensListe'`, so `groupByLinje` is exported automatically).
- **Modify** `packages/core/src/__tests__/presensListe.test.ts` — add `groupByLinje` tests.
- **Create** `web/src/data/presensLinjer.ts` — linje metadata (titel/navn/våben) +
  présens-intro fetch, pure mapper functions + thin Supabase-calling wrappers.
- **Create** `web/src/data/__tests__/presensLinjer.test.ts` — tests for the pure mappers.
- **Modify** `web/src/components/PresensView.tsx` — introduce `PresensLinjeSektion`,
  simplify `PresensGrenSektion`'s heading, redesign the top-level `PresensView` layout.
- **Modify** `web/src/components/__tests__/PresensView.test.tsx` — update the existing
  heading assertion, add `PresensLinjeSektion` tests.
- **Modify** `db-migrations.sql` — one idempotent `vocab` row (`rolle`/`vaaben`).
- **Create** `docs/superpowers/plans/2026-07-24-praesensliste-vaaben-data-runbook.md` —
  manual runbook for populating the *actual* coat-of-arms images/blasonering and the
  présens-intro text (real editorial content — not something to fabricate in this plan).

---

### Task 1: `groupByLinje` — group flat gren-list by linje

**Files:**
- Modify: `packages/core/src/presensListe.ts`
- Test: `packages/core/src/__tests__/presensListe.test.ts`

**Interfaces:**
- Consumes: existing `PresensGren` type (already in `presensListe.ts`: `{ anker:
  PresensAnker; ankerBlok: PresensNode; grupper: PresensGruppe[] }`), existing
  `PresensAnker` type (`{ personId: string; linje: string; gren: number | null;
  raaVaerdi: string }`).
- Produces: `export type PresensLinjeGruppe = { linje: string; grene: PresensGren[] }`
  and `export function groupByLinje(grene: PresensGren[]): PresensLinjeGruppe[]` — used
  by Task 5 (`PresensView.tsx`).

- [ ] **Step 1: Write the failing test**

Append to `packages/core/src/__tests__/presensListe.test.ts` (new `describe` block at
the end of the file):

```ts
import { groupByLinje } from '../presensListe';
import type { PresensGren } from '../presensListe';

describe('groupByLinje', () => {
  const anker = (linje: string, gren: number | null, personId: string): PresensAnker =>
    ({ personId, linje, gren, raaVaerdi: gren != null ? `${linje} linje, ${gren}. gren` : `${linje} linje` });
  const gren = (a: PresensAnker): PresensGren => ({
    anker: a,
    ankerBlok: { id: a.personId, levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false, krydsReference: false },
    grupper: [],
  });

  test('grupperer flad gren-liste under linje, bevarer indbyrdes rækkefølge', () => {
    const grene = [gren(anker('II', 1, 'A')), gren(anker('II', 2, 'B')), gren(anker('IV', 1, 'C'))];
    const grupperet = groupByLinje(grene);
    expect(grupperet.map((g) => g.linje)).toEqual(['II', 'IV']);
    expect(grupperet[0].grene.map((g) => g.anker.personId)).toEqual(['A', 'B']);
    expect(grupperet[1].grene.map((g) => g.anker.personId)).toEqual(['C']);
  });

  test('tom liste giver tom gruppering', () => {
    expect(groupByLinje([])).toEqual([]);
  });

  test('linje-overhoved uden gren-nummer (gren=null) grupperes for sig selv', () => {
    const grupperet = groupByLinje([gren(anker('I', null, 'Z'))]);
    expect(grupperet).toEqual([{ linje: 'I', grene: [gren(anker('I', null, 'Z'))] }]);
  });
});
```

Add the two new import lines shown above near the top of the test file (after the
existing `import { buildPresensListe, kanoniserPresensGrundlag } from '../presensListe';`
line). The file already has `import type { PresensAnker } from '../presensLabels';` at
line 5 — the new `describe` block's `anker` helper uses that existing import, don't
add a second one.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/core && npx vitest run src/__tests__/presensListe.test.ts`
Expected: FAIL — `groupByLinje is not exported from '../presensListe'` (or similar
resolution error), since the function doesn't exist yet.

- [ ] **Step 3: Implement `groupByLinje`**

Append to `packages/core/src/presensListe.ts` (at the end of the file, after
`kanoniserPresensGrundlag`):

```ts
export type PresensLinjeGruppe = { linje: string; grene: PresensGren[] };

// Ren, rækkefølge-bevarende gruppering af den flade gren-liste under linje (visningslag —
// liste.grene er allerede sorteret via sortAnkre, så grupperingen arver den rækkefølge).
export function groupByLinje(grene: PresensGren[]): PresensLinjeGruppe[] {
  const out: PresensLinjeGruppe[] = [];
  const byLinje = new Map<string, PresensGren[]>();
  for (const g of grene) {
    const arr = byLinje.get(g.anker.linje);
    if (arr) arr.push(g); else byLinje.set(g.anker.linje, [g]);
  }
  for (const g of grene) {
    if (!out.some((o) => o.linje === g.anker.linje)) out.push({ linje: g.anker.linje, grene: byLinje.get(g.anker.linje)! });
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/core && npx vitest run src/__tests__/presensListe.test.ts`
Expected: PASS — all tests in the file green (including the 3 new ones).

- [ ] **Step 5: Typecheck + commit**

Run: `cd packages/core && npx tsc --noEmit`
Expected: no errors.

```bash
git add packages/core/src/presensListe.ts packages/core/src/__tests__/presensListe.test.ts
git commit -m "feat(presens): groupByLinje — grupér flad gren-liste under linje til visning"
```

---

### Task 2: Web data layer — linje-metadata + præsens-intro

**Files:**
- Create: `web/src/data/presensLinjer.ts`
- Create: `web/src/data/__tests__/presensLinjer.test.ts`

**Interfaces:**
- Consumes: `supabase` client (`web/src/supabase.ts`, default conventions — same import
  as `web/src/data/presens.ts:4`), `getAll` from `@daa/core`, `fetchObjectMedia` +
  `firstSignable` + `MediaItem` type from `web/src/data/media.ts` (already existing,
  used unchanged by `ArmsView`/`fetchArms`).
- Produces: `export type PresensLinjeInfo = { titel: string; slaegtsnavn: string | null;
  vaaben: MediaItem | null }`, `export function fetchPresensLinjer():
  Promise<Record<string, PresensLinjeInfo>>` (keyed by `lineage.kode`, e.g. `'II'`),
  `export function fetchPresensIntro(): Promise<string | null>` — both consumed by
  Task 5 (`PresensView.tsx`). Also exports the pure `mapPresensLinjer` and
  `pickPresensIntro` for testing.

- [ ] **Step 1: Write the failing tests**

Create `web/src/data/__tests__/presensLinjer.test.ts`:

```ts
import { mapPresensLinjer, pickPresensIntro } from '../presensLinjer';

test('mapPresensLinjer: kobler lineage-rækker til deres våben-media via relation', () => {
  const lineageRows = [
    { id: 1, kode: 'I', navn: 'Den holstenske linje', slaegtsnavn: 'Reventlow' },
    { id: 2, kode: 'II', navn: 'Linjen Gallentin', slaegtsnavn: null },
  ];
  const vaabenRel = [{ subjekt_id: 1, objekt_id: 100 }];
  const media = { id: 'm1', slags: 'foto', titel: '', kunstner: '', datering: '', url: 'https://x/1.png', thumbUrl: null };
  const mediaByArm = new Map([['100', [media]]]);
  const result = mapPresensLinjer(lineageRows, vaabenRel, mediaByArm);
  expect(result['I']).toEqual({ titel: 'Den holstenske linje', slaegtsnavn: 'Reventlow', vaaben: media });
  expect(result['II']).toEqual({ titel: 'Linjen Gallentin', slaegtsnavn: null, vaaben: null });
});

test('mapPresensLinjer: linje uden vaaben-relation får vaaben=null', () => {
  const lineageRows = [{ id: 5, kode: 'V', navn: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow' }];
  const result = mapPresensLinjer(lineageRows, [], new Map());
  expect(result['V'].vaaben).toBeNull();
});

test('pickPresensIntro: filtrerer til source.slags=præsens-intro, vælger seneste id', () => {
  const rows = [
    { id: 1, tekst: 'gammel intro', source: { slags: 'præsens-intro' } },
    { id: 2, tekst: 'ny intro', source: { slags: 'præsens-intro' } },
    { id: 3, tekst: 'anden kilde', source: { slags: 'DAA-udgave' } },
  ];
  expect(pickPresensIntro(rows)).toBe('ny intro');
});

test('pickPresensIntro: ingen matchende kilde giver null', () => {
  expect(pickPresensIntro([{ id: 1, tekst: 'x', source: { slags: 'DAA-udgave' } }])).toBeNull();
  expect(pickPresensIntro([])).toBeNull();
});

test('pickPresensIntro: tom tekst tælles ikke som kandidat', () => {
  expect(pickPresensIntro([{ id: 1, tekst: '  ', source: { slags: 'præsens-intro' } }])).toBeNull();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web && npx vitest run src/data/__tests__/presensLinjer.test.ts`
Expected: FAIL — cannot resolve `../presensLinjer` (file doesn't exist yet).

- [ ] **Step 3: Implement `web/src/data/presensLinjer.ts`**

```ts
// Linje-metadata (titel/navn/våben) + dedikeret præsens-intro til Præsenslisten-visningen.
// Sideordnet presens.ts (som holder levende-flag + overhoved-ankre) — eget ansvar, egen fil.
import { supabase } from '../supabase';
import { getAll } from '@daa/core';
import { fetchObjectMedia, firstSignable, type MediaItem } from './media';

export type PresensLinjeInfo = { titel: string; slaegtsnavn: string | null; vaaben: MediaItem | null };

type RawLineage = { id: number; kode: string; navn: string; slaegtsnavn: string | null };
type RawRelation = { subjekt_id: number; objekt_id: number };

// Ren mapper — testes uden Supabase. mediaByArm er keyet på coat_of_arms.id som streng
// (samme konvention som fetchObjectMedia's returtype).
export function mapPresensLinjer(
  lineageRows: RawLineage[],
  vaabenRel: RawRelation[],
  mediaByArm: Map<string, MediaItem[]>,
): Record<string, PresensLinjeInfo> {
  const armIdByLineageId = new Map(vaabenRel.map((r) => [r.subjekt_id, r.objekt_id]));
  const out: Record<string, PresensLinjeInfo> = {};
  for (const l of lineageRows) {
    const armId = armIdByLineageId.get(l.id);
    const media = armId != null ? mediaByArm.get(String(armId)) ?? [] : [];
    out[l.kode] = { titel: l.navn, slaegtsnavn: l.slaegtsnavn, vaaben: firstSignable(media) };
  }
  return out;
}

export async function fetchPresensLinjer(): Promise<Record<string, PresensLinjeInfo>> {
  const lineageRows = await getAll<RawLineage>(() =>
    supabase.from('lineage').select('id,kode,navn,slaegtsnavn'));
  const lineageIds = lineageRows.map((l) => l.id);
  const vaabenRel = lineageIds.length
    ? await getAll<RawRelation>(() =>
        supabase.from('relation').select('subjekt_id,objekt_id')
          .eq('subjekt_type', 'lineage').eq('objekt_type', 'coat_of_arms').eq('rolle', 'vaaben')
          .in('subjekt_id', lineageIds))
    : [];
  const armIds = vaabenRel.map((r) => r.objekt_id);
  const mediaByArm = await fetchObjectMedia('coat_of_arms', armIds);
  return mapPresensLinjer(lineageRows, vaabenRel, mediaByArm);
}

type RawIntroNarr = { id: number; tekst: string | null; source: { slags: string | null } | null };

// IKKE pickPreferredBio (packages/core) — den gater på BIO_SLAGS=Set(['DAA-udgave']) og ville
// stille afvise en 'præsens-intro'-kilde. Kun én kilde forventes i praksis; seneste id vinder
// defensivt hvis der alligevel skulle opstå flere.
export function pickPresensIntro(rows: RawIntroNarr[]): string | null {
  const cands = rows.filter((r) => r.source?.slags === 'præsens-intro' && (r.tekst ?? '').trim() !== '');
  if (!cands.length) return null;
  return [...cands].sort((a, b) => b.id - a.id)[0].tekst;
}

export async function fetchPresensIntro(): Promise<string | null> {
  const rows = await getAll<RawIntroNarr>(() =>
    supabase.from('narrative').select('id,tekst,source:source_id(slags)')
      .eq('subjekt_type', 'slaegt').eq('subjekt_id', 1).eq('privat', false));
  return pickPresensIntro(rows);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web && npx vitest run src/data/__tests__/presensLinjer.test.ts`
Expected: PASS — 5 tests green. (If web tests fail with "Mangler VITE_SUPABASE_URL /
VITE_SUPABASE_ANON_KEY", create `web/.env.local` first — see prerequisite note at the
end of this plan.)

- [ ] **Step 5: Typecheck + commit**

Run: `cd web && npx tsc --noEmit`
Expected: no errors.

```bash
git add web/src/data/presensLinjer.ts web/src/data/__tests__/presensLinjer.test.ts
git commit -m "feat(presens): linje-metadata + dedikeret præsens-intro data-lag"
```

---

### Task 3: Database — vocab-kode for lineage→coat_of_arms-relationen

**Files:**
- Modify: `db-migrations.sql`

**Interfaces:**
- Produces: `vocab` row `(scheme='rolle', code='vaaben')`, consumed by Task 2's
  `fetchPresensLinjer` query (`.eq('rolle', 'vaaben')`) and by the follow-up data
  runbook (Task 6) when real relation rows are inserted.

- [ ] **Step 1: Append the migration**

Append to the end of `db-migrations.sql`:

```sql
-- Præsensliste-redesign 2026-07-24: ny rolle-kode til lineage→coat_of_arms-relationen
-- (linjens våben). Selve relations-/media-/coat_of_arms-rækkerne for de faktiske våben
-- indsættes separat via docs/superpowers/plans/2026-07-24-praesensliste-vaaben-data-runbook.md
-- (redaktionelt indhold — blasonering/billeder — ikke noget en migration skal fabrikere).
INSERT INTO vocab (scheme, code, label) VALUES ('rolle','vaaben','våbenskjold for') ON CONFLICT (scheme, code) DO NOTHING;
```

- [ ] **Step 2: Verify idempotency locally**

This step has no automated test (it's a one-line, idempotent SQL insert — the project's
own convention for vocab additions, matching the existing `'rolle','ikke_samme_som'`
row earlier in the same file). Confirm by reading the diff that the statement matches
the established `ON CONFLICT (scheme, code) DO NOTHING` pattern exactly.

- [ ] **Step 3: Commit**

```bash
git add db-migrations.sql
git commit -m "feat(presens): vocab-kode rolle='vaaben' til linje-våben-relationen"
```

*(Running this migration against prod is a separate, explicit deploy step — not part of
this plan's automated tasks. It only needs to run once, before the runbook in Task 6.)*

---

### Task 4: `PresensLinjeSektion` — two-level linje/gren rendering

**Files:**
- Modify: `web/src/components/PresensView.tsx`
- Modify: `web/src/components/__tests__/PresensView.test.tsx`

**Interfaces:**
- Consumes: `PresensGren` type, `PresensLinjeGruppe` type (from Task 1), the existing
  `PresensGrenSektion` component (same file), `PresensLinjeInfo` type (from Task 2).
- Produces: modified `PresensGrenSektion` (heading now `${gren}. gren` or nothing, not
  `anker.raaVaerdi`), new exported `PresensLinjeSektion` component — consumed by
  Task 5's top-level `PresensView`.

- [ ] **Step 1: Update the existing test to the new gren-only heading**

In `web/src/components/__tests__/PresensView.test.tsx`, change:

```ts
  expect(screen.getByText('II linje, 1. gren')).toBeTruthy();
```

to:

```ts
  expect(screen.getByText('1. gren')).toBeTruthy();
```

(This is the only change in that test file for this step — everything else in the
existing two tests stays as-is, since `gren.anker.gren` in the fixture is already `1`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd web && npx vitest run src/components/__tests__/PresensView.test.tsx`
Expected: FAIL — `getByText('1. gren')` finds nothing yet (component still renders
`anker.raaVaerdi`, i.e. `'II linje, 1. gren'`).

- [ ] **Step 3: Update `PresensGrenSektion` heading + add `PresensLinjeSektion`**

In `web/src/components/PresensView.tsx`, replace the `<h2>` heading block inside
`PresensGrenSektion` (currently `{gren.anker.raaVaerdi}`) with a conditional gren-number
heading, and add a new exported `PresensLinjeSektion` wrapper. Replace:

```tsx
  return (
    <section style={{ marginBottom: 34 }}>
      <h2 style={{ fontFamily: T.sans, fontSize: 13, letterSpacing: 1.5, textTransform: 'uppercase', color: T.bordeaux }}>
        {gren.anker.raaVaerdi}
      </h2>
      {renderNode(gren.ankerBlok, 0)}
```

with:

```tsx
  return (
    <section id={gren.anker.gren != null ? `${gren.anker.linje.toLowerCase()}-g${gren.anker.gren}` : undefined} style={{ marginBottom: 34 }}>
      {gren.anker.gren != null && (
        <h2 style={{ fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.22em', textTransform: 'uppercase', color: T.gold, fontWeight: 500 }}>
          {gren.anker.gren}. gren
        </h2>
      )}
      {renderNode(gren.ankerBlok, 0)}
```

Then add, directly below the closing `}` of the `PresensGrenSektion` function (still
inside the same file, before the `export default function PresensView` line):

```tsx
import type { PresensLinjeGruppe } from '@daa/core';
import type { PresensLinjeInfo } from '../data/presensLinjer';

// Pr.-linje sektion: våben + linjenummer + titel (lineage.navn) + navn (lineage.slaegtsnavn),
// derefter dens grene i rækkefølge (eksporteret til test, samme mønster som PresensGrenSektion).
export function PresensLinjeSektion(props: {
  gruppe: PresensLinjeGruppe;
  info: PresensLinjeInfo | undefined;
  navnAf: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  fokusId?: string | null;
}) {
  const { gruppe, info, navnAf, aarAf, onPick, fokusId } = props;
  return (
    <div id={`linje-${gruppe.linje.toLowerCase()}`} style={{ marginTop: 52 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 24, borderTop: `1px solid rgba(34,31,26,.14)`, paddingTop: 26 }}>
        {info?.vaaben?.url && (
          <img src={info.vaaben.url} alt="Linjens våben" style={{ width: 92, height: 'auto', display: 'block', flex: 'none' }} />
        )}
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, color: T.bordeaux, lineHeight: 1 }}>{gruppe.linje}</span>
            <span style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.26em', textTransform: 'uppercase', color: T.ink }}>linje</span>
          </div>
          {info?.titel && (
            <div style={{ fontFamily: T.serif, fontSize: 19, fontStyle: 'italic', color: '#3d382f', marginTop: 8 }}>{info.titel}</div>
          )}
          {info?.slaegtsnavn && (
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.3em', textTransform: 'uppercase', color: T.muted2, marginTop: 6 }}>{info.slaegtsnavn}</div>
          )}
        </div>
      </div>
      {gruppe.grene.map((g) => (
        <PresensGrenSektion key={g.anker.personId} gren={g} navnAf={navnAf} aarAf={aarAf} onPick={onPick} fokusId={fokusId} />
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd web && npx vitest run src/components/__tests__/PresensView.test.tsx`
Expected: PASS — both existing tests green with the updated heading assertion.

- [ ] **Step 5: Write a test for `PresensLinjeSektion`**

First, change the existing top import line
`import { PresensGrenSektion } from '../PresensView';` to
`import { PresensGrenSektion, PresensLinjeSektion } from '../PresensView';`, and add two
new type-only imports right after the existing `import type { PresensGren } from
'@daa/core';` line: `import type { PresensLinjeGruppe } from '@daa/core';` and
`import type { PresensLinjeInfo } from '../../data/presensLinjer';`.

Then append the two new tests to the end of the file:

```ts
test('linje-sektion viser linjenummer, titel, navn og dens grene', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'II', grene: [gren] };
  const info: PresensLinjeInfo = { titel: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', vaaben: null };
  render(<PresensLinjeSektion gruppe={gruppe} info={info} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('II')).toBeTruthy();
  expect(screen.getByText('Den grevelige linje af 1673')).toBeTruthy();
  expect(screen.getByText('Reventlow')).toBeTruthy();
  expect(screen.getByText('1. gren')).toBeTruthy(); // fra den indlejrede gren-sektion
});

test('linje-sektion uden info (data endnu ikke tilknyttet) viser stadig grenene', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'IV', grene: [gren] };
  render(<PresensLinjeSektion gruppe={gruppe} info={undefined} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('IV')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
});
```

(This reuses the existing `gren`, `navnAf`, `aarAf` fixtures already declared at the top
of the test file — no new fixtures needed.)

- [ ] **Step 6: Run test to verify it passes**

Run: `cd web && npx vitest run src/components/__tests__/PresensView.test.tsx`
Expected: PASS — 4 tests total, all green.

- [ ] **Step 7: Typecheck + commit**

Run: `cd web && npx tsc --noEmit`
Expected: no errors.

```bash
git add web/src/components/PresensView.tsx web/src/components/__tests__/PresensView.test.tsx
git commit -m "feat(presens): PresensLinjeSektion — linje-niveau (våben/titel/navn) over grenene"
```

---

### Task 5: Redesign top-level `PresensView` layout

**Files:**
- Modify: `web/src/components/PresensView.tsx`

**Interfaces:**
- Consumes: `groupByLinje` (Task 1), `fetchPresensLinjer`/`fetchPresensIntro` (Task 2),
  `PresensLinjeSektion` (Task 4).
- Produces: the full redesigned page — no further consumers within this plan.

- [ ] **Step 1: Extend imports and add the two new fetches**

In `web/src/components/PresensView.tsx`, extend the existing imports:

```tsx
import { buildPresensListe, kanoniserPresensGrundlag, groupByLinje } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode, PresensLinjeGruppe } from '@daa/core';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
import { fetchPresensLinjer, fetchPresensIntro, type PresensLinjeInfo } from '../data/presensLinjer';
```

Inside `export default function PresensView`, add two new state slots and fetch them
alongside the existing `grundlag` fetch:

```tsx
  const [linjeInfo, setLinjeInfo] = useState<Record<string, PresensLinjeInfo>>({});
  const [intro, setIntro] = useState<string | null>(null);
```

Extend the existing effect that fetches `grundlag` (the one gated on
`session?.role === 'redaktion'`) to also kick off the two new fetches in parallel —
replace:

```tsx
  useEffect(() => {
    if (session === 'henter' || session?.role !== 'redaktion') return;
    fetchPresensGrundlag().then(setGrundlag).catch((e) => setFejl(String(e?.message ?? e)));
  }, [session]);
```

with:

```tsx
  useEffect(() => {
    if (session === 'henter' || session?.role !== 'redaktion') return;
    fetchPresensGrundlag().then(setGrundlag).catch((e) => setFejl(String(e?.message ?? e)));
    fetchPresensLinjer().then(setLinjeInfo).catch(() => setLinjeInfo({})); // ikke-kritisk pynt
    fetchPresensIntro().then(setIntro).catch(() => setIntro(null)); // ikke-kritisk pynt
  }, [session]);
```

(Linje-metadata og intro-tekst er ikke-kritiske for selve præsenslistens korrekthed —
en fejl her skal ALDRIG blokere visningen af selve grenene, derfor egne, tavse
`.catch()`-fald frem for at sætte `fejl`.)

- [ ] **Step 2: Compute the grouped list**

Add, right after the existing `liste` `useMemo`:

```tsx
  const linjer = useMemo(() => (liste ? groupByLinje(liste.grene) : []), [liste]);
```

- [ ] **Step 3: Replace the render body**

Replace everything from `const navnAf = ...` to the end of the function (the final
`return (...)` block) with:

```tsx
  const navnAf = (id: string) => model!.byId[id]?.name ?? `person ${id}`;
  const aarAf = (id: string) => model!.byId[id]?.years ?? '';
  return (
    <div style={{ maxWidth: 1240, margin: '0 auto', padding: '40px 28px 90px', display: 'grid', gridTemplateColumns: '200px minmax(0,860px)', gap: 36, justifyContent: 'center', alignItems: 'start' }}>
      {/* Venstre sticky-indeks */}
      <nav style={{ position: 'sticky', top: 28, paddingTop: 10 }}>
        <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.2em', textTransform: 'uppercase', color: T.muted2, marginBottom: 14 }}>Indhold</div>
        {linjer.map((lin) => (
          <div key={lin.linje} style={{ marginBottom: 18 }}>
            <a href={`#linje-${lin.linje.toLowerCase()}`} style={{ display: 'flex', alignItems: 'baseline', gap: 8, color: T.ink }}>
              <span style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: T.bordeaux }}>{lin.linje}</span>
              <span style={{ fontSize: 12.5, fontWeight: 600 }}>linje</span>
            </a>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 5, margin: '8px 0 0 4px', borderLeft: '1px solid rgba(34,31,26,.12)', paddingLeft: 14 }}>
              {lin.grene.filter((g) => g.anker.gren != null).map((g) => (
                <a key={g.anker.personId} href={`#${lin.linje.toLowerCase()}-g${g.anker.gren}`} style={{ fontSize: 12.5, color: T.muted }}>
                  {g.anker.gren}. gren
                </a>
              ))}
            </div>
          </div>
        ))}
        <div style={{ borderTop: '1px solid rgba(34,31,26,.12)', marginTop: 6, paddingTop: 14 }}>
          <div style={{ fontFamily: T.mono, fontSize: 9.5, letterSpacing: '.2em', textTransform: 'uppercase', color: T.muted2, marginBottom: 10 }}>Signatur</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7, fontSize: 11.5, color: T.muted, lineHeight: 1.45 }}>
            <div><span style={{ fontWeight: 600, color: T.ink }}>Navn</span> — levende person</div>
            <div><span style={{ fontStyle: 'italic', color: T.muted2 }}>Navn</span> — afdød forbindelsesled</div>
            <div><span style={{ color: T.gold }}>⚠</span> usikkert slægtskabsled</div>
            <div><span style={{ color: T.muted2 }}>↗</span> vist andetsteds i grenen</div>
          </div>
        </div>
      </nav>

      {/* Arket */}
      <div style={{ minWidth: 0 }}>
        <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.12em', color: T.muted2, margin: '0 0 14px 4px' }}>Reventlow / Præsensliste</div>
        <div style={{ background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 4, boxShadow: '0 2px 14px rgba(34,31,26,.07)', padding: '56px 72px 64px' }}>
          <div style={{ textAlign: 'center' }}>
            <h1 style={{ fontFamily: T.serif, fontSize: 40, fontWeight: 500, lineHeight: 1.08, margin: 0 }}>Præsensliste</h1>
            <div style={{ fontSize: 13.5, color: T.muted, marginTop: 10 }}>Slægtens nulevende medlemmer, ordnet efter linje og gren</div>
            <div style={{ width: 44, height: 1.5, background: T.gold, margin: '26px auto 0' }} />
          </div>

          {intro && (
            <div style={{ maxWidth: 640, margin: '34px auto 0' }}>
              {intro.split('\n\n').map((afsnit, i) => (
                <p key={i} style={{ fontFamily: T.serif, fontSize: 17.5, fontStyle: 'italic', lineHeight: 1.65, color: '#3d382f', margin: i === 0 ? 0 : '16px 0 0' }}>{afsnit}</p>
              ))}
            </div>
          )}

          {liste.advarsler.length > 0 && (
            <details style={{ margin: '28px auto 0', maxWidth: 640, background: T.panel, border: '1px solid rgba(185,160,106,.4)', borderRadius: 4, padding: '12px 18px' }}>
              <summary style={{ fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.1em', color: T.muted }}>
                {liste.advarsler.length} redaktionelle advarsler — rapportering, udløser aldrig ændringer
              </summary>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 12, fontSize: 12.5, color: T.muted, lineHeight: 1.5 }}>
                {liste.advarsler.slice(0, 200).map((a, i) => (
                  <div key={i} style={{ display: 'flex', gap: 10 }}><span style={{ color: T.gold, flex: 'none' }}>▲</span><span>{a.besked}</span></div>
                ))}
              </div>
            </details>
          )}

          {linjer.map((lin) => (
            <PresensLinjeSektion key={lin.linje} gruppe={lin} info={linjeInfo[lin.linje]} navnAf={navnAf} aarAf={aarAf} onPick={onPickPerson} fokusId={fokusId} />
          ))}

          <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.08em', color: T.muted2, marginTop: 52, borderTop: '1px solid rgba(34,31,26,.08)', paddingTop: 14, textAlign: 'center' }}>
            Kun levende personer samt afdøde forbindelsesled medtages.
          </div>
        </div>
      </div>
    </div>
  );
```

Keep every earlier `if (...) return (...)` guard clause in the function (henter/adgang/
fejl/tom-tilstand) exactly as they are today — only the final render body changes.

- [ ] **Step 4 (verification, no code change): Run the full presens test suite**

Run:
```bash
cd packages/core && npx vitest run src/__tests__/presensListe.test.ts src/__tests__/presensLabels.test.ts src/__tests__/presensFacit.test.ts
cd ../../web && npx vitest run src/components/__tests__/PresensView.test.tsx src/data/__tests__/presens.test.ts src/data/__tests__/presensLinjer.test.ts
```
Expected: all PASS (baseline 34 + 4 + 2 + 5 = 45 tests green; exact count may differ
slightly by ± the tests added in Tasks 1/2/4, but there must be zero failures).

- [ ] **Step 5: Typecheck**

Run: `cd web && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 6: Manual browser verification**

Per the project's UI-change policy, this redesign must be exercised in a real browser
before being called done:

```bash
cd web && npm run dev
```

Open the printed local URL, log in as a redaktør (existing `/redaktion` login flow),
navigate to the "Præsens" tab. Verify:
- Page renders without a console error even if `linjer` is empty (no overhoveder
  assigned yet in the connected database) — the existing "Ingen overhoveder udpeget
  endnu" empty-state message (unchanged, still guarded before the new render body)
  should show.
- If at least one overhoved exists, confirm the linje header (with num/titel/navn — or
  gracefully blank titel/navn/våben if that data isn't populated yet, since Task 6's
  runbook hasn't necessarily run) renders above its gren(s), and the sticky left index
  scrolls the page to the right anchor on click.

- [ ] **Step 7: Commit**

```bash
git add web/src/components/PresensView.tsx
git commit -m "feat(presens): redesign top-level layout — titelblad, intro, sticky-indeks, linje-sektioner"
```

---

### Task 6: Manual runbook for real heraldik + præsens-intro data (not a code task)

This task has no automated test cycle — it's real editorial content (blasonering,
actual coat-of-arms images, the présens-intro paragraphs) that only the user can
supply/approve. Create the runbook so the content can be populated later without
re-deriving the SQL shape from scratch.

**Files:**
- Create: `docs/superpowers/plans/2026-07-24-praesensliste-vaaben-data-runbook.md`

- [ ] **Step 1: Write the runbook**

```markdown
# Præsensliste — våben + intro-tekst dataindsættelse (runbook)

Kør EFTER Task 3's migration (`vocab` rolle='vaaben') er anvendt mod prod. Kør altid
mod en lokal kopi/branch-base først (jf. global regel om DB-ændringer).

## 1. Upload våben-billeder til Storage

Upload de eksisterende PNG'er fra Claude Design-projektet (`assets/heraldik/linje-I.png`,
`linje-II.png` — kun disse to findes pt. som pr.-linje-specifikke filer; øvrige linjer
mangler stadig dedikerede billeder) til Supabase Storage-bucketten `media`, under en sti
efter eksisterende konvention, fx `heraldik/linje-i.png`.

## 2. Indsæt media + coat_of_arms + relation pr. linje

For hver linje der har et billede, kør (udfyld de firkantede parenteser med reelle
værdier — `lineage_id` findes via `SELECT id, kode, navn FROM lineage;`):

```sql
-- 1) media-række for billedfilen
INSERT INTO media (id, slags, bucket, storage_path, upload_status, maa_publiceres)
VALUES ([nyt_id], 'scanning', 'media', 'heraldik/linje-i.png', 'klar', true);

-- 2) coat_of_arms-række (blasonering kan eftersuppleres)
INSERT INTO coat_of_arms (id, blasonering, note)
VALUES ([nyt_id], '[blasonering — redaktionelt indhold]', NULL);

-- 3) media viser våbnet (eksisterende konvention, samme retning som fetchObjectMedia)
INSERT INTO relation (subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
VALUES ('media', [media_id], 'coat_of_arms', [coat_of_arms_id], 'afbildet');

-- 4) linjen har dette våben (ny relationstype, Task 3's vocab-kode)
INSERT INTO relation (subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
VALUES ('lineage', [lineage_id], 'coat_of_arms', [coat_of_arms_id], 'vaaben');
```

## 3. Præsens-intro narrativ

```sql
-- 1) dedikeret kilde
INSERT INTO source (id, slags, titel) VALUES ([nyt_id], 'præsens-intro', 'Præsensliste — indledning');

-- 2) narrativet selv (subjekt_id=1 er samme sentinel som "Om slægten"s subjekt_type='slaegt')
INSERT INTO narrative (id, subjekt_type, subjekt_id, source_id, tekst, privat)
VALUES ([nyt_id], 'slaegt', 1, [source_id fra trin 1], '[intro-tekst — redaktionelt indhold, to afsnit adskilt af \n\n]', false);
```

## 4. Verificér

Genindlæs `/praesens` (redaktør-login) og bekræft at våben/titel/navn/intro nu vises for
de linjer der har fået data — linjer uden data falder tilbage til blank (ingen fejl,
jf. Task 4/5's `undefined`-håndtering).
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-07-24-praesensliste-vaaben-data-runbook.md
git commit -m "docs(presens): runbook til at indsætte reelle våben-billeder og intro-tekst"
```

---

## Prerequisites (run once, before Task 1)

```bash
npm install   # monorepo root — installs packages/core + web + mobile workspaces
```

Web's Vitest suite throws at import-time without Supabase env vars (even for tests that
never hit the network, because `web/src/supabase.ts` validates eagerly at module load).
Create `web/.env.local` (git-ignored) with placeholder values if it doesn't already
exist locally:

```bash
cd web
printf 'VITE_SUPABASE_URL=https://placeholder.supabase.co\nVITE_SUPABASE_ANON_KEY=placeholder-anon-key\n' > .env.local
```
