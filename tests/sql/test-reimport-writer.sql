\set ON_ERROR_STOP on

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
         AND ARRAY(SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
         AND ARRAY(SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.confrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_constraint constraint_row
       WHERE conrelid='private.reimport_batch'::regclass AND contype='f'
         AND confrelid='private.reimport_writer_profile'::regclass
         AND ARRAY(SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
         AND ARRAY(SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.confrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['source_id','profile_id','profile_sha256']
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_constraint constraint_row
       WHERE conrelid='private.reimport_batch'::regclass AND contype='f'
         AND confrelid='private.reimport_authorization'::regclass
         AND ARRAY(SELECT attribute.attname FROM unnest(constraint_row.conkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.conrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['authorization_id','source_id','profile_id','profile_sha256']
         AND ARRAY(SELECT attribute.attname FROM unnest(constraint_row.confkey) WITH ORDINALITY key_column(attnum,ordinality) JOIN pg_attribute attribute ON attribute.attrelid=constraint_row.confrelid AND attribute.attnum=key_column.attnum ORDER BY key_column.ordinality)=ARRAY['id','source_id','profile_id','profile_sha256']
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
DECLARE v_error text; v_before jsonb;
BEGIN
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
  v_error:=NULL;
  BEGIN UPDATE private.reimport_event SET operation='tampered'; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_EVENT_MUTATION_ACCEPTED'; END IF;
  v_error:=NULL;
  BEGIN DELETE FROM private.reimport_name_completion_result; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS NULL THEN RAISE EXCEPTION 'REIMPORT_WRITER_RESULT_DELETE_ACCEPTED'; END IF;
END $profile_identity$;
