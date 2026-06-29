# Opret-ny-entitet (redaktør-app) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redaktøren kan oprette en ny person/gods/kilde/organisation fra "Tilføj"-fanen gennem det eksisterende dry-run→live-gate, og fortsætte i editoren (person) hhv. se den nye række i listen (øvrige).

**Architecture:** 4 nye komposite SECURITY DEFINER opret-RPC'er (mønster fra `red_opret_union`); nye `Change`-arter + `buildRpcCall`-cases; ny `OpretSheet` (grid + type-forms) der bygger et `Change` og routes gennem `SkrivePreviewSheet`. To enabler-fixes: B1 `loadRedaktionModel(force)` (så post-create reload ikke er no-op), B2 `SkrivePreviewSheet.onApplied(result)` (så ny id når frem til navigation).

**Tech Stack:** PostgreSQL/Supabase (plpgsql RPC'er), TypeScript, React Native / Expo Router, Zustand, Jest.

## Global Constraints

- **Sprog:** dansk i UI-tekst, kommentarer, commits.
- **id-allokering:** `coalesce(max(id),0)+1` (husstil; matcher `red_upsert_fakta`/`red_opret_union`). Race accepteret i single-editor PoC.
- **Rolle-gate:** hver skrive-RPC starter med `IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;`.
- **Påkrævet-felt:** afvis NULL OG whitespace med `nullif(btrim(x),'') IS NULL`.
- **Privatliv:** ny person defaulter til `privat=true` (RLS: `levende=false AND privat=false` = anon-læsbar).
- **Kontrolleret vokab i UI:** hardcodede const-arrays (husstil, jf. `KONFIDENS_VAERDIER`/`UNION_TYPER`), ingen vocab-fetch.
- **Write-sti:** ét `Change` → ét RPC-kald; al skrivning gennem `SkrivePreviewSheet` (dry-run default ON i store).
- **Ingen attribution-footer i commits.** Conventional Commits, dansk beskrivelse.
- **RPC'er i BÅDE `schema.sql` og `db-migrations.sql`** (idempotent `CREATE OR REPLACE`).

---

### Task 1: DB — 4 opret-RPC'er + grants

**Files:**
- Modify: `db-migrations.sql` (tilføj RPC'er + grants i slutningen af red_*-blokken)
- Modify: `schema.sql` (samme RPC-definitioner, så schema.sql forbliver source of truth)

**Interfaces:**
- Consumes: eksisterende `current_rolle()`, `red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)`, `regen_person_visning`-trigger, tabeller `person/estate/source/organisation`.
- Produces (RPC-signaturer som app-laget kalder):
  - `red_opret_person(p_navn text, p_koen text, p_levende boolean, p_privat boolean, p_foedt_raw text, p_doed_raw text, p_titel_raw text) → bigint`
  - `red_opret_estate(p_navn text, p_slags text, p_sted_id bigint) → bigint`
  - `red_opret_kilde(p_titel text, p_slags text, p_udgave text, p_ekstern boolean) → bigint`
  - `red_opret_organisation(p_navn text, p_slags text) → bigint`

- [ ] **Step 1: Skriv RPC'erne i `db-migrations.sql`** (append i red_*-sektionen, før grant-blokken)

```sql
-- ============ OPRET-NY-ENTITET (2026-06-29) ============
-- Komposite SECURITY DEFINER opret-RPC'er. id=max+1 (husstil). privat=true default (privatliv).
CREATE OR REPLACE FUNCTION red_opret_person(
  p_navn text, p_koen text DEFAULT NULL, p_levende boolean DEFAULT false,
  p_privat boolean DEFAULT true, p_foedt_raw text DEFAULT NULL,
  p_doed_raw text DEFAULT NULL, p_titel_raw text DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  IF p_koen IS NOT NULL AND p_koen NOT IN ('mand','kvinde','ukendt')
    THEN RAISE EXCEPTION 'Ugyldigt køn %', p_koen; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, levende, privat, koen) VALUES (v_id, p_levende, p_privat, p_koen);
  PERFORM red_upsert_fakta('person', v_id, 'navn', p_navn);
  IF nullif(btrim(p_foedt_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'fødsel', p_foedt_raw, p_date_raw => p_foedt_raw);
  END IF;
  IF nullif(btrim(p_doed_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'død', p_doed_raw, p_date_raw => p_doed_raw);
  END IF;
  IF nullif(btrim(p_titel_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'titel', p_titel_raw);
  END IF;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_estate(p_navn text, p_slags text DEFAULT NULL, p_sted_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM estate);
  INSERT INTO estate(id, navn, slags, sted_id) VALUES (v_id, p_navn, p_slags, p_sted_id);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_kilde(p_titel text, p_slags text DEFAULT NULL, p_udgave text DEFAULT NULL, p_ekstern boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_titel),'') IS NULL THEN RAISE EXCEPTION 'Titel er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel, udgave, ekstern) VALUES (v_id, p_slags, p_titel, p_udgave, p_ekstern);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_opret_organisation(p_navn text, p_slags text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM organisation);
  INSERT INTO organisation(id, navn, slags) VALUES (v_id, p_navn, p_slags);
  RETURN v_id;
END $$;
```

- [ ] **Step 2: Tilføj grants** (ved siden af de eksisterende `grant execute on function public.red_…` i `db-migrations.sql`)

```sql
grant execute on function public.red_opret_person(text,text,boolean,boolean,text,text,text) to authenticated;
grant execute on function public.red_opret_estate(text,text,bigint) to authenticated;
grant execute on function public.red_opret_kilde(text,text,text,boolean) to authenticated;
grant execute on function public.red_opret_organisation(text,text) to authenticated;
```

- [ ] **Step 3: Spejl de samme 4 RPC'er + grants ind i `schema.sql`** (i red_*-funktions-sektionen, så schema.sql = source of truth). Identisk SQL som Step 1+2.

- [ ] **Step 4: Schema-backup før deploy** (som de tidligere controller-gates)

Run: `mcp__supabase__execute_sql` med:
```sql
SELECT p.proname, pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname LIKE 'red_%' ORDER BY 1;
```
Gem output til `docs/db-backups/2026-06-29-prod-red-functions-opret-pre.sql`.

- [ ] **Step 5: Deploy RPC'er + grants til prod**

Run: `mcp__supabase__apply_migration` (name: `red_opret_ny_entitet`) med SQL fra Step 1+2.
Expected: success, ingen fejl.

- [ ] **Step 6: Negativ rollback-test (rolle-gate)** — RPC kaldt uden redaktion-rolle skal afvises

Run: `mcp__supabase__execute_sql`:
```sql
BEGIN;
SELECT red_opret_organisation('Test-org', 'institution');  -- forventet: ERROR
ROLLBACK;
```
Expected: ERROR `Kun redaktion` (P0001) — fordi `execute_sql` kører uden `rolle='redaktion'`-JWT.

- [ ] **Step 7: Happy-path rollback-test (under redaktion-kontekst)**

Kør under en redaktion-JWT (eller midlertidig `SET LOCAL request.jwt.claims` der giver `current_rolle()='redaktion'`):
```sql
BEGIN;
SET LOCAL request.jwt.claims = '{"sub":"<redaktion-auth-uid>","role":"authenticated"}';
SELECT red_opret_person('Testperson Reventlow', 'mand', false, true, '1700', '1755', 'kammerherre') AS pid \gset
SELECT visning_navn, privat, levende, koen FROM person WHERE id=:pid;          -- visning_navn='Testperson Reventlow', privat=t
SELECT faktatype FROM fact WHERE subjekt_type='person' AND subjekt_id=:pid ORDER BY 1; -- død, fødsel, navn, titel
SELECT red_opret_estate('Testgods', 'gods', NULL);
SELECT red_opret_kilde('Test-kirkebog', 'kirkebog', NULL, false);
-- NULL/whitespace navn afvises:
SELECT red_opret_person(NULL);    -- ERROR 'Navn er påkrævet'
ROLLBACK;
```
Expected: person-række + 4 facts + `visning_navn` regenereret + `privat=t`; estate/kilde oprettet; NULL-navn → ERROR. Alt rullet tilbage.

- [ ] **Step 8: Commit**

```bash
git add db-migrations.sql schema.sql docs/db-backups/2026-06-29-prod-red-functions-opret-pre.sql
git commit -m "feat(redaktion): 4 opret-RPC'er (person/gods/kilde/org) + grants, deployet til prod"
```

---

### Task 2: App write-lag — Change-arter + buildRpcCall-cases (TDD)

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts` (udvid `Change['art']`-union + 4 nye cases i `buildRpcCall`)
- Test: `mobile/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces:**
- Consumes: RPC-signaturer fra Task 1.
- Produces: `Change`-arter `opretPerson | opretEstate | opretKilde | opretOrganisation`, alle med felter i `c.payload`:
  - opretPerson payload: `{ navn: string; koen?: string; levende?: boolean; privat?: boolean; foedtRaw?: string; doedRaw?: string; titelRaw?: string }`
  - opretEstate payload: `{ navn: string; slags?: string; stedId?: number }`
  - opretKilde payload: `{ titel: string; slags?: string; udgave?: string; ekstern?: boolean }`
  - opretOrganisation payload: `{ navn: string; slags?: string }`
  - Returnerer `RpcCall { fn, args }` med kun ikke-tomme args; `null` hvis påkrævet-felt (navn/titel) mangler.

- [ ] **Step 1: Skriv de failing tests** (tilføj i `redaktionWrite.test.ts`)

```ts
describe('buildRpcCall opret-arter', () => {
  it('opretPerson → red_opret_person, kun udfyldte args', () => {
    const c = { art: 'opretPerson', subjektType: 'person', subjektId: '',
      payload: { navn: 'Conrad', koen: 'mand', levende: false, privat: true,
                 foedtRaw: '1700', doedRaw: '', titelRaw: 'greve' } } as const;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_opret_person', args: {
      p_navn: 'Conrad', p_koen: 'mand', p_levende: false, p_privat: true,
      p_foedt_raw: '1700', p_titel_raw: 'greve' } });   // doedRaw='' udeladt
  });
  it('opretPerson uden navn → null', () => {
    expect(buildRpcCall({ art: 'opretPerson', subjektType: 'person', subjektId: '',
      payload: { navn: '' } } as const)).toBeNull();
  });
  it('opretEstate → red_opret_estate', () => {
    expect(buildRpcCall({ art: 'opretEstate', subjektType: 'estate', subjektId: '',
      payload: { navn: 'Brahetrolleborg', slags: 'gods' } } as const))
      .toEqual({ fn: 'red_opret_estate', args: { p_navn: 'Brahetrolleborg', p_slags: 'gods' } });
  });
  it('opretKilde → red_opret_kilde', () => {
    expect(buildRpcCall({ art: 'opretKilde', subjektType: 'source', subjektId: '',
      payload: { titel: 'DAA 2018-20', slags: 'DAA-udgave', ekstern: false } } as const))
      .toEqual({ fn: 'red_opret_kilde', args: { p_titel: 'DAA 2018-20', p_slags: 'DAA-udgave', p_ekstern: false } });
  });
  it('opretOrganisation → red_opret_organisation', () => {
    expect(buildRpcCall({ art: 'opretOrganisation', subjektType: 'organisation', subjektId: '',
      payload: { navn: 'Livgarden', slags: 'regiment' } } as const))
      .toEqual({ fn: 'red_opret_organisation', args: { p_navn: 'Livgarden', p_slags: 'regiment' } });
  });
});
```

- [ ] **Step 2: Kør testene — verificér de fejler**

Run: `cd mobile && npx jest redaktionWrite -t 'opret-arter'`
Expected: FAIL (arterne findes ikke i union → buildRpcCall returnerer null / TS-fejl).

- [ ] **Step 3: Udvid `Change['art']`-union** i `redaktionWrite.ts`

```ts
  art: 'fakta' | 'narrativ' | 'relation' | 'gods' | 'hverv'
     | 'redigerOplysning' | 'sletOplysning' | 'setKonklusion' | 'setPrivat' | 'sletPerson'
     | 'tilfoejOplysning' | 'opretFakta' | 'sletRelation' | 'tilfoejRelation'
     | 'opretUnion' | 'tilfoejBarn' | 'setFamilieKonfidens' | 'sletFamilieLink'
     | 'opretPerson' | 'opretEstate' | 'opretKilde' | 'opretOrganisation';
```

- [ ] **Step 4: Tilføj de 4 cases** i `buildRpcCall` (før `return null;`)

```ts
  if (c.art === 'opretPerson') {
    const p = c.payload || {};
    if (!p.navn) return null;
    const args: Record<string, unknown> = { p_navn: p.navn };
    if (p.koen != null) args.p_koen = p.koen;
    if (p.levende != null) args.p_levende = p.levende;
    if (p.privat != null) args.p_privat = p.privat;
    if (p.foedtRaw) args.p_foedt_raw = p.foedtRaw;
    if (p.doedRaw) args.p_doed_raw = p.doedRaw;
    if (p.titelRaw) args.p_titel_raw = p.titelRaw;
    return { fn: 'red_opret_person', args };
  }
  if (c.art === 'opretEstate') {
    const p = c.payload || {};
    if (!p.navn) return null;
    const args: Record<string, unknown> = { p_navn: p.navn };
    if (p.slags) args.p_slags = p.slags;
    if (p.stedId != null) args.p_sted_id = Number(p.stedId);
    return { fn: 'red_opret_estate', args };
  }
  if (c.art === 'opretKilde') {
    const p = c.payload || {};
    if (!p.titel) return null;
    const args: Record<string, unknown> = { p_titel: p.titel };
    if (p.slags) args.p_slags = p.slags;
    if (p.udgave) args.p_udgave = p.udgave;
    if (p.ekstern != null) args.p_ekstern = p.ekstern;
    return { fn: 'red_opret_kilde', args };
  }
  if (c.art === 'opretOrganisation') {
    const p = c.payload || {};
    if (!p.navn) return null;
    const args: Record<string, unknown> = { p_navn: p.navn };
    if (p.slags) args.p_slags = p.slags;
    return { fn: 'red_opret_organisation', args };
  }
```

- [ ] **Step 5: Kør testene + tsc**

Run: `cd mobile && npx jest redaktionWrite && npx tsc --noEmit`
Expected: PASS, tsc rent.

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/redaktionWrite.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(redaktion): opret-Change-arter + buildRpcCall-cases (person/gods/kilde/org)"
```

---

### Task 3: B1 — `loadRedaktionModel(force)` (forced reload)

**Files:**
- Modify: `mobile/src/store/useStore.ts:75` (type-decl) og `:257-269` (action)

**Interfaces:**
- Produces: `loadRedaktionModel: (force?: boolean) => Promise<void>` — `force=true` springer `ready`-early-return over og henter friske data. Ved fejl: status='error', resolver (ingen re-throw — eksisterende mount-kaldere afventer uden catch). Kaldere tjekker selv `redaktionStatus` efter.

- [ ] **Step 1: Opdater type-deklarationen** (linje ~75)

```ts
  loadRedaktionModel: (force?: boolean) => Promise<void>;
```

- [ ] **Step 2: Opdater action'en** (linje ~257)

```ts
  loadRedaktionModel: async (force?: boolean) => {
    if (!force && (get().redaktionStatus === 'loading' || get().redaktionStatus === 'ready')) return;
    set({ redaktionStatus: 'loading' });
    try {
      const res = await loadFromSupabase({ includePrivat: true });
      const model = buildModel(res.db);
      set({ redaktionModel: model, redaktionAux: res.aux, redaktionStatus: 'ready' });
    } catch {
      // Redaktion skal VIDE hvis det fejler — ingen seed-fallback. Kaldere tjekker redaktionStatus.
      set({ redaktionStatus: 'error' });
    }
  },
```

- [ ] **Step 3: Verificér tsc + eksisterende tests urørte**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: tsc rent; alle eksisterende tests PASS (signatur-ændringen er bagudkompatibel — `force` valgfri).

- [ ] **Step 4: Commit**

```bash
git add mobile/src/store/useStore.ts
git commit -m "feat(redaktion): loadRedaktionModel(force) — tving reload efter opret (B1)"
```

---

### Task 4: B2 — `SkrivePreviewSheet.onApplied(result)` (ID-transport)

**Files:**
- Modify: `mobile/src/components/redaktion/SkrivePreviewSheet.tsx` (props-type + `run()`)

**Interfaces:**
- Consumes: `submitChange` returnerer ved live `{ dryRun: false; call; result }` hvor `result` = RPC-returværdi (ny id ved opret-RPC'er).
- Produces: `onApplied: (result?: unknown) => void` — kaldes ved live-success med RPC-resultatet. Bagudkompatibel: eksisterende kalder i `person/[id].tsx:607` (`onApplied={() => {…}}`) ignorerer arg.

- [ ] **Step 1: Opdater props-typen**

```ts
export function SkrivePreviewSheet({ change, onClose, onApplied }: {
  change: Change | null;
  onClose: () => void;
  onApplied: (result?: unknown) => void;
}) {
```

- [ ] **Step 2: Videregiv resultatet i `run()`**

```ts
  async function run() {
    setStatus('busy');
    setFejl(null);
    try {
      const res = await submitChange(change as Change, { dryRun });
      setStatus('ok');
      if (!dryRun) onApplied('result' in res ? res.result : undefined);
    } catch (e) {
      setFejl(oversaetFejl(e instanceof Error ? e.message : String(e)));
      setStatus('err');
    }
  }
```

- [ ] **Step 3: Verificér tsc + eksisterende editor-kalder urørt**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: tsc rent (person/[id].tsx's `onApplied={() => …}` matcher stadig `(result?) => void`); tests PASS.

- [ ] **Step 4: Commit**

```bash
git add mobile/src/components/redaktion/SkrivePreviewSheet.tsx
git commit -m "feat(redaktion): SkrivePreviewSheet.onApplied bærer live-resultat/ny id (B2)"
```

---

### Task 5: OpretSheet + wire "Tilføj"-fanen

**Files:**
- Create: `mobile/src/components/redaktion/OpretSheet.tsx`
- Modify: `mobile/src/app/redaktion/(red-tabs)/_layout.tsx` (fang `opretOpen`-state + render `OpretSheet`)

**Interfaces:**
- Consumes: `Change` opret-arter (Task 2), `SkrivePreviewSheet.onApplied(result)` (Task 4), `loadRedaktionModel(true)` (Task 3), `useStore`, expo-router `useRouter`.
- Produces: `OpretSheet({ visible, onClose }: { visible: boolean; onClose: () => void })`.

- [ ] **Step 1: Skriv `OpretSheet.tsx`** (grid → type-form → byg Change → SkrivePreviewSheet → post-create reload/nav)

```tsx
import { useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { SkrivePreviewSheet } from './SkrivePreviewSheet';
import { pickerSheetStyles } from './pickerSheetStyles';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, BtnLabel, Mono, Serif } from '../Typography';
import type { Change } from '../../data/redaktionWrite';

type EntType = 'person' | 'estate' | 'kilde' | 'organisation';
const TYPER: { key: EntType; label: string }[] = [
  { key: 'person', label: 'Person' }, { key: 'estate', label: 'Gods' },
  { key: 'kilde', label: 'Kilde' }, { key: 'organisation', label: 'Organisation' },
];
const KOEN = ['mand', 'kvinde', 'ukendt'];
const ESTATE_SLAGS = ['gods', 'len', 'stamhus', 'lensgrevskab', 'baroni'];
const KILDE_SLAGS = ['kirkebog', 'DAA-udgave', 'bog', 'artikel', 'diplomsamling'];
const ORG_SLAGS = ['amt', 'regiment', 'hof', 'institution', 'ridderorden'];

function Pille({ valgt, label, onPress }: { valgt: boolean; label: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress}
      style={[styles.pille, valgt && styles.pilleAktiv]}>
      <Mono size={11} color={valgt ? Colors.paperBg : Colors.textSecondary}>{label}</Mono>
    </Pressable>
  );
}

export function OpretSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const router = useRouter();
  const [type, setType] = useState<EntType | null>(null);
  // person
  const [navn, setNavn] = useState('');
  const [koen, setKoen] = useState<string | null>(null);
  const [levende, setLevende] = useState(false);
  const [foedt, setFoedt] = useState('');
  const [doed, setDoed] = useState('');
  const [titel, setTitel] = useState('');
  // fælles tekst
  const [slags, setSlags] = useState<string | null>(null);
  const [udgave, setUdgave] = useState('');
  const [ekstern, setEkstern] = useState(false);
  const [pending, setPending] = useState<Change | null>(null);

  function nulstil() {
    setType(null); setNavn(''); setKoen(null); setLevende(false); setFoedt('');
    setDoed(''); setTitel(''); setSlags(null); setUdgave(''); setEkstern(false); setPending(null);
  }
  function luk() { nulstil(); onClose(); }

  function byg(): Change | null {
    if (type === 'person') {
      if (!navn.trim()) return null;
      return { art: 'opretPerson', subjektType: 'person', subjektId: '',
        payload: { navn: navn.trim(), koen: koen ?? undefined, levende, privat: true,
          foedtRaw: foedt.trim(), doedRaw: doed.trim(), titelRaw: titel.trim() } };
    }
    if (type === 'estate') {
      if (!navn.trim()) return null;
      return { art: 'opretEstate', subjektType: 'estate', subjektId: '',
        payload: { navn: navn.trim(), slags: slags ?? undefined } };
    }
    if (type === 'kilde') {
      if (!navn.trim()) return null;
      return { art: 'opretKilde', subjektType: 'source', subjektId: '',
        payload: { titel: navn.trim(), slags: slags ?? undefined, udgave: udgave.trim(), ekstern } };
    }
    if (type === 'organisation') {
      if (!navn.trim()) return null;
      return { art: 'opretOrganisation', subjektType: 'organisation', subjektId: '',
        payload: { navn: navn.trim(), slags: slags ?? undefined } };
    }
    return null;
  }

  async function efterOpret(result?: unknown) {
    const t = type; // bevares før nulstil
    await useStore.getState().loadRedaktionModel(true);
    if (useStore.getState().redaktionStatus !== 'ready') return; // forced reload fejlede → bliv på sheet
    luk();
    if (t === 'person' && result != null) router.push(`/redaktion/person/${result}` as never);
  }

  const navnLabel = type === 'kilde' ? 'Titel' : 'Navn';
  const slagsListe = type === 'estate' ? ESTATE_SLAGS : type === 'kilde' ? KILDE_SLAGS : ORG_SLAGS;
  const kanGemme = navn.trim().length > 0;

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={luk}>
      <Pressable style={styles.backdrop} onPress={luk} />
      <View style={styles.sheet}>
        {!type ? (
          <>
            <Serif size={20} style={{ marginBottom: 14 }}>Opret ny post</Serif>
            <View style={styles.grid}>
              {TYPER.map((t) => (
                <Pressable key={t.key} style={styles.cell} onPress={() => setType(t.key)}>
                  <Serif size={17} color={Colors.bordeaux}>{t.label}</Serif>
                </Pressable>
              ))}
            </View>
          </>
        ) : (
          <ScrollView style={{ maxHeight: 460 }}>
            <Serif size={20} style={{ marginBottom: 12 }}>Ny {TYPER.find((t) => t.key === type)!.label.toLowerCase()}</Serif>
            <Mono size={9} color={Colors.gold}>{navnLabel.toUpperCase()} *</Mono>
            <TextInput style={pickerSheetStyles.input} value={navn} onChangeText={setNavn}
              placeholder={navnLabel} placeholderTextColor={Colors.textMuted} autoFocus />

            {type === 'person' ? (
              <>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 10 }}>KØN</Mono>
                <View style={styles.pilleRad}>
                  {KOEN.map((k) => <Pille key={k} label={k} valgt={koen === k} onPress={() => setKoen(koen === k ? null : k)} />)}
                </View>
                <View style={styles.switchRad}>
                  <Body size={13}>Nulevende</Body>
                  <Switch value={levende} onValueChange={setLevende} />
                </View>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>FØDT</Mono>
                <TextInput style={pickerSheetStyles.input} value={foedt} onChangeText={setFoedt}
                  placeholder="fx 1700" placeholderTextColor={Colors.textMuted} />
                <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>DØD</Mono>
                <TextInput style={pickerSheetStyles.input} value={doed} onChangeText={setDoed}
                  placeholder="fx 1755" placeholderTextColor={Colors.textMuted} />
                <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>TITEL</Mono>
                <TextInput style={pickerSheetStyles.input} value={titel} onChangeText={setTitel}
                  placeholder="fx greve" placeholderTextColor={Colors.textMuted} />
              </>
            ) : (
              <>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 10 }}>SLAGS</Mono>
                <View style={styles.pilleRad}>
                  {slagsListe.map((s) => <Pille key={s} label={s} valgt={slags === s} onPress={() => setSlags(slags === s ? null : s)} />)}
                </View>
                {type === 'kilde' ? (
                  <>
                    <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>UDGAVE</Mono>
                    <TextInput style={pickerSheetStyles.input} value={udgave} onChangeText={setUdgave}
                      placeholder="fx DAA 2018-20" placeholderTextColor={Colors.textMuted} />
                    <View style={styles.switchRad}>
                      <Body size={13}>Eksternt værk</Body>
                      <Switch value={ekstern} onValueChange={setEkstern} />
                    </View>
                  </>
                ) : null}
              </>
            )}

            <Pressable style={[styles.btn, !kanGemme && styles.btnDisabled]} disabled={!kanGemme}
              onPress={() => { const c = byg(); if (c) setPending(c); }}>
              <BtnLabel color="#fff">Gennemse & opret</BtnLabel>
            </Pressable>
            <Pressable style={styles.cancel} onPress={() => setType(null)}>
              <BtnLabel color={Colors.textSecondary}>Tilbage</BtnLabel>
            </Pressable>
          </ScrollView>
        )}
      </View>

      <SkrivePreviewSheet change={pending} onClose={() => setPending(null)} onApplied={efterOpret} />
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet,
    padding: 20, paddingBottom: 36, borderTopWidth: 1, borderColor: Border.light },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 9 },
  cell: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: 13,
    padding: 18, minWidth: '47%', alignItems: 'center' },
  pilleRad: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 4 },
  pille: { borderWidth: 1, borderColor: Border.medium, borderRadius: 14, paddingVertical: 5, paddingHorizontal: 11 },
  pilleAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  switchRad: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 },
  btn: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14, alignItems: 'center', marginTop: 16 },
  btnDisabled: { opacity: 0.5 },
  cancel: { padding: 12, alignItems: 'center', marginTop: 4 },
});
```

- [ ] **Step 2: Wire "Tilføj"-fanen** i `(red-tabs)/_layout.tsx` — fang state + render sheet

```tsx
import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import { useState } from 'react';
import type { ColorValue } from 'react-native';
import { OpretSheet } from '../../../components/redaktion/OpretSheet';
import { Border, Colors, Fonts } from '../../../theme/tokens';

type IconName = keyof typeof Ionicons.glyphMap;
const icon = (name: IconName) => ({ color, size }: { color: ColorValue; size: number }) =>
  <Ionicons name={name} color={color as string} size={size} />;

export default function RedTabsLayout() {
  const [opretOpen, setOpretOpen] = useState(false);
  return (
    <>
      <Tabs
        screenOptions={{
          headerShown: false,
          tabBarActiveTintColor: Colors.bordeaux,
          tabBarInactiveTintColor: Colors.textMuted2,
          tabBarStyle: { height: 66, paddingTop: 8, paddingBottom: 10,
            backgroundColor: Colors.ink, borderTopColor: Border.medium },
          tabBarLabelStyle: { fontFamily: Fonts.sansSemi, fontSize: 11, letterSpacing: 0.1 },
        }}>
        <Tabs.Screen name="index" options={{ title: 'Oversigt', tabBarIcon: icon('grid-outline') }} />
        <Tabs.Screen name="entiteter" options={{ title: 'Entiteter', tabBarIcon: icon('list-outline') }} />
        <Tabs.Screen
          name="tilfoej"
          options={{ title: 'Tilføj', tabBarIcon: icon('add-circle-outline') }}
          listeners={{ tabPress: (e) => { e.preventDefault(); setOpretOpen(true); } }}
        />
        <Tabs.Screen name="konto" options={{ title: 'Konto', tabBarIcon: icon('person-circle-outline') }} />
      </Tabs>
      <OpretSheet visible={opretOpen} onClose={() => setOpretOpen(false)} />
    </>
  );
}
```

- [ ] **Step 3: tsc + lint + eksisterende tests**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: tsc rent; tests PASS.

- [ ] **Step 4: Manuel web-e2e** (kør `cd mobile && npx expo start --web`, log ind som redaktion, dry-run AF)

1. Tilføj-fane → grid vises (Person/Gods/Kilde/Organisation).
2. Person: navn "Testperson" + køn + født "1700" → "Gennemse & opret" → LIVE → lander i `/redaktion/person/<id>` med navnet sat.
3. Tilføj → Gods: navn "Testgods" + slags → opret → Entiteter-fane → Godser-liste viser "Testgods" + tæller +1.
4. Tilføj → Person: tomt navn → "Gennemse & opret" disabled.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/components/redaktion/OpretSheet.tsx "mobile/src/app/redaktion/(red-tabs)/_layout.tsx"
git commit -m "feat(redaktion): OpretSheet (person/gods/kilde/org) + wire Tilføj-fane + post-create reload/nav"
```

---

### Task 6: Dokumentation + changelog

**Files:**
- Modify: `docs/changelog.md` (ny entry øverst)
- Modify: `docs/decisions.md` (privat=true-default + sted-udskydelse)

- [ ] **Step 1: Tilføj changelog-entry** (øverst, format som eksisterende)

```markdown
## Opret-ny-entitet — Tilføj-fanen (2026-06-29)
* **Hvad:** Redaktøren kan oprette ny person/gods/kilde/organisation fra "Tilføj"-fanen gennem
  dry-run→live-gate; person → lander i editoren, øvrige → vises i listen.
* **4 nye SECURITY DEFINER RPC'er (deployet prod):** red_opret_person (INSERT + navn/født/død/titel
  som facts via red_upsert_fakta, privat=true default), red_opret_estate, red_opret_kilde,
  red_opret_organisation. id=max+1, NULL/whitespace-navn afvist.
* **B1/B2 (Codex-review):** loadRedaktionModel(force) tvinger reload (var no-op på 'ready');
  SkrivePreviewSheet.onApplied(result) bærer ny id til navigation.
* **Privatliv:** ny person privat=true (levende=false=anon-læsbar → glemt toggle ville publicere).
* **Udskudt:** sted-picker til gods (ingen place-picker/placeListe); inline-opret fra PersonPicker;
  medie/våben/majorat; dedup-UNIQUE; id-sequence (post-PoC).
* **Test:** jest (buildRpcCall opret-arter) + DB rollback-test + manuel web-e2e.
```

- [ ] **Step 2: Tilføj decisions-entry**

```markdown
## Opret: privat=true default + sted udskudt (2026-06-29)
Ny person oprettes med privat=true (ikke levende=false alene), fordi RLS-reglen
`levende=false AND privat=false` gør personen anon-læsbar — en glemt levende-toggle ville ellers
publicere en nulevende person. Redaktøren afpublicerer bevidst via red_set_privat.
Gods-sted udskudt: EntitetPicker understøtter kun organisation/estate, og Aux har ingen placeListe.
```

- [ ] **Step 3: Commit**

```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs(redaktion): changelog + decisions for opret-ny-entitet"
```

---

## Self-Review (udført)

- **Spec-dækning:** §3 (4 RPC'er) → Task 1; §4 (Change/buildRpcCall) → Task 2; §5.3 B1 → Task 3; §5.3 B2 → Task 4; §5.1/§5.2 (OpretSheet + wire) → Task 5; §6 (test) → fordelt i Task 1/2/5; dok → Task 6. Ingen gaps.
- **Placeholder-scan:** ingen TBD/TODO; al kode konkret.
- **Type-konsistens:** `loadRedaktionModel(force?)` (Task 3) = samme som kaldt i OpretSheet (Task 5); `onApplied(result?)` (Task 4) = samme som forbrugt i OpretSheet; Change-payload-felter (Task 2) = samme navne brugt i `byg()` (Task 5); RPC-signaturer (Task 1) = args i buildRpcCall (Task 2).
- **Afvigelse fra spec:** B1 dropper re-throw (regresserede swallow-kaldere) → OpretSheet tjekker `redaktionStatus` i stedet; gods-sted udskudt (ingen place-picker). Begge noteret i spec §5.3/§5.2.
