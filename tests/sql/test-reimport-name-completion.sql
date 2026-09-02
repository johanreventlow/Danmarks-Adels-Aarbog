\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE v_signature text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_lock_reimport_name_completion(text,bigint,text)',
    'public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)',
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
  v_seed_run uuid := '15300000-0000-4000-8000-000000000111'; v_seed_record uuid := '15300000-0000-4000-8000-000000000112';
  v_seed_rendition uuid; v_seed_occurrence uuid; v_seed_observation uuid; v_record_placement uuid;
  v_authorization_envelope jsonb; v_preflight jsonb; v_result jsonb;
  v_source_payload jsonb; v_person_payload jsonb; v_completion_payload jsonb;
  v_authorized_source jsonb; v_authorized_completion jsonb;
  v_error text; v_event_before text; v_result_before text; v_cutover_authorization uuid; v_reversal_authorization uuid; v_activation jsonb; v_reversal jsonb;
  v_1939_config jsonb := '{"run_key_prefix":"reimport-1939-v50:","schema_version":"1939-v50-production-write-manifest-v1","extractor_version":"production-writer-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed_1939_v50","citation_label_template":"DAA 1939 side {page_from}"}'::jsonb;
  v_profile_sha text;
BEGIN
  IF public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_V2_BOOTSTRAP_FAILED';
  END IF;
  INSERT INTO auth.users(id,email) VALUES(v_actor,'reimport-name-completion-153@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_actor,'reimport-name-completion-153@example.invalid','redaktion','Task 1 generic name-completion fixture')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Task 1 generic name-completion fixture';
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'DAA','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','production-writer-v1',private.reimport_canonical_json_sha256(v_1939_config),v_1939_config)
  ON CONFLICT (source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT profile_sha256 INTO v_profile_sha FROM private.reimport_writer_profile
   WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES(-153101,'Task 3 fixture slægt','Task 3 fixture slægt','task-3-fixture') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES(-153101,-153101,3,'stamtavle','Task 3 fixture scheme') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES(-153101,-153101,-153101,'A','Task 3 fixture entry',1) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES(v_seed_run,3,'task-3-placement-seed','fixture','fixture','fixture',repeat('d',64),'{}') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES(3,'task-3-placement-seed','ocr_text',repeat('d',64),'{}') ON CONFLICT(source_id,rendition_key) DO NOTHING;
  SELECT id INTO v_seed_rendition FROM private.source_rendition WHERE source_id=3 AND rendition_key='task-3-placement-seed';
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES(v_seed_record,3,'task-1-name-completion-record','person',v_seed_run) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES(v_seed_rendition,'task-3-placement-seed',1,1,0,18,'Task 1 source text',repeat('d',64),repeat('e',64),v_seed_run) ON CONFLICT(rendition_id,extraction_run_id,occurrence_key) DO NOTHING;
  SELECT id INTO v_seed_occurrence FROM private.source_record_occurrence WHERE rendition_id=v_seed_rendition AND extraction_run_id=v_seed_run AND occurrence_key='task-3-placement-seed';
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES(v_seed_occurrence,v_seed_record,'accepted','{"fixture":"task-3"}',1,v_actor,'Task 3 fixture') ON CONFLICT(occurrence_id,source_record_id,version) DO NOTHING;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id) VALUES(v_seed_occurrence,'header',1,1,0,18,'Task 1 source text','clear','fixture',v_seed_run) RETURNING id INTO v_seed_observation;
  v_record_placement:=private.propose_source_record_placement(v_seed_record,-153101,v_seed_observation,jsonb_build_object('fixture','task-3'),'Task 3 fixture');
  PERFORM public.red_decide_source_record_placement(v_record_placement,1,'accepted',jsonb_build_object('fixture','task-3-accepted'));

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
    'source_record_placement_id',v_record_placement,'placement_role','principal_member',
    'placement_basis_sha256',repeat('2',64),'placement_review_sha256',repeat('3',64),'placement_decision_sha256',repeat('4',64),
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
    repeat('a',64),repeat('b',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,
    'daa-1939-v50-production-write-v1',v_profile_sha,
    '{"person_creates":1,"source_evidence":1}'::jsonb,
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
    repeat('1',64),v_source_batch,repeat('b',64),repeat('a',64),3,'daa-1939-v50-production-write-v1',v_profile_sha,
    '{"name_completions":1,"operations":1}'::jsonb,v_authorized_completion
  );
  v_child_auth:=(v_authorization_envelope->>'authorization_id')::uuid;
  v_preflight:=public.red_preflight_reimport_name_completion(v_child_auth,v_source_batch,repeat('1',64),v_authorized_completion);
  IF v_preflight->'authorization' IS DISTINCT FROM v_authorization_envelope
     OR v_preflight->'preflight'->>'valid'<>'true'
     OR v_preflight->'preflight'->>'database_name' IS DISTINCT FROM current_database()
     OR v_preflight->'preflight'->>'system_identifier' IS DISTINCT FROM (pg_control_system()).system_identifier::text
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

  -- The production lifecycle invokes activation in its next transaction. This
  -- single-transaction regression must clear the audit set opened by direct
  -- canonical fact writes before entering the #152 narrative kernel.
  PERFORM set_config('app.change_set_id','',true);
  v_cutover_authorization:=public.red_authorize_reimport_cutover(v_source_batch,'15300000-0000-4000-8000-000000000104',clock_timestamp()+interval '5 minutes');
  v_activation:=public.red_activate_reimport_batch(v_source_batch,v_cutover_authorization);
  IF v_activation->>'status'<>'activated' OR NOT EXISTS (
    SELECT 1 FROM private.reimport_event activation_event
     WHERE activation_event.batch_id=v_source_batch AND activation_event.operation='activation'
       AND activation_event.payload->'post_activation_receipts'->v_person::text->>'state_sha256' ~ '^[0-9a-f]{64}$'
       AND activation_event.payload->'post_activation_receipts'->v_person::text->>'source_person_create_event_id'=(SELECT payload->>'event_id' FROM private.reimport_event WHERE batch_id=v_source_batch AND operation='person_create')
       AND activation_event.payload->'post_activation_receipts'->v_person::text->>'event_id' IS NOT NULL
  ) OR NOT EXISTS(SELECT 1 FROM public.person WHERE id=v_person AND NOT staged) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_ACTIVATION_RECEIPT_INVALID';
  END IF;
  v_reversal_authorization:=public.red_authorize_reimport_reversal(v_source_batch,'15300000-0000-4000-8000-000000000105',clock_timestamp()+interval '5 minutes');
  v_reversal:=public.red_reverse_reimport(v_source_batch,v_reversal_authorization);
  IF v_reversal->>'status'<>'reversed'
     OR (SELECT status FROM private.reimport_batch WHERE id=v_child_batch)<>'reversed'
     OR EXISTS(SELECT 1 FROM public.person WHERE id=v_person AND NOT staged)
     OR EXISTS(SELECT 1 FROM public.fact WHERE subjekt_type='person' AND subjekt_id=v_person AND faktatype='navn')
     OR NOT EXISTS (
       SELECT 1 FROM private.narrative_record_publication binding
        JOIN public.narrative narrative ON narrative.id=binding.narrative_id
       WHERE narrative.subjekt_type='person' AND narrative.subjekt_id=v_person
         AND binding.source_record_id=v_record AND binding.status='withdrawn'
     ) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_REVERSAL_INVALID';
  END IF;
END $generic_lifecycle$;

-- The public lock is intentionally scoped to its fixed `(manifest, source,
-- profile)` signature.  It must reject absent source/profile combinations
-- without creating authorization or batch state, and hold the writer key for
-- the accepted source/profile combination.
DO $public_lock_contract$
DECLARE
  v_actor uuid := '15300000-0000-4000-8000-000000000101';
  v_authorizations_before bigint; v_batches_before bigint; v_error text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT count(*) INTO v_authorizations_before FROM private.reimport_authorization;
  SELECT count(*) INTO v_batches_before FROM private.reimport_batch;
  BEGIN
    PERFORM public.red_lock_reimport_name_completion(repeat('6',64),999999,'daa-1939-v50-production-write-v1');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_NAME_COMPLETION_INVALID' THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_LOCK_MISSING_SOURCE_ACCEPTED: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    PERFORM public.red_lock_reimport_name_completion(repeat('6',64),3,'task-9-missing-profile');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_NAME_COMPLETION_INVALID'
     OR (SELECT count(*) FROM private.reimport_authorization)<>v_authorizations_before
     OR (SELECT count(*) FROM private.reimport_batch)<>v_batches_before THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_LOCK_PROFILE_OR_MUTATION_INVALID: %',v_error;
  END IF;
  PERFORM public.red_lock_reimport_name_completion(repeat('6',64),3,'daa-1939-v50-production-write-v1');
  IF (SELECT count(*) FROM private.reimport_authorization)<>v_authorizations_before
     OR (SELECT count(*) FROM private.reimport_batch)<>v_batches_before THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_LOCK_CORRECT_PATH_MUTATED';
  END IF;
END $public_lock_contract$;

CREATE FUNCTION pg_temp.task3_stage_profile(
  p_source_id bigint,p_profile_id text,p_profile_sha256 text,p_record_key text,
  p_label text,p_fixture_id bigint,p_manifest_sha256 text DEFAULT repeat('9',64),
  p_preview_sha256 text DEFAULT repeat('8',64)
) RETURNS jsonb LANGUAGE plpgsql AS $task3_stage_profile$
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
  VALUES(v_occurrence,v_record,'accepted',jsonb_build_object('fixture','task-3'),1,'15300000-0000-4000-8000-000000000101','Task 3 fixture');
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
END $task3_stage_profile$;

CREATE FUNCTION pg_temp.task3_complete_profile(p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $task3_complete_profile$
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
    'citation_id',v_result#>>ARRAY['result_map','name-completion:'||(p_state->'person_payload'->>'source_record_key'),'citation_id']);
END $task3_complete_profile$;

DO $two_profile_scope$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000101'; a jsonb; b jsonb;
  v_error text; v_cutover_a uuid; v_cutover_b uuid; v_activation_a jsonb; v_activation_b jsonb;
  v_reversal_a uuid; v_reversal_b uuid; v_reverse_a jsonb; v_reverse_b jsonb;
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_actor,'reimport-name-completion-153@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_actor,'reimport-name-completion-153@example.invalid','redaktion','Task 3 generic fixture')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Task 3 generic fixture';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('app.change_set_id','',true);
  a:=pg_temp.task3_stage_profile(4,'task-3-profile-four',repeat('c',64),'task-3-profile-four-record','Task 3 profile four',-153104);
  b:=pg_temp.task3_stage_profile(5,'task-3-profile-five',repeat('d',64),'task-3-profile-five-record','Task 3 profile five',-153105);
  a:=pg_temp.task3_complete_profile(a);
  -- A's child is valid and finalized.  B has no child yet, so its activation
  -- must fail after the profile-scoped child lookup rather than borrowing A's.
  v_cutover_b:=public.red_authorize_reimport_cutover((b->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  BEGIN
    PERFORM public.red_activate_reimport_batch((b->>'source_batch_id')::uuid,v_cutover_b);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_CUTOVER_INVALID'
     OR NOT EXISTS(SELECT 1 FROM private.reimport_batch WHERE id=(a->>'child_batch_id')::uuid AND status='finalized')
     OR EXISTS(SELECT 1 FROM private.reimport_batch WHERE id=(b->>'source_batch_id')::uuid AND status<>'finalized') THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_FOREIGN_VALID_CHILD_ACCEPTED: %',v_error;
  END IF;
  b:=pg_temp.task3_complete_profile(b);
  IF a->>'source_authorization_id'=b->>'source_authorization_id'
     OR a->>'source_batch_id'=b->>'source_batch_id'
     OR a->>'child_authorization_id'=b->>'child_authorization_id'
     OR a->>'child_batch_id'=b->>'child_batch_id'
     OR a->>'person_id'=b->>'person_id'
     OR a->>'fact_id'=b->>'fact_id'
     OR a->>'assertion_id'=b->>'assertion_id'
     OR a->>'citation_id'=b->>'citation_id' THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_TWO_PROFILE_ID_COLLISION';
  END IF;
  IF NOT EXISTS(
       SELECT 1 FROM private.reimport_name_completion_result r
        JOIN private.reimport_batch child ON child.id=r.batch_id
        JOIN private.reimport_batch source ON source.id=r.source_batch_id
        JOIN public.fact f ON f.id=r.fact_id AND f.subjekt_id=r.person_id AND f.faktatype='navn'
        JOIN public.assertion x ON x.id=r.assertion_id AND x.target_id=r.fact_id
        JOIN public.citation c ON c.id=r.citation_id AND c.assertion_id=r.assertion_id AND c.source_id=source.source_id
       WHERE child.id=(a->>'child_batch_id')::uuid AND source.id=(a->>'source_batch_id')::uuid AND source.source_id=4 AND c.citat_tekst='task-3-profile-four side 1'
     ) OR NOT EXISTS(
       SELECT 1 FROM private.reimport_name_completion_result r
        JOIN private.reimport_batch child ON child.id=r.batch_id
        JOIN private.reimport_batch source ON source.id=r.source_batch_id
        JOIN public.fact f ON f.id=r.fact_id AND f.subjekt_id=r.person_id AND f.faktatype='navn'
        JOIN public.assertion x ON x.id=r.assertion_id AND x.target_id=r.fact_id
        JOIN public.citation c ON c.id=r.citation_id AND c.assertion_id=r.assertion_id AND c.source_id=source.source_id
       WHERE child.id=(b->>'child_batch_id')::uuid AND source.id=(b->>'source_batch_id')::uuid AND source.source_id=5 AND c.citat_tekst='task-3-profile-five side 1'
     ) OR (SELECT count(*) FROM private.reimport_name_completion_result WHERE batch_id IN((a->>'child_batch_id')::uuid,(b->>'child_batch_id')::uuid))<>2 THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_TWO_PROFILE_FACT_IDENTITY_CITATION_SCOPE_INVALID';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_cutover_a:=public.red_authorize_reimport_cutover((a->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_activation_a:=public.red_activate_reimport_batch((a->>'source_batch_id')::uuid,v_cutover_a);
  PERFORM set_config('app.change_set_id','',true);
  v_activation_b:=public.red_activate_reimport_batch((b->>'source_batch_id')::uuid,v_cutover_b);
  IF v_activation_a->>'status'<>'activated' OR v_activation_b->>'status'<>'activated'
     OR NOT EXISTS(SELECT 1 FROM private.reimport_event e WHERE e.batch_id=(a->>'source_batch_id')::uuid AND e.operation='activation'
                     AND e.payload->'post_activation_receipts'->(a->>'person_id')->>'source_person_create_event_id' IS NOT NULL
                     AND e.payload->'post_activation_receipts'->(a->>'person_id')->>'event_id' IS NOT NULL)
     OR NOT EXISTS(SELECT 1 FROM private.reimport_event e WHERE e.batch_id=(b->>'source_batch_id')::uuid AND e.operation='activation'
                     AND e.payload->'post_activation_receipts'->(b->>'person_id')->>'source_person_create_event_id' IS NOT NULL
                     AND e.payload->'post_activation_receipts'->(b->>'person_id')->>'event_id' IS NOT NULL)
     OR EXISTS(SELECT 1 FROM public.person WHERE id IN((a->>'person_id')::bigint,(b->>'person_id')::bigint) AND staged) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_TWO_PROFILE_POSTACTIVATION_RECEIPT_INVALID';
  END IF;
  v_reversal_a:=public.red_authorize_reimport_reversal((a->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_error:=NULL;
  BEGIN
    PERFORM public.red_reverse_reimport((b->>'source_batch_id')::uuid,v_reversal_a);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_REVERSAL_INVALID'
     OR EXISTS(SELECT 1 FROM private.reimport_batch
                WHERE id IN((a->>'source_batch_id')::uuid,(b->>'source_batch_id')::uuid)
                  AND status<>'activated')
     OR EXISTS(SELECT 1
                 FROM private.narrative_record_publication binding
                 JOIN public.narrative narrative ON narrative.id=binding.narrative_id
                WHERE binding.status='withdrawn'
                  AND narrative.subjekt_type='person'
                  AND narrative.subjekt_id=(b->>'person_id')::bigint) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_CROSS_PROFILE_REVERSAL_ACCEPTED: %',v_error;
  END IF;
  v_reversal_b:=public.red_authorize_reimport_reversal((b->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_reverse_a:=public.red_reverse_reimport((a->>'source_batch_id')::uuid,v_reversal_a);
  v_reverse_b:=public.red_reverse_reimport((b->>'source_batch_id')::uuid,v_reversal_b);
  IF v_reverse_a->>'status'<>'reversed' OR v_reverse_b->>'status'<>'reversed'
     OR EXISTS(SELECT 1 FROM private.reimport_batch WHERE id IN((a->>'source_batch_id')::uuid,(a->>'child_batch_id')::uuid,(b->>'source_batch_id')::uuid,(b->>'child_batch_id')::uuid) AND status<>'reversed')
     OR EXISTS(SELECT 1 FROM public.fact WHERE id IN((a->>'fact_id')::bigint,(b->>'fact_id')::bigint))
     OR NOT EXISTS(SELECT 1 FROM private.narrative_record_publication binding JOIN public.narrative narrative ON narrative.id=binding.narrative_id WHERE binding.status='withdrawn' AND narrative.subjekt_type='person' AND narrative.subjekt_id IN((a->>'person_id')::bigint,(b->>'person_id')::bigint)) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_TWO_PROFILE_EVENT_REVERSAL_INVALID';
  END IF;
END $two_profile_scope$;

-- Task 10 follow-up: reject unusable page evidence during child authorization,
-- before preflight or begin can mint durable writer state.  The failed
-- authorization's nested transaction must leave every writer/domain receipt
-- count unchanged.
DO $authorization_page_evidence_contract$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000101'; v_state jsonb;
  v_payload jsonb; v_payloads jsonb; v_candidate jsonb; v_error text;
  v_authorizations bigint; v_batches bigint; v_results bigint; v_events bigint;
  v_facts bigint; v_assertions bigint; v_citations bigint; v_conclusions bigint;
  v_case integer;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_state:=pg_temp.task3_stage_profile(
    8,'task10-authorization-page-evidence',repeat('a',64),'task10-authorization-page-evidence-record',
    'Task 10 authorization page evidence',-153108,repeat('b',64),repeat('c',64));
  v_payload:=jsonb_build_object(
    'source_batch_id',v_state->>'source_batch_id','source_person_create_element_id',v_state->>'source_element_id',
    'person_id',v_state->>'person_id','source_id',(v_state->'person_payload'->>'source_id')::bigint,
    'edition','fixture','source_record_key',v_state->'person_payload'->>'source_record_key',
    'source_persona_id',v_state->>'source_persona_id','name',v_state->'person_payload'->>'name',
    'source_span',v_state->'person_payload'->'source_span','page_evidence',v_state->'person_payload'->'page_evidence',
    'verbatim_text',v_state->'person_payload'->>'verbatim_text','verbatim_sha256',v_state->'person_payload'->>'verbatim_sha256',
    'source_payload_sha256',private.reimport_canonical_json_sha256(v_state->'person_payload'),
    'expected_before',jsonb_build_object('staged',true,'name_cache_empty',true,'name_facts',0),
    'expected_after',jsonb_build_object('name_fact',1,'selected_assertion',1,'citation',1,'conclusion',1));
  SELECT count(*) INTO v_authorizations FROM private.reimport_authorization;
  SELECT count(*) INTO v_batches FROM private.reimport_batch;
  SELECT count(*) INTO v_results FROM private.reimport_name_completion_result;
  SELECT count(*) INTO v_events FROM private.reimport_event;
  SELECT count(*) INTO v_facts FROM public.fact;
  SELECT count(*) INTO v_assertions FROM public.assertion;
  SELECT count(*) INTO v_citations FROM public.citation;
  SELECT count(*) INTO v_conclusions FROM public.conclusion;
  FOR v_case IN 0..5 LOOP
    v_candidate:=CASE v_case
      WHEN 0 THEN v_payload-'page_evidence'
      WHEN 1 THEN jsonb_set(v_payload,'{page_evidence}',jsonb_build_object('page_from',NULL))
      WHEN 2 THEN jsonb_set(v_payload,'{page_evidence}',jsonb_build_object('page_from',1.5))
      WHEN 3 THEN jsonb_set(v_payload,'{page_evidence}',jsonb_build_object('page_from',0))
      WHEN 4 THEN jsonb_set(v_payload,'{page_evidence}',jsonb_build_object('page_from',-1))
      ELSE jsonb_set(v_payload,'{page_evidence}',jsonb_build_object('page_from','1'))
    END;
    v_payloads:=jsonb_build_object('name-completion:'||(v_state->'person_payload'->>'source_record_key'),v_candidate);
    v_error:=NULL;
    BEGIN
      PERFORM public.red_authorize_reimport_name_completion(
        repeat('8',64),(v_state->>'source_batch_id')::uuid,v_state->>'preview_sha256',v_state->>'manifest_sha256',
        (v_state->>'source_id')::bigint,v_state->>'profile_id',v_state->>'profile_sha256',
        '{"name_completions":1,"operations":1}'::jsonb,v_payloads);
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS DISTINCT FROM 'REIMPORT_NAME_COMPLETION_INVALID'
       OR (SELECT count(*) FROM private.reimport_authorization)<>v_authorizations
       OR (SELECT count(*) FROM private.reimport_batch)<>v_batches
       OR (SELECT count(*) FROM private.reimport_name_completion_result)<>v_results
       OR (SELECT count(*) FROM private.reimport_event)<>v_events
       OR (SELECT count(*) FROM public.fact)<>v_facts
       OR (SELECT count(*) FROM public.assertion)<>v_assertions
       OR (SELECT count(*) FROM public.citation)<>v_citations
       OR (SELECT count(*) FROM public.conclusion)<>v_conclusions THEN
      RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_AUTHORIZATION_PAGE_EVIDENCE_ACCEPTED: %, %',v_case,v_error;
    END IF;
  END LOOP;
END $authorization_page_evidence_contract$;

-- Task 10: allocation is a shared identity contract, not a cooperative
-- writer-only lock.  An ordinary default writer must receive its own ID, and
-- a completion after earlier receipts were reversed must never reuse any
-- retained receipt ID.
DO $identity_allocation_contract$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000101'; v_state jsonb;
  v_ordinary_fact bigint; v_retained_fact_ids bigint[]; v_retained_assertion_ids bigint[];
  v_retained_citation_ids bigint[]; v_retained_conclusion_ids bigint[];
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT array_agg(result.fact_id),array_agg(result.assertion_id),
         array_agg(result.citation_id),array_agg(result.conclusion_id)
    INTO v_retained_fact_ids,v_retained_assertion_ids,v_retained_citation_ids,v_retained_conclusion_ids
    FROM private.reimport_name_completion_result result
    JOIN private.reimport_batch child ON child.id=result.batch_id
   WHERE child.status='reversed';
  IF coalesce(array_length(v_retained_fact_ids,1),0)<2 THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RETAINED_RECEIPTS_MISSING';
  END IF;
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
  VALUES('person',-153109,'task10-ordinary-default-writer')
  RETURNING id INTO v_ordinary_fact;
  IF v_ordinary_fact IS NULL THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_ORDINARY_DEFAULT_ID_MISSING';
  END IF;
  v_state:=pg_temp.task3_stage_profile(
    7,'task-10-post-reversal',repeat('f',64),'task-10-post-reversal-record',
    'Task 10 post reversal',-153109,repeat('5',64),repeat('6',64));
  v_state:=pg_temp.task3_complete_profile(v_state);
  IF (v_state->>'fact_id')::bigint=ANY(v_retained_fact_ids)
     OR (v_state->>'assertion_id')::bigint=ANY(v_retained_assertion_ids)
     OR (v_state->>'citation_id')::bigint=ANY(v_retained_citation_ids)
     OR EXISTS(
       SELECT 1 FROM private.reimport_name_completion_result result
        WHERE result.batch_id=(v_state->>'child_batch_id')::uuid
          AND result.conclusion_id=ANY(v_retained_conclusion_ids)
     ) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_RETAINED_ID_REUSED';
  END IF;
END $identity_allocation_contract$;

DO $same_profile_manifest_scope$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000101'; a jsonb; b jsonb;
  v_error text; v_cutover_a uuid; v_cutover_b uuid; v_activation_a jsonb; v_activation_b jsonb;
  v_reversal_a uuid; v_reversal_b uuid; v_reverse_a jsonb; v_reverse_b jsonb;
BEGIN
  INSERT INTO auth.users(id,email) VALUES(v_actor,'reimport-name-completion-153@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_actor,'reimport-name-completion-153@example.invalid','redaktion','Task 3 generic fixture')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Task 3 generic fixture';
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  a:=pg_temp.task3_stage_profile(
    6,'task-3-shared-profile',repeat('e',64),'task-3-shared-profile-record-a',
    'Task 3 shared profile A',-153106,repeat('1',64),repeat('2',64));
  b:=pg_temp.task3_stage_profile(
    6,'task-3-shared-profile',repeat('e',64),'task-3-shared-profile-record-b',
    'Task 3 shared profile B',-153107,repeat('3',64),repeat('4',64));
  a:=pg_temp.task3_complete_profile(a);
  b:=pg_temp.task3_complete_profile(b);
  PERFORM set_config('app.change_set_id','',true);
  v_cutover_a:=public.red_authorize_reimport_cutover((a->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_activation_a:=public.red_activate_reimport_batch((a->>'source_batch_id')::uuid,v_cutover_a);
  PERFORM set_config('app.change_set_id','',true);
  v_cutover_b:=public.red_authorize_reimport_cutover((b->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_activation_b:=public.red_activate_reimport_batch((b->>'source_batch_id')::uuid,v_cutover_b);
  IF v_activation_a->>'status'<>'activated' OR v_activation_b->>'status'<>'activated' THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_SAME_PROFILE_MANIFEST_ACTIVATION_INVALID';
  END IF;
  v_reversal_a:=public.red_authorize_reimport_reversal((a->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_error:=NULL;
  BEGIN
    PERFORM public.red_reverse_reimport((b->>'source_batch_id')::uuid,v_reversal_a);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_REVERSAL_INVALID'
     OR EXISTS(SELECT 1 FROM private.reimport_batch
                WHERE id IN((a->>'source_batch_id')::uuid,(b->>'source_batch_id')::uuid)
                  AND status<>'activated')
     OR EXISTS(SELECT 1 FROM private.reimport_batch
                WHERE id IN((a->>'child_batch_id')::uuid,(b->>'child_batch_id')::uuid)
                  AND status<>'finalized')
     OR (SELECT status FROM private.reimport_authorization WHERE id=v_reversal_a)<>'issued'
     OR EXISTS(SELECT 1 FROM private.reimport_event WHERE batch_id=(b->>'source_batch_id')::uuid AND operation='reversal')
     OR EXISTS(SELECT 1
                 FROM private.narrative_record_publication binding
                 JOIN public.narrative narrative ON narrative.id=binding.narrative_id
                WHERE binding.status='withdrawn'
                  AND narrative.subjekt_type='person'
                  AND narrative.subjekt_id=(b->>'person_id')::bigint) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_SAME_PROFILE_MANIFEST_REVERSAL_ACCEPTED: %',v_error;
  END IF;
  v_reversal_b:=public.red_authorize_reimport_reversal((b->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_reverse_a:=public.red_reverse_reimport((a->>'source_batch_id')::uuid,v_reversal_a);
  v_reverse_b:=public.red_reverse_reimport((b->>'source_batch_id')::uuid,v_reversal_b);
  IF v_reverse_a->>'status'<>'reversed' OR v_reverse_b->>'status'<>'reversed'
     OR EXISTS(SELECT 1 FROM private.reimport_batch
                WHERE id IN((a->>'source_batch_id')::uuid,(a->>'child_batch_id')::uuid,
                            (b->>'source_batch_id')::uuid,(b->>'child_batch_id')::uuid)
                  AND status<>'reversed')
     OR EXISTS(SELECT 1 FROM public.fact WHERE id IN((a->>'fact_id')::bigint,(b->>'fact_id')::bigint))
     OR NOT EXISTS(SELECT 1
                     FROM private.narrative_record_publication binding
                     JOIN public.narrative narrative ON narrative.id=binding.narrative_id
                    WHERE binding.status='withdrawn'
                      AND narrative.subjekt_type='person'
                      AND narrative.subjekt_id IN((a->>'person_id')::bigint,(b->>'person_id')::bigint)) THEN
    RAISE EXCEPTION 'REIMPORT_NAME_COMPLETION_SAME_PROFILE_MANIFEST_OWN_REVERSAL_INVALID';
  END IF;
END $same_profile_manifest_scope$;

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
