\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE v_relation text; v_signature text;
BEGIN
  FOREACH v_relation IN ARRAY ARRAY[
    'private.reimport_writer_profile','private.reimport_authorization',
    'private.reimport_batch','private.reimport_event',
    'private.reimport_name_completion_result'
  ] LOOP
    IF to_regclass(v_relation) IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_PRIMARY_MISSING: %',v_relation; END IF;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)',
    'public.red_begin_reimport(uuid,text,text)','public.red_apply_reimport_source_evidence(uuid,text,jsonb)',
    'public.red_apply_reimport_person_create(uuid,text,jsonb)','public.red_finalize_reimport(uuid)',
    'public.red_authorize_reimport_reversal(uuid,uuid,timestamptz)','public.red_reverse_reimport(uuid,uuid)',
    'public.red_authorize_reimport_cutover(uuid,uuid,timestamptz)','public.red_activate_reimport_batch(uuid,uuid)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_RPC_MISSING: %',v_signature; END IF;
  END LOOP;
  FOREACH v_relation IN ARRAY ARRAY['reimport_writer_profile','reimport_authorization','reimport_batch'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='private' AND table_name=v_relation AND column_name='profile_sha256') THEN RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_HASH_MISSING: %',v_relation; END IF;
  END LOOP;
  IF NOT EXISTS (
       SELECT 1 FROM pg_constraint constraint_row
       WHERE conrelid='private.reimport_authorization'::regclass AND contype='f'
         AND confrelid='private.reimport_writer_profile'::regclass
         AND ARRAY(SELECT attribute.attname::text FROM unnest(constraint_row.conkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
         AND ARRAY(SELECT attribute.attname::text FROM unnest(constraint_row.confkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.confrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_constraint constraint_row
       WHERE conrelid='private.reimport_batch'::regclass AND contype='f'
         AND confrelid='private.reimport_writer_profile'::regclass
         AND ARRAY(SELECT attribute.attname::text FROM unnest(constraint_row.conkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
         AND ARRAY(SELECT attribute.attname::text FROM unnest(constraint_row.confkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.confrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_constraint constraint_row
       WHERE conrelid='private.reimport_batch'::regclass AND contype='f'
         AND confrelid='private.reimport_authorization'::regclass
         AND ARRAY(SELECT attribute.attname::text FROM unnest(constraint_row.conkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['authorization_id','source_id','profile_id','profile_sha256']
         AND ARRAY(SELECT attribute.attname::text FROM unnest(constraint_row.confkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.confrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['id','source_id','profile_id','profile_sha256']
     ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_FOREIGN_KEYS_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.reimport_writer_profile'::regclass AND NOT tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.reimport_event'::regclass AND NOT tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='private.reimport_name_completion_result'::regclass AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_APPEND_ONLY_TRIGGER_MISSING';
  END IF;
END $catalog$;

DO $v1_gate$
DECLARE v_before bigint; v_error text;
BEGIN
  SELECT count(*) INTO v_before FROM private.reimport_authorization;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('a',64),repeat('b',64),current_database(),3,
      'daa-1939-v50-production-write-v1',repeat('a',64),'{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED'
     OR (SELECT count(*) FROM private.reimport_authorization)<>v_before THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_V2_GATE_INVALID: %',v_error;
  END IF;
END $v1_gate$;

\ir reimport-writer-v2-bootstrap.sql

DO $profile_identity$
DECLARE v_error text; v_before jsonb; v_authorizations_before bigint;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(3,'Task 2 primary profile','fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile
    (source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','production-writer-v1',repeat('a',64),
    '{"run_key_prefix":"fixture-1939:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"fixture-rendition-3","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed","citation_label_template":"Fixture 1939 side {page_from}"}'::jsonb)
  ON CONFLICT (source_id,profile_id,profile_sha256) DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM private.reimport_writer_profile WHERE source_id=3
      AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=repeat('a',64)) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_1939_PROFILE_MISSING';
  END IF;
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(-153002,'Task 1 unreferenced profile','fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(-153002,'task-1-unreferenced-profile-v1','fixture-v1',repeat('f',64),
    '{"run_key_prefix":"task-1:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"task-1","rendition_kind":"ocr_text","rendition_metadata":{},"observation_extraction_method":"fixture","citation_label_template":"Task 1 side {page_from}"}'::jsonb);
  SELECT to_jsonb(profile) INTO v_before FROM private.reimport_writer_profile profile WHERE source_id=-153002 AND profile_id='task-1-unreferenced-profile-v1';
  BEGIN UPDATE private.reimport_writer_profile SET profile_version='tampered' WHERE source_id=-153002 AND profile_id='task-1-unreferenced-profile-v1'; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_PROFILE_APPEND_ONLY'
     OR (SELECT to_jsonb(profile) FROM private.reimport_writer_profile profile WHERE source_id=-153002 AND profile_id='task-1-unreferenced-profile-v1') IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_MUTATION_ACCEPTED: %',v_error; END IF;
  v_error:=NULL;
  BEGIN DELETE FROM private.reimport_writer_profile WHERE source_id=-153002 AND profile_id='task-1-unreferenced-profile-v1'; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_PROFILE_APPEND_ONLY'
     OR (SELECT to_jsonb(profile) FROM private.reimport_writer_profile profile WHERE source_id=-153002 AND profile_id='task-1-unreferenced-profile-v1') IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_DELETE_ACCEPTED: %',v_error; END IF;
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(4,'Task 2 second profile','fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile
    (source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES
    (3,'daa-1939-v50-production-write-v1','production-writer-v1',repeat('a',64),
     '{"run_key_prefix":"fixture-1939:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"fixture-rendition-3","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed","citation_label_template":"Fixture 1939 side {page_from}"}'::jsonb),
    (4,'synthetic-second-profile-v1','synthetic-v1',repeat('b',64),
     '{"run_key_prefix":"fixture-second:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"fixture-rendition-4","rendition_kind":"ocr_text","rendition_metadata":{"edition":"synthetic"},"observation_extraction_method":"human_reviewed","citation_label_template":"Fixture second side {page_from}"}'::jsonb)
  ON CONFLICT (source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT count(*) INTO v_authorizations_before FROM private.reimport_authorization;
  v_error:=NULL;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('a',64),repeat('b',64),current_database(),3,
      'daa-1939-v50-production-write-v1',repeat('c',64),'{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_PROFILE_INVALID'
     OR (SELECT count(*) FROM private.reimport_authorization)<>v_authorizations_before THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_HASH_MISMATCH_ACCEPTED: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('a',64),repeat('b',64),current_database(),4,
      'daa-1939-v50-production-write-v1',repeat('a',64),'{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_PROFILE_INVALID'
     OR (SELECT count(*) FROM private.reimport_authorization)<>v_authorizations_before THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_SOURCE_MISMATCH_ACCEPTED: %',v_error;
  END IF;
END $profile_identity$;

DO $migration_writer_behavior$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000001';
  v_other_actor uuid:='15300000-0000-4000-8000-000000000006';
  v_authorization uuid; v_replay_authorization uuid; v_batch uuid; v_replay_batch uuid;
  v_source_payload jsonb; v_elements jsonb; v_error text;
  v_observations_before bigint; v_batches_before bigint; v_direct_denied boolean:=false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_source_payload:=jsonb_build_object(
    'disposition','retain_source_only','source_record_key','migration-behavior-source-153',
    'source_span',jsonb_build_object('char_from',0,'char_to',28),
    'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text','migration source evidence 153',
    'rendition_content_sha256',repeat('1',64)
  );
  v_elements:=jsonb_build_object('source-evidence:migration-153',v_source_payload);
  IF has_function_privilege('anon','private.ensure_reimport_source_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.ensure_reimport_source_evidence(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('service_role','private.ensure_reimport_source_evidence(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_SOURCE_HELPER_ACL_LEAK';
  END IF;
  v_authorization:=public.red_authorize_reimport(
    repeat('1',64),repeat('2',64),current_database(),3,
    'daa-1939-v50-production-write-v1',repeat('a',64),
    '{"person_creates":0,"source_evidence":1}'::jsonb,v_elements,
    '15300000-0000-4000-8000-000000000008',clock_timestamp()+interval '5 minutes'
  );
  v_batch:=public.red_begin_reimport(v_authorization,repeat('1',64),repeat('2',64));
  SELECT count(*) INTO v_observations_before FROM private.source_observation;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM private.ensure_reimport_source_evidence(v_batch,'source-evidence:migration-153',v_source_payload);
    EXCEPTION WHEN insufficient_privilege THEN
      v_direct_denied:=true;
    END;
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    RAISE;
  END;
  IF NOT v_direct_denied
     OR (SELECT count(*) FROM private.source_observation)<>v_observations_before THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_SOURCE_HELPER_DIRECT_WRITE_ACCEPTED';
  END IF;
  v_error:=NULL;
  BEGIN PERFORM public.red_finalize_reimport(v_batch); EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_FINALIZE_COUNT_MISMATCH'
     OR (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'open' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_FINALIZE_COUNT_GUARD_INVALID: %',v_error;
  END IF;
  INSERT INTO auth.users(id,email) VALUES(v_other_actor,'migration-other-editor@example.invalid') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.profiles(id,email,rolle,navn)
  VALUES(v_other_actor,'migration-other-editor@example.invalid','redaktion','Migration other editor')
  ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Migration other editor';
  PERFORM set_config('request.jwt.claim.sub',v_other_actor::text,true);
  v_error:=NULL;
  BEGIN PERFORM public.red_finalize_reimport(v_batch); EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_BATCH_INVALID'
     OR (SELECT status FROM private.reimport_batch WHERE id=v_batch)<>'open' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_FINALIZE_OWNER_GUARD_INVALID: %',v_error;
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:migration-153',v_source_payload);
  IF (public.red_finalize_reimport(v_batch)->>'status')<>'finalized' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_FINALIZE_FAILED';
  END IF;
  SELECT count(*) INTO v_batches_before FROM private.reimport_batch;
  v_replay_authorization:=public.red_authorize_reimport(
    repeat('1',64),repeat('2',64),current_database(),3,
    'daa-1939-v50-production-write-v1',repeat('a',64),
    '{"person_creates":0,"source_evidence":1}'::jsonb,v_elements,
    '15300000-0000-4000-8000-000000000009',clock_timestamp()+interval '5 minutes'
  );
  v_replay_batch:=public.red_begin_reimport(v_replay_authorization,repeat('1',64),repeat('2',64));
  IF v_replay_batch IS DISTINCT FROM v_batch
     OR (SELECT count(*) FROM private.reimport_batch)<>v_batches_before
     OR (SELECT status FROM private.reimport_authorization WHERE id=v_replay_authorization)<>'consumed' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_FINALIZED_REPLAY_INVALID';
  END IF;
END $migration_writer_behavior$;

DO $fixture_visible$
BEGIN
  IF public.narrative_record_contract_version()<>2
     OR NOT EXISTS (
       SELECT 1 FROM private.narrative_record_cutover_receipt
        WHERE nonce='15300000-0000-4000-8000-000000000004'
     ) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_V2_BOOTSTRAP_NOT_VISIBLE';
  END IF;
END $fixture_visible$;

ROLLBACK;
