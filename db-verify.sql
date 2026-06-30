-- =============================================================
-- db-verify.sql
-- Verifikations-script til Supabase SQL Editor.
--
-- Kør dette script MOD EN BRANCH ELLER KOPI af databasen,
-- EFTER at følgende filer er kørt i Supabase SQL Editor:
--   1. db-migrations.sql  (idempotent afstemning af skema)
--   2. db-rls.sql         (RLS-politikker + grants)
--
-- Advarsel: Nogle assert-blokke seeder midlertidige testrækker
-- (fx subjekt_id=-99 eller temporære fact/assertion/conclusion-
-- rækker) og rydder selv op bagefter. Kør ikke mod prod-base.
--
-- NOTE OM ROLLE-GATING: Supabase SQL Editor kører som databaseejer
-- (postgres/service_role), IKKE som en authenticated Supabase-bruger.
-- Det betyder auth.uid() returnerer NULL → current_rolle() returnerer
-- 'medlem'. Asserts der forventer AFVISNING (Kun redaktion-RAISE)
-- fungerer som forventet i SQL Editor.
-- Asserts der kræver happy-path FOR redaktion (fx Task 4's
-- slet-re-peg) kræver enten:
--   (a) Kørsel som funktionsejer (SET ROLE til ejer, derefter RESET ROLE),
--   (b) Midlertidigt seedet redaktion-profil for auth.uid(), eller
--   (c) Test via app-laget mod en redaktion-session (Task 9 i planen).
-- Dette er dokumenteret pr. assert-blok nedenfor.
-- =============================================================


-- ===== Task 1: Tabeller profiles + suggestion =====
-- Forvent: begge tabeller findes, rolle-CHECK håndhæves.

SELECT to_regclass('public.profiles') IS NOT NULL AS profiles_ok,
       to_regclass('public.suggestion') IS NOT NULL AS suggestion_ok;
-- Forvent profiles_ok=t, suggestion_ok=t

DO $$ BEGIN
  BEGIN
    INSERT INTO profiles(id, rolle) VALUES (gen_random_uuid(), 'forsker');
    RAISE EXCEPTION 'CHECK fejlede ikke — forventede afvisning';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK: rolle-CHECK afviser forsker';
  END;
END $$;


-- ===== Task 2: Cache-regenerering — regen_person_visning + trigger =====
-- Vælg en person med navne-fakta; nulstil cache; kald regen; bekræft den genskabes.
-- Forvent: NOTICE "OK: visning_navn regenereret".

WITH p AS (
  SELECT f.subjekt_id AS pid FROM fact f
  JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
  WHERE f.subjekt_type='person' AND f.faktatype='navn' LIMIT 1
)
UPDATE person SET visning_navn=NULL WHERE id=(SELECT pid FROM p);
-- Kald regen for samme person og bekræft visning_navn nu er sat igen:
DO $$ DECLARE tid BIGINT;
BEGIN
  SELECT f.subjekt_id INTO tid FROM fact f
   JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
   WHERE f.subjekt_type='person' AND f.faktatype='navn' LIMIT 1;
  PERFORM regen_person_visning(tid);
  IF (SELECT visning_navn FROM person WHERE id=tid) IS NULL
    THEN RAISE EXCEPTION 'regen genskabte ikke visning_navn';
    ELSE RAISE NOTICE 'OK: visning_navn regenereret';
  END IF;
END $$;


-- ===== Task 3: current_rolle + red_upsert_fakta (fact-triplet, rolle-gated) =====
-- (a) Uden redaktion-rolle: forvent afvisning.
-- Forvent: NOTICE "OK: medlem afvist".
-- NOTE: auth.uid() er NULL i SQL Editor → rolle 'medlem' → RAISE forventes.
-- Happy-path (insert med redaktion-session) testes i Task 9 via app-laget.

DO $$ BEGIN
  BEGIN
    PERFORM red_upsert_fakta('person', (SELECT id FROM person LIMIT 1), 'navn', 'Testnavn');
    RAISE EXCEPTION 'Forventede rolle-afvisning';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN RAISE NOTICE 'OK: medlem afvist';
    ELSE RAISE; END IF;
  END;
END $$;


-- ===== Task 4: red_set_konklusion + red_edit_oplysning + red_slet_oplysning =====
-- Seed et fact med to assertions, slet den valgte, bekræft konklusion peger på tilbageværende.
-- Forvent: NOTICE "OK: konklusion re-pegede til a2".
--
-- NOTE OM ROLLE-GATING: red_slet_oplysning tjekker current_rolle() = 'redaktion'.
-- I SQL Editor (auth.uid() NULL → 'medlem') vil kaldet REJSE en fejl.
-- Løsning: kør blokken som funktionsejer (postgres) eller seed en redaktion-profil
-- for auth.uid() midlertidigt — dokumentér i PR. Se Global Constraints i planen.

DO $$ DECLARE fid bigint; a1 bigint; a2 bigint; cid bigint; chosen bigint;
BEGIN
  fid := (SELECT coalesce(max(id),0)+1 FROM fact);
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (fid,'person',-99,'test_slet');
  a1 := (SELECT coalesce(max(id),0)+1 FROM assertion);
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig) VALUES (a1,'fact',fid,'A',false);
  a2 := a1+1;
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,uforanderlig) VALUES (a2,'fact',fid,'B',false);
  cid := (SELECT coalesce(max(id),0)+1 FROM conclusion);
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id) VALUES (cid,'fact',fid,a1);
  -- Slet den valgte (a1); forvent konklusion re-peger til a2.
  PERFORM red_slet_oplysning(a1);  -- bemærk: gating kræver redaktion; kør evt. som funktionsejer
  SELECT valgt_assertion_id INTO chosen FROM conclusion WHERE id=cid;
  IF chosen = a2 THEN RAISE NOTICE 'OK: konklusion re-pegede til a2';
  ELSE RAISE EXCEPTION 'Forventede a2, fik %', chosen; END IF;
  -- Oprydning:
  DELETE FROM conclusion WHERE id=cid; DELETE FROM assertion WHERE target_id=fid AND target_type='fact';
  DELETE FROM fact WHERE id=fid;
END $$;


-- ===== Task 5: Direkte person/narrativ/relation-RPC'er (rolle-gated) =====
-- Forvent: NOTICE "OK: koen-RPC gated".
-- NOTE: auth.uid() er NULL i SQL Editor → rolle 'medlem' → RAISE forventes.
-- Happy-path (faktisk koen-sætning) testes via app-laget med redaktion-session.

DO $$ BEGIN
  -- gating: medlem (auth.uid() NULL) afvises
  BEGIN PERFORM red_set_koen((SELECT id FROM person LIMIT 1),'mand');
    RAISE EXCEPTION 'Forventede afvisning';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN RAISE NOTICE 'OK: koen-RPC gated';
    ELSE RAISE; END IF;
  END;
END $$;


-- ===== Task 6: red_suggest — medlem-forslag til staging =====
-- Forvent: NOTICE "OK: anon afvist".
-- NOTE: auth.uid() er NULL i SQL Editor → red_suggest rejser 'Login kræves'.
-- Happy-path (forslag med authenticated session) testes via app-laget.

DO $$ BEGIN
  BEGIN PERFORM red_suggest('fakta','person',1,'navn','Test');
    RAISE EXCEPTION 'Forventede login-afvisning';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Login kræves%' THEN RAISE NOTICE 'OK: anon afvist';
    ELSE RAISE; END IF;
  END;
END $$;


-- ===== Task 7: Authenticated read-RLS + RPC-grants =====
-- Forvent: auth_policies >= 11 (auth_read × 10 tabeller + self_read + own_read).

SELECT count(*) AS auth_policies FROM pg_policies
 WHERE schemaname='public' AND policyname IN ('auth_read','self_read','own_read');
-- Forvent auth_policies >= 11


-- ===== Samlet politik-røgtest =====
-- Bredere tælling: alle fire navngivne politik-typer der forventes af dette migrations-sæt.
-- Forventet antal: mange (>10). Tjekker at anon_read (fra det eksisterende db-rls.sql),
-- auth_read, self_read og own_read alle er oprettet.

SELECT count(*) FROM pg_policies
  WHERE schemaname='public'
    AND policyname IN ('anon_read','auth_read','self_read','own_read');
-- Forventet: >= 12 (anon_read: mindst 1 fra tidligere migrations + auth_read: 10 + self_read: 1 + own_read: 1)


-- ===== Task 8: media afbildet-gating (anon) =====
-- Forvent: NOTICE "OK: media-gating ...". Seeder negative-id testrækker og rydder selv op.
-- Kører faktisk som rolle 'anon' (SET LOCAL ROLE) for at RAMME RLS — SQL Editor er ellers
-- ejer/bypass. Hele blokken er ét DO = én transaktion; rejser den, rulles seed-rækkerne tilbage.
-- Verificerer fail-closed-reglen: afdød afbildet → synlig, levende afbildet → skjult,
-- objekt uden afbildet-person → synlig.
DO $$
DECLARE vis_dead int; vis_live int; vis_obj int;
BEGIN
  -- ryd evt. rester fra et afbrudt løb
  DELETE FROM relation WHERE id IN (-901,-902);
  DELETE FROM media    WHERE id IN (-901,-902,-903);
  DELETE FROM person   WHERE id IN (-901,-902);

  INSERT INTO person(id, levende, privat) VALUES (-901, false, false), (-902, true, false);
  INSERT INTO media(id, slags, titel) VALUES
    (-901,'foto','portræt-afdød'), (-902,'foto','portræt-levende'), (-903,'segl','objekt-uden-person');
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle) VALUES
    (-901,'person',-901,'media',-901,'afbildet'),
    (-902,'person',-902,'media',-902,'afbildet');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_dead FROM media WHERE id = -901;
  SELECT count(*) INTO vis_live FROM media WHERE id = -902;
  SELECT count(*) INTO vis_obj  FROM media WHERE id = -903;
  RESET ROLE;

  IF vis_dead = 1 AND vis_live = 0 AND vis_obj = 1 THEN
    RAISE NOTICE 'OK: media-gating (afdød synlig, levende skjult, objekt synligt)';
  ELSE
    RAISE EXCEPTION 'media-gating FEJL: afdød=% (vent 1), levende=% (vent 0), objekt=% (vent 1)',
      vis_dead, vis_live, vis_obj;
  END IF;

  DELETE FROM relation WHERE id IN (-901,-902);
  DELETE FROM media    WHERE id IN (-901,-902,-903);
  DELETE FROM person   WHERE id IN (-901,-902);
END $$;


-- ===== Task 9: lineage trin (b) — forgrening + status =====
-- Forvent: kolonnerne findes, og en selv-refererende gren (parent_lineage_id) + en
-- 'gren_af'-relation kan oprettes og resolveres. Seeder negative-id rækker, rydder op.
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='lineage' AND column_name='parent_lineage_id') AS har_parent,
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='lineage' AND column_name='status') AS har_status;
-- Forvent har_parent=1, har_status=1

DO $$
DECLARE resolved_navn text; rel_ok int;
BEGIN
  DELETE FROM relation WHERE id = -910;
  DELETE FROM lineage  WHERE id IN (-910,-911);

  -- moderlinje + adlet gren der udgår af den
  INSERT INTO lineage(id, navn, status) VALUES (-910,'Test-moderlinje', NULL);
  INSERT INTO lineage(id, navn, parent_lineage_id, status)
    VALUES (-911,'Test-gren (adlet)', -910, 'uddød');
  -- evidens-bærende 'gren_af'-relation (polymorf, ingen skema-ændring)
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, konfidens)
    VALUES (-910,'lineage',-911,'lineage',-910,'gren_af','sandsynlig');

  -- FK resolves: grenens parent peger på moderlinjens navn
  SELECT m.navn INTO resolved_navn
    FROM lineage g JOIN lineage m ON m.id = g.parent_lineage_id WHERE g.id = -911;
  SELECT count(*) INTO rel_ok FROM relation
    WHERE id=-910 AND rolle='gren_af' AND subjekt_type='lineage' AND objekt_type='lineage';

  IF resolved_navn = 'Test-moderlinje' AND rel_ok = 1 THEN
    RAISE NOTICE 'OK: lineage (b) — forgrening + gren_af-relation';
  ELSE
    RAISE EXCEPTION 'lineage (b) FEJL: parent_navn=% (vent Test-moderlinje), rel_ok=% (vent 1)',
      resolved_navn, rel_ok;
  END IF;

  DELETE FROM relation WHERE id = -910;
  DELETE FROM lineage  WHERE id IN (-910,-911);
END $$;


-- =====================================================================
--  VERSIONERING + HYPERLINKS (2026-06-30) — asserts pr. task
--  Køres mod KOPI/branch-base, aldrig prod (jf. plan Global Constraints).
-- =====================================================================

-- ===== Versionering Task 1: PK-registry =====
DO $$
BEGIN
  IF to_regclass('public.version_pk_registry') IS NULL THEN
    RAISE EXCEPTION 'FEJL: version_pk_registry mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='family_member'
                 AND pk_cols = ARRAY['family_id','person_id','rolle']) THEN
    RAISE EXCEPTION 'FEJL: family_member composite PK ikke registreret korrekt';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='person'
                 AND skip_cols @> ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel']) THEN
    RAISE EXCEPTION 'FEJL: person visning_* ikke i skip_cols';
  END IF;
  RAISE NOTICE 'OK: version_pk_registry seeded';
END $$;

-- ===== Versionering Task 2: change_set/change_event =====
DO $$
BEGIN
  IF to_regclass('public.change_set') IS NULL OR to_regclass('public.change_event') IS NULL THEN
    RAISE EXCEPTION 'FEJL: change_set/change_event mangler';
  END IF;
  -- actor_id skal være ON DELETE SET NULL (spec-B3/H6)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.referential_constraints rc
    JOIN information_schema.key_column_usage k ON k.constraint_name=rc.constraint_name
    WHERE k.table_name='change_set' AND k.column_name='actor_id' AND rc.delete_rule='SET NULL') THEN
    RAISE EXCEPTION 'FEJL: change_set.actor_id mangler ON DELETE SET NULL';
  END IF;
  RAISE NOTICE 'OK: change_set/change_event findes m. korrekt actor-FK';
END $$;

-- ===== Versionering Task 3: begin_change_set re-entrant =====
DO $$
DECLARE a bigint; b bigint;
BEGIN
  PERFORM set_config('app.change_set_id', '', true);  -- nulstil
  a := begin_change_set('test_op','sum','person',1);
  b := begin_change_set('indre_op','sum2','person',1); -- nested → skal genbruge a
  IF a <> b THEN RAISE EXCEPTION 'FEJL: nested begin_change_set gav nyt id (% <> %)', a, b; END IF;
  IF current_setting('app.change_set_id', true) <> a::text THEN
    RAISE EXCEPTION 'FEJL: session-variabel ikke sat'; END IF;
  DELETE FROM change_set WHERE id=a;  -- oprydning
  PERFORM set_config('app.change_set_id', '', true);
  RAISE NOTICE 'OK: begin_change_set er re-entrant';
END $$;

-- ===== Versionering Task 4: log_change trigger =====
DO $$
DECLARE cs bigint; n int; ev change_event;
BEGIN
  -- (a) UDEN aktivt change_set: en UPDATE logges IKKE (bulk-load-sti)
  PERFORM set_config('app.change_set_id','',true);
  UPDATE person SET status=status WHERE id=(SELECT id FROM person LIMIT 1);
  -- (b) MED aktivt change_set: en ægte ændring logges
  cs := begin_change_set('test_log','t','person',NULL);
  UPDATE person SET status='__verify__' WHERE id=(SELECT id FROM person LIMIT 1);
  SELECT count(*) INTO n FROM change_event WHERE change_set_id=cs AND tabel='person';
  IF n <> 1 THEN RAISE EXCEPTION 'FEJL: forventede 1 person-event, fik %', n; END IF;
  -- (c) visning_* ekskluderet fra snapshot
  SELECT * INTO ev FROM change_event WHERE change_set_id=cs AND tabel='person' LIMIT 1;
  IF ev.efter ? 'visning_navn' THEN RAISE EXCEPTION 'FEJL: visning_navn ikke ekskluderet'; END IF;
  -- (d) kun-visning-ændring logges IKKE
  UPDATE person SET visning_navn='__x__' WHERE id=(ev.row_pk->>'id')::bigint;
  IF (SELECT count(*) FROM change_event WHERE change_set_id=cs AND tabel='person') <> 1 THEN
    RAISE EXCEPTION 'FEJL: kun-cache-ændring blev logget'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';  -- rul alt tilbage (vi muterede rigtige rækker)
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: log_change logger korrekt (rullet tilbage)';
    ELSE RAISE; END IF;
END $$;
