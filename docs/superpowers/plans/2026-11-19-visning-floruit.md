# visning_floruit (leverance 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personer uden fødsel og død viser »Nævnes 1349–1391« (afledt af strukturerede datoer) i stedet for »Livsdatoer ikke angivet«, alle fem steder.

**Architecture:** Nyt cachefelt `person.visning_floruit` (kun årstal) sat af `regen_person_visning` ud fra afklarede, daterede fakta på personen og på offentlige, ikke-formodede familier, hvor personen er partner; nye invalideringstriggere på familie-fakta, `family_member` og `person`. Klienten danner visningsteksten med én delt formatter i `@daa/core`, og samme_som-collapse fletter spændene.

**Tech Stack:** PostgreSQL 17 / Supabase (plpgsql, triggere), TypeScript + React (Vite, vitest), RN/Expo (jest).

**Spec:** `docs/superpowers/specs/2026-11-19-visning-floruit-design.md` (godkendt 19/11). Læs den før hver opgave.

## Global Constraints

- Cacheformat: `'1671'` eller `'1349–1391'` (U+2013 en-tankestreg, ingen mellemrum); NULL uden kilder. Ordet »Nævnes« gemmes aldrig i DB.
- Visningstekst: `'Nævnes ' + floruit` — kun når `fmtYears(foedt, doed)` er tom.
- `visning_floruit` skrives KUN af `regen_person_visning` (invariant 4); står i `version_pk_registry.skip_cols` for `person`.
- Kilder: kun `conclusion.status='afklaret'` og `assertion.id = conclusion.valgt_assertion_id`.
- Familie-fakta tæller kun, når familien er offentlig (intet medlem med `levende IS NOT FALSE`, `privat` eller `staged`) og personens egen partner-række ikke har `konfidens IN ('formodet','omstridt')`.
- `born`/`died`/`foedtSpaend`/`doedSpaend` uændrede — floruit må aldrig blive en fødsel eller død.
- `schema.sql` er source of truth; `db-migrations.sql` får en idempotent blok `-- ===== visning-floruit: »Nævnes …« som cache =====` sidst i filen.
- Commits: Conventional Commits, dansk beskrivelse, ingen Claude-attribution; implementer-subagenter committer IKKE (forælder-sessionen ejer commits). Ingen push uden projektejerens ja.
- PII: læs aldrig `work/`, `work_presens/`; prod røres kun af projektejeren via `!`-kommandoer.

## Review Focus

1. **Web deployet før DDL:** `select(... visning_floruit ...)` mod en prod uden kolonnen fejler, og hele modellen (alle sider) går ned. Forventet: DDL i prod FØR merge og før preview-afprøvning mod prod — Task 4, trin 1 håndhæver rækkefølgen.
2. **Levende barn i ægtefællens familie:** vielsesåret må ikke stå i cachen; når barnet markeres afdødt, kommer det. Test i Task 1 (`OK: visning-floruit gdpr`).
3. **Samme_som med livsdatoer på én alias og floruit på en anden:** livsdatoerne vises, ikke »Nævnes«. Test i Task 2 (`collapseSameAs` »alias med livsdatoer vinder over floruit«).
4. **Åben ende og kun råtekst:** `date_min` NULL (»før 1261«) giver `'1261'`; en påstand med kun `date_raw` (ingen min/max) tæller ikke. Test i Task 1 (`OK: visning-floruit spaend`).
5. **Rekursion/kaskade:** `regen_person_visning`s egen `UPDATE person SET visning_*` må ikke udløse `person`-triggeren; backfill af alle personer skal holde sig under prods `statement_timeout` (2 min). Test i Task 1 (trigger er `UPDATE OF levende, privat, staged`) + tidsmåling i Task 4's generalprøve.

---

### Task 0: Læse-kun måling af forventede tal (forælder-sessionen + projektejeren)

**Files:** job-tmp `floruit-forventet.sh` (ikke i repo).

**Interfaces:** Produces: tallene `N_FLORUIT_RAEKKER` (personrækker med ikke-NULL beregnet floruit) og `N_NAEVNES_IDENTITETER` (identiteter uden livsdatoer med floruit), som Task 4's invarianter låser.

- [ ] **Step 1:** Skriv et `BEGIN READ ONLY … ROLLBACK`-script (CTE'er, ingen temp-tabeller), der beregner spændet med præcis §5-reglerne (inkl. offentlig-familie- og konfidensfilter) for alle personer, og tæller `N_FLORUIT_RAEKKER`, `N_NAEVNES_IDENTITETER` (samme_som foldet som i `floruit-identitet.sh`) og hvor mange vielser filtrene fjerner. Syntakstjek mod lokal stand-in (output kasseres).
- [ ] **Step 2:** Projektejeren kører det (`! zsh …`). Notér tallene i Task 4's runbook. Forventet `N_NAEVNES_IDENTITETER` ≤ 85.

### Task 1: DB — kolonne, beregning, invalidering, verify

**Files:**
- Modify: `schema.sql` (`person`-tabellen ~l.126; `regen_person_visning` ~l.6432; triggerafsnittet ~l.6488-6565; `version_pk_registry`-seed)
- Modify: `db-migrations.sql` (ny blok sidst)
- Modify: `db-verify.sql` (skip_cols-assert ~l.7046; ny blok efter »Task 2: Cache-regenerering« ~l.6680)

**Interfaces:**
- Produces: `person.visning_floruit TEXT`; `regen_person_visning(pid bigint)` (uændret signatur); triggerfunktionerne `trg_regen_from_family_member()` og `trg_regen_from_person_offentlighed()`; hjælper `regen_familie_partnere(p_family_id bigint)`.

- [ ] **Step 1: Skriv verify-blokken først** — `-- ===== visning-floruit =====` i `db-verify.sql`, `BEGIN … ROLLBACK`, syntetiske negative id'er, én `DO`-blok pr. NOTICE:
  - `OK: visning-floruit spaend` — floruit-faktum 1349-01-01..1391-12-31 → `'1349–1391'`; dateret titel 1400 tilføjet → `'1349–1400'`; fødsel-faktum 1300 påvirker ikke; påstand med kun `date_raw` ignoreres; `date_min` NULL / `date_max` 1261-12-31 → `'1261'`; ikke-valgt påstand og `status<>'afklaret'` ignoreres; person uden kilder → NULL.
  - `OK: visning-floruit vielse` — to afdøde partnere + dateret vielse (fact på `family`) 1657 → begge `'1657'`; ny konklusion på vielsen (1658) regenererer begge via triggeren; partner-række `konfidens='formodet'` → den partner NULL, den anden `'1657'`; `UPDATE family_member SET konfidens='sikker'` → `'1657'` igen.
  - `OK: visning-floruit gdpr` — INSERT af et levende barn i familien → begge partnere NULL; `UPDATE person SET levende=false` på barnet → `'1657'`; samme med `privat=true` og `staged=true`; DELETE af barnets række → `'1657'`.
  - `OK: visning-floruit livsdatoer` — person med fødsel + floruit får både `visning_foedt` og `visning_floruit` sat.
  - Udvid skip_cols-assertet (~l.7046) med `'visning_floruit'`.
- [ ] **Step 2: Kør på frisk base og se den fejle**
  Run: `db=vf_t1; createdb $db && for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do psql -q -X -v ON_ERROR_STOP=1 -d $db -f $f >/dev/null || break; done; psql -X -v ON_ERROR_STOP=1 -d $db -f tests/sql/run-db-verify-disposable.sql 2>&1 | grep -E "visning-floruit|ERROR" | head`
  Expected: ERROR om manglende kolonne `visning_floruit`.
- [ ] **Step 3: Implementér i `schema.sql`.** Kolonnen; skip_cols; i `regen_person_visning` en ekstra CTE og `visning_floruit` i `UPDATE` + `IS DISTINCT FROM`-tuplen. Beregningen (bindende form; resten som eksisterende kode):

```sql
floruit_kilder AS (
  SELECT a.date_min, a.date_max FROM fact f
  JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
  JOIN assertion a ON a.id=c.valgt_assertion_id
  WHERE f.subjekt_type='person' AND f.subjekt_id=pid AND f.faktatype NOT IN ('fødsel','død')
    AND (a.date_min IS NOT NULL OR a.date_max IS NOT NULL)
  UNION ALL
  SELECT a.date_min, a.date_max FROM family_member fm
  JOIN fact f ON f.subjekt_type='family' AND f.subjekt_id=fm.family_id
  JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status='afklaret'
  JOIN assertion a ON a.id=c.valgt_assertion_id
  WHERE fm.person_id=pid AND fm.rolle='partner' AND coalesce(fm.konfidens,'') NOT IN ('formodet','omstridt')
    AND (a.date_min IS NOT NULL OR a.date_max IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM family_member m JOIN person q ON q.id=m.person_id
                    WHERE m.family_id=fm.family_id
                      AND (q.levende IS NOT FALSE OR coalesce(q.privat,false) OR coalesce(q.staged,false)))
), floruit AS (
  SELECT min(extract(year FROM coalesce(date_min,date_max)))::int AS lo,
         max(extract(year FROM coalesce(date_max,date_min)))::int AS hi FROM floruit_kilder
)
-- visning_floruit = CASE WHEN lo IS NULL THEN NULL WHEN lo=hi THEN lo::text ELSE lo||'–'||hi END
```

  Offentlighedsreglen er inlinet (ikke `family_offentlig()`), fordi `family_offentlig` defineres i `db-rls.sql`, der kører efter `schema.sql`; verify-blokken skal desuden assertere, at den inlinede regel og `family_offentlig(id)` er enige for alle familier i basen.
  Triggere:
  - `regen_familie_partnere(p_family_id)`: `PERFORM regen_person_visning(person_id)` for hver `partner` i familien.
  - `trg_regen_from_conclusion` / `trg_regen_from_assertion`: tilføj gren for `fact.subjekt_type='family'` → `regen_familie_partnere`.
  - `trg_regen_from_family_member()` AFTER INSERT OR DELETE OR UPDATE ON `family_member` FOR EACH ROW: `regen_familie_partnere` for NEW.family_id og OLD.family_id (begge, hvis forskellige), samt `regen_person_visning` for OLD.person_id, hvis den var partner og har forladt familien.
  - `trg_regen_from_person_offentlighed()` AFTER UPDATE OF levende, privat, staged ON `person` FOR EACH ROW WHEN (værdierne er DISTINCT): `regen_familie_partnere` for hver familie, personen er medlem af.
- [ ] **Step 4: Spejl i `db-migrations.sql`** — `ALTER TABLE person ADD COLUMN IF NOT EXISTS visning_floruit TEXT`, skip_cols-`UPDATE` som l.1512, `CREATE OR REPLACE` af de berørte funktioner (kopiér fra `schema.sql` ordret), `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`. Ingen backfill i blokken (Task 4).
- [ ] **Step 5: Kør verify på frisk og migrations-sti**
  Run: Step 2's kommando på ny base `vf_t1b`, derefter `psql -X -d vf_t1b -f tests/sql/run-db-verify-disposable.sql 2>&1 | grep -c "OK: visning-floruit"`.
  Expected: `4`, ingen ERROR. Kør derefter `db-migrations.sql` endnu en gang mod basen (idempotens): exit 0.
- [ ] **Step 6: Opgraderingssti** — gendan en lokal stand-in-kopi (`createdb -T daa5ab_ddl_standin_20261114150000_fmd vf_t1_up`), kør KUN den nye blok, kald `SELECT count(*) FROM (SELECT regen_person_visning(id) FROM person) x`, og tæl `visning_floruit IS NOT NULL`. Expected: tallet stemmer med Task 0's `N_FLORUIT_RAEKKER` ±(ændringer siden 14/11; forklar afvigelser), og `visning_foedt/doed` er uændrede for alle personer (sammenlign før/efter). Slet egne testbaser bagefter (stående ja for syntetiske baser; stand-in-kopien er din egen `-T`-kopi).
- [ ] **Step 7: Commit** — `git add schema.sql db-migrations.sql db-verify.sql && git commit -m "feat(db): visning_floruit som cache med offentlig-sikre vielser"`

### Task 2: Core — formatter og collapse-fletning

**Files:**
- Modify: `packages/core/src/fields.ts`, `packages/core/src/types.ts:113-125` (`AppPerson`), `packages/core/src/collapseSameAs.ts:249-310`, `packages/core/src/index.ts` (eksport, hvis fields ikke re-eksporteres i forvejen)
- Test: `packages/core/src/__tests__/fields.test.ts`, `packages/core/src/__tests__/collapseSameAs.test.ts`

**Interfaces:**
- Produces: `fmtVisningsAar(foedt: string | null | undefined, doed: string | null | undefined, floruit: string | null | undefined): string`; `fletFloruit(vaerdier: (string | null | undefined)[]): string | null`; `AppPerson.floruit?: string | null`.

- [ ] **Step 1: Failing tests** i `fields.test.ts`:
  - `fmtVisningsAar('* 1640', '† 1708', '1660')` → `'1640–1708'`; `(null, null, '1349–1391')` → `'Nævnes 1349–1391'`; `(null, null, '1671')` → `'Nævnes 1671'`; `(null, null, null)` → `''`; `(null, '(-1358)', '1319–1363')` → `fmtYears(null,'(-1358)')`.
  - `fletFloruit(['1349–1391', '1400', null])` → `'1349–1400'`; `fletFloruit(['1657'])` → `'1657'`; `fletFloruit([null, undefined])` → `null`; `fletFloruit(['1391–1349'])` normaliserer ikke (input er altid lo≤hi; testen dokumenterer kun gyldig form).
  I `collapseSameAs.test.ts`: »alias med livsdatoer vinder over floruit« (kanonisk uden år + floruit `'1600'`, alias med born 1640/died 1708 → `years === '1640–1708'`); »floruit flettes som forening« (to aliaser `'1349–1360'` og `'1380–1391'` uden livsdatoer → `floruit === '1349–1391'`, `years === 'Nævnes 1349–1391'`).
- [ ] **Step 2:** `npm run test -w @daa/core` → FAIL (`fmtVisningsAar` findes ikke).
- [ ] **Step 3:** Implementér i `fields.ts` (`fletFloruit` parser `^\d{3,4}(–\d{3,4})?$`, ignorerer andet). I `collapseSameAs.ts`: `floruit: fletFloruit(ids.map(...floruit))`, og `regenYears` erstattes af `fmtVisningsAar` med born/died-tallene som strenge og den flettede floruit.
- [ ] **Step 4:** `npm run test -w @daa/core && npm run typecheck -w @daa/core` → PASS.
- [ ] **Step 5: Commit** — `feat(core): fmtVisningsAar og fletning af floruit i samme_som`

### Task 3: Web og mobil — hent feltet, fjern fallbacks

**Files:**
- Modify: `web/src/data/model.ts:34-37,64,108`, `web/src/data/types.ts` (rå person-type ~l.49)
- Modify: `web/src/components/PersonSide.tsx:88-89`, `DetailPanel.tsx:71`, `SoegView.tsx:179`, `RelateView.tsx:112,202`
- Modify: `mobile/src/data/load.ts:100-102,215`, `mobile/src/data/types.ts:46`
- Test: `web/src/components/__tests__/DetailPanel.resume.test.tsx` (opdatér), nye/udvidede tests i `PersonSide.test.tsx`, `SoegView`-, `RelateView`-testfilerne (find med `ls web/src/components/__tests__ | grep -E "Soeg|Relate"`), mobil load-test hvis den findes.

**Interfaces:**
- Consumes: `fmtVisningsAar`, `AppPerson.floruit` (Task 2); kolonnen `visning_floruit` (Task 1).

- [ ] **Step 1: Failing tests:** for hver af de fem steder: person med `years: 'Nævnes 1349–1391'` viser teksten; person med `years: ''` viser hverken »Livsdatoer ikke angivet« eller en tom årslinje (personside/panel: intet `<p>` for år; Søg: kun titel; Relate:112: kun linje; Relate:202: intet årsspan). `model.ts`-test (eller ny): rå række `{visning_foedt:null, visning_doed:null, visning_floruit:'1657'}` → `years === 'Nævnes 1657'`, `born === null`.
- [ ] **Step 2:** `npm run test -w web` → FAIL.
- [ ] **Step 3:** Tilføj `visning_floruit` til select-strengene (web + mobil) og rå-typerne; `floruit: p.visning_floruit ?? null`; `years: fmtVisningsAar(p.visning_foedt, p.visning_doed, p.visning_floruit)`. Fjern de fem fallbacks; personside og panel renderer årslinjen kun når `p.years` er sand. Spec §8: tjek med `grep -n "'born',\|'died'" db-migrations.sql`, om en anon-læserflade viser RPC'ernes `born`/`died` uden modellen (feed-kortene bruger `modelPerson?.years` først, `FeedStreamView.tsx:340`); kun i så fald tilføjes `floruit` — notér fundet i PR-teksten.
- [ ] **Step 4: CI's node-job lokalt (hele jobbet, tjek exit-kode):**
  Run: `npm ci && npm run test -w @daa/core && npm run typecheck -w @daa/core && npm run test -w web && npm run build -w web && node --test web/scripts/verify-public-rpcs.test.mjs && npm --workspace mobile exec -- tsc --noEmit && npm test -w mobile; echo exit=$?`
  Expected: `exit=0`. (`web/.env.local` med CI-dummy kræves; se ci.yml l.85.)
- [ ] **Step 5: Commit** — `feat(personside): »Nævnes …« i stedet for »Livsdatoer ikke angivet«`

### Task 4: Prod — generalprøve, ceremoni, dokumentation (forælder-sessionen + projektejeren)

**Files:**
- Create: `docs/runbooks/visning-floruit-prod.md`
- Create (privat, ikke i git): `~/.private/visning-floruit/prod.zsh`
- Modify: `docs/database-current-state.md` (ny §33), `docs/changelog.md`, `docs/decisions.md` (indgang 2026-11-19: GDPR-filter, konfidens, kvalifikatorer, leverance 2-retning)

- [ ] **Step 1: Rækkefølge låses i runbooken:** CI grøn på draft-PR → generalprøve → prod-DDL+backfill → først derefter preview-afprøvning mod prod og merge (Review Focus 1).
- [ ] **Step 2: `prod.zsh`** efter mønstret i `database-current-state.md` §29: `apply` (default prøve-kørsel med ROLLBACK; `--jeg-mener-det` committer) i ÉN transaktion: hash-tjek af blokken (sha af `db-migrations.sql`-blokken) → blokken → db-verify-blokken `visning-floruit` (4 × OK) → `SELECT regen_person_visning(id) FROM person` → invarianter før COMMIT: antal personer med ikke-tom `visning_foedt`/`visning_doed` uændret (før-tal målt i samme transaktion), `count(visning_floruit IS NOT NULL) = N_FLORUIT_RAEKKER` (Task 0) → før/efter-tal skrives til `~/.private/visning-floruit/log/`. `fortryd --jeg-mener-det`: genskab main's funktionsdefinitioner, drop de nye triggere, `UPDATE person SET visning_floruit=NULL` (kolonnen bliver; ufarlig).
- [ ] **Step 3: Generalprøve** på en frisk restore af prod-dump (stand-in): `apply --jeg-mener-det`, mål tiden (skal være ≪ 2 min), `fortryd`, `apply` igen; tal = Task 0.
- [ ] **Step 4: Projektejeren kører** `! zsh ~/.private/visning-floruit/prod.zsh apply` (prøve), derefter med `--jeg-mener-det` efter eksplicit ja. Derefter `get_advisors` (security) uden nye fund.
- [ ] **Step 5: Browsertjek** (preview mod prod, som anon, desktop + mobil): 44 viser »Nævnes 1349–1391«; 594 viser »Nævnes 1657« (hvis familien er offentlig, ellers intet — se Task 0-tallet); 392 Conrad uændret; en person uden dato viser ingen årslinje.
- [ ] **Step 6: Dokumentér** tal og fortrydelsesartefakt i de tre docs-filer; commit `docs(floruit): prod-status og beslutninger for visning_floruit`.
