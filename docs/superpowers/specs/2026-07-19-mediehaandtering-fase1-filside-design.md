# Mediehåndtering — fase 1: filsiden & fuld CRUD (design-spec)

**Dato:** 2026-07-19
**Styringsgrundlag:** `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` §4.1, §4.4 (panel-delen), §9 (fase 1).
**Mål:** ethvert billede får ét hjem — en medie-detaljeside ("filsiden") hvor redaktøren
kan rette metadata, styre rettigheder/publicering og genoprette slettede medier.
Lukker koncept-manglerne **M1** (metadata låst efter upload), **M2** (rettigheder kan
aldrig ændres — et upubliceret billede kan reelt ikke frigives fra appen) og **M3**
(intet genopret af `'fjernet'`).

**Beslutninger arvet fra konceptet:** ingen nye tabeller; genbrug af eksisterende
RPC'er hvor de findes (`red_set_media_rettigheder` er komplet i DB men UI-løs);
fail-closed gating urørt; web/mobile fortsat duplikeret skrive-lag ("hold i sync").
**Uden for scope (fase 2–4):** mediebibliotek/arbejdskøer, "bruges på"-listen,
tilknyt-eksisterende-medie, sha256/dedup, erstat fil, udrensning, portræt-flag.

---

## 1. Baggrund & afgrænsning (empirisk)

I dag sættes `titel`/`slags`/`maa_publiceres` **kun** i upload-øjeblikket
(`web/src/Redaktion.tsx` `renderMateriale`, `mobile/.../MediaUploadSheet.tsx`);
`kunstner`/`datering` kan slet ikke indtastes — `red_upload_media` hardkoder dem
til `NULL` i sit interne `red_opret_media`-kald (`schema.sql:1725`), og
`rettigheder_status` sendes hardkodet `'ukendt'` fra klienten
(`redaktionWrite.ts`, `p_rettigheder_status: p.rettighederStatus ?? 'ukendt'` —
ingen UI-flade fylder feltet). Ingen RPC kan opdatere media-metadata bagefter.
`'fjernet'` filtreres permanent væk i begge redaktions-read-lag
(`web/src/data/redaktionRead.ts:633`, `mobile/src/data/redaktionRead.ts:643`),
så fortryd kræver arkæologi i change-set-historikken.

**I scope:** to nye RPC'er (`red_opdater_media`, `red_genopret_media`) +
signatur-udvidelse af `red_upload_media` (kunstner/datering); tre nye Change-arter
(`opdaterMedia`, `genopretMedia`, `mediaRettigheder`); udvidet redaktions-read af
media-rækker (flere felter, `'fjernet'` synlig for redaktionen); filside-UI på
web (overlay) og mobile (sheet); upload-ark udvidet med kunstner/datering +
rettigheds-status.

**Bevidst minimal filside i fase 1:** preview + metadata + rettigheder + status/
genopret + de eksisterende Fjern/Slet-handlinger. "Bruges på", historik-visning og
tilknytnings-redigering er fase 2 (kræver kø-/anvendelses-queries, der hører til
biblioteket). Filsiden bygges dog som det naturlige sted, de senere paneler lander.

---

## 2. Skæring (6 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | DB-lag: `red_opdater_media` + `red_genopret_media` + `red_upload_media`-udvidelse | `schema.sql`, `db-migrations.sql`, `db-verify-media.sql` | lokal Postgres: frisk install + migrationssti + RPC/versionerings-asserts |
| 2 | Skrive-lag: nye Change-arter (begge platforme) | `web/src/data/redaktionWrite.ts`, `mobile/src/data/redaktionWrite.ts` (+ tests) | vitest/jest på `buildRpcCall`; netværksfrit |
| 3 | Læse-lag: udvidet media-select + `'fjernet'` synlig for redaktion | `web/src/data/redaktionRead.ts`, `mobile/src/data/redaktionRead.ts` (+ tests) | vitest/jest på `mapPersonMediaRows` |
| 4 | Web: filside-overlay + upload-ark-udvidelse | `web/src/Redaktion.tsx` | tsc + vitest + build |
| 5 | Mobile: filside-sheet + upload-sheet-udvidelse | `mobile/src/components/redaktion/MediaDetaljeSheet.tsx` (ny), `MediaGallery.tsx`, `MaterialeSektion.tsx`, `MediaUploadSheet.tsx`, `app/redaktion/person/[id].tsx` | tsc + jest; simulator-verifikation |
| 6 | Verifikation & afstemning | changelog, koncept-doc status-note, `docs/database-current-state.md` (media-linjen er forældet) | fuld suite grøn; prod-deploy runbook-note |

1 er forudsætning for 2; 2 for 4+5; 3 kan bygges parallelt med 2. Hver skive
holder `tsc` + eksisterende suiter grønne. Prod-DDL (skive 1 mod prod) er som
altid controller-gated (bruger-OK + backup før deploy).

---

## 3. Skive 1 — DB-laget

Alle tre funktioner følger huskonventionen (`schema.sql:1663-1810`):
`SECURITY DEFINER SET search_path=public`, gate `IF current_rolle() <> 'redaktion'
THEN RAISE 'Kun redaktion'`, `PERFORM begin_change_set(...)`, versionering gratis
via eksisterende `trg_log_media`. Grants dækkes af det navnebaserede
`red_*`-grant-loop (`db-rls.sql:512-518`). **Ingen RLS-ændringer** — redaktionen
ser allerede alt (`redaktion_read`), og `'fjernet'`/upublicerede forbliver
fail-closed usynlige for anon/auth.

### 3.1 `red_opdater_media` (ny) — metadata-redigering (M1)

```sql
red_opdater_media(
  p_media_id bigint,
  p_titel    text DEFAULT NULL,   -- NULL = uændret; '' = ryd feltet
  p_slags    text DEFAULT NULL,   -- NULL = uændret; kan IKKE ryddes (påkrævet ved oprettelse)
  p_kunstner text DEFAULT NULL,   -- NULL = uændret; '' = ryd
  p_datering text DEFAULT NULL    -- NULL = uændret; '' = ryd
) RETURNS void
```

- **NULL/''-kontrakt:** `NULL` = feltet røres ikke (præcedens:
  `red_set_media_rettigheder`s coalesce-mønster); tom streng = ryd feltet til NULL
  (`nullif(btrim(...), '')`). `p_slags = ''` afvises med domæne-fejl ("Slags kan
  ikke ryddes") — spejler `red_opret_media`s påkrævethed.
- **Guards:** rækken skal findes (ellers RAISE); ingen upload_status-guard —
  metadata-rettelse af et `'fjernet'` medie er harmløs og ønskelig (papirkurvs-
  kuratering i fase 2).
- change_set-beskrivelse: `format('Opdaterede media %s', p_media_id)`.

### 3.2 `red_genopret_media` (ny) — fortryd blødt fjern (M3)

```sql
red_genopret_media(p_media_id bigint) RETURNS void
```

- Én UPDATE: `SET upload_status='klar' WHERE id=p_media_id AND upload_status='fjernet'`.
  Guard-formen spejler `red_bekraeft_media_upload`s `<> 'fjernet'`-hærdning — men
  omvendt: **kun** fra `'fjernet'`. Rammer UPDATE'en 0 rækker → RAISE med
  domæne-fejl ("Kan kun genoprette et fjernet medie") frem for stille no-op, så
  et forældet UI-kald ikke kvitterer falsk.
- Sikker by design: blødt fjern rører aldrig Storage-bytes (Slice 0h), så der er
  altid noget at genoprette til. Varianterne (`media_variant`) blev heller aldrig
  rørt. Synlighed vender automatisk tilbage via `media_rettigheder_ok` (kræver
  `'klar'`) — ingen ny RLS.

### 3.3 `red_upload_media` — signatur-udvidelse (kunstner/datering ved upload)

Tilføj `p_kunstner text DEFAULT NULL, p_datering text DEFAULT NULL` og send dem
videre til det interne `red_opret_media`-kald (i dag hardkodet `NULL, NULL`).

⚠ **Postgres-faldgrube (skal med i migrationen):** tilføjede parametre ændrer
funktionens signatur — `CREATE OR REPLACE` opretter en **overload** i stedet for
at erstatte. To overloads gør (a) PostgREST-`rpc`-kald tvetydige og (b) det
navnebaserede grant-loop fejlende (`grant ... on function public.red_upload_media`
uden argumenttyper kræver unikt navn). Migrationen skal derfor `DROP FUNCTION
red_upload_media(<fuld gammel signatur>)` **før** `CREATE`, i samme transaktion.
`schema.sql` (frisk install) opdateres blot in place.

### 3.4 `db-migrations.sql` + verifikation

- Idempotent blok efter etableret mønster: `CREATE OR REPLACE` for 3.1/3.2,
  DROP+CREATE for 3.3 (DROP med `IF EXISTS` + fuld gammel signatur → idempotent).
- **`db-verify-media.sql`:** filens kontrakt er RLS-tests uden redaktør-kontekst
  (`SET LOCAL ROLE anon/authenticated`) — RPC-happy-paths hører ikke hjemme dér
  (dokumenteret fravalg, changelog Slice 0h). Tilføj det der *passer* kontrakten:
  en gating-assert for genopret-cyklussen via direkte UPDATE-seed
  (`'klar'`-testrække → sæt `'fjernet'` → anon ser 0 → sæt `'klar'` → anon ser 1).
- **RPC/versionerings-asserts kører lokalt** (samme model som levende feed fase 2:
  frisk `schema.sql`-install + migrationssti mod lokal Postgres): kald de tre
  RPC'er under simuleret redaktør-claims, assert felt-effekter, NULL/''-kontrakten,
  genopret-guarden, at `red_fortryd_change_set` ruller en metadata-rettelse
  tilbage, og at `red_upload_media` nu bærer kunstner/datering hele vejen ind.

---

## 4. Skive 2 — skrive-laget (begge platforme, holdt i sync)

Tre nye arter i `Change`-unionen + `buildRpcCall`-grene:

| Art | RPC | Args | Null-kontrakt |
|---|---|---|---|
| `opdaterMedia` | `red_opdater_media` | `p_media_id` + `p_titel/p_slags/p_kunstner/p_datering` fra payload | kun udfyldte payload-nøgler sendes; UI sender `''` for "ryd" |
| `genopretMedia` | `red_genopret_media` | `p_media_id` | kræver `mediaId` (ellers `null` som `fjernMedia`-mønsteret) |
| `mediaRettigheder` | `red_set_media_rettigheder` | `p_media_id`, `p_status`, `p_maa_publiceres` + valgfrit `p_licens/p_kildehenvisning/p_gengivelsestilladelse/p_kilde_fritekst` | status+gate sendes altid (panelet viser altid begge); dokumentationsfelter kun når udfyldt |

- **Ingen fil-bytes** i nogen af de tre → de kan alle degradere til `red_suggest`
  via `planCall`-fallbacken (modsat `uploadMedia`-gaten). UI'et skjuler alligevel
  handlingerne for ikke-redaktion (som Fjern/Slet i dag), men ingen hård gate
  behøves i `submitChange`.
- **`uploadMedia`-payload udvides** med `kunstner`, `datering`, `rettighederStatus`
  → `p_kunstner`/`p_datering`/`p_rettigheder_status` (sidstnævnte mapping findes
  allerede — kun UI'et manglede at fylde den).
- `describeCall`/dry-run virker uændret (generisk). `oversaetFejl` udvides med de
  nye domæne-fejl: "Kan kun genoprette…" og "Slags kan ikke ryddes".
- **Tests** (vitest + jest, spejlede): buildRpcCall-grene for de tre arter inkl.
  manglende-id → `null`, delvis payload → delvise args, uploadMedia med
  kunstner/datering/rettighederStatus.

---

## 5. Skive 3 — læse-laget

`fetchRedPersonMedia`/`fetchRedObjectMedia` (web) og `fetchPersonMedia`/
`fetchObjectMediaRed` (mobile) udvider deres media-select med felterne filsiden
skal vise/redigere: `kunstner`, `datering`, `rettigheder_status`, `mime_type`,
`byte_size`, `bredde`, `hoejde`, `original_filnavn`. `PersonMedia`-typen (+
`RawPersonMediaRow`/`mapPersonMediaRows`) udvides tilsvarende.

**`'fjernet'`-filteret vendes for redaktionen:** `mapPersonMediaRows` beholder
rækkerne og markerer dem via det eksisterende `uploadStatus`-felt (ingen ny
boolean). Galleriet er redaktørens eneste vej til genopret i fase 1 (papirkurvs-
køen kommer først med biblioteket i fase 2), og mediet har stadig sin
`afbildet`-relation, så det hører naturligt hjemme under sit subjekt.

**Følgekonsekvenser der SKAL håndteres (fail-open-fælder):**
1. **Web-narrativ-billedvælgeren** (`renderMediaPicker`, `Redaktion.tsx:1196`)
   filtrerer i dag kun på `thumbUrl` — men redaktionens storage-politik kan
   signere også fjernede stier, så et fjernet medie ville dukke op som indsætteligt.
   Eksplicit `uploadStatus === 'klar'`-filter tilføjes (samme i mobiles
   `MediaMentionPicker`/`NarrativEditor`-picker-kilde).
2. **Lightbox:** fjernede rækker holdes ude af `withUrl`-listen/lightboxItems —
   de vises dæmpet i galleriet, ikke navigerbart.
3. **Læser-fladerne** (`data/media.ts`, `public.ts`) er urørte — RLS skjuler
   alligevel, og de fetcher separat.

**Tests:** mapPersonMediaRows bevarer fjernet-rækker med korrekt status; nye
felter mappes; picker-filteret (ren funktion hvor muligt).

---

## 6. Skive 4 — web-UI

### 6.1 Filside som overlay

Klik på en thumbnail i Materiale-galleriet åbner i dag Lightbox direkte. Nyt:
klik åbner **medie-detalje-overlayet** (samme `overlay()`-mønster som
billedvælgeren); Lightbox nås via klik på previewet inde i overlayet. Indhold,
oppefra:

1. **Preview** (medium/thumb-URL, klik → eksisterende Lightbox) + statuslinje
   (`slags · uploadStatus · dimensioner · byte-størrelse · original_filnavn`).
2. **Metadata-form:** `titel` (input), `slags` (samme `MEDIA_SLAGS`-chips som
   upload-arket), `kunstner` (input), `datering` (input, fritekst som DB-feltet).
   "Gem" → `run({ art: 'opdaterMedia', … })` (payload = kun ændrede felter;
   ryddet felt sendes som `''`). Dry-run/LIVE-flowet genbruges uændret.
3. **Rettigheds-panel:** chips for de seks `media_rettigheder_status`-vocab-værdier
   + "Må publiceres"-checkbox + tre valgfrie dokumentationsfelter (licens,
   kildehenvisning, gengivelsestilladelse) + kilde-fritekst. "Gem rettigheder" →
   `mediaRettigheder`-changen. **Klient-nudge (ikke server-tvang, jf. koncept
   §4.4):** `spaerret`/`begraenset` + publiceret viser en advarselslinje før Gem.
4. **Handlinger:** eksisterende "Fjern" (afkobl) og "Slet" (blødt fjern) flytter
   med ind i overlayet (beholdes også som hurtig-links i galleriet); for
   `uploadStatus === 'fjernet'` vises i stedet **"Genopret"** →
   `genopretMedia`-changen.

Refetch-betingelsen for medie-listen (`mediaChanged`-boolean fra Slice 0h)
udvides med de tre nye arter.

### 6.2 Galleri + upload-ark

- Fjernede medier: dæmpet thumb (opacity) + status-teksten viser allerede
  `· fjernet` via eksisterende `uploadStatus`-suffix; Fjern/Slet erstattes af
  Genopret for disse.
- Upload-arket får `kunstner`- og `datering`-inputs + rettigheds-status-chips
  (default `'ukendt'`); "Må publiceres"-checkboxen består. Payload udvides jf. §4.

## 7. Skive 5 — mobile-UI

- **Ny `MediaDetaljeSheet.tsx`** (mønster: `MediaUploadSheet`) med samme fire
  blokke som web-overlayet (§6.1). Åbnes ved tap på thumb i `MediaGallery`
  (Lightbox flytter ind bag preview-tap i sheetet — `MediaGallery` får en
  `onVaelg`-callback i stedet for direkte lightbox-state).
- `MaterialeSektion` og person-editoren (`app/redaktion/person/[id].tsx`) wire'r
  sheetet + de tre nye Change-arter gennem deres eksisterende
  `SkrivePreviewSheet`-flow og `refreshMedia()`-kontrakt.
- `MediaUploadSheet` udvides som web (§6.2): kunstner/datering/rettigheds-status.
- Mobile beholder fuld funktionel paritet (koncept §7): hele filsiden, ikke en
  reduceret udgave.

---

## 8. Verifikation

- **DB (lokalt):** frisk `schema.sql`-install + `db-migrations.sql` kørt to gange
  (idempotens, inkl. DROP+CREATE-blokken) mod lokal Postgres; RPC-asserts fra
  §3.4; `db-verify-media.sql` udvidet gating-assert grøn.
- **Enheds-tests:** nye buildRpcCall/mapPersonMediaRows-tests (vitest 155+ / jest
  272+ forbliver grønne); tsc begge platforme; web-build.
- **Empirisk:** web mod prod-svarende base — redigér metadata, frigiv et
  upubliceret billede (rettigheds-flowet ende-til-ende: upload upubliceret →
  filside → status + publicér → synligt anonymt), slet → genopret. Mobile:
  simulator-gennemløb af samme tre flows (kendt begrænsning: ingen automatiseret
  UI-driver i repo'et — manuel verifikation som Slice 0g/0h).
- **Prod-deploy:** controller-gated som al DDL (backup + bruger-OK); migrationen
  navngives `mediehaandtering_fase1_filside`.

## 9. Åbne punkter (afklares ved plan/implementering, blokerer ikke spec)

1. **`slags`-vocab-nudge:** filsiden genbruger upload-arkets faste `MEDIA_SLAGS`-
   liste (de facto-nudge). Fritekst-slags fra evt. fremtidig bulk-import vises
   som ekstra chip. (Koncept-§10.4's generelle vocab-FK-beslutning røres ikke.)
2. **Genopret-adgang uden relation:** et fjernet medie hvis *relation* også er
   slettet er usynligt i subjekt-gallerierne — det kan først genoprettes når
   biblioteket (fase 2) lander. Accepteret hul i fase 1 (dokumentér i changelog).
3. **To-change-UX på filsiden:** metadata og rettigheder gemmes som to separate
   changes (to change_sets — matcher RPC-skæringen og gør fortryd granulær).
   Hvis det føles klodset i praksis, kan en kombineret "Gem alt"-kø overvejes i
   fase 2 — ikke nu.
