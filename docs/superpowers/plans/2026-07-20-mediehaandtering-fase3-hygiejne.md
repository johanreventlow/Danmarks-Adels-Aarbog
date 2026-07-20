# Mediehåndtering — fase 3: hygiejne (dedup, sha-stier, janitor) · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dedup-mekanismen går fra død til aktiv (M8): klienten beregner sha256 af de
genkodede large-bytes, stier bliver deterministiske (`redaktor/<xx>/<sha>-{tier}.jpg`)
og upload idempotent; dubletter mødes som en hjælp ("Billedet findes allerede → tilknyt
i stedet"), strandede kladder kan genoptages selvhelende; biblioteket får alder på
strandede og en "Mulige dubletter"-kø (kø 5) med blødt flet-flow; et forsigtigt
janitor-R-script rapporterer og (kun med eksplicit flag) rydder affald (M9's oprydning).

**Architecture:** Lille additiv DDL (`media.created_at` to-trins + partielt unikt
`afbildet`-index med evidens-sikker oprydning + `unique_violation`-oversættelse i
`red_relation`) — ellers app-lag: ny ren `mediaPaths.ts` pr. platform (hash/sti-bygning,
"hold i sync"), omlagt `buildVariants` (tiers → hash → stier), duplicate-tolerant
`performUpload`, pre-flight-sha-opslag i upload-arkene, `p_sha256` gennem `buildRpcCall`,
læse-lags-udvidelser (createdAt + dublet-heuristik) og et selvstændigt ops-script
`R/media-janitor.R` (DBI/RPostgres + httr2, service_role). Ingen RLS-ændringer.

**Tech Stack:** PostgreSQL/Supabase (én migrationsblok, eksisterende guard/index),
TypeScript, React/Vite + vitest (web, node-miljø med nativ Web Crypto), RN/Expo + jest
(mobile, ny dependency `expo-crypto`), R (DBI/RPostgres, httr2, digest, testthat).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-20-mediehaandtering-fase3-hygiejne-design.md` (autoritativ; §-referencer nedenfor peger dertil)
- Koncept: `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` (§4.2 kø 5, §4.6, §9 fase 3, §10.1–3)
- Kortlægning (fil:linje verificeret på denne branch 2026-07-20 — spec'ens `redaktionWrite.ts`-ankre er forskudt ~7 linjer af fase 2's `tilknytMedia`-gren, resten uændrede): tilfældige stier + `upsert:false` (`web/src/data/mediaUpload.ts:18-21,74-80`, `mobile/src/lib/mediaUpload.ts:51-54,98-106`); HEIC-begrænsning (`web/src/data/mediaUpload.ts:26-35`, urørt); DB-guard + index (`schema.sql:79,89,1885-1887`), `p_sha256` i `red_bekraeft_media_upload`/`red_upload_media` (`schema.sql:1900,1922`); `red_relation` INSERT'er blindt (`schema.sql:1187-1208`), `relation` uden unikhed (`schema.sql:354-367`), `_delete_relation_evidence`s FK-orden (`schema.sql:1214-1227`); web `buildRpcCall`-uploadMedia uden `p_sha256` (`redaktionWrite.ts:316-332`), `submitChange`-upload-flow (`:453-492`), `oversaetFejl` (`:495-504`); upload-ark (`web/src/Redaktion.tsx:1244-1253`, `MediaUploadSheet.tsx:75`); læse-lag (`web/src/data/redaktionRead.ts:745,778-793,814-841,843-863`; mobile `:732-`, `mapMediaBibliotekRows :773`); `expo-crypto` IKKE installeret (`mobile/package.json:5-44`); R-præcedenser (`.claude/skills/daa-extract/scripts/load_daa.R:67-71`, `R/geo-enrich/03-geocode.R:12,18,42`, `tests/testthat/test-geo-enrich.R`); vitest node-miljø (`web/vitest.config.ts:6`)
- **Prod-status (VIGTIG afvigelse fra spec'ens §2/§8-formulering, verificeret):** fase 1+2-migrationerne + hele `db-rls.sql` gik LIVE i prod 2026-07-20 (changelog-top-entry, commit `2eb4a8c` — EFTER spec-commit `b8e7fd1`). "Samles med de udestående fase 1+2-migrationer" er derfor overhalet: fase 3-migrationen deployes ALENE i sin egen gated runbook — se Task 10.

## Global Constraints

- **Prod røres ALDRIG af denne plan.** Al DDL verificeres kun mod lokal Postgres
  (frisk `schema.sql`-install + migrationssti ×2). Prod-deploy er et separat,
  controller-gated trin (backup + bruger-OK) EFTER planen — se Task 10. Janitorens
  første kørsel mod noget ikke-lokalt er rapport-only og gennemgås med brugeren.
- **CI-hygiejne (læring fra fase 1-kørslen):** INGEN ændringer af `.github/workflows/`
  ud over evt. at holde eksisterende jobs grønne; ALDRIG `contents: write`, ALDRIG
  jobs der committer tilbage til branchen. Alle commits laves som almindelige commits
  af implementøren selv, så den normale testsuite kører på den endelige HEAD.
- **Web/mobile-lagene er bevidst duplikeret** — `mediaPaths.ts`, `mediaUpload.ts`,
  `redaktionRead.ts` og `redaktionWrite.ts` ændres ens begge steder ("hold i sync"-
  headerkontrakten; `mediaPaths.ts` fødes med samme kontrakt i sin header).
  Delt-pakke-ekstraktion er fortsat follow-up og må ikke ske her.
- **Sha er af de GENKODEDE large-bytes, ikke kildefilen** (spec §4.1) — det er dét,
  der ligger i Storage og på media-rækken. Konsekvens: dedup fanger samme-pipeline-
  genupload, IKKE web-vs-mobile af samme motiv (to genkodere → forskellige bytes).
  Ingen task må "forbedre" dette til kildefil-hash — det ville bryde sti-determinismen.
- **Oprydnings-DELETE'en før det partielle index skal være evidens-sikker** (spec §3.2):
  kun dublet-rækker UDEN assertion/conclusion/note må slettes; overlever en
  evidens-bærende dublet, SKAL `CREATE UNIQUE INDEX` fejle højlydt (manuel afgørelse
  frem for stille evidens-tab). Ingen "fiks" der sletter bredere.
- **Janitoren er rapport-first:** default rører INTET; destruktion kræver eksplicit
  `--slet` (kun kategori a+b, kun fund ældre end fristen) hhv. `--backfill-sha`;
  rækker med `created_at IS NULL` slettes ALDRIG (spec §7). Samme "glemt flag må
  ikke destruere"-forsigtighed som `load_daa.R`/TNG-QA.
- **Spec'ens åbne punkter (§9) er skøn, ikke afgørelser:** `--frist-dage`-default **7**
  og "muligvis i gang"-grænsen **1 time** bruges som standardværdier her, men markeres
  "bekræft ved implementering" (§9.1); `expo-crypto` er default-valget, med
  `@noble/hashes` som godkendt substitut hvis dev-client-genbygning viser sig at være
  friktion (§9.5 — beslutningen må tages i Task 5 uden spec-ændring, dokumentér valget).
- **HEIC på web er IKKE i scope** (spec-header): `web/src/data/mediaUpload.ts:26-35`
  forbliver ordret uændret.
- **Ingen nye farver/fonte:** web styler fra `theme.ts`-tokens/`primitives.tsx`;
  mobile fra `mobile/src/theme/tokens.ts` + `Typography`. Dialog-/kø-UI genbruger
  eksisterende chip-/sheet-mønstre.
- Hver task holder relevant suite grøn: web → `cd web && npx tsc --noEmit && npm run
  test && npm run build`; mobile → `cd mobile && npx tsc --noEmit && npm test`;
  DB → frisk install + verify-filer mod lokal Postgres; R → `Rscript run-tests.R`.
- Commit-beskeder på dansk, `feat(media): …`-stil; brug din egen sessions
  Claude-Session-footer.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql`, `db-verify.sql`, `db-verify-media.sql` | `media.created_at` + `relation_afbildet_uidx` + `unique_violation`-fangst i `red_relation`; asserts | 1 |
| `db-migrations.sql` | Idempotent blok `mediehaandtering_fase3_hygiejne` (to-trins ALTER + evidens-sikker DELETE + index) | 2 |
| NY `web/src/data/mediaPaths.ts` (+ test), `web/src/data/mediaUpload.ts` | `hexEncode`/`buildShaStoragePaths`; `sha256Hex`, omlagt `buildVariants`, duplicate-tolerant `performUpload` | 3 |
| `web/src/data/redaktionWrite.ts` (+ test), `web/src/Redaktion.tsx` | `p_sha256` i buildRpcCall, `oversaetFejl`-grene, pre-flight-dedup-dialog + genoptag-kladde | 4 |
| NY `mobile/src/lib/mediaPaths.ts` (+ test), `mobile/src/lib/mediaUpload.ts`, `mobile/package.json` | Spejl af Task 3 via `expo-crypto ~56.x` | 5 |
| `mobile/src/data/redaktionWrite.ts` (+ test), `mobile/src/components/redaktion/MediaUploadSheet.tsx` | Spejl af Task 4 (forenklet dialog-UI, fuld funktionalitet) | 6 |
| `web/src/data/redaktionRead.ts` (+ test), `mobile/src/data/redaktionRead.ts` (+ test) | `createdAt`-felt, `formatMedieAlder`, dublet-heuristik, `klassificerMedie`+`'dubletter'` | 7 |
| `web/src/Redaktion.tsx`, `web/src/components/MediaDetaljeOverlay.tsx` | Strandede-alder/sortering, dublet-kø-chip, "Flet ind i…"-flow | 8 |
| NY `R/media-janitor.R`, NY `tests/testthat/test-media-janitor.R` | Rapport/`--slet`/`--backfill-sha`-janitor, kategori a–d | 9 |
| `docs/changelog.md`, `docs/database-current-state.md`, koncept-§9-tabellen | Afstemning + prod-runbook-note | 10 |

Afhængigheder (spec §2): Task 1–2 er forudsætning for 7 (createdAt i læse-laget) og 9
(janitorens aldersbegreb); 3–4 og 5–6 er indbyrdes uafhængige platform-spejlinger;
7 er forudsætning for 8; 9 kan bygges parallelt med 3–8.

---

## Task 1: DB — `created_at` + `afbildet`-unikhed i `schema.sql` + asserts

**Files:**
- Modify: `schema.sql` (media-tabellen `:64-87`, index-blokken `:88-89`, `red_relation` `:1187-1208`)
- Modify: `db-verify.sql` (nye DO-blokke, fase 1 Task 5-mønsteret: impersonering + `ROLLBACK_TEST_OK`)
- Modify: `db-verify-media.sql` (filens kontrakt: `SET LOCAL ROLE`/direkte seed-DML, INGEN redaktør-RPC'er)

**Interface (spec §3.1–3.2):**
```sql
-- schema.sql (frisk install): direkte i CREATE TABLE media
created_at timestamptz DEFAULT now(),   -- fase 3: aldersbegreb for strandede uploads (NULL = ukendt, præ-fase-3)

-- schema.sql: efter media_sha256_uidx
CREATE UNIQUE INDEX IF NOT EXISTS relation_afbildet_uidx
  ON relation (subjekt_type, subjekt_id, objekt_type, objekt_id)
  WHERE rolle='afbildet';
```
`red_relation` (`schema.sql:1203-1206`): INSERT'en wrappes i blok med
```sql
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Mediet er allerede tilknyttet dette subjekt';
```
(eneste unique-index på `relation` er det partielle afbildet-index, så fangsten er
entydig; domæne-fejl frem for rå duplicate-key, spec §3.2 sidste punkt).
Frisk-install-skemaet indeholder INGEN oprydnings-DELETE (tom base) — den hører
udelukkende til migrationsblokken (Task 2).

- [ ] **Step 1: Skriv de fejlende asserts.**
  - `db-verify-media.sql` (ny DO-blok, seed negative id'er + ryd op i én transaktion):
    (a) direkte INSERT af media-række uden `created_at` → assert `created_at IS NOT NULL`
    (default-udfyldt) og at kolonnen er NULL-bar; (b) direkte INSERT af to identiske
    `afbildet`-relationer → forvent `unique_violation`; (c) to identiske `'ejer'`-rækker
    → skal LYKKES (partial-indexets negative kontrakt, spec §3.2).
  - `db-verify.sql` (impersonerings-blok): `red_upload_media` med `p_sha256` → assert
    sha landede på rækken og `created_at` er sat; gentaget kald samme sha → forvent
    dedup-guardens domæne-fejl (`schema.sql:1885-1887`); `red_relation` med dublet-
    afbildet → forvent 'Mediet er allerede tilknyttet dette subjekt'.
- [ ] **Step 2: Kør mod frisk lokal install** — bekræft at de nye blokke FEJLER
  (kolonne/index/fangst findes ikke; `red_relation`-dubletten går stille igennem).
- [ ] **Step 3: Implementér** kolonnen, indexet og `unique_violation`-fangsten i
  `schema.sql` jf. Interface.
- [ ] **Step 4: Frisk install + fuld verify** — nye blokke grønne, eksisterende
  `db-verify.sql`-/`db-verify-media.sql`-blokke uden regression (kendt begrænsning:
  den generelle fils ældre tom-base-fixture, jf. fase 2-planens Task 1-note).

## Task 2: DB — migrationssti (`mediehaandtering_fase3_hygiejne`)

**Files:**
- Modify: `db-migrations.sql` (ny navngiven blok, filens etablerede idempotens-mønster)

**Interface (spec §3.1–3.2, verbatim styringsgrundlag):**
```sql
-- (1) created_at TO-TRINS — ⚠ ét-trins ADD COLUMN … DEFAULT now() ville udfylde ALLE
-- eksisterende rækker med migrations-tidspunktet (fast-default-stien); to-trins giver
-- gamle rækker NULL (= ærligt "ukendt alder") og nye rækker now(). Ingen backfill.
ALTER TABLE media ADD COLUMN IF NOT EXISTS created_at timestamptz;
ALTER TABLE media ALTER COLUMN created_at SET DEFAULT now();

-- (2) EVIDENS-SIKKER oprydning FØR index (behold laveste id; rør ALDRIG rækker med
-- assertion/conclusion/note — fail-loud hvis en evidens-bærende dublet overlever):
DELETE FROM relation r USING relation r2
 WHERE r.rolle='afbildet' AND r2.rolle='afbildet' AND r.id > r2.id
   AND r.subjekt_type=r2.subjekt_type AND r.subjekt_id=r2.subjekt_id
   AND r.objekt_type=r2.objekt_type   AND r.objekt_id=r2.objekt_id
   AND NOT EXISTS (SELECT 1 FROM assertion  a WHERE a.target_type='relation' AND a.target_id=r.id)
   AND NOT EXISTS (SELECT 1 FROM conclusion c WHERE c.target_type='relation' AND c.target_id=r.id)
   AND NOT EXISTS (SELECT 1 FROM note       n WHERE n.target_type='relation' AND n.target_id=r.id);

-- (3) CREATE UNIQUE INDEX IF NOT EXISTS relation_afbildet_uidx … WHERE rolle='afbildet';
-- (4) CREATE OR REPLACE FUNCTION red_relation(…) — verbatim fra schema.sql (Task 1;
--     samme signatur → ingen overload-/grant-problem, jf. fase 1's DROP-læring).
```
`trg_log_media` snapshotter `created_at` automatisk (jsonb-rækkesnapshot) — ingen
versioneringsændring (spec §3.1).

- [ ] **Step 1: Skriv migrationsblokken** jf. Interface (DELETE+CREATE INDEX er
  tilsammen idempotente: andet gennemløb finder ingen dubletter og `IF NOT EXISTS`
  springer indexet over).
- [ ] **Step 2: Migrationssti-test lokalt** — frisk install af FØR-tilstanden (git
  checkout af `schema.sql` fra HEAD før Task 1), seed: (a) media-række (skal ende med
  `created_at IS NULL` — fanger fast-default-fælden), (b) evidens-fri afbildet-dublet
  (skal forsvinde), (c) evidens-bærende afbildet-dublet i en SEPARAT prøvekørsel
  (migrationen skal da fejle højlydt på CREATE INDEX — verificér, fjern seed igen).
  Kør `db-migrations.sql` **to gange** (idempotens), så `db-rls.sql` + hele Task 1-
  assert-sættet — alt grønt, og flade identisk med frisk install.

## Task 3: Web — `mediaPaths.ts` + sha256 + idempotent upload (rene funktioner)

**Files:**
- Create: `web/src/data/mediaPaths.ts`
- Create: `web/src/data/__tests__/mediaPaths.test.ts`
- Modify: `web/src/data/mediaUpload.ts`

**Interface (spec §4.1):**
```ts
// mediaPaths.ts — REN (netværks-/DOM-fri), spejles tegn-for-tegn på mobile (Task 5)
export function hexEncode(bytes: Uint8Array): string
export function buildShaStoragePaths(sha: string): Record<MediaTier, string>
// → redaktor/<sha[0..2]>/<sha>-{thumb|medium|large}.jpg  (to-tegns shard, Commons-
//   mønsteret; kompatibelt med bulk-importens tiltænkte import/<xx>/<sha>-form)

// mediaUpload.ts
export async function sha256Hex(blob: Blob): Promise<string>
// crypto.subtle.digest('SHA-256', await blob.arrayBuffer()) — secure context OK
// (localhost-dev + https-prod). buildVariants omlægges: genkod tre tiers FØRST (uden
// stier) → hash large-blobbens bytes → tildel stier via buildShaStoragePaths.
// Returtypen udvides med sha256. buildStoragePathBase() (:18-21) SLETTES.
// performUpload: behold upsert:false, men "The resource already exists"/409-Duplicate
// behandles som SUCCES — på en sha-sti beviser kollisionen at identiske bytes ligger
// der (write-once består; afbrudte forsøg kan genoptages uden at strø objekter).
```

- [ ] **Step 1: Skriv fejlende vitest-cases** (node-miljø, nativ Web Crypto —
  intet mock, spec §1/§4.3): `hexEncode` mod faste byte→hex-vektorer;
  `buildShaStoragePaths` mod fast sha (præfix = to første hex-tegn, alle tre tiers,
  `.jpg`-suffiks); `sha256Hex` mod NIST-vektoren (tom input → `e3b0c442…`) og mindst
  én ikke-tom kendt vektor; `buildVariants`-omlægningens sti-tildeling som ren
  funktion hvor det er praktisk (canvas-delen forbliver utestet browser-glue).
- [ ] **Step 2: Implementér** — ny fil + omlægning jf. Interface; duplicate-tolerant
  `performUpload` (match på Supabase-fejlens `statusCode`/`error === 'Duplicate'` og
  besked-teksten — begge, defensivt).
- [ ] **Step 3: Verifikation** — `cd web && npx tsc --noEmit && npm run test && npm run build`.

## Task 4: Web — skrive-lag + dedup-UX (pre-flight, genoptag, fejltekster)

**Files:**
- Modify: `web/src/data/redaktionWrite.ts` + `web/src/data/__tests__/redaktionWrite.test.ts`
- Modify: `web/src/Redaktion.tsx` (upload-arket `:1244-1253`)

**Interface (spec §4.2):**
```ts
// buildRpcCall, uploadMedia-grenen (:316-332): payload udvides med sha256 →
args.p_sha256 = p.sha256 ?? null;
// red_bekraeft_media_upload behøver den IKKE igen (guarden fyrer FØR rækken oprettes).

// oversaetFejl (:495-504) — nye grene FØR den generiske /duplicate key|unique/-fallback:
/medie med samme indhold findes allerede/i
  → "Billedet findes allerede i biblioteket — brug 'Tilknyt eksisterende' i stedet."
/allerede tilknyttet dette subjekt/i
  → "Mediet er allerede tilknyttet dette subjekt."
```
**Pre-flight (UX-laget, upload-arket):** efter `buildVariants` (sha kendt, INTET
uploadet endnu) slås sha op: `supabase.from('media')
.select('id,titel,upload_status,storage_path').eq('sha256', sha)` (redaktionen ser alt
via `redaktion_read`). Ved hit vises dialog i stedet for upload, forgrenet på
`upload_status` (spec §4.2.1):
- `'klar'`: "Billedet findes allerede" + thumb/titel + knap **"Tilknyt til [subjekt]
  i stedet"** → fase 2's `tilknytMedia`-change mod det aktuelle subjekt.
- `'fjernet'`: besked om papirkurven + link til filsiden (genopret dér — ingen
  auto-genopret fra upload-arket).
- `'kladde'`: **"Færdiggør afbrudt upload"** — re-upload bytes (idempotent, Task 3),
  kald `red_bekraeft_media_upload` + `red_registrer_media_variant` pr. tier mod den
  EKSISTERENDE række, og tilknyt om nødvendigt (selvhelende for samme-fil-tilfældet).
Server-guarden forbliver race-bagstopperen; race-tilfældets bytes ligger på vinderens
egen sha-sti (samme sha → samme sti) — intet orphan (spec §4.2.2).

- [ ] **Step 1: Skriv fejlende vitest-cases** — `buildRpcCall` med `sha256` i payload
  → `p_sha256` i args (og `null` når fraværende); begge nye `oversaetFejl`-grene
  (inkl. at de vinder over den generiske unique-fallback); genoptag-kladde-hjælperens
  kaldsekvens som ren funktion, hvis den faktoreres testbart (ellers dækkes den af
  Step 3's manuelle flow — dokumentér valget i testfilen).
- [ ] **Step 2: Implementér** payload/args, fejlgrene, pre-flight-opslag + dialogens
  tre grene i upload-arket (genbrug eksisterende overlay-/knap-mønstre; ingen nye
  tokens).
- [ ] **Step 3: Verifikation** — suite grøn + browser-røgtest mod lokal/dev: upload
  samme fil to gange → anden gang stopper pre-flight med tilknyt-tilbud; afbryd en
  upload efter bytes (dev-tools) → "Færdiggør afbrudt upload" fuldfører uden ny række
  eller nyt objekt.

## Task 5: Mobile — `expo-crypto` + `mediaPaths.ts` + upload-omlægning

**Files:**
- Modify: `mobile/package.json` (`npx expo install expo-crypto` → `~56.x`)
- Create: `mobile/src/lib/mediaPaths.ts`
- Create: `mobile/src/lib/__tests__/mediaPaths.test.ts` (eller under `mobile/src/data/__tests__/` — følg jest-opsætningens fund-mønster)
- Modify: `mobile/src/lib/mediaUpload.ts`

**Interface (spec §5):** `mediaPaths.ts` er tegn-for-tegn spejl af web-udgaven
(Task 3) — jest-testbar, ingen native imports. I `mediaUpload.ts`: hash via
`Crypto.digest(CryptoDigestAlgorithm.SHA256, bytes)` på `readFileBytes(large.uri)`
(`:43-46` genbruges — large-filen læses alligevel til upload); `buildVariants`
omlægges som web (tiers → hash af large-bytes → sha-stier; returtype + `sha256`);
`buildStoragePathBase` (`:51-54`) slettes; `performUpload` gøres duplicate-tolerant.
Filen forbliver utestet native-glue per sin egen header-konvention (`:1-3`) — al
testbar logik bor i `mediaPaths.ts`.
⚠ `expo-crypto` er med i Expo Go, men dev-/release-builds skal genbygges — noteres i
PR-beskrivelse + changelog (Task 10). **Bekræft ved implementering (spec §9.5):**
viser genbygningen sig at være friktion, er ren-JS `@noble/hashes` godkendt substitut
med samme kontrakt — dokumentér valget.

- [ ] **Step 1: Skriv fejlende jest-cases** — spejl af Task 3's `hexEncode`/
  `buildShaStoragePaths`-vektorer (identiske forventningsværdier som web-testen:
  det ER sync-kontrakten).
- [ ] **Step 2: Implementér** — dependency, spejlfil, omlægning jf. Interface.
- [ ] **Step 3: Verifikation** — `cd mobile && npx tsc --noEmit && npm test`;
  simulator-røgtest af ét upload (Expo Go/dev-client) — sti i Storage matcher
  `redaktor/<xx>/<sha>-…`-formen.

## Task 6: Mobile — skrive-lag + dedup-UX (spejl af Task 4)

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts` (uploadMedia-grenen `:342`) + `__tests__/redaktionWrite.test.ts`
- Modify: `mobile/src/components/redaktion/MediaUploadSheet.tsx` (`:75`-flowet)

**Interface:** som Task 4 — `p_sha256` i args, samme to `oversaetFejl`-grene
(tegn-for-tegn samme regex/tekster som web), pre-flight-opslag + dialogens tre grene
i sheet'et. Forenklet dialog-UI er ok, men funktionaliteten — tilknyt-i-stedet OG
færdiggør-kladde — skal med (koncept §7: fuld pr.-medie-funktionalitet på mobile;
spec §5 sidste punkt).

- [ ] **Step 1: Skriv fejlende jest-cases** — spejl af Task 4's buildRpcCall-/
  oversaetFejl-cases.
- [ ] **Step 2: Implementér** — hold arg-navne/tekster i sync med web.
- [ ] **Step 3: Verifikation** — tsc + jest; simulator: dublet-upload stoppes med
  tilknyt-tilbud (manuel, som fase 1/2 — ingen UI-driver i repo'et).

## Task 7: Læse-lag begge platforme — alder + dublet-heuristik

**Files:**
- Modify: `web/src/data/redaktionRead.ts` + `__tests__/redaktionRead.test.ts`
- Modify: `mobile/src/data/redaktionRead.ts` + `__tests__/redaktionRead.test.ts`

**Interfaces (spec §6.1–6.2):**
```ts
// media-selects (web :745 og :848 + mobile-spejle) udvides med created_at;
// PersonMedia/MediaBibliotekPost får: createdAt: string | null

export function formatMedieAlder(createdAt: string | null, nu?: Date): string
// null → "ukendt alder"; < 1 time → "under 1 time — muligvis i gang" (grænse er
// skøn, bekræft ved implementering, spec §9.1); ellers dansk relativ alder
// ("3 timer", "5 dage", "3 uger", "2 måneder"). Ren funktion, spejlet + testet.

export type MedieKoe = 'rettigheder' | 'loese' | 'strandede' | 'papirkurv' | 'dubletter';
export function klassificerMedie(m, antalAfbildet, antalMentions,
                                 harDubletKandidat: boolean): MedieKoe[]
// NY 4. parameter (beregnet af kalderen); eksisterende regler ændres IKKE —
// "enhver strandet kladde er værd at se" står ved magt (spec §6.1, INTET aldersfilter).
// dubletter: uploadStatus==='klar' && harDubletKandidat.
```
Heuristikken (spec §6.2, ærlig udgave — sha-dubletter er strukturelt umulige i DB):
`harDubletKandidat` beregnes i `mapMediaBibliotekRows` som "deler `(byte_size, bredde,
hoejde)` — alle tre ikke-NULL — med mindst ét ANDET `klar`-medie". Alle tre felter er
allerede i bibliotekets fetch (nul nye queries). Køen præsenteres som "Mulige
dubletter" — gennemsynskø, ikke dom; to sha-satte medier i samme gruppe er pr.
definition kun perceptuelt mistænkte. **Bekræft ved implementering (spec §9.4):**
støjer trillingen, kan `mime_type` føjes til nøglen — afgøres empirisk, notér valget.

- [ ] **Step 1: Skriv fejlende tests (vitest + jest, spejlet)** — `formatMedieAlder`
  (null/under-1-time/dage/uger + fast `nu`-injektion for determinisme);
  `klassificerMedie` med ny parameter (dublet-kø kun for `klar`; multi-kø sammen med
  fx `rettigheder`; eksisterende cases uændret grønne mod udvidet signatur);
  `mapMediaBibliotekRows`-heuristikken (to klar-medier med samme trilling → begge
  kandidater; NULL-felter → aldrig kandidat; `kladde`/`fjernet` tæller ikke med;
  `createdAt` mappes inkl. null).
- [ ] **Step 2: Implementér** — selects, typer, ren funktion, heuristik; hold
  web/mobile tegn-for-tegn i sync.
- [ ] **Step 3: Verifikation** — begge suiter + tsc grønne. (Mobile-aux'ens
  `medieKoeTaellere` følger automatisk med via den delte `klassificerMedie` — ret
  `buildAux`-kalderen til den nye signatur og lad dens eksisterende test dække det.)

## Task 8: Web-UI — strandede-alder, dubletkø-chip, "Flet ind i…"

**Files:**
- Modify: `web/src/Redaktion.tsx` (bibliotekets kø-chips + strandede-visning)
- Modify: `web/src/components/MediaDetaljeOverlay.tsx` (flet-indgang)

**Adfærd (spec §6.1–6.3):**
- **Strandede-køen:** sorteres ældste-først (NULL/`ukendt alder` sidst); alder pr.
  række via `formatMedieAlder` (den dæmpende "muligvis i gang"-mærkat følger med).
- **Dublet-chip:** fase 2's chip-række udvides med `Mulige dubletter (n)` —
  forberedt på ekstra kø (fase 2-spec §9.3); UI-teksten siger "mulige".
- **"Flet ind i…" (web-only, blødt — spec §6.3):** handling på filsiden/dubletkøen
  når mediet har dublet-kandidater. Redaktøren står på KOPIEN → picker over
  dublet-gruppens øvrige medier (originalen) → klient-orkestreret sekvens af
  EKSISTERENDE changes (ingen ny SQL): for hver `afbildet`-relation på kopien der
  ikke findes på originalen (`fetchMediaAnvendelse`, web `:956`):
  `tilknytMedia`(original) → `sletRelation`(kopiens relation); til sidst
  `fjernMedia`(kopien) → papirkurven. Narrativ-mentions flyttes IKKE — mention-listen
  vises som ADVARSEL før kørsel. Hvert trin er sit eget change_set (granulær
  fortrydelse); afbrydes midtvejs er tilstanden konsistent. Task 1-indexet gør
  "findes allerede på originalen"-racet ufarligt (domæne-fejl → spring over).
  Mobile får INGEN flet-orkestrering (kø-behandling er web, koncept §7).
- Den reelle udrensning af kopien er og bliver fase 4 (`red_udrens_media`) —
  flowet stopper ved blødt fjern (spec-scope + §9.6).

- [ ] **Step 1: Implementér** sortering/alder + chip + flet-flow (orkestrerings-
  sekvensen faktoreres som ren, testbar funktion over `MediaAnvendelse`-data hvis
  den overstiger triviel længde — så dækkes trin-rækkefølge + spring-over-racet af
  en vitest-case; ellers gælder Step 2's manuelle verifikation, jf. fase 2-planens
  UI-task-præcedens).
- [ ] **Step 2: Verifikation** — tsc + vitest + build; browser-røgtest: to medier med
  samme trilling → begge i "Mulige dubletter"; flet flytter relationen, advarer om
  mentions og parkerer kopien i papirkurven; genopret fra papirkurv virker fortsat.

## Task 9: Janitor — `R/media-janitor.R` (rapport-first)

**Files:**
- Create: `R/media-janitor.R`
- Create: `tests/testthat/test-media-janitor.R`

**Interface (spec §7):** Postgres via DBI/RPostgres + `~/.Renviron`
(`SUPABASE_HOST/USER/PASSWORD`, `load_daa.R:67-71`-mønsteret); Storage via httr2
(geo-enrich-præcedensen, `03-geocode.R:12,18,42`) mod `/storage/v1/object/…` med **ny
`SUPABASE_SERVICE_ROLE`-nøgle i `~/.Renviron`** (aldrig i klient-bundle). Default er
REN RAPPORT: konsol-resumé + `work/media-janitor-rapport.csv` (én række pr. fund:
kategori, media_id/sti, alder, anbefalet handling).

| Flag | Betydning |
|---|---|
| *(ingen)* | rapportér alt, rør intet |
| `--slet` | udfør sletninger for kategori a+b, KUN fund ældre end fristen |
| `--frist-dage N` | frist for `--slet` (default **7** — skøn, bekræft ved implementering, spec §9.1); rapporten viser alle uanset alder |
| `--backfill-sha` | skriv beregnede sha256 tilbage (kategori d) — separat opt-in |

Kategorier (spec §7a–d):
- **(a) Strandede:** `upload_status IN ('kladde','fejlet') AND created_at < now()-frist`.
  `--slet`: afbildet-relationer i `_delete_relation_evidence`s FK-orden
  (`schema.sql:1214-1227`) men KUN relationer uden evidens (med evidens → rapport +
  spring over); variant-rækker; media-rækken; Storage-objekter på rækkens/varianternes
  stier. `created_at IS NULL` slettes ALDRIG (rapporteres: "vurdér manuelt").
  Direkte SQL uden change_set (bulk-præcedensen — janitoren rydder affald,
  den redigerer ikke indhold; accepteret fortryd-hazard, spec §9.2 — bekræft).
- **(b) Forældreløse objekter:** rekursiv bucket-listning anti-joinet mod
  `media.storage_path ∪ media_variant.storage_path`; `--slet` kun objekter ældre end
  fristen (objektets egen `created_at`-metadata).
- **(c) Variant-huller:** `klar` uden thumb-/medium-række, eller registreret sti der
  mangler i bucket. KUN rapport, aldrig auto-fix (regenerering kræver klientens
  billedpipeline).
- **(d) sha-backfill + ægte dubletter:** `klar`/`fjernet` med `sha256 IS NULL` og
  eksisterende sti → download large-bytes, `digest::digest(file=…, algo="sha256")`.
  Findes shaen på en ANDEN række → ægte dublet-par i rapporten (ingen skrivning);
  ellers UPDATE (kun med `--backfill-sha`; uden change_set — afledt byte-metadata).
  Stierne omdøbes IKKE (koncept-beslutning: ingen migrering af gamle stier).

- [ ] **Step 1: Skriv fejlende testthat-cases** for de RENE helpers (skrives så de
  kan sources uden DB-forbindelse, jf. `test-geo-enrich.R`-mønsteret): sti-anti-join
  (kendt + forældreløs + variant-sti), frist-logik (over/under frist; `NA`-alder →
  aldrig sletbar), kategori-klassifikation af en syntetisk media-tabel,
  rapportrække-bygning (kolonner + anbefalet handling).
- [ ] **Step 2: Implementér** scriptet (flag-parsing efter `load_daa.R`s form; helpers
  øverst/source-bar; kørselsdel nederst) — `Rscript run-tests.R` grøn.
- [ ] **Step 3: Verificér mod lokal Postgres + dev-bucket med seedet affald** (strandet
  kladde m. alder, kladde m. `created_at IS NULL`, forældreløst objekt, variant-hul,
  NULL-sha-dublet-par): rapport finder alle fund; `--slet` fjerner KUN a+b over
  fristen og rører aldrig NULL-alder; `--backfill-sha` skriver sha og afslører
  dubletparret i rapporten. Uden flag: to kørsler i træk giver identisk rapport
  (bevis for at intet blev rørt).

## Task 10: Samlet verifikation, afstemning & prod-runbook

- [ ] **Step 1: Fuld lokal DB-cyklus** — frisk install + migrationssti ×2 (idempotens
  inkl. DELETE+CREATE INDEX-blokken) + `db-rls.sql`; alle asserts (Task 1 + fase 1/2's
  eksisterende) grønne ad begge veje.
- [ ] **Step 2: Fulde app-suiter** — web: tsc + vitest + build; mobile: tsc + jest;
  R: `Rscript run-tests.R`. På en HEAD committet af implementøren selv (normal CI
  SKAL have kørt på den endelige commit — ingen selv-committende workflows).
- [ ] **Step 3: Empirisk ende-til-ende (spec §8; dev — IKKE prod):** dublet-upload →
  pre-flight-tilbud → tilknyt; afbrudt upload → genoptag uden ny række/nyt objekt;
  web+mobile-upload af samme motiv → to rækker (kendt begrænsning) → begge i "Mulige
  dubletter" → flet flytter relation og parkerer kopien; janitor-rapport → CSV
  verificeret → `--slet` fjerner kun frist-overskredne fund.
- [ ] **Step 4: Dokumentations-afstemning** — changelog-afsnit (inkl. expo-crypto-
  genbyg-noten og de bekræftede/justerede skøn fra §9.1/§9.4/§9.5); markér fase 3
  "implementeret" i koncept-§9-tabellen; `docs/database-current-state.md` ajourføres
  med `created_at`, `relation_afbildet_uidx` og `red_relation`-ændringen.
- [ ] **Step 5: Prod-runbook-note (UDFØRES IKKE her — gated):** fase 1+2 + `db-rls.sql`
  er allerede LIVE (2026-07-20) — fase 3-migrationen `mediehaandtering_fase3_hygiejne`
  deployes derfor ALENE: backup → migrationsblokken → `db-verify-media.sql` +
  Task 1-asserts → `get_advisors(security)` (forvent kun kendte mønstre) → app-deploy
  (web + mobile-builds, sidstnævnte genbygget pga. expo-crypto). Janitorens første
  prod-kørsel er rapport-only og gennemgås med brugeren før noget `--slet`
  (spec §8 sidste afsnit).

---

## Endelig verifikation (Definition of Done)

1. Lokal Postgres: frisk install OG migrationssti ×2 giver identisk flade;
   Task 1-asserts (created_at-default, afbildet-unique_violation, ejer-dubletter
   tilladt, dedup-guard, domæne-fejl) grønne ad begge veje; den evidens-bærende
   dublet-prøve fejler migrationen højlydt som designet.
2. Web: tsc + vitest + build grønne; mobile: tsc + jest grønne; R: testthat grøn —
   på en HEAD committet af implementøren selv (normal CI kørt på endelig commit;
   ingen workflow-ændringer, ingen `contents: write`).
3. Hash-/sti-kontrakten bevist: samme fil → samme sha → samme sti på begge platforme
   (identiske testvektorer i vitest og jest); sha beregnes af genkodede large-bytes;
   `buildStoragePathBase` findes ikke længere i nogen af filerne.
4. Manuel verifikation gennemført (Task 10 Step 3): pre-flight-dedup, genoptag-kladde,
   dubletkø + flet, janitor-rapport/`--slet`/`--backfill-sha` med seedet affald —
   og janitoren har aldrig rørt en række med ukendt alder eller evidens.
5. HEIC-begrænsningen på web er uændret; ingen RLS-filer ændret; ingen migrering af
   gamle stier.
6. Dokumentation afstemt (Task 10 Step 4) — inkl. eksplicit notering af de tre
   "bekræft ved implementering"-afgørelser (frist-dage/1-times-grænse, dublet-
   heuristikkens nøgle, expo-crypto vs. @noble/hashes); prod-deploy udestår som
   separat gated trin med fase 3-migrationen alene.
