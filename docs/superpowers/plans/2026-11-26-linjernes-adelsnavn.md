# Linjernes adelsnavn: bogens formelle navneform — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personsiden (web + mobil) viser bogens formelle navneform — »Johan Martin greve af Reventlow« (V),
»Friedrich greve de Reventlou« (IV) — sammensat af personens fornavne og adelstitel plus en kildebundet regel på linjen.

**Architecture:** Partiklen og stavemåden følger linjen; titelordet følger personen. Linjens regel er et faktum
(`fact.subjekt_type='lineage'`, ny faktatype `adelsnavn`, værdi fx `af Reventlow`) med påstand, kilde og konklusion — som
`lineage`-kommentaren i `schema.sql` (»fact subjekt_type='lineage' → adling, … alternative navne m. evidens«) allerede
forudser. Ingen ny tabel, ingen ny cache-kolonne, ingen nye grants (anon læser allerede `fact` på `lineage` via
`entitet_offentlig`). Sammensætningen er en ren funktion i `@daa/core`, delt af web og mobil.

**Tech Stack:** PostgreSQL (schema.sql/db-migrations.sql/db-verify.sql), TypeScript (`packages/core`, vitest),
React (web, vitest), React Native/Expo (mobil, jest).

**Spec:** Afsnittet »Design« nedenfor (afgjort af projektejeren 2026-11-25/26 i chat; ingen separat spec).

## Design (afgjort)

- **Brugsform** i lister, træ, søgning og overskrift er uændret: `visning_fuldt_navn` (»Johan Martin Reventlow«) + titel-badge.
- **Formel form** = bogens form (projektejerens valg (a), 26/11), vist som én ekstra linje på personsiden:
  `{fornavne} {adelstitel med lille begyndelsesbogstav} {linjens adelsnavn}`.
- **Linjeregler i v1** (kun 2018-20-linjerne, `lineage` IV og V, fastlagt ved `(source.udgave, kode)`, aldrig id):
  - IV »Den lensgrevelige linje af 1767« → `de Reventlou`. Kilde: DAA 2018-20 s. 164, »ophøjet i lensgrevelig stand
    med navnet de Reventlou«.
  - V »Den grevelige linje af 1673« → `af Reventlow`. Kilde: bogens gennemgående form i V (fx PDF-side 206, »General
    Christian Detlef greve af Reventlows børn«). Patentets ordlyd (s. 201, »med navnet de Reventlow«) er IKKE reglen —
    den er stifterens adling og hører til en senere `navneform`.
- **Ingen formel form**, når: personen ikke har en adelstitel (`erAdelsTitel`), ingen af personens linjer har en regel,
  personens linjer har *forskellige* regler (fail-closed), eller fornavne mangler.
- **Tørkørsel mod prod 26/11 (kun læsning):** 2018-20 IV har 94 personer (93 med adelstitel), V 200 (192). Ingen
  `visning_navn` indeholder titelord, »til …« eller slægtsnavnet; kaldenavne i parentes (»Adelheid (Lilli) Margarethe«)
  er bogens egen form og bevares. Fail-closed rammer 2 med sammensat titel (415 »Grevinde (?)«, 470 »Grevinde, fyrstinde
  af Slesvig«) og 8 uden/anden titel. IV-stifteren (298) giver »Detlef lensgreve de Reventlou« = bogen. **Eneste kendte
  forkerte form: V-stifteren Conrad (392)** → »Conrad greve af Reventlow«, hvor bogen skriver »Greve Conrad de Reventlow«
  (se projektejerens afgørelse herom i PR'en).
- **Udgavernes linjekoder er byttet om:** 1939 »IV« → lineage 5 (grevelige 1673), 1939 »V« → lineage 4 (`lineage_scheme_entry_lineage`,
  `canonical`). Slå derfor aldrig en regel op på linjekoden — kun på lineage-id via den kanoniske kortlægning.
- **Udskudt (ikke i denne plan):** tyske former (V »Graf zu«, IV »Graf von«; venter på evt. tysk oversættelse), person-
  faktatypen `navneform` til undtagelser (stifterne, Criminil, Hardenberg-Reventlow, »von Reventlou«), ingifte via
  ægtefællens linje (»Margarethe lensgrevinde de Reventlou«), 1939-only-personer uden 2018-20-linje, oprydning af de 138
  navne-påstande med titelord, udtræk i prompten (kontraktfrys).

## Afvigelser under udførelsen (2026-11-26)

1. **Stifterne får ingen form** (projektejerens valg A for Conrad): `adelsnavnForLinjer(…, stifterAf)` returnerer `null`
   for linjens hoved. Grundlag: V, nr. 1 — 1673 »med navnet de Reventlow« (primogenitur), 1692-bevillingen på »af
   Reventlow« gælder sønner og descendenter (s. 202). Detlef (IV) mister dermed også sin (korrekte) form indtil `navneform`.
2. **Ingen variantklasse Reventlow/Reventlou**: søgefladens eksisterende »Mente du …?«/»Andre stavemåder« dækker
   stavemåden, og `soeg.test.ts` låser bevidst, at foldningen holder dem adskilt.
3. **Mobilen** slår linjen op via `(source_id, linjekode)` → lineage-id i core (`adelsnavnFraKoordinater`), fordi
   mobilens `linjeByPerson` nøgler på rå koder på tværs af udgaver (1939's IV/V er byttet om). Regelsammenstykningen
   er delt i core (`byggLinjeAdelsnavne`). Mobilens personside har ingen komponenttest; dækningen er core + `buildAux`.
4. V-reglens kilde er bevillingen 1692 (s. 202), ikke overskriftseksemplet på s. 206.

## Global Constraints

- Titler er aldrig en del af `person.name`/`navn`-fakta (decisions 2026-10-03); intet i denne plan skriver i `navn`.
- `visning_*` redigeres aldrig direkte (invariant 4); planen rører ikke cachen.
- Nye anon-grants kræver decisions-linje — planen tilføjer ingen; verificér det.
- Ingen `service_role` i klienter. Ingen `work_presens*/` læses.
- Commit-beskeder: Conventional Commits på dansk, ingen Claude-attribution. Én commit pr. task. Ingen push uden ja.
- Prod-rækkefølge: vocab-blok i prod → dataskript i prod (projektejerens shell) → merge af klient-PR.

## Review Focus

1. **Fornavne indeholder allerede slægtsnavnet** (»Johan Martin Reventlow« i `visning_navn`) → formel form må ikke blive
   »Johan Martin Reventlow greve af Reventlow«; slægtsnavnet fjernes med `udenSlaegtsnavnTilSidst`. Test i Task 2.
2. **Kvinder**: titlen er allerede kønsbøjet i `visning_titel` (»Komtesse«) → »Anna komtesse af Reventlow«. Test i Task 2.
3. **Samme_som-foldet person med linjer i både IV og V** (eller én med og én uden regel) → med to forskellige regler
   vises intet; én regel + linjer uden regel → reglen bruges. Test i Task 2.
4. **Ikke-adelig titel** (»Kammerherre«, »Premierløjtnant …«) → ingen formel form. Test i Task 2.
5. **Data mangler/fejler** (vocab-blokken eller dataskriptet ikke kørt, netværksfejl) → personsiden vises uændret uden
   linjen, ingen fejlbanner. Test i Task 3 (web) og Task 4 (mobil).

---

### Task 1: Faktatypen `adelsnavn` (DB)

**Files:**
- Modify: `schema.sql` (vocab-INSERT ved `fødenavn`, ~linje 6544)
- Modify: `db-migrations.sql` (ny navngiven blok sidst, efter mønstret `-- ===== fødenavn-faktatype =====`, ~42508)
- Modify: `db-verify.sql` (assert efter `fødenavn-faktatype`-asserten, ~11325)

**Interfaces:**
- Produces: vocab-række `('faktatype','adelsnavn','Adelsnavn — linjens navn efter titlen, som bogen skriver det (fx »af Reventlow«)')`.

- [ ] **Step 1: Tilføj db-verify-asserten** `OK: adelsnavn-faktatype` / `VERIFY_FAILED: adelsnavn-faktatype mangler` (kopiér fødenavn-asserten).
- [ ] **Step 2: Kør den lokalt mod frisk schema uden vocab-rækken** med samme kommandoer som CI's PostgreSQL-job i `.github/workflows/ci.yml`. Forventet: `VERIFY_FAILED: adelsnavn-faktatype mangler`.
- [ ] **Step 3: Tilføj vocab-rækken** i `schema.sql` og blokken `-- ===== adelsnavn-faktatype =====` … `-- END adelsnavn-faktatype` i `db-migrations.sql` (`ON CONFLICT (scheme, code) DO NOTHING`).
- [ ] **Step 4: Kør igen**: frisk schema + `db-migrations.sql` to gange (idempotens) + `db-verify.sql`. Forventet: `OK: adelsnavn-faktatype`, exit 0, ingen nye fejl. Kontrollér også, at verify-enheden `c1` er uændret grøn (ingen ny funktion).
- [ ] **Step 5: Commit** `feat(db): faktatype adelsnavn til linjernes navneform`

### Task 2: Sammensætning i `@daa/core`

**Files:**
- Create: `packages/core/src/adelsnavn.ts`
- Create: `packages/core/src/adelsTitler.ts` (flyt `ADELS_TITLER` + `erAdelsTitel` fra `web/src/data/presens.ts:85-91` uændret)
- Modify: `web/src/data/presens.ts` og `mobile/src/data/presens.ts` (begge har en kopi af listen; re-eksportér fra `@daa/core`, så eksisterende imports virker uændret, og `web/src/data/__tests__/adelstitler.sql-paritet.test.ts` forbliver grøn)
- Modify: `packages/core/src/navnevarianter.ts` (ny klasse `['reventlov', 'reventlou']` i `RAW_CLASSES` — lag-1-foldet form)
- Modify: `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/adelsnavn.test.ts`, udvid `packages/core/src/__tests__/navnevarianter*.test.ts`

**Interfaces:**
- Produces:
  - `export type LinjeAdelsnavne = Record<string, string>` — lineage-id (streng) → adelsnavn (»af Reventlow«).
  - `export function adelsnavnForLinjer(lineageIds: readonly string[], regler: LinjeAdelsnavne): string | null` — præcis én distinkt regel blandt linjerne → den; 0 eller ≥2 distinkte → `null`.
  - Samme form som præsenslistens `formatAnkerNavn` (`web/src/data/presens.ts:244`: navn + titel med lille + efternavn); hold dem konsistente.
  - `export function formelNavneform(input: { fornavne: string | null | undefined; titel: string | null | undefined; adelsnavn: string | null; slaegtsnavn?: string | null }): string | null` — `null` hvis et af de tre første mangler/er blankt eller titlen ikke er en adelstitel; ellers `${fornavne uden slægtsnavn til sidst} ${titel i små bogstaver} ${adelsnavn}`.
  - `export function lineageIdAfNoegle(key: string): string | null` — udtrækker lineage-id fra `lineageContextKey`-formatet (`…:lineage:<id>:…`); `null` for rå koder/tekniske nøgler.
  - `ADELS_TITLER`, `erAdelsTitel` (flyttet, uændret).

- [ ] **Step 1: Skriv de fejlende tests** (`adelsnavn.test.ts`):
  - `formelNavneform({ fornavne: 'Johan Martin', titel: 'Greve', adelsnavn: 'af Reventlow' })` → `'Johan Martin greve af Reventlow'`
  - `formelNavneform({ fornavne: 'Friedrich', titel: 'Greve', adelsnavn: 'de Reventlou' })` → `'Friedrich greve de Reventlou'`
  - `formelNavneform({ fornavne: 'Detlef', titel: 'Lensgreve', adelsnavn: 'de Reventlou' })` → `'Detlef lensgreve de Reventlou'`
  - `formelNavneform({ fornavne: 'Anna', titel: 'Komtesse', adelsnavn: 'af Reventlow' })` → `'Anna komtesse af Reventlow'`
  - `formelNavneform({ fornavne: 'Johan Martin Reventlow', titel: 'Greve', adelsnavn: 'af Reventlow', slaegtsnavn: 'Reventlow' })` → `'Johan Martin greve af Reventlow'`
  - `formelNavneform({ fornavne: 'Christian', titel: 'Kammerherre', adelsnavn: 'af Reventlow' })` → `null`
  - `formelNavneform({ fornavne: '  ', titel: 'Greve', adelsnavn: 'af Reventlow' })` → `null`; `adelsnavn: null` → `null`
  - `adelsnavnForLinjer(['5'], { '5': 'af Reventlow' })` → `'af Reventlow'`; `(['5', '7'], { '5': 'af Reventlow' })` → `'af Reventlow'`; `(['4', '5'], { '4': 'de Reventlou', '5': 'af Reventlow' })` → `null`; `([], {})` → `null`
  - `lineageIdAfNoegle('slaegt:1:lineage:5:scheme:canonical')` → `'5'`; `lineageIdAfNoegle('slaegt:1:lineage:5:scheme:3')` → `'5'`; `lineageIdAfNoegle('V')` → `null`; `lineageIdAfNoegle('legacy-source:3:V')` → `null`
  - navnevarianter: `foldToken('Reventlou') === foldToken('Reventlow')`.
- [ ] **Step 2: Kør** `npm run test -w @daa/core`. Forventet: FAIL (moduler findes ikke).
- [ ] **Step 3: Implementér** de fire funktioner, flyt titellisten, tilføj variantklassen, eksportér fra `index.ts`. Brug `udenSlaegtsnavnTilSidst` fra `slaegtsnavn.ts`.
- [ ] **Step 4: Kør** `npm run test -w @daa/core`, `npm run test -w web` (inkl. `adelstitler.sql-paritet`) og `npm test -w mobile -- presens`. Forventet: PASS.
- [ ] **Step 5: Commit** `feat(core): bogens formelle navneform ud fra linjens adelsnavn`

### Task 3: Web — hent linjereglerne og vis den formelle form

**Files:**
- Create: `web/src/data/adelsnavn.ts`
- Modify: `web/src/data/model.ts` (kald i `loadModel`'s `Promise.all`, læg resultatet på modellen; sæt `fornavne` på personen fra `visning_navn`)
- Modify: `packages/core/src/types.ts` (`AppPerson.fornavne?: string | null`; modellens `adelsnavne?: LinjeAdelsnavne`)
- Modify: `web/src/components/PersonSide.tsx` (`navneblok`, ~linje 124-128)
- Test: `web/src/data/__tests__/adelsnavn.test.ts`, udvid `web/src/components/__tests__/PersonSide.test.tsx`

**Interfaces:**
- Consumes: `formelNavneform`, `adelsnavnForLinjer`, `lineageIdAfNoegle`, `LinjeAdelsnavne` (Task 2).
- Produces: `export async function fetchLinjeAdelsnavne(): Promise<LinjeAdelsnavne>` — tre læsninger: `fact` (`subjekt_type='lineage'`, `faktatype='adelsnavn'`) → `conclusion` (`target_type='fact'`, `status='afklaret'`) → `assertion` (`valgt_assertion_id`, `vaerdi_tekst`). Fejl → `{}` + `console.warn` (som lineage-fallbacken i `model.ts:78`).

- [ ] **Step 1: Skriv fejlende tests**: (a) `fetchLinjeAdelsnavne` med mocket supabase returnerer `{ '4': 'de Reventlou', '5': 'af Reventlow' }` og ignorerer en ikke-afklaret konklusion; ved kastet fejl `{}`. (b) PersonSide: person med `fornavne 'Johan Martin'`, `title 'Greve'`, linjenøgle med lineage 5 og `adelsnavne { '5': 'af Reventlow' }` viser teksten `Johan Martin greve af Reventlow`; uden `adelsnavne` vises ingen sådan linje, og siden renderer i øvrigt som før.
- [ ] **Step 2: Kør** `npm run test -w web -- adelsnavn PersonSide`. Forventet: FAIL.
- [ ] **Step 3: Implementér.** Visning i `navneblok` under titlen, kun når `formelNavneform(...)` ≠ `null`: en synlig etiket »I Aarbogen« (samme stil som `etiketStil`) og derunder navneformen i `T.ink`, 15 px — en mini-sektion »Navne og titler«, der kan vokse, når `navneform`/tyske former kommer. Ingen `title`-attribut som eneste forklaring (usynlig på touch). Linje-id'er: `model.lineage.byPerson[focusId]` → `lineageIdAfNoegle`.
- [ ] **Step 4: Kør** `npm run test -w web` og `npm run build -w web`. Forventet: PASS / bygget. Kør e2e lokalt (CLAUDE.md-kommandoen) og notér resultatet til PR'en.
- [ ] **Step 5: Commit** `feat(web): personsiden viser bogens formelle navneform`

### Task 4: Mobil — samme visning

**Files:**
- Modify: `mobile/src/data/load.ts` (hent regler med samme tre læsninger; fejl → `{}`), `mobile/src/data/buildAux.ts` (person → lineage-id'er via `(source_id, linje)` mod `lineage`-rækkerne; sæt `fornavne`)
- Modify: `mobile/src/app/person/[id].tsx` (~linje 147, under titel-badgen)
- Test: tilsvarende jest-test under `mobile/src/**/__tests__/`

**Interfaces:**
- Kendt forskel (bemærk: 1939's koder IV/V er byttet om i forhold til 2018-20 — et kodeopslag på tværs af udgaver ville give forkert regel): web finder linjen gennem stamtavle-skemaets kanoniske kortlægning (`buildLineage`), så en 1939-person i V
  også får reglen; mobilen kender ikke `lineage_scheme*` og slår kun `(source_id, linje)` op, så 1939-only-personer får
  ingen formel form på mobil. Notér det i mobil-paritetslisten; løs det ikke her.
- Consumes: Task 2's funktioner. Data-læsningen må gerne flyttes til `packages/core` som en funktion, der tager en supabase-klient, hvis både web og mobil kan bruge den uden DOM/RN-afhængighed — ellers dupliker de 20 linjer.

- [ ] **Step 1: Fejlende jest-test**: person i V med »Greve« viser `Johan Martin greve af Reventlow`; uden regler ingen tekst.
- [ ] **Step 2: Kør** `npm test -w mobile -- adelsnavn`. Forventet: FAIL.
- [ ] **Step 3: Implementér** (`Body`, `Colors.inkMuted`, size 12, under badges).
- [ ] **Step 4: Kør** `npm test -w mobile` og mobilens `tsc --noEmit` (som CI). Forventet: PASS.
- [ ] **Step 5: Commit** `feat(mobil): personsiden viser bogens formelle navneform`

### Task 5: Dataskript, beslutning og dokumentation

**Files:**
- Create: `docs/runbooks/2026-11-26-linjernes-adelsnavn.sql`
- Modify: `docs/decisions.md` (ny sektion `## BESLUTTET: linjens adelsnavn giver bogens formelle navneform (2026-11-26)`)
- Modify: `datamodel-oversigt.md` (én linje under slægtslinjer: adelsnavn som lineage-faktum)

**Interfaces:**
- Consumes: Task 1's vocab-række (skal være i prod før skriptet køres).

- [ ] **Step 1: Skriv skriptet**: én transaktion; `set_config('request.jwt.claim.sub', :'redaktoer_uid', true)` (psql-variabel, aldrig hardkodet; se memory om jwt-claim); slå lineage-id op via `JOIN source s ON s.id=l.source_id WHERE s.udgave='DAA 2018-20' AND l.kode IN ('IV','V')` og afbryd, hvis der ikke er præcis to rækker; kald `red_upsert_fakta('lineage', <id>, 'adelsnavn', <værdi>, p_kilde_fritekst => …)` med kildeteksterne fra »Design«. Verificér PDF-sidernes trykte sidetal mod PDF'en før kildeteksten skrives. Afslut med en SELECT, der viser de to afklarede værdier. Idempotens: kør ikke `red_upsert_fakta`, hvis linjen allerede har en afklaret `adelsnavn` med samme værdi.
- [ ] **Step 2: Generalprøve** mod en lokal base med `db-migrations.sql` + en lineage-fixture (eller stand-in), kør to gange: første gang 2 fakta, anden gang 0 nye rækker.
- [ ] **Step 3: Skriv decisions-sektionen** (nævn, at reglens kilde er fritekst, fordi `red_upsert_fakta` sætter `source_id` NULL — jf. #389; design, fravalg: patentets ordlyd som regel, tysk nu, cache-kolonne; udskudte punkter fra »Design«) og datamodel-linjen.
- [ ] **Step 4: Commit** `docs(decisions): linjens adelsnavn og dataskript til IV og V`

### Efter alle tasks (projektejeren gater hvert skridt)

1. PR som draft med `[MERGE IKKE – prod-DDL først]` forrest i titel og beskrivelse.
2. Prod: kun blokken `adelsnavn-faktatype` fra `db-migrations.sql`, derefter dataskriptet i projektejerens shell; verificér som anon, at de to fakta er læsbare, og kør `get_advisors`.
3. Merge; tjek det live bundt; tilføj sektion i `docs/database-current-state.md`.
