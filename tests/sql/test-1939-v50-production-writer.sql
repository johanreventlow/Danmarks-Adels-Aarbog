\set ON_ERROR_STOP on

DO $test$
BEGIN
  IF to_regclass('private.reimport_1939_authorization') IS NULL
     OR to_regclass('private.reimport_1939_write_batch') IS NULL
     OR to_regclass('private.reimport_1939_write_event') IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_1939_WRITER_CONTRACT_MISSING';
  END IF;
END $test$;

DO $test$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_auth uuid; v_batch uuid; v_person bigint; v_result jsonb;
  v_source_payload jsonb; v_person_payload jsonb;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT DO NOTHING;
  INSERT INTO auth.users(id,email) VALUES(v_actor,'writer-test@example.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'writer-test@example.invalid','redaktion','Writer test')
    ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Writer test';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_source_payload := jsonb_build_object('review_subject_id','fixture','source_record_key','record-evidence-fixture','category','fact','disposition','retain_source_only','evidence_sha256',repeat('c',64),'canonical_target',jsonb_build_object('canonical_person_id',1),'source_span',jsonb_build_object('char_from',0,'char_to',8),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','evidence','legacy_payload',jsonb_build_object('value','evidence'),'rendition_content_sha256',repeat('d',64));
  v_person_payload := jsonb_build_object('source_record_key','record-fixture','source_id',3,'edition','1939','source_span',jsonb_build_object('char_from',10,'char_to',17),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','Fixture','verbatim_sha256',repeat('e',64),'source_persona_id','33333333-3333-5333-8333-333333333333','persona_key','1939:record-fixture','identity_decision_sha256',repeat('f',64),'review_sha256',repeat('1',64),'decision_basis','fixture','name','Fixture','sex',NULL,'narrative',jsonb_build_object('text','Fixture','source_record_key','record-fixture'),'source_mentions','[]'::jsonb,'persona_mention_links','[]'::jsonb,'facts','[]'::jsonb,'relations','[]'::jsonb,'families','[]'::jsonb,'uncertainties','[]'::jsonb,'staged',true,'rendition_content_sha256',repeat('d',64));
  v_auth := public.red_authorize_1939_v50_reimport(
    repeat('a',64),repeat('b',64),'fixture-db',3,
    '{"person_creates":1,"source_evidence":1,"canonical_delta":0}'::jsonb,
    jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),
    '22222222-2222-4222-8222-222222222222',clock_timestamp()+interval '5 minutes');
  v_batch := public.red_begin_1939_v50_reimport(v_auth,repeat('a',64),repeat('b',64));
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
