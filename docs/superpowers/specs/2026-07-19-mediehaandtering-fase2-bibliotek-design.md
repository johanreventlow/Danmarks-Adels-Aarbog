# Mediehåndtering — fase 2: biblioteket & "bruges på" (design-spec)

**Dato:** 2026-07-19
**Styringsgrundlag:** `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` §4.1 (filsidens
"bruges på"-del), §4.2 (biblioteket + arbejdskøer), §9 (fase 2).
**Bygger på fase 1 (merget, PR #59):** filsiden (`web/src/components/MediaDetaljeOverlay.tsx`,
`mobile/src/components/redaktion/MediaDetaljeSheet.tsx`), det udvidede redaktions-læselag
(fuld feltliste + `'fjernet'` beholdt) og RPC'erne `red_opdater_media`/`red_genopret_media`.
**Mål:** medier bliver en *forvaltet samling*: én tværgående biblioteksflade med søgning og
arbejdskøer (M7), en "bruges på"-visning med advarsel før fjern/slet (M6), synlighed for
strandede uploads (M9's synlighedsdel) og genbrug af eksisterende medier på nye subjekter (M5).

**Beslutninger arvet fra konceptet:** web er primærflade for kø-/biblioteksarbejde, mobile
fuld pr.-medie-funktionalitet men forenklet oversigt (koncept §7 — dette lukker samtidig
koncept-§10.5: mobile får kø-tællere + liste + filside, ikke fuld kø-paritet). Dubletkøen
(koncept §4.2 kø 5) venter på fase 3's sha256; udrensning venter på fase 4.
**Uden for scope:** sha256/dedup/janitor (fase 3), erstat-fil/udrens/portræt-flag (fase 4),
oprydning af strandede uploads (fase 3 — fase 2 gør dem kun *synlige*).

---

## 1. Baggrund & afgrænsning (empirisk, jf. kortlægning 2026-07-19)

- **Web har allerede en "Medier"-fane** i navigationen (`Redaktion.tsx:56`, `ENTITY_DB:75`)
  — men den er tom: `fetchEntityRecords('media')` returnerer bevidst `[]`
  (`redaktionRead.ts:424-451`, "kommer"-tilstand). Fanen skal blot *fyldes*, ikke opfindes.
- **Mobile har en let tværgående `medieListe`** i aux-laget (`load.ts:168`,
  `buildAux.ts:179-183`) med kun `{id,titel,slags,kunstner,datering}` — vises read-only og
  u-tappbart i `redaktion/entitet/[type].tsx:33,64` (`HAR_MATERIALE` dækker kun gods/våben).
- **"Bruges på"-byggeklodserne findes:** `text_mention` indekserer allerede
  `[[media:id|…]]`-tokens (`schema.sql:2140-2158`, `ix_text_mention_maal`), og
  `afbildet`-relationer ligger i `relation` i to retninger (person→media; media→objekt).
  Men ingen omvendt fetch ("hvem bruger dette medie?") findes, og `red_doede_links`
  dækker IKKE `maal_type='media'` (`schema.sql:2212-2216`).
- **Genbrug af eksisterende medie:** `red_relation(...,'afbildet')` findes, er granted og
  GDPR-guardet server-side (`schema.sql:996-998`) — men ingen UI-flade kalder den med
  media. Al tilknytning sker i dag kun via upload af NY fil.
- **Filside-komponenterne er rene props/callback-komponenter** på `PersonMedia` — kan
  genbruges fra biblioteket uden ændring af deres kontrakt (kun additive props).
- **`media` har ingen `created_at`** — "strandede uploads ældre end 24t" (koncept §4.2
  kø 3) kan ikke udtrykkes. Fase 2-beslutning: køen viser ALLE `kladde`/`fejlet` uden
  aldersfilter (de er få, og enhver strandet kladde er værd at se). En evt.
  `created_at`-kolonne udskydes til fase 3's janitor-behov (åbent punkt §9.1).

**I scope:** tværgående biblioteks-fetch + kø-klassifikation (ren, testbar funktion);
"bruges på"-fetch pr. medie; web-biblioteket i den eksisterende Medier-fane (søgning,
kø-chips, gitter, klik → fase 1-overlayet udvidet med "bruges på" + advarsel); ny
Change-art `tilknytMedia` → `red_relation`; mobile: tappbare medie-rækker + kø-chips +
`MediaDetaljeSheet` med "bruges på"; `red_doede_links` udvidet med media-gren.
**Én lille DB-ændring** (view-udvidelsen) — ellers ingen skema/RLS/RPC-ændringer:
redaktionen ser allerede alt via `redaktion_read`-politikkerne.

---

## 2. Skæring (6 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | DB: `red_doede_links` + media-gren | `schema.sql`, `db-migrations.sql`, `db-verify.sql` | lokal Postgres: view fanger mention → slettet media-række |
| 2 | Læse-lag: bibliotek + anvendelse + kø-klassifikation (begge platforme) | `web/src/data/redaktionRead.ts`, `mobile/src/data/redaktionRead.ts` (+ tests) | vitest/jest på `klassificerMedie`/mapping; netværksfrit |
| 3 | Skrive-lag: `tilknytMedia` (begge platforme) | `web/src/data/redaktionWrite.ts`, `mobile/src/data/redaktionWrite.ts` (+ tests) | vitest/jest på retnings-logikken |
| 4 | Web: biblioteket i Medier-fanen + overlay-udvidelse + tilknyt-picker | `web/src/Redaktion.tsx`, `web/src/components/MediaDetaljeOverlay.tsx` | tsc + vitest + build; browser-røgtest |
| 5 | Mobile: tappbare medie-rækker + kø-chips + sheet-udvidelse | `mobile/src/app/redaktion/entitet/[type].tsx`, ny `medie.tsx`-skærm, `MediaDetaljeSheet.tsx`, `buildAux.ts`/`load.ts` | tsc + jest; simulator-verifikation |
| 6 | Verifikation & afstemning | changelog, koncept-§9-tabellen, `docs/database-current-state.md` | fuld suite grøn |

1 og 2 er uafhængige; 2 er forudsætning for 4+5; 3 for tilknyt-delene af 4+5.
Prod-DDL (skive 1) er som altid controller-gated (backup + bruger-OK).

---

## 3. Skive 1 — `red_doede_links` udvides med media

Viewet (`schema.sql:2212-2216`, `security_invoker`) får en fjerde gren:

```sql
OR (m.maal_type='media' AND NOT EXISTS (SELECT 1 FROM media md WHERE md.id=m.maal_id))
```

- **Kun ikke-eksisterende media** regnes som døde links (rækken er udrenset/aldrig fandtes).
  Mentions der peger på et *fjernet* medie er IKKE døde — mediet findes og kan genoprettes;
  de synliggøres i stedet i papirkurvs-køens "bruges på" (skive 2). Dermed ingen
  fjernet-særlogik i viewet, og viewets anon-adfærd er uændret (security_invoker +
  media-RLS betyder blot at anon aldrig når media-grenen — viewet læses kun af redaktionen
  via `fetchDoedeLinks`, `mobile/src/data/redaktionRead.ts:615-620`).
- `db-migrations.sql`: `CREATE OR REPLACE VIEW` (idempotent, filens mønster).
- `db-verify.sql`: assert — seed narrativ med `[[media:-999...]]`-token (trigger fylder
  `text_mention`) → viewet indeholder rækken; seed eksisterende media → gør ikke.

## 4. Skive 2 — læse-laget: bibliotek, anvendelse, køer

Alle nye funktioner spejles web/mobile ("hold i sync"); mobile returnerer
`thumbStoragePath`, web signerer selv (fase 1-mønstrene fortsætter uændret).

### 4.1 `fetchMediaBibliotek(): Promise<MediaBibliotekPost[]>`

Fire `getAll`-paginerede queries, joinet klient-side (buildAux-mønsteret — ingen nye
DB-objekter):

1. `media` — ALLE rækker, fase 1-feltlisten (redaktionen ser alt inkl. `kladde`/`fjernet`).
2. `relation` hvor `objekt_type='media' AND rolle='afbildet'` (person→media).
3. `relation` hvor `subjekt_type='media' AND rolle='afbildet'` (media→gods/våben/linje).
4. `text_mention` hvor `maal_type='media'` (rammer `ix_text_mention_maal`).

`MediaBibliotekPost` = `PersonMedia`-felterne (uden `relationId` — biblioteket er ikke
subjekt-bundet) + `antalAfbildet: number` + `antalMentions: number` + `koeer: MedieKoe[]`.
Thumb-opslag genbruger fase 1-mekanikken (`media_variant tier='thumb'`).

### 4.2 Kø-klassifikation — ren, delt-pr.-platform funktion

```ts
type MedieKoe = 'rettigheder' | 'loese' | 'strandede' | 'papirkurv';
function klassificerMedie(m, antalAfbildet, antalMentions): MedieKoe[]
```

| Kø | Regel (koncept §4.2, tilpasset §1-fundene) |
|---|---|
| `rettigheder` | `uploadStatus='klar'` og (`rettighederStatus='ukendt'` eller `!maaPubliceres`) |
| `loese` | `uploadStatus='klar'` og `antalAfbildet=0` og `antalMentions=0` |
| `strandede` | `uploadStatus IN ('kladde','fejlet')` — intet aldersfilter (ingen `created_at`, §1) |
| `papirkurv` | `uploadStatus='fjernet'` |

Et medie kan stå i flere køer (`rettigheder`+`loese` er almindeligt for bulk-materiale).
Ren funktion → unit-testes udtømmende (alle statuskombinationer) uden netværk.

### 4.3 `fetchMediaAnvendelse(mediaId): Promise<MediaAnvendelse>` — "bruges på"

Hentes on-demand når filsiden åbnes (ikke for hele biblioteket — tællingerne fra §4.1
dækker listen). Tre små queries på ét id:

- person→media-relationer → opslag af `visning_navn` (personer der afbildes)
- media→objekt-relationer → opslag af estate/coa/lineage-navne
- `text_mention` → `kilde_type/kilde_id` opløst til narrativets subjekt (join mod
  `narrative.subjekt_type/subjekt_id` + navneopslag) så listen viser "narrativ på X",
  ikke rå id'er

`MediaAnvendelse` = `{ afbildet: {type, id, navn, relationId}[], mentions: {kildeType,
kildeId, subjektNavn}[] }`. `relationId` medtages så "Fjern tilknytning" kan tilbydes
pr. række (genbruger `sletRelation`-arten uændret).

## 5. Skive 3 — skrive-laget: `tilknytMedia` (M5)

Ny Change-art i begge `redaktionWrite.ts` (spejlet):

```ts
{ art: 'tilknytMedia', mediaId, payload: { maalType: 'person'|'estate'|'coat_of_arms'|'lineage', maalId } }
```

`buildRpcCall`-grenen bygger det korrekt-rettede `red_relation`-kald og spejler
`red_upload_media`s egen forgrening (GDPR-invarianten: person skal stå på subjekt-siden):

- `maalType='person'` → `red_relation('person', maalId, 'media', mediaId, 'afbildet')`
- ellers → `red_relation('media', mediaId, maalType, maalId, 'afbildet')`

Server-guarden (`schema.sql:996-998`) forbliver bagstopperen — klient-retningen er
bekvemmelighed, ikke sikkerhed. Ingen fil-bytes → arten kan degradere til `red_suggest`
(som fase 1's tre arter; ingen submitChange-gate). `oversaetFejl` udvides med
`red_relation`s afbildet-person-guard-tekst. Tests: begge retninger, manglende id → null.

## 6. Skive 4 — web: biblioteket

### 6.1 Medier-fanen fyldes

`fetchEntityRecords('media')`-grenen erstattes af `fetchMediaBibliotek()`; media får sin
egen liste-rendering i midterpanelet (fanen og URL-grammatikken `/redaktion/media/:id`
findes allerede):

- **Kø-chips** øverst: `Alle · Rettigheder (n) · Løse (n) · Strandede (n) · Papirkurv (n)`
  — klient-side filter på `koeer` + tællere. Chip-stilen genbruges fra `MEDIA_SLAGS`-chips.
- **Rækker/gitter:** thumb (fjernet = dæmpet, fase 1-mønsteret), titel, slags,
  status-badges (`uploadStatus`≠klar, "ej publiceret"), `antalAfbildet + antalMentions`
  som diskret "bruges 3 steder"-tekst. Eksisterende søgefelt filtrerer på
  titel/kunstner/original_filnavn.
- **Format-defensiv rendering (koncept §4.8, tilføjet 2026-07-19):** biblioteket og
  filsiden må ikke ANTAGE billede-mime. Et medie uden brugbar thumb — eller med
  `mime_type` uden for `image/*` (fremtidige PDF'er/dokumenter, koncept-fase 5) —
  renderes med et dokument-ikon-felt (samme dimensioner som thumb, `slags`-tekst i
  feltet) i stedet for tom/knækket thumbnail, og udelades af Lightbox. Gælder også
  mobile (§7). Ingen scope-udvidelse — kun en fallback-gren i thumb-renderingen.
- **Klik på række** → `MediaDetaljeOverlay` (samme instans som fase 1; biblioteket sender
  `media` uden `relationId` → "Fjern tilknytning" er allerede disabled by design).

### 6.2 Overlay-udvidelse: "bruges på" + advarsel (M6)

`MediaDetaljeOverlay` får en valgfri `anvendelse?: MediaAnvendelse`-prop (+ `onFjernTilknytning(relationId)`,
`onTilknyt()`-callbacks) og rendrer en ny sektion mellem rettigheds-panelet og handlingerne:

- Liste over afbildede subjekter (med pr.-række "Fjern") og narrativ-mentions (read-only
  — tokens i prosa ryddes manuelt, koncept §4.3).
- **Slet-advarsel:** når `anvendelse` viser brug (>0), skifter "Slet billede" til
  to-trins bekræft: "Bruges på 2 personer og i 1 narrativ — slet alligevel?" (mentions
  bliver hængende som inaktive tokens; teksten siger det eksplicit). Ubrugte medier
  sletter som i dag i ét klik.
- Kalderne (person-editor, objekt-materiale, bibliotek) henter `fetchMediaAnvendelse`
  ved åbning og sender den med — overlayet forbliver fetch-frit.

### 6.3 Tilknyt-picker

"Tilknyt til person/gods/våben/linje…"-knap i overlayet (og i biblioteksrækkens
papirkurvs-/løse-visning). Åbner en søge-picker (genbrug entitets-søgemønsteret fra
`renderList`/pickers i `Redaktion.tsx`) → valg udløser `run({art:'tilknytMedia', …})`.
Refetch-betingelsen (`mediaChanged`) udvides med `tilknytMedia`.

## 7. Skive 5 — mobile: forenklet bibliotek

- **`buildAux`/`load.ts`:** `medieListe` udvides med `uploadStatus`, `maaPubliceres`,
  `rettighederStatus` (+ kø-tællere beregnet med samme `klassificerMedie`; anvendelses-
  tællinger fra de relation/text_mention-data load allerede henter/udvides med).
- **`entitet/[type].tsx`:** medie-rækker bliver tappbare; kø-chips med tællere øverst
  (samme filterprincip som web). Tap → ny let skærm `redaktion/entitet/medie.tsx`
  (mønster: `materiale.tsx`) der henter fuld `PersonMedia` + `MediaAnvendelse` og åbner
  `MediaDetaljeSheet`.
- **`MediaDetaljeSheet`** får samme valgfri `anvendelse`-prop, "bruges på"-sektion og
  slet-advarsel som web-overlayet (§6.2). Tilknyt-picker: genbrug
  `MediaMentionPicker`-mønsteret til subjekt-søgning → `tilknytMedia`-changen.
- Fuld kø-*behandling* (masseflow) forbliver web — mobilen kan se, åbne og handle på
  enkeltmedier (fuld pr.-medie-paritet, koncept §7).

## 8. Verifikation

- **DB (lokalt):** frisk install + migrationssti ×2; nye `red_doede_links`-asserts grønne;
  eksisterende verify-filer uden regression.
- **Enheds-tests:** `klassificerMedie` (alle kombinationer), bibliotek-/anvendelses-mapping,
  `tilknytMedia`-retningslogik — spejlet vitest/jest; tsc + build begge platforme.
- **Empirisk (dev/prod-svarende base):** upload upubliceret → står i rettigheds-køen →
  frigiv fra biblioteket → forsvinder fra køen; løst medie → tilknyt person → forsvinder
  fra løse-køen og personen viser billedet; slet medie med anvendelser → advarsel viser
  de rigtige navne; papirkurv → genopret. Mobile: simulator-spejl af kø-chips + tap →
  sheet → tilknyt.
- **Prod-deploy:** kun view-ændringen (skive 1) er DDL — gated som altid; navngiven
  migration `mediehaandtering_fase2_doede_links`.

## 9. Åbne punkter (blokerer ikke spec'en)

1. **`media.created_at`:** uden tidsstempel kan strandede-køen ikke aldersfiltreres og
   fase 3's janitor ikke skelne "nyt igangværende upload" fra "strandet for uger siden".
   Beslut ved fase 3: additiv `created_at timestamptz DEFAULT now()` (NULL for
   eksisterende rækker = "ukendt alder").
2. **Ydelse ved vækst:** fire fulde tabel-fetches er fint ved nuværende skala (hundreder);
   når bulk-import (plan-Slice 2) lander tusinder, kan biblioteket få server-side
   pagination/søgning. Ingen præmatur optimering nu.
3. **Kø 5 (dubletter)** aktiveres i fase 3 når sha256 reelt beregnes — bibliotekets
   chip-række er forberedt på en ekstra kø uden strukturændring.
