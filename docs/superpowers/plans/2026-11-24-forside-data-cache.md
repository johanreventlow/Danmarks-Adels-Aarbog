# Færdigpakket forside-data — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forsiden henter sine langsomme data som én fil fra en Vercel-funktion bag Vercels CDN, så de første seks
kort er rigtige kort, mens blandingen stadig sker tilfældigt i browseren.

**Architecture:** De fem rå hentninger flyttes ud i ét env-frit modul, der tager en Supabase-klient som parameter;
browserens loadere og en ny funktion `web/api/forside-data.ts` bruger samme kode. Funktionen leverer de *rå* svar plus
`komplet`/`personIder`/`genereret`; browseren kører de eksisterende bygge-funktioner. Mangler filen, henter forsiden
som i dag.

**Tech Stack:** TypeScript, React 18, Vitest, Supabase JS v2, Vercel Node-funktioner.

**Spec:** `docs/superpowers/specs/2026-11-24-forside-data-cache-design.md`

## Global Constraints
- Kun anon-nøglen (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` fra Vercels miljø); aldrig service-rollen.
- Ingen DB-ændring, ingen ny RPC.
- Cache-header ved fuldt svar: `public, s-maxage=3600, stale-while-revalidate=86400`. Funktionsregion `fra1`,
  `maxDuration` 60.
- Alle brugere får filen (også indloggede). Klienten afviser en fil med `genereret` ældre end 48 timer.
- Et ufuldstændigt eller udækket resultat er aldrig bevis for fravær: intet nævnt-grundlag fra det.
- Kommentarer, testnavne og commits på dansk; Conventional Commits; én commit pr. task; mellemliggende push med
  `[skip ci]`.

## Review Focus
1. **Kold cache / langsom generering** (første besøg efter deploy, 10-60 s): browseren venter højst 2 s på filen og
   henter så som i dag; ingen dobbelt første uddeling → testet i Task 4.
2. **Rewrite-fælde**: hvis `/api/` ikke er undtaget i `vercel.json`, svarer Vercel med `index.html` (200, HTML); det må
   aldrig tolkes som data → testet i Task 4 (HTML-svar → `null`).
3. **Gammel fil** (basen pauset, `stale-while-revalidate` serverer længe): `genereret` > 48 t → afvist → testet i Task 4.
4. **Person tilføjet efter generering** (ikke-levende modelperson, hvis række-id ikke står i `personIder`): intet
   nævnt-grundlag fra filen → testet i Task 5.
5. **En del fejlede helt** (fx hændelses-bladringen): svar `503` + `no-store`, så CDN'et ikke gemmer en dårlig fil i en
   time; delvise biografier caches kun kort → testet i Task 3.

---

### Task 1: Vercel-forsøg — en funktion, der importerer `@daa/core`, kører på et preview

**Files:**
- Create: `web/api/forside-data.ts` (midlertidig: svarer `{ ok: true, version: FORSIDE_DATA_VERSION }`)
- Create: `web/src/data/forside/format.ts` (kun `export const FORSIDE_DATA_VERSION = 1;` i denne task)
- Modify: `web/vercel.json` (rewrite-regex undtager `api/`; `"functions": { "api/forside-data.ts": { "maxDuration": 60 } }`; `"regions": ["fra1"]`)

**Interfaces:**
- Produces: `FORSIDE_DATA_VERSION: 1` i `web/src/data/forside/format.ts`.

- [ ] **Step 1:** Skriv funktionen som Vercel Node-handler (`export default async function handler(req, res)` med
  `@vercel/node`-typer, eller Web-`Request`→`Response` — vælg den form Vercel bygger i dette repo) og lad den importere
  `FORSIDE_DATA_VERSION` *og* én funktion fra `@daa/core` (fx `getAll` som reference), så bundling af workspace-pakkerne
  (`exports: "./src/index.ts"`) bliver prøvet.
- [ ] **Step 2:** `npm run build -w web` → exit 0 (funktionen må ikke knække Vite-bygget eller `tsc -b`).
- [ ] **Step 3: Commit + push** (`[skip ci]`): `chore(web): forsøg med Vercel-funktion til forside-data [skip ci]`.
- [ ] **Step 4:** Når Vercel-previewet er bygget: `curl -s -D - <preview>/api/forside-data` → `200`,
  `content-type: application/json`, body `{"ok":true,"version":1}`. Får du `401` (Vercels preview-beskyttelse), så bed
  projektejeren åbne URL'en og sende svaret. Får du HTML, er rewriten forkert. Bygger funktionen ikke (workspace-TS),
  stop og rapportér — planens resten forudsætter, at dette virker.

### Task 2: Env-frie rå hentninger med klient som parameter

**Files:**
- Create: `web/src/data/forside/kilder.ts`
- Modify: `web/src/data/feedAux.ts` (`hentFeedBios` bruger `hentBioRaekker` + `vaelgFeedBios`)
- Modify: `web/src/data/haendelser.ts` (`bladrFeed` → `bladrHaendelser(supabase)`)
- Modify: `web/src/data/livsdato.ts`, `web/src/data/story.ts`, `web/src/data/feedGrundlag.ts` (delegerer)
- Test: `web/src/data/forside/__tests__/kilder.test.ts`; eksisterende `feedAux`, `haendelser`, `livsdato`, `story`,
  `feedGrundlag`-tests skal forblive grønne uændret.

**Interfaces:**
- Produces (alle i `kilder.ts`, ingen import af `../supabase`; `type Sb = SupabaseClient`; *kaster* ved fejl):
  - `hentPersonIder(sb: Sb): Promise<number[]>` — `person.id` som gæst kan læse, sorteret.
  - `hentBioRaekker(sb: Sb, personIds: number[]): Promise<{ kontrakt: number; rows: unknown[]; fejlede: number[] }>` —
    flyttet fra `hentFeedBios` (bidder à `FEED_BIO_IN_CHUNK`, parallelitet `FEED_BIO_PARALLEL`, genforsøg som to
    halvdele); kaster kun, når kontrakt-RPC'en fejler eller alle bidder fejler.
  - `vaelgFeedBios(r: { kontrakt: number; rows: unknown[]; fejlede: number[] }, canonicalIdById: Record<string, string>): Record<string, string>`
    — valget fra `hentFeedBios` (v2-default pr. kanonisk person; udelad kanoniske personer med et fejlet id).
  - `bladrHaendelser(sb: Sb): Promise<HaendelseRowsResult>` — dagens `bladrFeed` (ét genforsøg pr. side, fail-closed).
  - `hentLivsdatoRaekker(sb: Sb): Promise<LivsdatoRows>` — dagens hentning *uden* `try/catch`.
  - `hentHistorieRaekker(sb: Sb): Promise<StoryRowsResult>` — dagens hentning uden at sluge fejl.
  - `hentNaevntSubjekter(sb: Sb, haendelser: HaendelseRowsResult): Promise<SubjektRow[][]>` — relation- og
    story-subjekter + hændelsesrækkerne, i dagens rækkefølge.
- De eksisterende eksporter (`hentFeedBios`, `fetchHaendelseFeed`, `fetchLivsdatoRows`, `fetchStoryRows`,
  `fetchNaevntGrundlag`) beholder signatur og adfærd (inkl. at livsdato/historier sluger fejl).
- `kilder.ts` må kun bruge `import type` fra `feedAux.ts`/`haendelser.ts`/`livsdato.ts`/`story.ts`/`feedGrundlag.ts`
  (de indlæser `../supabase`, som kaster uden `VITE_`-env). Kode, de deler, flyttes ind i `kilder.ts` og re-eksporteres
  derfra: `FEED_BIO_IN_CHUNK`, `FEED_BIO_PARALLEL`, `mapLimited`, `chunks`, `buildFeedBioSubjectIds`, `erFeedSide`,
  `MAX_SIDER`, `fetchInChunks`. `SubjektRow` eksporteres fra `kilder.ts`.

- [ ] **Step 1: Skriv fejlende tests** i `kilder.test.ts` med en lokal mock-klient (ikke `vi.mock('../../supabase')`):
  `'kilder importerer ikke den env-bundne klient'` (modulet kan importeres uden `VITE_`-env: slet dummy-env i testen
  via `vi.stubEnv` og importér), `'hentLivsdatoRaekker kaster ved fejl'`, `'hentPersonIder giver sorterede tal'`,
  `'vaelgFeedBios udelader en kanonisk person med et fejlet alias'`.
- [ ] **Step 2:** `npm run test -w web -- forside/__tests__/kilder` → FAIL (modul findes ikke).
- [ ] **Step 3:** Flyt koden; lad de gamle eksporter delegere med `supabase`.
- [ ] **Step 4:** `npm run test -w web` → PASS (inkl. de uændrede eksisterende tests).
- [ ] **Step 5: Commit** — `refactor(feed): forsidens rå hentninger tager en Supabase-klient som parameter`

### Task 3: Filen bygges og serveres med cache-regler

**Files:**
- Modify: `web/src/data/forside/format.ts` (typen)
- Create: `web/src/data/forside/byg.ts`
- Modify: `web/api/forside-data.ts` (tynd: opretter klient fra `process.env`, kalder `forsideDataSvar`)
- Test: `web/src/data/forside/__tests__/byg.test.ts`

**Interfaces:**
- Produces (`format.ts`):
  ```ts
  type Del<T> = { komplet: boolean; data: T | null };
  export type ForsideData = {
    version: typeof FORSIDE_DATA_VERSION; genereret: string; // ISO
    personIder: string[];
    bios: Del<{ kontrakt: number; rows: unknown[]; fejlede: number[] }>;
    haendelser: Del<HaendelseRowsResult>; livsdato: Del<LivsdatoRows>;
    historier: Del<StoryRowsResult>; naevnt: Del<SubjektRow[][]>;
  };
  ```
- Produces (`byg.ts`): `byggForsideData(sb: Sb, nu: Date): Promise<ForsideData>` (delene hentes parallelt med
  `Promise.allSettled`; nævnt bygger på hændelserne; en fejlet del → `{ komplet: false, data: null }`; biografier med
  `fejlede.length > 0` → `komplet: false`, `data` sat) og
  `forsideDataSvar(sb: Sb, nu: Date): Promise<{ status: number; headers: Record<string, string>; body: string }>`.
- Cache-regel (plan-afgørelse, ud over spec'en): alle dele komplette → `200` + `public, s-maxage=3600,
  stale-while-revalidate=86400`; mindst én del med `data: null` → `503` + `no-store`; ellers (fx delvise biografier) →
  `200` + `public, s-maxage=300, stale-while-revalidate=3600`, så et halvt resultat højst lever 5 min.

- [ ] **Step 1: Skriv fejlende tests** (mock-klient): `'alle dele hentet giver 200 og en times cache'`,
  `'en fejlet hændelsesbladring giver 503, no-store og nævnt ufuldstændig'`, `'delvise biografier giver 200 og fem
  minutters cache'`, `'personIder og genereret står i filen'` (`genereret === nu.toISOString()`).
- [ ] **Step 2:** `npm run test -w web -- forside/__tests__/byg` → FAIL.
- [ ] **Step 3:** Implementér `byg.ts`; skift `web/api/forside-data.ts` til at kalde `forsideDataSvar` (klient:
  `createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_ANON_KEY, { auth: { persistSession: false } })`;
  manglende env → `500` + `no-store`).
- [ ] **Step 4:** `npm run test -w web` og `npm run build -w web` → PASS / exit 0.
- [ ] **Step 5: Commit + push** (`[skip ci]`) — `feat(web): Vercel-funktion bygger forsidens data som én fil`.
- [ ] **Step 6:** På previewet: `curl -s -o /dev/null -w '%{http_code} %{time_total}\n' <preview>/api/forside-data`
  to gange → første `200` (< 60 s), andet `200` hurtigt; `curl -sI` viser `x-vercel-cache: HIT` på andet kald.
  Notér størrelsen (`content-length` komprimeret).

### Task 4: Browseren henter og validerer filen

**Files:**
- Create: `web/src/data/forside/klient.ts`
- Test: `web/src/data/forside/__tests__/klient.test.ts`

**Interfaces:**
- Produces: `hentForsideData(opts?: { url?: string; fristMs?: number; nu?: () => number; fetchFn?: typeof fetch }): Promise<ForsideData | null>`
  — standard `url = '/api/forside-data'`, `fristMs = 2000` (under forsidens 2,5 s-frist), `MAKS_ALDER_MS = 48 * 3600_000`.
  `null` ved: timeout (AbortController), ikke-2xx, ikke-JSON (fx `index.html`), forkert `version`, manglende felter,
  `genereret` ældre end 48 t eller ugyldig.

- [ ] **Step 1: Skriv fejlende tests:** `'gyldig fil returneres'`, `'langsom server: null efter fristen'` (fake
  timers), `'HTML-svar (rewrite til index.html) giver null'`, `'forkert version giver null'`, `'fil ældre end 48 timer
  giver null'`, `'503 giver null'`.
- [ ] **Step 2:** `npm run test -w web -- forside/__tests__/klient` → FAIL.
- [ ] **Step 3:** Implementér.
- [ ] **Step 4:** `npm run test -w web -- forside` → PASS.
- [ ] **Step 5: Commit** — `feat(web): forsiden henter og validerer den færdigpakkede fil`

### Task 5: Filen pakkes ud til forsidens fem kilder, og forsiden bruger den

**Files:**
- Create: `web/src/data/forside/udpak.ts`
- Modify: `web/src/components/feed/FeedStreamView.tsx` (mount-effekten)
- Test: `web/src/data/forside/__tests__/udpak.test.ts`, `web/src/components/__tests__/FeedStreamView.test.tsx`

**Interfaces:**
- Consumes: `ForsideData` (Task 3), `hentForsideData` (Task 4), `vaelgFeedBios` (Task 2), de eksisterende
  `buildHaendelserBy`, `buildLivsdatoBy` (via `livsdato.ts`' byg-del), `buildStorieBy`, `buildNaevntGrundlag`.
- Produces: `udpakForsideData(fd: ForsideData, model: { canonicalIdById: Record<string, string>; persons: { id: string; levende?: boolean }[] }): { bios: FeedBios | null; livsdatoBy: LivsdatoBy; haendelserBy: HaendelserBy; storieBy: StorieBy; naevntGrundlag: NaevntGrundlag | 'fejlet' }`.
  - `bios: null` når `fd.bios.data` er `null` (→ forsiden viser biografi-fejlbanneret som i dag).
  - `naevntGrundlag = 'fejlet'`, medmindre `bios`, `haendelser`, `historier` og `naevnt` alle er komplette **og** filen
    dækker modellen: hvert subjekt-id fra `buildFeedBioSubjectIds(canonicalIdById, ikke-levende modelpersoner)` står i
    `fd.personIder`.
  - En del med `data: null` giver tom `…By` (forsiden degraderer som i dag).

- [ ] **Step 1: Skriv fejlende tests** i `udpak.test.ts`: `'komplet og dækkende fil giver nævnt-grundlag'`,
  `'ikke-levende person uden for personIder (tilføjet efter generering): nævnt fejlet'`, `'levende person uden for
  personIder påvirker ikke dækningen'`, `'delvise biografier: nævnt fejlet, biografierne med'`,
  `'fejlede biografier: bios null'`.
- [ ] **Step 2:** `npm run test -w web -- forside/__tests__/udpak` → FAIL.
- [ ] **Step 3:** Implementér `udpak.ts`.
- [ ] **Step 4: Skriv fejlende komponenttests** i `FeedStreamView.test.tsx` (mock `../../data/forside/klient`):
  `'med fil: ingen direkte hentning, første uddeling straks med fuld data'` (`hentFeedBios`, `loadHaendelserBy` m.fl.
  kaldes ikke), `'uden fil (null): direkte hentning som i dag'`.
- [ ] **Step 5:** I mount-effekten: kald `hentForsideData()` først; får du en fil, sæt de fem tilstande fra
  `udpakForsideData` (+ `biosKomplet` = `fd.bios.komplet`); ellers kør dagens loadere uændret. Fristen
  `FEED_FOERSTE_UDDELING_FRIST_MS` startes som i dag.
- [ ] **Step 6:** `npm run test -w web` → PASS.
- [ ] **Step 7: Commit** — `feat(web): forsiden bruger den færdigpakkede fil og falder tilbage til direkte hentning`

### Task 6: Samlet verifikation, dokumentation og prod-tjek

**Files:**
- Modify: `docs/decisions.md` (beslutning 2026-11-24: forside-data som Vercel-funktion bag CDN, kun anon, cache-regler,
  48 t-grænse; *nye offentlige tabeller, forsiden læser, skal også være RLS-sikre*), `docs/changelog.md`

- [ ] **Step 1:** Hele CI-node-jobbet lokalt (samme 16 trin som i `.github/workflows/ci.yml`, + `npm run lint -w web`) →
  alle exit 0.
- [ ] **Step 2: Commit + push** (uden `[skip ci]`) — `docs: forside-data bag Vercels CDN (beslutning + changelog)`;
  opret draft-PR med `[MÅ MERGES]`-præfiks, når preview-tjekket er grønt.
- [ ] **Step 3: Preview:** forsiden indlæst 5 gange efter hinanden (sekventielt, én fane) → portræt- eller citatkort
  blandt de første seks hver gang, rækkefølgen forskellig; netværksfanen viser ét kald til `/api/forside-data` og ingen
  `public_person_bio_source_versions_v2`.
- [ ] **Step 4: Prod-log før/efter** (efter merge, via `query_logs`): antal gæstekald til
  `public_person_bio_source_versions_v2` og `public_haendelse_feed` pr. time før og efter — forventet fra hundreder til
  højst en generering pr. time.
