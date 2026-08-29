-- Task 1 contract for issue #152. Run after bootstrap, schema.sql and db-rls.sql
-- on a disposable PostgreSQL 17 database.

BEGIN;

DO $narrative_record_contract_structure$
DECLARE
  v_actual text[];
  v_default text;
  v_missing text;
  v_role text;
  v_table text;
  v_privilege text;
BEGIN
  IF to_regprocedure('public.narrative_record_contract_version()') IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_VERSION_FUNCTION_MISSING';
  END IF;
  IF public.narrative_record_contract_version() <> 1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_VERSION_EXPECTED_1';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema='private'
       AND table_name='source_record'
       AND column_name='public_ref'
       AND data_type='uuid'
       AND is_nullable='NO'
  ) THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_COLUMN_MISSING_OR_INVALID';
  END IF;
  SELECT pg_get_expr(d.adbin,d.adrelid)
    INTO v_default
    FROM pg_attribute a
    JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid='private.source_record'::regclass
     AND a.attname='public_ref';
  IF replace(v_default,'pg_catalog.','') IS DISTINCT FROM 'gen_random_uuid()' THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_DEFAULT_INVALID: %',v_default;
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint c
     WHERE c.conrelid='private.source_record'::regclass
       AND c.conname='source_record_public_ref_key'
       AND c.contype='u'
       AND c.conkey=ARRAY[
         (SELECT attnum FROM pg_attribute
           WHERE attrelid='private.source_record'::regclass
             AND attname='public_ref')::smallint
       ]
  ) THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_UNIQUE_CONSTRAINT_MISSING';
  END IF;

  IF to_regclass('private.narrative_publication_event') IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TABLE_MISSING';
  END IF;
  IF to_regclass('private.narrative_legacy_publication') IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_TABLE_MISSING';
  END IF;

  SELECT array_agg(a.attname ORDER BY a.attnum)
    INTO v_actual
    FROM pg_attribute a
   WHERE a.attrelid='private.narrative_publication_event'::regclass
     AND a.attnum>0 AND NOT a.attisdropped;
  IF v_actual IS DISTINCT FROM ARRAY[
    'id','change_set_id','stream_ref','stream_version','event_type',
    'binding_id','narrative_id','source_id','source_record_id',
    'legacy_publication_ref','decision_basis','before_state','after_state',
    'before_state_sha256','after_state_sha256','reversed_event_id','decided_by',
    'decided_by_name','created_at'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_COLUMNS_INVALID: %',v_actual;
  END IF;
  SELECT array_agg(a.atttypid::regtype::text ORDER BY a.attnum)
    INTO v_actual
    FROM pg_attribute a
   WHERE a.attrelid='private.narrative_publication_event'::regclass
     AND a.attnum>0 AND NOT a.attisdropped;
  IF v_actual IS DISTINCT FROM ARRAY[
    'uuid','bigint','uuid','integer','text','uuid','bigint','bigint','uuid','uuid',
    'text','jsonb','jsonb','text','text','uuid','uuid','text',
    'timestamp with time zone'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TYPES_INVALID: %',v_actual;
  END IF;

  SELECT array_agg(a.attname ORDER BY a.attnum)
    INTO v_actual
    FROM pg_attribute a
   WHERE a.attrelid='private.narrative_legacy_publication'::regclass
     AND a.attnum>0 AND NOT a.attisdropped;
  IF v_actual IS DISTINCT FROM ARRAY[
    'legacy_publication_ref','narrative_id','source_id','baseline_state',
    'baseline_sha256','status','latest_event_id','created_at'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_COLUMNS_INVALID: %',v_actual;
  END IF;
  SELECT array_agg(a.atttypid::regtype::text ORDER BY a.attnum)
    INTO v_actual
    FROM pg_attribute a
   WHERE a.attrelid='private.narrative_legacy_publication'::regclass
     AND a.attnum>0 AND NOT a.attisdropped;
  IF v_actual IS DISTINCT FROM ARRAY[
    'uuid','bigint','bigint','jsonb','text','text','uuid','timestamp with time zone'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_TYPES_INVALID: %',v_actual;
  END IF;

  SELECT string_agg(e.name,', ' ORDER BY e.name)
    INTO v_missing
    FROM (VALUES
      ('narrative_publication_event_pkey','p'),
      ('narrative_publication_event_stream_version_key','u'),
      ('narrative_publication_event_event_type_check','c'),
      ('narrative_publication_event_stream_version_check','c'),
      ('narrative_publication_event_decision_basis_check','c'),
      ('narrative_publication_event_decided_by_name_check','c'),
      ('narrative_publication_event_before_state_object_check','c'),
      ('narrative_publication_event_after_state_object_check','c'),
      ('narrative_publication_event_before_state_sha256_check','c'),
      ('narrative_publication_event_after_state_sha256_check','c'),
      ('narrative_publication_event_target_check','c'),
      ('narrative_publication_event_reversal_reference_check','c'),
      ('narrative_publication_event_stream_target_check','c'),
      ('narrative_publication_event_change_set_id_fkey','f'),
      ('narrative_publication_event_binding_id_fkey','f'),
      ('narrative_publication_event_narrative_id_fkey','f'),
      ('narrative_publication_event_source_id_fkey','f'),
      ('narrative_publication_event_source_record_id_fkey','f'),
      ('narrative_publication_event_legacy_publication_ref_fkey','f'),
      ('narrative_publication_event_reversed_event_id_fkey','f')
    ) AS e(name,kind)
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_constraint c
      WHERE c.conrelid='private.narrative_publication_event'::regclass
        AND c.conname=e.name AND c.contype=e.kind::"char"
   );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_CONSTRAINTS_MISSING: %',v_missing;
  END IF;

  SELECT array_agg(m.value[1] ORDER BY m.value[1])
    INTO v_actual
    FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(
      pg_get_constraintdef(c.oid),'\x27([^\x27]+)\x27','g'
    ) AS m(value)
   WHERE c.conrelid='private.narrative_publication_event'::regclass
     AND c.conname='narrative_publication_event_event_type_check';
  IF v_actual IS DISTINCT FROM ARRAY[
    'baseline','draft_created','draft_discarded','draft_updated','legacy_migrated',
    'legacy_withdrawn','published','published_revision','revalidated','reversal','withdrawn'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_TYPES_CHECK_INVALID: %',v_actual;
  END IF;

  SELECT string_agg(e.name,', ' ORDER BY e.name)
    INTO v_missing
    FROM (VALUES
      ('narrative_publication_event_change_set_id_fkey','change_set_id','public.change_set','id'),
      ('narrative_publication_event_binding_id_fkey','binding_id','private.narrative_record_publication','id'),
      ('narrative_publication_event_narrative_id_fkey','narrative_id','public.narrative','id'),
      ('narrative_publication_event_source_id_fkey','source_id','public.source','id'),
      ('narrative_publication_event_source_record_id_fkey','source_record_id','private.source_record','id'),
      ('narrative_publication_event_legacy_publication_ref_fkey','legacy_publication_ref','private.narrative_legacy_publication','legacy_publication_ref'),
      ('narrative_publication_event_reversed_event_id_fkey','reversed_event_id','private.narrative_publication_event','id')
    ) AS e(name,local_col,foreign_table,foreign_col)
   WHERE NOT EXISTS (
     SELECT 1
       FROM pg_constraint c
      WHERE c.conrelid='private.narrative_publication_event'::regclass
        AND c.conname=e.name
        AND c.contype='f'
        AND c.confrelid=e.foreign_table::regclass
        AND c.conkey=ARRAY[(
          SELECT attnum FROM pg_attribute
           WHERE attrelid='private.narrative_publication_event'::regclass
             AND attname=e.local_col
        )]::smallint[]
        AND c.confkey=ARRAY[(
          SELECT attnum FROM pg_attribute
           WHERE attrelid=e.foreign_table::regclass
             AND attname=e.foreign_col
        )]::smallint[]
   );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_FOREIGN_KEYS_INVALID: %',v_missing;
  END IF;

  SELECT string_agg(e.name,', ' ORDER BY e.name)
    INTO v_missing
    FROM (VALUES
      ('narrative_legacy_publication_pkey','p'),
      ('narrative_legacy_publication_narrative_id_key','u'),
      ('narrative_legacy_publication_status_check','c'),
      ('narrative_legacy_publication_baseline_state_object_check','c'),
      ('narrative_legacy_publication_baseline_sha256_check','c'),
      ('narrative_legacy_publication_narrative_id_fkey','f'),
      ('narrative_legacy_publication_source_id_fkey','f'),
      ('narrative_legacy_publication_latest_event_id_fkey','f')
    ) AS e(name,kind)
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_constraint c
      WHERE c.conrelid='private.narrative_legacy_publication'::regclass
        AND c.conname=e.name AND c.contype=e.kind::"char"
   );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_CONSTRAINTS_MISSING: %',v_missing;
  END IF;

  SELECT array_agg(m.value[1] ORDER BY m.value[1])
    INTO v_actual
    FROM pg_constraint c
    CROSS JOIN LATERAL regexp_matches(
      pg_get_constraintdef(c.oid),'\x27([^\x27]+)\x27','g'
    ) AS m(value)
   WHERE c.conrelid='private.narrative_legacy_publication'::regclass
     AND c.conname='narrative_legacy_publication_status_check';
  IF v_actual IS DISTINCT FROM ARRAY[
    'grandfathered_publication','migrated','withdrawn'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_STATUS_CHECK_INVALID: %',v_actual;
  END IF;

  SELECT string_agg(e.name,', ' ORDER BY e.name)
    INTO v_missing
    FROM (VALUES
      ('narrative_legacy_publication_narrative_id_fkey','narrative_id','public.narrative','id'),
      ('narrative_legacy_publication_source_id_fkey','source_id','public.source','id'),
      ('narrative_legacy_publication_latest_event_id_fkey','latest_event_id','private.narrative_publication_event','id')
    ) AS e(name,local_col,foreign_table,foreign_col)
   WHERE NOT EXISTS (
     SELECT 1
       FROM pg_constraint c
      WHERE c.conrelid='private.narrative_legacy_publication'::regclass
        AND c.conname=e.name
        AND c.contype='f'
        AND c.confrelid=e.foreign_table::regclass
        AND c.conkey=ARRAY[(
          SELECT attnum FROM pg_attribute
           WHERE attrelid='private.narrative_legacy_publication'::regclass
             AND attname=e.local_col
        )]::smallint[]
        AND c.confkey=ARRAY[(
          SELECT attnum FROM pg_attribute
           WHERE attrelid=e.foreign_table::regclass
             AND attname=e.foreign_col
        )]::smallint[]
   );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_FOREIGN_KEYS_INVALID: %',v_missing;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='private'
       AND table_name='narrative_publication_event'
       AND column_name IN (
         'id','change_set_id','stream_ref','stream_version','event_type','narrative_id',
         'source_id','decision_basis','before_state','after_state',
         'before_state_sha256','after_state_sha256','decided_by_name','created_at'
       )
       AND is_nullable<>'NO'
  ) OR (
    SELECT count(*) FROM information_schema.columns
     WHERE table_schema='private'
       AND table_name='narrative_publication_event'
       AND column_name IN (
         'id','change_set_id','stream_ref','stream_version','event_type','narrative_id',
         'source_id','decision_basis','before_state','after_state',
         'before_state_sha256','after_state_sha256','decided_by_name','created_at'
       )
       AND is_nullable='NO'
  ) <> 14 THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_REQUIRED_NULLABILITY_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='private'
       AND table_name='narrative_legacy_publication'
       AND column_name IN (
         'legacy_publication_ref','narrative_id','source_id','baseline_state',
         'baseline_sha256','status','created_at'
       )
       AND is_nullable<>'NO'
  ) OR (
    SELECT count(*) FROM information_schema.columns
     WHERE table_schema='private'
       AND table_name='narrative_legacy_publication'
       AND column_name IN (
         'legacy_publication_ref','narrative_id','source_id','baseline_state',
         'baseline_sha256','status','created_at'
       )
       AND is_nullable='NO'
  ) <> 7 THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_REQUIRED_NULLABILITY_INVALID';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'private.narrative_publication_event',
    'private.narrative_legacy_publication'
  ] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table::regclass) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_RLS_DISABLED: %',v_table;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=v_table::regclass) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_RLS_NOT_DENY_ALL: %',v_table;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
        IF has_table_privilege(v_role,v_table,v_privilege) THEN
          RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_TABLE_PRIVILEGE_LEAK: % % %',
            v_role,v_privilege,v_table;
        END IF;
      END LOOP;
    END LOOP;
    IF EXISTS (
      SELECT 1
        FROM pg_class relation
        CROSS JOIN LATERAL aclexplode(
          coalesce(relation.relacl,acldefault('r',relation.relowner))
        ) acl
       WHERE relation.oid=v_table::regclass
         AND acl.grantee=0
         AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PRIVATE_TABLE_PUBLIC_PRIVILEGE_LEAK: %',v_table;
    END IF;
  END LOOP;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF NOT has_function_privilege(
      v_role,'public.narrative_record_contract_version()'::regprocedure,'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_VERSION_EXECUTE_MISSING: %',v_role;
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1
      FROM pg_proc function
      CROSS JOIN LATERAL aclexplode(
        coalesce(function.proacl,acldefault('f',function.proowner))
      ) acl
     WHERE function.oid='public.narrative_record_contract_version()'::regprocedure
       AND acl.grantee=0
       AND acl.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONTRACT_VERSION_PUBLIC_EXECUTE_LEAK';
  END IF;

  RAISE NOTICE 'OK: narrative record structural contract';
END
$narrative_record_contract_structure$;

DO $narrative_record_contract_behavior$
DECLARE
  v_actor uuid := '15200000-0000-0000-0000-000000000001';
  v_run uuid := '15200000-0000-0000-0000-000000000002';
  v_record uuid := '15200000-0000-0000-0000-000000000003';
  v_public_ref uuid;
  v_binding uuid := '15200000-0000-0000-0000-000000000004';
  v_record_event uuid := '15200000-0000-0000-0000-000000000005';
  v_legacy_ref uuid := '15200000-0000-0000-0000-000000000006';
  v_legacy_event uuid := '15200000-0000-0000-0000-000000000007';
  v_bad_legacy_ref uuid := '15200000-0000-0000-0000-000000000008';
  v_error text;
  v_inserted_narrative bigint;
  v_narrative_sequence text;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES (v_actor,'narrative-record-contract@test.invalid');
  INSERT INTO public.profiles(id,rolle,email)
  VALUES (v_actor,'redaktion','narrative-record-contract@test.invalid');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  IF EXISTS (SELECT 1 FROM private.narrative_publication_event)
     OR EXISTS (SELECT 1 FROM private.narrative_legacy_publication) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ADDITIVE_SCHEMA_CREATED_BASELINES';
  END IF;

  INSERT INTO public.source(id,slags,titel)
  VALUES
    (-91520001,'DAA-udgave','Narrative record contract fixture'),
    (-91520002,'DAA-udgave','Narrative record mismatch fixture');
  INSERT INTO private.extraction_run(
    id,source_id,run_key,schema_version,extractor_version,profile_version,
    input_sha256,manifest
  ) VALUES (
    v_run,-91520001,'narrative-record-contract','1','test','test',repeat('1',64),'{}'
  );
  INSERT INTO private.source_record(
    id,source_id,record_key,record_kind,created_run_id
  ) VALUES (
    v_record,-91520001,'task-1-record','person',v_run
  ) RETURNING public_ref INTO v_public_ref;
  IF v_public_ref IS NULL THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_DEFAULT_RETURNED_NULL';
  END IF;

  v_error:=NULL;
  BEGIN
    UPDATE private.source_record
       SET public_ref=gen_random_uuid()
     WHERE id=v_record;
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_UPDATE_NOT_REJECTED: %',v_error;
  END IF;
  IF (SELECT public_ref FROM private.source_record WHERE id=v_record)
       IS DISTINCT FROM v_public_ref THEN
    RAISE EXCEPTION 'SOURCE_RECORD_PUBLIC_REF_CHANGED_AFTER_REJECTION';
  END IF;

  INSERT INTO public.person(id,levende,privat,visning_navn)
  VALUES
    (-91520001,false,false,'Narrative record fixture'),
    (-91520002,false,false,'Narrative legacy fixture'),
    (-91520003,false,false,'Narrative identity-default fixture'),
    (-91520004,false,false,'Narrative mismatch fixture');
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat)
  VALUES
    (-91520001,'person',-91520001,-91520001,'Record text',false),
    (-91520002,'person',-91520002,-91520001,'Legacy text',false),
    (-91520004,'person',-91520004,-91520001,'Mismatch text',false);
  INSERT INTO private.narrative_record_publication(
    id,narrative_id,source_record_id,record_label,citation_label,status
  ) VALUES (
    v_binding,-91520001,v_record,'Task 1 record','DAA test, p. 1','draft'
  );
  INSERT INTO public.change_set(id,actor_id,actor_navn,actor_rolle,operation,summary)
  VALUES (-91520001,v_actor,'Task 1','redaktion','task_1_contract','Task 1 contract');

  INSERT INTO private.narrative_legacy_publication(
    legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status
  ) VALUES (
    v_legacy_ref,-91520002,-91520001,
    jsonb_build_object('kind','legacy'),repeat('c',64),'grandfathered_publication'
  );

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_legacy_publication(
      legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status
    ) VALUES (
      v_bad_legacy_ref,-91520004,-91520002,jsonb_build_object('kind','mismatch'),
      repeat('f',64),'grandfathered_publication'
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_LEGACY_PUBLICATION_TARGET_IDENTITY_INVALID' THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_WRONG_SOURCE_ACCEPTED: %',v_error;
  END IF;

  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
    source_id,source_record_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name
  ) VALUES (
    v_record_event,-91520001,v_binding,1,'baseline',v_binding,-91520001,
    -91520001,v_record,'Task 1 baseline',jsonb_build_object('state','before'),
    jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),
    v_actor,'Task 1 actor'
  );

  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,legacy_publication_ref,
    narrative_id,source_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name
  ) VALUES (
    v_legacy_event,-91520001,v_legacy_ref,1,'baseline',v_legacy_ref,
    -91520002,-91520001,'Task 1 legacy baseline',jsonb_build_object('state','before'),
    jsonb_build_object('state','after'),repeat('d',64),repeat('e',64),
    v_actor,'Task 1 actor'
  );
  UPDATE private.narrative_legacy_publication
     SET latest_event_id=v_legacy_event
   WHERE legacy_publication_ref=v_legacy_ref;

  v_error:=NULL;
  BEGIN
    UPDATE private.narrative_legacy_publication
       SET baseline_state=jsonb_build_object('kind','changed')
     WHERE legacy_publication_ref=v_legacy_ref;
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_LEGACY_PUBLICATION_BASELINE_IMMUTABLE' THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_BASELINE_UPDATE_NOT_REJECTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    UPDATE private.narrative_legacy_publication
       SET latest_event_id=v_record_event
     WHERE legacy_publication_ref=v_legacy_ref;
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_LEGACY_PUBLICATION_LATEST_EVENT_INVALID' THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_WRONG_LATEST_EVENT_ACCEPTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    UPDATE private.narrative_publication_event
       SET decision_basis='changed'
     WHERE id=v_record_event;
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_UPDATE_NOT_REJECTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    DELETE FROM private.narrative_publication_event WHERE id=v_record_event;
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_DELETE_NOT_REJECTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      -91520001,v_binding,2,'draft_updated',v_binding,-91520002,-91520001,v_record,
      'wrong narrative identity',jsonb_build_object('state','before'),
      jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),'Task 1 actor'
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_EVENT_TARGET_IDENTITY_INVALID' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_WRONG_IDENTITY_ACCEPTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      -91520001,v_binding,3,'draft_updated',v_binding,-91520001,-91520001,v_record,
      'skipped version',jsonb_build_object('state','before'),
      jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),'Task 1 actor'
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_EVENT_STREAM_VERSION_INVALID' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_VERSION_GAP_ACCEPTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,reversed_event_id,decided_by_name
    ) VALUES (
      -91520001,v_binding,2,'reversal',v_binding,-91520001,-91520001,v_record,
      'cross-stream reversal',jsonb_build_object('state','before'),
      jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),v_legacy_event,
      'Task 1 actor'
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_PUBLICATION_REVERSAL_TARGET_INVALID' THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_CROSS_STREAM_REVERSAL_ACCEPTED: %',v_error;
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      -91520001,v_binding,2,'not_an_event',v_binding,-91520001,-91520001,v_record,
      'invalid type',jsonb_build_object('state','before'),jsonb_build_object('state','after'),
      repeat('a',64),repeat('b',64),'Task 1 actor'
    );
  EXCEPTION WHEN check_violation THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_INVALID_TYPE_ACCEPTED';
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,legacy_publication_ref,decision_basis,
      before_state,after_state,before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      -91520001,v_binding,2,'draft_updated',v_binding,-91520001,-91520001,v_record,
      v_legacy_ref,'both targets',jsonb_build_object('state','before'),
      jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),'Task 1 actor'
    );
  EXCEPTION WHEN check_violation THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_BOTH_TARGETS_ACCEPTED';
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      -91520001,v_binding,2,'draft_updated',v_binding,-91520001,-91520001,v_record,
      'bad hash',jsonb_build_object('state','before'),jsonb_build_object('state','after'),
      'ABC',repeat('b',64),'Task 1 actor'
    );
  EXCEPTION WHEN check_violation THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_INVALID_HASH_ACCEPTED';
  END IF;

  v_error:=NULL;
  BEGIN
    INSERT INTO private.narrative_publication_event(
      change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,
      before_state_sha256,after_state_sha256,decided_by_name
    ) VALUES (
      -91520001,v_binding,2,'reversal',v_binding,-91520001,-91520001,v_record,
      'missing reverse target',jsonb_build_object('state','before'),
      jsonb_build_object('state','after'),repeat('a',64),repeat('b',64),'Task 1 actor'
    );
  EXCEPTION WHEN check_violation THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_REVERSAL_WITHOUT_TARGET_ACCEPTED';
  END IF;

  v_narrative_sequence:=pg_get_serial_sequence('public.narrative','id');
  PERFORM setval(v_narrative_sequence,915200001,false);
  PERFORM set_config('app.change_set_id','',true);
  v_inserted_narrative:=public.red_upsert_narrativ(
    'person',-91520003,'Identity-default text',false,-91520001,'1'
  );
  IF v_inserted_narrative<>915200001 THEN
    RAISE EXCEPTION 'RED_UPSERT_NARRATIV_DID_NOT_USE_IDENTITY_DEFAULT: %',
      v_inserted_narrative;
  END IF;

  IF (SELECT count(*) FROM private.narrative_publication_event)<>2 THEN
    RAISE EXCEPTION 'NARRATIVE_PUBLICATION_EVENT_REJECTED_MUTATION_CHANGED_ROWS';
  END IF;
  RAISE NOTICE 'OK: narrative record behavioral contract';
END
$narrative_record_contract_behavior$;

DO $narrative_record_task2_structure$
DECLARE
  v_signature text;
  v_expected_result text;
  v_actual_result text;
  v_role text;
  v_definition text;
  v_token text;
  v_position integer;
  v_previous_position integer;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'private.narrative_record_labels(uuid)',
    'private.narrative_publication_state(bigint,bigint,text)',
    'private.narrative_record_state(bigint,bigint,text,boolean)',
    'private.narrative_legacy_publication_state(uuid)',
    'private.narrative_legacy_state(uuid,boolean)',
    'public.red_person_narrative_records(bigint)',
    'public.red_person_narrative_publication_history(bigint)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_FUNCTION_MISSING: %',v_signature;
    END IF;
  END LOOP;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.narrative_record_publication_record_state_idx',
    'private.source_record_anchor_event_record_state_idx',
    'private.source_record_placement_record_state_idx',
    'private.source_persona_placement_record_state_idx',
    'private.source_persona_identity_person_state_idx',
    'private.source_record_revision_event_successor_state_idx'
  ] LOOP
    IF to_regclass(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_INDEX_MISSING: %',v_signature;
    END IF;
  END LOOP;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.narrative_record_labels(uuid)',
    'private.narrative_publication_state(bigint,bigint,text)',
    'private.narrative_record_state(bigint,bigint,text,boolean)',
    'private.narrative_legacy_publication_state(uuid)',
    'private.narrative_legacy_state(uuid,boolean)'
  ] LOOP
    SELECT pg_get_function_result(v_signature::regprocedure)
      INTO v_actual_result;
    IF v_actual_result IS DISTINCT FROM 'jsonb' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_PRIVATE_RESULT_INVALID: % %',
        v_signature,v_actual_result;
    END IF;
  END LOOP;

  v_expected_result := 'TABLE(person_id bigint, source_id bigint, source_year integer, source_label text, provenance_kind text, record_key text, source_record_ref uuid, legacy_publication_ref uuid, record_order integer, record_label text, citation_label text, narrative_id bigint, narrative_text text, narrative_private boolean, narrative_side text, publication_status text, text_editable boolean, allowed_actions jsonb, withdrawn_history jsonb, latest_event_version integer, published_text_sha256 text, eligibility_status text, blocking_reason text, state_sha256 text)';
  SELECT pg_get_function_result(
    'public.red_person_narrative_records(bigint)'::regprocedure
  ) INTO v_actual_result;
  IF v_actual_result IS DISTINCT FROM v_expected_result THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_RESULT_INVALID: %',v_actual_result;
  END IF;

  v_expected_result := 'TABLE(event_id uuid, change_set_id bigint, stream_version integer, event_type text, source_record_ref uuid, legacy_publication_ref uuid, before_state_sha256 text, after_state_sha256 text, before_text text, after_text text, decided_by_name text, created_at timestamp with time zone, can_reverse boolean, blocking_reason text)';
  SELECT pg_get_function_result(
    'public.red_person_narrative_publication_history(bigint)'::regprocedure
  ) INTO v_actual_result;
  IF v_actual_result IS DISTINCT FROM v_expected_result THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_RESULT_INVALID: %',v_actual_result;
  END IF;

  IF (
    SELECT array_agg(
      concat_ws(':',ordinal_position,parameter_mode,parameter_name,data_type)
      ORDER BY ordinal_position
    )
      FROM information_schema.parameters
     WHERE specific_schema='public'
       AND specific_name LIKE 'red_person_narrative_records_%'
  ) IS DISTINCT FROM ARRAY[
    '1:IN:p_person_id:bigint',
    '2:OUT:person_id:bigint','3:OUT:source_id:bigint',
    '4:OUT:source_year:integer','5:OUT:source_label:text',
    '6:OUT:provenance_kind:text','7:OUT:record_key:text',
    '8:OUT:source_record_ref:uuid','9:OUT:legacy_publication_ref:uuid',
    '10:OUT:record_order:integer','11:OUT:record_label:text',
    '12:OUT:citation_label:text','13:OUT:narrative_id:bigint',
    '14:OUT:narrative_text:text','15:OUT:narrative_private:boolean',
    '16:OUT:narrative_side:text','17:OUT:publication_status:text',
    '18:OUT:text_editable:boolean','19:OUT:allowed_actions:jsonb',
    '20:OUT:withdrawn_history:jsonb','21:OUT:latest_event_version:integer',
    '22:OUT:published_text_sha256:text','23:OUT:eligibility_status:text',
    '24:OUT:blocking_reason:text','25:OUT:state_sha256:text'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_PARAMETERS_INVALID';
  END IF;

  IF (
    SELECT array_agg(
      concat_ws(':',ordinal_position,parameter_mode,parameter_name,data_type)
      ORDER BY ordinal_position
    )
      FROM information_schema.parameters
     WHERE specific_schema='public'
       AND specific_name LIKE 'red_person_narrative_publication_history_%'
  ) IS DISTINCT FROM ARRAY[
    '1:IN:p_person_id:bigint',
    '2:OUT:event_id:uuid','3:OUT:change_set_id:bigint',
    '4:OUT:stream_version:integer','5:OUT:event_type:text',
    '6:OUT:source_record_ref:uuid','7:OUT:legacy_publication_ref:uuid',
    '8:OUT:before_state_sha256:text','9:OUT:after_state_sha256:text',
    '10:OUT:before_text:text','11:OUT:after_text:text',
    '12:OUT:decided_by_name:text','13:OUT:created_at:timestamp with time zone',
    '14:OUT:can_reverse:boolean','15:OUT:blocking_reason:text'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_PARAMETERS_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc function
     WHERE function.oid IN (
       'public.red_person_narrative_records(bigint)'::regprocedure,
       'public.red_person_narrative_publication_history(bigint)'::regprocedure
     )
       AND (
         NOT function.prosecdef
         OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_PUBLIC_FUNCTION_SECURITY_INVALID';
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon','service_role'] LOOP
    IF has_function_privilege(
      v_role,'public.red_person_narrative_records(bigint)'::regprocedure,'EXECUTE'
    ) OR has_function_privilege(
      v_role,
      'public.red_person_narrative_publication_history(bigint)'::regprocedure,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_PUBLIC_GRANT_INVALID: %',v_role;
    END IF;
  END LOOP;
  IF NOT has_function_privilege(
    'authenticated','public.red_person_narrative_records(bigint)'::regprocedure,'EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated',
    'public.red_person_narrative_publication_history(bigint)'::regprocedure,
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_AUTHENTICATED_GRANT_MISSING';
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(
      v_role,'private.narrative_record_labels(uuid)'::regprocedure,'EXECUTE'
    ) OR has_function_privilege(
      v_role,
      'private.narrative_publication_state(bigint,bigint,text)'::regprocedure,
      'EXECUTE'
    ) OR has_function_privilege(
      v_role,
      'private.narrative_record_state(bigint,bigint,text,boolean)'::regprocedure,
      'EXECUTE'
    ) OR has_function_privilege(
      v_role,
      'private.narrative_legacy_publication_state(uuid)'::regprocedure,
      'EXECUTE'
    ) OR has_function_privilege(
      v_role,'private.narrative_legacy_state(uuid,boolean)'::regprocedure,'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_PRIVATE_GRANT_INVALID: %',v_role;
    END IF;
  END LOOP;

  IF strpos(pg_get_functiondef(
       'private.narrative_publication_state(bigint,bigint,text)'::regprocedure
     ),'FOR UPDATE')<>0
     OR strpos(pg_get_functiondef(
       'private.narrative_legacy_publication_state(uuid)'::regprocedure
     ),'FOR UPDATE')<>0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_SEMANTIC_PROJECTOR_OWNS_LOCK';
  END IF;

  v_definition:=pg_get_functiondef(
    'private.narrative_record_state(bigint,bigint,text,boolean)'::regprocedure
  );
  v_previous_position:=0;
  FOREACH v_token IN ARRAY ARRAY[
    'PERFORM record.id FROM private.source_record record',
    'PERFORM binding.id FROM private.narrative_record_publication binding',
    'PERFORM event.id',
    'PERFORM narrative.id',
    'PERFORM anchor.id',
    'PERFORM occurrence.id',
    'PERFORM rendition.id',
    'PERFORM persona.id',
    'PERFORM placement.id FROM private.source_record_placement placement',
    'PERFORM decision.id',
    'PERFORM persona_placement.id',
    'PERFORM identity_state.source_persona_id',
    'PERFORM revision.id',
    'v_publication_state:=private.narrative_publication_state('
  ] LOOP
    v_position:=strpos(v_definition,v_token);
    IF v_position=0 OR v_position<=v_previous_position THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK2_LOCK_ORDER_INVALID: %',v_token;
    END IF;
    v_previous_position:=v_position;
  END LOOP;

  v_definition:=pg_get_functiondef(
    'private.narrative_legacy_state(uuid,boolean)'::regprocedure
  );
  v_previous_position:=0;
  FOREACH v_token IN ARRAY ARRAY[
    'PERFORM legacy.legacy_publication_ref',
    'PERFORM event.id',
    'PERFORM narrative.id',
    'v_publication_state:=private.narrative_legacy_publication_state('
  ] LOOP
    v_position:=strpos(v_definition,v_token);
    IF v_position=0 OR v_position<=v_previous_position THEN
      RAISE EXCEPTION 'NARRATIVE_LEGACY_TASK2_LOCK_ORDER_INVALID: %',v_token;
    END IF;
    v_previous_position:=v_position;
  END LOOP;

  RAISE NOTICE 'OK: narrative record Task 2 typed function contract';
END
$narrative_record_task2_structure$;

CREATE FUNCTION pg_temp.task2_seed_record(
  p_record_id uuid,
  p_record_key text,
  p_occurrence_id uuid,
  p_anchor_id uuid,
  p_observation_id uuid,
  p_page integer
) RETURNS void
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $task2_seed_record$
BEGIN
  INSERT INTO private.source_record(
    id,source_id,record_key,record_kind,created_run_id
  ) VALUES (
    p_record_id,-91521001,p_record_key,'person',
    '15210000-0000-0000-0000-000000000002'
  );
  INSERT INTO private.source_record_occurrence(
    id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
  ) VALUES (
    p_occurrence_id,'15210000-0000-0000-0000-000000000003',p_record_key,
    p_page,p_page,0,20,'Task 2 observation',
    'physical-'||p_record_key,'structural-'||p_record_key,
    '15210000-0000-0000-0000-000000000002'
  );
  IF p_anchor_id IS NOT NULL THEN
    INSERT INTO private.source_record_anchor_event(
      id,occurrence_id,source_record_id,decision_status,evidence,version,
      decided_by,decided_by_name
    ) VALUES (
      p_anchor_id,p_occurrence_id,p_record_id,'accepted',
      jsonb_build_object('basis','Task 2 accepted anchor'),1,
      '15200000-0000-0000-0000-000000000001','Task 2 actor'
    );
  END IF;
  INSERT INTO private.source_observation(
    id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
    verbatim_text,quality_status,extraction_method,extraction_run_id
  ) VALUES (
    p_observation_id,p_occurrence_id,'header',p_page,p_page,0,20,
    'Task 2 observation','clear','task2-test',
    '15210000-0000-0000-0000-000000000002'
  );
END
$task2_seed_record$;

CREATE FUNCTION pg_temp.task2_seed_identity(
  p_record_id uuid,
  p_observation_id uuid,
  p_persona_id uuid,
  p_mention_id uuid,
  p_record_placement_id uuid,
  p_persona_placement_id uuid,
  p_identity_event_id uuid,
  p_person_id bigint,
  p_placement_role text,
  p_scheme_entry_id bigint
) RETURNS void
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $task2_seed_identity$
BEGIN
  INSERT INTO private.source_persona(
    id,source_id,persona_key,created_run_id
  ) VALUES (
    p_persona_id,-91521001,'task2-persona-'||p_persona_id::text,
    '15210000-0000-0000-0000-000000000002'
  );
  INSERT INTO private.source_mention(
    id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id
  ) VALUES (
    p_mention_id,p_observation_id,'person_name',0,4,'Task',
    '15210000-0000-0000-0000-000000000002'
  );
  INSERT INTO private.source_persona_mention(
    persona_id,mention_id,mention_role,ordinal
  ) VALUES (p_persona_id,p_mention_id,'primary',1);
  INSERT INTO private.source_record_placement(
    id,source_record_id,scheme_entry_id,header_observation_id,initial_status
  ) VALUES (
    p_record_placement_id,p_record_id,p_scheme_entry_id,p_observation_id,'accepted'
  );
  INSERT INTO private.source_record_placement_decision(
    placement_id,version,decision_status,evidence,decision_origin,decided_by_name
  ) VALUES (
    p_record_placement_id,1,'accepted',jsonb_build_object('basis','Task 2'),
    'migration','Task 2 actor'
  );
  INSERT INTO private.source_persona_placement(
    id,source_persona_id,record_placement_id,placement_role,
    basis_observation_id,initial_status
  ) VALUES (
    p_persona_placement_id,p_persona_id,p_record_placement_id,p_placement_role,
    p_observation_id,'accepted'
  );
  INSERT INTO private.source_persona_placement_decision(
    placement_id,version,decision_status,evidence,decision_origin,decided_by_name
  ) VALUES (
    p_persona_placement_id,1,'accepted',jsonb_build_object('basis','Task 2'),
    'migration','Task 2 actor'
  );
  INSERT INTO private.source_persona_identity_event(
    id,source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at
  ) VALUES (
    p_identity_event_id,p_persona_id,p_person_id,'accepted',1,
    jsonb_build_object('basis','Task 2 identity'),
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:00:00+02'::timestamptz
  );
  INSERT INTO private.source_persona_identity(
    source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at
  ) VALUES (
    p_persona_id,p_person_id,'accepted',1,
    jsonb_build_object('basis','Task 2 identity'),
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:00:00+02'::timestamptz
  );
END
$task2_seed_identity$;

CREATE FUNCTION pg_temp.task2_seed_binding_event(
  p_person_id bigint,
  p_record_key text,
  p_binding_id uuid,
  p_narrative_id bigint,
  p_status text,
  p_event_id uuid,
  p_event_type text,
  p_text text,
  p_side text
) RETURNS void
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $task2_seed_binding_event$
DECLARE
  v_record_id uuid;
  v_state jsonb;
  v_hash text;
BEGIN
  SELECT id INTO STRICT v_record_id
    FROM private.source_record
   WHERE source_id=-91521001 AND record_key=p_record_key;
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,side,privat
  ) VALUES (
    p_narrative_id,'person',p_person_id,-91521001,p_text,p_side,false
  );
  INSERT INTO private.narrative_record_publication(
    id,narrative_id,source_record_id,record_label,citation_label,status,
    created_at,published_at
  ) VALUES (
    p_binding_id,p_narrative_id,v_record_id,
    'Existing '||p_record_key,'Existing citation '||p_record_key,p_status,
    '2026-08-29 12:10:00+02'::timestamptz,
    CASE WHEN p_status='published'
         THEN '2026-08-29 12:11:00+02'::timestamptz ELSE NULL END
  );
  v_state:=private.narrative_publication_state(
    p_person_id,-91521001,p_record_key
  );
  v_hash:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,binding_id,
    narrative_id,source_id,source_record_id,decision_basis,before_state,
    after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name,created_at
  ) VALUES (
    p_event_id,-91521001,p_binding_id,1,p_event_type,p_binding_id,
    p_narrative_id,-91521001,v_record_id,'Task 2 baseline',v_state,v_state,
    v_hash,v_hash,'15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:20:00+02'::timestamptz
  );
END
$task2_seed_binding_event$;

DO $narrative_record_task2_behavior$
DECLARE
  v_person_a bigint := -91521001;
  v_person_b bigint := -91521002;
  v_member uuid := '15210000-0000-0000-0000-000000000001';
  v_record_principal uuid := '15210000-0000-0000-0000-000000000101';
  v_record_co uuid := '15210000-0000-0000-0000-000000000110';
  v_record_empty uuid := '15210000-0000-0000-0000-000000000120';
  v_record_ambiguous uuid := '15210000-0000-0000-0000-000000000130';
  v_record_conflict uuid := '15210000-0000-0000-0000-000000000140';
  v_record_missing_anchor uuid := '15210000-0000-0000-0000-000000000150';
  v_record_withdrawn uuid := '15210000-0000-0000-0000-000000000160';
  v_record_draft uuid := '15210000-0000-0000-0000-000000000170';
  v_record_published uuid := '15210000-0000-0000-0000-000000000180';
  v_record_stale uuid := '15210000-0000-0000-0000-000000000190';
  v_record_neither uuid := '15210000-0000-0000-0000-000000000195';
  v_public_ref uuid;
  v_provenance jsonb;
  v_policy jsonb;
  v_expected_publication jsonb;
  v_expected_editor_input jsonb;
  v_expected_editor jsonb;
  v_expected_record_editor jsonb;
  v_actual jsonb;
  v_rows jsonb;
  v_history jsonb;
  v_state jsonb;
  v_hash text;
  v_timezone text;
  v_error text;
  v_sqlstate text;
  v_legacy_active uuid := '15210000-0000-0000-0000-000000000201';
  v_legacy_withdrawn uuid := '15210000-0000-0000-0000-000000000202';
  v_legacy_drift uuid := '15210000-0000-0000-0000-000000000203';
  v_legacy_active_state jsonb;
  v_legacy_withdrawn_state jsonb;
  v_legacy_drift_baseline jsonb;
  v_private_uuid text;
BEGIN
  INSERT INTO auth.users(id,email)
  VALUES (v_member,'narrative-record-task2-member@test.invalid');
  INSERT INTO public.profiles(id,rolle,email)
  VALUES (v_member,'medlem','narrative-record-task2-member@test.invalid');
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
  VALUES
    (v_person_a,false,false,false,'Task 2 person A'),
    (v_person_b,false,false,false,'Task 2 person B');
  INSERT INTO public.source(id,slags,titel,udgave,aar)
  VALUES (-91521001,'DAA-udgave','Task 2 source title','DAA Task 2',1939);
  INSERT INTO private.extraction_run(
    id,source_id,run_key,schema_version,extractor_version,profile_version,
    input_sha256,manifest
  ) VALUES (
    '15210000-0000-0000-0000-000000000002',-91521001,'task2-run','1',
    'task2-test','task2-test',repeat('1',64),'{}'
  );
  INSERT INTO private.source_rendition(
    id,source_id,rendition_key,rendition_kind,content_sha256,metadata
  ) VALUES (
    '15210000-0000-0000-0000-000000000003',-91521001,'task2-rendition',
    'text_layer',repeat('2',64),'{}'
  );
  INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug)
  VALUES (-91521001,'Task 2 slægt','Task 2 slægt','task-2-slaegt');
  INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label)
  VALUES (-91521001,-91521001,-91521001,'stamtavle','Task 2 scheme');
  INSERT INTO public.lineage_scheme_entry(
    id,scheme_id,slaegt_id,code,label,sort_order
  ) VALUES
    (-91521001,-91521001,-91521001,'A','Linje A',1),
    (-91521002,-91521001,-91521001,'B','Linje B',2);

  PERFORM pg_temp.task2_seed_record(
    v_record_principal,'accepted-principal',
    '15210000-0000-0000-0000-000000000301',
    '15210000-0000-0000-0000-000000000401',
    '15210000-0000-0000-0000-000000000501',2
  );
  INSERT INTO private.source_record_occurrence(
    id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
  ) VALUES (
    '15210000-0000-0000-0000-000000000302',
    '15210000-0000-0000-0000-000000000003','accepted-principal-page-10',
    10,10,0,20,'Task 2 observation','physical-accepted-principal-page-10',
    'structural-accepted-principal-page-10',
    '15210000-0000-0000-0000-000000000002'
  );
  INSERT INTO private.source_record_anchor_event(
    id,occurrence_id,source_record_id,decision_status,evidence,version,
    decided_by,decided_by_name
  ) VALUES (
    '15210000-0000-0000-0000-000000000402',
    '15210000-0000-0000-0000-000000000302',v_record_principal,'accepted',
    jsonb_build_object('basis','Task 2 second anchor'),1,
    '15200000-0000-0000-0000-000000000001','Task 2 actor'
  );
  PERFORM pg_temp.task2_seed_identity(
    v_record_principal,'15210000-0000-0000-0000-000000000501',
    '15210000-0000-0000-0000-000000000601',
    '15210000-0000-0000-0000-000000000701',
    '15210000-0000-0000-0000-000000000801',
    '15210000-0000-0000-0000-000000000901',
    '15210000-0000-0000-0000-000000001001',v_person_a,
    'principal_member',-91521001
  );

  PERFORM pg_temp.task2_seed_record(
    v_record_co,'accepted-co-principal',
    '15210000-0000-0000-0000-000000000310',
    '15210000-0000-0000-0000-000000000410',
    '15210000-0000-0000-0000-000000000510',3
  );
  PERFORM pg_temp.task2_seed_identity(
    v_record_co,'15210000-0000-0000-0000-000000000510',
    '15210000-0000-0000-0000-000000000610',
    '15210000-0000-0000-0000-000000000710',
    '15210000-0000-0000-0000-000000000810',
    '15210000-0000-0000-0000-000000000910',
    '15210000-0000-0000-0000-000000001010',v_person_a,
    'co_principal',-91521001
  );

  PERFORM pg_temp.task2_seed_record(
    v_record_empty,'empty-identity',
    '15210000-0000-0000-0000-000000000320',
    '15210000-0000-0000-0000-000000000420',
    '15210000-0000-0000-0000-000000000520',4
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_ambiguous,'ambiguous-identity',
    '15210000-0000-0000-0000-000000000330',
    '15210000-0000-0000-0000-000000000430',
    '15210000-0000-0000-0000-000000000530',5
  );
  PERFORM pg_temp.task2_seed_identity(
    v_record_ambiguous,'15210000-0000-0000-0000-000000000530',
    '15210000-0000-0000-0000-000000000630',
    '15210000-0000-0000-0000-000000000730',
    '15210000-0000-0000-0000-000000000830',
    '15210000-0000-0000-0000-000000000930',
    '15210000-0000-0000-0000-000000001030',v_person_a,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_identity(
    v_record_ambiguous,'15210000-0000-0000-0000-000000000530',
    '15210000-0000-0000-0000-000000000631',
    '15210000-0000-0000-0000-000000000731',
    '15210000-0000-0000-0000-000000000831',
    '15210000-0000-0000-0000-000000000931',
    '15210000-0000-0000-0000-000000001031',v_person_b,
    'co_principal',-91521002
  );

  PERFORM pg_temp.task2_seed_record(
    v_record_conflict,'conflicting-binding',
    '15210000-0000-0000-0000-000000000340',
    '15210000-0000-0000-0000-000000000440',
    '15210000-0000-0000-0000-000000000540',6
  );
  PERFORM pg_temp.task2_seed_identity(
    v_record_conflict,'15210000-0000-0000-0000-000000000540',
    '15210000-0000-0000-0000-000000000640',
    '15210000-0000-0000-0000-000000000740',
    '15210000-0000-0000-0000-000000000840',
    '15210000-0000-0000-0000-000000000940',
    '15210000-0000-0000-0000-000000001040',v_person_a,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_missing_anchor,'missing-anchor',
    '15210000-0000-0000-0000-000000000350',NULL,
    '15210000-0000-0000-0000-000000000550',12
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_withdrawn,'withdrawn-only',
    '15210000-0000-0000-0000-000000000360',
    '15210000-0000-0000-0000-000000000460',
    '15210000-0000-0000-0000-000000000560',7
  );
  PERFORM pg_temp.task2_seed_identity(
    v_record_withdrawn,'15210000-0000-0000-0000-000000000560',
    '15210000-0000-0000-0000-000000000660',
    '15210000-0000-0000-0000-000000000760',
    '15210000-0000-0000-0000-000000000860',
    '15210000-0000-0000-0000-000000000960',
    '15210000-0000-0000-0000-000000001060',v_person_a,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_draft,'active-draft',
    '15210000-0000-0000-0000-000000000370',
    '15210000-0000-0000-0000-000000000470',
    '15210000-0000-0000-0000-000000000570',8
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_published,'published',
    '15210000-0000-0000-0000-000000000380',
    '15210000-0000-0000-0000-000000000480',
    '15210000-0000-0000-0000-000000000580',9
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_stale,'stale-published',
    '15210000-0000-0000-0000-000000000390',
    '15210000-0000-0000-0000-000000000490',
    '15210000-0000-0000-0000-000000000590',11
  );
  PERFORM pg_temp.task2_seed_record(
    v_record_neither,'neither-route',
    '15210000-0000-0000-0000-000000000395',NULL,
    '15210000-0000-0000-0000-000000000595',13
  );

  SET CONSTRAINTS ALL IMMEDIATE;
  SET CONSTRAINTS ALL DEFERRED;

  INSERT INTO public.change_set(
    id,actor_id,actor_navn,actor_rolle,operation,summary
  ) VALUES (
    -91521001,'15200000-0000-0000-0000-000000000001','Task 2 actor',
    'redaktion','task_2_contract','Task 2 state contract'
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_b,'conflicting-binding',
    '15210000-0000-0000-0000-000000001140',-91521140,'draft',
    '15210000-0000-0000-0000-000000002140','draft_created','Conflict secret','6'
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_a,'missing-anchor',
    '15210000-0000-0000-0000-000000001150',-91521150,'draft',
    '15210000-0000-0000-0000-000000002150','draft_created','Missing anchor','12'
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_a,'withdrawn-only',
    '15210000-0000-0000-0000-000000001160',-91521160,'withdrawn',
    '15210000-0000-0000-0000-000000002160','withdrawn','Withdrawn text','7'
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_a,'active-draft',
    '15210000-0000-0000-0000-000000001170',-91521170,'draft',
    '15210000-0000-0000-0000-000000002170','draft_created','Draft text','8'
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_a,'published',
    '15210000-0000-0000-0000-000000001181',-91521181,'withdrawn',
    '15210000-0000-0000-0000-000000002181','withdrawn',
    'Prior withdrawn text','9'
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_a,'published',
    '15210000-0000-0000-0000-000000001180',-91521180,'published',
    '15210000-0000-0000-0000-000000002180','published','Published text','9'
  );
  v_state:=private.narrative_publication_state(
    v_person_a,-91521001,'published'
  );
  v_hash:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,binding_id,
    narrative_id,source_id,source_record_id,decision_basis,before_state,
    after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name,created_at
  ) VALUES (
    '15210000-0000-0000-0000-000000002182',-91521001,
    '15210000-0000-0000-0000-000000001180',2,'revalidated',
    '15210000-0000-0000-0000-000000001180',-91521180,-91521001,
    v_record_published,'Task 2 revalidation',v_state,v_state,v_hash,v_hash,
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:19:00+02'::timestamptz
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_a,'stale-published',
    '15210000-0000-0000-0000-000000001190',-91521190,'published',
    '15210000-0000-0000-0000-000000002190','published','Before drift','11'
  );
  UPDATE public.narrative SET tekst='After drift' WHERE id=-91521190;

  SELECT public_ref INTO v_public_ref
    FROM private.source_record WHERE id=v_record_principal;
  v_provenance:=jsonb_build_object(
    'anchors',jsonb_build_array(
      jsonb_build_object(
        'anchor_event_id','15210000-0000-0000-0000-000000000401'::uuid,
        'anchor_version',1,
        'occurrence_id','15210000-0000-0000-0000-000000000301'::uuid,
        'rendition_id','15210000-0000-0000-0000-000000000003'::uuid,
        'rendition_content_sha256',repeat('2',64),
        'page_from',2,'page_to',2,
        'physical_fingerprint','physical-accepted-principal',
        'structural_fingerprint','structural-accepted-principal'
      ),
      jsonb_build_object(
        'anchor_event_id','15210000-0000-0000-0000-000000000402'::uuid,
        'anchor_version',1,
        'occurrence_id','15210000-0000-0000-0000-000000000302'::uuid,
        'rendition_id','15210000-0000-0000-0000-000000000003'::uuid,
        'rendition_content_sha256',repeat('2',64),
        'page_from',10,'page_to',10,
        'physical_fingerprint','physical-accepted-principal-page-10',
        'structural_fingerprint','structural-accepted-principal-page-10'
      )
    ),
    'placements',jsonb_build_array(jsonb_build_object(
      'record_placement_id','15210000-0000-0000-0000-000000000801'::uuid,
      'placement_version',1,'scheme_entry_id',-91521001,
      'scheme_entry_label','Linje A','printed_number',NULL,
      'generation_local',NULL,'generation_global',NULL,
      'generation_label_raw',NULL,'kuld_label',NULL,
      'section_path','[]'::jsonb
    )),
    'identities',jsonb_build_array(jsonb_build_object(
      'source_persona_id','15210000-0000-0000-0000-000000000601'::uuid,
      'persona_placement_id','15210000-0000-0000-0000-000000000901'::uuid,
      'placement_role','principal_member','placement_version',1,
      'canonical_person_id',v_person_a,'identity_version',1
    )),
    'revisions','[]'::jsonb
  );
  v_policy:=jsonb_build_object(
    'person_levende',false,'person_private',false,'person_staged',false,
    'narrative_private',NULL,'person_publication_allowed',true,
    'narrative_publication_allowed',false,'publication_allowed',false
  );
  v_expected_publication:=jsonb_build_object(
    'target',jsonb_build_object(
      'person_id',v_person_a,'source_id',-91521001,
      'record_key','accepted-principal','source_record_id',v_record_principal,
      'source_record_ref',v_public_ref
    ),
    'source',jsonb_build_object(
      'source_year',1939,'source_label','DAA Task 2'
    ),
    'provenance',v_provenance,
    'provenance_sha256',encode(extensions.digest(v_provenance::text,'sha256'),'hex'),
    'authority',jsonb_build_object(
      'kind','accepted_identity','identity_people',to_jsonb(ARRAY[v_person_a]),
      'eligibility_status','eligible','blocking_reason',NULL
    ),
    'binding',NULL,
    'narrative',NULL,
    'publication_status','none',
    'labels',jsonb_build_object(
      'record_order',2,'record_label','Linje A',
      'citation_label','DAA Task 2, s. 2, 10','side','2, 10'
    ),
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',false
  );
  v_actual:=private.narrative_publication_state(
    v_person_a,-91521001,'accepted-principal'
  );
  IF v_actual IS DISTINCT FROM v_expected_publication THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_STATE_NOT_CANONICAL: actual=% expected=%',
      v_actual,v_expected_publication;
  END IF;
  IF v_actual ? 'publication_state_sha256' OR v_actual ? 'state_sha256' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLICATION_STATE_SELF_HASHED';
  END IF;

  v_hash:=encode(extensions.digest(v_expected_publication::text,'sha256'),'hex');
  v_expected_editor_input:=jsonb_build_object(
    'publication_state',v_expected_publication,
    'publication_state_sha256',v_hash,
    'withdrawn_history','[]'::jsonb,
    'latest_event_id',NULL,'latest_event_type',NULL,
    'latest_event_version',NULL,
    'latest_before_state_sha256',NULL,'latest_after_state_sha256',NULL,
    'publication_status','none','text_editable',true,
    'allowed_actions','["create_draft"]'::jsonb,
    'eligibility_status','eligible','blocking_reason',NULL,
    'published_text_sha256',NULL
  );
  v_expected_editor:=v_expected_editor_input||jsonb_build_object(
    'state_sha256',encode(
      extensions.digest(v_expected_editor_input::text,'sha256'),'hex'
    )
  );
  v_expected_record_editor:=v_expected_editor;
  v_actual:=private.narrative_record_state(
    v_person_a,-91521001,'accepted-principal',false
  );
  IF v_actual IS DISTINCT FROM v_expected_editor THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_STATE_NOT_CANONICAL: actual=% expected=%',
      v_actual,v_expected_editor;
  END IF;
  IF (v_actual-'state_sha256') ? 'state_sha256'
     OR v_actual->'publication_state' ? 'publication_state_sha256' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_STATE_SELF_HASHED';
  END IF;
  IF private.narrative_record_state(
       v_person_a,-91521001,'accepted-principal',true
     ) IS DISTINCT FROM v_actual THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_LOCK_MODE_CHANGED_CANONICAL_STATE';
  END IF;

  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,side,privat
  ) VALUES
    (-91521201,'person',v_person_a,-91521001,'Legacy active','20',false),
    (-91521202,'person',v_person_a,-91521001,'Legacy withdrawn','21',false),
    (-91521203,'person',v_person_a,-91521001,'Legacy before drift','22',false);
  v_policy:=jsonb_build_object(
    'person_levende',false,'person_private',false,'person_staged',false,
    'narrative_private',false,'person_publication_allowed',true,
    'narrative_publication_allowed',true,'publication_allowed',true
  );
  v_legacy_active_state:=jsonb_build_object(
    'target',jsonb_build_object(
      'legacy_publication_ref',v_legacy_active,'narrative_id',-91521201,
      'person_id',v_person_a,'source_id',-91521001
    ),
    'source',jsonb_build_object('source_year',1939,'source_label','DAA Task 2'),
    'narrative',jsonb_build_object(
      'narrative_id',-91521201,'text','Legacy active',
      'text_sha256',encode(extensions.digest('Legacy active','sha256'),'hex'),
      'private',false,'side','20','has_haendelse',false
    ),
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',false
  );
  v_legacy_withdrawn_state:=jsonb_build_object(
    'target',jsonb_build_object(
      'legacy_publication_ref',v_legacy_withdrawn,'narrative_id',-91521202,
      'person_id',v_person_a,'source_id',-91521001
    ),
    'source',jsonb_build_object('source_year',1939,'source_label','DAA Task 2'),
    'narrative',jsonb_build_object(
      'narrative_id',-91521202,'text','Legacy withdrawn',
      'text_sha256',encode(extensions.digest('Legacy withdrawn','sha256'),'hex'),
      'private',false,'side','21','has_haendelse',false
    ),
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',false
  );
  v_legacy_drift_baseline:=jsonb_build_object(
    'target',jsonb_build_object(
      'legacy_publication_ref',v_legacy_drift,'narrative_id',-91521203,
      'person_id',v_person_a,'source_id',-91521001
    ),
    'source',jsonb_build_object('source_year',1939,'source_label','DAA Task 2'),
    'narrative',jsonb_build_object(
      'narrative_id',-91521203,'text','Legacy before drift',
      'text_sha256',encode(extensions.digest('Legacy before drift','sha256'),'hex'),
      'private',false,'side','22','has_haendelse',false
    ),
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',false
  );
  INSERT INTO private.narrative_legacy_publication(
    legacy_publication_ref,narrative_id,source_id,baseline_state,
    baseline_sha256,status,created_at
  ) VALUES
    (v_legacy_active,-91521201,-91521001,v_legacy_active_state,
     encode(extensions.digest(v_legacy_active_state::text,'sha256'),'hex'),
     'grandfathered_publication','2026-08-29 12:30:01+02'),
    (v_legacy_withdrawn,-91521202,-91521001,v_legacy_withdrawn_state,
     encode(extensions.digest(v_legacy_withdrawn_state::text,'sha256'),'hex'),
     'withdrawn','2026-08-29 12:30:02+02'),
    (v_legacy_drift,-91521203,-91521001,v_legacy_drift_baseline,
     encode(extensions.digest(v_legacy_drift_baseline::text,'sha256'),'hex'),
     'grandfathered_publication','2026-08-29 12:30:03+02');

  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,legacy_publication_ref,
    narrative_id,source_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name,created_at
  ) VALUES (
    '15210000-0000-0000-0000-000000002201',-91521001,v_legacy_active,1,
    'baseline',v_legacy_active,-91521201,-91521001,'Task 2 legacy baseline',
    v_legacy_active_state,v_legacy_active_state,
    encode(extensions.digest(v_legacy_active_state::text,'sha256'),'hex'),
    encode(extensions.digest(v_legacy_active_state::text,'sha256'),'hex'),
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:31:01+02'
  );
  UPDATE private.narrative_legacy_publication
     SET latest_event_id='15210000-0000-0000-0000-000000002201'
   WHERE legacy_publication_ref=v_legacy_active;

  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,legacy_publication_ref,
    narrative_id,source_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name,created_at
  ) VALUES (
    '15210000-0000-0000-0000-000000002202',-91521001,v_legacy_withdrawn,1,
    'baseline',v_legacy_withdrawn,-91521202,-91521001,'Task 2 legacy baseline',
    v_legacy_withdrawn_state,v_legacy_withdrawn_state,
    encode(extensions.digest(v_legacy_withdrawn_state::text,'sha256'),'hex'),
    encode(extensions.digest(v_legacy_withdrawn_state::text,'sha256'),'hex'),
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:31:02+02'
  );
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,legacy_publication_ref,
    narrative_id,source_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name,created_at
  ) VALUES (
    '15210000-0000-0000-0000-000000002203',-91521001,v_legacy_withdrawn,2,
    'legacy_withdrawn',v_legacy_withdrawn,-91521202,-91521001,
    'Task 2 legacy withdrawal',v_legacy_withdrawn_state,v_legacy_withdrawn_state,
    encode(extensions.digest(v_legacy_withdrawn_state::text,'sha256'),'hex'),
    encode(extensions.digest(v_legacy_withdrawn_state::text,'sha256'),'hex'),
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:32:02+02'
  );
  UPDATE private.narrative_legacy_publication
     SET latest_event_id='15210000-0000-0000-0000-000000002203'
   WHERE legacy_publication_ref=v_legacy_withdrawn;

  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,legacy_publication_ref,
    narrative_id,source_id,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name,created_at
  ) VALUES (
    '15210000-0000-0000-0000-000000002204',-91521001,v_legacy_drift,1,
    'baseline',v_legacy_drift,-91521203,-91521001,'Task 2 legacy baseline',
    v_legacy_drift_baseline,v_legacy_drift_baseline,
    encode(extensions.digest(v_legacy_drift_baseline::text,'sha256'),'hex'),
    encode(extensions.digest(v_legacy_drift_baseline::text,'sha256'),'hex'),
    '15200000-0000-0000-0000-000000000001','Task 2 actor',
    '2026-08-29 12:31:03+02'
  );
  UPDATE private.narrative_legacy_publication
     SET latest_event_id='15210000-0000-0000-0000-000000002204'
   WHERE legacy_publication_ref=v_legacy_drift;
  UPDATE public.narrative SET tekst='Legacy after drift' WHERE id=-91521203;

  IF private.narrative_legacy_publication_state(v_legacy_active)
       IS DISTINCT FROM v_legacy_active_state THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_PUBLICATION_STATE_NOT_CANONICAL';
  END IF;
  v_hash:=encode(extensions.digest(v_legacy_active_state::text,'sha256'),'hex');
  v_expected_editor_input:=jsonb_build_object(
    'publication_state',v_legacy_active_state,
    'publication_state_sha256',v_hash,
    'ledger_status','grandfathered_publication','baseline_sha256',v_hash,
    'baseline_matches',true,'withdrawal_event_id',NULL,
    'withdrawn_history','[]'::jsonb,
    'latest_event_id','15210000-0000-0000-0000-000000002201'::uuid,
    'latest_event_type','baseline','latest_event_version',1,
    'latest_before_state_sha256',v_hash,'latest_after_state_sha256',v_hash,
    'publication_status','published','text_editable',false,
    'allowed_actions','["withdraw_legacy"]'::jsonb,
    'eligibility_status','eligible','blocking_reason',NULL,
    'published_text_sha256',encode(extensions.digest('Legacy active','sha256'),'hex')
  );
  v_expected_editor:=v_expected_editor_input||jsonb_build_object(
    'state_sha256',encode(
      extensions.digest(v_expected_editor_input::text,'sha256'),'hex'
    )
  );
  IF private.narrative_legacy_state(v_legacy_active,false)
       IS DISTINCT FROM v_expected_editor THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_EDITOR_STATE_NOT_CANONICAL: actual=% expected=%',
      private.narrative_legacy_state(v_legacy_active,false),v_expected_editor;
  END IF;
  IF private.narrative_legacy_state(v_legacy_active,true)
       IS DISTINCT FROM v_expected_editor THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_LOCK_MODE_CHANGED_CANONICAL_STATE';
  END IF;
  UPDATE private.narrative_legacy_publication
     SET status='migrated'
   WHERE legacy_publication_ref=v_legacy_active;
  v_state:=private.narrative_legacy_state(v_legacy_active,false);
  IF v_state->>'publication_status' IS DISTINCT FROM 'withdrawn'
     OR v_state->>'eligibility_status' IS DISTINCT FROM 'migrated'
     OR v_state->'allowed_actions' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_MIGRATED_DISPOSITION_INVALID: %',v_state;
  END IF;
  UPDATE private.narrative_legacy_publication
     SET status='grandfathered_publication'
   WHERE legacy_publication_ref=v_legacy_active;

  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  v_state:=private.narrative_record_state(
    v_person_a,-91521001,'accepted-principal',false
  );
  IF v_state IS DISTINCT FROM v_expected_record_editor THEN
    RAISE EXCEPTION
      'NARRATIVE_RECORD_EDITOR_STATE_CHANGED_WITH_UNRELATED_LEGACY_ROWS: actual=% expected=%',
      v_state,v_expected_record_editor;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(row)),'[]'::jsonb)
    INTO v_rows
    FROM public.red_person_narrative_records(v_person_a) row;
  IF jsonb_array_length(v_rows)<>12 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_ROW_COUNT_INVALID: %',v_rows;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.red_person_narrative_records(v_person_a)
     WHERE record_key IN ('empty-identity','neither-route')
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_INCLUDED_UNAUTHORIZED_ROUTE';
  END IF;
  IF (
    SELECT array_agg(record_key)
      FROM public.red_person_narrative_records(v_person_a)
     WHERE provenance_kind='source_record'
  ) IS DISTINCT FROM ARRAY[
    'accepted-principal','accepted-co-principal','ambiguous-identity',
    'conflicting-binding','withdrawn-only','active-draft','published',
    'stale-published','missing-anchor'
  ]::text[] THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_ORDER_INVALID';
  END IF;

  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='accepted-principal';
  IF v_actual->>'source_record_ref' IS DISTINCT FROM v_public_ref::text
     OR v_actual->>'record_label' IS DISTINCT FROM 'Linje A'
     OR v_actual->>'citation_label' IS DISTINCT FROM 'DAA Task 2, s. 2, 10'
     OR v_actual->>'record_order' IS DISTINCT FROM '2'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '["create_draft"]'::jsonb
     OR v_actual->>'state_sha256' IS DISTINCT FROM
          v_expected_record_editor->>'state_sha256' THEN
    RAISE EXCEPTION
      'NARRATIVE_RECORD_EDITOR_PRINCIPAL_MAPPING_INVALID: actual=% expected_ref=% expected_hash=%',
      v_actual,v_public_ref,v_expected_record_editor->>'state_sha256';
  END IF;

  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='accepted-co-principal';
  IF v_actual->>'eligibility_status' IS DISTINCT FROM 'eligible'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '["create_draft"]'::jsonb THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CO_PRINCIPAL_ROUTE_INVALID: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='ambiguous-identity';
  IF v_actual->>'blocking_reason' IS DISTINCT FROM
       'NARRATIVE_RECORD_IDENTITY_AMBIGUOUS'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_AMBIGUOUS_IDENTITY_NOT_BLOCKED: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='conflicting-binding';
  IF v_actual->>'blocking_reason' IS DISTINCT FROM
       'NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT'
     OR v_actual->>'narrative_text' IS NOT NULL
     OR v_actual->>'narrative_id' IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CONFLICTING_BINDING_LEAKED: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='missing-anchor';
  IF v_actual->>'blocking_reason' IS DISTINCT FROM 'NARRATIVE_RECORD_ANCHOR_REQUIRED'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_MISSING_ANCHOR_NOT_BLOCKED: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='withdrawn-only';
  IF v_actual->>'publication_status' IS DISTINCT FROM 'withdrawn'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '["create_draft"]'::jsonb
     OR jsonb_array_length(v_actual->'withdrawn_history')<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_WITHDRAWN_HISTORY_INVALID: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='active-draft';
  IF v_actual->'allowed_actions' IS DISTINCT FROM
       '["save_draft","discard_draft","publish"]'::jsonb
     OR (v_actual->>'text_editable')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_DRAFT_ACTIONS_INVALID: %',v_actual;
  END IF;
  UPDATE public.person SET levende=NULL WHERE id=v_person_a;
  v_state:=private.narrative_record_state(
    v_person_a,-91521001,'active-draft',false
  );
  IF jsonb_typeof(
       v_state #> '{publication_state,publication_policy,person_levende}'
     ) IS DISTINCT FROM 'null'
     OR (v_state #>>
          '{publication_state,publication_policy,person_publication_allowed}')::boolean
          IS DISTINCT FROM false
     OR v_state->'allowed_actions' IS DISTINCT FROM
          '["save_draft","discard_draft"]'::jsonb THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_UNKNOWN_LIVING_POLICY_NOT_FAIL_CLOSED: %',
      v_state;
  END IF;
  UPDATE public.person SET levende=false WHERE id=v_person_a;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='published';
  IF v_actual->>'publication_status' IS DISTINCT FROM 'published'
     OR v_actual->'allowed_actions' IS DISTINCT FROM
       '["publish_revision","withdraw"]'::jsonb
     OR (v_actual->>'text_editable')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PUBLISHED_ACTIONS_INVALID: %',v_actual;
  END IF;
  IF private.narrative_record_state(
       v_person_a,-91521001,'published',false
     )->>'latest_event_id' IS DISTINCT FROM
       '15210000-0000-0000-0000-000000002182' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_ACTIVE_STREAM_EVENT_NOT_SELECTED';
  END IF;
  v_state:=private.narrative_record_state(
    v_person_a,-91521001,'published',false
  );
  v_timezone:=current_setting('TimeZone');
  PERFORM set_config('TimeZone','UTC',true);
  IF private.narrative_record_state(
       v_person_a,-91521001,'published',false
     ) IS DISTINCT FROM v_state THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STATE_TIMEZONE_DEPENDENT';
  END IF;
  PERFORM set_config('TimeZone',v_timezone,true);
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE record_key='stale-published';
  IF v_actual->>'publication_status' IS DISTINCT FROM 'stale_published'
     OR v_actual->'allowed_actions' IS DISTINCT FROM
       '["revalidate","withdraw"]'::jsonb
     OR (v_actual->>'text_editable')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_STALE_ACTIONS_INVALID: %',v_actual;
  END IF;

  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE legacy_publication_ref=v_legacy_active;
  IF v_actual->>'provenance_kind' IS DISTINCT FROM 'grandfathered_legacy'
     OR v_actual->>'publication_status' IS DISTINCT FROM 'published'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '["withdraw_legacy"]'::jsonb
     OR (v_actual->>'text_editable')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_ACTIVE_MAPPING_INVALID: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE legacy_publication_ref=v_legacy_withdrawn;
  IF v_actual->>'publication_status' IS DISTINCT FROM 'withdrawn'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '[]'::jsonb
     OR jsonb_array_length(v_actual->'withdrawn_history')<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_WITHDRAWN_MAPPING_INVALID: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_records(v_person_a) row
   WHERE legacy_publication_ref=v_legacy_drift;
  IF v_actual->>'publication_status' IS DISTINCT FROM 'stale_published'
     OR v_actual->>'blocking_reason' IS DISTINCT FROM
       'NARRATIVE_LEGACY_BASELINE_DRIFT'
     OR v_actual->'allowed_actions' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_DRIFT_NOT_BLOCKED: %',v_actual;
  END IF;

  FOREACH v_private_uuid IN ARRAY ARRAY[
    v_record_principal::text,v_record_co::text,v_record_empty::text,
    v_record_ambiguous::text,v_record_conflict::text,
    v_record_missing_anchor::text,v_record_withdrawn::text,
    v_record_draft::text,v_record_published::text,v_record_stale::text,
    v_record_neither::text,
    '15210000-0000-0000-0000-000000001140',
    '15210000-0000-0000-0000-000000001150',
    '15210000-0000-0000-0000-000000001160',
    '15210000-0000-0000-0000-000000001170',
    '15210000-0000-0000-0000-000000001180',
    '15210000-0000-0000-0000-000000001181',
    '15210000-0000-0000-0000-000000001190',
    '15210000-0000-0000-0000-000000000601',
    '15210000-0000-0000-0000-000000000610',
    '15210000-0000-0000-0000-000000000630',
    '15210000-0000-0000-0000-000000000631',
    '15210000-0000-0000-0000-000000000640',
    '15210000-0000-0000-0000-000000000660',
    '15210000-0000-0000-0000-000000000801',
    '15210000-0000-0000-0000-000000000810',
    '15210000-0000-0000-0000-000000000830',
    '15210000-0000-0000-0000-000000000831',
    '15210000-0000-0000-0000-000000000840',
    '15210000-0000-0000-0000-000000000860',
    '15210000-0000-0000-0000-000000000901',
    '15210000-0000-0000-0000-000000000910',
    '15210000-0000-0000-0000-000000000930',
    '15210000-0000-0000-0000-000000000931',
    '15210000-0000-0000-0000-000000000940',
    '15210000-0000-0000-0000-000000000960',
    '15210000-0000-0000-0000-000000001001',
    '15210000-0000-0000-0000-000000001010',
    '15210000-0000-0000-0000-000000001030',
    '15210000-0000-0000-0000-000000001031',
    '15210000-0000-0000-0000-000000001040',
    '15210000-0000-0000-0000-000000001060'
  ] LOOP
    IF v_rows::text LIKE '%'||v_private_uuid||'%' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_PRIVATE_UUID_LEAK: %',v_private_uuid;
    END IF;
  END LOOP;
  IF v_rows::text LIKE '%publication_policy%'
     OR v_rows::text LIKE '%policy_sha256%'
     OR v_rows::text LIKE '%provenance_sha256%'
     OR v_rows::text LIKE '%identity_people%' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_PRIVATE_STATE_LEAK: %',v_rows;
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(row)),'[]'::jsonb)
    INTO v_history
    FROM public.red_person_narrative_publication_history(v_person_a) row;
  IF jsonb_array_length(v_history)<>11 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_ROW_COUNT_INVALID: %',v_history;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_publication_history(v_person_a) row
   WHERE event_id='15210000-0000-0000-0000-000000002182';
  IF v_actual->>'before_text' IS DISTINCT FROM 'Published text'
     OR v_actual->>'after_text' IS DISTINCT FROM 'Published text'
     OR (v_actual->>'can_reverse')::boolean IS DISTINCT FROM true
     OR v_actual->>'source_record_ref' IS NULL
     OR v_actual->>'blocking_reason' IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_PUBLISHED_MAPPING_INVALID: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_publication_history(v_person_a) row
   WHERE event_id='15210000-0000-0000-0000-000000002180';
  IF (v_actual->>'can_reverse')::boolean IS DISTINCT FROM false
     OR v_actual->>'blocking_reason' IS DISTINCT FROM
          'NARRATIVE_PUBLICATION_EVENT_NOT_LATEST' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_OLDER_EVENT_REVERSIBLE: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_publication_history(v_person_a) row
   WHERE event_id='15210000-0000-0000-0000-000000002190';
  IF (v_actual->>'can_reverse')::boolean IS DISTINCT FROM false
     OR v_actual->>'blocking_reason' IS DISTINCT FROM
       'NARRATIVE_PUBLICATION_EVENT_STATE_DRIFT' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_STALE_REVERSAL_INVALID: %',v_actual;
  END IF;
  SELECT to_jsonb(row) INTO v_actual
    FROM public.red_person_narrative_publication_history(v_person_a) row
   WHERE event_id='15210000-0000-0000-0000-000000002203';
  IF (v_actual->>'can_reverse')::boolean IS DISTINCT FROM true
     OR v_actual->>'legacy_publication_ref' IS DISTINCT FROM v_legacy_withdrawn::text
     OR v_actual->>'source_record_ref' IS NOT NULL THEN
    RAISE EXCEPTION 'NARRATIVE_LEGACY_HISTORY_MAPPING_INVALID: %',v_actual;
  END IF;
  FOREACH v_private_uuid IN ARRAY ARRAY[
    v_record_principal::text,v_record_co::text,v_record_empty::text,
    v_record_ambiguous::text,v_record_conflict::text,
    v_record_missing_anchor::text,v_record_withdrawn::text,
    v_record_draft::text,v_record_published::text,v_record_stale::text,
    v_record_neither::text,
    '15210000-0000-0000-0000-000000001140',
    '15210000-0000-0000-0000-000000001150',
    '15210000-0000-0000-0000-000000001160',
    '15210000-0000-0000-0000-000000001170',
    '15210000-0000-0000-0000-000000001180',
    '15210000-0000-0000-0000-000000001181',
    '15210000-0000-0000-0000-000000001190'
  ] LOOP
    IF v_history::text LIKE '%'||v_private_uuid||'%' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_PRIVATE_UUID_LEAK: %',v_private_uuid;
    END IF;
  END LOOP;
  IF v_history::text LIKE '%publication_policy%'
     OR v_history::text LIKE '%identity_people%'
     OR v_history::text LIKE '%provenance%' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_HISTORY_PRIVATE_STATE_LEAK: %',v_history;
  END IF;

  v_error:=NULL; v_sqlstate:=NULL;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM * FROM public.red_person_narrative_records(v_person_a);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate=RETURNED_SQLSTATE;
    v_error:=SQLERRM;
  END;
  SET LOCAL ROLE NONE;
  IF v_sqlstate IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_ANON_CALL_NOT_DENIED: % %',
      v_sqlstate,v_error;
  END IF;

  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  v_error:=NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM * FROM public.red_person_narrative_records(v_person_a);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  SET LOCAL ROLE NONE;
  IF v_error IS DISTINCT FROM 'NARRATIVE_RECORD_ROLE_FORBIDDEN' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_MEMBER_CALL_NOT_DENIED: %',v_error;
  END IF;

  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.red_person_narrative_records(v_person_a))<>12
     OR (
       SELECT count(*)
         FROM public.red_person_narrative_publication_history(v_person_a)
     )<>11 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_EDITOR_REDACTION_CALL_FAILED';
  END IF;
  SET LOCAL ROLE NONE;

  RAISE NOTICE 'OK: narrative record Task 2 canonical record state and lock mode';
  RAISE NOTICE 'OK: narrative record Task 2 authority, labels, editor and history';
END
$narrative_record_task2_behavior$;

ROLLBACK;
