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
    -- Trin 6e-2 (spec §12): en post med bogtrykt nøgle (her 'accepted-principal', ikke record-<uuid>) har record_key
    -- som postetiket; linjens navn indgår kun i etiketten for poster uden bognøgle.
    'labels',jsonb_build_object(
      'record_order',2,'record_label','accepted-principal',
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
     OR v_actual->>'record_label' IS DISTINCT FROM 'accepted-principal'   -- 6e-2: bognøgle ⇒ record_key
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
  -- Bred spærring (persona for helpost uden tekst, spec §4.5): person A har record-bindinger
  -- i samme kilde, så den tilbagetrukne legacy-tekst kan ikke fortrydes.
  IF (v_actual->>'can_reverse')::boolean IS DISTINCT FROM false
     OR v_actual->>'blocking_reason' IS DISTINCT FROM
          'NARRATIVE_LEGACY_RECORD_BINDING_EXISTS'
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

-- Simulate a fresh Supabase owner whose default ACL grants a newly installed
-- red_* overload before db-rls.sql classifies the public RPC surface. Re-running
-- RLS must revoke this unclassified overload while preserving exact readers.
ALTER DEFAULT PRIVILEGES
  GRANT EXECUTE ON FUNCTIONS TO PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.red_task3_unclassified_acl_probe(p_value integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path=pg_catalog
AS $$ SELECT p_value $$;
\ir ../../db-rls.sql
DO $narrative_record_task3_acl_classifier$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(
      v_role,'public.red_task3_unclassified_acl_probe(integer)','EXECUTE'
    ) THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_UNCLASSIFIED_RPC_EXECUTABLE: %',v_role;
    END IF;
  END LOOP;
  IF NOT has_function_privilege(
       'authenticated','public.red_person_narrative_records(bigint)','EXECUTE'
     ) OR NOT has_function_privilege(
       'authenticated','public.red_person_narrative_publication_history(bigint)','EXECUTE'
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_EDITOR_READER_GRANT_REGRESSION';
  END IF;
  RAISE NOTICE 'OK: narrative record Task 3 red_* ACL classification is fail-closed';
END
$narrative_record_task3_acl_classifier$;
DROP FUNCTION public.red_task3_unclassified_acl_probe(integer);

-- Task 4 structural contract: additive legacy withdrawal and dedicated
-- reversal stay owner-only at version 1, their helpers keep a fixed private
-- boundary, generic undo rejects publication-owned change sets before opening
-- its own audit set, and person hard-delete takes the shared cutover gate first.
DO $narrative_record_task4_structure$
DECLARE
  v_signature text;
  v_role text;
  v_definition text;
  v_lock_position integer;
  v_version_position integer;
  v_state_position integer;
  v_guard_position integer;
  v_change_set_position integer;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'private.withdraw_legacy_narrative(uuid,text,text)',
    'private.reverse_narrative_publication_event(uuid,text)',
    'public.red_tilbagetraek_legacy_narrative(uuid,text,text)',
    'public.red_fortryd_person_narrative_publication_event(uuid,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_FUNCTION_MISSING: %',v_signature;
    END IF;
    IF pg_get_function_result(to_regprocedure(v_signature)) IS DISTINCT FROM 'jsonb' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_RESULT_INVALID: %',v_signature;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM pg_proc function
     WHERE function.oid IN (
       'private.withdraw_legacy_narrative(uuid,text,text)'::regprocedure,
       'private.reverse_narrative_publication_event(uuid,text)'::regprocedure,
       'public.red_tilbagetraek_legacy_narrative(uuid,text,text)'::regprocedure,
       'public.red_fortryd_person_narrative_publication_event(uuid,text)'::regprocedure
     )
       AND (
         NOT function.prosecdef
         OR function.provolatile<>'v'
         OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_SECURITY_CONTRACT_INVALID';
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    FOREACH v_signature IN ARRAY ARRAY[
      'private.withdraw_legacy_narrative(uuid,text,text)',
      'private.reverse_narrative_publication_event(uuid,text)',
      'public.red_tilbagetraek_legacy_narrative(uuid,text,text)',
      'public.red_fortryd_person_narrative_publication_event(uuid,text)'
    ] LOOP
      IF has_function_privilege(v_role,v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_PRECUTOVER_GRANT_INVALID: % %',
          v_role,v_signature;
      END IF;
    END LOOP;
  END LOOP;

  v_definition:=pg_get_functiondef(
    'private.withdraw_legacy_narrative(uuid,text,text)'::regprocedure
  );
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_version_position:=strpos(v_definition,'public.narrative_record_contract_version()');
  v_state_position:=strpos(v_definition,'private.narrative_legacy_state(');
  IF v_lock_position=0 OR v_version_position<=v_lock_position
     OR v_state_position<=v_version_position
     OR strpos(v_definition,'''daa-narrative-record-contract''')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_LEGACY_GATE_OR_LOCK_ORDER_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'private.reverse_narrative_publication_event(uuid,text)'::regprocedure
  );
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_version_position:=strpos(v_definition,'public.narrative_record_contract_version()');
  IF v_lock_position=0 OR v_version_position<=v_lock_position
     OR strpos(v_definition,'''daa-narrative-record-contract''')=0
     OR strpos(v_definition,'private.narrative_record_state(')<=v_version_position
     OR strpos(v_definition,'private.narrative_legacy_state(')<=v_version_position THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_REVERSAL_GATE_OR_LOCK_ORDER_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'public.red_fortryd_change_set(bigint,boolean)'::regprocedure
  );
  v_lock_position:=strpos(
    v_definition,'LOCK TABLE public.change_set IN ACCESS SHARE MODE'
  );
  v_guard_position:=strpos(
    v_definition,'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED'
  );
  v_change_set_position:=strpos(
    v_definition,'INSERT INTO change_set'
  );
  IF v_lock_position=0 OR v_guard_position<=v_lock_position
     OR v_change_set_position=0
     OR v_guard_position>=v_change_set_position
     OR strpos(v_definition,'private.narrative_publication_event')=0
     OR strpos(v_definition,'private.narrative_legacy_publication')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_GENERIC_UNDO_GUARD_INVALID';
  END IF;

  v_definition:=pg_get_functiondef('public.red_slet_person(bigint)'::regprocedure);
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_guard_position:=strpos(
    v_definition,'PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY'
  );
  v_change_set_position:=strpos(v_definition,'begin_change_set(');
  IF v_lock_position=0 OR v_guard_position<=v_lock_position
     OR v_change_set_position<=v_guard_position
     OR strpos(v_definition,'''daa-narrative-record-contract''')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_PERSON_DELETE_GUARD_INVALID';
  END IF;

  v_definition:=pg_get_functiondef(
    'public.red_person_narrative_publication_history(bigint)'::regprocedure
  );
  IF strpos(v_definition,'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_HISTORY_REVERSAL_REASON_INVALID';
  END IF;
  IF strpos(v_definition,'NARRATIVE_PUBLICATION_EVENT_NOT_REVERSIBLE')=0
     OR strpos(v_definition,'classified.event_type NOT IN')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_HISTORY_LEGAL_EVENT_SET_INVALID';
  END IF;

  RAISE NOTICE 'OK: narrative record Task 4 signatures, gates and pre-cutover ACL';
END
$narrative_record_task4_structure$;

-- Task 3 contract: all six record mutations remain owner-only while version 1
-- is active. Their behavior is exercised below inside a savepoint which swaps
-- only the capability function to version 2 and is rolled back afterwards.
DO $narrative_record_task3_structure$
DECLARE
  v_signature text;
  v_role text;
  v_definition text;
  v_lock_position integer;
  v_version_position integer;
  v_state_position integer;
  v_error text;
  v_sqlstate text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)',
    'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
    'public.red_publicer_person_narrative_record(bigint,bigint,text,text)',
    'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)',
    'public.red_revalider_person_narrative_record(bigint,bigint,text,text)',
    'public.red_kasser_person_narrative_record(bigint,bigint,text,text)',
    'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_FUNCTION_MISSING: %',v_signature;
    END IF;
    IF pg_get_function_result(to_regprocedure(v_signature)) IS DISTINCT FROM 'jsonb' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_RESULT_INVALID: %',v_signature;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM pg_proc function
     WHERE function.oid IN (
       'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)'::regprocedure,
       'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)'::regprocedure,
       'public.red_publicer_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
       'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)'::regprocedure,
       'public.red_revalider_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
       'public.red_kasser_person_narrative_record(bigint,bigint,text,text)'::regprocedure,
       'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'::regprocedure
     )
       AND (
         NOT function.prosecdef
         OR function.provolatile<>'v'
         OR function.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
       )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_SECURITY_CONTRACT_INVALID';
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    FOREACH v_signature IN ARRAY ARRAY[
      'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)',
      'public.red_upsert_person_narrative_record(bigint,bigint,text,text,boolean,text)',
      'public.red_publicer_person_narrative_record(bigint,bigint,text,text)',
      'public.red_revider_publiceret_person_narrative_record(bigint,bigint,text,text,text)',
      'public.red_revalider_person_narrative_record(bigint,bigint,text,text)',
      'public.red_kasser_person_narrative_record(bigint,bigint,text,text)',
      'public.red_tilbagetraek_person_narrative_record(bigint,bigint,text,text)'
    ] LOOP
      IF has_function_privilege(v_role,v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_PRECUTOVER_GRANT_INVALID: % %',
          v_role,v_signature;
      END IF;
    END LOOP;
  END LOOP;

  v_definition:=pg_get_functiondef(
    'private.mutate_person_narrative_record(text,bigint,bigint,text,text,boolean,text)'::regprocedure
  );
  v_lock_position:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
  v_version_position:=strpos(v_definition,'public.narrative_record_contract_version()');
  v_state_position:=strpos(v_definition,'private.narrative_record_state(');
  IF v_lock_position=0 OR v_version_position<=v_lock_position
     OR v_state_position<=v_version_position
     OR strpos(v_definition,'''daa-narrative-record-contract''')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_GATE_OR_LOCK_ORDER_INVALID';
  END IF;

  v_error:=NULL;
  BEGIN
    PERFORM public.red_upsert_person_narrative_record(
      -91521001,-91521001,'accepted-principal','must not run',false,repeat('0',64)
    );
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'NARRATIVE_RECORD_CONTRACT_INACTIVE' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_VERSION_1_OWNER_CALL_NOT_BLOCKED: %',v_error;
  END IF;

  v_error:=NULL; v_sqlstate:=NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_upsert_person_narrative_record(
      -91521001,-91521001,'accepted-principal','must not run',false,repeat('0',64)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate=RETURNED_SQLSTATE;
    v_error:=SQLERRM;
  END;
  SET LOCAL ROLE NONE;
  IF v_sqlstate IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_AUTHENTICATED_CALL_NOT_DENIED: % %',
      v_sqlstate,v_error;
  END IF;

  RAISE NOTICE 'OK: narrative record Task 3 signatures, gate order and pre-cutover ACL';
END
$narrative_record_task3_structure$;

CREATE FUNCTION pg_temp.task3_write_snapshot()
RETURNS jsonb
LANGUAGE sql
VOLATILE
SET search_path=pg_catalog
AS $task3_write_snapshot$
  SELECT jsonb_build_object(
    'change_set',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.change_set row
    ),'[]'::jsonb),
    'change_event',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.change_event row
    ),'[]'::jsonb),
    'narrative',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.narrative row
    ),'[]'::jsonb),
    'binding',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id)
        FROM private.narrative_record_publication row
    ),'[]'::jsonb),
    'publication_event',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.created_at,row.id)
        FROM private.narrative_publication_event row
    ),'[]'::jsonb),
    'haendelse',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.haendelse row
    ),'[]'::jsonb)
  )
$task3_write_snapshot$;

CREATE FUNCTION pg_temp.task3_call(
  p_operation text,
  p_person_id bigint,
  p_record_key text,
  p_text text,
  p_private boolean,
  p_expected_state_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path=pg_catalog
AS $task3_call$
BEGIN
  CASE p_operation
    WHEN 'upsert' THEN
      RETURN public.red_upsert_person_narrative_record(
        p_person_id,-91521001,p_record_key,p_text,p_private,p_expected_state_sha256
      );
    WHEN 'publish' THEN
      RETURN public.red_publicer_person_narrative_record(
        p_person_id,-91521001,p_record_key,p_expected_state_sha256
      );
    WHEN 'revise' THEN
      RETURN public.red_revider_publiceret_person_narrative_record(
        p_person_id,-91521001,p_record_key,p_text,p_expected_state_sha256
      );
    WHEN 'revalidate' THEN
      RETURN public.red_revalider_person_narrative_record(
        p_person_id,-91521001,p_record_key,p_expected_state_sha256
      );
    WHEN 'discard' THEN
      RETURN public.red_kasser_person_narrative_record(
        p_person_id,-91521001,p_record_key,p_expected_state_sha256
      );
    WHEN 'withdraw' THEN
      RETURN public.red_tilbagetraek_person_narrative_record(
        p_person_id,-91521001,p_record_key,p_expected_state_sha256
      );
    ELSE
      RAISE EXCEPTION 'TASK3_TEST_OPERATION_INVALID';
  END CASE;
END
$task3_call$;

CREATE FUNCTION pg_temp.task3_expect_error(
  p_operation text,
  p_person_id bigint,
  p_record_key text,
  p_text text,
  p_private boolean,
  p_expected_state_sha256 text,
  p_expected_error text
) RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path=pg_catalog
AS $task3_expect_error$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_error text;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  v_before:=pg_temp.task3_write_snapshot();
  BEGIN
    PERFORM pg_temp.task3_call(
      p_operation,p_person_id,p_record_key,p_text,p_private,p_expected_state_sha256
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  v_after:=pg_temp.task3_write_snapshot();
  IF v_error IS DISTINCT FROM p_expected_error THEN
    RAISE EXCEPTION 'TASK3_EXPECTED_ERROR_MISMATCH: op=% record=% expected=% actual=%',
      p_operation,p_record_key,p_expected_error,v_error;
  END IF;
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'TASK3_REJECTION_CHANGED_WRITE_SET: op=% record=% before=% after=%',
      p_operation,p_record_key,v_before,v_after;
  END IF;
END
$task3_expect_error$;

CREATE FUNCTION pg_temp.task3_assert_success(
  p_before jsonb,
  p_result jsonb,
  p_person_id bigint,
  p_record_key text,
  p_before_publication_state jsonb,
  p_expected_status text,
  p_expected_event_type text,
  p_expected_narrative_delta integer,
  p_expected_binding_delta integer,
  p_expected_change_op text
) RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path=pg_catalog
AS $task3_assert_success$
DECLARE
  v_after jsonb:=pg_temp.task3_write_snapshot();
  v_event private.narrative_publication_event%ROWTYPE;
  v_after_publication_state jsonb;
  v_after_editor_state jsonb;
  v_before_hash text;
  v_after_hash text;
  v_result_keys text[];
  v_before_other jsonb;
  v_after_other jsonb;
  v_change_events jsonb;
BEGIN
  IF jsonb_array_length(v_after->'change_set')
       <> jsonb_array_length(p_before->'change_set')+1
     OR jsonb_array_length(v_after->'publication_event')
       <> jsonb_array_length(p_before->'publication_event')+1
     OR jsonb_array_length(v_after->'narrative')
       <> jsonb_array_length(p_before->'narrative')+p_expected_narrative_delta
     OR jsonb_array_length(v_after->'binding')
       <> jsonb_array_length(p_before->'binding')+p_expected_binding_delta
     OR jsonb_array_length(v_after->'change_event')
       <> jsonb_array_length(p_before->'change_event')
          +(CASE WHEN p_expected_change_op IS NULL THEN 0 ELSE 1 END) THEN
    RAISE EXCEPTION 'TASK3_SUCCESS_COUNT_DELTA_INVALID: before=% after=% result=%',
      p_before,v_after,p_result;
  END IF;

  SELECT array_agg(key ORDER BY key)
    INTO v_result_keys
    FROM jsonb_object_keys(p_result) key;
  IF v_result_keys IS DISTINCT FROM ARRAY[
    'event_id','narrative_id','person_id','publication_state_sha256',
    'record_key','source_id','source_record_ref','state_sha256','status'
  ]::text[] THEN
    RAISE EXCEPTION 'TASK3_RESULT_KEYS_UNSAFE_OR_INCOMPLETE: %',p_result;
  END IF;

  SELECT * INTO STRICT v_event
    FROM private.narrative_publication_event event
   WHERE event.id=(p_result->>'event_id')::uuid;
  v_after_publication_state:=private.narrative_publication_state(
    p_person_id,-91521001,p_record_key
  );
  v_after_editor_state:=private.narrative_record_state(
    p_person_id,-91521001,p_record_key,false
  );
  v_before_hash:=encode(
    extensions.digest(p_before_publication_state::text,'sha256'),'hex'
  );
  v_after_hash:=encode(
    extensions.digest(v_after_publication_state::text,'sha256'),'hex'
  );

  IF v_event.event_type IS DISTINCT FROM p_expected_event_type
     OR v_event.before_state IS DISTINCT FROM p_before_publication_state
     OR v_event.before_state_sha256 IS DISTINCT FROM v_before_hash
     OR v_event.after_state IS DISTINCT FROM v_after_publication_state
     OR v_event.after_state_sha256 IS DISTINCT FROM v_after_hash
     OR p_result->>'publication_state_sha256' IS DISTINCT FROM v_after_hash
     OR p_result->>'state_sha256' IS DISTINCT FROM v_after_editor_state->>'state_sha256'
     OR p_result->>'state_sha256' IS NOT DISTINCT FROM v_after_hash
     OR p_result->>'status' IS DISTINCT FROM p_expected_status
     OR p_result->>'person_id' IS DISTINCT FROM p_person_id::text
     OR p_result->>'source_id' IS DISTINCT FROM '-91521001'
     OR p_result->>'record_key' IS DISTINCT FROM p_record_key
     OR p_result->>'source_record_ref' IS DISTINCT FROM
          v_after_publication_state #>> '{target,source_record_ref}'
     OR p_result->>'narrative_id' IS DISTINCT FROM v_event.narrative_id::text
     OR v_after_editor_state->>'latest_event_id' IS DISTINCT FROM v_event.id::text
     OR v_after_editor_state->>'publication_status' IS DISTINCT FROM p_expected_status THEN
    RAISE EXCEPTION 'TASK3_SUCCESS_HASH_OR_RESULT_INVALID: result=% event=% editor=%',
      p_result,to_jsonb(v_event),v_after_editor_state;
  END IF;

  SELECT coalesce(jsonb_agg(item ORDER BY (item->>'id')::bigint),'[]'::jsonb)
    INTO v_before_other
    FROM jsonb_array_elements(p_before->'narrative') item
   WHERE item->>'id' IS DISTINCT FROM v_event.narrative_id::text;
  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.id),'[]'::jsonb)
    INTO v_after_other
    FROM public.narrative row
   WHERE row.id<>v_event.narrative_id;
  IF v_before_other IS DISTINCT FROM v_after_other THEN
    RAISE EXCEPTION 'TASK3_SUCCESS_CHANGED_OTHER_NARRATIVE_ROWS';
  END IF;

  SELECT coalesce(jsonb_agg(item ORDER BY item->>'id'),'[]'::jsonb)
    INTO v_before_other
    FROM jsonb_array_elements(p_before->'binding') item
   WHERE item->>'id' IS DISTINCT FROM v_event.binding_id::text;
  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.id),'[]'::jsonb)
    INTO v_after_other
    FROM private.narrative_record_publication row
   WHERE row.id<>v_event.binding_id;
  IF v_before_other IS DISTINCT FROM v_after_other THEN
    RAISE EXCEPTION 'TASK3_SUCCESS_CHANGED_OTHER_BINDING_ROWS';
  END IF;

  IF p_expected_change_op IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.change_event row
       WHERE row.change_set_id=v_event.change_set_id
    ) THEN
      RAISE EXCEPTION 'TASK3_SUCCESS_UNEXPECTED_CHANGE_EVENT';
    END IF;
  ELSE
    SELECT jsonb_agg(to_jsonb(row) ORDER BY row.seq)
      INTO v_change_events
      FROM public.change_event row
     WHERE row.change_set_id=v_event.change_set_id;
    IF jsonb_array_length(coalesce(v_change_events,'[]'::jsonb))<>1
       OR v_change_events->0->>'tabel' IS DISTINCT FROM 'narrative'
       OR v_change_events->0->>'op' IS DISTINCT FROM p_expected_change_op
       OR v_change_events->0->'row_pk' IS DISTINCT FROM
            jsonb_build_object('id',v_event.narrative_id) THEN
      RAISE EXCEPTION 'TASK3_SUCCESS_CHANGE_EVENT_WRITE_SET_INVALID: %',
        v_change_events;
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.change_set row
     WHERE row.id=v_event.change_set_id
       AND row.subjekt_type='person'
       AND row.subjekt_id=p_person_id
       AND row.operation='narrative_record_'||p_expected_event_type
  ) THEN
    RAISE EXCEPTION 'TASK3_SUCCESS_CHANGE_SET_INVALID: %',v_event.change_set_id;
  END IF;
END
$task3_assert_success$;

SAVEPOINT narrative_record_task3_version_2;
CREATE OR REPLACE FUNCTION public.narrative_record_contract_version()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$ SELECT 2 $$;

DO $narrative_record_task3_behavior$
DECLARE
  v_actor uuid := '15200000-0000-0000-0000-000000000001';
  v_person_private bigint := -91522001;
  v_person_staged bigint := -91522002;
  v_person_alive bigint := -91522003;
  v_person_revalidate bigint := -91522004;
  v_before jsonb;
  v_pre_state jsonb;
  v_state jsonb;
  v_result jsonb;
  v_hash text;
  v_old_narrative bigint;
  v_old_binding uuid;
  v_event private.narrative_publication_event%ROWTYPE;
  v_latest private.narrative_publication_event%ROWTYPE;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
  VALUES
    (v_person_private,false,false,false,'Task 3 private narrative'),
    (v_person_staged,false,false,true,'Task 3 staged person'),
    (v_person_alive,true,false,false,'Task 3 living person'),
    (v_person_revalidate,false,false,false,'Task 3 revalidation person');

  PERFORM pg_temp.task2_seed_record(
    '15220000-0000-0000-0000-000000000101','task3-private',
    '15220000-0000-0000-0000-000000000201',
    '15220000-0000-0000-0000-000000000301',
    '15220000-0000-0000-0000-000000000401',31
  );
  PERFORM pg_temp.task2_seed_identity(
    '15220000-0000-0000-0000-000000000101',
    '15220000-0000-0000-0000-000000000401',
    '15220000-0000-0000-0000-000000000501',
    '15220000-0000-0000-0000-000000000601',
    '15220000-0000-0000-0000-000000000701',
    '15220000-0000-0000-0000-000000000801',
    '15220000-0000-0000-0000-000000000901',v_person_private,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_record(
    '15220000-0000-0000-0000-000000000102','task3-staged',
    '15220000-0000-0000-0000-000000000202',
    '15220000-0000-0000-0000-000000000302',
    '15220000-0000-0000-0000-000000000402',32
  );
  PERFORM pg_temp.task2_seed_identity(
    '15220000-0000-0000-0000-000000000102',
    '15220000-0000-0000-0000-000000000402',
    '15220000-0000-0000-0000-000000000502',
    '15220000-0000-0000-0000-000000000602',
    '15220000-0000-0000-0000-000000000702',
    '15220000-0000-0000-0000-000000000802',
    '15220000-0000-0000-0000-000000000902',v_person_staged,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_record(
    '15220000-0000-0000-0000-000000000103','task3-alive',
    '15220000-0000-0000-0000-000000000203',
    '15220000-0000-0000-0000-000000000303',
    '15220000-0000-0000-0000-000000000403',33
  );
  PERFORM pg_temp.task2_seed_identity(
    '15220000-0000-0000-0000-000000000103',
    '15220000-0000-0000-0000-000000000403',
    '15220000-0000-0000-0000-000000000503',
    '15220000-0000-0000-0000-000000000603',
    '15220000-0000-0000-0000-000000000703',
    '15220000-0000-0000-0000-000000000803',
    '15220000-0000-0000-0000-000000000903',v_person_alive,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_record(
    '15220000-0000-0000-0000-000000000104','task3-revalidate',
    '15220000-0000-0000-0000-000000000204',
    '15220000-0000-0000-0000-000000000304',
    '15220000-0000-0000-0000-000000000404',34
  );
  PERFORM pg_temp.task2_seed_identity(
    '15220000-0000-0000-0000-000000000104',
    '15220000-0000-0000-0000-000000000404',
    '15220000-0000-0000-0000-000000000504',
    '15220000-0000-0000-0000-000000000604',
    '15220000-0000-0000-0000-000000000704',
    '15220000-0000-0000-0000-000000000804',
    '15220000-0000-0000-0000-000000000904',v_person_revalidate,
    'principal_member',-91521001
  );
  PERFORM pg_temp.task2_seed_binding_event(
    v_person_revalidate,'task3-revalidate',
    '15220000-0000-0000-0000-000000001104',-91522104,'published',
    '15220000-0000-0000-0000-000000002104','published',
    'Revalidation text','34'
  );
  INSERT INTO private.source_record_occurrence(
    id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
  ) VALUES (
    '15220000-0000-0000-0000-000000000205',
    '15210000-0000-0000-0000-000000000003','task3-revalidate-extra',
    35,35,21,40,'Task 3 extra occurrence','task3-revalidate-physical',
    'task3-revalidate-structural','15210000-0000-0000-0000-000000000002'
  );
  INSERT INTO private.source_record_anchor_event(
    id,occurrence_id,source_record_id,decision_status,evidence,version,
    decided_by,decided_by_name
  ) VALUES (
    '15220000-0000-0000-0000-000000000305',
    '15220000-0000-0000-0000-000000000205',
    '15220000-0000-0000-0000-000000000104','accepted',
    jsonb_build_object('basis','Task 3 additional accepted occurrence'),1,
    v_actor,'Task 3 actor'
  );

  -- Every negative row snapshots all Task-3 write tables before/after.
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'legacy-target-not-addressable','legacy edit',false,
    repeat('0',64),'NARRATIVE_RECORD_NOT_FOUND'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'empty-identity',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'empty-identity','missing identity',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_IDENTITY_REQUIRED'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'ambiguous-identity',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'ambiguous-identity','ambiguous identity',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_IDENTITY_AMBIGUOUS'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'conflicting-binding',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'conflicting-binding','binding conflict',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_ACTIVE_BINDING_CONFLICT'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'missing-anchor',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'missing-anchor','missing anchor',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_ANCHOR_REQUIRED'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'active-draft',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'active-draft','stale state',false,
    repeat('0',64),'NARRATIVE_RECORD_STATE_STALE'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'published',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'published','ordinary published save',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_PUBLISHED_REQUIRES_REVISION'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'stale-published',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'stale-published','ordinary stale save',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_PUBLICATION_STALE'
  );
  PERFORM pg_temp.task3_expect_error(
    'revise',-91521001,'stale-published','stale revision',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_PUBLICATION_STALE'
  );
  PERFORM pg_temp.task3_expect_error(
    'revalidate',-91521001,'stale-published',NULL,NULL,
    v_state->>'state_sha256','NARRATIVE_RECORD_PUBLICATION_TEXT_DRIFT'
  );

  -- New draft -> update -> discard -> fresh stream. The old stream and text
  -- stay byte-for-byte intact and every success owns one change set/event.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'accepted-principal','First draft bytes',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'accepted-principal',E'Draft bytes\nwith exact spacing ',true,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'draft','draft_updated',0,0,'UPDATE'
  );

  -- Make the first stream longer than each replacement stream. A stream-local
  -- version must never outrank a chronologically newer binding stream.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'accepted-principal','Long first stream bytes',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'draft','draft_updated',0,0,'UPDATE'
  );
  v_old_narrative:=(v_result->>'narrative_id')::bigint;
  SELECT id INTO STRICT v_old_binding
    FROM private.narrative_record_publication
   WHERE narrative_id=v_old_narrative;

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'discard',-91521001,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'withdrawn','draft_discarded',0,0,NULL
  );

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'accepted-principal','Fresh stream text',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );
  IF (v_result->>'narrative_id')::bigint=v_old_narrative
     OR (SELECT tekst FROM public.narrative WHERE id=v_old_narrative)
          IS DISTINCT FROM 'Long first stream bytes'
     OR (SELECT status FROM private.narrative_record_publication WHERE id=v_old_binding)
          IS DISTINCT FROM 'withdrawn'
     OR (SELECT count(*) FROM private.narrative_record_publication
          WHERE source_record_id='15210000-0000-0000-0000-000000000101')<>2 THEN
    RAISE EXCEPTION 'TASK3_WITHDRAWN_STREAM_NOT_PRESERVED';
  END IF;

  -- The fresh stream is only v2 after this immediate discard, while the older
  -- withdrawn stream is v4. Canonical latest-event selection must follow the
  -- newer stream, not compare these stream-local versions globally.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'discard',-91521001,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'withdrawn','draft_discarded',0,0,NULL
  );

  -- A second replacement stream reaches only v3 (create, publish, withdraw),
  -- still shorter than the first v4 stream. Withdrawal must nevertheless make
  -- its own event the canonical head after its binding becomes withdrawn.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'accepted-principal','Newest stream bytes',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'publish',-91521001,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'published','published',0,0,NULL
  );

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'withdraw',-91521001,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'withdrawn','withdrawn',0,0,NULL
  );

  -- Preserve the later identity-conflict test's active-binding premise while
  -- also proving a new draft remains possible after the shorter stream exits.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'accepted-principal'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'accepted-principal','Active conflict stream',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'accepted-principal',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );

  -- Active draft update, publication, explicit revision and derived-event block.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'active-draft'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'active-draft',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',-91521001,'active-draft','Updated active draft',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'active-draft',v_pre_state,
    'draft','draft_updated',0,0,'UPDATE'
  );

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'active-draft'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'active-draft',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'publish',-91521001,'active-draft',NULL,NULL,v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'active-draft',v_pre_state,
    'published','published',0,0,NULL
  );
  SELECT * INTO STRICT v_event
    FROM private.narrative_publication_event
   WHERE id=(v_result->>'event_id')::uuid;
  IF v_event.after_state #> '{provenance,anchors}' IS NULL
     OR v_event.after_state #> '{provenance,identities}' IS NULL
     OR v_event.after_state #> '{publication_policy}' IS NULL
     OR v_event.after_state #>> '{narrative,text}' IS DISTINCT FROM
          'Updated active draft'
     OR v_event.after_state #>> '{narrative,text_sha256}' IS NULL THEN
    RAISE EXCEPTION 'TASK3_PUBLISHED_SNAPSHOT_INCOMPLETE: %',v_event.after_state;
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'active-draft'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'active-draft',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'revise',-91521001,'active-draft',E'Published revision\nnew bytes',NULL,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'active-draft',v_pre_state,
    'published','published_revision',0,0,'UPDATE'
  );
  SELECT * INTO STRICT v_event
    FROM private.narrative_publication_event
   WHERE id=(v_result->>'event_id')::uuid;
  IF v_event.before_state #>> '{narrative,text}' IS DISTINCT FROM
       'Updated active draft'
     OR v_event.after_state #>> '{narrative,text}' IS DISTINCT FROM
       E'Published revision\nnew bytes'
     OR v_event.before_state #> '{provenance,anchors}' IS NULL
     OR v_event.after_state #> '{provenance,anchors}' IS NULL
     OR v_event.before_state #> '{publication_policy}' IS NULL
     OR v_event.after_state #> '{publication_policy}' IS NULL THEN
    RAISE EXCEPTION 'TASK3_PUBLISHED_REVISION_SNAPSHOT_INCOMPLETE';
  END IF;

  INSERT INTO public.haendelse(
    id,subjekt_type,subjekt_id,narrative_id,noegle,klausul
  ) VALUES (
    -91522001,'person',-91521001,-91521170,'task3-derived','Derived event'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'active-draft',false
  );
  PERFORM pg_temp.task3_expect_error(
    'revise',-91521001,'active-draft','must not rewrite derived event',NULL,
    v_state->>'state_sha256','NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT'
  );

  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    -91521001,-91521001,'active-draft'
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'active-draft',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'withdraw',-91521001,'active-draft',NULL,NULL,v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,-91521001,'active-draft',v_pre_state,
    'withdrawn','withdrawn',0,0,NULL
  );
  IF (SELECT tekst FROM public.narrative WHERE id=-91521170)
       IS DISTINCT FROM E'Published revision\nnew bytes' THEN
    RAISE EXCEPTION 'TASK3_WITHDRAW_DELETED_OR_CHANGED_TEXT';
  END IF;

  -- Publication policy rejects private narrative, staged person and living person.
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    v_person_private,-91521001,'task3-private'
  );
  v_state:=private.narrative_record_state(
    v_person_private,-91521001,'task3-private',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',v_person_private,'task3-private','Private draft',true,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,v_person_private,'task3-private',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );
  v_state:=private.narrative_record_state(
    v_person_private,-91521001,'task3-private',false
  );
  PERFORM pg_temp.task3_expect_error(
    'publish',v_person_private,'task3-private',NULL,NULL,v_state->>'state_sha256',
    'NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED'
  );
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    v_person_staged,-91521001,'task3-staged'
  );
  v_state:=private.narrative_record_state(
    v_person_staged,-91521001,'task3-staged',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',v_person_staged,'task3-staged','Staged draft',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,v_person_staged,'task3-staged',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );
  v_state:=private.narrative_record_state(
    v_person_staged,-91521001,'task3-staged',false
  );
  PERFORM pg_temp.task3_expect_error(
    'publish',v_person_staged,'task3-staged',NULL,NULL,v_state->>'state_sha256',
    'NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED'
  );
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    v_person_alive,-91521001,'task3-alive'
  );
  v_state:=private.narrative_record_state(
    v_person_alive,-91521001,'task3-alive',false
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'upsert',v_person_alive,'task3-alive','Living draft',false,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,v_person_alive,'task3-alive',v_pre_state,
    'draft','draft_created',1,1,'INSERT'
  );
  v_state:=private.narrative_record_state(
    v_person_alive,-91521001,'task3-alive',false
  );
  PERFORM pg_temp.task3_expect_error(
    'publish',v_person_alive,'task3-alive',NULL,NULL,v_state->>'state_sha256',
    'NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED'
  );

  -- Provenance-only drift may be explicitly revalidated; the event binds the
  -- current semantic state without changing text or projection rows.
  v_state:=private.narrative_record_state(
    v_person_revalidate,-91521001,'task3-revalidate',false
  );
  IF v_state->>'publication_status' IS DISTINCT FROM 'stale_published' THEN
    RAISE EXCEPTION 'TASK3_REVALIDATION_FIXTURE_NOT_STALE: %',v_state;
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_pre_state:=private.narrative_publication_state(
    v_person_revalidate,-91521001,'task3-revalidate'
  );
  v_before:=pg_temp.task3_write_snapshot();
  v_result:=pg_temp.task3_call(
    'revalidate',v_person_revalidate,'task3-revalidate',NULL,NULL,
    v_state->>'state_sha256'
  );
  PERFORM pg_temp.task3_assert_success(
    v_before,v_result,v_person_revalidate,'task3-revalidate',v_pre_state,
    'published','revalidated',0,0,NULL
  );

  -- An existing binding that gains an accepted identity for another person
  -- is blocked even though the binding itself still targets this person.
  PERFORM pg_temp.task2_seed_identity(
    '15210000-0000-0000-0000-000000000101',
    '15210000-0000-0000-0000-000000000501',
    '15220000-0000-0000-0000-000000000511',
    '15220000-0000-0000-0000-000000000611',
    '15220000-0000-0000-0000-000000000711',
    '15220000-0000-0000-0000-000000000811',
    '15220000-0000-0000-0000-000000000911',-91521002,
    'co_principal',-91521002
  );
  v_state:=private.narrative_record_state(
    -91521001,-91521001,'accepted-principal',false
  );
  PERFORM pg_temp.task3_expect_error(
    'upsert',-91521001,'accepted-principal','identity conflict',false,
    v_state->>'state_sha256','NARRATIVE_RECORD_IDENTITY_CONFLICT'
  );

  RAISE NOTICE 'OK: narrative record Task 3 transition table, write sets and hashes';
END
$narrative_record_task3_behavior$;

ROLLBACK TO SAVEPOINT narrative_record_task3_version_2;
DO $narrative_record_task3_version_restored$
BEGIN
  IF public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_TEST_WEAKENED_PRODUCTION_VERSION';
  END IF;
  RAISE NOTICE 'OK: narrative record Task 3 version-2 fixture rolled back to version 1';
END
$narrative_record_task3_version_restored$;

SAVEPOINT narrative_record_task4_version_2;
CREATE OR REPLACE FUNCTION public.narrative_record_contract_version()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$ SELECT 2 $$;

CREATE FUNCTION pg_temp.task4_write_snapshot()
RETURNS jsonb
LANGUAGE sql
VOLATILE
SET search_path=pg_catalog
AS $task4_write_snapshot$
  SELECT jsonb_build_object(
    'change_set',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.change_set row
    ),'[]'::jsonb),
    'change_event',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.change_event row
    ),'[]'::jsonb),
    'person',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.person row
    ),'[]'::jsonb),
    'narrative',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id) FROM public.narrative row
    ),'[]'::jsonb),
    'binding',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.id)
        FROM private.narrative_record_publication row
    ),'[]'::jsonb),
    'legacy',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.legacy_publication_ref)
        FROM private.narrative_legacy_publication row
    ),'[]'::jsonb),
    'publication_event',coalesce((
      SELECT jsonb_agg(to_jsonb(row) ORDER BY row.created_at,row.id)
        FROM private.narrative_publication_event row
    ),'[]'::jsonb)
  )
$task4_write_snapshot$;

CREATE FUNCTION pg_temp.task4_expect_reverse_error(
  p_event_id uuid,
  p_expected_state_sha256 text,
  p_expected_error text
) RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path=pg_catalog
AS $task4_expect_reverse_error$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_error text;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  v_before:=pg_temp.task4_write_snapshot();
  BEGIN
    PERFORM public.red_fortryd_person_narrative_publication_event(
      p_event_id,p_expected_state_sha256
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  v_after:=pg_temp.task4_write_snapshot();
  IF v_error IS DISTINCT FROM p_expected_error THEN
    RAISE EXCEPTION 'TASK4_REVERSAL_ERROR_MISMATCH: event=% expected=% actual=%',
      p_event_id,p_expected_error,v_error;
  END IF;
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'TASK4_REVERSAL_REJECTION_CHANGED_WRITE_SET: event=%',p_event_id;
  END IF;
END
$task4_expect_reverse_error$;

CREATE FUNCTION pg_temp.task4_expect_legacy_error(
  p_legacy_publication_ref uuid,
  p_expected_state_sha256 text,
  p_reason text,
  p_expected_error text
) RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path=pg_catalog
AS $task4_expect_legacy_error$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_error text;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  v_before:=pg_temp.task4_write_snapshot();
  BEGIN
    PERFORM public.red_tilbagetraek_legacy_narrative(
      p_legacy_publication_ref,p_expected_state_sha256,p_reason
    );
  EXCEPTION WHEN OTHERS THEN
    v_error:=SQLERRM;
  END;
  v_after:=pg_temp.task4_write_snapshot();
  IF v_error IS DISTINCT FROM p_expected_error THEN
    RAISE EXCEPTION 'TASK4_LEGACY_ERROR_MISMATCH: ref=% expected=% actual=%',
      p_legacy_publication_ref,p_expected_error,v_error;
  END IF;
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'TASK4_LEGACY_REJECTION_CHANGED_WRITE_SET: ref=%',
      p_legacy_publication_ref;
  END IF;
END
$task4_expect_legacy_error$;

DO $narrative_record_task4_behavior$
DECLARE
  v_actor uuid := '15200000-0000-0000-0000-000000000001';
  v_person bigint := -91521001;
  v_state jsonb;
  v_other_state jsonb;
  v_result jsonb;
  v_reverse_result jsonb;
  v_event_create uuid;
  v_event_update uuid;
  v_event_discard uuid;
  v_event_publish uuid;
  v_event_revision uuid;
  v_event_revalidate uuid;
  v_event_withdraw uuid;
  v_event_create_only uuid;
  v_event_create_only_reversal uuid;
  v_event_legacy uuid;
  v_event_legacy_reversal uuid;
  v_event_legacy_migrated uuid;
  v_event_drift uuid;
  v_narrative_id bigint;
  v_binding_id uuid;
  v_legacy_active uuid := '15210000-0000-0000-0000-000000000201';
  v_legacy_drift uuid := '15210000-0000-0000-0000-000000000203';
  v_legacy_sibling uuid := '15240000-0000-0000-0000-000000000210';
  v_legacy_free uuid := '15240000-0000-0000-0000-000000000260';
  v_legacy_free_sibling uuid := '15240000-0000-0000-0000-000000000261';
  v_free_person bigint := -91524060;
  v_legacy_sibling_state jsonb;
  v_policy jsonb;
  v_before jsonb;
  v_after jsonb;
  v_history jsonb;
  v_preview jsonb;
  v_error text;
  v_cs bigint;
  v_baseline_cs bigint;
  v_baseline_state jsonb;
  v_baseline_hash text;
  v_baseline_event uuid := '15240000-0000-0000-0000-000000002103';
  v_reversed_type text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  -- One stream exercises update, discard, publish, published revision,
  -- revalidation and withdrawal reversals without deleting any history.
  PERFORM set_config('app.change_set_id','',true);
  v_state:=private.narrative_record_state(
    v_person,-91521001,'accepted-principal',false
  );
  v_result:=pg_temp.task3_call(
    'upsert',v_person,'accepted-principal','Task 4 draft one',false,
    v_state->>'state_sha256'
  );
  v_event_create:=(v_result->>'event_id')::uuid;

  PERFORM set_config('app.change_set_id','',true);
  v_state:=private.narrative_record_state(
    v_person,-91521001,'accepted-principal',false
  );
  v_result:=pg_temp.task3_call(
    'upsert',v_person,'accepted-principal','Task 4 draft two',true,
    v_state->>'state_sha256'
  );
  v_event_update:=(v_result->>'event_id')::uuid;
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_create,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256',
    'NARRATIVE_PUBLICATION_EVENT_NOT_LATEST'
  );
  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_update,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  IF (SELECT tekst FROM public.narrative
       WHERE id=(v_result->>'narrative_id')::bigint)
       IS DISTINCT FROM 'Task 4 draft one'
     OR (SELECT privat FROM public.narrative
          WHERE id=(v_result->>'narrative_id')::bigint) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'TASK4_DRAFT_UPDATE_REVERSAL_DID_NOT_RESTORE_BEFORE_STATE';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  v_state:=private.narrative_record_state(
    v_person,-91521001,'accepted-principal',false
  );
  v_result:=pg_temp.task3_call(
    'discard',v_person,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  v_event_discard:=(v_result->>'event_id')::uuid;
  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_discard,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  IF private.narrative_record_state(
       v_person,-91521001,'accepted-principal',false
     )->>'publication_status' IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'TASK4_DRAFT_DISCARD_REVERSAL_DID_NOT_RESTORE_DRAFT';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  v_state:=private.narrative_record_state(
    v_person,-91521001,'accepted-principal',false
  );
  v_result:=pg_temp.task3_call(
    'publish',v_person,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  v_event_publish:=(v_result->>'event_id')::uuid;
  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_publish,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  SELECT binding.id INTO STRICT v_binding_id
    FROM private.narrative_record_publication binding
    JOIN public.narrative narrative ON narrative.id=binding.narrative_id
   WHERE narrative.subjekt_id=v_person
     AND binding.source_record_id='15210000-0000-0000-0000-000000000101';
  IF (SELECT status FROM private.narrative_record_publication WHERE id=v_binding_id)
       IS DISTINCT FROM 'draft'
     OR (SELECT published_at FROM private.narrative_record_publication WHERE id=v_binding_id)
       IS NOT NULL THEN
    RAISE EXCEPTION 'TASK4_PUBLISH_REVERSAL_DID_NOT_RESTORE_DRAFT';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  v_result:=pg_temp.task3_call(
    'publish',v_person,'accepted-principal',NULL,NULL,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  PERFORM set_config('app.change_set_id','',true);
  v_result:=pg_temp.task3_call(
    'revise',v_person,'accepted-principal','Task 4 published revision',NULL,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  v_event_revision:=(v_result->>'event_id')::uuid;
  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_revision,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  IF (SELECT tekst FROM public.narrative WHERE id=(v_result->>'narrative_id')::bigint)
       IS DISTINCT FROM 'Task 4 draft one' THEN
    RAISE EXCEPTION 'TASK4_PUBLISHED_REVISION_REVERSAL_DID_NOT_RESTORE_TEXT';
  END IF;

  -- Provenance drift becomes an explicit revalidation decision. Reversing that
  -- decision appends history and leaves the projection byte-identical.
  INSERT INTO private.source_record_occurrence(
    id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
  ) VALUES (
    '15240000-0000-0000-0000-000000000250',
    '15210000-0000-0000-0000-000000000003','task4-revalidate-extra',
    14,14,21,40,'Task 4 extra occurrence','task4-revalidate-physical',
    'task4-revalidate-structural','15210000-0000-0000-0000-000000000002'
  );
  INSERT INTO private.source_record_anchor_event(
    id,occurrence_id,source_record_id,decision_status,evidence,version,
    decided_by,decided_by_name
  ) VALUES (
    '15240000-0000-0000-0000-000000000350',
    '15240000-0000-0000-0000-000000000250',
    '15210000-0000-0000-0000-000000000101','accepted',
    jsonb_build_object('basis','Task 4 provenance drift'),1,v_actor,'Task 4 actor'
  );
  v_state:=private.narrative_record_state(
    v_person,-91521001,'accepted-principal',false
  );
  IF v_state->>'publication_status' IS DISTINCT FROM 'stale_published' THEN
    RAISE EXCEPTION 'TASK4_REVALIDATE_FIXTURE_NOT_STALE';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_result:=pg_temp.task3_call(
    'revalidate',v_person,'accepted-principal',NULL,NULL,v_state->>'state_sha256'
  );
  v_event_revalidate:=(v_result->>'event_id')::uuid;
  v_before:=(SELECT to_jsonb(narrative) FROM public.narrative narrative
              WHERE narrative.id=(v_result->>'narrative_id')::bigint);
  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_revalidate,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  v_after:=(SELECT to_jsonb(narrative) FROM public.narrative narrative
             WHERE narrative.id=(v_result->>'narrative_id')::bigint);
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'TASK4_REVALIDATION_REVERSAL_CHANGED_PROJECTION';
  END IF;
  IF private.narrative_record_state(
       v_person,-91521001,'accepted-principal',false
     )->>'publication_status' IS DISTINCT FROM 'stale_published' THEN
    RAISE EXCEPTION 'TASK4_REVALIDATION_REVERSAL_DID_NOT_RESTORE_STALE_STATE';
  END IF;

  PERFORM set_config('app.change_set_id','',true);
  v_result:=pg_temp.task3_call(
    'withdraw',v_person,'accepted-principal',NULL,NULL,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  v_event_withdraw:=(v_result->>'event_id')::uuid;

  -- Restoring a record publication rechecks the underlying narrative/person
  -- rows even though a withdrawn binding is absent from the public projector.
  PERFORM set_config('app.change_set_id','',true);
  UPDATE public.person SET privat=true WHERE id=v_person;
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_withdraw,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256',
    'NARRATIVE_PUBLICATION_REVERSAL_POLICY_BLOCKED'
  );
  PERFORM set_config('app.change_set_id','',true);
  UPDATE public.person SET privat=false WHERE id=v_person;

  -- Reversal tokens cannot be borrowed across streams.
  PERFORM pg_temp.task2_seed_record(
    '15240000-0000-0000-0000-000000000101','task4-create-only',
    '15240000-0000-0000-0000-000000000201',
    '15240000-0000-0000-0000-000000000301',
    '15240000-0000-0000-0000-000000000401',41
  );
  PERFORM pg_temp.task2_seed_identity(
    '15240000-0000-0000-0000-000000000101',
    '15240000-0000-0000-0000-000000000401',
    '15240000-0000-0000-0000-000000000501',
    '15240000-0000-0000-0000-000000000601',
    '15240000-0000-0000-0000-000000000701',
    '15240000-0000-0000-0000-000000000801',
    '15240000-0000-0000-0000-000000000901',v_person,
    'principal_member',-91521001
  );
  PERFORM set_config('app.change_set_id','',true);
  v_result:=pg_temp.task3_call(
    'upsert',v_person,'task4-create-only','Task 4 create only',false,
    private.narrative_record_state(
      v_person,-91521001,'task4-create-only',false
    )->>'state_sha256'
  );
  v_event_create_only:=(v_result->>'event_id')::uuid;
  v_narrative_id:=(v_result->>'narrative_id')::bigint;
  v_other_state:=private.narrative_record_state(
    v_person,-91521001,'task4-create-only',false
  );
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_withdraw,v_other_state->>'state_sha256',
    'NARRATIVE_RECORD_STATE_STALE'
  );
  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_create_only,v_other_state->>'state_sha256'
  );
  v_event_create_only_reversal:=(v_reverse_result->>'event_id')::uuid;
  IF NOT EXISTS (
    SELECT 1 FROM private.narrative_record_publication binding
     WHERE binding.narrative_id=v_narrative_id AND binding.status='withdrawn'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.narrative narrative WHERE narrative.id=v_narrative_id
  ) THEN
    RAISE EXCEPTION 'TASK4_DRAFT_CREATE_REVERSAL_DELETED_PROJECTION_HISTORY';
  END IF;
  v_other_state:=private.narrative_record_state(
    v_person,-91521001,'task4-create-only',false
  );
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_create_only_reversal,v_other_state->>'state_sha256',
    'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE'
  );
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_create_only,v_other_state->>'state_sha256',
    'NARRATIVE_PUBLICATION_EVENT_ALREADY_REVERSED'
  );

  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_withdraw,
    private.narrative_record_state(
      v_person,-91521001,'accepted-principal',false
    )->>'state_sha256'
  );
  IF private.narrative_record_state(
       v_person,-91521001,'accepted-principal',false
     )->>'publication_status' IS DISTINCT FROM 'stale_published' THEN
    RAISE EXCEPTION 'TASK4_STALE_WITHDRAW_REVERSAL_REVALIDATED_PUBLICATION';
  END IF;

  -- A latest event whose projection drifted is rejected even with a freshly
  -- measured editor token.
  PERFORM pg_temp.task2_seed_record(
    '15240000-0000-0000-0000-000000000102','task4-drift',
    '15240000-0000-0000-0000-000000000202',
    '15240000-0000-0000-0000-000000000302',
    '15240000-0000-0000-0000-000000000402',42
  );
  PERFORM pg_temp.task2_seed_identity(
    '15240000-0000-0000-0000-000000000102',
    '15240000-0000-0000-0000-000000000402',
    '15240000-0000-0000-0000-000000000502',
    '15240000-0000-0000-0000-000000000602',
    '15240000-0000-0000-0000-000000000702',
    '15240000-0000-0000-0000-000000000802',
    '15240000-0000-0000-0000-000000000902',v_person,
    'principal_member',-91521001
  );
  PERFORM set_config('app.change_set_id','',true);
  v_result:=pg_temp.task3_call(
    'upsert',v_person,'task4-drift','Task 4 drift before',false,
    private.narrative_record_state(
      v_person,-91521001,'task4-drift',false
    )->>'state_sha256'
  );
  v_event_drift:=(v_result->>'event_id')::uuid;
  PERFORM set_config('app.change_set_id','',true);
  UPDATE public.narrative SET tekst='Task 4 drift after'
   WHERE id=(v_result->>'narrative_id')::bigint;
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_drift,
    private.narrative_record_state(
      v_person,-91521001,'task4-drift',false
    )->>'state_sha256',
    'NARRATIVE_PUBLICATION_EVENT_STATE_DRIFT'
  );

  -- Legacy withdrawal changes only the selected ledger disposition and event
  -- stream. Text/privacy and a sibling grandfathered biography stay intact.
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,side,privat
  ) VALUES (
    -91524210,'person',v_person,-91521001,'Task 4 legacy sibling','51',false
  );
  v_policy:=jsonb_build_object(
    'person_levende',false,'person_private',false,'person_staged',false,
    'narrative_private',false,'person_publication_allowed',true,
    'narrative_publication_allowed',true,'publication_allowed',true
  );
  v_legacy_sibling_state:=jsonb_build_object(
    'target',jsonb_build_object(
      'legacy_publication_ref',v_legacy_sibling,'narrative_id',-91524210,
      'person_id',v_person,'source_id',-91521001
    ),
    'source',jsonb_build_object('source_year',1939,'source_label','DAA Task 2'),
    'narrative',jsonb_build_object(
      'narrative_id',-91524210,'text','Task 4 legacy sibling',
      'text_sha256',encode(
        extensions.digest('Task 4 legacy sibling','sha256'),'hex'
      ),'private',false,'side','51','has_haendelse',false
    ),
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',false
  );
  INSERT INTO private.narrative_legacy_publication(
    legacy_publication_ref,narrative_id,source_id,baseline_state,
    baseline_sha256,status
  ) VALUES (
    v_legacy_sibling,-91524210,-91521001,v_legacy_sibling_state,
    encode(extensions.digest(v_legacy_sibling_state::text,'sha256'),'hex'),
    'grandfathered_publication'
  );

  v_state:=private.narrative_legacy_state(v_legacy_active,false);
  PERFORM pg_temp.task4_expect_legacy_error(
    v_legacy_active,v_state->>'state_sha256','   ',
    'NARRATIVE_LEGACY_WITHDRAWAL_REASON_REQUIRED'
  );
  PERFORM pg_temp.task4_expect_legacy_error(
    v_legacy_active,repeat('0',64),'Task 4 stale',
    'NARRATIVE_RECORD_STATE_STALE'
  );
  PERFORM pg_temp.task4_expect_legacy_error(
    '15240000-0000-0000-0000-000000000299',repeat('0',64),'Task 4 unknown',
    'NARRATIVE_LEGACY_PUBLICATION_NOT_FOUND'
  );
  PERFORM pg_temp.task4_expect_legacy_error(
    v_legacy_drift,
    private.narrative_legacy_state(v_legacy_drift,false)->>'state_sha256',
    'Task 4 drifted baseline','NARRATIVE_LEGACY_BASELINE_DRIFT'
  );

  -- Bred spærring (persona for helpost uden tekst, spec §4.5): v_person har record-bindinger
  -- i kilden, så en tilbagetrukket legacy-tekst kan ikke fortrydes for v_person. Tilbagetrækning
  -- og fortrydelse prøves derfor på en person uden record-binding i kilden; v_legacy_active
  -- forbliver grandfathered (Task 5 læser den). Personen har to legacy-tekster i samme kilde,
  -- så granulariteten pr. person og kilde stadig prøves (v_legacy_free_sibling bliver stående).
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
  VALUES (v_free_person,false,false,false,'Task 4 legacy free');
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,side,privat
  ) VALUES (
    -91524160,'person',v_free_person,-91521001,'Task 4 legacy free','52',false
  ),(
    -91524161,'person',v_free_person,-91521001,'Task 4 legacy free sibling','53',false
  );
  v_before:=private.narrative_legacy_candidate_publication_state(
    -91524161,-91521001,v_legacy_free_sibling
  );
  INSERT INTO private.narrative_legacy_publication(
    legacy_publication_ref,narrative_id,source_id,baseline_state,
    baseline_sha256,status
  ) VALUES (
    v_legacy_free_sibling,-91524161,-91521001,v_before,
    encode(extensions.digest(v_before::text,'sha256'),'hex'),
    'grandfathered_publication'
  );
  v_before:=private.narrative_legacy_candidate_publication_state(
    -91524160,-91521001,v_legacy_free
  );
  INSERT INTO private.narrative_legacy_publication(
    legacy_publication_ref,narrative_id,source_id,baseline_state,
    baseline_sha256,status
  ) VALUES (
    v_legacy_free,-91524160,-91521001,v_before,
    encode(extensions.digest(v_before::text,'sha256'),'hex'),
    'grandfathered_publication'
  );

  v_before:=(SELECT to_jsonb(narrative) FROM public.narrative narrative
              WHERE narrative.id=-91524160);
  PERFORM set_config('app.change_set_id','',true);
  v_result:=public.red_tilbagetraek_legacy_narrative(
    v_legacy_free,private.narrative_legacy_state(v_legacy_free,false)->>'state_sha256',
    'Task 4 granular withdrawal'
  );
  v_event_legacy:=(v_result->>'event_id')::uuid;
  v_after:=(SELECT to_jsonb(narrative) FROM public.narrative narrative
             WHERE narrative.id=-91524160);
  IF v_after IS DISTINCT FROM v_before
     OR (SELECT status FROM private.narrative_legacy_publication
          WHERE legacy_publication_ref=v_legacy_free)
          IS DISTINCT FROM 'withdrawn'
     OR (SELECT status FROM private.narrative_legacy_publication
          WHERE legacy_publication_ref=v_legacy_sibling)
          IS DISTINCT FROM 'grandfathered_publication'
     OR (SELECT status FROM private.narrative_legacy_publication
          WHERE legacy_publication_ref=v_legacy_free_sibling)
          IS DISTINCT FROM 'grandfathered_publication'
     OR (SELECT tekst FROM public.narrative WHERE id=-91524161)
          IS DISTINCT FROM 'Task 4 legacy free sibling'
     OR private.narrative_legacy_state(v_legacy_free,false)
          ->>'publication_status' IS DISTINCT FROM 'withdrawn'
     OR private.narrative_legacy_state(v_legacy_sibling,false)
          ->>'publication_status' IS DISTINCT FROM 'published'
     OR private.narrative_legacy_state(v_legacy_free_sibling,false)
          ->>'publication_status' IS DISTINCT FROM 'published' THEN
    RAISE EXCEPTION 'TASK4_LEGACY_WITHDRAWAL_NOT_GRANULAR_OR_TEXT_SAFE';
  END IF;
  PERFORM pg_temp.task4_expect_legacy_error(
    v_legacy_free,
    private.narrative_legacy_state(v_legacy_free,false)->>'state_sha256',
    'Task 4 duplicate','NARRATIVE_LEGACY_PUBLICATION_ALREADY_WITHDRAWN'
  );

  SELECT to_jsonb(row) INTO STRICT v_history
    FROM public.red_person_narrative_publication_history(v_free_person) row
   WHERE row.event_id=v_event_legacy;
  IF (v_history->>'can_reverse')::boolean IS DISTINCT FROM true
     OR v_history->>'change_set_id' IS DISTINCT FROM
          (SELECT event.change_set_id::text
             FROM private.narrative_publication_event event
            WHERE event.id=v_event_legacy) THEN
    RAISE EXCEPTION 'TASK4_LEGACY_HISTORY_EVENT_MAPPING_INVALID: %',v_history;
  END IF;

  UPDATE public.person SET privat=true WHERE id=v_free_person;
  PERFORM pg_temp.task4_expect_reverse_error(
    v_event_legacy,
    private.narrative_legacy_state(v_legacy_free,false)->>'state_sha256',
    'NARRATIVE_PUBLICATION_REVERSAL_POLICY_BLOCKED'
  );
  UPDATE public.person SET privat=false WHERE id=v_free_person;

  PERFORM set_config('app.change_set_id','',true);
  v_reverse_result:=public.red_fortryd_person_narrative_publication_event(
    v_event_legacy,
    private.narrative_legacy_state(v_legacy_free,false)->>'state_sha256'
  );
  v_event_legacy_reversal:=(v_reverse_result->>'event_id')::uuid;
  IF (SELECT status FROM private.narrative_legacy_publication
       WHERE legacy_publication_ref=v_legacy_free)
       IS DISTINCT FROM 'grandfathered_publication' THEN
    RAISE EXCEPTION 'TASK4_LEGACY_REVERSAL_DID_NOT_RESTORE_LEDGER';
  END IF;
  SELECT to_jsonb(row) INTO STRICT v_history
    FROM public.red_person_narrative_publication_history(v_free_person) row
   WHERE row.event_id=v_event_legacy_reversal;
  IF (v_history->>'can_reverse')::boolean IS DISTINCT FROM false
     OR v_history->>'blocking_reason' IS DISTINCT FROM
          'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE' THEN
    RAISE EXCEPTION 'TASK4_HISTORY_REVERSAL_ROW_INVALID: %',v_history;
  END IF;
  SELECT to_jsonb(row) INTO STRICT v_history
    FROM public.red_person_narrative_publication_history(v_free_person) row
   WHERE row.event_id=v_event_legacy;
  IF (v_history->>'can_reverse')::boolean IS DISTINCT FROM false
     OR v_history->>'blocking_reason' IS DISTINCT FROM
          'NARRATIVE_PUBLICATION_EVENT_ALREADY_REVERSED' THEN
    RAISE EXCEPTION 'TASK4_HISTORY_REVERSED_TARGET_INVALID: %',v_history;
  END IF;

  -- #166 149b: legacy_migrated ER et lovligt fortryd-mål, når record-bindingen
  -- ikke er aktiv (spec §8's tredje trin). Denne fixture har ingen binding, så
  -- historikken skal markere det som reversibelt. Gaten for en AKTIV binding
  -- (NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE) dækkes af task4-blokken i
  -- tests/sql/test-reimport-legacy-migration.sql, hvor en ægte binding findes.
  v_before:=private.narrative_legacy_publication_state(v_legacy_sibling);
  v_baseline_hash:=encode(extensions.digest(v_before::text,'sha256'),'hex');
  PERFORM set_config('app.change_set_id','',true);
  v_cs:=public.begin_change_set(
    'task4_legacy_migrated','Task 4 reserved migration event','person',v_person
  );
  UPDATE private.narrative_legacy_publication
     SET status='migrated'
   WHERE legacy_publication_ref=v_legacy_sibling;
  INSERT INTO private.narrative_publication_event(
    change_set_id,stream_ref,stream_version,event_type,narrative_id,source_id,
    legacy_publication_ref,decision_basis,before_state,after_state,
    before_state_sha256,after_state_sha256,decided_by,decided_by_name
  ) VALUES (
    v_cs,v_legacy_sibling,1,'legacy_migrated',-91524210,-91521001,
    v_legacy_sibling,'Task 4 reserved migration event',v_before,v_before,
    v_baseline_hash,v_baseline_hash,v_actor,'Task 4 actor'
  ) RETURNING id INTO v_event_legacy_migrated;
  UPDATE private.narrative_legacy_publication
     SET latest_event_id=v_event_legacy_migrated
   WHERE legacy_publication_ref=v_legacy_sibling;
  SELECT to_jsonb(row) INTO STRICT v_history
    FROM public.red_person_narrative_publication_history(v_person) row
   WHERE row.event_id=v_event_legacy_migrated;
  IF (v_history->>'can_reverse')::boolean IS DISTINCT FROM true
     OR v_history->>'blocking_reason' IS NOT NULL THEN
    RAISE EXCEPTION 'TASK4_HISTORY_LEGACY_MIGRATED_INVALID: %',v_history;
  END IF;

  -- Every requested reversible event class has a dedicated reversal event.
  FOREACH v_event_update IN ARRAY ARRAY[
    v_event_update,v_event_discard,v_event_publish,v_event_revision,
    v_event_revalidate,v_event_withdraw,v_event_create_only,v_event_legacy
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM private.narrative_publication_event reversal
       WHERE reversal.event_type='reversal'
         AND reversal.reversed_event_id=v_event_update
    ) THEN
      RAISE EXCEPTION 'TASK4_REVERSAL_CLASS_NOT_COVERED: %',v_event_update;
    END IF;
  END LOOP;

  -- Generic undo remains unchanged for ordinary narrative change sets.
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
  VALUES (-91524020,false,false,false,'Task 4 ordinary undo');
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,privat
  ) VALUES (
    -91524120,'person',-91524020,-91521001,'Ordinary before',false
  );
  PERFORM set_config('app.change_set_id','',true);
  v_cs:=public.begin_change_set(
    'task4_ordinary_undo','Task 4 ordinary narrative undo','person',-91524020
  );
  UPDATE public.narrative SET tekst='Ordinary after' WHERE id=-91524120;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_fortryd_change_set(v_cs,false);
  IF (SELECT tekst FROM public.narrative WHERE id=-91524120)
       IS DISTINCT FROM 'Ordinary before' THEN
    RAISE EXCEPTION 'TASK4_GENERIC_UNDO_ORDINARY_CASE_REGRESSED';
  END IF;

  -- A publication event's own change set is routed away from generic undo
  -- before a reversal change set can be inserted.
  SELECT event.change_set_id INTO STRICT v_cs
    FROM private.narrative_publication_event event
   WHERE event.id=v_event_legacy_reversal;
  PERFORM set_config('app.change_set_id','',true);
  v_before:=pg_temp.task4_write_snapshot();
  BEGIN
    PERFORM public.red_fortryd_change_set(v_cs,false);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  v_after:=pg_temp.task4_write_snapshot();
  IF v_error IS DISTINCT FROM 'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED'
     OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'TASK4_GENERIC_UNDO_DIRECT_EVENT_GUARD_FAILED: %',v_error;
  END IF;

  -- A pre-cutover/C3-shaped narrative change set is also blocked once the
  -- narrative is represented by a later baseline event.
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
  VALUES (-91524030,false,false,false,'Task 4 C3 baseline');
  PERFORM pg_temp.task2_seed_record(
    '15240000-0000-0000-0000-000000000103','task4-c3-baseline',
    '15240000-0000-0000-0000-000000000203',
    '15240000-0000-0000-0000-000000000303',
    '15240000-0000-0000-0000-000000000403',43
  );
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,side,privat
  ) VALUES (
    -91524130,'person',-91524030,-91521001,'C3 before','43',false
  );
  PERFORM set_config('app.change_set_id','',true);
  v_cs:=public.begin_change_set(
    'task4_c3_pre_cutover','Task 4 pre-cutover C3 change','person',-91524030
  );
  UPDATE public.narrative SET tekst='C3 after' WHERE id=-91524130;
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO private.narrative_record_publication(
    id,narrative_id,source_record_id,record_label,citation_label,status
  ) VALUES (
    '15240000-0000-0000-0000-000000001103',-91524130,
    '15240000-0000-0000-0000-000000000103','Task 4 C3 record',
    'DAA Task 2, s. 43','published'
  );
  v_baseline_state:=private.narrative_publication_state(
    -91524030,-91521001,'task4-c3-baseline'
  );
  v_baseline_hash:=encode(
    extensions.digest(v_baseline_state::text,'sha256'),'hex'
  );
  v_baseline_cs:=public.begin_change_set(
    'task4_c3_baseline','Task 4 C3 baseline','person',-91524030
  );
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,binding_id,
    narrative_id,source_id,source_record_id,decision_basis,before_state,
    after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name
  ) VALUES (
    v_baseline_event,v_baseline_cs,
    '15240000-0000-0000-0000-000000001103',1,'baseline',
    '15240000-0000-0000-0000-000000001103',-91524130,-91521001,
    '15240000-0000-0000-0000-000000000103','Task 4 C3 baseline',
    v_baseline_state,v_baseline_state,v_baseline_hash,v_baseline_hash,
    v_actor,'Task 4 actor'
  );
  PERFORM set_config('app.change_set_id','',true);
  v_before:=pg_temp.task4_write_snapshot();
  v_error:=NULL;
  BEGIN
    PERFORM public.red_fortryd_change_set(v_cs,false);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  v_after:=pg_temp.task4_write_snapshot();
  IF v_error IS DISTINCT FROM 'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED'
     OR v_after IS DISTINCT FROM v_before
     OR (SELECT tekst FROM public.narrative WHERE id=-91524130)
          IS DISTINCT FROM 'C3 after' THEN
    RAISE EXCEPTION 'TASK4_GENERIC_UNDO_HISTORIC_BASELINE_GUARD_FAILED: %',v_error;
  END IF;

  -- Preview exposes only a count/block flag, and hard-delete rejects before
  -- begin_change_set or any domain write.
  v_preview:=public.red_slet_person_preview(-91524030);
  IF (v_preview->>'antal_publication_events')::integer IS DISTINCT FROM 1
     OR (v_preview->>'sletning_blokeret')::boolean IS DISTINCT FROM true
     OR v_preview ? 'publication_events'
     OR v_preview::text LIKE '%'||v_baseline_event::text||'%' THEN
    RAISE EXCEPTION 'TASK4_PERSON_DELETE_PREVIEW_CONTRACT_INVALID: %',v_preview;
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_before:=pg_temp.task4_write_snapshot();
  v_error:=NULL;
  BEGIN
    PERFORM public.red_slet_person(-91524030);
  EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM;
  END;
  v_after:=pg_temp.task4_write_snapshot();
  IF v_error IS DISTINCT FROM 'PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY'
     OR v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'TASK4_PERSON_DELETE_PREWRITE_BLOCK_FAILED: %',v_error;
  END IF;

  RAISE NOTICE 'OK: narrative record Task 4 withdrawal, reversal, undo and delete behavior';
END
$narrative_record_task4_behavior$;

ROLLBACK TO SAVEPOINT narrative_record_task4_version_2;
DO $narrative_record_task4_version_restored$
BEGIN
  IF public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK4_TEST_WEAKENED_PRODUCTION_VERSION';
  END IF;
  RAISE NOTICE 'OK: narrative record Task 4 version-2 fixture rolled back to version 1';
END
$narrative_record_task4_version_restored$;

-- Task 5: one semantic publication predicate must gate both public RPCs and
-- direct narrative RLS. Version 1 remains byte-compatible until cutover;
-- version 2 is exercised only below a savepoint that is rolled back.
DO $narrative_record_task5_structure$
DECLARE
  v_signature text;
  v_definition text;
  v_owner text;
  v_expected_owner oid;
  v_function_owner oid;
  v_role text;
  v_privilege text;
  v_policy text;
BEGIN
  IF to_regprocedure('public.person_daa_narrative_publication_allowed(bigint)')
       IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_PUBLICATION_PREDICATE_MISSING';
  END IF;
  IF to_regprocedure(
       'public.public_person_bio_source_versions_v2(bigint[])'
     ) IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_V2_RPC_MISSING';
  END IF;

  IF pg_get_function_result(
       'public.public_person_bio_source_versions_v2(bigint[])'::regprocedure
     ) IS DISTINCT FROM
       'TABLE(person_id bigint, source_id bigint, source_year integer, record_order integer, source_record_ref uuid, source_label text, record_label text, narrative_text text, citation_label text, provenance_kind text)' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_V2_SIGNATURE_INVALID: %',
      pg_get_function_result(
        'public.public_person_bio_source_versions_v2(bigint[])'::regprocedure
      );
  END IF;

  SELECT relation.relowner INTO v_expected_owner
    FROM pg_class relation WHERE relation.oid='public.narrative'::regclass;
  IF v_expected_owner IS DISTINCT FROM (
       SELECT relation.relowner FROM pg_class relation
        WHERE relation.oid='private.narrative_publication_event'::regclass
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_CONTROLLED_OWNER_SPLIT';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.person_daa_narrative_publication_allowed(bigint)',
    'public.public_person_bio_source_versions(bigint[])',
    'public.public_person_bio_source_versions_v2(bigint[])'
  ] LOOP
    SELECT function.proowner,role.rolname,function.prosecdef,
           function.proconfig=ARRAY['search_path=pg_catalog']::text[]
      INTO v_function_owner,v_owner,v_definition,v_policy
      FROM pg_proc function
      JOIN pg_roles role ON role.oid=function.proowner
     WHERE function.oid=v_signature::regprocedure;
    IF v_function_owner IS DISTINCT FROM v_expected_owner
       OR v_definition::boolean IS DISTINCT FROM true
       OR v_policy::boolean IS DISTINCT FROM true THEN
      RAISE EXCEPTION
        'NARRATIVE_RECORD_TASK5_FUNCTION_SECURITY_METADATA_INVALID: % owner=% definer=% path=%',
        v_signature,v_owner,v_definition,v_policy;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF NOT has_function_privilege(v_role,v_signature,'EXECUTE') THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_SAFE_EXECUTE_MISSING: % %',
          v_role,v_signature;
      END IF;
    END LOOP;
    IF EXISTS (
      SELECT 1
        FROM pg_proc function
        CROSS JOIN LATERAL aclexplode(
          coalesce(function.proacl,acldefault('f',function.proowner))
        ) acl
       WHERE function.oid=v_signature::regprocedure
         AND (
           acl.privilege_type<>'EXECUTE'
           OR acl.is_grantable
           OR acl.grantor<>v_expected_owner
           OR acl.grantee NOT IN (
             v_expected_owner,'anon'::regrole::oid,'authenticated'::regrole::oid
           )
         )
    ) OR (
      SELECT count(*)
        FROM pg_proc function
        CROSS JOIN LATERAL aclexplode(
          coalesce(function.proacl,acldefault('f',function.proowner))
        ) acl
       WHERE function.oid=v_signature::regprocedure
    )<>3 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_FUNCTION_ACL_NOT_EXACT: %',
        v_signature;
    END IF;
  END LOOP;

  SELECT pg_get_functiondef(
           'public.person_daa_narrative_publication_allowed(bigint)'::regprocedure
         ) INTO v_definition;
  IF strpos(v_definition,'private.narrative_publication_state(')=0
     OR strpos(v_definition,'private.narrative_legacy_publication_state(')=0
     OR strpos(v_definition,'private.narrative_record_state(')>0
     OR strpos(v_definition,'private.narrative_legacy_state(')>0 THEN
    RAISE EXCEPTION
      'NARRATIVE_RECORD_TASK5_PREDICATE_NOT_SEMANTIC_STATE_ONLY';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.public_person_bio_source_versions(bigint[])',
    'public.public_person_bio_source_versions_v2(bigint[])'
  ] LOOP
    SELECT pg_get_functiondef(v_signature::regprocedure) INTO v_definition;
    IF strpos(v_definition,'person_daa_narrative_publication_allowed')=0 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_RPC_BYPASSES_PREDICATE: %',
        v_signature;
    END IF;
  END LOOP;

  SELECT pg_get_expr(policy.polqual,policy.polrelid)
    INTO v_policy
    FROM pg_policy policy
   WHERE policy.polrelid='public.narrative'::regclass
     AND policy.polname='anon_read';
  IF strpos(coalesce(v_policy,''),'person_daa_narrative_publication_allowed')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_ANON_RLS_BYPASSES_PREDICATE: %',
      v_policy;
  END IF;
  SELECT pg_get_expr(policy.polqual,policy.polrelid)
    INTO v_policy
    FROM pg_policy policy
   WHERE policy.polrelid='public.narrative'::regclass
     AND policy.polname='auth_read';
  IF strpos(coalesce(v_policy,''),'person_daa_narrative_publication_allowed')=0 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_AUTH_RLS_BYPASSES_PREDICATE: %',
      v_policy;
  END IF;
  IF NOT (
    SELECT relation.relrowsecurity AND NOT relation.relforcerowsecurity
      FROM pg_class relation WHERE relation.oid='public.narrative'::regclass
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_NARRATIVE_RLS_FORCE_EXPECTATION_INVALID';
  END IF;

  FOREACH v_signature IN ARRAY ARRAY[
    'private.narrative_record_publication',
    'private.narrative_publication_event',
    'private.narrative_legacy_publication'
  ] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
        IF has_table_privilege(v_role,v_signature,v_privilege) THEN
          RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_PRIVATE_TABLE_GRANT: % % %',
            v_role,v_signature,v_privilege;
        END IF;
      END LOOP;
    END LOOP;
    IF EXISTS (
      SELECT 1
        FROM pg_class relation
        CROSS JOIN LATERAL aclexplode(
          coalesce(relation.relacl,acldefault('r',relation.relowner))
        ) acl
       WHERE relation.oid=v_signature::regclass
         AND acl.grantee=0
         AND acl.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    ) THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_PRIVATE_TABLE_GRANT: % %',
          'PUBLIC',v_signature;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: narrative record Task 5 typed public contract and security metadata';
END
$narrative_record_task5_structure$;

CREATE FUNCTION pg_temp.task5_v1_texts(p_person_id bigint)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
  SELECT coalesce(array_agg(row.narrative_text ORDER BY row.narrative_text),ARRAY[]::text[])
    FROM public.public_person_bio_source_versions(ARRAY[p_person_id]) row
$$;
CREATE FUNCTION pg_temp.task5_v2_texts(p_person_id bigint)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
  SELECT coalesce(array_agg(row.narrative_text ORDER BY row.narrative_text),ARRAY[]::text[])
    FROM public.public_person_bio_source_versions_v2(ARRAY[p_person_id]) row
$$;
CREATE FUNCTION pg_temp.task5_direct_narrative_ids(p_ids bigint[])
RETURNS bigint[]
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
  SELECT coalesce(array_agg(narrative.id ORDER BY narrative.id),ARRAY[]::bigint[])
    FROM public.narrative narrative WHERE narrative.id=ANY(p_ids)
$$;
CREATE FUNCTION pg_temp.task5_direct_event_ids(p_ids bigint[])
RETURNS bigint[]
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=pg_catalog
AS $$
  SELECT coalesce(array_agg(event.id ORDER BY event.id),ARRAY[]::bigint[])
    FROM public.haendelse event WHERE event.id=ANY(p_ids)
$$;
GRANT EXECUTE ON FUNCTION pg_temp.task5_v1_texts(bigint),
  pg_temp.task5_v2_texts(bigint),
  pg_temp.task5_direct_narrative_ids(bigint[]),
  pg_temp.task5_direct_event_ids(bigint[])
  TO anon,authenticated;

-- Extend the Task 2 fixtures with the cases that are meaningful only at the
-- public/RLS boundary: a never-baselined unbound row and unaffected controls.
INSERT INTO public.source(id,slags,titel,udgave,aar)
VALUES (-91525002,'test','Task 5 non-DAA source','Task 5 control',2025);
INSERT INTO public.narrative(
  id,subjekt_type,subjekt_id,source_id,tekst,side,privat
) VALUES
  (-91521204,'person',-91521001,-91521001,'New unbound','23',false),
  (-91521210,'source',-91521001,-91521001,'Non-person control','24',false),
  (-91521211,'person',-91521001,-91525002,'Non-DAA person control','25',false),
  (-91521212,'source',-91521001,-91521001,'Private non-person control','26',true);
INSERT INTO private.extraction_run(
  id,source_id,run_key,schema_version,extractor_version,profile_version,
  input_sha256,manifest
) VALUES (
  '15250000-0000-0000-0000-000000000101',-91525002,'task5-non-daa-run',
  '1','task5-test','task5-test',repeat('5',64),'{}'
);
INSERT INTO private.source_rendition(
  id,source_id,rendition_key,rendition_kind,content_sha256,metadata
) VALUES (
  '15250000-0000-0000-0000-000000000102',-91525002,
  'task5-non-daa-rendition','text_layer',repeat('6',64),'{}'
);
INSERT INTO private.source_record(
  id,source_id,record_key,record_kind,created_run_id
) VALUES (
  '15250000-0000-0000-0000-000000000103',-91525002,
  'task5-non-daa-record','person',
  '15250000-0000-0000-0000-000000000101'
);
INSERT INTO private.source_record_occurrence(
  id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id
) VALUES (
  '15250000-0000-0000-0000-000000000104',
  '15250000-0000-0000-0000-000000000102','task5-non-daa-occurrence',
  25,25,0,22,'Non-DAA person control','task5-non-daa-physical',
  'task5-non-daa-structural','15250000-0000-0000-0000-000000000101'
);
INSERT INTO private.source_record_anchor_event(
  id,occurrence_id,source_record_id,decision_status,evidence,version,
  decided_by,decided_by_name
) VALUES (
  '15250000-0000-0000-0000-000000000105',
  '15250000-0000-0000-0000-000000000104',
  '15250000-0000-0000-0000-000000000103','accepted',
  '{"basis":"Task 5 non-DAA control"}',1,
  '15200000-0000-0000-0000-000000000001','Task 5 actor'
);
INSERT INTO private.narrative_record_publication(
  id,narrative_id,source_record_id,record_label,citation_label,status,
  published_at
) VALUES (
  '15250000-0000-0000-0000-000000000106',-91521211,
  '15250000-0000-0000-0000-000000000103','Non-DAA control record',
  'Non-DAA control citation','published',clock_timestamp()
);
DO $narrative_record_task5_non_daa_attestation$
DECLARE
  v_state jsonb;
  v_hash text;
BEGIN
  v_state:=private.narrative_publication_state(
    -91521001,-91525002,'task5-non-daa-record'
  );
  v_hash:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,binding_id,
    narrative_id,source_id,source_record_id,decision_basis,before_state,
    after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name
  ) VALUES (
    '15250000-0000-0000-0000-000000000107',-91521001,
    '15250000-0000-0000-0000-000000000106',1,'published',
    '15250000-0000-0000-0000-000000000106',-91521211,-91525002,
    '15250000-0000-0000-0000-000000000103','Task 5 non-DAA attestation',
    v_state,v_state,v_hash,v_hash,
    '15200000-0000-0000-0000-000000000001','Task 5 actor'
  );
END
$narrative_record_task5_non_daa_attestation$;
-- Review 37 A2: gem tilstanden for den publicerede tekst FØR hændelserne, så det kan bevises, at de ikke
-- ændrer publiceringstilstanden (synlighed), men kun editor-låsen (text_editable/token).
CREATE TEMP TABLE task5_a2_before ON COMMIT DROP AS
SELECT private.narrative_publication_state(-91521001,-91521001,'published') AS publication_state,
       private.narrative_record_state(-91521001,-91521001,'published',false) AS editor_state;
INSERT INTO public.haendelse(
  id,subjekt_type,subjekt_id,narrative_id,noegle,klausul,feed_status
) VALUES
  (-91521290,'person',-91521001,-91521190,'task5-invalid','Invalid stale event','interessant'),
  (-91521291,'person',-91521001,-91521180,'task5-valid','Valid published event','interessant'),
  (-91521292,'source',-91521001,-91521210,'task5-control','Unaffected event','interessant');
DO $narrative_record_task5_revalidate_event_projection$
DECLARE
  v_state jsonb;
  v_hash text;
  v_before jsonb;
  v_before_editor jsonb;
  v_editor jsonb;
BEGIN
  -- Review 37 A2: has_haendelse er udfaset. En afledt hændelse ændrer ikke publiceringstilstanden, så den
  -- publicerede tekst forbliver synlig uden revalidering; kun editor-låsen (text_editable) og dermed
  -- editor-kuvertens token skifter.
  v_state:=private.narrative_publication_state(
    -91521001,-91521001,'published'
  );
  v_hash:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  v_before:=(SELECT before.publication_state FROM task5_a2_before before);
  v_before_editor:=(SELECT before.editor_state FROM task5_a2_before before);
  IF v_state->>'has_haendelse' IS DISTINCT FROM 'false'
     OR v_state #>> '{narrative,has_haendelse}' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_A2_HAS_HAENDELSE_NOT_FALSE: %',v_state;
  END IF;
  IF v_state IS DISTINCT FROM v_before
     OR v_hash IS DISTINCT FROM (
       SELECT event.after_state_sha256 FROM private.narrative_publication_event event
        WHERE event.stream_ref='15210000-0000-0000-0000-000000001180'
        ORDER BY event.stream_version DESC LIMIT 1
     ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_A2_EVENT_CHANGED_PUBLICATION_STATE';
  END IF;
  SET LOCAL ROLE anon;
  IF NOT 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR NOT 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001))
     OR NOT -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180])) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_A2_EVENT_HID_PUBLISHED_TEXT';
  END IF;
  SET LOCAL ROLE NONE;
  v_editor:=private.narrative_record_state(-91521001,-91521001,'published',false);
  IF v_before_editor->>'publication_status' IS DISTINCT FROM 'published'
     OR v_before_editor->>'text_editable' IS DISTINCT FROM 'true'
     OR v_editor->>'publication_status' IS DISTINCT FROM 'published'
     OR v_editor->>'text_editable' IS DISTINCT FROM 'false'
     OR v_editor->'allowed_actions' IS DISTINCT FROM '["withdraw"]'::jsonb
     OR v_editor->>'state_sha256' IS NOT DISTINCT FROM v_before_editor->>'state_sha256' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_A2_EDITOR_LOCK_INVALID: before=% after=%',
      v_before_editor,v_editor;
  END IF;
  -- Fjernes den sidste hændelse igen, er låsen væk, og editor-tokenet er det oprindelige (rulles tilbage).
  BEGIN
    DELETE FROM public.haendelse WHERE id=-91521291;
    IF private.narrative_record_state(-91521001,-91521001,'published',false)->>'state_sha256'
         IS DISTINCT FROM v_before_editor->>'state_sha256'
       OR private.narrative_publication_state(-91521001,-91521001,'published') IS DISTINCT FROM v_before THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_A2_LAST_EVENT_REMOVAL_INVALID';
    END IF;
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  END;
  -- Den efterfølgende drift-matrix bruger 2183 som seneste attestation. Revalideringen er ikke længere
  -- påkrævet af hændelsen; den attesterer den uændrede tilstand.
  RAISE NOTICE 'OK: review 37 A2 — hændelse bevarer synlighed og publiceringstilstand, låser kun redigering';
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,binding_id,
    narrative_id,source_id,source_record_id,decision_basis,before_state,
    after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name,created_at
  ) VALUES (
    '15210000-0000-0000-0000-000000002183',-91521001,
    '15210000-0000-0000-0000-000000001180',3,'revalidated',
    '15210000-0000-0000-0000-000000001180',-91521180,-91521001,
    '15210000-0000-0000-0000-000000000180','Task 5 event revalidation',
    v_state,v_state,v_hash,v_hash,
    '15200000-0000-0000-0000-000000000001','Task 5 actor',
    '2026-08-29 12:20:00+02'::timestamptz
  );
END
$narrative_record_task5_revalidate_event_projection$;

DO $narrative_record_task5_version1_matrix$
DECLARE
  v_person bigint:=-91521001;
  v_member uuid:='15210000-0000-0000-0000-000000000001';
  v_redactor uuid:='15200000-0000-0000-0000-000000000001';
  v_expected_rpc text[]:=ARRAY[
    'After drift','Legacy active','Legacy after drift','Legacy withdrawn',
    'New unbound','Published text'
  ];
  v_all_ids bigint[]:=ARRAY[
    -91521212,-91521211,-91521210,-91521204,-91521203,-91521202,
    -91521201,-91521190,-91521181,-91521180,-91521170,-91521160,-91521150
  ];
  v_public_ids bigint[]:=ARRAY[
    -91521211,-91521210,-91521204,-91521203,-91521202,-91521201,
    -91521190,-91521181,-91521180,-91521170,-91521160,-91521150
  ];
  v_all_events bigint[]:=ARRAY[-91521292,-91521291,-91521290];
  v_actual_texts text[];
  v_actual_ids bigint[];
BEGIN
  IF public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION1_MATRIX_VERSION_INVALID';
  END IF;

  SET LOCAL ROLE anon;
  v_actual_texts:=pg_temp.task5_v1_texts(v_person);
  IF v_actual_texts IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_v2_texts(v_person) IS DISTINCT FROM v_expected_rpc THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION1_ANON_RPC_DRIFT: %',v_actual_texts;
  END IF;
  v_actual_ids:=pg_temp.task5_direct_narrative_ids(v_all_ids);
  IF v_actual_ids IS DISTINCT FROM v_public_ids
     OR pg_temp.task5_direct_event_ids(v_all_events)
          IS DISTINCT FROM v_all_events THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION1_ANON_RLS_DRIFT: %',v_actual_ids;
  END IF;
  SET LOCAL ROLE NONE;

  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  SET LOCAL ROLE authenticated;
  IF pg_temp.task5_v1_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_v2_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_direct_narrative_ids(v_all_ids) IS DISTINCT FROM v_public_ids
     OR pg_temp.task5_direct_event_ids(v_all_events) IS DISTINCT FROM v_all_events THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION1_AUTH_MATRIX_DRIFT';
  END IF;
  SET LOCAL ROLE NONE;

  PERFORM set_config('request.jwt.claim.sub',v_redactor::text,true);
  SET LOCAL ROLE authenticated;
  IF pg_temp.task5_v1_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_v2_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_direct_narrative_ids(v_all_ids) IS DISTINCT FROM v_all_ids
     OR pg_temp.task5_direct_event_ids(v_all_events) IS DISTINCT FROM v_all_events THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION1_REDACTION_MATRIX_DRIFT';
  END IF;
  SET LOCAL ROLE NONE;
  RAISE NOTICE 'OK: narrative record Task 5 version-1 public and redaction behavior preserved';
END
$narrative_record_task5_version1_matrix$;

SAVEPOINT narrative_record_task5_version_2;
CREATE OR REPLACE FUNCTION public.narrative_record_contract_version()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=pg_catalog
AS $$ SELECT 2 $$;

-- Two active legacy rows in the same person/source have identical public sort
-- fields. Their internal ledger refs must still make the RPC order total and
-- deterministic without exposing that private tie-break.
DO $narrative_record_task5_second_legacy_fixture$
DECLARE
  v_ref uuid:='15210000-0000-0000-0000-000000000200';
  v_event uuid:='15250000-0000-0000-0000-000000000200';
  v_policy jsonb;
  v_state jsonb;
  v_hash text;
BEGIN
  INSERT INTO public.narrative(
    id,subjekt_type,subjekt_id,source_id,tekst,side,privat
  ) VALUES (
    -91521205,'person',-91521001,-91521001,'Legacy stable first','19',false
  );
  v_policy:=jsonb_build_object(
    'person_levende',false,'person_private',false,'person_staged',false,
    'narrative_private',false,'person_publication_allowed',true,
    'narrative_publication_allowed',true,'publication_allowed',true
  );
  v_state:=jsonb_build_object(
    'target',jsonb_build_object(
      'legacy_publication_ref',v_ref,'narrative_id',-91521205,
      'person_id',-91521001,'source_id',-91521001
    ),
    'source',jsonb_build_object('source_year',1939,'source_label','DAA Task 2'),
    'narrative',jsonb_build_object(
      'narrative_id',-91521205,'text','Legacy stable first',
      'text_sha256',encode(
        extensions.digest('Legacy stable first','sha256'),'hex'
      ),
      'private',false,'side','19','has_haendelse',false
    ),
    'publication_policy',v_policy,
    'policy_sha256',encode(extensions.digest(v_policy::text,'sha256'),'hex'),
    'has_haendelse',false
  );
  v_hash:=encode(extensions.digest(v_state::text,'sha256'),'hex');
  INSERT INTO private.narrative_legacy_publication(
    legacy_publication_ref,narrative_id,source_id,baseline_state,
    baseline_sha256,status,created_at
  ) VALUES (
    v_ref,-91521205,-91521001,v_state,v_hash,
    'grandfathered_publication','2026-08-29 12:30:00+02'
  );
  INSERT INTO private.narrative_publication_event(
    id,change_set_id,stream_ref,stream_version,event_type,
    legacy_publication_ref,narrative_id,source_id,decision_basis,before_state,
    after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name,created_at
  ) VALUES (
    v_event,-91521001,v_ref,1,'baseline',v_ref,-91521205,-91521001,
    'Task 5 stable legacy order',v_state,v_state,v_hash,v_hash,
    '15200000-0000-0000-0000-000000000001','Task 5 actor',
    '2026-08-29 12:31:00+02'
  );
  UPDATE private.narrative_legacy_publication SET latest_event_id=v_event
   WHERE legacy_publication_ref=v_ref;
END
$narrative_record_task5_second_legacy_fixture$;

DO $narrative_record_task5_version2_matrix$
DECLARE
  v_person bigint:=-91521001;
  v_member uuid:='15210000-0000-0000-0000-000000000001';
  v_redactor uuid:='15200000-0000-0000-0000-000000000001';
  v_expected_rpc text[]:=ARRAY[
    'Legacy active','Legacy stable first','Published text'
  ];
  v_expected_v2_order text[]:=ARRAY[
    'Published text','Legacy stable first','Legacy active'
  ];
  v_all_ids bigint[]:=ARRAY[
    -91521212,-91521211,-91521210,-91521205,-91521204,-91521203,-91521202,
    -91521201,-91521190,-91521181,-91521180,-91521170,-91521160,-91521150
  ];
  v_public_ids bigint[]:=ARRAY[
    -91521211,-91521210,-91521205,-91521201,-91521180
  ];
  v_all_events bigint[]:=ARRAY[-91521292,-91521291,-91521290];
  v_public_events bigint[]:=ARRAY[-91521292,-91521291];
  v_actual record;
  v_actual_v2_order text[];
BEGIN
  SET LOCAL ROLE anon;
  IF pg_temp.task5_v1_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_v2_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_direct_narrative_ids(v_all_ids) IS DISTINCT FROM v_public_ids
     OR pg_temp.task5_direct_event_ids(v_all_events) IS DISTINCT FROM v_public_events THEN
    RAISE EXCEPTION
      'NARRATIVE_RECORD_TASK5_VERSION2_ANON_MATRIX_INVALID: v1=% v2=% narrative=% event=%',
      pg_temp.task5_v1_texts(v_person),pg_temp.task5_v2_texts(v_person),
      pg_temp.task5_direct_narrative_ids(v_all_ids),
      pg_temp.task5_direct_event_ids(v_all_events);
  END IF;
  SET LOCAL ROLE NONE;

  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  SET LOCAL ROLE authenticated;
  IF pg_temp.task5_v1_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_v2_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_direct_narrative_ids(v_all_ids) IS DISTINCT FROM v_public_ids
     OR pg_temp.task5_direct_event_ids(v_all_events) IS DISTINCT FROM v_public_events THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION2_AUTH_MATRIX_INVALID';
  END IF;
  SET LOCAL ROLE NONE;

  PERFORM set_config('request.jwt.claim.sub',v_redactor::text,true);
  SET LOCAL ROLE authenticated;
  IF pg_temp.task5_v1_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_v2_texts(v_person) IS DISTINCT FROM v_expected_rpc
     OR pg_temp.task5_direct_narrative_ids(v_all_ids) IS DISTINCT FROM v_all_ids
     OR pg_temp.task5_direct_event_ids(v_all_events) IS DISTINCT FROM v_all_events THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_VERSION2_REDACTION_MATRIX_INVALID';
  END IF;
  SET LOCAL ROLE NONE;

  SELECT array_agg(row.narrative_text ORDER BY row.ordinality)
    INTO v_actual_v2_order
    FROM public.public_person_bio_source_versions_v2(ARRAY[v_person])
      WITH ORDINALITY AS row;
  IF v_actual_v2_order IS DISTINCT FROM v_expected_v2_order THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_V2_ORDER_NOT_TOTAL: %',
      v_actual_v2_order;
  END IF;

  SELECT * INTO v_actual
    FROM public.public_person_bio_source_versions_v2(ARRAY[v_person]) row
   WHERE row.narrative_text='Published text';
  IF v_actual.source_id IS DISTINCT FROM -91521001
     OR v_actual.source_year IS DISTINCT FROM 1939
     OR v_actual.record_order IS DISTINCT FROM 9
     OR v_actual.source_record_ref IS NULL
     OR v_actual.record_label IS DISTINCT FROM 'Existing published'
     OR v_actual.narrative_text IS DISTINCT FROM (
       SELECT event.after_state #>> '{narrative,text}'
         FROM private.narrative_publication_event event
        WHERE event.id='15210000-0000-0000-0000-000000002183'
     )
     OR v_actual.provenance_kind IS DISTINCT FROM 'source_record' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_V2_BOUND_MAPPING_INVALID: %',
      to_jsonb(v_actual);
  END IF;
  IF EXISTS (
    SELECT 1
      FROM jsonb_object_keys(to_jsonb(v_actual)) key
     WHERE key IN (
       'record_key','source_record_id','binding_id','source_persona_id',
       'identity_people','publication_policy','policy_sha256','state_sha256'
     )
  ) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_V2_PRIVATE_FIELD_LEAK';
  END IF;
  RAISE NOTICE 'OK: narrative record Task 5 version-2 anon/auth/redaction matrix';
  RAISE NOTICE 'OK: narrative record Task 5 draft/withdrawn/unbound/legacy and event cascade';
END
$narrative_record_task5_version2_matrix$;

-- Each stale dimension must independently remove the once-valid published
-- record from v1, v2 and direct anon RLS. Roll back every mutation so the next
-- dimension starts from the exact same attested semantic state.
SAVEPOINT narrative_record_task5_anchor_drift;
INSERT INTO private.source_record_anchor_event(
  id,occurrence_id,source_record_id,decision_status,evidence,version,
  decided_by,decided_by_name
) VALUES (
  '15250000-0000-0000-0000-000000000001',
  '15210000-0000-0000-0000-000000000380',
  '15210000-0000-0000-0000-000000000180','rejected',
  '{"basis":"Task 5 anchor drift"}',2,
  '15200000-0000-0000-0000-000000000001','Task 5 actor'
);
DO $task5_anchor_drift$
BEGIN
  IF 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_ANCHOR_RPC_VISIBLE';
  END IF;
  SET LOCAL ROLE anon;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180])) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_ANCHOR_RLS_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15210000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_ANCHOR_AUTH_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF NOT -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_ANCHOR_REDACTION_INVALID';
  END IF;
  SET LOCAL ROLE NONE;
END
$task5_anchor_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_anchor_drift;

SAVEPOINT narrative_record_task5_rendition_drift;
SET LOCAL session_replication_role=replica;
UPDATE private.source_rendition
   SET content_sha256=repeat('9',64)
 WHERE id='15210000-0000-0000-0000-000000000003';
SET LOCAL session_replication_role=origin;
DO $task5_rendition_drift$
BEGIN
  IF 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_RENDITION_RPC_VISIBLE';
  END IF;
  SET LOCAL ROLE anon;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180])) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_RENDITION_RLS_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15210000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_RENDITION_AUTH_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF NOT -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_RENDITION_REDACTION_INVALID';
  END IF;
  SET LOCAL ROLE NONE;
END
$task5_rendition_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_rendition_drift;

SAVEPOINT narrative_record_task5_identity_drift;
SELECT pg_temp.task2_seed_identity(
  '15210000-0000-0000-0000-000000000180',
  '15210000-0000-0000-0000-000000000580',
  '15250000-0000-0000-0000-000000000010',
  '15250000-0000-0000-0000-000000000011',
  '15250000-0000-0000-0000-000000000012',
  '15250000-0000-0000-0000-000000000013',
  '15250000-0000-0000-0000-000000000014',
  -91521002,'principal_member',-91521002
);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $task5_identity_drift$
BEGIN
  IF 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_IDENTITY_RPC_VISIBLE';
  END IF;
  SET LOCAL ROLE anon;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180])) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_IDENTITY_RLS_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15210000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_IDENTITY_AUTH_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF NOT -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_IDENTITY_REDACTION_INVALID';
  END IF;
  SET LOCAL ROLE NONE;
END
$task5_identity_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_identity_drift;

SAVEPOINT narrative_record_task5_privacy_drift;
UPDATE public.narrative SET privat=true WHERE id=-91521180;
DO $task5_privacy_drift$
BEGIN
  IF 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_PRIVACY_RPC_VISIBLE';
  END IF;
  SET LOCAL ROLE anon;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180])) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_PRIVACY_RLS_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15210000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_PRIVACY_AUTH_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF NOT -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_PRIVACY_REDACTION_INVALID';
  END IF;
  SET LOCAL ROLE NONE;
END
$task5_privacy_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_privacy_drift;

SAVEPOINT narrative_record_task5_policy_drift;
UPDATE public.person SET staged=true WHERE id=-91521001;
DO $task5_policy_drift$
BEGIN
  IF 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_POLICY_RPC_VISIBLE';
  END IF;
  SET LOCAL ROLE anon;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180])) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_POLICY_RLS_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15210000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_POLICY_AUTH_VISIBLE';
  END IF;
  SET LOCAL ROLE NONE;
  PERFORM set_config(
    'request.jwt.claim.sub','15200000-0000-0000-0000-000000000001',true
  );
  SET LOCAL ROLE authenticated;
  IF NOT -91521180=ANY(pg_temp.task5_direct_narrative_ids(ARRAY[-91521180]))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_STALE_POLICY_REDACTION_INVALID';
  END IF;
  SET LOCAL ROLE NONE;
END
$task5_policy_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_policy_drift;

SAVEPOINT narrative_record_task5_event_hash_drift;
SET LOCAL session_replication_role=replica;
UPDATE private.narrative_publication_event
   SET after_state_sha256=repeat('f',64)
 WHERE id='15210000-0000-0000-0000-000000002183';
SET LOCAL session_replication_role=origin;
DO $task5_event_hash_drift$
BEGIN
  IF 'Published text'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Published text'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_EVENT_HASH_MISMATCH_VISIBLE';
  END IF;
END
$task5_event_hash_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_event_hash_drift;

SAVEPOINT narrative_record_task5_legacy_hash_drift;
SET LOCAL session_replication_role=replica;
UPDATE private.narrative_legacy_publication
   SET baseline_sha256=repeat('e',64)
 WHERE legacy_publication_ref='15210000-0000-0000-0000-000000000201';
SET LOCAL session_replication_role=origin;
DO $task5_legacy_hash_drift$
BEGIN
  IF 'Legacy active'=ANY(pg_temp.task5_v1_texts(-91521001))
     OR 'Legacy active'=ANY(pg_temp.task5_v2_texts(-91521001)) THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_LEGACY_HASH_MISMATCH_VISIBLE';
  END IF;
  RAISE NOTICE 'OK: narrative record Task 5 semantic stale-axis matrix';
END
$task5_legacy_hash_drift$;
ROLLBACK TO SAVEPOINT narrative_record_task5_legacy_hash_drift;

ROLLBACK TO SAVEPOINT narrative_record_task5_version_2;
DO $narrative_record_task5_version_restored$
BEGIN
  IF public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK5_TEST_WEAKENED_PRODUCTION_VERSION';
  END IF;
  RAISE NOTICE 'OK: narrative record Task 5 version-2 fixture rolled back to version 1';
END
$narrative_record_task5_version_restored$;

ROLLBACK;

-- Task 3 policy serialization: the canonical writer lock must cover the person
-- row whose levende/privat/staged values are hashed into publication_policy.
-- This committed disposable fixture is required because both dblink sessions
-- must observe it; the exception handler removes it on both RED and GREEN paths.
SET search_path TO public,private,extensions,pg_catalog;
DO $narrative_record_task3_person_policy_lock$
DECLARE
  v_conn text:=format(
    'dbname=%s port=%s host=%s user=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1),session_user
  );
  v_person_id bigint:=-91523001;
  v_source_id bigint:=-91523001;
  v_actor uuid:='15230000-0000-0000-0000-000000000099';
  v_record_id uuid:='15230000-0000-0000-0000-000000000001';
  v_run_id uuid:='15230000-0000-0000-0000-000000000002';
  v_writer_result jsonb;
  v_event_type text;
  v_attested_allowed boolean;
  v_chronology_predated boolean;
  v_latest_event_id uuid;
  v_before_event_count bigint;
  v_after_event_count bigint;
  v_before_change_count bigint;
  v_after_change_count bigint;
  v_undo_result text;
  v_original_error text;
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_deadline timestamptz;
  v_setup_connected boolean:=false;
  v_a_connected boolean:=false;
  v_b_connected boolean:=false;
  v_cleanup text:=$cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.narrative_publication_event
      WHERE source_record_id='15230000-0000-0000-0000-000000000001';
    DELETE FROM public.change_event
      WHERE change_set_id IN (
        SELECT id FROM public.change_set
         WHERE subjekt_type='person' AND subjekt_id=-91523001
      );
    DELETE FROM public.change_set
      WHERE subjekt_type='person' AND subjekt_id=-91523001;
    DELETE FROM private.narrative_record_publication
      WHERE source_record_id='15230000-0000-0000-0000-000000000001';
    DELETE FROM public.narrative
      WHERE subjekt_type='person' AND subjekt_id=-91523001 AND source_id=-91523001;
    DELETE FROM private.source_persona_identity
      WHERE source_persona_id='15230000-0000-0000-0000-000000000008';
    DELETE FROM private.source_persona_identity_event
      WHERE source_persona_id='15230000-0000-0000-0000-000000000008';
    DELETE FROM private.source_persona_placement_decision
      WHERE placement_id='15230000-0000-0000-0000-000000000012';
    DELETE FROM private.source_persona_placement
      WHERE id='15230000-0000-0000-0000-000000000012';
    DELETE FROM private.source_record_placement_decision
      WHERE placement_id='15230000-0000-0000-0000-000000000011';
    DELETE FROM private.source_record_placement
      WHERE id='15230000-0000-0000-0000-000000000011';
    DELETE FROM private.source_persona_mention
      WHERE persona_id='15230000-0000-0000-0000-000000000008';
    DELETE FROM private.source_mention
      WHERE id='15230000-0000-0000-0000-000000000009';
    DELETE FROM private.source_persona
      WHERE id='15230000-0000-0000-0000-000000000008';
    DELETE FROM private.source_observation
      WHERE id='15230000-0000-0000-0000-000000000007';
    DELETE FROM private.source_record_anchor_event
      WHERE source_record_id='15230000-0000-0000-0000-000000000001';
    DELETE FROM private.source_record_occurrence
      WHERE id='15230000-0000-0000-0000-000000000006';
    DELETE FROM private.source_record
      WHERE id='15230000-0000-0000-0000-000000000001';
    DELETE FROM private.source_rendition
      WHERE id='15230000-0000-0000-0000-000000000005';
    DELETE FROM private.extraction_run
      WHERE id='15230000-0000-0000-0000-000000000002';
    DELETE FROM public.lineage_scheme_entry WHERE id=-91523001;
    DELETE FROM public.lineage_scheme WHERE id=-91523001;
    DELETE FROM public.slaegt WHERE id=-91523001;
    DELETE FROM public.profiles WHERE id='15230000-0000-0000-0000-000000000099';
    DELETE FROM auth.users WHERE id='15230000-0000-0000-0000-000000000099';
    DELETE FROM public.source WHERE id=-91523001;
    DELETE FROM public.person WHERE id=-91523001;
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  IF to_regprocedure('extensions.dblink_connect(text,text)') IS NULL THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK3_DBLINK_REQUIRED';
  END IF;

  PERFORM extensions.dblink_connect('task3_policy_setup',v_conn);
  v_setup_connected:=true;
  PERFORM extensions.dblink_exec('task3_policy_setup',v_cleanup);
  PERFORM extensions.dblink_exec('task3_policy_setup',
    'INSERT INTO auth.users(id,email) VALUES '
    || '(''15230000-0000-0000-0000-000000000099'',''task3-policy@test.invalid'');'
    || 'INSERT INTO public.profiles(id,rolle,email) VALUES '
    || '(''15230000-0000-0000-0000-000000000099'',''redaktion'',''task3-policy@test.invalid'');'
    || 'INSERT INTO public.person(id,levende,privat,staged,visning_navn) '
    || 'VALUES (-91523001,false,false,false,''Task 3 policy lock'');'
    || 'INSERT INTO public.source(id,slags,titel,udgave,aar,import_key) '
    || 'VALUES (-91523001,''test'',''Task 3 policy lock'',''Task 3 policy'',1939,''task3:policy-lock'');'
    || 'INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) '
    || 'VALUES (-91523001,''Task 3 policy slægt'',''Task 3 policy slægt'',''task3-policy-lock'');'
    || 'INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) '
    || 'VALUES (-91523001,-91523001,-91523001,''stamtavle'',''Task 3 policy scheme'');'
    || 'INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) '
    || 'VALUES (-91523001,-91523001,-91523001,''A'',''Task 3 policy line'',1);'
    || 'INSERT INTO private.extraction_run('
    || 'id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) '
    || 'VALUES (''15230000-0000-0000-0000-000000000002'',-91523001,''task3-policy-lock'','
    || '''1'',''task3'',''task3'',''' || repeat('3',64) || ''',''{}'');'
    || 'INSERT INTO private.source_rendition('
    || 'id,source_id,rendition_key,rendition_kind,content_sha256,metadata) '
    || 'VALUES (''15230000-0000-0000-0000-000000000005'',-91523001,'
    || '''task3-policy-lock'',''text_layer'',''' || repeat('5',64) || ''',''{}'');'
    || 'INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) '
    || 'VALUES (''15230000-0000-0000-0000-000000000001'',-91523001,'
    || '''task3-policy-lock'',''person_entry'',''15230000-0000-0000-0000-000000000002'');'
    || 'INSERT INTO private.source_record_occurrence('
    || 'id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,'
    || 'physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES '
    || '(''15230000-0000-0000-0000-000000000006'',''15230000-0000-0000-0000-000000000005'','
    || '''task3-policy-lock'',1,1,0,20,''Task 3 policy occurrence'',''task3-policy-physical'','
    || '''task3-policy-structural'',''15230000-0000-0000-0000-000000000002'');'
    || 'INSERT INTO private.source_record_anchor_event('
    || 'occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) '
    || 'VALUES (''15230000-0000-0000-0000-000000000006'',''15230000-0000-0000-0000-000000000001'','
    || '''accepted'',''{"basis":"Task 3 policy anchor"}'',1,'
    || '''15230000-0000-0000-0000-000000000099'',''Task 3 policy actor'');'
    || 'INSERT INTO private.source_observation('
    || 'id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,'
    || 'quality_status,extraction_method,extraction_run_id) VALUES '
    || '(''15230000-0000-0000-0000-000000000007'',''15230000-0000-0000-0000-000000000006'','
    || '''header'',1,1,0,20,''Task 3 policy observation'',''clear'',''task3-test'','
    || '''15230000-0000-0000-0000-000000000002'');'
    || 'INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES '
    || '(''15230000-0000-0000-0000-000000000008'',-91523001,''task3-policy-persona'','
    || '''15230000-0000-0000-0000-000000000002'');'
    || 'INSERT INTO private.source_mention('
    || 'id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) VALUES '
    || '(''15230000-0000-0000-0000-000000000009'',''15230000-0000-0000-0000-000000000007'','
    || '''person_name'',0,4,''Task'',''15230000-0000-0000-0000-000000000002'');'
    || 'INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) '
    || 'VALUES (''15230000-0000-0000-0000-000000000008'',''15230000-0000-0000-0000-000000000009'','
    || '''primary'',1);'
    || 'INSERT INTO private.source_record_placement('
    || 'id,source_record_id,scheme_entry_id,header_observation_id,initial_status) VALUES '
    || '(''15230000-0000-0000-0000-000000000011'',''15230000-0000-0000-0000-000000000001'','
    || '-91523001,''15230000-0000-0000-0000-000000000007'',''accepted'');'
    || 'INSERT INTO private.source_record_placement_decision('
    || 'placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES '
    || '(''15230000-0000-0000-0000-000000000011'',1,''accepted'','
    || '''{"basis":"Task 3 policy placement"}'',''migration'',''Task 3 policy actor'');'
    || 'INSERT INTO private.source_persona_placement('
    || 'id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status) VALUES '
    || '(''15230000-0000-0000-0000-000000000012'',''15230000-0000-0000-0000-000000000008'','
    || '''15230000-0000-0000-0000-000000000011'',''principal_member'','
    || '''15230000-0000-0000-0000-000000000007'',''accepted'');'
    || 'INSERT INTO private.source_persona_placement_decision('
    || 'placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES '
    || '(''15230000-0000-0000-0000-000000000012'',1,''accepted'','
    || '''{"basis":"Task 3 policy persona placement"}'',''migration'',''Task 3 policy actor'');'
    || 'INSERT INTO private.source_persona_identity_event('
    || 'source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,'
    || 'decided_by_name,decided_at) VALUES '
    || '(''15230000-0000-0000-0000-000000000008'',-91523001,''accepted'',1,'
    || '''{"basis":"Task 3 policy identity"}'',''15230000-0000-0000-0000-000000000099'','
    || '''Task 3 policy actor'',now());'
    || 'INSERT INTO private.source_persona_identity('
    || 'source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,'
    || 'decided_by_name,decided_at) VALUES '
    || '(''15230000-0000-0000-0000-000000000008'',-91523001,''accepted'',1,'
    || '''{"basis":"Task 3 policy identity"}'',''15230000-0000-0000-0000-000000000099'','
    || '''Task 3 policy actor'',now())');

  PERFORM extensions.dblink_connect('task3_policy_a',v_conn);
  v_a_connected:=true;
  PERFORM extensions.dblink_connect('task3_policy_b',v_conn);
  v_b_connected:=true;
  SELECT pid INTO v_a_pid
    FROM extensions.dblink('task3_policy_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid
    FROM extensions.dblink('task3_policy_b','SELECT pg_backend_pid()') AS t(pid integer);

  -- Cross-transaction chronology: session A starts first, but the old v4
  -- withdrawn binding is inserted and committed afterwards. Any ordering by
  -- binding.created_at therefore misclassifies the later A stream as older.
  PERFORM extensions.dblink_exec('task3_policy_a','BEGIN');
  PERFORM started_at
    FROM extensions.dblink('task3_policy_a','SELECT now()')
      AS t(started_at timestamptz);
  PERFORM extensions.dblink_exec(
    'task3_policy_setup',
    'SET session_replication_role=replica;'
    || 'INSERT INTO public.narrative('
    || 'id,subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES '
    || '(-91523041,''person'',-91523001,-91523001,''1'',''Old v4 stream'',false);'
    || 'INSERT INTO private.narrative_record_publication('
    || 'id,narrative_id,source_record_id,record_label,citation_label,status) VALUES '
    || '(''15230000-0000-0000-0000-000000000041'',-91523041,'
    || '''15230000-0000-0000-0000-000000000001'',''Task 3 old record'','
    || '''Task 3 old citation'',''withdrawn'');'
    || 'WITH changes AS (SELECT public.begin_change_set('
    || '''task3_old_stream'',''Task 3 old v4 stream'',''person'',-91523001) AS id) '
    || 'INSERT INTO private.narrative_publication_event('
    || 'id,change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,'
    || 'source_id,source_record_id,decision_basis,before_state,after_state,'
    || 'before_state_sha256,after_state_sha256,decided_by,decided_by_name) SELECT '
    || '''15230000-0000-0000-0000-000000000042'',changes.id,'
    || '''15230000-0000-0000-0000-000000000041'',4,''draft_discarded'','
    || '''15230000-0000-0000-0000-000000000041'',-91523041,-91523001,'
    || '''15230000-0000-0000-0000-000000000001'',''Task 3 old stream fixture'','
    || '''{"fixture":"old-before"}'',''{"fixture":"old-after"}'','
    || '''' || repeat('4',64) || ''',''' || repeat('5',64) || ''','
    || '''15230000-0000-0000-0000-000000000099'',''Task 3 policy actor'' FROM changes;'
    || 'SET session_replication_role=origin'
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 2 $version$'
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'SET LOCAL "request.jwt.claim.sub"=' || quote_literal(v_actor::text)
  );
  SELECT result INTO v_writer_result
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT public.red_upsert_person_narrative_record('
      || '-91523001,-91523001,''task3-policy-lock'',''Predated fresh stream'',false,'
      || 'private.narrative_record_state('
      || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256'')'
    ) AS t(result jsonb);
  -- Resolve the fresh binding through the returned narrative because event_id
  -- and binding_id deliberately belong to different identifier domains.
  SELECT predated INTO v_chronology_predated
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT fresh.created_at<old.created_at '
      || 'FROM private.narrative_record_publication fresh '
      || 'JOIN private.narrative_record_publication old '
      || 'ON old.id=''15230000-0000-0000-0000-000000000041'' '
      || 'WHERE fresh.narrative_id=' || (v_writer_result->>'narrative_id')
    ) AS t(predated boolean);
  IF v_writer_result->>'status' IS DISTINCT FROM 'draft'
     OR v_chronology_predated IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CROSS_TRANSACTION_FIXTURE_INVALID';
  END IF;

  PERFORM value FROM extensions.dblink(
    'task3_policy_a','SELECT set_config(''app.change_set_id'','''',true)'
  ) AS t(value text);
  SELECT result INTO v_writer_result
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT public.red_kasser_person_narrative_record('
      || '-91523001,-91523001,''task3-policy-lock'',private.narrative_record_state('
      || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256'')'
    ) AS t(result jsonb);
  SELECT latest_event_id INTO v_latest_event_id
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT (private.narrative_record_state('
      || '-91523001,-91523001,''task3-policy-lock'',false)->>''latest_event_id'')::uuid'
    ) AS t(latest_event_id uuid);
  IF v_writer_result->>'status' IS DISTINCT FROM 'withdrawn'
     OR v_latest_event_id IS DISTINCT FROM (v_writer_result->>'event_id')::uuid THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CROSS_TRANSACTION_DISCARD_INVALID';
  END IF;

  PERFORM value FROM extensions.dblink(
    'task3_policy_a','SELECT set_config(''app.change_set_id'','''',true)'
  ) AS t(value text);
  SELECT result INTO v_writer_result FROM extensions.dblink(
    'task3_policy_a',
    'SELECT public.red_upsert_person_narrative_record('
    || '-91523001,-91523001,''task3-policy-lock'',''Predated publish stream'',false,'
    || 'private.narrative_record_state('
    || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256'')'
  ) AS t(result jsonb);
  PERFORM value FROM extensions.dblink(
    'task3_policy_a','SELECT set_config(''app.change_set_id'','''',true)'
  ) AS t(value text);
  SELECT result INTO v_writer_result FROM extensions.dblink(
    'task3_policy_a',
    'SELECT public.red_publicer_person_narrative_record('
    || '-91523001,-91523001,''task3-policy-lock'',private.narrative_record_state('
    || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256'')'
  ) AS t(result jsonb);
  PERFORM value FROM extensions.dblink(
    'task3_policy_a','SELECT set_config(''app.change_set_id'','''',true)'
  ) AS t(value text);
  SELECT result INTO v_writer_result FROM extensions.dblink(
    'task3_policy_a',
    'SELECT public.red_tilbagetraek_person_narrative_record('
    || '-91523001,-91523001,''task3-policy-lock'',private.narrative_record_state('
    || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256'')'
  ) AS t(result jsonb);
  SELECT latest_event_id INTO v_latest_event_id
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT (private.narrative_record_state('
      || '-91523001,-91523001,''task3-policy-lock'',false)->>''latest_event_id'')::uuid'
    ) AS t(latest_event_id uuid);
  IF v_writer_result->>'status' IS DISTINCT FROM 'withdrawn'
     OR v_latest_event_id IS DISTINCT FROM (v_writer_result->>'event_id')::uuid THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_CROSS_TRANSACTION_WITHDRAW_INVALID';
  END IF;
  PERFORM extensions.dblink_exec('task3_policy_a','ROLLBACK');

  -- Seed the active draft for the independent policy/deadlock interleaving.
  PERFORM extensions.dblink_exec(
    'task3_policy_setup',
    'INSERT INTO public.narrative('
    || 'id,subjekt_type,subjekt_id,source_id,side,tekst,privat) VALUES '
    || '(-91523010,''person'',-91523001,-91523001,''1'',''Policy race draft'',false);'
    || 'INSERT INTO private.narrative_record_publication('
    || 'id,narrative_id,source_record_id,record_label,citation_label,status) VALUES '
    || '(''15230000-0000-0000-0000-000000000010'',-91523010,'
    || '''15230000-0000-0000-0000-000000000001'',''Task 3 policy record'','
    || '''Task 3 policy citation'',''draft'')'
  );

  -- Task 4 generic-undo routing must serialize before its event predicate.
  -- Session A models a publication writer that already owns change_set but has
  -- not committed the event which claims an older narrative change set. The
  -- undo call must wait, then re-evaluate the predicate and reject; evaluating
  -- first and merely blocking on the later change_set read is a TOCTOU bypass.
  PERFORM extensions.dblink_exec(
    'task3_policy_setup',
    'INSERT INTO public.change_set('
    || 'id,actor_id,actor_navn,actor_rolle,operation,summary,subjekt_type,subjekt_id) VALUES '
    || '(-91523991,''15230000-0000-0000-0000-000000000099'',''Task 4 actor'', '
    || '''redaktion'',''task4_undo_race'',''Task 4 undo race'',''person'',-91523001);'
    || 'WITH snapshot AS ('
    || 'SELECT public._version_current_row(''narrative'',''{"id": -91523010}''::jsonb) AS state) '
    || 'INSERT INTO public.change_event('
    || 'id,change_set_id,seq,tabel,row_pk,op,foer,efter) '
    || 'SELECT -91523991,-91523991,1,''narrative'',''{"id": -91523010}''::jsonb,'
    || '''UPDATE'',state,state FROM snapshot'
  );
  PERFORM extensions.dblink_exec('task3_policy_a','BEGIN');
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;'
    || 'INSERT INTO private.narrative_publication_event('
    || 'id,change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,'
    || 'source_id,source_record_id,decision_basis,before_state,after_state,'
    || 'before_state_sha256,after_state_sha256,decided_by,decided_by_name) VALUES ('
    || '''15230000-0000-0000-0000-000000000091'',-91523991,'
    || '''15230000-0000-0000-0000-000000000010'',1,''baseline'','
    || '''15230000-0000-0000-0000-000000000010'',-91523010,-91523001,'
    || '''15230000-0000-0000-0000-000000000001'',''Task 4 undo race owner'','
    || '''{"race":"owned"}'',''{"race":"owned"}'','
    || 'encode(extensions.digest(''{"race":"owned"}''::jsonb::text,''sha256''),''hex''),'
    || 'encode(extensions.digest(''{"race":"owned"}''::jsonb::text,''sha256''),''hex''),'
    || '''15230000-0000-0000-0000-000000000099'',''Task 4 actor'')'
  );
  PERFORM extensions.dblink_exec('task3_policy_b','BEGIN');
  PERFORM extensions.dblink_exec(
    'task3_policy_b',
    'SET LOCAL "request.jwt.claim.sub"='
    || quote_literal(v_actor::text)
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_b',
    'CREATE FUNCTION pg_temp.task4_attempt_undo() RETURNS text '
    || 'LANGUAGE plpgsql AS $attempt$ BEGIN '
    || 'PERFORM public.red_fortryd_change_set(-91523991,false); '
    || 'RETURN ''ACCEPTED''; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $attempt$'
  );
  PERFORM extensions.dblink_send_query(
    'task3_policy_b','SELECT pg_temp.task4_attempt_undo()'
  );
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT extensions.dblink_is_busy('task3_policy_b') INTO v_busy;
    IF v_busy=0 THEN
      RAISE EXCEPTION 'TASK4_GENERIC_UNDO_DID_NOT_SERIALIZE_WITH_EVENT_OWNER';
    END IF;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'TASK4_GENERIC_UNDO_SERIALIZATION_TIMEOUT';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM extensions.dblink_exec('task3_policy_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    SELECT extensions.dblink_is_busy('task3_policy_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'TASK4_GENERIC_UNDO_DID_NOT_RESUME';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  SELECT result INTO v_undo_result
    FROM extensions.dblink_get_result('task3_policy_b') AS t(result text);
  PERFORM result
    FROM extensions.dblink_get_result('task3_policy_b') AS t(result text);
  IF v_undo_result IS DISTINCT FROM
       'NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED' THEN
    RAISE EXCEPTION 'TASK4_GENERIC_UNDO_CONCURRENT_EVENT_BYPASS: %',v_undo_result;
  END IF;
  SELECT reversal_count INTO v_after_change_count
    FROM extensions.dblink(
      'task3_policy_setup',
      'SELECT count(*) FROM public.change_set WHERE reverterer_id=-91523991'
    ) AS t(reversal_count bigint);
  IF v_after_change_count<>0 THEN
    RAISE EXCEPTION 'TASK4_GENERIC_UNDO_CONCURRENT_REJECTION_WROTE';
  END IF;
  PERFORM extensions.dblink_exec('task3_policy_b','ROLLBACK');
  PERFORM extensions.dblink_exec(
    'task3_policy_setup',
    'SET session_replication_role=replica;'
    || 'DELETE FROM private.narrative_publication_event '
    || 'WHERE id=''15230000-0000-0000-0000-000000000091'';'
    || 'DELETE FROM public.change_event WHERE change_set_id=-91523991;'
    || 'DELETE FROM public.change_set WHERE id=-91523991;'
    || 'SET session_replication_role=origin'
  );
  RAISE NOTICE 'OK: narrative record Task 4 generic undo serializes before event routing';

  PERFORM extensions.dblink_exec('task3_policy_a','BEGIN');
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 2 $version$'
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'SET LOCAL "request.jwt.claim.sub"='
    || quote_literal(v_actor::text)
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_a','SET LOCAL deadlock_timeout=''100ms'''
  );
  -- Enter the production record-lock path before the publication RPC. The
  -- canonical order blocks red_set_privat at its change-set allocator before
  -- that legacy writer can retain an audit lock and wait on session A's person.
  PERFORM state
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT private.narrative_record_state('
      || '-91523001,-91523001,''task3-policy-lock'',true)'
    ) AS t(state jsonb);

  PERFORM extensions.dblink_exec('task3_policy_b','BEGIN');
  PERFORM extensions.dblink_exec(
    'task3_policy_b',
    'SET LOCAL "request.jwt.claim.sub"='
    || quote_literal(v_actor::text)
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_b','SET LOCAL deadlock_timeout=''100ms'''
  );
  PERFORM extensions.dblink_send_query(
    'task3_policy_b',
    'SELECT public.red_set_privat(-91523001,true)::text'
  );
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT extensions.dblink_is_busy('task3_policy_b') INTO v_busy;
    IF v_busy=0 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_POLICY_NOT_SERIALIZED';
    END IF;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_POLICY_LOCK_TIMEOUT';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;

  PERFORM value
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT set_config(''app.change_set_id'','''',true)'
    ) AS t(value text);
  SELECT result INTO v_writer_result
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT public.red_publicer_person_narrative_record('
      || '-91523001,-91523001,''task3-policy-lock'','
      || 'private.narrative_record_state('
      || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256'')'
    ) AS t(result jsonb);
  SELECT event_type,attested_allowed
    INTO v_event_type,v_attested_allowed
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT event_type,'
      || '(after_state #>> ''{publication_policy,publication_allowed}'')::boolean '
      || 'FROM private.narrative_publication_event '
      || 'WHERE id='
      || quote_literal(v_writer_result->>'event_id')
    ) AS t(event_type text,attested_allowed boolean);
  IF v_writer_result->>'status' IS DISTINCT FROM 'published'
     OR v_event_type IS DISTINCT FROM 'published'
     OR v_attested_allowed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_POLICY_PUBLISHED_ATTESTATION_INVALID';
  END IF;

  -- Restore the capability function inside the same transaction, so commit
  -- makes the valid publication durable without ever exposing version 2.
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 1 $version$'
  );
  PERFORM extensions.dblink_exec('task3_policy_a','COMMIT');
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    SELECT extensions.dblink_is_busy('task3_policy_b') INTO v_busy;
    EXIT WHEN v_busy=0;
    IF clock_timestamp()>v_deadline THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_POLICY_UPDATE_DID_NOT_RESUME';
    END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM result FROM extensions.dblink_get_result('task3_policy_b') AS t(result text);
  PERFORM result FROM extensions.dblink_get_result('task3_policy_b') AS t(result text);
  PERFORM extensions.dblink_exec('task3_policy_b','COMMIT');
  PERFORM extensions.dblink_disconnect('task3_policy_b'); v_b_connected:=false;

  v_writer_result:=private.narrative_record_state(
    v_person_id,v_source_id,'task3-policy-lock',false
  );
  IF v_writer_result->>'publication_status' IS DISTINCT FROM 'stale_published'
     OR coalesce((v_writer_result #>>
          '{publication_state,publication_policy,publication_allowed}'
        )::boolean,true)
     OR (SELECT count(*) FROM private.narrative_publication_event event
          WHERE event.source_record_id=v_record_id
            AND event.id<>'15230000-0000-0000-0000-000000000042')<>1
     OR public.narrative_record_contract_version()<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_PERSON_POLICY_POST_STATE_INVALID';
  END IF;

  -- Count through an autocommit helper session. The coordinating DO must not
  -- retain an ACCESS SHARE lock on change_set while session A proves that the
  -- canonical lock path can acquire its allocator lock and reject revalidation.
  SELECT event_count,change_count
    INTO v_before_event_count,v_before_change_count
    FROM extensions.dblink(
      'task3_policy_setup',
      'SELECT (SELECT count(*) FROM private.narrative_publication_event '
      || 'WHERE source_record_id=''15230000-0000-0000-0000-000000000001''),'
      || '(SELECT count(*) FROM public.change_set '
      || 'WHERE subjekt_type=''person'' AND subjekt_id=-91523001)'
    ) AS t(event_count bigint,change_count bigint);
  PERFORM extensions.dblink_exec('task3_policy_a','BEGIN');
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 2 $version$'
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'SET LOCAL "request.jwt.claim.sub"='
    || quote_literal(v_actor::text)
  );
  PERFORM extensions.dblink_exec(
    'task3_policy_a',
    'DO $expect$ BEGIN '
    || 'PERFORM public.red_revalider_person_narrative_record('
    || '-91523001,-91523001,''task3-policy-lock'',private.narrative_record_state('
    || '-91523001,-91523001,''task3-policy-lock'',false)->>''state_sha256''); '
    || 'RAISE EXCEPTION ''NARRATIVE_RECORD_POLICY_REVALIDATION_ACCEPTED''; '
    || 'EXCEPTION WHEN OTHERS THEN '
    || 'IF SQLERRM<>''NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED'' THEN RAISE; END IF; '
    || 'END $expect$'
  );
  SELECT event_count,change_count
    INTO v_after_event_count,v_after_change_count
    FROM extensions.dblink(
      'task3_policy_a',
      'SELECT (SELECT count(*) FROM private.narrative_publication_event '
      || 'WHERE source_record_id=''15230000-0000-0000-0000-000000000001''),'
      || '(SELECT count(*) FROM public.change_set '
      || 'WHERE subjekt_type=''person'' AND subjekt_id=-91523001)'
    ) AS t(event_count bigint,change_count bigint);
  IF v_after_event_count IS DISTINCT FROM v_before_event_count
     OR v_after_change_count IS DISTINCT FROM v_before_change_count THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_POLICY_REVALIDATION_WROTE';
  END IF;
  PERFORM extensions.dblink_exec('task3_policy_a','ROLLBACK');
  PERFORM extensions.dblink_disconnect('task3_policy_a'); v_a_connected:=false;

  PERFORM extensions.dblink_exec('task3_policy_setup',v_cleanup);
  PERFORM extensions.dblink_disconnect('task3_policy_setup');
  v_setup_connected:=false;
  RAISE NOTICE 'OK: narrative record Task 3 person policy row is serialized before attestation';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_original_error=MESSAGE_TEXT;
  IF v_a_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task3_policy_a','ROLLBACK');
      EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task3_policy_a');
      EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM extensions.dblink_cancel_query('task3_policy_b');
      EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN
      WHILE extensions.dblink_is_busy('task3_policy_b')=1 LOOP
        PERFORM pg_sleep(0.02);
      END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM * FROM extensions.dblink_get_result('task3_policy_b') AS t(result text);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_exec('task3_policy_b','ROLLBACK');
      EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task3_policy_b');
      EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task3_policy_setup',v_cleanup);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task3_policy_setup');
      EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RAISE EXCEPTION '%',v_original_error;
END
$narrative_record_task3_person_policy_lock$;
RESET search_path;

-- Task 6: every remaining legacy mutation surface joins the cutover lock
-- protocol. The #153 red_*_1939_v50_* transition facade is deliberately not
-- legacy storage: its active one-version adapters delegate to the generic v2
-- writer and are covered by the 1939 writer contracts.
DO $narrative_record_task6_structure$
DECLARE
  v_signature text;
  v_definition text;
  v_gate integer;
  v_version integer;
  v_other integer;
  v_position integer;
  v_timeout integer;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_upsert_narrativ(text,bigint,text,boolean,bigint,text)',
    'public.red_publicer_narrative_record(bigint,uuid,text,text)',
    'public.red_tilbagetraek_narrative_record(bigint)',
    'public.red_slet_person(bigint)',
    'public.red_fortryd_change_set(bigint,boolean)',
    'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)',
    'public.red_apply_reimport_cases(uuid,text,text)',
    'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)',
    'public.red_reverse_reimport_cases(uuid,uuid)',
    'private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_WRITER_MISSING: %',v_signature;
    END IF;
    v_definition:=regexp_replace(
      pg_get_functiondef(to_regprocedure(v_signature)),
      '--[^' || chr(10) || ']*',' ','g'
    );
    v_gate:=strpos(v_definition,'pg_advisory_xact_lock_shared(');
    v_version:=strpos(v_definition,'public.narrative_record_contract_version()');
    IF v_gate=0 OR v_version<=v_gate
       OR strpos(v_definition,'''daa-narrative-record-contract''')=0 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_GATE_ORDER_INVALID: %',v_signature;
    END IF;
    v_other:=0;
    FOREACH v_position IN ARRAY ARRAY[
      strpos(v_definition,'pg_advisory_xact_lock('),
      strpos(v_definition,'LOCK TABLE '),
      strpos(v_definition,' FOR UPDATE'),
      strpos(v_definition,' FOR SHARE')
    ] LOOP
      IF v_position>0 AND (v_other=0 OR v_position<v_other) THEN v_other:=v_position; END IF;
    END LOOP;
    IF v_other>0 AND v_other<v_gate THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_FIRST_LOCK_INVALID: %',v_signature;
    END IF;
    IF v_signature IN (
         'public.red_apply_reimport_cases(uuid,text,text)',
         'public.red_reverse_reimport_cases(uuid,uuid)'
       ) THEN
      v_timeout:=strpos(v_definition,'set_config(''lock_timeout''');
      IF v_timeout=0 OR v_timeout<v_version THEN
        RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_CUTOVER_TIMEOUT_ORDER_INVALID: %',v_signature;
      END IF;
    END IF;
  END LOOP;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_preview_reimport_cases(bigint,text,jsonb)',
    'private.reimport_case_receipt(uuid)',
    'private.reimport_case_reversal_plan(uuid)'
  ] LOOP
    v_definition:=pg_get_functiondef(to_regprocedure(v_signature));
    IF strpos(v_definition,'daa-narrative-record-contract')>0 THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_READ_ONLY_CLASSIFICATION_INVALID: %',v_signature;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: narrative record Task 6 complete writer inventory and first-lock order';
END
$narrative_record_task6_structure$;

-- Real two-session orders. Each committed fixture is isolated to negative ids
-- and removed by the exception-safe cleanup path.
SET search_path TO public,private,extensions,pg_catalog;
DO $narrative_record_task6_lock_orders$
DECLARE
  v_conn text:=format(
    'dbname=%s port=%s host=%s user=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1),session_user
  );
  v_actor uuid:='15260000-0000-0000-0000-000000000099';
  v_a_pid integer;
  v_b_pid integer;
  v_busy integer;
  v_deadline timestamptz;
  v_index integer;
  v_result text;
  v_before jsonb;
  v_after jsonb;
  v_manifest text;
  v_acl text;
  v_calls text[]:=ARRAY[
    'SELECT public.red_upsert_narrativ(''person'',-91526001,''task6 order A'',false,-91526001,NULL)',
    'SELECT public.red_apply_reimport_cases(NULL,NULL,NULL)',
    'SELECT public.red_reverse_reimport_cases(NULL,NULL)'
  ];
  v_errors text[]:=ARRAY[
    'NARRATIVE_RECORD_REQUIRED',
    'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED',
    'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED'
  ];
  v_disabled_calls text[]:=ARRAY[
    'SELECT public.red_publicer_narrative_record(NULL,NULL,NULL,NULL)',
    'SELECT public.red_tilbagetraek_narrative_record(NULL)',
    'SELECT public.red_authorize_reimport_cases(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)',
    'SELECT public.red_apply_reimport_cases(NULL,NULL,NULL)',
    'SELECT public.red_authorize_reimport_case_reversal(NULL,NULL,NULL,NULL)',
    'SELECT public.red_reverse_reimport_cases(NULL,NULL)',
    'SELECT private.write_reimport_case_narrative(NULL,NULL,NULL,NULL,NULL,NULL)'
  ];
  v_setup_connected boolean:=false;
  v_a_connected boolean:=false;
  v_b_connected boolean:=false;
  v_cleanup text:=$cleanup$
    SET session_replication_role=replica;
    DELETE FROM public.change_event WHERE change_set_id IN (
      SELECT id FROM public.change_set WHERE subjekt_id IN (-91526001,-91526002)
    );
    DELETE FROM public.change_set WHERE subjekt_id IN (-91526001,-91526002);
    DELETE FROM private.narrative_record_publication WHERE narrative_id IN (
      SELECT id FROM public.narrative WHERE subjekt_id IN (-91526001,-91526002)
    );
    DELETE FROM public.narrative WHERE subjekt_id IN (-91526001,-91526002);
    DELETE FROM public.person WHERE id IN (-91526001,-91526002);
    DELETE FROM public.source WHERE id IN (-91526001,-91526002);
    DELETE FROM public.profiles WHERE id='15260000-0000-0000-0000-000000000099';
    DELETE FROM auth.users WHERE id='15260000-0000-0000-0000-000000000099';
    SET session_replication_role=origin;
  $cleanup$;
  v_snapshot_sql text:=$snapshot$
    SELECT jsonb_build_object(
      'v50_auth',(SELECT count(*) FROM private.reimport_1939_authorization),
      'v50_batch',(SELECT count(*) FROM private.reimport_1939_write_batch),
      'v50_event',(SELECT count(*) FROM private.reimport_1939_write_event),
      'c3_auth',(SELECT count(*) FROM private.reimport_case_authorization),
      'c3_batch',(SELECT count(*) FROM private.reimport_case_batch),
      'c3_event',(SELECT count(*) FROM private.reimport_case_event),
      'change_set',(SELECT count(*) FROM public.change_set),
      'change_event',(SELECT count(*) FROM public.change_event),
      'narrative',(SELECT count(*) FROM public.narrative),
      'binding',(SELECT count(*) FROM private.narrative_record_publication)
    )
  $snapshot$;
BEGIN
  PERFORM extensions.dblink_connect('task6_setup',v_conn); v_setup_connected:=true;
  PERFORM extensions.dblink_connect('task6_a',v_conn); v_a_connected:=true;
  PERFORM extensions.dblink_connect('task6_b',v_conn); v_b_connected:=true;
  PERFORM extensions.dblink_exec('task6_setup',v_cleanup);
  PERFORM extensions.dblink_exec('task6_setup',
    'INSERT INTO auth.users(id,email) VALUES '
    || '(''15260000-0000-0000-0000-000000000099'',''task6@test.invalid'');'
    || 'INSERT INTO public.profiles(id,rolle,email) VALUES '
    || '(''15260000-0000-0000-0000-000000000099'',''redaktion'',''task6@test.invalid'');'
    || 'INSERT INTO public.person(id,levende,privat,staged,visning_navn) VALUES '
    || '(-91526001,false,false,false,''Task 6 old writer'');'
    || 'INSERT INTO public.source(id,slags,titel,udgave,aar,import_key) VALUES '
    || '(-91526001,''DAA-udgave'',''Task 6 DAA'',''Task 6'',1939,''task6:daa''),'
    || '(-91526002,''bog'',''Task 6 control'',''Task 6'',1939,''task6:control'')'
  );
  PERFORM extensions.dblink_exec('task6_a',
    'CREATE OR REPLACE FUNCTION pg_temp.task6_attempt(p_sql text) RETURNS text '
    || 'LANGUAGE plpgsql AS $attempt$ BEGIN EXECUTE p_sql; RETURN ''NO_ERROR''; '
    || 'EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $attempt$'
  );
  SELECT pid INTO v_a_pid FROM extensions.dblink('task6_a','SELECT pg_backend_pid()') AS t(pid integer);
  SELECT pid INTO v_b_pid FROM extensions.dblink('task6_b','SELECT pg_backend_pid()') AS t(pid integer);

  -- Order A: exclusive first. Every family representative blocks, then wakes
  -- under committed v2 and rejects before any old-family write.
  FOR v_index IN 1..array_length(v_calls,1) LOOP
    PERFORM extensions.dblink_exec('task6_b','BEGIN');
    PERFORM extensions.dblink_exec('task6_b',
      'DO $lock$ BEGIN PERFORM pg_advisory_xact_lock('
      || 'hashtextextended(''daa-narrative-record-contract'',0)); END $lock$'
    );
    PERFORM extensions.dblink_exec('task6_b',
      'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
      || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
      || 'SET search_path=pg_catalog AS $version$ SELECT 2 $version$'
    );
    PERFORM extensions.dblink_exec('task6_a','BEGIN');
    PERFORM extensions.dblink_exec('task6_a',
      'SET LOCAL "request.jwt.claim.sub"='||quote_literal(v_actor::text)
    );
    PERFORM extensions.dblink_send_query(
      'task6_a','SELECT pg_temp.task6_attempt('||quote_literal(v_calls[v_index])||')'
    );
    v_deadline:=clock_timestamp()+interval '3 seconds';
    LOOP
      EXIT WHEN v_b_pid=ANY(pg_blocking_pids(v_a_pid));
      SELECT extensions.dblink_is_busy('task6_a') INTO v_busy;
      IF v_busy=0 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_A_DID_NOT_BLOCK: %',v_index; END IF;
      IF clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_A_TIMEOUT: %',v_index; END IF;
      PERFORM pg_sleep(0.02);
    END LOOP;
    -- C3 apply/reversal historically installed a five-second lock_timeout
    -- before their first advisory lock. A real cutover may legitimately hold
    -- exclusive for longer: the old call must remain queued, then wake and
    -- return the exact version error rather than a generic lock timeout.
    IF v_index IN (2,3) THEN PERFORM pg_sleep(5.25); END IF;
    PERFORM extensions.dblink_exec('task6_b','COMMIT');
    SELECT result INTO v_result FROM extensions.dblink_get_result('task6_a') AS t(result text);
    PERFORM result FROM extensions.dblink_get_result('task6_a') AS t(result text);
    IF v_result IS DISTINCT FROM v_errors[v_index] THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_A_ERROR: % %',v_index,v_result;
    END IF;
    PERFORM extensions.dblink_exec('task6_a','ROLLBACK');
    PERFORM extensions.dblink_exec('task6_b',
      'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
      || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
      || 'SET search_path=pg_catalog AS $version$ SELECT 1 $version$'
    );
  END LOOP;

  -- At v2 every remaining mutation entry point rejects with no authorization,
  -- batch, event, change-set, narrative, or binding delta.
  PERFORM extensions.dblink_exec('task6_b','BEGIN');
  PERFORM extensions.dblink_exec('task6_b',
    'DO $lock$ BEGIN PERFORM pg_advisory_xact_lock('
    || 'hashtextextended(''daa-narrative-record-contract'',0)); END $lock$'
  );
  PERFORM extensions.dblink_exec('task6_b',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 2 $version$'
  );
  PERFORM extensions.dblink_exec('task6_b','COMMIT');
  SELECT snapshot INTO v_before FROM extensions.dblink('task6_setup',v_snapshot_sql) AS t(snapshot jsonb);
  PERFORM extensions.dblink_exec('task6_a','BEGIN');
  PERFORM extensions.dblink_exec('task6_a',
    'SET LOCAL "request.jwt.claim.sub"='||quote_literal(v_actor::text)
  );
  FOREACH v_result IN ARRAY v_disabled_calls LOOP
    SELECT result INTO v_result FROM extensions.dblink(
      'task6_a','SELECT pg_temp.task6_attempt('||quote_literal(v_result)||')'
    ) AS t(result text);
    IF v_result IS DISTINCT FROM 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED' THEN
      RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_V2_BYPASS: %',v_result;
    END IF;
  END LOOP;
  SELECT result INTO v_result FROM extensions.dblink(
    'task6_a',
    'SELECT pg_temp.task6_attempt(''SELECT public.red_upsert_narrativ(''''person'''',-91526001,''''blocked'''',false,-91526001,NULL)'')'
  ) AS t(result text);
  IF v_result IS DISTINCT FROM 'NARRATIVE_RECORD_REQUIRED' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_UPSERT_V2_BYPASS: %',v_result;
  END IF;
  SELECT snapshot INTO v_after FROM extensions.dblink('task6_a',v_snapshot_sql) AS t(snapshot jsonb);
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_V2_REJECTION_WROTE: % %',v_before,v_after;
  END IF;
  -- Controls: only person+DAA is disabled. Other subjects and sources preserve
  -- the legacy v1 behavior even while the contract is at v2.
  PERFORM result FROM extensions.dblink(
    'task6_a',
    'SELECT public.red_upsert_narrativ(''estate'',-91526002,''estate control'',false,-91526001,NULL)'
  ) AS t(result bigint);
  PERFORM result FROM extensions.dblink(
    'task6_a',
    'SELECT public.red_upsert_narrativ(''person'',-91526001,''source control'',false,-91526002,NULL)'
  ) AS t(result bigint);
  PERFORM extensions.dblink_exec('task6_a','ROLLBACK');
  PERFORM extensions.dblink_exec('task6_b',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 1 $version$'
  );

  -- Order B: the v1 writer takes shared first and commits. The exclusive
  -- cutover waits, recomputes the exact narrative manifest under its lock, and
  -- aborts on drift without changing the version function or ACL manifest.
  SELECT manifest INTO v_manifest FROM extensions.dblink(
    'task6_setup',
    'SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg('
    || 'jsonb_build_array(id,subjekt_type,subjekt_id,source_id,tekst,side,privat) ORDER BY id),'
    || '''[]''::jsonb)::text,''UTF8''),''sha256''),''hex'') FROM public.narrative'
  ) AS t(manifest text);
  SELECT acl INTO v_acl FROM extensions.dblink(
    'task6_setup',
    'SELECT md5(string_agg(n.nspname||''.''||p.proname||coalesce(p.proacl::text,''''),'','' ORDER BY n.nspname,p.proname,p.oid)) '
    || 'FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace '
    || 'WHERE p.proname LIKE ''red_%narrative_record%'' OR p.proname=''narrative_record_contract_version'''
  ) AS t(acl text);
  PERFORM extensions.dblink_exec('task6_b',
    'CREATE OR REPLACE FUNCTION pg_temp.task6_cutover(p_expected text) RETURNS text '
    || 'LANGUAGE plpgsql SET search_path=pg_catalog,public,private,extensions AS $cutover$ '
    || 'DECLARE v_actual text; BEGIN '
    || 'PERFORM pg_advisory_xact_lock(hashtextextended(''daa-narrative-record-contract'',0)); '
    || 'SELECT encode(extensions.digest(convert_to(coalesce(jsonb_agg('
    || 'jsonb_build_array(id,subjekt_type,subjekt_id,source_id,tekst,side,privat) ORDER BY id),'
    || '''[]''::jsonb)::text,''UTF8''),''sha256''),''hex'') INTO v_actual FROM public.narrative; '
    || 'IF v_actual IS DISTINCT FROM p_expected THEN RAISE EXCEPTION ''CUTOVER_MANIFEST_DRIFT''; END IF; '
    || 'RETURN ''NO_DRIFT''; END $cutover$'
  );
  PERFORM extensions.dblink_exec('task6_b',
    'CREATE OR REPLACE FUNCTION pg_temp.task6_attempt(p_sql text) RETURNS text '
    || 'LANGUAGE plpgsql AS $attempt$ BEGIN EXECUTE p_sql; RETURN ''NO_ERROR''; '
    || 'EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $attempt$'
  );
  PERFORM extensions.dblink_exec('task6_a','BEGIN');
  PERFORM extensions.dblink_exec('task6_a',
    'SET LOCAL "request.jwt.claim.sub"='||quote_literal(v_actor::text)
  );
  PERFORM result FROM extensions.dblink(
    'task6_a',
    'SELECT public.red_upsert_narrativ(''person'',-91526001,''order B committed'',false,-91526001,''1'')'
  ) AS t(result bigint);
  PERFORM extensions.dblink_exec('task6_b','BEGIN');
  PERFORM extensions.dblink_send_query(
    'task6_b','SELECT pg_temp.task6_attempt('||quote_literal(
      'SELECT pg_temp.task6_cutover('||quote_literal(v_manifest)||')'
    )||')'
  );
  v_deadline:=clock_timestamp()+interval '3 seconds';
  LOOP
    EXIT WHEN v_a_pid=ANY(pg_blocking_pids(v_b_pid));
    SELECT extensions.dblink_is_busy('task6_b') INTO v_busy;
    IF v_busy=0 THEN RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_B_DID_NOT_BLOCK'; END IF;
    IF clock_timestamp()>v_deadline THEN RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_B_TIMEOUT'; END IF;
    PERFORM pg_sleep(0.02);
  END LOOP;
  PERFORM extensions.dblink_exec('task6_a','COMMIT');
  SELECT result INTO v_result FROM extensions.dblink_get_result('task6_b') AS t(result text);
  PERFORM result FROM extensions.dblink_get_result('task6_b') AS t(result text);
  IF v_result IS DISTINCT FROM 'CUTOVER_MANIFEST_DRIFT' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_B_RECHECK_FAILED: %',v_result;
  END IF;
  PERFORM extensions.dblink_exec('task6_b','ROLLBACK');
  SELECT result INTO v_result FROM extensions.dblink(
    'task6_setup','SELECT public.narrative_record_contract_version()::text'
  ) AS t(result text);
  IF v_result IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_B_CHANGED_VERSION';
  END IF;
  SELECT acl INTO v_result FROM extensions.dblink(
    'task6_setup',
    'SELECT md5(string_agg(n.nspname||''.''||p.proname||coalesce(p.proacl::text,''''),'','' ORDER BY n.nspname,p.proname,p.oid)) '
    || 'FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace '
    || 'WHERE p.proname LIKE ''red_%narrative_record%'' OR p.proname=''narrative_record_contract_version'''
  ) AS t(acl text);
  IF v_result IS DISTINCT FROM v_acl THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_ORDER_B_CHANGED_GRANTS';
  END IF;

  PERFORM extensions.dblink_exec('task6_setup',v_cleanup);
  PERFORM extensions.dblink_disconnect('task6_b'); v_b_connected:=false;
  PERFORM extensions.dblink_disconnect('task6_a'); v_a_connected:=false;
  PERFORM extensions.dblink_disconnect('task6_setup'); v_setup_connected:=false;
  RAISE NOTICE 'OK: narrative record Task 6 real lock orders A/B, v1 compatibility and v2 zero writes';
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM extensions.dblink_cancel_query('task6_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM extensions.dblink_cancel_query('task6_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
  IF v_a_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task6_a','ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task6_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task6_b','ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_exec('task6_b',
      'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
      || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
      || 'SET search_path=pg_catalog AS $version$ SELECT 1 $version$'
    ); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task6_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task6_setup',v_cleanup); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task6_setup'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RAISE;
END
$narrative_record_task6_lock_orders$;

DO $narrative_record_task6_new_writer_cutover$
DECLARE
  v_conn text:=format(
    'dbname=%s port=%s host=%s user=%s',current_database(),current_setting('port'),
    split_part(current_setting('unix_socket_directories'),',',1),session_user
  );
  v_actor uuid:='15260000-0000-0000-0000-000000000199';
  v_result text;
  v_writer jsonb;
  v_setup_connected boolean:=false;
  v_a_connected boolean:=false;
  v_b_connected boolean:=false;
  v_cleanup text:=$cleanup$
    SET session_replication_role=replica;
    DELETE FROM private.narrative_publication_event
      WHERE source_record_id='15260000-0000-0000-0000-000000000101';
    DELETE FROM public.change_event WHERE change_set_id IN (
      SELECT id FROM public.change_set WHERE subjekt_id=-91526003
    );
    DELETE FROM public.change_set WHERE subjekt_id=-91526003;
    DELETE FROM private.narrative_record_publication
      WHERE source_record_id='15260000-0000-0000-0000-000000000101';
    DELETE FROM public.narrative WHERE subjekt_id=-91526003 AND source_id=-91526003;
    DELETE FROM private.source_persona_identity
      WHERE source_persona_id='15260000-0000-0000-0000-000000000108';
    DELETE FROM private.source_persona_identity_event
      WHERE source_persona_id='15260000-0000-0000-0000-000000000108';
    DELETE FROM private.source_persona_placement_decision
      WHERE placement_id='15260000-0000-0000-0000-000000000112';
    DELETE FROM private.source_persona_placement
      WHERE id='15260000-0000-0000-0000-000000000112';
    DELETE FROM private.source_record_placement_decision
      WHERE placement_id='15260000-0000-0000-0000-000000000111';
    DELETE FROM private.source_record_placement
      WHERE id='15260000-0000-0000-0000-000000000111';
    DELETE FROM private.source_persona_mention
      WHERE persona_id='15260000-0000-0000-0000-000000000108';
    DELETE FROM private.source_mention
      WHERE id='15260000-0000-0000-0000-000000000109';
    DELETE FROM private.source_persona
      WHERE id='15260000-0000-0000-0000-000000000108';
    DELETE FROM private.source_observation
      WHERE id='15260000-0000-0000-0000-000000000107';
    DELETE FROM private.source_record_anchor_event
      WHERE source_record_id='15260000-0000-0000-0000-000000000101';
    DELETE FROM private.source_record_occurrence
      WHERE id='15260000-0000-0000-0000-000000000106';
    DELETE FROM private.source_record
      WHERE id='15260000-0000-0000-0000-000000000101';
    DELETE FROM private.source_rendition
      WHERE id='15260000-0000-0000-0000-000000000105';
    DELETE FROM private.extraction_run
      WHERE id='15260000-0000-0000-0000-000000000102';
    DELETE FROM public.lineage_scheme_entry WHERE id=-91526003;
    DELETE FROM public.lineage_scheme WHERE id=-91526003;
    DELETE FROM public.slaegt WHERE id=-91526003;
    DELETE FROM public.person WHERE id=-91526003;
    DELETE FROM public.source WHERE id=-91526003;
    DELETE FROM public.profiles WHERE id='15260000-0000-0000-0000-000000000199';
    DELETE FROM auth.users WHERE id='15260000-0000-0000-0000-000000000199';
    SET session_replication_role=origin;
  $cleanup$;
BEGIN
  PERFORM extensions.dblink_connect('task6_new_setup',v_conn); v_setup_connected:=true;
  PERFORM extensions.dblink_connect('task6_new_a',v_conn); v_a_connected:=true;
  PERFORM extensions.dblink_connect('task6_new_b',v_conn); v_b_connected:=true;
  PERFORM extensions.dblink_exec('task6_new_setup',v_cleanup);
  PERFORM extensions.dblink_exec('task6_new_setup',
    'INSERT INTO auth.users(id,email) VALUES '
    || '(''15260000-0000-0000-0000-000000000199'',''task6-new@test.invalid'');'
    || 'INSERT INTO public.profiles(id,rolle,email) VALUES '
    || '(''15260000-0000-0000-0000-000000000199'',''redaktion'',''task6-new@test.invalid'');'
    || 'INSERT INTO public.person(id,levende,privat,staged,visning_navn) VALUES '
    || '(-91526003,false,false,false,''Task 6 new writer'');'
    || 'INSERT INTO public.source(id,slags,titel,udgave,aar,import_key) VALUES '
    || '(-91526003,''DAA-udgave'',''Task 6 new writer'',''Task 6'',1939,''task6:new-writer'');'
    || 'INSERT INTO public.slaegt(id,navn,sorteringsnavn,slug) VALUES '
    || '(-91526003,''Task 6 slægt'',''Task 6 slægt'',''task6-new-writer'');'
    || 'INSERT INTO public.lineage_scheme(id,slaegt_id,source_id,kind,label) VALUES '
    || '(-91526003,-91526003,-91526003,''stamtavle'',''Task 6 scheme'');'
    || 'INSERT INTO public.lineage_scheme_entry(id,scheme_id,slaegt_id,code,label,sort_order) VALUES '
    || '(-91526003,-91526003,-91526003,''A'',''Task 6 entry'',1);'
    || 'INSERT INTO private.extraction_run('
    || 'id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest) VALUES '
    || '(''15260000-0000-0000-0000-000000000102'',-91526003,''task6-new-writer'','
    || '''1'',''task6'',''task6'','''||repeat('3',64)||''',''{}'');'
    || 'INSERT INTO private.source_rendition('
    || 'id,source_id,rendition_key,rendition_kind,content_sha256,metadata) VALUES '
    || '(''15260000-0000-0000-0000-000000000105'',-91526003,''task6-new-writer'','
    || '''text_layer'','''||repeat('5',64)||''',''{}'');'
    || 'INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id) VALUES '
    || '(''15260000-0000-0000-0000-000000000101'',-91526003,''task6-new-writer'','
    || '''person_entry'',''15260000-0000-0000-0000-000000000102'');'
    || 'INSERT INTO private.source_record_occurrence('
    || 'id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,verbatim_text,'
    || 'physical_fingerprint,structural_fingerprint,extraction_run_id) VALUES '
    || '(''15260000-0000-0000-0000-000000000106'',''15260000-0000-0000-0000-000000000105'','
    || '''task6-new-writer'',1,1,0,20,''Task 6 occurrence'',''task6-physical'','
    || '''task6-structural'',''15260000-0000-0000-0000-000000000102'');'
    || 'INSERT INTO private.source_record_anchor_event('
    || 'occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name) VALUES '
    || '(''15260000-0000-0000-0000-000000000106'',''15260000-0000-0000-0000-000000000101'','
    || '''accepted'',''{"basis":"task6"}'',1,''15260000-0000-0000-0000-000000000199'',''Task 6 actor'');'
    || 'INSERT INTO private.source_observation('
    || 'id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,'
    || 'quality_status,extraction_method,extraction_run_id) VALUES '
    || '(''15260000-0000-0000-0000-000000000107'',''15260000-0000-0000-0000-000000000106'','
    || '''header'',1,1,0,20,''Task 6 observation'',''clear'',''task6'','
    || '''15260000-0000-0000-0000-000000000102'');'
    || 'INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id) VALUES '
    || '(''15260000-0000-0000-0000-000000000108'',-91526003,''task6-persona'','
    || '''15260000-0000-0000-0000-000000000102'');'
    || 'INSERT INTO private.source_mention('
    || 'id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id) VALUES '
    || '(''15260000-0000-0000-0000-000000000109'',''15260000-0000-0000-0000-000000000107'','
    || '''person_name'',0,4,''Task'',''15260000-0000-0000-0000-000000000102'');'
    || 'INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES '
    || '(''15260000-0000-0000-0000-000000000108'',''15260000-0000-0000-0000-000000000109'',''primary'',1);'
    || 'INSERT INTO private.source_record_placement('
    || 'id,source_record_id,scheme_entry_id,header_observation_id,initial_status) VALUES '
    || '(''15260000-0000-0000-0000-000000000111'',''15260000-0000-0000-0000-000000000101'','
    || '-91526003,''15260000-0000-0000-0000-000000000107'',''accepted'');'
    || 'INSERT INTO private.source_record_placement_decision('
    || 'placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES '
    || '(''15260000-0000-0000-0000-000000000111'',1,''accepted'',''{"basis":"task6"}'','
    || '''migration'',''Task 6 actor'');'
    || 'INSERT INTO private.source_persona_placement('
    || 'id,source_persona_id,record_placement_id,placement_role,basis_observation_id,initial_status) VALUES '
    || '(''15260000-0000-0000-0000-000000000112'',''15260000-0000-0000-0000-000000000108'','
    || '''15260000-0000-0000-0000-000000000111'',''principal_member'','
    || '''15260000-0000-0000-0000-000000000107'',''accepted'');'
    || 'INSERT INTO private.source_persona_placement_decision('
    || 'placement_id,version,decision_status,evidence,decision_origin,decided_by_name) VALUES '
    || '(''15260000-0000-0000-0000-000000000112'',1,''accepted'',''{"basis":"task6"}'','
    || '''migration'',''Task 6 actor'');'
    || 'INSERT INTO private.source_persona_identity_event('
    || 'source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) VALUES '
    || '(''15260000-0000-0000-0000-000000000108'',-91526003,''accepted'',1,''{"basis":"task6"}'','
    || '''15260000-0000-0000-0000-000000000199'',''Task 6 actor'',now());'
    || 'INSERT INTO private.source_persona_identity('
    || 'source_persona_id,canonical_person_id,decision_status,version,evidence,decided_by,decided_by_name,decided_at) VALUES '
    || '(''15260000-0000-0000-0000-000000000108'',-91526003,''accepted'',1,''{"basis":"task6"}'','
    || '''15260000-0000-0000-0000-000000000199'',''Task 6 actor'',now())'
  );
  PERFORM extensions.dblink_exec('task6_new_a',
    'CREATE OR REPLACE FUNCTION pg_temp.task6_attempt(p_sql text) RETURNS text '
    || 'LANGUAGE plpgsql AS $attempt$ BEGIN EXECUTE p_sql; RETURN ''NO_ERROR''; '
    || 'EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $attempt$'
  );
  PERFORM extensions.dblink_exec('task6_new_a','BEGIN');
  PERFORM extensions.dblink_exec('task6_new_a',
    'SET LOCAL "request.jwt.claim.sub"='||quote_literal(v_actor::text)
  );
  SELECT result INTO v_result FROM extensions.dblink(
    'task6_new_a',
    'SELECT pg_temp.task6_attempt(''SELECT public.red_upsert_person_narrative_record('
    || '-91526003,-91526003,''''task6-new-writer'''',''''blocked'''',false,repeat(''''0'''',64))'')'
  ) AS t(result text);
  IF v_result IS DISTINCT FROM 'NARRATIVE_RECORD_CONTRACT_INACTIVE' THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_NEW_WRITER_V1_NOT_BLOCKED: %',v_result;
  END IF;
  PERFORM extensions.dblink_exec('task6_new_a','ROLLBACK');

  PERFORM extensions.dblink_exec('task6_new_b','BEGIN');
  PERFORM extensions.dblink_exec('task6_new_b',
    'DO $lock$ BEGIN PERFORM pg_advisory_xact_lock('
    || 'hashtextextended(''daa-narrative-record-contract'',0)); END $lock$'
  );
  PERFORM extensions.dblink_exec('task6_new_b',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 2 $version$'
  );
  PERFORM extensions.dblink_exec('task6_new_b','COMMIT');

  PERFORM extensions.dblink_exec('task6_new_a','BEGIN');
  PERFORM extensions.dblink_exec('task6_new_a',
    'SET LOCAL "request.jwt.claim.sub"='||quote_literal(v_actor::text)
  );
  SELECT result INTO v_writer FROM extensions.dblink(
    'task6_new_a',
    'SELECT public.red_upsert_person_narrative_record('
    || '-91526003,-91526003,''task6-new-writer'',''Task 6 v2 text'',false,'
    || 'private.narrative_record_state(-91526003,-91526003,''task6-new-writer'',false)->>''state_sha256'')'
  ) AS t(result jsonb);
  PERFORM extensions.dblink_exec('task6_new_a','COMMIT');
  IF v_writer->>'status' IS DISTINCT FROM 'draft'
     OR (SELECT n FROM extensions.dblink(
          'task6_new_setup',
          'SELECT count(*) FROM public.narrative n JOIN private.narrative_record_publication p '
          || 'ON p.narrative_id=n.id WHERE n.subjekt_id=-91526003 AND n.source_id=-91526003 '
          || 'AND n.tekst=''Task 6 v2 text'' AND p.status=''draft'''
        ) AS t(n bigint))<>1 THEN
    RAISE EXCEPTION 'NARRATIVE_RECORD_TASK6_NEW_WRITER_V2_FAILED: %',v_writer;
  END IF;

  PERFORM extensions.dblink_exec('task6_new_b','BEGIN');
  PERFORM extensions.dblink_exec('task6_new_b',
    'DO $lock$ BEGIN PERFORM pg_advisory_xact_lock('
    || 'hashtextextended(''daa-narrative-record-contract'',0)); END $lock$'
  );
  PERFORM extensions.dblink_exec('task6_new_b',
    'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
    || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
    || 'SET search_path=pg_catalog AS $version$ SELECT 1 $version$'
  );
  PERFORM extensions.dblink_exec('task6_new_b','COMMIT');
  PERFORM extensions.dblink_exec('task6_new_setup',v_cleanup);
  PERFORM extensions.dblink_disconnect('task6_new_b'); v_b_connected:=false;
  PERFORM extensions.dblink_disconnect('task6_new_a'); v_a_connected:=false;
  PERFORM extensions.dblink_disconnect('task6_new_setup'); v_setup_connected:=false;
  RAISE NOTICE 'OK: narrative record Task 6 new writer requires committed exclusive v2 cutover';
EXCEPTION WHEN OTHERS THEN
  IF v_a_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task6_new_a','ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task6_new_a'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_b_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task6_new_b','ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_exec('task6_new_b',
      'CREATE OR REPLACE FUNCTION public.narrative_record_contract_version() '
      || 'RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER '
      || 'SET search_path=pg_catalog AS $version$ SELECT 1 $version$'
    ); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task6_new_b'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  IF v_setup_connected THEN
    BEGIN PERFORM extensions.dblink_exec('task6_new_setup',v_cleanup); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM extensions.dblink_disconnect('task6_new_setup'); EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RAISE;
END
$narrative_record_task6_new_writer_cutover$;
RESET search_path;
