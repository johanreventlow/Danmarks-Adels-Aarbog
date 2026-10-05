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
