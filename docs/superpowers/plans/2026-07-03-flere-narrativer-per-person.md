# Flere narrativer pr. person — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør `narrative` udgave-nøglet, så en person kan bære én biografi pr. DAA-udgave (`source`), uden at bryde versionering, hyperlinks eller `samme_som`-foldning.

**Architecture:** DB-laget nøgles på `(subjekt_type, subjekt_id, source_id)` via en ny `red_upsert_narrativ`-signatur; en additiv `source.aar`-kolonne bærer udgave-kronologi. En ren, per-subjekt selector (`pickPreferredBio`) vælger deterministisk den foretrukne offentlige narrativ (nyeste DAA-udgave) og bruges af både web- og mobil-læseren. Redaktør-fladen får udgave-faner (web) hhv. en minimal source-korrekt skrivevej (mobil, obligatorisk fordi RPC-signaturen droppes for begge klienter).

**Tech Stack:** PostgreSQL/Supabase (RPC'er), TypeScript + React (web, `vitest`), React Native/Expo (mobil, `jest`).

## Global Constraints

- `schema.sql` er source of truth; **alle** DB-ændringer spejles idempotent i `db-migrations.sql` (`ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE`, eksplicit `DROP FUNCTION` før signatur-ændring). Verificér i `db-verify.sql`-stil.
- Cache-felter (`visning_*`, `koen`) skrives aldrig direkte — irrelevant her, men prosaen (`narrative.tekst`) **konkateneres/overskrives aldrig på tværs af udgaver** (invariant §6).
- Hver DAA-udgave = egen `source` (invariant §7).
- Web-tests: `cd web && npm test` (`vitest run`). Mobil-tests: `cd mobile && npm test` (`jest`).
- Ingen shared TS-pakke mellem web og mobil → selector-koden **duplikeres** i `web/src/data/` og `mobile/src/data/` med **identiske parallelle tests** (samme mønster som `lib/mentions.ts` i begge apps).
- Dansk UI-tekst.
- RPC-DROP + CREATE er en **cross-client breaking change** (web + mobil deler kontrakt) — begge klienter opdateres i denne plan.
- Data-fakta (verificeret 2026-07-03): 591 narrativer, alle `source_id=1` (`slags='DAA-udgave'`); source 2 = TNG (`genealogi-database`, 0 narrativer); 0 personer med >1 narrativ. Ændringen er kollisionsfri på eksisterende data.

**Selector-semantik (per-subjekt, ikke per-gruppe):** `pickPreferredBio` vælger for ét subjekt. Cross-medlem-komposition bevares uændret pr. app (web concat i `public.ts:144`; mobil merge via `collapseSameAs`). Determinisme opnås fordi per-subjekt-valget nu er deterministisk (fuld orden), ikke fordi vi indfører gruppe-niveau-valg.

---

### Task 1: DB — `source.aar`-kolonne + `red_opret_kilde` udvidet med `p_aar`

**Files:**
- Modify: `schema.sql` (source-tabel ~L32-39; `red_opret_kilde` ~L983-993)
- Modify: `db-migrations.sql` (append i bunden)
- Modify: `db-verify.sql` (tilføj assert-blok)

**Interfaces:**
- Produces: `source.aar SMALLINT` (nullable); `red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false, p_aar smallint DEFAULT NULL) RETURNS bigint`

- [ ] **Step 1: Skriv verifikations-SQL (fejlende assert)** i `db-verify.sql` — tilføj:

```sql
-- Task: flere-narrativer — source.aar findes + red_opret_kilde tager p_aar
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM information_schema.columns
          WHERE table_name='source' AND column_name='aar')=1,
    'source.aar mangler';
  ASSERT (SELECT count(*) FROM information_schema.routines
          WHERE routine_name='red_opret_kilde'
            AND pg_get_function_identity_arguments(
                  (quote_ident(specific_schema)||'.'||routine_name)::regproc) LIKE '%p_aar%')=1,
    'red_opret_kilde mangler p_aar';
  ASSERT (SELECT aar FROM source WHERE id=1)=2018, 'source 1 aar ikke backfillet';
END $$;
```

- [ ] **Step 2: Kør assert mod prod for at se den fejle**

Run: `mcp__supabase__execute_sql` med indholdet af DO-blokken.
Expected: FEJL `source.aar mangler`.

- [ ] **Step 3: Opdatér `schema.sql`** — tilføj kolonne i `source`-tabellen:

```sql
CREATE TABLE source (             -- = kilde/værk; også DAA-udgaver og eksterne værker
  id            BIGINT PRIMARY KEY,
  slags         TEXT,             -- 'kirkebog','DAA-udgave','diplomsamling','bog','artikel','segl'
  titel         TEXT,
  udgave        TEXT,             -- fx 'DAA 2018-20', 'DAA 1982-84'
  aar           SMALLINT,         -- udgave-kronologi (struktureret; udgave-fritekst er upålidelig til sortering)
  ekstern       BOOLEAN DEFAULT FALSE,   -- eksternt referenceværk (Gotha, ES, DBL ...)
  repository_id BIGINT REFERENCES repository(id)
);
```

Og erstat `red_opret_kilde` med 5-arg-versionen:

```sql
CREATE OR REPLACE FUNCTION red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false, p_aar smallint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_opret_kilde', format('Oprettede kilde %s', p_titel), NULL, NULL);
  IF nullif(btrim(p_titel),'') IS NULL THEN RAISE EXCEPTION 'Titel er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel, udgave, aar, ekstern) VALUES (v_id, p_slags, p_titel, p_udgave, p_aar, p_ekstern);
  RETURN v_id;
END $$;
```

- [ ] **Step 4: Append idempotent migration** til `db-migrations.sql`:

```sql
-- ---------- FLERE NARRATIVER: source.aar + red_opret_kilde(p_aar) (2026-07-03) ----------
ALTER TABLE source ADD COLUMN IF NOT EXISTS aar SMALLINT;
UPDATE source SET aar=2018 WHERE id=1 AND aar IS NULL;   -- backfill eksisterende DAA-udgave
DROP FUNCTION IF EXISTS red_opret_kilde(text, text, text, boolean);   -- undgå PostgREST-overload
-- (CREATE OR REPLACE af 5-arg-versionen — kopiér funktionsteksten fra schema.sql)
```

Efterfulgt af den fulde 5-arg `CREATE OR REPLACE FUNCTION red_opret_kilde(...)` fra Step 3.

- [ ] **Step 5: Anvend migration mod prod**

Run: `mcp__supabase__apply_migration` (name: `flere_narrativer_source_aar`) med `ALTER` + `UPDATE` + `DROP` + `CREATE`-blokken.

- [ ] **Step 6: Kør assert-blokken fra Step 1 igen**

Run: `mcp__supabase__execute_sql`.
Expected: ingen fejl (alle ASSERT passerer).

- [ ] **Step 7: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): source.aar + red_opret_kilde(p_aar) for udgave-kronologi"
```

---

### Task 2: DB — `red_upsert_narrativ` source-nøglet

**Files:**
- Modify: `schema.sql` (`red_upsert_narrativ` ~L591-609)
- Modify: `db-migrations.sql` (append)
- Modify: `db-verify.sql` (assert)

**Interfaces:**
- Consumes: `source.aar` (Task 1) er ikke krævet her, men `source_id` FK bruges.
- Produces: `red_upsert_narrativ(p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean, p_source_id bigint, p_side text DEFAULT NULL) RETURNS bigint` — nøgles på `(subjekt_type, subjekt_id, source_id)`.

- [ ] **Step 1: Skriv fejlende funktionel test (SQL)** — kør som redaktion mod en throwaway test-person (brug et højt `subjekt_id` der ikke findes, fx 999999):

```sql
-- Forventning EFTER fix: to sources → to narrativ-rækker for samme person
SELECT set_config('request.jwt.claims', json_build_object('role','redaktion')::text, true);
SELECT red_upsert_narrativ('person', 999999, 'Bio udgave A', false, 1, '10-11');
SELECT red_upsert_narrativ('person', 999999, 'Bio udgave B', false, 2, NULL);
-- assert: 2 rækker
DO $$ BEGIN ASSERT (SELECT count(*) FROM narrative WHERE subjekt_id=999999)=2, 'source-nøgling virker ikke'; END $$;
```

Bemærk: rollemocking følger mønsteret i `db-verify.sql`; brug den etablerede helper hvis en findes (`current_rolle()`-kilde).

- [ ] **Step 2: Kør mod prod for at se den fejle**

Run: `mcp__supabase__execute_sql`.
Expected: FEJL — gammel signatur har ikke `p_source_id`; kaldet fejler (funktionen findes ikke med 6 args). Ryd op: `DELETE FROM narrative WHERE subjekt_id=999999;`

- [ ] **Step 3: Opdatér `schema.sql`** — erstat `red_upsert_narrativ`:

```sql
-- Upsert narrativ, nøglet på (subjekt_type, subjekt_id, source_id) — én narrativ pr. udgave
CREATE OR REPLACE FUNCTION red_upsert_narrativ(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean,
  p_source_id bigint, p_side text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_upsert_narrativ', format('Opdaterede narrativ på %s/%s (kilde %s)', p_subjekt_type, p_subjekt_id, p_source_id), p_subjekt_type, p_subjekt_id);
  SELECT id INTO v_id FROM narrative
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND source_id IS NOT DISTINCT FROM p_source_id
    ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO narrative(id, subjekt_type, subjekt_id, source_id, tekst, side, privat)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM narrative), p_subjekt_type, p_subjekt_id, p_source_id, p_tekst, p_side, p_privat)
      RETURNING id INTO v_id;
  ELSE
    UPDATE narrative SET tekst=p_tekst, privat=p_privat, side=COALESCE(p_side, side) WHERE id=v_id;
  END IF;
  RETURN v_id;
END $$;
```

- [ ] **Step 4: Append idempotent migration** til `db-migrations.sql`:

```sql
-- ---------- FLERE NARRATIVER: red_upsert_narrativ source-nøglet (2026-07-03) ----------
DROP FUNCTION IF EXISTS red_upsert_narrativ(text, bigint, text, boolean);   -- gammel 4-arg → undgå overload
-- (CREATE OR REPLACE af 6-arg-versionen — kopiér fra schema.sql)
```

Efterfulgt af den fulde 6-arg `CREATE OR REPLACE FUNCTION` fra Step 3.

- [ ] **Step 5: Anvend migration mod prod**

Run: `mcp__supabase__apply_migration` (name: `flere_narrativer_upsert_source_keyed`).

- [ ] **Step 6: Kør Step 1-testen igen + oprydning**

Run: `mcp__supabase__execute_sql` (Step 1-blokken), derefter `DELETE FROM narrative WHERE subjekt_id=999999;`
Expected: ASSERT passerer (2 rækker); oprydning fjerner testdata. Kør også en re-upsert-check: gentag `red_upsert_narrativ('person',999999,'Bio A2',false,1,NULL)` → assert stadig 2 rækker og tekst opdateret + `side` uændret ('10-11').

- [ ] **Step 7: Commit**

```bash
git add schema.sql db-migrations.sql db-verify.sql
git commit -m "feat(db): red_upsert_narrativ nøglet på (subjekt,source_id)"
```

---

### Task 3: Web — `pickPreferredBio` ren selector + tests

**Files:**
- Create: `web/src/data/pickPreferredBio.ts`
- Test: `web/src/data/__tests__/pickPreferredBio.test.ts`

**Interfaces:**
- Produces:
```ts
export type NarrativeCand = {
  narrativeId: number;
  tekst: string | null;
  sourceId: number | null;
  slags: string | null;   // source.slags
  aar: number | null;     // source.aar
  udgave: string | null;  // source.udgave (til byline)
};
export function pickPreferredBio(cands: NarrativeCand[]): NarrativeCand | null;
```

- [ ] **Step 1: Skriv fejlende tests**

```ts
import { describe, it, expect } from 'vitest';
import { pickPreferredBio, NarrativeCand } from '../pickPreferredBio';

const c = (o: Partial<NarrativeCand>): NarrativeCand =>
  ({ narrativeId: 1, tekst: 'x', sourceId: 1, slags: 'DAA-udgave', aar: 2018, udgave: 'DAA 2018-20', ...o });

describe('pickPreferredBio', () => {
  it('vælger nyeste DAA-udgave (aar DESC)', () => {
    const r = pickPreferredBio([
      c({ narrativeId: 1, aar: 1982, udgave: 'DAA 1982-84' }),
      c({ narrativeId: 2, aar: 2018, udgave: 'DAA 2018-20' }),
    ]);
    expect(r?.narrativeId).toBe(2);
  });
  it('NULLS LAST: udgave uden aar taber til backfillet 2018', () => {
    const r = pickPreferredBio([
      c({ narrativeId: 1, aar: null, udgave: 'DAA særudgave' }),
      c({ narrativeId: 2, aar: 2018 }),
    ]);
    expect(r?.narrativeId).toBe(2);
  });
  it('ignorerer tom tekst', () => {
    const r = pickPreferredBio([c({ narrativeId: 1, tekst: '' }), c({ narrativeId: 2, tekst: 'bio' })]);
    expect(r?.narrativeId).toBe(2);
  });
  it('non-DAA giver ingen bio (fallback = null, ikke vilkårlig stub)', () => {
    const r = pickPreferredBio([c({ narrativeId: 1, slags: 'genealogi-database', aar: null, udgave: null })]);
    expect(r).toBeNull();
  });
  it('deterministisk tie-break ved ens aar: sourceId DESC, så narrativeId DESC', () => {
    const r = pickPreferredBio([
      c({ narrativeId: 5, sourceId: 1, aar: 2018 }),
      c({ narrativeId: 6, sourceId: 3, aar: 2018 }),
    ]);
    expect(r?.narrativeId).toBe(6);
  });
});
```

- [ ] **Step 2: Kør — fejler (modul findes ikke)**

Run: `cd web && npx vitest run src/data/__tests__/pickPreferredBio.test.ts`
Expected: FAIL (cannot find module).

- [ ] **Step 3: Implementér `web/src/data/pickPreferredBio.ts`**

```ts
export type NarrativeCand = {
  narrativeId: number;
  tekst: string | null;
  sourceId: number | null;
  slags: string | null;
  aar: number | null;
  udgave: string | null;
};

// Godkendte source-slags der må levere en offentlig standardbio. Kun DAA-udgaver nu;
// udvid bevidst (ikke vilkårlig fallback — en TNG-stub må ikke blive autoritativ bio).
const BIO_SLAGS = new Set(['DAA-udgave']);

// Vælger den foretrukne offentlige narrativ for ÉT subjekt. Kalderen har allerede
// filtreret private rækker fra (RLS + query). Fuld deterministisk orden:
// aar DESC NULLS LAST, sourceId DESC, narrativeId DESC.
export function pickPreferredBio(cands: NarrativeCand[]): NarrativeCand | null {
  const eligible = cands.filter((c) => (c.tekst ?? '').trim() !== '' && c.slags != null && BIO_SLAGS.has(c.slags));
  if (eligible.length === 0) return null;
  eligible.sort((a, b) => {
    const aa = a.aar ?? -Infinity, ba = b.aar ?? -Infinity;   // NULLS LAST ved DESC
    if (aa !== ba) return ba - aa;
    const as = a.sourceId ?? -Infinity, bs = b.sourceId ?? -Infinity;
    if (as !== bs) return bs - as;
    return b.narrativeId - a.narrativeId;
  });
  return eligible[0];
}
```

- [ ] **Step 4: Kør — passerer**

Run: `cd web && npx vitest run src/data/__tests__/pickPreferredBio.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add web/src/data/pickPreferredBio.ts web/src/data/__tests__/pickPreferredBio.test.ts
git commit -m "feat(web): pickPreferredBio ren selector (nyeste DAA-udgave, deterministisk)"
```

---

### Task 4: Mobil — `pickPreferredBio` (spejlet) + tests

**Files:**
- Create: `mobile/src/data/pickPreferredBio.ts`
- Test: `mobile/src/data/__tests__/pickPreferredBio.test.ts`

**Interfaces:**
- Produces: identisk `NarrativeCand` + `pickPreferredBio` som Task 3 (duplikeret; hold i sync).

- [ ] **Step 1: Skriv fejlende tests (jest)** — samme cases som Task 3, men jest-syntaks:

```ts
import { pickPreferredBio, NarrativeCand } from '../pickPreferredBio';

const c = (o: Partial<NarrativeCand>): NarrativeCand =>
  ({ narrativeId: 1, tekst: 'x', sourceId: 1, slags: 'DAA-udgave', aar: 2018, udgave: 'DAA 2018-20', ...o });

test('vælger nyeste DAA-udgave', () => {
  expect(pickPreferredBio([c({ narrativeId: 1, aar: 1982 }), c({ narrativeId: 2, aar: 2018 })])?.narrativeId).toBe(2);
});
test('NULLS LAST', () => {
  expect(pickPreferredBio([c({ narrativeId: 1, aar: null }), c({ narrativeId: 2, aar: 2018 })])?.narrativeId).toBe(2);
});
test('ignorerer tom tekst', () => {
  expect(pickPreferredBio([c({ narrativeId: 1, tekst: '' }), c({ narrativeId: 2, tekst: 'bio' })])?.narrativeId).toBe(2);
});
test('non-DAA giver null', () => {
  expect(pickPreferredBio([c({ slags: 'genealogi-database' })])).toBeNull();
});
test('tie-break sourceId DESC så narrativeId DESC', () => {
  expect(pickPreferredBio([c({ narrativeId: 5, sourceId: 1 }), c({ narrativeId: 6, sourceId: 3 })])?.narrativeId).toBe(6);
});
```

- [ ] **Step 2: Kør — fejler**

Run: `cd mobile && npx jest src/data/__tests__/pickPreferredBio.test.ts`
Expected: FAIL (cannot find module).

- [ ] **Step 3: Implementér `mobile/src/data/pickPreferredBio.ts`** — **kopiér ordret** filen fra Task 3, Step 3.

- [ ] **Step 4: Kør — passerer**

Run: `cd mobile && npx jest src/data/__tests__/pickPreferredBio.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/pickPreferredBio.ts mobile/src/data/__tests__/pickPreferredBio.test.ts
git commit -m "feat(mobile): pickPreferredBio (spejlet fra web)"
```

---

### Task 5: Web — læse-lag: `fetchPersonNarrativer` + `fetchSources`

**Files:**
- Modify: `web/src/data/redaktionRead.ts:152-170` (erstat `fetchPersonNarrativ`)
- Test: `web/src/data/__tests__/redaktionRead.narrativer.test.ts` (ny, hvis pattern findes — ellers unit på `mapNarrativer`)

**Interfaces:**
- Produces:
```ts
export type PersonNarrativ = { id: number; sourceId: number | null; sourceTitel: string | null; udgave: string | null; side: string | null; tekst: string; privat: boolean };
export function mapNarrativer(rows: RawNarrativRow[]): PersonNarrativ[];
export function fetchPersonNarrativer(id: string): Promise<PersonNarrativ[]>;
export type SourceRow = { id: number; titel: string | null; udgave: string | null; slags: string | null; aar: number | null };
export function fetchSources(): Promise<SourceRow[]>;
```
- Consumes (Task 6/8): editoren og reader-wiringen kalder disse.

- [ ] **Step 1: Skriv fejlende test for `mapNarrativer`** (ren mapping, ingen netværk):

```ts
import { describe, it, expect } from 'vitest';
import { mapNarrativer } from '../redaktionRead';

describe('mapNarrativer', () => {
  it('mapper rækker med source-join, ordnet efter kilde', () => {
    const rows = [
      { id: 7, source_id: 2, side: null, tekst: 'B', privat: false, source: { titel: 'DAA 1982', udgave: 'DAA 1982-84' } },
      { id: 3, source_id: 1, side: '10', tekst: 'A', privat: true, source: { titel: 'DAA 2018', udgave: 'DAA 2018-20' } },
    ];
    const out = mapNarrativer(rows as any);
    expect(out.map((n) => n.id)).toEqual([3, 7]);         // ordnet efter source_id
    expect(out[0]).toMatchObject({ sourceId: 1, udgave: 'DAA 2018-20', side: '10', privat: true });
  });
});
```

- [ ] **Step 2: Kør — fejler** (`mapNarrativer` findes ikke)

Run: `cd web && npx vitest run src/data/__tests__/redaktionRead.narrativer.test.ts`
Expected: FAIL.

- [ ] **Step 3: Erstat `fetchPersonNarrativ`-blokken** (`redaktionRead.ts:152-170`) med:

```ts
// --- Narrativ-læsning: ALLE udgaver pr. person (source-join til byline + ordning) ---

export type PersonNarrativ = { id: number; sourceId: number | null; sourceTitel: string | null; udgave: string | null; side: string | null; tekst: string; privat: boolean };

type RawNarrativRow = { id: number; source_id: number | null; side: string | null; tekst: string | null; privat: boolean | null; source: { titel: string | null; udgave: string | null } | null };

export function mapNarrativer(rows: RawNarrativRow[]): PersonNarrativ[] {
  return rows
    .map((r) => ({
      id: r.id, sourceId: r.source_id, sourceTitel: r.source?.titel ?? null,
      udgave: r.source?.udgave ?? null, side: r.side, tekst: r.tekst ?? '', privat: Boolean(r.privat),
    }))
    .sort((a, b) => (a.sourceId ?? Infinity) - (b.sourceId ?? Infinity) || a.id - b.id);
}

export async function fetchPersonNarrativer(id: string): Promise<PersonNarrativ[]> {
  const { data, error } = await supabase
    .from('narrative').select('id,source_id,side,tekst,privat,source:source_id(titel,udgave)')
    .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
    .order('source_id', { ascending: true }).order('id', { ascending: true });
  if (error) throw new Error(error.message);
  return mapNarrativer((data ?? []) as unknown as RawNarrativRow[]);
}

export type SourceRow = { id: number; titel: string | null; udgave: string | null; slags: string | null; aar: number | null };
export async function fetchSources(): Promise<SourceRow[]> {
  const { data, error } = await supabase.from('source').select('id,titel,udgave,slags,aar').order('aar', { ascending: false, nullsFirst: false });
  if (error) throw new Error(error.message);
  return (data ?? []) as SourceRow[];
}
```

- [ ] **Step 4: Ret kalder-sites af `fetchPersonNarrativ`** — grep og opdatér:

Run: `cd web && grep -rn "fetchPersonNarrativ\b" src`
For hver forekomst (fx `Redaktion.tsx`, `data/index.ts`-reeksport): opdateres i Task 6. Efterlad `fetchPersonNarrativ` **fjernet** — ingen dead export.

- [ ] **Step 5: Kør test + tsc**

Run: `cd web && npx vitest run src/data/__tests__/redaktionRead.narrativer.test.ts && npx tsc --noEmit`
Expected: mapping-test PASS. `tsc` kan fejle midlertidigt på `Redaktion.tsx` (rettes i Task 6) — noter det; hvis så, spring commit til efter Task 6. Ellers commit nu.

- [ ] **Step 6: Commit**

```bash
git add web/src/data/redaktionRead.ts web/src/data/__tests__/redaktionRead.narrativer.test.ts
git commit -m "feat(web): fetchPersonNarrativer (liste pr. udgave) + fetchSources"
```

---

### Task 6: Web — redaktør-UI: udgave-faner + source-korrekt skriv

**Files:**
- Modify: `web/src/Redaktion.tsx` (narrativ-state ~L93, effekt ~L149-153, render ~L431-452)
- Modify: `web/src/data/redaktionWrite.ts:100-104` (narrativ arg-builder)

**Interfaces:**
- Consumes: `fetchPersonNarrativer`, `fetchSources`, `PersonNarrativ`, `SourceRow` (Task 5); `red_opret_kilde(...,p_aar)` (Task 1); source-nøglet `red_upsert_narrativ` (Task 2).
- Produces: `Command` for narrativ bærer nu `sourceId` + `side`.

- [ ] **Step 1: Udvid `Command`-typen + arg-builder** i `redaktionWrite.ts`. Erstat narrativ-grenen (L100-104):

```ts
  if (c.art === 'narrativ') {
    return { fn: 'red_upsert_narrativ', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: c.vaerdi,
      p_privat: Boolean(c.payload?.privat),
      p_source_id: c.payload?.sourceId ?? null,
      p_side: c.payload?.side ?? null } };
  }
```

Sørg for at `Command['payload']`-typen tillader `sourceId?: number | null; side?: string | null` (udvid interface-definitionen i samme fil).

- [ ] **Step 2: Skriv fejlende test for arg-builder**

```ts
// web/src/data/__tests__/redaktionWrite.narrativ.test.ts
import { describe, it, expect } from 'vitest';
import { buildCall } from '../redaktionWrite';   // brug den faktiske eksport (tjek navn i filen)

describe('narrativ arg-builder', () => {
  it('sender p_source_id + p_side', () => {
    const call = buildCall({ art: 'narrativ', subjektType: 'person', subjektId: '5', vaerdi: 'bio',
      payload: { privat: false, sourceId: 2, side: '12' } } as any);
    expect(call).toMatchObject({ fn: 'red_upsert_narrativ', args: { p_source_id: 2, p_side: '12' } });
  });
});
```

Bemærk: tilpas import/funktionsnavn til den faktiske interne builder (`describeCall`/`toCall` — verificér i `redaktionWrite.ts`). Hvis builderen ikke er eksporteret, eksportér den.

- [ ] **Step 3: Kør — fejler, implementér, kør — passerer**

Run: `cd web && npx vitest run src/data/__tests__/redaktionWrite.narrativ.test.ts`
Expected: FAIL → efter Step 1 → PASS.

- [ ] **Step 4: Ombyg narrativ-sektionen i `Redaktion.tsx`.** State bliver en liste + aktiv-kilde:

```tsx
const [narrativer, setNarrativer] = useState<PersonNarrativ[]>([]);
const [aktivSourceId, setAktivSourceId] = useState<number | null>(null);
const [sources, setSources] = useState<SourceRow[]>([]);
const aktiv = narrativer.find((n) => n.sourceId === aktivSourceId) ?? null;
```

I person-effekten (erstat L153): `fetchPersonNarrativer(id).then((ns) => { setNarrativer(ns); setAktivSourceId(ns[0]?.sourceId ?? 1); });` og `fetchSources().then(setSources)` (én gang, evt. i mount-effekt).

Render (erstat L431-452) — udgave-faner + bundet textarea:

```tsx
{/* Narrativ · biografi — pr. udgave */}
<div style={sectionHeader(24)}>Narrativ · biografi</div>
<div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8 }}>
  {narrativer.map((n) => (
    <div key={n.id} onClick={() => setAktivSourceId(n.sourceId)}
      style={{ fontSize: 12, padding: '4px 10px', borderRadius: 7, cursor: 'pointer',
        background: n.sourceId === aktivSourceId ? T.bordeaux : 'transparent',
        color: n.sourceId === aktivSourceId ? T.paper : T.muted2, border: '1px solid rgba(34,31,26,.16)' }}>
      {n.udgave ?? n.sourceTitel ?? `Kilde ${n.sourceId}`}
    </div>
  ))}
  <div onClick={() => setAddingUdgave(true)} style={{ fontSize: 12, padding: '4px 10px', borderRadius: 7, cursor: 'pointer', border: '1px dashed rgba(34,31,26,.3)', color: T.muted2 }}>+ Ny udgave</div>
</div>
```

Textarea/privat/side binder til `aktiv` (fallback tom hvis `aktiv==null`, dvs. ny udgave under oprettelse). "Gem narrativ" sender:

```tsx
onClick={() => run({ art: 'narrativ', subjektType: 'person', subjektId: p.id,
  vaerdi: udkast.tekst,
  payload: { privat: udkast.privat, sourceId: aktivSourceId, side: udkast.side || null } }, 'Narrativ')}
```

hvor `udkast` er lokal edit-state for den aktive fane (nulstil ved fane-/record-skift, jf. eksisterende record-skift-logik L553). "+ Ny udgave" åbner en lille dialog: vælg eksisterende `source` (fra `sources`) **eller** opret via `red_opret_kilde` (kald gennem `run`/direkte RPC) med `p_slags='DAA-udgave'` + `p_aar` (påkrævet felt), sæt derefter `aktivSourceId` til den nye kilde og lad `aktiv==null` vise et tomt felt.

- [ ] **Step 5: Kør tsc + build + eksisterende suite**

Run: `cd web && npx tsc --noEmit && npm test && npm run build`
Expected: 0 TS-fejl; alle web-tests grønne; build OK.

- [ ] **Step 6: Commit**

```bash
git add web/src/Redaktion.tsx web/src/data/redaktionWrite.ts web/src/data/__tests__/redaktionWrite.narrativ.test.ts
git commit -m "feat(web): udgave-faner i redaktør + source-korrekt narrativ-skriv"
```

---

### Task 7: Web — læser: `public.ts` bruger `pickPreferredBio` pr. medlem

**Files:**
- Modify: `web/src/data/public.ts:128-144` (narrativ-fetch + `firstByMember`)
- Test: `web/src/data/__tests__/public.bio.test.ts` (hvis netværks-mock findes; ellers dæk via `pickPreferredBio`-tests + manuel)

**Interfaces:**
- Consumes: `pickPreferredBio`, `NarrativeCand` (Task 3).
- Bevarer: cross-medlem-concat (`orderedIds` … `.join('\n\n')`) uændret — kun *per-medlem-valget* ændres fra "første by id" til "foretrukne udgave".

- [ ] **Step 1: Udvid narrativ-query** (L130) til at hente source-metadata:

```ts
supabase.from('narrative').select('id,subjekt_id,tekst,source_id,source:source_id(slags,aar,udgave)')
  .eq('subjekt_type', 'person').in('subjekt_id', numIds)
  .eq('privat', false).order('id', { ascending: true }),
```

- [ ] **Step 2: Erstat `firstByMember`-løkken** (L138-142) med foretrukne-udgave pr. medlem:

```ts
import { pickPreferredBio, NarrativeCand } from './pickPreferredBio';
// ...
const candsByMember = new Map<string, NarrativeCand[]>();
for (const n of (narr.data ?? []) as any[]) {
  const k = String(n.subjekt_id);
  const arr = candsByMember.get(k) ?? [];
  arr.push({ narrativeId: n.id, tekst: n.tekst, sourceId: n.source_id, slags: n.source?.slags ?? null, aar: n.source?.aar ?? null, udgave: n.source?.udgave ?? null });
  candsByMember.set(k, arr);
}
const firstByMember = new Map<string, string>();
for (const [k, cands] of candsByMember) {
  const best = pickPreferredBio(cands);
  if (best?.tekst) firstByMember.set(k, best.tekst);
}
```

`orderedIds` + `bio`-concat (L143-144) forbliver uændret.

- [ ] **Step 3: Kør tsc + build + suite**

Run: `cd web && npx tsc --noEmit && npm test && npm run build`
Expected: grønt. Adfærd i dag uændret (alle narrativer er DAA-udgave source 1 → `pickPreferredBio` vælger samme som "første by id").

- [ ] **Step 4: Commit**

```bash
git add web/src/data/public.ts
git commit -m "feat(web): læser vælger foretrukne DAA-udgave pr. medlem (pickPreferredBio)"
```

---

### Task 8: Mobil — redaktør: source-korrekt læse + skriv (minimal, ingen faner)

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts:176-185` (narrativ-læs — tilføj `source_id`)
- Modify: `mobile/src/data/redaktionWrite.ts:104-106` (send `p_source_id`)
- Modify: `mobile/src/app/redaktion/person/[id].tsx` (bær `sourceId` i state, send i Gem)

**Interfaces:**
- Consumes: source-nøglet `red_upsert_narrativ` (Task 2).
- Produces: mobil-redaktørens Gem sender `p_source_id` → knækker ikke af RPC-DROP.

- [ ] **Step 1: Udvid mobil narrativ-læs** — `redaktionRead.ts` (~L181): tilføj `source_id` til `select` og returnér det i typen (`PersonNarrativ` mobil-side får `sourceId: number | null`). Behold `LIMIT 1` (single-narrativ-UI bevaret).

```ts
.from('narrative').select('id,tekst,privat,source_id')
```

Returnér `{ tekst, privat, sourceId: row.source_id ?? 1 }` (fallback 1 = primær DAA-udgave, defensivt).

- [ ] **Step 2: Send `p_source_id` i mobil arg-builder** — `redaktionWrite.ts` narrativ-gren:

```ts
  if (c.art === 'narrativ') {
    return { fn: 'red_upsert_narrativ', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: c.vaerdi,
      p_privat: Boolean(c.payload?.privat),
      p_source_id: c.payload?.sourceId ?? 1,
      p_side: c.payload?.side ?? null } };
  }
```

- [ ] **Step 3: Bær `sourceId` i editor-state** — `[id].tsx`: gem `sourceId` fra prefill (Step 1) i en `useState`, og inkludér `sourceId` i `payload` når Gem-kommandoen bygges. Ingen UI-ændring udover det.

- [ ] **Step 4: Skriv/udvid test for mobil arg-builder** (jest) — analog til web Task 6 Step 2: assert `p_source_id` sendes (default 1 hvis ukendt).

- [ ] **Step 5: Kør tsc + jest**

Run: `cd mobile && npx tsc --noEmit && npm test`
Expected: grønt.

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/redaktionWrite.ts "mobile/src/app/redaktion/person/[id].tsx" mobile/src/data/__tests__
git commit -m "fix(mobile): source-korrekt narrativ-skriv (Gem knækker ikke af RPC-DROP)"
```

---

### Task 9: Mobil — læser: `load.ts` bruger `pickPreferredBio`

**Files:**
- Modify: `mobile/src/data/load.ts:134-139` (narrativ-fetch — tilføj source-join), `:173-177` (`bioBy`)
- Modify: `mobile/src/data/types.ts` (`RawNarrative` får `source_id` + source-felter)
- Test: dækket af `pickPreferredBio`-tests (Task 4) + tsc

**Interfaces:**
- Consumes: `pickPreferredBio`, `NarrativeCand` (Task 4).
- Bevarer: `bioBy` pr. rå person + eksisterende `collapseSameAs`-merge (per-medlem-valget bliver deterministisk).

- [ ] **Step 1: Udvid narrativ-fetch** (L134-139) med `id` + source-join:

```ts
getAll<RawNarrative>(() =>
  sb.from('narrative').select('id,subjekt_id,subjekt_type,tekst,privat,source_id,source:source_id(slags,aar,udgave)')
    .eq('subjekt_type', 'person'),
),
```

Opdatér `RawNarrative` i `types.ts`: tilføj `id: number; source_id: number | null; source: { slags: string | null; aar: number | null; udgave: string | null } | null`.

- [ ] **Step 2: Erstat `bioBy`-løkken** (L173-177):

```ts
import { pickPreferredBio, NarrativeCand } from './pickPreferredBio';
// ...
const candsBy: Record<string, NarrativeCand[]> = {};
(narratives || []).forEach((n) => {
  if (n.privat) return;
  const k = String(n.subjekt_id);
  (candsBy[k] ??= []).push({ narrativeId: (n as any).id, tekst: n.tekst, sourceId: (n as any).source_id ?? null,
    slags: (n as any).source?.slags ?? null, aar: (n as any).source?.aar ?? null, udgave: (n as any).source?.udgave ?? null });
});
const bioBy: Record<string, string> = {};
for (const k of Object.keys(candsBy)) {
  const best = pickPreferredBio(candsBy[k]);
  if (best?.tekst) bioBy[k] = best.tekst;
}
```

- [ ] **Step 3: Kør tsc + jest + (hvis muligt) build**

Run: `cd mobile && npx tsc --noEmit && npm test`
Expected: grønt. Adfærd uændret i dag (alle narrativer DAA source 1).

- [ ] **Step 4: Commit**

```bash
git add mobile/src/data/load.ts mobile/src/data/types.ts
git commit -m "feat(mobile): læser vælger foretrukne DAA-udgave pr. person (pickPreferredBio)"
```

---

### Task 10: Verifikation, docs & sync-guard

**Files:**
- Modify: `docs/changelog.md`, `docs/decisions.md`
- Verify: begge selector-filer identiske

- [ ] **Step 1: Bekræft de to selector-filer er identiske**

Run: `diff web/src/data/pickPreferredBio.ts mobile/src/data/pickPreferredBio.ts`
Expected: ingen forskel (kun eventuelle import-frie forskelle = ingen).

- [ ] **Step 2: Kør fulde suites + tsc + build begge apps**

Run:
```bash
cd web && npx tsc --noEmit && npm test && npm run build
cd ../mobile && npx tsc --noEmit && npm test
```
Expected: alt grønt.

- [ ] **Step 3: Manuel prod-verifikation (redaktør, web)**

- Opret en 2. DAA-udgave via "+ Ny udgave" (`p_slags='DAA-udgave'`, `p_aar` sat).
- Tilføj en narrativ for en testperson på den nye udgave → bekræft begge faner + begge rækker i basen (`SELECT ... FROM narrative WHERE subjekt_id=<test>`).
- Rediger hver udgave uafhængigt; bekræft `privat` + `side` pr. udgave.
- Fortryd (change set) på én udgave → kun den udgave påvirkes.
- Læser (web + mobil): viser nyeste udgaves offentlige bio.
- **Ryd op:** fortryd testskrivningerne (change_set-restore) — efterlad ikke testdata i prod.

- [ ] **Step 4: Opdatér changelog + decisions**

Tilføj changelog-entry (2026-07-03): udgave-nøglede narrativer, `source.aar`, delt `pickPreferredBio`, mobil-redaktør source-korrekt. Decisions: per-subjekt selector-valg (ikke gruppe-niveau) + fallback = DAA-only (ingen vilkårlig stub).

- [ ] **Step 5: Commit**

```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: flere narrativer pr. person — changelog + decisions"
```

---

## Self-Review-noter

- **Spec-dækning:** §3.1 → Task 1-2; §3.2 → Task 5; §3.3 → Task 6; §3.3b → Task 8; §3.4 → Task 3-4 (selector) + Task 7 (web-læser) + Task 9 (mobil-læser); §5 test → pr.-task + Task 10.
- **Selector-altitude:** per-subjekt (ikke per-gruppe) — bevidst afvigelse fra spec §3.4's "på tværs af hele gruppen"-formulering, fordi web's cross-medlem-concat (`public.ts:144`) er tilsigtet og ikke må regressere. Determinisme opnås via fuld orden i `pickPreferredBio`. Noteret i decisions (Task 10).
- **Kendt begrænsning:** `max(id)+1`-ID-allokering (ikke concurrency-sikker) uændret; DB unique-constraint udskudt (tie-break på `narrative.id` kompenserer).
- **RPC-DROP-rækkefølge:** Task 1-2 (DB) SKAL landes før Task 6/8 (klient-kald), ellers fejler eksisterende kald i mellemtiden. Da DB anvendes direkte mod prod, koordinér: land Task 2 og Task 8 (mobil-klient) tæt, og deploy web (Task 6) samtidig — undgå at prod-web/mobil kører gammelt bundle mod ny RPC i et vindue. Overvej at deploye klient-bundles først efter alle commits er merged.
