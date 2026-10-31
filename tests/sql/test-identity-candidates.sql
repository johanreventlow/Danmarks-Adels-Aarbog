CREATE EXTENSION IF NOT EXISTS dblink;
-- Trin 5a, Task 1-2: kandidatlaget. Kør efter bootstrap, schema.sql, db-rls.sql og
-- migrationerne på en frisk base. Hver blok ruller sin fixture tilbage selv.

DO $identity_candidate_tables$
DECLARE v_table text; v_role text; v_state text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['source_persona_identity_candidate_run','source_persona_identity_candidate'] LOOP
    IF to_regclass(format('private.%I',v_table)) IS NULL THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: private.% mangler',v_table;
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=format('private.%I',v_table)::regclass) THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: RLS er slået fra på %',v_table;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      v_state:=NULL;
      BEGIN
        EXECUTE format('SET LOCAL ROLE %I',v_role);
        EXECUTE format('SELECT 1 FROM private.%I LIMIT 1',v_table);
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
      END;
      EXECUTE 'SET LOCAL ROLE NONE';
      IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % kunne læse % (%)',v_role,v_table,v_state;
      END IF;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'OK: kandidattabellerne findes, har RLS og ingen API-adgang';
END $identity_candidate_tables$;

DO $identity_candidate_constraints$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a01';
  v_run uuid := '22000000-0000-0000-0000-000000005a01';
  v_persona uuid := '88000000-0000-0000-0000-000000005a01';
  v_cand_run uuid;
  v_state text;
BEGIN
  BEGIN
    INSERT INTO person(id,levende,privat,status) VALUES (-987655001,false,false,'5a fixture'),(-987655002,false,false,'5a fixture');
    INSERT INTO source(id,titel,import_key) VALUES (-987655001,'5a kandidat','verify:5a:cand');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655001,'5a-run','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_persona,-987655001,'5a-persona',v_run);
    INSERT INTO private.source_persona_identity_candidate_run(
      source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name
    ) VALUES (-987655001,'test','{}',repeat('a',64),'{"mode":"undecided"}',repeat('b',64),repeat('c',64),1,1,v_actor,'test') RETURNING id INTO v_cand_run;
    INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
      VALUES (v_cand_run,v_persona,-987655001,1,0.91,'auto','{"signals":["name"]}');
    -- rang 0, score over 1, ukendt tier og tom basis skal alle afvises
    FOREACH v_state IN ARRAY ARRAY['rank','score','tier','basis'] LOOP
      BEGIN
        INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
          VALUES (v_cand_run,v_persona,-987655002,
                  CASE WHEN v_state='rank' THEN 0 ELSE 2 END,
                  CASE WHEN v_state='score' THEN 1.5 ELSE 0.5 END,
                  CASE WHEN v_state='tier' THEN 'x' ELSE 'none' END,
                  CASE WHEN v_state='basis' THEN '{}'::jsonb ELSE '{"signals":[]}'::jsonb END);
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % blev accepteret',v_state;
      EXCEPTION WHEN check_violation THEN NULL;
      END;
    END LOOP;
    -- append-only: UPDATE, DELETE og TRUNCATE afvises af triggeren (ikke af en FK eller rettighed)
    FOREACH v_state IN ARRAY ARRAY['update','delete','truncate','truncate_run'] LOOP
      BEGIN
        IF v_state='update' THEN UPDATE private.source_persona_identity_candidate SET score=0.1 WHERE run_id=v_cand_run;
        ELSIF v_state='delete' THEN DELETE FROM private.source_persona_identity_candidate WHERE run_id=v_cand_run;
        ELSIF v_state='truncate' THEN TRUNCATE private.source_persona_identity_candidate;
        ELSE TRUNCATE private.source_persona_identity_candidate_run CASCADE;
        END IF;
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % lykkedes',v_state;
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'EVIDENCE_APPEND_ONLY:%' THEN RAISE; END IF;
      END;
    END LOOP;
    RAISE EXCEPTION 'ROLLBACK_5A_CANDIDATE_CONSTRAINTS';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_CANDIDATE_CONSTRAINTS' THEN
      RAISE NOTICE 'OK: kandidatrækkernes constraints og append-only holder';
    ELSE RAISE; END IF;
  END;
END $identity_candidate_constraints$;

DO $identity_candidate_writer$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a02';
  v_run uuid := '22000000-0000-0000-0000-000000005a02';
  v_p1 uuid := '88000000-0000-0000-0000-000000005a21';
  v_p2 uuid := '88000000-0000-0000-0000-000000005a22';
  v_other uuid := '88000000-0000-0000-0000-000000005a23';
  v_spec jsonb := '{"mode":"undecided"}';
  v_in jsonb; v_meta jsonb; v_cands jsonb; v_id uuid; v_id2 uuid; v_err text; v_state text;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-writer@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a writer','5a-writer@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655021,false,false,'5a'),(-987655022,false,false,'5a');
    INSERT INTO source(id,titel,import_key) VALUES (-987655021,'5a A','verify:5a:a'),(-987655022,'5a B','verify:5a:b');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655021,'5a-run-w','1.0','verify','verify',repeat('9',64),'{}'),
             ('22000000-0000-0000-0000-000000005a03',-987655022,'5a-run-w-b','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES (v_p1,-987655021,'5a-p1',v_run),(v_p2,-987655021,'5a-p2',v_run),
             (v_other,-987655022,'5a-other','22000000-0000-0000-0000-000000005a03');

    -- uden redaktionsrolle
    BEGIN PERFORM red_identity_candidate_input(-987655021,v_spec);
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: input uden rolle lykkedes';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'EVIDENCE_ROLE_FORBIDDEN' THEN RAISE; END IF; END;

    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    v_in := red_identity_candidate_input(-987655021,v_spec);
    IF v_in->'input' IS NULL OR jsonb_array_length(v_in->'input'->'personas')<>2
       OR v_in->>'input_sha256' !~ '^[0-9a-f]{64}$'
       OR v_in->>'input_sha256'<>(red_identity_candidate_input(-987655021,v_spec)->>'input_sha256') THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: input er ikke deterministisk eller forkert afgrænset (%)',v_in->'input'->'personas';
    END IF;
    v_meta := jsonb_build_object('source_id',-987655021,'generator_version','test-1','input_spec',v_spec,
                                 'input_sha256',v_in->>'input_sha256','config',jsonb_build_object('topK',3));
    -- samme person er kandidat 1 for begge personas: ikke-injektivt er tilladt; p2 får kun én kandidat
    v_cands := jsonb_build_array(
      jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-987655021,'rank',1,'score',0.93,'tier','auto','basis',jsonb_build_object('signals',jsonb_build_array('name','birth'))),
      jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-987655022,'rank',2,'score',0.71,'tier','review','basis',jsonb_build_object('signals',jsonb_build_array('name'))),
      jsonb_build_object('source_persona_id',v_p2,'candidate_person_id',-987655021,'rank',1,'score',0.8,'tier','review','basis',jsonb_build_object('signals',jsonb_build_array('name'))));
    v_id := red_record_identity_candidates(v_meta,v_cands);
    v_id2 := red_record_identity_candidates(v_meta,v_cands);
    IF v_id IS DISTINCT FROM v_id2 THEN RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: ikke idempotent'; END IF;

    FOR v_err IN SELECT unnest(ARRAY['conflict','foreign','person','gap','keys','count','hash','spec']) LOOP
      BEGIN
        IF v_err='conflict' THEN
          PERFORM red_record_identity_candidates(v_meta, v_cands - 2);
        ELSIF v_err='foreign' THEN   -- persona fra en anden kilde er ikke i inputtet
          PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":4}}',
            jsonb_build_array(jsonb_build_object('source_persona_id',v_other,'candidate_person_id',-987655021,'rank',1,'score',0.9,'tier','auto','basis','{"signals":["name"]}'::jsonb)));
        ELSIF v_err='person' THEN    -- person, der ikke findes i inputtets personmængde
          PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":5}}',
            jsonb_build_array(jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-1,'rank',1,'score',0.9,'tier','auto','basis','{"signals":["name"]}'::jsonb)));
        ELSIF v_err='gap' THEN
          PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":6}}',
            jsonb_build_array(jsonb_build_object('source_persona_id',v_p1,'candidate_person_id',-987655021,'rank',2,'score',0.9,'tier','auto','basis','{"signals":["name"]}'::jsonb)));
        ELSIF v_err='keys' THEN
          PERFORM red_record_identity_candidates(v_meta || '{"extra":1}', v_cands);
        ELSIF v_err='count' THEN     -- klienten må ikke selv angive antal
          PERFORM red_record_identity_candidates(v_meta || '{"persona_count":99}', v_cands);
        ELSIF v_err='hash' THEN      -- falsk input-hash
          PERFORM red_record_identity_candidates(v_meta || jsonb_build_object('input_sha256',repeat('e',64)), v_cands);
        ELSE
          PERFORM red_record_identity_candidates(v_meta || '{"input_spec":{"mode":"alle"}}', v_cands);
        END IF;
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % blev accepteret',v_err;
      EXCEPTION WHEN OTHERS THEN
        -- præcis den forventede kode pr. tilfælde, så et tilfælde ikke kan bestå på en andens fejl
        IF SQLERRM IS DISTINCT FROM (CASE v_err
             WHEN 'conflict' THEN 'IDENTITY_CANDIDATE_RUN_CONFLICT' WHEN 'foreign' THEN 'IDENTITY_CANDIDATE_PERSONA_NOT_IN_INPUT'
             WHEN 'person' THEN 'IDENTITY_CANDIDATE_PERSON_NOT_IN_INPUT' WHEN 'gap' THEN 'IDENTITY_CANDIDATE_RANK_GAP'
             WHEN 'keys' THEN 'IDENTITY_CANDIDATE_RUN_INVALID' WHEN 'count' THEN 'IDENTITY_CANDIDATE_RUN_INVALID'
             WHEN 'hash' THEN 'IDENTITY_CANDIDATE_INPUT_DRIFT' ELSE 'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID' END) THEN RAISE; END IF;
      END;
    END LOOP;
    RESET ROLE;

    -- ændret DB-input efter eksport: en ny persona i kilden ⇒ drift
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES ('88000000-0000-0000-0000-000000005a24',-987655021,'5a-p4',v_run);
    SET LOCAL ROLE authenticated;
    BEGIN PERFORM red_record_identity_candidates(v_meta || '{"config":{"topK":7}}', v_cands);
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: forældet input accepteret';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'IDENTITY_CANDIDATE_INPUT_DRIFT' THEN RAISE; END IF; END;
    RESET ROLE;

    IF (SELECT persona_count FROM private.source_persona_identity_candidate_run WHERE id=v_id)<>2
       OR (SELECT candidate_count FROM private.source_persona_identity_candidate_run WHERE id=v_id)<>3
       OR (SELECT count(*) FROM private.source_persona_identity_candidate WHERE run_id=v_id)<>3
       OR (SELECT config_sha256 FROM private.source_persona_identity_candidate_run WHERE id=v_id)
          <>private.reimport_canonical_json_sha256('{"topK":3}'::jsonb) THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: serverens antal eller hashes er forkerte';
    END IF;
    -- Indholds-id (#151, spec §3, §5.2): kørslens og kandidaternes id afledes af deres naturlige nøgler.
    IF v_id IS DISTINCT FROM (SELECT private.content_uuid('identity-candidate-run',jsonb_build_object('source_id',r.source_id,
            'input_sha256',r.input_sha256,'config_sha256',r.config_sha256)) FROM private.source_persona_identity_candidate_run r WHERE r.id=v_id)
       OR EXISTS (SELECT 1 FROM private.source_persona_identity_candidate c WHERE c.run_id=v_id
                   AND c.id<>private.content_uuid('identity-candidate',jsonb_build_object('run_id',c.run_id,
                         'source_persona_id',c.source_persona_id::text,'candidate_person_id',c.candidate_person_id))) THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: id ikke af indholdet';
    END IF;
    -- Kollision: en kørsel med det afledte id, men en anden config_sha256, fejler lukket.
    SET LOCAL ROLE authenticated;
    v_in := red_identity_candidate_input(-987655021,v_spec);
    RESET ROLE;
    INSERT INTO private.source_persona_identity_candidate_run(id,
      source_id,generator_version,config,config_sha256,input_spec,input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name
    ) VALUES (private.content_uuid('identity-candidate-run',jsonb_build_object('source_id',-987655021,'input_sha256',v_in->>'input_sha256',
                'config_sha256',private.reimport_canonical_json_sha256('{"topK":8}'::jsonb))),
              -987655021,'test','{}',repeat('d',64),v_spec,v_in->>'input_sha256',repeat('c',64),1,1,v_actor,'test');
    SET LOCAL ROLE authenticated;
    BEGIN
      PERFORM red_record_identity_candidates(v_meta || jsonb_build_object('config',jsonb_build_object('topK',8),
        'input_sha256',v_in->>'input_sha256'), jsonb_build_array(v_cands->0));
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: kollision godtaget';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'DETERMINISTIC_ID_COLLISION: identity-candidate-run%' THEN RAISE; END IF; END;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_CANDIDATE_WRITER';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_5A_CANDIDATE_WRITER' THEN
      RAISE NOTICE 'OK: kandidat-writeren genberegner input, udleder antal, er idempotent og ikke-injektiv, og afviser konflikt, fremmed persona/person, ranghul, ukendte nøgler, falsk hash og drift';
    ELSE RAISE; END IF;
  END;
END $identity_candidate_writer$;

-- Writeren tager kildelåsen: holder en anden forbindelse den, venter writeren (her: timeout 55P03).
DO $identity_candidate_lock$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000005a09';
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_state text;
BEGIN
  PERFORM dblink_connect('cand_lock',v_conn);
  PERFORM dblink_exec('cand_lock','BEGIN');
  PERFORM * FROM dblink('cand_lock','SELECT pg_advisory_xact_lock(hashtextextended(''daa-identity-candidates:-987655021'',0))::text') AS t(x text);
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'5a-lock@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','5a lock','5a-lock@test.invalid');
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;
    SET LOCAL lock_timeout='300ms';
    BEGIN
      PERFORM red_record_identity_candidates(
        '{"source_id":-987655021,"generator_version":"t","input_spec":{"mode":"undecided"},"input_sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","config":{}}','[]');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE;
    END;
    RESET ROLE;
    RAISE EXCEPTION 'ROLLBACK_5A_CANDIDATE_LOCK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'ROLLBACK_5A_CANDIDATE_LOCK' THEN
      PERFORM dblink_exec('cand_lock','ROLLBACK'); PERFORM dblink_disconnect('cand_lock'); RAISE;
    END IF;
  END;
  PERFORM dblink_exec('cand_lock','ROLLBACK'); PERFORM dblink_disconnect('cand_lock');
  IF v_state IS DISTINCT FROM '55P03' THEN
    RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: writeren ventede ikke på kildelåsen (%)',v_state;
  END IF;
  RAISE NOTICE 'OK: kandidat-writeren tager kildelåsen';
END $identity_candidate_lock$;

DO $identity_candidate_concurrent$
DECLARE
  v_conn text := format('dbname=%s port=%s host=%s',current_database(),current_setting('port'),split_part(current_setting('unix_socket_directories'),',',1));
  v_fix text := $fix$
    INSERT INTO auth.users(id,email) VALUES ('11000000-0000-0000-0000-000000005a07','5a-conc@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES ('11000000-0000-0000-0000-000000005a07','redaktion','5a conc','5a-conc@test.invalid');
    INSERT INTO source(id,titel,import_key) VALUES (-987655071,'5a C','verify:5a:c');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES ('22000000-0000-0000-0000-000000005a07',-987655071,'5a-run-c','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
      VALUES ('88000000-0000-0000-0000-000000005a71',-987655071,'5a-c1','22000000-0000-0000-0000-000000005a07');
  $fix$;
  v_cleanup text := $cl$
    SET session_replication_role=replica;
    DELETE FROM private.source_persona_identity_candidate c USING private.source_persona_identity_candidate_run r
     WHERE c.run_id=r.id AND r.source_id=-987655071;
    DELETE FROM private.source_persona_identity_candidate_run WHERE source_id=-987655071;
    DELETE FROM private.source_persona WHERE source_id=-987655071;
    DELETE FROM private.extraction_run WHERE id='22000000-0000-0000-0000-000000005a07';
    DELETE FROM source WHERE id=-987655071;
    DELETE FROM profiles WHERE id='11000000-0000-0000-0000-000000005a07';
    DELETE FROM auth.users WHERE id='11000000-0000-0000-0000-000000005a07';
    SET session_replication_role=origin;
  $cl$;
  v_role text := $r$SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000005a07',false); SET ROLE authenticated;$r$;
  v_hash text; v_call text; v_a text; v_b text; v_runs int;
BEGIN
  PERFORM dblink_connect('cc_setup',v_conn);
  PERFORM dblink_exec('cc_setup',v_cleanup);
  PERFORM dblink_exec('cc_setup',v_fix);
  BEGIN
    PERFORM dblink_connect('cc_a',v_conn); PERFORM dblink_connect('cc_b',v_conn);
    PERFORM dblink_exec('cc_a',v_role); PERFORM dblink_exec('cc_b',v_role);
    SELECT h INTO v_hash FROM dblink('cc_a',$q$SELECT red_identity_candidate_input(-987655071,'{"mode":"undecided"}')->>'input_sha256'$q$) AS t(h text);
    v_call := format($q$SELECT red_record_identity_candidates(jsonb_build_object('source_id',-987655071,'generator_version','t',
      'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',%L,'config','{"topK":3}'::jsonb),'[]'::jsonb)::text$q$,v_hash);
    PERFORM dblink_exec('cc_a','BEGIN'); PERFORM dblink_exec('cc_b','BEGIN');
    PERFORM dblink_send_query('cc_a',v_call);
    PERFORM dblink_send_query('cc_b',v_call);            -- venter på A's kildelås
    SELECT r INTO v_a FROM dblink_get_result('cc_a') AS t(r text); PERFORM * FROM dblink_get_result('cc_a') AS t(r text);
    PERFORM dblink_exec('cc_a','COMMIT');
    SELECT r INTO v_b FROM dblink_get_result('cc_b') AS t(r text); PERFORM * FROM dblink_get_result('cc_b') AS t(r text);
    PERFORM dblink_exec('cc_b','COMMIT');
    SELECT count(*) INTO v_runs FROM private.source_persona_identity_candidate_run WHERE source_id=-987655071;
    IF v_a IS NULL OR v_a IS DISTINCT FROM v_b OR v_runs<>1 THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: samtidige kald gav % og % (% kørsler)',v_a,v_b,v_runs;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    BEGIN PERFORM dblink_disconnect('cc_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM dblink_disconnect('cc_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM dblink_exec('cc_setup',v_cleanup); PERFORM dblink_disconnect('cc_setup');
    RAISE;
  END;
  PERFORM dblink_disconnect('cc_a'); PERFORM dblink_disconnect('cc_b');
  PERFORM dblink_exec('cc_setup',v_cleanup); PERFORM dblink_disconnect('cc_setup');
  RAISE NOTICE 'OK: samtidige identiske writer-kald giver samme kørsel og én run-række';
END $identity_candidate_concurrent$;

-- Trin 6b, Task 4: årstalsreserve fra assertion.date_raw, tilvalgt i input_spec.
DO $identity_candidate_year_fallback$
DECLARE
  v_actor uuid := '11000000-0000-0000-0000-000000006b04';
  v_run uuid := '22000000-0000-0000-0000-000000006b04';
  v_p1 uuid := '88000000-0000-0000-0000-000000006b41';
  v_spec jsonb := '{"mode":"undecided"}';
  v_spec_fb jsonb := '{"mode":"undecided","year_fallback":"date_raw-v1"}';
  v_in jsonb; v_fb jsonb; v_a jsonb; v_expected_plain jsonb; v_fact bigint; v_n int;
BEGIN
  BEGIN
    INSERT INTO auth.users(id,email) VALUES (v_actor,'6b4@test.invalid');
    INSERT INTO profiles(id,rolle,navn,email) VALUES (v_actor,'redaktion','6b4','6b4@test.invalid');
    INSERT INTO person(id,levende,privat,status) VALUES (-987655401,false,false,'6b4');
    INSERT INTO source(id,titel,import_key) VALUES (-987655401,'6b4','verify:6b4');
    INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
      VALUES (v_run,-987655401,'6b4-run','1.0','verify','verify',repeat('9',64),'{}');
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES (v_p1,-987655401,'6b4-p1',v_run);
    INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-987655401,'person',-987655401,'fødsel') RETURNING id INTO v_fact;
    INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,date_raw,date_min,date_max) VALUES
      (-987655411,'fact',v_fact,'a','1750',NULL,NULL),
      (-987655412,'fact',v_fact,'b','c. 1750',NULL,NULL),
      (-987655413,'fact',v_fact,'c','12. Marts 1750',NULL,NULL),
      (-987655414,'fact',v_fact,'d','1750 el. 1751',NULL,NULL),
      (-987655415,'fact',v_fact,'e','17..',NULL,NULL),
      (-987655416,'fact',v_fact,'f','1800','1760-01-01','1760-12-31'),
      (-987655417,'fact',v_fact,'g','1750 og 1750',NULL,NULL),
      (-987655418,'fact',v_fact,'h',NULL,NULL,NULL);
    PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
    SET LOCAL ROLE authenticated;

    v_in := red_identity_candidate_input(-987655401,v_spec);
    v_fb := red_identity_candidate_input(-987655401,v_spec_fb);
    -- uden nøglen: ingen date_origin nogen steder og assertions præcis som red_match_personer leverer dem
    IF v_in::text LIKE '%date_origin%' THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: date_origin uden year_fallback';
    END IF;
    SELECT coalesce(jsonb_agg(e ORDER BY e::text COLLATE "C"),'[]') INTO v_expected_plain
      FROM jsonb_array_elements(red_match_personer()->'assertions') e;
    IF v_in->'input'->'persons'->'assertions' IS DISTINCT FROM v_expected_plain THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: input uden year_fallback er ikke uændret';
    END IF;
    IF v_in->>'input_sha256'=v_fb->>'input_sha256' THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: year_fallback ændrede ikke hashen';
    END IF;
    IF v_fb->>'input_sha256'<>(red_identity_candidate_input(-987655401,v_spec_fb)->>'input_sha256')
       OR v_fb->'input_spec'<>v_spec_fb THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: year_fallback-input er ikke deterministisk';
    END IF;
    -- list-tilstand tillader også nøglen
    PERFORM red_identity_candidate_input(-987655401,
      jsonb_build_object('mode','list','persona_ids',jsonb_build_array(v_p1),'year_fallback','date_raw-v1'));

    FOR v_n IN SELECT unnest(ARRAY[-987655411,-987655412,-987655413]) LOOP
      SELECT e INTO v_a FROM jsonb_array_elements(v_fb->'input'->'persons'->'assertions') e WHERE (e->>'id')::bigint=v_n;
      IF v_a->>'date_min'<>'1750-01-01' OR v_a->>'date_max'<>'1750-12-31' OR v_a->>'date_origin'<>'date_raw' THEN
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: reserve for % forkert (%)',v_n,v_a;
      END IF;
    END LOOP;
    FOR v_n IN SELECT unnest(ARRAY[-987655414,-987655415,-987655418]) LOOP
      SELECT e INTO v_a FROM jsonb_array_elements(v_fb->'input'->'persons'->'assertions') e WHERE (e->>'id')::bigint=v_n;
      IF v_a->>'date_min' IS NOT NULL OR v_a->>'date_max' IS NOT NULL OR v_a ? 'date_origin' THEN
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: % skulle ingen reserve have (%)',v_n,v_a;
      END IF;
    END LOOP;
    -- samme årstal to gange = ét forskelligt årstal
    SELECT e INTO v_a FROM jsonb_array_elements(v_fb->'input'->'persons'->'assertions') e WHERE (e->>'id')::bigint=-987655417;
    IF v_a->>'date_min'<>'1750-01-01' OR v_a->>'date_origin'<>'date_raw' THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: ens årstal to gange skulle give reserve (%)',v_a;
    END IF;
    -- påstand med date_min sat er uændret
    SELECT e INTO v_a FROM jsonb_array_elements(v_fb->'input'->'persons'->'assertions') e WHERE (e->>'id')::bigint=-987655416;
    IF v_a->>'date_min'<>'1760-01-01' OR v_a->>'date_max'<>'1760-12-31' OR v_a ? 'date_origin' THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: påstand med date_min blev ændret (%)',v_a;
    END IF;
    -- alle øvrige elementer er byte-ens
    IF (SELECT count(*) FROM jsonb_array_elements(v_fb->'input'->'persons'->'assertions') e
         WHERE NOT e ? 'date_origin' AND NOT v_expected_plain @> jsonb_build_array(e))<>0 THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: ikke-reserve-påstande er ændret';
    END IF;
    IF v_fb->'input'->'personas'<>v_in->'input'->'personas' OR v_fb->'input'->'same_as'<>v_in->'input'->'same_as'
       OR (v_fb->'input'->'persons')-'assertions'<>(v_in->'input'->'persons')-'assertions' THEN
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: year_fallback rørte andet end assertions';
    END IF;

    -- ukendt værdi eller forkert type afvises
    FOREACH v_a IN ARRAY ARRAY['"date_raw-v2"'::jsonb,'null'::jsonb,'1'::jsonb,'true'::jsonb] LOOP
      BEGIN
        PERFORM red_identity_candidate_input(-987655401,jsonb_build_object('mode','undecided','year_fallback',v_a));
        RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: year_fallback % blev accepteret',v_a;
      EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID' THEN RAISE; END IF; END;
    END LOOP;
    BEGIN
      PERFORM red_identity_candidate_input(-987655401,'{"mode":"undecided","year_fallback":"date_raw-v1","x":1}');
      RAISE EXCEPTION 'IDENTITY_CANDIDATE_TEST_FAILED: ekstra nøgle blev accepteret';
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'IDENTITY_CANDIDATE_INPUT_SPEC_INVALID' THEN RAISE; END IF; END;

    RAISE EXCEPTION 'ROLLBACK_6B4_YEAR_FALLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='ROLLBACK_6B4_YEAR_FALLBACK' THEN
      RAISE NOTICE 'OK: årstalsreserven fra date_raw er tilvalgt, entydig og lader alt andet være uændret';
    ELSE RAISE; END IF;
  END;
END $identity_candidate_year_fallback$;
