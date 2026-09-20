\set ON_ERROR_STOP on

BEGIN;
\ir reimport-writer-v2-bootstrap.sql
COMMIT;
\ir ../../db-rls.sql

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
    'red_apply_reimport_person_create','red_apply_reimport_canonical_delta','red_finalize_reimport',
    'red_authorize_reimport_reversal','red_reverse_reimport','red_authorize_reimport_cutover',
    'red_activate_reimport_batch','red_lock_reimport_name_completion',
    'red_authorize_reimport_name_completion','red_preflight_reimport_name_completion',
    'red_begin_reimport_name_completion','red_apply_reimport_name_completion',
    'red_finalize_reimport_name_completion'
  ];
  v_return text[]:=ARRAY['uuid','uuid','void','bigint','void','jsonb','uuid','jsonb','uuid','jsonb','void','jsonb','jsonb','uuid','void','jsonb'];
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
    IF cardinality(string_to_array(v_definition,v_generic[v_index]))-1<>1
       OR v_definition ~* '\\m(INSERT|UPDATE|DELETE)\\M|pg_advisory|LOCK TABLE|validate_reimport_1939' THEN
      RAISE EXCEPTION 'REIMPORT_1939_FACADE_DELEGATION_DRIFT: %',v_legacy[v_index];
    END IF;
  END LOOP;
END $facade_matrix$;

-- Full public-RPC ACL matrix: every primary and facade is owner-held,
-- SECURITY DEFINER, has an explicit search_path, grants no anon capability,
-- and preserves the service authorization/authenticated mutation split.
DO $rpc_acl_matrix$
DECLARE
  v_generic text[]:=ARRAY[
    'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)',
    'public.red_begin_reimport(uuid,text,text)','public.red_apply_reimport_source_evidence(uuid,text,jsonb)',
    'public.red_apply_reimport_person_create(uuid,text,jsonb)','public.red_finalize_reimport(uuid)',
    'public.red_authorize_reimport_reversal(uuid,uuid,timestamptz)','public.red_reverse_reimport(uuid,uuid)',
    'public.red_authorize_reimport_cutover(uuid,uuid,timestamptz)','public.red_activate_reimport_batch(uuid,uuid)',
    'public.red_lock_reimport_name_completion(text,bigint,text)','public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)',
    'public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)','public.red_begin_reimport_name_completion(uuid,text,uuid)',
    'public.red_apply_reimport_name_completion(uuid,text,jsonb)','public.red_finalize_reimport_name_completion(uuid)'
  ];
  v_legacy text[]:=ARRAY[
    'public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)',
    'public.red_begin_1939_v50_reimport(uuid,text,text)','public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)',
    'public.red_apply_1939_v50_person_create(uuid,text,jsonb)','public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)',
    'public.red_finalize_1939_v50_reimport(uuid)','public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)',
    'public.red_reverse_1939_v50_reimport(uuid,uuid)','public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)',
    'public.red_activate_1939_v50_batch(uuid,uuid)','public.red_lock_1939_v50_name_completion(text)',
    'public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)',
    'public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)','public.red_begin_1939_v50_name_completion(uuid,text,uuid)',
    'public.red_apply_1939_v50_name_completion(uuid,text,jsonb)','public.red_finalize_1939_v50_name_completion(uuid)'
  ];
  v_signature text; v_index integer; v_service boolean; v_authenticated boolean;
BEGIN
  FOR v_index IN 1..array_length(v_generic,1) LOOP
    v_signature:=v_generic[v_index];
    v_service:=v_index IN (1,6,8,11); v_authenticated:=NOT v_service;
    IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_signature::regprocedure
      AND p.proowner=(SELECT oid FROM pg_roles WHERE rolname=current_user) AND p.prosecdef
      AND coalesce(array_to_string(p.proconfig,','),'') LIKE 'search_path=pg_catalog, public, private%')
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE')<>v_service
       OR has_function_privilege('authenticated',v_signature,'EXECUTE')<>v_authenticated THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_GENERIC_ACL_MATRIX_INVALID: %',v_signature;
    END IF;
  END LOOP;
  FOR v_index IN 1..array_length(v_legacy,1) LOOP
    v_signature:=v_legacy[v_index];
    v_service:=v_index IN (1,7,9,12); v_authenticated:=NOT v_service;
    IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_signature::regprocedure
      AND p.proowner=(SELECT oid FROM pg_roles WHERE rolname=current_user) AND p.prosecdef
      AND array_to_string(p.proconfig,',')='search_path=pg_catalog, public, private')
       OR has_function_privilege('anon',v_signature,'EXECUTE')
       OR has_function_privilege('service_role',v_signature,'EXECUTE')<>v_service
       OR has_function_privilege('authenticated',v_signature,'EXECUTE')<>v_authenticated THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_FACADE_ACL_MATRIX_INVALID: %',v_signature;
    END IF;
  END LOOP;
END $rpc_acl_matrix$;

-- The compatibility matrix is intentionally explicit: every historic domain
-- token has one facade mapping and each wrapper re-raises unknown failures.
DO $error_map_matrix$
DECLARE v_signature text; v_token text; v_definition text;
BEGIN
  FOR v_signature,v_token IN VALUES
    ('public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)','REIMPORT_1939_AUTHORIZATION_INVALID'),
    ('public.red_authorize_1939_v50_reimport(text,text,text,bigint,jsonb,jsonb,uuid,timestamptz)','REIMPORT_1939_ROLE_FORBIDDEN'),
    ('public.red_begin_1939_v50_reimport(uuid,text,text)','REIMPORT_1939_AUTHORIZATION_INVALID'),
    ('public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)','REIMPORT_1939_BATCH_INVALID'),
    ('public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)','REIMPORT_1939_ELEMENT_NOT_AUTHORIZED'),
    ('public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)','REIMPORT_1939_SOURCE_EVIDENCE_INVALID'),
    ('public.red_apply_1939_v50_source_evidence(uuid,text,jsonb)','REIMPORT_1939_RENDITION_DRIFT'),
    ('public.red_apply_1939_v50_person_create(uuid,text,jsonb)','REIMPORT_1939_PERSON_CREATE_INVALID'),
    ('public.red_apply_1939_v50_canonical_delta(uuid,text,jsonb)','REIMPORT_1939_CANONICAL_DELTA_UNSUPPORTED'),
    ('public.red_finalize_1939_v50_reimport(uuid)','REIMPORT_1939_FINALIZE_COUNT_MISMATCH'),
    ('public.red_authorize_1939_v50_reversal(uuid,uuid,timestamptz)','REIMPORT_1939_REVERSAL_INVALID'),
    ('public.red_reverse_1939_v50_reimport(uuid,uuid)','REIMPORT_1939_REVERSAL_INVALID'),
    ('public.red_authorize_1939_v50_cutover(uuid,uuid,timestamptz)','REIMPORT_1939_CUTOVER_INVALID'),
    ('public.red_activate_1939_v50_batch(uuid,uuid)','REIMPORT_1939_NAME_COMPLETION_INVALID'),
    ('public.red_lock_1939_v50_name_completion(text)','NAME_COMPLETION_1939_LOCK_INVALID'),
    ('public.red_authorize_1939_v50_name_completion(text,uuid,text,text,jsonb,jsonb)','NAME_COMPLETION_1939_AUTHORIZATION_INVALID'),
    ('public.red_preflight_1939_v50_name_completion(uuid,uuid,text,jsonb)','NAME_COMPLETION_1939_PREFLIGHT_INVALID'),
    ('public.red_begin_1939_v50_name_completion(uuid,text,uuid)','NAME_COMPLETION_1939_AUTHORIZATION_INVALID'),
    ('public.red_apply_1939_v50_name_completion(uuid,text,jsonb)','NAME_COMPLETION_1939_APPLY_INVALID'),
    ('public.red_finalize_1939_v50_name_completion(uuid)','NAME_COMPLETION_1939_FINALIZE_COUNT_MISMATCH')
  LOOP
    v_definition:=pg_get_functiondef(v_signature::regprocedure);
    IF position(v_token IN v_definition)=0 OR position('RAISE;' IN v_definition)=0 THEN
      RAISE EXCEPTION 'REIMPORT_1939_ERROR_MAP_DRIFT: %: %',v_signature,v_token;
    END IF;
  END LOOP;
END $error_map_matrix$;

DO $test$
DECLARE
  v_actor uuid := '11111111-1111-4111-8111-111111111111';
  v_auth uuid; v_batch uuid; v_reversal_auth uuid; v_person bigint; v_result jsonb;
  v_name_authorization uuid; v_name_batch uuid; v_error text;
  v_source_payload jsonb; v_person_payload jsonb; v_completion_payload jsonb;
  v_fact_count bigint; v_assertion_count bigint; v_citation_count bigint;
  v_conclusion_count bigint; v_name_result_count bigint; v_name_event_count bigint;
  v_run uuid:='15300000-0000-4000-8000-000000000201'; v_record uuid:='15300000-0000-4000-8000-000000000202';
  v_rendition uuid; v_occurrence uuid; v_observation uuid; v_placement uuid;
  v_1939_config jsonb := '{"run_key_prefix":"reimport-1939-v50:","schema_version":"1939-v50-production-write-manifest-v1","extractor_version":"production-writer-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed_1939_v50","citation_label_template":"DAA 1939 side {page_from}"}'::jsonb;
  v_profile_sha text;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT DO NOTHING;
  INSERT INTO auth.users(id,email) VALUES(v_actor,'writer-test@example.invalid') ON CONFLICT DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'writer-test@example.invalid','redaktion','Writer test')
    ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Writer test';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','production-writer-v1',private.reimport_canonical_json_sha256(v_1939_config),v_1939_config)
  ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT profile_sha256 INTO v_profile_sha FROM private.reimport_writer_profile
   WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1';
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES(-153201,'Facade fixture','Facade fixture','facade-fixture') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES(-153201,-153201,3,'stamtavle','Facade fixture') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES(-153201,-153201,-153201,'A','Facade fixture',1) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,3,'facade-placement','fixture','fixture','fixture',repeat('d',64),'{}') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(3,'facade-placement','ocr_text',repeat('d',64),'{}') ON CONFLICT(source_id,rendition_key) DO NOTHING;
  SELECT id INTO v_rendition FROM private.source_rendition WHERE source_id=3 AND rendition_key='facade-placement';
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES(v_record,3,'record-fixture','person',v_run) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rendition,'facade-placement',1,1,0,18,'Fixture',repeat('d',64),repeat('e',64),v_run) ON CONFLICT(rendition_id,extraction_run_id,occurrence_key) DO NOTHING;
  SELECT id INTO v_occurrence FROM private.source_record_occurrence WHERE rendition_id=v_rendition AND extraction_run_id=v_run AND occurrence_key='facade-placement';
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES(v_occurrence,v_record,'accepted','{"fixture":"facade"}',1,v_actor,'Facade fixture') ON CONFLICT(occurrence_id,source_record_id,version) DO NOTHING;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occurrence,'header',1,1,0,18,'Fixture','clear','fixture',v_run) RETURNING id INTO v_observation;
  v_placement:=private.propose_source_record_placement(v_record,-153201,v_observation,jsonb_build_object('fixture','facade'),'Facade fixture');
  PERFORM public.red_decide_source_record_placement(v_placement,1,'accepted',jsonb_build_object('fixture','facade'));

  v_source_payload := jsonb_build_object('review_subject_id','fixture','source_record_key','record-evidence-fixture','category','fact','disposition','retain_source_only','evidence_sha256',repeat('c',64),'canonical_target',jsonb_build_object('canonical_person_id',1),'source_span',jsonb_build_object('char_from',0,'char_to',8),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','evidence','legacy_payload',jsonb_build_object('value','evidence'),'rendition_content_sha256',repeat('d',64));
  v_person_payload := jsonb_build_object('source_record_key','record-fixture','source_id',3,'edition','1939','source_span',jsonb_build_object('char_from',10,'char_to',17),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','Fixture','verbatim_sha256',repeat('e',64),'source_persona_id','33333333-3333-5333-8333-333333333333','persona_key','1939:record-fixture','source_record_placement_id',v_placement,'placement_role','principal_member','placement_basis_sha256',repeat('2',64),'placement_review_sha256',repeat('3',64),'placement_decision_sha256',repeat('4',64),'identity_decision_sha256',repeat('f',64),'review_sha256',repeat('1',64),'decision_basis','fixture','name','Fixture','sex',NULL,'narrative',jsonb_build_object('text','Fixture','source_record_key','record-fixture'),'source_mentions','[]'::jsonb,'persona_mention_links','[]'::jsonb,'facts','[]'::jsonb,'relations','[]'::jsonb,'families','[]'::jsonb,'uncertainties','[]'::jsonb,'staged',true,'rendition_content_sha256',repeat('d',64));
  BEGIN
    PERFORM public.red_authorize_1939_v50_reimport(repeat('a',64),repeat('b',64),'wrong-db',3,'{"person_creates":1,"source_evidence":1}'::jsonb,jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
    RAISE EXCEPTION 'REIMPORT_1939_DATABASE_DRIFT_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_DATABASE_DRIFT_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_1939_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  -- The active Phase-A caller still sends its historic database name and the
  -- zero canonical-delta count.  The facade alone must normalize both before
  -- the generic authorization is persisted.
  v_auth := public.red_authorize_1939_v50_reimport(
    repeat('a',64),repeat('b',64),current_database(),3,
    '{"person_creates":1,"source_evidence":1,"canonical_delta":0}'::jsonb,
    jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),
    '22222222-2222-4222-8222-222222222222',clock_timestamp()+interval '5 minutes');
  v_batch := public.red_begin_1939_v50_reimport(v_auth,repeat('a',64),repeat('b',64));
  IF NOT EXISTS (SELECT 1 FROM private.reimport_authorization WHERE id=v_auth AND source_id=3
      AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=v_profile_sha
      AND expected_counts='{"person_creates":1,"source_evidence":1}'::jsonb
      AND database_identity=jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text)
     OR NOT EXISTS (SELECT 1 FROM private.reimport_batch WHERE id=v_batch AND authorization_id=v_auth
      AND source_id=3 AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=v_profile_sha) THEN
    RAISE EXCEPTION 'REIMPORT_1939_FACADE_PROFILE_PARITY_FAILED';
  END IF;
  -- Missing/nonzero/malformed/extra historic counts must keep the historic
  -- invalid-token behavior.  They must never be silently coerced by the
  -- compatibility facade.
  FOR v_error IN SELECT value FROM unnest(ARRAY[
    '{"person_creates":1,"source_evidence":1}'::text,
    '{"person_creates":1,"source_evidence":1,"canonical_delta":1}'::text,
    '{"person_creates":1,"source_evidence":1,"canonical_delta":"0"}'::text,
    '{"person_creates":1,"source_evidence":1,"canonical_delta":0,"extra":0}'::text
  ]) AS values(value) LOOP
    BEGIN
      PERFORM public.red_authorize_1939_v50_reimport(repeat('9',64),repeat('8',64),current_database(),3,
        v_error::jsonb,jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),
        gen_random_uuid(),clock_timestamp()+interval '5 minutes');
      RAISE EXCEPTION 'REIMPORT_1939_HISTORIC_COUNT_DRIFT_ACCEPTED';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM='REIMPORT_1939_HISTORIC_COUNT_DRIFT_ACCEPTED' THEN RAISE; END IF;
      IF SQLERRM<>'REIMPORT_1939_AUTHORIZATION_INVALID' THEN RAISE; END IF;
    END;
  END LOOP;
  -- The generic authority remains closed over the canonical database identity
  -- and its two supported count keys.  Keep the probes independent: either
  -- legacy representation alone is invalid at the generic boundary.
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('7',64),repeat('6',64),current_database(),3,
      'daa-1939-v50-production-write-v1',v_profile_sha,
      '{"person_creates":1,"source_evidence":1}'::jsonb,
      jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),
      gen_random_uuid(),clock_timestamp()+interval '5 minutes');
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_DATABASE_IDENTITY_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_WRITER_LEGACY_DATABASE_IDENTITY_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_WRITER_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('5',64),repeat('4',64),
      jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
      3,'daa-1939-v50-production-write-v1',v_profile_sha,
      '{"person_creates":1,"source_evidence":1,"canonical_delta":0}'::jsonb,
      jsonb_build_object('source-evidence:fixture',v_source_payload,'person-create:record-fixture',v_person_payload),
      gen_random_uuid(),clock_timestamp()+interval '5 minutes');
    RAISE EXCEPTION 'REIMPORT_WRITER_LEGACY_COUNTS_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_WRITER_LEGACY_COUNTS_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_WRITER_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.red_apply_1939_v50_source_evidence(v_batch,'source-evidence:fixture',v_source_payload||'{"verbatim_text":"tampered"}'::jsonb);
    RAISE EXCEPTION 'REIMPORT_1939_TAMPERED_PAYLOAD_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_TAMPERED_PAYLOAD_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_1939_ELEMENT_NOT_AUTHORIZED' THEN RAISE; END IF;
  END;
  PERFORM public.red_apply_1939_v50_source_evidence(v_batch,'source-evidence:fixture',v_source_payload);
  v_person := public.red_apply_1939_v50_person_create(v_batch,'person-create:record-fixture',v_person_payload);
  IF v_person IS NULL OR NOT EXISTS(SELECT 1 FROM public.person WHERE id=v_person AND staged) THEN
    RAISE EXCEPTION 'REIMPORT_1939_PERSON_CREATE_FAILED';
  END IF;
  v_result := public.red_finalize_1939_v50_reimport(v_batch);
  IF v_result->>'status' <> 'finalized' THEN RAISE EXCEPTION 'REIMPORT_1939_FINALIZE_FAILED'; END IF;

  -- The historic canonical-delta endpoint is deliberately unsupported.  Even
  -- when the generic child batch is otherwise valid and open, it must reach a
  -- generic fail-closed path and leave every generic/canonical ledger intact.
  v_completion_payload:=jsonb_build_object(
    'source_batch_id',v_batch,'source_person_create_element_id','person-create:record-fixture',
    'person_id',v_person,'source_id',3,'edition','1939','source_record_key','record-fixture',
    'source_persona_id',v_person_payload->>'source_persona_id','name','Facade fixture',
    'source_span',v_person_payload->'source_span','page_evidence',v_person_payload->'page_evidence',
    'verbatim_text',v_person_payload->>'verbatim_text','verbatim_sha256',v_person_payload->>'verbatim_sha256',
    'source_payload_sha256',private.reimport_canonical_json_sha256(v_person_payload),
    'expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),
    'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1)
  );
  v_name_authorization:=(public.red_authorize_reimport_name_completion(
    repeat('1',64),v_batch,repeat('b',64),repeat('a',64),3,'daa-1939-v50-production-write-v1',v_profile_sha,
    '{"name_completions":1,"operations":1}'::jsonb,
    jsonb_build_object('name-completion:record-fixture',v_completion_payload)
  )->>'authorization_id')::uuid;
  v_name_batch:=public.red_begin_reimport_name_completion(v_name_authorization,repeat('1',64),v_batch);
  SELECT count(*) INTO v_fact_count FROM public.fact;
  SELECT count(*) INTO v_assertion_count FROM public.assertion;
  SELECT count(*) INTO v_citation_count FROM public.citation;
  SELECT count(*) INTO v_conclusion_count FROM public.conclusion;
  SELECT count(*) INTO v_name_result_count FROM private.reimport_name_completion_result WHERE batch_id=v_name_batch;
  SELECT count(*) INTO v_name_event_count FROM private.reimport_event WHERE batch_id=v_name_batch;
  BEGIN
    PERFORM public.red_apply_1939_v50_canonical_delta(
      v_name_batch,'name-completion:record-fixture',v_completion_payload
    );
    RAISE EXCEPTION 'REIMPORT_1939_CANONICAL_DELTA_VALID_NAME_BATCH_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_CANONICAL_DELTA_VALID_NAME_BATCH_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_1939_CANONICAL_DELTA_UNSUPPORTED' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.fact)<>v_fact_count
     OR (SELECT count(*) FROM public.assertion)<>v_assertion_count
     OR (SELECT count(*) FROM public.citation)<>v_citation_count
     OR (SELECT count(*) FROM public.conclusion)<>v_conclusion_count
     OR (SELECT count(*) FROM private.reimport_name_completion_result WHERE batch_id=v_name_batch)<>v_name_result_count
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=v_name_batch)<>v_name_event_count
     OR (SELECT status FROM private.reimport_batch WHERE id=v_name_batch)<>'open' THEN
    RAISE EXCEPTION 'REIMPORT_1939_CANONICAL_DELTA_MUTATED_VALID_NAME_BATCH';
  END IF;

  v_reversal_auth := public.red_authorize_1939_v50_reversal(v_batch,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  BEGIN
    PERFORM public.red_reverse_1939_v50_reimport(gen_random_uuid(),v_reversal_auth);
    RAISE EXCEPTION 'REIMPORT_1939_CROSS_BATCH_REVERSAL_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='REIMPORT_1939_CROSS_BATCH_REVERSAL_ACCEPTED' THEN RAISE; END IF;
    IF SQLERRM<>'REIMPORT_1939_REVERSAL_INVALID' THEN RAISE; END IF;
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

-- Cutover followed by db-rls.sql has already exercised the matrix above.
-- Re-running the one #152 ACL authority afterwards is the opposite ordering;
-- it must preserve the exact v2 compatibility facade split, not revoke it.
DO $v2_facade_acl_authority_order$
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
  v_before jsonb; v_after jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object('signature',s.signature,
           'anon',has_function_privilege('anon',s.signature,'EXECUTE'),
           'authenticated',has_function_privilege('authenticated',s.signature,'EXECUTE'),
           'service_role',has_function_privilege('service_role',s.signature,'EXECUTE')) ORDER BY s.signature)
    INTO v_before FROM unnest(v_legacy) AS s(signature);
  PERFORM private.apply_narrative_record_contract_acl(2);
  SELECT jsonb_agg(jsonb_build_object('signature',s.signature,
           'anon',has_function_privilege('anon',s.signature,'EXECUTE'),
           'authenticated',has_function_privilege('authenticated',s.signature,'EXECUTE'),
           'service_role',has_function_privilege('service_role',s.signature,'EXECUTE')) ORDER BY s.signature)
    INTO v_after FROM unnest(v_legacy) AS s(signature);
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'REIMPORT_1939_V2_ACL_AUTHORITY_ORDER_DRIFT: before=% after=%',v_before,v_after;
  END IF;
END $v2_facade_acl_authority_order$;

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
