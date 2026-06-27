# Redaktions-UI kerne-skive — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Byg den vertikale kerne-skive af redaktør-appen — dashboard, person-editor (evidens-lag), konto + tre kritiske sheets — så en redaktør kan logge ind og redigere kerne-fakta/narrativ mod live-Supabase.

**Architecture:** Nyt `redaktion/`-route-segment i den eksisterende Expo-app med en native `(red-tabs)` Tabs-gruppe. Et nyt evidens-read-lag (`redaktionRead.ts`) henter fact/assertion/conclusion/citation som N flade queries + klient-join (polymorf model uden FK). Writes går gennem de allerede-deployede `red_*`-RPC'er via et udvidet `redaktionWrite.ts`. Tre små additive DB-ændringer (konflikt-view, redaktion-read-RLS, slet-preview) understøtter editoren.

**Tech Stack:** TypeScript, React Native, Expo Router, Zustand, `@supabase/supabase-js`, Jest, PostgreSQL/Supabase (RLS + SECURITY DEFINER RPC'er).

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-27-redaktion-ui-kerne-skive-design.md` (autoritativ). Underliggende: `docs/superpowers/specs/2026-06-26-redaktion-skrive-model-auth-design.md`.
- **Branch:** `feat/folgesvend-mobile` (arbejd her; ingen merge/push uden eksplicit godkendelse).
- **Cache-felter** (`person.visning_*`, `koen`): skriv ALDRIG direkte fra app — regenereres af DB-trigger.
- **Tokens:** brug `mobile/src/theme/tokens.ts` (`Colors`, `Border`, `Fonts`, `Radius`, `Shadow`). Tilføj kun manglende redaktion-tokens additivt; opfind ikke nye farver.
- **Typografi-komponenter:** `Serif`, `Mono`, `Kicker`, `Body`, `BtnLabel` fra `components/Typography.tsx`. Aldrig rå `<Text>` med inline-font.
- **Person-opslag:** `model.byId[id]` (ModelPerson). Selectors i `data/selectors.ts`.
- **DB source of truth:** `schema.sql`. Migrationer idempotent i `db-migrations.sql`. RLS i `db-rls.sql`. Verificér mod live-base via REST-probe (mønster i spec §0).
- **Hifi-værdier** (farver/spacing/radier pr. komponent): `design_handoff_redaktion_mobile/README.md` §Skærme + §Design tokens. Plan'en refererer dem; kopiér ikke prototypens HTML.
- **Test-niveau matcher risiko:** logik-lag (read-join, write-build, RLS) = TDD/SQL-assert. Skærme = render-light + manuel funktionstest (jf. projektets regel).
- **Ingen Claude-attribution** i commits. Conventional Commits, dansk beskrivelse.

---

## File Structure

**DB (eksisterende filer, additivt):**
- `schema.sql` — `red_konflikt`-view; `red_slet_person_preview`-RPC.
- `db-migrations.sql` — idempotent gentagelse af ovenstående.
- `db-rls.sql` — redaktion-read-policies (private rækker for rolle=redaktion); grant på view.

**App — nye filer:**
- `mobile/src/data/redaktionRead.ts` — `fetchPersonEvidence`, `fetchKonflikter` + typer.
- `mobile/src/data/__tests__/redaktionRead.test.ts`.
- `mobile/src/app/redaktion/_layout.tsx` — Stack.
- `mobile/src/app/redaktion/(red-tabs)/_layout.tsx` — Tabs (4 faner).
- `mobile/src/app/redaktion/(red-tabs)/index.tsx` — dashboard.
- `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` — stub.
- `mobile/src/app/redaktion/(red-tabs)/konto.tsx` — login/dry-run/logout.
- `mobile/src/app/redaktion/person/[id].tsx` — person-editor (kerneskærm).
- `mobile/src/components/redaktion/LoginSheet.tsx`.
- `mobile/src/components/redaktion/SkrivePreviewSheet.tsx`.
- `mobile/src/components/redaktion/SletBekraeftSheet.tsx`.
- `mobile/src/components/redaktion/FaktaKort.tsx` — ét kerne-fakta-kort (fold/udfold + handlinger).

**App — ændrede filer:**
- `mobile/src/data/redaktionWrite.ts` — nye `Change`-arter + `buildRpcCall`-cases + fejl-oversættelse.
- `mobile/src/data/__tests__/redaktionWrite.test.ts` — nye cases.
- `mobile/src/store/useStore.ts` — kun hvis ny tværgående state kræves (auth/dryRun findes).

---

## Task 1: DB — konflikt-view, redaktion-read-RLS, slet-preview

**Files:**
- Modify: `schema.sql` (efter eksisterende `red_*`-funktioner)
- Modify: `db-migrations.sql` (idempotent blok i bunden)
- Modify: `db-rls.sql` (efter §5 authenticated-laget)

**Interfaces:**
- Produces (læses i Task 2–3 via PostgREST):
  - View `red_konflikt(person_id bigint, faktatype text, antal_vaerdier int, antal_oplysninger int)`.
  - RPC `red_slet_person_preview(p_person_id bigint) RETURNS jsonb` — `{antal_relationer, antal_facts, relationer:[{rolle, modpart_id, retning}]}`.
  - Redaktion-read-policies (rolle=redaktion ser private rækker).

- [ ] **Step 1: Tilføj `red_konflikt`-view + slet-preview til `schema.sql`**

Indsæt efter den sidste `red_*`-funktion i `schema.sql`:

```sql
-- Konflikt-kø til redaktions-dashboard: kerne-tekstfelter med >1 DISTINKT værdi.
-- security_invoker=true er KRITISK: ellers kører viewet med ejer-rettigheder og omgår RLS
-- på fact/assertion → ville lække private personers konflikter (spec §5, Codex-review høj).
-- v1: kun 'navn'/'titel' (dato-fakta har typisk tom vaerdi_tekst → udeladt, spec §5).
CREATE OR REPLACE VIEW red_konflikt
  WITH (security_invoker = true) AS
SELECT f.subjekt_id AS person_id,
       f.faktatype,
       count(DISTINCT a.vaerdi_tekst) AS antal_vaerdier,
       count(*)                       AS antal_oplysninger
FROM fact f
JOIN assertion a ON a.target_type = 'fact' AND a.target_id = f.id
WHERE f.subjekt_type = 'person'
  AND f.faktatype IN ('navn','titel')
GROUP BY f.subjekt_id, f.faktatype
HAVING count(DISTINCT a.vaerdi_tekst) > 1;

-- Read-only forhåndsvisning af hvad red_slet_person ville slette. Spejler RPC'ens
-- relations-logik: personen som subjekt ELLER objekt (spec §7, Codex-review høj).
CREATE OR REPLACE FUNCTION red_slet_person_preview(p_person_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rels jsonb; v_nfacts int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT count(*) INTO v_nfacts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_rels FROM (
    SELECT rolle,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id)
  ) r;
  RETURN jsonb_build_object(
    'antal_relationer', jsonb_array_length(v_rels),
    'antal_facts', v_nfacts,
    'relationer', v_rels);
END $$;
```

- [ ] **Step 2: Tilføj redaktion-read-policies til `db-rls.sql`**

Indsæt efter §5 (authenticated-laget). Mønster spejler eksisterende `redaktion_read_all` på suggestion (`(select public.current_rolle()) = 'redaktion'`). Redaktøren skal se private rækker, ellers låser privat-toggle hende ude (spec §6.2/§8b):

```sql
-- 5b) REDAKTION-LAG: rolle=redaktion ser OGSÅ private rækker (ellers skjuler auth_read-laget
-- en netop privat-markeret person for redaktøren selv — spec §8b, Codex-review høj).
-- Additiv: hver tabel har nu (anon_read) + (auth_read ikke-privat) + (redaktion_read alt).
do $$
declare t text;
begin
  foreach t in array array['person','person_external_id','family_member','fact',
                           'relation','narrative','note','assertion','conclusion','citation']
  loop
    execute format('drop policy if exists redaktion_read on public.%I;', t);
    execute format(
      'create policy redaktion_read on public.%I for select to authenticated '
      || 'using ((select public.current_rolle()) = ''redaktion'');', t);
  end loop;
end $$;

-- Konflikt-view: læsbar for authenticated (RLS håndhæves af security_invoker på basistabeller).
grant select on public.red_konflikt to authenticated;
grant select on public.red_konflikt to anon;
```

- [ ] **Step 3: Spejl Step 1+2 idempotent i `db-migrations.sql`**

Tilføj samme `CREATE OR REPLACE VIEW`, `CREATE OR REPLACE FUNCTION` og det `do $$`-policy-loop + grants i bunden af `db-migrations.sql` (alle udsagn er allerede idempotente: `CREATE OR REPLACE` / `drop policy if exists`).

- [ ] **Step 4: Deploy mod live-base + verificér**

Kør `db-migrations.sql` + `db-rls.sql` mod Supabase (psql/dashboard). Verificér derefter via REST (mønster spec §0). Brug repo-rodens `.env`-nøgle:

Run:
```bash
cd mobile && URL=$(grep EXPO_PUBLIC_SUPABASE_URL .env | cut -d= -f2) && KEY=$(grep EXPO_PUBLIC_SUPABASE_ANON_KEY .env | cut -d= -f2)
# view findes + returnerer rækker (anon ser kun ikke-private pga security_invoker):
curl -s "$URL/rest/v1/red_konflikt?select=person_id,faktatype&limit=3" -H "apikey: $KEY"
# preview-RPC findes (anon → rolle-exception beviser deploy):
curl -s -X POST "$URL/rest/v1/rpc/red_slet_person_preview" -H "apikey: $KEY" -H "Content-Type: application/json" -d '{"p_person_id":1}'
```
Expected: første kald = JSON-array (evt. `[]`); andet kald = `{"code":"P0001",...,"message":"Kun redaktion"}` (beviser RPC deployet + gated).

- [ ] **Step 5: Verificér privat-læk er lukket**

Run (samme URL/KEY):
```bash
# Find en privat person hvis nogen findes; anon må IKKE se den i red_konflikt eller person.
curl -s "$URL/rest/v1/person?select=id,privat&privat=eq.true&limit=1" -H "apikey: $KEY"
```
Expected: `[]` for anon (privat-rækker usynlige). Hvis ikke-tom → RLS-fejl, stop og undersøg.

- [ ] **Step 6: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql
git commit -m "feat(db): red_konflikt-view (security_invoker), redaktion-read-RLS, slet-preview-RPC"
```

---

## Task 2: Evidens-read-lag — `fetchPersonEvidence`

**Files:**
- Create: `mobile/src/data/redaktionRead.ts`
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts`

**Interfaces:**
- Consumes: `supabase` fra `lib/supabase.ts`; faktatype-map fra `redaktionWrite.ts` (`FELT_FAKTATYPE`).
- Produces:
  - `type Kilde = { sourceId: number|null; sourceTitel?: string; side?: string; citatTekst?: string; citatDato?: string }`
  - `type Oplysning = { assertionId: number; vaerdi: string; dato?: { min: string|null; max: string|null; qualifier: string|null; raw: string|null }; kilder: Kilde[]; erKonklusion: boolean }`
  - `type FeltEvidens = { felt: string; faktatype: string; factId: number; konklusionAssertionId: number|null; oplysninger: Oplysning[]; uenig: boolean }`
  - `type PersonEvidence = { felter: Record<string, FeltEvidens>; koen: string|null }`
  - `joinEvidence(rows: { facts; assertions; conclusions; citations; koen }): PersonEvidence` — ren funktion (testbar uden net).
  - `async fetchPersonEvidence(personId: string): Promise<PersonEvidence>`

- [ ] **Step 1: Skriv den fejlende test for `joinEvidence`**

Opret `mobile/src/data/__tests__/redaktionRead.test.ts`:

```ts
import { joinEvidence } from '../redaktionRead';

const FACTS = [
  { id: 10, subjekt_type: 'person', subjekt_id: 1, faktatype: 'navn' },
  { id: 11, subjekt_type: 'person', subjekt_id: 1, faktatype: 'fødsel' },
];
const ASSERTS = [
  { id: 100, target_type: 'fact', target_id: 10, vaerdi_tekst: 'Conrad', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  { id: 101, target_type: 'fact', target_id: 10, vaerdi_tekst: 'Konrad', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  { id: 102, target_type: 'fact', target_id: 11, vaerdi_tekst: null, date_min: '1644-01-01', date_max: '1644-12-31', date_qualifier: 'about', date_raw: 'ca. 1644' },
];
const CONCS = [{ target_type: 'fact', target_id: 10, valgt_assertion_id: 100 }];
const CITS = [
  { assertion_id: 100, source_id: 5, side: 's. 12', citat_tekst: 'Conrad', citat_dato: null, source: { titel: 'DAA 2018' } },
];

test('joinEvidence samler felter, markerer konklusion + uenig', () => {
  const ev = joinEvidence({ facts: FACTS, assertions: ASSERTS, conclusions: CONCS, citations: CITS, koen: 'M' });
  expect(ev.koen).toBe('M');
  expect(ev.felter.navn.uenig).toBe(true); // Conrad ≠ Konrad
  expect(ev.felter.navn.konklusionAssertionId).toBe(100);
  expect(ev.felter.navn.oplysninger.find((o) => o.assertionId === 100)?.erKonklusion).toBe(true);
  expect(ev.felter.navn.oplysninger.find((o) => o.assertionId === 100)?.kilder[0].sourceTitel).toBe('DAA 2018');
  expect(ev.felter.foedt.uenig).toBe(false); // kun én oplysning
  expect(ev.felter.foedt.oplysninger[0].dato?.raw).toBe('ca. 1644');
});
```

- [ ] **Step 2: Kør testen — verificér fejl**

Run: `cd mobile && npx jest redaktionRead -t "joinEvidence"`
Expected: FAIL — `joinEvidence is not a function` (filen findes ikke endnu).

- [ ] **Step 3: Implementér `redaktionRead.ts`**

```ts
// Evidens-read-lag til person-editoren. Modellen er polymorf (assertion/conclusion peger på
// fact via target_type/target_id UDEN rigtig FK), så vi henter N flade queries og joiner i
// klienten. citation→source HAR FK og nestes (spec §3). Ren joinEvidence er testbar uden net.
import { supabase } from '../lib/supabase';
import { FELT_FAKTATYPE } from './redaktionWrite';

// faktatype → UI-felt (omvendt af FELT_FAKTATYPE).
const FAKTATYPE_FELT: Record<string, string> = Object.fromEntries(
  Object.entries(FELT_FAKTATYPE).map(([felt, ft]) => [ft, felt]),
);

export type Kilde = {
  sourceId: number | null;
  sourceTitel?: string;
  side?: string;
  citatTekst?: string;
  citatDato?: string;
};
export type Oplysning = {
  assertionId: number;
  vaerdi: string;
  dato?: { min: string | null; max: string | null; qualifier: string | null; raw: string | null };
  kilder: Kilde[];
  erKonklusion: boolean;
};
export type FeltEvidens = {
  felt: string;
  faktatype: string;
  factId: number;
  konklusionAssertionId: number | null;
  oplysninger: Oplysning[];
  uenig: boolean;
};
export type PersonEvidence = { felter: Record<string, FeltEvidens>; koen: string | null };

type RawFact = { id: number; faktatype: string };
type RawAssert = { id: number; target_id: number; vaerdi_tekst: string | null;
  date_min: string | null; date_max: string | null; date_qualifier: string | null; date_raw: string | null };
type RawConc = { target_id: number; valgt_assertion_id: number | null };
type RawCit = { assertion_id: number; source_id: number | null; side: string | null;
  citat_tekst: string | null; citat_dato: string | null; source?: { titel?: string } | null };

export function joinEvidence(rows: {
  facts: RawFact[]; assertions: RawAssert[]; conclusions: RawConc[]; citations: RawCit[]; koen: string | null;
}): PersonEvidence {
  const concByFact = new Map(rows.conclusions.map((c) => [c.target_id, c.valgt_assertion_id]));
  const citByAssert = new Map<number, Kilde[]>();
  for (const c of rows.citations) {
    const list = citByAssert.get(c.assertion_id) ?? [];
    list.push({
      sourceId: c.source_id, sourceTitel: c.source?.titel ?? undefined,
      side: c.side ?? undefined, citatTekst: c.citat_tekst ?? undefined, citatDato: c.citat_dato ?? undefined,
    });
    citByAssert.set(c.assertion_id, list);
  }
  const felter: Record<string, FeltEvidens> = {};
  for (const f of rows.facts) {
    const felt = FAKTATYPE_FELT[f.faktatype];
    if (!felt) continue; // kun kerne-fakta (navn/foedt/doed/titel)
    const valgt = concByFact.get(f.id) ?? null;
    const opl = rows.assertions
      .filter((a) => a.target_id === f.id)
      .map<Oplysning>((a) => ({
        assertionId: a.id,
        vaerdi: a.vaerdi_tekst ?? a.date_raw ?? '',
        dato: a.date_raw != null || a.date_min != null
          ? { min: a.date_min, max: a.date_max, qualifier: a.date_qualifier, raw: a.date_raw } : undefined,
        kilder: citByAssert.get(a.id) ?? [],
        erKonklusion: a.id === valgt,
      }));
    const distinkte = new Set(opl.map((o) => o.vaerdi));
    felter[felt] = {
      felt, faktatype: f.faktatype, factId: f.id,
      konklusionAssertionId: valgt, oplysninger: opl, uenig: distinkte.size > 1,
    };
  }
  return { felter, koen: rows.koen };
}

export async function fetchPersonEvidence(personId: string): Promise<PersonEvidence> {
  const empty: PersonEvidence = { felter: {}, koen: null };
  if (!supabase) return empty;
  const pid = Number(personId);
  const { data: facts } = await supabase
    .from('fact').select('id,faktatype').eq('subjekt_type', 'person').eq('subjekt_id', pid);
  const factIds = (facts ?? []).map((f: RawFact) => f.id);
  if (!factIds.length) {
    const { data: p0 } = await supabase.from('person').select('koen').eq('id', pid).maybeSingle();
    return { felter: {}, koen: p0?.koen ?? null };
  }
  const [{ data: assertions }, { data: conclusions }, { data: person }] = await Promise.all([
    supabase.from('assertion').select('id,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw')
      .eq('target_type', 'fact').in('target_id', factIds),
    supabase.from('conclusion').select('target_id,valgt_assertion_id')
      .eq('target_type', 'fact').in('target_id', factIds),
    supabase.from('person').select('koen').eq('id', pid).maybeSingle(),
  ]);
  const assertIds = (assertions ?? []).map((a: RawAssert) => a.id);
  const { data: citations } = assertIds.length
    ? await supabase.from('citation')
        .select('assertion_id,source_id,side,citat_tekst,citat_dato,source(titel)')
        .in('assertion_id', assertIds)
    : { data: [] };
  return joinEvidence({
    facts: (facts ?? []) as RawFact[],
    assertions: (assertions ?? []) as RawAssert[],
    conclusions: (conclusions ?? []) as RawConc[],
    citations: (citations ?? []) as RawCit[],
    koen: person?.koen ?? null,
  });
}
```

- [ ] **Step 4: Kør testen — verificér pass**

Run: `cd mobile && npx jest redaktionRead`
Expected: PASS.

- [ ] **Step 5: tsc-tjek + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(data): evidens-read-lag (fetchPersonEvidence + joinEvidence)"
```

---

## Task 3: Konflikt-kø-read — `fetchKonflikter`

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts`
- Test: `mobile/src/data/__tests__/redaktionRead.test.ts`

**Interfaces:**
- Produces: `type Konflikt = { personId: string; felt: string; antalVaerdier: number }`; `async fetchKonflikter(): Promise<Konflikt[]>`. Felt udledes via `FAKTATYPE_FELT[faktatype]`.

- [ ] **Step 1: Skriv fejlende test for mapping**

Tilføj i `redaktionRead.test.ts`:

```ts
import { mapKonfliktRow } from '../redaktionRead';

test('mapKonfliktRow oversætter faktatype → UI-felt', () => {
  expect(mapKonfliktRow({ person_id: 7, faktatype: 'navn', antal_vaerdier: 2 }))
    .toEqual({ personId: '7', felt: 'navn', antalVaerdier: 2 });
});
```

- [ ] **Step 2: Kør — verificér fejl**

Run: `cd mobile && npx jest redaktionRead -t "mapKonfliktRow"`
Expected: FAIL — `mapKonfliktRow is not a function`.

- [ ] **Step 3: Implementér i `redaktionRead.ts`**

```ts
export type Konflikt = { personId: string; felt: string; antalVaerdier: number };

export function mapKonfliktRow(r: { person_id: number; faktatype: string; antal_vaerdier: number }): Konflikt {
  return { personId: String(r.person_id), felt: FAKTATYPE_FELT[r.faktatype] ?? r.faktatype, antalVaerdier: r.antal_vaerdier };
}

export async function fetchKonflikter(): Promise<Konflikt[]> {
  if (!supabase) return [];
  const { data } = await supabase.from('red_konflikt').select('person_id,faktatype,antal_vaerdier');
  return (data ?? []).map(mapKonfliktRow);
}
```

- [ ] **Step 4: Kør test + commit**

Run: `cd mobile && npx jest redaktionRead && npx tsc --noEmit`
Expected: PASS, ingen tsc-fejl.
```bash
git add mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(data): konflikt-kø-read (fetchKonflikter)"
```

---

## Task 4: Write-lag — nye `Change`-arter + fejl-oversættelse

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts`
- Test: `mobile/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces:**
- Consumes: eksisterende `Change`, `buildRpcCall`, `submitChange`.
- Produces (udvider `Change.art` + nye felter):
  - `art` udvides med `'redigerOplysning' | 'sletOplysning' | 'setKonklusion' | 'setPrivat' | 'sletPerson'`.
  - `Change` får valgfri: `assertionId?: string`, og `payload` bruges til `{ privat?: boolean }`.
  - `buildRpcCall` mapper de nye arter til RPC'erne (signaturer fra `schema.sql`):
    - `red_set_konklusion(p_assertion_id)`
    - `red_edit_oplysning(p_assertion_id, p_vaerdi, p_date_raw?, p_kilde_fritekst?)`
    - `red_slet_oplysning(p_assertion_id)`
    - `red_set_privat(p_person_id, p_privat)`
    - `red_slet_person(p_person_id)`
  - `oversaetFejl(message: string): string` — PostgREST/Postgres → dansk UI-tekst.

- [ ] **Step 1: Skriv fejlende tests**

Tilføj i `redaktionWrite.test.ts`:

```ts
import { buildRpcCall, oversaetFejl } from '../redaktionWrite';

test('redigerOplysning → red_edit_oplysning', () => {
  expect(buildRpcCall({ art: 'redigerOplysning', subjektType: 'person', subjektId: '1',
    assertionId: '100', vaerdi: 'Konrad', kildeFritekst: 'DAA 2018' }))
    .toEqual({ fn: 'red_edit_oplysning',
      args: { p_assertion_id: 100, p_vaerdi: 'Konrad', p_kilde_fritekst: 'DAA 2018' } });
});

test('setKonklusion → red_set_konklusion', () => {
  expect(buildRpcCall({ art: 'setKonklusion', subjektType: 'person', subjektId: '1', assertionId: '100' }))
    .toEqual({ fn: 'red_set_konklusion', args: { p_assertion_id: 100 } });
});

test('setPrivat → red_set_privat', () => {
  expect(buildRpcCall({ art: 'setPrivat', subjektType: 'person', subjektId: '1', payload: { privat: true } }))
    .toEqual({ fn: 'red_set_privat', args: { p_person_id: 1, p_privat: true } });
});

test('sletPerson → red_slet_person', () => {
  expect(buildRpcCall({ art: 'sletPerson', subjektType: 'person', subjektId: '1' }))
    .toEqual({ fn: 'red_slet_person', args: { p_person_id: 1 } });
});

test('oversaetFejl: rolle-gating → dansk', () => {
  expect(oversaetFejl('Kun redaktion')).toBe('Kræver redaktør-rettigheder.');
});
```

- [ ] **Step 2: Kør — verificér fejl**

Run: `cd mobile && npx jest redaktionWrite`
Expected: FAIL på de nye tests (`oversaetFejl` udefineret; nye arter giver `null`).

- [ ] **Step 3: Udvid `Change` + `buildRpcCall` + tilføj `oversaetFejl`**

Opdatér `Change.art`-unionen og indsæt cases øverst i `buildRpcCall` (før den eksisterende `fakta`-gren). Tilføj `assertionId?: string` til `Change`:

```ts
export type Change = {
  art: 'fakta' | 'narrativ' | 'relation' | 'gods' | 'hverv'
     | 'redigerOplysning' | 'sletOplysning' | 'setKonklusion' | 'setPrivat' | 'sletPerson';
  subjektType: string;
  subjektId: string;
  assertionId?: string;
  felt?: string;
  vaerdi?: string;
  kildeFritekst?: string;
  payload?: Record<string, unknown>;
};
```

Indsæt i `buildRpcCall` (efter `const sid = Number(c.subjektId);`):

```ts
  const aid = c.assertionId != null ? Number(c.assertionId) : undefined;
  if (c.art === 'setKonklusion') {
    return { fn: 'red_set_konklusion', args: { p_assertion_id: aid } };
  }
  if (c.art === 'redigerOplysning') {
    const args: Record<string, unknown> = { p_assertion_id: aid, p_vaerdi: c.vaerdi };
    if (c.felt && DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_edit_oplysning', args };
  }
  if (c.art === 'sletOplysning') {
    return { fn: 'red_slet_oplysning', args: { p_assertion_id: aid } };
  }
  if (c.art === 'setPrivat') {
    return { fn: 'red_set_privat', args: { p_person_id: sid, p_privat: Boolean(c.payload?.privat) } };
  }
  if (c.art === 'sletPerson') {
    return { fn: 'red_slet_person', args: { p_person_id: sid } };
  }
```

Tilføj nederst i filen:

```ts
// PostgREST/Postgres-fejl → dansk UI-tekst (spec §9). Fald tilbage til rå besked.
export function oversaetFejl(message: string): string {
  if (/kun redaktion/i.test(message)) return 'Kræver redaktør-rettigheder.';
  if (/duplicate key|unique/i.test(message)) return 'Findes allerede.';
  if (/not configured|ikke konfigureret/i.test(message)) return 'Ingen forbindelse til basen.';
  return message;
}
```

- [ ] **Step 4: Kør — verificér pass**

Run: `cd mobile && npx jest redaktionWrite && npx tsc --noEmit`
Expected: PASS, ingen tsc-fejl.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionWrite.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(data): write-lag — edit/slet/konklusion/privat/slet-person + fejl-oversættelse"
```

---

## Task 5: Navigation-skelet — `redaktion/`-segment + `(red-tabs)`

**Files:**
- Create: `mobile/src/app/redaktion/_layout.tsx`
- Create: `mobile/src/app/redaktion/(red-tabs)/_layout.tsx`
- Create: `mobile/src/app/redaktion/(red-tabs)/index.tsx` (midlertidig placeholder, fyldes i Task 7)
- Create: `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` (stub)
- Create: `mobile/src/app/redaktion/(red-tabs)/konto.tsx` (placeholder, fyldes i Task 6)

**Interfaces:**
- Produces: rute `/redaktion` (→ dashboard-tab), `/redaktion/person/[id]` (Task 8). "Tilføj"-tab åbner sheet via `tabPress`-interception.

- [ ] **Step 1: Stack-layout**

`mobile/src/app/redaktion/_layout.tsx`:

```tsx
// Redaktions-segment: egen Stack, skjult header (skærme har egen hero/TopBar). Adskilt fra
// publikums-(tabs). person/[id] pushes uden for tabbaren (spec §2).
import { Stack } from 'expo-router';

export default function RedaktionLayout() {
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(red-tabs)" />
      <Stack.Screen name="person/[id]" />
    </Stack>
  );
}
```

- [ ] **Step 2: Tabs-layout med "Tilføj"-interception**

`mobile/src/app/redaktion/(red-tabs)/_layout.tsx`:

```tsx
// Redaktions-tabbar: Oversigt · Entiteter · Tilføj · Konto (IKKE publikums-fanerne, spec §2).
// "Tilføj" navigerer ikke — den åbner opret-sheet (plan 2-stub). Vi intercepter tabPress.
import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import { useState } from 'react';
import type { ColorValue } from 'react-native';
import { Border, Colors, Fonts } from '../../../theme/tokens';

type IconName = keyof typeof Ionicons.glyphMap;
const icon = (name: IconName) => ({ color, size }: { color: ColorValue; size: number }) =>
  <Ionicons name={name} color={color as string} size={size} />;

export default function RedTabsLayout() {
  const [, setOpretOpen] = useState(false); // plan 1: stub; sheet-komponent = plan 2
  return (
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
  );
}
```

> Bemærk: `tilfoej` har ingen skærm-fil → tilføj en tom rute-fil så Expo ikke advarer.

- [ ] **Step 3: Tom `tilfoej`-rute + entiteter-stub + placeholders**

`mobile/src/app/redaktion/(red-tabs)/tilfoej.tsx`:
```tsx
// Tom rute — "Tilføj"-fanen intercepter tabPress og åbner sheet (plan 2). Vises aldrig.
import { View } from 'react-native';
export default function Tilfoej() { return <View />; }
```

`mobile/src/app/redaktion/(red-tabs)/entiteter.tsx`:
```tsx
// Stub (plan 2): entitetslister. Plan 1 viser tom-tilstand.
import { View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body } from '../../../components/Typography';
import { Colors } from '../../../theme/tokens';
export default function Entiteter() {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Entiteter" showBack={false} />
      <View style={{ padding: 24 }}>
        <Body color={Colors.textMuted}>Entitetslister kommer i næste version.</Body>
      </View>
    </View>
  );
}
```

`index.tsx` og `konto.tsx`: midlertidige placeholders (samme mønster som entiteter, titel "Oversigt"/"Konto"). Fyldes i Task 6–7.

- [ ] **Step 4: Verificér ruterne loader**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel: `npx expo start`, naviger til `/redaktion` → tabbaren med 4 faner vises; "Tilføj"-tryk skifter ikke skærm (stub-state). (Hvis device ikke tilgængelig: noter sprunget, jf. test-regel.)

- [ ] **Step 5: Commit**

```bash
git add mobile/src/app/redaktion
git commit -m "feat(redaktion): navigation-skelet — (red-tabs) + stubs"
```

---

## Task 6: Konto-skærm + LoginSheet

**Files:**
- Create: `mobile/src/components/redaktion/LoginSheet.tsx`
- Modify: `mobile/src/app/redaktion/(red-tabs)/konto.tsx`

**Interfaces:**
- Consumes: store-actions `doSignIn`, `doSignOut`, state `session`, `rolle`, `dryRun`, `showAnnotations`, `setDryRun`, `setShowAnnotations` (alle findes i `useStore`); `oversaetFejl` fra `redaktionWrite.ts`.
- Produces: `<LoginSheet visible onClose />`.

- [ ] **Step 1: LoginSheet-komponent**

`mobile/src/components/redaktion/LoginSheet.tsx` — `Modal` (slide), drag-handle, e-mail + password `TextInput`, fejltekst, bordeaux "Log ind". Bruger `doSignIn` + `oversaetFejl`:

```tsx
import { useState } from 'react';
import { Modal, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { oversaetFejl } from '../../data/redaktionWrite';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export function LoginSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const doSignIn = useStore((s) => s.doSignIn);
  const [email, setEmail] = useState('');
  const [pw, setPw] = useState('');
  const [fejl, setFejl] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true); setFejl(null);
    try { await doSignIn(email.trim(), pw); onClose(); }
    catch (e) { setFejl(oversaetFejl(e instanceof Error ? e.message : String(e))); }
    finally { setBusy(false); }
  }

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <View style={styles.handle} />
        <Serif size={22} style={{ marginBottom: 14 }}>Log ind</Serif>
        <TextInput style={styles.input} placeholder="E-mail" autoCapitalize="none"
          keyboardType="email-address" value={email} onChangeText={setEmail} />
        <TextInput style={styles.input} placeholder="Adgangskode" secureTextEntry
          value={pw} onChangeText={setPw} />
        {fejl ? <Mono size={11} color={Colors.bordeaux} style={{ marginBottom: 8 }}>{fejl}</Mono> : null}
        <Pressable style={[styles.btn, busy && { opacity: 0.6 }]} disabled={busy} onPress={submit}>
          <BtnLabel color="#fff">{busy ? 'Logger ind…' : 'Log ind'}</BtnLabel>
        </Pressable>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet, padding: 20, paddingBottom: 36 },
  handle: { alignSelf: 'center', width: 38, height: 4, borderRadius: 2,
    backgroundColor: Border.medium, marginBottom: 14 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, padding: 12, marginBottom: 10, fontFamily: Fonts.sans, fontSize: 14 },
  btn: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14, alignItems: 'center' },
});
```

- [ ] **Step 2: Konto-skærm**

Erstat placeholderen i `konto.tsx`: logget ind → profil-kort (avatar via `InitialBadge` på session-email + rolle) + to toggles (dry-run, vis-forklaringer via `Switch`) + Log ud. Ikke logget ind → mørkt promo-kort + "Log ind"-knap (åbner `LoginSheet`). Brug `session`, `rolle`, `dryRun`, `showAnnotations`, `setDryRun`, `setShowAnnotations`, `doSignOut`. (Hifi-værdier: handoff §5.)

```tsx
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { LoginSheet } from '../../../components/redaktion/LoginSheet';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function Konto() {
  const session = useStore((s) => s.session);
  const rolle = useStore((s) => s.rolle);
  const dryRun = useStore((s) => s.dryRun);
  const showAnn = useStore((s) => s.showAnnotations);
  const setDryRun = useStore((s) => s.setDryRun);
  const setShowAnn = useStore((s) => s.setShowAnnotations);
  const doSignOut = useStore((s) => s.doSignOut);
  const [loginOpen, setLoginOpen] = useState(false);
  const email = session?.user?.email ?? '';

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Konto" showBack={false} />
      <ScrollView contentContainerStyle={{ padding: 18 }}>
        {session ? (
          <View style={styles.card}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
              <InitialBadge name={email || '?'} size={52} bg={Colors.bordeaux} color="#fff" />
              <View>
                <Body>{email}</Body>
                <Mono size={9} color={Colors.textMuted}>{rolle.toUpperCase()}</Mono>
              </View>
            </View>
          </View>
        ) : (
          <View style={[styles.card, { backgroundColor: Colors.ink }]}>
            <Serif size={20} color={Colors.paperBg}>Log ind for at redigere</Serif>
            <Pressable style={styles.loginBtn} onPress={() => setLoginOpen(true)}>
              <BtnLabel color={Colors.ink}>Log ind</BtnLabel>
            </Pressable>
          </View>
        )}

        <View style={styles.card}>
          <Row label="Dry-run · skriver ikke" value={dryRun} onChange={setDryRun} />
          <Row label="Vis forklaringer" value={showAnn} onChange={setShowAnn} />
        </View>

        {session ? (
          <Pressable style={styles.logout} onPress={doSignOut}>
            <BtnLabel color={Colors.danger ?? '#8a2b2b'}>Log ud</BtnLabel>
          </Pressable>
        ) : null}
      </ScrollView>
      <LoginSheet visible={loginOpen} onClose={() => setLoginOpen(false)} />
    </View>
  );
}

function Row({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <View style={styles.row}>
      <Body>{label}</Body>
      <Switch value={value} onValueChange={onChange} />
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 16, marginBottom: 12 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 6 },
  loginBtn: { backgroundColor: Colors.goldLight, borderRadius: Radius.field, padding: 12,
    alignItems: 'center', marginTop: 12 },
  logout: { borderWidth: 1, borderColor: 'rgba(138,43,43,0.3)', borderRadius: Radius.field,
    padding: 12, alignItems: 'center' },
});
```

> Hvis `Colors.danger` ikke findes: tilføj `danger: '#8a2b2b'` til tokens (additivt) — se Task 9 Step 0.

- [ ] **Step 3: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl (tilføj `Colors.danger` hvis tsc klager).
Manuel (hvis device): konto-tab → "Log ind" åbner sheet; forkert login → dansk fejltekst; toggles skifter state.
```bash
git add mobile/src/components/redaktion/LoginSheet.tsx mobile/src/app/redaktion/(red-tabs)/konto.tsx mobile/src/theme/tokens.ts
git commit -m "feat(redaktion): konto-skærm + login-sheet (auth wired)"
```

---

## Task 7: Dashboard-skærm

**Files:**
- Modify: `mobile/src/app/redaktion/(red-tabs)/index.tsx`

**Interfaces:**
- Consumes: `fetchKonflikter` (Task 3); store `model`, `aux`, `session`, `rolle`, `dryRun`, `setDryRun`; selectors `counts`; `LoginSheet` (Task 6).
- Produces: dashboard-rute.

- [ ] **Step 1: Implementér dashboard**

Hero (Kicker "DANMARKS ADELS AARBOG" + Serif "Redaktion") · rolle/skrivemode-kort (mørkt; avatar/email/rolle eller "Log ind"; dry-run-toggle) · "Til gennemsyn"-kø fra `fetchKonflikter` (hver række: `InitialBadge` + `model.byId[personId]?.name` + felt-tag → `router.push('/redaktion/person/' + personId)`) · entitets-grid (`counts(model, aux)`). Hifi: handoff §1.

```tsx
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { LoginSheet } from '../../../components/redaktion/LoginSheet';
import { Body, Kicker, Mono, Serif } from '../../../components/Typography';
import { fetchKonflikter, type Konflikt } from '../../../data/redaktionRead';
import { counts } from '../../../data/selectors';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function Dashboard() {
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const session = useStore((s) => s.session);
  const rolle = useStore((s) => s.rolle);
  const dryRun = useStore((s) => s.dryRun);
  const setDryRun = useStore((s) => s.setDryRun);
  const [konflikter, setKonflikter] = useState<Konflikt[]>([]);
  const [loginOpen, setLoginOpen] = useState(false);
  const c = counts(model, aux);

  useEffect(() => { if (session) fetchKonflikter().then(setKonflikter).catch(() => {}); }, [session]);

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <ScrollView contentContainerStyle={{ padding: 18 }}>
        <Kicker color={Colors.gold}>DANMARKS ADELS AARBOG</Kicker>
        <Serif size={34} style={{ marginBottom: 16 }}>Redaktion</Serif>

        <View style={[styles.card, { backgroundColor: Colors.ink }]}>
          {session ? (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
              <InitialBadge name={session.user?.email ?? '?'} size={40} bg={Colors.bordeaux} color="#fff" />
              <View style={{ flex: 1 }}>
                <Body color={Colors.paperBg}>{session.user?.email}</Body>
                <Mono size={9} color={Colors.textMuted3}>{rolle.toUpperCase()}</Mono>
              </View>
            </View>
          ) : (
            <Pressable onPress={() => setLoginOpen(true)}>
              <Serif size={18} color={Colors.paperBg}>Log ind for at redigere</Serif>
            </Pressable>
          )}
          <View style={styles.divider} />
          <View style={styles.rowBetween}>
            <Mono size={11} color={dryRun ? Colors.textMuted3 : '#c0392b'}>
              {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · skriver til basen'}
            </Mono>
            <Switch value={dryRun} onValueChange={setDryRun} />
          </View>
        </View>

        {session && konflikter.length ? (
          <>
            <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 8, marginBottom: 6 }}>
              TIL GENNEMSYN · {konflikter.length} UENIGE FELTER
            </Mono>
            {konflikter.map((k) => {
              const navn = model?.byId[k.personId]?.name ?? `#${k.personId}`;
              return (
                <Pressable key={`${k.personId}-${k.felt}`} style={styles.konfliktRow}
                  onPress={() => router.push(`/redaktion/person/${k.personId}`)}>
                  <InitialBadge name={navn} size={32} />
                  <View style={{ flex: 1, marginLeft: 10 }}>
                    <Serif size={16}>{navn}</Serif>
                    <Mono size={9} color={Colors.textMuted}>uenige kilder · {k.felt}</Mono>
                  </View>
                </Pressable>
              );
            })}
          </>
        ) : null}

        <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 12, marginBottom: 6 }}>
          ENTITETER I BASEN
        </Mono>
        <View style={styles.grid}>
          <GridCell n={c.personer} label="Personer" />
          {/* flere celler additivt fra counts(): familier, godser, kilder … */}
        </View>
      </ScrollView>
      <LoginSheet visible={loginOpen} onClose={() => setLoginOpen(false)} />
    </View>
  );
}

function GridCell({ n, label }: { n: number; label: string }) {
  return (
    <View style={styles.cell}>
      <Serif size={21} color={Colors.bordeaux}>{n}</Serif>
      <Body size={13}>{label}</Body>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: Radius.card, padding: 16, marginBottom: 12 },
  divider: { height: 1, backgroundColor: 'rgba(244,239,230,0.14)', marginVertical: 12 },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  konfliktRow: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#f8ecef',
    borderWidth: 1, borderColor: 'rgba(136,26,51,0.2)', borderRadius: 13, padding: 12, marginBottom: 7 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 9 },
  cell: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: 13, padding: 14, minWidth: '47%' },
});
```

- [ ] **Step 2: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel (hvis device + seeded redaktion-login): konflikt-kø viser rækker; tap → person-editor. Uden login: kun hero + entitets-grid.
```bash
git add mobile/src/app/redaktion/(red-tabs)/index.tsx
git commit -m "feat(redaktion): dashboard — rolle-kort, dry-run, konflikt-kø, entitets-grid"
```

---

## Task 8: Person-editor — visning af kerne-fakta (`FaktaKort` read)

**Files:**
- Create: `mobile/src/components/redaktion/FaktaKort.tsx`
- Create: `mobile/src/app/redaktion/person/[id].tsx`

**Interfaces:**
- Consumes: `fetchPersonEvidence`, `FeltEvidens`, `Oplysning` (Task 2); store `model`, `showAnnotations`.
- Produces: `<FaktaKort felt evidens onAction />` hvor `onAction` er en callback (wires i Task 9). Person-editor-rute.

- [ ] **Step 1: `FaktaKort` (read-only fold/udfold)**

Ét kort pr. kerne-felt. Sammenklappet: feltlabel (Mono) + konklusionsværdi (Serif) + kilde + "uenige"-tag + "N oplysn." + chevron. Udfoldet: pr. oplysning værdi + status + kilde; konklusion = grøn-tonet flade. Handlingsknapper renderes men kalder `onAction` (no-op i Task 8, wires i Task 9).

```tsx
import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import type { FeltEvidens, Oplysning } from '../../data/redaktionRead';
import { Border, Colors, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export type FaktaAction =
  | { type: 'gørKonklusion'; assertionId: number }
  | { type: 'redigér'; assertionId: number; nuvaerende: string }
  | { type: 'slet'; assertionId: number }
  | { type: 'tilføj'; felt: string };

export function FaktaKort({ felt, evidens, onAction }: {
  felt: string; evidens?: FeltEvidens; onAction: (a: FaktaAction) => void;
}) {
  const [open, setOpen] = useState(false);
  const konkl = evidens?.oplysninger.find((o) => o.erKonklusion);
  return (
    <View style={styles.card}>
      <Pressable style={styles.head} onPress={() => setOpen((v) => !v)}>
        <View style={{ flex: 1 }}>
          <Mono size={9} color={Colors.textMuted}>{felt.toUpperCase()}</Mono>
          <Serif size={19}>{konkl?.vaerdi ?? '—'}</Serif>
        </View>
        {evidens?.uenig ? <Mono size={8} color={Colors.bordeaux}>UENIGE</Mono> : null}
        <Mono size={9} color={Colors.textMuted}>{evidens?.oplysninger.length ?? 0} oplysn.</Mono>
      </Pressable>
      {open ? (
        <View>
          {(evidens?.oplysninger ?? []).map((o) => (
            <OplysningRad key={o.assertionId} o={o} felt={felt} onAction={onAction} />
          ))}
          <Pressable style={styles.addBtn} onPress={() => onAction({ type: 'tilføj', felt })}>
            <BtnLabel color={Colors.bordeaux}>+ Tilføj oplysning</BtnLabel>
          </Pressable>
        </View>
      ) : null}
    </View>
  );
}

function OplysningRad({ o, felt, onAction }: { o: Oplysning; felt: string; onAction: (a: FaktaAction) => void }) {
  return (
    <View style={[styles.opl, o.erKonklusion && styles.oplKonkl]}>
      <View style={{ flex: 1 }}>
        <Serif size={17}>{o.vaerdi}</Serif>
        <Mono size={8} color={Colors.textMuted}>
          {o.erKonklusion ? 'konklusion' : 'oplysning'} · {o.kilder[0]?.sourceTitel ?? '(kilde mangler)'}
        </Mono>
      </View>
      <View style={{ flexDirection: 'row', gap: 8 }}>
        {!o.erKonklusion ? (
          <Pressable onPress={() => onAction({ type: 'gørKonklusion', assertionId: o.assertionId })}>
            <Mono size={9} color="#1f5b3a">Gør til konkl.</Mono>
          </Pressable>
        ) : null}
        <Pressable onPress={() => onAction({ type: 'redigér', assertionId: o.assertionId, nuvaerende: o.vaerdi })}>
          <Mono size={9} color={Colors.textMuted}>✎</Mono>
        </Pressable>
        <Pressable onPress={() => onAction({ type: 'slet', assertionId: o.assertionId })}>
          <Mono size={9} color="#8a2b2b">🗑</Mono>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: 12, padding: 12, marginBottom: 8 },
  head: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  opl: { flexDirection: 'row', alignItems: 'center', backgroundColor: Colors.paperBg,
    borderWidth: 1, borderColor: Border.light, borderRadius: 9, padding: 10, marginTop: 8 },
  oplKonkl: { backgroundColor: '#eaf3ec', borderColor: 'rgba(31,91,58,0.32)' },
  addBtn: { paddingVertical: 10, marginTop: 4 },
});
```

- [ ] **Step 2: Person-editor-skærm (visning)**

`person/[id].tsx`: header (`InitialBadge` + navn fra `model.byId[id]`), evidens-note hvis `showAnnotations`, 5 `FaktaKort` (navn/foedt/doed/koen/titel) drevet af `fetchPersonEvidence`. `onAction` = midlertidig `console.log` (wires i Task 9). Familie/sektioner: read-only via eksisterende selectors (kan tilføjes additivt; plan 1-minimum = kerne-fakta + navn-header).

```tsx
import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { FaktaKort, type FaktaAction } from '../../../components/redaktion/FaktaKort';
import { Body, Mono, Serif } from '../../../components/Typography';
import { fetchPersonEvidence, type PersonEvidence } from '../../../data/redaktionRead';
import { useStore } from '../../../store/useStore';
import { Colors } from '../../../theme/tokens';

const FELTER = ['navn', 'foedt', 'doed', 'titel']; // koen håndteres separat (ikke et fact)

export default function PersonEditor() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const model = useStore((s) => s.model);
  const showAnn = useStore((s) => s.showAnnotations);
  const [ev, setEv] = useState<PersonEvidence | null>(null);
  const person = id && model ? model.byId[id] : null;

  useEffect(() => { if (id) fetchPersonEvidence(id).then(setEv).catch(() => {}); }, [id]);

  function onAction(a: FaktaAction) { console.log('action', a); } // wires i Task 9

  if (!person) return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Person" />
      <Body color={Colors.textMuted} style={{ padding: 24 }}>Personen blev ikke fundet.</Body>
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={person.name} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <View style={{ alignItems: 'center', marginBottom: 16 }}>
          <InitialBadge name={person.name} size={56} bg="#f8ecef" />
          <Serif size={25} style={{ marginTop: 8 }}>{person.name}</Serif>
          <Mono size={9} color={Colors.textMuted}>id {String(person.id)} · {ev?.koen ?? '—'}</Mono>
        </View>
        {showAnn ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 12 }}>
            Konklusion ← oplysninger. Hver oplysning er én kildes udsagn.
          </Mono>
        ) : null}
        {FELTER.map((felt) => (
          <FaktaKort key={felt} felt={felt} evidens={ev?.felter[felt]} onAction={onAction} />
        ))}
      </ScrollView>
    </View>
  );
}
```

- [ ] **Step 3: Verificér + commit**

Run: `cd mobile && npx tsc --noEmit`
Expected: ingen fejl.
Manuel (hvis device): åbn `/redaktion/person/<id>` → kerne-fakta-kort folder ud; konklusion grøn-tonet; uenige felter har UENIGE-tag.
```bash
git add mobile/src/components/redaktion/FaktaKort.tsx mobile/src/app/redaktion/person/[id].tsx
git commit -m "feat(redaktion): person-editor — kerne-fakta-visning (FaktaKort read)"
```

---

## Task 9: Person-editor — skrive-handlinger + SkrivePreviewSheet

**Files:**
- Modify: `mobile/src/theme/tokens.ts` (tilføj redaktion-status-tokens hvis manglende)
- Create: `mobile/src/components/redaktion/SkrivePreviewSheet.tsx`
- Modify: `mobile/src/app/redaktion/person/[id].tsx` (wire `onAction` → submit + preview)

**Interfaces:**
- Consumes: `submitChange`, `buildRpcCall`, `describeCall`, `oversaetFejl`, `Change` (Task 4); store `dryRun`, `rolle`; `fetchPersonEvidence` (re-fetch efter write).
- Produces: `<SkrivePreviewSheet ... />`; fungerende skrive-flow på kerne-fakta + narrativ.

- [ ] **Step 0: Tilføj manglende status-tokens (hvis ikke til stede)**

I `tokens.ts` `Colors`, tilføj additivt:
```ts
  // Redaktion-status (handoff §Design tokens)
  konklusionGroen: '#1f5b3a',
  konklusionFlade: '#eaf3ec',
  danger: '#8a2b2b',
  liveRoed: '#c0392b',
  konfliktFlade: '#f2dede',
```

- [ ] **Step 1: SkrivePreviewSheet**

Modal der viser enten dry-run-preview (`describeCall`) eller udfører LIVE og viser resultat/fejl. Tager en `Change` + `onDone`-callback:

```tsx
import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { buildRpcCall, describeCall, oversaetFejl, submitChange, type Change } from '../../data/redaktionWrite';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export function SkrivePreviewSheet({ change, onClose, onApplied }: {
  change: Change | null; onClose: () => void; onApplied: () => void;
}) {
  const dryRun = useStore((s) => s.dryRun);
  const [status, setStatus] = useState<'idle' | 'busy' | 'ok' | 'err'>('idle');
  const [fejl, setFejl] = useState<string | null>(null);
  useEffect(() => { setStatus('idle'); setFejl(null); }, [change]);
  if (!change) return null;
  const call = buildRpcCall(change);

  async function run() {
    setStatus('busy'); setFejl(null);
    try { await submitChange(change as Change, { dryRun }); setStatus('ok');
      if (!dryRun) onApplied(); }
    catch (e) { setFejl(oversaetFejl(e instanceof Error ? e.message : String(e))); setStatus('err'); }
  }

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>
          {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · skriver til basen'}
        </Serif>
        <ScrollView style={{ maxHeight: 220 }}>
          <View style={styles.code}>
            <Mono size={11} color={Colors.paperBg}>{call ? describeCall(call) : '(intet kald)'}</Mono>
          </View>
        </ScrollView>
        {fejl ? <Mono size={11} color={Colors.bordeaux} style={{ marginTop: 8 }}>{fejl}</Mono> : null}
        {status === 'ok' ? <Mono size={11} color={Colors.konklusionGroen} style={{ marginTop: 8 }}>
          ✓ {dryRun ? 'Forhåndsvist' : 'Udført'}</Mono> : null}
        <Pressable style={styles.btn} disabled={status === 'busy'} onPress={status === 'ok' && !dryRun ? onClose : run}>
          <BtnLabel color="#fff">{dryRun ? 'Forhåndsvis' : status === 'ok' ? 'Luk' : 'Skriv til basen'}</BtnLabel>
        </Pressable>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet, padding: 20, paddingBottom: 36 },
  code: { backgroundColor: Colors.ink, borderRadius: 8, padding: 12, marginBottom: 6 },
  btn: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14,
    alignItems: 'center', marginTop: 12 },
});
```

- [ ] **Step 2: Wire `onAction` i person-editoren**

Erstat `console.log`-stubben. `onAction` bygger en `Change` og åbner `SkrivePreviewSheet`. For `redigér`/`tilføj` vises først en inline-formular (værdi + kilde) — minimal: brug `prompt`-lignende lokal state med to `TextInput` i en lille inline-boks, eller åbn preview direkte med indtastet værdi. Efter LIVE-write: `fetchPersonEvidence(id).then(setEv)`.

```tsx
// I PersonEditor: tilføj state
const [pending, setPending] = useState<Change | null>(null);
const dryRun = useStore((s) => s.dryRun);

function onAction(a: FaktaAction) {
  if (a.type === 'gørKonklusion') {
    setPending({ art: 'setKonklusion', subjektType: 'person', subjektId: id!, assertionId: String(a.assertionId) });
  } else if (a.type === 'slet') {
    setPending({ art: 'sletOplysning', subjektType: 'person', subjektId: id!, assertionId: String(a.assertionId) });
  } else if (a.type === 'redigér') {
    // minimal: åbn inline-editor (egen state), her vist som direkte preview med uændret værdi
    setPending({ art: 'redigerOplysning', subjektType: 'person', subjektId: id!,
      assertionId: String(a.assertionId), felt: a.felt ?? undefined, vaerdi: a.nuvaerende });
  } else if (a.type === 'tilføj') {
    setPending({ art: 'fakta', subjektType: 'person', subjektId: id!, felt: a.felt, vaerdi: '' });
  }
}

// I JSX, efter ScrollView:
<SkrivePreviewSheet change={pending} onClose={() => setPending(null)}
  onApplied={() => { setPending(null); if (id) fetchPersonEvidence(id).then(setEv); }} />
```

> Inline værdi/kilde-input: tilføj en simpel `EditOplysningSheet` ELLER udvid `FaktaKort` med inline `TextInput` (handoff §3 "Udfoldet"). Minimum for plan 1: en inline-boks med to felter (værdi, kilde) der opdaterer `pending.vaerdi`/`pending.kildeFritekst` før preview. Implementér som lokal state i `FaktaKort` der kalder `onAction` med de indtastede værdier.

- [ ] **Step 3: Verificér + commit**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: alle tests PASS, ingen tsc-fejl.
Manuel (seeded redaktion-login + LIVE): redigér en oplysning → preview viser `red_edit_oplysning` → "Skriv til basen" → værdi opdateres efter re-fetch. Dry-run: viser kun fn+args. Medlem-rolle/P0001: dansk fejltekst.
```bash
git add mobile/src/components/redaktion/SkrivePreviewSheet.tsx mobile/src/app/redaktion/person/[id].tsx mobile/src/theme/tokens.ts
git commit -m "feat(redaktion): skrive-handlinger + skrive-preview-sheet (dry-run/live)"
```

---

## Task 10: Slet-bekræft-sheet + narrativ-redigering

**Files:**
- Create: `mobile/src/components/redaktion/SletBekraeftSheet.tsx`
- Modify: `mobile/src/app/redaktion/person/[id].tsx` (Slet-knap + Privat-toggle + narrativ-felt)

**Interfaces:**
- Consumes: `red_slet_person_preview` (Task 1) via en lille `fetchSletPreview(personId)` (tilføj til `redaktionRead.ts`); `submitChange` med `art:'sletPerson'`/`'setPrivat'`/`'narrativ'`.
- Produces: fungerende sletning m. cascade-advarsel + acknowledge; privat-toggle; narrativ-redigering.

- [ ] **Step 1: `fetchSletPreview` i `redaktionRead.ts`**

```ts
export type SletPreview = { antalRelationer: number; antalFacts: number;
  relationer: { rolle: string; retning: string; modpartId: number }[] };

export async function fetchSletPreview(personId: string): Promise<SletPreview> {
  const tom: SletPreview = { antalRelationer: 0, antalFacts: 0, relationer: [] };
  if (!supabase) return tom;
  const { data, error } = await supabase.rpc('red_slet_person_preview', { p_person_id: Number(personId) });
  if (error || !data) return tom;
  return { antalRelationer: data.antal_relationer ?? 0, antalFacts: data.antal_facts ?? 0,
    relationer: (data.relationer ?? []).map((r: { rolle: string; retning: string; modpart_id: number }) =>
      ({ rolle: r.rolle, retning: r.retning, modpartId: r.modpart_id })) };
}
```

- [ ] **Step 2: SletBekraeftSheet**

⚠-badge, "Slet person?", cascade-advarsel (`fetchSletPreview` — "N relationer · M facts brydes", liste af modparter via `model.byId`), acknowledge-checkbox → låser rød "Slet endeligt" op → `submitChange({ art:'sletPerson', ... })`. (Mønster som SkrivePreviewSheet; checkbox via lokal `useState<boolean>`.)

- [ ] **Step 3: Wire Slet + Privat + narrativ i editoren**

I `person/[id].tsx` header-handlinger: **Slet**-knap → åbner `SletBekraeftSheet`; **Privat**-toggle → `submitChange({ art:'setPrivat', subjektId:id, payload:{ privat:!nuvaerende } })` (via preview-sheet). Tilføj **narrativ**-sektion: `TextInput` (multiline) + "Gem" → `submitChange({ art:'narrativ', subjektType:'person', subjektId:id, vaerdi:tekst })`. (Ingen kilde-felt — RPC mangler params, spec §6.2.)

- [ ] **Step 4: Verificér + commit**

Run: `cd mobile && npx jest && npx tsc --noEmit`
Expected: PASS, ingen tsc-fejl.
Manuel (seeded redaktion, LIVE, en test-person): Slet → advarsel viser korrekte relations-antal (ind+ud) → acknowledge → slet; privat-toggle skjuler ikke personen for redaktøren (RLS Task 1 virker); narrativ gemmes.
```bash
git add mobile/src/components/redaktion/SletBekraeftSheet.tsx mobile/src/data/redaktionRead.ts mobile/src/app/redaktion/person/[id].tsx
git commit -m "feat(redaktion): slet-bekræft m. cascade-advarsel + privat-toggle + narrativ-redigering"
```

---

## Task 11: Integration + manuel funktionstest + dokumentation

**Files:**
- Modify: `docs/changelog.md`, `docs/decisions.md` (kort entry)

- [ ] **Step 1: Seed en redaktion-profil (manuelt, engangs)**

I Supabase-dashboard: opret en auth-bruger (e-mail/password). Indsæt `profiles`-row:
```sql
insert into profiles (id, rolle, email) values ('<auth-user-uuid>', 'redaktion', '<email>')
on conflict (id) do update set rolle='redaktion';
```

- [ ] **Step 2: Fuld manuel happy-path mod LIVE**

Login (redaktion) → dashboard konflikt-kø → åbn person → udfold fakta → tilføj oplysning (LIVE) → gør til konklusion → redigér → slet → narrativ gem → privat-toggle → slet test-person. Verificér hver write i Supabase Table Editor. Notér resultat (bestået/sprunget + hvorfor) jf. test-regel.

- [ ] **Step 3: Kør hele jest-suiten**

Run: `cd mobile && npx jest`
Expected: alle grønne (eksisterende 71 + nye read/write-tests).

- [ ] **Step 4: Changelog + decisions + commit**

Tilføj kort entry i `docs/changelog.md` (redaktions-UI kerne-skive) + `docs/decisions.md` (security_invoker-view, redaktion-read-RLS, blød assertion arvet). Commit:
```bash
git add docs/changelog.md docs/decisions.md
git commit -m "docs: redaktions-UI kerne-skive — changelog + decisions"
```

---

## Self-Review

**Spec coverage:**
- §2 navigation → Task 5. §3 evidens-read → Task 2. §4 felt-map → genbrugt i Task 2/4. §5 konflikt-view (security_invoker, navn/titel) → Task 1+3. §6.1 dashboard → Task 7. §6.2 person-editor (kerne-fakta + narrativ, RLS-afhængighed) → Task 8–10. §6.3 konto → Task 6. §7 sheets → Task 6 (login), 9 (preview), 10 (slet). §8 write-wiring → Task 4. §8b DB-ændringer → Task 1. §9 dry-run/fejl → Task 4 (oversaetFejl), 9. §11 test → TDD i Task 2–4, manuel i Task 11. Alle spec-sektioner dækket.
- **Non-goals** (§13: entitetslister, generisk editor, opret-flow, relations/sektion-redigering) er IKKE planlagt — korrekt.

**Placeholder-scan:** Inline value/kilde-editor i Task 9 Step 2 er beskrevet som "implementér som lokal state i FaktaKort" uden fuld JSX — eneste bevidste skitse-punkt; resten har komplet kode. Eksekvér med en simpel to-felts inline-boks (værdi + kilde) der kalder `onAction` med indtastede værdier.

**Type-konsistens:** `Change.assertionId: string` → `Number()` i buildRpcCall. `FaktaAction` matcher onAction i Task 8/9. `PersonEvidence`/`FeltEvidens`/`Oplysning`/`Kilde` ens i Task 2 og forbrugt i Task 8. RPC-param-navne (`p_assertion_id`, `p_person_id`, `p_vaerdi`, `p_date_raw`, `p_kilde_fritekst`, `p_privat`) verificeret mod `schema.sql`-signaturer.
