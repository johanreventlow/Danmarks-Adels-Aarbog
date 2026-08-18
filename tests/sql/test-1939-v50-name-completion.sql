\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;
CREATE TEMP TABLE name_completion_1939_test_state (
  authorization_id uuid NOT NULL,
  source_batch_id uuid NOT NULL,
  payloads jsonb NOT NULL,
  authorization_envelope jsonb NOT NULL
) ON COMMIT PRESERVE ROWS;

DO $test$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_other_actor uuid := '99999999-9999-4999-8999-999999999999';
  v_source_batch uuid := '560c39f8-5c87-4c0d-a768-025d97fa2974';
  v_source_auth uuid := '560c39f8-5c87-4c0d-a768-025d97fa2973';
  v_run uuid := '560c39f8-5c87-4c0d-a768-025d97fa2972';
  v_auth uuid; v_completion_batch uuid; v_envelope jsonb; v_preflight jsonb; v_result jsonb;
  v_payloads jsonb := '{}'::jsonb; v_payload jsonb; v_source_payload jsonb;
  v_person bigint; v_record text; v_persona uuid; v_name text; v_page integer; v_element text;
  v_index integer; v_busy integer; v_temp_fact bigint;
BEGIN
  IF to_regclass('private.reimport_1939_name_completion_result') IS NULL THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_RESULT_TABLE_MISSING';
  END IF;
  IF to_regprocedure('public.red_lock_1939_v50_name_completion(text)') IS NULL
     OR to_regprocedure('public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)') IS NULL
     OR to_regprocedure('public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_begin_1939_v50_name_completion(uuid,text,uuid)') IS NULL
     OR to_regprocedure('public.red_apply_1939_v50_name_completion(uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_finalize_1939_v50_name_completion(uuid)') IS NULL THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_RPC_MISSING';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,3,'name-completion-fixture','fixture','fixture','fixture',repeat('a',64),'{}')
  ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_1939_authorization(id,operation,manifest_sha256,preview_sha256,database_identity,source_id,expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at)
  VALUES(v_source_auth,'reimport',repeat('a',64),repeat('b',64),current_database(),3,
    '{"person_creates":8,"source_evidence":0,"canonical_delta":0}'::jsonb,'{}',v_actor,
    '560c39f8-5c87-4c0d-a768-025d97fa2901',clock_timestamp()+interval '1 hour','consumed',clock_timestamp());
  INSERT INTO private.reimport_1939_write_batch(id,authorization_id,manifest_sha256,preview_sha256,principal_id,status,expected_counts,observed_counts,finalized_at)
  VALUES(v_source_batch,v_source_auth,repeat('a',64),repeat('b',64),v_actor,'finalized',
    '{"person_creates":8,"source_evidence":0,"canonical_delta":0}'::jsonb,
    '{"person_creates":8,"source_evidence":0,"canonical_delta":0}'::jsonb,clock_timestamp());

  FOR v_index IN 1..8 LOOP
    v_person := 1845 + v_index;
    v_record := 'record-fixture-' || v_index;
    v_persona := ('00000000-0000-4000-8000-' || lpad(v_index::text,12,'0'))::uuid;
    v_name := CASE v_index WHEN 1 THEN 'Fixture' ELSE 'Fixture ' || v_index END;
    v_page := 505 + v_index;
    v_element := 'person-create:' || v_record;
    INSERT INTO public.person(id,staged) VALUES(v_person,true);
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
    VALUES(('10000000-0000-4000-8000-' || lpad(v_index::text,12,'0'))::uuid,3,v_record,'person',v_run);
    INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
    VALUES(v_persona,3,'1939:' || v_record,v_run);
    INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
    VALUES(v_persona,v_person,'accepted',1,'{"fixture":true}',v_actor,'Writer CI',clock_timestamp());
    INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
    SELECT v_persona,v_person,'accepted',1,'{"fixture":true}',v_actor,'Writer CI',decided_at
      FROM private.source_persona_identity WHERE source_persona_id=v_persona;
    v_source_payload := jsonb_build_object(
      'source_record_key',v_record,'source_id',3,'edition','1939','source_persona_id',v_persona,
      'source_span',jsonb_build_object('char_from',v_index,'char_to',v_index+10),
      'page_evidence',jsonb_build_object('page_from',v_page,'page_to',v_page),
      'verbatim_text',v_name || ' source text','verbatim_sha256',encode(extensions.digest((v_name || ' source text')::bytea,'sha256'),'hex'),
      'staged',true,'name',v_name,'facts','[]'::jsonb,'relations','[]'::jsonb,'families','[]'::jsonb
    );
    INSERT INTO private.reimport_1939_write_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256)
    VALUES(v_source_batch,v_element,'person_create',v_record,v_person,v_source_payload,
      encode(extensions.digest(v_source_payload::text,'sha256'),'hex'));
    v_payload := jsonb_build_object(
      'source_batch_id',v_source_batch,'source_person_create_element_id',v_element,'person_id',v_person,
      'source_id',3,'edition','1939','source_record_key',v_record,'source_persona_id',v_persona,
      'name',v_name,'source_span',v_source_payload->'source_span','page_evidence',v_source_payload->'page_evidence',
      'verbatim_text',v_source_payload->>'verbatim_text','verbatim_sha256',v_source_payload->>'verbatim_sha256',
      'source_payload_sha256',private.reimport_1939_canonical_json_sha256(v_source_payload),
      'expected_before','{"staged":true,"name_cache_empty":true,"name_facts":0}'::jsonb,
      'expected_after','{"name_fact":1,"selected_assertion":1,"daa_1939_citation":1,"conclusion":1}'::jsonb
    );
    v_payloads := v_payloads || jsonb_build_object('name-completion:' || v_record,v_payload);
  END LOOP;

  v_envelope := public.red_authorize_1939_v50_name_completion(
    repeat('1',64),v_source_batch,repeat('a',64),repeat('b',64),
    '{"name_completions":8,"operations":8}'::jsonb,v_payloads);
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_envelope) AS t(key))
       <> ARRAY['authorization_id','database_name','system_identifier']
     OR v_envelope->>'database_name'<>current_database()
     OR nullif(v_envelope->>'system_identifier','') IS NULL THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_AUTHORIZATION_ENVELOPE_INVALID';
  END IF;
  v_auth := (v_envelope->>'authorization_id')::uuid;
  INSERT INTO name_completion_1939_test_state
    VALUES(v_auth,v_source_batch,v_payloads,v_envelope);
END $test$;

DO $test$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_other_actor uuid := '99999999-9999-4999-8999-999999999999';
  v_source_batch uuid; v_auth uuid; v_completion_batch uuid; v_envelope jsonb; v_preflight jsonb; v_result jsonb;
  v_payloads jsonb; v_payload jsonb;
  v_record text; v_element text; v_index integer; v_busy integer; v_temp_fact bigint;
BEGIN
  SELECT authorization_id,source_batch_id,payloads,authorization_envelope
    INTO v_auth,v_source_batch,v_payloads,v_envelope
    FROM name_completion_1939_test_state;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  PERFORM public.red_lock_1939_v50_name_completion(repeat('1',64));

  INSERT INTO auth.users(id,email) VALUES(v_other_actor,'other-writer-ci@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_other_actor,'other-writer-ci@example.invalid','redaktion','Other Writer CI')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Other Writer CI';
  PERFORM set_config('request.jwt.claim.sub',v_other_actor::text,true);
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_WRONG_ACTOR_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_WRONG_ACTOR_ACCEPTED' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  UPDATE private.reimport_1939_authorization SET expires_at=clock_timestamp()-interval '1 minute' WHERE id=v_auth;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_EXPIRED_AUTH_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_EXPIRED_AUTH_ACCEPTED' THEN RAISE; END IF; END;
  UPDATE private.reimport_1939_authorization SET expires_at=clock_timestamp()+interval '5 minutes' WHERE id=v_auth;

  SELECT coalesce(max(id),0)+1 INTO v_temp_fact FROM public.fact;
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES(v_temp_fact,'person',1846,'navn');
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_EXISTING_NAME_FACT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_EXISTING_NAME_FACT_ACCEPTED' THEN RAISE; END IF; END;
  DELETE FROM public.fact WHERE id=v_temp_fact;

  DELETE FROM private.source_persona_identity WHERE source_persona_id='00000000-0000-4000-8000-000000000001';
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_MISSING_SOURCE_LINK_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_MISSING_SOURCE_LINK_ACCEPTED' THEN RAISE; END IF; END;
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
  SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
    FROM private.source_persona_identity_event
    WHERE source_persona_id='00000000-0000-4000-8000-000000000001'
    ORDER BY version DESC LIMIT 1;
END $test$;

DO $test$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_source_batch uuid; v_auth uuid; v_completion_batch uuid; v_envelope jsonb; v_preflight jsonb; v_result jsonb;
  v_payloads jsonb; v_payload jsonb;
  v_record text; v_element text; v_index integer; v_busy integer; v_remote_pid integer; v_attempt integer; v_temp_fact bigint;
  v_blocked boolean;
BEGIN
  SELECT authorization_id,source_batch_id,payloads,authorization_envelope
    INTO v_auth,v_source_batch,v_payloads,v_envelope
    FROM name_completion_1939_test_state;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM public.red_lock_1939_v50_name_completion(repeat('1',64));

  v_preflight := public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_preflight) AS t(key)) <> ARRAY['authorization','preflight']
     OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_preflight->'authorization') AS t(key))
        <> ARRAY['authorization_id','database_name','system_identifier']
     OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_preflight->'preflight') AS t(key))
        <> ARRAY['database_name','manifest_sha256','source_batch_id','system_identifier','valid']
     OR v_preflight->'authorization'<>v_envelope
     OR v_preflight->'preflight'<>jsonb_build_object('valid',true,'database_name',current_database(),
          'system_identifier',(pg_control_system()).system_identifier::text,
          'source_batch_id',v_source_batch,'manifest_sha256',repeat('1',64)) THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PREFLIGHT_ENVELOPE_INVALID';
  END IF;

  PERFORM extensions.dblink_connect('name_completion_concurrent','dbname=' || current_database());
  SELECT pid INTO v_remote_pid
    FROM extensions.dblink('name_completion_concurrent','SELECT pg_backend_pid()') AS t(pid integer);
  PERFORM extensions.dblink_exec('name_completion_concurrent','BEGIN');
  PERFORM extensions.dblink_send_query('name_completion_concurrent','UPDATE public.person SET staged=false WHERE id=1846');
  PERFORM pg_sleep(0.2);
  SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=v_remote_pid AND wait_event_type='Lock') INTO v_blocked;
  v_busy:=extensions.dblink_is_busy('name_completion_concurrent');
  IF v_busy=1 THEN PERFORM extensions.dblink_cancel_query('name_completion_concurrent'); END IF;
  FOR v_attempt IN 1..100 LOOP
    EXIT WHEN extensions.dblink_is_busy('name_completion_concurrent')=0;
    PERFORM pg_sleep(0.01);
  END LOOP;
  PERFORM status FROM extensions.dblink_get_result('name_completion_concurrent',false) AS t(status text);
  PERFORM status FROM extensions.dblink_get_result('name_completion_concurrent',false) AS t(status text);
  PERFORM extensions.dblink_exec('name_completion_concurrent','ROLLBACK');
  PERFORM extensions.dblink_disconnect('name_completion_concurrent');
  IF NOT v_blocked THEN RAISE EXCEPTION 'NAME_COMPLETION_1939_CONCURRENT_PERSON_MUTATION_ACCEPTED'; END IF;

  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(gen_random_uuid(),v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_UNKNOWN_AUTH_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_UNKNOWN_AUTH_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,gen_random_uuid(),repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_SOURCE_BATCH_DRIFT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_SOURCE_BATCH_DRIFT_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),
      jsonb_set(v_payloads,'{name-completion:record-fixture-1,name}','"tampered"'));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_NAME_TAMPER_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_NAME_TAMPER_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),
      jsonb_set(v_payloads,'{name-completion:record-fixture-1,verbatim_text}','"tampered"'));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_TEXT_TAMPER_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_TEXT_TAMPER_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),
      jsonb_set(v_payloads,'{name-completion:record-fixture-1,page_evidence,page_from}','999'));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PAGE_TAMPER_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_PAGE_TAMPER_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),
      jsonb_set(v_payloads,'{name-completion:record-fixture-1,person_id}','999'));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PERSON_TAMPER_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_PERSON_TAMPER_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),
      jsonb_set(v_payloads,'{name-completion:record-fixture-1,source_persona_id}','"00000000-0000-4000-8000-999999999999"'));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PERSONA_TAMPER_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_PERSONA_TAMPER_ACCEPTED' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),
      jsonb_set(v_payloads,'{name-completion:record-fixture-1,source_payload_sha256}','"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_EVENT_HASH_TAMPER_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_EVENT_HASH_TAMPER_ACCEPTED' THEN RAISE; END IF; END;

  UPDATE private.reimport_1939_authorization SET database_identity='{"database_name":"drift","system_identifier":"drift"}' WHERE id=v_auth;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_DATABASE_DRIFT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_DATABASE_DRIFT_ACCEPTED' THEN RAISE; END IF; END;
  UPDATE private.reimport_1939_authorization SET database_identity=jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text WHERE id=v_auth;

  UPDATE public.person SET staged=false WHERE id=1846;
  BEGIN
    PERFORM public.red_preflight_1939_v50_name_completion(v_auth,v_source_batch,repeat('1',64),v_payloads);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_NONSTAGED_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_NONSTAGED_ACCEPTED' THEN RAISE; END IF; END;
  UPDATE public.person SET staged=true WHERE id=1846;

  v_completion_batch := public.red_begin_1939_v50_name_completion(v_auth,repeat('1',64),v_source_batch);
  BEGIN
    PERFORM public.red_finalize_1939_v50_name_completion(v_completion_batch);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_PARTIAL_FINALIZE_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_PARTIAL_FINALIZE_ACCEPTED' THEN RAISE; END IF; END;
  v_payload:=v_payloads->'name-completion:record-fixture-1';
  UPDATE public.person SET staged=false WHERE id=1846;
  BEGIN
    PERFORM public.red_apply_1939_v50_name_completion(v_completion_batch,'name-completion:record-fixture-1',v_payload);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_NONSTAGED_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_APPLY_NONSTAGED_ACCEPTED' THEN RAISE; END IF; END;
  UPDATE public.person SET staged=true WHERE id=1846;
  SELECT coalesce(max(id),0)+1 INTO v_temp_fact FROM public.fact;
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES(v_temp_fact,'person',1846,'navn');
  BEGIN
    PERFORM public.red_apply_1939_v50_name_completion(v_completion_batch,'name-completion:record-fixture-1',v_payload);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_EXISTING_NAME_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_APPLY_EXISTING_NAME_ACCEPTED' THEN RAISE; END IF; END;
  DELETE FROM public.fact WHERE id=v_temp_fact;
  DELETE FROM private.source_persona_identity
    WHERE source_persona_id='00000000-0000-4000-8000-000000000001';
  BEGIN
    PERFORM public.red_apply_1939_v50_name_completion(v_completion_batch,'name-completion:record-fixture-1',v_payload);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_IDENTITY_DRIFT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_APPLY_IDENTITY_DRIFT_ACCEPTED' THEN RAISE; END IF; END;
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
  SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
    FROM private.source_persona_identity_event
    WHERE source_persona_id='00000000-0000-4000-8000-000000000001'
    ORDER BY version DESC LIMIT 1;
  FOR v_index IN 1..8 LOOP
    v_record := 'record-fixture-' || v_index;
    v_element := 'name-completion:' || v_record;
    v_payload := v_payloads->v_element;
    PERFORM public.red_apply_1939_v50_name_completion(v_completion_batch,v_element,v_payload);
  END LOOP;
  BEGIN
    PERFORM public.red_apply_1939_v50_name_completion(v_completion_batch,'name-completion:ninth',v_payloads->'name-completion:record-fixture-1');
    RAISE EXCEPTION 'NAME_COMPLETION_1939_NINTH_ELEMENT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_NINTH_ELEMENT_ACCEPTED' THEN RAISE; END IF; END;
  v_result := public.red_finalize_1939_v50_name_completion(v_completion_batch);
  IF v_result->>'status'<>'finalized'
     OR (SELECT visning_navn FROM public.person WHERE id=1846)<>'Fixture'
     OR (SELECT count(*) FROM public.fact WHERE subjekt_type='person' AND subjekt_id=1846 AND faktatype='navn')<>1
     OR (SELECT count(*) FROM public.citation c JOIN public.assertion a ON a.id=c.assertion_id JOIN public.fact f ON f.id=a.target_id
         WHERE f.subjekt_id=1846 AND c.source_id=3 AND c.side='506' AND c.citat_tekst='Fixture source text')<>1
     OR (SELECT count(*) FROM private.reimport_1939_name_completion_result WHERE batch_id=v_completion_batch)<>8 THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_APPLY_FAILED';
  END IF;
  BEGIN
    PERFORM public.red_begin_1939_v50_name_completion(v_auth,repeat('1',64),v_source_batch);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_AUTH_REUSE_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_AUTH_REUSE_ACCEPTED' THEN RAISE; END IF; END;
END $test$;

DO $test$
BEGIN
  BEGIN
    UPDATE private.reimport_1939_name_completion_result SET element_id='tampered';
    RAISE EXCEPTION 'NAME_COMPLETION_1939_RESULT_MUTATION_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM='NAME_COMPLETION_1939_RESULT_MUTATION_ACCEPTED' THEN RAISE; END IF; END;
  IF has_table_privilege('anon','private.reimport_1939_name_completion_result','SELECT')
     OR has_table_privilege('authenticated','private.reimport_1939_name_completion_result','SELECT')
     OR has_function_privilege('authenticated','public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_RLS_OR_GRANT_INVALID';
  END IF;
END $test$;
