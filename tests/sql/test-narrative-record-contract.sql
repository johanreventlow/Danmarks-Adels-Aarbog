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

ROLLBACK;
