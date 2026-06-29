# Versionering + Hyperlinks — App-lag (RN/Expo) Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Byg RN/Expo-app-laget der gør hyperlinks i narrativer redigerbare + klikbare, og giver redaktøren en ændringshistorik med fortryd + en døde-links-rapport — oven på DB-laget fra `2026-06-30-versionering-hyperlinks-db-lag.md`.

**Architecture:** Token-parsing/-indsættelse er rene, unit-testede TS-funktioner (`src/lib/mentions.ts`). En `NarrativRenderer` gør segmenter klikbare via Expo Router. En @-vælger-sheet (genbruger eksisterende Modal/sheet-mønster) indsætter tokens i narrativ-TextInput'en. Historik + fortryd + døde-links læser DB-laget via `supabase.rpc(...)`/`.from(view)` i `redaktionRead`/`redaktionWrite`, vist på en ny Expo Router-skærm.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand (`src/store/useStore.ts`), Jest (pure-funktion-tests), `@supabase/supabase-js`.

## Global Constraints

- **Forudsætning:** DB-lag-planen (`2026-06-30-versionering-hyperlinks-db-lag.md`) er implementeret og kørt mod basen. Denne plan KONSUMERER dens API.
- **DB-API (eksakte navne, fra DB-planen):**
  - `supabase.rpc('hist_for_subjekt', { p_type, p_id })` → `change_set[]` (redaktion-only)
  - `supabase.rpc('hist_events', { p_change_set_id })` → `change_event[]`
  - `supabase.rpc('red_fortryd_change_set', { p_change_set_id, p_force })` → `{ reversal_change_set, divergenser }`
  - `supabase.from('red_doede_links').select('*')` → `text_mention`-rækker m. manglende mål
- **Token-grammatik (spec §5.1):** `[[<type>:<id>|<visningstekst>]]`; type ∈ `person|estate|place|organisation|source|coat_of_arms|family|historical_event|media|lineage`; id heltal uden foranstillet nul; `|[]` escapes som `\|\[\]`. Malformet → vis som rå tekst.
- **Data-lag-mønster:** ren build-/map-funktion (netværksfri, unit-testet) + tynd udfør-funktion (`supabase.rpc/.from`, ikke unit-testet) — som eksisterende `buildRpcCall`/`submitChange` (`src/data/redaktionWrite.ts:38,143`).
- **Tema:** brug `Colors`/`Border`/`Radius` fra `src/theme/tokens.ts` (fx `Colors.bordeaux` til links, `Colors.danger` til fortryd, `Colors.textMuted` til mono-labels). Aldrig hardcodede hex.
- **Styling:** `StyleSheet.create()`, funktionskomponenter + hooks (matcher `src/components/redaktion/*`).
- **Test-niveau:** rene funktioner → jest. Komponenter/skærme → manuel verifikation i Expo (ingen RNTL-setup i repoet). Rapportér eksplicit hvad der er jest-dækket vs. manuelt.
- **Commit-stil:** Conventional Commits, dansk. Ingen Claude-attribution. Afslut med `Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd`.

**UI-beslutninger (defaults — kan overstyres af bruger før eksekvering):**
- **D1:** Historik = dedikeret Expo Router-skærm `src/app/redaktion/historik/[id].tsx`, linket fra person-editoren. (Alternativ: modal i editoren.)
- **D2:** @-vælger = Modal bottom-sheet (samme mønster som `UnionTypeSheet`), PoC kun person-mål. (Andre entitetstyper additivt senere.)
- **D3:** Døde-links-rapport = sektion på historik-skærmen (ikke egen rute).

**Spec:** `docs/superpowers/specs/2026-06-30-versionering-og-hyperlinks-design.md`.

---

## Sådan køres tests

```bash
cd mobile
npm test -- src/lib/__tests__/mentions.test.ts        # Task 1, 3
npm test -- src/data/__tests__/redaktionWrite.test.ts # Task 5
npm test -- src/data/__tests__/redaktionRead.test.ts  # Task 4, 7
npm run start  # Expo — manuel verifikation af komponenter/skærme (Task 2, 6)
```

---

## Filstruktur

| Fil | Ansvar | Ændring |
|---|---|---|
| `mobile/src/lib/mentions.ts` | Token parse/insert (ren) | Create |
| `mobile/src/lib/__tests__/mentions.test.ts` | Jest | Create |
| `mobile/src/components/NarrativRenderer.tsx` | Klikbar narrativ-visning | Create |
| `mobile/src/components/redaktion/MentionPicker.tsx` | @-vælger-sheet | Create |
| `mobile/src/app/redaktion/person/[id].tsx` | Narrativ-editor | Modify (`:427–458`) |
| `mobile/src/app/person/[id].tsx` | Person-visning | Modify (render narrativ klikbart) |
| `mobile/src/data/redaktionRead.ts` | Læs historik/døde-links | Modify |
| `mobile/src/data/redaktionWrite.ts` | Fortryd-RPC | Modify (`Change` + `buildRpcCall`) |
| `mobile/src/data/__tests__/redaktionRead.test.ts` | Jest mappers | Modify |
| `mobile/src/app/redaktion/historik/[id].tsx` | Historik-skærm | Create |

---

## Task 1: Token-parser (ren TS)

**Files:**
- Create: `mobile/src/lib/mentions.ts`
- Test: `mobile/src/lib/__tests__/mentions.test.ts`

**Interfaces:**
- Produces:
  - `type MentionType = 'person'|'estate'|'place'|'organisation'|'source'|'coat_of_arms'|'family'|'historical_event'|'media'|'lineage'`
  - `type Segment = { kind: 'text'; text: string } | { kind: 'link'; maalType: MentionType; maalId: number; label: string }`
  - `parseNarrativ(text: string): Segment[]` — splitter tekst i tekst/link-segmenter; malformede tokens bliver `text`-segmenter; håndterer `\|\[\]`-escapes i label.

- [ ] **Step 1: Skriv failing test**

```typescript
import { parseNarrativ } from '../mentions';

describe('parseNarrativ', () => {
  it('splitter gyldigt token til link-segment', () => {
    const segs = parseNarrativ('Se [[person:482|Chr. D. R.]] her.');
    expect(segs).toEqual([
      { kind: 'text', text: 'Se ' },
      { kind: 'link', maalType: 'person', maalId: 482, label: 'Chr. D. R.' },
      { kind: 'text', text: ' her.' },
    ]);
  });
  it('malformet/ukendt type bliver rå tekst', () => {
    const segs = parseNarrativ('[[person:abc|x]] [[ufo:1|y]]');
    expect(segs.every((s) => s.kind === 'text')).toBe(true);
  });
  it('afkoder escaped pipe i label', () => {
    const segs = parseNarrativ('[[person:9|a\\|b]]');
    expect(segs).toEqual([{ kind: 'link', maalType: 'person', maalId: 9, label: 'a|b' }]);
  });
});
```

- [ ] **Step 2: Kør → FAIL** (`Cannot find module '../mentions'`)

Run: `cd mobile && npm test -- src/lib/__tests__/mentions.test.ts`

- [ ] **Step 3: Implementér `mentions.ts`**

```typescript
// Token-grammatik (spec §5.1): [[<type>:<id>|<visningstekst>]]
export type MentionType =
  | 'person' | 'estate' | 'place' | 'organisation' | 'source'
  | 'coat_of_arms' | 'family' | 'historical_event' | 'media' | 'lineage';

const TYPES = new Set<string>([
  'person','estate','place','organisation','source',
  'coat_of_arms','family','historical_event','media','lineage',
]);

export type Segment =
  | { kind: 'text'; text: string }
  | { kind: 'link'; maalType: MentionType; maalId: number; label: string };

// type:id-hoved; label fanges manuelt frem til uescaped ]]
const HEAD = /\[\[(person|estate|place|organisation|source|coat_of_arms|family|historical_event|media|lineage):(0|[1-9][0-9]*)\|/;

function unescape(s: string): string {
  return s.replace(/\\([|[\]])/g, '$1');
}

export function parseNarrativ(text: string): Segment[] {
  const out: Segment[] = [];
  let rest = text ?? '';
  let buf = '';
  while (rest.length > 0) {
    const m = HEAD.exec(rest);
    if (!m || m.index !== 0) {
      // ingen token ved start: flyt ét tegn til buffer
      const nextStart = m ? m.index : rest.length;
      buf += rest.slice(0, Math.max(nextStart, 1));
      rest = rest.slice(Math.max(nextStart, 1));
      continue;
    }
    // find uescaped ]] efter hovedet
    const after = rest.slice(m[0].length);
    let i = 0, label = '';
    let closed = false;
    while (i < after.length) {
      if (after[i] === '\\' && i + 1 < after.length) { label += after.slice(i, i + 2); i += 2; continue; }
      if (after[i] === ']' && after[i + 1] === ']') { closed = true; break; }
      label += after[i]; i += 1;
    }
    if (!closed || !TYPES.has(m[1])) {  // malformet → rå tekst
      buf += rest[0]; rest = rest.slice(1); continue;
    }
    if (buf) { out.push({ kind: 'text', text: buf }); buf = ''; }
    out.push({ kind: 'link', maalType: m[1] as MentionType, maalId: Number(m[2]), label: unescape(label) });
    rest = after.slice(i + 2);
  }
  if (buf) out.push({ kind: 'text', text: buf });
  return out;
}
```

- [ ] **Step 4: Kør → PASS**

- [ ] **Step 5: Commit**

```bash
git add mobile/src/lib/mentions.ts mobile/src/lib/__tests__/mentions.test.ts
git commit -m "feat(app): hyperlinks — parseNarrativ token-parser + tests

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 2: `NarrativRenderer` — klikbar visning

**Files:**
- Create: `mobile/src/components/NarrativRenderer.tsx`
- Modify: `mobile/src/app/person/[id].tsx` (render narrativ via komponenten)

**Interfaces:**
- Consumes: `parseNarrativ` (T1), Expo Router `useRouter`.
- Produces: `<NarrativRenderer tekst={string} />` — `<Text>` med `Pressable`-spans for links; person-links navigerer til `/person/[id]`, øvrige typer vises som dæmpet ikke-klikbar tekst i PoC (D2).

- [ ] **Step 1: Implementér komponenten**

```tsx
import React from 'react';
import { Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { parseNarrativ } from '../lib/mentions';
import { Colors } from '../theme/tokens';

export function NarrativRenderer({ tekst }: { tekst: string }) {
  const router = useRouter();
  const segs = parseNarrativ(tekst);
  return (
    <Text style={styles.body}>
      {segs.map((s, i) => {
        if (s.kind === 'text') return <Text key={i}>{s.text}</Text>;
        if (s.maalType === 'person') {
          return (
            <Text key={i} style={styles.link}
              onPress={() => router.push(`/person/${s.maalId}`)}
              accessibilityRole="link">
              {s.label}
            </Text>
          );
        }
        return <Text key={i} style={styles.linkInaktiv}>{s.label}</Text>;
      })}
    </Text>
  );
}

const styles = StyleSheet.create({
  body: { color: Colors.textSecondary, fontSize: 16, lineHeight: 24 },
  link: { color: Colors.bordeaux, textDecorationLine: 'underline' },
  linkInaktiv: { color: Colors.textMuted },
});
```

- [ ] **Step 2: Brug den i person-visningen**

I `mobile/src/app/person/[id].tsx`: find hvor narrativ-prosaen vises som ren `<Text>` og erstat med `<NarrativRenderer tekst={narrativTekst} />` (importér øverst). Hvis person-visningen i dag ikke viser narrativ, tilføj en sektion under de strukturerede fakta.

- [ ] **Step 3: Manuel verifikation** (jest dækker ikke RN-komponenter her)

Run: `cd mobile && npm run start`
Verificér: en person med et `[[person:N|navn]]`-token i narrativet viser navnet som bordeaux-understreget link; tap navigerer til person N. Malformet token vises som rå tekst.

- [ ] **Step 4: Commit**

```bash
git add mobile/src/components/NarrativRenderer.tsx mobile/src/app/person/[id].tsx
git commit -m "feat(app): hyperlinks — NarrativRenderer m. klikbare person-links

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 3: Token-indsættelse + @-vælger i editoren

**Files:**
- Modify: `mobile/src/lib/mentions.ts` (+ test)
- Create: `mobile/src/components/redaktion/MentionPicker.tsx`
- Modify: `mobile/src/app/redaktion/person/[id].tsx` (narrativ-editor `:438`)

**Interfaces:**
- Consumes: `RedPerson`-liste (eksisterende redaktionsmodel i store), `parseNarrativ` (indirekte).
- Produces:
  - `makeToken(type: MentionType, id: number, label: string): string` — escaper `|[]` i label.
  - `insertAt(text: string, pos: number, insert: string): { text: string; cursor: number }`.
  - `<MentionPicker visible personer onVælg onLuk />` Modal-sheet.

- [ ] **Step 1: Skriv failing test (makeToken + insertAt)**

```typescript
import { makeToken, insertAt } from '../mentions';

describe('makeToken/insertAt', () => {
  it('makeToken escaper specialtegn i label', () => {
    expect(makeToken('person', 5, 'a|b]c')).toBe('[[person:5|a\\|b\\]c]]');
  });
  it('insertAt indsætter ved position og flytter cursor', () => {
    expect(insertAt('Hej  verden', 4, 'X')).toEqual({ text: 'Hej X verden', cursor: 5 });
  });
});
```

- [ ] **Step 2: Kør → FAIL**

- [ ] **Step 3: Tilføj til `mentions.ts`**

```typescript
export function makeToken(type: MentionType, id: number, label: string): string {
  const esc = label.replace(/([|[\]])/g, '\\$1');
  return `[[${type}:${id}|${esc}]]`;
}

export function insertAt(text: string, pos: number, insert: string): { text: string; cursor: number } {
  const p = Math.max(0, Math.min(pos, text.length));
  return { text: text.slice(0, p) + insert + text.slice(p), cursor: p + insert.length };
}
```

- [ ] **Step 4: Kør → PASS**

- [ ] **Step 5: Implementér `MentionPicker.tsx`** (mønster fra `UnionTypeSheet`/`SkrivePreviewSheet`)

```tsx
import React, { useState } from 'react';
import { Modal, View, Text, TextInput, Pressable, FlatList, StyleSheet } from 'react-native';
import { Colors, Border, Radius } from '../../theme/tokens';
import type { RedPerson } from '../../data/redaktionRead';

export function MentionPicker(props: {
  visible: boolean; personer: RedPerson[];
  onVælg: (p: RedPerson) => void; onLuk: () => void;
}) {
  const [q, setQ] = useState('');
  const filt = props.personer.filter((p) => p.navn.toLowerCase().includes(q.toLowerCase())).slice(0, 50);
  return (
    <Modal visible={props.visible} transparent animationType="slide" onRequestClose={props.onLuk}>
      <Pressable style={styles.backdrop} onPress={props.onLuk} />
      <View style={styles.sheet}>
        <Text style={styles.titel}>Indsæt link til person</Text>
        <TextInput style={styles.søg} placeholder="Søg navn…" value={q} onChangeText={setQ} autoFocus />
        <FlatList
          data={filt} keyExtractor={(p) => p.id}
          renderItem={({ item }) => (
            <Pressable style={styles.row} onPress={() => props.onVælg(item)}>
              <Text style={styles.navn}>{item.navn}</Text>
              <Text style={styles.aar}>{item.aar}</Text>
            </Pressable>
          )}
        />
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,.3)' },
  sheet: { maxHeight: '70%', backgroundColor: Colors.paperCard, borderTopLeftRadius: Radius.lg ?? 16,
           borderTopRightRadius: Radius.lg ?? 16, padding: 16 },
  titel: { fontSize: 18, color: Colors.ink, marginBottom: 8 },
  søg: { borderWidth: 1, borderColor: Border.subtle ?? '#0002', borderRadius: 8, padding: 10, marginBottom: 8 },
  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 10,
         borderBottomWidth: 1, borderBottomColor: Border.subtle ?? '#0001' },
  navn: { color: Colors.textSecondary, fontSize: 16 },
  aar: { color: Colors.textMuted, fontSize: 13 },
});
```

> Hvis `Radius`/`Border`-nøgler afviger, brug de faktiske fra `tokens.ts` (verificér ved import). `RedPerson`-liste hentes fra redaktionsmodellen i store (`useStore(s => s.redaktionModel)` mappet til navne) — i editoren findes personlisten allerede til relations-vælgeren; genbrug den kilde.

- [ ] **Step 6: Wire ind i narrativ-editoren** (`redaktion/person/[id].tsx:438`)

Tilføj en "🔗 Indsæt link"-knap over narrativ-`TextInput`. Hold styr på cursor via `onSelectionChange`. Ved valg: `const { text, cursor } = insertAt(narrativTekst, selPos, makeToken('person', Number(p.id), p.navn)); setNarrativTekst(text);`.

```tsx
// i komponenten:
const [selPos, setSelPos] = useState(0);
const [pickerÅben, setPickerÅben] = useState(false);
// ...
<Pressable onPress={() => setPickerÅben(true)}><Text style={{ color: Colors.bordeaux }}>🔗 Indsæt link</Text></Pressable>
<TextInput multiline value={narrativTekst} onChangeText={setNarrativTekst}
  onSelectionChange={(e) => setSelPos(e.nativeEvent.selection.start)} /* ...eksisterende props */ />
<MentionPicker visible={pickerÅben} personer={redPersoner}
  onLuk={() => setPickerÅben(false)}
  onVælg={(p) => { const r = insertAt(narrativTekst, selPos, makeToken('person', Number(p.id), p.navn));
                   setNarrativTekst(r.text); setPickerÅben(false); }} />
```

- [ ] **Step 7: Manuel verifikation** — indsæt et link, gem narrativ (eksisterende `red_upsert_narrativ`-flow uændret), åbn person-visning → linket er klikbart (Task 2).

- [ ] **Step 8: Commit**

```bash
git add mobile/src/lib/mentions.ts mobile/src/lib/__tests__/mentions.test.ts \
        mobile/src/components/redaktion/MentionPicker.tsx mobile/src/app/redaktion/person/[id].tsx
git commit -m "feat(app): hyperlinks — @-vælger + token-indsættelse i narrativ-editor

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 4: Læse-lag — historik + events

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts`
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts`

**Interfaces:**
- Produces:
  - `type HistPost = { id: string; hvem: string; hvornaar: string; resume: string; reverteret: boolean }`
  - `mapHistRow(r): HistPost` (ren, testet)
  - `fetchHistorik(personId: string): Promise<HistPost[]>` (`hist_for_subjekt`)
  - `type HistEvent = { tabel: string; op: string; foer: unknown; efter: unknown }`
  - `fetchHistEvents(changeSetId: number): Promise<HistEvent[]>` (`hist_events`)

- [ ] **Step 1: Skriv failing test (mapper)**

```typescript
import { mapHistRow } from '../redaktionRead';

describe('mapHistRow', () => {
  it('mapper change_set-række til HistPost', () => {
    const r = { id: 12, actor_navn: 'Johan', created_at: '2026-06-30T10:00:00Z',
                summary: 'Rettede dødsdato', reverterer_id: null } as any;
    expect(mapHistRow(r)).toMatchObject({ id: '12', hvem: 'Johan', resume: 'Rettede dødsdato', reverteret: false });
  });
});
```

- [ ] **Step 2: Kør → FAIL**

- [ ] **Step 3: Tilføj i `redaktionRead.ts`**

```typescript
export type HistPost = { id: string; hvem: string; hvornaar: string; resume: string; reverteret: boolean };
type RawHist = { id: number; actor_navn: string | null; created_at: string;
                 summary: string | null; reverterer_id: number | null };

export function mapHistRow(r: RawHist): HistPost {
  return {
    id: String(r.id),
    hvem: r.actor_navn ?? 'ukendt',
    hvornaar: new Date(r.created_at).toLocaleString('da-DK'),
    resume: r.summary ?? '(uden beskrivelse)',
    reverteret: r.reverterer_id != null, // dette sæt ER en fortrydelse
  };
}

export async function fetchHistorik(personId: string): Promise<HistPost[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.rpc('hist_for_subjekt', { p_type: 'person', p_id: Number(personId) });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapHistRow);
}

export type HistEvent = { tabel: string; op: string; foer: unknown; efter: unknown };
export async function fetchHistEvents(changeSetId: number): Promise<HistEvent[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.rpc('hist_events', { p_change_set_id: changeSetId });
  if (error) throw new Error(error.message);
  return (data ?? []).map((e: any) => ({ tabel: e.tabel, op: e.op, foer: e.foer, efter: e.efter }));
}
```

- [ ] **Step 4: Kør → PASS**

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(app): historik — fetchHistorik/fetchHistEvents + mapHistRow

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 5: Skrive-lag — fortryd-RPC

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts`
- Test: `mobile/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces:**
- Consumes: eksisterende `Change`/`buildRpcCall`/`submitChange`.
- Produces: ny `Change.art = 'fortryd'` med `payload.changeSetId` + `payload.force`; `buildRpcCall` mapper til `red_fortryd_change_set`.

- [ ] **Step 1: Skriv failing test**

```typescript
it('fortryd → red_fortryd_change_set m. force', () => {
  const c = { art: 'fortryd', subjektType: 'person', subjektId: '7',
              payload: { changeSetId: 12, force: true } } as const;
  expect(buildRpcCall(c)).toEqual({
    fn: 'red_fortryd_change_set', args: { p_change_set_id: 12, p_force: true },
  });
});
```

- [ ] **Step 2: Kør → FAIL**

- [ ] **Step 3: Udvid `Change`-union + `buildRpcCall`**

I `redaktionWrite.ts`: tilføj `'fortryd'` til `Change['art']`-unionen, og indsæt i `buildRpcCall` (fx efter `setKonklusion`-blokken):

```typescript
  if (c.art === 'fortryd') {
    const csId = c.payload?.changeSetId;
    if (csId == null) return null;
    return { fn: 'red_fortryd_change_set',
             args: { p_change_set_id: Number(csId), p_force: Boolean(c.payload?.force) } };
  }
```

- [ ] **Step 4: Kør → PASS**

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionWrite.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(app): historik — fortryd-RPC i buildRpcCall

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Task 6: Historik-skærm + fortryd-flow + døde-links-sektion

**Files:**
- Create: `mobile/src/app/redaktion/historik/[id].tsx`
- Modify: `mobile/src/data/redaktionRead.ts` (døde-links-fetch + mapper)
- Modify: `mobile/src/app/redaktion/person/[id].tsx` (link til historik-skærm)
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts` (døde-links-mapper)

**Interfaces:**
- Consumes: `fetchHistorik` (T4), `submitChange({art:'fortryd'})` (T5), `oversaetFejl`.
- Produces: `type DoedLink = { kilde: string; maalType: string; maalId: string }`; `mapDoedLinkRow` (ren); `fetchDoedeLinks(): Promise<DoedLink[]>`; skærm-komponent.

- [ ] **Step 1: Skriv failing test (døde-links-mapper)**

```typescript
import { mapDoedLinkRow } from '../redaktionRead';
it('mapDoedLinkRow', () => {
  const r = { kilde_type: 'narrative', kilde_id: 3, maal_type: 'person', maal_id: 999 } as any;
  expect(mapDoedLinkRow(r)).toEqual({ kilde: 'narrative#3', maalType: 'person', maalId: '999' });
});
```

- [ ] **Step 2: Kør → FAIL**

- [ ] **Step 3: Tilføj døde-links i `redaktionRead.ts`**

```typescript
export type DoedLink = { kilde: string; maalType: string; maalId: string };
export function mapDoedLinkRow(r: { kilde_type: string; kilde_id: number; maal_type: string; maal_id: number }): DoedLink {
  return { kilde: `${r.kilde_type}#${r.kilde_id}`, maalType: r.maal_type, maalId: String(r.maal_id) };
}
export async function fetchDoedeLinks(): Promise<DoedLink[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.from('red_doede_links').select('*');
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapDoedLinkRow);
}
```

- [ ] **Step 4: Kør → PASS**

- [ ] **Step 5: Implementér historik-skærmen**

```tsx
import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, FlatList, Pressable, Alert, ActivityIndicator, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { fetchHistorik, fetchDoedeLinks, type HistPost, type DoedLink } from '../../../data/redaktionRead';
import { submitChange, oversaetFejl } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Colors } from '../../../theme/tokens';

export default function HistorikSkaerm() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const dryRun = useStore((s) => s.dryRun);
  const [poster, setPoster] = useState<HistPost[]>([]);
  const [doede, setDoede] = useState<DoedLink[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [fejl, setFejl] = useState<string | null>(null);

  const indlæs = useCallback(async () => {
    try {
      setStatus('loading');
      setPoster(await fetchHistorik(String(id)));
      setDoede(await fetchDoedeLinks());
      setStatus('ready');
    } catch (e: any) { setFejl(oversaetFejl(e.message)); setStatus('error'); }
  }, [id]);
  useEffect(() => { indlæs(); }, [indlæs]);

  const fortryd = useCallback(async (post: HistPost, force: boolean) => {
    try {
      await submitChange({ art: 'fortryd', subjektType: 'person', subjektId: String(id),
        payload: { changeSetId: Number(post.id), force } }, { dryRun });
      await indlæs();
    } catch (e: any) {
      const msg = e.message as string;
      if (/afvist .*force/i.test(msg) && !force) {
        Alert.alert('Nyere ændring rører samme data', 'Fortryd alligevel?',
          [{ text: 'Annullér', style: 'cancel' },
           { text: 'Fortryd alligevel', style: 'destructive', onPress: () => fortryd(post, true) }]);
      } else { Alert.alert('Fejl', oversaetFejl(msg)); }
    }
  }, [id, dryRun, indlæs]);

  if (status === 'loading') return <ActivityIndicator style={{ marginTop: 40 }} />;
  if (status === 'error') return <Text style={styles.fejl}>{fejl}</Text>;

  return (
    <FlatList
      data={poster} keyExtractor={(p) => p.id}
      ListHeaderComponent={<Text style={styles.h1}>Ændringshistorik</Text>}
      renderItem={({ item }) => (
        <View style={[styles.kort, item.reverteret && styles.kortReverteret]}>
          <Text style={styles.resume}>{item.resume}</Text>
          <Text style={styles.meta}>{item.hvem} · {item.hvornaar}</Text>
          {!item.reverteret && (
            <Pressable style={styles.fortrydKnap} onPress={() => fortryd(item, false)}>
              <Text style={styles.fortrydTekst}>Fortryd</Text>
            </Pressable>
          )}
        </View>
      )}
      ListFooterComponent={
        <View style={styles.doedeSektion}>
          <Text style={styles.h2}>Døde links ({doede.length})</Text>
          {doede.map((d, i) => (
            <Text key={i} style={styles.doedRow}>{d.kilde} → {d.maalType}:{d.maalId}</Text>
          ))}
        </View>
      }
    />
  );
}

const styles = StyleSheet.create({
  h1: { fontSize: 22, color: Colors.ink, padding: 16 },
  h2: { fontSize: 18, color: Colors.ink, marginBottom: 8 },
  kort: { backgroundColor: Colors.paperCard, marginHorizontal: 16, marginBottom: 8, padding: 12, borderRadius: 10 },
  kortReverteret: { opacity: 0.5 },
  resume: { fontSize: 16, color: Colors.textSecondary },
  meta: { fontSize: 12, color: Colors.textMuted, marginTop: 4 },
  fortrydKnap: { alignSelf: 'flex-start', marginTop: 8, paddingVertical: 6, paddingHorizontal: 12,
                 borderRadius: 8, backgroundColor: Colors.konfliktFlade },
  fortrydTekst: { color: Colors.danger, fontWeight: '600' },
  doedeSektion: { padding: 16 },
  doedRow: { color: Colors.textMuted, fontSize: 13, marginBottom: 2 },
  fejl: { color: Colors.danger, padding: 16 },
});
```

> **Konflikt-flow:** `red_fortryd_change_set` kaster `FEJL: ... afvist (brug force)` ved divergens (DB-plan B9). Klienten matcher beskeden og tilbyder "Fortryd alligevel" → kald igen med `force:true`. Beskeds-matchen (`/afvist .*force/i`) skal holdes i sync med DB-RAISE-teksten.

- [ ] **Step 6: Link fra person-editoren**

I `redaktion/person/[id].tsx`: tilføj en knap "📜 Historik" der `router.push('/redaktion/historik/' + id)`.

- [ ] **Step 7: Manuel verifikation** — lav en redigering, åbn historik, se posten m. hvem/hvornår, tryk Fortryd → ændringen forsvinder + posten markeres reverteret. Slet en person der er nævnt i et narrativ → den dukker op under Døde links.

- [ ] **Step 8: Commit**

```bash
git add mobile/src/app/redaktion/historik/[id].tsx mobile/src/data/redaktionRead.ts \
        mobile/src/data/__tests__/redaktionRead.test.ts mobile/src/app/redaktion/person/[id].tsx
git commit -m "feat(app): historik-skærm + fortryd-flow + døde-links-rapport

Claude-Session: https://claude.ai/code/session_01NwvCB66DaXqfwuqqL9DZcd"
```

---

## Self-Review (udført)

**Spec-dækning (app-relevante dele):**
- §5.1 token-grammatik → T1 `parseNarrativ` + T3 `makeToken` (escaping) ✓
- §5.2 rendering (links klikbare; person navigerer) → T2 `NarrativRenderer` ✓
- §5.4 @-vælger-indsættelse → T3 `MentionPicker` ✓
- Historik-visning (hvem/hvornår — B3) → T4 `mapHistRow` + T6 skærm ✓
- Fortryd + konflikt-advarsel (B6/B9) → T5 RPC + T6 force-flow ✓
- Døde-links-rapport (§5.3/M4) → T6 `fetchDoedeLinks` ✓

**DB-API-alignment:** alle kald bruger DB-planens eksakte navne (`hist_for_subjekt`, `hist_events`, `red_fortryd_change_set`, `red_doede_links`). `red_edit_oplysning`s nye `jsonb`-retur er bagudkompatibel for klienten (`submitChange` returnerer `result` generisk; ingen kalder læser den i dag) — ingen ændring krævet, men verificér ved Task 5-kørsel at ingen test asserter `void`.

**Type-konsistens:** `RedPerson` (eksisterende) genbrugt i `MentionPicker`. `Segment.maalType: MentionType` matcher `parse`-output. `Change.art` udvidet med `'fortryd'`; `payload.changeSetId/force` matcher `buildRpcCall`-aflæsning.

**Placeholder-scan:** ingen TBD; al kode komplet. Antagelser markeret (`Radius`/`Border`-nøgler verificeres mod `tokens.ts`; konflikt-besked-match holdes i sync med DB-RAISE).

**Test-niveau:** jest dækker rene funktioner (T1, T3, T4, T5, T6-mappers). Komponenter/skærme (T2, T3-sheet, T6-skærm) = manuel Expo-verifikation (ingen RNTL i repoet) — eksplicit noteret pr. task.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-30-versionering-hyperlinks-app-lag.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

> **Forudsætning:** DB-lag-planen skal være implementeret + kørt mod basen først (denne plan kalder dens RPC'er). UI-beslutninger D1-D3 bekræftes/overstyres før eksekvering.
