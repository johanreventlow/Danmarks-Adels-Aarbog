# Mediehåndtering — fase 2: biblioteket & "bruges på" · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Medier bliver en forvaltet samling: web's eksisterende (tomme) "Medier"-fane
bliver et rigtigt bibliotek med søgning og arbejdskøer (M7), filsiden får "bruges på"
med advarsel før fjern/slet (M6), strandede uploads bliver synlige (M9's synlighed),
og eksisterende medier kan tilknyttes nye personer/objekter uden genupload (M5).

**Architecture:** Én lille DDL (`red_doede_links` + media-gren) — ellers rent app-lag:
fire klient-joinede `getAll`-queries (buildAux-mønsteret) bygger biblioteket, en ren
`klassificerMedie`-funktion afgør køerne, "bruges på" hentes on-demand pr. filside, og
genbrug af medier eksponerer den ALLEREDE eksisterende `red_relation(...,'afbildet')`
(GDPR-guardet server-side) via ny Change-art `tilknytMedia`. Fase 1-filsiden
(`MediaDetaljeOverlay`/`MediaDetaljeSheet`) udvides kun med additive props.

**Tech Stack:** PostgreSQL/Supabase (view-ændring, eksisterende RLS), TypeScript,
React/Vite + vitest (web), RN/Expo + jest (mobile).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-19-mediehaandtering-fase2-bibliotek-design.md` (autoritativ; §-referencer peger dertil)
- Koncept: `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` (§4.1-4.2, §4.8, §9 fase 2)
- Kortlægning (fil:linje-grundlag): web-fanen findes men er tom (`Redaktion.tsx:56`, `ENTITY_DB:75`, `fetchEntityRecords('media')→[]` `redaktionRead.ts:424-451`); filside-callbacks `Redaktion.tsx:985-1008`; overlay-props `MediaDetaljeOverlay.tsx:14-23`; mobile-åbnere `person/[id].tsx:564-573` + `MaterialeSektion.tsx:40-45`; mobile entitetsliste `entitet/[type].tsx:11-16,33,64`; aux `buildAux.ts:179-183` + `load.ts:168`; `text_mention` `schema.sql:2151-2158`; `red_doede_links` `schema.sql:2212-2216`; `red_relation` + GDPR-guard `schema.sql:984-1005,996-998`; media-select `web redaktionRead.ts:668` / `mobile :673`

## Global Constraints

- **Prod røres ALDRIG af denne plan.** Skive 1's DDL verificeres mod lokal Postgres;
  prod-deploy er gated (backup + bruger-OK) og kan med fordel samles med fase 1's
  endnu-ikke-deployede migration — se Task 7.
- **CI-hygiejne (læring fra fase 1-kørslen):** INGEN ændringer af `.github/workflows/`
  ud over evt. at holde eksisterende jobs grønne; ALDRIG `contents: write`, ALDRIG
  jobs der committer tilbage til branchen. Alle commits laves som almindelige commits
  af implementøren selv, så den normale testsuite kører på den endelige HEAD.
- **Web/mobile-lagene er bevidst duplikeret** — `redaktionRead.ts`/`redaktionWrite.ts`
  ændres ens begge steder ("hold i sync"-headerkontrakten). Delt-pakke-ekstraktion er
  fortsat follow-up og må ikke ske her.
- **Format-defensiv rendering (spec §6.1, koncept §4.8):** bibliotek + filside må ikke
  antage billede-mime. Manglende brugbar thumb ELLER `mime_type` uden for `image/*` →
  dokument-ikon-felt (thumb-dimensioner, `slags`-tekst), udeladt af Lightbox.
- **Fail-open-fælderne fra fase 1 gælder stadig:** biblioteket VISER bevidst
  `kladde`/`fejlet`/`fjernet` (det er pointen med køerne), men alle indsættelses-
  pickers og Lightbox filtrerer fortsat `uploadStatus === 'klar'`.
- **GDPR-retningen i `tilknytMedia`:** person skal stå på subjekt-siden
  (person→media); klient-forgreningen er bekvemmelighed — serverens guard
  (`schema.sql:996-998`) er bagstopperen og må ikke "hjælpes udenom".
- **Ingen nye farver/fonte:** web: `theme.ts`-tokens/`primitives.tsx`; mobile:
  `theme/tokens.ts` + `Typography`. Kø-chips genbruger `MEDIA_SLAGS`-chip-stilen.
- Hver task holder relevant suite grøn: web → `cd web && npx tsc --noEmit && npm run
  test && npm run build`; mobile → `cd mobile && npx tsc --noEmit && npm test`;
  DB → frisk install + verify-filer mod lokal Postgres.
- Commit-beskeder på dansk, `feat(media): …`-stil; brug din egen sessions
  Claude-Session-footer.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql`, `db-migrations.sql`, `db-verify.sql` | `red_doede_links` + media-gren (eneste DDL) | 1 |
| `web/src/data/redaktionRead.ts` (+ test) | `fetchMediaBibliotek`, `fetchMediaAnvendelse`, `klassificerMedie`, `MediaBibliotekPost` | 2 |
| `mobile/src/data/redaktionRead.ts` (+ test), `mobile/src/data/{load,buildAux}.ts` (+ test) | Spejl af Task 2 + `medieListe`-udvidelse m. status/kø-tællere | 3 |
| `web/src/data/redaktionWrite.ts`, `mobile/src/data/redaktionWrite.ts` (+ tests) | Ny Change-art `tilknytMedia` → `red_relation` (retningsforgrening) + `oversaetFejl` | 4 |
| `web/src/Redaktion.tsx`, `web/src/components/MediaDetaljeOverlay.tsx` | Biblioteket i Medier-fanen; overlay + bruges-på/advarsel/tilknyt; format-defensiv thumb | 5 |
| `mobile/src/app/redaktion/entitet/[type].tsx`, NY `mobile/src/app/redaktion/entitet/medie.tsx`, `mobile/src/components/redaktion/MediaDetaljeSheet.tsx` | Kø-chips, tappbare rækker, medie-skærm, sheet-udvidelse | 6 |
| `docs/changelog.md`, `docs/database-current-state.md`, koncept-§9-tabellen | Afstemning + samlet prod-runbook-note | 7 |

Task 1 og 2/3 er uafhængige; 2/3 er forudsætning for 5/6; 4 for tilknyt-delene af 5/6.

---

## Task 1: DB — `red_doede_links` udvides med media

**Files:**
- Modify: `schema.sql` (viewet `:2212-2216`)
- Modify: `db-migrations.sql` (ny blok `mediehaandtering_fase2_doede_links`, `CREATE OR REPLACE VIEW` — idempotent)
- Modify: `db-verify.sql` (ny DO-blok)

**Interface (spec §3):** viewet får en fjerde gren:
```sql
OR (m.maal_type='media' AND NOT EXISTS (SELECT 1 FROM media md WHERE md.id=m.maal_id))
```
Kun IKKE-eksisterende media er døde links. Et `'fjernet'` medie er IKKE dødt (kan
genoprettes; synliggøres via papirkurven i stedet) — ingen fjernet-særlogik i viewet.
`security_invoker` bevares; anon-adfærd uændret.

- [ ] **Step 1: Skriv den fejlende assert** i `db-verify.sql`: seed narrativ med
  `[[media:-999901|x]]`-token (mention-triggeren fylder `text_mention`) → assert at
  viewet indeholder rækken; seed media-række -999902 + token mod den → assert at
  viewet IKKE indeholder den (heller ikke hvis den sættes `'fjernet'`). Ryd op /
  ROLLBACK_TEST_OK-mønsteret.
- [ ] **Step 2: Kør mod frisk lokal install** — bekræft at asserten FEJLER (grenen
  findes ikke).
- [ ] **Step 3: Implementér** view-ændringen i `schema.sql` + migrationsblokken.
- [ ] **Step 4: Frisk install + migrationssti ×2** — alle verify-filer grønne begge veje.

## Task 2: Web læse-lag — bibliotek, anvendelse, køer

**Files:**
- Modify: `web/src/data/redaktionRead.ts`
- Modify: `web/src/data/__tests__/redaktionRead.test.ts`

**Interfaces (spec §4):**
```ts
type MedieKoe = 'rettigheder' | 'loese' | 'strandede' | 'papirkurv';
function klassificerMedie(m: {uploadStatus, rettighederStatus, maaPubliceres},
                          antalAfbildet: number, antalMentions: number): MedieKoe[]
// rettigheder: klar && (status='ukendt' || !maaPubliceres)
// loese:       klar && antalAfbildet===0 && antalMentions===0
// strandede:   uploadStatus 'kladde'|'fejlet'  (INTET aldersfilter — ingen created_at)
// papirkurv:   'fjernet'.  Flere køer samtidig er lovligt.

type MediaBibliotekPost = /* PersonMedia-felterne UDEN relationId */ & {
  antalAfbildet: number; antalMentions: number; koeer: MedieKoe[] };
async function fetchMediaBibliotek(): Promise<MediaBibliotekPost[]>
// 4 getAll-queries: media (alle, fase 1-feltlisten fra :668), relation objekt_type='media'
// rolle='afbildet', relation subjekt_type='media' rolle='afbildet',
// text_mention maal_type='media'. Join + tælling klient-side. Thumb via fase 1-mekanikken.

type MediaAnvendelse = {
  afbildet: { type: string; id: string; navn: string; relationId: string }[];
  mentions: { kildeType: string; kildeId: string; subjektNavn: string }[] };
async function fetchMediaAnvendelse(mediaId: string): Promise<MediaAnvendelse>
// on-demand pr. filside; mentions opløses via narrative.subjekt_type/subjekt_id → navneopslag
```

- [ ] **Step 1: Skriv fejlende tests** — `klassificerMedie` udtømmende (alle
  status-/tælle-kombinationer, multi-kø-tilfældet); mapping-funktionen bag
  `fetchMediaBibliotek` som ren funktion på rå rækker (tællinger joines korrekt,
  media uden relationer/mentions → 0/0); anvendelses-mapping (mention → subjektNavn).
- [ ] **Step 2: Implementér** — følg filens `getAll`-/select-mønstre; INGEN
  `upload_status`-filter i bibliotek-query'en.
- [ ] **Step 3: Verifikation** — web-suiten grøn.

## Task 3: Mobile læse-lag — spejl + aux-udvidelse

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts` (+ test) — spejl af Task 2
- Modify: `mobile/src/data/load.ts` (`:168` henter allerede alle media) og
  `mobile/src/data/buildAux.ts` (`:179-183`) + `mobile/src/data/types.ts`
- Modify: `mobile/src/data/__tests__/buildAux.test.ts`

**Interfaces:** `medieListe`-posterne udvides med `uploadStatus`, `maaPubliceres`,
`rettighederStatus`; aux får `medieKoeTaellere: Record<MedieKoe, number>` beregnet med
samme `klassificerMedie` (anvendelses-tællinger fra de relation-/mention-data load
allerede henter — udvid fetch hvis `text_mention` ikke hentes i dag).

- [ ] **Step 1: Skriv fejlende tests** (jest — spejl af Task 2 + buildAux-udvidelsen).
- [ ] **Step 2: Implementér** — hold `klassificerMedie` tegn-for-tegn i sync med web.
- [ ] **Step 3: Verifikation** — `npx tsc --noEmit && npm test`.

## Task 4: Skrive-lag — `tilknytMedia` (begge platforme)

**Files:**
- Modify: `web/src/data/redaktionWrite.ts` + `__tests__/redaktionWrite.test.ts`
- Modify: `mobile/src/data/redaktionWrite.ts` + `__tests__/redaktionWrite.test.ts`

**Interface (spec §5):**
```ts
{ art: 'tilknytMedia', mediaId,
  payload: { maalType: 'person'|'estate'|'coat_of_arms'|'lineage', maalId } }
// maalType='person' → red_relation('person', maalId, 'media', mediaId, 'afbildet')
// ellers            → red_relation('media', mediaId, maalType, maalId, 'afbildet')
```
Ingen fil-bytes → må degradere til `red_suggest` (ingen submitChange-gate).
`oversaetFejl` udvides med `red_relation`s afbildet-person-guard-tekst.

- [ ] **Step 1: Skriv fejlende tests** — begge retninger; manglende mediaId/maalId →
  `null`; ukendt maalType → `null` (fail-closed klient-side).
- [ ] **Step 2: Implementér** spejlet i begge filer.
- [ ] **Step 3: Verifikation** — begge suiter grønne.

## Task 5: Web-UI — biblioteket + overlay-udvidelse

**Files:**
- Modify: `web/src/Redaktion.tsx`
- Modify: `web/src/components/MediaDetaljeOverlay.tsx`

**Adfærd (spec §6):**
- **Medier-fanen fyldes:** `fetchEntityRecords`-grenen for media (`redaktionRead.ts:451`)
  erstattes af `fetchMediaBibliotek()`; media får egen liste-rendering i midterpanelet
  (fanen `Redaktion.tsx:56` + URL `/redaktion/media/:id` findes allerede): kø-chips
  `Alle · Rettigheder (n) · Løse (n) · Strandede (n) · Papirkurv (n)` (klient-filter),
  rækker/gitter med thumb (fjernet dæmpet), status-badges, "bruges n steder"-tekst;
  søgefeltet filtrerer titel/kunstner/original_filnavn.
- **Format-defensiv thumb** (Global Constraint): fallback-gren i thumb-renderingen —
  dokument-ikon-felt ved ikke-billede-mime/manglende thumb; ude af Lightbox.
- **Klik på række** → eksisterende `renderMediaDetalje`-overlay (`:985-1008`) med
  media uden `relationId` ("Fjern tilknytning" er allerede disabled by design).
- **Overlay-udvidelse:** additive props `anvendelse?: MediaAnvendelse`,
  `onFjernTilknytning(relationId)`, `onTilknyt()`. Ny "Bruges på"-sektion mellem
  rettigheds-panel og handlinger: afbildede subjekter (pr.-række "Fjern" →
  `sletRelation`-arten) + narrativ-mentions (read-only). **Slet-advarsel:** ved brug>0
  bliver "Slet billede" to-trins ("Bruges på 2 personer og i 1 narrativ — slet
  alligevel? Mentions bliver stående som inaktive tokens."). Kalderne (person-editor,
  objekt-materiale, bibliotek) henter `fetchMediaAnvendelse` ved åbning — overlayet
  forbliver fetch-frit.
- **Tilknyt-picker:** "Tilknyt til person/gods/våben/linje…"-knap i overlayet →
  søge-picker (genbrug entitets-søgemønsteret) → `run({art:'tilknytMedia',…})`.
  `mediaChanged`-refetch-betingelsen udvides med `tilknytMedia`.

- [ ] **Step 1: Implementér** liste + chips + overlay-udvidelse + picker + fallback.
- [ ] **Step 2: Verifikation** — tsc + vitest + build; browser-røgtest: kø-flow
  (upubliceret → rettigheds-kø → frigiv → væk), tilknyt løst medie → væk fra løse-kø,
  slet-advarsel viser navne, papirkurv → genopret.

## Task 6: Mobile-UI — forenklet bibliotek

**Files:**
- Modify: `mobile/src/app/redaktion/entitet/[type].tsx` (`:11-16,33,64`)
- Create: `mobile/src/app/redaktion/entitet/medie.tsx` (mønster: `materiale.tsx`)
- Modify: `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`

**Adfærd (spec §7):** medie-rækker bliver tappbare (fjern `disabled`-gaten for
`type==='medie'`); kø-chips m. tællere fra aux øverst i medie-listen; tap → ny
`medie.tsx`-skærm der henter fuld `PersonMedia` + `MediaAnvendelse` og åbner
`MediaDetaljeSheet` med samme additive props/sektioner som web-overlayet (bruges-på,
slet-advarsel, tilknyt via `MediaMentionPicker`-mønsteret → `tilknytMedia`). Fuld
kø-behandling forbliver web; mobilen har fuld pr.-medie-paritet.

- [ ] **Step 1: Implementér** — inkl. format-defensiv thumb-fallback i `MediaGallery`/listen.
- [ ] **Step 2: Verifikation** — tsc + jest; simulator: chips-tællere, tap → sheet →
  tilknyt → genopret (manuel, som fase 1 — ingen UI-driver i repo'et).

## Task 7: Samlet verifikation, afstemning & prod-runbook

- [ ] **Step 1: Fuld lokal DB-cyklus** — frisk install + migrationssti ×2 + alle
  verify-filer grønne.
- [ ] **Step 2: Fulde app-suiter** — web tsc+vitest+build; mobile tsc+jest.
- [ ] **Step 3: Dokumentations-afstemning** — changelog-afsnit; markér fase 2
  "implementeret" i koncept-§9-tabellen; `docs/database-current-state.md` ajourføres
  med view-ændringen.
- [ ] **Step 4: Prod-runbook-note (UDFØRES IKKE her — gated):** fase 1-migrationen
  (`mediehaandtering_fase1_filside`) er ENDNU IKKE deployet til prod — de to
  migrationer (fase 1 + `mediehaandtering_fase2_doede_links`) bør deployes samlet:
  backup → begge blokke → `db-verify-media.sql` + doede-links-assert → app-deploy.

---

## Endelig verifikation (Definition of Done)

1. Lokal Postgres: frisk install og migrationssti giver identisk flade; alle
   verify-asserts (inkl. ny doede-links-gren) grønne ad begge veje.
2. Web: tsc + vitest + build grønne; mobile: tsc + jest grønne — på en HEAD committet
   af implementøren selv (normal CI SKAL have kørt på den endelige commit).
3. Manuel verifikation: de fire kø-flows + tilknyt + slet-advarsel + genopret
   gennemført i browser; kø-chips + tap-flow i simulator.
4. Ingen `kladde`/`fejlet`/`fjernet`-medier kan indsættes i narrativer eller optræde
   i Lightbox; ikke-billede-mime renderes som dokument-ikon (kode-inspektion + test).
5. Dokumentation afstemt (Task 7); prod-deploy udestår som samlet gated trin.
