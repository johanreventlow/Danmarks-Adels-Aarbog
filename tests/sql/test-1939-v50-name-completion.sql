\set ON_ERROR_STOP on

BEGIN;
\ir reimport-writer-v2-bootstrap.sql
COMMIT;
\ir ../../db-rls.sql

-- The facade keeps the legacy surface only.  Generic v2 lifecycle coverage is
-- in test-reimport-name-completion.sql; an anchor-less pre-#153 source chain
-- must remain non-executable after upgrade.
DO $facade$
DECLARE
  v_legacy text[]:=ARRAY[
    'public.red_lock_1939_v50_name_completion(text)',
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)',
    'public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_name_completion(uuid)'
  ];
  v_generic text[]:=ARRAY[
    'red_lock_reimport_name_completion','red_authorize_reimport_name_completion',
    'red_preflight_reimport_name_completion','red_begin_reimport_name_completion',
    'red_apply_reimport_name_completion','red_finalize_reimport_name_completion'
  ];
  v_return text[]:=ARRAY['void','jsonb','jsonb','uuid','void','jsonb'];
  v_index integer; v_definition text;
BEGIN
  IF (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_authorization'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_batch'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_write_event'::regclass)<>'v'
     OR (SELECT relkind FROM pg_class WHERE oid='private.reimport_1939_name_completion_result'::regclass)<>'v' THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_FACADE_VIEW_REQUIRED';
  END IF;
  FOR v_index IN 1..array_length(v_legacy,1) LOOP
    IF to_regprocedure(v_legacy[v_index]) IS NULL
       OR pg_get_function_result(v_legacy[v_index]::regprocedure) IS DISTINCT FROM v_return[v_index] THEN
      RAISE EXCEPTION 'NAME_COMPLETION_1939_FACADE_SIGNATURE_DRIFT: %',v_legacy[v_index];
    END IF;
    v_definition:=pg_get_functiondef(v_legacy[v_index]::regprocedure);
    IF cardinality(string_to_array(v_definition,v_generic[v_index]))-1<>1
       OR v_definition ~* '\\m(INSERT|UPDATE|DELETE)\\M|pg_advisory|LOCK TABLE|validate_reimport_1939' THEN
      RAISE EXCEPTION 'NAME_COMPLETION_1939_FACADE_DELEGATION_DRIFT: %',v_legacy[v_index];
    END IF;
  END LOOP;
END $facade$;

-- The v2 primary reports its generic authorization failure.  The facade must
-- retain the historic 1939 token and must not blanket-translate other errors.
DO $role_error_map$
BEGIN
  PERFORM set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
  BEGIN
    PERFORM public.red_lock_1939_v50_name_completion(repeat('1',64));
    RAISE EXCEPTION 'NAME_COMPLETION_1939_ROLE_ERROR_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NAME_COMPLETION_1939_ROLE_ERROR_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_1939_ROLE_FORBIDDEN' THEN RAISE; END IF;
  END;
END $role_error_map$;

DO $legacy_chain$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_source_auth uuid := '560c39f8-5c87-4c0d-a768-025d97fa2973';
  v_source_batch uuid := '560c39f8-5c87-4c0d-a768-025d97fa2974';
  v_run uuid := '560c39f8-5c87-4c0d-a768-025d97fa2972';
  v_persona uuid := '00000000-0000-4000-8000-000000000001';
  v_payload jsonb; v_source_payload jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO auth.users(id,email) VALUES(v_actor,'writer-ci@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'writer-ci@example.invalid','redaktion','Writer CI') ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Writer CI';
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','fixture-v1',repeat('a',64),
    '{"run_key_prefix":"fixture:","schema_version":"fixture","extractor_version":"fixture","rendition_key":"fixture","rendition_kind":"ocr_text","rendition_metadata":{},"observation_extraction_method":"fixture","citation_label_template":"Fixture"}'::jsonb)
  ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,3,'name-completion-legacy-facade','fixture','fixture','fixture',repeat('a',64),'{}') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.person(id,staged) VALUES(1846,true) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES('10000000-0000-4000-8000-000000000001',3,'legacy-name-record','person',v_run) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  VALUES(v_persona,3,'1939:legacy-name-record',v_run) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
  VALUES(v_persona,1846,'accepted',1,'{"fixture":true}',v_actor,'Writer CI',clock_timestamp()) ON CONFLICT DO NOTHING;
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at)
  SELECT source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
    FROM private.source_persona_identity WHERE source_persona_id=v_persona AND canonical_person_id=1846;
  INSERT INTO private.reimport_1939_authorization(id,operation,manifest_sha256,preview_sha256,database_identity,source_id,profile_id,profile_sha256,expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at)
  VALUES(v_source_auth,'reimport',repeat('c',64),repeat('d',64),current_database(),3,
    'daa-1939-v50-production-write-v1',repeat('a',64),'{"person_creates":1,"source_evidence":0}'::jsonb,'{}',v_actor,
    '560c39f8-5c87-4c0d-a768-025d97fa2901',clock_timestamp()+interval '1 hour','consumed',clock_timestamp());
  INSERT INTO private.reimport_1939_write_batch(id,authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,status,expected_counts,observed_counts,finalized_at)
  VALUES(v_source_batch,v_source_auth,repeat('c',64),repeat('d',64),3,'daa-1939-v50-production-write-v1',repeat('a',64),v_actor,'finalized',
    '{"person_creates":1,"source_evidence":0}'::jsonb,'{"person_creates":1,"source_evidence":0}'::jsonb,clock_timestamp());
  v_source_payload:=jsonb_build_object('source_record_key','legacy-name-record','source_id',3,'source_persona_id',v_persona,
    'source_span',jsonb_build_object('char_from',0,'char_to',10),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text','Legacy name','name','Legacy name');
  INSERT INTO private.reimport_1939_write_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256)
  VALUES(v_source_batch,'person-create:legacy-name-record','person_create','legacy-name-record',1846,v_source_payload,repeat('e',64));
  v_payload:=jsonb_build_object('name-completion:legacy-name-record',jsonb_build_object(
    'source_batch_id',v_source_batch,'source_person_create_element_id','person-create:legacy-name-record','person_id',1846,
    'source_id',3,'source_record_key','legacy-name-record','source_persona_id',v_persona,'name','Legacy name',
    'source_span',jsonb_build_object('char_from',0,'char_to',10),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text','Legacy name','source_payload_sha256',private.reimport_canonical_json_sha256(v_source_payload)));
  BEGIN
    PERFORM public.red_authorize_1939_v50_name_completion(repeat('1',64),v_source_batch,repeat('d',64),repeat('c',64),
      '{"name_completions":1,"operations":1}'::jsonb,v_payload);
    RAISE EXCEPTION 'NAME_COMPLETION_1939_LEGACY_CHAIN_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NAME_COMPLETION_1939_LEGACY_CHAIN_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'NAME_COMPLETION_1939_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM private.reimport_name_completion_result WHERE source_batch_id=v_source_batch)
     OR (SELECT status FROM private.reimport_batch WHERE id=v_source_batch)<>'finalized' THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_LEGACY_CHAIN_MUTATED';
  END IF;
END $legacy_chain$;
