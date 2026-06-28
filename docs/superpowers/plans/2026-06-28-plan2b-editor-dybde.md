# Plan 2B — Editor-dybde (separat redaktion-model) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør person-editoren selv-forsynende via en separat redaktion-model (virker for de 70 levende), tilføj køn-editor, vis familie + sektioner read-only via eksisterende selektorer, og fix narrativ-privat-tab.

**Architecture:** En ekstra fuld model loades via redaktion-sessionen (`loadFromSupabase({includePrivat:true})` → `buildModel`), gemt i en separat store-slice adskilt fra publikums-modellen (ingen GDPR-læk). Editoren bruger `redaktionModel`/`redaktionAux` med de EKSISTERENDE selektorer (`parentsOf`/`spousesOf`/`childrenByMarriage`/aux) — ingen ny derivation, ingen divergens fra publikum.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand, `@supabase/supabase-js`, Jest.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-28-plan2b-editor-dybde-design.md` (autoritativ).
- **Branch:** opret feature-branch fra `main` (`feat/plan2b-editor-dybde`); ingen merge/push uden eksplicit godkendelse.
- **Separat model:** publikums-`model`/`aux` røres ALDRIG; redaktion-data lever i `redaktionModel`/`redaktionAux`. To modeller side om side.
- **Genbrug derivation:** familie/sektion via EKSISTERENDE `parentsOf`/`spousesOf`/`childrenByMarriage` + `aux.officesBy/estatesBy/sourcesBy`. INGEN ny familie/hverv-logik (Codex 2B #2/#4).
- **Pagination gratis:** `loadFromSupabase` bruger allerede `getAll` → ingen 1000-cap.
- **Køn-vocab:** `mand` / `kvinde` / `ukendt` (DB-constraint `person_koen_chk`, Codex-bekræftet).
- **Narrativ-fix:** prefill-kilde == skrive-mål (første narrativ by id, uanset privat) + bevar privat-flag på Gem (Codex 2B #1).
- **Fejl kastes, aldrig tom-som-clean** (cycle 03 NEW1): loadRedaktionModel/fetchPersonNarrativ kaster ved error; UI viser eksplicit fejl-tilstand.
- **Kun køn redigerbart** i 2B; familie/sektioner read-only.
- **Tokens/Typography** (`Serif`/`Mono`/`Body`/`BtnLabel`/`InitialBadge`, tokens). Ingen rå hex (#fff/rgba OK).
- **Test-niveau matcher risiko:** ren logik (mapAppPersons, narrativ-mapping) = TDD/jest; store-slice + skærm = tsc + manuel.
- Ingen Claude-attribution i commits. Conventional Commits, dansk.

---

## File Structure

**Ændrede:**
- `mobile/src/data/types.ts` — `AppPerson.privat?: boolean`.
- `mobile/src/data/load.ts` — `includePrivat`-param; udtræk `mapAppPersons` (ren) + behold `privat`.
- `mobile/src/data/redaktionRead.ts` — `fetchPersonNarrativ`.
- `mobile/src/store/useStore.ts` — `redaktionModel`/`redaktionAux`/`redaktionStatus` + `loadRedaktionModel`.
- `mobile/src/app/redaktion/_layout.tsx` — trigger `loadRedaktionModel` ved rolle=redaktion.
- `mobile/src/app/redaktion/person/[id].tsx` — header/familie/sektion fra redaktionModel; køn-editor; privat-init; narrativ-prefill.
- Tests: `mobile/src/data/__tests__/load.test.ts` (ny), `redaktionRead.test.ts`.

---

## Task 1: `load.ts` — `includePrivat` + `privat` på AppPerson (ren `mapAppPersons`)

**Files:**
- Modify: `mobile/src/data/types.ts` (AppPerson)
- Modify: `mobile/src/data/load.ts` (loadFromSupabase signatur + udtræk mapAppPersons)
- Test: `mobile/src/data/__tests__/load.test.ts` (ny)

**Interfaces:**
- Produces: `mapAppPersons(persons: RawPerson[], bioBy: Record<string,string>, includePrivat: boolean): AppPerson[]` (ren); `loadFromSupabase(opts?: { includePrivat?: boolean }): Promise<LoadResult>`. `AppPerson` får `privat: boolean`.

- [ ] **Step 1: Tilføj `privat` til AppPerson**

I `mobile/src/data/types.ts`, i `AppPerson`-typen tilføj feltet:
```ts
export type AppPerson = {
  id: string;
  name: string;
  born: number | null;
  died: number | null;
  years: string;
  title: string;
  bio: string;
  privat: boolean;
};
```

- [ ] **Step 2: Skriv fejlende test for `mapAppPersons`**

Opret `mobile/src/data/__tests__/load.test.ts`:
```ts
import { mapAppPersons } from '../load';

const RAW = [
  { id: 1, visning_navn: 'Conrad', visning_foedt: '1644', visning_doed: '1708', visning_titel: 'greve', privat: false },
  { id: 2, visning_navn: 'Levende', visning_foedt: '1980', visning_doed: null, visning_titel: '', privat: true },
];

test('mapAppPersons: includePrivat=false filtrerer private fra', () => {
  const r = mapAppPersons(RAW as never, {}, false);
  expect(r.map((p) => p.id)).toEqual(['1']);
});

test('mapAppPersons: includePrivat=true beholder private + sætter privat-flag', () => {
  const r = mapAppPersons(RAW as never, {}, true);
  expect(r.map((p) => p.id)).toEqual(['1', '2']);
  expect(r.find((p) => p.id === '2')?.privat).toBe(true);
  expect(r.find((p) => p.id === '1')?.privat).toBe(false);
});

test('mapAppPersons: bio fra bioBy, navn-fallback', () => {
  const r = mapAppPersons([{ id: 3, visning_navn: null, visning_foedt: null, visning_doed: null, visning_titel: null, privat: false }] as never,
    { '3': 'En biografi' }, false);
  expect(r[0]).toMatchObject({ id: '3', name: '(uden navn)', bio: 'En biografi', privat: false });
});
```

- [ ] **Step 3: Kør — verificér fejl**

Run: `cd mobile && npx jest load -t "mapAppPersons"`
Expected: FAIL — `mapAppPersons is not a function`.

- [ ] **Step 4: Udtræk `mapAppPersons` + parametrisér `loadFromSupabase`**

I `load.ts`: erstat det inline `appPersons`-udtryk med et kald til en ny eksporteret ren funktion. Tilføj `import type { RawPerson, AppPerson } from './types';` hvis ikke til stede (RawPerson findes allerede importeret). Tilføj funktionen (fx lige over `loadFromSupabase`):

```ts
export function mapAppPersons(
  persons: RawPerson[],
  bioBy: Record<string, string>,
  includePrivat: boolean,
): AppPerson[] {
  return (persons || [])
    .filter((p) => includePrivat || !p.privat)
    .map((p) => ({
      id: String(p.id),
      name: p.visning_navn || '(uden navn)',
      born: parseYear(p.visning_foedt),
      died: parseYear(p.visning_doed),
      years: fmtYears(p.visning_foedt, p.visning_doed),
      title: p.visning_titel || '',
      bio: bioBy[String(p.id)] || '',
      privat: Boolean(p.privat),
    }));
}
```

Ændr `loadFromSupabase`-signaturen + kaldet til det inline-map:
```ts
export async function loadFromSupabase(opts?: { includePrivat?: boolean }): Promise<LoadResult> {
  // ... eksisterende fetch ...
  const appPersons = mapAppPersons(persons || [], bioBy, opts?.includePrivat ?? false);
  // ... resten uændret ...
}
```
(Slet den gamle inline `.filter().map()`-blok — `mapAppPersons` erstatter den 1:1.)

Bekræft `AppPerson` importeres/typecheck'er (privat nu påkrævet — alle map-stier sætter det; `SEED`-data skal også have `privat` — tilføj `privat: false` til seed-personer hvis tsc klager, se Step 5).

- [ ] **Step 5: Kør tests + tsc (fix seed hvis nødvendigt)**

Run: `cd mobile && npx jest load && npx tsc --noEmit`
Expected: PASS. Hvis tsc klager over `privat` mangler i `SEED`/`seed.ts`-personer: tilføj `privat: false` til hver seed-AppPerson (de er alle offentlige). Kør igen.

- [ ] **Step 6: Commit**

```bash
git add mobile/src/data/types.ts mobile/src/data/load.ts mobile/src/data/__tests__/load.test.ts mobile/src/data/seed.ts
git commit -m "feat(data): loadFromSupabase includePrivat + privat på AppPerson (ren mapAppPersons)"
```

---

## Task 2: `fetchPersonNarrativ` — narrativ-privat-fix

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts`
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts`

**Interfaces:**
- Produces: `type PersonNarrativ = { tekst: string; privat: boolean }`; `mapNarrativRow(rows: { tekst: string|null; privat: boolean|null }[]): PersonNarrativ | null` (ren — første række, uanset privat); `async fetchPersonNarrativ(id: string): Promise<PersonNarrativ | null>`.

- [ ] **Step 1: Skriv fejlende test**

Tilføj i `redaktionRead.test.ts`:
```ts
import { mapNarrativRow } from '../redaktionRead';

test('mapNarrativRow: første række uanset privat (skrive-mål == prefill)', () => {
  // red_upsert_narrativ redigerer FØRSTE narrativ by id — prefill skal læse SAMME.
  expect(mapNarrativRow([{ tekst: 'Privat bio', privat: true }, { tekst: 'Offentlig', privat: false }]))
    .toEqual({ tekst: 'Privat bio', privat: true });
});

test('mapNarrativRow: tom liste → null', () => {
  expect(mapNarrativRow([])).toBeNull();
});

test('mapNarrativRow: null-tekst → tom streng, privat-bool', () => {
  expect(mapNarrativRow([{ tekst: null, privat: null }])).toEqual({ tekst: '', privat: false });
});
```

- [ ] **Step 2: Kør — verificér fejl**

Run: `cd mobile && npx jest redaktionRead -t "mapNarrativRow"`
Expected: FAIL — `mapNarrativRow is not a function`.

- [ ] **Step 3: Implementér i `redaktionRead.ts`**

```ts
export type PersonNarrativ = { tekst: string; privat: boolean };

export function mapNarrativRow(rows: { tekst: string | null; privat: boolean | null }[]): PersonNarrativ | null {
  const first = rows[0];
  if (!first) return null;
  return { tekst: first.tekst ?? '', privat: Boolean(first.privat) };
}

// Henter FØRSTE narrativ by id (uanset privat) = præcis den række red_upsert_narrativ redigerer.
// Prefill-kilde == skrive-mål; privat-flaget bevares af editoren på Gem (Codex 2B #1).
export async function fetchPersonNarrativ(id: string): Promise<PersonNarrativ | null> {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from('narrative').select('tekst,privat')
    .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
    .order('id', { ascending: true }).limit(1);
  if (error) throw new Error(error.message);
  return mapNarrativRow(data ?? []);
}
```

- [ ] **Step 4: Kør tests + tsc**

Run: `cd mobile && npx jest redaktionRead && npx tsc --noEmit`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(data): fetchPersonNarrativ (først-by-id = skrive-mål, bevar privat)"
```

---

## Task 3: Store — redaktion-model-slice + `loadRedaktionModel` + trigger

**Files:**
- Modify: `mobile/src/store/useStore.ts`
- Modify: `mobile/src/app/redaktion/_layout.tsx`

**Interfaces:**
- Consumes: `loadFromSupabase({includePrivat:true})` + `buildModel` (begge importeret i store allerede).
- Produces: state `redaktionModel: Model | null`, `redaktionAux: Aux | null`, `redaktionStatus: 'idle'|'loading'|'ready'|'error'`; action `loadRedaktionModel: () => Promise<void>`.

- [ ] **Step 1: Tilføj state + action i `useStore.ts`**

I `State`-typen (ved siden af `model`/`aux`):
```ts
  redaktionModel: import('../data/types').Model | null;
  redaktionAux: import('../data/types').Aux | null;
  redaktionStatus: 'idle' | 'loading' | 'ready' | 'error';
  loadRedaktionModel: () => Promise<void>;
```
I store-objektets initial-state:
```ts
  redaktionModel: null,
  redaktionAux: null,
  redaktionStatus: 'idle',
```
Tilføj action (ved siden af `load`):
```ts
  loadRedaktionModel: async () => {
    if (get().redaktionStatus === 'loading' || get().redaktionStatus === 'ready') return;
    set({ redaktionStatus: 'loading' });
    try {
      const res = await loadFromSupabase({ includePrivat: true });
      const model = buildModel(res.db);
      set({ redaktionModel: model, redaktionAux: res.aux, redaktionStatus: 'ready' });
    } catch {
      // Redaktion skal VIDE hvis det fejler — ingen seed-fallback, ingen tom-som-clean.
      set({ redaktionStatus: 'error' });
    }
  },
```

- [ ] **Step 2: Trigger i `redaktion/_layout.tsx`**

I `mobile/src/app/redaktion/_layout.tsx`, tilføj et `useEffect` der loader redaktion-modellen når rollen er redaktion:
```tsx
import { useEffect } from 'react';
import { useStore } from '../../store/useStore';
// ... i RedaktionLayout-komponenten, før return:
  const rolle = useStore((s) => s.rolle);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const loadRedaktionModel = useStore((s) => s.loadRedaktionModel);
  useEffect(() => {
    if (rolle === 'redaktion' && redaktionStatus === 'idle') loadRedaktionModel();
  }, [rolle, redaktionStatus, loadRedaktionModel]);
```
(Hvis `_layout.tsx` er en ren Stack uden komponent-krop, konvertér til en funktionskomponent der returnerer `<Stack ...>` og indsæt hooks før return.)

- [ ] **Step 3: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel (hvis device): log ind redaktion → redaktion-model loader (redaktionStatus→ready); publikums-faner uændrede.
```bash
git add mobile/src/store/useStore.ts mobile/src/app/redaktion/_layout.tsx
git commit -m "feat(redaktion): separat redaktion-model-slice + lazy load ved rolle=redaktion"
```

---

## Task 4: Editor — redaktionModel + køn-editor + familie/sektion-visning + narrativ-fix

**Files:**
- Modify: `mobile/src/app/redaktion/person/[id].tsx`

**Interfaces:**
- Consumes: `redaktionModel`/`redaktionAux`/`redaktionStatus` (Task 3); `parentsOf`/`spousesOf`/`childrenByMarriage` (selectors); `fetchPersonNarrativ` (Task 2); `fetchPersonEvidence` (køn, eksisterende).

- [ ] **Step 1: Skift header/bio-kilde + privat-init + køn-editor + familie/sektion-blokke**

Ændr `person/[id].tsx`. Erstat `model.byId[id]`-afhængigheden med `redaktionModel`. Tilføj imports:
```tsx
import { parentsOf, spousesOf, childrenByMarriage } from '../../../data/selectors';
import { fetchPersonNarrativ } from '../../../data/redaktionRead';
```
Skift store-selektorer (erstat `const model = useStore((s) => s.model)`):
```tsx
  const redaktionModel = useStore((s) => s.redaktionModel);
  const redaktionAux = useStore((s) => s.redaktionAux);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const person = id && redaktionModel ? redaktionModel.byId[id] : null;
```
Privat-init (erstat `useState(false)`):
```tsx
  const [privat, setPrivat] = useState(false);
  useEffect(() => { if (person) setPrivat(Boolean(person.privat)); }, [person?.privat]);
```
Narrativ-prefill (erstat `person.bio`-effekten) — hent skrive-målet + bevar privat:
```tsx
  const [narrativPrivat, setNarrativPrivat] = useState(false);
  useEffect(() => {
    if (id) fetchPersonNarrativ(id).then((n) => {
      setNarrativTekst(n?.tekst ?? '');
      setNarrativPrivat(n?.privat ?? false);
    }).catch(() => {});
  }, [id]);
```
Narrativ-Gem bevarer privat:
```tsx
  onPress={() => setPending({ art: 'narrativ', subjektType: 'person', subjektId: id!,
    vaerdi: narrativTekst, payload: { privat: narrativPrivat } })}
```
Loading/fejl/not-found-tilstande (erstat den nuværende `if (!person)`):
```tsx
  if (redaktionStatus === 'loading') return <CenterMsg title="Person">Henter…</CenterMsg>;
  if (redaktionStatus === 'error') return <CenterMsg title="Person">Kunne ikke hente redaktion-data.</CenterMsg>;
  if (!person) return <CenterMsg title="Person">Personen blev ikke fundet.</CenterMsg>;
```
(Tilføj en lille `CenterMsg`-helper i filen: `function CenterMsg({title,children}) { return (<View style={{flex:1,backgroundColor:Colors.paperBg}}><TopBar title={title}/><Body color={Colors.textMuted} style={{padding:24}}>{children}</Body></View>); }`)

Køn-editor (NYT) — indsæt under kerne-fakta-FELTER-loopet, før narrativ-sektionen:
```tsx
        {/* Køn (redigerbart — arbejdsværdi, ikke et fact) */}
        <View style={{ marginBottom: 6 }}>
          <Mono size={9} color={Colors.gold} style={{ marginTop: 6, marginBottom: 4 }}>KØN</Mono>
          <View style={{ flexDirection: 'row', gap: 8 }}>
            {(['mand', 'kvinde', 'ukendt'] as const).map((k) => {
              const aktiv = (ev?.koen ?? 'ukendt') === k;
              return (
                <Pressable key={k}
                  style={[editorStyles.koenPille, aktiv && editorStyles.koenPilleAktiv]}
                  onPress={() => setPending({ art: 'fakta', subjektType: 'person', subjektId: id!, felt: 'koen', vaerdi: k })}>
                  <BtnLabel size={12} color={aktiv ? '#fff' : Colors.textSecondary2}>{k}</BtnLabel>
                </Pressable>
              );
            })}
          </View>
        </View>
```
Familie & sektioner (read-only) — indsæt efter narrativ-sektionen (bruger redaktionModel/redaktionAux + eksisterende selektorer):
```tsx
        {/* Familie & relationer (read-only) */}
        {redaktionModel ? (() => {
          const foraeldre = parentsOf(redaktionModel, id!);
          const aegtefaeller = spousesOf(redaktionModel, id!);
          const aegteskaber = childrenByMarriage(redaktionModel, id!).filter((m) => m.children.length);
          const off = redaktionAux?.officesBy[id!] ?? [];
          const god = redaktionAux?.estatesBy[id!] ?? [];
          const kld = redaktionAux?.sourcesBy[id!] ?? [];
          const PersonRad = ({ pid, navn }: { pid: string | null; navn: string }) => (
            <Pressable style={editorStyles.relRad} disabled={!pid}
              onPress={() => pid && router.push(`/redaktion/person/${pid}` as never)}>
              <InitialBadge name={navn} size={28} />
              <Body size={14} style={{ marginLeft: 8 }}>{navn}</Body>
            </Pressable>
          );
          return (
            <View style={editorStyles.relSektion}>
              {foraeldre.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>FORÆLDRE</Mono>
                {foraeldre.map((p) => <PersonRad key={p.id} pid={p.id} navn={p.name} />)}</>) : null}
              {aegtefaeller.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>ÆGTEFÆLLER</Mono>
                {aegtefaeller.map((s, i) => <PersonRad key={s.id ?? i} pid={s.id} navn={s.name} />)}</>) : null}
              {aegteskaber.map((m, i) => (
                <View key={m.unionId ?? i}>
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>BØRN{m.spouseName ? ` · m. ${m.spouseName}` : ''}</Mono>
                  {m.children.map((c) => <PersonRad key={c.id} pid={c.id} navn={c.name} />)}
                </View>
              ))}
              {off.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>HVERV</Mono>
                {off.map((o, i) => <View key={i} style={editorStyles.sekRad}><Body size={13}>{o.label}</Body>{o.period ? <Mono size={9} color={Colors.textMuted}>{o.period}</Mono> : null}</View>)}</>) : null}
              {god.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>GODSER</Mono>
                {god.map((g, i) => <View key={i} style={editorStyles.sekRad}><Body size={13}>{g.navn}</Body>{g.period ? <Mono size={9} color={Colors.textMuted}>{g.period}</Mono> : null}</View>)}</>) : null}
              {kld.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>KILDER</Mono>
                {kld.map((s, i) => <View key={i} style={editorStyles.sekRad}><Body size={13}>{s.work}</Body><Mono size={9} color={Colors.textMuted}>{s.ref}</Mono></View>)}</>) : null}
            </View>
          );
        })() : null}
```
Opdatér `onApplied` (SkrivePreviewSheet) så køn-ændring re-henter evidens (køn): behold den eksisterende `fetchPersonEvidence(id).then(setEv)`.

Tilføj styles til `editorStyles`:
```tsx
  koenPille: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 16, paddingVertical: 6 },
  koenPilleAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  relSektion: { marginTop: 16, paddingTop: 14, borderTopWidth: 1, borderTopColor: Border.light },
  relLabel: { marginTop: 10, marginBottom: 4 },
  relRad: { flexDirection: 'row', alignItems: 'center', paddingVertical: 5 },
  sekRad: { paddingVertical: 4 },
```

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: ingen tsc-fejl; alle jest grønne.
Manuel (hvis device + redaktion-login): åbn en LEVENDE person → editoren ÅBNER (header) → familie/sektioner vist (matcher publikum) → skift køn (LIVE) → opdateres → narrativ: privat bio bevaret ved Gem. Ellers notér sprunget.
```bash
git add "mobile/src/app/redaktion/person/[id].tsx"
git commit -m "feat(redaktion): editor selv-forsynende (redaktionModel) + køn-editor + familie/sektion-visning + narrativ-privat-fix"
```

---

## Task 5: Integration — fuld jest + manuel e2e + docs

**Files:**
- Modify: `docs/changelog.md`, `docs/decisions.md`

- [ ] **Step 1: Fuld jest + tsc**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: alle grønne (eksisterende 94 + mapAppPersons + narrativ-mapping), tsc rent.

- [ ] **Step 2: Manuel e2e (web)**

`cd mobile && npm run web` → `/redaktion` → log ind redaktion → vent på redaktion-model → Entiteter → åbn en LEVENDE person (tag "levende") → editoren ÅBNER, header korrekt → familie (forældre/ægtefæller/børn) + sektioner (hverv/godser/kilder) vist, matcher publikums-visning → skift køn til LIVE → vælg "kvinde" → header-køn opdateres → narrativ med privat bio: Gem bevarer privat. Notér bestået/sprunget.

- [ ] **Step 3: Changelog + decisions + commit**

Tilføj entry i `docs/changelog.md` (2B editor-dybde) + `docs/decisions.md` (separat redaktion-model, Codex-recalibrering, narrativ-privat-fix). Commit:
```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: plan 2B — editor-dybde changelog + decisions"
```

---

## Self-Review

**Spec coverage:**
- §2.1 loadFromSupabase includePrivat + getAll → Task 1. §2.1 store-slice + loadRedaktionModel → Task 3. §2.2 trigger → Task 3. §2.3 privat på AppPerson → Task 1. §3 editor header/familie/sektion fra redaktionModel + køn-editor + privat-init → Task 4. §4 narrativ-fix (fetchPersonNarrativ + bevar privat) → Task 2 + Task 4. §5 fejl-tilstande → Task 3 (status='error') + Task 4 (CenterMsg). §6 test → Task 1,2,5. Alle dækket.
- **Non-goals** (familie/sektion-redigering, medier, generisk editor) IKKE planlagt — korrekt.

**Placeholder-scan:** ingen TBD/TODO; komplet kode. `_layout.tsx`-konvertering til funktionskomponent (Task 3 Step 2) er beskrevet betinget — implementeren tjekker den faktiske form.

**Type-konsistens:** `AppPerson.privat` (Task 1) → brugt i Task 4 privat-init. `PersonNarrativ`/`mapNarrativRow` (Task 2) → brugt i Task 4. `redaktionModel`/`redaktionAux`/`redaktionStatus`/`loadRedaktionModel` (Task 3) → brugt i Task 4. `parentsOf`/`spousesOf`/`childrenByMarriage` returtyper (ModelPerson[] / {id,name}[] / {unionId,spouseName,children}[]) matcher render-brug i Task 4. Køn-vocab `mand/kvinde/ukendt` konsistent med buildRpcCall-koen-case.
