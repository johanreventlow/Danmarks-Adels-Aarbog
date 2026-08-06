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

-- ===== Person OCR kvalitetsark — atomisk rettelse og historik =====
-- Selvstændig transaktionsfixture. Alle positive og negative veje kører gennem
-- den offentlige SECURITY DEFINER-flade, og blokken ruller altid tilbage.
DO $$
DECLARE
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000c4';
  v_row jsonb; v_hist record; v_cs_date bigint; v_journal_id bigint;
  v_name_assertion bigint := -987655301; v_birth_assertion bigint := -987655302;
  v_death_assertion bigint := -987655303; v_citation_id bigint := -987655501;
  v_before_journal int; v_before_events int; v_before_assertions int;
  v_before_conclusions int; v_before_name text; v_before_gender text; v_koen_fingerprint text;
  v_fresh_fingerprint text; v_frozen_fingerprint text; v_name_events int; v_name_history int;
  v_member_blocked boolean := false; v_anon_blocked boolean := false;
  v_hist_member_blocked boolean := false; v_hist_anon_blocked boolean := false;
  v_hist_count int; v_first_after jsonb; v_second_after jsonb;
  v_original_import jsonb;
BEGIN
  INSERT INTO source(id,titel,import_key) VALUES
    (-987655101,'OCR rette-fixture','verify:ocr:write'),
    (-987655102,'Forkert OCR-kilde','verify:ocr:other'),
    (-987655103,'Ekstra importanker','verify:ocr:extra');
  INSERT INTO person(id,koen) VALUES
    (-987655111,'mand'), (-987655112,'kvinde'), (-987655113,'mand'),
    (-987655114,'ukendt');
  INSERT INTO person_external_id(person_id,source_id,record_key) VALUES
    (-987655111,-987655101,'I-15a'),
    (-987655112,-987655101,'I-16'),
    (-987655113,-987655101,'I-17'),
    (-987655113,-987655103,'I-17-extra'),
    (-987655114,-987655101,'I-18');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987655201,'person',-987655111,'navn'),
    (-987655202,'person',-987655111,'fødsel'),
    (-987655203,'person',-987655111,'død'),
    (-987655204,'person',-987655112,'navn'),
    (-987655205,'person',-987655114,'navn'),
    (-987655206,'person',-987655114,'navn');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_raw,date_min,date_max,
                        date_qualifier,calendar,date_certainty,uforanderlig) VALUES
    (v_name_assertion,'fact',-987655201,'Mikkel OCR',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true),
    (v_birth_assertion,'fact',-987655202,NULL,'1644-06-11','1644-06-11','1644-06-11','exact','gregoriansk',NULL,true),
    (v_death_assertion,'fact',-987655203,NULL,'1700-01-01','1700-01-01','1700-01-01','exact','gregoriansk',NULL,true),
    (-987655304,'fact',-987655204,'Forkert kilde',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true),
    (-987655305,'fact',-987655205,'Flertydig A',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true),
    (-987655306,'fact',-987655206,'Flertydig B',NULL,NULL,NULL,NULL,'gregoriansk',NULL,true);
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987655401,'fact',-987655201,v_name_assertion,'afklaret'),
    (-987655402,'fact',-987655202,v_birth_assertion,'afklaret'),
    (-987655403,'fact',-987655203,v_death_assertion,'afklaret'),
    (-987655404,'fact',-987655204,-987655304,'afklaret'),
    (-987655405,'fact',-987655205,-987655305,'afklaret');
  -- A second selected fact makes the fourth person fail closed as ambiguous.
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status)
    VALUES (-987655406,'fact',-987655206,-987655306,'afklaret');
  INSERT INTO citation(id,assertion_id,source_id,side,citat_tekst) VALUES
    (v_citation_id,v_name_assertion,-987655101,'42','Mikkel OCR'),
    (-987655502,v_birth_assertion,-987655101,'42','født 1644-06-11'),
    (-987655503,v_death_assertion,-987655101,'42','død 1700-01-01'),
    (-987655504,-987655304,-987655102,'42','Forkert kilde'),
    (-987655505,-987655305,-987655101,'42','Flertydig A'),
    (-987655506,-987655306,-987655101,'42','Flertydig B');

  -- Fixed SQL vector is independent of the new helper and must remain in Task 2 parity.
  IF ocr_input_fingerprint('verify:ocr:write','I-15a','foedsel',
       '{"raw":"1644-06-11","min":"1644-06-11","max":"1644-06-11","qualifier":"exact","calendar":"gregoriansk","certainty":null}'::jsonb,
       'født 1644-06-11') IS NULL THEN
    RAISE EXCEPTION 'FEJL: OCR-fingerprint-vektor kunne ikke beregnes';
  END IF;

  -- Execute ACL and internal role guards are independently observable.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn','x',NULL,'godkendt');
  EXCEPTION WHEN insufficient_privilege THEN v_anon_blocked := true;
  END;
  BEGIN
    PERFORM * FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  EXCEPTION WHEN insufficient_privilege THEN v_hist_anon_blocked := true;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn','x',NULL,'godkendt');
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'OCR_ROLE_FORBIDDEN%' THEN v_member_blocked := true; ELSE RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'OCR_ROLE_FORBIDDEN%' THEN v_hist_member_blocked := true; ELSE RAISE; END IF;
  END;
  RESET ROLE;
  IF NOT v_anon_blocked OR NOT v_hist_anon_blocked OR NOT v_member_blocked OR NOT v_hist_member_blocked THEN
    RAISE EXCEPTION 'FEJL: OCR-RPC ACL/rolle-gate anon=%/% medlem=%/%',
      v_anon_blocked,v_hist_anon_blocked,v_member_blocked,v_hist_member_blocked;
  END IF;

  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'ocr-write-verify@test.invalid');
  INSERT INTO profiles(id,rolle,navn,email) VALUES
    (v_redaktor,'redaktion','OCR Verify Actor','ocr-write-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_redaktor::text,true);
  SET LOCAL ROLE authenticated;

  -- First and repeated name correction: one logical journal row keeps original import/fingerprint.
  SELECT input_fingerprint->>'navn', importeret->'navn' INTO STRICT v_before_name, v_original_import
    FROM red_person_grid() WHERE person_id=-987655111;
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',v_before_name,
    '{"value":"Mikkel Rettet"}'::jsonb,'rettet','må ikke vinde');
  IF v_row->>'person_id' <> '-987655111' OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet' THEN
    RAISE EXCEPTION 'FEJL: navnerettelse returnerede ikke den friske, rettede række';
  END IF;
  SELECT id INTO v_journal_id FROM import_korrektion
    WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='navn';
  IF v_journal_id IS NULL OR (SELECT actor_id FROM import_korrektion WHERE id=v_journal_id) <> v_redaktor
     OR (SELECT actor_navn FROM import_korrektion WHERE id=v_journal_id) <> 'OCR Verify Actor' THEN
    RAISE EXCEPTION 'FEJL: navnejournal mangler autentisk aktør';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',v_before_name,
    '{"value":"Mikkel Rettet Igen"}'::jsonb,'rettet','fallback');
  IF (SELECT count(*) FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='navn') <> 1
     OR (SELECT id FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='navn') <> v_journal_id
     OR (SELECT importeret FROM import_korrektion WHERE id=v_journal_id) <> v_original_import
     OR (SELECT korrigeret FROM import_korrektion WHERE id=v_journal_id) <> '{"value":"Mikkel Rettet Igen"}'::jsonb
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet Igen' THEN
    RAISE EXCEPTION 'FEJL: gentagen OCR-rettelse drev import-snapshot eller journalidentitet';
  END IF;
  SELECT input_fingerprint INTO v_frozen_fingerprint FROM import_korrektion WHERE id=v_journal_id;
  IF v_frozen_fingerprint <> v_before_name THEN
    RAISE EXCEPTION 'FEJL: gentagen OCR-rettelse ændrede frosset source-fingerprint';
  END IF;
  -- A newly projected fingerprint after source-context drift must not bless a stale journal.
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  UPDATE citation SET citat_tekst='Mikkel OCR ændret kildekontekst' WHERE id=v_citation_id;
  SET LOCAL ROLE authenticated;
  SELECT input_fingerprint->>'navn' INTO v_fresh_fingerprint FROM red_person_grid() WHERE person_id=-987655111;
  RESET ROLE;
  SELECT count(*) INTO v_name_events FROM change_event;
  SELECT count(*) INTO v_name_history FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  BEGIN
    PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',v_fresh_fingerprint,
      '{"value":"må ikke gemmes"}'::jsonb);
    RAISE EXCEPTION 'FEJL: frisk fingerprint efter kildeændring blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_FINGERPRINT_STALE%' THEN RAISE; END IF; END;
  IF (SELECT input_fingerprint FROM import_korrektion WHERE id=v_journal_id) <> v_frozen_fingerprint
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet Igen'
     OR (SELECT count(*) FROM change_event) <> v_name_events
     OR (SELECT count(*) FROM red_ocr_historik('verify:ocr:write','I-15a','navn')) <> v_name_history THEN
    RAISE EXCEPTION 'FEJL: stale kildekontekst ændrede journal, model eller historik';
  END IF;
  IF EXISTS (SELECT 1 FROM assertion WHERE id NOT IN (v_name_assertion,v_birth_assertion,v_death_assertion,-987655304,-987655305,-987655306)
             AND target_id IN (-987655201,-987655202,-987655203))
     OR (SELECT count(*) FROM conclusion WHERE target_id IN (-987655201,-987655202,-987655203)) <> 3
     OR (SELECT source_id FROM citation WHERE id=v_citation_id) <> -987655101
     OR NOT (SELECT uforanderlig FROM assertion WHERE id=v_name_assertion) THEN
    RAISE EXCEPTION 'FEJL: OCR-navnerettelse ændrede evidensidentitet';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  -- Date touches only the one selected assertion's date fields, and the normal trigger regenerates the cache.
  SELECT input_fingerprint->>'foedsel' INTO STRICT v_before_name FROM red_person_grid() WHERE person_id=-987655111;
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','foedsel',v_before_name,
    '{"raw":"1644-06-12","min":"1644-06-12","max":"1644-06-12","qualifier":"exact","calendar":"gregoriansk","certainty":null}'::jsonb);
  v_cs_date := current_setting('app.change_set_id')::bigint;
  IF (SELECT date_raw FROM assertion WHERE id=v_birth_assertion) <> '1644-06-12'
     OR (SELECT date_min FROM assertion WHERE id=v_birth_assertion) <> date '1644-06-12'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_birth_assertion) IS NOT NULL
     OR (SELECT date_raw FROM assertion WHERE id=v_death_assertion) <> '1700-01-01' THEN
    RAISE EXCEPTION 'FEJL: datorettelse ramte ikke kun den valgte assertion';
  END IF;
  PERFORM red_fortryd_change_set(v_cs_date,false);
  IF (SELECT date_raw FROM assertion WHERE id=v_birth_assertion) <> '1644-06-11'
     OR EXISTS (SELECT 1 FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='foedsel') THEN
    RAISE EXCEPTION 'FEJL: fortryd genskabte ikke OCR-dato og journal';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  -- Gender is the sole model mutation for gender; approve/defer never mutate the model.
  SELECT input_fingerprint->>'koen', koen INTO STRICT v_before_name,v_before_gender FROM red_person_grid() WHERE person_id=-987655111;
  v_row := red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_before_name,
    '{"value":"kvinde"}'::jsonb);
  IF (SELECT koen FROM person WHERE id=-987655111) <> 'kvinde'
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> 'Mikkel Rettet Igen' THEN
    RAISE EXCEPTION 'FEJL: kønsrettelse rørte andet end person.koen';
  END IF;
  SELECT input_fingerprint->>'koen' INTO STRICT v_before_name FROM red_person_grid() WHERE person_id=-987655111;
  PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_before_name,NULL,'godkendt');
  PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_before_name,NULL,'udskudt');
  IF (SELECT koen FROM person WHERE id=-987655111) <> 'kvinde'
     OR (SELECT status FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='koen') <> 'udskudt'
     OR (SELECT korrigeret FROM import_korrektion WHERE import_key='verify:ocr:write' AND record_key='I-15a' AND felt='koen') <> '{"value":"kvinde"}'::jsonb THEN
    RAISE EXCEPTION 'FEJL: godkend/udskyd ændrede model eller journalstatus forkert';
  END IF;

  -- History is scoped to the one logical journal PK and frozen, newest first snapshots.
  SELECT count(*) INTO v_hist_count FROM red_ocr_historik('verify:ocr:write','I-15a','navn');
  SELECT h.efter INTO v_first_after FROM red_ocr_historik('verify:ocr:write','I-15a','navn') h LIMIT 1;
  SELECT h.efter INTO v_second_after FROM red_ocr_historik('verify:ocr:write','I-15a','navn') h OFFSET 1 LIMIT 1;
  IF v_hist_count <> 2 OR v_first_after->>'korrigeret' IS NULL OR v_second_after->>'importeret' IS NULL
     OR EXISTS (SELECT 1 FROM red_ocr_historik('verify:ocr:write','I-15a','doed')) THEN
    RAISE EXCEPTION 'FEJL: OCR-historik er ikke isoleret eller komplet';
  END IF;

  -- Every negative path is atomic: counts and model values remain exactly as before.
  RESET ROLE;
  SELECT count(*) INTO v_before_journal FROM import_korrektion;
  SELECT count(*) INTO v_before_events FROM change_event;
  SELECT count(*) INTO v_before_assertions FROM assertion;
  SELECT count(*) INTO v_before_conclusions FROM conclusion;
  SELECT vaerdi_tekst INTO v_before_name FROM assertion WHERE id=v_name_assertion;
  SELECT koen INTO v_before_gender FROM person WHERE id=-987655111;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','ukendt','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: ukendt felt blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_FIELD_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen','forkert',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: stale fingerprint blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_FINGERPRINT_STALE%' THEN RAISE; END IF; END;
  SELECT input_fingerprint->>'koen' INTO v_koen_fingerprint FROM red_person_grid() WHERE person_id=-987655111;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','koen',v_koen_fingerprint,'{"value":"andet"}'::jsonb);
    RAISE EXCEPTION 'FEJL: ugyldigt køn blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_VALUE_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655111,'verify:ocr:write','I-15a','navn',(SELECT input_fingerprint->>'navn' FROM red_person_grid() WHERE person_id=-987655111),NULL);
    RAISE EXCEPTION 'FEJL: manglende rettelse blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_VALUE_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655113,'verify:ocr:write','I-17','koen','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: flere importankre blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_IMPORT_ANCHOR_AMBIGUOUS%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655114,'verify:ocr:write','I-18','navn','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: flere assertion-kandidater blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_ASSERTION_AMBIGUOUS%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_ocr_felt(-987655112,'verify:ocr:write','I-16','navn','x',NULL,'godkendt');
    RAISE EXCEPTION 'FEJL: source mismatch blev accepteret';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'OCR_ASSERTION_AMBIGUOUS%' THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM import_korrektion) <> v_before_journal
     OR (SELECT count(*) FROM change_event) <> v_before_events
     OR (SELECT count(*) FROM assertion) <> v_before_assertions
     OR (SELECT count(*) FROM conclusion) <> v_before_conclusions
     OR (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion) <> v_before_name
     OR (SELECT koen FROM person WHERE id=-987655111) <> v_before_gender THEN
    RAISE EXCEPTION 'FEJL: negativ OCR-vej var ikke atomisk journal=%/% event=%/% assertion=%/% conclusion=%/% navn=%/% koen=%/%',
      (SELECT count(*) FROM import_korrektion),v_before_journal,(SELECT count(*) FROM change_event),v_before_events,
      (SELECT count(*) FROM assertion),v_before_assertions,(SELECT count(*) FROM conclusion),v_before_conclusions,
      (SELECT vaerdi_tekst FROM assertion WHERE id=v_name_assertion),v_before_name,
      (SELECT koen FROM person WHERE id=-987655111),v_before_gender;
  END IF;
  RESET ROLE;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: Person OCR kvalitetsark — atomisk rettelse, historik, undo og roller';
  ELSE RAISE; END IF;
END $$;

-- ===== Person OCR kvalitetsark — reel to-forbindelses låseorden =====
-- dblink er bevidst kun et VERIFY-hjælpemiddel. En produktionsbase uden extension
-- springer over; den lokale disposable gate aktiverer den og kører den reelle cyklus.
DO $$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-0000000000c6';
  v_conn text := format('dbname=%s', current_database());
  v_a_busy integer;
  v_b_busy integer;
  v_a_pid integer;
  v_b_pid integer;
  v_locked bigint;
  v_result bigint;
  v_deleted bigint;
  v_deadline timestamptz;
  v_a_async boolean := false;
  v_b_async boolean := false;
  v_a_in_tx boolean := false;
  v_b_in_tx boolean := false;
  v_error_state text;
  v_error_message text;
  v_cleanup_error text;
  v_cleanup_sql text := $cleanup_sql$
    DO $remote_cleanup$
    BEGIN
      DELETE FROM change_event WHERE change_set_id IN (
        SELECT id FROM change_set
        WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-987654611
      );
      DELETE FROM change_set
        WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-987654611;
      DELETE FROM import_korrektion
        WHERE import_key='verify:ocr:lock' AND record_key='I-lock';
      DELETE FROM citation WHERE id=-987654951;
      DELETE FROM conclusion WHERE id=-987654901;
      DELETE FROM assertion WHERE id=-987654801;
      DELETE FROM fact WHERE id=-987654701;
      DELETE FROM person_external_id WHERE person_id=-987654611 AND source_id=-987654601;
      DELETE FROM profiles WHERE id='00000000-0000-0000-0000-0000000000c6';
      DELETE FROM auth.users WHERE id='00000000-0000-0000-0000-0000000000c6';
      DELETE FROM person WHERE id=-987654611;
      DELETE FROM source WHERE id=-987654601;
    END $remote_cleanup$
  $cleanup_sql$;
BEGIN
  IF to_regprocedure('public.dblink_connect(text,text)') IS NULL THEN
    RAISE NOTICE 'SKIP: OCR-låseorden kræver dblink i disposable verify-base';
    RETURN;
  END IF;
  -- Setup is committed through a third local connection: dblink sessions cannot see
  -- uncommitted rows from this verify DO-block.
  PERFORM dblink_connect('ocr_lock_setup',v_conn || ' application_name=daa_verify_ocr_lock_setup');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO source(id,titel,import_key) VALUES (-987654601,''OCR lock verify'',''verify:ocr:lock'') ON CONFLICT (id) DO UPDATE SET titel=excluded.titel');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO person(id) VALUES (-987654611) ON CONFLICT (id) DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO person_external_id(person_id,source_id,record_key) VALUES (-987654611,-987654601,''I-lock'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987654701,''person'',-987654611,''navn'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst) VALUES (-987654801,''fact'',-987654701,''Lock'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES (-987654901,''fact'',-987654701,-987654801,''afklaret'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup','INSERT INTO citation(id,assertion_id,source_id,citat_tekst) VALUES (-987654951,-987654801,-987654601,''Lock'') ON CONFLICT DO NOTHING');
  PERFORM dblink_exec('ocr_lock_setup',format('INSERT INTO auth.users(id,email) VALUES (''%s'',''ocr-lock-verify@test.invalid'') ON CONFLICT (id) DO NOTHING',v_uid));
  PERFORM dblink_exec('ocr_lock_setup',format('INSERT INTO profiles(id,rolle,email) VALUES (''%s'',''redaktion'',''ocr-lock-verify@test.invalid'') ON CONFLICT (id) DO UPDATE SET rolle=''redaktion''',v_uid));
  PERFORM dblink_connect('ocr_lock_a',v_conn || ' application_name=daa_verify_ocr_lock_a');
  PERFORM dblink_connect('ocr_lock_b',v_conn || ' application_name=daa_verify_ocr_lock_b');
  SELECT pid INTO v_a_pid
    FROM dblink('ocr_lock_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid
    FROM dblink('ocr_lock_b','SELECT pg_backend_pid()') AS t(pid integer);
  IF v_a_pid IS NULL OR v_b_pid IS NULL THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden kunne ikke observere backend-PID';
  END IF;

  -- A acquires both stable-anchor row locks synchronously. B is not started until this
  -- real lock operation has returned, so the intended interleaving has no timer race.
  PERFORM dblink_exec('ocr_lock_a','BEGIN');
  v_a_in_tx := true;
  PERFORM dblink_exec('ocr_lock_a','SET LOCAL statement_timeout=''10s''');
  SELECT locked INTO v_locked FROM dblink('ocr_lock_a',
    'SELECT count(*)::bigint FROM ('
    || 'SELECT s.id FROM source s JOIN person_external_id pei ON pei.source_id=s.id '
    || 'WHERE pei.person_id=-987654611 FOR UPDATE OF s,pei'
    || ') locked') AS t(locked bigint);
  IF v_locked IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden A låste ikke source/external-id, antal=%',v_locked;
  END IF;

  PERFORM dblink_exec('ocr_lock_b','BEGIN');
  v_b_in_tx := true;
  PERFORM dblink_exec('ocr_lock_b','SET LOCAL statement_timeout=''10s''');
  PERFORM * FROM dblink('ocr_lock_b',format(
    'SELECT set_config(''request.jwt.claim.sub'',''%s'',true)',v_uid)) AS t(value text);
  PERFORM dblink_send_query('ocr_lock_b',
    'SELECT count(*)::bigint AS deleted FROM (SELECT red_slet_person(-987654611)) s');
  v_b_async := true;

  -- The barrier is behavior, not elapsed time: B must be waiting behind A's backend
  -- before A reaches citation. With the old inverse order B already owns citation here,
  -- so A's next statement recreates the deadlock; with the fixed order A can proceed.
  v_deadline := clock_timestamp() + interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid = ANY(pg_blocking_pids(v_b_pid));
    SELECT dblink_is_busy('ocr_lock_b') INTO v_b_busy;
    IF v_b_busy = 0 THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden B nåede ikke blocker-barrieren';
    END IF;
    IF clock_timestamp() > v_deadline THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden observerede ikke B blokeret af A';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  -- Kept as an executable failure-mode test: at this point A owns the anchor locks
  -- and B is actively waiting, so the exception path must roll back/disconnect both.
  IF current_setting('daa.verify_force_ocr_lock_failure',true) = 'on' THEN
    RAISE EXCEPTION 'FORCED_OCR_LOCK_VERIFY_FAILURE';
  END IF;

  PERFORM dblink_send_query('ocr_lock_a',
    'UPDATE citation SET citat_tekst=''A'' WHERE id=-987654951 RETURNING id');
  v_a_async := true;
  v_deadline := clock_timestamp() + interval '10 seconds';
  LOOP
    SELECT dblink_is_busy('ocr_lock_a') INTO v_a_busy;
    EXIT WHEN v_a_busy = 0;
    IF clock_timestamp() > v_deadline THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden A overskred 10 sekunder (mulig deadlock)';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  SELECT id INTO v_result FROM dblink_get_result('ocr_lock_a') AS t(id bigint);
  PERFORM * FROM dblink_get_result('ocr_lock_a') AS t(id bigint);
  v_a_async := false;
  IF v_result IS DISTINCT FROM -987654951 THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden fuldførte ikke citation-skriveren, resultat=%',v_result;
  END IF;
  PERFORM dblink_exec('ocr_lock_a','COMMIT');
  v_a_in_tx := false;

  v_deadline := clock_timestamp() + interval '10 seconds';
  LOOP
    SELECT dblink_is_busy('ocr_lock_b') INTO v_b_busy;
    EXIT WHEN v_b_busy = 0;
    IF clock_timestamp() > v_deadline THEN
      RAISE EXCEPTION 'FEJL: OCR-låseorden B overskred 10 sekunder';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  SELECT deleted INTO v_deleted FROM dblink_get_result('ocr_lock_b') AS t(deleted bigint);
  PERFORM * FROM dblink_get_result('ocr_lock_b') AS t(deleted bigint);
  v_b_async := false;
  IF v_deleted IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden fuldførte ikke personsletningen, resultat=%',v_deleted;
  END IF;
  PERFORM dblink_exec('ocr_lock_b','COMMIT');
  v_b_in_tx := false;
  PERFORM dblink_disconnect('ocr_lock_a');
  PERFORM dblink_disconnect('ocr_lock_b');

  PERFORM dblink_exec('ocr_lock_setup',v_cleanup_sql);
  PERFORM dblink_disconnect('ocr_lock_setup');
  IF EXISTS (
       SELECT 1 FROM source WHERE id=-987654601
       UNION ALL SELECT 1 FROM person WHERE id=-987654611
       UNION ALL SELECT 1 FROM person_external_id WHERE person_id=-987654611
       UNION ALL SELECT 1 FROM fact WHERE id=-987654701
       UNION ALL SELECT 1 FROM assertion WHERE id=-987654801
       UNION ALL SELECT 1 FROM conclusion WHERE id=-987654901
       UNION ALL SELECT 1 FROM citation WHERE id=-987654951
       UNION ALL SELECT 1 FROM import_korrektion
         WHERE import_key='verify:ocr:lock' AND record_key='I-lock'
       UNION ALL SELECT 1 FROM profiles WHERE id=v_uid
       UNION ALL SELECT 1 FROM auth.users WHERE id=v_uid
       UNION ALL SELECT 1 FROM change_set
         WHERE operation='red_slet_person' AND subjekt_type='person' AND subjekt_id=-987654611
     )
     OR EXISTS (
       SELECT 1 FROM pg_stat_activity
       WHERE datname=current_database() AND application_name LIKE 'daa_verify_ocr_lock_%'
     ) THEN
    RAISE EXCEPTION 'FEJL: OCR-låseorden efterlod fixture eller dblink-session';
  END IF;
  RAISE NOTICE 'OK: OCR-låseorden to-forbindelsesregression';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS
    v_error_state = RETURNED_SQLSTATE,
    v_error_message = MESSAGE_TEXT;

  -- Cancel/drain first when possible, explicitly roll back, and always disconnect.
  -- Disconnect is the final rollback guarantee if a remote query is still active.
  IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_a') IS NOT NULL THEN
    BEGIN
      IF v_a_async AND dblink_is_busy('ocr_lock_a') = 1 THEN
        PERFORM dblink_cancel_query('ocr_lock_a');
      END IF;
      IF v_a_async THEN
        v_deadline := clock_timestamp() + interval '2 seconds';
        WHILE dblink_is_busy('ocr_lock_a') = 1 AND clock_timestamp() < v_deadline
          LOOP PERFORM pg_sleep(0.01); END LOOP;
        IF dblink_is_busy('ocr_lock_a') = 0 THEN
          PERFORM * FROM dblink_get_result('ocr_lock_a',false) AS t(id bigint);
          PERFORM * FROM dblink_get_result('ocr_lock_a',false) AS t(id bigint);
        END IF;
      END IF;
      IF v_a_in_tx THEN PERFORM dblink_exec('ocr_lock_a','ROLLBACK'); END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN PERFORM dblink_disconnect('ocr_lock_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_b') IS NOT NULL THEN
    BEGIN
      IF v_b_async AND dblink_is_busy('ocr_lock_b') = 1 THEN
        PERFORM dblink_cancel_query('ocr_lock_b');
      END IF;
      IF v_b_async THEN
        v_deadline := clock_timestamp() + interval '2 seconds';
        WHILE dblink_is_busy('ocr_lock_b') = 1 AND clock_timestamp() < v_deadline
          LOOP PERFORM pg_sleep(0.01); END LOOP;
        IF dblink_is_busy('ocr_lock_b') = 0 THEN
          PERFORM * FROM dblink_get_result('ocr_lock_b',false) AS t(deleted bigint);
          PERFORM * FROM dblink_get_result('ocr_lock_b',false) AS t(deleted bigint);
        END IF;
      END IF;
      IF v_b_in_tx THEN PERFORM dblink_exec('ocr_lock_b','ROLLBACK'); END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN PERFORM dblink_disconnect('ocr_lock_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_setup') IS NOT NULL THEN
    BEGIN PERFORM dblink_disconnect('ocr_lock_setup'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  -- Setup is autonomous/committed, so cleanup must be autonomous too. A fresh
  -- connection avoids an aborted setup/RPC transaction and retries success-cleanup errors.
  BEGIN
    IF array_position(coalesce(dblink_get_connections(),'{}'::text[]),'ocr_lock_cleanup') IS NOT NULL THEN
      PERFORM dblink_disconnect('ocr_lock_cleanup');
    END IF;
    PERFORM dblink_connect('ocr_lock_cleanup',
      v_conn || ' application_name=daa_verify_ocr_lock_cleanup');
    PERFORM dblink_exec('ocr_lock_cleanup',v_cleanup_sql);
    PERFORM dblink_disconnect('ocr_lock_cleanup');
  EXCEPTION WHEN OTHERS THEN
    v_cleanup_error := SQLERRM;
    BEGIN PERFORM dblink_disconnect('ocr_lock_cleanup'); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE EXCEPTION USING
      ERRCODE = v_error_state,
      MESSAGE = format('%s; autonom cleanup fejlede: %s',v_error_message,v_cleanup_error);
  END;
  RAISE EXCEPTION USING ERRCODE = v_error_state, MESSAGE = v_error_message;
END $$;

-- ===== Person OCR kvalitetsark — samlet redaktionsprojektion =====
-- Selvstændig grid-fixture. Den ruller alle rækker tilbage og afprøver den faktiske
-- SECURITY DEFINER-overflade med lokale roller; den afhænger ikke af produktionsdata.
DO $$
DECLARE
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000c3';
  v_anon_blokeret boolean := false;
  v_medlem_blokeret boolean := false;
  v_antal integer;
  v_qa text[];
BEGIN
  INSERT INTO source(id,titel,udgave,import_key) VALUES
    (-987656101,'Grid verify-kilde','Grid verify 1','daa:1939'),
    (-987656102,'Grid verify-ekstra','Grid verify 2','daa:1940');
  INSERT INTO person(id,koen) VALUES
    (-987656111,'mand'), (-987656112,'kvinde'), (-987656113,NULL),
    (-987656114,'ukendt'), (-987656115,'mand'), (-987656116,'kvinde');
  INSERT INTO person(id,koen) VALUES (-987656117,'mand');
  UPDATE person SET staged=true WHERE id=-987656114;
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal) VALUES
    (-987656111,-987656101,'I',15,'I-15a',3),
    (-987656112,-987656101,'I',16,'I-16',3),
    (-987656113,-987656101,'I',17,NULL,4),
    (-987656114,-987656101,'II',1,'II-1',1),
    (-987656115,-987656101,'II',2,'II-2',1),
    (-987656116,-987656101,'II',3,'II-3',1),
    (-987656116,-987656102,'II',3,'II-3-ny',1),
    (-987656117,-987656101,'III',99,NULL,5);

  -- Normal person: selected source assertions, titel/familie/relation-counts and
  -- deliberately odd OCR/date context for the deterministic QA contract.
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-987656201,'person',-987656111,'navn'),
    (-987656202,'person',-987656111,'fødsel'),
    (-987656203,'person',-987656111,'død'),
    (-987656204,'person',-987656111,'titel'),
    (-987656205,'person',-987656112,'navn'),
    (-987656206,'person',-987656112,'fødsel'),
    (-987656207,'person',-987656112,'fødsel'),
    (-987656208,'person',-987656113,'fødsel'),
    (-987656209,'person',-987656114,'navn'),
    (-987656210,'person',-987656115,'navn'),
    (-987656211,'person',-987656116,'navn'),
    (-987656212,'person',-987656112,'død'),
    (-987656213,'person',-987656117,'navn'),
    (-987656214,'person',-987656117,'fødsel');
  INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw)
  VALUES
    (-987656301,'fact',-987656201,'Mikkel',NULL,NULL,NULL,NULL),
    (-987656302,'fact',-987656202,NULL,'1901-01-01','1901-12-31','between','født 1901'),
    (-987656303,'fact',-987656203,NULL,'1900-01-01','1900-12-31','between','død 1900'),
    (-987656304,'fact',-987656204,'kammerherre',NULL,NULL,NULL,NULL),
    (-987656305,'fact',-987656205,'Ambig',NULL,NULL,NULL,NULL),
    (-987656306,'fact',-987656206,NULL,'1800-01-01','1800-12-31','between','født 1800'),
    (-987656307,'fact',-987656207,NULL,'1801-01-01','1801-12-31','between','født 1801'),
    (-987656308,'fact',-987656208,NULL,NULL,NULL,NULL,'dato kan ikke læses'),
    (-987656309,'fact',-987656209,'Uden kontekst',NULL,NULL,NULL,NULL),
    (-987656310,'fact',-987656210,'Alias',NULL,NULL,NULL,NULL),
    (-987656311,'fact',-987656211,'Kanonisk',NULL,NULL,NULL,NULL),
    (-987656312,'fact',-987656212,NULL,NULL,NULL,NULL,'dato kan ikke læses'),
    (-987656313,'fact',-987656213,'Legacy Navn Uden Anker',NULL,NULL,NULL,NULL),
    (-987656314,'fact',-987656214,NULL,'1690-01-01','1690-12-31','between','født 1690');
  INSERT INTO conclusion(id,target_type,target_id,valgt_assertion_id,status) VALUES
    (-987656401,'fact',-987656201,-987656301,'afklaret'),
    (-987656402,'fact',-987656202,-987656302,'afklaret'),
    (-987656403,'fact',-987656203,-987656303,'afklaret'),
    (-987656404,'fact',-987656204,-987656304,'afklaret'),
    (-987656405,'fact',-987656205,-987656305,'afklaret'),
    (-987656406,'fact',-987656206,-987656306,'afklaret'),
    (-987656407,'fact',-987656207,-987656307,'afklaret'),
    (-987656408,'fact',-987656208,-987656308,'afklaret'),
    (-987656409,'fact',-987656209,-987656309,'afklaret'),
    (-987656410,'fact',-987656210,-987656310,'forældet'),
    (-987656411,'fact',-987656211,-987656311,'afklaret'),
    (-987656412,'fact',-987656212,-987656312,'afklaret'),
    (-987656413,'fact',-987656213,-987656313,'afklaret'),
    (-987656414,'fact',-987656214,-987656314,'afklaret');
  INSERT INTO citation(id,assertion_id,source_id,side,citat_tekst) VALUES
    (-987656501,-987656301,-987656101,'42','Mikkel ?'),
    (-987656502,-987656302,-987656101,'42','født 1901'),
    (-987656503,-987656303,-987656101,'42','død 1900'),
    (-987656504,-987656304,-987656101,'42','kammerherre'),
    (-987656505,-987656305,-987656101,'43','Ambig'),
    (-987656506,-987656306,-987656101,'43','født 1800'),
    (-987656507,-987656307,-987656101,'43','født 1801'),
    (-987656508,-987656308,-987656101,'44','dato kan ikke læses'),
    (-987656510,-987656310,-987656101,'45','Alias'),
    (-987656511,-987656311,-987656101,'45','Kanonisk'),
    (-987656512,-987656312,-987656101,'44','dato kan ikke læses'),
    (-987656513,-987656313,-987656101,'99','Legacy Navn Uden Anker'),
    (-987656514,-987656314,-987656101,'99','født 1690');
  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,korrigeret,status)
    VALUES ('daa:1939','I-15a','navn','0123456789abcdef0123456789abcdef',
            '{"value":"Mikkel"}','{"value":"Mikkel rettet"}','rettet');
  INSERT INTO family(id,type) VALUES (-987656601,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (-987656601,-987656111,'partner');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-987656701,'person',-987656111,'person',-987656112,'bekendt_med'),
    (-987656702,'person',-987656115,'person',-987656116,'samme_som');

  -- samme_som-KÆDE: -987656119 er BÅDE alias (af -987656120) OG kanonisk (for
  -- -987656118). same_as_context producerede før én række pr. rolle, og da de to
  -- rækker adskiller sig på samme_som_status overlevede begge GROUP BY'et — samme
  -- fysiske person kom altså ud af griddet TO gange. Griddet lover én række pr.
  -- fysisk person; kæden låser det løfte fast.
  --
  -- RÆKKEFØLGEN ER IKKE VILKÅRLIG. enforce_samme_som_invariants() er BEFORE INSERT,
  -- og G4 tjekker kun om den NYE rækkes SUBJEKT allerede er kanonisk — ikke om dens
  -- OBJEKT allerede er alias. Indsættes den inderste kant (119→120) først, slipper
  -- den ydre (118→119) derfor igennem, og kæden opstår. Det er ikke et hul jeg
  -- opfinder til testen: præcis én person i prod står i den tilstand. Den omvendte
  -- rækkefølge ville blive afvist af G4 — griddet skal alligevel kunne tåle
  -- tilstanden, uanset om invarianten senere strammes.
  INSERT INTO person(id,koen) VALUES
    (-987656118,'mand'), (-987656119,'mand'), (-987656120,'mand');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-987656704,'person',-987656119,'person',-987656120,'samme_som');
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-987656703,'person',-987656118,'person',-987656119,'samme_som');

  -- Fingerprint-parity with Task 2's independently fixed UTF-8 vector.
  IF ocr_input_fingerprint('daa:1939','I-15a','foedsel',
       '{"raw":"* 1644","min":"1644-01-01","max":"1644-12-31","qualifier":null,"calendar":"gregoriansk","certainty":null}'::jsonb,
       'side=42;span=1') <> '5fc3d843cc82550a45ff2a176bc7cc83' THEN
    RAISE EXCEPTION 'FEJL: OCR-fingerprint er ikke i Task 2-paritet';
  END IF;

  -- EXECUTE ACL plus SECURITY DEFINER-role guard are both part of the contract.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM * FROM red_person_grid();
  EXCEPTION WHEN insufficient_privilege THEN v_anon_blokeret := true;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM * FROM red_person_grid();
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN v_medlem_blokeret := true; ELSE RAISE; END IF;
  END;
  RESET ROLE;
  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'ocr-grid-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_redaktor,'redaktion','ocr-grid-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_redaktor::text,true);
  SET LOCAL ROLE authenticated;

  SELECT count(*) INTO v_antal FROM red_person_grid() WHERE person_id BETWEEN -987656116 AND -987656111;
  IF v_antal <> 6 THEN RAISE EXCEPTION 'FEJL: grid returnerede %/6 fysiske personer', v_antal; END IF;
  IF (SELECT count(*) FROM red_person_grid() WHERE person_id IN (-987656115,-987656116)) <> 2
     OR (SELECT kanonisk_person_id FROM red_person_grid() WHERE person_id=-987656115) <> -987656116 THEN
    RAISE EXCEPTION 'FEJL: grid kollapser eller mister samme_som-kontekst';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656111
                 AND antal_titler=1 AND antal_familier=1 AND antal_relationer=1
                 AND antal_kilde_assertions=4
                 AND ocr_context->>'navn'='Mikkel ?' AND kilde_side->>'navn'='42') THEN
    RAISE EXCEPTION 'FEJL: grid-counts eller valgt assertions OCR-kontekst er forkert';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656112
                 AND kan_rettes->>'foedsel'='false'
                 AND blokarsager->>'foedsel'='flere_importerede_facts'
                 AND foedsel_assertion_id IS NULL AND foedsel_raw IS NULL
                 AND foedsel_min IS NULL AND foedsel_max IS NULL
                 AND ocr_context->'foedsel' IS NULL) THEN
    RAISE EXCEPTION 'FEJL: flere importerede fødselsfacts er ikke koherent fail-closed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656115
                 AND navn IS NULL AND navn_assertion_id IS NULL
                 AND kan_rettes->>'navn'='false'
                 AND NOT (qa_koder @> ARRAY['ocr_kontekst_mangler']::text[])) THEN
    RAISE EXCEPTION 'FEJL: ikke-afklaret konklusion projekteres stadig';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656116
                 AND kan_rettes='{"navn": false, "foedsel": false, "doed": false, "koen": false}'::jsonb
                 AND blokarsager='{"navn": "flere_importankre", "foedsel": "flere_importankre", "doed": "flere_importankre", "koen": "flere_importankre"}'::jsonb) THEN
    RAISE EXCEPTION 'FEJL: flere importankre er ikke blokeret for alle felter';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656113
                 AND kan_rettes->>'navn'='false' AND blokarsager->>'navn'='record_key_mangler') THEN
    RAISE EXCEPTION 'FEJL: legacy-række uden record_key er ikke blokeret';
  END IF;
  -- En legacy-række uden stabilt anker (record_key NULL) kan ikke rettes, men skal
  -- stadig kunne IDENTIFICERES og TIDSFÆSTES i griddet. Fallback bruger den allerede
  -- afklarede evidens (selected_assertions, FØR anker-gaten) — IKKE person.visning_*,
  -- som viste sig at ignorere conclusion.status og derfor kan lække en forældet værdi.
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656117
                 AND navn='Legacy Navn Uden Anker' AND kan_rettes->>'navn'='false'
                 AND foedsel_min='1690-01-01' AND foedsel_max='1690-12-31'
                 AND kan_rettes->>'foedsel'='false') THEN
    RAISE EXCEPTION 'FEJL: legacy-række uden stabilt anker viser ikke afklaret evidens som navn/fødsel';
  END IF;
  -- Beskyttelse mod status-læk: -987656115's eneste navn-konklusion er 'forældet'
  -- (ikke afklaret). Fallback må IKKE hente fra en ikke-afklaret konklusion, selvom
  -- den har et gyldigt valgt_assertion_id — det ville lade en tilbagetrukket værdi
  -- sive ind i visningen. Denne test dækkede allerede dette FØR fallback blev tilføjet;
  -- den skal fortsat holde bagefter.

  SELECT qa_koder INTO v_qa FROM red_person_grid() WHERE person_id=-987656111;
  IF NOT (v_qa @> ARRAY['mistænkeligt_ocr_tegn','foedt_efter_doed','struktureret_afviger_fra_ocr']::text[]) THEN
    RAISE EXCEPTION 'FEJL: normale OCR-/dato-QA-koder mangler: %', v_qa;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656111
                 AND review_status->>'navn'='stale'
                 AND qa_koder @> ARRAY['kilde_aendret']::text[]
                 AND importeret->'navn'='{"value":"Mikkel"}'::jsonb
                 AND korrigeret->'navn'='{"value":"Mikkel rettet"}'::jsonb) THEN
    RAISE EXCEPTION 'FEJL: stale journal-overlay bevarer ikke immutable importinput';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656112 AND qa_koder @> ARRAY['flere_importerede_facts']::text[])
     OR NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656113 AND qa_koder @> ARRAY['dato_ufortolkelig','record_key_mangler']::text[])
     OR NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114 AND qa_koder @> ARRAY['ocr_kontekst_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: deterministiske grid-QA-koder mangler ambig=% legacy=% staged_context=%',
      EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656112 AND qa_koder @> ARRAY['flere_importerede_facts']::text[]),
      EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656113 AND qa_koder @> ARRAY['dato_ufortolkelig','record_key_mangler']::text[]),
      EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114 AND qa_koder @> ARRAY['ocr_kontekst_mangler']::text[]);
  END IF;

  -- ---- navn_mangler betyder "der vises intet navn" — IKKE "navnet kan ikke rettes" ----
  -- Redigerbarhed udtrykkes af kan_rettes/blokarsager. Da QA-koden tidligere målte på
  -- de anker-gatede felter (candidate_count/felt_vaerdi), mens VISNINGEN falder tilbage
  -- til afklaret evidens, flagede den hver eneste ikke-redigerbare række — 1169 af 1757
  -- i prod, alle med et synligt navn, nul ægte. Samme fejlklasse som den tomme
  -- navnekolonne: gaten hørte til redigerbarheden, ikke til værdien.

  -- (a) Anker-løs, men navn opløst via fallback => navnet mangler IKKE.
  IF EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656117
             AND qa_koder @> ARRAY['navn_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: navn_mangler sat på række der viser et navn (anker-løs fallback)';
  END IF;

  -- (b) Navn kendt (afklaret konklusion) men uden citation => vises, altså ikke
  -- navn_mangler; manglen er kildedækning, og den udtrykkes af ocr_kontekst_mangler
  -- + blokårsagen ingen_kildebelagt_assertion.
  IF EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114
             AND qa_koder @> ARRAY['navn_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: navn_mangler forveksler manglende kildedækning med manglende navn';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656114
                 AND navn='Uden kontekst'
                 AND kan_rettes->>'navn'='false'
                 AND blokarsager->>'navn'='ingen_kildebelagt_assertion') THEN
    RAISE EXCEPTION 'FEJL: ukildebelagt navn vises ikke, eller er ikke blokeret for rettelse';
  END IF;

  -- (c) Ægte tomt navn SKAL stadig flages. -987656115's eneste navn-konklusion er
  -- 'forældet', så selected_assertions giver intet — der er reelt intet navn at vise.
  -- Denne retning er værnet mod at fixet bare slukker for koden.
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656115
                 AND navn IS NULL AND qa_koder @> ARRAY['navn_mangler']::text[]) THEN
    RAISE EXCEPTION 'FEJL: ægte manglende navn flages ikke længere';
  END IF;

  -- ---- én række pr. fysisk person, også midt i en samme_som-kæde ----
  IF (SELECT count(*) FROM red_person_grid() WHERE person_id=-987656119) <> 1 THEN
    RAISE EXCEPTION 'FEJL: person midt i samme_som-kæde duplikeres i griddet (% rækker)',
      (SELECT count(*) FROM red_person_grid() WHERE person_id=-987656119);
  END IF;
  -- Alias-rollen vinder over kanonisk: at være alias er det stærkere udsagn om
  -- personens identitetsstatus, og redaktøren skal kunne se hvem hun peger på.
  IF NOT EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656119
                 AND samme_som_status='alias' AND kanonisk_person_id=-987656120) THEN
    RAISE EXCEPTION 'FEJL: kæde-person viser ikke alias-rollen mod sin kanoniske';
  END IF;
  IF EXISTS (SELECT 1 FROM red_person_grid() WHERE person_id=-987656115
             AND (qa_koder @> ARRAY['dato_ufortolkelig']::text[])) THEN
    RAISE EXCEPTION 'FEJL: manglende fødsel/død blev fejlagtigt OCR-fejl';
  END IF;
  RESET ROLE;
  IF NOT v_anon_blokeret OR NOT v_medlem_blokeret THEN
    RAISE EXCEPTION 'FEJL: grid EXECUTE/gate anon=% medlem=%',v_anon_blokeret,v_medlem_blokeret;
  END IF;
  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN others THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: Person OCR kvalitetsark — set-baseret grid, QA, fingerprint og roller';
  ELSE RAISE; END IF;
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
  -- maa_publiceres=true + upload_status='klar' på alle: isolér afbildet-gatingen fra rettigheds-gatingen
  -- (rettigheder testes separat i Task 12).
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status) VALUES
    (-901,'foto','portræt-afdød',      true,'klar'),
    (-902,'foto','portræt-levende',    true,'klar'),
    (-903,'segl','objekt-uden-person', true,'klar');
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


-- ===== Task 8b: F-02 authenticated (medlem) fail-close på levende =====
-- Forvent: NOTICE "OK: authenticated fail-close ...". Seeder negative-id rækker, rydder selv op.
-- Kører som rolle 'authenticated' UDEN jwt-sub → auth.uid()=NULL → current_rolle() ≠ 'redaktion',
-- så redaktion_read-laget fyrer IKKE og auth_read styrer alene (medlem-tier).
-- Invariant #8 (CLAUDE.md §3): LEVENDE kræver samtykke — indtil samtykke/scope findes skal
-- medlem-tier fail-close til samme regel som anon (afdøde synlige, levende skjult). Codex-fund F-02.
-- Dækker BÅDE person-laget OG media-laget (media_synlig_auth tillod ellers fotos af levende).
DO $$
DECLARE vis_live int; vis_dead int; media_live int; media_dead int;
BEGIN
  DELETE FROM relation WHERE id IN (-950,-951);
  DELETE FROM media    WHERE id IN (-950,-951);
  DELETE FROM person   WHERE id IN (-950,-951);
  INSERT INTO person(id, levende, privat) VALUES (-950, true, false), (-951, false, false);
  -- media der afbilder hhv. den levende og den afdøde person (rettigheder=klar, så kun GDPR-gating måles)
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status) VALUES
    (-950,'foto','portræt-levende', true,'klar'), (-951,'foto','portræt-afdød', true,'klar');
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle) VALUES
    (-950,'person',-950,'media',-950,'afbildet'), (-951,'person',-951,'media',-951,'afbildet');

  PERFORM set_config('request.jwt.claim.sub','', true);  -- ingen bruger → ikke-redaktion
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO vis_live   FROM person WHERE id = -950;
  SELECT count(*) INTO vis_dead   FROM person WHERE id = -951;
  SELECT count(*) INTO media_live FROM media  WHERE id = -950;
  SELECT count(*) INTO media_dead FROM media  WHERE id = -951;
  RESET ROLE;

  IF vis_live = 0 AND vis_dead = 1 AND media_live = 0 AND media_dead = 1 THEN
    RAISE NOTICE 'OK: authenticated fail-close (levende person+foto skjult, afdød synlig)';
  ELSE
    RAISE EXCEPTION 'F-02 FEJL: authenticated person levende=%/afdød=% (vent 0/1), media levende=%/afdød=% (vent 0/1)',
      vis_live, vis_dead, media_live, media_dead;
  END IF;

  DELETE FROM relation WHERE id IN (-950,-951);
  DELETE FROM media    WHERE id IN (-950,-951);
  DELETE FROM person   WHERE id IN (-950,-951);
END $$;


-- ===== Task 8c: F-02c polymorf entitets-gating (family + ukendt type fail-close) =====
-- Forvent: NOTICE "OK: F-02c ...". Codex dual-review-fund: "<>'person'"-mønstret var fail-OPEN for
-- (1) family-mål (levende families vielse-fakta/noter synlige for anon+auth) og (2) ukendte/fejlstavede
-- typer. Nu erstattet af entitet_offentlig() (+ family_offentlig()). Tester BEGGE retninger:
-- læk-siden (family/unknown skjult) OG over-hiding-siden (public entitets-data STADIG synligt).
DO $$
DECLARE
  fo_dead boolean; fo_live boolean;
  leak_fam_anon int; leak_fam_auth int; leak_note_auth int; leak_mis int; leak_assert int;
  ok_deadfam int; ok_estate int; ok_org_rel int; ok_narr int;
BEGIN
  DELETE FROM citation WHERE id=-981; DELETE FROM assertion WHERE id=-981;
  DELETE FROM note WHERE id IN (-980,-981); DELETE FROM narrative WHERE id=-980;
  DELETE FROM relation WHERE id IN (-980,-981); DELETE FROM fact WHERE id IN (-980,-981,-982,-983);
  DELETE FROM family_member WHERE family_id IN (-980,-981); DELETE FROM family WHERE id IN (-980,-981);
  DELETE FROM organisation WHERE id=-999; DELETE FROM estate WHERE id=-999;
  DELETE FROM person WHERE id IN (-980,-981);

  INSERT INTO person(id,levende,privat) VALUES(-980,false,false),(-981,true,false);
  INSERT INTO organisation(id,navn) VALUES(-999,'testorg');  INSERT INTO estate(id,navn) VALUES(-999,'testgods');
  INSERT INTO family(id,type) VALUES(-980,'ægteskab'),(-981,'ægteskab');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES(-980,-980,'partner'),(-981,-981,'partner');
  INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
    (-980,'family',-980,'vielse'),(-981,'family',-981,'vielse'),
    (-982,'Person',-981,'fødsel'),(-983,'estate',-999,'opførelse');
  INSERT INTO assertion(id,target_type,target_id) VALUES(-981,'fact',-981);  -- evidens på levende-fam-fact
  INSERT INTO relation(id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES
    (-980,'person',-980,'organisation',-999,'medlem'),(-981,'person',-981,'organisation',-999,'medlem');
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst) VALUES(-980,'person',-980,'død bio');
  INSERT INTO note(id,target_type,target_id) VALUES(-980,'family',-980),(-981,'family',-981);

  SET LOCAL ROLE anon;
  SELECT public.family_offentlig(-980), public.family_offentlig(-981) INTO fo_dead, fo_live;  -- DEFINER-check
  SELECT count(*) INTO leak_fam_anon FROM fact WHERE id=-981;
  SELECT count(*) INTO ok_deadfam FROM fact WHERE id=-980;   SELECT count(*) INTO ok_estate FROM fact WHERE id=-983;
  SELECT count(*) INTO ok_org_rel FROM relation WHERE id=-980; SELECT count(*) INTO ok_narr FROM narrative WHERE id=-980;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','',true); SET LOCAL ROLE authenticated;
  SELECT count(*) INTO leak_fam_auth FROM fact WHERE id=-981;  SELECT count(*) INTO leak_note_auth FROM note WHERE id=-981;
  SELECT count(*) INTO leak_mis FROM fact WHERE id=-982;       SELECT count(*) INTO leak_assert FROM assertion WHERE id=-981;
  RESET ROLE;

  IF fo_dead AND NOT fo_live
     AND leak_fam_anon=0 AND leak_fam_auth=0 AND leak_note_auth=0 AND leak_mis=0 AND leak_assert=0
     AND ok_deadfam=1 AND ok_estate=1 AND ok_org_rel=1 AND ok_narr=1 THEN
    RAISE NOTICE 'OK: F-02c — family/unknown+evidens fail-closed OG public entitets-data stadig synligt';
  ELSE
    RAISE EXCEPTION 'F-02c FEJL: DEFINER død/lev=%/% | læk fam(a/au)=%/% note=% mis=% assert=% | over-hide dødfam=% estate=% rel=% narr=%',
      fo_dead,fo_live,leak_fam_anon,leak_fam_auth,leak_note_auth,leak_mis,leak_assert,ok_deadfam,ok_estate,ok_org_rel,ok_narr;
  END IF;

  DELETE FROM citation WHERE id=-981; DELETE FROM assertion WHERE id=-981;
  DELETE FROM note WHERE id IN (-980,-981); DELETE FROM narrative WHERE id=-980;
  DELETE FROM relation WHERE id IN (-980,-981); DELETE FROM fact WHERE id IN (-980,-981,-982,-983);
  DELETE FROM family_member WHERE family_id IN (-980,-981); DELETE FROM family WHERE id IN (-980,-981);
  DELETE FROM organisation WHERE id=-999; DELETE FROM estate WHERE id=-999;
  DELETE FROM person WHERE id IN (-980,-981);
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
  -- hist_for_subjekter skal RAISE for ikke-redaktion (SQL Editor = medlem)
  BEGIN
    PERFORM * FROM hist_for_subjekter('person', ARRAY[1]::bigint[]);
    RAISE EXCEPTION 'FEJL: hist_for_subjekter tillod ikke-redaktion';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FEJL:%' THEN RAISE; END IF;  -- vores assert-fejl propagerer
  END;
  RAISE NOTICE 'OK: historik-API redaktion-gated + døde-links-view findes';
END $$;

-- ===== Fase 4.1: batchet tværudgave-match-RPC =====
DO $$
DECLARE
  v_uid uuid := gen_random_uuid();
  v_result jsonb;
  v_denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM red_match_personer();
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'Kun redaktion%' THEN v_denied := true;
    ELSE RAISE; END IF;
  END;
  RESET ROLE;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'FEJL: red_match_personer tillod ikke-redaktion';
  END IF;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'match-rpc-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','match-rpc-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  SET LOCAL ROLE authenticated;
  v_result := red_match_personer();
  RESET ROLE;

  IF v_result IS NULL
     OR NOT v_result ?& ARRAY['persons','facts','concs','assertions','extIds']
     OR jsonb_typeof(v_result->'persons') <> 'array'
     OR jsonb_array_length(v_result->'persons') <> (SELECT count(*) FROM person) THEN
    RAISE EXCEPTION 'FEJL: red_match_personer returnerede ugyldigt datasæt';
  END IF;

  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: red_match_personer er redaktion-gated og returnerer komplet rådatasæt';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE;
END $$;

-- ===== Mediehåndtering fase 2: døde media-mentions =====
-- Token-id'er skal være positive: parse_mentions-kontrakten accepterer ikke negative id'er.
DO $$
DECLARE
  v_nid bigint := -999903;
  v_manglende_media_id bigint := 999999901;
  v_eksisterende_media_id bigint := 999999902;
BEGIN
  PERFORM set_config('app.change_set_id','',true);  -- bulk-sti, ingen versionering af testdata

  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid='public.red_doede_links'::regclass
      AND coalesce(reloptions, ARRAY[]::text[]) @> ARRAY['security_invoker=true']
  ) THEN
    RAISE EXCEPTION 'FEJL: red_doede_links har mistet security_invoker=true';
  END IF;

  INSERT INTO media(id, slags, titel, upload_status)
    VALUES (v_eksisterende_media_id, 'foto', '__verify_doede_links__', 'klar');
  INSERT INTO narrative(id, subjekt_type, subjekt_id, tekst)
    VALUES (
      v_nid,
      'person',
      1,
      format(
        '[[media:%s|mangler]] og [[media:%s|findes]]',
        v_manglende_media_id,
        v_eksisterende_media_id
      )
    );

  IF NOT EXISTS (
    SELECT 1 FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_manglende_media_id
  ) OR NOT EXISTS (
    SELECT 1 FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_eksisterende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: mention-triggeren indekserede ikke begge media-tokens';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_manglende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: manglende media blev ikke vist som dødt link';
  END IF;
  IF EXISTS (
    SELECT 1 FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_eksisterende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: eksisterende media blev fejlagtigt vist som dødt link';
  END IF;

  UPDATE media SET upload_status='fjernet' WHERE id=v_eksisterende_media_id;
  IF EXISTS (
    SELECT 1 FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_eksisterende_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: fjernet media blev fejlagtigt vist som dødt link';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: døde media-mentions skelner manglende/fjernet (rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Mediehåndtering fase 2: redaktionen ser private media-mentions =====
DO $$
DECLARE
  v_uid uuid := '00000000-0000-0000-0000-00000000f202';
  v_member_uid uuid := '00000000-0000-0000-0000-00000000f203';
  v_nid bigint := -999904;
  v_public_nid bigint := -999905;
  v_public_person_id bigint := 999999905;
  v_media_id bigint := 999999904;
  v_hidden_media_id bigint := 999999906;
  v_missing_media_id bigint := 999999907;
  v_anon int;
  v_member int;
  v_redaktion int;
  v_dead_redaktion int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='text_mention'
      AND policyname='redaktion_read'
      AND roles @> ARRAY['authenticated']::name[]
  ) THEN
    RAISE EXCEPTION 'FEJL: text_mention.redaktion_read-policy mangler';
  END IF;

  -- Lokale PostgreSQL-shims har ikke Supabases default grants. De midlertidige
  -- grants rulles tilbage sammen med fixtures og tester kun policy-adfærden.
  EXECUTE 'GRANT SELECT ON text_mention, red_doede_links TO anon, authenticated';
  INSERT INTO auth.users(id,email) VALUES
    (v_uid,'media-fase2@test.invalid'),
    (v_member_uid,'media-fase2-member@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES
    (v_uid,'redaktion','media-fase2@test.invalid'),
    (v_member_uid,'medlem','media-fase2-member@test.invalid');
  INSERT INTO person(id,levende,privat) VALUES (v_public_person_id,false,false);
  INSERT INTO media(id,slags,titel,upload_status,maa_publiceres) VALUES
    (v_media_id,'foto','__verify_public_media__','klar',true),
    (v_hidden_media_id,'foto','__verify_hidden_media__','fjernet',true);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst,privat)
    VALUES
      (v_nid,'person',-999904,format('[[media:%s|privat]]',v_media_id),true),
      (v_public_nid,'person',v_public_person_id,
        format('[[media:%s|klar]] [[media:%s|skjult]] [[media:%s|mangler]]',
          v_media_id,v_hidden_media_id,v_missing_media_id),false);

  IF NOT EXISTS (
    SELECT 1 FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id=v_nid
      AND maal_type='media' AND maal_id=v_media_id
  ) THEN
    RAISE EXCEPTION 'FEJL: privat media-token blev ikke indekseret';
  END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_anon FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id IN (v_nid,v_public_nid)
      AND maal_type='media';
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub',v_member_uid::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_member FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id IN (v_nid,v_public_nid)
      AND maal_type='media';
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_redaktion FROM text_mention
    WHERE kilde_type='narrative' AND kilde_id IN (v_nid,v_public_nid)
      AND maal_type='media';
  SELECT count(*) INTO v_dead_redaktion FROM red_doede_links
    WHERE kilde_type='narrative' AND kilde_id=v_public_nid AND maal_type='media';
  RESET ROLE;

  IF v_anon <> 1 OR v_member <> 1 OR v_redaktion <> 4 OR v_dead_redaktion <> 1 THEN
    RAISE EXCEPTION 'FEJL: media-mention RLS anon=%/medlem=%/redaktion=%/død=% (vent 1/1/4/1)',
      v_anon, v_member, v_redaktion, v_dead_redaktion;
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media-mentions gater kilde+mål for anon/medlem og er komplette for redaktion (rullet tilbage)';
  ELSE RAISE; END IF;
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


-- ===== Task 12: media rettigheds-gating + storage.objects-mapping (mediehåndtering 2026-07-04) =====
-- Verificerer den ANDEN gating-dimension (copyright/publikation), ortogonal til afbildet-gatingen:
--   · objekt-foto, maa_publiceres=false → SKJULT for anon OG medlem, men SYNLIGT for redaktion
--   · objekt-foto, maa_publiceres=true men upload_status='kladde' → SKJULT (kun 'klar' publiceres)
--   · objekt-foto, maa_publiceres=true + 'klar' → SYNLIGT for anon
-- Plus storage-objekt→media-mappingen (media_id_for_object) inkl. forældreløst objekt → fail-closed.
DO $$
DECLARE vis_spaerret int; vis_kladde int; vis_klar int; vis_red int;
        map_hit bigint; map_orphan bigint; ok_orphan boolean;
BEGIN
  DELETE FROM media WHERE id IN (-911,-912,-913);
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-911,'segl','objekt-spaerret', false,'klar',   'media','test/spaerret.jpg'),
    (-912,'segl','objekt-kladde',   true, 'kladde', 'media','test/kladde.jpg'),
    (-913,'segl','objekt-klar',     true, 'klar',   'media','test/klar.jpg');

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_spaerret FROM media WHERE id = -911;
  SELECT count(*) INTO vis_kladde   FROM media WHERE id = -912;
  SELECT count(*) INTO vis_klar     FROM media WHERE id = -913;
  RESET ROLE;

  IF NOT (vis_spaerret = 0 AND vis_kladde = 0 AND vis_klar = 1) THEN
    RAISE EXCEPTION 'rettigheds-gating FEJL (anon): spaerret=% (vent 0), kladde=% (vent 0), klar=% (vent 1)',
      vis_spaerret, vis_kladde, vis_klar;
  END IF;

  -- objekt→media-mapping: kendt sti resolver, ukendt (forældreløs) → NULL → rettigheder_ok=false
  SELECT public.media_id_for_object('test/klar.jpg')        INTO map_hit;
  SELECT public.media_id_for_object('findes/ikke.jpg')      INTO map_orphan;
  SELECT public.media_rettigheder_ok(public.media_id_for_object('findes/ikke.jpg')) INTO ok_orphan;
  IF map_hit IS DISTINCT FROM -913 OR map_orphan IS NOT NULL OR ok_orphan IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'storage-mapping FEJL: hit=% (vent -913), orphan=% (vent NULL), orphan_ok=% (vent false)',
      map_hit, map_orphan, ok_orphan;
  END IF;

  DELETE FROM media WHERE id IN (-911,-912,-913);
  RAISE NOTICE 'OK: media rettigheds-gating (spærret/kladde skjult, klar synlig) + storage-mapping (forældreløs fail-closed)';
END $$;


-- ===== Task 12b: storage.objects-POLITIKKER under faktiske roller (ikke kun helper-kald) =====
-- Task 12 tester media-TABELLEN + helperne. Denne blok udøver de rigtige storage.objects-politikker
-- (media_obj_anon/auth) ved at indsætte objekt-rækker og læse dem under SET LOCAL ROLE — så en
-- fail-open-politik (OR i stedet for AND, manglende rettigheds-gate, eller manglende bucket-guard)
-- rejser her. Springes over hvis der ikke findes en 'media'-bucket (lokalt/pre-provisionering).
DO $$
DECLARE has_bucket boolean; vis_klar int; vis_spaerret int; vis_orphan int; vis_klar_auth int; vis_spaerret_auth int;
BEGIN
  SELECT EXISTS(SELECT 1 FROM storage.buckets WHERE id='media') INTO has_bucket;
  IF NOT has_bucket THEN
    RAISE NOTICE 'SPRINGER OVER Task 12b (storage.objects-politikker): ingen media-bucket — opret den for fuld dækning';
    RETURN;
  END IF;
  DELETE FROM storage.objects WHERE bucket_id='media' AND name IN ('test/klar.jpg','test/spaerret.jpg','test/orphan.jpg');
  DELETE FROM media WHERE id IN (-921,-922);
  INSERT INTO media(id, slags, titel, maa_publiceres, upload_status, bucket, storage_path) VALUES
    (-921,'segl','obj-klar',    true, 'klar','media','test/klar.jpg'),
    (-922,'segl','obj-spaerret',false,'klar','media','test/spaerret.jpg');
  INSERT INTO storage.objects(bucket_id, name) VALUES
    ('media','test/klar.jpg'), ('media','test/spaerret.jpg'), ('media','test/orphan.jpg'); -- orphan = ingen media-række

  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_klar     FROM storage.objects WHERE bucket_id='media' AND name='test/klar.jpg';
  SELECT count(*) INTO vis_spaerret FROM storage.objects WHERE bucket_id='media' AND name='test/spaerret.jpg';
  SELECT count(*) INTO vis_orphan   FROM storage.objects WHERE bucket_id='media' AND name='test/orphan.jpg';
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO vis_klar_auth     FROM storage.objects WHERE bucket_id='media' AND name='test/klar.jpg';
  SELECT count(*) INTO vis_spaerret_auth FROM storage.objects WHERE bucket_id='media' AND name='test/spaerret.jpg';
  RESET ROLE;

  IF NOT (vis_klar=1 AND vis_spaerret=0 AND vis_orphan=0 AND vis_klar_auth=1 AND vis_spaerret_auth=0) THEN
    RAISE EXCEPTION 'storage.objects-gating FEJL: anon(klar=% [1], spaerret=% [0], orphan=% [0]), medlem(klar=% [1], spaerret=% [0])',
      vis_klar, vis_spaerret, vis_orphan, vis_klar_auth, vis_spaerret_auth;
  END IF;

  DELETE FROM storage.objects WHERE bucket_id='media' AND name IN ('test/klar.jpg','test/spaerret.jpg','test/orphan.jpg');
  DELETE FROM media WHERE id IN (-921,-922);
  RAISE NOTICE 'OK: storage.objects-politikker (klar synlig anon+medlem; spærret + forældreløs skjult for begge)';
END $$;

-- ===== Task 13: generations-reparation — slægtled-kolonner findes + trigger scoped =====
DO $$
BEGIN
  ASSERT (SELECT count(*) FROM information_schema.columns
          WHERE table_name='person_external_id'
            AND column_name IN ('slaegtled_lokal','slaegtled_gennem','kuld')) = 3,
    'Mangler generations-kolonner på person_external_id';
END $$;

-- Trigger-scoping: trg_external_id_regen skal være kolonne-scoped (UPDATE OF
-- person_id, source_id, linje, nr), IKKE et bart "AFTER UPDATE" — ellers
-- fyrer den unødigt på slaegtled_lokal/slaegtled_gennem/kuld-opdateringer
-- (backfill_slaegtled.R), som ikke selv skal trigge lineage-regen.
DO $$
DECLARE
  def text;
BEGIN
  SELECT pg_get_triggerdef(oid) INTO def
    FROM pg_trigger
   WHERE tgname = 'trg_external_id_regen' AND NOT tgisinternal;
  ASSERT def IS NOT NULL, 'trg_external_id_regen findes ikke';
  ASSERT position('UPDATE OF' in def) > 0,
    'trg_external_id_regen er ikke kolonne-scoped (mangler UPDATE OF) — fyrer på ALLE updates';
  ASSERT position('linje' in def) > 0 AND position('nr' in def) > 0,
    'trg_external_id_regen UPDATE OF-liste mangler linje/nr-kolonner';
  RAISE NOTICE 'OK: trg_external_id_regen er kolonne-scoped (%)', def;
END $$;


-- ===== Task 14: bookmark — RLS-isolation, dublet-sikring, anon-lukket, cascade =====
DO $$
DECLARE cnt_a int; cnt_b int; insert_denied boolean := false; anon_denied boolean := false;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    ('00000000-0000-0000-0000-0000000000a1','a@test'),
    ('00000000-0000-0000-0000-0000000000a2','b@test')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO person(id) VALUES (-931),(-932) ON CONFLICT (id) DO NOTHING;

  -- Bruger A gemmer -931
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-931);
  SELECT count(*) INTO cnt_a FROM bookmark WHERE person_id=-931;
  RESET ROLE;

  -- Bruger B ser IKKE A's bogmærke; forsøg på at skrive i A's navn afvises
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO cnt_b FROM bookmark WHERE person_id=-931;
  BEGIN
    INSERT INTO bookmark(user_id, person_id) VALUES ('00000000-0000-0000-0000-0000000000a1', -932);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN insert_denied := true;
  END;
  RESET ROLE;

  -- Anon kan hverken læse eller skrive: INGEN grant overhovedet (stærkere end RLS-filtrering —
  -- dual-review N1), så selv et bart SELECT rejser permission denied, ikke et tomt resultat.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM 1 FROM bookmark WHERE person_id=-931;
  EXCEPTION WHEN insufficient_privilege THEN anon_denied := true;
  END;
  RESET ROLE;

  IF cnt_a <> 1 THEN RAISE EXCEPTION 'FEJL: bruger A ser ikke eget bogmærke (fik %)', cnt_a; END IF;
  IF cnt_b <> 0 THEN RAISE EXCEPTION 'FEJL: RLS-læk — bruger B ser bruger A''s bogmærke'; END IF;
  IF NOT insert_denied THEN RAISE EXCEPTION 'FEJL: WITH CHECK afviste ikke insert i fremmed navn'; END IF;
  IF NOT anon_denied THEN RAISE EXCEPTION 'FEJL: anon kunne læse bookmark uden grant (vent permission denied)'; END IF;

  -- Dubletsikring: samme (user,person) igen = no-op
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
  SET LOCAL ROLE authenticated;
  INSERT INTO bookmark(person_id) VALUES (-931) ON CONFLICT (user_id,person_id) DO NOTHING;
  RESET ROLE;

  -- Cascade: slet person -931 → bogmærket forsvinder
  DELETE FROM person WHERE id=-931;
  IF EXISTS (SELECT 1 FROM bookmark WHERE person_id=-931) THEN
    RAISE EXCEPTION 'FEJL: bookmark overlevede person-sletning (cascade virkede ikke)';
  END IF;

  DELETE FROM bookmark WHERE person_id IN (-931,-932);
  DELETE FROM person WHERE id IN (-931,-932);
  DELETE FROM auth.users WHERE id IN ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a2');
  RAISE NOTICE 'OK: bookmark RLS-isolation (egen-læs, fremmed-skriv afvist, anon blokeret) + cascade + dubletsikring';
END $$;

-- ===== ikke_samme_som — persisteret identitets-afvisning (tværudgave-spec §4) =====
-- Kræver redaktion-kontekst (auth.uid() → redaktion-profil). Lokalt: sæt
-- request.jwt.claim.sub; i Supabase SQL Editor kør som funktionsejer (jf. Task 4-note).
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001', false);
DO $$
DECLARE r_ikke bigint; r_samme bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE NOTICE 'SPRINGER OVER ikke_samme_som-verify: ikke redaktion-kontekst'; RETURN; END IF;
  INSERT INTO person(id, levende, koen) VALUES (-1001,false,'mand'),(-1002,false,'kvinde') ON CONFLICT (id) DO NOTHING;

  -- evidens-triple + normalisering + INGEN citation
  r_ikke := red_ikke_samme_som(-1001,-1002);
  IF NOT EXISTS(SELECT 1 FROM relation WHERE id=r_ikke AND rolle='ikke_samme_som'
      AND subjekt_id=least(-1001,-1002) AND objekt_id=greatest(-1001,-1002))
     OR NOT EXISTS(SELECT 1 FROM assertion WHERE target_type='relation' AND target_id=r_ikke)
     OR NOT EXISTS(SELECT 1 FROM conclusion WHERE target_type='relation' AND target_id=r_ikke AND status='afklaret')
     OR EXISTS(SELECT 1 FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='relation' AND target_id=r_ikke))
  THEN RAISE EXCEPTION 'ikke_samme_som: evidens-triple/normalisering/citation-fri fejlede'; END IF;

  -- idempotens begge retninger
  IF red_ikke_samme_som(-1002,-1001) <> r_ikke THEN RAISE EXCEPTION 'ikke_samme_som: idempotens fejlede'; END IF;

  -- self afvist
  BEGIN PERFORM red_ikke_samme_som(-1001,-1001); RAISE EXCEPTION 'self ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%sig selv%' THEN RAISE; END IF; END;

  -- kontradiktion begge veje
  PERFORM red_fjern_ikke_samme_som(r_ikke);
  r_samme := red_samme_som(-1001,-1002);
  BEGIN PERFORM red_ikke_samme_som(-1001,-1002); RAISE EXCEPTION 'samme_som→ikke ikke fanget';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%allerede linket som samme_som%' THEN RAISE; END IF; END;
  PERFORM red_fjern_samme_som(r_samme);
  r_ikke := red_ikke_samme_som(-1001,-1002);
  BEGIN PERFORM red_samme_som(-1001,-1002); RAISE EXCEPTION 'ikke→samme ikke fanget';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%markeret ikke_samme_som%' THEN RAISE; END IF; END;

  -- red_relation-guard + fjern sletter evidens
  BEGIN PERFORM red_relation('person',-1001,'person',-1002,'ikke_samme_som'); RAISE EXCEPTION 'red_relation tillod ikke_samme_som';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_ikke_samme_som%' THEN RAISE; END IF; END;
  PERFORM red_fjern_ikke_samme_som(r_ikke);
  IF EXISTS(SELECT 1 FROM relation WHERE id=r_ikke) THEN RAISE EXCEPTION 'fjern slettede ikke relationen'; END IF;

  DELETE FROM person WHERE id IN (-1001,-1002);
  RAISE NOTICE 'OK: ikke_samme_som (evidens-triple, idempotens, self, kontradiktion begge veje, red_relation-guard, fjern)';
END $$;

-- drift-assert: intet person-par har BÅDE samme_som og ikke_samme_som
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM relation s JOIN relation i
      ON i.rolle='ikke_samme_som' AND s.rolle='samme_som'
     AND least(s.subjekt_id,s.objekt_id)=i.subjekt_id AND greatest(s.subjekt_id,s.objekt_id)=i.objekt_id
    WHERE s.subjekt_type='person' AND s.objekt_type='person')
  THEN RAISE EXCEPTION 'DRIFT: par med både samme_som og ikke_samme_som'; END IF;
  RAISE NOTICE 'OK: ingen samme_som/ikke_samme_som-drift';
END $$;

-- ===== Problem 2 — konkurrerende forældrefamilie-påstande (spec §10, RPC/constraint/guard) =====
-- Syntetiske negativ-id-fixtures (rører ikke rigtige data). Backfill-komplethed + global P1-drift
-- verificeres separat mod ren single-edition-bed (multi-edition daa_test2 ville falsk-bestå, se docs/reviews/29).
DO $$
DECLARE
  v jsonb; a1 bigint; a2 bigint; v_fam bigint; v_status text; v_konf text; v_valgt bigint; v_slotfact bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE NOTICE 'SPRINGER OVER forældre-konflikt-verify: ikke redaktion-kontekst'; RETURN; END IF;

  -- Defensiv oprydning FØR (så re-runs efter en halv-fejlet kørsel er sikre — og family_member
  -- kan indsættes plain: den DEFERRABLE EXCLUDE kan ikke bruges som ON CONFLICT-arbiter).
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001;
  DELETE FROM family_member WHERE person_id IN (-2001,-2002,-2003,-2004,-2005) OR family_id IN (-3001,-3002,-3099);
  DELETE FROM family WHERE id IN (-3001,-3002,-3099);
  DELETE FROM person WHERE id IN (-2001,-2002,-2003,-2004,-2005);
  DELETE FROM source WHERE id IN (-9001,-9002);

  -- fixtures: barn -2001; udgave-1-familie -3001 (partnere -2002/-2003); udgave-2-familie -3002 (-2004/-2005);
  -- -3099 = tom familie til rå-EXCLUDE-test. Barn starter projiceret i -3001 (udgave 1's graf).
  INSERT INTO person(id, levende, koen) VALUES
    (-2001,false,'mand'),(-2002,false,'mand'),(-2003,false,'kvinde'),(-2004,false,'mand'),(-2005,false,'kvinde');
  INSERT INTO family(id, type) VALUES (-3001,'vielse'),(-3002,'vielse'),(-3099,'vielse');
  INSERT INTO family_member(family_id, person_id, rolle) VALUES
    (-3001,-2002,'partner'),(-3001,-2003,'partner'),(-3002,-2004,'partner'),(-3002,-2005,'partner'),(-3001,-2001,'barn');
  INSERT INTO source(id, udgave) VALUES (-9001,'TEST udgave 1'),(-9002,'TEST udgave 2');

  -- (a) selv-helende korroboration: påstand matcher barnets projicerede række → afklaret, ingen konflikt.
  v := red_tilfoej_foraeldre_paastand(-2001, -3001, -9001, 's.1', 'udg1 citat');
  a1 := (v->>'assertion_id')::bigint;
  v_slotfact := (v->>'fact_id')::bigint;
  IF (v->>'konflikt')::boolean THEN RAISE EXCEPTION 'a: selv-helende gav konflikt'; END IF;
  IF NOT EXISTS(SELECT 1 FROM assertion WHERE id=a1 AND objekt_type='family' AND objekt_id=-3001 AND vaerdi_tekst='barn')
     OR NOT EXISTS(SELECT 1 FROM citation WHERE assertion_id=a1 AND source_id=-9001)
     OR NOT EXISTS(SELECT 1 FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact AND valgt_assertion_id=a1 AND status='afklaret')
  THEN RAISE EXCEPTION 'a: evidens-tripel/afklaret-konklusion fejlede'; END IF;

  -- (b) idempotens: samme familie + samme kilde → samme id'er, intet nyt.
  v := red_tilfoej_foraeldre_paastand(-2001, -3001, -9001);
  IF (v->>'assertion_id')::bigint <> a1 OR NOT (v->>'idempotent')::boolean THEN RAISE EXCEPTION 'b: idempotens fejlede'; END IF;

  -- (c) korroboration fra ANDEN kilde (samme familie) → ekstra påstand, stadig afklaret, ingen konflikt.
  v := red_tilfoej_foraeldre_paastand(-2001, -3001, -9002, 's.5', 'udg2 enig');
  IF (v->>'konflikt')::boolean THEN RAISE EXCEPTION 'c: korroboration gav konflikt'; END IF;
  IF (SELECT status FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact) <> 'afklaret'
  THEN RAISE EXCEPTION 'c: status ikke afklaret efter korroboration'; END IF;

  -- (d) konflikt: rival peger på anden familie → omstridt + konfidens-eskalering, valgt URØRT.
  v := red_tilfoej_foraeldre_paastand(-2001, -3002, -9002, 's.9', 'udg2 anden far');
  a2 := (v->>'assertion_id')::bigint;
  IF NOT (v->>'konflikt')::boolean THEN RAISE EXCEPTION 'd: konflikt ikke detekteret'; END IF;
  SELECT status, valgt_assertion_id INTO v_status, v_valgt FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact;
  IF v_status <> 'omstridt' THEN RAISE EXCEPTION 'd: status ikke omstridt'; END IF;
  IF v_valgt <> a1 THEN RAISE EXCEPTION 'd: valgt_assertion_id blev rørt (skal pege på udgave 1)'; END IF;
  IF (SELECT konfidens FROM family_member WHERE person_id=-2001 AND rolle='barn' AND family_id=-3001) <> 'omstridt'
  THEN RAISE EXCEPTION 'd: barn-rækkens konfidens ikke eskaleret til omstridt'; END IF;

  -- (e) konflikt-view rapporterer to distinkte familier.
  IF NOT EXISTS(SELECT 1 FROM red_foraeldre_konflikt WHERE person_id=-2001 AND antal_familier=2 AND status='omstridt')
  THEN RAISE EXCEPTION 'e: red_foraeldre_konflikt viste ikke konflikten'; END IF;

  -- (f) adjudikér udgave 2: re-peg + flyt projektion + konfidens sat, i ét kald. P1 holder.
  PERFORM red_vaelg_foraeldre(a2, 'sikker');
  SELECT valgt_assertion_id, status INTO v_valgt, v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slotfact;
  IF v_valgt <> a2 OR v_status <> 'afklaret' THEN RAISE EXCEPTION 'f: konklusion ikke re-pegget/afklaret'; END IF;
  SELECT family_id INTO v_fam FROM family_member WHERE person_id=-2001 AND rolle='barn';
  IF v_fam <> -3002 THEN RAISE EXCEPTION 'f: barn ikke flyttet til udgave-2-familie (P1)'; END IF;
  IF (SELECT konfidens FROM family_member WHERE person_id=-2001 AND rolle='barn') <> 'sikker'
  THEN RAISE EXCEPTION 'f: konfidens ikke sat'; END IF;

  -- (g) skift tilbage til udgave 1: flytter projektion tilbage (begge påstande stadig bevaret).
  PERFORM red_vaelg_foraeldre(a1);
  SELECT family_id INTO v_fam FROM family_member WHERE person_id=-2001 AND rolle='barn';
  IF v_fam <> -3001 THEN RAISE EXCEPTION 'g: barn ikke flyttet tilbage til udgave 1'; END IF;
  IF (SELECT count(*) FROM assertion WHERE target_type='fact' AND target_id=v_slotfact AND objekt_type='family') < 2
  THEN RAISE EXCEPTION 'g: en påstand gik tabt ved adjudikation'; END IF;

  -- (h) forældre_ukendt-kontradiktion: markér, forsøg vælg → RAISE; tilbagetræk, retry virker.
  v := red_upsert_fakta('person',-2001,'forældre_ukendt','ukendt');
  BEGIN PERFORM red_vaelg_foraeldre(a2); RAISE EXCEPTION 'h: forældre_ukendt-guard fyrede ikke';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%forældre_ukendt%' THEN RAISE; END IF; END;
  PERFORM red_tilbagetraek_fakta((v->>'fact_id')::bigint);
  PERFORM red_vaelg_foraeldre(a1);  -- virker igen

  -- (i) guards: de tre fakta-RPC'er afviser 'forældrefamilie'.
  BEGIN PERFORM red_upsert_fakta('person',-2001,'forældrefamilie','x'); RAISE EXCEPTION 'i: red_upsert_fakta tillod forældrefamilie';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_tilfoej_foraeldre_paastand%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_opret_fakta('person',-2001,'forældrefamilie','x'); RAISE EXCEPTION 'i: red_opret_fakta tillod forældrefamilie';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_tilfoej_foraeldre_paastand%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_tilfoej_oplysning(v_slotfact,'x'); RAISE EXCEPTION 'i: red_tilfoej_oplysning tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_tilfoej_foraeldre_paastand%' THEN RAISE; END IF; END;

  -- (i2) konklusions-dørene afviser forældrefamilie-slottet (lukker P1-hullet: re-peg uden projektion).
  BEGIN PERFORM red_set_konklusion(a1); RAISE EXCEPTION 'i2: red_set_konklusion tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%red_vaelg_foraeldre%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_edit_oplysning(a1,'x'); RAISE EXCEPTION 'i2: red_edit_oplysning tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%uforanderlige%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_slet_oplysning(a1); RAISE EXCEPTION 'i2: red_slet_oplysning tillod forældrefamilie-slot';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%uforanderlige%' THEN RAISE; END IF; END;

  -- (j) red_tilfoej_barn venligt prætjek: barn har allerede fødselsfamilie (-3001) → venlig fejl.
  BEGIN PERFORM red_tilfoej_barn(-3002, -2001); RAISE EXCEPTION 'j: red_tilfoej_barn tillod anden fødselsfamilie';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%allerede en fødselsfamilie%' THEN RAISE; END IF; END;

  -- (k) rå EXCLUDE-værn: direkte INSERT af en anden 'barn'-række afvises (deferred → tving med SET CONSTRAINTS).
  BEGIN
    INSERT INTO family_member(family_id, person_id, rolle) VALUES (-3099, -2001, 'barn');
    SET CONSTRAINTS family_member_en_foedselsfamilie IMMEDIATE;
    RAISE EXCEPTION 'k: EXCLUDE tillod to fødselsfamilier';
  EXCEPTION WHEN exclusion_violation THEN NULL; END;

  -- P1 lokal-invariant: afklaret slot ⇒ valgt assertions objekt_id = barn-rækkens family_id.
  IF EXISTS(
    SELECT 1 FROM conclusion c JOIN assertion aa ON aa.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_slotfact AND c.status='afklaret'
      AND aa.objekt_id <> (SELECT family_id FROM family_member WHERE person_id=-2001 AND rolle='barn'))
  THEN RAISE EXCEPTION 'P1: valgt slot-familie ≠ projiceret barn-række'; END IF;

  -- cleanup (FK-ordnet)
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001);
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id=-2001;
  DELETE FROM family_member WHERE person_id IN (-2001,-2002,-2003,-2004,-2005) OR family_id IN (-3001,-3002,-3099);
  DELETE FROM family WHERE id IN (-3001,-3002,-3099);
  DELETE FROM person WHERE id IN (-2001,-2002,-2003,-2004,-2005);
  DELETE FROM source WHERE id IN (-9001,-9002);
  RAISE NOTICE 'OK: forældre-konflikt (selv-helende, idempotens, korroboration, konflikt→omstridt+konfidens, view, vælg+flyt+P1, skift-tilbage, forældre_ukendt-guard, 3 fakta-guards, 3 konklusions-dør-guards, tilfoej_barn-prætjek, rå EXCLUDE)';
END $$;

-- ===== Problem 2 — undo af adjudikation (fortryd genopretter BÅDE conclusion og barn-række) =====
-- Beviser at family_member ER versions-sporet (red_flyt_barn's flytning er undo-bar) og at fortryd-
-- replay ikke tripper EXCLUDE. Eget change_set pr. trin via app.change_set_id-reset (som Task 8).
DO $$
DECLARE v jsonb; a1 bigint; a2 bigint; v_slot bigint; cs bigint; v_fam bigint; v_valgt bigint; v_status text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE NOTICE 'SPRINGER OVER forældre-undo: ikke redaktion'; RETURN; END IF;
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011);
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011);
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id=-2011;
  DELETE FROM family_member WHERE person_id IN (-2011,-2012,-2013,-2014,-2015) OR family_id IN (-3011,-3012);
  DELETE FROM family WHERE id IN (-3011,-3012); DELETE FROM person WHERE id IN (-2011,-2012,-2013,-2014,-2015);

  INSERT INTO person(id, levende, koen) VALUES (-2011,false,'mand'),(-2012,false,'mand'),(-2013,false,'kvinde'),(-2014,false,'mand'),(-2015,false,'kvinde');
  INSERT INTO family(id, type) VALUES (-3011,'vielse'),(-3012,'vielse');
  INSERT INTO family_member(family_id, person_id, rolle) VALUES
    (-3011,-2012,'partner'),(-3011,-2013,'partner'),(-3012,-2014,'partner'),(-3012,-2015,'partner'),(-3011,-2011,'barn');

  v := red_tilfoej_foraeldre_paastand(-2011,-3011); a1 := (v->>'assertion_id')::bigint; v_slot := (v->>'fact_id')::bigint;
  v := red_tilfoej_foraeldre_paastand(-2011,-3012); a2 := (v->>'assertion_id')::bigint;  -- konflikt

  -- adjudikér udgave 2 i EGET change_set → flytter barn -3011→-3012 + re-peg conclusion
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_vaelg_foraeldre(a2, 'sikker');
  SELECT max(id) INTO cs FROM change_set;
  IF (SELECT family_id FROM family_member WHERE person_id=-2011 AND rolle='barn') <> -3012 THEN RAISE EXCEPTION 'undo-setup: barn ikke flyttet'; END IF;

  -- fortryd → barn tilbage i -3011, conclusion tilbage til udgave 1 (a1), INGEN exclusion_violation under replay
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(cs, false);
  SELECT family_id INTO v_fam FROM family_member WHERE person_id=-2011 AND rolle='barn';
  IF v_fam <> -3011 THEN RAISE EXCEPTION 'undo: barn-række ikke genoprettet til -3011 (fik %)', v_fam; END IF;
  SELECT valgt_assertion_id, status INTO v_valgt, v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  IF v_valgt <> a1 THEN RAISE EXCEPTION 'undo: conclusion ikke genoprettet til udgave 1 (valgt=%)', v_valgt; END IF;

  DELETE FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id=v_slot);
  DELETE FROM assertion WHERE target_type='fact' AND target_id=v_slot;
  DELETE FROM fact WHERE id=v_slot;
  DELETE FROM family_member WHERE person_id IN (-2011,-2012,-2013,-2014,-2015) OR family_id IN (-3011,-3012);
  DELETE FROM family WHERE id IN (-3011,-3012); DELETE FROM person WHERE id IN (-2011,-2012,-2013,-2014,-2015);
  RAISE NOTICE 'OK: forældre-undo (fortryd genoprettede barn-række + conclusion, ingen EXCLUDE-brud under replay)';
END $$;

-- ===== Problem 2 — slot-vedligehold på ALLE strukturelle mutatorer (review 30, B1+B2) =====
-- red_tilfoej_barn (nyt barn) opretter slot; red_slet_familie_link (fjern barn) retrakterer;
-- red_flyt_barn følger slottet — så P1/komplethed holder for alle skrive-veje (§2 "ALLE skrive-veje").
DO $$
DECLARE v_fam bigint; v_slot bigint; v_status text;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE NOTICE 'SPRINGER OVER mutator-slot-vedligehold: ikke redaktion'; RETURN; END IF;
  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002)));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002);
  DELETE FROM family_member WHERE person_id IN (-6001,-6002,-6003,-6004,-6005,-6006) OR family_id IN (-6101,-6102);
  DELETE FROM family WHERE id IN (-6101,-6102); DELETE FROM person WHERE id IN (-6001,-6002,-6003,-6004,-6005,-6006);
  INSERT INTO person(id,levende) VALUES (-6001,false),(-6002,false),(-6003,false),(-6004,false),(-6005,false),(-6006,false);
  INSERT INTO family(id,type) VALUES (-6101,'vielse'),(-6102,'vielse');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (-6101,-6003,'partner'),(-6101,-6004,'partner'),(-6102,-6005,'partner'),(-6102,-6006,'partner');

  -- (B2) genuint nyt barn via red_tilfoej_barn → slot oprettet afklaret→familien
  PERFORM red_tilfoej_barn(-6101,-6001);
  SELECT f.id INTO v_slot FROM fact f WHERE f.subjekt_type='person' AND f.subjekt_id=-6001 AND f.faktatype='forældrefamilie';
  IF v_slot IS NULL THEN RAISE EXCEPTION 'B2: nyt barn fik intet slot'; END IF;
  IF NOT EXISTS(SELECT 1 FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_slot AND c.status='afklaret' AND a.objekt_id=-6101)
  THEN RAISE EXCEPTION 'B2: slot ikke afklaret→rette familie'; END IF;

  -- (flyt) strukturel red_flyt_barn → slot følger til -6102
  PERFORM red_flyt_barn(-6101,-6102,-6001);
  SELECT a.objekt_id INTO v_fam FROM conclusion c JOIN assertion a ON a.id=c.valgt_assertion_id
    WHERE c.target_type='fact' AND c.target_id=v_slot AND c.status='afklaret';
  IF v_fam <> -6102 THEN RAISE EXCEPTION 'flyt: slot fulgte ikke til til-familien (fik %)', v_fam; END IF;
  IF (SELECT family_id FROM family_member WHERE person_id=-6001 AND rolle='barn') <> -6102 THEN RAISE EXCEPTION 'flyt: barn-række ikke flyttet'; END IF;

  -- (B1) fjern barn-række via red_slet_familie_link → slot retrakteret (ikke forældreløst afklaret)
  PERFORM red_slet_familie_link(-6102,-6001,'barn');
  SELECT status INTO v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  IF v_status <> 'tilbagetrukket' THEN RAISE EXCEPTION 'B1: slot ikke retrakteret efter barn-slet (status=%)', v_status; END IF;

  -- (Codex #1) delete→re-add: retrakteret slot genoprettes til afklaret (ikke slotløs)
  PERFORM red_tilfoej_barn(-6102,-6001);
  SELECT status INTO v_status FROM conclusion WHERE target_type='fact' AND target_id=v_slot;
  IF v_status <> 'afklaret' THEN RAISE EXCEPTION 'Codex #1: slot ikke genoprettet afklaret ved re-add (status=%)', v_status; END IF;
  IF EXISTS(SELECT 1 FROM family_member fm WHERE fm.rolle='barn' AND fm.person_id=-6001
    AND NOT EXISTS(SELECT 1 FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id AND c.status IN ('afklaret','omstridt')
                   WHERE f.subjekt_type='person' AND f.subjekt_id=fm.person_id AND f.faktatype='forældrefamilie'))
  THEN RAISE EXCEPTION 'Codex #1: slotløs barn-række efter re-add'; END IF;

  DELETE FROM conclusion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM citation WHERE assertion_id IN (SELECT id FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002)));
  DELETE FROM assertion WHERE target_type='fact' AND target_id IN (SELECT id FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002));
  DELETE FROM fact WHERE subjekt_type='person' AND subjekt_id IN (-6001,-6002);
  DELETE FROM family_member WHERE person_id IN (-6001,-6002,-6003,-6004,-6005,-6006) OR family_id IN (-6101,-6102);
  DELETE FROM family WHERE id IN (-6101,-6102); DELETE FROM person WHERE id IN (-6001,-6002,-6003,-6004,-6005,-6006);
  RAISE NOTICE 'OK: mutator-slot-vedligehold (B2 tilføj→opret, flyt→følg, B1 slet→retrakter, delete→re-add→afklaret)';
END $$;

-- ===== Problem 2 — global backfill-komplethed + P1-drift-fanger =====
-- Gated: kun meningsfuld på en base hvor forældre-backfillen ER kørt (≥1 slot). På en ikke-backfyldt
-- base (fx frisk daa_test2) springes den over. Bemærk: dette verificerer STRUKTUR (slot+valgt+projektion);
-- citation-KILDE-korrekthed garanteres ved konstruktion af den rene single-edition-bed (§5), ikke her.
DO $$
DECLARE v_uden int; v_p1 int; v_multi int;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM fact WHERE subjekt_type='person' AND faktatype='forældrefamilie') THEN
    RAISE NOTICE 'SPRINGER OVER forældre-backfill-komplethed: ingen forældrefamilie-slots (backfill ikke kørt på denne base)';
    RETURN;
  END IF;
  -- (1) hver 'barn'-række har et slot med afklaret ELLER omstridt conclusion
  SELECT count(*) INTO v_uden FROM family_member fm WHERE fm.rolle='barn'
    AND NOT EXISTS(SELECT 1 FROM fact f JOIN conclusion c ON c.target_type='fact' AND c.target_id=f.id
                   WHERE f.subjekt_type='person' AND f.subjekt_id=fm.person_id AND f.faktatype='forældrefamilie'
                     AND c.status IN ('afklaret','omstridt'));
  IF v_uden > 0 THEN RAISE EXCEPTION 'backfill-komplethed: % barn-række(r) uden afklaret/omstridt forældrefamilie-slot', v_uden; END IF;
  -- (2) P1: afklaret slot ⇒ valgt assertions objekt_id = personens 'barn'-rækkes family_id
  SELECT count(*) INTO v_p1 FROM conclusion c
    JOIN assertion a ON a.id=c.valgt_assertion_id
    JOIN fact f ON f.id=c.target_id AND c.target_type='fact' AND f.subjekt_type='person' AND f.faktatype='forældrefamilie'
    WHERE c.status='afklaret'
      AND a.objekt_id IS DISTINCT FROM (SELECT family_id FROM family_member WHERE person_id=f.subjekt_id AND rolle='barn');
  IF v_p1 > 0 THEN RAISE EXCEPTION 'P1-drift: % afklaret slot(s) hvor valgt familie ≠ projiceret barn-række', v_p1; END IF;
  -- (3) hver slot-assertion har objekt_type='family' + eksisterende familie
  IF EXISTS(SELECT 1 FROM assertion a JOIN fact f ON f.id=a.target_id AND a.target_type='fact'
            WHERE f.faktatype='forældrefamilie' AND (a.objekt_type IS DISTINCT FROM 'family'
              OR NOT EXISTS(SELECT 1 FROM family fa WHERE fa.id=a.objekt_id)))
  THEN RAISE EXCEPTION 'backfill: slot-assertion m. ugyldig/manglende familie-reference'; END IF;
  SELECT count(*) INTO v_multi FROM red_foraeldre_konflikt;
  RAISE NOTICE 'OK: forældre-backfill-komplethed + P1-drift (alle barn-rækker slot-dækket, projektion konsistent; % åbne konflikter i red_foraeldre_konflikt)', v_multi;
END $$;
SELECT set_config('request.jwt.claim.sub','', false);

-- ===== Sikkerheds-hærdning: interne _-helpers ikke anon-kaldbare (review 30/fable) =====
DO $$
DECLARE fn text; v_bad text := '';
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    '_delete_relation_evidence(bigint)','_version_upsert_row(text, jsonb)','_version_delete_row(text, jsonb)',
    '_row_pk(text, jsonb)','_version_pk_where(text, jsonb)','_version_current_row(text, jsonb)']
  LOOP
    IF has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('authenticated', fn, 'EXECUTE') THEN
      v_bad := v_bad || fn || ' ';
    END IF;
  END LOOP;
  IF v_bad <> '' THEN RAISE EXCEPTION 'Sikkerhed: anon/authenticated har EXECUTE på interne helper(e): %', v_bad; END IF;
  -- _delete_relation_evidence har DESUDEN en rolle-guard (belt-and-suspenders)
  BEGIN PERFORM set_config('request.jwt.claim.sub','',true); PERFORM _delete_relation_evidence(-999999);
    RAISE EXCEPTION 'Sikkerhed: _delete_relation_evidence-guard fyrede ikke';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%relations-slet-helper%' THEN RAISE; END IF; END;
  -- _regen_mentions_for er BEVIDST ikke revoked (SECURITY INVOKER-trigger kalder den som skriveren)
  RAISE NOTICE 'OK: interne _-helpers ikke anon-kaldbare (REVOKE + guard); _regen_mentions_for bevidst undtaget';
END $$;

-- ===== Dato-hærdning A1: additive felter (plan Spor A, 2026-07-17) =====
DO $$
DECLARE v_mangler text;
BEGIN
  DELETE FROM assertion WHERE id BETWEEN -987654326 AND -987654321;  -- ryd evt. residual fra fejlet kørsel
  -- (1) date_certainty-kolonne findes
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='assertion' AND column_name='date_certainty') THEN
    RAISE EXCEPTION 'A1: assertion.date_certainty-kolonne mangler'; END IF;
  -- (2) CHECK afviser ugyldig værdi
  BEGIN
    INSERT INTO assertion (id,target_type,target_id,date_certainty) VALUES (-987654321,'fact',-1,'sikker-forkert');
    RAISE EXCEPTION 'A1: date_certainty-CHECK fyrede ikke på ugyldig værdi';
  EXCEPTION WHEN check_violation THEN NULL;  -- forventet
  END;
  -- (3) gyldige værdier + NULL tillades
  INSERT INTO assertion (id,target_type,target_id,date_certainty) VALUES
    (-987654322,'fact',-1,'certain'),(-987654323,'fact',-1,'uncertain'),
    (-987654324,'fact',-1,'ambiguous'),(-987654325,'fact',-1,NULL);
  -- (4) calendar-DEFAULT anvendes når kolonnen udelades
  INSERT INTO assertion (id,target_type,target_id) VALUES (-987654326,'fact',-1);
  IF (SELECT calendar FROM assertion WHERE id=-987654326) IS DISTINCT FROM 'gregoriansk' THEN
    RAISE EXCEPTION 'A1: calendar-DEFAULT er ikke gregoriansk'; END IF;
  -- (5) faktavokabular seedet (kerne-dato-/event-typer)
  SELECT string_agg(w.code,' ') INTO v_mangler FROM (VALUES
    ('fødsel'),('dåb'),('død'),('begravelse'),('floruit'),('naturalisering'),('introduktion_ridderhus'))
    AS w(code) WHERE NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND vocab.code=w.code);
  IF v_mangler IS NOT NULL THEN RAISE EXCEPTION 'A1: faktatype-vokabular mangler: %', v_mangler; END IF;
  DELETE FROM assertion WHERE id BETWEEN -987654326 AND -987654321;  -- oprydning
  RAISE NOTICE 'OK: dato-hærdning A1 (date_certainty-kolonne+CHECK, calendar-default, faktavokabular)';
END $$;

-- ===== K2: staging-gate skjuler ny-udgave-poster for anon (plan Konvergens/K2, 2026-07-17) =====
DO $$
DECLARE vis_staged int; vis_ikke_staged int; vis_null_staged int;
BEGIN
  DELETE FROM person WHERE id BETWEEN -987655003 AND -987655001;  -- ryd residual
  -- afdød (levende=FALSE), ikke-privat: STAGED skal skjule, IKKE-staged skal vise
  INSERT INTO person (id, levende, privat, staged) VALUES
    (-987655001, false, false, true),    -- staged  → skjult
    (-987655002, false, false, false),   -- ikke-staged → synlig
    (-987655003, false, false, NULL);    -- NULL staged → synlig (fail-open-sikkert: kun loader sætter TRUE)
  IF person_offentlig(-987655001) THEN
    RAISE EXCEPTION 'K2: staged person er offentlig (skulle være skjult)'; END IF;
  IF NOT person_offentlig(-987655002) THEN
    RAISE EXCEPTION 'K2: ikke-staged afdød person er skjult (skulle være synlig)'; END IF;
  IF NOT person_offentlig(-987655003) THEN
    RAISE EXCEPTION 'K2: NULL-staged person er skjult (skulle være synlig — default)'; END IF;
  -- Test den FAKTISKE tabel-policy som anon, ikke kun hjælperen. Det fanger drift
  -- hvor person_offentlig er korrekt, men person.anon_read glemmer staged.
  SET LOCAL ROLE anon;
  SELECT count(*) INTO vis_staged FROM person WHERE id=-987655001;
  SELECT count(*) INTO vis_ikke_staged FROM person WHERE id=-987655002;
  SELECT count(*) INTO vis_null_staged FROM person WHERE id=-987655003;
  RESET ROLE;
  IF NOT (vis_staged=0 AND vis_ikke_staged=1 AND vis_null_staged=1) THEN
    RAISE EXCEPTION 'K2 person-RLS FEJL: staged=% (vent 0), ikke-staged=% (vent 1), NULL=% (vent 1)',
      vis_staged, vis_ikke_staged, vis_null_staged;
  END IF;
  DELETE FROM person WHERE id BETWEEN -987655003 AND -987655001;
  RAISE NOTICE 'OK: K2 staging-gate (hjælper + faktisk anon person-RLS)';
END $$;

-- ===== Levende feed fase 2: haendelse-skema, RLS, RPC og fortryd =====
DO $$
DECLARE
  v_live int; v_hidden int; v_private int; v_public int; v_auth_hidden int;
  v_uid uuid := '00000000-0000-0000-0000-0000000000f2';
  v_cs bigint; v_undo bigint; v_before jsonb; v_after jsonb; v_result jsonb;
BEGIN
  IF to_regclass('public.haendelse') IS NULL THEN
    RAISE EXCEPTION 'Fase2: haendelse-tabellen mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='haendelse') THEN
    RAISE EXCEPTION 'Fase2: haendelse mangler i version_pk_registry';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgrelid='public.haendelse'::regclass AND tgname='trg_log_haendelse'
                   AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase2: trg_log_haendelse mangler';
  END IF;

  DELETE FROM haendelse WHERE id BETWEEN -987656029 AND -987656020;
  DELETE FROM narrative WHERE id BETWEEN -987656019 AND -987656010;
  DELETE FROM person WHERE id IN (-987656001,-987656002);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-987656001,true,false,false),(-987656002,false,false,false);
  INSERT INTO narrative(id,subjekt_type,subjekt_id,tekst,privat) VALUES
    (-987656011,'person',-987656001,'Levende testnarrativ',false),
    (-987656012,'person',-987656002,'Offentligt testnarrativ',false),
    (-987656013,'person',-987656002,'Privat testnarrativ',true);
  INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,feed_status) VALUES
    (-987656021,'person',-987656001,-987656011,'live','Levende hændelse','kandidat'),
    (-987656022,'person',-987656002,-987656012,'hidden','Skjult hændelse','skjult'),
    (-987656023,'person',-987656002,-987656013,'private','Privat hændelse','kandidat'),
    (-987656024,'person',-987656002,-987656012,'public','Offentlig hændelse','kandidat');
  BEGIN
    INSERT INTO haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,feed_status)
      VALUES (-987656025,'person',-987656002,-987656012,'invalid','Ugyldig','ingen');
    RAISE EXCEPTION 'Fase2: feed_status-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_live FROM haendelse WHERE id=-987656021;
  SELECT count(*) INTO v_hidden FROM haendelse WHERE id=-987656022;
  SELECT count(*) INTO v_private FROM haendelse WHERE id=-987656023;
  SELECT count(*) INTO v_public FROM haendelse WHERE id=-987656024;
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_auth_hidden FROM haendelse WHERE id=-987656022;
  RESET ROLE;
  IF v_live<>0 OR v_hidden<>0 OR v_private<>0 OR v_public<>1 OR v_auth_hidden<>0 THEN
    RAISE EXCEPTION 'Fase2 RLS FEJL live=% hidden=% private=% public=% auth_hidden=%',
      v_live,v_hidden,v_private,v_public,v_auth_hidden;
  END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM red_set_haendelse_status(-987656024,'interessant');
    RAISE EXCEPTION 'Fase2: ikke-redaktør blev ikke afvist';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF;
  END;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'fase2@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','fase2@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  BEGIN
    PERFORM red_set_haendelse_status(-987656024,'ingen');
    RAISE EXCEPTION 'Fase2: ugyldig RPC-status blev ikke afvist';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE '%ikke en gyldig feed-status%' THEN RAISE; END IF;
  END;

  SELECT to_jsonb(h)-'feed_status' INTO v_before FROM haendelse h WHERE id=-987656024;
  PERFORM red_set_haendelse_status(-987656024,'interessant');
  v_cs := current_setting('app.change_set_id')::bigint;
  IF (SELECT feed_status FROM haendelse WHERE id=-987656024) <> 'interessant' THEN
    RAISE EXCEPTION 'Fase2: RPC satte ikke interessant';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_result := red_fortryd_change_set(v_cs,false);
  v_undo := (v_result->>'reversal_change_set')::bigint;
  SELECT to_jsonb(h)-'feed_status' INTO v_after FROM haendelse h WHERE id=-987656024;
  IF (SELECT feed_status FROM haendelse WHERE id=-987656024) <> 'kandidat' OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'Fase2: fortryd genskabte ikke status/projektionskolonner';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  DELETE FROM haendelse WHERE id BETWEEN -987656029 AND -987656020;
  DELETE FROM narrative WHERE id BETWEEN -987656019 AND -987656010;
  DELETE FROM person WHERE id IN (-987656001,-987656002);
  DELETE FROM change_event WHERE change_set_id IN (v_cs,v_undo);
  DELETE FROM change_set WHERE id=v_undo;
  DELETE FROM change_set WHERE id=v_cs;
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: levende feed fase 2 (haendelse CHECK/RLS/RPC/versionering/fortryd)';
END $$;

-- ===== Mediehåndtering fase 1: metadata, genopret, upload-signatur og undo =====
DO $$
DECLARE v_id bigint; v_upload bigint; v_cs bigint; v_cs_foer int; v_cs_efter int;
        v_relation bigint; v_sha text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  v_id := (SELECT coalesce(max(id),0)+1 FROM media);
  INSERT INTO media(id,slags,titel,kunstner,datering,upload_status,maa_publiceres)
    VALUES (v_id,'foto','Gammel titel','Gammel kunstner','1699','klar',false);

  SELECT count(*) INTO v_cs_foer FROM change_set;
  PERFORM red_opdater_media(v_id, 'Ny titel', NULL, '', 'ca. 1700');
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND titel='Ny titel' AND slags='foto'
                 AND kunstner IS NULL AND datering='ca. 1700') THEN
    RAISE EXCEPTION 'FEJL: red_opdater_media overholdt ikke NULL/tom-streng-kontrakten';
  END IF;
  SELECT count(*) INTO v_cs_efter FROM change_set;
  IF v_cs_efter <> v_cs_foer + 1 THEN
    RAISE EXCEPTION 'FEJL: red_opdater_media oprettede % change_set (vent 1)', v_cs_efter-v_cs_foer;
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_opdater_media(v_id, NULL, '', NULL, NULL);
    RAISE EXCEPTION 'FEJL: tom slags blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Slags kan ikke ryddes%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_opdater_media(-999999999, 'Ukendt', NULL, NULL, NULL);
    RAISE EXCEPTION 'FEJL: ukendt media-id blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Media % findes ikke%' THEN RAISE; END IF;
  END;
  SELECT max(id) INTO v_cs FROM change_set;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs, false);
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_id AND titel='Gammel titel' AND kunstner='Gammel kunstner') THEN
    RAISE EXCEPTION 'FEJL: undo af media-metadata gendannede ikke rækken';
  END IF;

  UPDATE media SET upload_status='fjernet' WHERE id=v_id;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_genopret_media(v_id);
  IF (SELECT upload_status FROM media WHERE id=v_id) <> 'klar' THEN
    RAISE EXCEPTION 'FEJL: red_genopret_media satte ikke klar';
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_genopret_media(v_id);
    RAISE EXCEPTION 'FEJL: genopret-guard accepterede et ikke-fjernet medie';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun genoprette et fjernet medie%' THEN RAISE; END IF;
  END;

  PERFORM set_config('app.change_set_id','',true);
  v_sha := '__verify_fase3_sha_' || v_id;
  v_upload := red_upload_media(
    p_slags => 'foto', p_titel => 'Upload-test',
    p_storage_path => '__verify__/fase1-' || v_id || '.jpg', p_mime => 'image/jpeg',
    p_kunstner => 'Testkunstner', p_datering => '1701',
    p_sha256 => v_sha,
    p_rettigheder_status => 'ukendt', p_maa_publiceres => false
  );
  IF NOT EXISTS (SELECT 1 FROM media WHERE id=v_upload AND kunstner='Testkunstner' AND datering='1701'
                 AND sha256=v_sha AND created_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FEJL: red_upload_media førte ikke metadata/sha256/created_at igennem';
  END IF;
  BEGIN
    PERFORM red_upload_media(
      p_slags => 'foto', p_titel => 'Upload-dublet-test',
      p_storage_path => '__verify__/fase1-dublet-' || v_id || '.jpg', p_mime => 'image/jpeg',
      p_sha256 => v_sha,
      p_rettigheder_status => 'ukendt', p_maa_publiceres => false
    );
    RAISE EXCEPTION 'FEJL: red_upload_media accepterede gentaget sha256';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Medie med samme indhold findes allerede (sha256=%' THEN RAISE; END IF;
  END;
  v_relation := red_relation('person',-999951,'media',v_upload,'afbildet');
  IF v_relation IS NULL OR NOT EXISTS (
    SELECT 1 FROM relation
    WHERE id=v_relation AND subjekt_type='person' AND subjekt_id=-999951
      AND objekt_type='media' AND objekt_id=v_upload AND rolle='afbildet'
  ) THEN
    RAISE EXCEPTION 'FEJL: første red_relation-kald returnerede/indsatte ikke relationen';
  END IF;
  BEGIN
    PERFORM red_relation('person',-999951,'media',v_upload,'afbildet');
    RAISE EXCEPTION 'FEJL: red_relation accepterede dublet-afbildet';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'Mediet er allerede tilknyttet dette subjekt' THEN RAISE; END IF;
  END;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: media fase 1 RPC + undo + upload-signatur (rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

-- ===== Mediehåndtering fase 3: fremmed unique-constraint genkastes uændret =====
-- relation_pkey-racet kan ikke reproduceres deterministisk i én sekventiel session.
-- Simulér derfor PostgreSQL-diagnostikken og assert, at den brede handler ikke
-- maskerer den som en afbildet-dublet.
DO $$
DECLARE v_sqlstate text; v_constraint_name text; v_message text;
BEGIN
  BEGIN
    BEGIN
      RAISE EXCEPTION 'simuleret relation_pkey-kollision'
        USING ERRCODE='23505', CONSTRAINT='relation_pkey';
    EXCEPTION WHEN unique_violation THEN
      DECLARE v_constraint_name text;
      BEGIN
        GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
        IF v_constraint_name = 'relation_afbildet_uidx' THEN
          RAISE EXCEPTION 'Mediet er allerede tilknyttet dette subjekt';
        END IF;
        RAISE;
      END;
    END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_sqlstate = RETURNED_SQLSTATE,
      v_constraint_name = CONSTRAINT_NAME,
      v_message = MESSAGE_TEXT;
  END;

  IF v_sqlstate IS DISTINCT FROM '23505'
     OR v_constraint_name IS DISTINCT FROM 'relation_pkey'
     OR v_message IS DISTINCT FROM 'simuleret relation_pkey-kollision' THEN
    RAISE EXCEPTION 'FEJL: fremmed unique-fejl blev ændret: sqlstate=%, constraint=%, message=%',
      v_sqlstate, v_constraint_name, v_message;
  END IF;
  RAISE NOTICE 'OK: fremmed unique-constraint genkastes uændret';
END $$;

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

  -- Guard: kun 'klar' (status='fjernet')
  UPDATE media SET upload_status='fjernet' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_tredje_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: fjernet medie kunne erstattes';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun erstatte filen på et klart medie%' THEN RAISE; END IF;
  END;

  -- Guard: kun 'klar' (status='kladde') — dækker den anden ikke-'klar' status,
  -- ikke kun 'fjernet'
  UPDATE media SET upload_status='kladde' WHERE id=v_id;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(v_id,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_fjerde_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: kladde-medie kunne erstattes';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Kan kun erstatte filen på et klart medie%' THEN RAISE; END IF;
  END;
  UPDATE media SET upload_status='klar' WHERE id=v_id;

  -- Guard: nonexistent media id
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_erstat_media_fil(-999999999,'redaktor/dd/y.jpg','image/jpeg',1,1,1,'__f4_femte_sha_'||v_id);
    RAISE EXCEPTION 'FEJL: ikke-eksisterende media blev accepteret';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Media % findes ikke%' THEN RAISE; END IF;
  END;

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

-- ===== Mediehåndtering fase 4: red_udrens_media + preview (den rigtige sletning) =====
-- Review 34: seeder BEVIDST alle syv polymorfe ankre (relation, mention, fakta via LIVE
-- red_set_media_rettigheder, story via red_opret_story, narrativ via red_upsert_narrativ,
-- note direkte, forslag via LIVE red_suggest) og rydder dem én ad gangen — den oprindelige
-- plan seedede kun to og passerede grøn med H1/H3 til stede. H2 (atomisk guard+slet) er ikke
-- serielt testbar; den verificeres ved kode-form (ét DELETE-statement, Step 3) + race-
-- bagstopper-fejlteksten. Forslags-ankeret (Codex-review efter H1/H3) seedes via den RIGTIGE
-- red_suggest-RPC (ikke en hånd-rullet INSERT) — den kræver kun auth.uid() IS NOT NULL, ingen
-- rolle-check, så et almindeligt medlem (anden uid end redaktøren ovenfor) kan kalde den direkte.
DO $$
DECLARE v_id bigint; v_rel bigint; v_story bigint; v_narr bigint; v_note bigint; v_forslag bigint;
        v_prev jsonb; v_res jsonb; v_cs bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  INSERT INTO profiles(id,rolle,email) VALUES ('00000000-0000-0000-0000-000000000001','redaktion','t@x')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('app.change_set_id','',true);

  -- Seed: fjernet medie m. variant + ALLE syv ankre
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
  -- Forslag via LIVE red_suggest, som en anden (ikke-redaktion) logget-ind bruger.
  INSERT INTO auth.users(id,email) VALUES
    ('00000000-0000-0000-0000-000000000002','media-fase4-medlem@test.invalid') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
  v_forslag := red_suggest('fakta','media',v_id,'titel','Foreslået ny titel');
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);

  -- Preview: blokeret af alle syv kategorier, med tællinger + stier
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR (v_prev->>'antal_tilknytninger')::int <> 1
     OR (v_prev->>'antal_mentions')::int <> 1
     OR (v_prev->>'antal_fakta')::int <> 2          -- licens + kildehenvisning (tredje felt NULL)
     OR (v_prev->>'antal_stories')::int <> 1
     OR (v_prev->>'antal_narrativer')::int <> 1
     OR (v_prev->>'antal_noter')::int <> 1
     OR (v_prev->>'antal_forslag')::int <> 1
     OR jsonb_array_length(v_prev->'stier') <> 2
     OR jsonb_array_length(v_prev->'blokeringer') <> 7 THEN
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

  -- Udrens blokeret af forslag i kø (Codex-review efter H1/H3 — suggestion som 7. anker)
  v_prev := red_udrens_media_preview(v_id);
  IF (v_prev->>'kan_udrenses')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_prev->'blokeringer') b
                    WHERE b LIKE '%forslag i kø%') THEN
    RAISE EXCEPTION 'FEJL: preview grøn/uklar trods forslag i kø: %', v_prev;
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    PERFORM red_udrens_media(v_id);
    RAISE EXCEPTION 'FEJL: udrens accepterede medie med forslag i kø';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'Mediet har forslag i kø%' THEN RAISE; END IF;
  END;
  DELETE FROM suggestion WHERE id=v_forslag;  -- ingen retract-RPC findes; direkte SQL er OK til test-oprydning

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
  -- Intet forældreløst tilbage: fact-kæden, story, narrativ, note og forslag blev ryddet FØR
  -- udrens (blokerings-modellen), og efter udrens må INTET pege på det slettede medie (H1-garantien)
  IF EXISTS (SELECT 1 FROM fact WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM story WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM narrative WHERE subjekt_type='media' AND subjekt_id=v_id)
     OR EXISTS (SELECT 1 FROM note WHERE target_type='media' AND target_id=v_id)
     OR EXISTS (SELECT 1 FROM text_mention WHERE maal_type='media' AND maal_id=v_id)
     OR EXISTS (SELECT 1 FROM suggestion WHERE subjekt_type='media' AND subjekt_id=v_id) THEN
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
    RAISE NOTICE 'OK: media fase 4 udrens (alle syv anker-guards, paritet, DELETE-log, fortryd uden varianter, rullet tilbage)';
  ELSE RAISE; END IF;
END $$;

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
  IF (SELECT kvalifikator->>'primaer' FROM relation WHERE id=v_r1) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'FEJL: primaer-flag blev ikke sat';
  END IF;

  -- Skift til m2 → søskende-nulstilling af m1
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_saet_portraet(-999943, v_m2);
  IF (SELECT kvalifikator FROM relation WHERE id=v_r1) IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: søskende-nulstilling efterlod kvalifikator på m1 (%)',
      (SELECT kvalifikator FROM relation WHERE id=v_r1);
  END IF;
  IF (SELECT kvalifikator->>'primaer' FROM relation WHERE id=v_r2) IS DISTINCT FROM 'true' THEN
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

-- ===== Levende feed fase 3: story/story_kilde/feed_pin — skema, RLS, RPC'er og fortryd =====
DO $$
DECLARE
  v_pub int; v_kladde int; v_levende int; v_privat int;
  v_kilde int; v_kilde_kladde int; v_pin int; v_auth_pub int; v_auth_kladde int;
  v_uid uuid := '00000000-0000-0000-0000-0000000000f3';
  v_seed_af uuid := '00000000-0000-0000-0000-0000000000f4';
  v_story bigint; v_cs_opret bigint; v_cs_status bigint;
  v_undo1 bigint; v_undo2 bigint; v_res jsonb;
BEGIN
  IF to_regclass('public.story') IS NULL THEN RAISE EXCEPTION 'Fase3: story-tabellen mangler'; END IF;
  IF to_regclass('public.story_kilde') IS NULL THEN RAISE EXCEPTION 'Fase3: story_kilde mangler'; END IF;
  IF to_regclass('public.feed_pin') IS NULL THEN RAISE EXCEPTION 'Fase3: feed_pin mangler'; END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='story' AND skip_cols='{}') THEN
    RAISE EXCEPTION 'Fase3: story mangler i version_pk_registry uden skip_cols (fuld versionering, §3.7)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='feed_pin' AND skip_cols='{}') THEN
    RAISE EXCEPTION 'Fase3: feed_pin mangler i version_pk_registry uden skip_cols';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.story'::regclass
                 AND tgname='trg_log_story' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase3: trg_log_story mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.feed_pin'::regclass
                 AND tgname='trg_log_feed_pin' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase3: trg_log_feed_pin mangler';
  END IF;

  -- Oprydning + seeds
  DELETE FROM feed_pin WHERE kort_noegle LIKE 'verify3:%';
  DELETE FROM story_kilde WHERE id BETWEEN -987657029 AND -987657020;
  DELETE FROM story WHERE id BETWEEN -987657019 AND -987657010;
  DELETE FROM source WHERE id=-987657031;
  DELETE FROM person WHERE id IN (-987657001,-987657002);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-987657001,true,false,false),(-987657002,false,false,false);
  INSERT INTO source(id,titel,udgave) VALUES (-987657031,'Verify-kilde','1939');
  INSERT INTO story(id,subjekt_type,subjekt_id,tekst,status,privat,skabt_af) VALUES
    (-987657011,'person',-987657002,'Publiceret offentlig historie','publiceret',false,v_seed_af),
    (-987657012,'person',-987657002,'Kladde-historie','kladde',false,v_seed_af),
    (-987657013,'person',-987657001,'Publiceret om levende','publiceret',false,v_seed_af),
    (-987657014,'person',-987657002,'Publiceret men privat','publiceret',true,v_seed_af);
  INSERT INTO story_kilde(id,story_id,source_id,side) VALUES
    (-987657021,-987657011,-987657031,'112'),
    (-987657022,-987657012,-987657031,'7');
  INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af) VALUES
    (-987657041,'verify3:portrait:1','pin',v_seed_af);

  -- CHECK + UNIQUE
  BEGIN
    INSERT INTO story(id,subjekt_type,subjekt_id,tekst,status,skabt_af)
      VALUES (-987657015,'person',-987657002,'X','udgivet',v_seed_af);
    RAISE EXCEPTION 'Fase3: story.status-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO story(id,subjekt_type,subjekt_id,tekst,oprindelse,skabt_af)
      VALUES (-987657015,'person',-987657002,'X','ai',v_seed_af);
    RAISE EXCEPTION 'Fase3: story.oprindelse-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af)
      VALUES (-987657042,'verify3:x','fremhaev',v_seed_af);
    RAISE EXCEPTION 'Fase3: feed_pin.handling-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af)
      VALUES (-987657043,'verify3:portrait:1','skjul',v_seed_af);
    RAISE EXCEPTION 'Fase3: feed_pin UNIQUE(kort_noegle) fyrede ikke';
  EXCEPTION WHEN unique_violation THEN NULL; END;

  -- RLS-synlighed (anon + authenticated, F-02-linjen)
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_pub     FROM story WHERE id=-987657011;
  SELECT count(*) INTO v_kladde  FROM story WHERE id=-987657012;
  SELECT count(*) INTO v_levende FROM story WHERE id=-987657013;
  SELECT count(*) INTO v_privat  FROM story WHERE id=-987657014;
  SELECT count(*) INTO v_kilde        FROM story_kilde WHERE id=-987657021;
  SELECT count(*) INTO v_kilde_kladde FROM story_kilde WHERE id=-987657022;
  SELECT count(*) INTO v_pin FROM feed_pin WHERE kort_noegle='verify3:portrait:1';
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_auth_pub    FROM story WHERE id=-987657011;
  SELECT count(*) INTO v_auth_kladde FROM story WHERE id=-987657012;
  RESET ROLE;
  IF v_pub<>1 OR v_kladde<>0 OR v_levende<>0 OR v_privat<>0
     OR v_kilde<>1 OR v_kilde_kladde<>0 OR v_pin<>1
     OR v_auth_pub<>1 OR v_auth_kladde<>0 THEN
    RAISE EXCEPTION 'Fase3 RLS FEJL pub=% kladde=% levende=% privat=% kilde=% kilde_kladde=% pin=% auth_pub=% auth_kladde=%',
      v_pub,v_kladde,v_levende,v_privat,v_kilde,v_kilde_kladde,v_pin,v_auth_pub,v_auth_kladde;
  END IF;

  -- RPC-gates
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM red_opret_story('person',-987657002,'Uautoriseret');
    RAISE EXCEPTION 'Fase3: red_opret_story afviste ikke ikke-redaktør';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM red_set_feed_pin('verify3:portrait:1','pin');
    RAISE EXCEPTION 'Fase3: red_set_feed_pin afviste ikke ikke-redaktør';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF; END;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'fase3@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','fase3@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  BEGIN
    PERFORM red_set_story_status(-987657011,'udgivet');
    RAISE EXCEPTION 'Fase3: ugyldig story-status blev ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%ikke en gyldig story-status%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM red_set_feed_pin('verify3:x','fremhaev');
    RAISE EXCEPTION 'Fase3: ugyldig pin-handling blev ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%ikke en gyldig pin-handling%' THEN RAISE; END IF; END;

  -- Fortryd-assert (fuld versionering, §3.7/§3.8): begge retninger
  v_story := red_opret_story('person',-987657002,'Fortryd-testhistorie','Titel');
  v_cs_opret := current_setting('app.change_set_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  BEGIN
    PERFORM red_set_story_status(v_story,'publiceret');
    RAISE EXCEPTION 'Fase3: publicering uden kilde blev accepteret';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Story % kan ikke publiceres uden mindst én kilde' THEN RAISE; END IF;
  END;
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO story_kilde(id,story_id,source_id,side)
    VALUES (-987657023,v_story,-987657031,'112');
  PERFORM red_set_story_status(v_story,'publiceret');
  v_cs_status := current_setting('app.change_set_id')::bigint;
  IF (SELECT status FROM story WHERE id=v_story) <> 'publiceret'
     OR (SELECT publiceret_dato FROM story WHERE id=v_story) IS NULL THEN
    RAISE EXCEPTION 'Fase3: publicering satte ikke status/publiceret_dato';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(v_cs_status,false);
  v_undo1 := (v_res->>'reversal_change_set')::bigint;
  IF (SELECT status FROM story WHERE id=v_story) <> 'kladde' THEN
    RAISE EXCEPTION 'Fase3: fortryd af status-skiftet genskabte ikke kladde';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(v_cs_opret,false);
  v_undo2 := (v_res->>'reversal_change_set')::bigint;
  IF EXISTS (SELECT 1 FROM story WHERE id=v_story) THEN
    RAISE EXCEPTION 'Fase3: fortryd af opret-settet slettede ikke storyen';
  END IF;

  -- Oprydning
  PERFORM set_config('app.change_set_id','',true);
  DELETE FROM feed_pin WHERE kort_noegle LIKE 'verify3:%';
  DELETE FROM story_kilde WHERE id BETWEEN -987657029 AND -987657020;
  DELETE FROM story WHERE id BETWEEN -987657019 AND -987657010;
  DELETE FROM source WHERE id=-987657031;
  DELETE FROM person WHERE id IN (-987657001,-987657002);
  DELETE FROM change_event WHERE change_set_id IN (v_cs_opret,v_cs_status,v_undo1,v_undo2);
  DELETE FROM change_set WHERE id IN (v_undo1,v_undo2,v_cs_status,v_cs_opret);
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: levende feed fase 3 (story/story_kilde/feed_pin CHECK/UNIQUE/RLS/RPC/fuld versionering/fortryd)';
END $$;

-- Præsensliste: vokabular-seed for overhoved-faktatypen
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM vocab WHERE scheme='faktatype' AND code='overhoved') THEN
    RAISE EXCEPTION 'FEJL: vocab mangler (faktatype, overhoved) — kør db-migrations.sql';
  END IF;
END $$;

-- ===== Person OCR kvalitetsark — identitet =====
-- Selvstændig, rollback-sikker kontrakt for stabile importnøgler og den varige
-- korrektionsjournal. Den bruger rigtige constraints, trigger og SET ROLE, ikke
-- kildekode-matching, og efterlader derfor ingen verify-rækker.
DO $$
DECLARE
  v_kolonner int;
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000c1';
  v_journal_id bigint;
  v_change_set bigint := -987658099;
  v_anon_blokeret boolean := false;
  v_indsaet_blokeret boolean := false;
  v_opdater_blokeret boolean := false;
  v_slet_blokeret boolean := false;
  v_medlem_antal int;
  v_redaktor_antal int;
BEGIN
  -- Eksakte kolonnekontrakter: nullable import-/record-nøgler bevarer legacy-rækker;
  -- journalens beslutningsfelter er obligatoriske bortset fra rettelse og aktør.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='source'
                   AND column_name='import_key' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'FEJL: source.import_key mangler eller har forkert type/nullability';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='person_external_id'
                   AND column_name='record_key' AND data_type='text' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'FEJL: person_external_id.record_key mangler eller har forkert type/nullability';
  END IF;
  SELECT count(*) INTO v_kolonner
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='import_korrektion'
     AND ((column_name='id' AND data_type='bigint' AND is_nullable='NO')
       OR (column_name IN ('import_key','record_key','felt','input_fingerprint','status')
           AND data_type='text' AND is_nullable='NO')
       OR (column_name='importeret' AND data_type='jsonb' AND is_nullable='NO')
       OR (column_name='korrigeret' AND data_type='jsonb' AND is_nullable='YES')
       OR (column_name='actor_id' AND data_type='uuid' AND is_nullable='YES')
       OR (column_name='actor_navn' AND data_type='text' AND is_nullable='YES')
       OR (column_name IN ('oprettet_at','opdateret_at')
           AND data_type='timestamp with time zone' AND is_nullable='NO'));
  IF v_kolonner <> 12 THEN
    RAISE EXCEPTION 'FEJL: import_korrektion mangler eksakte kolonnekontrakter (fik %/12)', v_kolonner;
  END IF;

  -- Delvise unikke nøgler: ikke-NULL importidentiteter må aldrig dubleres,
  -- men de historiske NULL-rækker skal fortsat kunne sameksistere.
  INSERT INTO source(id,titel,import_key) VALUES
    (-987658001,'Legacy A',NULL),(-987658002,'Legacy B',NULL),
    (-987658003,'Import-nøgle','verify:ocr:source');
  BEGIN
    INSERT INTO source(id,titel,import_key) VALUES (-987658004,'Dublet','verify:ocr:source');
    RAISE EXCEPTION 'FEJL: source import_key-unikhed afviste ikke dublet';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO person(id) VALUES (-987658011),(-987658012),(-987658013),(-987658014);
  INSERT INTO person_external_id(person_id,source_id,record_key) VALUES
    (-987658011,-987658003,NULL),(-987658012,-987658003,NULL),
    (-987658013,-987658003,'verify:ocr:record');
  BEGIN
    INSERT INTO person_external_id(person_id,source_id,record_key)
      VALUES (-987658014,-987658003,'verify:ocr:record');
    RAISE EXCEPTION 'FEJL: person_external_id record_key-unikhed afviste ikke dublet';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Journalens kontrollerede vokabular og MD5-fingerprint afviser ukendte værdier.
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','ukendt-felt','ukendt','0123456789abcdef0123456789abcdef','{}','aaben');
    RAISE EXCEPTION 'FEJL: import_korrektion.felt-CHECK afviste ikke ukendt felt';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','ukendt-status','navn','0123456789abcdef0123456789abcdef','{}','ukendt');
    RAISE EXCEPTION 'FEJL: import_korrektion.status-CHECK afviste ikke ukendt status';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','forkert-hash','navn','IKKE-EN-MD5','{}','aaben');
    RAISE EXCEPTION 'FEJL: import_korrektion.input_fingerprint-CHECK afviste ikke ugyldig hash';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conrelid='public.import_korrektion'::regclass AND contype='f') THEN
    RAISE EXCEPTION 'FEJL: import_korrektion har FK til regenererbare identifikatorer';
  END IF;

  -- Registry + konkret trigger bevarer den immutable historik i change_event.
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry
                 WHERE tabel='import_korrektion' AND pk_cols=ARRAY['id']::text[] AND skip_cols='{}') THEN
    RAISE EXCEPTION 'FEJL: import_korrektion mangler korrekt version_pk_registry-række';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgrelid='public.import_korrektion'::regclass
                   AND tgname='trg_log_import_korrektion' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'FEJL: trg_log_import_korrektion mangler';
  END IF;

  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
    VALUES ('verify:ocr','journal','navn','0123456789abcdef0123456789abcdef','{"navn":"OCR"}','aaben')
    RETURNING id INTO v_journal_id;

  -- RLS og grants: anon har ingen adgang; medlemmet får ingen rækker; redaktøren
  -- må læse, men alle direkte DML-veje er lukkede indtil den kommende RPC.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM 1 FROM import_korrektion WHERE id=v_journal_id;
  EXCEPTION WHEN insufficient_privilege THEN v_anon_blokeret := true;
  END;
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_medlem_antal FROM import_korrektion WHERE id=v_journal_id;
  RESET ROLE;

  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'ocr-journal-verify@test.invalid');
  INSERT INTO profiles(id,rolle,email) VALUES (v_redaktor,'redaktion','ocr-journal-verify@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_redaktor::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_redaktor_antal FROM import_korrektion WHERE id=v_journal_id;
  BEGIN
    INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
      VALUES ('verify:ocr','redaktor-indsaet','navn','0123456789abcdef0123456789abcdef','{}','aaben');
  EXCEPTION WHEN insufficient_privilege THEN v_indsaet_blokeret := true;
  END;
  BEGIN
    UPDATE import_korrektion SET actor_navn='må ikke ske' WHERE id=v_journal_id;
  EXCEPTION WHEN insufficient_privilege THEN v_opdater_blokeret := true;
  END;
  BEGIN
    DELETE FROM import_korrektion WHERE id=v_journal_id;
  EXCEPTION WHEN insufficient_privilege THEN v_slet_blokeret := true;
  END;
  RESET ROLE;
  IF NOT v_anon_blokeret OR v_medlem_antal <> 0 OR v_redaktor_antal <> 1
     OR NOT v_indsaet_blokeret OR NOT v_opdater_blokeret OR NOT v_slet_blokeret THEN
    RAISE EXCEPTION 'FEJL: journal-RLS/grants anon=% medlem=% redaktor=% dml=%/%/%',
      v_anon_blokeret,v_medlem_antal,v_redaktor_antal,
      v_indsaet_blokeret,v_opdater_blokeret,v_slet_blokeret;
  END IF;

  INSERT INTO change_set(id,operation) VALUES (v_change_set,'verify_import_korrektion');
  PERFORM set_config('app.change_set_id',v_change_set::text,true);
  PERFORM set_config('app.change_seq','0',true);
  INSERT INTO import_korrektion(import_key,record_key,felt,input_fingerprint,importeret,status)
    VALUES ('verify:ocr','journal','navn','0123456789abcdef0123456789abcdef','{"navn":"OCR"}','rettet')
  ON CONFLICT (import_key,record_key,felt) DO UPDATE SET status=excluded.status;
  IF NOT EXISTS (SELECT 1 FROM change_event
                 WHERE change_set_id=v_change_set AND tabel='import_korrektion' AND op='UPDATE'
                   AND row_pk->>'id'=v_journal_id::text) THEN
    RAISE EXCEPTION 'FEJL: import_korrektion-upsert loggede ikke normalt change_event';
  END IF;

  RAISE EXCEPTION 'ROLLBACK_TEST_OK';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='ROLLBACK_TEST_OK' THEN
    RAISE NOTICE 'OK: Person OCR kvalitetsark — stabile nøgler, constraints, RLS og journalhistorik';
  ELSE RAISE; END IF;
END $$;

-- ===== Slægts-rod i lineage (flerslægts-forberedelse, B2) =====
-- Forvent: præcis én navnbærende rod pr. slægt, alle grene hænger under den,
-- alle grene arver samme effektive slægtsnavn, og personernes visning_efternavn
-- er UÆNDRET (migrationen må ikke røre cachen).
DO $$
DECLARE v_roedder INT; v_grene INT; v_uden_ophav INT; v_effektiv INT; v_sentinel INT;
BEGIN
  SELECT count(*) INTO v_roedder FROM lineage
   WHERE parent_lineage_id IS NULL AND slaegtsnavn IS NOT NULL;
  IF v_roedder < 1 THEN
    RAISE EXCEPTION 'FEJL: ingen slægts-rod i lineage (B2-migrationen er ikke kørt)';
  END IF;

  -- Ingen gren må stå tilbage som sideordnet rod med sit eget slægtsnavn: det er
  -- præcis den tilstand B2 fjerner, og den ville gøre roden dekorativ.
  SELECT count(*) INTO v_uden_ophav FROM lineage
   WHERE parent_lineage_id IS NULL AND kode IS NOT NULL;
  IF v_uden_ophav > 0 THEN
    RAISE EXCEPTION 'FEJL: % gren(e) med kode står uden slægts-rod', v_uden_ophav;
  END IF;

  SELECT count(*) INTO v_grene FROM lineage WHERE kode IS NOT NULL;
  SELECT count(*) INTO v_effektiv FROM lineage
   WHERE kode IS NOT NULL AND lineage_effective_slaegtsnavn(id) IS NULL;
  IF v_effektiv > 0 THEN
    RAISE EXCEPTION 'FEJL: % af % grene kan ikke udlede et slægtsnavn', v_effektiv, v_grene;
  END IF;

  -- Roden må aldrig få medlemmer: person_external_id joiner på (source_id, kode),
  -- og roden har begge NULL. Fanger en fremtidig rod der får sat kode ved et uheld.
  IF EXISTS (
    SELECT 1 FROM lineage l JOIN person_external_id pei
      ON pei.source_id = l.source_id AND pei.linje = l.kode
     WHERE l.parent_lineage_id IS NULL AND l.slaegtsnavn IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'FEJL: slægts-roden har medlemmer — den skal være en ren beholder';
  END IF;

  -- Slægts-narrativet er en SENTINEL (subjekt_id=1 = "hele slægten"), ikke en
  -- fremmednøgle til lineage 1. B2 flytter den IKKE; denne assert fastholder det.
  SELECT count(*) INTO v_sentinel FROM narrative
   WHERE subjekt_type = 'slaegt' AND subjekt_id <> 1;
  IF v_sentinel > 0 THEN
    RAISE EXCEPTION 'FEJL: % slægts-narrativ(er) er flyttet væk fra sentinel subjekt_id=1', v_sentinel;
  END IF;

  RAISE NOTICE 'OK: slægts-rod — % rod(/rødder), % grene, alle med arvet slægtsnavn', v_roedder, v_grene;
END $$;

-- Dublet-rod skal afvises af det partielle unikke indeks.
DO $$
DECLARE v_navn TEXT;
BEGIN
  SELECT slaegtsnavn INTO v_navn FROM lineage
   WHERE parent_lineage_id IS NULL AND slaegtsnavn IS NOT NULL LIMIT 1;
  BEGIN
    INSERT INTO lineage (id, source_id, kode, navn, slaegtsnavn, parent_lineage_id)
    VALUES (-99, NULL, NULL, v_navn, v_navn, NULL);
    DELETE FROM lineage WHERE id = -99;
    RAISE EXCEPTION 'FEJL: en rod nummer to for samme slægt blev accepteret';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'OK: lineage_slaegtsrod_uidx afviser dublet slægts-rod';
  END;
END $$;

-- =============================================================
-- 2026-08-01: union-redigering — red_tilfoej_partner + to-parts-invariant
-- Kører som redaktion via transaktions-lokal jwt-claim. Blokken ruller sine
-- RÆKKER tilbage til sidst (RAISE fanget af blokkens egen EXCEPTION-klausul);
-- IDENTITY-sekvenser rulles derimod ikke tilbage, så et par id-numre brændes
-- pr. kørsel. Ingen eksisterende data røres.
-- Mangler der en redaktionsprofil, FEJLER blokken — en assert der stiltiende
-- springer sig selv over er værre end ingen assert (Codex sol, 2026-08-01).
-- Hver negativ assert matcher den FORVENTEDE fejltekst, så et grønt assert
-- ikke kan skyldes en uvedkommende fejl (Codex sol runde 2).
-- =============================================================
DO $$
DECLARE
  v_uid uuid; v_fam bigint; v_a bigint; v_b bigint; v_barn bigint; v_alias bigint; v_fejl text;
BEGIN
  SELECT id INTO v_uid FROM profiles WHERE rolle='redaktion' LIMIT 1;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'FEJL: ingen redaktion-profil — union-asserts kan ikke køres'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role','authenticated')::text, true);

  v_a := red_opret_person('VERIFY far');
  v_b := red_opret_person('VERIFY mor');
  v_barn := red_opret_person('VERIFY barn');

  -- Skallen bygges råt: red_opret_union kræver to partnere fra start, og det er netop den
  -- mor-løse børne-familie fra 1939-loaderen vi vil kunne reparere.
  INSERT INTO family(type) VALUES ('vielse') RETURNING id INTO v_fam;
  INSERT INTO family_member(family_id, person_id, rolle) VALUES (v_fam, v_a, 'partner');
  INSERT INTO family_member(family_id, person_id, rolle) VALUES (v_fam, v_barn, 'barn');

  -- 1) tilføj partner virker og er idempotent
  PERFORM red_tilfoej_partner(v_fam, v_b);
  PERFORM red_tilfoej_partner(v_fam, v_b);
  IF (SELECT count(*) FROM family_member WHERE family_id=v_fam AND rolle='partner') <> 2 THEN
    RAISE EXCEPTION 'FEJL: red_tilfoej_partner gav ikke præcis 2 partnere (idempotens brudt?)';
  END IF;

  -- 1b) en tredje part afvises af RPC'en (læselaget projicerer kun p1/p2)
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, red_opret_person('VERIFY tredje'));
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: en tredje part blev accepteret i unionen'; END IF;
  IF v_fejl NOT LIKE '%to parter%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  -- 1c) …og af tabellen selv, uden om RPC'en (fortryd-stien skriver rækker direkte tilbage)
  v_fejl := NULL;
  BEGIN
    INSERT INTO family_member(family_id, person_id, rolle)
      VALUES (v_fam, red_opret_person('VERIFY raa tredje'), 'partner');
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: rå INSERT omgik to-parts-invarianten'; END IF;
  IF v_fejl NOT LIKE '%en union har to%' THEN RAISE EXCEPTION 'FEJL: rå INSERT afvist af forkert grund: %', v_fejl; END IF;

  -- 1d) …men en legitim UPDATE af en eksisterende parts person_id må IKKE afvises
  UPDATE family_member SET person_id = red_opret_person('VERIFY mor v2')
    WHERE family_id=v_fam AND person_id=v_b AND rolle='partner';
  IF (SELECT count(*) FROM family_member WHERE family_id=v_fam AND rolle='partner') <> 2 THEN
    RAISE EXCEPTION 'FEJL: legitim partner-UPDATE ændrede antallet af parter';
  END IF;

  -- 2) et barn i familien kan ikke også blive partner
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, v_barn);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: barn blev accepteret som partner i samme familie'; END IF;
  IF v_fejl NOT LIKE '%allerede barn%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  -- 3) …og heller ikke en alias-post for barnet (identitets-bevidst cyklus-guard)
  v_alias := red_opret_person('VERIFY barn-alias');
  PERFORM red_samme_som(v_alias, v_barn);
  DELETE FROM family_member WHERE family_id=v_fam AND rolle='partner' AND person_id <> v_a;
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, v_alias);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: alias for et barn blev accepteret som part (cyklus)'; END IF;
  IF v_fejl NOT LIKE 'Cyklus:%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  -- 3b) …og heller ikke et alias for den SIDDENDE part (to parter, én person = selv-ægtefælle
  --      efter collapse). Både gennem RPC'en og udenom den.
  v_alias := red_opret_person('VERIFY far-alias');
  PERFORM red_samme_som(v_alias, v_a);
  v_fejl := NULL;
  BEGIN PERFORM red_tilfoej_partner(v_fam, v_alias);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: alias for den siddende part blev accepteret som part nr. 2'; END IF;
  IF v_fejl NOT LIKE '%samme person%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;

  v_fejl := NULL;
  BEGIN INSERT INTO family_member(family_id, person_id, rolle) VALUES (v_fam, v_alias, 'partner');
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: rå INSERT omgik identitets-distinktheden'; END IF;
  IF v_fejl NOT LIKE '%samme person%' THEN RAISE EXCEPTION 'FEJL: rå INSERT afvist af forkert grund: %', v_fejl; END IF;

  -- 3c) Den OMVENDTE rækkefølge er også spærret: to parter først, samme_som bagefter.
  --      Uden denne ville håndhævelsen afhænge af redaktørens klik-rækkefølge.
  v_fejl := NULL;
  BEGIN PERFORM red_samme_som(red_opret_person('VERIFY spejl'), v_a);
  EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
  IF v_fejl IS NOT NULL THEN RAISE EXCEPTION 'FEJL: et uskyldigt samme_som-link blev afvist: %', v_fejl; END IF;

  DECLARE v_fam2 bigint; v_x bigint; v_y bigint;
  BEGIN
    v_x := red_opret_person('VERIFY union-part X');
    v_y := red_opret_person('VERIFY union-part Y');
    v_fam2 := red_opret_union(v_x, v_y, 'vielse');
    v_fejl := NULL;
    BEGIN PERFORM red_samme_som(v_y, v_x);
    EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
    IF v_fejl IS NULL THEN RAISE EXCEPTION 'FEJL: to parter i samme union blev linket som samme person'; END IF;
    IF v_fejl NOT LIKE '%samme union%' THEN RAISE EXCEPTION 'FEJL: afvist, men af den forkerte grund: %', v_fejl; END IF;
  END;

  -- 3d) En eksisterende relation må ikke kunne omskrives TIL samme_som med rå UPDATE.
  --      samme_som-identitet oprettes og fjernes som en hel relation, så dens evidens ikke
  --      stiltiende genbruges til en anden rolle eller andre endepunkter.
  DECLARE v_rel bigint; v_alias2 bigint; v_kanon2 bigint; v_anden bigint;
  BEGIN
    v_alias2 := red_opret_person('VERIFY UPDATE alias');
    v_kanon2 := red_opret_person('VERIFY UPDATE kanonisk');
    INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
              'person', v_alias2, 'person', v_kanon2, 'bekendt_med')
      RETURNING id INTO v_rel;
    v_fejl := NULL;
    BEGIN
      UPDATE relation SET rolle='samme_som' WHERE id=v_rel;
      RAISE EXCEPTION 'VERIFY_UPDATE_BLEV_ACCEPTERET';
    EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
    IF v_fejl = 'VERIFY_UPDATE_BLEV_ACCEPTERET' THEN
      RAISE EXCEPTION 'FEJL: rå UPDATE kunne ændre en eksisterende relation til samme_som';
    END IF;
    IF v_fejl <> 'samme_som: rolle og endepunkter er uforanderlige — brug slet+genopret' THEN
      RAISE EXCEPTION 'FEJL: rå samme_som-UPDATE afvist af forkert grund: %', v_fejl;
    END IF;

    -- 3e) Undo-hjælperens eksisterende-række-sti bruger UPDATE og skal ramme samme guard.
    --      INSERT-stien for en slettet relation forbliver tilladt og valideres af insert-guarden.
    v_rel := red_samme_som(v_alias2, v_kanon2);
    v_anden := red_opret_person('VERIFY UPDATE andet endpoint');
    v_fejl := NULL;
    BEGIN
      PERFORM _version_upsert_row(
        'relation',
        jsonb_set((SELECT to_jsonb(r) FROM relation r WHERE r.id=v_rel),
                  '{objekt_id}', to_jsonb(v_anden), false)
      );
      RAISE EXCEPTION 'VERIFY_VERSION_UPSERT_BLEV_ACCEPTERET';
    EXCEPTION WHEN others THEN v_fejl := SQLERRM; END;
    IF v_fejl = 'VERIFY_VERSION_UPSERT_BLEV_ACCEPTERET' THEN
      RAISE EXCEPTION 'FEJL: _version_upsert_row kunne flytte et samme_som-endepunkt';
    END IF;
    IF v_fejl <> 'samme_som: rolle og endepunkter er uforanderlige — brug slet+genopret' THEN
      RAISE EXCEPTION 'FEJL: _version_upsert_row samme_som-UPDATE afvist af forkert grund: %', v_fejl;
    END IF;
  END;

  -- 4) negativ kontrol: guarden afviser ikke bare alt
  PERFORM red_tilfoej_partner(v_fam, red_opret_person('VERIFY urelateret'));
  IF (SELECT count(*) FROM family_member WHERE family_id=v_fam AND rolle='partner') <> 2 THEN
    RAISE EXCEPTION 'FEJL: en urelateret person blev ikke accepteret som part';
  END IF;

  RAISE NOTICE 'OK: red_tilfoej_partner + trg_partner_loft — guards holder (to-parts-loft i RPC og tabel, legitim partner-UPDATE, barn, identitets-cyklus, identitets-distinkthed begge veje, samme_som-immutability via rå UPDATE og _version_upsert_row, negativ kontrol)';
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;

-- ===== Issue #127: story_kilde i version_pk_registry + registry-dækning =====
-- Forvent: alle tre blokke ender i NOTICE 'OK: ...'.

-- 1) Registry-dækning: enhver tabel en red_*-funktion DML'er mod skal stå i
--    version_pk_registry eller være eksplicit undtaget. Undtagelserne er
--    dokumenteret: change_set (versioneringens egen infrastruktur),
--    suggestion (forslags-kø, ikke kanonisk data — versioneres ved apply, #128),
--    media_variant (afledt cache, B8-mønsteret — schema.sql-kommentar ved media_variant),
--    slaegtsnavn_karantaene (afledt, selv-helbredende karantæne-liste).
DO $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(t.tabel, ', ' ORDER BY t.tabel) INTO v_missing
  FROM (
    SELECT DISTINCT lower(m.grp[2]) AS tabel
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL regexp_matches(p.prosrc,
      '(INSERT INTO|UPDATE|DELETE FROM)\s+([a-zA-Z_]+)', 'gi') AS m(grp)
    WHERE n.nspname = 'public' AND p.proname LIKE 'red\_%'
  ) t
  JOIN pg_class c ON c.relname = t.tabel
    AND c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
  WHERE t.tabel NOT IN (SELECT tabel FROM version_pk_registry)
    AND t.tabel NOT IN ('change_set','suggestion','media_variant','slaegtsnavn_karantaene');
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: red_*-DML-tabeller uden versionering (fortryd = tavs no-op): %', v_missing;
  END IF;
  RAISE NOTICE 'OK: alle red_*-DML-tabeller er versioneret eller eksplicit undtaget';
END $$;

-- 2) Trigger-paritet: en registry-række uden trg_log_-trigger logger intet.
DO $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(r.tabel, ', ' ORDER BY r.tabel) INTO v_missing
  FROM version_pk_registry r
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relnamespace = 'public'::regnamespace
      AND c.relname = r.tabel AND t.tgname = 'trg_log_' || r.tabel);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FEJL: registry-tabeller uden log_change-trigger: %', v_missing;
  END IF;
  RAISE NOTICE 'OK: alle registry-tabeller har deres trg_log_-trigger';
END $$;

-- 3) Adfærd: red_set_story_kilder logger story_kilde-events, og fortryd
--    genskaber tilstanden (var tavs no-op før #127).
DO $$
DECLARE
  v_redaktor uuid := '00000000-0000-0000-0000-0000000000d7';
  v_person bigint; v_story bigint; v_src bigint; v_cs bigint;
  v_events int; v_rows int;
BEGIN
  INSERT INTO auth.users(id,email) VALUES (v_redaktor,'verify-127@test')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,navn) VALUES (v_redaktor,'redaktion','VERIFY 127')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub', v_redaktor::text, true);

  v_person := red_opret_person('VERIFY 127 person');
  INSERT INTO source(id,titel) VALUES ((SELECT coalesce(max(id),0)+1 FROM source),'VERIFY 127 kilde')
    RETURNING id INTO v_src;
  v_story := red_opret_story('person', v_person, 'VERIFY 127 story-tekst');

  -- nyt change_set specifikt for kilde-kaldet, så fortryd rammer præcist
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_story_kilder(v_story,
    jsonb_build_array(jsonb_build_object('source_id', v_src, 'side', '12')));
  v_cs := current_setting('app.change_set_id', true)::bigint;

  SELECT count(*) INTO v_events
    FROM change_event WHERE change_set_id = v_cs AND tabel = 'story_kilde';
  IF v_events = 0 THEN
    RAISE EXCEPTION 'FEJL: red_set_story_kilder loggede ingen story_kilde-events — fortryd er tavs no-op (#127)';
  END IF;

  -- fortryd i eget change_set: kildelisten skal være tom igen
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_fortryd_change_set(v_cs);
  SELECT count(*) INTO v_rows FROM story_kilde WHERE story_id = v_story;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FEJL: fortryd genskabte ikke tom kildeliste (% rækker tilbage)', v_rows;
  END IF;

  RAISE NOTICE 'OK: story_kilde versioneres — % events logget, fortryd genskabte tom kildeliste', v_events;
  RAISE EXCEPTION 'ROLLBACK_TESTDATA';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TESTDATA' THEN RAISE NOTICE 'OK: testdata rullet tilbage'; ELSE RAISE; END IF;
END $$;
