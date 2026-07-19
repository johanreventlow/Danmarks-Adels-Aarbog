# Mediehåndtering — fase 1: filsiden & fuld CRUD · Implementeringsplan

**Status 2026-07-19:** Implementeret på PR-branch. Produktionsdeploy er ikke udført.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ethvert billede får ét hjem — en medie-detaljeside (web-overlay + mobile-sheet)
hvor redaktøren kan rette metadata (M1), styre rettigheder/publicering (M2) og genoprette
blødt slettede medier (M3). Kunstner/datering kan angives allerede ved upload.

**Architecture:** To nye `red_*`-RPC'er + én signatur-udvidelse oven på det eksisterende
media-lag (ingen nye tabeller, ingen RLS-ændringer — redaktionen ser allerede alt, og
`'fjernet'`/upublicerede forbliver fail-closed for anon/auth). Tre nye Change-arter i det
duplikerede skrive-lag; redaktions-read udvides med filsidens felter og beholder
`'fjernet'`-rækker (dæmpet + Genopret). UI genbruger dry-run/LIVE-flowet
(`run()`/`SkrivePreviewSheet`) uændret.

**Tech Stack:** PostgreSQL/Supabase (SECURITY DEFINER-RPC'er, `begin_change_set`,
`trg_log_media`), TypeScript, React/Vite + vitest (web), RN/Expo + jest (mobile).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-19-mediehaandtering-fase1-filside-design.md` (autoritativ for alle regler; §-referencer nedenfor peger dertil)
- Koncept: `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` (§4.1, §4.4, §9 fase 1)
- RPC-konvention: `schema.sql:1663-1810` (media-blokken); impersonerings-mønster: `db-verify.sql` Task 5/5b (`:432-470`)
- Skrive-lag: `web/src/data/redaktionWrite.ts`, `mobile/src/data/redaktionWrite.ts` ("hold i sync")
- Læse-lag: `web/src/data/redaktionRead.ts:600-660`, `mobile/src/data/redaktionRead.ts:620-693`
- UI: `web/src/Redaktion.tsx` (`renderMateriale` `:835-952`, `renderMediaPicker` `:1196`), `mobile/src/components/redaktion/{MediaGallery,MaterialeSektion,MediaUploadSheet}.tsx`, `mobile/src/app/redaktion/person/[id].tsx`

## Global Constraints

- **Prod røres ALDRIG af denne plan.** Al DDL verificeres mod lokal Postgres (frisk
  `schema.sql`-install + migrationssti). Prod-deploy er et separat, controller-gated
  trin (bruger-OK + backup) EFTER planen — se Task 9's runbook-afsnit.
- **RPC-konvention** (alle tre DB-tasks): `SECURITY DEFINER SET search_path=public`;
  gate `IF current_rolle() <> 'redaktion' THEN RAISE 'Kun redaktion'`; `PERFORM
  begin_change_set(...)`; id-alloc er ikke relevant (ingen INSERT af nye rækker).
  Grants dækkes automatisk af navne-loopet `db-rls.sql:512-518` — men KUN ved unikt
  funktionsnavn (⚠ overload-fælden, Task 2).
- **NULL/''-kontrakten** (spec §3.1): `NULL` = feltet røres ikke; `''` = ryd til NULL;
  `p_slags=''` afvises. Gælder `red_opdater_media` og spejles i UI-payloads.
- **Web/mobile-skrivelaget er bevidst duplikeret** — hver ændring i `redaktionWrite.ts`
  laves ens begge steder ("hold i sync"-headerkontrakten). Delt-pakke-ekstraktion er
  fortsat follow-up og må ikke ske i denne plan.
- **Fail-open-fælderne** (spec §5): alle steder der vælger/viser medier til indsættelse
  eller Lightbox skal eksplicit filtrere `uploadStatus === 'klar'` — "har signed URL"
  er IKKE nok (redaktionens storage-politik signerer også fjernede stier).
- **Ingen nye farver/fonte:** web styler fra `theme.ts`-tokens/`primitives.tsx`-mønstre,
  mobile fra `mobile/src/theme/tokens.ts` + `Typography`.
- Hver task holder relevant suite grøn: web → `cd web && npx tsc --noEmit && npm run
  test && npm run build`; mobile → `cd mobile && npx tsc --noEmit && npm test`;
  DB → frisk install + verify-filer mod lokal Postgres.
- Commit-beskeder på dansk, `feat(media): …`-stil; brug din egen sessions
  Claude-Session-footer.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql` | `red_opdater_media`, `red_genopret_media` (nye); `red_upload_media` + kunstner/datering (in place) | 1 |
| `db-verify.sql` | RPC-asserts (Task 5-mønsteret: impersonering + ROLLBACK_TEST_OK) | 1 |
| `db-migrations.sql` | Idempotent blok: CREATE OR REPLACE ×2 + DROP+CREATE for `red_upload_media` | 2 |
| `db-verify-media.sql` | Anon-gating-assert for fjern→genopret-cyklussen (RLS-only-kontrakten) | 2 |
| `web/src/data/redaktionWrite.ts` (+ test) | 3 nye Change-arter + uploadMedia-payload-udvidelse + `oversaetFejl` | 3 |
| `mobile/src/data/redaktionWrite.ts` (+ test) | Spejl af Task 3 | 4 |
| `web/src/data/redaktionRead.ts` (+ test) | Udvidet media-select/-type; `'fjernet'` beholdes | 5 |
| `mobile/src/data/redaktionRead.ts` (+ test) | Spejl af Task 5 | 6 |
| `web/src/Redaktion.tsx` | Filside-overlay, galleri-ændringer, upload-ark-udvidelse, picker/lightbox-filtre | 7 |
| `mobile/src/components/redaktion/MediaDetaljeSheet.tsx` | NY: filside-sheet | 8 |
| `mobile/src/components/redaktion/{MediaGallery,MaterialeSektion,MediaUploadSheet}.tsx`, `mobile/src/app/redaktion/person/[id].tsx` | Wiring: tap→detalje, Genopret, udvidet upload | 8 |
| `docs/changelog.md`, `docs/database-current-state.md`, koncept-§9-tabellen | Afstemning + prod-runbook-note | 9 |

---

## Task 1: DB — nye RPC'er + upload-udvidelse (`schema.sql` + RPC-asserts)

**Files:**
- Modify: `schema.sql` (media-RPC-blokken `:1663-1810`)
- Modify: `db-verify.sql` (nye DO-blokke efter Task 5b-mønsteret `:452-470`)

**Interfaces (fra spec §3):**
```sql
red_opdater_media(p_media_id bigint, p_titel text DEFAULT NULL, p_slags text DEFAULT NULL,
                  p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL) RETURNS void
-- NULL=uændret; ''=ryd (nullif/btrim); p_slags='' → RAISE 'Slags kan ikke ryddes';
-- ukendt id → RAISE. Ingen upload_status-guard (fjernet må metadata-rettes).
red_genopret_media(p_media_id bigint) RETURNS void
-- UPDATE ... SET upload_status='klar' WHERE id=... AND upload_status='fjernet';
-- 0 rækker ramt → RAISE 'Kan kun genoprette et fjernet medie'.
red_upload_media(..., p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL)
-- sendes videre til det interne red_opret_media-kald (i dag hardkodet NULL, NULL — schema.sql:1725).
```

- [ ] **Step 1: Skriv de fejlende asserts** — nye DO-blokke i `db-verify.sql`
  (impersonér redaktion via `set_config('request.jwt.claim.sub', …)` + profiles-upsert,
  afslut med `RAISE 'ROLLBACK_TEST_OK'` så seed rulles tilbage — kopiér Task 5-formen):
  1. `red_opdater_media`: opret testmedia (direkte INSERT, negative id) → kald med
     `p_titel='Ny', p_kunstner=''` → assert titel ændret, kunstner NULL, slags/datering
     urørt; kald med `p_slags=''` → forvent domæne-fejl; ukendt id → forvent fejl.
  2. `red_genopret_media`: media `'fjernet'` → kald → assert `'klar'`; kald igen
     (nu `'klar'`) → forvent domæne-fejl.
  3. Versionering: assert at opdater-kaldet skabte præcis ét nyt `change_set` og at
     `red_fortryd_change_set` ruller titlen tilbage.
  4. `red_upload_media` med `p_kunstner/p_datering` → assert felterne landede på rækken.
- [ ] **Step 2: Kør asserts mod frisk lokal install** — `schema.sql` + `db-rls.sql` på
  tom lokal Postgres; bekræft at de nye blokke FEJLER (funktionerne findes ikke).
- [ ] **Step 3: Implementér de tre funktioner i `schema.sql`** jf. Interfaces + husets
  konvention (change_set-beskrivelser: `'Opdaterede media %s'` / `'Genoprettede media %s'`).
  `red_upload_media` rettes in place (frisk install har ingen overload-problem).
- [ ] **Step 4: Geninstallér frisk + kør hele `db-verify.sql`** — nye blokke grønne,
  gamle uændret grønne (ingen regression i fx Task 5's max(id)-antagelser).

## Task 2: DB — migrationssti + gating-assert

**Files:**
- Modify: `db-migrations.sql` (ny navngiven blok `mediehaandtering_fase1_filside`)
- Modify: `db-verify-media.sql` (ny RLS-only DO-blok)

**⚠ Overload-fælden (spec §3.3):** `CREATE OR REPLACE` af `red_upload_media` med nye
parametre opretter en overload → PostgREST-tvetydighed + grant-loopet
(`grant … on function public.red_upload_media` uden argumenttyper) fejler. Migrationen
SKAL `DROP FUNCTION IF EXISTS red_upload_media(<fuld gammel 14-parameter-signatur>)`
før `CREATE`, i samme transaktion. Skriv den gamle signatur eksplicit af fra git-historikken.

- [ ] **Step 1: Skriv migrationsblokken** — idempotent: DROP IF EXISTS (gammel signatur)
  + CREATE for alle tre funktioner (verbatim fra `schema.sql`, filens etablerede mønster).
- [ ] **Step 2: Migrationssti-test lokalt** — frisk install af FØR-tilstanden (git
  stash/checkout af gammel `schema.sql`), kør `db-migrations.sql` **to gange** (idempotens
  inkl. DROP+CREATE), kør så `db-rls.sql` (grant-loopet må ikke fejle) og hele
  `db-verify.sql` — alt grønt.
- [ ] **Step 3: Gating-assert i `db-verify-media.sql`** (filens kontrakt: `SET LOCAL
  ROLE`, INGEN redaktør-RPC'er — brug direkte UPDATE på seed-rækker): media `'klar'`+
  publiceret+afdød-afbildet → anon ser 1; UPDATE til `'fjernet'` → anon ser 0 (og
  variant-rækken forsvinder med, jf. delegerende variant-RLS); UPDATE tilbage til
  `'klar'` → anon ser 1 igen. Kør filen lokalt — 5 OK-NOTICE'er.

## Task 3: Web skrive-lag — tre nye Change-arter

**Files:**
- Modify: `web/src/data/redaktionWrite.ts`
- Modify: `web/src/data/__tests__/redaktionWrite.test.ts`

**Interfaces (fra spec §4):** nye arter i `Change`-unionen + `buildRpcCall`-grene:
```ts
{ art: 'opdaterMedia', mediaId, payload: { titel?, slags?, kunstner?, datering? } }
  → red_opdater_media; kun tilstedeværende payload-nøgler sendes ('' betyder ryd)
{ art: 'genopretMedia', mediaId } → red_genopret_media (mediaId mangler → null)
{ art: 'mediaRettigheder', mediaId, payload: { status, maaPubliceres,
    licens?, kildehenvisning?, gengivelsestilladelse?, kildeFritekst? } }
  → red_set_media_rettigheder (status+gate altid; dok-felter kun når udfyldt ikke-tomme)
```
`uploadMedia`-payload udvides: `kunstner`, `datering`, `rettighederStatus` →
`p_kunstner`/`p_datering`/`p_rettigheder_status` (sidstnævnte arg-mapping findes allerede).
Ingen af de tre nye arter bærer fil-bytes → INGEN hård gate i `submitChange`
(de må degradere til `red_suggest` via `planCall`, modsat `uploadMedia`).
`oversaetFejl` udvides: `/kan kun genoprette/i` og `/slags kan ikke ryddes/i` → danske tekster.

- [ ] **Step 1: Skriv fejlende vitest-cases** — buildRpcCall for de tre arter (fuld
  payload, delvis payload, manglende mediaId → null); uploadMedia inkl. de tre nye
  felter og deres fravær (defaults); planCall-routing (ikke-redaktion → red_suggest
  for `opdaterMedia`, men fortsat throw for `uploadMedia`); oversaetFejl-mapninger.
- [ ] **Step 2: Implementér** unionen, grenene, payload-mapningen, oversaetFejl.
- [ ] **Step 3: Verifikation** — `cd web && npx tsc --noEmit && npm run test`.

## Task 4: Mobile skrive-lag — spejl af Task 3

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts` (identiske grene; mobile har ingen
  planCall/buildSuggestCall — følg filens egen form, jf. header-kontrakten)
- Modify: `mobile/src/data/__tests__/redaktionWrite.test.ts`

- [ ] **Step 1: Skriv fejlende jest-cases** (spejl af Task 3's, minus planCall-routing).
- [ ] **Step 2: Implementér** — hold arg-navne/rækkefølge tegn-for-tegn i sync med web.
- [ ] **Step 3: Verifikation** — `cd mobile && npx tsc --noEmit && npm test`.

## Task 5: Web læse-lag — filsidens felter + `'fjernet'` beholdes

**Files:**
- Modify: `web/src/data/redaktionRead.ts` (`fetchRedPersonMedia`/`fetchRedObjectMedia`
  + `mapPersonMediaRows` + typer)
- Modify: `web/src/data/__tests__/redaktionRead.test.ts`

**Interfaces (fra spec §5):** media-select + `RawPersonMediaRow`/`PersonMedia` udvides
med `kunstner`, `datering`, `rettigheder_status`, `mime_type`, `byte_size`, `bredde`,
`hoejde`, `original_filnavn` (camelCase i den mappede type). `mapPersonMediaRows`
**fjerner sit `upload_status !== 'fjernet'`-filter** — rækkerne beholdes og skelnes
via det eksisterende `uploadStatus`-felt. Filens `:611`-kommentar omskrives (den
begrunder i dag det modsatte).

- [ ] **Step 1: Skriv fejlende tests** — mapPersonMediaRows beholder en fjernet række
  med `uploadStatus='fjernet'`; nye felter mappes (inkl. null-tolerance).
- [ ] **Step 2: Implementér** select-kolonner + mapping.
- [ ] **Step 3: Verifikation** — web-suiten grøn. (⚠ UI-konsekvenserne — picker/
  lightbox-filtre — hører til Task 7; indtil da er web i en mellemtilstand hvor
  fjernede thumbs kan dukke op i galleriet. Task 5+7 bør derfor lande i samme PR/serie.)

## Task 6: Mobile læse-lag — spejl af Task 5

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts` (`fetchPersonMedia`/`fetchObjectMediaRed`,
  `mapPersonMediaRows` `:637-653`, `PersonMedia`-typen `:628`)
- Modify: `mobile/src/data/__tests__/redaktionRead.test.ts`

- [ ] **Step 1–3:** som Task 5 (jest). Samme mellemtilstands-forbehold ift. Task 8.

## Task 7: Web-UI — filside-overlay + galleri + upload-ark

**Files:**
- Modify: `web/src/Redaktion.tsx`

**Adfærd (fra spec §6):**
- **Nyt `renderMediaDetalje()`-overlay** (genbrug `overlay()`-mønstret fra
  `renderMediaPicker`): (1) preview (klik → eksisterende Lightbox) + statuslinje
  (`slags · uploadStatus · bredde×hoejde · byte_size · original_filnavn`);
  (2) metadata-form (titel-input, `MEDIA_SLAGS`-chips, kunstner-input, datering-input)
  med "Gem" → `run({art:'opdaterMedia', …payload: kun ændrede felter, ryddet felt='' })`;
  (3) rettigheds-panel (seks status-chips, "Må publiceres"-checkbox, licens/
  kildehenvisning/gengivelsestilladelse/kilde-fritekst-inputs) med "Gem rettigheder" →
  `mediaRettigheder`-changen + klient-nudge (advarselslinje ved
  `spaerret`/`begraenset` + publiceret); (4) handlinger: Fjern/Slet (flyttet med ind,
  beholdes også i galleriet) — for `uploadStatus==='fjernet'` i stedet **Genopret** →
  `genopretMedia`.
- **Galleriet** (`renderMateriale`): thumb-klik åbner nu detalje-overlayet (Lightbox
  nås via previewet); fjernede rækker vises dæmpet (opacity ~0.45; status-suffixet
  `· fjernet` kommer gratis) med Genopret i stedet for Fjern/Slet; fjernede holdes
  ude af `withUrl`-lightbox-listen.
- **Billedvælgeren** (`renderMediaPicker`): `brugbar`-filteret udvides med
  `m.uploadStatus === 'klar'` (fail-open-fælde #1).
- **Upload-arket:** kunstner- + datering-inputs + rettigheds-status-chips (default
  `'ukendt'`); payload udvides jf. Task 3.
- **Refetch:** `mediaChanged`-boolean (Slice 0h) udvides med de tre nye arter.

- [ ] **Step 1: Implementér** overlay + galleri + picker-filter + upload-ark + refetch.
- [ ] **Step 2: Verifikation** — `npx tsc --noEmit && npm run test && npm run build`;
  manuel browser-røgtest mod lokal/dev: redigér metadata → dry-run viser
  `red_opdater_media`-kaldet; frigiv upubliceret billede; slet → dæmpet → genopret.

## Task 8: Mobile-UI — `MediaDetaljeSheet` + wiring

**Files:**
- Create: `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`
- Modify: `MediaGallery.tsx` (tap → `onVaelg(m)`-callback; Lightbox-state flytter til
  sheetet; dæmpet fjernet-visning; Genopret i knap-rækken for fjernede)
- Modify: `MaterialeSektion.tsx` + `mobile/src/app/redaktion/person/[id].tsx`
  (sheet-state + de tre nye Change-arter gennem eksisterende `SkrivePreviewSheet` +
  `refreshMedia()`; person-editorens picker-kilde filtreres på `'klar'`)
- Modify: `MediaUploadSheet.tsx` (kunstner/datering/rettigheds-status, jf. Task 4)

**Adfærd:** samme fire blokke som web-overlayet (spec §7) — fuld funktionel paritet;
sheet-mønstret kopieres fra `MediaUploadSheet` (KeyboardAvoiding/ScrollView-chrome).

- [ ] **Step 1: Implementér** sheet + wiring + upload-udvidelse + picker-filter.
- [ ] **Step 2: Verifikation** — `npx tsc --noEmit && npm test`; simulator-gennemløb
  af de tre flows (metadata, frigiv, slet→genopret) — kendt begrænsning: manuel
  (ingen UI-driver i repo'et, jf. Slice 0g/0h).

## Task 9: Samlet verifikation, afstemning & prod-runbook

- [ ] **Step 1: Fuld lokal DB-cyklus igen** (nu mod endelig kode): frisk install +
  migrationssti ×2 + `db-rls.sql` + `db-verify.sql` + `db-verify-media.sql` — alt grønt.
- [ ] **Step 2: Fulde app-suiter** — web: tsc + vitest + build; mobile: tsc + jest.
- [ ] **Step 3: Empirisk ende-til-ende (dev/prod-svarende base, EFTER DDL-deploy):**
  upload m. kunstner/datering/status → filside → redigér → frigiv → verificér anonym
  synlighed (logget-ud fane) → slet → genopret → synlig igen. Mobile: simulator-spejl.
- [ ] **Step 4: Dokumentations-afstemning:** changelog-afsnit (inkl. det accepterede
  fase 1-hul: fjernet medie uden relation kræver fase 2-biblioteket); ret den
  forældede media-linje i `docs/database-current-state.md` §3 (siger deny-all/tom —
  Slice 0 gik i prod 2026-07-05) og tilføj de nye RPC'er til dens funktions-oversigt;
  markér fase 1 "implementeret" i koncept-§9-tabellen.
- [ ] **Step 5: Prod-runbook-afsnit i changelog/plan** (UDFØRES IKKE her — controller-
  gated): backup → kør `db-migrations.sql`-blokken som navngiven migration
  `mediehaandtering_fase1_filside` via MCP/dashboard → kør `db-verify-media.sql` →
  `get_advisors(security)` (forvent kendte search_path-advisories som ved Slice 0) →
  app-deploy.

---

## Endelig verifikation (Definition of Done)

1. Lokal Postgres: frisk install OG migrationssti giver identisk funktionsflade;
   `db-verify.sql` (inkl. nye RPC/versionerings-blokke) + `db-verify-media.sql`
   (inkl. genopret-cyklus) grønne ad begge veje.
2. Web: tsc + vitest + build grønne; mobile: tsc + jest grønne.
3. Manuel verifikation: de tre flows (metadata-redigering, frigivelse, slet→genopret)
   gennemført i browser og simulator uden konsolfejl.
4. Ingen fjernede medier kan indsættes i narrativer eller optræde i Lightbox
   (kode-inspektion + manuel test af begge pickers).
5. Dokumentation afstemt (Task 9 Step 4); prod-deploy udestår som gated trin.
