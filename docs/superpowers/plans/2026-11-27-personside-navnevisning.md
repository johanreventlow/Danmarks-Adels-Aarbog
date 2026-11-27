# Navnevisning og skilsmisse — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personsiden får én statuslinje (»Kammerherre, greve af Reventlow« / »Komtesse, gift lensgrevinde af
Reventlow«), stamtræet viser personens egen titel, Fakta siger »Fornavne«, og skilsmisser vises overalt, hvor
ægteskabet vises — plus to prod-runbooks (køn for ingifte, skilsmissedatoer).

**Architecture:** Al logik er rene funktioner i `packages/core` (delt af web og mobil). Skilsmisserne hentes én gang
i modellen som `Model.skilsmisser` (som `adelsnavne`); `null`/`undefined` betyder ukendt og er fail-closed for
gift-visning. Ingen DDL, ingen nye grants; prod-data skrives via redaktørens RPC'er i to runbooks.

**Tech Stack:** TypeScript (vitest i core/web, jest i mobil), React/Vite, Expo, PostgreSQL/psql, Supabase MCP.

**Spec:** `docs/superpowers/specs/2026-11-27-personside-navnevisning-design.md`

## Global Constraints

- Statuslinjens rækkefølge: `[hof-/rangtitel], [egen adelstitel][ adelsnavn][, gift <feminin mandstitel> <mandens adelsnavn>]`; første bogstav stort, resten som i bogen.
- »gift«, ikke »ved ægteskab«; intet »·« i statuslinjen.
- Titlen følger navnet: stamtræets kort viser kun personens egen titel; ægteskabets titel kun i statuslinjens gift-del.
- Hof-/rangtitel kun for `koen === 'mand'` i denne leverance.
- Aldrig en titel, personen ikke havde; ved tvivl vises mindre (fail-closed).
- Skilsmisse-tekst: personside `skilt 12. okt. 1901`, træ `skilt`, præsensliste `skilt 1901`; uden dato `skilt`.
- Ingen DDL, ingen nye anon-grants. Prod-skrivning kun efter projektejerens ja, med backup, prøvekørsel og anon-tjek.
- Datoer, navne og aktør-uuid vises aldrig i chat eller repo fra runbookene; output er antal og person-/familie-id'er.
- Ingen model læser biografier om levende (runbook 2 er ren SQL).
- Commits: Conventional Commits på dansk, ingen Claude-attribution, ingen Claude-Session-linje.

## Review Focus

1. Et skilt par, der efter samme_som-sammenfoldning står i to familier (fx 1939 og 2018-20), hvor kun den ene har
   skilsmissen — parret skal stadig vises som skilt (test i Task 1).
2. Skilsmisse-opslaget fejler (`skilsmisser === null`) — en skilt kvinde må ikke få gift-del eller overtaget
   ægtefælle-titel i præsenslisten (tests i Task 3 og Task 5).
3. Et embede, hvis etiket er »Kammerherre · Hoffet« — algoritmen skal læse den rå rolle, ikke etiketten (test i Task 2).
4. En ingift kvinde gift to gange, med en greve og en lensgreve, ingen skilsmisse — lensgrevinde vinder (test i Task 3).
5. Lineage-stifteren af en linje med adelsnavn-regel — ingen partikel (personensAdelsnavn giver null), statuslinjen er
   »Greve« alene (test i Task 3).

---

### Task 1: Skilsmisse-indeks i kernen

**Files:**
- Create: `packages/core/src/skilsmisse.ts`
- Modify: `packages/core/src/types.ts` (Model), `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/skilsmisse.test.ts`

**Interfaces:**
- Produces:
  - `type Skilsmisse = { dateMin: string | null; dateMax: string | null }`
  - `type Skilsmisser = Record<string, Skilsmisse>` (nøgle: family-id uden »f«)
  - `Model.skilsmisser?: Skilsmisser | null` (undefined = ikke hentet, null = opslag fejlede; begge = ukendt)
  - `byggSkilsmisser(facts: {id,subjekt_id}[], konkl: {target_id,valgt_assertion_id}[], assertions: {id,date_min,date_max}[]): Skilsmisser`
  - `parSkilsmisse(model: Model, a: string, b: string): Skilsmisse | null | undefined` — Skilsmisse = skilt; null = ikke skilt; undefined = ukendt. Kigger på alle unioner i `model.indexes.unionById` med parret {a, b}.
  - `fmtSkilt(s: Skilsmisse, form: 'dag' | 'aar' | 'ord'): string`

- [ ] **Step 1: Write the failing tests**

```ts
it('byggSkilsmisser nøgler på familie-id og bærer datoerne', () => {
  expect(byggSkilsmisser([{ id: 9, subjekt_id: 350 }], [{ target_id: 9, valgt_assertion_id: 4 }],
    [{ id: 4, date_min: '1901-10-12', date_max: '1901-10-12' }])).toEqual({ '350': { dateMin: '1901-10-12', dateMax: '1901-10-12' } });
});
it('fmtSkilt: dag, år og ord', () => {
  const s = { dateMin: '1901-10-12', dateMax: '1901-10-12' };
  expect(fmtSkilt(s, 'dag')).toBe('skilt 12. okt. 1901');
  expect(fmtSkilt(s, 'aar')).toBe('skilt 1901');
  expect(fmtSkilt(s, 'ord')).toBe('skilt');
  expect(fmtSkilt({ dateMin: '1901-01-01', dateMax: '1901-12-31' }, 'dag')).toBe('skilt 1901');
  expect(fmtSkilt({ dateMin: null, dateMax: null }, 'dag')).toBe('skilt');
});
it('parSkilsmisse: skilt hvis bare én af parrets familier har skilsmissen (samme_som-kopi)', () => {
  // model med unionerne f350 (a,b) og f351 (a,b); skilsmisser = { '350': … }
  expect(parSkilsmisse(model, 'a', 'b')).toEqual({ dateMin: null, dateMax: null });
});
it('parSkilsmisse: null når ingen familie er skilt; undefined når skilsmisser er null eller mangler', () => { /* … */ });
```

- [ ] **Step 2:** `npm run test -w @daa/core -- skilsmisse` → FAIL (modul findes ikke).
- [ ] **Step 3:** Implementér i `skilsmisse.ts`; `fmtSkilt` bruger `fmtDagDato` fra `vielse.ts` (dag når dateMin === dateMax, år når samme år, ellers kun `skilt`). Tilføj `skilsmisser?` til `Model` og eksportér fra `index.ts`.
- [ ] **Step 4:** `npm run test -w @daa/core -- skilsmisse` → PASS.
- [ ] **Step 5:** Commit `feat(core): skilsmisse-indeks med fail-closed ukendt-tilstand`.

### Task 2: Titelalgoritmen

**Files:**
- Create: `packages/core/src/titelAlgoritme.ts`
- Test: `packages/core/src/__tests__/titelAlgoritme.test.ts`

**Interfaces:**
- Produces: `normTitel(v: string): string`, `hofTitel(vaerdier: readonly string[]): string | null` (returnerer ordet med lille begyndelsesbogstav, fx `'kammerherre'`).

- [ ] **Step 1: Write the failing tests**

```ts
it('normTitel skræller præfiks, parentes, komma og stedled', () => {
  expect(normTitel('Karakt. Etatsraad')).toBe('etatsråd'); // 1939-stavning »aa« → »å«
  expect(normTitel('Amtmand over Sorø Amt')).toBe('amtmand');
  expect(normTitel('kammerherre (1801)')).toBe('kammerherre');
  expect(normTitel('Hofjægermester, Ritmester')).toBe('hofjægermester');
});
it('hofTitel: højeste trin pr. stige, så rangfølgen', () => {
  expect(hofTitel(['kammerjunker', 'kammerherre', 'major'])).toBe('kammerherre');
  expect(hofTitel(['oberst', 'generalmajor'])).toBe('generalmajor');
  expect(hofTitel(['etatsråd', 'amtmand'])).toBe('amtmand');
});
it('hofTitel: adelstitler, ordener og ukendte ord giver null', () => {
  expect(hofTitel(['greve', 'hvid ridder', 'godsejer'])).toBeNull();
});
it('hofTitel: en embedsetiket »rolle · org« er ikke input — kun rollen', () => {
  expect(hofTitel(['Kammerherre · Hoffet'])).toBeNull(); // dokumenterer kontrakten: kalderen giver rollen
  expect(hofTitel(['Kammerherre'])).toBe('kammerherre');
});
```

- [ ] **Step 2:** Kør → FAIL.
- [ ] **Step 3:** Implementér efter spec'ens afsnit »Titelalgoritmen« (normalisering, frasortering, de fire stiger, rangfølgen som tilladt liste). `normTitel` oversætter `aa` → `å` (1939-stavning) før opslag, så `Etatsraad` → `etatsråd`. Kilden er målescriptet `maal_titulatur.py` (`norm`, `STIGER`, `PRIO`), men listen er spec'ens.
- [ ] **Step 4:** Kør → PASS.
- [ ] **Step 5:** Commit `feat(core): titelalgoritme for hof- og rangtitel`.

### Task 3: Statuslinje, egen titel og træets titelord

**Files:**
- Create: `packages/core/src/statuslinje.ts`
- Modify: `packages/core/src/adelsTitler.ts` (flyt `feminiserTitel` hertil + `ADELS_RANG`), `web/src/data/presens.ts` og `mobile/src/data/presens.ts` (re-eksportér `feminiserTitel` fra `@daa/core`), `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/statuslinje.test.ts`

**Interfaces:**
- Consumes: `parSkilsmisse` (Task 1), `hofTitel` (Task 2), `personensAdelsnavn`, `erAdelsTitel`.
- Produces:
  - `feminiserTitel(mandsTitel: string): string | null` (nu i core)
  - `egenAdelstitel(model: Model, id: string): string | null` — `title` hvis adelstitel, men for kvinder ikke hvis den er lig `feminiserTitel` af en ægtefælles titel.
  - `traeTitel(model: Model, id: string): string | null` — `egenAdelstitel` med stort begyndelsesbogstav.
  - `byggStatuslinje(model: Model, id: string, hofKilder: readonly string[] | null): string | null` — `hofKilder` = rå titel-fakta + embedsroller; `null` = detaljer ikke hentet (ingen hof-del).

- [ ] **Step 1: Write the failing tests** — én test pr. række i spec'ens tabel »Statuslinjen — regel« plus Review Focus 2, 4, 5:

```ts
expect(byggStatuslinje(m, 'v44', ['Kammerherre'])).toBe('Kammerherre, greve af Reventlow');
expect(byggStatuslinje(m, 'iv1', [])).toBe('Greve de Reventlou');
expect(byggStatuslinje(m, 'datter', null)).toBe('Komtesse af Reventlow');
expect(byggStatuslinje(m, 'friherre', null)).toBe('Friherre');          // linje uden regel
expect(byggStatuslinje(m, 'utitlet', ['Kammerherre'])).toBe('Kammerherre');
expect(byggStatuslinje(m, 'beke', ['dekanesse'])).toBe('Komtesse, gift lensgrevinde af Reventlow'); // ingen hof for kvinder
expect(byggStatuslinje(m, 'ingiftUdenTitel', null)).toBe('Gift grevinde de Reventlou');
expect(byggStatuslinje(m, 'komtesseGiftBorgerlig', null)).toBe('Komtesse');
expect(byggStatuslinje(m, 'ingen', [])).toBeNull();
// Review Focus 2: skilt → ingen gift-del; ukendt (skilsmisser null) → ingen gift-del
expect(byggStatuslinje(mSkilt, 'beke', null)).toBe('Komtesse');
expect(byggStatuslinje({ ...m, skilsmisser: null }, 'beke', null)).toBe('Komtesse');
// Review Focus 4: greve + lensgreve → lensgrevinde
expect(byggStatuslinje(mToMaend, 'k', null)).toBe('Gift lensgrevinde af Reventlow');
// Review Focus 5: linjens stifter → ingen partikel
expect(byggStatuslinje(m, 'stifter', null)).toBe('Greve');
// Titlen følger navnet
expect(traeTitel(m, 'beke')).toBe('Komtesse');
expect(egenAdelstitel(mGrevindeSomEgen, 'k')).toBeNull(); // »grevinde« = mandens greve feminiseret → ægteskabstitel
```

Fixtures: byg `Model` med `lineage` (V med regel »af Reventlow«, IV med »de Reventlou«, en friherre-linje uden regel), `adelsnavne`, `slaegtsnavn: 'Reventlow'`, `unionById`/`spousesBy`, `skilsmisser: {}`; følg mønstret i `adelsnavn.test.ts`.

- [ ] **Step 2:** Kør → FAIL.
- [ ] **Step 3:** Implementér. Rang (`ADELS_RANG` i `adelsTitler.ts`): komtesse = comtesse < friherreinde = baronesse < grevinde < lensgrevinde < rigsgrevinde; friherre = baron < greve < lensgreve < rigsgreve. Gift-delen: kun `koen === 'kvinde'`; spring ægtefæller over, hvor `parSkilsmisse` ikke er `null`; mandens navn = `personensAdelsnavn(mand)` ?? (`model.slaegtsnavn` hvis manden har en ikke-teknisk linje) — ellers ingen gift-del. Adelsdelen bruger `personensAdelsnavn(id)`.
- [ ] **Step 4:** Kør → PASS; `npm run test -w @daa/core` grøn (også `paritet.test.ts` og SQL-paritetstesten for `ADELS_TITLER`).
- [ ] **Step 5:** Commit `feat(core): statuslinje og egen titel (titlen følger navnet)`.

### Task 4: Kernens visninger — Fornavne, træ og præsensliste

**Files:**
- Modify: `packages/core/src/faktaVisning.ts:7`, `packages/core/src/fokusTrae.ts`, `packages/core/src/presensListe.ts`
- Test: `packages/core/src/__tests__/fokusTrae.test.ts`, `presensListe.test.ts`, `faktaVisning`-testen (findes den ikke, i `personFacts.test.ts`)

**Interfaces:**
- Consumes: `parSkilsmisse` (Task 1).
- Produces: `FokusAegteskab.skilt: boolean`; `PresensPartner.skilsmisse: Skilsmisse | null` (kun sat, når parret er skilt).

- [ ] **Step 1: Failing tests**
  - `faktaTypeNavn('navn')` (eller labelopslaget i `faktaVisning.ts`) → `'Fornavne'`.
  - `byggFokusRaekker(mSkilt, fokus).aegteskaber[0].skilt === true`; uden skilsmisse `false`; med `skilsmisser: null` `false`.
  - præsensliste: partneren får `skilsmisse`; en levende skilt ægtefælle til en afdød blodforfader står **ikke** i enke-gruppen; en afdød blodperson uden børn, hvis eneste levende partner er skilt, giver ingen node (`efterlevendePartner` falsk).
- [ ] **Step 2:** Kør → FAIL.
- [ ] **Step 3:** Implementér. Ukendt skilsmisse (`undefined`) ændrer intet i træ og præsensliste (vises som i dag) — *planens beslutning; kun statuslinjen og præsenslistens navne-overtagelse er fail-closed*.
- [ ] **Step 4:** `npm run test -w @daa/core` → PASS.
- [ ] **Step 5:** Commit `feat(core): Fornavne, skilt i træ og præsensliste`.

### Task 5: Web — data

**Files:**
- Create: `web/src/data/skilsmisser.ts`
- Modify: `web/src/data/model.ts` (hent parallelt som `adelsnavneP`, sæt `skilsmisser`), `web/src/data/public.ts:171,393` (`PersonOffice.rolle`), `web/src/data/presens.ts` (`fetchAegtefaelleIdById` springer skilte familier over; `null` → tom map)
- Test: `web/src/data/__tests__/skilsmisser.fetch.test.ts`, `presens.fetch.test.ts`

**Interfaces:**
- Produces: `fetchSkilsmisser(): Promise<Skilsmisser | null>` (null ved enhver fejl); `PersonOffice = { label; period; rolle: string | null }`; `fetchPresensNavneDele(ids: string[], skilteFamilier: ReadonlySet<string> | null)`.

- [ ] **Step 1: Failing tests** — mock supabase som `adelsnavn.fetch.test.ts`: tre læsninger → indeks; kast i andet kald → `null`. Præsens: en kvinde gift med lensgreve i en skilt familie får ikke `tilgiftet`; med `skilteFamilier = null` heller ikke.
- [ ] **Step 2:** `npm run test -w web -- skilsmisser presens` → FAIL.
- [ ] **Step 3:** Implementér (fact `subjekt_type='family'`, `faktatype='skilsmisse'` → conclusion `status='afklaret'` → assertion `id,date_min,date_max`; `byggSkilsmisser`). Kalderen af `fetchPresensNavneDele` giver `new Set(Object.keys(model.skilsmisser))` eller `null`.
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(web): hent skilsmisser i modellen og respekter dem i præsenslistens navne`.

### Task 6: Web — visning

**Files:**
- Modify: `web/src/components/PersonSide.tsx:110-138,252-260`, `web/src/components/FokusTrae.tsx:61,159-164`, `web/src/components/PresensView.tsx:120-126`
- Test: `web/src/components/__tests__/PersonSide.test.tsx`, FokusTrae-/PresensView-testene

- [ ] **Step 1: Failing tests**
  - PersonSide: statuslinjen står under H1 med teksten fra `byggStatuslinje`; »I Aarbogen« findes ikke længere; den gamle titellinje er væk (titlen står kun i statuslinjen); ægtefællen viser `⚭ 3. maj 1890, skilt 12. okt. 1901`.
  - FokusTrae: fokuskortet viser `traeTitel` (Beke-fixture → »Komtesse«); rækken »Gift« viser `⚭ X, skilt`.
  - PresensView: `· g. m. X, skilt 1901`.
- [ ] **Step 2:** `npm run test -w web` → de nye FAIL.
- [ ] **Step 3:** Implementér. Statuslinjen genbruger den bordeaux titellinjes stil; `hofKilder` = `detail.faktaInput.rows` med `faktatype === 'titel'` og `chosen` → `vaerdi_tekst`, plus `detail.offices.map(o => o.rolle)`; før detaljerne er hentet: `null`. Skilt-teksten sættes efter `vielse` i `PersonLink` (eller som eget prop).
- [ ] **Step 4:** `npm run test -w web` og `npm run build -w web` grønne.
- [ ] **Step 5:** Commit `feat(web): statuslinje, træets egen titel og skilsmisse på personside, træ og præsensliste`.

### Task 7: Mobil — paritet

**Files:**
- Create: `mobile/src/data/skilsmisser.ts`
- Modify: `mobile/src/data/load.ts:461,534`, `mobile/src/data/udgaveLag.ts:13`, `mobile/src/data/types.ts:129` + `buildAux.ts:106` (`OfficeRef.rolle`), `mobile/src/data/presens.ts`, `mobile/src/app/person/[id].tsx:142-218,296-305`, `mobile/src/app/(tabs)/tree.tsx:111,441,527`, `mobile/src/app/praesens.tsx:85-92`
- Test: tilsvarende jest-tests i `mobile/src/data/__tests__/`

- [ ] **Step 1:** Failing tests: `fetchSkilsmisser(sb)` (indeks / `null` ved fejl), `buildAux` giver `rolle`, præsensnavne springer skilte over.
- [ ] **Step 2:** `npm test -w mobile` → FAIL.
- [ ] **Step 3:** Implementér som Task 5-6 (samme kernefunktioner; »I Aarbogen«-Kicker fjernes; træets titel = `traeTitel`).
- [ ] **Step 4:** `npm test -w mobile` og `npx tsc --noEmit -p mobile` grønne; `paritet.test.ts` i core grøn (nyt databasekald i begge apps).
- [ ] **Step 5:** Commit `feat(mobile): statuslinje, træets titel og skilsmisse (paritet)`.

### Task 8: Beslutning, verifikation og PR

**Files:**
- Modify: `docs/decisions.md` (ny post »BESLUTTET: personsidens statuslinje, titlen følger navnet og skilsmisse vises (2026-11-27)«: regler, fail-closed, kun mænds hof-titel, kvinder i #424), `datamodel-oversigt.md` (én linje: `Model.skilsmisser`, ingen skemaændring)

- [ ] **Step 1:** Skriv beslutningsposten og linjen.
- [ ] **Step 2:** Hele CI-node-jobbet lokalt: `npm ci && npm run test -w @daa/core && npm run test -w @daa/feed && npm run test -w web && npm test -w mobile && npx tsc --noEmit -p mobile` → alle grønne (exit 0).
- [ ] **Step 3:** e2e lokalt: `PLAYWRIGHT_PORT=5293 VITE_SUPABASE_URL=https://e2e.invalid VITE_SUPABASE_ANON_KEY=e2e-dummy npx playwright test` (fra `web/`); notér resultat (feed.spec fejler kendt på main).
- [ ] **Step 4:** Commit `docs: beslutning om statuslinje og skilsmissevisning`; push og draft-PR efter `docs/pull_request_template.md` med »mobil: følger med her« og e2e-resultatet. Ingen DDL → ingen [MERGE IKKE]-markør.

### Task 9: Runbook — køn for ingifte (prod, gated)

**Files:**
- Create: `docs/runbooks/2026-11-27-koen-ingifte.sql`

**Interfaces:** psql-variabler som `2026-11-26-linjernes-adelsnavn.sql`: `-v redaktoer_uid=<uuid>` (påkrævet), `-v skriv=1` (ellers ROLLBACK).

- [ ] **Step 1:** Skriv runbooken: én transaktion; `set_config('request.jwt.claim.sub', …)`; kandidater = `koen IS NULL AND NOT levende` med mindst én modpart på tværs af alle familier, og alle modparter af samme kendte køn; `red_set_koen(id, 'kvinde'|'mand')` pr. kandidat (ét ændringssæt, fordi `begin_change_set` genbruger transaktionens sæt). Output: antal pr. udfald (kvinde/mand/levende sprunget over/ingen ægtefælle/ukendt modpart/blandet) og id-listen over dem, der ikke blev sat. Forventet i prod 27/11: 305 kvinde + 309 mand = 614; 45 ikke sat.
- [ ] **Step 2:** Prøv lokalt på en frisk base (`createdb`, `tests/sql/evidence-promotion-bootstrap.sql`, `schema.sql`, `db-rls.sql`) med syntetiske personer: en hustru uden køn, en levende uden køn, en med blandede modparter. Forvent 1 sat, 2 på listen; med `skriv` ikke sat → intet ændret. Slet den lokale base bagefter (egen syntetisk base).
- [ ] **Step 3:** Commit `docs(runbook): køn for ingifte efter ægteskabsreglen`.
- [ ] **Step 4 (prod, først efter projektejerens ja):** backup til `~/.private/` (pg_dump, chmod 600) → prøvekørsel via Supabase MCP (ROLLBACK; tal = forventet) → skriv → tjek: `SELECT count(*) FROM person WHERE koen IS NULL` = 45; anon ser stadig 0 levende; `get_advisors` uden nye fund. Redaktørlisten (id'er) til `~/.private/koen-ingifte/redaktoerliste.txt`.

### Task 10: Runbook — skilsmissedatoer (prod, gated)

**Files:**
- Create: `docs/runbooks/2026-11-27-skilsmissedatoer.sql`

- [ ] **Step 1:** Skriv runbooken (samme variabler og transaktionsform). For hver skilsmisse-familie: kildeudgaven = citationens `source_id` (1 = 2018-20, 3 = 1939); søg partnernes `narrative` (`subjekt_type='person'`, samme `source_id`) med `(?:skilt|ægteskabet (?:er )?opløst|ægteskabet ophævet)\s+(\d{1,2}\.?\s*[A-Za-zæøå]+\.?\s+\d{4}|\d{4})`; fortolk dag + måned (jan./Jan./januar, feb., marts, april, maj, juni, juli, aug., sept., okt., nov., dec.) eller år til `date_min`/`date_max`. Skriv kun ved: partneren har præcis én skilt familie, præcis én distinkt dato, og `date_min >= vielsens date_min` når vielsen har en dato. Kald `red_upsert_fakta('family', fam, 'skilsmisse', NULL, dmin, dmax, NULL, raw, 'Dansk Adels Aarbog <udgave>, biografien')`. Output: kun antal (skrevet / flertydig / uden dato / før vielsen / ukendt måned) og familie-id'er for dem, der ikke blev skrevet. Aldrig datoer eller tekst.
- [ ] **Step 2:** Prøv lokalt på frisk base med syntetiske familier og narrativer: én entydig 2018-20 (»skilt 12. okt. 1901«), én 1939 (»Ægteskabet opløst 1921«), én med to datoer, én med dato før vielsen → 2 skrevet, 2 på listen; den gamle påstand findes stadig; `red_fortryd_change_set` fjerner de to nye.
- [ ] **Step 3:** Commit `docs(runbook): skilsmissedatoer fra biografierne`.
- [ ] **Step 4 (prod, først efter projektejerens ja):** backup → prøvekørsel via MCP (forventet ca. 14 skrevet før vielses-tjekket) → skriv → tjek: antal skilsmisse-påstande med `date_min` = skrevet; anon ser stadig 15 skilsmisse-fakta og 0 levende; `get_advisors`. Familielisten til `~/.private/skilsmissedatoer/redaktoerliste.txt`.
