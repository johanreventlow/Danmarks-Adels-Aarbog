# Plan 2C-1 — Entitetslister (read-only) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gør redaktions-appens Entiteter-tab til en type-menu (Personer + Godser + Kilder + Organisationer + Medier + Våben) med read-only lister, så redaktøren kan browse alle entitetstyper.

**Architecture:** Udvid `buildAux` med flade lister fra de rå entitets-arrays den allerede modtager (+ ét nyt `coat_of_arms`-fetch). Læs dem fra `redaktionAux` (2B-modellen). Entiteter-tab bliver en type-menu; person-listen (2A) udtrækkes til en genbrugelig komponent; en generisk `entitet/[type]`-rute viser de read-only ikke-person-lister. Ingen write — der findes ingen entitets-write-RPC'er.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand, Jest.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-28-plan2c1-entitetslister-design.md` (autoritativ).
- **Branch:** opret feature-branch fra `main` (`feat/plan2c1-entitetslister`); ingen merge/push uden eksplicit godkendelse.
- **Read-only:** ingen write-RPC for source/organisation/estate/media/coat_of_arms → 2C-1 redigerer/opretter INTET.
- **Genbrug allerede-loadet data:** de fire (kilde/org/medie/gods) kommer fra `buildAux`'s eksisterende input; kun `coat_of_arms` er et nyt fetch.
- **Auth-state-kontrakt (spec §4b):** `rolle !== 'redaktion'` → "Kræver redaktør-rolle" (IKKE "Henter…"); `redaktionStatus==='loading'`/`'idle'`-under-redaktør → "Henter…"; `'error'` → fejl; `'ready'` → lister. "Henter…" ALDRIG permanent for ikke-redaktører.
- **majorat** udeladt (slags af estate, ingen egen tabel); **våben** = `coat_of_arms` (id/blasonering/note).
- **Tap:** ikke-person-lister ikke-tappbare (D1); Personer → editor (2B) uændret.
- **Tokens/Typography** (`Serif`/`Mono`/`Body`/`BtnLabel`/`InitialBadge`, tokens). Ingen rå hex (#fff/rgba OK).
- **media har ingen person_id** → medie-liste fra rå medie-rækker (id/slags/titel/kunstner/datering).
- **Test-niveau matcher risiko:** buildAux-mappings = TDD/jest; skærme = tsc + manuel.
- Ingen Claude-attribution i commits. Conventional Commits, dansk.

---

## File Structure

**Ændrede:**
- `mobile/src/data/types.ts` — `Aux` + 5 entry-typer + `RawArms`.
- `mobile/src/data/load.ts` — hent `coat_of_arms`; send `arms` til `buildAux`.
- `mobile/src/data/buildAux.ts` — `BuildAuxInput.arms` + 5 flade lister.
- `mobile/src/app/redaktion/_layout.tsx` — registrér `entitet/person` + `entitet/[type]`.
- `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` — person-liste → type-menu.

**Nye:**
- `mobile/src/components/redaktion/RedPersonListe.tsx` — udtrukket 2A person-liste.
- `mobile/src/app/redaktion/entitet/person.tsx` — Personer-rute → `<RedPersonListe/>`.
- `mobile/src/app/redaktion/entitet/[type].tsx` — generisk read-only liste (gods/kilde/organisation/medie/vaaben).

---

## Task 1: `buildAux` flade lister + `coat_of_arms`-fetch

**Files:**
- Modify: `mobile/src/data/types.ts`, `mobile/src/data/load.ts`, `mobile/src/data/buildAux.ts`
- Test: `mobile/src/data/__tests__/buildAux.test.ts` (ny)

**Interfaces:**
- Produces (på `Aux`): `kildeListe`, `orgListe`, `medieListe`, `godsListe`, `vaabenListe` (typer i Step 1). `RawArms = { id: number|string; blasonering: string|null; note: string|null }`. `BuildAuxInput.arms?: RawArms[]`.

- [ ] **Step 1: Tilføj typer i `types.ts`**

I `types.ts`, tilføj `RawArms` (ved de øvrige Raw-typer) + de fem liste-typer på `Aux`:
```ts
export type RawArms = { id: number | string; blasonering: string | null; note: string | null };

// På Aux-typen (ved estateList):
  kildeListe: { id: string; titel: string; slags: string; udgave: string }[];
  orgListe: { id: string; navn: string; slags: string }[];
  medieListe: { id: string; titel: string; slags: string; kunstner: string; datering: string }[];
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
```

- [ ] **Step 2: Skriv fejlende test**

Opret `mobile/src/data/__tests__/buildAux.test.ts`:
```ts
import { buildAux } from '../buildAux';

const base = { extIds: [], sources: [], relations: [], estates: [], orgs: [], media: [], lineage: [], arms: [] };

test('buildAux: kildeListe fra sources (felt-map + sort)', () => {
  const aux = buildAux({ ...base, sources: [
    { id: 2, slags: 'kirkebog', titel: 'Øster', udgave: '1700', ekstern: null },
    { id: 1, slags: 'bog', titel: 'Aarbog', udgave: 'DAA 2018', ekstern: null },
  ] as never });
  expect(aux.kildeListe.map((k) => k.titel)).toEqual(['Aarbog', 'Øster']); // dansk sort, Ø sidst
  expect(aux.kildeListe[0]).toEqual({ id: '1', titel: 'Aarbog', slags: 'bog', udgave: 'DAA 2018' });
});

test('buildAux: vaabenListe fra arms (null-fallback)', () => {
  const aux = buildAux({ ...base, arms: [{ id: 5, blasonering: null, note: 'x' }] as never });
  expect(aux.vaabenListe).toEqual([{ id: '5', blasonering: '', note: 'x' }]);
});

test('buildAux: godsListe komplet (inkl. ejerløse) m. ownerCount', () => {
  const aux = buildAux({ ...base,
    estates: [{ id: 1, navn: 'Brahetrolleborg', slags: null }, { id: 2, navn: 'Ejerløs', slags: null }] as never,
    relations: [{ subjekt_type: 'person', subjekt_id: 9, objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: null }] as never,
  });
  const brahe = aux.godsListe.find((g) => g.id === '1');
  const ejerloes = aux.godsListe.find((g) => g.id === '2');
  expect(brahe?.ownerCount).toBe(1);
  expect(ejerloes?.ownerCount).toBe(0); // ejerløs gods er MED (modsat estateList)
});

test('buildAux: orgListe + medieListe felt-map', () => {
  const aux = buildAux({ ...base,
    orgs: [{ id: 1, navn: 'Hæren', slags: 'myndighed' }] as never,
    media: [{ id: 1, slags: 'foto', titel: 'Portræt', kunstner: 'NN', datering: '1900' }] as never });
  expect(aux.orgListe[0]).toEqual({ id: '1', navn: 'Hæren', slags: 'myndighed' });
  expect(aux.medieListe[0]).toEqual({ id: '1', titel: 'Portræt', slags: 'foto', kunstner: 'NN', datering: '1900' });
});
```

- [ ] **Step 3: Kør — verificér fejl**

Run: `cd mobile && npx jest buildAux`
Expected: FAIL (kildeListe/vaabenListe udefineret på aux).

- [ ] **Step 4: Implementér i `buildAux.ts`**

Tilføj `arms` til `BuildAuxInput` + destrukturering. Importér `compareDanish` (allerede importeret) + `RawArms` fra types. Byg de fem lister før `return` og tilføj dem til retur-objektet:
```ts
  // Flade entitets-lister (2C-1, read-only browse). Rene mappings, dansk-sorteret.
  const kildeListe = (sources || []).map((s) => ({
    id: String(s.id), titel: s.titel ?? '', slags: s.slags ?? '', udgave: s.udgave ?? '',
  })).sort((a, b) => compareDanish(a.titel, b.titel));
  const orgListe = (orgs || []).map((o) => ({
    id: String(o.id), navn: o.navn ?? '(uden navn)', slags: o.slags ?? '',
  })).sort((a, b) => compareDanish(a.navn, b.navn));
  const medieListe = (media || []).map((m) => ({
    id: String((m as { id?: unknown }).id ?? ''), titel: String((m as { titel?: unknown }).titel ?? ''),
    slags: String((m as { slags?: unknown }).slags ?? ''), kunstner: String((m as { kunstner?: unknown }).kunstner ?? ''),
    datering: String((m as { datering?: unknown }).datering ?? ''),
  })).sort((a, b) => compareDanish(a.titel, b.titel));
  // godsListe: KOMPLET (alle estates, ikke kun ejede); ownerCount fra ownersByEstate (0 hvis ingen).
  const godsListe = (estates || []).map((e) => ({
    id: String(e.id), navn: e.navn ?? '(uden navn)', slags: e.slags ?? '',
    ownerCount: (ownersByEstate[String(e.id)] || []).length,
  })).sort((a, b) => compareDanish(a.navn, b.navn));
  const vaabenListe = (arms || []).map((a) => ({
    id: String(a.id), blasonering: a.blasonering ?? '', note: a.note ?? '',
  }));

  return {
    // ... eksisterende felter ...
    kildeListe, orgListe, medieListe, godsListe, vaabenListe,
  };
```
(`ownersByEstate` er allerede bygget tidligere i `buildAux` — genbrug den.)

- [ ] **Step 5: Hent `coat_of_arms` i `load.ts`**

I `load.ts`: importér `RawArms` fra types. I `Promise.all`-arrayet (efter `media`-getAll, før/efter lineage), tilføj:
```ts
      getAll<RawArms>(() => sb.from('coat_of_arms').select('id,blasonering,note')).catch(() => [] as RawArms[]),
```
Tilføj `arms` til destruktureringen af `Promise.all`-resultatet (samme orden som arrayet), og send det til buildAux:
```ts
  const aux = buildAux({ extIds, sources, relations, estates, orgs, media, lineage, arms });
```
(`.catch(() => [])` — tolerant som lineage, hvis tabellen mangler i en gammel base.)

- [ ] **Step 6: Kør tests + tsc**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: alle grønne (eksisterende 100 + 4 nye buildAux), tsc rent. Hvis tsc kræver `arms` i `SEED.aux`/seed: tilføj tomme lister (`kildeListe: [], orgListe: [], medieListe: [], godsListe: [], vaabenListe: []`) til seed-aux'en.

- [ ] **Step 7: Commit**

```bash
git add mobile/src/data/types.ts mobile/src/data/load.ts mobile/src/data/buildAux.ts mobile/src/data/__tests__/buildAux.test.ts mobile/src/data/seed.ts
git commit -m "feat(data): flade entitets-lister i buildAux + coat_of_arms-fetch (2C-1)"
```

---

## Task 2: Udtræk `RedPersonListe` + `entitet/person`-rute

**Files:**
- Create: `mobile/src/components/redaktion/RedPersonListe.tsx`
- Create: `mobile/src/app/redaktion/entitet/person.tsx`
- Modify: `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` (render `<RedPersonListe/>` midlertidigt)
- Modify: `mobile/src/app/redaktion/_layout.tsx` (registrér ruter)

**Interfaces:**
- Produces: `<RedPersonListe />` (default export) — den nuværende 2A person-liste-adfærd, uændret.

- [ ] **Step 1: Udtræk person-listen til komponent**

Flyt HELE den nuværende komponent-krop fra `(red-tabs)/entiteter.tsx` (søg/alfabet/sort/tags/fejl,
`fetchRedaktionPersoner`, `searchPool`, `SectionList`, `PersonRow`/`SortPill`, styles) til en ny fil
`mobile/src/components/redaktion/RedPersonListe.tsx`. Eksportér som `export function RedPersonListe()`.
Justér relative imports (komponenten ligger nu i `components/redaktion/`, så `../../` → `../../`):
`InitialBadge`/`TopBar`/`Typography` = `../`; `data/...`/`store`/`theme` = `../../`. Indholdet er ellers
IDENTISK med 2A (ingen adfærdsændring).

- [ ] **Step 2: `entitet/person.tsx`-rute**

`mobile/src/app/redaktion/entitet/person.tsx`:
```tsx
import { RedPersonListe } from '../../../components/redaktion/RedPersonListe';
export default function EntitetPerson() {
  return <RedPersonListe />;
}
```

- [ ] **Step 3: Midlertidig: entiteter.tsx renderer komponenten**

Erstat `(red-tabs)/entiteter.tsx`'s krop midlertidigt (bliver type-menu i Task 4) med:
```tsx
import { RedPersonListe } from '../../../components/redaktion/RedPersonListe';
export default function Entiteter() {
  return <RedPersonListe />;
}
```
(Bevarer 2A-adfærd indtil Task 4.)

- [ ] **Step 4: Registrér ruter i `_layout.tsx`**

I `mobile/src/app/redaktion/_layout.tsx`, tilføj til `<Stack>`:
```tsx
      <Stack.Screen name="entitet/person" />
      <Stack.Screen name="entitet/[type]" />
```

- [ ] **Step 5: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: ingen tsc-fejl; jest grøn.
Manuel (hvis device): Entiteter-tab viser stadig person-listen (uændret); `/redaktion/entitet/person` virker.
```bash
git add mobile/src/components/redaktion/RedPersonListe.tsx mobile/src/app/redaktion/entitet/person.tsx "mobile/src/app/redaktion/(red-tabs)/entiteter.tsx" mobile/src/app/redaktion/_layout.tsx
git commit -m "refactor(redaktion): udtræk RedPersonListe + entitet/person-rute"
```

---

## Task 3: Generisk read-only liste `entitet/[type].tsx`

**Files:**
- Create: `mobile/src/app/redaktion/entitet/[type].tsx`

**Interfaces:**
- Consumes: `redaktionAux` (Task 1-lister), `redaktionStatus`, `rolle` (store).

- [ ] **Step 1: Implementér generisk liste m. auth-state**

`mobile/src/app/redaktion/entitet/[type].tsx`:
```tsx
import { useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body, Mono, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

type Row = { id: string; titel: string; under: string };
const TITLER: Record<string, string> = {
  gods: 'Godser', kilde: 'Kilder', organisation: 'Organisationer', medie: 'Medier', vaaben: 'Våben',
};

export default function EntitetListe() {
  const { type } = useLocalSearchParams<{ type: string }>();
  const rolle = useStore((s) => s.rolle);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const aux = useStore((s) => s.redaktionAux);
  const [query, setQuery] = useState('');
  const titel = TITLER[type ?? ''] ?? 'Entiteter';

  // type → rækker fra redaktionAux (read-only).
  const rows = useMemo<Row[]>(() => {
    if (!aux) return [];
    if (type === 'gods') return aux.godsListe.map((g) => ({ id: g.id, titel: g.navn, under: `${g.slags || 'gods'} · ${g.ownerCount} ejere` }));
    if (type === 'kilde') return aux.kildeListe.map((k) => ({ id: k.id, titel: k.titel, under: [k.slags, k.udgave].filter(Boolean).join(' · ') }));
    if (type === 'organisation') return aux.orgListe.map((o) => ({ id: o.id, titel: o.navn, under: o.slags }));
    if (type === 'medie') return aux.medieListe.map((m) => ({ id: m.id, titel: m.titel || '(uden titel)', under: [m.slags, m.kunstner, m.datering].filter(Boolean).join(' · ') }));
    if (type === 'vaaben') return aux.vaabenListe.map((v) => ({ id: v.id, titel: v.blasonering || '(uden blasonering)', under: v.note }));
    return [];
  }, [aux, type]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? rows.filter((r) => r.titel.toLowerCase().includes(q)) : rows;
  }, [rows, query]);

  // Auth-state (spec §4b): "Henter…" ALDRIG permanent for ikke-redaktører.
  if (rolle !== 'redaktion') return <Msg title={titel}>Kræver redaktør-rolle.</Msg>;
  if (redaktionStatus === 'error') return <Msg title={titel}>Kunne ikke hente redaktion-data.</Msg>;
  if (redaktionStatus !== 'ready') return <Msg title={titel}>Henter…</Msg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={titel} />
      <TextInput style={styles.input} placeholder="Søg…" placeholderTextColor={Colors.textMuted}
        value={query} onChangeText={setQuery} autoCorrect={false} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {filtered.length === 0 ? (
          <Body color={Colors.textMuted}>Ingen {titel.toLowerCase()}.</Body>
        ) : (
          filtered.map((r) => (
            // Ikke-tappbar (D1) — ingen detail-editor endnu.
            <View key={r.id} style={styles.row}>
              <Serif size={16}>{r.titel}</Serif>
              {r.under ? <Mono size={9} color={Colors.textMuted}>{r.under}</Mono> : null}
            </View>
          ))
        )}
      </ScrollView>
    </View>
  );
}

function Msg({ title, children }: { title: string; children: string }) {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={title} />
      <Body color={Colors.textMuted} style={{ padding: 24 }}>{children}</Body>
    </View>
  );
}

const styles = StyleSheet.create({
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, marginHorizontal: 16, marginTop: 8, paddingHorizontal: 12, paddingVertical: 9,
    fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  row: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, padding: 12, marginBottom: 7 },
});
```

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel (hvis device + redaktion): `/redaktion/entitet/gods` viser gods-liste m. ejer-tæller; kilde/organisation/medie/vaaben tilsvarende; ikke logget ind → "Kræver redaktør-rolle".
```bash
git add "mobile/src/app/redaktion/entitet/[type].tsx"
git commit -m "feat(redaktion): generisk read-only entitets-liste (gods/kilde/org/medie/våben)"
```

---

## Task 4: Entiteter-tab → type-menu

**Files:**
- Modify: `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx`

**Interfaces:**
- Consumes: `redaktionModel`/`redaktionAux`/`redaktionStatus`/`rolle` (store); `useRouter`.

- [ ] **Step 1: Erstat med type-menu**

`(red-tabs)/entiteter.tsx`:
```tsx
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function Entiteter() {
  const router = useRouter();
  const rolle = useStore((s) => s.rolle);
  const status = useStore((s) => s.redaktionStatus);
  const model = useStore((s) => s.redaktionModel);
  const aux = useStore((s) => s.redaktionAux);

  if (rolle !== 'redaktion')
    return <View style={s.wrap}><TopBar title="Entiteter" showBack={false} /><Body color={Colors.textMuted} style={{ padding: 24 }}>Kræver redaktør-rolle.</Body></View>;
  if (status === 'error')
    return <View style={s.wrap}><TopBar title="Entiteter" showBack={false} /><Body color={Colors.textMuted} style={{ padding: 24 }}>Kunne ikke hente redaktion-data.</Body></View>;
  if (status !== 'ready')
    return <View style={s.wrap}><TopBar title="Entiteter" showBack={false} /><Body color={Colors.textMuted} style={{ padding: 24 }}>Henter…</Body></View>;

  const celler = [
    { n: model?.persons.length ?? 0, label: 'Personer', rute: '/redaktion/entitet/person' },
    { n: aux?.godsListe.length ?? 0, label: 'Godser', rute: '/redaktion/entitet/gods' },
    { n: aux?.kildeListe.length ?? 0, label: 'Kilder', rute: '/redaktion/entitet/kilde' },
    { n: aux?.orgListe.length ?? 0, label: 'Organisationer', rute: '/redaktion/entitet/organisation' },
    { n: aux?.medieListe.length ?? 0, label: 'Medier', rute: '/redaktion/entitet/medie' },
    { n: aux?.vaabenListe.length ?? 0, label: 'Våben', rute: '/redaktion/entitet/vaaben' },
  ];

  return (
    <View style={s.wrap}>
      <TopBar title="Entiteter" showBack={false} />
      <ScrollView contentContainerStyle={{ padding: 18 }}>
        <View style={s.grid}>
          {celler.map((c) => (
            <Pressable key={c.label} style={s.cell} onPress={() => router.navigate(c.rute as never)}>
              <Serif size={21} color={Colors.bordeaux}>{c.n}</Serif>
              <Body size={13}>{c.label}</Body>
            </Pressable>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: Colors.paperBg },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 9 },
  cell: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: 13, padding: 14, minWidth: '47%' },
});
```

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit && npx jest`
Expected: ingen tsc-fejl; jest grøn.
Manuel (hvis device + redaktion): Entiteter-tab → 6-korts type-menu m. tællere → tap Personer → 2A-liste → tap person → editor; tap Godser/Kilder/… → read-only liste; ikke logget ind → "Kræver redaktør-rolle".
```bash
git add "mobile/src/app/redaktion/(red-tabs)/entiteter.tsx"
git commit -m "feat(redaktion): Entiteter-tab → type-menu (6 typer, auth-state)"
```

---

## Task 5: Integration + docs

**Files:**
- Modify: `docs/changelog.md`, `docs/decisions.md`

- [ ] **Step 1: Fuld jest + tsc**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: alle grønne, tsc rent.

- [ ] **Step 2: Manuel e2e (web)**

`cd mobile && npm run web` → `/redaktion` → log ind redaktion → vent på redaktion-model → Entiteter-tab → 6 kort m. tællere → hver type-liste viser data (godser m. ejer-tæller, kilder m. udgave, org, medier, våben) → ikke-person ikke-tappbar → Personer → 2A-liste → tap → editor. Log ud → Entiteter viser "Kræver redaktør-rolle" (ikke "Henter…"). Notér bestået/sprunget.

- [ ] **Step 3: Changelog + decisions + commit**

Tilføj entry i `docs/changelog.md` (2C-1 entitetslister) + `docs/decisions.md` (read-only via udvidet buildAux; majorat=slags-af-estate; våben fundet via Codex). Commit:
```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: plan 2C-1 — entitetslister changelog + decisions"
```

---

## Self-Review

**Spec coverage:**
- §2 flade lister i buildAux + coat_of_arms-fetch → Task 1. §3 type-menu + person-rute-genbrug + generisk [type]-rute → Task 2 (RedPersonListe + person-rute), Task 3 ([type]), Task 4 (menu). §4 read-only lister + ikke-tappbar (D1) → Task 3. §4b auth-state-kontrakt → Task 3 + Task 4 (rolle/status-guards). §5 test → Task 1 (buildAux-mappings), Task 5 (manuel). Alle dækket.
- **Non-goals** (write/opret, detail-skærm, relations-redigering, majorat) IKKE planlagt — korrekt.

**Placeholder-scan:** ingen TBD/TODO; komplet kode. Task 2 Step 1 (udtræk) er en mekanisk flytning — implementeren flytter 2A-kroppen 1:1 + justerer imports.

**Type-konsistens:** `Aux.{kilde,org,medie,gods,vaaben}Liste` (Task 1) → forbrugt i Task 3/4. `RawArms` (Task 1) → load.ts + buildAux. Rute-stier `/redaktion/entitet/<type>` (Task 4) matcher `entitet/[type].tsx` + `entitet/person.tsx` (Task 2/3). `redaktionModel`/`redaktionAux`/`redaktionStatus`/`rolle` (2B) → Task 3/4. type-værdier (gods/kilde/organisation/medie/vaaben) konsistente mellem menu-ruter (Task 4) og [type]-mapping (Task 3).
