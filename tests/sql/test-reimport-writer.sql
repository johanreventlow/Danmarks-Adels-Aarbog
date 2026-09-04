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
    'public.red_apply_reimport_person_create(uuid,text,jsonb)',
    'public.red_apply_reimport_legacy_migration(uuid,text,jsonb)','public.red_finalize_reimport(uuid)',
    'public.red_apply_reimport_canonical_delta(uuid,text,jsonb)',
    'public.red_reimport_batch_result(uuid,uuid)',
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

DO $writer_config_contract$
DECLARE v_config jsonb := '{"run_key_prefix":"task9:","schema_version":"v1","extractor_version":"v1","rendition_key":"task9","rendition_kind":"ocr_text","rendition_metadata":{},"observation_extraction_method":"fixture","citation_label_template":"Task 9 side {page_from}"}'::jsonb;
  v_invalid jsonb; v_error text;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(-153009,'Task 9 config','fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  FOREACH v_invalid IN ARRAY ARRAY[
    v_config-'rendition_key',v_config||jsonb_build_object('extra','x'),
    jsonb_set(v_config,'{rendition_metadata}','null'::jsonb),jsonb_set(v_config,'{rendition_metadata}','[]'::jsonb),
    jsonb_set(v_config,'{run_key_prefix}','1'::jsonb),jsonb_set(v_config,'{schema_version}','null'::jsonb),
    jsonb_set(v_config,'{extractor_version}','""'::jsonb),jsonb_set(v_config,'{rendition_key}','null'::jsonb),
    jsonb_set(v_config,'{rendition_kind}','1'::jsonb),jsonb_set(v_config,'{observation_extraction_method}','null'::jsonb),
    jsonb_set(v_config,'{citation_label_template}','null'::jsonb),
    jsonb_set(v_config,'{citation_label_template}','"no placeholder"'::jsonb),jsonb_set(v_config,'{citation_label_template}','"{page_from} {other}"'::jsonb)
  ] LOOP
    v_error:=NULL;
    BEGIN
      INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
      VALUES(-153009,'task9-invalid-'||substr(md5(v_invalid::text),1,8),'v1',private.reimport_canonical_json_sha256(v_invalid),v_invalid);
    EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
    END;
    IF v_error IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_CONFIG_INVALID_ACCEPTED'; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM private.reimport_writer_profile WHERE source_id=-153009 AND profile_id LIKE 'task9-invalid-%') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_CONFIG_INVALID_STORED';
  END IF;
END $writer_config_contract$;

DO $v1_gate$
DECLARE v_before bigint; v_error text;
BEGIN
  SELECT count(*) INTO v_before FROM private.reimport_authorization;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('a',64),repeat('b',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,
      'daa-1939-v50-production-write-v1',repeat('a',64),'{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED'
     OR (SELECT count(*) FROM private.reimport_authorization)<>v_before THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_V2_GATE_INVALID: %',v_error;
  END IF;
END $v1_gate$;

\ir reimport-writer-v2-bootstrap.sql

DO $acl_parity$
DECLARE
  v_signature text; v_expect_authenticated boolean; v_expect_service_role boolean;
  v_public boolean; v_anon boolean; v_authenticated boolean; v_service_role boolean;
BEGIN
  FOR v_signature,v_expect_authenticated,v_expect_service_role IN
    SELECT * FROM unnest(ARRAY[
      'private.reject_reimport_writer_mutation()',
      'private.require_reimport_writer_editor()',
      'private.require_reimport_open_batch(uuid)',
      'private.lock_reimport_writer(bigint,text)',
      'private.validate_reimport_authorization_payload(jsonb,jsonb)',
      'private.ensure_reimport_source_evidence(uuid,text,jsonb)',
      'private.reimport_canonical_json_text(jsonb)',
      'private.reimport_canonical_json_sha256(jsonb)',
      'private.validate_reimport_name_completion(uuid,uuid,text,jsonb)',
      'private.migrate_legacy_narrative_record(uuid,text,jsonb)',
      'private.legacy_migration_reversal_state(uuid)',
      'private.record_reimport_legacy_reversal(uuid,uuid,jsonb)',
      'public.red_authorize_reimport(text,text,text,bigint,text,text,jsonb,jsonb,uuid,timestamptz)',
      'public.red_preflight_reimport_authorization(uuid,text,text)',
      'public.red_begin_reimport(uuid,text,text)',
      'public.red_apply_reimport_source_evidence(uuid,text,jsonb)',
      'public.red_apply_reimport_person_create(uuid,text,jsonb)',
      'public.red_apply_reimport_legacy_migration(uuid,text,jsonb)',
      'public.red_finalize_reimport(uuid)',
      'public.red_reimport_batch_result(uuid,uuid)',
      'public.red_authorize_reimport_reversal(uuid,uuid,timestamptz)',
      'public.red_reverse_reimport(uuid,uuid)',
      'public.red_authorize_reimport_cutover(uuid,uuid,timestamptz)',
      'public.red_activate_reimport_batch(uuid,uuid)',
      'public.red_apply_reimport_canonical_delta(uuid,text,jsonb)',
      'public.red_lock_reimport_name_completion(text,bigint,text)',
      'public.red_authorize_reimport_name_completion(text,uuid,text,text,bigint,text,text,jsonb,jsonb)',
      'public.red_preflight_reimport_name_completion(uuid,uuid,text,jsonb)',
      'public.red_begin_reimport_name_completion(uuid,text,uuid)',
      'public.red_apply_reimport_name_completion(uuid,text,jsonb)',
      'public.red_finalize_reimport_name_completion(uuid)'
    ],ARRAY[
      false,false,false,false,false,false,false,false,false,false,false,false,
      false,true,true,true,true,true,true,true,false,true,false,true,true,
      true,false,true,true,true,true
    ],ARRAY[
      false,false,false,false,false,false,false,false,false,false,false,false,
      true,false,false,false,false,false,false,false,true,false,true,false,false,
      false,true,false,false,false,false
    ]) AS acl(signature,expect_authenticated,expect_service_role)
  LOOP
    SELECT EXISTS(
      SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       WHERE p.oid=to_regprocedure(v_signature) AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
    ) INTO v_public;
    v_anon:=has_function_privilege('anon',v_signature,'EXECUTE');
    v_authenticated:=has_function_privilege('authenticated',v_signature,'EXECUTE');
    v_service_role:=has_function_privilege('service_role',v_signature,'EXECUTE');
    IF v_public OR v_anon OR v_authenticated IS DISTINCT FROM v_expect_authenticated
       OR v_service_role IS DISTINCT FROM v_expect_service_role THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_ACL_PARITY_INVALID: % public=% anon=% authenticated=% service_role=%',
        v_signature,v_public,v_anon,v_authenticated,v_service_role;
    END IF;
  END LOOP;
END $acl_parity$;

DO $profile_identity$
DECLARE
  v_error text; v_before jsonb; v_authorizations_before bigint;
  v_profile_sha text;
  v_1939_config jsonb := '{"run_key_prefix":"reimport-1939-v50:","schema_version":"1939-v50-production-write-manifest-v1","extractor_version":"production-writer-v1","rendition_key":"daa-1939-calamari-r6-clean","rendition_kind":"ocr_text","rendition_metadata":{"edition":"1939"},"observation_extraction_method":"human_reviewed_1939_v50","citation_label_template":"DAA 1939 side {page_from}"}'::jsonb;
  v_unreferenced_config jsonb := '{"run_key_prefix":"task-1:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"task-1","rendition_kind":"ocr_text","rendition_metadata":{},"observation_extraction_method":"fixture","citation_label_template":"Task 1 side {page_from}"}'::jsonb;
  v_second_config jsonb := '{"run_key_prefix":"fixture-second:","schema_version":"fixture-v1","extractor_version":"fixture-v1","rendition_key":"fixture-rendition-4","rendition_kind":"ocr_text","rendition_metadata":{"edition":"synthetic"},"observation_extraction_method":"human_reviewed","citation_label_template":"Fixture second side {page_from}"}'::jsonb;
BEGIN
  INSERT INTO public.source(id,titel,udgave,slags)
  VALUES(3,'Task 2 primary profile','fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'daa-1939-v50-production-write-v1','production-writer-v1',private.reimport_canonical_json_sha256(v_1939_config),v_1939_config)
  ON CONFLICT(source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT profile_sha256 INTO v_profile_sha FROM private.reimport_writer_profile
   WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1';
  IF NOT EXISTS (SELECT 1 FROM private.reimport_writer_profile WHERE source_id=3
      AND profile_id='daa-1939-v50-production-write-v1' AND profile_sha256=v_profile_sha
      AND profile_sha256=private.reimport_canonical_json_sha256(writer_config)) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_1939_PROFILE_MISSING';
  END IF;
  INSERT INTO public.source(id,titel,udgave,slags) VALUES(-153002,'Task 1 unreferenced profile','fixture','DAA-udgave') ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(-153002,'task-1-unreferenced-profile-v1','fixture-v1',private.reimport_canonical_json_sha256(v_unreferenced_config),v_unreferenced_config);
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
  VALUES(4,'synthetic-second-profile-v1','synthetic-v1',private.reimport_canonical_json_sha256(v_second_config),v_second_config)
  ON CONFLICT (source_id,profile_id,profile_sha256) DO NOTHING;
  SELECT count(*) INTO v_authorizations_before FROM private.reimport_authorization;
  v_error:=NULL;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('a',64),repeat('b',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,
      'daa-1939-v50-production-write-v1',repeat('c',64),'{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_PROFILE_HASH_INVALID'
     OR (SELECT count(*) FROM private.reimport_authorization)<>v_authorizations_before THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PROFILE_HASH_MISMATCH_ACCEPTED: %',v_error;
  END IF;
  v_error:=NULL;
  BEGIN
    PERFORM public.red_authorize_reimport(repeat('a',64),repeat('b',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,4,
    'daa-1939-v50-production-write-v1',v_profile_sha,'{}'::jsonb,'{}'::jsonb,gen_random_uuid(),clock_timestamp()+interval '5 minutes');
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
  v_authorization uuid; v_replay_authorization uuid; v_batch uuid; v_replay_batch uuid; v_result jsonb;
  v_source_payload jsonb; v_elements jsonb; v_error text; v_profile_sha text;
  v_observations_before bigint; v_batches_before bigint; v_direct_denied boolean:=false; v_private_read_denied boolean:=false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SELECT profile_sha256 INTO v_profile_sha FROM private.reimport_writer_profile
   WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1';
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
  IF has_table_privilege('anon','private.reimport_authorization','SELECT')
     OR has_table_privilege('authenticated','private.reimport_authorization','SELECT')
     OR has_table_privilege('service_role','private.reimport_authorization','SELECT')
     OR has_table_privilege('anon','private.reimport_batch','SELECT')
     OR has_table_privilege('authenticated','private.reimport_batch','SELECT')
     OR has_table_privilege('service_role','private.reimport_batch','SELECT')
     OR has_table_privilege('anon','private.reimport_event','SELECT')
     OR has_table_privilege('authenticated','private.reimport_event','SELECT')
     OR has_table_privilege('service_role','private.reimport_event','SELECT') THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PRIVATE_LEDGER_ACL_LEAK';
  END IF;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM 1 FROM private.reimport_batch LIMIT 1;
    EXCEPTION WHEN insufficient_privilege THEN
      v_private_read_denied:=true;
    END;
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    RAISE;
  END;
  IF NOT v_private_read_denied THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PRIVATE_LEDGER_READ_ACCEPTED';
  END IF;
  v_authorization:=public.red_authorize_reimport(
    repeat('1',64),repeat('2',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,
    'daa-1939-v50-production-write-v1',v_profile_sha,
    '{"person_creates":0,"source_evidence":1}'::jsonb,v_elements,
    '15300000-0000-4000-8000-000000000008',clock_timestamp()+interval '5 minutes'
  );
  v_batch:=public.red_begin_reimport(v_authorization,repeat('1',64),repeat('2',64));
  v_result:=public.red_reimport_batch_result(v_authorization,v_batch);
  IF v_result IS DISTINCT FROM jsonb_build_object('batch_id',v_batch,'status','open','replayed',false,'person_id_map','{}'::jsonb) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_OPEN_BATCH_RESULT_INVALID: %',v_result;
  END IF;
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
    repeat('1',64),repeat('2',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,
    'daa-1939-v50-production-write-v1',v_profile_sha,
    '{"person_creates":0,"source_evidence":1}'::jsonb,v_elements,
    '15300000-0000-4000-8000-000000000009',clock_timestamp()+interval '5 minutes'
  );
  v_replay_batch:=public.red_begin_reimport(v_replay_authorization,repeat('1',64),repeat('2',64));
  IF v_replay_batch IS DISTINCT FROM v_batch
     OR (SELECT count(*) FROM private.reimport_batch)<>v_batches_before
     OR (SELECT status FROM private.reimport_authorization WHERE id=v_replay_authorization)<>'consumed' THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_FINALIZED_REPLAY_INVALID';
  END IF;
  v_result:=public.red_reimport_batch_result(v_replay_authorization,v_replay_batch);
  IF v_result IS DISTINCT FROM jsonb_build_object('batch_id',v_batch,'status','finalized','replayed',true,'person_id_map','{}'::jsonb) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_FINALIZED_BATCH_RESULT_INVALID: %',v_result;
  END IF;
END $migration_writer_behavior$;

-- Task 10: source-scoped profiles may share neither an incompatible extraction
-- run nor an incompatible rendition.  A rejected reuse rolls back its attempt
-- before it can add evidence rows or events.
DO $same_source_profile_provenance$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000001';
  v_run_config jsonb; v_rendition_config jsonb; v_hash text; v_auth uuid; v_batch uuid;
  v_payload jsonb; v_error text; v_runs bigint; v_renditions bigint; v_records bigint;
  v_observations bigint; v_events bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_payload:=jsonb_build_object('disposition','retain_source_only','source_record_key','task10-same-source-record',
    'source_span',jsonb_build_object('char_from',0,'char_to',20),
    'page_evidence',jsonb_build_object('page_from',1,'page_to',1),
    'verbatim_text','Task 10 same source','rendition_content_sha256',repeat('1',64));
  SELECT count(*) INTO v_runs FROM private.extraction_run;
  SELECT count(*) INTO v_renditions FROM private.source_rendition;
  SELECT count(*) INTO v_records FROM private.source_record;
  SELECT count(*) INTO v_observations FROM private.source_observation;
  SELECT count(*) INTO v_events FROM private.reimport_event;
  v_run_config:=jsonb_build_object('run_key_prefix','reimport-1939-v50:',
    'schema_version','task10-incompatible-run','extractor_version','production-writer-v1',
    'rendition_key','daa-1939-calamari-r6-clean','rendition_kind','ocr_text',
    'rendition_metadata',jsonb_build_object('edition','1939'),
    'observation_extraction_method','human_reviewed_1939_v50',
    'citation_label_template','DAA 1939 side {page_from}');
  v_hash:=private.reimport_canonical_json_sha256(v_run_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'task10-incompatible-run','production-writer-v1',v_hash,v_run_config);
  v_auth:=public.red_authorize_reimport(repeat('1',64),repeat('2',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,'task10-incompatible-run',v_hash,
    '{"person_creates":0,"source_evidence":1}'::jsonb,jsonb_build_object('source-evidence:task10-run',v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_batch:=public.red_begin_reimport(v_auth,repeat('1',64),repeat('2',64));
  BEGIN
    PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:task10-run',v_payload);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_SOURCE_EVIDENCE_INVALID'
     OR (SELECT count(*) FROM private.extraction_run)<>v_runs
     OR (SELECT count(*) FROM private.source_rendition)<>v_renditions
     OR (SELECT count(*) FROM private.source_record)<>v_records
     OR (SELECT count(*) FROM private.source_observation)<>v_observations
     OR (SELECT count(*) FROM private.reimport_event)<>v_events THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_SAME_SOURCE_RUN_REUSE_ACCEPTED: %',v_error;
  END IF;
  v_error:=NULL;
  v_rendition_config:=jsonb_build_object('run_key_prefix','task10-rendition:',
    'schema_version','1939-v50-production-write-manifest-v1','extractor_version','production-writer-v1',
    'rendition_key','daa-1939-calamari-r6-clean','rendition_kind','ocr_text',
    'rendition_metadata',jsonb_build_object('edition','task10-drift'),
    'observation_extraction_method','human_reviewed_1939_v50',
    'citation_label_template','DAA 1939 side {page_from}');
  v_hash:=private.reimport_canonical_json_sha256(v_rendition_config);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
  VALUES(3,'task10-incompatible-rendition','production-writer-v1',v_hash,v_rendition_config);
  v_auth:=public.red_authorize_reimport(repeat('3',64),repeat('4',64),jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,'task10-incompatible-rendition',v_hash,
    '{"person_creates":0,"source_evidence":1}'::jsonb,jsonb_build_object('source-evidence:task10-rendition',v_payload),gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_batch:=public.red_begin_reimport(v_auth,repeat('3',64),repeat('4',64));
  BEGIN
    PERFORM public.red_apply_reimport_source_evidence(v_batch,'source-evidence:task10-rendition',v_payload);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_RENDITION_DRIFT'
     OR (SELECT count(*) FROM private.extraction_run)<>v_runs
     OR (SELECT count(*) FROM private.source_rendition)<>v_renditions
     OR (SELECT count(*) FROM private.source_record)<>v_records
     OR (SELECT count(*) FROM private.source_observation)<>v_observations
     OR (SELECT count(*) FROM private.reimport_event)<>v_events THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_SAME_SOURCE_RENDITION_REUSE_ACCEPTED: %',v_error;
  END IF;
END $same_source_profile_provenance$;

CREATE FUNCTION pg_temp.task3_source_record_placement(
  p_source_id bigint,p_record_key text,p_fixture_id bigint,p_accepted boolean
) RETURNS uuid LANGUAGE plpgsql AS $task3_source_record_placement$
DECLARE
  v_run uuid:=gen_random_uuid(); v_record uuid; v_rendition uuid; v_occurrence uuid;
  v_observation uuid; v_placement uuid;
BEGIN
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug)
  VALUES(p_fixture_id,'Task 3 placement fixture','Task 3 placement fixture','task-3-placement-'||abs(p_fixture_id))
  ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label)
  VALUES(p_fixture_id,p_fixture_id,p_source_id,'stamtavle','Task 3 placement fixture') ON CONFLICT(id) DO NOTHING;
  INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order)
  VALUES(p_fixture_id,p_fixture_id,p_fixture_id,'A','Task 3 placement fixture',1) ON CONFLICT(id) DO NOTHING;
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES(v_run,p_source_id,'task-3-placement-'||abs(p_fixture_id),'fixture','fixture','fixture',repeat('d',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES(p_source_id,'task-3-placement-'||abs(p_fixture_id),'ocr_text',repeat('d',64),'{}');
  SELECT id INTO v_rendition FROM private.source_rendition
   WHERE source_id=p_source_id AND rendition_key='task-3-placement-'||abs(p_fixture_id);
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
  VALUES(p_source_id,p_record_key,'person',v_run) ON CONFLICT(source_id,record_key) DO NOTHING;
  SELECT id INTO v_record FROM private.source_record WHERE source_id=p_source_id AND record_key=p_record_key;
  INSERT INTO private.source_record_occurrence(rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES(v_rendition,'task-3-placement-'||abs(p_fixture_id),1,1,0,18,p_record_key,repeat('d',64),repeat('e',64),v_run)
  RETURNING id INTO v_occurrence;
  INSERT INTO private.source_record_anchor_event(occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
  VALUES(v_occurrence,v_record,'accepted',jsonb_build_object('fixture','task-3'),1,'15300000-0000-4000-8000-000000000001','Task 3 fixture');
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES(v_occurrence,'header',1,1,0,18,p_record_key,'clear','fixture',v_run) RETURNING id INTO v_observation;
  v_placement:=private.propose_source_record_placement(v_record,p_fixture_id,v_observation,jsonb_build_object('fixture','task-3'),'Task 3 fixture');
  IF p_accepted THEN
    PERFORM public.red_decide_source_record_placement(v_placement,1,'accepted',jsonb_build_object('fixture','task-3'));
  END IF;
  RETURN v_placement;
END $task3_source_record_placement$;

CREATE FUNCTION pg_temp.task3_assert_person_create_rejected(
  p_label text,p_authorized_payload jsonb,p_attempt_payload jsonb,p_expected_error text
) RETURNS void LANGUAGE plpgsql AS $task3_assert_person_create_rejected$
DECLARE
  v_auth uuid; v_batch uuid; v_error text; v_before_persons bigint; v_before_events bigint;
  v_manifest text:=encode(extensions.digest(convert_to(p_label,'UTF8'),'sha256'),'hex');
  v_preview text:=encode(extensions.digest(convert_to(p_label||':preview','UTF8'),'sha256'),'hex');
BEGIN
  SELECT count(*) INTO v_before_persons FROM public.person;
  SELECT count(*) INTO v_before_events FROM private.reimport_event;
  v_auth:=public.red_authorize_reimport(
    v_manifest,v_preview,jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,3,'daa-1939-v50-production-write-v1',
    (SELECT profile_sha256 FROM private.reimport_writer_profile WHERE source_id=3 AND profile_id='daa-1939-v50-production-write-v1'),
    '{"person_creates":1,"source_evidence":0}'::jsonb,jsonb_build_object('person-create:'||p_label,p_authorized_payload),
    gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  v_batch:=public.red_begin_reimport(v_auth,v_manifest,v_preview);
  BEGIN
    PERFORM public.red_apply_reimport_person_create(v_batch,'person-create:'||p_label,p_attempt_payload);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM p_expected_error
     OR (SELECT count(*) FROM public.person)<>v_before_persons
     OR (SELECT count(*) FROM private.reimport_event)<>v_before_events
     OR EXISTS(SELECT 1 FROM public.person_external_id WHERE source_id=3 AND record_key=p_attempt_payload->>'source_record_key')
     OR EXISTS(SELECT 1 FROM private.source_persona WHERE id=(p_attempt_payload->>'source_persona_id')::uuid)
     OR (p_attempt_payload->>'source_record_key' NOT IN ('writer-placement-good','writer-placement-nonaccepted','writer-placement-ambiguous')
         AND EXISTS(SELECT 1 FROM private.source_record WHERE source_id=3 AND record_key=p_attempt_payload->>'source_record_key')) THEN
    RAISE EXCEPTION 'REIMPORT_WRITER_PLACEMENT_NO_RESIDUE_INVALID: % error=%',p_label,v_error;
  END IF;
END $task3_assert_person_create_rejected$;

DO $placement_negative_no_residue$
DECLARE
  v_actor uuid:='15300000-0000-4000-8000-000000000001'; v_good uuid; v_foreign uuid;
  v_nonaccepted uuid; v_ambiguous_one uuid; v_ambiguous_two uuid; v_payload jsonb; v_variant jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_good:=pg_temp.task3_source_record_placement(3,'writer-placement-good',-153106,true);
  v_foreign:=pg_temp.task3_source_record_placement(4,'writer-placement-foreign',-153107,true);
  v_nonaccepted:=pg_temp.task3_source_record_placement(3,'writer-placement-nonaccepted',-153108,false);
  v_ambiguous_one:=pg_temp.task3_source_record_placement(3,'writer-placement-ambiguous',-153109,true);
  v_ambiguous_two:=pg_temp.task3_source_record_placement(3,'writer-placement-ambiguous',-153110,true);
  v_payload:=jsonb_build_object(
    'source_record_key','writer-placement-good','source_id',3,'source_span',jsonb_build_object('char_from',0,'char_to',18),
    'page_evidence',jsonb_build_object('page_from',1,'page_to',1),'verbatim_text','Task 3 placement payload',
    'rendition_content_sha256',repeat('1',64),'source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-good',
    'source_record_placement_id',v_good,'placement_role','principal_member',
    'placement_basis_sha256',repeat('2',64),'placement_review_sha256',repeat('3',64),'placement_decision_sha256',repeat('4',64),
    'name','Task 3 placement','narrative',jsonb_build_object('text','Task 3 placement narrative'));
  PERFORM pg_temp.task3_assert_person_create_rejected('missing-placement',v_payload-'source_record_placement_id',v_payload-'source_record_placement_id','REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=jsonb_set(v_payload,'{source_record_key}','"writer-placement-foreign"')||jsonb_build_object('source_record_placement_id',v_foreign,'source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-foreign');
  PERFORM pg_temp.task3_assert_person_create_rejected('foreign-placement',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=jsonb_set(v_payload,'{source_record_key}','"writer-placement-wrong"')||jsonb_build_object('source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-wrong');
  PERFORM pg_temp.task3_assert_person_create_rejected('wrong-record',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=jsonb_set(v_payload,'{source_record_key}','"writer-placement-nonaccepted"')||jsonb_build_object('source_record_placement_id',v_nonaccepted,'source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-nonaccepted');
  PERFORM pg_temp.task3_assert_person_create_rejected('nonaccepted-placement',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=jsonb_set(v_payload,'{source_record_key}','"writer-placement-ambiguous"')||jsonb_build_object('source_record_placement_id',v_ambiguous_one,'source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-ambiguous');
  PERFORM pg_temp.task3_assert_person_create_rejected('ambiguous-placement',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=v_payload||jsonb_build_object('source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-role','placement_role','child');
  PERFORM pg_temp.task3_assert_person_create_rejected('invalid-role',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=v_payload||jsonb_build_object('source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-basis','placement_basis_sha256','invalid');
  PERFORM pg_temp.task3_assert_person_create_rejected('invalid-basis-hash',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=v_payload||jsonb_build_object('source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-review','placement_review_sha256','invalid');
  PERFORM pg_temp.task3_assert_person_create_rejected('invalid-review-hash',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=v_payload||jsonb_build_object('source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-decision','placement_decision_sha256','invalid');
  PERFORM pg_temp.task3_assert_person_create_rejected('invalid-decision-hash',v_variant,v_variant,'REIMPORT_WRITER_PERSON_CREATE_INVALID');
  v_variant:=v_payload||jsonb_build_object('source_persona_id',gen_random_uuid(),'persona_key','task-3-placement-replay');
  PERFORM pg_temp.task3_assert_person_create_rejected('replay-tamper',v_variant,v_variant||jsonb_build_object('name','tampered'),'REIMPORT_WRITER_ELEMENT_NOT_AUTHORIZED');
END $placement_negative_no_residue$;

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
