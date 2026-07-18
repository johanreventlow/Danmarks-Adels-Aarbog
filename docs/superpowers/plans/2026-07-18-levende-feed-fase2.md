# Levende feed — fase 2: hændelses-skelettet & arkivkort · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Feed'en bliver hændelses-drevet: en ny `haendelse`-tabel (additivt formidlingslag,
regenererbar projektion af narrativ-prosaen) fyldes af en offline pipeline-skill
(`.claude/skills/daa-haendelser/`), klienterne indlæser hændelserne efter livsdato-mønstret,
`@daa/feed` får `arkiv`-kort + hændelses-udvidet `paadennedag` + klausul-drevet citat-kort,
og redaktionen får en kronologisk hændelses-tidslinje med én skrivehandling
(`red_set_haendelse_status`) — alt uden at røre evidensmodellen.

**Architecture:** Skive 1 er én additiv migration (tabel + vocab + RLS + RPC + versionering
af KUN `feed_status`). Skive 2 er en offline pipeline efter daa-extract-arketypen
(deterministisk eksport → LLM pr. narrativ → blokerende validering H1–H8 → R-load med
markering-bevarende merge på stabil nøgle `(narrative_id, noegle)`). Skive 3 er et
loader-spejlpar (`haendelser.ts`) 1:1 efter `livsdato.ts`-parret + en ren join i pakken.
Skive 4 udvider motoren (pool/temporal/score/order) bagudkompatibelt: tom `haendelserBy`
⇒ bit-identisk fase 1-ordning. Skive 5 er read/write-lag + UI i begge apps gennem det
eksisterende `Change`/`buildRpcCall`/dry-run-flow. Skive 6 er CI + afstemning.

**Tech Stack:** PostgreSQL/Supabase (RLS, plpgsql, PostgREST), R (RPostgres, testthat),
Python 3 (unittest), TypeScript + vitest (`packages/feed`), React Native/Expo 56 + jest
(mobil), React/Vite + vitest (web).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-18-levende-feed-fase2-design.md` (autoritativ for alle regler; §-referencer nedenfor peger dertil)
- Koncept: `docs/design/2026-07-18-levende-feed-koncept.md` (§3 hændelses-skelet, §10 fase 2)
- Pipeline-arketype: `.claude/skills/daa-extract/` (SKILL.md, `scripts/validate.py`, `scripts/load_daa.R`, `scripts/escalate_merge.py`) + `docs/daa-extraction-archetype.md`
- Fase 1-implementeringen (den faktiske kode, ikke planen): `packages/feed/src/`, `mobile/src/data/livsdato.ts`, `web/src/data/livsdato.ts`, `web/src/components/feed/FeedStreamView.tsx`
- DB-konventioner: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`

## Global Constraints

- **Migrationen er additiv og afgrænset:** KUN `haendelse`-tabellen + vocab-seed + RLS-
  politikker + `red_set_haendelse_status` + `version_pk_registry`-registrering. De
  eksisterende evidenstabeller (`fact`/`assertion`/`conclusion`/`citation`/`narrative`)
  røres IKKE af skemaet — `haendelse` bærer aldrig assertion/conclusion (invariant #4).
- **`haendelse` er en regenererbar projektion, ALDRIG ny evidens.** Eneste varige kolonne
  er `feed_status`; alt andet må loaderen overskrive ved gen-kørsel. Bestrides indholdet,
  rettes prosaen/faktaene — aldrig hændelses-rækken.
- **GDPR-hegn om LLM'en:** levende/private/staged personers narrativer sendes ALDRIG til
  LLM-passet — håndhævet i selve eksport-queryen (scriptet bypasser RLS som ejer, så
  filtret må aldrig være implicit), spejlet i RLS og klient-filter (defense-in-depth).
- **Loaderen er en markering-bevarende merge, aldrig append:** match på
  `(narrative_id, noegle)` → UPDATE; `feed_status` røres aldrig af loaderen; mistede
  markeringer logges ALTID i CSV (aldrig tavst datatab). Delkørsler er sikre.
- **Motoren forbliver ren:** ingen netværk/`Math.random`/`Date.now` i `packages/feed`.
  `haendelserBy` udeladt/tom ⇒ ordningen er dybt identisk med fase 1 (regressionsinvariant,
  spec §6.4 — testes eksplicit).
- **Tolerant klient-load:** enhver fejl (inkl. u-migreret base) ⇒ `{}` + `console.warn` —
  feed'en brydes aldrig; alt degraderer til fase 1-adfærd.
- **Prod-migrering er IKKE en del af denne plan** (gated handling, fase 4-runbook-
  disciplinen): alt SQL verificeres mod kopi-base; `docs/database-current-state.md`
  opdateres først når migrationen reelt køres mod prod. Husk dér: `db-rls.sql` skal
  gen-anvendes for at haendelse-politikkerne + det generiske RPC-grant lander.
- **Ingen nye farver/fonte:** mobil styler fra `mobile/src/theme/tokens.ts` (+
  `personEditorSheetStyles`), web fra `web/src/theme.ts`.
- Hver task holder relevante suiter grønne: `packages/feed` → `npx vitest run` +
  `npx tsc --noEmit`; mobil → `npx tsc --noEmit && npm test` (fra `mobile/`); web →
  `npm run test` (fra `web/`); pipeline → `python3 -m unittest discover -s
  .claude/skills/daa-haendelser/scripts -p 'test_*.py'`; R → `Rscript run-tests.R`.
- Commit-beskeder på dansk, `feat(feed): …`-stil; brug din egen sessions Claude-Session-footer.

**Rækkefølge/parallelitet (spec §2):** Task 1 (skive 1) er forudsætning for alt andet.
Task 2–7 (skive 3+4) og task 8–10 (skive 2) og task 11–12 (skive 5) kan bygges parallelt
efter task 1 — klientlagene degraderer tolerant mod en tom tabel. Task 13 (skive 6) sidst.
Rækkefølgen nedenfor er den anbefalede serielle.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql` | Kanonisk `haendelse`-tabel + indexes + RPC | 1 |
| `db-migrations.sql` | Idempotent migration (tabel, vocab, registry, trigger, grants) | 1 |
| `db-rls.sql` | anon/auth/redaktion-politikker + grant/revoke for `haendelse` | 1 |
| `db-verify.sql` | Asserts: CHECK, RLS-synlighed, RPC-gates, fortryd | 1 |
| `packages/feed/src/haendelser.ts` (+ test) | `buildHaendelserBy` — ren join, kanonisering, sortering | 2 |
| `packages/feed/src/types.ts` | `HaendelserBy` i `FeedInputs`; `arkiv`-kind; udvidet `paadennedag` | 2, 5 |
| `mobile/src/data/haendelser.ts` (+ test), `load.ts`, `store/useStore.ts` | Mobil-load + store-felt + strøm-input | 3 |
| `web/src/data/haendelser.ts` (+ test), `components/feed/FeedStreamView.tsx` | Web-load + resume-flow | 4 |
| `packages/feed/src/pool.ts` (+ test) | `buildArkivKort` + klausul-citat i `buildPortraitAndCitat` | 5 |
| `packages/feed/src/temporal.ts`, `score.ts`, `order.ts` (+ test) | Hændelses-paadennedag; `BASE.arkiv`; interessant ×2; wiring | 6 |
| `mobile/src/components/feed/FeedCardView.tsx`, `web/src/components/feed/FeedCardView.tsx` | `arkiv`-case + hændelses-paadennedag-visning | 7 |
| `.claude/skills/daa-haendelser/{SKILL.md,references/*}` + `scripts/export_narratives.R` | Skill-skelet, frossen prompt, schema, vocab, GDPR-eksport | 8 |
| `.claude/skills/daa-haendelser/scripts/validate_haendelser.py` (+ `test_…py`) | H1–H8, span, nøgle, dato-berigelse, eskalering | 9 |
| `.claude/skills/daa-haendelser/scripts/load_haendelser{,_helpers}.R` + `tests/testthat/test-haendelse-merge.R` | Merge-load, dedup, dry-run | 10 |
| `mobile/src/data/redaktion{Read,Write}.ts`, `web/src/data/redaktion{Read,Write}.ts` (+ tests) | `mapHaendelser`/`buildTidslinje`/`haendelseStatus`-change | 11 |
| `mobile/src/components/redaktion/HaendelseTidslinje.tsx`, `mobile/src/app/redaktion/person/[id].tsx`, `web/src/Redaktion.tsx` | Tidslinje-UI + status-piller + klausul-hop | 12 |
| `.github/workflows/ci.yml`, `docs/changelog.md`, `docs/README.md` | Nyt pipeline-job + afstemning | 13 |

---

## Task 1: DB — `haendelse`-tabel + vocab + RLS + RPC + versionering (skive 1)

**Files:**
- Modify: `schema.sql` — tabel + indexes indsættes efter `narrative`-blokken
  (`schema.sql:415-431`, altså FØR `regen_person_visning` linje 433 — projektionen bor ved
  sit substrat); RPC'en indsættes efter `red_set_privat` (`schema.sql:848-859`, dvs. mellem
  den og `red_slet_person` linje 861 — samme lille-setter-familie som `red_set_koen`); **NY
  række i den EKSISTERENDE `version_pk_registry`-INSERT** (`schema.sql:1757-1769`, samme
  `VALUES`-liste som `person`/`fact`/… — IKKE en ny separat INSERT). schema.sql har sin egen
  fulde versionerings-infrastruktur (`version_pk_registry` + generisk trigger-tilknytnings-
  loop, `schema.sql:1751-1770` hhv. `1888-1896` — VERIFICERET, modsiger specens antagelse
  om at infrastrukturen kun findes i db-migrations.sql, se Self-review-noter): den
  eksisterende `DO $$ … FOR r IN SELECT tabel FROM version_pk_registry LOOP …` (linje
  1888-1896) kører EFTER INSERT-listen og tilknytter `trg_log_haendelse` AUTOMATISK for
  enhver ny række i listen — skriv IKKE en separat `CREATE TRIGGER` i schema.sql (loopet gør
  det allerede, og en duplikeret eksplicit trigger ville blot blive overskrevet af loopets
  `DROP TRIGGER IF EXISTS` + gen-opret ved næste fulde kørsel — harmløst, men overflødigt).
- Modify: `db-migrations.sql` — NY dateret sektion appendes til sidst (efter K2-sektionen,
  `red_publicer_udgave`, fil-slut ~linje 2550) med `-- ===…`-bannerstil som de øvrige:
  `-- 2026-07-18: levende feed fase 2 — haendelse (formidlingslag, fase2-spec §3)`. Her er
  situationen OMVENDT af schema.sql: db-migrations.sql's egen generiske trigger-loop
  (`db-migrations.sql:945-952`) står FØR hvor denne dateret sektion appendes, og har derfor
  allerede kørt færdig da `haendelse`-rækken indsættes — ingen eksisterende precedent i filen
  for at en senere dateret sektion re-kører loopet (verificeret: `grep -n "INSERT INTO
  version_pk_registry" db-migrations.sql` giver kun basens oprindelige liste). Denne sektion
  skal derfor selv indeholde en EKSPLICIT `CREATE TRIGGER trg_log_haendelse … EXECUTE
  FUNCTION log_change()` ved siden af sin egen `INSERT INTO version_pk_registry (…) VALUES
  ('haendelse', …) ON CONFLICT (tabel) DO UPDATE …` (som spec §3.5 allerede foreskriver —
  det er KUN schema.sql-siden af denne task der ændres af verifikationen).
- Modify: `db-rls.sql` — haendelse-politikker: anon-blok efter narrative/note-anon-
  politikkerne (~linje 343-368), auth-blok efter narrative/note-auth (~linje 437-455),
  redaktion_read sammen med dem. Det generiske `red\_%`-grant-loop (`db-rls.sql:497-499`)
  fanger RPC'en ved gen-anvendelse — ingen ændring dér nødvendig.
- Modify: `db-verify.sql` — nyt `DO $$ … END $$;`-blok appendes efter K2-blokket
  (fil-slut ~linje 1617).

**Interfaces (spec §3.1–§3.5 er den autoritative SQL — kopiér derfra):**
- Tabel: surrogat-BIGINT-PK uden IDENTITY (basens `max(id)+1`/`nid()`-mønster), fuzzy dato
  = assertion-felterne 1:1, `feed_status` CHECK `('kandidat','interessant','skjult')`,
  `UNIQUE (narrative_id, noegle)`, `ON DELETE CASCADE` på `narrative_id`,
  `ix_haendelse_subjekt` + `ix_haendelse_narrative`.
- Vocab: `haendelse_feed_status` (3 koder) + `haendelse_kategori` (11 koder) —
  `ON CONFLICT (scheme, code) DO NOTHING` (vocab-PK er `(scheme, code)`, `schema.sql:18-24`).
- RLS: anon/auth using-klausul = `feed_status <> 'skjult' AND entitet_offentlig(subjekt_type,
  subjekt_id) AND EXISTS(narrative)`; redaktion ser alt via `current_rolle() = 'redaktion'`.
  Husk eksplicit `revoke insert, update, delete, … from anon, authenticated` (Supabase-
  default-DML, bookmark-fundet review 22 — mønstret står i spec §3.3).
- RPC `red_set_haendelse_status(p_haendelse_id bigint, p_status text)`: gate → validér →
  `begin_change_set` → UPDATE (`red_set_koen`-mønstret, `schema.sql:839-846`). Migrationen
  skal SELV indeholde `GRANT EXECUTE … TO authenticated` (db-migrations gen-anvender ikke
  RLS-laget — fase 4-runbook-lektien).
- Versionering: `version_pk_registry`-ny-række med alle projektionskolonner som `skip_cols`
  (kun `feed_status` logges — B8-mønstret fra `person`). **To forskellige mekanismer pr.
  fil** (se Files-afsnittet ovenfor for hvorfor): i `schema.sql` er det KUN en ny linje i den
  eksisterende `VALUES`-liste (`schema.sql:1757-1769`) — den eksisterende generiske
  trigger-loop (`1888-1896`) tilknytter `trg_log_haendelse` af sig selv; i
  `db-migrations.sql` er det en egen `INSERT INTO version_pk_registry (…) VALUES
  ('haendelse', …) ON CONFLICT (tabel) DO UPDATE …` (spejl af basens `db-migrations.sql:808-831`)
  PLUS en eksplicit `CREATE TRIGGER trg_log_haendelse … EXECUTE FUNCTION log_change()`
  (loopet dér, `db-migrations.sql:945-952`, når ikke rækken — den indsættes efter loopet er
  kørt i samme filgennemløb).

- [ ] **Step 1: Skriv de fejlende asserts (RED).** Nyt db-verify-blok i K2-stilen
  (`db-verify.sql:1589-1617`: negative sentinel-id'er — brug et ubrugt bånd, fx
  `-987656001 …`; `SET LOCAL ROLE anon; … RESET ROLE;`; afslut `RAISE NOTICE 'OK: …'`):
  - `to_regclass('public.haendelse') IS NOT NULL`; INSERT med `feed_status='ingen'` →
    forvent `check_violation` (vokabular-beslutningen: `ingen` udgik).
  - Seed temp-narrativ + temp-hændelse på **levende** person ⇒ 0 rækker som anon; på afdød
    + `feed_status='skjult'` ⇒ 0 rækker som anon OG authenticated; på afdød + narrativ
    `privat=true` ⇒ 0 rækker (cascade); afdød+kandidat+offentligt narrativ ⇒ 1 række.
  - `red_set_haendelse_status` uden redaktion-rolle → EXCEPTION; ugyldig status → EXCEPTION.
  - Fortryd-assert (spec §3.5-forbeholdet): som redaktion, sæt status via RPC'en, kald
    `red_fortryd_change_set` på settet → `feed_status` er tilbage på udgangsværdien og
    ingen skip-kolonne er ændret (`_version_upsert_row`-UPDATE-stien mod en skip_cols-tung
    tabel — det uprøvede terræn bekræftes her).
- [ ] **Step 2: Kør blokket mod u-migreret kopi-base — verificér FAIL** (fejler allerede på
  `to_regclass`).
- [ ] **Step 3: Implementér** SQL'en i alle fire filer jf. Interfaces (spec §3 ordret som
  udgangspunkt; kommentarstil som naboblokkene — dansk, med invariant-/review-referencer).
  Husk `schema.sql`s registry-række KUN tilføjes til den eksisterende `VALUES`-liste (ingen
  ny `CREATE TRIGGER` dér), mens `db-migrations.sql` får sin egen `INSERT … ON CONFLICT`
  OG en eksplicit `CREATE TRIGGER trg_log_haendelse`.
- [ ] **Step 4: Kør — verificér PASS mod BEGGE deploy-stier:** (a) `schema.sql` mod en helt
  frisk kopi-base (clean-slate) — bekræft at `haendelse` optræder i `version_pk_registry`
  OG at `trg_log_haendelse` findes (`\d haendelse` eller
  `SELECT tgname FROM pg_trigger WHERE tgrelid='haendelse'::regclass`), tilknyttet af den
  eksisterende loop uden nogen ny trigger-kode i schema.sql; (b) `db-migrations.sql` mod en
  ALLEREDE deployet (fase 1-niveau) kopi-base, kørt **to gange** (idempotens: anden kørsel =
  no-op) — bekræft samme trigger findes efter den eksplicitte `CREATE TRIGGER`; derefter
  `db-rls.sql` (gen-anvendelse — bekræft at grant-loopet fanger `red_set_haendelse_status`),
  derefter hele `db-verify.sql` grøn mod migrations-stien.
  Kør også `EXPLAIN` på anon-`SELECT * FROM haendelse WHERE subjekt_type='person'` med
  ~10k seedede rækker — bekræft at `ix_haendelse_narrative` bruges i exists-cascaden
  (spec §3.3-forbeholdet; mønstret er identisk med note/assertion-politikkerne).
- [ ] **Step 5: Commit** — `feat(feed): haendelse-tabel + RLS + red_set_haendelse_status + versionering (skive 1)`.

---

## Task 2: `@daa/feed` — ren hændelses-join (`haendelser.ts`) (skive 3)

**Files:**
- Create: `packages/feed/src/haendelser.ts`, `packages/feed/src/__tests__/haendelser.test.ts`.
- Modify: `packages/feed/src/types.ts` (`FeedInputs` linje 45-54: nyt valgfrit felt
  `haendelserBy?: HaendelserBy` — bagudkompatibelt som `livsdatoBy`),
  `packages/feed/src/index.ts` (nyt `export * from './haendelser';`).

**Interfaces (spec §5.1 — kopiér typerne ordret derfra):**
- Rå række-typer `HaendelseRow`/`HaendelseNarrativRow`/`HaendelseSourceRow` (PostgREST-form,
  `string | number`-id'er — samme stil som `LivsdatoFactRow` m.fl., `temporal.ts:9-23`).
- `HaendelseItem { id; klausul; kategori; dato: FuzzyDato; dateRaw; interessant; rygrad; kilde }`
  — `FuzzyDato` genbruges fra `types.ts:37`; `kilde` sammensættes `'DAA <udgave>, s. <side>'`
  (source mangler → `null`).
- `buildHaendelserBy(rows, narrativer, sources, canonicalIdById = {}): HaendelserBy` —
  spejler `buildLivsdatoBy`-kontrakten (`temporal.ts:28-50`): Map-opslag, kanonisering via
  `canonicalIdById[String(subjekt_id)] ?? String(subjekt_id)`, intet netværk.
- Deterministisk sortering pr. person: `date_min` stigende, NULL sidst, `id`-tiebreak.
- `feed_status === 'skjult'` filtreres defensivt (RLS fjerner dem allerede — defense-in-depth).

**Bevidst sekvens-afvigelse fra spec'ens skive-tabel:** `FeedInputs.haendelserBy` tilføjes
allerede her (spec placerer den i skive 4/§6.1) så task 3–4 kan wire loadere ind med grøn
`tsc` — feltet er no-op indtil task 5–6 (motoren ignorerer det). Ingen adfærdsændring.

- [ ] **Step 1: Skriv de fejlende tests** (vitest): join af 3 række-sæt → `HaendelserBy`;
  alias-id kanoniseres til samme nøgle som kanonisk id; sortering (dato, NULL sidst,
  id-tiebreak); `skjult` filtreres; `interessant`/`rygrad`-flag afledes korrekt
  (`fact_id` ELLER `relation_id` sat ⇒ `rygrad:true`); kilde-sammensætning med og uden
  source/side; tomme input → `{}`.
- [ ] **Step 2: Kør — verificér FAIL** (`npx vitest run` fra `packages/feed/`).
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør — verificér PASS** + `npx tsc --noEmit` i pakken.
- [ ] **Step 5: Commit** — `feat(feed): buildHaendelserBy — ren join med kanonisering og skjult-filter (skive 3)`.

---

## Task 3: Mobil — hændelses-load (`mobile/src/data/haendelser.ts`) (skive 3)

**Files:**
- Create: `mobile/src/data/haendelser.ts`, `mobile/src/data/__tests__/haendelser.test.ts`.
- Modify: `mobile/src/data/load.ts`, `mobile/src/store/useStore.ts`,
  `mobile/src/app/(tabs)/index.tsx`.

**Interfaces (spec §5.2 — livsdato-skabelonen 1:1):**
- Kopiér formen fra `mobile/src/data/livsdato.ts`: `IN_CHUNK = 200` (linje 17),
  `chunkArray`/`fetchInChunks` (linje 19-36), tolerant top-catch (linje 63-66) med
  `console.warn('[haendelser] utilgængelig — arkiv-/hændelseskort udelades:', e)`.
- `fetchHaendelseRows(sb): Promise<HaendelseRowsResult>` — 3 queries:
  1) `sb.from('haendelse').select('id,subjekt_id,narrative_id,klausul,kategori,date_min,date_max,date_qualifier,date_raw,feed_status,fact_id,relation_id').eq('subjekt_type','person').order('id')` (via `getAll` fra `@daa/core`)
  2) `narrative` · `id,source_id,side` · chunked `.in('id', narrativeIds)`
  3) `source` · `id,udgave` · chunked `.in('id', sourceIds)` — narrativ-TEKSTEN hentes IKKE.
- `loadHaendelserBy(sb, canonicalIdById): Promise<HaendelserBy>` = fetch + `buildHaendelserBy`.
- `load.ts`-integration (livsdato-mønstret): parallel promise FØR hoved-batchen ved siden af
  `livsdatoRowsP` (`load.ts:116-118`); join efter collapse med `collapsed.canonicalIdById`
  (som `load.ts:323-324`); nyt felt i `LoadResult` (`load.ts:39-63`) med kommentar i
  `livsdatoBy`-stilen (linje 62-63).
- `useStore.ts`: nyt felt `haendelserBy: HaendelserBy` — kommentar + placering som
  `livsdatoBy` (linje 49-51), init `{}` (linje 130), sat fra `res.haendelserBy ?? {}` i
  `load()` (linje 183), `{}` i SEED-fallback med kommentar "SEED bærer ingen hændelser —
  arkiv-/hændelseskort udelades" (linje 215-mønstret).
- `index.tsx`: `haendelserBy` læses fra store (som `livsdatoBy` linje 44) og gives til
  `createFeedStream`-inputs (linje 82-89, + dependency i `useMemo`). No-op indtil task 6.

- [ ] **Step 1: Skriv de fejlende tests** (jest, spejl af `mobile/src/data/__tests__/livsdato.test.ts`):
  mockede queries → join-kæden; chunking (>200 narrativ-id'er → flere `.in`-kald); fejl i
  vilkårligt led → `{}` + warn (aldrig kast); tom `haendelse`-tabel → `{}`.
- [ ] **Step 2: Kør — verificér FAIL.**
- [ ] **Step 3: Implementér** (fetch + integration i load/useStore/index).
- [ ] **Step 4: Kør — verificér PASS**; `npx tsc --noEmit && npm test` grøn fra `mobile/`.
- [ ] **Step 5: Commit** — `feat(feed): haendelses-load mobil — tolerant fetch + store-felt (skive 3)`.

---

## Task 4: Web — hændelses-load + resume-flow (skive 3)

**Files:**
- Create: `web/src/data/haendelser.ts`, `web/src/data/__tests__/haendelser.test.ts`.
- Modify: `web/src/components/feed/FeedStreamView.tsx`.

**Interfaces:**
- `web/src/data/haendelser.ts` = web-spejl af task 3 (samme queries; modul-`supabase` i
  stedet for parameter — præcis som `web/src/data/livsdato.ts` afviger fra mobilens).
- **Mount-orkestreringen bor i `web/src/components/feed/FeedStreamView.tsx` — IKKE
  `Folgesvend.tsx`** (spec §5.2's formodning; verificeret i koden): bio + livsdato hentes
  ved mount (linje 50-55), og rebuild-effekten (linje 84-100) genopbygger strømmen med
  SAMME seed og genoptager via `resumeStream(built, shownIds)` (linje 93). Hæng
  `loadHaendelserBy(canon)` på præcis samme sted: ny state `haendelserBy` (init `{}`),
  hent i samme `useEffect` som `fetchFeedBios`/`loadLivsdatoBy`, giv til
  `createFeedStream`-inputs og tilføj i effektens dependency-liste — append-kontrakten
  (allerede viste kort røres ikke) er fase 1-testet og gratis.

- [ ] **Step 1: Skriv de fejlende tests** (vitest, spejl af `web/src/data/__tests__/livsdato.test.ts`):
  join-kæde, chunking, fejl → `{}`.
- [ ] **Step 2: Kør — verificér FAIL** (`npm run test` fra `web/`).
- [ ] **Step 3: Implementér** (loader + FeedStreamView-wiring).
- [ ] **Step 4: Kør — verificér PASS** + `npm run build` grøn.
- [ ] **Step 5: Commit** — `feat(feed): haendelses-load web + resume ved ankomst (skive 3)`.

---

## Task 5: Motor — `arkiv`-kort + klausul-citat (`types.ts`, `pool.ts`) (skive 4)

**Files:**
- Modify: `packages/feed/src/types.ts`, `packages/feed/src/pool.ts`,
  `packages/feed/src/__tests__/pool.test.ts`.

**Interfaces (spec §6.1–§6.2):**
- `types.ts`: ny `FeedCard`-variant (kopiér fra spec §6.1):

```ts
| { kind: 'arkiv'; id: string; personId: string; name: string; klausul: string;
    aarLabel: string | null; kategori: string | null; kilde: string | null;
    interessant?: boolean; kicker: string }
```

  og `paadennedag`-varianten (`types.ts:31-32`) udvides: `hvad: 'født' | 'død' | 'hændelse'`
  + valgfrit `klausul?: string`. `bookmarkPersonId` (`types.ts:57-59`) virker uændret —
  `arkiv` har `personId` (eksisterende `'personId' in card`-kontrakt).
- `buildArkivKort(model, haendelserBy, usedCitatHaendelseIds): FeedCard[]` (ny, i `pool.ts`):
  kandidat pr. `HaendelseItem` hvor `rygrad === false` OG `!usedCitatHaendelseIds.has(item.id)`;
  `id: 'arkiv:' + item.id`; `aarLabel` = `dateRaw` (verbatim, foretrukket) ellers årstal af
  `dato.min` ellers `null` (aldrig fabrikeret præcision); navn fra `model.byId` (mangler
  personen — ikke-kanoniseret id — udelades kortet); kicker `'Årbogen skriver'`; stabil
  `byIdStr`-sortering (`pool.ts:12`) som alle builders.
- `buildPortraitAndCitat(model, excludeId = null, haendelserBy = {})` (`pool.ts:28-55`):
  hash-mod-4-partitionen (linje 38) er URØRT; for en citat-slot-person vælges citatet nu
  blandt personens klausuler: kandidater = `haendelserBy[p.id]` med `rygrad === false` og
  `klausul.length` 40–180 (længde-gaten fra `firstQuotableSentence` genbrugt som
  kvalitetsgate); valg = `stableHash(p.id) % kandidater.length` (deterministisk,
  dagsuafhængigt). **Fallback:** ingen brugbar klausul → `firstQuotableSentence(p.bio)`
  (`pool.ts:15-22`, uændret); heller intet dér → slotten falder ud (linje 41-mønstret,
  disjunkthed bevares). Returtype udvides til
  `{ portraits, citater, usedCitatHaendelseIds: Set<string> }` — kalder i `order.ts:77`
  rettes i task 6 (denne task retter kun det destrukturerende kald minimalt så `tsc` er grøn).

- [ ] **Step 1: Skriv de fejlende tests** (udvid `pool.test.ts`):
  - `buildArkivKort`: `rygrad:true` udelades; id i `usedCitatHaendelseIds` udelades;
    `aarLabel`-prioritet (dateRaw → år af min → null); ukendt person-id → intet kort;
    stabil sortering; tom `haendelserBy` → `[]`.
  - Citat: person med brugbare klausuler → klausul-citat, deterministisk valg (samme input
    → samme klausul); klausuler udenfor 40–180 → bio-fallback; hverken klausul eller
    bio-sætning → slot falder ud; partitionen uændret (portræt-personer får aldrig citat);
    `usedCitatHaendelseIds` indeholder præcis de valgte klausulers hændelses-id'er.
  - Regressionsværn: `buildPortraitAndCitat(model, ex)` uden tredje argument ≡ fase 1-output.
- [ ] **Step 2: Kør — verificér FAIL.**
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør — verificér PASS** + `tsc` grøn (BASE-recorden i `score.ts:5-17` er
  `Record<FeedCard['kind'], number>` og vil kræve `arkiv`-nøglen — tilføj `arkiv: 0.5`
  allerede her, den fulde scoring testes i task 6).
- [ ] **Step 5: Commit** — `feat(feed): arkiv-kort + klausul-drevet citat med bio-fallback (skive 4)`.

---

## Task 6: Motor — hændelses-paadennedag + scoring + ordning (skive 4)

**Files:**
- Modify: `packages/feed/src/temporal.ts`, `packages/feed/src/score.ts`,
  `packages/feed/src/order.ts`, `packages/feed/src/__tests__/temporal.test.ts`,
  `packages/feed/src/__tests__/order.test.ts`.

**Interfaces (spec §6.2–§6.3):**
- `buildPaaDenneDag(model, livsdatoBy, todayISO, haendelserBy = {})` (`temporal.ts:59-87`):
  hændelser med `dato.qualifier === 'exact'` + `dato.min` og `rygrad === false` føjes til
  de EKSISTERENDE `dayMatches`/`monthMatches`-lister efter samme MM-DD-/MM-regler;
  `id: 'paadennedag:h:' + item.id`, `hvad: 'hændelse'`, `klausul` sat, navn/years fra
  `model.byId` (mangler → udelad). Dag/måneds-fallbacken (linje 86) afgøres over den
  SAMLEDE mængde — ét hændelses-dagtræf undertrykker livsdato-månedstræf (og omvendt).
- `score.ts`: `BASE.arkiv = 0.5` (krydderi-tier med forbundet — sat i task 5); nyt
  redaktionelt signal i `score()` (linje 33-49), dokumenteret ved siden af
  timeliness/personal/seen: `if (card.kind === 'arkiv' && card.interessant) s *= 2;`.
  `paadennedag` med `hvad:'hændelse'` scorer som de øvrige (timeliness ×4 ved
  `praecision==='dag'`, linje 37 — uændret logik, ingen kode-ændring).
- `order.ts` (`buildFeedOrder`, linje 70-155): `const haendelserBy = inputs.haendelserBy ?? {};`
  ved siden af `livsdatoBy` (linje 72); `buildPortraitAndCitat(model, dagensPersonId,
  haendelserBy)` (linje 77) med `usedCitatHaendelseIds` ført videre til
  `buildArkivKort(model, haendelserBy, usedCitatHaendelseIds)` i `candidateCards`
  (linje 80-91); `buildPaaDenneDag(…, haendelserBy)` (linje 89). Rytme-reglerne R1–R3 og
  positionslåse er UMODIFICEREDE — `arkiv` har `personId`, så R2 spreder samme persons
  hændelser automatisk.

- [ ] **Step 1: Skriv de fejlende tests:**
  - `temporal.test.ts`: hændelses-dag-træf → `paadennedag` m. `hvad:'hændelse'`+`klausul`;
    blandet fallback (livsdato-månedstræf undertrykkes af hændelses-dagtræf); qualifier ≠
    'exact' eller `rygrad:true` → aldrig kort; ukendt person-id → udeladt.
  - `order.test.ts`: **fase 1-regressionsværnet** — `buildFeedOrder` med `haendelserBy`
    udeladt OG med `haendelserBy: {}` er dybt identisk med output uden feltet (genbrug
    eksisterende fixtures); determinisme med `haendelserBy` (samme inputs → identisk
    ordning; to seeds → forskellig rækkefølge, samme kort-mængde); valgt citat-klausul
    optræder ALDRIG også som arkiv-kort i ordningen (dublet-testen, over flere seeds);
    `interessant: true` rykker arkiv-kortet statistisk frem over en fast seed-liste
    (gennemsnits-index-assert som fase 1's bookmark-test); tom model → `[]`.
- [ ] **Step 2: Kør — verificér FAIL.**
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør — verificér PASS** (hele pakke-suiten + `tsc`).
- [ ] **Step 5: Commit** — `feat(feed): haendelses-paadennedag + arkiv-scoring med interessant-boost (skive 4)`.

---

## Task 7: Kort-views i begge apps (skive 4)

**Files:**
- Modify: `mobile/src/components/feed/FeedCardView.tsx` (switch, linje 52-207),
  `web/src/components/feed/FeedCardView.tsx` (switch, linje 28-163).

**Regler:**
- Ny `case 'arkiv'`: kicker `'Årbogen skriver'`, klausulen som citat-tekst (verbatim, i
  citat-kortets typografiske idiom — se `case 'citat'` mobil linje 69/web linje 43),
  `aarLabel` som dato-label, kategori diskret, `kilde` som kildefod ('efter DAA …, s. …').
  Styling KUN fra `tokens.ts`/`theme.ts` — oversæt fra de eksisterende korts idiom.
- `case 'paadennedag'` (mobil linje 153, web linje 117) udvides: `hvad === 'hændelse'` →
  vis `klausul` i stedet for født/død-formuleringen; kicker/praecision-logikken uændret.
- Bogmærke-ikonet kommer gratis (`bookmarkPersonId(card) !== null` — eksisterende kontrakt);
  kort-navigation: `arkiv` navigerer til personen (samme handler som portræt-kortet).

- [ ] **Step 1: Implementér views** (ingen unit-test af ren JSX — fase 1-præcedens, task
  10: logikken er allerede testet i motoren).
- [ ] **Step 2: Verificér manuelt:** mobil-simulator + browser mod kopi-base MED seedede
  hændelses-rækker (fra task 1's verify-seed eller en tidlig pipeline-kørsel): arkiv-kort
  renderes med verbatim klausul + kildefod; hændelses-paadennedag viser klausul;
  bogmærke-toggle virker på begge; mod TOM tabel: intet arkiv-kort, ingen fejl i konsollen.
  `npx tsc --noEmit && npm test` (mobil) + `npm run test && npm run build` (web) grønne.
- [ ] **Step 3: Commit** — `feat(feed): arkiv- og haendelses-kort-views mobil+web (skive 4)`.

---

## Task 8: Pipeline-skill — skelet + GDPR-eksport (skive 2)

**Files:**
- Create: `.claude/skills/daa-haendelser/SKILL.md`,
  `references/haendelse-prompt.md`, `references/haendelse-schema.json`,
  `references/vocab.json`, `scripts/export_narratives.R`.

**Interfaces (spec §4, §4.1–§4.2):**
- `SKILL.md`: frontmatter (name/description) + pipeline-oversigt i daa-extract-stilen
  (`.claude/skills/daa-extract/SKILL.md` er skabelonen — trin-diagram, "Hurtig kørsel",
  principper). Tre bevidste forskelle fra arketypen dokumenteres: input er narrativer fra
  DB (ikke PDF), output er `haendelse`-rækker, load er markering-bevarende merge.
- `references/haendelse-prompt.md`: FROSSEN prompt med `<!-- prompt-version: … -->`-header
  (præcis som `extract-prompt.md:1-6`); indhold efter spec §4.2's 6 punkter (klausul-reglen
  BLOKERENDE/verbatim; date_raw verbatim; qualifier fra assertion-vokabularet; kategori fra
  medsendt liste, tvivl → 'andet'; hvad der IKKE er en hændelse; kort status-svar).
  Versionen skrives i `haendelse.pass_version` ved load (proveniens).
- `references/haendelse-schema.json`: draft-07, `additionalProperties: false`
  (R5-mønstret fra `extraction-schema.json`) — kopiér spec §4.2's skema ordret. Bemærk:
  LLM'en leverer ALDRIG `span_start/laengde`, `noegle`, `fact_id/relation_id`.
- `references/vocab.json`: `haendelse_kategori`-listen — SAMME 11 koder som migrationens
  vocab-seed (task 1); én liste, seedet begge steder (som daa-extracts `seed_vocab()`,
  `load_daa.R:212`).
- `scripts/export_narratives.R`: forbinder som loaderne (`~/.Renviron`, session-pooler —
  kopiér forbindelses-preamblen fra `load_daa.R`); kører spec §4.1's query ORDRET
  (GDPR-filtret ligger i queryen: `coalesce(n.privat,false)=false AND p.levende=false AND
  coalesce(p.privat,false)=false AND coalesce(p.staged,false)=false` — fail-closed:
  NULL-levende udelukkes, som `person_offentlig`). Output: én JSON-record pr. narrativ til
  `work/haendelser/narrativer.json`. Scriptet slutter med en HÅRD selvkontrol: gen-query
  af antal narrativer for levende/private/staged personer i output-mængden — ≠ 0 →
  `stop()` (aldrig stole på ét WHERE alene).

- [ ] **Step 1: Implementér** filerne (dokumenter + ét deterministisk DB-script — ingen
  kunstig unit-test-tvang; fase 1-præcedens for ikke-kode-tasks).
- [ ] **Step 2: Verificér mod kopi-basen:** kør eksporten; assert manuelt (psql-tælling):
  antal records = antal person-narrativer minus levende/private/staged/private-narrativer;
  stikprøve et par records for felterne `narrative_id/subjekt_id/source_id/side/tekst/
  udgave/visning_navn`. Bekræft at `work/` er git-ignoreret (mellemformer kan indeholde
  persondata — disciplinen gælder selv om eksporten kun tager afdøde).
- [ ] **Step 3: Commit** — `feat(feed): daa-haendelser-skill — skelet, frossen prompt + GDPR-eksport (skive 2)`.

---

## Task 9: Pipeline — validering H1–H8 (`validate_haendelser.py`) (skive 2)

**Files:**
- Create: `.claude/skills/daa-haendelser/scripts/validate_haendelser.py`,
  `.claude/skills/daa-haendelser/scripts/test_validate_haendelser.py`.

**Interfaces (spec §4.3, §9.1):**
- CLI: `python3 scripts/validate_haendelser.py narrativer.json extracted/ --clean … --review … --escalate …`
  (samme argumentform som `validate.py`; ét blokerende brud → HELE narrativets udtræk i
  `review.json`, loades ikke).
- Reglerne H1–H3 (blokerende: klausul ordret substring; årstal i date_raw findes i
  klausulen; ingen ukendte felter), H4–H6 (deterministisk berigelse: dato-bounds fra
  date_raw+qualifier OVERSKRIVER LLM'ens bud; span som klausulens første endnu-ubrugte
  forekomst — forekomst-indekseret; nøgle jf. §9.1), H7–H8 (advisory: kategori mod
  `references/vocab.json` → ukendt erstattes af 'andet'; ≥N år-tokens men 0 hændelser →
  `escalation.json` — fastlæg N empirisk mod eksport-data, start-bud N=3, dokumentér valget
  i scriptets docstring).
- **Nøglen (§9.1, aldrig af LLM):** `normaliser(klausul)` = NFC → lowercase →
  whitespace-løb → ét mellemrum → trim → første 160 tegn; `noegle` = normaliseret tekst
  + `'#2'/'#3'…` ved identiske klausuler i samme narrativ (forekomst-orden).
- **Dato-parser-genbrug (H4):** daa-extracts kanoniske parser er
  `validate.derive_date_info(date_raw)` (`.claude/skills/daa-extract/scripts/validate.py:451`,
  returnerer `{date_min,date_max,qualifier,certainty,calendar}`) — `escalate_merge.py:9-11`
  importerer allerede `validate` som modul via `sys.path.insert`. Gør det samme på tværs af
  skills: `sys.path.insert(0, <repo>/.claude/skills/daa-extract/scripts); import validate` —
  **verificér i koden at importen er bivirkningsfri** (main-guard); virker det ikke rent,
  udtræk parseren til et delt modul frem for at duplikere (samme kanoniske parser er et mål
  i sig selv).
- **Eskalering (③b):** genbrug driften fra daa-extract §④b (snapshot → Opus-subagent →
  deterministisk re-validering + promotion). **Verificér** om `escalate_merge.py`s
  `decide()`-kerne (promotér kun uden blokerende brud og uden nye advisory-typer) kan
  genbruges parametrisk; ellers skriv en lille pendant `escalate_haendelser.py` med samme
  kriterium (H8-typer i stedet for R8) — dokumentér valget i SKILL.md.

- [ ] **Step 1: Skriv de fejlende tests** (`unittest`, som `test_validate.py`):
  H1: parafraseret/opdigtet klausul → blokerende; typografi-afvigelse → blokerende.
  H2: årstal i date_raw uden forekomst i klausul → blokerende. H3: ekstra felt → blokerende.
  H4: 'ca. 1580' → hele året + 'about' (parserens output overskriver LLM-bud).
  H5: to ens klausuler → to forskellige spans (forekomst-indeksering).
  H6: nøgle-determinisme (samme input → samme nøgler; to ens klausuler → '#2'-suffiks;
  whitespace-/case-varianter → samme nøgle; 160-tegns-trunkering).
  H7: ukendt kategori → advisory + 'andet'. H8: år-rig prosa uden hændelser → escalation.
  Clean/review-partition: ét brud → hele narrativet i review.
- [ ] **Step 2: Kør — verificér FAIL** (`python3 -m unittest discover -s .claude/skills/daa-haendelser/scripts -p 'test_*.py'`).
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør — verificér PASS.** Kør derefter valideringen mod et LILLE reelt
  udtræk (5–10 narrativer gennem prompten) og læs rapporten — sanity, ikke gate.
- [ ] **Step 5: Commit** — `feat(feed): validate_haendelser — H1-H8, span, stabil noegle (skive 2)`.

---

## Task 10: Pipeline — merge-load (`load_haendelser.R`) (skive 2)

**Files:**
- Create: `.claude/skills/daa-haendelser/scripts/load_haendelser.R`,
  `.claude/skills/daa-haendelser/scripts/load_haendelser_helpers.R`,
  `tests/testthat/test-haendelse-merge.R`.

**Interfaces (spec §4.4, §9.2):**
- CLI: `Rscript … load_haendelser.R work/haendelser/clean.json [--dry-run]`. Én transaktion
  (`dbBegin`/`tryCatch`/rollback — `load_daa.R:243`-mønstret); id'er fra `MAX(id)`-sekvens
  (`seed_seq`/`nid`-mønstret, `load_daa.R:84-96`); `--dry-run` printer buffer-tællinger og
  ruller tilbage (`DRY_RUN`-flaget, `load_daa.R:41`). **Ingen `--reset`** — kun kørslens
  narrativer berøres. Loaderen kører UDEN change_set (ingen historik-støj — `log_change`
  no-op'er uden `app.change_set_id`, den eksisterende bulk-load-sti).
- Pr. narrativ (§9.2's 5 trin — kopiér algoritmen derfra): (1) re-verificér klausul mod
  AKTUEL `narrative.tekst` + genberegn span; fejl → skip + `work/haendelser/load-unresolved.csv`
  (aldrig tavst); (2) rygrads-dedup: konservativ match mod personens valgte assertions
  (identisk ikke-NULL `(date_min,date_max)` ELLER identisk normaliseret `date_raw` →
  `fact_id`; tilsvarende relation/`periode_raw` → `relation_id`; ellers NULL — fejl til den
  billige side); (3) nøgle-match → UPDATE af alle regenererbare kolonner, `feed_status`
  røres ALDRIG; (4) ny nøgle → INSERT (default 'kandidat'); (5) forældreløs nøgle:
  'kandidat' → DELETE; markeret → sekundær match (samme kategori + identiske
  `(date_min,date_max)`, præcis ét træf → overfør status) ellers DELETE +
  `work/haendelser/mistede-markeringer.csv` (id, nøgle, status, klausul) + tælle-print.
- Rene helpers i `load_haendelser_helpers.R` (DB-fri, testbare med data frames — sourced
  fra testthat som `test-load-daa.R:6` sourcer `load_helpers.R`):
  `genberegn_span(tekst, klausul, brugte_offsets)`, `match_rygrad(haendelse, valgte_fakta_df,
  relationer_df)`, `plan_merge(eksisterende_df, nye_df)` → liste af
  `{updates, inserts, deletes, overfoerte, mistede}` (sekundær-match-logikken ligger her).

- [ ] **Step 1: Skriv de fejlende tests** (`tests/testthat/test-haendelse-merge.R` —
  DB-service-fri som resten af suiten, kører i det eksisterende `r · testthat`-CI-job):
  `plan_merge`: nøgle-match → update (status urørt i update-settet); ny nøgle → insert;
  forældreløs kandidat → delete; forældreløs markeret + ét sekundær-træf → status
  overført; nul/flere træf → mistet-post; narrativer udenfor input urørte.
  `genberegn_span`: forekomst-indeksering; klausul ikke fundet → NA.
  `match_rygrad`: dato-match → fact_id; date_raw-match; intet match → NA; aldrig match på
  NULL-datoer.
- [ ] **Step 2: Kør — verificér FAIL** (`Rscript run-tests.R`).
- [ ] **Step 3: Implementér** helpers + loader.
- [ ] **Step 4: Kør — verificér PASS.** Derefter mod kopi-basen: (a) `--dry-run` ruller
  rent tilbage (tællinger printes, 0 rækker efter); (b) fuld kørsel over eksporten fra
  task 8 → stikprøve: hver `klausul` er ordret substring af sit narrativ (H1 = 0 brud i
  basen, psql-tjek); (c) **gen-kørsels-testen** (spec §11): markér 2-3 rækker
  interessant/skjult via RPC'en, kør loaderen igen → markeringerne består og rækkernes
  `id` er uændrede (kort-id-stabilitet, §9.3).
- [ ] **Step 5: Commit** — `feat(feed): load_haendelser — markering-bevarende merge + rygrads-dedup (skive 2)`.

---

## Task 11: Redaktion — read/write-lag i begge apps (skive 5)

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts`, `mobile/src/data/redaktionWrite.ts`,
  `mobile/src/data/__tests__/redaktionRead.test.ts`, `…/redaktionWrite.test.ts`.
- Modify: `web/src/data/redaktionRead.ts`, `web/src/data/redaktionWrite.ts`,
  `web/src/data/__tests__/redaktionRead.test.ts`, `…/redaktionWrite.test.ts`.

**Interfaces (spec §7.1–§7.2 — typerne ordret derfra; spejlpar som i dag):**
- Read (begge apps): `HaendelsePost`-typen; `mapHaendelser(rows): HaendelsePost[]` (ren,
  testbar — `mapNarrativer`-mønstret, mobil `redaktionRead.ts:314`, web `:299`);
  `fetchHaendelserForPerson(personId)`: flad query mod `haendelse` med source-titel via
  nest-select gennem narrativet (samme `source:source_id(titel,udgave)`-stil som
  `fetchNarrativer`, mobil `redaktionRead.ts:323-331` — verificér om PostgREST tillader
  `narrative:narrative_id(side,source:source_id(titel))` i ét kald, ellers to flade
  queries). **Fejl KASTER** (redaktions-reglen fra `fetchKonflikter`, mobil
  `redaktionRead.ts:139`: en tavs catch ville skjule en RLS-fejl som "ingen hændelser").
  Redaktion ser også `skjult` (redaktion_read-politikken fra task 1).
- `buildTidslinje(haendelser: HaendelsePost[], evidens: PersonEvidence): TidslinjePost[]`
  (ren helper, én pr. app som `joinEvidence`, mobil `redaktionRead.ts:86`/web `:85`):
  fletter hændelser med daterede rygradsfakta fra det allerede-hentede `PersonEvidence`
  (mobil `redaktionRead.ts:77`/web `:76` — INGEN ekstra queries); rygradsposter markeres
  `art:'rygrad'`; hændelser med `factId` kobles til deres fakta-post frem for at dubleres;
  sortering `date_min`, NULL sidst, stabil id-tiebreak. Definér `TidslinjePost` i samme fil.
- Write (begge apps): `Change`-unionen (mobil `redaktionWrite.ts:14-44`, web `:14-46`)
  udvides med `art: 'haendelseStatus'` + felterne `haendelseId: number` og
  `status: 'kandidat' | 'interessant' | 'skjult'` (følg unionens flade felt-stil);
  `buildRpcCall` (mobil `:53`, web `:54`) mapper til
  `{ fn: 'red_set_haendelse_status', args: { p_haendelse_id, p_status } }`. Dermed er
  dry-run/LIVE gratis (`submitChange` mobil `:296`, web `:282`); webs `planCall`-routing
  (web `redaktionWrite.ts:272`) degraderer ikke-redaktører til `red_suggest` uændret.

- [ ] **Step 1: Skriv de fejlende tests:** `mapHaendelser` (rå rækker → poster; skjulte
  medtages; NULL-felter); `buildTidslinje` (fletning; `factId`-kobling frem for dublet;
  NULL-dato sidst; stabil orden); `buildRpcCall`-caset (gyldigt kald; manglende
  haendelseId → null) — i BEGGE apps' eksisterende suiter (jest hhv. vitest).
- [ ] **Step 2: Kør — verificér FAIL** (begge apps).
- [ ] **Step 3: Implementér** (read + write, begge apps).
- [ ] **Step 4: Kør — verificér PASS**; mobil `tsc` + web `build` grønne.
- [ ] **Step 5: Commit** — `feat(feed): redaktions-read/write for haendelser — tidslinje-join + haendelseStatus-change (skive 5)`.

---

## Task 12: Redaktion — tidslinje-UI i begge apps (skive 5)

**Files:**
- Create: `mobile/src/components/redaktion/HaendelseTidslinje.tsx`.
- Modify: `mobile/src/app/redaktion/person/[id].tsx`, `web/src/Redaktion.tsx`.

**Regler (spec §7.3–§7.4):**
- **Web** (`Redaktion.tsx`): ny sektion i `renderPersonEditor` (linje 625) —
  `sectionHeader('Hændelser · tidslinje fra prosaen')` indsat EFTER Kerne-fakta-sektionen
  (`sectionHeader(22)`-blokken linje 662) og før 'Narrativ · biografi' (linje 684) —
  spec'ens "mellem Kerne-fakta og familie-relationer". Én række pr. `TidslinjePost`:
  dato-label (verbatim `dato.raw` foretrukket) · klausul som citat · kategori-badge ·
  kildefod (`sourceTitel, side` — `kildeAf`-mønstret, linje 73) · status-vælger.
  Status-vælgeren genbruger KONF-pille-mønstret (linje 973-991: konstant-array + aktiv
  pille markeret): tre piller kandidat/interessant/skjult, klik →
  `run({ art: 'haendelseStatus', subjektType: 'person', subjektId: id, haendelseId,
  status }, 'Feed-status')` — `run`-wrapperen (linje 393-412) giver dry-run-preview +
  re-load efter LIVE uændret. Rygrads-poster (`art:'rygrad'`) viser INGEN status-vælger.
- **Klausul-i-kontekst (web, bevidst minimal MVP):** klik på klausulen scroller til
  narrativ-sektionen, vælger den rette udgave-fane, og sætter selektionen via det
  eksisterende `narrativTextareaRef`-mønster (ref linje 131, textarea linje 728;
  `focus()` FØR `setSelectionRange` — samme mekanik som `insertNarrativToken`,
  linje 289-297): `setSelectionRange(spanStart, spanStart + spanLaengde)`. Span driftet →
  fallback `tekst.indexOf(klausul)`; klausul slet ikke fundet → stille notits "klausul
  ikke længere i narrativet — gen-kør hændelses-passet". Rig inline-highlight i
  `NarrativRenderer` er IKKE i scope (verificeret: ingen span-highlight-mekanisme findes).
- **Mobil:** `HaendelseTidslinje.tsx` efter `FaktaKort`-arkitekturen
  (`FaktaKort.tsx:17`: egen fold-state, rapporterer via callback, kalder ALDRIG selv
  write-laget): props `{ poster: TidslinjePost[]; onSetStatus: (haendelseId, status) => void }`.
  Statuspiller i `personEditorSheetStyles.koenPille`/`koenPilleAktiv`-stilen (som
  køn-vælgeren, `[id].tsx:336`). Monteres i `mobile/src/app/redaktion/person/[id].tsx`
  ved fakta-sektionen (FaktaKort-listen komponeres omkring linje 278 — verificér den
  præcise sektions-rækkefølge i filen og spejl webbens placering efter kernefakta);
  `onSetStatus` bygger `Change` og sender gennem det eksisterende
  `SkrivePreviewSheet`-flow (`[id].tsx:575-580` — sheeten kalder selv `buildRpcCall`/
  `submitChange` og re-fetcher evidens efter LIVE; hæng en hændelses-refetch på samme
  `onApplied`). Data: `fetchHaendelserForPerson` hentes ved siden af
  `fetchPersonEvidence` (`[id].tsx:62`-mønstret).

- [ ] **Step 1: Implementér web-sektionen** (ingen unit-test af ren JSX — logikken bor i
  task 11's testede helpers; fase 1-præcedens task 10).
- [ ] **Step 2: Implementér mobil-komponenten + montering.**
- [ ] **Step 3: Verificér manuelt mod kopi-basen** (dry-run FØRST — projektets etablerede
  mønster): tidslinjen viser hændelser + rygrad flettet kronologisk; skjulte er synlige
  for redaktionen med markering; pille-klik viser dry-run-preview med
  `red_set_haendelse_status`-kaldet; LIVE-skriv slår igennem (interessant-boost/skjult-væk
  i feed'en efter reload — task 6's scoring) og er fortrydbar i historikken (ét pænt
  change_event med kun `{id, feed_status}`); klausul-klik hopper til narrativet og
  markerer spanet; driftet span falder pænt tilbage. Ikke-redaktør-login på web →
  pille-klik degraderer til `red_suggest`-staging. `tsc`/suiter grønne i begge apps.
- [ ] **Step 4: Commit** — `feat(feed): redaktionens haendelses-tidslinje mobil+web med status-piller (skive 5)`.

---

## Task 13: CI + afstemning (skive 6)

**Files:**
- Modify: `.github/workflows/ci.yml`, `docs/changelog.md`, `docs/README.md`.

- [ ] **Step 1: Nyt CI-job `pipeline · unittest`** i `ci.yml` ved siden af `r`-jobbet
  (jobs-listen er i dag `core`/`feed`/`r`/`web`/`mobile`): checkout + `python3 -m unittest
  discover -s .claude/skills/daa-haendelser/scripts -p 'test_*.py'` — INGEN npm-steps
  (mønster: `r`-jobbet, der heller ikke installerer node). Kun den nye skills tests gates;
  daa-extracts `test_*.py` hægtes IKKE på blindt (de har aldrig været CI-gatet — verificér
  dem grønne separat før en evt. senere udvidelse). Verificér at
  `tests/testthat/test-haendelse-merge.R` allerede kører i `r · testthat`-jobbet
  (`run-tests.R` kører hele `tests/testthat/`).
- [ ] **Step 2: Fuld verifikation:** `packages/feed` vitest+tsc, `packages/core` vitest,
  mobil `tsc`+jest, web vitest+build, `Rscript run-tests.R`, pipeline-unittest — alt grønt
  lokalt og i CI.
- [ ] **Step 3: Afstemning:** `docs/changelog.md`-implementeringspost (hvad er testet vs.
  manuelt verificeret — inkl. gen-kørsels-testen fra task 10 og RLS-asserts fra task 1);
  statuslinje i `docs/README.md`s design-sektion ("fase 2 implementeret") + indeksering af
  den nye skill; notér i `docs/design/2026-07-18-levende-feed-koncept.md` §10 at fase 2 er
  implementeret (spec-linket findes allerede). `docs/database-current-state.md` røres IKKE
  endnu — den opdateres først ved den gatede prod-migrering (Global Constraints).
- [ ] **Step 4: Commit** — `chore(feed): CI-job for pipeline-tests + fase 2-afstemning (skive 6)`.

---

## Verifikation (afsluttende, spec §11)

- [ ] Migrationen idempotent (to kørsler = én); db-verify grøn mod kopi-base: skjulte/
  levende/private hændelser usynlige for anon+authenticated, redaktion ser alt, CHECK og
  RPC-gates afviser, status-fortryd virker.
- [ ] Pipeline kørt over kopi-basens narrativer: hver klausul ordret i sit narrativ (H1=0
  brud i clean); gen-kørsel oven på markerede rækker bevarer alle `feed_status ≠ 'kandidat'`
  (eller logger i mistede-markeringer.csv); `--dry-run` ruller rent tilbage; ingen
  levende/private/staged i eksporten (hård selvkontrol).
- [ ] Feed'en viser arkiv-kort med verbatim klausul + kildefod; citat fra klausuler med
  heuristikken kun som fallback; paadennedag bærer hændelser — alt deterministisk pr.
  seed+dato (vitest), og med tom `haendelserBy` er ordningen dybt identisk med fase 1.
- [ ] Redaktøren ser komplet flettet tidslinje, hopper til klausulen, sætter status med
  dry-run-preview; markeringen slår igennem i feed'en og er fortrydbar i historikken.
- [ ] Alle suiter + nyt pipeline-CI-job grønne; diffen rører ingen evidenstabel-DDL
  (fact/assertion/conclusion/citation/narrative-blokkene i `schema.sql` uændrede — kun
  additivt skema + nye læsninger).

## Self-review-noter (udført ved skrivning)

- **Spec-dækning:** §3 → task 1; §4 → task 8–10; §5 → task 2–4; §6 → task 5–7; §7 → task
  11–12; §8 → task 13; §9 → task 9 (nøgle) + 10 (merge) + 1 (versionering). Alle
  spec-testkrav (§3.6, §4.3-tests, §5.3, §6.4, §7.5) er fordelt på tasks. Kort-views
  (task 7) står ikke i spec'ens skive-tabel men følger af succeskriteriet "feed'en viser
  arkiv-kort" — placeret i skive 4.
- **Bevidste implementer-verifikationer** (markeret i tasks — slå efter i koden frem for
  at gætte): exists-cascadens ydelse ved ~10k rækker + EXPLAIN (task 1); cross-skill-import
  af `validate.derive_date_info` (task 9); `escalate_merge.decide`-genbrug vs. pendant
  (task 9); H8-tærsklen N fastlægges empirisk (task 9); nested PostgREST-select gennem
  `narrative_id` (task 11); den præcise sektions-placering i mobilens person-editor
  (task 12); payload-måling på klienten (spec §10: >2,5 MB → server-filtreret hentning bag
  samme loader-kontrakt — mål ved task 4's manuelle verifikation, log længden én gang).
- **Verificerede spec-formodninger:** webbens mount-orkestrering bor i
  `web/src/components/feed/FeedStreamView.tsx` (ikke `Folgesvend.tsx` som spec §5.2
  formodede); kort-views bor i `mobile/src/components/feed/FeedCardView.tsx` +
  `web/src/components/feed/FeedCardView.tsx` (switch-baserede); mobilens preview-flow er
  `SkrivePreviewSheet` der selv kalder `submitChange`.
- **Rettelse efter selvstændig efterverifikation (uafhængig af skrive-agenten):**
  versionerings-infrastrukturen (`version_pk_registry` + den generiske trigger-
  tilknytnings-loop) findes i BÅDE `schema.sql` (`1751-1770` hhv. `1888-1896`) OG
  `db-migrations.sql` (`802-831` hhv. `945-952`) — den oprindelige plan-tekst påstod
  fejlagtigt at den kun lå i migrationsfilen. De to filer kræver derfor FORSKELLIG
  håndtering i task 1 (se Files/Interfaces/Step 3-4 dér): schema.sql får kun en ny linje i
  den eksisterende `VALUES`-liste (loopet tilknytter triggeren selv); db-migrations.sql får
  sin egen `INSERT … ON CONFLICT` PLUS en eksplicit `CREATE TRIGGER trg_log_haendelse`, fordi
  dens generiske loop allerede er kørt færdig når den nye dateret sektion appendes. Uden
  denne rettelse ville en frisk clean-slate-deploy (`schema.sql` alene) mangle
  `trg_log_haendelse` — `red_set_haendelse_status`-writes ville stille ikke blive
  historik-logget på nye miljøer, selvom kopi-base-verifikationen (kørt mod en allerede
  migreret base) ville se grøn ud.
- **Kendt afvigelse fra spec'ens skive-inddeling:** `FeedInputs.haendelserBy` tilføjes i
  task 2 (skive 3) frem for skive 4, så loader-wiring kan lande med grøn `tsc` — feltet er
  no-op indtil task 5–6 og adfærden er uændret (regressionstestet i task 6).
- **DELETE-fortrydelse mod skip_cols-tabellen er eksplicit uunderstøttet** (kun loaderen
  sletter, uden change_set) — dokumenteret i task 1's skema-kommentar og bekræftet ved at
  fortryd-asserten kun øver UPDATE-stien.
