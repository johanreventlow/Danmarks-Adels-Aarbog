# Fødenavn som faktatype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Præsenslistens født-klausul læser en kildebundet `fødenavn`-påstand i stedet for den cachede `visning_efternavn`, så 811 kan følge cache-reglen uden at ligne en født Reventlow (#401).

**Architecture:** Ny faktatype i `vocab` (data, ingen kolonne). Redaktion får feltet `foedenavn`. Præsenslisten henter afklarede `fødenavn`-påstande med samme fact→conclusion→assertion-join som adelstitlerne og foretrækker dem i `fodtKlausul`.

**Tech Stack:** PostgreSQL 17 (schema.sql/db-migrations.sql/db-verify.sql), React + vitest (web), React Native + jest (mobile, kun dev), `@daa/core`.

**Spec:** `docs/superpowers/specs/2026-11-20-foedenavn-design.md`

## Global Constraints

- Faktatypens kode er præcis `fødenavn`; redaktørfeltets nøgle er `foedenavn`, etiket `Fødenavn`.
- Vocab-label: `Fødenavn — slægtsnavn ved fødslen (ingifte); titel er et eget titel-faktum`.
- Værdien er kun slægtsnavnet; titlen er et separat `titel`-faktum.
- `regen_person_visning` og `visning_efternavn`'s betydning ændres ikke (#396).
- Kun afklarede konklusioner (`status='afklaret'`) og den valgte påstand tæller.
- Commits: Conventional Commits, dansk beskrivelse, ingen Claude-attribution.

## Review Focus

- Kone uden fødenavn-faktum og med slægtsnavn fra linjen (de 4 født-Reventlow-koner) → klausulen er uændret (`født Reventlow` / `født komtesse …`). Test i Task 2.
- Kone med fødenavn-faktum OG cachet efternavn → fødenavnet vinder. Test i Task 2.
- Fødenavn-faktum med tom/whitespace værdi eller konklusion ≠ afklaret → ignoreres (falder tilbage). Test i Task 2.
- Mand eller kone uden adelig ægtefælle med fødenavn → intet ændres i formatet (klausulen gælder kun den tilgiftede gren). Test i Task 2.
- Migrationen køres to gange → én vocab-række. Verifikation i Task 1.

---

### Task 1: Faktatypen i databasen

**Files:**
- Modify: `schema.sql` (vocab-indsættelsen ved `('faktatype','overhoved',…)`, ~linje 6405)
- Modify: `db-migrations.sql` (ny blok sidst: `-- ===== fødenavn-faktatype =====` … `-- END fødenavn-faktatype`)
- Modify: `db-verify.sql` (ny DO-blok efter overhoved-tjekket ~linje 9867)

**Interfaces:**
- Produces: `vocab(scheme='faktatype', code='fødenavn')`.

- [ ] **Step 1:** db-verify-blok `$verify_foedenavn$`: `RAISE EXCEPTION 'VERIFY_FAILED: fødenavn-faktatype mangler'` hvis rækken mangler; ellers `RAISE NOTICE 'OK: fødenavn-faktatype'`.
- [ ] **Step 2:** Byg engangsbase (bootstrap → dblink → schema.sql → db-migrations.sql → db-rls.sql) fra main's `schema.sql` og kør blokken alene. Forventet: `VERIFY_FAILED: fødenavn-faktatype mangler`.
- [ ] **Step 3:** Tilføj rækken i `schema.sql` og blokken i `db-migrations.sql` (`INSERT … ON CONFLICT (scheme, code) DO NOTHING`).
- [ ] **Step 4:** Fuld kørsel på frisk base: `psql -X -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql` → exit 0 og `OK: fødenavn-faktatype`; kør `db-migrations.sql` en gang til → exit 0 og `SELECT count(*) FROM vocab WHERE scheme='faktatype' AND code='fødenavn'` = 1.
- [ ] **Step 5:** Commit `feat(db): faktatypen fødenavn (#401)`.

### Task 2: Web — Redaktion-felt, præsensliste og personside

**Files:**
- Modify: `web/src/data/redaktionWrite.ts` (`FELT_FAKTATYPE`: `foedenavn: 'fødenavn'`)
- Modify: `web/src/Redaktion.tsx` (`FELT_DEFS`: `['foedenavn', 'Fødenavn']` efter `['navn','Navn']`)
- Modify: `web/src/data/presens.ts`
- Modify: `packages/core/src/personFacts.ts` (`FAKTA_RAEKKEFOELGE`: `'fødenavn'` efter `'tilnavn'`)
- Test: `web/src/data/__tests__/presens.test.ts`, `web/src/data/__tests__/redaktionWrite*.test.ts` (eksisterende fil for `buildRpcCall`)

**Interfaces:**
- Consumes: faktatypen `fødenavn` (Task 1).
- Produces:
  - `mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById = new Map(), foedenavnFakta: RawTitelFact[] = [])` — fjerde parameter; første ikke-tomme fødenavn pr. person (laveste conclusion-id) vinder.
  - `fetchFaktaVaerdier(faktatype: string, personIds: number[]): Promise<RawTitelFact[]>` — den fælles join, udskilt af `fetchAdelsTitelFakta`, som nu filtrerer dens resultat med `erAdelsTitel`.
  - `fodtKlausul(egenTitel, foedenavn)` — uændret form; kaldes med `foedenavnFakta`-værdien ?? `visning_efternavn`.

- [ ] **Step 1:** Tests i `presens.test.ts`:
  - `født-klausul bruger fødenavn-faktum frem for cachet efternavn` — kone 2 (`koen:'kvinde'`, `visning_efternavn:'Reventlow'`), mand 1 med titel `Greve` og `visning_efternavn:'Reventlow'`, `foedenavnFakta=[{subjekt_id:2, vaerdi_tekst:'Hansen'}]` → `fodt === 'Hansen'`, `titel === 'Grevinde'`, `tilgiftet === true`.
  - `født-klausul uden fødenavn er uændret` — samme uden `foedenavnFakta`, kone med egen titel `Komtesse` og `visning_efternavn:'Ahlefeldt-Laurvig'` → `fodt === 'komtesse Ahlefeldt-Laurvig'`.
  - `tomt fødenavn ignoreres` — `vaerdi_tekst:'  '` → falder tilbage til `visning_efternavn`.
  - `kone uden visning_efternavn men med fødenavn får klausul` — `visning_efternavn:null`, fødenavn `Hansen` → `fodt === 'Hansen'`.
  - `fødenavn uden adelig ægtefælle ændrer intet` — ingen ægtefælle → `fodt` undefined, `efternavn` = egen `visning_efternavn ?? ''`.
- [ ] **Step 2:** Test i redaktionWrite-testen: `opretFakta` med `felt:'foedenavn'` → `{ fn:'red_opret_fakta', args.p_faktatype:'fødenavn' }` og ingen `p_date_raw`.
- [ ] **Step 3:** `cd web && npx vitest run src/data/__tests__/presens.test.ts <redaktionWrite-testfil>` → de nye tests fejler.
- [ ] **Step 4:** Implementér: `fetchFaktaVaerdier` (afklaret + valgt påstand, `ORDER BY id` på alle tre led som i dag), `fetchPresensNavneDele` henter `fetchFaktaVaerdier('fødenavn', alleIds)` parallelt med adelstitlerne og sender det som fjerde argument; `mapPresensNavneDele` bygger `foedenavnById` (trim; tom = ingen) og bruger `foedenavnById.get(id) ?? egetEfternavn` i `fodtKlausul`. `FELT_FAKTATYPE`, `FELT_DEFS`, `FAKTA_RAEKKEFOELGE` som angivet.
- [ ] **Step 5:** Hele web- og core-suiten: `cd web && npx vitest run` og `npm run test -w @daa/core`, `npm run typecheck -w @daa/core`, `npm run build -w web` → alle exit 0.
- [ ] **Step 6:** Commit `feat(præsensliste): født-klausul læser faktatypen fødenavn (#401)`.

### Task 3: Mobil (dev) i sync

**Files:**
- Modify: `mobile/src/data/presens.ts`, `mobile/src/data/redaktionWrite.ts`, `mobile/src/app/redaktion/person/[id].tsx` (`FELTER`: `'foedenavn'` efter `'navn'`)
- Test: `mobile/src/data/__tests__/presens.test.ts`

**Interfaces:**
- Consumes: samme signaturer som Task 2 (`mapPresensNavneDele` 4. parameter, `fetchFaktaVaerdier`).

- [ ] **Step 1:** Port de fem presens-tests fra Task 2 til `mobile/src/data/__tests__/presens.test.ts`.
- [ ] **Step 2:** `npm test -w mobile -- presens` → fejler.
- [ ] **Step 3:** Port implementeringen (samme navne og regler som web).
- [ ] **Step 4:** `npm test -w mobile` og `npm --workspace mobile exec -- tsc --noEmit` → exit 0.
- [ ] **Step 5:** Commit `feat(mobil): fødenavn-felt og født-klausul i sync med web (#401)`.

### Task 4: Prod, 811 og dokumentation (operatør: projektejeren; agenten forbereder og verificerer)

**Files:**
- Modify: `docs/decisions.md`, `docs/database-current-state.md` (§35), `docs/changelog.md`
- Privat: `~/.private/visning-cache-396/prod.zsh` (ny handling `vocab`)

- [ ] **Step 1:** Runner-handling `vocab [--jeg-mener-det]`: én transaktion med blokken `fødenavn-faktatype` (sha-låst fra grenens commit), tjek `count=1`, ingen andre ændringer (`person`/`change_set`/`change_event`-tællere uændrede); prøve på stand-in fra frisk læsedump.
- [ ] **Step 2:** Projektejeren kører `vocab` (prøve) og `vocab --jeg-mener-det` i prod. Agenten verificerer læse-kun med ny forbindelse.
- [ ] **Step 3:** PR (draft) med CI grøn; projektejeren merger (rækkefølgen sikrer, at web ikke skriver en ukendt faktatype).
- [ ] **Step 4:** Projektejeren indtaster 811's fødenavn i Redaktion med kilde. Agenten verificerer læse-kun: afklaret `fødenavn`-påstand på 811.
- [ ] **Step 5:** Projektejeren kører `prod.zsh rest` (prøve) og `rest --jeg-mener-det`; agenten verificerer drift = 0. Projektejeren kontrollerer, at præsenslisten stadig viser »født ‹pigenavn›« for 811.
- [ ] **Step 6:** Docs + kommentar og lukning af #401 (`Closes #401` i docs-PR'en).
