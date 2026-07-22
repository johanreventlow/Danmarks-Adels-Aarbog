# Mediehåndtering — fase 4: identitet & endeligt farvel (erstat fil, udrensning, portræt-valg) · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mediets *identitet* skilles endeligt fra dets *bytes*: `red_erstat_media_fil` (M4)
udskifter filen bag et stabilt media-id uden at røre relationer/mentions/rettigheder; den
sjældne *rigtige* sletning får sin gatede to-trins-vej `red_udrens_media` + preview (M11,
kun fra `'fjernet'`, blokeret ved enhver anvendelse); og portrættet bliver et redaktionelt
valg via `red_saet_portraet` + `relation.kvalifikator` `{"primaer":true}` (M10) — med
`pickPortrait` degraderet til fallback i begge læseflader.

**Architecture:** Lille additiv DDL (én jsonb-kolonne på `relation` + tre RPC'er + én
preview-RPC — versionering/fortryd kommer gratis via eksisterende `trg_log_media`/
`trg_log_relation` og `version_pk_registry`). App-laget: tre nye `Change`-arter i begge
platformes skrive-lag (erstat genbruger fase 3's sha-sti-pipeline og uploader bytes FØR
RPC'en; udrens er DB-først, klient-sidet `storage.remove` bagefter), kvalifikator-flaget
føres gennem læse-lagene til `pickPortrait`, og filsiden (web-overlay + mobile-sheet) får
de tre handlinger. INGEN janitor-ændring (kategori b dækker allerede erstat-efterladenskaber)
og INGEN RLS-ændring (`media_obj_delete`-politikken findes og får sin første forbruger).

**Tech Stack:** PostgreSQL/Supabase (idempotent migrationsblok
`mediehaandtering_fase4_identitet`, verify-asserts med simulerede redaktør-claims),
TypeScript, React/Vite + vitest (web), RN/Expo + jest (mobile).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-21-mediehaandtering-fase4-identitet-design.md` (autoritativ; §-referencer nedenfor peger dertil). ⚠ Spec-filen er pt. **utracket** i git — committes som en del af Task 1's første commit, så plan og spec følges ad i historikken.
- Review: `docs/reviews/34-mediehaandtering-fase4-plan-dual-review.md` (dual-review Claude + ægte Codex CLI). **Indarbejdet i denne plan-revision:** H1+H3 (udrens blokerer på ALLE polymorfe ankre — fakta m. evidenskæde, story, narrativ, defensiv note — ikke kun relation+mention; spec §1's FK-billede talte kun deklarative FK'er), H2 (guard+slet kollapset til ét atomisk DELETE-statement, TOCTOU-lukning), L1 (preview-feltet omdøbt `afbildet`→`tilknytninger`). M1 dismissed med bevis (Task 3's kode uændret — se funktions-kommentaren). Scope-afgrænsning pr. reviewet: `red_relation`/`red_opret_story`/`red_upsert_narrativ` røres IKKE.
- Koncept: `docs/design/2026-07-19-mediehaandtering-robust-koncept.md` (§4.3, §4.5, §4.7, §5, §9, §10.1–2)
- Kortlægning (fil:linje **re-verificeret på main `caeb6a3` 2026-07-22, efter PR #74-merge — alle spec'ens ankre holder uden drift**): `red_slet_person_preview` (`schema.sql:1883-1904`), `red_fjern_media`/`red_genopret_media` (`schema.sql:2113-2119`/`2077-2087`), `red_opret_media`s dedup-guard (`schema.sql:1987-1991`), `red_registrer_media_variant` (`schema.sql:2128-2146`, tier-validering + upsert, INTET change_set), `_delete_relation_evidence`/`red_slet_relation` (`schema.sql:1230-1243`/`1245-1251`), `red_slet_medierelation_uden_evidens` (`schema.sql:1309-1339`), `relation`-tabellen uden kvalifikator (`schema.sql:355-368`) + `relation_afbildet_uidx` (`:369-371`), `media_variant` eneste FK mod `media` med CASCADE (`schema.sql:100` — grep bekræfter INGEN andre `REFERENCES media`), GDPR-guarden i `red_relation` (`schema.sql:1204-1206`), `version_pk_registry` med `relation` (`:2169`) og `media` (`:2183`), `log_change`-DELETE-snapshot (`:2280-2293`), `_version_upsert_row` (`:2330-2365`) + DELETE-inverse (`:2415-2419`), `red_doede_links`-media-gren (`schema.sql:2521-2526`), `media_obj_delete` (`db-rls.sql:296-298`), `media_id_for_object` fail-closed (`db-rls.sql:154-162`), navnebaseret `red_*`-grant-loop (`db-rls.sql:512-518`), `pickPortrait` + relations-fetch (`web/src/data/media.ts:114-141,168-171`; `mobile/src/lib/media.ts:87-89`), skrive-lag (`web/src/data/redaktionWrite.ts:19-63` union, `:365-382` uploadMedia, `:504-543` submitChange m. hård gate `:512-514`, `:546-558` oversaetFejl; mobile-spejl `mobile/src/data/redaktionWrite.ts:18-60,342-359,437-475,486-501`), fase 3-pipelinen (`web/src/data/mediaUpload.ts:56-99`, `mobile/src/lib/mediaUpload.ts:82-120`), pre-flight-helperen `fetchExistingMediaBySha` (`web/src/data/mediaDedup.ts:83-87` + mobile-spejl), filsiden (`web/src/components/MediaDetaljeOverlay.tsx`, wiring `web/src/Redaktion.tsx:1309-1412`, `MEDIA_ARTER` `:51`; `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`, wiring `mobile/src/app/redaktion/entitet/medie/[id].tsx:129-146` + `mobile/src/app/redaktion/person/[id].tsx:653-665`), impersonerings-mønsteret i verify (`db-verify.sql:1883-1985`: `set_config('request.jwt.claim.sub',…)` + seedet redaktion-profil + `app.change_set_id`-reset + `ROLLBACK_TEST_OK`), migrationsfilens blok-mønster (`db-migrations.sql:2727-2871`, fase 3-blokken; filen slutter ved `red_publicer_personer` `:3109-3132` — fase 4-blokken appendes EFTER den).
- **Faktuel finjustering af spec fundet under verifikation (§6-tabellen):** degraderings-mekanismen til `red_suggest` findes **kun på web**. `mobile/src/data/redaktionWrite.ts` har hverken `buildSuggestCall`, `planCall` eller `role`-parameter — mobiles `submitChange` kaster ved `buildRpcCall(...)===null` og kalder ellers altid direkte (`:442-443`), og mobile-UI'et er allerede rolle-gatet (`rolle !== 'redaktion'`-early-return, fx `medie/[id].tsx:125`). Konsekvens: den "hårde gate" for `erstatMediaFil`/`udrensMedia` er en **web-kodeændring**; på mobile er alle tre arter almindelige direkte RPC'er, og `saetPortraet`s "ja til degradering" gælder kun web. Ingen spec-ændring — dokumenteret her (samme mønster som fase 3-planens `relation_pkey`-fund).
- **Arbejdstræ-status (2026-07-22):** main har **ukommitterede docs-ændringer** fra fase 3-prod-cutover-sessionen (`docs/changelog.md`, `docs/database-current-state.md`, `docs/db-backups/2026-07-20-mediehaandtering-fase3-runbook.md`, `docs/design/2026-07-19-mediehaandtering-robust-koncept.md`). De må IKKE overskrives eller stages med af fase 4-commits — branch fra main og commit kun egne filer (global regel §3).
- **Spec'ens §10 punkt 1–2 er besluttet** (accepter hård sletning; frist = janitorens `--frist-dage`). Punkt 3–5 afgøres HER: **§10.3** variant-mismatch efter fortryd-af-erstat accepteres som dokumenteret begrænsning (ingen "erstat tilbage"-UI i denne fase — B8 står). **§10.4** to-trins-bekræft = dobbelt-klik-bekræft (genbrug filsidens eksisterende `bekraeftSlet`-mønster, `MediaDetaljeOverlay.tsx:220-226` — ingen skriv-ordet-dialog, projektet har intet præcedens for den); INGEN masse-udrensning i papirkurvs-køen (4 rækker i prod — YAGNI). **§10.5** portræt-ryd-grenen (`p_media_id = NULL`) MEDTAGES (lille, symmetrisk, spec'et).

## Global Constraints

- **Prod røres ALDRIG af denne plan.** Al DDL verificeres kun mod lokal Postgres (frisk
  `schema.sql`-install + migrationssti ×2, jf. memory 'lokal-db-testbase': brew
  postgresql@17 + auth-shim + genskabt prod-kopi). Prod-deploy er et separat,
  controller-gated trin (backup + bruger-OK) EFTER planen — se Task 11. Migrationen
  navngives `mediehaandtering_fase4_identitet`; `get_advisors(security)` køres efter
  prod-apply (husreglen 'koer-get-advisors-efter-ddl').
- **Web/mobile-lagene er bevidst duplikeret** — `redaktionWrite.ts`, `redaktionRead.ts`,
  `media.ts`-lagene og UI-komponenterne ændres ens begge steder ("hold i sync"-
  headerkontrakten). Delt-pakke-ekstraktion er fortsat follow-up og må ikke ske her.
- **dryRun-prop-threading-regressionstest for HVER ny UI-indgang** (læringen fra PR #72,
  spec §6): hver ny skrivevej skal have en test der beviser at dry-run-tilstanden
  respekteres ("default respekteres") — konkret: ved dry-run uploades INTET, intet
  `storage.remove`-kald, og RPC'en udføres ikke.
- **INGEN janitor-ændring** (spec §1): kategori b i `R/media-janitor.R` dækker allerede
  erstat-efterladenskaber (forladte sha-stier = forældreløse objekter); fristbindingen
  (§3.3/§10.2) er en dokumenteret kontrakt, ikke ny kode. `R/media-janitor.R` og
  `tests/testthat/test-media-janitor.R` røres IKKE.
- **INGEN RLS-ændring:** `db-rls.sql` røres ikke. Nye `red_*`-funktioner gates i kroppen
  (`current_rolle()`), er kaldbare af authenticated via Supabases default-grants (prod)
  hhv. det navnebaserede grant-loop (`db-rls.sql:512-518`, frisk install). Udrensningens
  `storage.remove` er den EKSISTERENDE `media_obj_delete`-politiks første forbruger.
- **Erstat overskriver ALDRIG gamle objekter** (koncept §4.5): nye bytes lander på NYE
  sha-stier (fase 3-pipelinen uændret); gamle stier bliver forældreløse = fail-closed
  usynlige. Ingen task må "optimere" til at slette/overskrive de gamle stier — janitoren
  ejer dem.
- **Udrens er DB-først:** `red_udrens_media` sletter rækken og RETURNERER stierne;
  klienten kalder `storage.remove` BAGEFTER. Fejler Storage-kaldet, vises en advarsel
  ("bytes ryddes af janitoren") — DB-tilstanden ER sandheden, aldrig omvendt rækkefølge.
- **Ingen nye farver/fonte:** web styler med de eksisterende `C`-konstanter i
  `MediaDetaljeOverlay.tsx`; mobile med `mobile/src/theme/tokens.ts` + `Typography`.
  Dialoger genbruger eksisterende bekræft-/sheet-mønstre.
- **CI-hygiejne (fase 1-læringen):** INGEN ændringer af `.github/workflows/`; ingen
  selv-committende jobs. Alle commits laves af implementøren selv.
- Hver task holder relevant suite grøn: web → `cd web && npx tsc --noEmit && npm run test
  && npm run build`; mobile → `cd mobile && npx tsc --noEmit && npm test`; DB → frisk
  install + verify-filer mod lokal Postgres.
- Commit-beskeder på dansk, `feat(media): …`-stil; brug din egen sessions
  Claude-Session-footer. Branch fra main (fx `feat/media-fase4-identitet`); rør ikke de
  ukommitterede docs-ændringer (se Kilder).

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql`, `db-verify.sql` | `red_erstat_media_fil` + impersonerede RPC-asserts | 1 |
| `schema.sql`, `db-verify.sql`, `db-verify-media.sql` | `red_udrens_media_preview` + `red_udrens_media` + asserts (guards på alle polymorfe ankre, atomisk slet, paritet, anon-0-synlighed) | 2 |
| `schema.sql`, `db-verify.sql` | `relation.kvalifikator`-kolonne + `red_saet_portraet` + asserts | 3 |
| `db-migrations.sql` | Idempotent blok `mediehaandtering_fase4_identitet` (kolonne + 4 funktioner verbatim) | 4 |
| `web/src/data/redaktionWrite.ts` (+ test) | 3 nye Change-arter, hårde gates, erstat-upload-flow, `oversaetFejl`-grene | 5 |
| `mobile/src/data/redaktionWrite.ts` (+ test) | Spejl af Task 5 (uden degraderings-mekanik — findes ikke på mobile) | 6 |
| `web/src/data/media.ts` (+ test), `web/src/data/redaktionRead.ts` (+ test) | `kvalifikator` gennem læse-laget: `MediaItem.primaer`, `pickPortrait`-prioritet, `PersonMedia.primaer`, `MediaAnvendelse.afbildet[].primaer`, `fetchUdrensPreview` | 7 |
| `mobile/src/data/load.ts`, `mobile/src/data/types.ts`, `mobile/src/data/buildAux.ts`, `mobile/src/lib/media.ts` (+ test), `mobile/src/data/redaktionRead.ts` (+ test) | Mobile-spejl af Task 7 | 8 |
| `web/src/components/MediaDetaljeOverlay.tsx`, `web/src/Redaktion.tsx` | Erstat-/udrens-/portræt-UI på filsiden + dryRun-sikret udrens-orkestrering | 9 |
| `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`, `mobile/src/app/redaktion/entitet/medie/[id].tsx`, `mobile/src/app/redaktion/person/[id].tsx` | Mobile-spejl af Task 9 | 10 |
| `docs/changelog.md`, `docs/database-current-state.md`, koncept-§9-tabellen | Samlet verifikation, afstemning + prod-runbook-note (inkl. koncept-§9's forældede fase 1+2-statuslinjer) | 11 |

Afhængigheder (spec §2): Task 1–3 er indbyrdes uafhængige DB-skiver; Task 4 kræver 1–3;
Task 5–6 kræver 1–3 (RPC-kontrakterne); Task 7–8 kræver 3; Task 9 kræver 5+7; Task 10
kræver 6+8; Task 11 kræver alt. 5/7/9 (web) og 6/8/10 (mobile) er indbyrdes uafhængige
platform-spejlinger.

---

## Task 1: DB — `red_erstat_media_fil` i `schema.sql` + asserts (spec §3, M4)

**Files:**
- Modify: `schema.sql` (ny funktion efter `red_registrer_media_variant`, dvs. efter `:2146`)
- Modify: `db-verify.sql` (ny impersonerings-DO-blok efter fase 3-blokken `:1987-2022`)

**Interfaces:**
- Consumes: `red_registrer_media_variant(p_media_id,p_tier,p_storage_path,p_mime,p_byte_size,p_bredde,p_hoejde)` (`schema.sql:2128-2146` — upsert på `(media_id,tier)`, tier-validering, INTET change_set), `begin_change_set(operation,summary,subjekt_type,subjekt_id)`, `current_rolle()`.
- Produces (Task 4 kopierer verbatim; Task 5 kalder):
```sql
red_erstat_media_fil(
  p_media_id bigint,
  p_storage_path text, p_mime text, p_byte_size bigint,
  p_bredde int, p_hoejde int, p_sha256 text,
  p_original_filnavn text DEFAULT NULL,   -- NULL/tom = behold eksisterende
  p_varianter jsonb DEFAULT '[]'          -- [{tier,storage_path,mime,byte_size,bredde,hoejde},…]
) RETURNS void
-- Domæne-fejl (Task 5's oversaetFejl matcher på disse): 'Kun redaktion',
-- 'Media % findes ikke', 'Kan kun erstatte filen på et klart medie',
-- 'Filen er identisk med den nuværende',
-- 'Medie med samme indhold findes allerede (sha256=%)…' (samme form som red_opret_media)
```

- [ ] **Step 1: Skriv den fejlende assert-blok i `db-verify.sql`** (indsæt efter fase 3-blokken, før "Levende feed fase 3"-blokken `:2024`). Mønsteret er fase 1-blokkens (`:1883-1985`): impersonér redaktion, reset `app.change_set_id` før hvert RPC-kald, afslut med `ROLLBACK_TEST_OK`:

```sql
-- ===== Mediehåndtering fase 4: red_erstat_media_fil (erstat fil, stabil identitet) =====
DO $$
DECLARE v_id bigint; v_rel bigint; v_andet bigint; v_cs bigint; v_thumb_foer text; v_thumb_efter text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Seed: klart medie med sha + thumb-variant + afbildet-relation (identiteten der skal overleve)
  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,titel,storage_path,mime_type,byte_size,bredde,hoejde,sha256,
                    original_filnavn,upload_status,maa_publiceres)
    VALUES (v_id,'foto','Erstat-test','redaktor/aa/gammel-large.jpg','image/jpeg',100,20,10,
            '__f4_gammel_sha_'||v_id,'gammel.jpg','klar',false);
  INSERT INTO media_variant(id,media_id,tier,storage_path)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM media_variant),v_id,'thumb','redaktor/aa/gammel-thumb.jpg');
  v_rel := red_relation('person',-999941,'media',v_id,'afbildet');
  SELECT storage_path INTO v_thumb_foer FROM media_variant WHERE media_id=v_id AND tier='thumb';

  -- Happy path: én transaktion flytter identiteten + re-registrerer varianter
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_erstat_media_fil(v_id,'redaktor/bb/ny-large.jpg','image/jpeg',200,40,20,
    '__f4_ny_sha_'||v_id, NULL,
    jsonb_build_array(jsonb_build_object('tier','thumb','storage_path','redaktor/bb/ny-thumb.jpg',
      'mime','image/jpeg','byte_size',5,'bredde',4,'hoejde',2)));
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND storage_path='redaktor/bb/ny-large.jpg'
                 AND sha256='__f4_ny_sha_'||v_id AND byte_size=200
                 AND original_filnavn='gammel.jpg' AND upload_status='klar') THEN
    RAISE EXCEPTION 'FEJL: erstat opdaterede ikke rækken korrekt (eller mistede original_filnavn)';
  END IF;
  SELECT storage_path INTO v_thumb_efter FROM media_variant WHERE media_id=v_id AND tier='thumb';
  IF v_thumb_efter <> 'redaktor/bb/ny-thumb.jpg' THEN
    RAISE EXCEPTION 'FEJL: varianten blev ikke re-registreret atomisk';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM relation WHERE id=v_rel AND objekt_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: relationen overlevede ikke erstatningen';
  END IF;

  -- Guard: identisk sha (no-op-erstat afvises)
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/bb/ny-large.jpg','image/jpeg',200,40,20,'__f4_ny_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: identisk sha blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Filen er identisk med den nuværende%' THEN RAISE; END IF;
  END;

  -- Guard: sha på ANDEN række (dedup-bagstopper)
  v_andet := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,upload_status,sha256) VALUES (v_andet,'foto','klar','__f4_andet_sha_'||v_id);
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/cc/x.jpg','image/jpeg',1,1,1,'__f4_andet_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: fremmed sha blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Medie med samme indhold findes allerede%' THEN RAISE; END IF;
  END;

  -- Guard: kun 'klar'
  UPDATE media SET upload_status='fjernet' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_tredje_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: fjernet medie kunne erstattes';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun erstatte filen på et klart medie%' THEN RAISE; END IF;
  END;
  UPDATE media SET upload_status='klar' WHERE id=v_id;

  -- Fortryd: media-rækken ruller tilbage til gamle stier; variant-rækken bliver
  -- BEVIDST stående på den nye sti (uversioneret cache, B8 — spec §3.2, plan-beslutning §10.3)
  SELECT max(id) INTO v_cs FROM change_set WHERE operation='red_erstat_media_fil';
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs, false);
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND storage_path='redaktor/aa/gammel-large.jpg'
                 AND sha256='__f4_gammel_sha_'||v_id) THEN
    RAISE EXCEPTION 'FEJL: fortryd rullede ikke media-rækken tilbage';
  END IF;
  IF (SELECT storage_path FROM media_variant WHERE media_id=v_id AND tier='thumb')
     <> 'redaktor/bb/ny-thumb.jpg' THEN
    RAISE EXCEPTION 'FEJL: variant-cache uventet versioneret (B8-kontrakten er brudt)';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 4 erstat-fil (guards, atomiske varianter, fortryd, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør mod frisk lokal install og bekræft FEJL.** Frisk base (lokal-db-testbase-opskriften: auth-shim + `psql -f schema.sql -f db-migrations.sql -f db-rls.sql`), derefter `psql -f db-verify.sql`. Forvent: den nye blok fejler med `function red_erstat_media_fil(...) does not exist`.

- [ ] **Step 3: Implementér funktionen i `schema.sql`** (efter `red_registrer_media_variant`, `:2146`):

```sql
-- Fase 4 (M4): erstat mediets BYTES men behold dets IDENTITET (id, relationer, mentions,
-- rettigheder, bogmærkelinks). Klienten har lagt de nye bytes på NYE sha-stier FØRST
-- (fase 3-pipelinen, idempotent) — dette kald flytter rækkens identitet atomisk over på dem.
-- Gamle objekter overskrives ALDRIG: de bliver forældreløse (media_id_for_object → NULL =
-- fail-closed usynlige) og ryddes af janitorens kategori b efter --frist-dage — DET er
-- fortryd-vinduet (koncept §10.2). Varianter re-registreres INDE i transaktionen (et afbrud
-- må ikke efterlade ny large + gamle thumbs); red_registrer_media_variant åbner bevidst intet
-- eget change_set, så hele erstatningen er ÉT fortrydbart sæt — fortryd-historikken ER
-- filhistorikken (koncept §4.5), ingen media_version-tabel. KENDT begrænsning (B8, spec §3.2):
-- fortryd ruller kun media-rækken tilbage; variant-rækkerne er uversioneret cache og bliver
-- stående på de nye stier (selvopdagende thumb/large-mismatch — afhjælpes ved at erstatte igen).
CREATE OR REPLACE FUNCTION red_erstat_media_fil(
  p_media_id bigint,
  p_storage_path text, p_mime text, p_byte_size bigint,
  p_bredde int, p_hoejde int, p_sha256 text,
  p_original_filnavn text DEFAULT NULL,
  p_varianter jsonb DEFAULT '[]'
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_egen_sha text; v_v record;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_storage_path),'') IS NULL THEN RAISE EXCEPTION 'Storage-sti er påkrævet'; END IF;
  IF nullif(btrim(p_sha256),'') IS NULL THEN RAISE EXCEPTION 'sha256 er påkrævet'; END IF;
  SELECT upload_status, sha256 INTO v_status, v_egen_sha FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  -- 'kladde' færdiggøres via fase 3's genoptag-flow; 'fjernet' genoprettes først.
  IF v_status <> 'klar' THEN RAISE EXCEPTION 'Kan kun erstatte filen på et klart medie'; END IF;
  -- Dedup-guard, to grene (klientens pre-flight fanger begge FØR bytes uploades; dette er race-bagstopperen):
  IF v_egen_sha = p_sha256 THEN RAISE EXCEPTION 'Filen er identisk med den nuværende'; END IF;
  IF EXISTS (SELECT 1 FROM media WHERE sha256 = p_sha256 AND id <> p_media_id) THEN
    RAISE EXCEPTION 'Medie med samme indhold findes allerede (sha256=%). Genbrug den eksisterende media-række via red_relation.', p_sha256;
  END IF;
  PERFORM begin_change_set('red_erstat_media_fil', format('Erstattede filen på media %s', p_media_id), 'media', p_media_id);
  UPDATE media SET
    storage_path = p_storage_path, mime_type = p_mime, byte_size = p_byte_size,
    bredde = p_bredde, hoejde = p_hoejde, sha256 = p_sha256,
    original_filnavn = coalesce(nullif(btrim(p_original_filnavn),''), original_filnavn)
  WHERE id = p_media_id;
  FOR v_v IN SELECT * FROM jsonb_to_recordset(coalesce(p_varianter,'[]'::jsonb))
      AS x(tier text, storage_path text, mime text, byte_size bigint, bredde int, hoejde int)
  LOOP
    PERFORM red_registrer_media_variant(p_media_id, v_v.tier, v_v.storage_path,
                                        v_v.mime, v_v.byte_size, v_v.bredde, v_v.hoejde);
  END LOOP;
END $$;
```

- [ ] **Step 4: Frisk install + verify grøn.** Kør frisk install-cyklussen igen (auth-shim → schema → migrations → rls → verify). Forvent NOTICE `OK: media fase 4 erstat-fil …` og INGEN regression i eksisterende blokke.

- [ ] **Step 5: Commit**

```bash
git add schema.sql db-verify.sql docs/superpowers/specs/2026-07-21-mediehaandtering-fase4-identitet-design.md docs/superpowers/plans/2026-07-22-mediehaandtering-fase4-identitet.md
git commit -m "feat(media): tilføj red_erstat_media_fil — erstat bytes, behold identitet

Fase 4 skive 1 (spec §3): atomisk UPDATE + variant-re-registrering i ét
change_set; dedup-guard i to grene; fortryd-historikken er filhistorikken."
```

## Task 2: DB — `red_udrens_media_preview` + `red_udrens_media` i `schema.sql` + asserts (spec §4, M11)

**Files:**
- Modify: `schema.sql` (to nye funktioner efter `red_erstat_media_fil` fra Task 1)
- Modify: `db-verify.sql` (ny impersonerings-DO-blok efter Task 1's blok)
- Modify: `db-verify-media.sql` (ny DO-blok — filens kontrakt: `SET LOCAL ROLE`/direkte seed-DML, INGEN redaktør-RPC'er)

**Interfaces:**
- Consumes: `begin_change_set`, `current_rolle()`; `media_variant` CASCADE'r ved media-DELETE (`schema.sql:100`); `trg_log_media` logger DELETE med `foer`-snapshot; forbilledet `red_slet_person_preview` (`schema.sql:1883-1904`); anker-skriverne der gør guardsne nødvendige: `red_set_media_rettigheder` (`schema.sql:2091` — skriver `fact` m. hel evidenskæde på mediet via `red_upsert_fakta`), `red_opret_story` (`schema.sql:986` — validerer IKKE sit polymorfe mål), `red_upsert_narrativ` (`schema.sql:1170` — ditto).
- Produces (Task 4 kopierer verbatim; Task 5/7 kalder):
```sql
red_udrens_media_preview(p_media_id bigint) RETURNS jsonb
-- { "upload_status": text, "kan_udrenses": bool, "blokeringer": [tekst…],
--   "antal_tilknytninger": n, "antal_mentions": n,
--   "antal_fakta": n, "antal_stories": n, "antal_narrativer": n, "antal_noter": n,
--   "tilknytninger": [{"relation_id","retning":"ud"|"ind","modpart_type","modpart_id"}…],
--   "mentions": [{"kilde_type","kilde_id"}…],
--   "fakta": [id…], "stories": [id…], "narrativer": [id…], "noter": [id…],
--   "stier": [{"bucket","sti","kilde":"media"|"thumb"|"medium"}…] }
-- (Review 34 L1: feltet hed 'afbildet' i første plan-udkast — omdøbt til 'tilknytninger',
-- fordi det indeholder ALLE relationer, enhver rolle, begge retninger. Task 7's
-- MediaAnvendelse.afbildet er et SEPARAT, korrekt navngivet felt og røres ikke.)

red_udrens_media(p_media_id bigint) RETURNS jsonb   -- {"stier":[{"bucket","sti"}…]}
-- Domæne-fejl: 'Kun redaktion', 'Media % findes ikke', 'Kan kun udrense et fjernet medie',
-- 'Mediet har tilknytninger og kan ikke udrenses — fjern dem først',
-- 'Mediet er nævnt i narrativer og kan ikke udrenses — redigér omtalerne ud først',
-- 'Mediet har rettighedsdokumentation (fakta) og kan ikke udrenses — fjern den først',
-- 'Mediet er subjekt for en story og kan ikke udrenses — flyt eller slet storyen først',
-- 'Mediet har et tilknyttet narrativ og kan ikke udrenses — slet narrativet først',
-- 'Mediet har noter og kan ikke udrenses — fjern dem først',
-- 'Mediet kunne ikke udrenses — tilstanden ændrede sig undervejs, prøv igen'  (race-bagstopper, H2)
-- De fire nye fejl + bagstopperen er læsbare danske tekster og falder gennem oversaetFejls
-- rå-besked-fallback (web:546-558) — INGEN Task 5/6-ændring nødvendig for dem.
```

> **Review 34 (H1/H2/H3) indarbejdet i denne task:** udrens blokerer fail-loud på ALLE
> polymorfe ankre i den FK-frie model — `relation` (begge retninger), `text_mention`,
> `fact` med `subjekt_type='media'` (rettighedsdokumentation skabt af den LIVE
> `red_set_media_rettigheder`; evidenskæden `assertion`/`citation`/`conclusion` hænger på
> fact'et via `target_type='fact'` og følger dets blokering — intet kan forældreløses),
> `story` og `narrative` med `subjekt_type='media'` (deres RPC'er validerer ikke målet)
> samt `note` med `target_type='media'` (DEFENSIVT — ingen live RPC skriver den i dag,
> samme forsigtighed som `red_slet_person`s note-håndtering). `haendelse` cascader FRA
> `narrative` (`ON DELETE CASCADE`, `schema.sql:436`) og kræver INGEN selvstændig kode —
> den er ikke overset, den følger narrativ-blokeringen gratis. Guard-tjek og sletning er
> desuden kollapset til ÉT atomisk DELETE-statement (H2, TOCTOU-lukning). Scope-afgrænsning
> pr. reviewets beslutning: `red_relation`/`red_opret_story`/`red_upsert_narrativ` ændres IKKE.

- [ ] **Step 1: Skriv de fejlende asserts.**
  - `db-verify.sql` (impersonerings-blok, samme skabelon som Task 1's Step 1):

```sql
-- ===== Mediehåndtering fase 4: red_udrens_media + preview (den rigtige sletning) =====
-- Review 34: seeder BEVIDST alle seks polymorfe ankre (relation, mention, fakta via LIVE
-- red_set_media_rettigheder, story via red_opret_story, narrativ via red_upsert_narrativ,
-- note direkte) og rydder dem én ad gangen — den oprindelige plan seedede kun to og
-- passerede grøn med H1/H3 til stede. H2 (atomisk guard+slet) er ikke serielt testbar;
-- den verificeres ved kode-form (ét DELETE-statement, Step 3) + race-bagstopper-fejlteksten.
DO $$
DECLARE v_id bigint; v_rel bigint; v_story bigint; v_narr bigint; v_note bigint;
        v_prev jsonb; v_res jsonb; v_cs bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Seed: fjernet medie m. variant + ALLE seks ankre
  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,titel,storage_path,upload_status,maa_publiceres)
    VALUES (v_id,'foto','Udrens-test','redaktor/ee/udrens-large.jpg','fjernet',false);
  INSERT INTO media_variant(id,media_id,tier,storage_path)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM media_variant),v_id,'thumb','redaktor/ee/udrens-thumb.jpg');
  v_rel := red_relation('person',-999942,'media',v_id,'afbildet');
  INSERT INTO text_mention(kilde_type,kilde_id,maal_type,maal_id) VALUES ('narrative',-999942,'media',v_id);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_media_rettigheder(v_id,'afklaret',false,'CC-BY-4.0','Testarkivet',NULL,'fase4-verify');
  PERFORM set_config('app.change_set_id','',true);
  v_story := red_opret_story('media',v_id,'En story der peger direkte på mediet');
  PERFORM set_config('app.change_set_id','',true);
  v_narr := red_upsert_narrativ('media',v_id,'Et narrativ ophængt på mediet',false,NULL);
  v_note := (SELECT coalesce(max(id),0)+1 FROM note);
  INSERT INTO note(id,target_type,target_id,indhold) VALUES (v_note,'media',v_id,'defensiv note');
  IF NOT EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: seed-forudsætning brast — red_set_media_rettigheder skrev ingen fakta';
  END IF;

  -- Preview: blokeret af alle seks kategorier, med tællinger + stier
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR (v_prev->>'antal_tilknytninger')::int <> 1
     OR (v_prev->>'antal_mentions')::int <> 1
     OR (v_prev->>'antal_fakta')::int <> 2          -- licens + kildehenvisning (tredje felt NULL)
     OR (v_prev->>'antal_stories')::int <> 1
     OR (v_prev->>'antal_narrativer')::int <> 1
     OR (v_prev->>'antal_noter')::int <> 1
     OR jsonb_array_length(v_prev->'stier') <> 2
     OR jsonb_array_length(v_prev->'blokeringer') <> 6 THEN
    RAISE EXCEPTION 'FEJL: preview-blokeringer/tællinger forkerte: %', v_prev;
  END IF;

  -- Udrens blokeret af relation
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har tilknytninger%' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_relation(v_rel);

  -- Udrens blokeret af mention
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med mention';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet er nævnt i narrativer%' THEN RAISE; END IF;
  END;
  DELETE FROM text_mention WHERE maal_type='media' AND maal_id=v_id;

  -- Udrens blokeret af rettigheds-fakta (H1) — preview skal også være rød med rette tekst
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_prev->'blokeringer') b
                    WHERE b LIKE '%rettighedsdokumentation%') THEN
    RAISE EXCEPTION 'FEJL: preview grøn/uklar trods rettigheds-fakta: %', v_prev;
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med rettigheds-fakta (H1)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har rettighedsdokumentation%' THEN RAISE; END IF;
  END;
  -- Ryd fakta-blokeringen: HELE evidenskæden i FK-orden (red_slet_person-mønsteret, schema.sql:1128-1165)
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id));
  DELETE FROM conclusion WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id);
  DELETE FROM assertion WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id);
  DELETE FROM note WHERE target_type='fact'
    AND target_id IN (SELECT id FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id);
  DELETE FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id;

  -- Udrens blokeret af story (H3)
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med story (H3)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet er subjekt for en story%' THEN RAISE; END IF;
  END;
  DELETE FROM story WHERE id=v_story;

  -- Udrens blokeret af narrativ (H3) — evt. haendelser ville cascade FRA narrativet, ingen egen oprydning
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med narrativ (H3)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har et tilknyttet narrativ%' THEN RAISE; END IF;
  END;
  DELETE FROM narrative WHERE id=v_narr;

  -- Udrens blokeret af note (defensiv guard)
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med note (defensiv guard)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har noter%' THEN RAISE; END IF;
  END;
  DELETE FROM note WHERE id=v_note;

  -- Kun-fra-fjernet
  UPDATE media SET upload_status='klar' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede et klart medie';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun udrense et fjernet medie%' THEN RAISE; END IF;
  END;
  UPDATE media SET upload_status='fjernet' WHERE id=v_id;

  -- Preview↔udrens-paritet på stier + selve sletningen
  v_prev := red_udrens_media_preview(v_id);
  IF NOT (v_prev->>'kan_udrenses')::boolean THEN RAISE EXCEPTION 'FEJL: preview burde være grøn nu: %', v_prev; END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_udrens_media(v_id);
  IF jsonb_array_length(v_res->'stier') <> jsonb_array_length(v_prev->'stier') THEN
    RAISE EXCEPTION 'FEJL: preview og udrens er uenige om stierne (% vs %)', v_prev->'stier', v_res->'stier';
  END IF;
  IF EXISTS (SELECT 1 FROM media WHERE id=v_id) OR EXISTS (SELECT 1 FROM media_variant WHERE media_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: række/varianter overlevede udrensningen';
  END IF;
  -- Intet forældreløst tilbage: fact-kæden, story, narrativ og note blev ryddet FØR udrens
  -- (blokerings-modellen), og efter udrens må INTET pege på det slettede medie (H1-garantien)
  IF EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=v_id)
     OR EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: forældreløst anker/evidens peger stadig på det udrensede medie';
  END IF;
  -- DELETE-event med foer-snapshot logget
  SELECT max(cs.id) INTO v_cs FROM change_set cs WHERE cs.operation='red_udrens_media';
  IF NOT EXISTS (SELECT 1 FROM change_event WHERE change_set_id=v_cs AND tabel='media'
                 AND op='DELETE' AND foer->>'id' = v_id::text AND efter IS NULL) THEN
    RAISE EXCEPTION 'FEJL: udrens loggede ikke DELETE med foer-snapshot';
  END IF;
  -- Fortryd genskaber rækken fra snapshottet — men uden varianter (dokumenteret hazard, spec §4.2)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs, false);
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND upload_status='fjernet') THEN
    RAISE EXCEPTION 'FEJL: fortryd genskabte ikke media-rækken';
  END IF;
  IF EXISTS (SELECT 1 FROM media_variant WHERE media_id=v_id) THEN
    RAISE EXCEPTION 'FEJL: variant-rækker uventet genskabt (cache er ikke versioneret)';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 4 udrens (alle seks anker-guards, paritet, DELETE-log, fortryd uden varianter, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;
```

  - `db-verify-media.sql` (RLS-kontrakten, spec §4.3 — ingen RPC'er, kun seed + rolle-skift; append efter filens sidste task):

```sql
-- ===== Task fase 4: anon ser 0 gennem hele udrens-cyklussen =====
-- Forvent: NOTICE "OK: media fase 4 anon-usynlighed ...". Seeder negative id'er, rydder selv op.
-- Udrens-tilstandene ('fjernet' → slettet række) må aldrig ændre anon-synligheden fra 0.
DO $$
DECLARE vis int;
BEGIN
  DELETE FROM media WHERE id = -941;
  INSERT INTO media(id,slags,titel,storage_path,upload_status,maa_publiceres)
    VALUES (-941,'foto','fase4-anon-test','__verify__/f4-anon.jpg','fjernet',true);

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis FROM media WHERE id = -941;
  RESET ROLE;
  IF vis <> 0 THEN RAISE EXCEPTION 'FEJL: anon ser et fjernet medie (%)', vis; END IF;

  DELETE FROM media WHERE id = -941;  -- simuleret udrens (rækken borte)
  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis FROM media WHERE id = -941;
  RESET ROLE;
  IF vis <> 0 THEN RAISE EXCEPTION 'FEJL: anon ser en slettet række (%)', vis; END IF;

  RAISE NOTICE 'OK: media fase 4 anon-usynlighed gennem udrens-cyklussen';
END $$;
```

- [ ] **Step 2: Kør verify og bekræft FEJL** (`function red_udrens_media_preview(...) does not exist`).

- [ ] **Step 3: Implementér de to funktioner i `schema.sql`** (efter `red_erstat_media_fil`):

```sql
-- Fase 4 (M11): read-only forhåndsvisning af udrensning — bekræftelsesdialogens datagrundlag.
-- Kopierer red_slet_person_preview-kontrakten: SECURITY DEFINER, rolle-gated, intet change_set.
-- 'blokeringer' fortæller UI'et præcis hvorfor knappen er grå; 'stier' er samtidig klientens
-- arbejdsliste til Storage-sletningen — preview og udførelse deler ét sandhedsgrundlag.
-- Review 34 (H1/H3): tæller ALLE polymorfe ankre, ikke kun deklarative FK'er — relation
-- (begge retninger), text_mention, fact (rettighedsdokumentation via red_set_media_rettigheder;
-- evidenskæden assertion/citation/conclusion hænger på fact'et og blokeres med det), story og
-- narrative (deres RPC'er validerer ikke det polymorfe mål; haendelse cascader FRA narrative
-- og tælles bevidst ikke selvstændigt) samt note (defensivt — ingen live skriver i dag).
-- Review 34 (L1): feltet hedder 'tilknytninger', IKKE 'afbildet' — det rummer enhver rolle.
CREATE OR REPLACE FUNCTION red_udrens_media_preview(p_media_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_tilknytninger jsonb; v_mentions jsonb; v_fakta jsonb; v_stories jsonb;
        v_narrativer jsonb; v_noter jsonb; v_stier jsonb; v_blok text[] := '{}';
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT upload_status INTO v_status FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  -- ALLE relationer (enhver rolle, begge retninger) blokerer — ikke kun 'afbildet'.
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_tilknytninger FROM (
    SELECT id AS relation_id,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN objekt_type ELSE subjekt_type END AS modpart_type,
           CASE WHEN subjekt_type='media' AND subjekt_id=p_media_id THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
       OR (objekt_type='media'  AND objekt_id=p_media_id)
    ORDER BY id) r;
  SELECT coalesce(jsonb_agg(m), '[]'::jsonb) INTO v_mentions FROM (
    SELECT kilde_type, kilde_id FROM text_mention
    WHERE maal_type='media' AND maal_id=p_media_id
    ORDER BY kilde_type, kilde_id) m;
  SELECT coalesce(jsonb_agg(f.id ORDER BY f.id), '[]'::jsonb) INTO v_fakta
    FROM fact f WHERE f.subjekt_type='media' AND f.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(s.id ORDER BY s.id), '[]'::jsonb) INTO v_stories
    FROM story s WHERE s.subjekt_type='media' AND s.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(n.id ORDER BY n.id), '[]'::jsonb) INTO v_narrativer
    FROM narrative n WHERE n.subjekt_type='media' AND n.subjekt_id=p_media_id;
  SELECT coalesce(jsonb_agg(t.id ORDER BY t.id), '[]'::jsonb) INTO v_noter
    FROM note t WHERE t.target_type='media' AND t.target_id=p_media_id;
  SELECT coalesce(jsonb_agg(s), '[]'::jsonb) INTO v_stier FROM (
    SELECT bucket, storage_path AS sti, 'media' AS kilde FROM media
      WHERE id=p_media_id AND storage_path IS NOT NULL
    UNION ALL
    SELECT m.bucket, v.storage_path, v.tier FROM media_variant v JOIN media m ON m.id=v.media_id
      WHERE v.media_id=p_media_id) s;
  IF v_status <> 'fjernet' THEN
    v_blok := v_blok || 'Kan kun udrense et fjernet medie — fjern det først (papirkurven)';
  END IF;
  IF jsonb_array_length(v_tilknytninger) > 0 THEN
    v_blok := v_blok || format('%s tilknytning(er) skal fjernes først', jsonb_array_length(v_tilknytninger));
  END IF;
  IF jsonb_array_length(v_mentions) > 0 THEN
    v_blok := v_blok || format('%s narrativ-omtale(r) skal redigeres ud først', jsonb_array_length(v_mentions));
  END IF;
  IF jsonb_array_length(v_fakta) > 0 THEN
    v_blok := v_blok || format('Mediet har rettighedsdokumentation (%s faktum/fakta) — fjern den først', jsonb_array_length(v_fakta));
  END IF;
  IF jsonb_array_length(v_stories) > 0 THEN
    v_blok := v_blok || format('Mediet er subjekt for %s story/stories — flyt eller slet dem først', jsonb_array_length(v_stories));
  END IF;
  IF jsonb_array_length(v_narrativer) > 0 THEN
    v_blok := v_blok || format('Mediet har %s tilknyttet narrativ(er) — slet dem først', jsonb_array_length(v_narrativer));
  END IF;
  IF jsonb_array_length(v_noter) > 0 THEN
    v_blok := v_blok || format('%s note(r) peger på mediet — fjern dem først', jsonb_array_length(v_noter));
  END IF;
  RETURN jsonb_build_object(
    'upload_status', v_status,
    'kan_udrenses', coalesce(array_length(v_blok,1),0) = 0,
    'blokeringer', to_jsonb(v_blok),
    'antal_tilknytninger', jsonb_array_length(v_tilknytninger),
    'antal_mentions', jsonb_array_length(v_mentions),
    'antal_fakta', jsonb_array_length(v_fakta),
    'antal_stories', jsonb_array_length(v_stories),
    'antal_narrativer', jsonb_array_length(v_narrativer),
    'antal_noter', jsonb_array_length(v_noter),
    'tilknytninger', v_tilknytninger,
    'mentions', v_mentions,
    'fakta', v_fakta,
    'stories', v_stories,
    'narrativer', v_narrativer,
    'noter', v_noter,
    'stier', v_stier);
END $$;

-- Fase 4 (M11): den rigtige sletning — række + (returnerede) stier. To-trins: KUN fra 'fjernet'
-- (blødt fjern først, koncept §4.3) og BLOKERET ved ethvert polymorft anker (review 34 H1/H3):
-- relation (begge retninger — ryddes eksplicit først via red_slet_relation /
-- red_slet_medierelation_uden_evidens, som håndterer polymorf evidens; flad DELETE her ville ikke),
-- text_mention (redigeres ud af prosaen manuelt), fact m. subjekt_type='media'
-- (rettighedsdokumentation fra red_set_media_rettigheder — evidenskæden assertion/citation/
-- conclusion hænger på fact'et og ville forældreløses af en flad media-DELETE), story og
-- narrative m. subjekt_type='media' (red_opret_story/red_upsert_narrativ validerer ikke målet;
-- haendelse cascader FRA narrative via ON DELETE CASCADE og kræver INGEN selvstændig kode) samt
-- note m. target_type='media' (DEFENSIVT — ingen live skriver i dag; red_slet_person-forsigtigheden).
-- Udrens kan derfor aldrig forældreløse evidens eller efterlade friske døde links
-- (red_doede_links-media-grenen er bagstopper for historiske tokens).
-- Review 34 (H2): guard-tjek + slet er kollapset til ÉT atomisk DELETE-statement — de venlige
-- RAISE-guards ovenfor giver præcise domæne-fejl, men den AUTORITATIVE gate er DELETE'ens egne
-- NOT EXISTS-betingelser, som ikke kan skilles fra sletningen af en samtidig skriver (fx
-- red_relation, der INSERT'er blindt). Postgres' standardmønster for check-then-act i en
-- polymorf, FK-fri model uden separate lås-primitiver. Rammer DELETE 0 rækker efter at
-- guardsne passerede, ændrede tilstanden sig undervejs → fail-loud, prøv igen.
-- Storage-sletning er KLIENT-SIDET og sker EFTER dette kald (Postgres-txn og Storage deler ikke
-- transaktion): DB-først garanterer at der aldrig findes en synlig række uden bytes; fejler
-- klientens storage.remove, er objekterne forældreløse = fail-closed usynlige + janitor-kategori-b.
-- media_variant CASCADE'r (uversioneret cache, ikke logget); media-rækken logges som DELETE med
-- foer-snapshot → red_fortryd_change_set kan genskabe RÆKKEN, men hverken varianter eller bytes
-- (dokumenteret, accepteret hazard — UI'et siger "kan ikke reelt fortrydes"; janitor-kategori c opdager).
CREATE OR REPLACE FUNCTION red_udrens_media(p_media_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status text; v_stier jsonb;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT upload_status INTO v_status FROM media WHERE id = p_media_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Media % findes ikke', p_media_id; END IF;
  IF v_status <> 'fjernet' THEN RAISE EXCEPTION 'Kan kun udrense et fjernet medie'; END IF;
  -- Venlige, kategori-præcise domæne-fejl (det atomiske DELETE nedenfor er den autoritative gate):
  IF EXISTS (SELECT 1 FROM relation
             WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
                OR (objekt_type='media' AND objekt_id=p_media_id)) THEN
    RAISE EXCEPTION 'Mediet har tilknytninger og kan ikke udrenses — fjern dem først';
  END IF;
  IF EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet er nævnt i narrativer og kan ikke udrenses — redigér omtalerne ud først';
  END IF;
  IF EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har rettighedsdokumentation (fakta) og kan ikke udrenses — fjern den først';
  END IF;
  IF EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet er subjekt for en story og kan ikke udrenses — flyt eller slet storyen først';
  END IF;
  IF EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har et tilknyttet narrativ og kan ikke udrenses — slet narrativet først';
  END IF;
  IF EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=p_media_id) THEN
    RAISE EXCEPTION 'Mediet har noter og kan ikke udrenses — fjern dem først';
  END IF;
  SELECT coalesce(jsonb_agg(s), '[]'::jsonb) INTO v_stier FROM (
    SELECT bucket, storage_path AS sti FROM media WHERE id=p_media_id AND storage_path IS NOT NULL
    UNION ALL
    SELECT m.bucket, v.storage_path FROM media_variant v JOIN media m ON m.id=v.media_id
      WHERE v.media_id=p_media_id) s;
  PERFORM begin_change_set('red_udrens_media', format('Udrensede media %s permanent', p_media_id), 'media', p_media_id);
  -- ÉT atomisk statement (H2): check-then-act kan ikke splittes af en samtidig transaktion.
  DELETE FROM media
   WHERE id = p_media_id
     AND upload_status = 'fjernet'
     AND NOT EXISTS (SELECT 1 FROM relation
                     WHERE (subjekt_type='media' AND subjekt_id=p_media_id)
                        OR (objekt_type='media' AND objekt_id=p_media_id))
     AND NOT EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=p_media_id)
     AND NOT EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=p_media_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mediet kunne ikke udrenses — tilstanden ændrede sig undervejs, prøv igen';
  END IF;
  RETURN jsonb_build_object('stier', v_stier);
END $$;
```

- [ ] **Step 4: Frisk install + fuld verify grøn** — begge nye blokke `OK:`, `db-verify-media.sql` uden regression (fortsat de eksisterende NOTICE'er + den nye).

- [ ] **Step 5: Commit**

```bash
git add schema.sql db-verify.sql db-verify-media.sql
git commit -m "feat(media): tilføj red_udrens_media + preview — gatet permanent sletning

Fase 4 skive 2 (spec §4 + review 34 H1/H2/H3/L1): to-trins (kun fra
fjernet), blokeret på ALLE polymorfe ankre (relation, mention, fakta m.
evidenskæde, story, narrativ, defensiv note); guard+slet i ét atomisk
statement; DB-først med returnerede stier; preview deler sandhedsgrundlag
og hedder 'tilknytninger', ikke 'afbildet'."
```

## Task 3: DB — `relation.kvalifikator` + `red_saet_portraet` i `schema.sql` + asserts (spec §5, M10)

**Files:**
- Modify: `schema.sql` (kolonne i `CREATE TABLE relation` `:355-368`; ny funktion efter `red_udrens_media`)
- Modify: `db-verify.sql` (ny impersonerings-DO-blok)

**Interfaces:**
- Consumes: `relation_afbildet_uidx` (`schema.sql:369-371` — garanterer max én afbildet-række pr. (subjekt,objekt)-par); `relation` i `version_pk_registry` uden skip-cols (`:2169` — jsonb-snapshottet bærer ny kolonne automatisk, INGEN registry-ændring).
- Produces (Task 4 kopierer verbatim; Task 5 kalder; Task 7/8 læser kolonnen):
```sql
-- CREATE TABLE relation får (frisk install):
kvalifikator jsonb,   -- fase 4: rolle-kvalifikation, fx {"primaer":true} (portræt); deles med fremtidig region-tagging (bbox)

red_saet_portraet(p_person_id bigint, p_media_id bigint DEFAULT NULL) RETURNS void
-- p_media_id = NULL: ryd eksplicit valg → heuristikken gælder igen.
-- Domæne-fejl: 'Kun redaktion', 'Mediet er ikke tilknyttet personen — tilknyt først'
```

- [ ] **Step 1: Skriv den fejlende assert-blok i `db-verify.sql`:**

```sql
-- ===== Mediehåndtering fase 4: relation.kvalifikator + red_saet_portraet =====
DO $$
DECLARE v_m1 bigint; v_m2 bigint; v_r1 bigint; v_r2 bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Kolonnen findes og er jsonb
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='relation'
                   AND column_name='kvalifikator' AND data_type='jsonb') THEN
    RAISE EXCEPTION 'FEJL: relation.kvalifikator mangler eller har forkert type';
  END IF;

  v_m1 := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,upload_status) VALUES (v_m1,'foto','klar');
  v_m2 := v_m1 + 1;
  INSERT INTO media(id,slags,upload_status) VALUES (v_m2,'foto','klar');
  v_r1 := red_relation('person',-999943,'media',v_m1,'afbildet');
  v_r2 := red_relation('person',-999943,'media',v_m2,'afbildet');

  -- Sæt portræt på m1
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, v_m1);
  IF (SELECT kvalifikator->>'primaer' FROM relation WHERE id=v_r1) <> 'true' THEN
    RAISE EXCEPTION 'FEJL: primaer-flag blev ikke sat';
  END IF;

  -- Skift til m2 → søskende-nulstilling af m1
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, v_m2);
  IF (SELECT kvalifikator FROM relation WHERE id=v_r1) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: søskende-nulstilling efterlod kvalifikator på m1 (%)',
      (SELECT kvalifikator FROM relation WHERE id=v_r1);
  END IF;
  IF (SELECT kvalifikator->>'primaer' FROM relation WHERE id=v_r2) <> 'true' THEN
    RAISE EXCEPTION 'FEJL: flaget flyttede ikke til m2';
  END IF;

  -- Ryd-grenen (p_media_id = NULL)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, NULL);
  IF EXISTS (SELECT 1 FROM relation
             WHERE subjekt_type='person' AND subjekt_id=-999943 AND kvalifikator ? 'primaer') THEN
    RAISE EXCEPTION 'FEJL: ryd-grenen fjernede ikke flaget';
  END IF;

  -- Manglende relation → domæne-fejl, INGEN implicit oprettelse
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_saet_portraet(-999943, -424242);
    RAISE EXCEPTION 'FEJL: portræt accepteret uden relation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet er ikke tilknyttet personen%' THEN RAISE; END IF;
  END;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 4 portræt (kolonne, søskende-nulstilling, ryd, guard, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;
```

- [ ] **Step 2: Kør verify og bekræft FEJL** (kolonnen mangler → første assert rejser).

- [ ] **Step 3: Implementér.** I `CREATE TABLE relation` (`schema.sql:355-368`), efter `konfidens   TEXT`:

```sql
  konfidens   TEXT,
  kvalifikator jsonb                     -- fase 4: rolle-kvalifikation, fx {"primaer":true} (portræt-valg, M10); generisk pr. plan Slice 3 — deles med fremtidig region-tagging (bbox) uden ny DDL
```

Og funktionen (efter `red_udrens_media`):

```sql
-- Fase 4 (M10): portræt som redaktionelt VALG — {"primaer":true} på personens afbildet-relation.
-- pickPortrait i læse-lagene prioriterer flaget og degraderer til slags-heuristikken (koncept §4.7).
-- relation_afbildet_uidx garanterer max én relation pr. (person, media)-par, så "sæt flaget på
-- parret" er entydigt. Retningen person→media er GDPR-invariantens (red_relation-guarden) — kun
-- den ene retning scannes. Ingen upload_status-guard: et flag på et senere-fjernet medie er
-- harmløst (læse-lagene ser kun synlige medier) og overlever genopret. p_media_id=NULL rydder
-- valget. relation står i version_pk_registry uden skip-cols → begge UPDATEs logges og fortrydes.
-- Samtidighed (review 34, M1 dismissed): to samtidige kald kan IKKE efterlade to primaer-flag
-- — begin_change_set's eget max(id)+1 på change_set kolliderer FØRST (unique_violation), og
-- taberen ruller hele sit kald tilbage før portræt-logikken nås. Verificeret umuligt, ikke
-- blot usandsynligt; ingen ekstra lås nødvendig.
CREATE OR REPLACE FUNCTION red_saet_portraet(p_person_id bigint, p_media_id bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rows int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  PERFORM begin_change_set('red_saet_portraet',
    CASE WHEN p_media_id IS NULL THEN format('Ryddede portræt-valg for person %s', p_person_id)
         ELSE format('Satte media %s som portræt for person %s', p_media_id, p_person_id) END,
    'person', p_person_id);
  -- Nulstil søskende først (én UPDATE): fjern nøglen; tom jsonb normaliseres til NULL.
  UPDATE relation SET kvalifikator = nullif(kvalifikator - 'primaer', '{}'::jsonb)
   WHERE subjekt_type='person' AND subjekt_id=p_person_id
     AND objekt_type='media' AND rolle='afbildet'
     AND kvalifikator ? 'primaer';
  IF p_media_id IS NOT NULL THEN
    UPDATE relation SET kvalifikator = coalesce(kvalifikator,'{}'::jsonb) || '{"primaer":true}'::jsonb
     WHERE subjekt_type='person' AND subjekt_id=p_person_id
       AND objekt_type='media' AND objekt_id=p_media_id AND rolle='afbildet';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
      RAISE EXCEPTION 'Mediet er ikke tilknyttet personen — tilknyt først';
    END IF;
  END IF;
END $$;
```

- [ ] **Step 4: Frisk install + fuld verify grøn** (nye + gamle blokke).

- [ ] **Step 5: Commit**

```bash
git add schema.sql db-verify.sql
git commit -m "feat(media): tilføj relation.kvalifikator + red_saet_portraet

Fase 4 skive 3 (spec §5): portræt er et redaktionelt valg (primaer-flag);
relation_afbildet_uidx gør parret entydigt; versionering gratis via registry."
```

## Task 4: DB — migrationssti (`mediehaandtering_fase4_identitet` i `db-migrations.sql`)

**Files:**
- Modify: `db-migrations.sql` (ny navngiven blok APPENDES efter filens sidste funktion, `red_publicer_personer` `:3109-3132`)

**Interfaces:**
- Consumes: de fire funktioner + kolonnen fra Task 1–3 (kopieres VERBATIM — samme signatur → ingen overload-/grant-problem, jf. fase 1's DROP-læring og fase 3-blokkens `red_relation`-kopi `:2752-2785`).
- Produces: en idempotent migrationsblok der bringer en fase 3-base op på fase 4-fladen.

- [ ] **Step 1: Skriv migrationsblokken** (filens etablerede mønster — kommentar-header + rå idempotent SQL, jf. `:2727-2732`):

```sql
-- =====================================================================
-- 2026-07-22: mediehaandtering_fase4_identitet
-- Erstat fil (M4), udrensning + preview (M11), portræt-valg (M10).
-- Additiv jsonb-kolonne relation.kvalifikator (fase 4 bruger {"primaer":true};
-- fremtidig region-tagging deler kolonnen uden ny DDL). relation står i
-- version_pk_registry uden skip-cols → jsonb-rækkesnapshottet bærer den nye
-- kolonne automatisk; INGEN registry-/trigger-/RLS-ændring. Funktionerne er
-- verbatim-kopier af schema.sql (samme signaturer). Nye red_*-funktioner er
-- kaldbare af authenticated via Supabases default-grants (frisk install:
-- db-rls.sql's navnebaserede grant-loop); rolle-gaten sidder i kroppen.
-- Udrens blokerer på ALLE polymorfe ankre (relation/mention/fakta m.
-- evidenskæde/story/narrativ/defensiv note) og sletter i ét atomisk
-- statement (review 34 H1/H2/H3).
-- =====================================================================
ALTER TABLE relation ADD COLUMN IF NOT EXISTS kvalifikator jsonb;

-- (1) red_erstat_media_fil — VERBATIM kopi af Task 1's funktion fra schema.sql
CREATE OR REPLACE FUNCTION red_erstat_media_fil( … ) …;

-- (2)+(3) red_udrens_media_preview + red_udrens_media — VERBATIM kopi af Task 2's funktioner
CREATE OR REPLACE FUNCTION red_udrens_media_preview( … ) …;
CREATE OR REPLACE FUNCTION red_udrens_media( … ) …;

-- (4) red_saet_portraet — VERBATIM kopi af Task 3's funktion
CREATE OR REPLACE FUNCTION red_saet_portraet( … ) …;
```

  (De fire `…`-kroppe er IKKE pladsholdere for implementøren at digte — de er en
  kopi-instruktion: indsæt funktionerne tegn-for-tegn som de står i `schema.sql` efter
  Task 1–3, så de to filer ikke driver fra hinanden. `ADD COLUMN IF NOT EXISTS` +
  `CREATE OR REPLACE` gør hele blokken idempotent.)

- [ ] **Step 2: Migrationssti-test lokalt (×2).** Frisk install af FØR-tilstanden
  (`git stash` / checkout af `schema.sql` fra HEAD før Task 1 til en midlertidig fil):
  `psql -f schema-foer-fase4.sql` → seed en afbildet-relation → kør den NYE
  `db-migrations.sql` **to gange** (idempotens: andet gennemløb må ikke fejle eller ændre
  noget) → kør `db-rls.sql` → kør HELE `db-verify.sql` + `db-verify-media.sql`.
  Forvent: alle blokke grønne, inkl. Task 1–3's fase 4-blokke — herunder Task 2's
  anker-blokerings-asserts (fakta/story/narrativ/note + atomisk-slet-kontrakten), som er
  migrationsstiens bevis for at review 34's H1/H2/H3-rettelser også står i den kopierede
  blok, ikke kun i `schema.sql`; eksisterende relation har `kvalifikator IS NULL`
  (additivt, ingen backfill).

- [ ] **Step 3: Flade-sammenligning.** Bekræft at frisk `schema.sql`-install og
  migrationsstien giver samme fase 4-flade:

```bash
psql -d <frisk> -c "\df red_erstat_media_fil" -c "\df red_udrens_media*" -c "\df red_saet_portraet" -c "\d relation" > /tmp/frisk.txt
psql -d <migreret> -c "\df red_erstat_media_fil" -c "\df red_udrens_media*" -c "\df red_saet_portraet" -c "\d relation" > /tmp/migreret.txt
diff /tmp/frisk.txt /tmp/migreret.txt   # forvent: tom
```

- [ ] **Step 4: Commit**

```bash
git add db-migrations.sql
git commit -m "feat(media): migrationsblok mediehaandtering_fase4_identitet

Idempotent (ADD COLUMN IF NOT EXISTS + CREATE OR REPLACE), verificeret ×2
mod lokal fase 3-base; flade identisk med frisk install."
```

## Task 5: Web skrive-lag — `erstatMediaFil`/`udrensMedia`/`saetPortraet` (spec §6)

**Files:**
- Modify: `web/src/data/redaktionWrite.ts`
- Test: `web/src/data/__tests__/redaktionWrite.test.ts` (udvid eksisterende)

**Interfaces:**
- Consumes: RPC-kontrakterne fra Task 1–3; `performUpload(file, storagePath)` (`web/src/data/mediaUpload.ts:93-99`, duplicate-tolerant); `parsePostgresBigintId` (`redaktionWrite.ts:71-76`).
- Produces (Task 9 kalder):
```ts
// Change-unionen udvides med tre arter:
//   'erstatMediaFil'  — payload: { file: Blob; storagePath; mimeType; byteSize; bredde; hoejde;
//                        sha256; originalFilnavn?; varianter: Array<{tier; file: Blob; storagePath;
//                        mimeType; byteSize; bredde; hoejde}> } + mediaId
//   'udrensMedia'     — mediaId; submitChange-result.result = { stier: {bucket; sti}[] }
//   'saetPortraet'    — personId (person), mediaId (null/udeladt = ryd)
// Hårde gates (kan IKKE degradere til red_suggest): erstatMediaFil, udrensMedia.
// saetPortraet degraderer som metadata-changes (buildSuggestCall-fallback).
```

- [ ] **Step 1: Skriv fejlende vitest-cases** i `redaktionWrite.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { buildRpcCall, buildSuggestCall, oversaetFejl, submitChange, type Change } from '../redaktionWrite';

vi.mock('../../supabase', () => ({ supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } } }));
vi.mock('../mediaUpload', () => ({ performUpload: vi.fn() }));

describe('fase 4: erstatMediaFil', () => {
  const base: Change = { art: 'erstatMediaFil', subjektType: 'media', subjektId: '7', mediaId: '7',
    payload: { file: new Blob(['x']), storagePath: 'redaktor/ab/s-large.jpg', mimeType: 'image/jpeg',
      byteSize: 3, bredde: 2, hoejde: 1, sha256: 'abc123', originalFilnavn: 'ny.jpg',
      varianter: [{ tier: 'thumb', file: new Blob(['t']), storagePath: 'redaktor/ab/s-thumb.jpg',
        mimeType: 'image/jpeg', byteSize: 1, bredde: 1, hoejde: 1 }] } };
  it('bygger red_erstat_media_fil med metadata-varianter (ALDRIG file-blobs i args)', () => {
    const call = buildRpcCall(base)!;
    expect(call.fn).toBe('red_erstat_media_fil');
    expect(call.args.p_media_id).toBe(7);
    expect(call.args.p_sha256).toBe('abc123');
    expect(call.args.p_varianter).toEqual([{ tier: 'thumb', storage_path: 'redaktor/ab/s-thumb.jpg',
      mime: 'image/jpeg', byte_size: 1, bredde: 1, hoejde: 1 }]);
    expect(JSON.stringify(call.args)).not.toContain('"file"');
  });
  it('afviser manglende mediaId/sha256/sti', () => {
    expect(buildRpcCall({ ...base, mediaId: undefined })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, sha256: undefined } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, storagePath: undefined } })).toBeNull();
  });
  it('kan IKKE degradere til red_suggest (hård gate som uploadMedia)', async () => {
    await expect(submitChange(base, { dryRun: false, role: 'medlem' }))
      .rejects.toThrow(/redaktør-rettigheder/);
  });
  it('dry-run uploader INTET og udfører intet RPC (dryRun respekteres)', async () => {
    const { performUpload } = await import('../mediaUpload');
    const { supabase } = await import('../../supabase');
    const res = await submitChange(base, { dryRun: true, role: 'redaktion' });
    expect(res.dryRun).toBe(true);
    expect(performUpload).not.toHaveBeenCalled();
    expect(supabase.rpc).not.toHaveBeenCalled();
  });
});

describe('fase 4: udrensMedia', () => {
  const change: Change = { art: 'udrensMedia', subjektType: 'media', subjektId: '9', mediaId: '9' };
  it('bygger red_udrens_media', () => {
    expect(buildRpcCall(change)).toEqual({ fn: 'red_udrens_media', args: { p_media_id: 9 } });
    expect(buildRpcCall({ ...change, mediaId: undefined })).toBeNull();
  });
  it('kan IKKE degradere til red_suggest', async () => {
    await expect(submitChange(change, { dryRun: false, role: 'medlem' }))
      .rejects.toThrow(/redaktør-rettigheder/);
  });
});

describe('fase 4: saetPortraet', () => {
  it('bygger red_saet_portraet med og uden media (NULL = ryd)', () => {
    expect(buildRpcCall({ art: 'saetPortraet', subjektType: 'person', subjektId: '5', personId: '5', mediaId: '7' }))
      .toEqual({ fn: 'red_saet_portraet', args: { p_person_id: 5, p_media_id: 7 } });
    expect(buildRpcCall({ art: 'saetPortraet', subjektType: 'person', subjektId: '5', personId: '5' }))
      .toEqual({ fn: 'red_saet_portraet', args: { p_person_id: 5, p_media_id: null } });
    expect(buildRpcCall({ art: 'saetPortraet', subjektType: 'person', subjektId: '', personId: undefined })).toBeNull();
  });
  it('degraderer til red_suggest for ikke-redaktion (metadata-change)', () => {
    const call = buildSuggestCall({ art: 'saetPortraet', subjektType: 'person', subjektId: '5', personId: '5', mediaId: '7' });
    expect(call.fn).toBe('red_suggest');
    expect(call.args.p_payload).toEqual({ personId: '5', mediaId: '7' });
  });
});

describe('fase 4: oversaetFejl', () => {
  it.each([
    ['Kan kun erstatte filen på et klart medie', /kun erstattes på et klart medie/i],
    ['Filen er identisk med den nuværende', /identisk/i],
    ['Kan kun udrense et fjernet medie', /papirkurven/i],
    ['Mediet har tilknytninger og kan ikke udrenses — fjern dem først', /tilknytninger/i],
    ['Mediet er nævnt i narrativer og kan ikke udrenses — redigér omtalerne ud først', /narrativer/i],
    ['Mediet er ikke tilknyttet personen — tilknyt først', /tilknyt/i],
  ])('oversætter %s', (raa, forvent) => {
    expect(oversaetFejl(raa)).toMatch(forvent);
  });
});
```

- [ ] **Step 2: Kør og verificér FAIL** — `cd web && npm run test -- redaktionWrite`.
  Forvent: buildRpcCall returnerer `null` for de nye arter (TS-fejl på union først — det
  tæller som fail).

- [ ] **Step 3: Implementér i `redaktionWrite.ts`:**
  1. Union (`:35-38`-blokken) udvides:
```ts
     | 'erstatMediaFil' // fase 4 (M4): erstat bytes, behold identitet — bytes FØR RPC, hård gate
     | 'udrensMedia'    // fase 4 (M11): permanent sletning (kun fra 'fjernet'); result = {stier}
     | 'saetPortraet'   // fase 4 (M10): {"primaer":true} på afbildet-relationen; mediaId udeladt = ryd
```
  2. `buildRpcCall`-grene (efter `fjernMedia`-grenen `:441-445`):
```ts
  // Fase 4 (M4): varianter sendes som METADATA (p_varianter); file-blobs må ALDRIG med i args
  // (File JSON-serialiserer til {} — samme fælde som uploadMedia-forslags-gaten beskriver).
  if (c.art === 'erstatMediaFil') {
    const mediaId = parsePostgresBigintId(c.mediaId);
    const p = c.payload || {};
    if (mediaId == null || !p.storagePath || !p.mimeType || !p.sha256) return null;
    const varianter = (p.varianter ?? []) as Array<{
      tier: string; storagePath: string; mimeType: string; byteSize: number; bredde: number; hoejde: number;
    }>;
    return { fn: 'red_erstat_media_fil', args: {
      p_media_id: mediaId,
      p_storage_path: p.storagePath, p_mime: p.mimeType,
      p_byte_size: p.byteSize ?? null, p_bredde: p.bredde ?? null, p_hoejde: p.hoejde ?? null,
      p_sha256: p.sha256,
      p_original_filnavn: p.originalFilnavn ?? null,
      p_varianter: varianter.map((v) => ({
        tier: v.tier, storage_path: v.storagePath, mime: v.mimeType,
        byte_size: v.byteSize, bredde: v.bredde, hoejde: v.hoejde,
      })),
    } };
  }
  if (c.art === 'udrensMedia') {
    const mediaId = parsePostgresBigintId(c.mediaId);
    if (mediaId == null) return null;
    return { fn: 'red_udrens_media', args: { p_media_id: mediaId } };
  }
  if (c.art === 'saetPortraet') {
    const personId = parsePostgresBigintId(c.personId ?? c.subjektId);
    if (personId == null) return null;
    const mediaId = c.mediaId != null ? parsePostgresBigintId(c.mediaId) : null;
    if (c.mediaId != null && mediaId == null) return null;
    return { fn: 'red_saet_portraet', args: { p_person_id: personId, p_media_id: mediaId } };
  }
```
  3. `buildSuggestCall`-fallbackPayload (`:457-469`) får en `saetPortraet`-gren:
```ts
    : c.art === 'saetPortraet'
      ? { personId: c.personId ?? c.subjektId, mediaId: c.mediaId ?? null }
```
  4. `submitChange`: udvid den hårde gate (`:512-514`) og erstat-upload-flowet:
```ts
  // erstatMediaFil bærer fil-bytes (samme fælde som uploadMedia); udrensMedia er destruktiv og
  // afhænger af de RETURNEREDE stier — et "udrens-forslag" ville lyve om begge dele (spec §6).
  if ((c.art === 'uploadMedia' || c.art === 'erstatMediaFil') && !direkte) {
    throw new Error('Medieupload kræver redaktør-rettigheder — kan ikke sendes som forslag.');
  }
  if (c.art === 'udrensMedia' && !direkte) {
    throw new Error('Udrensning kræver redaktør-rettigheder — kan ikke sendes som forslag.');
  }
  if (opts.dryRun) return { dryRun: true as const, call, direkte };
  if (c.art === 'erstatMediaFil') {
    // Bytes FØR RPC (idempotent på sha-stier, fase 3). Modsat upload er der ingen bekræft-fase:
    // rækken forbliver 'klar' hele vejen, og RPC'en re-registrerer varianterne selv.
    const p = c.payload || {};
    if (!p.file || !p.storagePath) throw new Error('Mangler fil eller sti til erstatning');
    const varianter = (p.varianter ?? []) as Array<{ file: Blob; storagePath: string }>;
    await performUpload(p.file as Blob, String(p.storagePath));
    await Promise.all(varianter.map((v) => performUpload(v.file, v.storagePath)));
  }
```
  (den eksisterende `if (opts.dryRun) return …`-linje flyttes altså OP før upload-blokkene
  hvis den ikke allerede står før — den står allerede før uploadMedia-uploaden på `:515`;
  behold rækkefølgen: gates → dryRun-return → uploads → rpc.)
  5. `oversaetFejl`-grene (før den generiske `/duplicate key|unique/`-fallback `:550`):
```ts
  if (/kan kun erstatte filen på et klart medie/i.test(message)) return 'Filen kan kun erstattes på et klart medie.';
  if (/filen er identisk med den nuværende/i.test(message)) return 'Filen er identisk med den nuværende — ingen ændring.';
  if (/kan kun udrense et fjernet medie/i.test(message)) return 'Mediet skal først fjernes (papirkurven), før det kan udrenses.';
  if (/har tilknytninger og kan ikke udrenses/i.test(message)) return 'Mediet har tilknytninger — fjern dem, før det udrenses.';
  if (/nævnt i narrativer og kan ikke udrenses/i.test(message)) return 'Mediet er nævnt i narrativer — redigér omtalerne ud, før det udrenses.';
  if (/ikke tilknyttet personen/i.test(message)) return 'Mediet er ikke tilknyttet personen — tilknyt det først.';
```

- [ ] **Step 4: Kør og verificér PASS** — `cd web && npx tsc --noEmit && npm run test`.

- [ ] **Step 5: Commit**

```bash
git add web/src/data/redaktionWrite.ts web/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(media): web-skrivelag for erstat/udrens/portræt

Fase 4 skive 4 (spec §6): tre nye Change-arter; erstat/udrens kan ikke
degradere til forslag; dry-run rører hverken Storage eller basen."
```

## Task 6: Mobile skrive-lag — spejl af Task 5

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts`
- Test: `mobile/src/data/__tests__/redaktionWrite.test.ts` (udvid eksisterende)

**Interfaces:**
- Consumes: RPC-kontrakterne fra Task 1–3; mobiles `performUpload(localUri, storagePath, mimeType)` (`mobile/src/lib/mediaUpload.ts:112-120`, dynamisk import + `deps`-injektion som uploadMedia, `redaktionWrite.ts:447-452`).
- Produces (Task 10 kalder): samme tre arter og RPC-args som web (tegn-for-tegn samme arg-navne/fejltekster). **Forskel (dokumenteret i Kilder):** mobile har INGEN degraderings-mekanik — `submitChange` kaster allerede ved `buildRpcCall===null` og kalder ellers altid direkte; ingen gate-kode tilføjes. Payload-formen for `erstatMediaFil` bruger `localUri`/`uri` i stedet for `file`-blobs (RN): `{ localUri: string; storagePath; mimeType; byteSize; bredde; hoejde; sha256; originalFilnavn?; varianter: Array<{tier; uri: string; storagePath; mimeType; byteSize; bredde; hoejde}> }`.

- [ ] **Step 1: Skriv fejlende jest-cases** (spejl af Task 5's buildRpcCall-/oversaetFejl-cases med samme forventningsværdier — det ER sync-kontrakten; `file`-felterne erstattes af `localUri`/`uri`-strenge i testdata). Tilføj desuden dryRun-testen mod mobiles `submitChange`-signatur:

```ts
it('dry-run uploader INTET og udfører intet RPC (dryRun respekteres)', async () => {
  const performUpload = jest.fn();
  const res = await submitChange(erstatChange, { dryRun: true }, { performUpload });
  expect(res.dryRun).toBe(true);
  expect(performUpload).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: Kør og verificér FAIL** — `cd mobile && npm test -- redaktionWrite`.

- [ ] **Step 3: Implementér:** union + tre `buildRpcCall`-grene (identiske med Task 5's, bortset fra at `erstatMediaFil`-varianterne læses fra payload med `uri`-felt — som stadig KUN mapper metadata til `p_varianter`), `oversaetFejl`-grene (tegn-for-tegn som web), og en erstat-gren i `submitChange` (efter `if (opts.dryRun) return …`, parallel til uploadMedia-grenen `:448-453`):

```ts
  if (c.art === 'erstatMediaFil') {
    const p = c.payload || {};
    if (!p.localUri || !p.storagePath) throw new Error('Mangler lokal fil eller sti til erstatning');
    upload = deps.performUpload ?? (await import('../lib/mediaUpload')).performUpload;
    await upload(String(p.localUri), String(p.storagePath), String(p.mimeType ?? 'application/octet-stream'));
    const varianter = (p.varianter ?? []) as Array<{ uri: string; storagePath: string; mimeType: string }>;
    for (const v of varianter) await upload(v.uri, v.storagePath, v.mimeType);
  }
```

- [ ] **Step 4: Kør og verificér PASS** — `cd mobile && npx tsc --noEmit && npm test`.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/redaktionWrite.ts mobile/src/data/__tests__/redaktionWrite.test.ts
git commit -m "feat(media): mobile-skrivelag for erstat/udrens/portræt (spejl af web)

Samme arg-navne og fejltekster som web; ingen degraderings-mekanik på
mobile (findes ikke i dette lag — dokumenteret i planens Kilder)."
```

## Task 7: Web læse-lag — `kvalifikator` gennem til `pickPortrait` + `fetchUdrensPreview` (spec §5.3)

**Files:**
- Modify: `web/src/data/media.ts` (`MediaItem`, `fetchMediaByRelation`, `pickPortrait`)
- Modify: `web/src/data/redaktionRead.ts` (`PersonMedia`, `mapPersonMediaRows`, `mediaFromRelPairs`, `fetchRedPersonMedia`, `MediaAnvendelse`, `mapMediaAnvendelse`, `fetchMediaAnvendelse`, NY `fetchUdrensPreview`)
- Test: `web/src/data/__tests__/media.test.ts` (opret hvis den ikke findes — `pickPortrait` er ren), `web/src/data/__tests__/redaktionRead.test.ts` (udvid)

**Interfaces:**
- Consumes: `relation.kvalifikator` (Task 3), `red_udrens_media_preview` (Task 2).
- Produces (Task 9 forbruger):
```ts
// media.ts
export type MediaItem = { …eksisterende…; primaer?: boolean };
export function pickPortrait(media: MediaItem[]): MediaItem | null
// prioritet: første signerbare med primaer → slags-heuristik → første signerbare

// redaktionRead.ts
export type PersonMedia = { …eksisterende…; primaer: boolean;             // false i bibliotek/objekt-kontekst
                            sha256: string | null };                       // Task 9's erstat-pre-flight ("identisk fil"-stop)
export type MediaAnvendelse = {
  afbildet: { type; id; navn; relationId; primaer: boolean }[];            // primaer kun sand for person-rækker
  mentions: { kildeType; kildeId; subjektNavn }[];
};
// 'tilknytninger' (review 34 L1): ALLE relationer, enhver rolle — bevidst IKKE 'afbildet',
// som ville kollidere med MediaAnvendelse.afbildet (et separat, korrekt navngivet felt).
export type UdrensPreview = {
  uploadStatus: string; kanUdrenses: boolean; blokeringer: string[];
  antalTilknytninger: number; antalMentions: number;
  antalFakta: number; antalStories: number; antalNarrativer: number; antalNoter: number;
  tilknytninger: { relationId: string; retning: 'ud' | 'ind'; modpartType: string; modpartId: string }[];
  mentions: { kildeType: string; kildeId: string }[];
  fakta: string[]; stories: string[]; narrativer: string[]; noter: string[];  // id-lister (review 34 H1/H3)
  stier: { bucket: string; sti: string; kilde: string }[];
};
export function mapUdrensPreview(raw: unknown): UdrensPreview               // ren, testbar
export async function fetchUdrensPreview(mediaId: string): Promise<UdrensPreview>  // rpc('red_udrens_media_preview')
```

- [ ] **Step 1: Skriv fejlende tests.**
  - `media.test.ts` (`pickPortrait`-prioriteten; `MediaItem`-fixtures med `url`):

```ts
import { describe, expect, it, vi } from 'vitest';
vi.mock('../../supabase', () => ({ supabase: { storage: { from: vi.fn() }, auth: { onAuthStateChange: vi.fn() }, from: vi.fn() } }));
import { pickPortrait, type MediaItem } from '../media';

const m = (id: number, slags: string, url: string | null, primaer?: boolean): MediaItem =>
  ({ id: String(id), slags, titel: '', kunstner: '', datering: '', url, thumbUrl: url, primaer });

describe('pickPortrait med primaer-flag (fase 4)', () => {
  it('primaer vinder over slags-heuristikken', () => {
    expect(pickPortrait([m(1, 'maleri', 'u1'), m(2, 'segl', 'u2', true)])?.id).toBe('2');
  });
  it('usignerbar primaer ignoreres (fallback til heuristik)', () => {
    expect(pickPortrait([m(1, 'segl', null, true), m(2, 'maleri', 'u2')])?.id).toBe('2');
  });
  it('uden primaer gælder den gamle heuristik uændret', () => {
    expect(pickPortrait([m(1, 'segl', 'u1'), m(2, 'maleri', 'u2')])?.id).toBe('2');
    expect(pickPortrait([m(1, 'segl', 'u1'), m(2, 'dokument', 'u2')])?.id).toBe('1');
  });
});
```

  - `redaktionRead.test.ts`: `mapUdrensPreview` (rå jsonb → camelCase, tomme lister,
    blokeringer, `tilknytninger` — ikke `afbildet` — samt de nye anker-tællinger/id-lister
    `fakta`/`stories`/`narrativer`/`noter`), `mapMediaAnvendelse` fører `primaer` igennem for person-rækker (raw
    `kvalifikator: {primaer:true}` → `primaer: true`; `null`/objekt-rækker → `false`),
    `mapPersonMediaRows` defaulter `primaer: false`.

- [ ] **Step 2: Kør og verificér FAIL** (`primaer`/`mapUdrensPreview` findes ikke → TS-fejl).

- [ ] **Step 3: Implementér.**
  - `media.ts`: `MediaItem` += `primaer?: boolean`. I `fetchMediaByRelation` (`:121-124`) udvid select til `'subjekt_id,objekt_id,kvalifikator'` og rel-typen med `kvalifikator: { primaer?: boolean } | null`; ved opbygningen af `byAnker` (`:129-136`) kopiér item pr. relation når flaget er sat (items deles ellers på tværs af ankre):
```ts
    for (const r of rels) {
      const it = itemById.get(String(mediaIdOf(r)));
      if (!it) continue;
      const k = String(ankerIdOf(r));
      const arr = byAnker.get(k) ?? [];
      arr.push(r.kvalifikator?.primaer === true ? { ...it, primaer: true } : it);
      byAnker.set(k, arr);
    }
```
    `pickPortrait` (`:168-171`):
```ts
// Vælg hovedbillede: eksplicit portræt-valg (primaer, fase 4/M10) → slags-heuristik → første med URL.
export function pickPortrait(media: MediaItem[]): MediaItem | null {
  const signable = withUrl(media);
  return signable.find((m) => m.primaer === true)
    ?? signable.find((m) => PORTRAIT_SLAGS.has(normSlags(m.slags)))
    ?? signable[0] ?? null;
}
```
    (`DetailPanel.tsx:39` opdager flaget automatisk — INGEN komponent-ændring, spec §7.3.)
  - `redaktionRead.ts`: `PersonMedia` += `primaer: boolean` og `sha256: string | null` (Task 9's pre-flight); `RawPersonMediaRow` += `sha256?: string | null`, og media-selectet i `mediaFromRelPairs` (`:784`) samt `mediaBibliotekQuerySpecs().media.select` (`:905`) udvides med `,sha256`; `mapPersonMediaRows` mapper `sha256: m.sha256 ?? null` og sætter `primaer: false` (bibliotek/objekt-kontekst); `fetchRedPersonMedia` (`:794-800`) select `'id,objekt_id,kvalifikator'`, byg `primaerByMediaId` og lad `mediaFromRelPairs` tage `pairs: { mediaId: number; relationId: number; primaer?: boolean }[]` og overskrive flaget i sit retur-map. `mediaAnvendelseQuerySpecs().personRelationer.select` += `',kvalifikator'`; `RawMediaPersonAnvendelse` += `kvalifikator?: { primaer?: boolean } | null`; `mapMediaAnvendelse` sætter `primaer: r.kvalifikator?.primaer === true` på person-rækker og `primaer: false` på objekt-rækker. Ny:
```ts
export function mapUdrensPreview(raw: unknown): UdrensPreview {
  const r = (raw ?? {}) as Record<string, unknown>;
  const arr = (v: unknown) => (Array.isArray(v) ? v : []);
  const ids = (v: unknown) => arr(v).map(String);
  return {
    uploadStatus: String(r.upload_status ?? ''),
    kanUdrenses: r.kan_udrenses === true,
    blokeringer: arr(r.blokeringer).map(String),
    antalTilknytninger: Number(r.antal_tilknytninger ?? 0),
    antalMentions: Number(r.antal_mentions ?? 0),
    antalFakta: Number(r.antal_fakta ?? 0),
    antalStories: Number(r.antal_stories ?? 0),
    antalNarrativer: Number(r.antal_narrativer ?? 0),
    antalNoter: Number(r.antal_noter ?? 0),
    tilknytninger: arr(r.tilknytninger).map((a) => {
      const x = a as Record<string, unknown>;
      return { relationId: String(x.relation_id), retning: x.retning === 'ud' ? 'ud' as const : 'ind' as const,
        modpartType: String(x.modpart_type), modpartId: String(x.modpart_id) };
    }),
    mentions: arr(r.mentions).map((m) => {
      const x = m as Record<string, unknown>;
      return { kildeType: String(x.kilde_type), kildeId: String(x.kilde_id) };
    }),
    fakta: ids(r.fakta), stories: ids(r.stories), narrativer: ids(r.narrativer), noter: ids(r.noter),
    stier: arr(r.stier).map((s) => {
      const x = s as Record<string, unknown>;
      return { bucket: String(x.bucket), sti: String(x.sti), kilde: String(x.kilde ?? 'media') };
    }),
  };
}

export async function fetchUdrensPreview(mediaId: string): Promise<UdrensPreview> {
  const id = parseDatabaseId(mediaId);
  if (id == null) throw new Error('Ugyldigt media-id');
  const { data, error } = await supabase.rpc('red_udrens_media_preview', { p_media_id: id });
  if (error) throw new Error(error.message);
  return mapUdrensPreview(data);
}
```

- [ ] **Step 4: Kør og verificér PASS** — `cd web && npx tsc --noEmit && npm run test && npm run build`.

- [ ] **Step 5: Commit**

```bash
git add web/src/data/media.ts web/src/data/redaktionRead.ts web/src/data/__tests__/
git commit -m "feat(media): web-læselag — primaer-flag til pickPortrait + udrens-preview

Fase 4 (spec §5.3): heuristikken er nu fallback; preview-RPC'ens jsonb
mappes rent og testbart."
```

## Task 8: Mobile læse-lag — spejl af Task 7

**Files:**
- Modify: `mobile/src/data/load.ts` (`:180-185` relations-select), `mobile/src/data/types.ts` (`RawRelation`, `RawMedia`), `mobile/src/data/buildAux.ts` (`:168-176` mediaBy), `mobile/src/lib/media.ts` (`pickPortrait` `:87-89`), `mobile/src/data/redaktionRead.ts` (spejl af Task 7's redaktionRead-ændringer)
- Test: `mobile/src/lib/__tests__/media.test.ts` (udvid), `mobile/src/data/__tests__/redaktionRead.test.ts` (udvid)

**Interfaces:**
- Consumes: Task 3's kolonne; Task 7's kontrakter (identiske forventningsværdier i test = sync-kontrakten).
- Produces (Task 10 forbruger): `RawMedia` += `primaer?: boolean` (sat pr. person-kontekst i `buildAux`s `mediaBy`); `pickPortrait` prioriterer `primaer`; `PersonMedia.primaer`, `MediaAnvendelse.afbildet[].primaer`, `mapUdrensPreview`/`fetchUdrensPreview` — samme former som web.

- [ ] **Step 1: Skriv fejlende jest-cases** — `media.test.ts`: primaer vinder over slags (`pickPortrait([m(1,'maleri'), {…m(2,'segl'), primaer: true}])?.id === 2`), uden primaer uændret heuristik (eksisterende cases skal forblive grønne); `redaktionRead.test.ts`: spejl af Task 7's `mapUdrensPreview`-/`mapMediaAnvendelse`-cases.

- [ ] **Step 2: Kør og verificér FAIL** — `cd mobile && npm test`.

- [ ] **Step 3: Implementér.**
  - `types.ts`: `RawRelation` += `kvalifikator?: { primaer?: boolean } | null`; `RawMedia` += `primaer?: boolean`.
  - `load.ts` (`:180-185`): person-relations-selectet udvides med `,kvalifikator` (media-subjekt-queryen `:186-192` uændret — objekt-fotoer har intet portræt-begreb). NB deploy-orden: DDL før app (Task 11); mobilen er dev-only (memory), så ingen `.catch`-degradering nødvendig.
  - `buildAux.ts` (`:168-176`): flaget følger RELATIONEN, ikke media-rækken (samme billede kan være portræt for én person og ej for en anden):
```ts
  (relations || []).forEach((r) => {
    if (r.objekt_type !== 'media' || (r.rolle || '') !== 'afbildet') return;
    const m = mediaById[String(r.objekt_id)];
    if (m) {
      const pid = cid(String(r.subjekt_id));
      (mediaBy[pid] = mediaBy[pid] || []).push(
        r.kvalifikator?.primaer === true ? { ...m, primaer: true } : m);
    }
  });
```
  - `mobile/src/lib/media.ts` (`:87-89`):
```ts
// Vælg hovedbillede: eksplicit portræt-valg (primaer, fase 4/M10) → slags-heuristik → første medie.
export function pickPortrait(media: RawMedia[]): RawMedia | null {
  return media.find((m) => m.primaer === true)
    ?? media.find((m) => PORTRAIT_SLAGS.has(normSlags(String(m.slags ?? ''))))
    ?? media[0] ?? null;
}
```
  - `redaktionRead.ts`: tegn-for-tegn spejl af Task 7's ændringer (`PersonMedia.primaer`, `fetchRedPersonMedia`-select, `mapMediaAnvendelse`, `mapUdrensPreview` + `fetchUdrensPreview`).

- [ ] **Step 4: Kør og verificér PASS** — `cd mobile && npx tsc --noEmit && npm test`.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/data/load.ts mobile/src/data/types.ts mobile/src/data/buildAux.ts mobile/src/lib/media.ts mobile/src/lib/__tests__/media.test.ts mobile/src/data/redaktionRead.ts mobile/src/data/__tests__/redaktionRead.test.ts
git commit -m "feat(media): mobile-læselag — primaer-flag + udrens-preview (spejl af web)"
```

## Task 9: Web-UI — filsidens tre handlinger (spec §7)

**Files:**
- Modify: `web/src/components/MediaDetaljeOverlay.tsx`
- Modify: `web/src/Redaktion.tsx` (`MEDIA_ARTER` `:51`, `renderMediaDetalje` `:1309-1412`)
- Test: `web/src/data/__tests__/redaktionWrite.test.ts` (udrens-orkestreringens dryRun-gate — ren funktion, se nedenfor)

**Interfaces:**
- Consumes: Task 5's arter, Task 7's `PersonMedia.primaer`/`MediaAnvendelse.afbildet[].primaer`/`fetchUdrensPreview`/`UdrensPreview`; fase 3-pipelinen `buildVariants` (`mediaUpload.ts:62-81`) og pre-flight `fetchExistingMediaBySha` (`mediaDedup.ts`); `run(change, titel)`-callbacken (`Redaktion.tsx:494-527`, treader komponentens `dryRun` ind i `submitChange`).
- Produces: tre nye overlay-props + orkestreringshelper:
```ts
// MediaDetaljeOverlay nye props:
onErstatFil?: (file: File) => void;                       // vises kun ved uploadStatus==='klar'
onUdrens?: () => void;                                    // vises kun ved uploadStatus==='fjernet'
udrensPreview?: UdrensPreview;                            // hentes af Redaktion.tsx når fjernet
onSaetPortraet?: (personId: string, mediaId: string | null) => void;  // på afbildet-person-rækker
// Redaktion.tsx: ren, testbar udrens-orkestrering (dryRun-gaten er PRÆCIS her):
export async function executeUdrens(opts: { mediaId: string; dryRun: boolean; role?: string }, deps: {
  submit: (c: Change, o: { dryRun: boolean; role?: string }) => Promise<{ dryRun: boolean; result?: unknown }>;
  removeObjects: (bucket: string, stier: string[]) => Promise<{ error: { message: string } | null }>;
}): Promise<{ kind: 'dry-run' | 'completed'; storageAdvarsel?: string }>
// placeres i web/src/data/mediaUdrens.ts (ny fil) så vitest kan øve den netværksfrit
```

- [ ] **Step 1: Skriv fejlende vitest-cases for `executeUdrens`** (ny fil `web/src/data/__tests__/mediaUdrens.test.ts`):

```ts
import { describe, expect, it, vi } from 'vitest';
import { executeUdrens } from '../mediaUdrens';

describe('executeUdrens (fase 4 — dryRun-threading-regressionstest, PR #72-læringen)', () => {
  it('dry-run: submitChange kaldes med dryRun=true og storage røres ALDRIG', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: true });
    const removeObjects = vi.fn();
    const res = await executeUdrens({ mediaId: '9', dryRun: true, role: 'redaktion' }, { submit, removeObjects });
    expect(submit).toHaveBeenCalledWith(expect.objectContaining({ art: 'udrensMedia' }),
      expect.objectContaining({ dryRun: true }));
    expect(removeObjects).not.toHaveBeenCalled();
    expect(res.kind).toBe('dry-run');
  });
  it('live: sletter de RETURNEREDE stier grupperet pr. bucket', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: false,
      result: { stier: [{ bucket: 'media', sti: 'a.jpg' }, { bucket: 'media', sti: 'b.jpg' }] } });
    const removeObjects = vi.fn().mockResolvedValue({ error: null });
    const res = await executeUdrens({ mediaId: '9', dryRun: false, role: 'redaktion' }, { submit, removeObjects });
    expect(removeObjects).toHaveBeenCalledWith('media', ['a.jpg', 'b.jpg']);
    expect(res).toEqual({ kind: 'completed' });
  });
  it('fejlet storage-kald bliver en ADVARSEL, ikke en fejlet udrensning (DB er sandheden)', async () => {
    const submit = vi.fn().mockResolvedValue({ dryRun: false, result: { stier: [{ bucket: 'media', sti: 'a.jpg' }] } });
    const removeObjects = vi.fn().mockResolvedValue({ error: { message: 'nede' } });
    const res = await executeUdrens({ mediaId: '9', dryRun: false, role: 'redaktion' }, { submit, removeObjects });
    expect(res.kind).toBe('completed');
    expect(res.storageAdvarsel).toMatch(/janitor/i);
  });
});
```

- [ ] **Step 2: Kør og verificér FAIL** (modulet findes ikke).

- [ ] **Step 3: Implementér `web/src/data/mediaUdrens.ts`:**

```ts
// Fase 4 (M11): klient-orkestrering af udrensning — DB-først, Storage bagefter (spec §4.2).
// Ren funktion med injicerede deps, så dryRun-gaten OG "advarsel, ikke fejl"-kontrakten er
// vitest-dækket (dryRun-threading-regressionstesten er obligatorisk pr. ny skrivevej, PR #72).
import type { Change } from './redaktionWrite';

type SubmitFn = (c: Change, o: { dryRun: boolean; role?: string }) => Promise<{ dryRun: boolean; result?: unknown }>;
type RemoveFn = (bucket: string, stier: string[]) => Promise<{ error: { message: string } | null }>;

export async function executeUdrens(
  opts: { mediaId: string; dryRun: boolean; role?: string },
  deps: { submit: SubmitFn; removeObjects: RemoveFn },
): Promise<{ kind: 'dry-run' | 'completed'; storageAdvarsel?: string }> {
  const res = await deps.submit(
    { art: 'udrensMedia', subjektType: 'media', subjektId: opts.mediaId, mediaId: opts.mediaId },
    { dryRun: opts.dryRun, role: opts.role },
  );
  if (res.dryRun) return { kind: 'dry-run' };
  const stier = ((res.result as { stier?: { bucket: string; sti: string }[] } | null)?.stier ?? []);
  const byBucket = new Map<string, string[]>();
  for (const s of stier) byBucket.set(s.bucket, [...(byBucket.get(s.bucket) ?? []), s.sti]);
  const fejl: string[] = [];
  for (const [bucket, paths] of byBucket) {
    const { error } = await deps.removeObjects(bucket, paths);
    if (error) fejl.push(`${bucket}: ${error.message}`);
  }
  return fejl.length
    ? { kind: 'completed', storageAdvarsel: `Rækken er slettet, men ${fejl.length} Storage-kald fejlede (${fejl.join('; ')}) — de forladte bytes er usynlige og ryddes af janitoren.` }
    : { kind: 'completed' };
}
```

- [ ] **Step 4: Kør og verificér PASS** — `cd web && npm run test -- mediaUdrens`.

- [ ] **Step 5: Overlay-ændringer i `MediaDetaljeOverlay.tsx`** (ingen nye tokens; `fletBusy`-fieldset-mønsteret genbruges):
  1. Props: `onErstatFil?`, `onUdrens?`, `udrensPreview?`, `onSaetPortraet?` (typerne fra Interface).
  2. **"Erstat fil…"** i handlings-sektionen (`:215-228`), kun når `media.uploadStatus === 'klar'` — skjult `<input type="file" accept="image/*">` + knap der trigger den (samme accept som upload-arket; HEIC-grænsen håndhæves af `buildVariants`s `decodeImage` uændret):
```tsx
{media.uploadStatus === 'klar' && onErstatFil ? (
  <label style={{ border: '1px solid rgba(34,31,26,.18)', borderRadius: 7, padding: '8px 13px', cursor: 'pointer', background: C.beige, color: C.muted, fontSize: 13 }}>
    Erstat fil…
    <input type="file" accept="image/*" style={{ display: 'none' }}
      onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) onErstatFil(f); }} />
  </label>
) : null}
```
  3. **"Slet permanent…"** ved siden af Genopret-knappen (kun `uploadStatus === 'fjernet'`), med dobbelt-bekræft (beslutning §10.4 — samme `bekraeft`-state-mønster som `bekraeftSlet` `:220-226`) og preview-data:
```tsx
{media.uploadStatus === 'fjernet' && onUdrens ? (
  <button type="button" disabled={fletBusy || !udrensPreview || !udrensPreview.kanUdrenses}
    title={udrensPreview && !udrensPreview.kanUdrenses ? udrensPreview.blokeringer.join(' · ') : undefined}
    onClick={() => {
      if (fletBusy || !udrensPreview?.kanUdrenses) return;
      if (!bekraeftUdrens) { setBekraeftUdrens(true); return; }
      onUdrens();
    }}
    style={{ border: 0, borderRadius: 7, padding: '8px 13px', cursor: udrensPreview?.kanUdrenses ? 'pointer' : 'default', background: C.red, color: '#fff', opacity: udrensPreview?.kanUdrenses ? 1 : .45 }}>
    {bekraeftUdrens
      ? `${udrensPreview?.stier.length ?? 0} fil(er) slettes permanent — bytes kan IKKE fortrydes. Klik igen for at bekræfte.`
      : !udrensPreview ? 'Kontrollerer…' : udrensPreview.kanUdrenses ? 'Slet permanent…' : 'Slet permanent (blokeret)'}
  </button>
) : null}
{media.uploadStatus === 'fjernet' && udrensPreview && !udrensPreview.kanUdrenses ? (
  <div role="alert" style={{ fontSize: 11.5, color: C.red }}>
    {udrensPreview.blokeringer.map((b) => <div key={b}>· {b}</div>)}
  </div>
) : null}
```
     (ny state `const [bekraeftUdrens, setBekraeftUdrens] = useState(false);`, nulstilles i den eksisterende `useEffect` `:44-49`. Blokeret tilstand: anvendelses-listen står allerede i "Bruges på"-sektionen med fjern-knapper — det ER "links til at rydde", spec §7.2.)
  4. **Portræt-knap + badge** på afbildet-person-rækkerne i "Bruges på" (`:131-136`):
```tsx
{anvendelse.afbildet.map((a) => (
  <div key={a.relationId} style={{ display: 'flex', alignItems: 'center', gap: 9, background: C.panel, borderRadius: 8, padding: '8px 10px' }}>
    <span style={{ flex: 1, minWidth: 0, fontSize: 12.5 }}>
      {a.navn} <span style={{ color: C.muted2 }}>· {a.type}</span>
      {a.primaer ? <span style={{ marginLeft: 7, fontSize: 9.5, letterSpacing: '.06em', textTransform: 'uppercase', color: C.bordeaux, border: '1px solid rgba(136,26,51,.28)', borderRadius: 5, padding: '1px 5px' }}>Portræt</span> : null}
    </span>
    {a.type === 'person' && onSaetPortraet && media.uploadStatus === 'klar' ? (
      <button type="button" disabled={fletBusy}
        onClick={() => { if (!fletBusy) onSaetPortraet(a.id, a.primaer ? null : media.id); }}
        style={{ border: 0, background: 'transparent', color: C.bordeaux, cursor: fletBusy ? 'default' : 'pointer', padding: 2, fontSize: 12 }}>
        {a.primaer ? 'Fjern portræt-valg' : 'Sæt som portræt'}
      </button>
    ) : null}
    {onFjernTilknytning ? <button type="button" disabled={fletBusy} onClick={() => { if (!fletBusy) onFjernTilknytning(a.relationId); }} style={{ border: 0, background: 'transparent', color: C.red, cursor: fletBusy ? 'default' : 'pointer', padding: 2 }}>Fjern</button> : null}
  </div>
))}
```

- [ ] **Step 6: Wiring i `Redaktion.tsx`:**
  1. `MEDIA_ARTER` (`:51`) += `'erstatMediaFil', 'udrensMedia', 'saetPortraet'` (så `mediaChanged`-refetch-kæden `:503-511` dækker de nye arter).
  2. State + preview-hentning i `renderMediaDetalje`-konteksten: når det viste medie har `uploadStatus === 'fjernet'`, hent `fetchUdrensPreview(m.id)` (effekt ved `mediaDetalje`-skift, med fejl → `udrensPreview` forbliver `undefined` og knappen viser 'Kontrollerer…').
  3. Erstat-handler (pre-flight FØR upload, spec §7.1):
```ts
const erstatFil = async (file: File) => {
  try {
    const built = await buildVariants(file);  // fase 3-pipelinen: tiers → sha → sha-stier
    if (m.sha256 != null && built.sha256 === m.sha256) {  // m.sha256 kommer fra Task 7's udvidede selects
      setWriteView({ title: 'Erstat stoppet', lines: [], error: 'Filen er identisk med den nuværende — ingen ændring.', done: false, dryRun, direkte: true });
      return;
    }
    const existing = await fetchExistingMediaBySha(built.sha256);
    if (existing && existing.id !== m.id) {
      setWriteView({ title: 'Erstat stoppet', lines: [`Billedet findes allerede som medie ${existing.id}.`], error: "Brug 'Tilknyt eksisterende' i stedet for at erstatte.", done: false, dryRun, direkte: true });
      return;
    }
    await run({ art: 'erstatMediaFil', subjektType: mediaDetalje.subjektType, subjektId: mediaDetalje.subjektId,
      mediaId: m.id, payload: {
        file: built.large.file, storagePath: built.large.storagePath, mimeType: built.large.mimeType,
        byteSize: built.large.byteSize, bredde: built.large.bredde, hoejde: built.large.hoejde,
        sha256: built.sha256, originalFilnavn: file.name,
        varianter: [built.thumb, built.medium],
      } }, 'Erstat fil');
  } catch (e) {
    setWriteView({ title: 'Erstat fil fejlede', lines: [], error: oversaetFejl(String((e as Error)?.message ?? e)), done: false, dryRun, direkte: false });
  }
};
```
     (`run` treader komponentens `dryRun` → `submitChange` uploader intet ved dry-run, Task 5. Rækkens `sha256` er kendt i UI-laget via Task 7's udvidede selects. NB: pre-flightens egen-sha-gren er kun en hurtig-stop-optimering — server-guarden 'Filen er identisk…' er bagstopperen, også når `m.sha256` er NULL på gamle rækker.)
  4. Udrens-handler via helperen:
```ts
const udrens = async () => {
  const res = await executeUdrens({ mediaId: m.id, dryRun, role }, {
    submit: (c, o) => submitChange(c, o),
    removeObjects: async (bucket, stier) => supabase.storage.from(bucket).remove(stier),
  });
  setWriteView({
    title: res.kind === 'dry-run' ? 'Dry-run · udrensning' : 'Mediet er udrenset permanent',
    lines: res.storageAdvarsel ? [res.storageAdvarsel] : [],
    error: '', done: res.kind === 'completed', dryRun: res.kind === 'dry-run', direkte: true,
  });
  if (res.kind === 'completed') { setMediaDetalje(null); refreshMediaBibliotek(); }
};
```
     (wrap i try/catch med `oversaetFejl` som de øvrige handlers.)
  5. Props på `<MediaDetaljeOverlay …>` (`:1383-1409`): `onErstatFil={erstatFil}`, `onUdrens={udrens}`, `udrensPreview={udrensPreview}`, `onSaetPortraet={(personId, mediaId) => run({ art: 'saetPortraet', subjektType: 'person', subjektId: personId, personId, mediaId: mediaId ?? undefined }, mediaId ? 'Sæt portræt' : 'Fjern portræt-valg')}`.
  6. Papirkurvs-køens rækker (bibliotekets `fjernet`-kø) åbner allerede filsiden — dét ER indgangen fra køen (spec §7.2); ingen ekstra massehandling (beslutning §10.4).

- [ ] **Step 7: Verifikation** — `cd web && npx tsc --noEmit && npm run test && npm run build`; browser-røgtest mod lokal/dev-base: (a) erstat en fil på et klart medie → nyt billede vises, id/relationer uændrede; erstat med samme fil → stoppes af pre-flight; (b) blødt fjern → "Slet permanent…" viser blokeringer ved tilknytning → ryd → dobbelt-bekræft → række + preview væk, papirkurvs-køen opdateret; dry-run-toggle på → begge handlinger viser kun forhåndsvisning; (c) sæt portræt på et ikke-heuristik-billede → læserens `DetailPanel` viser det; "Fjern portræt-valg" → heuristikken igen.

- [ ] **Step 8: Commit**

```bash
git add web/src/components/MediaDetaljeOverlay.tsx web/src/Redaktion.tsx web/src/data/mediaUdrens.ts web/src/data/__tests__/mediaUdrens.test.ts web/src/data/redaktionRead.ts
git commit -m "feat(media): web-filside — erstat fil, slet permanent, portræt-valg

Fase 4 skive 5 (spec §7): pre-flight før bytes, DB-først-udrens med
testbar dryRun-gate (PR #72-regressionsmønsteret), portræt-badge og -knap."
```

## Task 10: Mobile-UI — spejl på sheet + filside (spec §8)

**Files:**
- Modify: `mobile/src/components/redaktion/MediaDetaljeSheet.tsx`
- Modify: `mobile/src/app/redaktion/entitet/medie/[id].tsx` (wiring `:129-146`)
- Modify: `mobile/src/app/redaktion/person/[id].tsx` (sheet-wiring `:653-665` + `applied`-art-listen `:733`)

**Interfaces:**
- Consumes: Task 6's arter, Task 8's `fetchUdrensPreview`/`UdrensPreview`/`primaer`; `pickImage`/`buildVariants` (`mobile/src/lib/mediaUpload.ts:24-98` — HEIC virker her, native afkoder); mobiles dedup-opslag (`mobile/src/data/mediaDedup.ts`); `SkrivePreviewSheet` (treader store'ns `dryRun` automatisk — `:16,33`).
- Produces: nye sheet-props `onErstatFil?: () => void` (sheetet ejer IKKE billedvælgeren — callback'en åbner den i skærmen), `onUdrens?: () => void`, `udrensPreview?: UdrensPreview`, `onSaetPortraet?: (personId: string, mediaId: string | null) => void`.

- [ ] **Step 1: Sheet-ændringer i `MediaDetaljeSheet.tsx`** (samme adfærd som web-overlayet, RN-udtryk):
  - "Erstat fil…"-knap i handlingsrækken (`:119-130`), kun `uploadStatus === 'klar'`: `<Pressable style={styles.neutral} onPress={onErstatFil}><BtnLabel color={Colors.textMuted}>Erstat fil…</BtnLabel></Pressable>`.
  - "Slet permanent…" ved siden af Genopret (kun `'fjernet'`), dobbelt-bekræft med ny `bekraeftUdrens`-state (kopiér `bekraeftSlet`-mønsteret `:124-128`), disabled/blokeret-tekst fra `udrensPreview` som web (Task 9 Step 5.3 — genbrug teksterne ordret).
  - Portræt-badge + knap på afbildet-person-rækkerne (`:109-112`): badge `Portræt` (Mono, `Colors.gold`) når `a.primaer`; knap `Sæt som portræt`/`Fjern portræt-valg` når `a.type === 'person' && media.uploadStatus === 'klar'` → `onSaetPortraet(a.id, a.primaer ? null : media.id)`.

- [ ] **Step 2: Wiring i `medie/[id].tsx`:**
  - Hent preview når `media.uploadStatus === 'fjernet'`: `fetchUdrensPreview(media.id)` i `hent`-kæden (fejl-tolerant som anvendelses-fetchen).
  - `onErstatFil`: `pickImage()` → `buildVariants(picked)` → pre-flight (egen sha → besked-stop; fremmed sha via `fetchExistingMediaBySha` → besked "brug Tilknyt i stedet") → `setPending({ art: 'erstatMediaFil', subjektType: 'media', subjektId: media.id, mediaId: media.id, payload: { localUri: built.large.uri, storagePath: built.large.storagePath, mimeType: built.large.mimeType, byteSize: built.large.byteSize, bredde: built.large.bredde, hoejde: built.large.hoejde, sha256: built.sha256, originalFilnavn: picked.fileName ?? undefined, varianter: [built.thumb, built.medium] } })` — `SkrivePreviewSheet` treader `dryRun` fra store'n (regressionstesten er Task 6's submitChange-test; sheet-laget tilføjer ingen egen dryRun-beslutning).
  - `onUdrens`: `setPending({ art: 'udrensMedia', subjektType: 'media', subjektId: media.id, mediaId: media.id })`; i `SkrivePreviewSheet.onApplied(result)`: hvis den anvendte art var `udrensMedia`, kør `supabase.storage.from(bucket).remove(stier)` over `result.stier` grupperet pr. bucket (samme "advarsel, ikke fejl"-kontrakt som web — fejl vises som tekst, DB-tilstanden er sandheden) og `router.back()` (rækken findes ikke længere).
  - `onSaetPortraet`: `setPending({ art: 'saetPortraet', subjektType: 'person', subjektId: personId, personId, mediaId: mediaId ?? undefined })`.
- [ ] **Step 3: Wiring i `person/[id].tsx`:** samme fire props på sheet-instansen (`:653-665`); udvid `applied`-art-listen (`:733`) med `'erstatMediaFil','udrensMedia','saetPortraet'` så modellen genindlæses. Kø-*behandling* (papirkurvs-massegennemgang) forbliver web (koncept §7) — mobilen udrenser enkeltmedier fra sheetet.

- [ ] **Step 4: Verifikation** — `cd mobile && npx tsc --noEmit && npm test`; simulator-gennemløb (fysisk enhed hvis Metro-fetch driller, memory 'mobil-sim-rn-fetch-1005'): erstat (HEIC-kilde OK), udrens af et fjernet medie uden anvendelser, sæt/fjern portræt — alle tre først i dry-run (preview-sheet viser kaldet, intet skrives), så live.

- [ ] **Step 5: Commit**

```bash
git add mobile/src/components/redaktion/MediaDetaljeSheet.tsx "mobile/src/app/redaktion/entitet/medie/[id].tsx" "mobile/src/app/redaktion/person/[id].tsx"
git commit -m "feat(media): mobile-filside — erstat fil, slet permanent, portræt-valg

Fase 4 skive 6 (spec §8): fuld pr.-medie-paritet; kø-behandling forbliver web."
```

## Task 11: Samlet verifikation, afstemning & prod-runbook-note (spec §9)

- [ ] **Step 1: Fuld lokal DB-cyklus** — frisk `schema.sql`-install OG migrationssti ×2
  (Task 4 Step 2-proceduren gentaget på endelig HEAD) + `db-rls.sql`; hele
  `db-verify.sql` + `db-verify-media.sql` grønne ad begge veje (inkl. fase 1–3's
  eksisterende blokke — ingen regression).
- [ ] **Step 2: Fulde app-suiter** — web: `npx tsc --noEmit && npm run test && npm run build`
  (422+ tests); mobile: `npx tsc --noEmit && npm test` (345+); core uberørt men kør
  `npm test` i `packages/core` for en sikkerheds skyld (267+). På en HEAD committet af
  implementøren selv.
- [ ] **Step 3: Empirisk ende-til-ende (dev/lokal prod-kopi — IKKE prod; spec §9):**
  (a) erstat en fil → id/relationer/mentions/rettigheder uændrede, ny fil vises, gamle
  stier forældreløse → `R/media-janitor.R`-RAPPORT (uden flag!) viser dem som kategori b;
  fortryd erstat → gammel fil tilbage, variant-mismatch synlig (dokumenteret §10.3);
  (b) blødt fjern → udrens blokeret af relation → ryd → udrens → række + bytes borte,
  anon/auth ser 0 (db-verify-media-blokken beviser det statisk; bekræft empirisk med
  anon-nøgle), janitor-rapport ren; (c) sæt portræt → læser-web + mobile viser valgt
  billede; ryd → heuristik igen.
- [ ] **Step 4: Dokumentations-afstemning.** BYG OVENPÅ de eksisterende (endnu
  ukommitterede) docs-ændringer — overskriv intet: changelog-entry (fase 4 implementeret
  lokalt, prod-deploy udestår; nævn §10.3–5-beslutningerne: variant-mismatch accepteret,
  dobbelt-bekræft valgt, ryd-gren medtaget); koncept-§9-tabellen: fase 4-rækken →
  "implementeret lokalt" + RET de forældede fase 1+2-statuslinjer ("Implementeret lokalt;
  prod-deploy gated" → LIVE 2026-07-20, spec §1's dokumentationsafvigelse);
  `docs/database-current-state.md`: `relation.kvalifikator` + de fire funktioner i
  funktionsinventaret, markeret "lokal — ikke deployet".
- [ ] **Step 5: Prod-runbook-note (UDFØRES IKKE her — gated):** fase 4-migrationen
  `mediehaandtering_fase4_identitet` deployes ALENE i sin egen gated runbook (fase 3-
  præcedensen): krypteret backup → migrationsblokken → fase 4-verify-blokkene +
  `db-verify-media.sql` → `get_advisors(security)` (forvent kun kendte mønstre) →
  app-deploy (web; mobile er dev-only — ren JS-ændring, ingen native genbygning nødvendig
  i fase 4) → redaktør-røgtest af de tre flows → første janitor-kørsel efter et reelt
  erstat er fortsat rapport-only og gennemgås med brugeren før noget `--slet`.
- [ ] **Step 6: Commit**

```bash
git add docs/changelog.md docs/database-current-state.md docs/design/2026-07-19-mediehaandtering-robust-koncept.md
git commit -m "docs(media): afstem fase 4 — implementeret lokalt, prod-deploy gated"
```

---

## Endelig verifikation (Definition of Done)

1. Lokal Postgres: frisk install OG migrationssti ×2 giver identisk flade (`diff` tom);
   alle fase 4-asserts grønne ad begge veje (erstat: guards + atomiske varianter +
   fortryd-tilbage-rul m. dokumenteret variant-mismatch; udrens: kun-fra-fjernet +
   anker-blok på ALLE seks polymorfe ankre (relation begge retninger, mention, fakta m.
   evidenskæde, story, narrativ, defensiv note — review 34 H1/H3) + atomisk guard+slet i
   ét statement (H2) + preview↔udrens-paritet + intet-forældreløst-efter-udrens +
   DELETE-event m. foer-snapshot + fortryd-uden-varianter; portræt: søskende-nulstilling
   + ryd-gren + guard + kolonne-eksistens (samtidigheds-scenariet verificeret umuligt,
   M1 dismissed); anon-0-synlighed gennem udrens-cyklussen).
2. Web + mobile: tsc + suiter + build grønne; de nye buildRpcCall-/oversaetFejl-/
   pickPortrait-/mapUdrensPreview-tests spejlet med identiske forventningsværdier.
3. dryRun-threading bevist pr. ny skrivevej: erstat (submitChange-dry-run uploader
   intet, begge platforme), udrens (`executeUdrens`-testen: intet `storage.remove` ved
   dry-run), portræt (går gennem den generiske `run`/`SkrivePreviewSheet`-vej, dækket af
   submitChange-dry-run-kontrakten).
4. Erstat overskriver aldrig gamle objekter; ingen janitor-kode ændret; ingen RLS-fil
   ændret; `red_registrer_media_variant` åbner fortsat intet change_set (erstat = ÉT sæt).
5. Manuel verifikation gennemført (Task 11 Step 3) — inkl. janitor-rapportens kategori
   b-fund efter erstat (fristbindings-kontrakten §3.3/§10.2 empirisk bekræftet).
6. Dokumentation afstemt uden at overskrive de eksisterende ukommitterede fase 3-
   cutover-ændringer; spec-filen committet; prod-deploy udestår som separat gated trin.
