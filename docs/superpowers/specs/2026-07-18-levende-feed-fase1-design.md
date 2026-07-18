# Levende feed — fase 1: dynamik & uendelig scroll (design-spec)

**Dato:** 2026-07-18
**Styringsgrundlag:** `docs/design/2026-07-18-levende-feed-koncept.md` §4 + §10 (fase 1).
**Mål:** feed'en møder brugeren med en ny sammensætning ved hvert besøg, kan scrolles
"uendeligt" med ægte dosering, og kører på **én delt motor** for mobil og web — alt
uden backend-ændringer (ingen skemaændringer, ingen nye RPC'er; kun nye *læsninger*
af eksisterende tabeller under eksisterende RLS).

**Beslutninger arvet fra konceptet:** ✓b (ét injiceret seed, ren motor), ✓c
(sessions-seed + dags-forankrede tidskort), ✓e (web-forside = faste indgange + feed,
delt pakke). **Konceptets åbne ○a lukkes her:** motoren bliver en **ny pakke
`@daa/feed`** (afhænger af `@daa/core`), ikke en udvidelse af core — feed'en har sin
egen aux-kontrakt og korttyper, og core forbliver ren domænekerne.

---

## 1. Baggrund & afgrænsning

I dag (empirisk): `mobile/src/data/buildFeed.ts` er en deterministisk generator
(stabil id-sort + `FEED_CAPS` + fast `interleave`-rytme) der returnerer hele listen
på én gang; footeren "Henter flere blade" er dekorativ. Web har ingen feed —
`HomeView.tsx` viser 4 `curatedFounders` + månedens gods. Webbens model indlæser
**ikke** biografier (`model.ts` sætter `bio: ''`; bio hentes pr. person i
`fetchPersonDetail`), og webbens publikumslag har **ingen** `officesBy` — det
betaler skive 5 for (§7.2–7.3).

**I scope:** motor-omskrivning (pool → score → seeded sampling → rytme) i ny delt
pakke; strøm-dosering + ægte uendelig scroll i begge apps; set-hukommelse; to nye
korttyper (`paadennedag`, `dagensperson`) + dag-præcise jubilæer via en
klientside load-udvidelse (konklusionsdatoer for fødsel/død); web-feed-MVP under
den eksisterende forside-hero.

**Ikke i scope (senere faser, jf. koncept §10):** `haendelse`/`story`/`feed_pin`-
tabellerne, `arkiv`-/`historie`-kort, redaktions-UI, LLM, push, multi-slægt.
`FeedOverride`-kroget forbliver defineret men no-op (realiseres i fase 3).
Bio-kilden er fortsat `narrative`-prosaen — citatkortets kendte kluntethed
accepteres endnu en fase (klausul-kilden kommer i fase 2).

---

## 2. Skæring (6 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | Pakken `@daa/feed` + motor-kernen | `packages/feed/src/{types,prng,pool,score,order}.ts` (+ flyt af builders/`feedHash`) | Ren funktion; vitest; ingen UI |
| 2 | Strøm-API + terminalkort | `packages/feed/src/stream.ts` | `next(a)`+`next(b)` ≡ `next(a+b)`; vitest |
| 3 | Mobil: dosering, reseed, set-hukommelse | `mobile/src/app/(tabs)/index.tsx`, `mobile/src/lib/seenCards.ts` | tsc + jest; simulator-verifikation |
| 4 | Tidslige kort + livsdato-load | `packages/feed/src/temporal.ts`, `packages/core` (delt fetch-helper) el. pr.-app loader | vitest m. injiceret dato; tolerant load |
| 5 | Web-feed-MVP | `web/src/components/feed/*`, `web/src/data/feedAux.ts`, ændret `HomeView.tsx` | vitest på adapter; Playwright-røgtest |
| 6 | Oprydning & afstemning | slet gammel `buildFeed`-sti, changelog, v3-spec-note | tsc + fuld suite grøn |

1→2 er forudsætning for 3; 4 er uafhængig af 3 (kan bygges parallelt); 5 kræver 1–2
(+4 for tidslige kort på web); 6 sidst. Hver skive holder `tsc` + eksisterende
suiter grønne.

---

## 3. Skive 1 — `@daa/feed`: pool → score → sampling → rytme

### 3.1 Pakke

`packages/feed/` spejler `packages/core`s opsætning (source-only `.ts`, egen
vitest, workspace-medlem; CI-job tilføjes som core-typecheck-mønstret fra F-16).
Afhængighed: `@daa/core` (Model-typer, `computeRelationship`). Mobil-filerne
`buildFeed.ts`/`feedHash.ts` flyttes herind; `mobile/src/data/buildFeed.ts`
erstattes af re-eksport i skive 3 og slettes i skive 6.

**Aux-kontrakten** (motoren må ikke kende mobilens fulde `Aux`):

```ts
export interface FeedAux {
  godsListe: { id: string; navn: string; slags: string; ownerCount: number }[];
  vaabenListe: { id: string; blasonering: string; note: string }[];
  officesBy: Record<string, { label: string; period: string; _y: number }[]>;
}
```

Mobilens `Aux` opfylder den strukturelt (verificeret mod `types.ts:116-129`);
web bygger en adapter (§7.2). Tomme felter (`officesBy: {}`) giver blot ingen
kort af den type — eksisterende tom-gruppe-adfærd bevares.

### 3.2 Inputs (afløser `FeedOptions`)

```ts
export interface FeedInputs {
  seed: number;               // sessions-seed — AL variation kommer herfra
  todayISO: string;           // 'YYYY-MM-DD' — driver ALLE tidslige kort (afløser today: number)
  meId: string | null;
  focusId: string | null;
  bookmarkedIds?: string[];   // kanoniske person-id'er (let personalisering)
  seenWeights?: Record<string, number>;  // kort-id → faktor 0..1 (fra set-hukommelsen, §5.3)
  livsdatoBy?: LivsdatoBy;    // §6.1 — udeladt ⇒ tidslige kort degraderer til års-niveau
  overrides?: FeedOverride[]; // fortsat no-op (fase 3)
}
```

Motoren forbliver **ren**: ingen `Math.random`/`Date.now` — seed og dato injiceres.
UI-randen må gerne bruge tilfældighed til at *vælge* seedet (§5.2).

### 3.3 Kandidat-pool

De eksisterende builders (`buildPortraitAndCitat`, `buildGods`, `buildForbundet`,
`buildEmbeder`, `buildJubilaeer`, `buildVaaben`, `buildSlaegt`) genbruges næsten
uændret, men **uden caps** — `FEED_CAPS` udgår. Poolen er alle kandidater
(~920 personer → typisk et par tusind kort). Portrait/citat-partitionen (§3.3a i
v3-spec) beholdes uændret — disjunkthed er stadig et krav.

### 3.4 Scoring (rene, forklarlige signaler)

```ts
score(card) = BASE[kind] × timeliness × personal × seen
```

- `BASE` (fase 1-værdier, én kilde til sandhed i `score.ts`): portrait 1.0,
  paadennedag 1.0, dagensperson 1.0, jubilaeum 0.9, gods 0.6, embede 0.6,
  forbundet 0.5, citat 0.4, vaaben 0.3, slaegt 0.8.
- `timeliness`: ×4 på `paadennedag`/`jubilaeum` hvis kortets mærkedag matcher
  `todayISO`s dag+måned (§6.2–6.3); ellers ×1.
- `personal`: ×1.5 hvis kortets `personId` er i `bookmarkedIds`; ×1.
- `seen`: `seenWeights[card.id] ?? 1` (0..1 — nyligt sete trækkes ned, §5.3).

Ingen anden logik i fase 1 (pin/hide og story-boost kommer i fase 3).

### 3.5 Seeded sampling + rytme-regler

`prng.ts`: **mulberry32** over seedet (32-bit, ren, veldokumenteret; `stableHash`
fra `feedHash.ts` genbruges til at aflede del-seeds). `order.ts`:

1. **Vægtet trækning uden tilbagelægning** fra poolen (vægt = score).
2. **Rytme-begrænsninger** håndhæves under trækningen (afvis-og-træk-igen, maks.
   20 forsøg pr. slot, derefter lempes i rækkefølge — determinismen bevares fordi
   forsøgene selv er seed-drevne):
   - R1: aldrig to kort af samme `kind` i træk.
   - R2: samme `personId` med mindst 8 korts mellemrum.
   - R3: mindst ét portræt-kort pr. 6 kort (feed'ens "hovedret").
3. **`dagensperson` låses til position 0–2** (dagens fremhævning skal mødes uden
   scroll); `slaegt`-kortet (maks. 1, som i dag) placeres i første 10.
4. Terminalkortet (`samle`, uændret semantik) lægges altid sidst.

**Implementeringsvalg (bevidst):** hele ordningen beregnes **én gang pr. seed**
(eager) — poolen er få tusind kort, og trækningen er O(n·forsøg); mål: <50 ms på
en ældre telefon (verificeres i skive 3; overskrides det, flyttes trækningen til
inkrementel beregning bag samme API uden kontraktændring). "Uendelig scroll" er
dermed **dosering af en færdig ordning**, ikke løbende genberegning — enklest,
robust, og `next`-stabiliteten (§4) følger gratis.

### 3.6 Test (vitest, `packages/feed/src/__tests__/`)

- Determinisme: samme (model, aux, inputs) → dybt identisk ordning, to kald.
- Seed-effekt: to forskellige seeds → forskellig ordning (og samme kort-mængde).
- Rytme: R1–R3 holder på tæt fixture; lempelse aktiveres målbart på degenereret
  fixture (fx kun én kind) uden crash/uendelig løkke.
- Vægt-effekt: `seenWeights: {id: 0}` → kortet sidst/aldrig blandt første N;
  bookmarked person rykker frem statistisk over mange seeds (property-agtig test
  med fast seed-liste, ikke ægte tilfældighed).
- Portrait/citat-disjunkthed + tom model → `[]` (arves fra v3-suiten, porteres).
- `FeedAux` med tomme felter → ingen kort af typen, ingen crash.

---

## 4. Skive 2 — strøm-API

```ts
export interface FeedStream {
  next(n: number): FeedCard[];  // næste n kort (færre ved slut; [] når udtømt)
  done(): boolean;
  total(): number;              // til badge/telemetri; terminalkort inkluderet
}
export function createFeedStream(model: Model, aux: FeedAux, inputs: FeedInputs): FeedStream;
```

- Tynd wrapper om den eagre ordning (§3.5): intern cursor, `next` returnerer en
  slice. **Kontrakt-invariant:** `next(a)` efterfulgt af `next(b)` giver præcis de
  samme kort som ét `next(a+b)` — testet eksplicit.
- `buildFeedOrder(model, aux, inputs): FeedCard[]` eksporteres også (test +
  ikke-strømmede aftagere, fx fremtidens "Ugens brev").
- Terminalkortet er sidste element; `done()` er sandt når cursor er forbi det.

Test: stabilitet (`next(5)`+`next(5)` ≡ `next(10)`), udtømning (`[]` efter slut,
`done()` sand), `total()` = ordningens længde.

---

## 5. Skive 3 — mobil-integration

### 5.1 Dosering i `index.tsx`

- `createFeedStream` memoiseres på (model, aux, seed, dagsdato, meId, focusId,
  bookmarks, seenWeights). Lokal state holder de viste kort; init = `next(12)`.
- `FlatList.onEndReached` (threshold ~0.6) → `next(12)` appendes. Footeren
  "Henter flere blade fra slægten" bliver **ægte tilstand**: spinner-variant mens
  en append er undervejs, og en afsluttende variant ("Du har mødt hele slægten i
  dag — udforsk registeret") når `done()` — dekorationslinjen fjernes.

### 5.2 Seed & genopfriskning

- Seed vælges ved mount: `stableHash(todayISO + ':' + nonce)` hvor `nonce` er én
  tilfældig streng pr. mount (UI-randen — motoren forbliver ren).
- **Pull-to-refresh** (`RefreshControl`) → ny nonce → ny strøm fra toppen.
  Dagsdatoen (`todayISO`) hentes ét injicerbart sted (afløser `CURRENT_YEAR`).

### 5.3 Set-hukommelse (`mobile/src/lib/seenCards.ts`)

- AsyncStorage-nøgle `daa_feed_seen`: `{ [cardId]: epochDays }`, LRU-cappet til
  300 poster. Skrivninger batches (debounce) og fejl sluges (ikke-kritisk,
  samme princip som bogmærke-lageret).
- Registrering via `FlatList.onViewableItemsChanged` (≥60 % synligt) — ikke ved
  append (et kort under folden er ikke "set").
- `seenWeights`-afledning (ren, testet): set for <3 dage siden → 0.25; <7 → 0.5;
  <14 → 0.75; ældre → udeladt (1.0). Læses ÉN gang ved mount og fryses for
  strømmens levetid (determinisme inden for sessionen).
- Terminal-/`slaegt`-/`dagensperson`-kort registreres ikke (positionslåste).

### 5.4 Test

Jest: seen-lager (LRU, decay-afledning, batching, fejl-tolerance — spejl af
bogmærke-suitens async/race-cases). Dosering/`onEndReached`: primært tsc +
iOS-simulator mod prod-data (projektets etablerede mønster); dokumentér hvad der
er testet vs. simulator-verificeret.

---

## 6. Skive 4 — tidslige kort + livsdato-load

### 6.1 Load-udvidelse: konklusionsdatoer for fødsel/død

`person.visning_foedt/doed` er **rå datotekst** (`coalesce(date_raw, vaerdi_tekst)`
i `regen_person_visning`, schema.sql) — uegnet til dag-præcision. I stedet hentes
de valgte assertions' strukturerede datoer (3 små queries, JS-join — samme mønster
som `fetchParentsUnknownRows` i `web/src/data/model.ts`; polymorfe koblinger kan
ikke FK-joines i PostgREST):

1. `fact`: `id,subjekt_id,faktatype` hvor `subjekt_type='person'`,
   `faktatype in ('fødsel','død')`, `.order('id')`.
2. `conclusion`: `target_id,valgt_assertion_id` hvor `target_type='fact'`,
   `.in('target_id', factIds)`.
3. `assertion`: `id,date_min,date_max,date_qualifier` `.in('id', valgte)`.

→ `LivsdatoBy = Record<personId, { foedt?: FuzzyDato; doed?: FuzzyDato }>` med
`FuzzyDato = { min: string|null; max: string|null; qualifier: string|null }`.
Person-id'er kanoniseres via `canonicalIdById`. **Tolerant:** enhver fejl →
`{}` + `console.warn` (tidslige kort degraderer til års-niveau — feed'en
brydes aldrig). Loaderen deles mellem apps (helper i `@daa/core` ved siden af
`buildParentsUnknown`-mønstret eller i `@daa/feed` — implementørens valg, men ét
sted). RLS: læser kun rækker publikums-tieren allerede må se; volumen ≈ 2 fakta
× ~920 personer — ubetydelig.

### 6.2 `paadennedag`-kort (`temporal.ts`)

```ts
{ kind: 'paadennedag'; id: `paadennedag:${personId}:${faktatype}:${aar}`;
  personId: string; name: string; aarstal: number; hvad: 'født' | 'død';
  praecision: 'dag' | 'maaned'; kicker: 'På denne dag' | 'I denne måned' }
```

- Kandidat når `date_qualifier='exact'`, `date_min` har dag+måned == `todayISO`s
  (år ignoreres). **Fallback:** giver dagen 0 træf, medtages måneds-træf
  (`praecision:'maaned'`, kicker "I denne måned") — aldrig fabrikeret præcision:
  kortteksten siger kun det, datoen bærer.
- Bogmærkbar (har `personId`); tap → `/person/[id]`. `timeliness`-boost §3.4.

### 6.3 `dagensperson`-kort + dag-præcise jubilæer

- `dagensperson`: `hash(todayISO) % N` over den stabilt sorterede bio-population
  → én person pr. dag, ens for alle brugere. Kort = portræt-varianten med kicker
  "Dagens person"; personen udelades samtidig af den almindelige
  portræt-/citat-pool for dagen (ingen dublet; disjunkthedstesten udvides).
- `jubilaeum`: uændret års-regel (`≥100 && % 50`), men når `livsdatoBy` har en
  eksakt dato hvis dag+måned == i dag, opgraderes teksten ("i dag for 300 år
  siden — på dagen") og `timeliness`-boostet udløses.

### 6.4 Test

Vitest med injiceret `todayISO` + fixture-`livsdatoBy`: dag-match, måneds-
fallback, qualifier≠exact ⇒ aldrig dag-kort, tom `livsdatoBy` ⇒ ingen tidslige
kort men intakt feed, dagensperson-determinisme pr. dato + disjunkthed mod
portræt/citat-poolen. Load-helperen: JS-join + kanonisering + tolerance (mockede
queries).

---

## 7. Skive 5 — web-feed-MVP

### 7.1 Placering & udseende

`HomeView.tsx` beholder søge-hero + "Redaktionen foreslår" øverst (koncept ✓e /
web-koncept §6). Derunder monteres `FeedStreamView` (ny, `web/src/components/feed/`):
én kolonne, maks-bredde ~680 px, centreret; kort-views i webbens idiom
(`theme.ts`-tokens, `primitives.tsx` — **ingen nye farver/fonte**). Uendelig
scroll via én `IntersectionObserver`-sentinel nederst → `next(12)`. Slut-tilstand
som mobil (§5.1). Bogmærke-toggle på person-kort genbruger `data/bookmarks.ts`
(localStorage, person-kun — kontrakten matcher allerede `bookmarkPersonId`).

### 7.2 Web-aux-adapter (`web/src/data/feedAux.ts`)

```ts
buildWebFeedAux(estates: EstateItem[], arms: ArmsItem[]): FeedAux
// godsListe ← fetchEstates()-resultatet (samme felter), vaabenListe ← fetchArms(),
// officesBy: {}  ← web-publikum indlæser ikke embeder pr. person ⇒ ingen embede-kort i MVP
```

`fetchEstates`/`fetchArms` kaldes ved feed-mount (cachet i view-state).
Embede-kort på web er en bevidst udeladelse — noteres i changelog; kommer
gratis når fase 2 alligevel rører webbens load.

### 7.3 Bio-strategi på web (portræt/citat/dagensperson kræver bio)

Webbens model har `bio: ''`. **Valg:** ved feed-mount hentes person-narrativer i
ÉN pagineret, tolerant query (`narrative`: `subjekt_id,source_id,tekst` hvor
`subjekt_type='person'` — RLS filtrerer allerede privat/levende), flettes med
`pickPreferredBio` (findes i `@daa/core`) og stemples ind i en **kopi** af
`model.persons` til feed-brug (modellen i øvrigt røres ikke). Indtil svaret er
landet, bygges strømmen uden bio-population (gods/våben/forbundet/tidslige kort
vises straks); når bios lander, genbygges strømmen med samme seed — kortene
*føjes til* poolen deterministisk.
**Målepunkt + fallback (accepteret risiko):** payload måles; overstiger den
~2,5 MB overgås til chunket hentning (`.in('subjekt_id', …)` for det seed-ordnede
præfiks af bio-kandidater, fx 200 ad gangen) bag samme adapter — kontrakten mod
motoren ændres ikke.

### 7.4 Test

Vitest: `buildWebFeedAux` (mapping + tomme input), bio-fletning m.
`pickPreferredBio` (flere udgaver → foretrukken), strøm-genbyg ved bio-ankomst
(samme seed → superset-ordning uden dubletter). Playwright-røgtest: forsiden
viser hero + mindst 5 feed-kort, scroll udløser append, ingen konsol-fejl.

---

## 8. Skive 6 — oprydning & afstemning

- `mobile/src/data/buildFeed.ts`/`feedHash.ts` slettes (imports peger på
  `@daa/feed`); v3-testene er porteret/afløst i pakken; ingen dublet-kilde.
- `FEED_CAPS` og `interleave` udgår af det offentlige API (interleave kan
  overleve internt hvis lempelses-fallbacken §3.5 bruger den).
- Notér i toppen af v3-spec'en (2026-07-05) at §3 (feed-datamodellen) er afløst
  af denne spec — v3-spec'ens skive 2–4 (UI/drawer/bogmærker) er fortsat gældende
  historik. Changelog-post + `docs/README.md` er allerede dækket af
  koncept-indekseringen; tilføj status-linje ved implementeringens afslutning.

---

## 9. Risici & modforanstaltninger

- **Eager ordning for dyr på gammel telefon** → målt budget (<50 ms, §3.5);
  eskalering: inkrementel trækning bag uændret API.
- **Rytme-lempelse skaber synlige mønstre** på tynd data → lempelses-rækkefølgen
  er fast og testet; værste fald = v3-lignende monotoni, aldrig crash/løkke.
- **Web-bio-payload** → målepunkt + chunket fallback (§7.3).
- **Strøm-genbyg ved bio-ankomst blinker** → genbyg bevarer allerede viste korts
  præfiks (append-only kontrakt testes, §7.4).
- **`onViewableItemsChanged`-støj** (hurtig scroll markerer alt som set) →
  ≥60 %-synlighed + minimum-visningstid (500 ms) i viewability-config.
- **Dublet dagensperson/portræt** → disjunkthed testes eksplicit (§6.4).
- **Livsdato-queries mod ældre baser** → tolerant catch → års-degradering (§6.1).

## 10. Succeskriterier

- To app-åbninger samme dag giver forskellig kort-rækkefølge; samme seed i test
  giver identisk ordning (determinisme bevist i vitest).
- Scroll henter reelt flere kort (mobil + web); slut-tilstanden er ærlig; footeren
  er aldrig ren dekoration.
- "På denne dag"/"Dagens person" skifter med dagsdatoen (testet med injiceret
  dato) og degraderer pænt uden livsdato-data.
- Web-forsiden viser hero + feed fra samme motor som mobil; `@daa/feed` har egen
  grøn vitest-suite + CI-job; `tsc` + jest (mobil) + vitest (web/core/feed) grønne.
- Ingen backend-ændringer: intet nyt skema, ingen nye RPC'er, kun eksisterende
  tabeller/RLS læst.
