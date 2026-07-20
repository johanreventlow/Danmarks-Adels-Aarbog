# Mediehåndtering — fase 3: hygiejne — dedup, deterministiske stier, janitor (design-spec)

**Dato:** 2026-07-20
**Styringsgrundlag:** `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` §4.6
(upload-hygiejne), §4.2 kø 5 (dubletter), §9 (fase 3), §10 punkt 1–3.
**Bygger på fase 1 (merget) + fase 2 (implementeret lokalt):** filsiden
(`web/src/components/MediaDetaljeOverlay.tsx`, `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`),
biblioteket med køerne 1–4 (`fetchMediaBibliotek`/`klassificerMedie`,
`web/src/data/redaktionRead.ts:776-863`, `mobile/src/data/redaktionRead.ts:732-807`)
og tilknyt-flowet (`tilknytMedia` → `red_relation`, `web/src/data/redaktionWrite.ts:327-342`).
**Mål:** dedup-mekanismen går fra død til aktiv (M8): klienten beregner sha256, stier bliver
deterministiske og upload idempotent; strandede uploads og forældreløse Storage-objekter kan
ryddes op (M9's oprydningsdel) via et forsigtigt janitor-R-script; biblioteket får dubletkøen
(kø 5) og et aldersbegreb for strandede uploads (`media.created_at`).

**Beslutninger arvet fra konceptet:** DB-guarden og `media_sha256_uidx` findes allerede og
røres ikke; dedup skal opleves som en hjælp ("billedet findes allerede → tilknyt i stedet"),
ikke en fejlbesked; janitor følger read-only-rapport-først-mønsteret; ingen migrering af
eksisterende fase-0/1/2-stier — kun nye uploads får sha-stier.
**Uden for scope:** erstat fil/udrensning/portræt-flag (fase 4 — "flet dubletter" i denne fase
stopper derfor ved *blødt* fjern af kopien), bulk-R-import (plan-Slice 2, ikke implementeret —
men janitor/sti-designet er kompatibelt med dens tiltænkte `import/<xx>/<sha>`-mønster,
`docs/superpowers/plans/2026-07-04-mediehaandtering.md:145-150`), dokumenter (fase 5).
**HEIC på web er eksplicit IKKE en fase 3-opgave:** begrænsningen består uændret
(`web/src/data/mediaUpload.ts:26-35` fejler eksplicit med henvisning til mobilappen) og er
ortogonal til hygiejne — en WASM-dekoder er en feature, ikke oprydning (koncept §4.6 sidste
punkt: "ikke en del af dette koncept").

---

## 1. Baggrund & afgrænsning (empirisk, verificeret på main 2026-07-20)

- **Klienten hasher aldrig.** Ingen forekomst af sha256/crypto i `web/src` eller `mobile/src`
  (grep). Stierne er tilfældige: `redaktor/${Date.now()}-${rand}` i BEGGE platforme
  (`web/src/data/mediaUpload.ts:18-21`, `mobile/src/lib/mediaUpload.ts:51-54`), og
  `performUpload` kører `upsert: false` (`web/src/data/mediaUpload.ts:74-80`,
  `mobile/src/lib/mediaUpload.ts:98-106`).
- **DB-siden er komplet men reelt død kode:** `media.sha256` (`schema.sql:79`),
  `media_sha256_uidx` partial-unique (`schema.sql:89`), dedup-guarden i `red_opret_media`
  (`schema.sql:1885-1887`, domæne-fejl *"Medie med samme indhold findes allerede (sha256=%)…"*),
  og `p_sha256`-parametre hele vejen gennem `red_bekraeft_media_upload` (`schema.sql:1900,1909`)
  og `red_upload_media` (`schema.sql:1922,1930`). Klienten sender dem aldrig
  (`web/src/data/redaktionWrite.ts:309-325` bygger args uden `p_sha256`; mobile spejler).
- **`media` har fortsat ingen `created_at`** (`schema.sql:64-87`) — fase 2-spec §9.1's
  observation gælder stadig. Strandede-køen viser derfor ALLE `kladde`/`fejlet` uden alder
  (`klassificerMedie`, `web/src/data/redaktionRead.ts:790`). Bemærk: `'fejlet'` er dokumenteret
  i kolonnekommentaren (`schema.sql:81`) men sættes aldrig af nogen kodevej — den praktiske
  strandede tilstand er `'kladde'`.
- **Fase 2's kendte dublet-gap:** `relation` (`schema.sql:354-367`) har ingen unikhed;
  `red_relation` (`schema.sql:1187-1208`) INSERT'er blindt. Identiske `afbildet`-relationer
  kan derfor opstå ved dobbeltklik/samtidige kald (changelog-entry "fase 2 — biblioteket").
  Andre roller (fx `'ejer'`) har LEGITIME gentagelser af samme (subjekt, objekt)-par med
  forskellige perioder (`start_min`/`end_min`-kolonnerne er netop til det) — et globalt unikt
  index på `(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)` er derfor udelukket; et
  *partielt* på `WHERE rolle='afbildet'` er sikkert (en person er afbildet på et billede én
  gang; Slice 3's kommende `kvalifikator`-kolonne forudsætter netop én række pr. par).
- **sha-dubletter er strukturelt umulige i DB:** `media_sha256_uidx` er UNIQUE — to rækker
  kan aldrig dele sha256. Dubletter fra før fase 3 har `sha256 IS NULL` (blev aldrig beregnet)
  og kan KUN opdages via bytes (backfill) eller heuristik. Kø 5 kan altså ikke være en
  "samme sha på flere rækker"-query — det skal spec'en være ærlig om (§6).
- **R-infrastruktur:** ingen `import_media.R` findes (plan-Slice 2 ubygget). Præcedenser:
  `load_daa.R` (DBI/RPostgres, login fra `~/.Renviron` med `SUPABASE_HOST/USER/PASSWORD`,
  `.claude/skills/daa-extract/scripts/load_daa.R:68-71`; `--dry-run`-flag og eksplicit
  destruktivt `--reset`-flag efter "glemt flag må ikke destruere"-læringen), `R/geo-enrich/`
  (httr2 til ekstern REST, `03-geocode.R:12,18`), `R/tng-qa/` (rapport-pipeline). Bulk-load
  kører bevidst uden `change_set` (plan:150).
- **Test-konventioner:** web-vitest kører `environment: 'node'` (`web/vitest.config.ts:6`) på
  Node 22 — `globalThis.crypto.subtle` (Web Crypto) findes NATIVT i test-miljøet; der findes
  intet crypto-mock/polyfill-mønster i suiten (setup.ts mocker kun maplibre-gl), og der
  behøves ingen: sha256-helperen kan testes deterministisk mod kendte vektorer direkte.
  `mediaUpload.ts` har i dag INGEN tests på nogen platform; mobile-filens header fastslår
  konventionen "rører device-native API'er → ikke unit-testet" (`mobile/src/lib/mediaUpload.ts:1-3`).
- **Mobile-crypto:** `expo-crypto` er IKKE installeret (`mobile/package.json:15-44`) — skal
  tilføjes (`~56.x`, Expo SDK-modul, med i Expo Go; dev-/standalone-builds skal genbygges).
  Hermes har ingen Web Crypto, så web-koden kan ikke genbruges 1:1 (sædvanlig
  "ét mønster, to implementeringer"-kontrakt).
- **Fase 2's RLS-rettelse er i main** (afvigelse fra fase 2-spec'en, verificeret):
  `text_mention` har `GRANT SELECT` + media-mål gates via `media_synlig_anon`
  (`db-rls.sql:697-723`) i stedet for `entitet_offentlig`s ubetingede media→true-gren
  (`db-rls.sql:84`). Fase 3 rører ingen RLS — men spec'ens DB-arbejde skal forankres i den
  FAKTISKE `db-rls.sql`/`db-migrations.sql`, ikke i fase 2-planens tekst.

**I scope:** additiv `media.created_at`; partielt unikt `afbildet`-index + domæne-fejl i
`red_relation`; klient-sha256 + sha-stier + idempotent upload + dedup-UX (begge platforme);
strandede-køen får alder; dubletkøen (kø 5) + "flet ind i…"-flow (web); janitor-R-script
med rapport/`--slet`; verify-asserts og afstemning.

---

## 2. Skæring (6 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | DB: `created_at` + `afbildet`-unikhed | `schema.sql`, `db-migrations.sql`, `db-verify-media.sql` | lokal Postgres: frisk install + migrationssti ×2; asserts |
| 2 | Web: sha256 + sha-stier + dedup-UX | `web/src/data/mediaUpload.ts`, ny `web/src/data/mediaPaths.ts`, `redaktionWrite.ts`, `Redaktion.tsx` (+ tests) | vitest (hash-vektorer, sti-bygning, buildRpcCall), tsc, build |
| 3 | Mobile: samme, via expo-crypto | `mobile/src/lib/mediaUpload.ts`, ny `mobile/src/lib/mediaPaths.ts`, `redaktionWrite.ts`, `MediaUploadSheet.tsx`, `package.json` | jest (sti-bygning, buildRpcCall), tsc; simulator-røgtest |
| 4 | Bibliotek: alder på strandede + dubletkø + flet | `web/src/data/redaktionRead.ts`, `mobile/src/data/redaktionRead.ts`, `web/src/Redaktion.tsx`, `MediaDetaljeOverlay.tsx` (+ tests) | vitest/jest på klassifikation/heuristik; netværksfrit |
| 5 | Janitor: `R/media-janitor.R` | ny R-fil (+ evt. `tests/testthat/test-media-janitor.R` for rene helpers) | kørsel mod lokal Postgres + dev-bucket; rapport før slet |
| 6 | Verifikation & afstemning | changelog, koncept-§9, `docs/database-current-state.md` | fuld suite grøn |

1 er forudsætning for 4 (created_at i læse-laget) og for 5 (janitorens aldersbegreb);
2 og 3 er indbyrdes uafhængige spejlinger; 5 kan bygges parallelt med 2–4.
Prod-DDL (skive 1) er som altid controller-gated (backup + bruger-OK) og skal samles med
de endnu ikke-deployede fase 1+2-migrationer i ét gated deploy.

---

## 3. Skive 1 — DB: `created_at` + `afbildet`-unikhed

### 3.1 `media.created_at` (additiv, jf. fase 2-spec §9.1)

```sql
ALTER TABLE media ADD COLUMN IF NOT EXISTS created_at timestamptz;
ALTER TABLE media ALTER COLUMN created_at SET DEFAULT now();
```

⚠ **Postgres-faldgrube (skal med i migrationen):** ét-trins `ADD COLUMN … DEFAULT now()`
udfylder ALLE eksisterende rækker med migrations-tidspunktet (now() er ikke-volatil →
fast-default-stien) — alle gamle medier ville lyve sig "nye". To-trins-formen ovenfor giver
eksisterende rækker `NULL` (= "ukendt alder", ærligt) og nye rækker `now()`. `schema.sql`
(frisk install) skriver kolonnen med `DEFAULT now()` direkte i CREATE TABLE.
Ingen backfill: gamle rækkers alder er reelt ukendt, og janitoren behandler `NULL`
fail-safe (§7). `trg_log_media` snapshotter kolonnen automatisk (jsonb-rækkesnapshot) —
ingen versioneringsændring.

### 3.2 Partielt unikt index lukker fase 2's dublet-gap

```sql
-- oprydning FØR index (identiske afbildet-dubletter fra dobbeltklik; behold laveste id):
DELETE FROM relation r USING relation r2
 WHERE r.rolle='afbildet' AND r2.rolle='afbildet' AND r.id > r2.id
   AND r.subjekt_type=r2.subjekt_type AND r.subjekt_id=r2.subjekt_id
   AND r.objekt_type=r2.objekt_type   AND r.objekt_id=r2.objekt_id;
CREATE UNIQUE INDEX IF NOT EXISTS relation_afbildet_uidx
  ON relation (subjekt_type, subjekt_id, objekt_type, objekt_id)
  WHERE rolle='afbildet';
```

- **Kun `afbildet`** (partielt): et globalt index ville bryde periode-bårne roller
  (`'ejer'` med ejet→solgt→generhvervet er tre legitime rækker, §1). `afbildet` har ingen
  periode-semantik, og Slice 3's kvalifikator (bbox/primær-flag) forudsætter netop én række
  pr. par — indexet er dens forudsætning, ikke dens konkurrent.
- **Oprydningen skal være evidens-sikker:** upload-skabte afbildet-dubletter bærer i
  praksis ingen assertions (de skabes af `red_upload_media`/`tilknytMedia`, aldrig af
  load-scripts med evidens) — men assertions peger pr. relations-id, så en naiv DELETE
  ville forældreløse evidens på den slettede række. Betingelsen strammes derfor: DELETE
  rammer kun dublet-rækker UDEN assertion/conclusion/note
  (`NOT EXISTS (… target_type='relation' AND target_id=r.id)`). Overlever en
  evidens-bærende dublet oprydningen, fejler `CREATE UNIQUE INDEX` højlydt → manuel
  afgørelse (fail-loud frem for stille evidens-tab).
- **`red_relation` fanger `unique_violation`** for `rolle='afbildet'` og genudløser som
  domæne-fejl *"Mediet er allerede tilknyttet dette subjekt"* — pænere end rå
  duplicate-key, og `oversaetFejl`s eksisterende `/duplicate key|unique/`-fallback
  (`web/src/data/redaktionWrite.ts:490`) suppleres med den præcise tekst (skive 2/3).
  Applikations-dedup i pickerne (fase 2 skjuler allerede tilknyttede mål) består som UX;
  indexet er bagstopperen.

### 3.3 `db-verify-media.sql` + lokale RPC-asserts

- Verify-filens kontrakt er RLS-asserts uden redaktør-kontekst (fase 1-spec §3.4) —
  her tilføjes det der passer: seed to identiske afbildet-rækker via direkte INSERT →
  forvent unique_violation; `created_at` er NULL-bar og default-udfyldt ved INSERT.
- Lokalt (frisk install + migrationssti ×2, idempotens inkl. DELETE+CREATE INDEX-blokken):
  `red_upload_media` med `p_sha256` → række med sha; gentaget kald samme sha → dedup-guardens
  domæne-fejl; `red_relation` dublet-afbildet → ny domæne-fejl; `created_at` sat på ny række,
  NULL på præ-eksisterende.

---

## 4. Skive 2 — web: sha256, deterministiske stier, dedup-UX

### 4.1 Hash + stier (`mediaPaths.ts`, ny ren fil + `mediaUpload.ts`-omlægning)

- **Ny `web/src/data/mediaPaths.ts`** (ren, netværks-/DOM-fri, spejles på mobile §5):
  `hexEncode(bytes: Uint8Array): string` og
  `buildShaStoragePaths(sha: string): Record<MediaTier, string>` →
  `redaktor/<sha[0..2]>/<sha>-{thumb|medium|large}.jpg`. To-tegns-præfixet sharder
  bucket-listning (Commons-mønsteret; plan-Slice 2 valgte samme form for `import/`).
- **`mediaUpload.ts`:** `sha256Hex(blob: Blob): Promise<string>` via
  `crypto.subtle.digest('SHA-256', await blob.arrayBuffer())` (secure context: localhost-dev
  + https-prod — begge opfyldt). `buildVariants` omlægges: genkod de tre tiers FØRST (uden
  stier), hash `large`-blobbens bytes, og tildel dernæst stier via `buildShaStoragePaths`.
  `buildStoragePathBase()` (`mediaUpload.ts:18-21`) slettes. Returtypen udvides med `sha256`.
- **Sha er af de GENKODEDE large-bytes,** ikke kildefilen — det er dét, der ligger i
  Storage og på media-rækken, og dét stien skal være deterministisk over. Ærlig konsekvens:
  dedup fanger "samme fil uploadet igen ad samme pipeline" (langt det hyppigste:
  dobbeltklik, genupload efter glemt upload, samme scanning to gange fra samme maskine) —
  men IKKE samme motiv uploadet fra hhv. web og mobile (to genkodere → forskellige bytes →
  forskellige sha). Perceptuel dedup er bevidst fravalgt; kø 5's heuristik (§6) er
  sikkerhedsnettet.
- **Idempotent upload:** `performUpload` beholder `upsert: false` men behandler
  Storage-fejlen "The resource already exists" (409/Duplicate) som succes — på en sha-sti
  BEVISER kollisionen at identiske bytes allerede ligger der (samme bytes → samme sti).
  Write-once-semantikken består (ingen blind overskrivning à la `upsert: true`); afbrudte
  forsøg kan genoptages uden at strø objekter (koncept §4.6).

### 4.2 Dedup-UX: pre-flight-tjek + guard-oversættelse

Upload-flowet (`submitChange`, `redaktionWrite.ts:446-485`) uploader bytes FØR RPC'en.
Uden pre-flight ville en dublet altså først opdages EFTER bytes-upload. Derfor:

1. **Pre-flight (UX-laget, `Redaktion.tsx`-upload-arket):** efter `buildVariants` (sha
   kendt, intet uploadet endnu) slås sha op:
   `supabase.from('media').select('id,titel,upload_status,…').eq('sha256', sha)` —
   redaktionen ser alt via `redaktion_read`. Ved hit vises dialog i stedet for upload:
   - `upload_status='klar'`: **"Billedet findes allerede"** + thumb/titel af det
     eksisterende medie + knappen **"Tilknyt til [subjekt] i stedet"** → kører fase 2's
     `tilknytMedia`-change mod det aktuelle subjekt (dedup bliver en hjælp, koncept §4.6).
   - `'fjernet'`: besked om at mediet ligger i papirkurven + link til filsiden
     (genopret dér; ingen auto-genopret fra upload-arket).
   - `'kladde'`: **"Færdiggør afbrudt upload"** — re-upload bytes (idempotent, §4.1),
     kald `red_bekraeft_media_upload` + `red_registrer_media_variant` pr. tier og
     tilknyt om nødvendigt. Dét gør to-fase-uploadens kendte strandings-hul
     selvhelende for samme-fil-tilfældet.
2. **Server-guarden er race-bagstopperen** (to redaktører, samme fil, samme minut):
   `red_upload_media` fejler med guard-teksten; `oversaetFejl` udvides med
   `/medie med samme indhold findes allerede/i` → *"Billedet findes allerede i
   biblioteket — brug 'Tilknyt eksisterende' i stedet."* (+ `/allerede tilknyttet/i`
   fra §3.2). Race-tilfældets allerede-uploadede bytes ligger på den VINDENDE rækkes
   egen sha-sti (samme sha → samme sti) — intet orphan; kun hvis vinderen er en
   præ-fase-3-række med backfillet sha og gammel sti (janitor-opgave b, §7).
3. **`buildRpcCall`:** `uploadMedia`-payload/args udvides med `sha256` → `p_sha256`
   (`redaktionWrite.ts:312-318`); `red_bekraeft_media_upload` behøver den ikke igen
   (guarden skal fyre FØR rækken oprettes).

### 4.3 Tests (vitest, node-miljø — intet mock behøves, §1)

`hexEncode`/`buildShaStoragePaths` mod faste vektorer; `sha256Hex` mod NIST-vektoren
(tom streng → `e3b0c442…`) direkte på Node 22's native Web Crypto; `buildRpcCall` med
`sha256` i payload → `p_sha256` i args; oversaetFejl-grenene. Ingen browser-afhængighed.

## 5. Skive 3 — mobile: samme kontrakt via expo-crypto

- **`expo-crypto ~56.x` tilføjes** (`npx expo install expo-crypto`; med i Expo Go, men
  dev-/release-builds skal genbygges — noteres i PR/changelog). Hashen:
  `Crypto.digest(CryptoDigestAlgorithm.SHA256, bytes)` på `readFileBytes(large.uri)`
  (`mobile/src/lib/mediaUpload.ts:43-46` genbruges — large-variantens fil læses alligevel
  til upload).
- **Ny `mobile/src/lib/mediaPaths.ts`** — tegn-for-tegn spejl af web-udgaven (samme
  "hold i sync"-kontrakt som `klassificerMedie`); jest-testbar (ingen native imports).
  `mediaUpload.ts` forbliver utestet native-glue per sin egen header-konvention
  (`mobile/src/lib/mediaUpload.ts:1-3`) — al testbar logik bor i `mediaPaths.ts`.
- `buildVariants` omlægges som web (§4.1): tiers → hash af large-bytes → sha-stier;
  `performUpload` gøres duplicate-tolerant; `buildStoragePathBase` (`:51-54`) slettes.
- `MediaUploadSheet` + `redaktionWrite.ts` spejler §4.2's pre-flight/dialog/fejltekster
  (forenklet dialog-UI er ok; funktionaliteten — tilknyt-i-stedet og færdiggør-kladde —
  skal med, jf. koncept §7: fuld pr.-medie-funktionalitet på mobile).

## 6. Skive 4 — biblioteket: alder på strandede + dubletkøen + flet

### 6.1 Strandede-køen får alder (created_at nu findes)

- Læse-lagets media-selects (fase 1-feltlisten, `web/src/data/redaktionRead.ts:745,848` +
  mobile-spejle) udvides med `created_at`; `PersonMedia`/`MediaBibliotekPost` får
  `createdAt: string | null`.
- **`klassificerMedie` ændres IKKE** (fase 2-beslutningen "enhver strandet kladde er værd
  at se" står ved magt — at SKJULE unge kladder ville genindføre usynlighed). I stedet:
  strandede-køens visning sorteres ældste-først og viser alder pr. række ("3 uger",
  "ukendt alder" for NULL, "under 1 time — muligvis i gang" som dæmpende mærkat).
  Ren formatteringsfunktion (`formatMedieAlder`), spejlet + testet.

### 6.2 Kø 5 — dubletter (ærlig udgave)

- **sha-baserede DB-dubletter kan ikke findes:** `media_sha256_uidx` gør to rækker med
  samme sha umulige, og præ-fase-3-rækker har `sha256 IS NULL` (§1). Koncept-§4.2's
  "samme sha256 på tværs af flere media-rækker" er altså strukturelt tom som kø-regel.
  Reel detektion af gamle dubletter kræver bytes — det er janitorens backfill-opgave (§7d),
  hvis rapport er den autoritative dublet-liste.
- **Køen i biblioteket kører derfor på en heuristik:** `dubletter`-kø for `klar`-medier
  der deler `(byte_size, bredde, hoejde)` med mindst ét andet `klar`-medie (alle tre
  felter er allerede i bibliotekets fetch — nul nye queries). Trillingen er et stærkt
  signal ved identiske genkodninger og billig at beregne i `mapMediaBibliotekRows`;
  falske positive er mulige (to forskellige billeder med præcis samme pixelmål OG
  bytestørrelse er dog sjældne) og køen præsenteres som **"Mulige dubletter"** — en
  gennemsynskø, ikke en dom. `klassificerMedie` får en ny parameter
  (`harDubletKandidat: boolean`, beregnet af kalderen) og `MedieKoe`-unionen udvides med
  `'dubletter'` — fase 2's chip-række er forberedt på en ekstra kø (fase 2-spec §9.3).
- Medier med udfyldt sha kan aldrig være ægte byte-dubletter af hinanden (indexet) —
  to sha-satte medier i samme trilling-gruppe er derfor pr. definition kun *perceptuelt*
  mistænkte; UI-teksten siger det.

### 6.3 "Flet ind i…" — hvad fase 3 reelt kan (og ikke kan)

Koncept-§10.3 spurgte: flet eller flag? Fase 3-svaret er **begge dele, men blødt**:
flowet om-peger og parkerer — den *reelle* udrensning af kopiens bytes/række er og
bliver fase 4 (`red_udrens_media`). Web-only handling på filsiden/dubletkøen:

1. Redaktøren står på kopien, vælger "Flet ind i…" → picker over dublet-gruppens øvrige
   medier (originalen).
2. Klient-orkestreret sekvens af EKSISTERENDE changes (ingen ny SQL): for hver
   `afbildet`-relation på kopien der ikke allerede findes på originalen (fase 2's
   `fetchMediaAnvendelse` leverer listen): `tilknytMedia`(original) → `sletRelation`(kopiens
   relation). Til sidst `fjernMedia`(kopien) → papirkurven.
3. **Narrativ-mentions flyttes IKKE automatisk** — `[[media:id|…]]`-tokens er redaktørens
   prosa (koncept §4.3-princippet). Flowet viser mention-listen som advarsel før kørsel
   og efterlader dem pegende på det nu-fjernede medie (synligt via papirkurvs-"bruges på";
   `red_doede_links` melder dem først hvis rækken engang udrenses).
4. Hvert trin er sit eget change_set → granulær fortrydelse; afbrydes sekvensen midtvejs,
   er tilstanden konsistent (relationer flyttet, kopien stadig `klar` og stadig i køen).
   §3.2-indexet gør "findes allerede på originalen"-racet ufarligt (domæne-fejl → spring over).

Mobile får ingen flet-orkestrering (kø-*behandling* er web, koncept §7) men kan naturligvis
udføre trinnene manuelt via sheet'ets eksisterende handlinger.

## 7. Skive 5 — janitor: `R/media-janitor.R`

Placeres i `R/` (ops-værktøj som `tng-qa`/`geo-enrich`, ikke i extract-skillet — der er
ingen bulk-import endnu, men sti-/sha-konventionen deles med dens tiltænkte design så
`import_media.R` senere kan genbruge helpers). Forbindelser: Postgres via DBI/RPostgres +
`~/.Renviron` (`SUPABASE_HOST/USER/PASSWORD`, load_daa.R-mønsteret:68-71); Storage via
httr2 (geo-enrich-præcedensen) mod `/storage/v1/object/…` med **ny `SUPABASE_SERVICE_ROLE`-
nøgle i `~/.Renviron`** (aldrig i klient-bundle; plan-Slice 2 forudså præcis denne nøgle
til betroet server-side import).

**Modus-kontrakt (TNG-QA/load_daa-forsigtigheden):** default er REN RAPPORT — konsol-resumé
+ `work/media-janitor-rapport.csv` (én række pr. fund: kategori, media_id/sti, alder,
anbefalet handling). Destruktion kræver eksplicitte flag; "glemt flag" kan aldrig slette.

| Flag | Betydning |
|---|---|
| *(ingen)* | rapportér alt, rør intet |
| `--slet` | udfør sletninger for kategori a+b, KUN fund ældre end fristen |
| `--frist-dage N` | frist for `--slet` (default 7); rapporten viser alle uanset alder |
| `--backfill-sha` | skriv beregnede sha256 tilbage (kategori d) — separat opt-in |

**Kategorierne:**

- **(a) Strandede uploads:** `upload_status IN ('kladde','fejlet') AND created_at < now()-frist`.
  `--slet`: fjern evt. afbildet-relationer (samme FK-orden som `_delete_relation_evidence`,
  `schema.sql:1214-1227` — men kun for relationer UDEN evidens; med evidens → rapport +
  spring over), media_variant-rækker (CASCADE), media-rækken, og Storage-objekterne på
  rækkens/varianternes stier. **Rækker med `created_at IS NULL` slettes ALDRIG** (ukendt
  alder = fail-safe; de rapporteres med anbefalingen "vurdér manuelt i papirkurvs-/
  strandede-køen"). Kørslen er direkte SQL uden change_set (bulk-præcedensen, plan:150) —
  janitoren rydder affald, den redigerer ikke indhold.
- **(b) Forældreløse Storage-objekter:** list bucket'en rekursivt, anti-join mod
  `media.storage_path ∪ media_variant.storage_path`. `--slet`: kun objekter ældre end
  fristen (Storage-objektets egen `created_at`-metadata). Fanger fase-0-2's fejlslagne
  uploads OG fremtidens erstat-fil-efterladenskaber (fase 4) uden ændring.
- **(c) Variant-huller:** `klar`-media uden thumb- eller medium-række, eller hvor en
  registreret sti ikke findes i bucket'en. **Kun rapport, aldrig auto-fix** — regenerering
  kræver klientens billedpipeline (eller fase 4's erstat-fil); rapporten er arbejdslisten.
- **(d) sha-backfill + ægte dublet-detektion:** for `klar`/`fjernet`-rækker med
  `sha256 IS NULL` og eksisterende storage_path: download large-bytes (service_role),
  `digest::digest(file=…, algo="sha256")`. Findes shaen allerede på en ANDEN række →
  **ægte dublet-par i rapporten** (ingen skrivning — unique-indexet ville også afvise den);
  ellers skrives shaen med `--backfill-sha` (direkte UPDATE uden change_set — afledt
  byte-metadata, ikke en redaktionel påstand). Backfill gør gradvist pre-flight-tjekket
  (§4.2) dækkende for HELE samlingen og fylder dublet-rapporten, som er kø 5's
  autoritative supplement (§6.2). Stierne omdøbes IKKE (koncept-beslutning: ingen
  migrering af gamle stier — `media_storage_path_uidx` og signed-URL-flowet er ligeglade).

Rene helpers (sti-antijoins, frist-logik, rapportrækker) skrives testbart og dækkes af
`tests/testthat/test-media-janitor.R` (testthat-præcedensen); selve kørslen verificeres
mod lokal Postgres + dev-bucket med seedet affald (strandet kladde, forældreløst objekt,
variant-hul, NULL-sha-dublet) — rapport finder alle fire, `--slet` fjerner kun a+b over
fristen, `--backfill-sha` skriver sha og afslører dubletparret.

---

## 8. Verifikation

- **DB (lokalt):** frisk `schema.sql`-install + `db-migrations.sql` ×2 (idempotens inkl.
  dublet-DELETE + partial-index); §3.3-asserts grønne; eksisterende verify-filer uden
  regression.
- **Enheds-tests:** hash-vektorer + sti-bygning (vitest, native Node-WebCrypto; jest på
  den rene mobile-spejlfil), `buildRpcCall` med `p_sha256`, `klassificerMedie` med
  dublet-parameter, `formatMedieAlder`, oversaetFejl-grene — spejlet web/mobile; tsc +
  build begge platforme; R-helpers via testthat.
- **Empirisk (dev/prod-svarende base):** upload samme fil to gange fra web → anden gang
  stopper pre-flight med tilknyt-tilbud; tilknyt → subjektet viser det eksisterende medie;
  afbryd en upload efter bytes (dev-tools) → genoptag-flowet fuldfører uden ny række eller
  nyt objekt; upload fra web + mobile af samme motiv → to rækker (kendt begrænsning,
  dokumenteret) → begge i "Mulige dubletter"-køen → flet-flowet flytter relationen og
  parkerer kopien i papirkurven. Janitor: kør rapport mod dev, verificér CSV, kør `--slet`
  og bekræft kun frist-overskredne fund forsvandt.
- **Prod-deploy:** skive 1-DDL gated som altid (backup + bruger-OK); migration navngives
  `mediehaandtering_fase3_hygiejne` og samles med de udestående fase 1+2-migrationer i
  én runbook. Janitorens første prod-kørsel er rapport-only, og resultatet gennemgås med
  brugeren før noget `--slet`.

## 9. Åbne punkter (blokerer ikke spec'en)

1. **Frist-værdier:** rapporten viser alt; `--slet`-defaulten på 7 dage og
   "muligvis i gang"-grænsen på 1 time er skøn — bekræft/justér ved plan-arbejdet.
2. **Fortryd-hazard efter janitor-slet:** `red_fortryd_change_set` på et gammelt
   upload-sæt kan genoplive en media-række hvis bytes janitoren har slettet (rækken
   bliver da et variant-hul i næste rapport — selvopdagende, men ikke selvhelende).
   Accepteret restrisiko; alternativet (janitor skriver change_sets) ville gøre affaldsrydning
   til redaktionshistorik. Bekræft.
3. **Koncept-§10.2 (tilbageholdelses-frist for erstattede bytes)** besvares reelt først i
   fase 4 — janitorens `--frist-dage` er den mekanisme, fristen så udtrykkes i. Ingen
   handling nu, men fase 4-spec'en skal binde de to sammen.
4. **Dublet-heuristikkens støjniveau:** giver `(byte_size,bredde,hoejde)` for mange falske
   positive i praksis, kan trillingen strammes (fx + `mime_type`) eller køen gøres
   janitor-rapport-drevet alene. Afgøres empirisk efter første brug.
5. **expo-crypto vs. ren-JS-hash:** hvis dev-client-genbygningen viser sig at være friktion,
   er en ren-JS SHA-256 (fx `@noble/hashes`, ingen native modul) en gyldig substitut med
   samme kontrakt — beslutning kan tages i planen uden spec-ændring.
6. **Koncept-§10.3 status:** fase 3 leverer "flag + blød flet" (§6.3); det endelige
   "udrens kopien"-trin afgøres i fase 4 sammen med §10.1. Denne spec foregriber ikke.
