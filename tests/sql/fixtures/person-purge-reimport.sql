-- Task 4c: én rigtig generel person_create -> name_completion-kæde til rollback-tests.
-- En-personsudgave af task3_stage_profile/task3_complete_profile i test-reimport-name-completion.sql.
-- Aktør = purge-fixturens redaktør; kald med nye, positive kilde-/slægts-id'er. Ingen bootstrap/COMMIT her.
CREATE FUNCTION pg_temp.purge_stage_profile(
  p_source_id bigint,p_profile_id text,p_record_key text,
  p_label text,p_fixture_id bigint,p_manifest_sha256 text DEFAULT repeat('9',64),
  p_preview_sha256 text DEFAULT repeat('8',64)
) RETURNS jsonb LANGUAGE plpgsql AS $purge_stage_profile$
DECLARE
  v_run uuid:=gen_random_uuid(); v_record uuid:=gen_random_uuid(); v_rendition uuid;
  v_occurrence uuid; v_observation uuid; v_placement uuid; v_persona uuid:=gen_random_uuid();
  v_source_payload jsonb; v_person_payload jsonb; v_authorization uuid; v_batch uuid; v_person bigint;
  v_profile_config jsonb; v_profile_hash text;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(p_source_id,p_label,'fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  v_profile_config:=jsonb_build_object('run_key_prefix','task3-'||p_source_id||':','schema_version','fixture-v1',
    'extractor_version','fixture-v1','rendition_key','task3-'||p_source_id,
    'rendition_kind','ocr_text','rendition_metadata','{}'::jsonb,
    'observation_extraction_method','fixture','citation_label_template',p_profile_id||' side {page_from}');
  v_profile_hash:=private.reimport_canonical_json_sha256(v_profile_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(p_source_id,p_profile_id,'fixture-v1',v_profile_hash,v_profile_config)
  ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING;
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug)
  VALUES(p_fixture_id,p_label,p_label,'task-3-profile-'||abs(p_fixture_id)) ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label)
  VALUES(p_fixture_id,p_fixture_id,p_source_id,'stamtavle',p_label) ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order)
  VALUES(p_fixture_id,p_fixture_id,p_fixture_id,'A',p_label,1) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,p_source_id,'task-3-placement-'||p_source_id||'-'||p_record_key,'fixture','fixture','fixture',repeat('d',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(p_source_id,'task-3-placement-'||p_source_id||'-'||p_record_key,'ocr_text',repeat('d',64),'{}');
  SELECT id INTO v_rendition FROM private.source_rendition
   WHERE source_id=p_source_id AND rendition_key='task-3-placement-'||p_source_id||'-'||p_record_key;
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES(v_record,p_source_id,p_record_key,'person',v_run);
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rendition,'task-3-placement-'||p_source_id,1,1,0,18,p_label,repeat('d',64),repeat('e',64),v_run)
  RETURNING id INTO v_occurrence;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES(v_occurrence,v_record,'accepted',jsonb_build_object('fixture','task-3'),1,'a2a00000-0000-4000-8000-00000000a001','Task 3 fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occurrence,'header',1,1,0,18,p_label,'clear','fixture',v_run) RETURNING id INTO v_observation;
  v_placement:=private.propose_source_record_placement(v_record,p_fixture_id,v_observation,jsonb_build_object('fixture','task-3'),'Task 3 fixture');
  PERFORM public.red_decide_source_record_placement(v_placement,1,'accepted',jsonb_build_object('fixture','task-3'));
  v_source_payload:=jsonb_build_object(
    'review_subject_id','task-3-source-'||p_source_id,'source_record_key',p_record_key,
    'category','person','disposition','retain_source_only','evidence_sha256',repeat('c',64),
    'canonical_target',jsonb_build_object('canonical_person_id',1),
    'source_span',jsonb_build_object('char_from',0,'char_to',18),
    'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text',p_label,'legacy_payload',jsonb_build_object('value',p_label),
    'rendition_content_sha256',repeat('d',64));
  v_person_payload:=jsonb_build_object(
    'source_record_key',p_record_key,'source_id',p_source_id,'edition','fixture',
    'source_span',v_source_payload->'source_span','page_evidence',v_source_payload->'page_evidence',
    'verbatim_text',p_label,'verbatim_sha256',encode(extensions.digest(convert_to(p_label,'UTF8'),'sha256'),'hex'),
    'source_persona_id',v_persona,'persona_key','task-3:'||p_source_id||':'||p_record_key,
    'source_record_placement_id',v_placement,'placement_role','principal_member',
    'placement_basis_sha256',repeat('2',64),'placement_review_sha256',repeat('3',64),'placement_decision_sha256',repeat('4',64),
    'identity_decision_sha256',repeat('f',64),'review_sha256',repeat('1',64),'decision_basis','Task 3 fixture',
    'name',p_label,'sex',NULL,'narrative',jsonb_build_object('text',p_label||' narrative','source_record_key',p_record_key),
    'source_mentions','[]'::jsonb,'persona_mention_links','[]'::jsonb,'facts','[]'::jsonb,'relations','[]'::jsonb,
    'families','[]'::jsonb,'uncertainties','[]'::jsonb,'staged',true,'rendition_content_sha256',repeat('d',64));
  PERFORM set_config('app.change_set_id','',true);
  v_authorization:=public.red_authorize_reimport(
    p_manifest_sha256,p_preview_sha256,jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,p_source_id,p_profile_id,v_profile_hash,
    '{"person_creates":1,"source_evidence":1}'::jsonb,
    jsonb_build_object('source-evidence:'||p_record_key,v_source_payload,'person-create:'||p_record_key,v_person_payload),
    gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_batch:=public.red_begin_reimport(v_authorization,p_manifest_sha256,p_preview_sha256);
  PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:'||p_record_key,v_source_payload);
  v_person:=public.red_apply_reimport_person_create(v_batch,'person-create:'||p_record_key,v_person_payload);
  IF public.red_finalize_reimport(v_batch)->>'status'<>'finalized' THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_TWO_PROFILE_SOURCE_NOT_FINALIZED';
  END IF;
  RETURN jsonb_build_object('source_authorization_id',v_authorization,'source_batch_id',v_batch,'source_id',p_source_id,'profile_id',p_profile_id,'profile_sha256',v_profile_hash,
    'person_id',v_person,'source_record_id',v_record,'source_persona_id',v_persona,
    'source_element_id','person-create:'||p_record_key,'person_payload',v_person_payload,
    'manifest_sha256',p_manifest_sha256,'preview_sha256',p_preview_sha256);
END $purge_stage_profile$;

CREATE FUNCTION pg_temp.purge_complete_profile(p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $purge_complete_profile$
DECLARE
  v_payload jsonb; v_payloads jsonb; v_envelope jsonb; v_child_auth uuid; v_child_batch uuid; v_result jsonb;
BEGIN
  v_payload:=jsonb_build_object(
    'source_batch_id',p_state->>'source_batch_id','source_person_create_element_id',p_state->>'source_element_id',
    'person_id',p_state->>'person_id','source_id',(p_state->'person_payload'->>'source_id')::bigint,
    'edition','fixture','source_record_key',p_state->'person_payload'->>'source_record_key',
    'source_persona_id',p_state->>'source_persona_id','name',p_state->'person_payload'->>'name',
    'source_span',p_state->'person_payload'->'source_span','page_evidence',p_state->'person_payload'->'page_evidence',
    'verbatim_text',p_state->'person_payload'->>'verbatim_text','verbatim_sha256',p_state->'person_payload'->>'verbatim_sha256',
    'source_payload_sha256',private.reimport_canonical_json_sha256(p_state->'person_payload'),
    'expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),
    'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1));
  v_payloads:=jsonb_build_object('name-completion:'||(p_state->'person_payload'->>'source_record_key'),v_payload);
  v_envelope:=public.red_authorize_reimport_name_completion(
    repeat('7',64),(p_state->>'source_batch_id')::uuid,p_state->>'preview_sha256',p_state->>'manifest_sha256',(p_state->>'source_id')::bigint,p_state->>'profile_id',p_state->>'profile_sha256',
    '{"name_completions":1,"operations":1}'::jsonb,v_payloads);
  v_child_auth:=(v_envelope->>'authorization_id')::uuid;
  PERFORM public.red_preflight_reimport_name_completion(v_child_auth,(p_state->>'source_batch_id')::uuid,repeat('7',64),v_payloads);
  v_child_batch:=public.red_begin_reimport_name_completion(v_child_auth,repeat('7',64),(p_state->>'source_batch_id')::uuid);
  PERFORM public.red_apply_reimport_name_completion(v_child_batch,'name-completion:'||(p_state->'person_payload'->>'source_record_key'),v_payload);
  v_result:=public.red_finalize_reimport_name_completion(v_child_batch);
  IF v_result->>'status'<>'finalized' THEN RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_TWO_PROFILE_CHILD_NOT_FINALIZED'; END IF;
  RETURN p_state||jsonb_build_object('child_authorization_id',v_child_auth,'child_batch_id',v_child_batch,
    'completion_payload',v_payload,'fact_id',v_result#>>ARRAY['result_map','name-completion:'||(p_state->'person_payload'->>'source_record_key'),'fact_id'],
    'assertion_id',v_result#>>ARRAY['result_map','name-completion:'||(p_state->'person_payload'->>'source_record_key'),'assertion_id'],
    'citation_id',v_result#>>ARRAY['result_map','name-completion:'||(p_state->'person_payload'->>'source_record_key'),'citation_id'],
    'conclusion_id',v_result#>>ARRAY['result_map','name-completion:'||(p_state->'person_payload'->>'source_record_key'),'conclusion_id']);
END $purge_complete_profile$;

