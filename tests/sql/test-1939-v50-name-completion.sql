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
  v_1939_config jsonb := '{"run_key_prefix":"reimport-1939-v50:","schema_version":"1939-v50-production-write-manifest-v1","extractor_version":"production-writer-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed_1939_v50","citation_label_template":"DAA 1939 side {page_from}"}'::jsonb;
  v_profile_sha text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO auth.users(id,email) VALUES(v_actor,'writer-ci@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'writer-ci@example.invalid','redaktion','Writer CI') ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Writer CI';
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','production-writer-v1',private.reimport_canonical_json_sha256(v_1939_config),v_1939_config)
  ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT profile_sha256 INTO v_profile_sha FROM private.reimport_writer_profile
   WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1';
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
  VALUES(v_source_auth,'reimport',repeat('c',64),repeat('d',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,
    'daa-1939-v50-production-write-v1',v_profile_sha,'{"person_creates":1,"source_evidence":0}'::jsonb,'{}',v_actor,
    '560c39f8-5c87-4c0d-a768-025d97fa2901',clock_timestamp()+interval '1 hour','consumed',clock_timestamp());
  INSERT INTO private.reimport_1939_write_batch(id,authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,status,expected_counts,observed_counts,finalized_at)
  VALUES(v_source_batch,v_source_auth,repeat('c',64),repeat('d',64),3,'daa-1939-v50-production-write-v1',v_profile_sha,v_actor,'finalized',
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

-- A successful legacy authorization is intentionally a three-field object.
-- The adapter, not SQL, supplies the pinned profile/source for the generic
-- gateway; adding it here would silently widen the historic caller contract.
DO $return_shape$
DECLARE
  v_actor uuid := '15300000-0000-4000-8000-000000000601';
  v_source_auth uuid; v_source_batch uuid; v_person bigint;
  v_run uuid := '15300000-0000-4000-8000-000000000602';
  v_record uuid := '15300000-0000-4000-8000-000000000603';
  v_persona uuid := '15300000-0000-4000-8000-000000000604';
  v_rendition uuid; v_occurrence uuid; v_observation uuid; v_placement uuid;
  v_profile_sha text; v_source_payload jsonb; v_person_payload jsonb; v_completion_payload jsonb;
  v_authorized jsonb; v_envelope jsonb;
  v_1939_config jsonb := '{"run_key_prefix":"reimport-1939-v50:","schema_version":"1939-v50-production-write-manifest-v1","extractor_version":"production-writer-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed_1939_v50","citation_label_template":"DAA 1939 side {page_from}"}'::jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO auth.users(id,email) VALUES(v_actor,'name-shape-ci@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn) VALUES(v_actor,'name-shape-ci@example.invalid','redaktion','Name shape CI') ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Name shape CI';
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','production-writer-v1',private.reimport_canonical_json_sha256(v_1939_config),v_1939_config)
  ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT profile_sha256 INTO v_profile_sha FROM private.reimport_writer_profile WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1';
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES(-153601,'Name shape fixture','Name shape fixture','name-shape-fixture') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES(-153601,-153601,3,'stamtavle','Name shape fixture') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES(-153601,-153601,-153601,'A','Name shape fixture',1) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES(v_run,3,'name-shape-source','fixture','fixture','fixture',repeat('6',64),'{}') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES(3,'name-shape-source','ocr_text',repeat('7',64),'{}') RETURNING id INTO v_rendition;
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES(v_record,3,'name-shape-record','person',v_run);
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES(v_rendition,'name-shape-source',1,1,0,16,'Name shape source',repeat('8',64),repeat('9',64),v_run) RETURNING id INTO v_occurrence;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES(v_occurrence,v_record,'accepted','{"fixture":"name-shape"}',1,v_actor,'Name shape CI');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES(v_occurrence,'header',1,1,0,16,'Name shape source','clear','fixture',v_run) RETURNING id INTO v_observation;
  v_placement:=private.propose_source_record_placement(v_record,-153601,v_observation,jsonb_build_object('fixture','name-shape'),'Name shape CI');
  PERFORM public.red_decide_source_record_placement(v_placement,1,'accepted',jsonb_build_object('fixture','name-shape'));
  v_source_payload:=jsonb_build_object('review_subject_id','name-shape-evidence','source_record_key','name-shape-record','category','person','disposition','retain_source_only','evidence_sha256',repeat('c',64),'canonical_target',jsonb_build_object('canonical_person_id',1),'source_span',jsonb_build_object('char_from',0,'char_to',16),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','Name shape source','legacy_payload',jsonb_build_object('value','Name shape source'),'rendition_content_sha256',repeat('d',64));
  v_person_payload:=jsonb_build_object('source_record_key','name-shape-record','source_id',3,'edition','1939','source_span',jsonb_build_object('char_from',0,'char_to',16),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','Name shape source','verbatim_sha256',encode(extensions.digest(convert_to('Name shape source','UTF8'),'sha256'),'hex'),'source_persona_id',v_persona,'persona_key','1939:name-shape-record','source_record_placement_id',v_placement,'placement_role','principal_member','placement_basis_sha256',repeat('2',64),'placement_review_sha256',repeat('3',64),'placement_decision_sha256',repeat('4',64),'identity_decision_sha256',repeat('f',64),'review_sha256',repeat('1',64),'decision_basis','name-shape fixture','name','Name shape','sex',NULL,'narrative',jsonb_build_object('text','Name shape source','source_record_key','name-shape-record'),'source_mentions','[]'::jsonb,'persona_mention_links','[]'::jsonb,'facts','[]'::jsonb,'relations','[]'::jsonb,'families','[]'::jsonb,'uncertainties','[]'::jsonb,'staged',true,'rendition_content_sha256',repeat('d',64));
  v_authorized:=jsonb_build_object('source-evidence:name-shape',v_source_payload,'person-create:name-shape-record',v_person_payload);
  v_source_auth:=public.red_authorize_reimport(repeat('6',64),repeat('5',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,'daa-1939-v50-production-write-v1',v_profile_sha,'{"person_creates":1,"source_evidence":1}'::jsonb,v_authorized,'15300000-0000-4000-8000-000000000605',clock_timestamp()+interval '5 minutes');
  v_source_batch:=public.red_begin_reimport(v_source_auth,repeat('6',64),repeat('5',64));
  PERFORM public.red_apply_reimport_source_evidence(v_source_batch,'source-evidence:name-shape',v_source_payload);
  v_person:=public.red_apply_reimport_person_create(v_source_batch,'person-create:name-shape-record',v_person_payload);
  IF public.red_finalize_reimport(v_source_batch)->>'status'<>'finalized' THEN RAISE EXCEPTION 'NAME_COMPLETION_1939_RETURN_SHAPE_SOURCE_NOT_FINALIZED'; END IF;
  v_completion_payload:=jsonb_build_object('source_batch_id',v_source_batch,'source_person_create_element_id','person-create:name-shape-record','person_id',v_person,'source_id',3,'edition','1939','source_record_key','name-shape-record','source_persona_id',v_persona,'name','Name shape','source_span',v_person_payload->'source_span','page_evidence',v_person_payload->'page_evidence','verbatim_text',v_person_payload->>'verbatim_text','verbatim_sha256',v_person_payload->>'verbatim_sha256','source_payload_sha256',private.reimport_canonical_json_sha256(v_person_payload),'expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1));
  v_envelope:=public.red_authorize_1939_v50_name_completion(repeat('4',64),v_source_batch,repeat('5',64),repeat('6',64),'{"name_completions":1,"operations":1}'::jsonb,jsonb_build_object('name-completion:name-shape-record',v_completion_payload));
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_envelope) key) IS DISTINCT FROM ARRAY['authorization_id','database_name','system_identifier']
     OR v_envelope ? 'source' OR nullif(v_envelope->>'authorization_id','') IS NULL
     OR v_envelope->>'database_name' IS DISTINCT FROM current_database()
     OR v_envelope->>'system_identifier' IS DISTINCT FROM (pg_control_system()).system_identifier::text THEN
    RAISE EXCEPTION 'NAME_COMPLETION_1939_AUTHORIZATION_RETURN_SHAPE_INVALID';
  END IF;
END $return_shape$;
