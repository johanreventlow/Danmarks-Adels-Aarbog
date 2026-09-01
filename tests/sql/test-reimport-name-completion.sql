\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE v_signature text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_lock_reimport_name_completion(text)',
    'public.red_authorize_reimport_name_completion(text,uuid,text,text,jsonb,jsonb)',
    'public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)',
    'public.red_begin_reimport_name_completion(uuid,text,uuid)',
    'public.red_apply_reimport_name_completion(uuid,text,jsonb)',
    'public.red_finalize_reimport_name_completion(uuid)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RPC_MISSING: %',v_signature;
    END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'private.reimport_writer_profile','private.reimport_authorization','private.reimport_batch',
    'private.reimport_event','private.reimport_name_completion_result'
  ] LOOP
    IF to_regclass(v_signature) IS NULL THEN
      RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_PRIMARY_MISSING: %',v_signature;
    END IF;
  END LOOP;
END $catalog$;

\ir reimport-writer-v2-bootstrap.sql

DO $generic_lifecycle$
DECLARE
  v_actor uuid := '15300000-0000-4000-8000-000000000101';
  v_source_auth uuid; v_source_batch uuid; v_child_auth uuid; v_child_batch uuid;
  v_person bigint; v_record uuid; v_persona uuid := '15300000-0000-4000-8000-000000000102';
  v_authorization_envelope jsonb; v_preflight jsonb; v_result jsonb;
  v_source_payload jsonb; v_person_payload jsonb; v_completion_payload jsonb;
  v_authorized_source jsonb; v_authorized_completion jsonb;
  v_error text; v_event_before text; v_result_before text;
BEGIN
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_V2_BOOTSTRAP_FAILED';
  END IF;
  INSERT INTO auth.users(id,email) VALUES(v_actor,'reimport-name-completion-153@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_actor,'reimport-name-completion-153@example.invalid','redaktion','Task 1 generic name-completion fixture')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Task 1 generic name-completion fixture';
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_source_payload:=jsonb_build_object(
    'review_subject_id','task-1-source-evidence','source_record_key','task-1-name-completion-record',
    'category','person','disposition','retain_source_only','evidence_sha256',repeat('c',64),
    'canonical_target',jsonb_build_object('canonical_person_id',1),
    'source_span',jsonb_build_object('char_from',0,'char_to',18),
    'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text','Task 1 source text','legacy_payload',jsonb_build_object('value','Task 1 source text'),
    'rendition_content_sha256',repeat('d',64)
  );
  v_person_payload:=jsonb_build_object(
    'source_record_key','task-1-name-completion-record','source_id',3,'edition','1939',
    'source_span',jsonb_build_object('char_from',0,'char_to',18),
    'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text','Task 1 source text',
    'verbatim_sha256',encode(extensions.digest(convert_to('Task 1 source text','UTF8'),'sha256'),'hex'),
    'source_persona_id',v_persona,'persona_key','task-1:persona',
    'identity_decision_sha256',repeat('f',64),'review_sha256',repeat('1',64),
    'decision_basis','task-1 generic fixture','name','Task One','sex',NULL,
    'narrative',jsonb_build_object('text','Task 1 narrative','source_record_key','task-1-name-completion-record'),
    'source_mentions','[]'::jsonb,'persona_mention_links','[]'::jsonb,'facts','[]'::jsonb,
    'relations','[]'::jsonb,'families','[]'::jsonb,'uncertainties','[]'::jsonb,
    'staged',true,'rendition_content_sha256',repeat('d',64)
  );
  v_authorized_source:=jsonb_build_object(
    'source-evidence:task-1',v_source_payload,
    'person-create:task-1-name-completion-record',v_person_payload
  );
  v_source_auth:=public.red_authorize_reimport(
    repeat('a',64),repeat('b',64),current_database(),3,
    'daa-1939-v50-production-write-v1',repeat('a',64),
    '{"person_creates":1,"source_evidence":1,"canonical_delta":0}'::jsonb,
    v_authorized_source,'15300000-0000-4000-8000-000000000103',clock_timestamp()+interval '5 minutes'
  );
  v_source_batch:=public.red_begin_reimport(v_source_auth,repeat('a',64),repeat('b',64));
  PERFORM public.red_apply_reimport_source_evidence(v_source_batch,'source-evidence:task-1',v_source_payload);
  v_person:=public.red_apply_reimport_person_create(v_source_batch,'person-create:task-1-name-completion-record',v_person_payload);
  IF public.red_finalize_reimport(v_source_batch)->>'status'<>'finalized' THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_SOURCE_FIXTURE_NOT_FINALIZED';
  END IF;
  SELECT id INTO v_record FROM private.source_record
   WHERE source_id=3 AND record_key='task-1-name-completion-record';
  IF v_record IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.reimport_event event
     WHERE event.batch_id=v_source_batch AND event.element_id='person-create:task-1-name-completion-record'
       AND event.operation='person_create' AND event.canonical_person_id=v_person
       AND event.payload ?& ARRAY['event_id','narrative_id','publication_state_sha256','state_sha256']
       AND nullif(event.payload->>'event_id','') IS NOT NULL
       AND nullif(event.payload->>'narrative_id','') IS NOT NULL
       AND event.payload->>'publication_state_sha256' ~ '^[0-9a-f]{64}$'
       AND event.payload->>'state_sha256' ~ '^[0-9a-f]{64}$'
  ) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_SOURCE_RECEIPT_MISSING';
  END IF;

  v_completion_payload:=jsonb_build_object(
    'source_batch_id',v_source_batch,'source_person_create_element_id','person-create:task-1-name-completion-record',
    'person_id',v_person,'source_id',3,'edition','1939','source_record_key','task-1-name-completion-record',
    'source_persona_id',v_persona,'name','Task One',
    'source_span',v_person_payload->'source_span','page_evidence',v_person_payload->'page_evidence',
    'verbatim_text',v_person_payload->>'verbatim_text','verbatim_sha256',v_person_payload->>'verbatim_sha256',
    'source_payload_sha256',private.reimport_canonical_json_sha256(v_person_payload),
    'expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),
    'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1)
  );
  v_authorized_completion:=jsonb_build_object('name-completion:task-1-name-completion-record',v_completion_payload);
  v_authorization_envelope:=public.red_authorize_reimport_name_completion(
    repeat('1',64),v_source_batch,repeat('b',64),repeat('a',64),
    '{"name_completions":1,"operations":1}'::jsonb,v_authorized_completion
  );
  v_child_auth:=(v_authorization_envelope->>'authorization_id')::uuid;
  v_preflight:=public.red_preflight_reimport_name_completion(v_child_auth,v_source_batch,repeat('1',64),v_authorized_completion);
  IF v_preflight->'authorization' IS DISTINCT FROM v_authorization_envelope
     OR v_preflight->'preflight'->>'valid'<>'true'
     OR (v_preflight->'preflight'->>'source_batch_id')::uuid IS DISTINCT FROM v_source_batch THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_PREFLIGHT_INVALID';
  END IF;
  v_child_batch:=public.red_begin_reimport_name_completion(v_child_auth,repeat('1',64),v_source_batch);
  PERFORM public.red_apply_reimport_name_completion(v_child_batch,'name-completion:task-1-name-completion-record',v_completion_payload);
  v_result:=public.red_finalize_reimport_name_completion(v_child_batch);
  IF v_result->>'status'<>'finalized'
     OR v_result->'result_map'->'name-completion:task-1-name-completion-record' IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_FINAL_RESULT_INVALID';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM private.reimport_authorization child_authorization
      JOIN private.reimport_batch child_batch ON child_batch.authorization_id=child_authorization.id
      JOIN private.reimport_authorization source_authorization ON source_authorization.id=v_source_auth
      JOIN private.reimport_batch source_batch ON source_batch.id=v_source_batch
      JOIN private.reimport_name_completion_result result ON result.batch_id=child_batch.id
      JOIN private.reimport_event child_event ON child_event.batch_id=child_batch.id
     WHERE child_authorization.id=v_child_auth AND child_batch.id=v_child_batch
       AND child_authorization.source_id=source_authorization.source_id
       AND child_authorization.profile_id=source_authorization.profile_id
       AND child_authorization.profile_sha256=source_authorization.profile_sha256
       AND child_batch.source_id=source_batch.source_id
       AND child_batch.profile_id=source_batch.profile_id
       AND child_batch.profile_sha256=source_batch.profile_sha256
       AND result.source_batch_id=v_source_batch AND result.person_id=v_person
       AND result.source_record_id=v_record AND result.source_persona_id=v_persona
       AND child_event.element_id='name-completion:task-1-name-completion-record'
       AND child_event.operation='canonical_delta' AND child_event.canonical_person_id=v_person
  ) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_PROFILE_OR_SOURCE_LINKAGE_INVALID';
  END IF;

  SELECT event::text INTO v_event_before
    FROM private.reimport_event event
   WHERE event.batch_id=v_child_batch
     AND event.element_id='name-completion:task-1-name-completion-record';
  IF v_event_before IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_EVENT_SEED_MISSING';
  END IF;
  BEGIN
    UPDATE private.reimport_event
       SET operation='tampered'
     WHERE batch_id=v_child_batch
       AND element_id='name-completion:task-1-name-completion-record';
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_EVENT_APPEND_ONLY'
     OR (SELECT event::text FROM private.reimport_event event WHERE event.batch_id=v_child_batch AND event.element_id='name-completion:task-1-name-completion-record') IS DISTINCT FROM v_event_before THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_EVENT_UPDATE_ACCEPTED: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    DELETE FROM private.reimport_event
     WHERE batch_id=v_child_batch
       AND element_id='name-completion:task-1-name-completion-record';
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_EVENT_APPEND_ONLY'
     OR (SELECT event::text FROM private.reimport_event event WHERE event.batch_id=v_child_batch AND event.element_id='name-completion:task-1-name-completion-record') IS DISTINCT FROM v_event_before THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_EVENT_DELETE_ACCEPTED: %',v_error;
  END IF;

  SELECT result::text INTO v_result_before
    FROM private.reimport_name_completion_result result
   WHERE result.batch_id=v_child_batch
     AND result.source_batch_id=v_source_batch AND result.person_id=v_person
     AND result.source_record_id=v_record AND result.source_persona_id=v_persona;
  IF v_result_before IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RESULT_SEED_MISSING';
  END IF;
  v_error:=NULL;
  BEGIN
    UPDATE private.reimport_name_completion_result
       SET element_id='tampered'
     WHERE batch_id=v_child_batch AND source_batch_id=v_source_batch AND person_id=v_person
       AND source_record_id=v_record AND source_persona_id=v_persona;
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_NAME_COMPLETION_RESULT_APPEND_ONLY'
     OR (SELECT result::text FROM private.reimport_name_completion_result result WHERE result.batch_id=v_child_batch AND result.source_batch_id=v_source_batch AND result.person_id=v_person AND result.source_record_id=v_record AND result.source_persona_id=v_persona) IS DISTINCT FROM v_result_before THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RESULT_UPDATE_ACCEPTED: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    DELETE FROM private.reimport_name_completion_result
     WHERE batch_id=v_child_batch AND source_batch_id=v_source_batch AND person_id=v_person
       AND source_record_id=v_record AND source_persona_id=v_persona;
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_NAME_COMPLETION_RESULT_APPEND_ONLY'
     OR (SELECT result::text FROM private.reimport_name_completion_result result WHERE result.batch_id=v_child_batch AND result.source_batch_id=v_source_batch AND result.person_id=v_person AND result.source_record_id=v_record AND result.source_persona_id=v_persona) IS DISTINCT FROM v_result_before THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RESULT_DELETE_ACCEPTED: %',v_error;
  END IF;
END $generic_lifecycle$;

DO $fixture_visible$
BEGIN
  IF public.narrative_record_contract_version()<>2
     OR NOT EXISTS (
       SELECT 1 FROM private.narrative_record_cutover_receipt
        WHERE nonce='15300000-0000-4000-8000-000000000004'
     ) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_V2_BOOTSTRAP_NOT_VISIBLE';
  END IF;
END $fixture_visible$;

ROLLBACK;
