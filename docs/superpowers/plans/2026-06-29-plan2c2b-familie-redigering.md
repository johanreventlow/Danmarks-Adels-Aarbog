# Plan 2C-2b — Familie-redigering (partner + barn + konfidens) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør familie-relationer (FORÆLDRE/ÆGTEFÆLLER/BØRN) redigerbare i redaktør-person-editoren: opret/fjern partner-union, tilføj/fjern barn (m. cyklus-guard + era-advarsel), ret konfidens på ethvert familie-link.

**Architecture:** Spejler 2C-2a. Fire SECURITY DEFINER family-RPC'er + en egen per-person familie-fetch (med id'er) + en PersonPicker-komponent + redigerbare familie-sektioner. Alle writes via det eksisterende `setPending → SkrivePreviewSheet`-gate. Familie-links bærer INGEN evidens → slet er ren DELETE; family-ENTITETEN bærer facts/notes → slettes ALDRIG.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand, `@supabase/supabase-js`, Jest, PostgreSQL/Supabase.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-29-plan2c2b-familie-redigering-design.md` (autoritativ).
- **Branch:** opret feature-branch fra `main` (`feat/plan2c2b-familie-redigering`); ingen merge/push uden eksplicit godkendelse.
- **Ingen family-entitets-sletning (Codex H1):** family bærer 276 `fact` (`subjekt_type='family'`) + 700 `note` (`target_type='family'`) uden FK. `red_slet_familie_link` sletter KUN family_member-rækken; tom family tolereres.
- **Ingen auto-dedup af unioner (Codex H2):** `red_opret_union` opretter ALTID ny union (samme par kan gifte sig igen).
- **Struktur-guards (Codex H3):** `red_tilfoej_barn` afviser barn==partner-i-samme-family + ane-cyklus (recursiv CTE over partner→barn-kanter, alle barn-subtyper).
- **Era-advarsel** er klient-side + ikke-blokerende (advar-og-tillad).
- **Familie-links bærer ingen evidens** (verificeret: assertion/conclusion.target_type ∈ {fact,relation}). Slet = ren DELETE.
- **`max(id)+1`** id-tildeling (projekt-bred PoC single-writer-debt) for family + family_member.
- **Fejl kastes, aldrig tom-som-clean** (cycle 03 NEW1).
- **GDPR:** fetchPersonFamilie/PersonPicker KUN i redaktør-editor (living-person-navne); aldrig i public model.
- **Pagination:** `getAll`/`.range()` (PostgREST 1000-cap).
- **DB-deploy = controller-gate** (prod, bruger-OK + backup), deferred til Task 8.
- **Vocab:** konfidens ∈ `sikker|sandsynlig|formodet|omstridt` (+ NULL); union-type ∈ `vielse|partnerskab|ugift union`; barn-rolle ∈ `barn|adopteret_barn|plejebarn|stedbarn`.
- **Tokens/Typography**; ingen rå hex (rgba OK). Ingen Claude-attribution. Conventional Commits, dansk.

---

## File Structure

**Ændrede:**
- `schema.sql`, `db-migrations.sql` — 4 RPC'er.
- `mobile/src/data/redaktionRead.ts` — `PersonFamilie`-typer, `mapFamilieRows`, `fetchPersonFamilie`.
- `mobile/src/data/redaktionWrite.ts` — `Change`-felter + 4 cases.
- `mobile/src/app/redaktion/person/[id].tsx` — redigerbar familie-sektion.

**Nye:**
- `mobile/src/data/eraAdvarsel.ts` — era-validerings-helper + `parseAar`.
- `mobile/src/components/redaktion/PersonPicker.tsx` — søgbar person-vælger.
- `mobile/src/data/__tests__/eraAdvarsel.test.ts`.

---

## Task 1: DB — `red_opret_union` + `red_set_familie_konfidens` + `red_slet_familie_link`

**Files:** Modify `schema.sql` (efter `red_tilfoej_relation`), `db-migrations.sql` (idempotent blok).

**Interfaces:**
- Produces: `red_opret_union(p_partner_a bigint, p_partner_b bigint, p_type text, p_ordinal int DEFAULT NULL) RETURNS bigint`; `red_set_familie_konfidens(p_family_id bigint, p_person_id bigint, p_rolle text, p_konfidens text) RETURNS void`; `red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text) RETURNS void`.

- [ ] **Step 1: Tilføj de 3 funktioner i `schema.sql`** (efter `red_tilfoej_relation`'s `END $$;`):
```sql
-- 2C-2b familie-redigering -------------------------------------------------
-- Opret partner-union. INGEN auto-dedup (Codex H2): samme par kan gifte sig igen.
CREATE OR REPLACE FUNCTION red_opret_union(p_partner_a bigint, p_partner_b bigint, p_type text, p_ordinal int DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_fam bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_partner_a = p_partner_b THEN RAISE EXCEPTION 'Partnere skal være forskellige'; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_partner_a) THEN RAISE EXCEPTION 'Person % findes ikke', p_partner_a; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_partner_b) THEN RAISE EXCEPTION 'Person % findes ikke', p_partner_b; END IF;
  IF p_type NOT IN ('vielse','partnerskab','ugift union') THEN RAISE EXCEPTION 'Ugyldig union-type %', p_type; END IF;
  INSERT INTO family(id, type) VALUES ((SELECT coalesce(max(id),0)+1 FROM family), p_type) RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens) VALUES (v_fam, p_partner_a, 'partner', p_ordinal, NULL);
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens) VALUES (v_fam, p_partner_b, 'partner', p_ordinal, NULL);
  RETURN v_fam;
END $$;

-- Ret konfidens på et eksisterende familie-link.
CREATE OR REPLACE FUNCTION red_set_familie_konfidens(p_family_id bigint, p_person_id bigint, p_rolle text, p_konfidens text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_n int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  UPDATE family_member SET konfidens=p_konfidens
    WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'Familie-link findes ikke (%, %, %)', p_family_id, p_person_id, p_rolle; END IF;
END $$;

-- Slet ÉT familie-link. INGEN family-entitets-sletning (Codex H1): family bærer facts/notes uden FK.
CREATE OR REPLACE FUNCTION red_slet_familie_link(p_family_id bigint, p_person_id bigint, p_rolle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  DELETE FROM family_member WHERE family_id=p_family_id AND person_id=p_person_id AND rolle=p_rolle;
END $$;
```

- [ ] **Step 2: Spejl idempotent i `db-migrations.sql`** — samme 3 `CREATE OR REPLACE`-blokke i bunden under kommentar `-- 2026-06-29: 2C-2b familie-RPC'er (1/2)`. (Grant arver `red\_%`-loopet — PUBLIC-default + db-rls.sql; ingen ekstra grant.)

- [ ] **Step 3: Commit**
```bash
git add schema.sql db-migrations.sql
git commit -m "feat(db): red_opret_union + red_set_familie_konfidens + red_slet_familie_link (2C-2b)"
```
(Live deploy = controller-gate Task 8.)

---

## Task 2: DB — `red_tilfoej_barn` (cyklus-guard)

**Files:** Modify `schema.sql` (efter Task 1's funktioner), `db-migrations.sql`.

**Interfaces:**
- Produces: `red_tilfoej_barn(p_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn', p_konfidens text DEFAULT NULL) RETURNS void`.

- [ ] **Step 1: Tilføj funktionen i `schema.sql`:**
```sql
-- Tilføj barn til en union. Struktur-guards (Codex H3): barn ≠ partner i samme family;
-- ingen ane-cyklus (recursiv CTE: descendants(barn) må ikke indeholde en partner i family).
CREATE OR REPLACE FUNCTION red_tilfoej_barn(p_family_id bigint, p_barn_id bigint, p_rolle text DEFAULT 'barn', p_konfidens text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cyklus boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS(SELECT 1 FROM family WHERE id=p_family_id) THEN RAISE EXCEPTION 'Familie % findes ikke', p_family_id; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_barn_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_barn_id; END IF;
  IF p_rolle NOT IN ('barn','adopteret_barn','plejebarn','stedbarn') THEN RAISE EXCEPTION 'Ugyldig barn-rolle %', p_rolle; END IF;
  IF p_konfidens IS NOT NULL AND p_konfidens NOT IN ('sikker','sandsynlig','formodet','omstridt')
    THEN RAISE EXCEPTION 'Ugyldig konfidens %', p_konfidens; END IF;
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle='partner')
    THEN RAISE EXCEPTION 'Person % er partner i familie % — kan ikke også være barn', p_barn_id, p_family_id; END IF;
  -- Cyklus: er en partner i family en efterkommer af barnet?
  WITH RECURSIVE efterkommere(pid) AS (
    SELECT p_barn_id
    UNION
    SELECT b.person_id FROM efterkommere e
      JOIN family_member par ON par.person_id = e.pid AND par.rolle = 'partner'
      JOIN family_member b   ON b.family_id = par.family_id
        AND b.rolle IN ('barn','adopteret_barn','plejebarn','stedbarn')
  )
  SELECT EXISTS(
    SELECT 1 FROM family_member fp
    WHERE fp.family_id = p_family_id AND fp.rolle='partner' AND fp.person_id IN (SELECT pid FROM efterkommere)
  ) INTO v_cyklus;
  IF v_cyklus THEN RAISE EXCEPTION 'Cyklus: barn % er ane til en partner i familie %', p_barn_id, p_family_id; END IF;
  -- Dup-guard (PK): no-op hvis linket allerede findes
  IF EXISTS(SELECT 1 FROM family_member WHERE family_id=p_family_id AND person_id=p_barn_id AND rolle=p_rolle) THEN RETURN; END IF;
  INSERT INTO family_member(family_id, person_id, rolle, ordinal, konfidens)
    VALUES (p_family_id, p_barn_id, p_rolle, NULL, p_konfidens);
END $$;
```

- [ ] **Step 2: Spejl i `db-migrations.sql`** under `-- 2026-06-29: 2C-2b familie-RPC'er (2/2)`.

- [ ] **Step 3: Commit**
```bash
git add schema.sql db-migrations.sql
git commit -m "feat(db): red_tilfoej_barn m. cyklus-guard (2C-2b)"
```

---

## Task 3: `fetchPersonFamilie` + `mapFamilieRows`

**Files:** Modify `mobile/src/data/redaktionRead.ts`; Test `mobile/src/data/__tests__/redaktionRead.test.ts`.

**Interfaces:**
- Consumes: `getAll`, `supabase`, `Model` (types).
- Produces:
```ts
export type FamiliePartner = { personId: string; navn: string; konfidens: string | null; ordinal: number | null };
export type FamilieBarn = { personId: string; navn: string; rolle: string; konfidens: string | null };
export type Union = { familyId: string; type: string; partnere: FamiliePartner[]; boern: FamilieBarn[] };
export type SomBarn = { familyId: string; rolle: string; konfidens: string | null; foraeldre: { personId: string; navn: string }[] };
export type PersonFamilie = { somPartner: Union[]; somBarn: SomBarn[] };
type RawFamRow = { family_id: number; person_id: number; rolle: string; ordinal: number | null; konfidens: string | null };
type RawFamilyMeta = { id: number; type: string | null };
export function mapFamilieRows(personId: string, families: RawFamilyMeta[], members: RawFamRow[], model: import('./types').Model | null): PersonFamilie
export async function fetchPersonFamilie(id: string, model): Promise<PersonFamilie>
```

- [ ] **Step 1: Skriv fejlende test for `mapFamilieRows`** i `redaktionRead.test.ts`:
```ts
import { mapFamilieRows } from '../redaktionRead';

const MODEL = { byId: {
  '1': { visning_navn: 'Far' }, '2': { visning_navn: 'Mor' },
  '3': { visning_navn: 'Barn A' }, '7': { visning_navn: 'Fokus' },
} } as never;

test('mapFamilieRows: union m. partnere+børn, og person som barn', () => {
  const families = [{ id: 10, type: 'vielse' }, { id: 20, type: 'vielse' }];
  const members = [
    // family 10: fokus(7) + far(1) partnere, barn A(3)
    { family_id: 10, person_id: 7, rolle: 'partner', ordinal: 1, konfidens: null },
    { family_id: 10, person_id: 1, rolle: 'partner', ordinal: 1, konfidens: 'sikker' },
    { family_id: 10, person_id: 3, rolle: 'barn', ordinal: null, konfidens: null },
    // family 20: fokus(7) er barn af far(1)+mor(2)
    { family_id: 20, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 20, person_id: 2, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 20, person_id: 7, rolle: 'barn', ordinal: null, konfidens: 'formodet' },
  ];
  const r = mapFamilieRows('7', families as never, members as never, MODEL);
  expect(r.somPartner).toEqual([{ familyId: '10', type: 'vielse',
    partnere: [{ personId: '1', navn: 'Far', konfidens: 'sikker', ordinal: 1 }],
    boern: [{ personId: '3', navn: 'Barn A', rolle: 'barn', konfidens: null }] }]);
  expect(r.somBarn).toEqual([{ familyId: '20', rolle: 'barn', konfidens: 'formodet',
    foraeldre: [{ personId: '1', navn: 'Far' }, { personId: '2', navn: 'Mor' }] }]);
});

test('mapFamilieRows: ukendt person → #id-fallback', () => {
  const r = mapFamilieRows('7', [{ id: 10, type: 'vielse' }] as never,
    [{ family_id: 10, person_id: 7, rolle: 'partner', ordinal: null, konfidens: null },
     { family_id: 10, person_id: 99, rolle: 'barn', ordinal: null, konfidens: null }] as never, MODEL);
  expect(r.somPartner[0].boern[0].navn).toBe('#99');
});
```

- [ ] **Step 2: Kør — verificér fejl.** Run: `cd mobile && npx jest redaktionRead -t mapFamilieRows` → FAIL (`mapFamilieRows is not a function`).

- [ ] **Step 3: Implementér i `redaktionRead.ts`:**
```ts
export type FamiliePartner = { personId: string; navn: string; konfidens: string | null; ordinal: number | null };
export type FamilieBarn = { personId: string; navn: string; rolle: string; konfidens: string | null };
export type Union = { familyId: string; type: string; partnere: FamiliePartner[]; boern: FamilieBarn[] };
export type SomBarn = { familyId: string; rolle: string; konfidens: string | null; foraeldre: { personId: string; navn: string }[] };
export type PersonFamilie = { somPartner: Union[]; somBarn: SomBarn[] };
type RawFamRow = { family_id: number; person_id: number; rolle: string; ordinal: number | null; konfidens: string | null };
type RawFamilyMeta = { id: number; type: string | null };
const BARN_ROLLER = ['barn', 'adopteret_barn', 'plejebarn', 'stedbarn'];

export function mapFamilieRows(personId: string, families: RawFamilyMeta[], members: RawFamRow[], model: import('./types').Model | null): PersonFamilie {
  const navnAf = (pid: number) => model?.byId?.[String(pid)]?.visning_navn ?? `#${pid}`;
  const typeAf = new Map(families.map((f) => [String(f.id), f.type ?? '']));
  const byFamily = new Map<string, RawFamRow[]>();
  members.forEach((m) => {
    const k = String(m.family_id);
    (byFamily.get(k) ?? byFamily.set(k, []).get(k)!).push(m);
  });
  const somPartner: Union[] = [];
  const somBarn: SomBarn[] = [];
  byFamily.forEach((rows, familyId) => {
    const mig = rows.find((r) => String(r.person_id) === personId);
    if (!mig) return;
    if (mig.rolle === 'partner') {
      somPartner.push({
        familyId, type: typeAf.get(familyId) ?? '',
        partnere: rows.filter((r) => r.rolle === 'partner' && String(r.person_id) !== personId)
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id), konfidens: r.konfidens, ordinal: r.ordinal })),
        boern: rows.filter((r) => BARN_ROLLER.includes(r.rolle))
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id), rolle: r.rolle, konfidens: r.konfidens })),
      });
    } else if (BARN_ROLLER.includes(mig.rolle)) {
      somBarn.push({
        familyId, rolle: mig.rolle, konfidens: mig.konfidens,
        foraeldre: rows.filter((r) => r.rolle === 'partner')
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id) })),
      });
    }
  });
  return { somPartner, somBarn };
}

export async function fetchPersonFamilie(id: string, model: import('./types').Model | null): Promise<PersonFamilie> {
  if (!supabase) return { somPartner: [], somBarn: [] };
  const sb = supabase;
  const mine = await getAll<{ family_id: number }>(() =>
    sb.from('family_member').select('family_id').eq('person_id', Number(id)));
  const famIds = Array.from(new Set(mine.map((m) => m.family_id)));
  if (!famIds.length) return { somPartner: [], somBarn: [] };
  const members = await getAll<RawFamRow>(() =>
    sb.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens').in('family_id', famIds));
  const families = await getAll<RawFamilyMeta>(() =>
    sb.from('family').select('id,type').in('id', famIds));
  return mapFamilieRows(id, families, members, model);
}
```

- [ ] **Step 4: Kør tests + tsc.** Run: `cd mobile && npx jest redaktionRead && npx tsc --noEmit` → PASS.

- [ ] **Step 5: Commit**
```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(data): fetchPersonFamilie + mapFamilieRows (2C-2b)"
```

---

## Task 4: `eraAdvarsel` + `parseAar` helper

**Files:** Create `mobile/src/data/eraAdvarsel.ts`; Test `mobile/src/data/__tests__/eraAdvarsel.test.ts`.

**Interfaces:**
- Produces: `parseAar(s: string | null): number | null`; `eraAdvarsel(barnFoedselAar: number | null, foraeldre: { foedsel: number | null; doed: number | null }[]): string | null`.

- [ ] **Step 1: Skriv fejlende test** `eraAdvarsel.test.ts`:
```ts
import { eraAdvarsel, parseAar } from '../eraAdvarsel';

test('parseAar: træk første 4-cifrede årstal', () => {
  expect(parseAar('1650')).toBe(1650);
  expect(parseAar('f. 1650 i Kbh')).toBe(1650);
  expect(parseAar(null)).toBeNull();
  expect(parseAar('ukendt')).toBeNull();
});

test('eraAdvarsel: barn født før forælder → advarsel', () => {
  expect(eraAdvarsel(1600, [{ foedsel: 1650, doed: 1700 }])).toMatch(/før forælder/i);
});
test('eraAdvarsel: barn født efter forælders død+margin → advarsel', () => {
  expect(eraAdvarsel(1705, [{ foedsel: 1650, doed: 1700 }])).toMatch(/efter forælders død/i);
});
test('eraAdvarsel: konsistent → null', () => {
  expect(eraAdvarsel(1675, [{ foedsel: 1650, doed: 1700 }])).toBeNull();
});
test('eraAdvarsel: manglende år → null (ingen falsk advarsel)', () => {
  expect(eraAdvarsel(null, [{ foedsel: 1650, doed: 1700 }])).toBeNull();
  expect(eraAdvarsel(1600, [{ foedsel: null, doed: null }])).toBeNull();
});
```

- [ ] **Step 2: Kør — verificér fejl.** Run: `cd mobile && npx jest eraAdvarsel` → FAIL.

- [ ] **Step 3: Implementér `eraAdvarsel.ts`:**
```ts
const DOEDS_MARGIN = 1; // år efter forælders død et barn stadig kan fødes (graviditet)

export function parseAar(s: string | null): number | null {
  if (!s) return null;
  const m = s.match(/\d{4}/);
  return m ? Number(m[0]) : null;
}

export function eraAdvarsel(
  barnFoedselAar: number | null,
  foraeldre: { foedsel: number | null; doed: number | null }[],
): string | null {
  if (barnFoedselAar == null) return null;
  for (const f of foraeldre) {
    if (f.foedsel != null && barnFoedselAar < f.foedsel)
      return 'Barn født før forælder — tjek kilder.';
    if (f.doed != null && barnFoedselAar > f.doed + DOEDS_MARGIN)
      return 'Barn født efter forælders død — tjek kilder.';
  }
  return null;
}
```

- [ ] **Step 4: Kør tests.** Run: `cd mobile && npx jest eraAdvarsel && npx tsc --noEmit` → PASS.

- [ ] **Step 5: Commit**
```bash
git add mobile/src/data/eraAdvarsel.ts mobile/src/data/__tests__/eraAdvarsel.test.ts
git commit -m "feat(data): eraAdvarsel + parseAar helper (2C-2b)"
```

---

## Task 5: `buildRpcCall` — 4 familie-cases + `Change`-felter

**Files:** Modify `mobile/src/data/redaktionWrite.ts`; Test `mobile/src/data/__tests__/redaktionWrite.test.ts`.

**Interfaces:**
- Produces: `Change.art` += `'opretUnion' | 'tilfoejBarn' | 'setFamilieKonfidens' | 'sletFamilieLink'`; `Change.familyId?: string`; `Change.personId?: string`; `Change.rolle?: string`; `Change.konfidens?: string | null`.
  - `opretUnion` → `red_opret_union(p_partner_a, p_partner_b, p_type, p_ordinal)` fra `payload: { partnerA, partnerB, type, ordinal }`.
  - `tilfoejBarn` → `red_tilfoej_barn(p_family_id, p_barn_id, p_rolle, p_konfidens)` fra `payload: { familyId, barnId, rolle, konfidens }`.
  - `setFamilieKonfidens` → `red_set_familie_konfidens(p_family_id, p_person_id, p_rolle, p_konfidens)` fra `familyId/personId/rolle/konfidens`.
  - `sletFamilieLink` → `red_slet_familie_link(p_family_id, p_person_id, p_rolle)` fra `familyId/personId/rolle`.

- [ ] **Step 1: Skriv fejlende tests** i `redaktionWrite.test.ts`:
```ts
test('opretUnion → red_opret_union', () => {
  expect(buildRpcCall({ art: 'opretUnion', subjektType: 'person', subjektId: '7',
    payload: { partnerA: '7', partnerB: '1', type: 'vielse', ordinal: 1 } }))
    .toEqual({ fn: 'red_opret_union', args: { p_partner_a: 7, p_partner_b: 1, p_type: 'vielse', p_ordinal: 1 } });
});
test('tilfoejBarn → red_tilfoej_barn', () => {
  expect(buildRpcCall({ art: 'tilfoejBarn', subjektType: 'person', subjektId: '7',
    payload: { familyId: '10', barnId: '3', rolle: 'barn', konfidens: 'sikker' } }))
    .toEqual({ fn: 'red_tilfoej_barn', args: { p_family_id: 10, p_barn_id: 3, p_rolle: 'barn', p_konfidens: 'sikker' } });
});
test('setFamilieKonfidens → red_set_familie_konfidens (NULL ryd)', () => {
  expect(buildRpcCall({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '1', rolle: 'partner', konfidens: null }))
    .toEqual({ fn: 'red_set_familie_konfidens', args: { p_family_id: 10, p_person_id: 1, p_rolle: 'partner', p_konfidens: null } });
});
test('sletFamilieLink → red_slet_familie_link', () => {
  expect(buildRpcCall({ art: 'sletFamilieLink', subjektType: 'person', subjektId: '7',
    familyId: '10', personId: '3', rolle: 'barn' }))
    .toEqual({ fn: 'red_slet_familie_link', args: { p_family_id: 10, p_person_id: 3, p_rolle: 'barn' } });
});
test('opretUnion uden påkrævet payload → null', () => {
  expect(buildRpcCall({ art: 'opretUnion', subjektType: 'person', subjektId: '7', payload: { partnerA: '7' } as never })).toBeNull();
});
```

- [ ] **Step 2: Kør — verificér fejl.** Run: `cd mobile && npx jest redaktionWrite` → FAIL på de nye.

- [ ] **Step 3: Udvid `Change` + `buildRpcCall`.** Tilføj til `Change.art`-union: `| 'opretUnion' | 'tilfoejBarn' | 'setFamilieKonfidens' | 'sletFamilieLink'`; tilføj felter `familyId?: string; personId?: string; rolle?: string; konfidens?: string | null;`. Indsæt cases før `return null`:
```ts
  if (c.art === 'opretUnion') {
    const p = c.payload || {};
    if (p.partnerA == null || p.partnerB == null || !p.type) return null;
    return { fn: 'red_opret_union', args: {
      p_partner_a: Number(p.partnerA), p_partner_b: Number(p.partnerB), p_type: p.type,
      p_ordinal: p.ordinal != null ? Number(p.ordinal) : null } };
  }
  if (c.art === 'tilfoejBarn') {
    const p = c.payload || {};
    if (p.familyId == null || p.barnId == null) return null;
    return { fn: 'red_tilfoej_barn', args: {
      p_family_id: Number(p.familyId), p_barn_id: Number(p.barnId),
      p_rolle: p.rolle || 'barn', p_konfidens: p.konfidens ?? null } };
  }
  if (c.art === 'setFamilieKonfidens') {
    if (c.familyId == null || c.personId == null || !c.rolle) return null;
    return { fn: 'red_set_familie_konfidens', args: {
      p_family_id: Number(c.familyId), p_person_id: Number(c.personId), p_rolle: c.rolle, p_konfidens: c.konfidens ?? null } };
  }
  if (c.art === 'sletFamilieLink') {
    if (c.familyId == null || c.personId == null || !c.rolle) return null;
    return { fn: 'red_slet_familie_link', args: {
      p_family_id: Number(c.familyId), p_person_id: Number(c.personId), p_rolle: c.rolle } };
  }
```
(Udvid `payload`-typen med `partnerA?/partnerB?/type?/ordinal?/familyId?/barnId?/rolle?/konfidens?` hvis den er typed.)

- [ ] **Step 4: Kør tests + tsc.** Run: `cd mobile && npx jest redaktionWrite && npx tsc --noEmit` → PASS.

- [ ] **Step 5: Commit**
```bash
git add mobile/src/data/redaktionWrite.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(data): buildRpcCall 4 familie-cases (2C-2b)"
```

---

## Task 6: `PersonPicker`-sheet

**Files:** Create `mobile/src/components/redaktion/PersonPicker.tsx`.

**Interfaces:**
- Consumes: `fetchRedaktionPersoner` (redaktionRead), `searchPool` (selectors).
- Produces: `<PersonPicker excludeId={string} onValg={(v:{personId,navn})=>void} onClose={()=>void} />`.

- [ ] **Step 1: Implementér `PersonPicker.tsx`** (følg `EntitetPicker`-mønster — Modal, søgefelt, liste; men kilde = redaktør-personer):
```tsx
import { useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { fetchRedaktionPersoner, type RedPerson } from '../../data/redaktionRead';
import { searchPool } from '../../data/selectors';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, Mono, Serif } from '../Typography';

export function PersonPicker({ excludeId, onValg, onClose }: {
  excludeId?: string;
  onValg: (v: { personId: string; navn: string }) => void;
  onClose: () => void;
}) {
  const [personer, setPersoner] = useState<RedPerson[]>([]);
  const [query, setQuery] = useState('');
  useEffect(() => { fetchRedaktionPersoner().then(setPersoner).catch(() => {}); }, []);
  const pool = useMemo(() => personer.filter((p) => p.id !== excludeId)
    .map((p) => ({ id: p.id, name: p.navn, years: p.aar, born: p.born })), [personer, excludeId]);
  const { matches } = useMemo(() => searchPool(pool, { query, sort: 'alpha', activeLetter: null }), [pool, query]);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Vælg person</Serif>
        <TextInput style={styles.input} placeholder="Søg navn…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoFocus autoCorrect={false} />
        <ScrollView style={{ maxHeight: 360 }} keyboardShouldPersistTaps="handled">
          {matches.length === 0 ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body> : null}
          {matches.map((p) => (
            <Pressable key={p.id} style={styles.row}
              onPress={() => { onValg({ personId: p.id, navn: p.name }); onClose(); }}>
              <Body size={14}>{p.name}</Body>
              {p.years ? <Mono size={9} color={Colors.textMuted}>{p.years}</Mono> : null}
            </Pressable>
          ))}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet, padding: 20, paddingBottom: 36 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field,
    paddingHorizontal: 12, paddingVertical: 9, marginBottom: 8, fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  row: { paddingVertical: 9, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: Border.light },
});
```
VERIFICÉR mod koden: `RedPerson`-felter (`id/navn/aar/born`), `searchPool`-signatur + retur (`{matches}`), token-nøgler — juster hvis de afviger.

- [ ] **Step 2: Verificér + commit.** Run: `cd mobile && npx tsc --noEmit` → rent.
```bash
git add mobile/src/components/redaktion/PersonPicker.tsx
git commit -m "feat(redaktion): PersonPicker-sheet (vælg redaktør-person)"
```

---

## Task 7: Editor — redigerbar familie-sektion

**Files:** Modify `mobile/src/app/redaktion/person/[id].tsx`.

**Interfaces:**
- Consumes: `fetchPersonFamilie`/`PersonFamilie` (Task 3); `eraAdvarsel`/`parseAar` (Task 4); `buildRpcCall`-arter (Task 5); `PersonPicker` (Task 6); eksisterende `setPending`/SkrivePreviewSheet + `redaktionModel`.

- [ ] **Step 1: Hent familie + gør sektionen redigerbar.**
- Imports: `import { fetchPersonFamilie, type PersonFamilie } from '../../../data/redaktionRead';`, `import { eraAdvarsel, parseAar } from '../../../data/eraAdvarsel';`, `import { PersonPicker } from '../../../components/redaktion/PersonPicker';`.
- State + fetch (re-fetch efter writes):
```tsx
  const [familie, setFamilie] = useState<PersonFamilie>({ somPartner: [], somBarn: [] });
  useEffect(() => { if (id) fetchPersonFamilie(id, redaktionModel).then(setFamilie).catch(() => {}); }, [id, redaktionModel]);
  // Add-flow state:
  const [partnerPicker, setPartnerPicker] = useState(false);
  const [barnPickerFam, setBarnPickerFam] = useState<string | null>(null);
  const [unionScratch, setUnionScratch] = useState<{ personId: string; navn: string } | null>(null);
  const [barnScratch, setBarnScratch] = useState<{ familyId: string; personId: string; navn: string } | null>(null);
```
- I `onApplied` (SkrivePreviewSheet): tilføj `if (id) fetchPersonFamilie(id, redaktionModel).then(setFamilie).catch(() => {});`.
- ERSTAT den read-only FORÆLDRE/ÆGTEFÆLLER/BØRN-blok (linje ~356-365, `parentsOf`/`spousesOf`/`childrenByMarriage`) med redigerbar visning drevet af `familie`. Behold `PersonRad`-mønstret til navne, tilføj konfidens-dropdown + slet + tilføj-knapper. KILDER + HVERV/GODSER (2C-2a) urørt.
```tsx
              {/* ÆGTEFÆLLER + BØRN (redigerbart, pr. union) */}
              {familie.somPartner.map((u) => (
                <View key={u.familyId}>
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>ÆGTEFÆLLE ({u.type})</Mono>
                  {u.partnere.map((pt) => (
                    <View key={pt.personId} style={editorStyles.relEditRad}>
                      <View style={{ flex: 1 }}><Body size={13}>{pt.navn}</Body></View>
                      <KonfidensVaelger vaerdi={pt.konfidens}
                        onVael={(k) => setPending({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: pt.personId, rolle: 'partner', konfidens: k })} />
                      <Pressable onPress={() => setPending({ art: 'sletFamilieLink', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: pt.personId, rolle: 'partner' })}>
                        <Mono size={9} color={Colors.danger}>🗑</Mono></Pressable>
                    </View>
                  ))}
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>BØRN</Mono>
                  {u.boern.map((b) => (
                    <View key={b.personId} style={editorStyles.relEditRad}>
                      <View style={{ flex: 1 }}><Body size={13}>{b.navn}{b.rolle !== 'barn' ? ` · ${b.rolle}` : ''}</Body></View>
                      <KonfidensVaelger vaerdi={b.konfidens}
                        onVael={(k) => setPending({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: b.personId, rolle: b.rolle, konfidens: k })} />
                      <Pressable onPress={() => setPending({ art: 'sletFamilieLink', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: b.personId, rolle: b.rolle })}>
                        <Mono size={9} color={Colors.danger}>🗑</Mono></Pressable>
                    </View>
                  ))}
                  <Pressable style={{ paddingVertical: 6 }} onPress={() => setBarnPickerFam(u.familyId)}>
                    <Mono size={9} color={Colors.bordeaux}>+ Tilføj barn</Mono></Pressable>
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => setPartnerPicker(true)}>
                <Mono size={9} color={Colors.bordeaux}>+ Tilføj partner (ny union)</Mono></Pressable>

              {/* FORÆLDRE (somBarn) — forældre read-only; konfidens+slet redigerbart */}
              {familie.somBarn.map((sb) => (
                <View key={sb.familyId}>
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>FORÆLDRE{sb.rolle !== 'barn' ? ` · ${sb.rolle}` : ''}</Mono>
                  {sb.foraeldre.map((f) => <PersonRad key={f.personId} pid={f.personId} navn={f.navn} />)}
                  <View style={editorStyles.relEditRad}>
                    <KonfidensVaelger vaerdi={sb.konfidens}
                      onVael={(k) => setPending({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: id!, familyId: sb.familyId, personId: id!, rolle: sb.rolle, konfidens: k })} />
                    <Pressable onPress={() => setPending({ art: 'sletFamilieLink', subjektType: 'person', subjektId: id!, familyId: sb.familyId, personId: id!, rolle: sb.rolle })}>
                      <Mono size={9} color={Colors.danger}>🗑 afkobl forælder</Mono></Pressable>
                  </View>
                </View>
              ))}
```
- Efter ScrollView (ved siden af de øvrige sheets): pickers + scratch-ark:
```tsx
      {partnerPicker ? (
        <PersonPicker excludeId={id} onClose={() => setPartnerPicker(false)}
          onValg={(v) => setUnionScratch(v)} />
      ) : null}
      {unionScratch ? (
        <UnionTypeSheet partner={unionScratch} onClose={() => setUnionScratch(null)}
          onGem={(type, ordinal) => { setPending({ art: 'opretUnion', subjektType: 'person', subjektId: id!,
            payload: { partnerA: id, partnerB: unionScratch.personId, type, ordinal } }); setUnionScratch(null); }} />
      ) : null}
      {barnPickerFam ? (
        <PersonPicker excludeId={id} onClose={() => setBarnPickerFam(null)}
          onValg={(v) => { setBarnScratch({ familyId: barnPickerFam, personId: v.personId, navn: v.navn }); setBarnPickerFam(null); }} />
      ) : null}
      {barnScratch ? (
        <BarnSheet scratch={barnScratch}
          advarsel={eraAdvarsel(parseAar(redaktionModel?.byId?.[barnScratch.personId]?.visning_foedt ?? null),
            (familie.somPartner.find((u) => u.familyId === barnScratch.familyId)?.partnere ?? []).map((pt) => ({
              foedsel: parseAar(redaktionModel?.byId?.[pt.personId]?.visning_foedt ?? null),
              doed: parseAar(redaktionModel?.byId?.[pt.personId]?.visning_doed ?? null) })))}
          onClose={() => setBarnScratch(null)}
          onGem={(rolle, konfidens) => { setPending({ art: 'tilfoejBarn', subjektType: 'person', subjektId: id!,
            payload: { familyId: barnScratch.familyId, barnId: barnScratch.personId, rolle, konfidens } }); setBarnScratch(null); }} />
      ) : null}
```
- Tilføj inline-helpers i filen: `KonfidensVaelger` (lille række af 4 valg + "ryd" → `onVael(null)`); `UnionTypeSheet` (Modal: 3 type-knapper + ordinal-TextInput + Gem); `BarnSheet` (Modal: 4 barn-rolle-knapper + konfidens-valg + valgfri `advarsel`-tekst i bordeaux + Gem). Følg SkrivePreviewSheet's Modal/backdrop/token-mønster. Tilføj styles `relEditRad` (genbrug fra 2C-2a hvis til stede).

- [ ] **Step 2: Verificér + commit.** Run: `cd mobile && npx tsc --noEmit && npx jest` → tsc rent, jest grøn.
Manuel e2e kræver deploy (Task 8) — notér sprunget.
```bash
git add "mobile/src/app/redaktion/person/[id].tsx"
git commit -m "feat(redaktion): redigerbar familie-sektion (partner+barn+konfidens) (2C-2b)"
```

---

## Task 8: Integration — deploy (controller-gate) + rollback-tests + docs

**Files:** Modify `docs/changelog.md`, `docs/decisions.md`.

- [ ] **Step 1: Fuld jest + tsc.** Run: `cd mobile && npx jest && npx tsc --noEmit` → alle grønne.

- [ ] **Step 2: Deploy de 4 RPC'er til prod (CONTROLLER-GATE).** Kun controller, bruger-OK + backup (R/RPostgres, `CREATE OR REPLACE`). Verificér eksistens + rolle-gating.

- [ ] **Step 3: Rollback-tests mod prod (nul mutation, `set local request.jwt.claims` redaktion, `dbRollback`):**
  - `red_opret_union`: opretter ny family + 2 partner-links; samme par igen → NY family (ingen kollaps); partner_a==b → RAISE; ugyldig type → RAISE; ukendt person → RAISE.
  - `red_tilfoej_barn`: tilføjer barn-link; PK-dublet → no-op; barn==partner-i-family → RAISE; **cyklus** (tilføj en ane som barn) → RAISE; ugyldig rolle/konfidens → RAISE.
  - `red_set_familie_konfidens`: UPDATE rammer rigtige række; ukendt link → RAISE; ugyldig konfidens → RAISE.
  - `red_slet_familie_link`: sletter KUN family_member; **verificér family-rækken + dens facts/notes STADIG findes efter slet af sidste medlem** (Codex H1).

- [ ] **Step 4: Manuel e2e (web).** Tilføj partner → ny union vises; tilføj barn (m. era-advarsel hvis datoer skæve); ret konfidens; afkobl forælder. Notér bestået/sprunget.

- [ ] **Step 5: Changelog + decisions + commit.**
```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: plan 2C-2b — familie-redigering changelog + decisions"
```

---

## Self-Review

**Spec coverage:** RPC'er §Arkitektur → Task 1+2. fetchPersonFamilie §Fetch → Task 3. eraAdvarsel §Era → Task 4. buildRpcCall §Write-path → Task 5. PersonPicker §Komponenter → Task 6. Redigerbar sektion §Komponenter → Task 7. Test §Test + deploy → Task 8. Codex H1/H2/H3 → Task 1 (ingen family-slet, ingen dedup) + Task 2 (cyklus-guard) + Task 8 (rollback-tests for alle tre). Non-goals (family-entitets-slet, identitet, flyt-barn, bred cache, type/ordinal-edit) IKKE planlagt — korrekt.

**Placeholder-scan:** Inline-helpers i Task 7 (`KonfidensVaelger`/`UnionTypeSheet`/`BarnSheet`) er beskrevet m. præcis adfærd + Modal-mønster-reference; eneste skitse-punkt, resten komplet kode. Acceptabelt (parallelt til 2C-2a's RelTilfoejSheet).

**Type-konsistens:** `Change`-felter (familyId/personId/rolle/konfidens/payload) + arter (Task 5) brugt i Task 7. `PersonFamilie`/`Union`/`SomBarn`-felter (Task 3) brugt i Task 7. RPC-param-navne (`p_partner_a/b`, `p_type`, `p_ordinal`, `p_family_id`, `p_barn_id`, `p_person_id`, `p_rolle`, `p_konfidens`) matcher schema (Task 1/2) ↔ buildRpcCall (Task 5). `PersonPicker`-props (Task 6) ↔ kald (Task 7). `eraAdvarsel`-signatur (Task 4) ↔ kald (Task 7).
