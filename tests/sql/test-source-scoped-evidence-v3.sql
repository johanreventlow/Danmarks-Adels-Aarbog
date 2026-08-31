-- #153 Task 4A.  Run after the disposable bootstrap, schema.sql and db-rls.sql.
-- The transaction is rolled back so this contract never leaves fixture rows behind.
BEGIN;

DO $source_scoped_evidence_v3_contract$
DECLARE
  v_signature text;
  v_error text;
  v_state text;
  v_inventory_hash_before text;
  v_inventory_hash_after text;
  v_contract_hash_before text;
  v_contract_hash_after text;
  v_role text;
  v_relation text;
  v_typed_member_rejected boolean := false;
  v_predecessor_rejected boolean := false;
  v_inventory_id uuid;
  v_source_id bigint;
  v_person_id bigint;
  v_fact_id bigint;
  v_assertion_id bigint;
  v_unbound_assertion_id bigint;
  v_run_id uuid;
  v_record_id uuid;
  v_persona_id uuid;
  v_chain_id uuid;
  v_revision_id uuid;
  v_trigger text;
BEGIN
  IF to_regclass('private.source_scoped_evidence_contract_inventory') IS NULL
     OR to_regclass('private.source_scoped_evidence_v3_deployment') IS NULL
     OR to_regprocedure('private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_INVENTORY_OR_DEPLOYMENT_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='daa_source_scoped_evidence_deployer')
     OR NOT has_function_privilege(
       'daa_source_scoped_evidence_deployer',
       'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)',
       'EXECUTE'
     )
     OR NOT has_schema_privilege('daa_source_scoped_evidence_deployer','private','USAGE')
     OR has_schema_privilege('daa_source_scoped_evidence_deployer','private','CREATE')
     OR has_schema_privilege('daa_source_scoped_evidence_gateway','private','USAGE')
     OR has_table_privilege('daa_source_scoped_evidence_deployer','private.source_scoped_evidence_contract_inventory','INSERT')
     OR has_table_privilege('daa_source_scoped_evidence_deployer','private.source_scoped_evidence_v3_deployment','INSERT') THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_DEPLOYMENT_ACL_INVALID';
  END IF;
  IF NOT EXISTS (
       SELECT 1
         FROM pg_roles gateway
         JOIN pg_roles deployer
           ON deployer.rolname='daa_source_scoped_evidence_deployer'
         JOIN pg_auth_members membership
           ON membership.roleid=deployer.oid
          AND membership.member=gateway.oid
        WHERE gateway.rolname='daa_source_scoped_evidence_gateway'
          AND gateway.rolcanlogin
          AND NOT gateway.rolinherit
          AND NOT gateway.rolbypassrls
          AND NOT gateway.rolsuper
     )
     OR has_function_privilege(
       'daa_source_scoped_evidence_gateway',
       'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)',
       'EXECUTE'
     )
     OR position(
       'session_user' IN pg_get_functiondef(
         'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)'::regprocedure
       )
     )=0
     OR position(
       'auth.uid' IN lower(pg_get_functiondef(
         'private.register_source_scoped_evidence_v3_deployment(uuid,text,text,text,text,text,uuid)'::regprocedure
       ))
     )>0
  THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_GATEWAY_IDENTITY_INVALID';
  END IF;
  v_contract_hash_before:=private.source_scoped_evidence_v3_task4b_contract_sha256();
  ALTER ROLE daa_source_scoped_evidence_gateway INHERIT;
  v_contract_hash_after:=private.source_scoped_evidence_v3_task4b_contract_sha256();
  ALTER ROLE daa_source_scoped_evidence_gateway NOINHERIT;
  IF v_contract_hash_before IS NOT DISTINCT FROM v_contract_hash_after THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_GATEWAY_ROLE_RECEIPT_UNBOUND';
  END IF;
  -- A gateway that can create roles could recreate its capability boundary.
  -- The deployment receipt must therefore bind every privilege-bearing role
  -- attribute, not only LOGIN/INHERIT/BYPASSRLS/SUPERUSER.
  ALTER ROLE daa_source_scoped_evidence_gateway CREATEROLE;
  v_contract_hash_after:=private.source_scoped_evidence_v3_task4b_contract_sha256();
  ALTER ROLE daa_source_scoped_evidence_gateway NOCREATEROLE;
  IF v_contract_hash_before IS NOT DISTINCT FROM v_contract_hash_after THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_GATEWAY_ROLE_PRIVILEGE_RECEIPT_UNBOUND';
  END IF;
  -- SET ROLE must remain possible, but the gateway must not be able to grant
  -- the deployer capability onward.  Bind the membership options themselves.
  GRANT daa_source_scoped_evidence_deployer TO daa_source_scoped_evidence_gateway WITH ADMIN OPTION;
  v_contract_hash_after:=private.source_scoped_evidence_v3_task4b_contract_sha256();
  REVOKE ADMIN OPTION FOR daa_source_scoped_evidence_deployer FROM daa_source_scoped_evidence_gateway;
  IF v_contract_hash_before IS NOT DISTINCT FROM v_contract_hash_after THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_GATEWAY_MEMBERSHIP_RECEIPT_UNBOUND';
  END IF;
  -- The deployer needs schema lookup for its sole register capability; that
  -- narrow namespace grant must itself be receipt-bound.
  REVOKE USAGE ON SCHEMA private FROM daa_source_scoped_evidence_deployer;
  v_contract_hash_after:=private.source_scoped_evidence_v3_task4b_contract_sha256();
  GRANT USAGE ON SCHEMA private TO daa_source_scoped_evidence_deployer;
  IF v_contract_hash_before IS NOT DISTINCT FROM v_contract_hash_after THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_DEPLOYER_SCHEMA_RECEIPT_UNBOUND';
  END IF;
  IF to_regprocedure('private.refresh_source_scoped_evidence_contract_inventory(text)') IS NULL
     OR has_function_privilege(
       'authenticated',
       'private.refresh_source_scoped_evidence_contract_inventory(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'daa_source_scoped_evidence_deployer',
       'private.refresh_source_scoped_evidence_contract_inventory(text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_INVENTORY_REFRESH_ACL_INVALID';
  END IF;
  v_inventory_id:=private.refresh_source_scoped_evidence_contract_inventory(
    'source-scoped-evidence-v3-inventory-test-v1'
  );
  IF NOT EXISTS (
    SELECT 1
      FROM private.source_scoped_evidence_contract_inventory inventory
     WHERE inventory.id=v_inventory_id
       AND inventory.catalog_definition_sha256 ~ '^[0-9a-f]{64}$'
       AND inventory.reader_probe_source_sha256 ~ '^[0-9a-f]{64}$'
       AND inventory.consumer_probe_source_sha256 ~ '^[0-9a-f]{64}$'
       AND inventory.writer_probe_source_sha256 ~ '^[0-9a-f]{64}$'
       AND inventory.inventory_result_sha256 ~ '^[0-9a-f]{64}$'
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_INVENTORY_REFRESH_INVALID';
  END IF;
  SELECT inventory.inventory_result_sha256 INTO v_inventory_hash_before
    FROM private.source_scoped_evidence_contract_inventory inventory
   WHERE inventory.id=v_inventory_id;
  IF to_regprocedure('private.reject_source_scoped_evidence_v3_bound_member_mutation()') IS NULL
     OR to_regprocedure('private.reject_source_scoped_evidence_v3_consumer_mutation()') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger
        WHERE tgrelid='public.fact'::regclass
          AND tgname='trg_source_scoped_evidence_v3_fact_bound_member'
          AND NOT tgisinternal
     )
     OR EXISTS (
       SELECT 1
         FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p')
          AND c.oid NOT IN ('public.fact'::regclass,'public.assertion'::regclass,'public.citation'::regclass)
          AND NOT (n.nspname='private' AND c.relname LIKE 'source_scoped_evidence_v3_%')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0
                        AND NOT a.attisdropped AND a.attname IN (
                          'fact_id','assertion_id','citation_id','valgt_assertion_id','target_type','target_id',
                          'subjekt_type','subjekt_id','objekt_type','objekt_id'))
          AND NOT EXISTS (SELECT 1 FROM pg_trigger t
                           WHERE t.tgrelid=c.oid AND NOT t.tgisinternal
                             AND t.tgfoid='private.reject_source_scoped_evidence_v3_consumer_mutation()'::regprocedure)
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_BOUND_MEMBER_GUARDS_MISSING';
  END IF;
  FOR v_role IN SELECT unnest(ARRAY['authenticated','service_role']) LOOP
    FOR v_relation IN SELECT unnest(ARRAY['fact','assertion','citation']) LOOP
      v_error:=NULL;
      BEGIN
        EXECUTE format('SET LOCAL ROLE %I',v_role);
        EXECUTE format('INSERT INTO public.%I DEFAULT VALUES',v_relation);
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
      END;
      EXECUTE 'RESET ROLE';
      IF v_error IS NULL THEN
        RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_RAW_MODEL_DML_ALLOWED: %.%',v_role,v_relation;
      END IF;
    END LOOP;
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.red_authorize_source_scoped_replace(text,text,uuid,uuid,jsonb,text,text,timestamptz)',
    'public.red_apply_source_scoped_replace(uuid,jsonb)',
    'public.red_verify_source_scoped_replace(uuid)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_V1_SIGNATURE_MISSING: %', v_signature;
    END IF;
    IF has_function_privilege('anon', v_signature::regprocedure, 'EXECUTE')
       OR has_function_privilege('authenticated', v_signature::regprocedure, 'EXECUTE')
       OR has_function_privilege('service_role', v_signature::regprocedure, 'EXECUTE') THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_V1_EXECUTE_LEAK: %', v_signature;
    END IF;
    IF EXISTS (
      SELECT 1
        FROM pg_proc p
       WHERE p.oid=v_signature::regprocedure
         AND EXISTS (
           SELECT 1
             FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) privilege
            WHERE privilege.grantee=0 AND privilege.privilege_type='EXECUTE'
         )
    ) THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_V1_PUBLIC_EXECUTE_LEAK: %', v_signature;
    END IF;
  END LOOP;

  v_error:=NULL;
  v_state:=NULL;
  BEGIN
    PERFORM public.red_apply_source_scoped_replace(
      '00000000-0000-0000-0000-000000000153'::uuid, '{}'::jsonb
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT, v_state=RETURNED_SQLSTATE;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_REPLACE_V1_RETIRED' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_V1_BODY_NOT_RETIRED: %, %', v_state, v_error;
  END IF;

  -- BEFORE triggers must retire the historical V1 ledger itself, before a
  -- stale direct writer can reach its ordinary NOT NULL/FK constraints.
  FOREACH v_signature IN ARRAY ARRAY[
    'private.source_scoped_replace_authorization',
    'private.source_scoped_replace_batch',
    'private.source_scoped_replace_event'
  ] LOOP
    v_error:=NULL;
    BEGIN
      EXECUTE format('INSERT INTO %s DEFAULT VALUES', v_signature);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    END;
    IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_REPLACE_V1_RETIRED' THEN
      RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_V1_LEDGER_NOT_RETIRED: %, %',
        v_signature, v_error;
    END IF;
  END LOOP;

  IF to_regclass('private.source_scoped_evidence_v3_member') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_MEMBER_TABLE_MISSING';
  END IF;
  IF to_regclass('private.source_scoped_evidence_v3_migration_receipt') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_MIGRATION_RECEIPT_MISSING';
  END IF;
  IF to_regprocedure('private.source_scoped_evidence_v3_task4b_contract_sha256()') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
        WHERE receipt.contract_version='source-scoped-evidence-v3-task4b-v2'
          AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4b_contract_sha256()
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_TASK4B_RECEIPT_DRIFT';
  END IF;
  IF encode(extensions.digest(convert_to(
       pg_get_functiondef('private.source_scoped_evidence_v3_task4b_contract_sha256()'::regprocedure),'UTF8'
    ),'sha256'),'hex')<>'1fb9fdd14d75701d3a67b730c12a4f07ab4b0e65f9de6123aa776cd63f0b73ba' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_TASK4B_CONTRACT_HASH_FUNCTION_DRIFT';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4a-v1'
       AND receipt.contract_sha256 ~ '^[0-9a-f]{64}$'
  )
     OR NOT EXISTS (
       SELECT 1
         FROM private.source_scoped_evidence_v3_migration_receipt receipt
        WHERE receipt.contract_version='source-scoped-evidence-v3-task4a-v2'
          AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4a_contract_sha256()
     )
     OR (SELECT contract_sha256
           FROM private.source_scoped_evidence_v3_migration_receipt
          WHERE contract_version='source-scoped-evidence-v3-task4a-v1')
        IS NOT DISTINCT FROM
        (SELECT contract_sha256
           FROM private.source_scoped_evidence_v3_migration_receipt
          WHERE contract_version='source-scoped-evidence-v3-task4a-v2') THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_TASK4A_RECEIPT_TRANSITION_INVALID';
  END IF;
  IF encode(extensions.digest(convert_to(
       pg_get_functiondef('private.source_scoped_evidence_v3_task4a_contract_sha256()'::regprocedure),'UTF8'
     ),'sha256'),'hex')<>'6f9ee99a0b5ff924eee42c05dbd7fc6b8f2eeffa045da340a61b008622eb647c' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_CONTRACT_HASH_FUNCTION_DRIFT';
  END IF;

  -- A real V3 member must be protected through the selected-assertion
  -- consumer path, not merely through the similarly named assertion_id path.
  v_source_id:=990153001;
  v_person_id:=990153002;
  v_fact_id:=990153003;
  v_assertion_id:=990153004;
  v_unbound_assertion_id:=990153005;
  INSERT INTO public.source(id,titel) VALUES (v_source_id,'Task 4B guard fixture');
  INSERT INTO public.person(id) VALUES (v_person_id);
  INSERT INTO private.extraction_run(
    source_id,run_key,schema_version,extractor_version,profile_version,input_sha256
  ) VALUES (
    v_source_id,'task4b-guard','task4b','task4b','task4b',repeat('0',64)
  ) RETURNING id INTO v_run_id;
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
  VALUES (v_source_id,'task4b-guard-record','fixture',v_run_id) RETURNING id INTO v_record_id;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
  VALUES (v_source_id,'task4b-guard-persona',v_run_id) RETURNING id INTO v_persona_id;
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype)
  VALUES (v_fact_id,'person',v_person_id,'fixture');
  INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst)
  VALUES (v_assertion_id,'person',v_person_id,'fixture');
  INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst)
  VALUES (v_unbound_assertion_id,'person',v_person_id,'unbound fixture');
  UPDATE public.assertion
     SET vaerdi_tekst='unbound mutation permitted'
   WHERE id=v_unbound_assertion_id;
  IF (SELECT vaerdi_tekst FROM public.assertion WHERE id=v_unbound_assertion_id)
       IS DISTINCT FROM 'unbound mutation permitted' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_UNBOUND_MEMBER_MUTATION_BLOCKED';
  END IF;
  INSERT INTO private.source_scoped_evidence_v3_chain(
    source_id,source_record_id,source_record_key,source_persona_id,canonical_person_id,chain_key
  ) VALUES (
    v_source_id,v_record_id,'task4b-guard-record',v_persona_id,v_person_id,repeat('1',64)
  ) RETURNING id INTO v_chain_id;
  INSERT INTO private.source_scoped_evidence_v3_revision(
    chain_id,revision,fact_id,revision_kind,chain_sha256,manifest_semantic_sha256
  ) VALUES (
    v_chain_id,1,v_fact_id,'content',repeat('2',64),repeat('3',64)
  ) RETURNING id INTO v_revision_id;
  INSERT INTO private.source_scoped_evidence_v3_member(
    revision_id,member_kind,member_key,assertion_id
  ) VALUES (v_revision_id,'assertion','assertion:task4b-guard',v_assertion_id);
  v_error:=NULL;
  BEGIN
    INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id)
    VALUES ('person',v_person_id,v_assertion_id);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_CONSUMER_MUTATION' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_SELECTED_ASSERTION_BYPASS: %',v_error;
  END IF;

  ALTER TABLE private.source_scoped_evidence_v3_migration_receipt
    ADD COLUMN source_scoped_evidence_v3_test_drift boolean;
  IF EXISTS (
    SELECT 1
      FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4a-v1'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4a_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_RECEIPT_SHAPE_NOT_HASHED';
  END IF;
  BEGIN
    INSERT INTO private.source_scoped_evidence_v3_member
      (revision_id,member_kind,member_key,fact_id,assertion_id)
    VALUES (
      '00000000-0000-0000-0000-000000000001'::uuid,
      'fact','fact:1',1,1
    );
  EXCEPTION WHEN check_violation THEN
    v_typed_member_rejected:=true;
  END;
  IF NOT v_typed_member_rejected THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_MEMBER_ONE_OF_NOT_ENFORCED';
  END IF;

  BEGIN
    INSERT INTO private.source_scoped_evidence_v3_revision(
      chain_id,revision,predecessor_revision_id,revision_kind,chain_sha256,
      manifest_semantic_sha256
    ) VALUES (
      '00000000-0000-0000-0000-000000000153'::uuid,2,
      '00000000-0000-0000-0000-000000000154'::uuid,'tombstone',
      repeat('a',64),repeat('b',64)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    v_predecessor_rejected:=(v_error='SOURCE_SCOPED_EVIDENCE_V3_PREDECESSOR_INVALID');
  END;
  IF NOT v_predecessor_rejected THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_PREDECESSOR_GUARD_MISSING: %', v_error;
  END IF;

  -- Every discovery family must be represented by actual catalog objects, not
  -- a synthetic probe marker.  The new objects are transaction-local.
  EXECUTE 'CREATE VIEW public.source_scoped_evidence_v3_test_reader_view AS SELECT id FROM public.fact';
  EXECUTE $create_reader$
    CREATE FUNCTION private.source_scoped_evidence_v3_test_reader()
    RETURNS SETOF public.fact
    LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public
    AS 'SELECT * FROM public.fact'
  $create_reader$;
  EXECUTE 'CREATE TABLE public.visibility_probe_consumer (fact_id bigint REFERENCES public.fact(id), target_type text, target_id bigint)';
  v_inventory_id:=private.refresh_source_scoped_evidence_contract_inventory(
    'source-scoped-evidence-v3-inventory-test-v1'
  );
  SELECT inventory.inventory_result_sha256 INTO v_inventory_hash_after
    FROM private.source_scoped_evidence_contract_inventory inventory
   WHERE inventory.id=v_inventory_id;
  IF v_inventory_hash_after IS NOT DISTINCT FROM v_inventory_hash_before
     OR NOT (private.source_scoped_evidence_v3_reader_probe() @> jsonb_build_array(
       jsonb_build_object('kind','reader_view','object_schema','public',
         'object_name','source_scoped_evidence_v3_test_reader_view')
     ))
     OR NOT (private.source_scoped_evidence_v3_reader_probe() @> jsonb_build_array(
       jsonb_build_object('kind','reader_routine','object_schema','private',
         'object_name','source_scoped_evidence_v3_test_reader')
     ))
     OR NOT (private.source_scoped_evidence_v3_consumer_probe() @> jsonb_build_array(
       jsonb_build_object('kind','consumer','object_schema','public',
         'object_name','visibility_probe_consumer')
     )) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_CATALOG_DISCOVERY_INCOMPLETE';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM jsonb_array_elements(private.source_scoped_evidence_v3_reader_probe()) entry
     WHERE entry @> jsonb_build_object(
       'kind','reader_view','object_schema','public',
       'object_name','source_scoped_evidence_v3_test_reader_view'
     )
       AND entry->'guard' ?& ARRAY[
         'object_acl','security_barrier','security_invoker','relation_security_surface','classification'
       ]
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_READER_GUARD_INCOMPLETE';
  END IF;
  v_inventory_hash_before:=v_inventory_hash_after;
  EXECUTE 'GRANT SELECT ON public.source_scoped_evidence_v3_test_reader_view TO authenticated';
  EXECUTE 'ALTER VIEW public.source_scoped_evidence_v3_test_reader_view SET (security_invoker=true)';
  v_inventory_id:=private.refresh_source_scoped_evidence_contract_inventory(
    'source-scoped-evidence-v3-inventory-test-v1'
  );
  SELECT inventory.inventory_result_sha256 INTO v_inventory_hash_after
    FROM private.source_scoped_evidence_contract_inventory inventory
   WHERE inventory.id=v_inventory_id;
  IF v_inventory_hash_after IS NOT DISTINCT FROM v_inventory_hash_before THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_READER_GUARD_DRIFT_UNDETECTED';
  END IF;
  v_inventory_hash_before:=v_inventory_hash_after;
  SELECT tgname INTO v_trigger
    FROM pg_trigger
   WHERE tgrelid='public.conclusion'::regclass AND NOT tgisinternal
     AND tgfoid='private.reject_source_scoped_evidence_v3_consumer_mutation()'::regprocedure;
  EXECUTE format('DROP TRIGGER %I ON public.conclusion',v_trigger);
  v_inventory_id:=private.refresh_source_scoped_evidence_contract_inventory(
    'source-scoped-evidence-v3-inventory-test-v1'
  );
  SELECT inventory.inventory_result_sha256 INTO v_inventory_hash_after
    FROM private.source_scoped_evidence_contract_inventory inventory
   WHERE inventory.id=v_inventory_id;
  IF v_inventory_hash_after IS NOT DISTINCT FROM v_inventory_hash_before THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_CONSUMER_GUARD_DRIFT_UNDETECTED';
  END IF;
  IF NOT (private.source_scoped_evidence_v3_writer_probe() @> jsonb_build_array(
    jsonb_build_object('kind','writer','object_schema','public','object_name','_version_upsert_row',
      'guard',jsonb_build_object('dynamic_sql_allowlist',jsonb_build_object(
        'mode','version_pk_registry','model_targets',jsonb_build_array('assertion','citation','fact')
      )))
  )) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_VERSION_WRITER_UNINVENTORIED';
  END IF;
  EXECUTE $create_writer$
    CREATE PROCEDURE public.source_scoped_evidence_v3_test_lowercase_dynamic()
    LANGUAGE plpgsql AS $procedure$
    BEGIN
      execute 'SELECT 1';
    END
    $procedure$
  $create_writer$;
  v_error:=NULL;
  BEGIN
    PERFORM private.refresh_source_scoped_evidence_contract_inventory(
      'source-scoped-evidence-v3-inventory-test-v1'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_UNCLASSIFIED_DYNAMIC_SQL' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_LOWERCASE_DYNAMIC_PROCEDURE_NOT_REJECTED: %',v_error;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid='private.source_scoped_evidence_v3_revision'::regclass
       AND pg_get_constraintdef(c.oid,true) LIKE '%FOREIGN KEY (predecessor_revision_id, chain_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid='private.source_scoped_evidence_v3_publication'::regclass
       AND pg_get_constraintdef(c.oid,true) LIKE '%FOREIGN KEY (revision_id, chain_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid='private.source_scoped_evidence_v3_chain_event'::regclass
       AND pg_get_constraintdef(c.oid,true) LIKE '%FOREIGN KEY (revision_id, chain_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid='private.source_scoped_evidence_v3_chain_state'::regclass
       AND pg_get_constraintdef(c.oid,true) LIKE '%FOREIGN KEY (last_event_id, chain_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid='private.source_scoped_evidence_v3_chain_state'::regclass
       AND pg_get_constraintdef(c.oid,true) LIKE '%FOREIGN KEY (head_revision_id, chain_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid='private.source_scoped_evidence_v3_chain_state'::regclass
       AND pg_get_constraintdef(c.oid,true) LIKE '%FOREIGN KEY (visible_revision_id, chain_id)%'
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_CHAIN_COHERENCE_MISSING';
  END IF;
END
$source_scoped_evidence_v3_contract$;

CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_test_dynamic_writer()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $$
BEGIN
  EXECUTE 'INSERT INTO fact DEFAULT VALUES';
END
$$;

DO $source_scoped_evidence_v3_dynamic_writer_contract$
DECLARE v_error text;
BEGIN
  BEGIN
    PERFORM private.refresh_source_scoped_evidence_contract_inventory(
      'source-scoped-evidence-v3-inventory-test-v1'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_UNCLASSIFIED_DYNAMIC_SQL' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_DYNAMIC_WRITER_NOT_REJECTED: %',v_error;
  END IF;
END
$source_scoped_evidence_v3_dynamic_writer_contract$;

ROLLBACK;
