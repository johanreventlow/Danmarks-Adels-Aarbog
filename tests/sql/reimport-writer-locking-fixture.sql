-- Loaded by the DBI locking integration test in its setup connection only.
-- It intentionally stages the minimal already-finalized source receipt and
-- open name-completion child batch needed to exercise the public writer.
CREATE OR REPLACE FUNCTION pg_temp.task9_seed_name_completion(
  p_source_id bigint, p_profile_id text, p_tag text, p_actor uuid
) RETURNS jsonb LANGUAGE plpgsql AS $task9_seed_name_completion$
DECLARE
  v_config jsonb; v_profile_sha256 text; v_run uuid:=gen_random_uuid();
  v_record uuid:=gen_random_uuid(); v_persona uuid:=gen_random_uuid(); v_person bigint;
  v_source_authorization uuid:=gen_random_uuid(); v_source_batch uuid:=gen_random_uuid();
  v_child_authorization uuid:=gen_random_uuid(); v_child_batch uuid:=gen_random_uuid();
  v_source_payload jsonb; v_payload jsonb; v_element_id text; v_decided_at timestamptz:=clock_timestamp();
BEGIN
  v_config:=jsonb_build_object(
    'run_key_prefix','task9:'||p_tag||':','schema_version','task9','extractor_version','task9',
    'rendition_key','task9-'||p_tag,'rendition_kind','ocr_text','rendition_metadata','{}'::jsonb,
    'observation_extraction_method','task9','citation_label_template',p_profile_id||' side {page_from}'
  );
  v_profile_sha256:=private.reimport_canonical_json_sha256(v_config);
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(p_source_id,'Task 9 locking '||p_tag,'synthetic','DAA-udgave');
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(p_source_id,p_profile_id,'task9',v_profile_sha256,v_config);
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,p_source_id,'task9-'||p_tag,'task9','task9','task9',repeat('a',64),'{}');
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
  VALUES(v_record,p_source_id,'task9-record-'||p_tag,'person',v_run);
  INSERT INTO public.person(staged) VALUES(true) RETURNING id INTO v_person;
  INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  VALUES(v_persona,p_source_id,'task9-persona-'||p_tag,v_run);
  INSERT INTO private.source_persona_identity(
    source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
  ) VALUES(v_persona,v_person,'accepted',1,jsonb_build_object('fixture','task9'),p_actor,'Task 9 locking',v_decided_at);
  INSERT INTO private.source_persona_identity_event(
    source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at
  ) VALUES(v_persona,v_person,'accepted',1,jsonb_build_object('fixture','task9'),p_actor,'Task 9 locking',v_decided_at);
  v_source_payload:=jsonb_build_object('fixture','task9','tag',p_tag);
  INSERT INTO private.reimport_authorization(
    id,operation,manifest_sha256,preview_sha256,database_identity,source_id,profile_id,profile_sha256,
    expected_counts,authorized_elements,principal_id,nonce,expires_at,status,consumed_at
  ) VALUES(
    v_source_authorization,'reimport',repeat('a',64),repeat('b',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,p_source_id,p_profile_id,v_profile_sha256,
    '{}'::jsonb,'{}'::jsonb,p_actor,gen_random_uuid(),clock_timestamp()+interval '5 minutes','consumed',clock_timestamp()
  );
  INSERT INTO private.reimport_batch(
    id,authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,status,expected_counts,observed_counts,finalized_at
  ) VALUES(
    v_source_batch,v_source_authorization,repeat('a',64),repeat('b',64),p_source_id,p_profile_id,v_profile_sha256,p_actor,
    'finalized','{}'::jsonb,'{}'::jsonb,clock_timestamp()
  );
  INSERT INTO private.reimport_event(batch_id,element_id,operation,source_record_key,canonical_person_id,payload,after_sha256)
  VALUES(v_source_batch,'person-create:task9-'||p_tag,'person_create','task9-record-'||p_tag,v_person,
    jsonb_build_object('authorized_payload_sha256',private.reimport_canonical_json_sha256(v_source_payload),'source_persona_id',v_persona),repeat('a',64));
  v_element_id:='name-completion:task9-record-'||p_tag;
  v_payload:=jsonb_build_object(
    'source_batch_id',v_source_batch,'source_person_create_element_id','person-create:task9-'||p_tag,
    'person_id',v_person,'source_id',p_source_id,'edition','synthetic','source_record_key','task9-record-'||p_tag,
    'source_persona_id',v_persona,'name','Task 9 '||p_tag,
    'source_span',jsonb_build_object('char_from',0,'char_to',1),'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text',p_tag,'verbatim_sha256',repeat('c',64),
    'source_payload_sha256',private.reimport_canonical_json_sha256(v_source_payload),
    'expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),
    'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1)
  );
  INSERT INTO private.reimport_authorization(
    id,operation,manifest_sha256,preview_sha256,database_identity,source_id,profile_id,profile_sha256,
    expected_counts,authorized_elements,principal_id,nonce,expires_at
  ) VALUES(
    v_child_authorization,'name_completion',repeat('c',64),repeat('d',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,p_source_id,p_profile_id,v_profile_sha256,
    '{"name_completions":1,"operations":1}'::jsonb,
    jsonb_build_object('payloads',jsonb_build_object(v_element_id,v_payload),'source_batch_id',v_source_batch),
    p_actor,gen_random_uuid(),clock_timestamp()+interval '5 minutes'
  );
  INSERT INTO private.reimport_batch(
    id,authorization_id,manifest_sha256,preview_sha256,source_id,profile_id,profile_sha256,principal_id,status,expected_counts
  ) VALUES(
    v_child_batch,v_child_authorization,repeat('c',64),repeat('d',64),p_source_id,p_profile_id,v_profile_sha256,p_actor,
    'open','{"name_completions":1,"operations":1}'::jsonb
  );
  RETURN jsonb_build_object('source_id',p_source_id,'profile_id',p_profile_id,'profile_sha256',v_profile_sha256,
    'source_batch_id',v_source_batch,'child_authorization_id',v_child_authorization,'child_batch_id',v_child_batch,'person_id',v_person,
    'element_id',v_element_id,'payload',v_payload);
END
$task9_seed_name_completion$;
