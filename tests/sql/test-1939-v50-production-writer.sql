\set ON_ERROR_STOP on

DO $facade_matrix$
DECLARE
  v_legacy text[]:=ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_begin_1939_v50_reimport(uuid,text,text)',
    'public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)',
    'public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)',
    'public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)',
    'public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)',
    'public.red_activate_1939_v50_batch(uuid,uuid)',
    'public.red_lock_1939_v50_name_completion(text)',
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_name_completion(uuid)'
  ];
  v_generic text[]:=ARRAY[
    'red_authorize_reimport','red_begin_reimport','red_apply_reimport_source_evidence',
    'red_apply_reimport_person_create','red_apply_reimport_name_completion','red_finalize_reimport',
    'red_authorize_reimport_reversal','red_reverse_reimport','red_authorize_reimport_cutover',
    'red_activate_reimport_batch','red_lock_reimport_name_completion',
    'red_authorize_reimport_name_completion','red_preflight_reimport_name_completion',
    'red_begin_reimport_name_completion','red_apply_reimport_name_completion',
    'red_finalize_reimport_name_completion'
  ];
  v_return text[]:=ARRAY['uuid','uuid','void','bigint','void','jsonb','uuid','jsonb','uuid','jsonb','void','uuid','jsonb','uuid','void','jsonb'];
  v_index integer; v_definition text;
BEGIN
  IF (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_authorization'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_batch'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_event'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_name_completion_result'::regclass)<>'v' THEN
    RAISE EXCEPTION 'REIMPORT_1939_FACADE_VIEW_REQUIRED';
  END IF;
  FOR v_index IN 1..array_length(v_legacy,1) LOOP
    IF to_regprocedure(v_legacy[v_index]) IS NULL
       OR pg_get_function_result(v_legacy[v_index]::regprocedure) IS DISTINCT FROM v_return[v_index] THEN
      RAISE EXCEPTION 'REIMPORT_1939_FACADE_SIGNATURE_OR_RETURN_DRIFT: %',v_legacy[v_index];
    END IF;
    v_definition:=pg_get_functiondef(v_legacy[v_index]::regprocedure);
    IF length(string_to_array(v_definition,v_generic[v_index]))-1<>1
       OR v_definition ~* '\\m(INSERT|UPDATE|DELETE)\\M|pg_advisory|LOCK TABLE|validate_reimport_1939' THEN
      RAISE EXCEPTION 'REIMPORT_1939_FACADE_DELEGATION_DRIFT: %',v_legacy[v_index];
    END IF;
  END LOOP;
END $facade_matrix$;

DO $test$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_auth uuid; v_batch uuid; v_reversal_auth uuid; v_person bigint; v_result jsonb;
  v_source_payload jsonb; v_person_payload jsonb;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT DO NOTHING;
  INSERT INTO auth.users(id,email) VALUES(v_actor,'writer-test@example.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'writer-test@example.invalid','redaktion','Writer test')
    ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Writer test';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_source_payload := jsonb_build_object('review_subject_id','fixture','source_record_key','record-evidence-fixture','category','fact','disposition','retain_source_only','evidence_sha256',repeat('c',64),'canonical_target',jsonb_build_object('canonical_person_id',1),'source_span',jsonb_build_object('char_from',0,'char_to',8),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','evidence','legacy_payload',jsonb_build_object('value','evidence'),'rendition_content_sha256',repeat('d',64));
  v_person_payload := jsonb_build_object('source_record_key','record-fixture','source_id',3,'edition','1939','source_span',jsonb_build_object('char_from',10,'char_to',17),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','Fixture','verbatim_sha256',repeat('e',64),'source_persona_id','33333333-3333-5333-8333-333333333333','persona_key','1939:record-fixture','identity_decision_sha256',repeat('f',64),'review_sha256',repeat('1',64),'decision_basis','fixture','name','Fixture','sex',NULL,'narrative',jsonb_build_object('text','Fixture','source_record_key','record-fixture'),'source_mentions','[]'::jsonb,'persona_mention_links','[]'::jsonb,'facts','[]'::jsonb,'relations','[]'::jsonb,'families','[]'::jsonb,'uncertainties','[]'::jsonb,'staged',true,'rendition_content_sha256',repeat('d',64));
  BEGIN
    PERFORM public.red_authorize_1939_v50_reimport(repeat('a',64),repeat('b',64),'wrong-db',3,'{"person_creates":1,"source_evidence":1,"canonical_delta":0}'::jsonb,jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
    RAISE EXCEPTION 'REIMPORT_1939_DATABASE_DRIFT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_DATABASE_DRIFT_ACCEPTED' THEN RAISE; END IF;
  END;
  v_auth := public.red_authorize_1939_v50_reimport(
    repeat('a',64),repeat('b',64),current_database(),3,
    '{"person_creates":1,"source_evidence":1,"canonical_delta":0}'::jsonb,
    jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),
    '22222222-2222-4222-8222-222222222222',clock_timestamp()+interval '5 minutes');
  v_batch := public.red_begin_1939_v50_reimport(v_auth,repeat('a',64),repeat('b',64));
  IF NOT EXISTS (SELECT 1 FROM private.reimport_authorization WHERE id=v_auth AND source_id=3
      AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=repeat('a',64))
     OR NOT EXISTS (SELECT 1 FROM private.reimport_batch WHERE id=v_batch AND authorization_id=v_auth
      AND source_id=3 AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=repeat('a',64)) THEN
    RAISE EXCEPTION 'REIMPORT_1939_FACADE_PROFILE_PARITY_FAILED';
  END IF;
  BEGIN
    PERFORM public.red_apply_1939_v50_source_evidence(v_batch,'source-evidence:fixture',v_source_payload||'{"verbatim_text":"tampered"}'::jsonb);
    RAISE EXCEPTION 'REIMPORT_1939_TAMPERED_PAYLOAD_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_TAMPERED_PAYLOAD_ACCEPTED' THEN RAISE; END IF;
  END;
  PERFORM public.red_apply_1939_v50_source_evidence(v_batch,'source-evidence:fixture',v_source_payload);
  v_person := public.red_apply_1939_v50_person_create(v_batch,'person-create:record-fixture',v_person_payload);
  IF v_person IS NULL OR NOT EXISTS(SELECT 1 FROM public.person WHERE id=v_person AND staged) THEN
    RAISE EXCEPTION 'REIMPORT_1939_PERSON_CREATE_FAILED';
  END IF;
  v_result := public.red_finalize_1939_v50_reimport(v_batch);
  IF v_result->>'status' <> 'finalized' THEN RAISE EXCEPTION 'REIMPORT_1939_FINALIZE_FAILED'; END IF;
  v_reversal_auth := public.red_authorize_1939_v50_reversal(v_batch,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  BEGIN
    PERFORM public.red_reverse_1939_v50_reimport(gen_random_uuid(),v_reversal_auth);
    RAISE EXCEPTION 'REIMPORT_1939_CROSS_BATCH_REVERSAL_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_CROSS_BATCH_REVERSAL_ACCEPTED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.red_begin_1939_v50_reimport(v_auth,repeat('a',64),repeat('b',64));
    RAISE EXCEPTION 'REIMPORT_1939_AUTH_REUSE_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_AUTH_REUSE_ACCEPTED' THEN RAISE; END IF;
  END;
END $test$;

DO $test$
BEGIN
  BEGIN
    UPDATE private.reimport_1939_write_event SET operation='tampered';
    RAISE EXCEPTION 'REIMPORT_1939_EVENT_MUTATION_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_EVENT_MUTATION_ACCEPTED' THEN RAISE; END IF;
  END;
END $test$;

DO $test$
BEGIN
  IF has_table_privilege('anon','private.reimport_1939_write_event','SELECT')
     OR has_table_privilege('authenticated','private.reimport_1939_write_event','SELECT') THEN
    RAISE EXCEPTION 'REIMPORT_1939_PRIVATE_GRANT_INVALID';
  END IF;
  IF has_function_privilege('authenticated','public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamp with time zone)','EXECUTE') THEN
    RAISE EXCEPTION 'REIMPORT_1939_SELF_AUTHORIZATION_EXPOSED';
  END IF;
END $test$;
