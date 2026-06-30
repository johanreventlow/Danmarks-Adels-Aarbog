# Plan 2C-2a — Sektion-relationer (rediger hverv/godser) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør hverv/godser (relation-tabellen) redigerbare i person-editoren — tilføj (valideret) og slet (FK-ordnet) person↔organisation/estate-relationer.

**Architecture:** To nye SECURITY DEFINER RPC'er: `red_slet_relation` (FK-ordnet cascade af relation-evidens) + `red_tilfoej_relation` (objekt-validering + dup-guard). En egen per-person `fetchPersonRelationer` (pagineret, med relation-id'er) driver en redigerbar relations-sektion i editoren; entitets-picker vælger org/gods fra 2C-1's redaktionAux-lister. Familie + kilder forbliver read-only.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand, `@supabase/supabase-js`, Jest, PostgreSQL/Supabase.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-28-plan2c2a-sektion-relationer-design.md` (autoritativ).
- **Branch:** opret feature-branch fra `main` (`feat/plan2c2a-sektion-relationer`); ingen merge/push uden eksplicit godkendelse.
- **FK-ordnet slet (KRITISK):** relationer har 955 assertion+conclusion (`target_type='relation'`); `red_slet_relation` SKAL rydde citation→conclusion→assertion→note→relation (ALDRIG flad DELETE). Spejler `red_slet_person`.
- **Valideret tilføj:** `red_tilfoej_relation` validerer `objekt_type IN ('organisation','estate')` + objekt-eksistens + dup-guard (returnér eksisterende ved samme subjekt/objekt/rolle). `max(id)+1`-concurrency = projekt-bredt PoC-debt (uændret).
- **Pagination:** `fetchPersonRelationer` bruger `getAll`/`.range()` (PostgREST 1000-cap).
- **Fejl kastes, aldrig tom-som-clean** (cycle 03 NEW1).
- **Read-only bevares:** familie (family_member) + kilder (external_id) forbliver read-only; KUN relation-baserede hverv/godser bliver redigerbare.
- **Egen fetch:** relations-sektionen bruger `fetchPersonRelationer` (re-fetch efter write) — IKKE redaktionAux (som er stale). Bredere aux-invalidering = follow-up (uden for 2C-2a).
- **DB-deploy = controller-gate** (prod, bruger-OK + backup), deferred til Task 6 (jest mocker supabase; app-tasks kræver ikke live-deploy).
- **Tokens/Typography**; ingen rå hex (#fff/rgba OK).
- **Test-niveau:** RPC'er = SQL-rollback-test; logik (fetch/write) = TDD/jest; skærme = tsc + manuel.
- Ingen Claude-attribution i commits. Conventional Commits, dansk.

---

## File Structure

**Ændrede:**
- `schema.sql`, `db-migrations.sql` — `red_slet_relation` + `red_tilfoej_relation`.
- `mobile/src/data/redaktionRead.ts` — `PersonRelation`, `mapRelationRow`, `fetchPersonRelationer`.
- `mobile/src/data/redaktionWrite.ts` — `Change.relationId`/arter `sletRelation`/`tilfoejRelation` + cases.
- `mobile/src/app/redaktion/person/[id].tsx` — redigerbar relations-sektion.

**Nye:**
- `mobile/src/components/redaktion/EntitetPicker.tsx` — søgbar entitets-vælger-sheet.

---

## Task 1: DB — `red_slet_relation` (FK-ordnet) + `red_tilfoej_relation` (valideret)

**Files:**
- Modify: `schema.sql` (efter `red_relation`), `db-migrations.sql` (idempotent blok)

**Interfaces:**
- Produces: `red_slet_relation(p_relation_id bigint) RETURNS void`; `red_tilfoej_relation(p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL) RETURNS bigint`.

- [ ] **Step 1: Tilføj begge funktioner i `schema.sql`**

Indsæt efter `red_relation`-funktionen:
```sql
-- FK-ORDNET slet af en relation + dens evidens (relationer har 955 assertion+conclusion med
-- target_type='relation' UDEN FK → flad DELETE forældreløser dem). Spejler red_slet_person.
CREATE OR REPLACE FUNCTION red_slet_relation(p_relation_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $$;

-- Valideret + idempotent tilføj af person↔org/estate-relation (erstatter rå red_relation for UI).
CREATE OR REPLACE FUNCTION red_tilfoej_relation(
  p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint; v_findes boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_objekt_type NOT IN ('organisation','estate') THEN RAISE EXCEPTION 'Ugyldig objekt_type %', p_objekt_type; END IF;
  IF p_objekt_type='organisation' THEN SELECT EXISTS(SELECT 1 FROM organisation WHERE id=p_objekt_id) INTO v_findes;
  ELSE SELECT EXISTS(SELECT 1 FROM estate WHERE id=p_objekt_id) INTO v_findes; END IF;
  IF NOT v_findes THEN RAISE EXCEPTION 'Objekt %/% findes ikke', p_objekt_type, p_objekt_id; END IF;
  SELECT id INTO v_id FROM relation WHERE subjekt_type='person' AND subjekt_id=p_subjekt_id
    AND objekt_type=p_objekt_type AND objekt_id=p_objekt_id AND coalesce(rolle,'')=coalesce(p_rolle,'') LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $$;
```

- [ ] **Step 2: Spejl idempotent i `db-migrations.sql`**

Tilføj de SAMME to `CREATE OR REPLACE FUNCTION`-blokke i bunden af `db-migrations.sql` under en dateret kommentar (`-- 2026-06-28: 2C-2a relation-RPC'er`). Begge er `CREATE OR REPLACE` → idempotente. (Grant arver `red_*`-loopet i `db-rls.sql`; intet ekstra grant nødvendigt.)

- [ ] **Step 3: Commit (deploy deferred til Task 6)**

```bash
git add schema.sql db-migrations.sql
git commit -m "feat(db): red_slet_relation (FK-ordnet) + red_tilfoej_relation (valideret) (2C-2a)"
```
(Live prod-deploy = controller-gate i Task 6; app-tasks 2-5 kræver ikke live-deploy — jest mocker supabase.)

---

## Task 2: `fetchPersonRelationer` + `mapRelationRow`

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts`
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts`

**Interfaces:**
- Consumes: `getAll` (load.ts), `supabase`, `Aux` (types).
- Produces:
  - `type PersonRelation = { relationId: number; art: 'hverv'|'gods'|'event'; objektType: string; objektId: string; navn: string; rolle: string; periode: string }`
  - `type RawRelRow = { id: number; objekt_type: string; objekt_id: number; rolle: string|null; periode_raw: string|null }`
  - `mapRelationRow(rows: RawRelRow[], aux: import('./types').Aux | null): PersonRelation[]` (ren)
  - `async fetchPersonRelationer(id: string, aux): Promise<PersonRelation[]>`

- [ ] **Step 1: Skriv fejlende test for `mapRelationRow`**

Tilføj i `redaktionRead.test.ts`:
```ts
import { mapRelationRow } from '../redaktionRead';

const AUX = { orgListe: [{ id: '1', navn: 'Hæren', slags: '' }], godsListe: [{ id: '5', navn: 'Brahetrolleborg', slags: '', ownerCount: 1 }] } as never;

test('mapRelationRow: art + navn-opslag fra aux', () => {
  const rows = [
    { id: 100, objekt_type: 'organisation', objekt_id: 1, rolle: 'oberst', periode_raw: '1700–1710' },
    { id: 101, objekt_type: 'estate', objekt_id: 5, rolle: 'ejer', periode_raw: null },
    { id: 102, objekt_type: 'historical_event', objekt_id: 9, rolle: 'deltager', periode_raw: null },
  ];
  expect(mapRelationRow(rows as never, AUX)).toEqual([
    { relationId: 100, art: 'hverv', objektType: 'organisation', objektId: '1', navn: 'Hæren', rolle: 'oberst', periode: '1700–1710' },
    { relationId: 101, art: 'gods', objektType: 'estate', objektId: '5', navn: 'Brahetrolleborg', rolle: 'ejer', periode: '' },
    { relationId: 102, art: 'event', objektType: 'historical_event', objektId: '9', navn: 'Begivenhed #9', rolle: 'deltager', periode: '' },
  ]);
});

test('mapRelationRow: ukendt objekt-id → fallback-navn', () => {
  expect(mapRelationRow([{ id: 1, objekt_type: 'estate', objekt_id: 99, rolle: null, periode_raw: null }] as never, AUX)[0].navn)
    .toBe('#99');
});
```

- [ ] **Step 2: Kør — verificér fejl**

Run: `cd mobile && npx jest redaktionRead -t "mapRelationRow"`
Expected: FAIL — `mapRelationRow is not a function`.

- [ ] **Step 3: Implementér i `redaktionRead.ts`**

Tilføj (importér `getAll` fra `./load` hvis ikke til stede — den er det fra plan 2A):
```ts
export type PersonRelation = {
  relationId: number; art: 'hverv' | 'gods' | 'event';
  objektType: string; objektId: string; navn: string; rolle: string; periode: string;
};
type RawRelRow = { id: number; objekt_type: string; objekt_id: number; rolle: string | null; periode_raw: string | null };

export function mapRelationRow(rows: RawRelRow[], aux: import('./types').Aux | null): PersonRelation[] {
  const orgNavn = new Map((aux?.orgListe ?? []).map((o) => [o.id, o.navn]));
  const godsNavn = new Map((aux?.godsListe ?? []).map((g) => [g.id, g.navn]));
  return rows.map((r) => {
    const objektId = String(r.objekt_id);
    let art: PersonRelation['art'] = 'event';
    let navn = `Begivenhed #${objektId}`;
    if (r.objekt_type === 'organisation') { art = 'hverv'; navn = orgNavn.get(objektId) ?? `#${objektId}`; }
    else if (r.objekt_type === 'estate') { art = 'gods'; navn = godsNavn.get(objektId) ?? `#${objektId}`; }
    return { relationId: r.id, art, objektType: r.objekt_type, objektId, navn, rolle: r.rolle ?? '', periode: r.periode_raw ?? '' };
  });
}

export async function fetchPersonRelationer(id: string, aux: import('./types').Aux | null): Promise<PersonRelation[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<RawRelRow>(() =>
    sb.from('relation').select('id,objekt_type,objekt_id,rolle,periode_raw')
      .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
      .in('objekt_type', ['organisation', 'estate', 'historical_event']).order('id'));
  return mapRelationRow(rows, aux);
}
```

- [ ] **Step 4: Kør tests + tsc**

Run: `cd mobile && npx jest redaktionRead && npx tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(data): fetchPersonRelationer (pagineret) + mapRelationRow (2C-2a)"
```

---

## Task 3: `buildRpcCall` — `sletRelation` + `tilfoejRelation`

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts`
- Test: `mobile/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces:**
- Produces: `Change.art` += `'sletRelation' | 'tilfoejRelation'`; `Change.relationId?: string`. cases:
  - `sletRelation` → `red_slet_relation(p_relation_id)`
  - `tilfoejRelation` → `red_tilfoej_relation(p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)` fra payload.

- [ ] **Step 1: Skriv fejlende tests**

Tilføj i `redaktionWrite.test.ts`:
```ts
test('sletRelation → red_slet_relation', () => {
  expect(buildRpcCall({ art: 'sletRelation', subjektType: 'person', subjektId: '1', relationId: '100' }))
    .toEqual({ fn: 'red_slet_relation', args: { p_relation_id: 100 } });
});

test('tilfoejRelation → red_tilfoej_relation fra payload', () => {
  expect(buildRpcCall({ art: 'tilfoejRelation', subjektType: 'person', subjektId: '7',
    payload: { objektType: 'estate', objektId: '5', rolle: 'ejer', periodeRaw: '1700' } }))
    .toEqual({ fn: 'red_tilfoej_relation',
      args: { p_subjekt_id: 7, p_objekt_type: 'estate', p_objekt_id: 5, p_rolle: 'ejer', p_periode_raw: '1700' } });
});

test('sletRelation uden relationId → null', () => {
  expect(buildRpcCall({ art: 'sletRelation', subjektType: 'person', subjektId: '1' })).toBeNull();
});
```

- [ ] **Step 2: Kør — verificér fejl**

Run: `cd mobile && npx jest redaktionWrite`
Expected: FAIL på de nye.

- [ ] **Step 3: Udvid `Change` + `buildRpcCall`**

Tilføj til `Change.art`-unionen: `| 'sletRelation' | 'tilfoejRelation'` og `relationId?: string` til `Change`. Indsæt cases i `buildRpcCall` (før `return null`):
```ts
  if (c.art === 'sletRelation') {
    const rid = c.relationId != null ? Number(c.relationId) : null;
    if (rid == null) return null;
    return { fn: 'red_slet_relation', args: { p_relation_id: rid } };
  }
  if (c.art === 'tilfoejRelation') {
    const p = c.payload || {};
    return { fn: 'red_tilfoej_relation', args: {
      p_subjekt_id: sid, p_objekt_type: p.objektType, p_objekt_id: Number(p.objektId),
      p_rolle: p.rolle, p_periode_raw: p.periodeRaw ?? null } };
  }
```

- [ ] **Step 4: Kør tests + tsc**

Run: `cd mobile && npx jest redaktionWrite && npx tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionWrite.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(data): buildRpcCall sletRelation + tilfoejRelation (2C-2a)"
```

---

## Task 4: `EntitetPicker`-sheet

**Files:**
- Create: `mobile/src/components/redaktion/EntitetPicker.tsx`

**Interfaces:**
- Consumes: `redaktionAux` (orgListe/godsListe).
- Produces: `<EntitetPicker type="organisation"|"estate" onValg={(v:{objektType,objektId,navn})=>void} onClose={()=>void} />`.

- [ ] **Step 1: Implementér picker-sheet**

`mobile/src/components/redaktion/EntitetPicker.tsx`:
```tsx
import { useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, Mono, Serif } from '../Typography';

export function EntitetPicker({ type, onValg, onClose }: {
  type: 'organisation' | 'estate';
  onValg: (v: { objektType: string; objektId: string; navn: string }) => void;
  onClose: () => void;
}) {
  const aux = useStore((s) => s.redaktionAux);
  const [query, setQuery] = useState('');
  const liste = useMemo(() => {
    const base = type === 'organisation'
      ? (aux?.orgListe ?? []).map((o) => ({ id: o.id, navn: o.navn }))
      : (aux?.godsListe ?? []).map((g) => ({ id: g.id, navn: g.navn }));
    const q = query.trim().toLowerCase();
    return q ? base.filter((x) => x.navn.toLowerCase().includes(q)) : base;
  }, [aux, type, query]);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>{type === 'organisation' ? 'Vælg organisation' : 'Vælg gods'}</Serif>
        <TextInput style={styles.input} placeholder="Søg…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoFocus />
        <ScrollView style={{ maxHeight: 320 }}>
          {liste.length === 0 ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body> : null}
          {liste.map((x) => (
            <Pressable key={x.id} style={styles.row}
              onPress={() => { onValg({ objektType: type, objektId: x.id, navn: x.navn }); onClose(); }}>
              <Body size={14}>{x.navn}</Body>
              <Mono size={8} color={Colors.textMuted}>#{x.id}</Mono>
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

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
```bash
git add mobile/src/components/redaktion/EntitetPicker.tsx
git commit -m "feat(redaktion): EntitetPicker-sheet (vælg org/gods fra redaktionAux)"
```

---

## Task 5: Editor — redigerbar relations-sektion

**Files:**
- Modify: `mobile/src/app/redaktion/person/[id].tsx`

**Interfaces:**
- Consumes: `fetchPersonRelationer`/`PersonRelation` (Task 2); `EntitetPicker` (Task 4); `redaktionAux` (allerede i editor); `pending`/SkrivePreviewSheet-mekanisme (2B).

- [ ] **Step 1: Hent relationer + gør hverv/godser redigerbare**

I `person/[id].tsx`:
- Tilføj imports: `import { fetchPersonRelationer, type PersonRelation } from '../../../data/redaktionRead';` og `import { EntitetPicker } from '../../../components/redaktion/EntitetPicker';`.
- Tilføj state + fetch (re-fetch efter write):
```tsx
  const [relationer, setRelationer] = useState<PersonRelation[]>([]);
  const [pickerType, setPickerType] = useState<'organisation' | 'estate' | null>(null);
  const [relScratch, setRelScratch] = useState<{ objektType: string; objektId: string; navn: string; rolle: string; periode: string } | null>(null);
  useEffect(() => {
    if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});
  }, [id, redaktionAux]);
```
- I `onApplied` (SkrivePreviewSheet), tilføj re-fetch: `if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});` (ved siden af de eksisterende re-fetches).
- I sektion-blokken: erstat de read-only `off`/`god`-render (HVERV/GODSER fra `redaktionAux.officesBy/estatesBy`) med redigerbare rækker drevet af `relationer` (filtreret på art). Behold FORÆLDRE/ÆGTEFÆLLER/BØRN + KILDER read-only.
```tsx
              {/* HVERV (redigerbart) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>HVERV</Mono>
              {relationer.filter((r) => r.art === 'hverv' || r.art === 'event').map((r) => (
                <View key={r.relationId} style={editorStyles.relEditRad}>
                  <View style={{ flex: 1 }}>
                    <Body size={13}>{r.navn}{r.rolle ? ` · ${r.rolle}` : ''}</Body>
                    {r.periode ? <Mono size={9} color={Colors.textMuted}>{r.periode}</Mono> : null}
                  </View>
                  <Pressable onPress={() => setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: String(r.relationId) })}>
                    <Mono size={9} color={Colors.danger}>🗑</Mono>
                  </Pressable>
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => { setPickerType('organisation'); setRelScratch(null); }}>
                <Mono size={9} color={Colors.bordeaux}>+ Tilføj hverv</Mono>
              </Pressable>

              {/* GODSER (redigerbart) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>GODSER</Mono>
              {relationer.filter((r) => r.art === 'gods').map((r) => (
                <View key={r.relationId} style={editorStyles.relEditRad}>
                  <View style={{ flex: 1 }}>
                    <Body size={13}>{r.navn}{r.rolle ? ` · ${r.rolle}` : ''}</Body>
                    {r.periode ? <Mono size={9} color={Colors.textMuted}>{r.periode}</Mono> : null}
                  </View>
                  <Pressable onPress={() => setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: String(r.relationId) })}>
                    <Mono size={9} color={Colors.danger}>🗑</Mono>
                  </Pressable>
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => { setPickerType('estate'); setRelScratch(null); }}>
                <Mono size={9} color={Colors.bordeaux}>+ Tilføj gods</Mono>
              </Pressable>
```
- Efter ScrollView (ved siden af SkrivePreviewSheet/SletBekraeftSheet), tilføj picker + tilføj-formular:
```tsx
      {pickerType ? (
        <EntitetPicker type={pickerType}
          onClose={() => setPickerType(null)}
          onValg={(v) => setRelScratch({ ...v, rolle: '', periode: '' })} />
      ) : null}
      {relScratch ? (
        <RelTilfoejSheet scratch={relScratch} onClose={() => setRelScratch(null)}
          onGem={(rolle, periode) => {
            setPending({ art: 'tilfoejRelation', subjektType: 'person', subjektId: id!,
              payload: { objektType: relScratch.objektType, objektId: relScratch.objektId, rolle, periodeRaw: periode || null } });
            setRelScratch(null);
          }} />
      ) : null}
```
- Tilføj en lille inline `RelTilfoejSheet`-helper i filen (Modal: viser valgt navn + to TextInput rolle/periode + Gem/Annullér). Brug samme Modal-mønster som SkrivePreviewSheet.
- Tilføj styles `relEditRad: { flexDirection: 'row', alignItems: 'center', paddingVertical: 5 }`.

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: ingen tsc-fejl; jest grøn.
Manuel (kræver live-deploy, Task 6): notér sprunget indtil deploy.
```bash
git add "mobile/src/app/redaktion/person/[id].tsx"
git commit -m "feat(redaktion): redigerbar relations-sektion (tilføj/slet hverv+gods)"
```

---

## Task 6: Integration — deploy RPC'er (controller-gate) + rollback-test + docs

**Files:**
- Modify: `docs/changelog.md`, `docs/decisions.md`

- [ ] **Step 1: Fuld jest + tsc**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: alle grønne (eksisterende + mapRelationRow + buildRpcCall-relations-cases), tsc rent.

- [ ] **Step 2: Deploy RPC'erne til prod (CONTROLLER-GATE)**

Kun controller, med bruger-OK + backup (samme model som tidligere DDL): kør de to
`CREATE OR REPLACE FUNCTION` mod prod via R/RPostgres. Verificér: `red_slet_relation`/`red_tilfoej_relation`
eksisterer; rolle-gating (anon → P0001).

- [ ] **Step 3: Rollback-test mod prod (FK-ordnet slet)**

R-script i transaktion (`set local request.jwt.claims` redaktion, `dbRollback` til sidst — nul mutation):
verificér at `red_slet_relation` på en relation med evidens sletter citation/conclusion/assertion FØR
relation (ingen forældreløse); `red_tilfoej_relation` validerer objekt-eksistens + dup-guard (samme
subjekt/objekt/rolle returnerer eksisterende id, ingen dublet).

- [ ] **Step 4: Manuel e2e (web)**

`/redaktion/person/<id>` → LIVE → "+ Tilføj gods" → vælg fra picker + rolle/periode → vises → 🗑 slet → forsvinder. Notér bestået/sprunget.

- [ ] **Step 5: Changelog + decisions + commit**

```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: plan 2C-2a — sektion-relationer changelog + decisions"
```

---

## Self-Review

**Spec coverage:**
- §2a red_slet_relation FK-ordnet → Task 1. §2b red_tilfoej_relation valideret → Task 1. §3 fetchPersonRelationer pagineret → Task 2. §4 buildRpcCall-cases → Task 3. §5 redigerbar sektion → Task 5. §6 EntitetPicker → Task 4. §7 test (rollback + jest + manuel) → Task 1/2/3/6. Alle dækket.
- **Non-goals** (in-place edit, familie, event-tilføj, kilder, generisk editor, bredere cache) IKKE planlagt — korrekt.

**Placeholder-scan:** `RelTilfoejSheet`-helper i Task 5 Step 1 beskrevet (Modal m. navn + 2 TextInput + Gem/Annullér) — implementeren bygger en simpel inline-Modal som SkrivePreviewSheet-mønsteret; eneste skitse-punkt, resten komplet kode.

**Type-konsistens:** `Change.relationId`/arter `sletRelation`/`tilfoejRelation` (Task 3) → brugt i Task 5. `PersonRelation`/`fetchPersonRelationer(id, aux)` (Task 2) → Task 5. `EntitetPicker`-props (Task 4) → Task 5. RPC-param-navne (`p_relation_id`, `p_subjekt_id`, `p_objekt_type/id`, `p_rolle`, `p_periode_raw`) matcher schema.sql (Task 1) ↔ buildRpcCall (Task 3).
