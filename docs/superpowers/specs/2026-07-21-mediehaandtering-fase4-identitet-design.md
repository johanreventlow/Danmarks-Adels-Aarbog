# Mediehåndtering — fase 4: identitet & endeligt farvel — erstat fil, udrensning, portræt-valg (design-spec)

**Dato:** 2026-07-21
**Styringsgrundlag:** `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` §4.3
(livscyklus/udrensning), §4.5 (erstat fil), §4.7 (portræt-valg), §5 (RPC-tabellen),
§9 (fase 4), §10 punkt 1–2 (de to beslutningstunge punkter — behandlet i §10 her).
**Bygger på fase 1+2+3 — ALLE live i prod** (changelog 2026-07-20 + 2026-07-21;
`docs/database-current-state.md` "Sidst afstemt 2026-07-21"): filsiden
(`web/src/components/MediaDetaljeOverlay.tsx`, `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`),
biblioteket med køerne 1–5 og "bruges på" (`fetchMediaAnvendelse`,
`web/src/data/redaktionRead.ts:1074`, `mobile/src/data/redaktionRead.ts:979`),
sha256/sha-stier/idempotent upload, `relation_afbildet_uidx` og `R/media-janitor.R`
(første prod-kørsel rapport-only: 0 strandede, 0 forældreløse, 2 variant-huller,
6 sha-backfill-kandidater).
**Mål:** mediets *identitet* skilles endeligt fra dets *bytes* (M4: erstat fil med stabilt id),
den sjældne *rigtige* sletning får sin gatede vej (M11: udrens række + bytes), og portrættet
bliver et redaktionelt valg i stedet for en heuristik (M10: primær-flag på `afbildet`).

**Beslutninger arvet fra konceptet:** to-trins udrensning (kun fra `'fjernet'`, blokeret ved
anvendelser — "fil i brug slettes ikke"); erstat overskriver ALDRIG gamle objekter (nye
sha-stier, fase 3); filhistorik = versioneringen, ingen `media_version`-tabel;
`pickPortrait` bliver fallback, ikke dommer; `relation.kvalifikator jsonb` er planens
Slice 3-kolonne (`docs/superpowers/plans/2026-07-04-mediehaandtering.md:153,180`) og deles
med fremtidig region-tagging.
**Uden for scope:** dokumenter/transskription (fase 5), region-tagging/bbox (Slice 3 —
kolonnen kommer, indholdet gør ikke), albums (Slice 4), bulk-import (Slice 2), automatisk
flytning af narrativ-mentions (prosaen er redaktørens, koncept §4.3).

---

## 1. Baggrund & afgrænsning (empirisk, verificeret på main 2026-07-21)

- **Ingen af fase 4-RPC'erne findes.** Grep i `schema.sql`/`db-migrations.sql` giver nul
  hits for `red_erstat_media_fil`, `red_udrens_media`, `red_saet_portraet` — bekræftet.
- **`relation.kvalifikator` findes ikke.** `relation`-tabellen (`schema.sql:355-368`) har
  ingen kvalifikator-kolonne. Men fase 3's `relation_afbildet_uidx`
  (`schema.sql:369-371`) garanterer allerede præcis én `afbildet`-række pr.
  (subjekt, objekt)-par — netop den forudsætning et primær-flag kræver (fase 3-spec §3.2
  formulerede det eksplicit: "indexet er dens forudsætning").
- **Portræt vælges i dag heuristisk** i BEGGE læseflader: `pickPortrait`
  (`web/src/data/media.ts:168-171`: første signerbare med portræt-egnet `slags`, ellers
  første; `mobile/src/lib/media.ts:87-89` spejl, jest-testet). Relations-fetchen bag
  (`web/src/data/media.ts:122-124`) selecter kun `subjekt_id,objekt_id` — intet
  kvalifikator-felt flyder til klienten i dag.
- **Mønsteret for tilstandsskift er etableret:** `red_fjern_media` (`schema.sql:2113-2119`)
  = gate + `begin_change_set` + én UPDATE; `red_genopret_media` (`schema.sql:2077-2087`)
  spejler med `ROW_COUNT`-guard + domæne-fejl. Erstat/udrens følger huskonventionen
  (`SECURITY DEFINER SET search_path=public`, rolle-gate, versionering gratis via
  `trg_log_media`; grants via det navnebaserede `red_*`-loop i `db-rls.sql`).
- **Preview-forbilledet findes:** `red_slet_person_preview` (`schema.sql:1883-1904`) —
  read-only SECURITY DEFINER, `RETURNS jsonb` med tællinger + aggregeret liste, gated men
  uden change_set. Udrens-preview'et kopierer kontrakten.
- **`media_obj_delete`-politikken findes men er UBRUGT:** `db-rls.sql:296-298` tillader
  redaktions-DELETE i `media`-bucketen, men ingen `storage.remove`-kald findes i `web/src`
  eller `mobile/src` (grep — kun kort/bogmærke-hits). Udrensningens klient-sidede
  Storage-sletning bliver politikkens første forbruger.
- **FK-billedet for hård sletning er enkelt:** kun `media_variant` refererer `media`
  (`ON DELETE CASCADE`, `schema.sql:100`). `relation`/`text_mention` er polymorfe uden FK —
  derfor SKAL udrens selv blokere på dem (§4). Relations-evidens er allerede løst:
  relationer ryddes FØR udrens via eksisterende `red_slet_relation`
  (`schema.sql:1245-1251` → `_delete_relation_evidence`, `schema.sql:1230-1243`).
- **Versionering bærer både erstat og udrens:** `media` står i `version_pk_registry`
  (`schema.sql:2183`), så `trg_log_media` logger også DELETE med fuldt `foer`-snapshot
  (`schema.sql:2301-2305`), og `red_fortryd_change_set` kan genskabe en slettet række via
  INSERT fra snapshottet (`_version_upsert_row`, `schema.sql:2330-2365`; DELETE-inverse
  `schema.sql:2415-2419`). Det er svaret på koncept-§10.1's "hvad overlever": rækkens
  metadata overlever i `change_event.foer` — bytes gør ikke (se §10.1).
- **`media_variant` er bevidst uversioneret cache** (B8; tabel-kommentar `schema.sql:96`,
  `red_registrer_media_variant` uden change_set, `schema.sql:2128-2146`). Konsekvens for
  erstat-fortryd behandles ærligt i §3.
- **Janitoren dækker allerede erstat-efterladenskaber:** `find_orphan_objects`
  (`R/media-janitor.R:162`) anti-joiner bucket-listning mod
  `media.storage_path ∪ media_variant.storage_path`; `--slet` rammer kun fund ældre end
  `--frist-dage` (default `7L`, `parse_media_janitor_args`, `R/media-janitor.R:68-90`;
  aldersberegning `eligible_by_age`, `R/media-janitor.R:139-141`, på Storage-objektets egen
  `created_at`). Fase 3-spec §7b forudsagde at kategori b "fanger fremtidens
  erstat-fil-efterladenskaber uden ændring" — verificeret i koden: efter erstat peger ingen
  række på de gamle stier → de ER kategori b. **Fase 4 har derfor INGEN janitor-skive**;
  bindingen mellem erstat og fristen er en dokumenteret kontrakt (§3.3 + §10.2), ikke ny kode.
- **Gamle bytes er fail-closed usynlige efter erstat:** `media_id_for_object`
  (`db-rls.sql:154-160`) mapper objekt-sti → media via `storage_path`/variant-sti; en
  forladt sti giver NULL → `media_synlig_anon/auth` false (NULL-mid = fail-closed,
  kommentaren ved `db-rls.sql:163-165`). Kun `media_obj_redaktion` kan signe dem — præcis
  hvad et fortryd i fortryd-vinduet kræver.
- **Skrive-laget i dag** (`web/src/data/redaktionWrite.ts:35-38` + mobile-spejl):
  media-arterne `uploadMedia`, `opdaterMedia`, `genopretMedia`, `mediaRettigheder`,
  `tilknytMedia`, `fjernMedia` (+ `sletMedierelation` fra fase 3-flet). `uploadMedia` har
  den hårde kan-ikke-degradere-til-`red_suggest`-gate (`redaktionWrite.ts:512-514`) —
  præcedens for erstat/udrens (§6).
- **Prod-skala:** 6 media-rækker (2 `klar`, 4 `fjernet`; `docs/database-current-state.md`
  §1) — papirkurvens 4 er udrensningens første reelle kandidater. Alt er småt; ingen
  performance-hensyn i denne fase.
- **Dokumentationsafvigelse fundet:** koncept-§9's fase 1+2-rækker siger fortsat
  "Implementeret lokalt; prod-deploy gated", men begge gik i prod 2026-07-20 (changelog).
  Rettes i skive 7's afstemning (koncept-filen røres ikke af denne spec).

**I scope:** tre nye RPC'er + én preview-RPC + én additiv kolonne; tre nye Change-arter
(begge platforme); erstat-/udrens-/portræt-UI på filsiden (web + mobile); portræt-flag
gennem læse-lagene så `pickPortrait` bliver fallback; verify-asserts og afstemning.

---

## 2. Skæring (7 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | DB: `red_erstat_media_fil` | `schema.sql`, `db-migrations.sql` | lokal Postgres: frisk install + migrationssti ×2; RPC-asserts |
| 2 | DB: `red_udrens_media` + `red_udrens_media_preview` | `schema.sql`, `db-migrations.sql`, `db-verify-media.sql` | asserts: to-trins-guard, anvendelses-blok, preview-paritet |
| 3 | DB: `relation.kvalifikator` + `red_saet_portraet` | `schema.sql`, `db-migrations.sql` | asserts: søskende-nulstilling, ryd-gren, manglende relation |
| 4 | Skrive-lag: `erstatMediaFil`/`udrensMedia`/`saetPortraet` (begge platforme) | `web/src/data/redaktionWrite.ts`, `mobile/src/data/redaktionWrite.ts` (+ tests) | vitest/jest på `buildRpcCall` + gate-adfærd; netværksfrit |
| 5 | Web: filside-handlinger + portræt gennem læse-laget | `web/src/components/MediaDetaljeOverlay.tsx`, `web/src/Redaktion.tsx`, `web/src/data/media.ts`, `web/src/data/redaktionRead.ts` (+ tests) | tsc + vitest + build; browser-røgtest |
| 6 | Mobile: spejl | `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`, `mobile/src/lib/media.ts`, `mobile/src/data/redaktionRead.ts`, `mobile/src/lib/mediaUpload.ts` (+ tests) | tsc + jest; simulator-verifikation |
| 7 | Verifikation & afstemning | changelog, koncept-§9 (inkl. forældede fase 1+2-statuslinjer), `docs/database-current-state.md` | fuld suite grøn; gated prod-deploy |

1–3 er indbyrdes uafhængige DB-skiver (kan committes hver for sig); 4 kræver 1–3;
5+6 kræver 4 og er indbyrdes uafhængige spejlinger. Ingen janitor-skive (jf. §1 — kategori
b dækker allerede). Prod-DDL (skive 1–3) er som altid controller-gated (backup + bruger-OK).

---

## 3. Skive 1 — DB: `red_erstat_media_fil` (M4)

### 3.1 Flow og signatur

Erstat er to-faset som upload: klienten kører fase 3-pipelinen på den nye fil
(genkod tiers → hash large → sha-stier, `buildVariants`/`buildShaStoragePaths`) og lægger
bytes på de NYE sha-stier FØRST (idempotent, 409-tolerant — fase 3-mekanikken uændret);
dernæst ét RPC-kald der atomisk flytter rækkens identitet over på de nye bytes:

```sql
red_erstat_media_fil(
  p_media_id bigint,
  p_storage_path text, p_mime text, p_byte_size bigint,
  p_bredde int, p_hoejde int, p_sha256 text,
  p_original_filnavn text DEFAULT NULL,   -- NULL = behold eksisterende
  p_varianter jsonb DEFAULT '[]'          -- [{tier,storage_path,mime,byte_size,bredde,hoejde},…]
) RETURNS void
```

- **Guards:** rolle-gate; rækken findes og `upload_status='klar'` (en `'kladde'`
  færdiggøres via fase 3's genoptag-flow; en `'fjernet'` genoprettes først — domæne-fejl
  "Kan kun erstatte filen på et klart medie"); `p_sha256`/`p_storage_path` påkrævede
  (`nullif(btrim(…),'')`-mønsteret).
- **Dedup-guard, to grene:** (a) `p_sha256` findes på en ANDEN række → samme domæne-fejl-form
  som `red_opret_media`s guard (`schema.sql:1987-1991`) men med `id <> p_media_id`;
  (b) `p_sha256` = rækkens egen sha → domæne-fejl "Filen er identisk med den nuværende"
  (no-op-erstat må ikke skrive et tomt change_set). Klientens pre-flight (§7) fanger begge
  FØR bytes uploades; guarden er race-bagstopperen.
- **Én UPDATE** af `storage_path`/`mime_type`/`byte_size`/`bredde`/`hoejde`/`sha256`
  (+ `original_filnavn = coalesce(nullif(btrim(p_original_filnavn),''), original_filnavn)`).
  `trg_log_media` snapshotter de gamle sti-/metadata-værdier — **fortryd-historikken ER
  filhistorikken** (koncept §4.5), ingen ny tabel.
- **Varianter re-registreres INDE i RPC'en:** loop over `p_varianter` →
  `PERFORM red_registrer_media_variant(p_media_id, tier, …)` (upsert på `(media_id,tier)`,
  `schema.sql:2139-2144`; tier-validering genbruges dér). Begrundelse: separate klient-kald
  efter RPC'en ville ved afbrud efterlade ny large + gamle thumbs — én transaktion lukker
  det hul. `red_registrer_media_variant` åbner bevidst intet eget change_set, så
  erstatningen forbliver ét sæt.

### 3.2 Fortryd-adfærd (ærlig, dokumenteret)

`red_fortryd_change_set` på et erstat-sæt ruller media-rækken tilbage til de gamle stier
(bytes ligger der stadig — erstat overskriver aldrig). Men variant-rækkerne er uversioneret
cache (§1): de bliver stående på de NYE stier → thumb/medium viser den nye version, large
den gamle. Selvopdagende inkonsistens (synlig på filsiden), afhjælpes ved at erstatte igen
med den ønskede fil. Alternativet — `media_variant` ind i `version_pk_registry` — afvises:
det ville vende B8-beslutningen (cache versioneres ikke) for et hjørnetilfælde. Noteret som
åbent punkt §10.3 til plan-bekræftelse.

### 3.3 Gamle bytes: tilbageholdelse via janitorens eksisterende frist

Efter erstat er de gamle objekter forældreløse: fail-closed usynlige for anon/auth
(`media_id_for_object` → NULL, §1) og fanges af janitor kategori b. **Kontrakten** (svarer
koncept-§10.2, uddybet i §10.2 her): fortryd-vinduet for en erstattet fil = janitorens
`--frist-dage` (default 7) — plus det menneskelige led, at `--slet` aldrig kører uden
eksplicit flag og rapportgennemgang. Ingen ny mekanisme, ingen janitor-kodeændring.

---

## 4. Skive 2 — DB: `red_udrens_media` + preview (M11)

### 4.1 `red_udrens_media_preview` — bekræftelsesdialogens datagrundlag

Kontrakten kopierer `red_slet_person_preview` (`schema.sql:1883-1904`): read-only,
`SECURITY DEFINER`, rolle-gated, intet change_set:

```sql
red_udrens_media_preview(p_media_id bigint) RETURNS jsonb
-- { "upload_status": …, "kan_udrenses": bool, "blokeringer": [tekst…],
--   "antal_afbildet": n, "antal_mentions": n,
--   "afbildet": [{relation_id, retning, modpart_type, modpart_id}…],
--   "mentions": [{kilde_type, kilde_id}…],
--   "stier": [{bucket, sti, kilde: 'media'|'thumb'|'medium'}…] }
```

`blokeringer` udfyldes når `upload_status <> 'fjernet'` eller anvendelser findes — UI'et
viser præcis hvorfor knappen er grå, og listerne genbruger fase 2's "bruges på"-rendering.
`stier` er samtidig klientens arbejdsliste til Storage-sletningen (§4.2), så preview og
udførelse deler ét sandhedsgrundlag.

### 4.2 `red_udrens_media` — den rigtige sletning

```sql
red_udrens_media(p_media_id bigint) RETURNS jsonb   -- {"stier":[{bucket,sti}…]}
```

- **Guards (alle domæne-fejl, fail-loud):** rolle-gate; rækken findes; **kun fra
  `'fjernet'`** (to-trins: blødt fjern først — koncept §4.3); **blokeret ved enhver
  anvendelse**: relationer hvor mediet er subjekt ELLER objekt, og `text_mention` med
  `maal_type='media'`. Relationer ryddes eksplicit først (via `red_slet_relation` eller
  fase 3's `red_slet_medierelation_uden_evidens`, `schema.sql:1309-1339` — begge håndterer
  polymorf evidens korrekt, hvilket flad DELETE her ikke ville); mention-tokens redigeres
  ud af prosaen manuelt, guidet af preview'ets liste. Dermed kan udrens aldrig forældreløse
  evidens eller efterlade friske døde links — `red_doede_links`-media-grenen
  (`schema.sql:2521`) er bagstopper for historiske tokens, ikke en tilladelse.
- **Sletningen:** `PERFORM begin_change_set(…)`; saml varianternes + rækkens stier;
  `DELETE FROM media WHERE id=p_media_id` — `media_variant` CASCADE'r (`schema.sql:100`,
  uversioneret cache, ikke logget), media-rækken logges som DELETE med `foer`-snapshot
  (§1). Returnér stierne.
- **Storage-sletning er klient-sidet, EFTER DB-kaldet** (koncept §4.3; Postgres-txn og
  Storage deler ikke transaktion — samme asymmetri som upload): klienten kalder
  `supabase.storage.from(bucket).remove(stier)` — `media_obj_delete`-politikkens første
  forbruger (§1). Fejler kaldet, er objekterne forældreløse = fail-closed usynlige og
  janitor-kategori-b-fund; rækkefølgen DB-først garanterer at der aldrig findes en synlig
  række uden bytes.
- **Fortryd-hazard (dokumenteret, accepteret):** `red_fortryd_change_set` på udrens-sættet
  genskaber media-rækken fra snapshottet, men hverken variant-rækker (cache) eller bytes
  (borte) — rækken bliver et variant-hul/manglende large, som janitor-kategori c-rapporten
  opdager. Spejler fase 3-spec §9.2's accepterede janitor-hazard. UI'ets bekræftelsesdialog
  siger eksplicit "kan ikke reelt fortrydes" (§7).

### 4.3 `db-verify-media.sql`-asserts (filens kontrakt: RLS/gating uden redaktør-kontekst)

Seed medie + relation → direkte forsøg på at nå udrens-tilstanden verificerer gatingen
indirekte (anon ser fortsat intet under hele cyklussen); RPC-happy-paths og guard-asserts
(kun-fra-fjernet, anvendelses-blok, preview↔udrens-paritet på `stier`) kører som altid
lokalt under simulerede redaktør-claims (fase 1-spec §3.4-modellen).

---

## 5. Skive 3 — DB: `relation.kvalifikator` + `red_saet_portraet` (M10)

### 5.1 Kolonnen (planens Slice 3-kolonne, additiv)

```sql
ALTER TABLE relation ADD COLUMN IF NOT EXISTS kvalifikator jsonb;
```

- Generisk pr. plan (`2026-07-04-mediehaandtering.md:153`): fase 4 bruger kun
  `{"primaer": true}`; fremtidig region-tagging (bbox) deler kolonnen uden ny DDL.
- **Versionering gratis:** `relation` står i `version_pk_registry` uden skip-cols
  (`schema.sql:2169`) — jsonb-rækkesnapshottet bærer den nye kolonne automatisk; ingen
  registry-ændring. `schema.sql` (frisk install) skriver kolonnen direkte i CREATE TABLE.
- **Ingen RLS-ændring:** kolonnen følger rækkens eksisterende politikker; et primær-flag
  lækker intet (relationen selv er allerede gated).

### 5.2 `red_saet_portraet`

```sql
red_saet_portraet(p_person_id bigint, p_media_id bigint DEFAULT NULL) RETURNS void
-- p_media_id = NULL: ryd eksplicit valg → heuristikken gælder igen
```

- Rolle-gate + `begin_change_set('red_saet_portraet', …, 'person', p_person_id)`.
- **Nulstil søskende først** (én UPDATE): fjern `'primaer'`-nøglen (`kvalifikator - 'primaer'`,
  tom jsonb → NULL) på alle personens `afbildet`-relationer
  (`subjekt_type='person' AND subjekt_id=p_person_id AND rolle='afbildet'
  AND objekt_type='media' AND kvalifikator ? 'primaer'`).
- **Sæt flaget** (når `p_media_id` ikke er NULL): UPDATE relationen for parret —
  `relation_afbildet_uidx` garanterer max én (§1); `kvalifikator =
  coalesce(kvalifikator,'{}'::jsonb) || '{"primaer":true}'::jsonb`. `ROW_COUNT=0` →
  domæne-fejl "Mediet er ikke tilknyttet personen — tilknyt først" (ingen implicit
  relation-oprettelse; tilknyt-flowet fra fase 2 er vejen).
- Retningen person→media er GDPR-invariantens (`red_relation`-guarden,
  `schema.sql:1204-1206`) — portræt-RPC'en behøver derfor kun scanne den ene retning.
- Ingen `upload_status`-guard: et flag på et senere-fjernet medie er harmløst —
  læse-lagene ser kun signerbare/synlige medier (§5.3), og flaget overlever genopret.

### 5.3 Læse-lagene: flaget gennem til `pickPortrait`

- **Læser (web):** relations-queryen i `fetchMediaByRelation`
  (`web/src/data/media.ts:122-124`) udvider select med `kvalifikator`; `MediaItem` får
  `primaer?: boolean`. `pickPortrait` (`media.ts:168-171`) prioriterer: første signerbare
  med `primaer` → eksisterende slags-heuristik → første signerbare. Heuristikken er
  fallback, præcis som koncept §4.7 kræver.
- **Læser (mobile):** spejl i `mobile/src/lib/media.ts` (relations-fetch + `pickPortrait`,
  `:87-89`; eksisterende jest-suite udvides).
- **Redaktion:** `fetchRedPersonMedia`/`fetchMediaAnvendelse`-lagene (begge platforme)
  medtager flaget, så filsiden/galleriet kan vise "Portræt"-badge og knap-tilstand
  (fase 2's "om mediet er nogens aktuelle portræt"-punkt bliver hermed reelt).

---

## 6. Skive 4 — skrive-laget (begge platforme, holdt i sync)

Tre nye arter i `Change`-unionen + `buildRpcCall`-grene (`web/src/data/redaktionWrite.ts` +
mobile-spejl):

| Art | RPC | Args | Degradering til `red_suggest`? |
|---|---|---|---|
| `erstatMediaFil` | `red_erstat_media_fil` | `p_media_id` + sti/mime/mål/sha + `p_varianter` | **NEJ** — bærer fil-bytes; samme hårde gate som `uploadMedia` (`redaktionWrite.ts:512-514`): fejl frem for korrupt forslag |
| `udrensMedia` | `red_udrens_media` | `p_media_id` | **NEJ** — destruktiv og afhængig af returnerede stier; et "udrens-forslag" ville lyve om begge dele |
| `saetPortraet` | `red_saet_portraet` | `p_person_id`, `p_media_id` (NULL = ryd) | ja (harmløs metadata-change, som `opdaterMedia`) |

- **Live-flowet for `erstatMediaFil`** spejler `uploadMedia`s tre-trins-orkestrering i
  `submitChange`: bytes (large + varianter, idempotent på sha-stier) uploades FØR RPC'en,
  og RPC'en re-registrerer varianterne selv (§3.1) — modsat upload er der ingen
  bekræft-fase (rækken forbliver `'klar'` hele vejen).
- **Dry-run:** alle tre arter returnerer det planlagte kald uændret gennem det generiske
  flow (`submitChange` `dryRun`-grenen); ved dry-run uploades INTET (samme betingelse som
  `uploadMedia`). Udrens-dialogens indhold kommer fra preview-RPC'en uafhængigt af
  dry-run-togglen.
- `oversaetFejl` udvides med de nye domæne-fejl: "Kan kun erstatte filen på et klart
  medie", "Filen er identisk…", "Kan kun udrense et fjernet medie", anvendelses-blokken og
  "Mediet er ikke tilknyttet personen…".
- **Tests** (vitest + jest, spejlede): buildRpcCall-grene inkl. manglende id → `null`,
  `p_varianter`-formen, NULL-ryd-grenen for portræt; gate-adfærd for de to
  ikke-degraderbare arter; **dryRun-prop-threading-regressionstest for hver ny
  UI-indgang** ("default respekteres" — læringen fra SammenlignUdgaver-fejlen, PR #72).

---

## 7. Skive 5 — web-UI

Alle tre handlinger bor på filsiden (`MediaDetaljeOverlay`) — "ethvert billede har ét hjem":

1. **"Erstat fil…"** (kun `uploadStatus==='klar'`): file-picker (samme accept/HEIC-grænse
   som upload, `web/src/data/mediaUpload.ts` uændret) → fase 3-pipeline (varianter + sha)
   → **pre-flight på shaen** før upload: egen række = "Filen er identisk med den nuværende"
   (stop); anden række = fase 3's dedup-dialog ("findes allerede → tilknyt i stedet");
   ellers upload → `run({art:'erstatMediaFil', …})`. Efter succes: refetch
   (`mediaChanged`-betingelsen udvides) + preview viser den nye fil.
2. **"Slet permanent…"** (kun `uploadStatus==='fjernet'`; indgang fra papirkurvs-køen og
   filsiden): henter `red_udrens_media_preview` → dialog med anvendelses-liste (genbruger
   fase 2's "bruges på"-rendering), sti-antal og eksplicit "Bytes slettes — kan ikke
   fortrydes". Blokeret tilstand viser `blokeringer` med links til at rydde (fjern
   tilknytning / redigér narrativ). To-trins bekræft (skriv-ordet-mønster eller dobbelt
   klik-bekræft — planens valg) → `run({art:'udrensMedia'})` → `storage.remove(stier)` →
   refetch. Fejlet Storage-kald vises som advarsel ("bytes ryddes af janitoren"), ikke som
   fejlet udrensning — DB-tilstanden ER sandheden.
3. **"Sæt som portræt" / "Fjern portræt-valg"** på afbildet-person-rækkerne i "bruges
   på"-sektionen og i person-editorens galleri: `run({art:'saetPortraet', …})`; badge på
   den aktuelle primær. Læserens `DetailPanel` (der kalder `pickPortrait`,
   `web/src/components/DetailPanel.tsx:39`) opdager flaget automatisk via §5.3 — ingen
   komponent-ændring.

## 8. Skive 6 — mobile-UI

- `MediaDetaljeSheet` får samme tre handlinger (fuld pr.-medie-paritet, koncept §7):
  erstat via `expo-image-picker` + fase 3-mobile-pipelinen (`mobile/src/lib/mediaUpload.ts`
  genbruges — HEIC virker her); udrens-dialog med preview-data; portræt-knap i sheet'ets
  tilknytnings-/galleri-kontekst.
- Kø-*behandling* (papirkurvs-masseudrensning) forbliver web; mobilen udrenser
  enkeltmedier fra sheet'et.
- `pickPortrait`-flaget i `mobile/src/lib/media.ts` + read-lag som §5.3; jest-suiten for
  `pickPortrait` udvides med primær-prioriteringen.

---

## 9. Skive 7 — Verifikation & afstemning

- **DB (lokalt):** frisk `schema.sql`-install + `db-migrations.sql` ×2 (idempotens inkl.
  `ADD COLUMN IF NOT EXISTS`) mod lokal Postgres; RPC-asserts under simulerede
  redaktør-claims: erstat (guards, dedup-grene, varianter re-registreret atomisk, fortryd
  ruller media-rækken tilbage og efterlader dokumenteret variant-mismatch), udrens
  (kun-fra-fjernet, anvendelses-blok begge retninger + mentions, preview↔udrens-paritet,
  DELETE-event med foer-snapshot, fortryd genskaber række uden varianter), portræt
  (søskende-nulstilling, ryd-gren, fejl ved manglende relation, unikhed under
  `relation_afbildet_uidx`); `db-verify-media.sql` udvidet (§4.3) uden regression i de
  eksisterende 447 linjers asserts.
- **Enheds-tests:** nye buildRpcCall-/pickPortrait-/oversaetFejl-tests spejlet
  (vitest 422+ / jest 345+ / core 267+ forbliver grønne); tsc + build begge platforme;
  dryRun-threading-regressionstests (§6).
- **Empirisk (dev/prod-svarende base):** (a) erstat en fil → id/relationer/mentions/
  rettigheder uændrede, ny fil vises, gamle stier forældreløse → janitor-rapport kategori b
  viser dem, `--slet` først efter frist; fortryd erstat inden fristen → gammel fil tilbage
  (variant-mismatch synlig og dokumenteret); (b) blødt fjern → udrens blokeret af relation
  → ryd → udrens → række + bytes borte, anon/auth uændret 0-synlighed, janitor-rapport ren;
  (c) sæt portræt → læser-web + mobile viser valgt billede frem for heuristikkens; ryd →
  heuristik igen. Mobile: simulator-gennemløb af alle tre flows.
- **Prod-deploy:** controller-gated som al DDL (backup + bruger-OK); migration navngives
  `mediehaandtering_fase4_identitet`; `get_advisors(security)` efter apply (husreglen).
  Afstemning: changelog-entry, koncept-§9 fase 4-rækken + de forældede fase 1+2-statuslinjer
  (§1), `docs/database-current-state.md` (media-afsnit + funktionsinventar).

---

## 10. Åbne punkter (blokerer ikke spec'en)

1. **Koncept-§10.1 — udrensning vs. "påstande overskrives aldrig": ANBEFALING = acceptér
   hård sletning, som spec'et her.** Invarianten (CLAUDE.md "Evidensbaseret", invariant #1)
   freder *påstande* — kildebundne udsagn i `assertion`/`conclusion`. En media-række er
   materiale-*metadata* og bytes er *materiale*, ikke evidens (koncept-§4.3's begrundelse
   holder ved efterprøvning: ingen assertion kan target'e media, kun fact/relation —
   `schema.sql:376`). Vigtigere: systemet HAR allerede hård sletning som etableret kategori
   (`red_slet_person`, `red_slet_relation`/`_delete_relation_evidence`) — udrens er ikke et
   principbrud men den mest gatede udgave af en eksisterende operationstype, og dens
   anvendelses-blok garanterer at ingen evidens forældreløses. **Hvad overlever:**
   `change_event.foer`-snapshottet (metadata + stier) — vurderet NOK som arkivspor og ikke
   FOR MEGET ift. GDPR: bytes er det persondata-tunge, og skulle et konkret sletningskrav
   også omfatte metadata, er svaret en dokumenteret manuel operatør-procedure
   (change_event-scrub mod prod), ikke en indbygget RPC. Bekræftes af brugeren ved
   plan-arbejdet — det er en beslutning, ikke en implementeringsdetalje.
2. **Koncept-§10.2 — tilbageholdelsesfrist for erstattede bytes: ANBEFALING = janitorens
   eksisterende `--frist-dage` (default 7), INGEN change_event-baseret fredning.**
   Fase 3-spec §9.3 krævede at fase 4 binder de to sammen — bindingen er §3.3: erstattede
   bytes bliver kategori b-forældreløse, og `eligible_by_age`/`--frist-dage`
   (`R/media-janitor.R:68-90,139-141`) ER fristen; nul ny kode. Koncept-§4.5's alternativ
   ("behold så længe et change_set refererer stien") frarådes eksplicit: change_events
   slettes aldrig → erstattede bytes ville være udødelige — hvilket underminerer netop det
   rettigheds-/GDPR-scenarie (tilbagekaldt materiale SKAL kunne dø), som er M4/M11's
   eksistensberettigelse. Efter fristen er fortryd-af-erstat officielt delvist
   (metadata ruller tilbage, bytes borte → selvopdagende via kategori b/c) — samme
   accepterede hazard-familie som fase 3-spec §9.2. Operatøren kan hæve fristen pr. kørsel
   (`--frist-dage 30` efter store erstat-runder) uden kodeændring.
3. **Variant-mismatch efter fortryd-af-erstat** (§3.2): accepteret som dokumenteret
   begrænsning (cache versioneres ikke, B8). Hvis det viser sig at gøre ondt i praksis, er
   alternativet at fortryd-flowet i UI'et tilbyder "erstat tilbage til forrige version"
   (filhistorikken har stierne) frem for rå `red_fortryd_change_set` — plan-beslutning.
4. **To-trins-bekræftens form for udrens** (skriv-ordet vs. dobbelt-bekræft, §7.2) og om
   papirkurvs-køen skal have en samlet "udrens alle uden anvendelser"-massehandling
   (næppe ved 4 rækker i prod) — afgøres ved plan/implementering.
5. **Portræt-ryd-grenen** (`p_media_id = NULL`): medtaget i spec'en som lille og symmetrisk;
   droppes uden skade hvis planen vil minimere — heuristikken er altid fallback.
