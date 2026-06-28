# Plan 2A — Navigation & person-adgang (design/spec)

**Dato:** 2026-06-28
**Status:** Godkendt design — klar til implementeringsplan
**Branch:** arbejd på `main` (feature-branch oprettes ved implementering)
**Kontekst:** Første slice af plan 2 (redaktions-UI ud over kerne-skiven). Plan 1 leverede
person-editoren, men der er INGEN in-app-vej til en person — man taster URL'en, hvilket på web
giver fuld reload (nulstiller bl.a. skrivemode). 2A giver Entiteter-tab'en en rigtig
person-liste med søg, så enhver person (inkl. private) kan findes og åbnes uden URL-tastning.

Forudgående: `docs/superpowers/specs/2026-06-27-redaktion-ui-kerne-skive-design.md` (plan 1).

---

## 1. Besluttede valg

| Beslutning | Valg | Note |
|---|---|---|
| Datakilde for listen | **Separat `fetchRedaktionPersoner()`** (inkl. private) | Den delte publikums-model røres ikke → ingen GDPR-læk i publikums-faner. |
| Entiteter-tab i 2A | **Direkte til person-liste** | Entitets-type-menu hører til 2C (når andre lister findes). |
| Søge-tilstand | **Lokal component-state** | Ingen kobling med publikums-søg (global store). |
| Søge-logik | **Refaktorér `buildSearch` til pool-baseret** | DRY — genbruges af publikum + redaktion. |
| Scope | **Kun person-liste** | Ikke-person-entiteter har ingen editor endnu (2C). |

---

## 2. Data: `fetchRedaktionPersoner`

Nyt i `mobile/src/data/redaktionRead.ts`:

```ts
export type RedPerson = { id: string; navn: string; aar: string; privat: boolean };

export async function fetchRedaktionPersoner(): Promise<RedPerson[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('person')
    .select('id,visning_navn,visning_foedt,visning_doed,privat');
  // Kast ved fejl — ALDRIG tom-som-clean (cycle 03 NEW1-læring): en RLS/grant-fejl må
  // ikke fremstå som "ingen personer".
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapRedPerson);
}
```

- RLS gør arbejdet: logget ind som **redaktion** → `redaktion_read`-policy returnerer OGSÅ
  private rækker (plan 1 §8b). Som `medlem`/anon → kun ikke-private.
- `mapRedPerson(row)` → `{ id: String(id), navn: visning_navn ?? '(uden navn)', aar: fmtAar(foedt, doed), privat: Boolean(privat) }`. Ren funktion → unit-testes.
- `fmtAar` genbruger samme år-formattering som publikums-modellen (`fields.ts`/`fmtYears`) hvor muligt; ellers en lille lokal `"foedt–doed"`-formattering.
- Den delte `load.ts` (`.filter(p => !p.privat)`, linje 103) ændres IKKE.

## 3. Søge-logik: pool-baseret `buildSearch`

`buildSearch(model, opts)` i `selectors.ts` læser i dag `model.persons` direkte. Refaktorér så
kernen tager en **pool** af `SearchItem`:

```ts
// Ny kerne (ren, poolable):
export function searchPool(
  pool: SearchItem[],
  opts: { query: string; sort: 'alpha' | 'born'; activeLetter: string | null },
): { matches: SearchItem[]; letters: {...}[]; showLetters: boolean; groups: {...}[] }

// Bagudkompatibel wrapper (publikums-appen uændret):
export function buildSearch(model, opts) {
  return searchPool((model?.persons ?? []).map(p => ({ id: p.id, name: p.name, years: p.years, born: p.born })), opts);
}
```

Redaktions-listen mapper `RedPerson[]` → `SearchItem[]` (`{ id, name: navn, years: aar, born: <årstal-til-sort> }`) og kalder `searchPool`. `SearchItem` udvides IKKE med `privat`; privat-tag slås op separat i render via et `Set<id>` af private (eller en parallel map), så `SearchItem`-kontrakten holdes ren.

**Bemærk:** `searchPool` bevarer eksakt samme adfærd som nuværende `buildSearch` (dansk alfabet-orden, Æ/Ø/Å sidst, alfabet-bar skjult ved born-sort/søgning). Refaktoreringen er ren udtræk — publikums-`search.tsx` skal stadig bestå uændret.

## 4. Skærme & navigation

### 4.1 `redaktion/(red-tabs)/entiteter.tsx` (erstat stub)
Person-liste, mønster fra `app/(tabs)/search.tsx`:
- TopBar "Personer" (showBack=false).
- Sticky søgefelt (`TextInput`, ⌕-glyph) — **lokal** `query`-state.
- Alfabet-bar (chips, kun forekommende bogstaver) — **lokal** `activeLetter`-state; skjult ved søgning.
- Sortér-toggle (alfabetisk / fødeår) — **lokal** `sort`-state.
- `SectionList` med sticky bogstav-headers (alfa-sort) eller flad liste (born-sort).
- Rad: `InitialBadge` + navn (Serif) + år (Mono) + **"privat"-tag** (mono, `Colors.bordeaux`-tonet) hvis privat. Tap → `router.push('/redaktion/person/' + id)`.
- Henter via `fetchRedaktionPersoner()` i `useEffect` (afhænger af `session`); **fejl-tilstand** (eksplicit "Kunne ikke hente personer", ikke tom liste).
- Tom-tilstand (0 personer, ingen fejl): "Ingen personer".

### 4.2 Dashboard entitets-grid
- "Personer"-cellen → `router.push('/redaktion/entiteter')` (eller tab-skift til Entiteter).
- Øvrige celler (godser/kilder/…) → "kommer snart" (no-op eller lille toast/label) indtil 2C.
- Grid-tallet forbliver fra den delte model (ikke-private count) — kan afvige let fra
  redaktions-listens fulde antal; acceptabelt (noteres).

## 5. Privat-håndtering
- Private personer vises i redaktions-listen (redaktion ser dem via RLS); markeret med tag.
- Som ikke-redaktion: RLS giver kun ikke-private → listen viser ikke-private (ingen tag).
- Ingen klient-side privat-filter i redaktions-stien (modsat publikums-`load.ts`).

## 6. Fejlhåndtering
- `fetchRedaktionPersoner` kaster ved Supabase-fejl.
- Entiteter-skærmen fanger → eksplicit fejl-tilstand (samme mønster som cycle 03 NEW1
  konflikt-kø). ALDRIG tom-som-clean.

## 7. Test
- **jest:** `searchPool` (alfabet-orden, query-filter, letter-filter, born-sort, showLetters-regel)
  + bekræft `buildSearch`-wrapper giver samme output som før (regression). `mapRedPerson`
  (navn-fallback, privat-bool, år-format).
- **Manuel:** reload → log ind redaktion → Entiteter → liste m. private (tag) → søg → alfabet-hop
  → tap → person-editor. Fejl-sti: manuel/noteret.

## 8. Berørte artefakter
**Nye:** (ingen nye filer ud over screen-erstatning)
**Ændrede:**
- `mobile/src/data/redaktionRead.ts` (+ `fetchRedaktionPersoner`, `mapRedPerson`, `RedPerson`).
- `mobile/src/data/selectors.ts` (refaktorér `buildSearch` → `searchPool` + wrapper).
- `mobile/src/app/redaktion/(red-tabs)/entiteter.tsx` (stub → person-liste).
- `mobile/src/app/redaktion/(red-tabs)/index.tsx` (dashboard "Personer"-celle → naviger).
- Tests: `redaktionRead.test.ts`, `selectors`-test (ny eller eksisterende).

## 9. Scope / non-goals
**I scope:** person-liste (søg/alfabet/sort) i Entiteter-tab; separat redaktion-person-fetch
inkl. private; pool-baseret `buildSearch`-refactor; dashboard "Personer"-celle-navigation;
fejl-tilstand.

**Non-goals (senere slices):**
- Entitets-type-menu + ikke-person-lister (godser/kilder/hverv/våben/…) → 2C.
- Generisk record-editor + opret-flow → 2C.
- Køn-editor + familie/sektion-read-only-visning i person-editoren → 2B.
- Reload af delt model post-login (undgås bevidst — separat fetch i stedet).
