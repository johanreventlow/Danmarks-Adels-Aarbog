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
                 AND skip_cols @> ARRAY['visning_navn','visning_foedt','visning_doed','visning_titel',
                                         'visning_efternavn','visning_fuldt_navn']) THEN
    RAISE EXCEPTION 'FEJL: person visning_* (inkl. udledt-slægtsnavn-kolonnerne) ikke i skip_cols';
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

-- ===== Versionering Task 5: RPC-wiring =====
DO $$
DECLARE r jsonb; cs bigint; n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','__verify__',NULL,NULL,NULL,NULL,'testkilde');
  -- find seneste change_set og tæl events (fact+assertion+citation+conclusion = 4)
  SELECT max(id) INTO cs FROM change_set;
  SELECT count(*) INTO n FROM change_event WHERE change_set_id=cs;
  IF n < 4 THEN RAISE EXCEPTION 'FEJL: red_opret_fakta grupperede ikke 4 rækker (fik %)', n; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: RPC grupperer rækker i ét change_set';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 5b: re-entrant nested wiring (red_opret_person → red_upsert_fakta) =====
-- Dækker flerlinjet-rolle-tjek-stien (red_upsert_fakta) som 5a ikke rører, og B7-re-entrancy:
-- nested red_* må IKKE åbne et nyt change_set.
DO $$
DECLARE r jsonb; v_pid bigint; cs_before bigint; cs_after bigint; n_sets int; n_person int; n_fact int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  cs_before := (SELECT coalesce(max(id),0) FROM change_set);
  v_pid := red_opret_person('__verify_person__','mand',false,'1700','1750',NULL);
  cs_after := (SELECT coalesce(max(id),0) FROM change_set);
  -- præcis ÉT nyt change_set (re-entrancy: nested red_upsert_fakta åbnede ikke flere)
  n_sets := cs_after - cs_before;
  IF n_sets <> 1 THEN RAISE EXCEPTION 'FEJL: red_opret_person åbnede % change_sets (vent 1)', n_sets; END IF;
  -- person-INSERT logget i sættet (beviser ydre begin_change_set kørte FØR person-INSERT)
  SELECT count(*) INTO n_person FROM change_event WHERE change_set_id=cs_after AND tabel='person' AND op='INSERT';
  IF n_person <> 1 THEN RAISE EXCEPTION 'FEJL: person-INSERT ikke logget (fik %)', n_person; END IF;
  -- nested red_upsert_fakta logget i SAMME sæt (beviser red_upsert_fakta-wiring kører for redaktion)
  SELECT count(*) INTO n_fact FROM change_event WHERE change_set_id=cs_after AND tabel='fact' AND op='INSERT';
  IF n_fact < 1 THEN RAISE EXCEPTION 'FEJL: nested fakta ikke logget i samme sæt (fik %)', n_fact; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: nested red_opret_person re-entrant (ét sæt, person+fakta logget)';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 6: red_edit_oplysning append =====
DO $$
DECLARE v_fact bigint; v_old bigint; v_concl_valgt bigint; n_before int; n_after int; r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','gammel',NULL,NULL,NULL,NULL,'k');
  v_old := (r->>'assertion_id')::bigint; v_fact := (r->>'fact_id')::bigint;
  SELECT count(*) INTO n_before FROM assertion WHERE target_type='fact' AND target_id=v_fact;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_edit_oplysning(v_old, 'rettet', NULL, NULL);
  SELECT count(*) INTO n_after FROM assertion WHERE target_type='fact' AND target_id=v_fact;
  IF n_after <> n_before + 1 THEN RAISE EXCEPTION 'FEJL: edit oprettede ikke ny assertion (% -> %)', n_before, n_after; END IF;
  IF NOT EXISTS (SELECT 1 FROM assertion WHERE id=v_old AND vaerdi_tekst='gammel') THEN
    RAISE EXCEPTION 'FEJL: gammel assertion blev muteret/slettet'; END IF;
  SELECT valgt_assertion_id INTO v_concl_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_fact;
  IF (SELECT vaerdi_tekst FROM assertion WHERE id=v_concl_valgt) <> 'rettet' THEN
    RAISE EXCEPTION 'FEJL: konklusion peger ikke på ny værdi'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: red_edit_oplysning er append';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 7: restore-hjælpere =====
DO $$
DECLARE v_id bigint; cur jsonb;
BEGIN
  v_id := (SELECT coalesce(max(id),0)+1 FROM note);
  PERFORM _version_upsert_row('note', jsonb_build_object('id',v_id,'target_type','person','target_id',1,'indhold','A','privat',false));
  cur := _version_current_row('note', jsonb_build_object('id',v_id));
  IF cur->>'indhold' <> 'A' THEN RAISE EXCEPTION 'FEJL: upsert insert virkede ikke'; END IF;
  PERFORM _version_upsert_row('note', jsonb_build_object('id',v_id,'target_type','person','target_id',1,'indhold','B','privat',false));
  cur := _version_current_row('note', jsonb_build_object('id',v_id));
  IF cur->>'indhold' <> 'B' THEN RAISE EXCEPTION 'FEJL: upsert update virkede ikke'; END IF;
  PERFORM _version_delete_row('note', jsonb_build_object('id',v_id));
  IF _version_current_row('note', jsonb_build_object('id',v_id)) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: delete virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: restore-hjælpere round-trip';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 8: restore =====
DO $$
DECLARE r jsonb; v_fact bigint; v_aid bigint; cs bigint; v_val text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  -- opret en oplysning (change_set #1)
  PERFORM set_config('app.change_set_id','',true);
  r := red_opret_fakta('person',(SELECT id FROM person LIMIT 1),'tilnavn','original',NULL,NULL,NULL,NULL,'k');
  v_aid := (r->>'assertion_id')::bigint; v_fact := (r->>'fact_id')::bigint;
  SELECT max(id) INTO cs FROM change_set;
  -- fortryd #1 → fact/assertion/citation/conclusion skal forsvinde igen
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  IF EXISTS (SELECT 1 FROM assertion WHERE id=v_aid) THEN
    RAISE EXCEPTION 'FEJL: restore slettede ikke den oprettede assertion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM change_set WHERE reverterer_id=cs) THEN
    RAISE EXCEPTION 'FEJL: ingen reversal-change_set oprettet'; END IF;
  -- dobbelt-fortryd af samme sæt skal afvises
  BEGIN
    PERFORM red_fortryd_change_set(cs, false);
    RAISE EXCEPTION 'FEJL: dobbelt-fortryd blev ikke afvist';
  EXCEPTION WHEN OTHERS THEN
    -- forventet: funktionen afviser med "... er allerede fortrudt" → svælg.
    -- Re-raise KUN hvis afvisningen udeblev (vores egen "blev ikke afvist"-fejl).
    IF SQLERRM LIKE '%blev ikke afvist%' THEN RAISE;
    END IF;
  END;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: restore round-trip + dobbelt-fortryd afvist';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 8b: person-slet-restore (FK-graf, H5) =====
-- Dækker H5: red_slet_person sletter børn før forælder → omvendt-seq genindsætter
-- forælder før børn (FK-sikkert). Fakta-stien (8a) rører ikke denne ordning.
DO $$
DECLARE v_pid bigint; cs_del bigint; n_facts_before int; n_facts_after int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_pid := red_opret_person('__verify_slet__','kvinde',false,'1600','1660','Fru');
  SELECT count(*) INTO n_facts_before FROM fact WHERE subjekt_type='person' AND subjekt_id=v_pid;
  -- slet personen (eget change_set)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_person(v_pid);
  SELECT max(id) INTO cs_del FROM change_set;
  IF EXISTS (SELECT 1 FROM person WHERE id=v_pid) THEN RAISE EXCEPTION 'FEJL: person ikke slettet'; END IF;
  -- fortryd sletningen → person + alle børn (fact/assertion/citation/conclusion) tilbage
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs_del, false);
  IF NOT EXISTS (SELECT 1 FROM person WHERE id=v_pid) THEN
    RAISE EXCEPTION 'FEJL: person ikke genskabt ved restore'; END IF;
  SELECT count(*) INTO n_facts_after FROM fact WHERE subjekt_type='person' AND subjekt_id=v_pid;
  IF n_facts_after <> n_facts_before THEN
    RAISE EXCEPTION 'FEJL: fakta ikke fuldt genskabt (% -> %)', n_facts_before, n_facts_after; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: person-slet-restore genskaber fuld FK-graf';
  ELSE RAISE; END IF;
END $$;

-- ===== Hyperlinks Task 9: parse_mentions =====
DO $$
DECLARE n int; got record;
BEGIN
  -- gyldigt token + malformet + ukendt type + escaped pipe i visningstekst
  SELECT count(*) INTO n FROM parse_mentions(
    'Se [[person:482|Chr. D. Reventlow]] og [[estate:7|Christianssæde]]. '
    || 'Malformet [[person:abc|x]] ukendt [[ufo:1|y]] escaped [[person:9|a\|b]].');
  IF n <> 3 THEN RAISE EXCEPTION 'FEJL: forventede 3 gyldige mentions, fik %', n; END IF;
  IF NOT EXISTS (SELECT 1 FROM parse_mentions('[[person:482|x]]') WHERE maal_type='person' AND maal_id=482) THEN
    RAISE EXCEPTION 'FEJL: token ikke parset korrekt'; END IF;
  RAISE NOTICE 'OK: parse_mentions';
END $$;

-- ===== Hyperlinks Task 10: text_mention =====
DO $$
DECLARE v_nid bigint; n int;
BEGIN
  PERFORM set_config('app.change_set_id','',true);  -- bulk-sti, ingen versionering af testdata
  v_nid := (SELECT coalesce(max(id),0)+1 FROM narrative);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst)
    VALUES (v_nid,'person',1,'[[person:1|a]] og [[person:1|igen]] og [[estate:2|g]]');
  SELECT count(*) INTO n FROM text_mention WHERE kilde_type='narrative' AND kilde_id=v_nid;
  IF n <> 2 THEN RAISE EXCEPTION 'FEJL: forventede 2 dedup-mentions, fik %', n; END IF;  -- person:1 dedup
  UPDATE narrative SET tekst='[[lineage:5|x]]' WHERE id=v_nid;  -- replace
  SELECT count(*) INTO n FROM text_mention WHERE kilde_type='narrative' AND kilde_id=v_nid;
  IF n <> 1 OR NOT EXISTS (SELECT 1 FROM text_mention WHERE kilde_id=v_nid AND maal_type='lineage') THEN
    RAISE EXCEPTION 'FEJL: replace-semantik virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: text_mention dedup + replace';
  ELSE RAISE; END IF;
END $$;

-- ===== Task 11: historik-RLS + døde links =====
DO $$
DECLARE n int;
BEGIN
  IF to_regclass('public.red_doede_links') IS NULL THEN
    RAISE EXCEPTION 'FEJL: red_doede_links view mangler'; END IF;
  -- hist_for_subjekt skal RAISE for ikke-redaktion (SQL Editor = medlem)
  BEGIN
    PERFORM * FROM hist_for_subjekt('person', 1);
    RAISE EXCEPTION 'FEJL: hist_for_subjekt tillod ikke-redaktion';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;  -- vores assert-fejl propagerer
  END;
  RAISE NOTICE 'OK: historik-API redaktion-gated + døde-links-view findes';
END $$;

-- ===== Versionering Task 7b: composite-PK restore-hjælpere (B11/M2) =====
-- T7 dækkede kun enkelt-id (note). Her: family_member (3-kol PK) gennem alle tre
-- helper-stier — fanger ON CONFLICT-constraint-match + multi-kolonne WHERE-cast.
DO $$
DECLARE cur jsonb; pk jsonb := jsonb_build_object('family_id',1,'person_id',1,'rolle','__verify_fm__');
BEGIN
  PERFORM _version_upsert_row('family_member',
    jsonb_build_object('family_id',1,'person_id',1,'rolle','__verify_fm__','ordinal',9,'konfidens','sikker'));
  cur := _version_current_row('family_member', pk);
  IF cur->>'konfidens' <> 'sikker' THEN RAISE EXCEPTION 'FEJL: composite upsert-insert virkede ikke (%)', cur; END IF;
  -- update via ON CONFLICT (samme composite-nøgle)
  PERFORM _version_upsert_row('family_member',
    jsonb_build_object('family_id',1,'person_id',1,'rolle','__verify_fm__','ordinal',9,'konfidens','formodet'));
  cur := _version_current_row('family_member', pk);
  IF cur->>'konfidens' <> 'formodet' THEN RAISE EXCEPTION 'FEJL: composite upsert-update virkede ikke (%)', cur; END IF;
  PERFORM _version_delete_row('family_member', pk);
  IF _version_current_row('family_member', pk) IS NOT NULL THEN RAISE EXCEPTION 'FEJL: composite delete virkede ikke'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: composite-PK restore-hjælpere round-trip';
  ELSE RAISE; END IF;
END $$;

-- ===== Versionering Task 8c: non-person restore (tom v_pids — regen-loop no-op) =====
-- Alle øvrige restore-asserts rørte en person. Her: undo en kilde-oprettelse (ingen person,
-- ingen conclusion) → v_pids tom → FOREACH IN ARRAY NULL skal være no-op, ikke fejle.
DO $$
DECLARE v_sid bigint; cs bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_sid := red_opret_kilde('__verify_kilde__', NULL, NULL, false);
  SELECT max(id) INTO cs FROM change_set;
  IF NOT EXISTS (SELECT 1 FROM source WHERE id=v_sid) THEN RAISE EXCEPTION 'FEJL: kilde ikke oprettet'; END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  IF EXISTS (SELECT 1 FROM source WHERE id=v_sid) THEN RAISE EXCEPTION 'FEJL: non-person restore slettede ikke kilden'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: non-person restore (tom regen-loop) virker';
  ELSE RAISE; END IF;
END $$;

-- ===== Review 09 H1: DELETE-inverse divergens-tjek (PK-genbrug) =====
-- Bekræfter at restore afviser når en slettet PK er genbrugt af en fremmed række
-- (uden force), og kun overskriver med force. Ville have fanget review09 H1.
DO $$
DECLARE v_nid bigint; cs bigint; cur text; afvist boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_nid := (SELECT coalesce(max(id),0)+1 FROM note);
  cs := (SELECT coalesce(max(id),0)+1 FROM change_set);
  INSERT INTO change_set(id,operation,summary,subjekt_synlighed) VALUES (cs,'t','slet note','offentlig');
  INSERT INTO change_event(id,change_set_id,seq,tabel,row_pk,op,foer,efter)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM change_event), cs, 1, 'note',
            jsonb_build_object('id',v_nid),'DELETE',
            jsonb_build_object('id',v_nid,'target_type','person','target_id',1,'indhold','GAMMEL','privat',false), NULL);
  INSERT INTO note(id,target_type,target_id,indhold,privat) VALUES (v_nid,'person',1,'FREMMED-NY',false);
  -- uden force: skal afvise
  BEGIN PERFORM red_fortryd_change_set(cs, false);
  EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%nyere ændring rører%' THEN afvist := true; ELSE RAISE; END IF; END;
  IF NOT afvist THEN RAISE EXCEPTION 'FEJL: DELETE-inverse afviste ikke PK-genbrug'; END IF;
  IF (SELECT indhold FROM note WHERE id=v_nid) <> 'FREMMED-NY' THEN
    RAISE EXCEPTION 'FEJL: fremmed række blev rørt trods afvisning'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review09 H1 — DELETE-inverse afviser PK-genbrug';
  ELSE RAISE; END IF;
END $$;

-- ===== Review 09 H2: restore bevarer skip_cols (profiles email/rolle) =====
-- End-to-end: slet en profil-bundet person, fortryd → profilen genskabes med
-- rolle/email intakt (ikke NULL-crash). Ville have fanget review09 H2.
DO $$
DECLARE v_uid uuid := '00000000-0000-0000-0000-000000000077'; v_pid bigint; cs bigint; r_after text; e_after text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);
  v_pid := red_opret_person('__verify_h2__','mand',false,NULL,NULL,NULL);
  -- bind en profil til personen
  INSERT INTO auth.users(id,email) VALUES (v_uid,'medlem@x') ON CONFLICT DO NOTHING;
  INSERT INTO profiles(id,rolle,email,reventlow_person_id) VALUES (v_uid,'medlem','medlem@x',v_pid)
    ON CONFLICT (id) DO UPDATE SET rolle='medlem', email='medlem@x', reventlow_person_id=v_pid;
  -- slet personen (nulstiller profiles.reventlow_person_id → logget UPDATE)
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_slet_person(v_pid);
  SELECT max(id) INTO cs FROM change_set;
  -- fortryd → må IKKE crashe på rolle NOT NULL, og skal bevare email/rolle
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  SELECT rolle, email INTO r_after, e_after FROM profiles WHERE id=v_uid;
  IF r_after IS NULL OR e_after IS NULL THEN
    RAISE EXCEPTION 'FEJL: restore nulstillede skip_cols (rolle=%, email=%)', r_after, e_after; END IF;
  IF (SELECT reventlow_person_id FROM profiles WHERE id=v_uid) <> v_pid THEN
    RAISE EXCEPTION 'FEJL: reventlow_person_id ikke genskabt'; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: review09 H2 — restore bevarer profiles skip_cols';
  ELSE RAISE; END IF;
END $$;

-- ===== samme_som redaktionel identitets-sammenkædning (spec 2026-07-02) =====
-- End-to-end: red_samme_som skaber relation+assertion+afklaret-conclusion; idempotent; triggeren
-- afviser G3 multi-sink; red_fjern_samme_som fjerner al evidens. Ruller tilbage.
DO $$
DECLARE a bigint; b bigint; c bigint; rel bigint; rel2 bigint; n_ass int; n_con int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true); a := red_opret_person('__ss_a__','mand',false,NULL,NULL,NULL);
  PERFORM set_config('app.change_set_id','',true); b := red_opret_person('__ss_b__','mand',false,NULL,NULL,NULL);
  PERFORM set_config('app.change_set_id','',true); c := red_opret_person('__ss_c__','mand',false,NULL,NULL,NULL);
  -- opret a→b
  PERFORM set_config('app.change_set_id','',true); rel := red_samme_som(a,b);
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=rel AND rolle='samme_som' AND subjekt_id=a AND objekt_id=b) THEN
    RAISE EXCEPTION 'FEJL: samme_som-relation ikke oprettet'; END IF;
  SELECT count(*) INTO n_con FROM conclusion WHERE target_type='relation' AND target_id=rel AND status='afklaret';
  IF n_con <> 1 THEN RAISE EXCEPTION 'FEJL: afklaret conclusion mangler (n=%)', n_con; END IF;
  -- idempotens: samme retning → samme id
  PERFORM set_config('app.change_set_id','',true); rel2 := red_samme_som(a,b);
  IF rel2 <> rel THEN RAISE EXCEPTION 'FEJL: idempotens brudt (% <> %)', rel2, rel; END IF;
  -- G3 multi-sink: a→c skal afvises af triggeren
  BEGIN
    PERFORM set_config('app.change_set_id','',true); PERFORM red_samme_som(a,c);
    RAISE EXCEPTION 'FEJL: G3 multi-sink accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;
    IF SQLERRM !~* 'multi-sink' THEN RAISE EXCEPTION 'FEJL: forkert afvisning: %', SQLERRM; END IF;
  END;
  -- fjern → al evidens væk
  PERFORM set_config('app.change_set_id','',true); PERFORM red_fjern_samme_som(rel);
  SELECT count(*) INTO n_ass FROM assertion WHERE target_type='relation' AND target_id=rel;
  SELECT count(*) INTO n_con FROM conclusion WHERE target_type='relation' AND target_id=rel;
  IF n_ass <> 0 OR n_con <> 0 OR EXISTS(SELECT 1 FROM relation WHERE id=rel) THEN
    RAISE EXCEPTION 'FEJL: fjern efterlod evidens (ass=%, con=%)', n_ass, n_con; END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN RAISE NOTICE 'OK: samme_som — opret/idempotens/G3-multi-sink/fjern virker';
  ELSE RAISE; END IF;
END $$;

-- Task: flere narrativer pr. person (2026-07-03) — skema-shape
DO $$ BEGIN
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name='source' AND column_name='aar')<>1 THEN
    RAISE EXCEPTION 'FEJL: source.aar mangler'; END IF;
  IF (SELECT count(*) FROM information_schema.parameters
      WHERE specific_name IN (SELECT specific_name FROM information_schema.routines WHERE routine_name='red_upsert_narrativ')
        AND parameter_name='p_source_id')<>1 THEN
    RAISE EXCEPTION 'FEJL: red_upsert_narrativ mangler p_source_id'; END IF;
  IF (SELECT count(*) FROM information_schema.parameters
      WHERE specific_name IN (SELECT specific_name FROM information_schema.routines WHERE routine_name='red_opret_kilde')
        AND parameter_name='p_aar')<>1 THEN
    RAISE EXCEPTION 'FEJL: red_opret_kilde mangler p_aar'; END IF;
  RAISE NOTICE 'OK: flere-narrativer skema (source.aar, red_upsert_narrativ.p_source_id, red_opret_kilde.p_aar)';
END $$;

-- ===== Udledt slægtsnavn Task 1: lineage-graf-walkers + cyklus-vagt =====
DO $$
DECLARE v_anc BIGINT[];
BEGIN
  IF to_regprocedure('lineage_ancestors(bigint)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: lineage_ancestors mangler';
  END IF;
  IF to_regprocedure('lineage_descendants(bigint)') IS NULL THEN
    RAISE EXCEPTION 'FEJL: lineage_descendants mangler';
  END IF;
  SELECT lineage_ancestors(id) INTO v_anc FROM lineage WHERE kode='I' LIMIT 1;
  IF v_anc IS NULL OR array_length(v_anc,1) <> 1 THEN
    RAISE EXCEPTION 'FEJL: lineage_ancestors(I) skal returnere præcis [sig selv] uden forgrening, fik %', v_anc;
  END IF;
  RAISE NOTICE 'OK: lineage_ancestors basal';
END $$;

DO $$
DECLARE v_a BIGINT; v_b BIGINT; v_source BIGINT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_a := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn) VALUES (v_a, v_source, '__TEST_A', 'Test A');
  v_b := v_a + 1;
  INSERT INTO lineage(id, source_id, kode, navn, parent_lineage_id) VALUES (v_b, v_source, '__TEST_B', 'Test B', v_a);
  BEGIN
    UPDATE lineage SET parent_lineage_id = v_b WHERE id = v_a;  -- ville lukke løkken A→B→A
    RAISE EXCEPTION 'FEJL: cyklus A→B→A blev IKKE afvist';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE '%cyklus%' THEN RAISE; END IF;
    RAISE NOTICE 'OK: cyklus A→B→A korrekt afvist (%)', SQLERRM;
  END;
  DELETE FROM lineage WHERE id IN (v_a, v_b);
END $$;

-- ===== Udledt slægtsnavn Task 2: nye kolonner + skip-liste =====
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lineage' AND column_name='slaegtsnavn') THEN
    RAISE EXCEPTION 'FEJL: lineage.slaegtsnavn mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='person' AND column_name='visning_efternavn') THEN
    RAISE EXCEPTION 'FEJL: person.visning_efternavn mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='person' AND column_name='visning_fuldt_navn') THEN
    RAISE EXCEPTION 'FEJL: person.visning_fuldt_navn mangler';
  END IF;
  RAISE NOTICE 'OK: udledt-slægtsnavn nye kolonner';
END $$;

-- ===== Udledt slægtsnavn Task 3: normalisering + suffiks-match (spec §4.6, 5 eksempler) =====
DO $$
BEGIN
  IF NOT slaegtsnavn_suffiks_match('Detlef von Reventlow', 'Reventlow') THEN
    RAISE EXCEPTION 'FEJL: "Detlef von Reventlow" burde matche "Reventlow" (partikel)';
  END IF;
  IF slaegtsnavn_suffiks_match('X Ahlefeldt', 'Ahlefeldt-Laurvig-Lehn') THEN
    RAISE EXCEPTION 'FEJL: "X Ahlefeldt" må IKKE matche "Ahlefeldt-Laurvig-Lehn" (rod ≠ gren-variant)';
  END IF;
  IF NOT slaegtsnavn_suffiks_match('X Ahlefeldt', 'Ahlefeldt') THEN
    RAISE EXCEPTION 'FEJL: "X Ahlefeldt" burde matche rod "Ahlefeldt"';
  END IF;
  IF slaegtsnavn_suffiks_match('Anna Reventlow Hansen', 'Reventlow') THEN
    RAISE EXCEPTION 'FEJL: "Anna Reventlow Hansen" må IKKE matche (Reventlow er mellemnavn, ikke suffiks)';
  END IF;
  IF NOT slaegtsnavn_suffiks_match('X von Brockdorff', 'von Brockdorff') THEN
    RAISE EXCEPTION 'FEJL: "X von Brockdorff" burde matche fler-ords-efternavnet "von Brockdorff"';
  END IF;
  RAISE NOTICE 'OK: suffiks-token-match (5/5 spec-eksempler)';
END $$;

-- ===== Udledt slægtsnavn Task 4: regen_person_visning-udvidelse =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_efternavn TEXT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_lineage, v_source, '__TEST_L', 'Test-linje', 'Reventlow');

  -- (a) enkelt-fornavn, født medlem uden efternavn i visning_navn
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Conrad');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_L', 999);
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn <> 'Reventlow' OR v_fuldt <> 'Conrad Reventlow' THEN
    RAISE EXCEPTION 'FEJL: (a) enkelt-fornavn — fik efternavn=% fuldt=%', v_efternavn, v_fuldt;
  END IF;

  -- (d) allerede indeholder efternavnet → NULL, uændret visning_navn
  UPDATE person SET visning_navn = 'Detlef von Reventlow' WHERE id=v_p;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL OR v_fuldt <> 'Detlef von Reventlow' THEN
    RAISE EXCEPTION 'FEJL: (d) allerede-Reventlow skal give NULL efternavn, fik % / %', v_efternavn, v_fuldt;
  END IF;

  -- (e) indgift-ægtefælle uden external_id → NULL
  DELETE FROM person_external_id WHERE person_id=v_p;
  UPDATE person SET visning_navn='Anna Ingift' WHERE id=v_p;
  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn, visning_fuldt_navn INTO v_efternavn, v_fuldt FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL OR v_fuldt <> 'Anna Ingift' THEN
    RAISE EXCEPTION 'FEJL: (e) indgift skal give NULL efternavn, fik % / %', v_efternavn, v_fuldt;
  END IF;

  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: regen_person_visning — (a)/(d)/(e) scenarier';
END $$;

-- Fan-out → karantæne (to distinkte linjer/sources, to distinkte efternavne)
DO $$
DECLARE v_source BIGINT; v_source2 BIGINT; v_l1 BIGINT; v_l2 BIGINT; v_l3 BIGINT; v_p BIGINT; v_efternavn TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_l1 := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l1, v_source, '__TEST_FO1', 'A', 'Alfa');
  v_l2 := v_l1 + 1;
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l2, v_source, '__TEST_FO2', 'B', 'Beta');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Fanout Person');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_FO1', 1);

  v_source2 := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel) VALUES (v_source2, 'DAA-udgave', 'Test-udgave 2');
  v_l3 := v_l2 + 1;
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l3, v_source2, '__TEST_FO2', 'B2', 'Beta');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source2, '__TEST_FO2', 1);

  PERFORM regen_person_visning(v_p);
  SELECT visning_efternavn INTO v_efternavn FROM person WHERE id=v_p;
  IF v_efternavn IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: fan-out (2 distinkte efternavne) skal give NULL, fik %', v_efternavn;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL: fan-out skal logges i slaegtsnavn_karantaene';
  END IF;
  PERFORM regen_person_visning(v_p);  -- idempotens: karantæne-rækken må ikke duplikeres
  IF (SELECT count(*) FROM slaegtsnavn_karantaene WHERE person_id=v_p) <> 1 THEN
    RAISE EXCEPTION 'FEJL: karantæne-log er ikke idempotent (upsert)';
  END IF;

  DELETE FROM slaegtsnavn_karantaene WHERE person_id=v_p;
  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id IN (v_l1, v_l2, v_l3);
  DELETE FROM source WHERE id=v_source2;
  RAISE NOTICE 'OK: fan-out → karantæne + idempotens';
END $$;

-- ===== Udledt slægtsnavn Task 5: invalidation-triggere (person_external_id + lineage) =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_lineage, v_source, '__TEST_TRG', 'Trigger-test', 'Testnavn');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Trigger Person');

  -- INSERT på person_external_id skal regenerere UDEN eksplicit regen-kald
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_TRG', 1);
  SELECT visning_fuldt_navn INTO v_fuldt FROM person WHERE id=v_p;
  IF v_fuldt <> 'Trigger Person Testnavn' THEN
    RAISE EXCEPTION 'FEJL: person_external_id-INSERT trigger regen ikke, fik fuldt_navn=%', v_fuldt;
  END IF;

  -- UPDATE på lineage.slaegtsnavn skal regenerere undertræets medlemmer UDEN eksplicit regen-kald
  UPDATE lineage SET slaegtsnavn = 'Nytnavn' WHERE id = v_lineage;
  SELECT visning_fuldt_navn INTO v_fuldt FROM person WHERE id=v_p;
  IF v_fuldt <> 'Trigger Person Nytnavn' THEN
    RAISE EXCEPTION 'FEJL: lineage.slaegtsnavn-UPDATE trigger ikke subtræ-regen, fik fuldt_navn=%', v_fuldt;
  END IF;

  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: invalidation-triggere (person_external_id + lineage)';
END $$;

-- ===== Review 19 H1: frisk lineage-INSERT (ikke kun UPDATE) trigger regen =====
DO $$
DECLARE v_source BIGINT; v_lineage BIGINT; v_p BIGINT; v_fuldt TEXT;
BEGIN
  SELECT id INTO v_source FROM source LIMIT 1;
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'Frisk Insert Person');
  v_lineage := (SELECT coalesce(max(id),0)+1 FROM lineage);
  -- external_id INDSAT FØR lineage-rækken findes (matcher load_daa.R → post_load_fixup.R-rækkefølgen).
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_H1', 1);
  -- fresh INSERT (ikke UPDATE) på lineage — skal ALENE trigge regen af v_p uden noget eksplicit kald.
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_lineage, v_source, '__TEST_H1', 'H1-test', 'Insertnavn');
  SELECT visning_fuldt_navn INTO v_fuldt FROM person WHERE id=v_p;
  IF v_fuldt <> 'Frisk Insert Person Insertnavn' THEN
    RAISE EXCEPTION 'FEJL (review19 H1): lineage-INSERT trigger ikke regen, fik fuldt_navn=%', v_fuldt;
  END IF;
  DELETE FROM person_external_id WHERE person_id=v_p;
  DELETE FROM person WHERE id=v_p;
  DELETE FROM lineage WHERE id=v_lineage;
  RAISE NOTICE 'OK: review19 H1 — frisk lineage-INSERT trigger regen';
END $$;

-- ===== Review 19 H2: red_slet_person for en karantæneret person =====
DO $$
DECLARE v_source BIGINT; v_source2 BIGINT; v_l1 BIGINT; v_l2 BIGINT; v_p BIGINT; v_uid UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
  INSERT INTO profiles(id, rolle, email) VALUES (v_uid,'redaktion','t@x') ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  SELECT id INTO v_source FROM source LIMIT 1;
  v_l1 := (SELECT coalesce(max(id),0)+1 FROM lineage);
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l1, v_source, '__TEST_H2A', 'A', 'Alfa');
  v_source2 := (SELECT coalesce(max(id),0)+1 FROM source);
  INSERT INTO source(id, slags, titel) VALUES (v_source2, 'DAA-udgave', 'Test-udgave H2');
  v_l2 := v_l1 + 1;
  INSERT INTO lineage(id, source_id, kode, navn, slaegtsnavn) VALUES (v_l2, v_source2, '__TEST_H2B', 'B', 'Beta');
  v_p := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, visning_navn) VALUES (v_p, 'H2 Karantæne Person');
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source, '__TEST_H2A', 1);
  INSERT INTO person_external_id(person_id, source_id, linje, nr) VALUES (v_p, v_source2, '__TEST_H2B', 1);
  PERFORM regen_person_visning(v_p);
  IF NOT EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL (review19 H2 setup): person burde være i karantæne';
  END IF;
  -- red_slet_person MÅ IKKE fejle (FK-violation) selvom personen er i karantæne.
  PERFORM red_slet_person(v_p);
  IF EXISTS (SELECT 1 FROM person WHERE id=v_p) OR EXISTS (SELECT 1 FROM slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'FEJL (review19 H2): red_slet_person efterlod rester for en karantæneret person';
  END IF;
  DELETE FROM lineage WHERE id IN (v_l1, v_l2);
  DELETE FROM source WHERE id=v_source2;
  RAISE NOTICE 'OK: review19 H2 — red_slet_person virker for karantæneret person';
END $$;
