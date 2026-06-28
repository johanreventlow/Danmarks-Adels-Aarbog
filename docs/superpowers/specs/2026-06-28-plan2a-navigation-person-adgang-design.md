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
export type RedPerson = {
  id: string;
  navn: string;
  aar: string;            // KUN til visning ("1644–1708")
  born: number | null;    // til born-sort — udledt DIREKTE af visning_foedt (ikke af aar)
  levende: boolean;       // skjult fra publikum (de 70 levende)
  privat: boolean;        // manuelt skjult (pt. 0)
};

export async function fetchRedaktionPersoner(): Promise<RedPerson[]> {
  if (!supabase) return [];
  // PAGINÉR: PostgREST capper ved 1000 rækker pr. svar (lydløst). Genbrug getAll/.range()-
  // mønsteret fra load.ts — basen har 963 personer nu, men ÉN import mere → >1000 → tabte
  // personer (Codex cycle 2A H1). getAll kaster videre ved error (cycle 03 NEW1) → ingen
  // tom-som-clean.
  const rows = await getAll<RawRedPerson>(() =>
    supabase!.from('person').select('id,visning_navn,visning_foedt,visning_doed,levende,privat'));
  return rows.map(mapRedPerson);
}
```

- **RLS verificeret live (2026-06-28):** `redaktion_read`-policy ER deployet og virker — som
  **redaktion** returnerer `person` alle **963** rækker; som **anon** kun **893** (de 70
  `levende` skjult). Forudsætning: `db-rls.sql` redaktion-read-lag deployet (gjort + verificeret).
- `getAll` skal kaste videre ved Supabase-error (tilpas/genbrug eksisterende helper — den nuværende
  `getAll` i load.ts kaster allerede via `if (error) throw error`).
- `mapRedPerson(row)` → ren funktion: `navn = visning_navn ?? '(uden navn)'`; `born =
  parseYear(visning_foedt)` (DIREKTE fra fødselsfeltet — IKKE fra dødsår); `aar =
  fmtYears(visning_foedt, visning_doed)` (genbrug `fields.ts:fmtYears` — verificeret tager
  streng-felter, samme som load.ts bruger); `levende`/`privat` = `Boolean(...)`.
- Den delte `load.ts` (`.filter(p => !p.privat)`, linje 103) ændres IKKE → publikums-faner urørt.

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

Redaktions-listen mapper `RedPerson[]` → `SearchItem[]` (`{ id, name: navn, years: aar, born:
p.born }`) og kalder `searchPool`. **`born` tages DIREKTE fra `RedPerson.born`** (udledt af
visning_foedt), IKKE ved at re-parse `aar`-strengen — ellers ville en person uden fødselsår men
med dødsår få dødsåret som born og sortere forkert (Codex cycle 2A M1). `SearchItem` udvides IKKE
med levende/privat; tags slås op separat i render via et `Set<id>` (eller map) — så
`SearchItem`-kontrakten holdes ren.

**Bemærk:** `searchPool` bevarer eksakt samme adfærd som nuværende `buildSearch` (dansk alfabet-orden, Æ/Ø/Å sidst, alfabet-bar skjult ved born-sort/søgning). Refaktoreringen er ren udtræk — publikums-`search.tsx` skal stadig bestå uændret.

## 4. Skærme & navigation

### 4.1 `redaktion/(red-tabs)/entiteter.tsx` (erstat stub)
Person-liste, mønster fra `app/(tabs)/search.tsx`:
- TopBar "Personer" (showBack=false).
- Sticky søgefelt (`TextInput`, ⌕-glyph) — **lokal** `query`-state.
- Alfabet-bar (chips, kun forekommende bogstaver) — **lokal** `activeLetter`-state; skjult ved søgning.
- Sortér-toggle (alfabetisk / fødeår) — **lokal** `sort`-state.
- `SectionList` med sticky bogstav-headers (alfa-sort) eller flad liste (born-sort).
- Rad: `InitialBadge` + navn (Serif) + år (Mono) + **"ikke-offentlig"-tag** (mono,
  `Colors.bordeaux`-tonet) hvis `levende` ELLER `privat` — tekst "levende" hhv. "privat". (De 70
  levende er den faktiske skjulte-fra-publikum-gruppe; `privat` er pt. 0.) Tap →
  `router.push('/redaktion/person/' + id)`.
- Henter via `fetchRedaktionPersoner()` i `useEffect` (afhænger af `session`); **fejl-tilstand** (eksplicit "Kunne ikke hente personer", ikke tom liste).
- Tom-tilstand (0 personer, ingen fejl): "Ingen personer".

### 4.2 Dashboard entitets-grid
- "Personer"-cellen → `router.push('/redaktion/entiteter')` (eller tab-skift til Entiteter).
- Øvrige celler (godser/kilder/…) → "kommer snart" (no-op eller lille toast/label) indtil 2C.
- Grid-tallet forbliver fra den delte model (ikke-private count) — kan afvige let fra
  redaktions-listens fulde antal; acceptabelt (noteres).

## 5. Skjult-fra-publikum-håndtering (levende + privat)
- **Verificeret live:** redaktion ser alle 963 (inkl. 70 `levende`); anon ser 893. `redaktion_read`
  er unconditional for rollen → redaktøren finder også levende personer publikum ikke kan.
- Tag på rækken = `levende || privat` ("levende"/"privat"). Pt.: 70 levende, 0 privat.
- Ingen klient-side filter i redaktions-stien (modsat publikums-`load.ts` der filtrerer privat).
- Som ikke-redaktion: RLS giver kun det offentlige (893) → listen viser det, ingen tags.

## 5b. Codex adversarial-review konsekvens (2026-06-28)
**Verdict:** needs-attention → rettet i denne spec.
- **H1 (pagination) — confirmed:** ét select rammer PostgREST's 1000-cap; `fetchRedaktionPersoner`
  bruger nu `getAll/.range()` (§2). Plan SKAL teste mod >1000-datasæt.
- **#2 (RLS-deployment) — recalibrated/empirisk afkræftet:** Codex læste db-rls.sql's header
  ("RLS endnu ikke anvendt") og antog policy ikke live. Verificeret mod prod 2026-06-28:
  redaktion ser 963, anon 893 → `redaktion_read` ER live + virker. Spec noterer deployment som
  forudsætning + anbefaler integrationstest (anon/medlem/redaktion mod synlighed).
- **M1 (born-sort) — confirmed:** `RedPerson.born` udledes nu direkte af visning_foedt, ikke af
  aar-strengen (§2-3).
- **Bekræftet sikkert af Codex:** navigation (`/redaktion/entiteter`, group ikke i URL), separat
  tag-Set, fmtYears-genbrug, publikums-model-isolering.

## 6. Fejlhåndtering
- `fetchRedaktionPersoner` kaster ved Supabase-fejl.
- Entiteter-skærmen fanger → eksplicit fejl-tilstand (samme mønster som cycle 03 NEW1
  konflikt-kø). ALDRIG tom-som-clean.

## 7. Test
- **jest:** `searchPool` (alfabet-orden, query-filter, letter-filter, born-sort, showLetters-regel)
  + **regression:** `buildSearch`-wrapper giver EKSAKT samme output som før refactor (snapshot/
  eksplicit). `mapRedPerson` (navn-fallback; `born` fra visning_foedt — IKKE dødsår når foedt
  mangler; levende/privat-bool; aar-format).
- **Pagination:** test at `fetchRedaktionPersoner` henter >1000 rækker (mock getAll/range med
  2 sider) — ingen lydløs trunkering (Codex H1).
- **RLS-integration (anbefalet, R/psql):** bekræft synlighed pr. rolle mod prod/branch —
  anon=893, redaktion=963; ved fremtidig manuel `privat`-markering: anon taber den, redaktion ser den.
- **Manuel:** reload → log ind redaktion → Entiteter → liste (levende-tags) → søg → alfabet-hop
  → tap → person-editor. Fejl-tilstand: manuel/noteret.

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
