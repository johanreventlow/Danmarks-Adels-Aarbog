# Mediehåndtering — samlet design, faset build

## Context

Stamtræet skal kunne beriges med billeder: **portrætter/malerier på personer**, og **objekt-billeder** af godser (`estate`), våben (`coat_of_arms`), samt medier til artikler/kilder og delte begivenheder. Dette er den "samlede design-session for foto/medier" som `claude.md` §6.6 + §9 bevidst har udskudt ("samlet, ikke stykvis").

**Overraskende meget er allerede på plads** — men intet virker endnu:
- `media`-entiteten findes (`schema.sql:64`, bevidst tynd), er i vokabularet, i mention-grammatikken (`[[media:id|tekst]]`), og i `version_pk_registry` (`schema.sql:1247` — dermed dækket af fortryd-historik).
- Tilknytning sker via den generiske `relation` (`rolle='afbildet'|'skabt_af'|'ejer'|'placeret_på'`, `objekt_type='media'`). `red_relation` (`schema.sql:820`) understøtter det allerede.
- **RLS-medie-gating er deployet og korrekt** (`db-rls.sql:50-153`): fail-closed via `media_afbilder_skjult/privat` — et billede skjules hvis det afbilder en levende/privat person; objekt-fotos uden afbildet person er offentlige.
- Frontend-stillads findes: web har `RawMedia`/`mediaBy`/`medieListe`-typer + placeholder-slots; mobile fetcher `media` og har en "Materiale"-sektion.

**Hullet der lukkes her:**
1. **Storage-laget findes slet ikke** — `media`-rækken har ingen `bucket`/`sti`/`mime`/`dimensioner`/`checksum`; ingen Supabase Storage-bucket; ingen `storage.objects`-politikker (bekræftet `docs/reviews/12:142`, `docs/database-current-state.md:70`).
2. **Rettigheder/ophavsret modelleres ikke** — publikations-kritisk (DAA-portrætgalleri + museumsportrætter har reel copyright). Ønsket fra dag 1.
3. **Ingen upload-vej** (redaktør) og **ingen bulk-import** (R).
4. **Ingen faktisk billed-visning** — kun gradient-placeholdere.
5. **Latent bug:** `mobile/src/data/buildAux.ts:159` nøgler `mediaBy` på `m.person_id` — en kolonne der **ikke findes** i `media`-skemaet. Den reelle kobling er `relation`/`afbildet`. `mediaBy` er derfor altid tom i dag.

**Beslutninger (låst med brugeren):** samlet plan + faset build; redaktør-upload **og** bulk-import (crowdsource senere); **rettigheder fra dag 1**.

---

## Designprincip — hvor hører hver medie-attribut hjemme

Respektér invarianterne (`claude.md` §3): lille fast entitetssæt + én generisk relation; "alt er et faktum"; nye behov = nye *værdier* (vocab), ikke nye tabeller.

| Attribut-type | Hjemsted | Begrundelse |
|---|---|---|
| Fysisk byte-metadata (bucket, sti, mime, størrelse, dimensioner, checksum) | **Kolonner på `media`** | Bytes har intet andet hjem. Eneste legitime "fedning" af den tynde tabel. |
| Semantiske links (afbildet, skabt_af, ejer, placeret_på, event) | **`relation`** (allerede deployet) | Polymorf, kildebåret. |
| Dokumenterende rettighedskrav (licens, tilladelse, kildehenvisning) | **`fact` på `subjekt_type='media'`** + `citation` | Den sanktionerede udvidelsesmekanisme; tilladelsesbrevet *er* en citation. |
| Publikations-gating (må billedet vises?) | **Kontrol-kolonne på `media`** | Præcedens: `person.levende`/`privat` er kolonner der driver RLS — ikke facts. |

---

## SLICE 0 — MVP: storage + gating + visning (fundament)

### 0a. Skema-udvidelse af `media` (`schema.sql` CREATE TABLE + `db-migrations.sql` som idempotente ALTER'er)

```sql
ALTER TABLE media ADD COLUMN IF NOT EXISTS bucket           TEXT NOT NULL DEFAULT 'media';
ALTER TABLE media ADD COLUMN IF NOT EXISTS storage_path     TEXT;   -- = storage.objects.name
ALTER TABLE media ADD COLUMN IF NOT EXISTS mime_type        TEXT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS byte_size        BIGINT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS bredde           INT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS hoejde           INT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS sha256           TEXT;   -- dedup + deterministisk sti
ALTER TABLE media ADD COLUMN IF NOT EXISTS original_filnavn TEXT;
ALTER TABLE media ADD COLUMN IF NOT EXISTS upload_status    TEXT NOT NULL DEFAULT 'kladde'; -- 'kladde'|'klar'|'fejlet'
-- Rettigheds-gating (se 0b):
ALTER TABLE media ADD COLUMN IF NOT EXISTS maa_publiceres     BOOLEAN NOT NULL DEFAULT false; -- FAIL-CLOSED
ALTER TABLE media ADD COLUMN IF NOT EXISTS rettigheder_status TEXT NOT NULL DEFAULT 'ukendt';

CREATE UNIQUE INDEX IF NOT EXISTS media_storage_path_uidx ON media (bucket, storage_path) WHERE storage_path IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_sha256_uidx       ON media (sha256)               WHERE sha256 IS NOT NULL;
```

- **To-fase upload:** RPC opretter række (`'kladde'`) → bytes uploades til Storage → bekræftelse flipper til `'klar'`. RLS + app viser kun `'klar'`. (Postgres-txn og Storage-upload kan ikke dele transaktion.)
- **Derivater (thumbnail/web-str.):** ingen kolonner. Deterministisk sti-konvention fra originalen (fx `derived/thumb/<sha256>.webp`), eller Supabase image-transformation på originalen (arver originalens RLS — foretrukket til MVP, ingen ekstra politik-sti).
- `media` har `skip_cols='{}'` i `version_pk_registry` → nye kolonner versioneres automatisk. Ingen registry-ændring nødvendig.

### 0b. Rettighedsmodel (fra dag 1) — disciplineret mix

- **`maa_publiceres BOOLEAN DEFAULT false`** = fail-closed publikations-gate, uafhængig af GDPR-person-gating. Et rettigheds-begrænset billede af en for-længst-død person forbliver skjult. Nyimporteret billede er usynligt for offentligheden indtil en redaktør frigiver.
- **`rettigheder_status`**: `'ukendt'|'public_domain'|'licenseret'|'tilladelse_givet'|'begraenset'|'spaerret'` (nyt vocab-scheme `media_rettigheder_status`).
- **Rig dokumentation (Slice 1)** som `fact` på `subjekt_type='media'` + `citation`; parter som `relation` (ny rolle `rettighedshaver`; eksisterende `skabt_af` for ophavsmand). *Slice 0 nøjes med de to gating-kolonner.*
- **Ny RLS-helper** (SECURITY DEFINER STABLE, spejler `media_afbilder_*`):
```sql
create or replace function public.media_rettigheder_ok(mid bigint)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select m.maa_publiceres from public.media m where m.id = mid), false);
$$;
grant execute on function public.media_rettigheder_ok(bigint) to anon, authenticated;
```
- **Udvid de tre deployede `media`-politikker** (`db-rls.sql:144-153`) med `and public.media_rettigheder_ok(media.id)` på anon + authenticated (ikke redaktion).

### 0c. Storage-bucket + `storage.objects`-RLS

**Én privat bucket `media`. Ingen offentlig bucket.** Servér alt via `createSignedUrl` (kort TTL, ~60–300 s) mintet på brugerens session, så Storage-RLS håndhæves på kalderens JWT.

*Hvorfor ikke offentlig bucket:* begge gating-dimensioner er **dynamiske og tilbagekaldelige** (person kan markeres `privat` senere; tilladelse kan trækkes; `maa_publiceres` kan flippe). En offentlig URL kan ikke tilbagekaldes. Privat + signed URLs bevarer tilbagekaldelighed (GDPR + copyright-forpligtelse). Prisen er ét signed-URL-kald, RLS-tjekket gratis.

```sql
-- objekt→media mapping (sti er autoritativ: storage.objects.name == media.storage_path)
create or replace function public.media_id_for_object(p_name text)
returns bigint language sql stable security definer set search_path=public as $$
  select m.id from public.media m where m.bucket='media' and m.storage_path=p_name limit 1;
$$;
grant execute on function public.media_id_for_object(text) to anon, authenticated;

-- SELECT: spejler den deployede 3-politik-media-stak + rettigheds-dimension
create policy media_obj_anon on storage.objects for select to anon using (
  bucket_id='media'
  and not public.media_afbilder_skjult(public.media_id_for_object(name))
  and public.media_rettigheder_ok(public.media_id_for_object(name)));
create policy media_obj_auth on storage.objects for select to authenticated using (
  bucket_id='media'
  and not public.media_afbilder_privat(public.media_id_for_object(name))
  and public.media_rettigheder_ok(public.media_id_for_object(name)));
create policy media_obj_redaktion on storage.objects for select to authenticated using (
  bucket_id='media' and (select public.current_rolle())='redaktion');
-- WRITE: kun redaktion (bulk-import bruger service_role → bypasser RLS)
create policy media_obj_write  on storage.objects for insert to authenticated with check (bucket_id='media' and (select public.current_rolle())='redaktion');
create policy media_obj_update on storage.objects for update to authenticated using      (bucket_id='media' and (select public.current_rolle())='redaktion');
create policy media_obj_delete on storage.objects for delete to authenticated using      (bucket_id='media' and (select public.current_rolle())='redaktion');
```
- **Fail-closed edge:** objekt uden matchende media-række → `media_id_for_object`=NULL → `media_rettigheder_ok(NULL)`=false → nægtet for anon/auth. Forældreløse objekter usynlige undtagen for redaktion. Godt default.
- Bucket oprettes som privat via Supabase Storage (dashboard eller `storage.buckets` insert) — dokumentér i `db-rls.sql` ved siden af politikkerne.

### 0d. Nye `red_*` RPC'er (`schema.sql`, følg konventionen `schema.sql:518-561`)

Alle: `SECURITY DEFINER SET search_path=public`; gate `IF current_rolle()<>'redaktion' THEN RAISE`; `PERFORM begin_change_set(...)`; id-alloc `(SELECT coalesce(max(id),0)+1 FROM media)`. Grants automatiske via `db-rls.sql:312-317`-loopet.

- **`red_opret_media(...)`** → opretter række i `'kladde'` med storage-metadata + rettigheds-felter. Returnerer `bigint`.
- **`red_bekraeft_media_upload(p_media_id, p_byte_size, p_sha256)`** → flipper til `'klar'` efter bytes er landet.
- **`red_upload_media(...)`** = kombineret: opretter media + `afbildet`-relation i **ét change_set** (re-entrant `begin_change_set` → nested `red_relation` slutter sig til samme sæt). Tager enten `p_afbildet_person_id` (portræt) eller `p_objekt_type/p_objekt_id` (objekt-foto: estate/coa via `red_relation('media', v_media, p_objekt_type, p_objekt_id, 'afbildet')`).
- **Tilknytning af eksisterende media = eksisterende `red_relation`** — ingen ændring (`schema.sql:820`, accepterer `objekt_type='media'`, blokerer kun `rolle='samme_som'`).

### 0e. Frontend — web (`web/`)

- **Fetch:** tilføj en `relation`-fetch hvor `objekt_type='media'` til `loadModel` (`web/src/data/model.ts`) — spejl org/estate-mønsteret (`web/src/data/public.ts:137-159`, `memberIds`-union for samme_som-foldede), og resolvér `objekt_id` mod `media`-tabellen som `resolveOrgEstateNames` (`public.ts:107-116`). Genbrug `getAll` (`web/src/data/paginate.ts`).
- **Signed URL-helper:** ny lille modul der kalder `supabase.storage.from('media').createSignedUrl(path, ttl)` med kort cache; RLS-gater automatisk.
- **Portræt:** erstat gradient-placeholder `Folgesvend.tsx:703` med `<img>` når personen har et `klar` afbildet-media (portræt-valg: nyeste `klar` afbildet af slags `foto`/`maleri`; eksplicit primær-valg udskudt til Slice 3-kvalifikator). Fallback til eksisterende `Avatar`-initialer (`primitives.tsx:23`).
- **Objekt-billeder:** fyld våben-slots (`Folgesvend.tsx:895/:909`, `ArmsView`) og estate-kort (`EstatesView`) fra deres `afbildet`-medier.
- **Mentions:** udvid `NarrativRenderer.tsx:18-29` så `maalType==='media'` renderer et lille inline-thumbnail/lightbox-link (token parser accepterer allerede `media`, `mentions.ts:14`).
- Alt inline-styling + `theme.ts`-tokens, jf. konventionen.

### 0f. Frontend — mobile (`mobile/`)

- **Ret `mediaBy`-bug:** `buildAux.ts:157-161` skal nøgle på `relation`/`afbildet` (join media↔person via relation), ikke den ikke-eksisterende `m.person_id`. Kræver at `load.ts` også fetcher relevante `relation`-rækker med `objekt_type='media'` (eller udvider den eksisterende relation-fetch).
- **Signed URL-helper:** `mobile/src/lib/` — `supabase.storage.from('media').createSignedUrl(...)`.
- **Materiale-sektion:** `mobile/src/app/person/[id].tsx:209-225` — erstat tælle-strengen med et faktisk galleri (`expo-image` er allerede installeret, `~56.0.11`); portræt i header-slot `:80` (i dag `StripedPlaceholder`).
- **Redaktør-upload:** ny action der følger `Change`→`buildRpcCall`→`submitChange`-mønsteret (`mobile/src/data/redaktionWrite.ts`) med dry-run/LIVE via `SkrivePreviewSheet`. Ny `Change`-art `opretMedia`/`uploadMedia` → `red_upload_media`. Selve billed-valg kræver **ny dependency `expo-image-picker`** (+ evt. `expo-file-system`) — **læs SDK-56-docs først** (`mobile/AGENTS.md` + `app.json`-permission-plugin: `NSPhotoLibraryUsageDescription`/`NSCameraUsageDescription`). Upload-flow: pick → upload bytes til Storage (redaktør-session, RLS write-politik) → `red_upload_media` med `storage_path` → `onApplied` re-fetch.
- **Entitet-browser** (`redaktion/entitet/[type].tsx`) viser allerede `medieListe` read-only — gør rækker tappbare til en simpel medie-detalje/rettigheds-editor.

---

## SLICE 1 — Rig rettigheds-dokumentation
- Vocab: nye `faktatype`-værdier (`licens`, `ophavsret`, `gengivelsestilladelse`, `ophavsret_udloeb`, `public_domain_begrundelse`, `kildehenvisning`) + `rolle`-værdi `rettighedshaver`. Seedes via `vocab.json` (`.claude/skills/daa-extract/references/vocab.json` + `post_load_fixup.R`).
- **`red_set_media_rettigheder(...)`**: opdaterer `rettigheder_status`/`maa_publiceres` + skriver rettigheds-`fact`s via eksisterende `red_upsert_fakta('media', ...)` (re-entrant change_set). Tilladelsesbreve bliver citations.
- Redaktør-UI (web + mobile): rettigheds-panel på medie-detalje.

## SLICE 2 — Bulk R-import (mirror `load_daa.R`)
- Tilføj `"media"` til `id_tables` (`load_daa.R:61`) + `seed_seq` + flush-orden `ord` (`:95`) i FK-sikker position (efter person/estate/coa, **før relation**).
- Ny factory `add_media(...)`; tilknyt via eksisterende `rel_value(..., "media", mid, "afbildet", sid=src)`; rettigheds-dokumentation via eksisterende fact/assertion/citation-factories.
- **Byte-upload uden for Postgres:** i R: `digest::digest(file=..., algo="sha256")` → deterministisk sti `import/<xx>/<sha>.<ext>` (gratis dedup) → `POST {URL}/storage/v1/object/media/{sti}` via `httr` med **service_role**-nøgle (bypasser RLS, korrekt for betroet server-import), `x-upsert: true`. **Bytes først, så DB-række** (`upload_status='klar'`). Service_role kun i `~/.Renviron`, aldrig i klient-bundle.
- Manifest (CSV/JSON): `filnavn, sha256, mime, bredde, hoejde, titel, kunstner, datering, afbildet_person_ref, rettigheder_status, maa_publiceres, licens, rettighedshaver, kildehenvisning`. `afbildet_person_ref` resolveres via `preload_cache`/`get_or_create`.
- Bemærk: bulk-load kører uden `change_set` (som `load_daa.R`) → usynlig for fortryd-historik by design; rettigheds-proveniens overlever som fact/citation.

## SLICE 3 — Ansigts-region-tagging
- Én generisk kvalifikator-kolonne på relation: `ALTER TABLE relation ADD COLUMN kvalifikator JSONB` (fx `{"bbox":{...},"coord":"rel"}`). `afbildet`-relationen forbliver eneste sandhed for "hvem er i billedet"; bbox er valgfri detalje på samme række → `media_afbilder_skjult` uændret. *Muliggør også eksplicit primær-portræt-flag.*

## SLICE 4 — Albums + event-scoped medier
- Album = `fact` på media, `faktatype='samling'`, værdi=albumnavn (ingen ny tabel). De fleste "albums" er emergente (en persons galleri = query `afbildet→person`). Kun hvis kuraterede albums senere kræver rig metadata → overvej tynd `samling`-entitet (flag som eneste berettigede nye-entitet-tilfælde).
- Event-scoped = ren `relation` `media→historical_event`, ny rolle `dokumenterer`. Intet nyt.

## SLICE 5 — Crowdsource/medlemsbidrag (senere, ude af scope nu)
- Sandsynligt: `bidrag`/moderations-status på media + non-redaktion write-RPC + moderationskø.

---

## Slice-oversigt

| Slice | Leverer | Kerne-filer |
|---|---|---|
| **0 (MVP)** | Storage-kolonner + gating + bucket + objekt-RLS + `red_upload_media` + portræt/objekt-visning (web+mobile) | `schema.sql`, `db-rls.sql`, `db-migrations.sql`, `web/src/data/*`, `web/src/Folgesvend.tsx`, `mobile/src/data/buildAux.ts`+`load.ts`, `mobile/src/app/person/[id].tsx`, `mobile/src/data/redaktionWrite.ts` |
| 1 | Rig rettigheds-dokumentation + `red_set_media_rettigheder` | `schema.sql`, `vocab.json`, redaktør-UI |
| 2 | Bulk R-import | `.claude/skills/daa-extract/scripts/load_daa.R`, ny `import_media.R` |
| 3 | Ansigts-region-tagging | `relation.kvalifikator` |
| 4 | Albums + event-scoped | vocab-værdier |
| 5 | Crowdsource | (nyt design) |

---

## Invariant-spændinger (eksplicit flagget)
1. **Storage-kolonner fedter den "tynde" media** — kun bytes-metadata; semantik forbliver relation/fact. Afgrænset.
2. **`maa_publiceres` er kontrol-kolonne, ikke fact** — konsistent med `person.levende`/`privat`-præcedensen.
3. **`relation.kvalifikator jsonb` (Slice 3)** — én polymorf kvalifikator-slot på den ene polymorfe relation; ikke ny tabel.
4. **Privat bucket + signed URLs** — bytter overhead for tilbagekaldelighed (påkrævet: dynamisk gating).
5. **Bulk-import usynlig for change-historik** — konsistent med `load_daa.R`; proveniens som fact/citation.

---

## Verifikation
- **DB/RLS:** udvid `db-verify.sql` (mønster `:175-194`): objekt-foto uden person → synligt for anon; portræt af afdød ikke-privat + `maa_publiceres=true` → synligt; samme med `maa_publiceres=false` → skjult for anon **og** medlem, synligt for redaktion; portræt af levende → skjult for anon, synligt for medlem. Verificér `storage.objects`-politikker via `media_id_for_object`-mapping (også forældreløst objekt → skjult).
- **RPC:** kør `red_upload_media` som redaktør-rolle mod dev/prod-svarende base; bekræft media-række + `afbildet`-relation i ét change_set; bekræft `red_fortryd_change_set` ruller begge tilbage.
- **Web:** `tsc` + web-tests + build; empirisk (Playwright) mod prod — portræt renderer via signed URL, skjult billede giver ingen URL.
- **Mobile:** `tsc` + jest; **iOS-simulator/fysisk enhed** mod prod (jf. `mobil-sim-rn-fetch-1005`-memory): portræt i header, galleri i Materiale, redaktør-upload dry-run→LIVE.
- **Bulk-import (Slice 2):** dry-run mod manifest-udsnit; bekræft dedup (samme sha256 → samme sti, ingen dublet), `upload_status='klar'`, afbildet-links.

## Åbent punkt til afklaring ved build-start
- **Primær-portræt-valg:** MVP bruger deterministisk "nyeste `klar` afbildet af slags foto/maleri". Eksplicit "dette er visnings-portrættet"-markering udskydes til Slice 3-kvalifikatoren. Bekræft dette er acceptabelt, ellers tilføjes et let flag i Slice 0.

---

## PROD-OPSÆTNING RUNBOOK (Slice 0) — kør i Supabase-dashboardet

Al kode er committet/pushet + verificeret lokalt (Postgres 16 + Supabase-stub: Task 8/12/12b grønne;
web tsc+147+build; mobile tsc+264). Prod-projektet mangler kun opsætning. Alle Supabase-afhængigheder er
doc-verificeret understøttet; billed-transformationer (Pro-only) bruges IKKE — vi serverer originaler.
Free-tier: 1 GB storage, ~5 GB egress/md, 50 MB max fil, pauser efter 7 dages inaktivitet.

**Rækkefølge: migrations → rls → bucket → verify.**

1. **SQL Editor → kør `db-migrations.sql`** (idempotent): media-kolonner + indekser + RPC'er
   (`red_opret_media`, `red_bekraeft_media_upload`, `red_upload_media`, `red_set_media_rettigheder`) +
   `red_relation` GDPR-guard + sha256-dedup.
2. **SQL Editor → kør `db-rls.sql`** (re-runnable): helpers (`media_rettigheder_ok`, `media_id_for_object`,
   `media_synlig_anon/auth`) + udvidede media-tabel-politikker + `storage.objects`-politikker.
   *Migrations SKAL køres først (helperne læser de nye kolonner).*
3. **Storage → New bucket:** navn `media`, **Public: FRA** (privat). Alternativt SQL:
   `insert into storage.buckets (id,name,public) values ('media','media',false) on conflict do nothing;`
4. **SQL Editor → kør `db-verify.sql`:** forvent `OK: media-gating`, `OK: media rettigheds-gating`,
   `OK: storage.objects-politikker`. (Task 12b kører kun når bucket'en findes.) Seeder/rydder selv op.
5. **App-env:** `VITE_SUPABASE_*` / `EXPO_PUBLIC_SUPABASE_*` peger på projektet. Read-path bruger anon-nøglen;
   ingen nye hemmeligheder (service_role behøves først ved Slice 2 bulk-import).

**Rollback:** kolonner additive (intet datatab); RPC-ændringer fortrydbare via `red_fortryd_change_set`;
RLS rulles tilbage ved at køre forrige `db-rls.sql` fra git-historik. **Bucket SKAL være privat** —
en offentlig bucket omgår RLS via permanente URLs.
