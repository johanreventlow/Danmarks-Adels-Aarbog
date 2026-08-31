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
        WHERE receipt.contract_version='source-scoped-evidence-v3-task4a-v3'
          AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4a_contract_sha256()
     )
     OR (SELECT contract_sha256
           FROM private.source_scoped_evidence_v3_migration_receipt
          WHERE contract_version='source-scoped-evidence-v3-task4a-v1')
        IS NOT DISTINCT FROM
        (SELECT contract_sha256
           FROM private.source_scoped_evidence_v3_migration_receipt
          WHERE contract_version='source-scoped-evidence-v3-task4a-v3') THEN
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

-- #153 Task 4C RED: bound evidence must not rely on the historical model
-- policies alone.  The three policy-safe public ID projections are the only
-- public surface through which a V3-bound member can become readable.
DO $source_scoped_evidence_v3_visibility_matrix$
DECLARE
  v_source_id bigint:=990153100;
  v_person_id bigint:=990153101;
  v_fact_id bigint:=990153102;
  v_assertion_id bigint:=990153103;
  v_citation_id bigint:=990153104;
  v_cross_assertion_id bigint:=990153107;
  v_cross_citation_id bigint:=990153108;
  v_unbound_fact_id bigint:=990153105;
  v_relation_id bigint;
  v_run_id uuid;
  v_record_id uuid;
  v_persona_id uuid;
  v_chain_id uuid;
  v_revision_id uuid;
  v_event_id uuid;
  v_error text;
  v_actor_id uuid:='00000000-0000-0000-0000-000000153001';
  v_authorization_id uuid;
  v_replay_authorization_id uuid;
  v_inventory_id uuid;
  v_deployment_id uuid;
  v_receipt jsonb;
  v_receipt_sha256 text;
  v_contract_hash_before text;
  v_contract_hash_after text;
  v_state private.source_scoped_evidence_v3_chain_state%ROWTYPE;
BEGIN
  IF (SELECT count(*) FROM pg_class view_class
        JOIN pg_namespace view_schema ON view_schema.oid=view_class.relnamespace
       WHERE view_schema.nspname='public'
         AND view_class.relname=ANY(ARRAY[
           'source_scoped_evidence_visible_fact_ids',
           'source_scoped_evidence_visible_assertion_ids',
           'source_scoped_evidence_visible_citation_ids'
         ])
         AND view_class.relkind='v'
         AND view_class.reloptions @> ARRAY['security_barrier=true']
         AND NOT (view_class.reloptions @> ARRAY['security_invoker=true']))<>3 THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_VISIBILITY_VIEWS_MISSING';
  END IF;

  -- Task 4C publication is deliberately two-stage.  The authorize endpoint
  -- must be the sole application-writable entry point; the apply endpoint
  -- consumes only that immutable authorization.
  IF to_regprocedure(
       'public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)'
     ) IS NULL
     OR to_regprocedure(
       'public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)'
     ) IS NULL
     OR to_regprocedure('private.source_scoped_evidence_v3_task4c_contract_sha256()') IS NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_RPC_MISSING';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_v3_migration_receipt receipt
        WHERE receipt.contract_version='source-scoped-evidence-v3-task4c-v5'
          AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4c_contract_sha256()
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_RECEIPT_MISSING';
  END IF;
  IF NOT has_function_privilege(
       'authenticated',
       'public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'authenticated',
       'public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.red_authorize_source_scoped_evidence_publication_v3(uuid,uuid,uuid,text,jsonb,uuid,timestamp with time zone)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'service_role',
       'public.red_publish_source_scoped_evidence_revision_v3(uuid,jsonb)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_RPC_ACL_INVALID';
  END IF;

  INSERT INTO public.source(id,titel) VALUES (v_source_id,'Task 4C visibility fixture');
  INSERT INTO public.person(id,levende,privat,staged) VALUES (v_person_id,false,false,false);
  INSERT INTO auth.users(id,email) VALUES (v_actor_id,'task4c-publication@example.invalid');
  INSERT INTO public.profiles(id,rolle) VALUES (v_actor_id,'redaktion');
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype)
  VALUES (v_fact_id,'person',v_person_id,'fixture'),(v_unbound_fact_id,'person',v_person_id,'fixture');
  INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst)
  VALUES (v_assertion_id,'fact',v_fact_id,'fixture');
  INSERT INTO public.citation(id,assertion_id,source_id,side)
  VALUES (v_citation_id,v_assertion_id,v_source_id,'fixture');
  -- This assertion/citation remain historically unbound, but their fact target
  -- is a hidden V3 member. Their public ID views must not become an oracle for
  -- the hidden fact's binding state.
  INSERT INTO public.assertion(id,target_type,target_id,vaerdi_tekst)
  VALUES (v_cross_assertion_id,'fact',v_fact_id,'cross-binding fixture');
  INSERT INTO public.citation(id,assertion_id,source_id,side)
  VALUES (v_cross_citation_id,v_cross_assertion_id,v_source_id,'cross-binding fixture');
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
  VALUES ('person',v_person_id,'person',v_person_id,'fixture') RETURNING id INTO v_relation_id;
  INSERT INTO public.note(id,target_type,target_id,indhold,privat)
  VALUES (990153106,'fact',v_fact_id,'bound note',false);
  INSERT INTO private.extraction_run(source_id,run_key,schema_version,extractor_version,profile_version,input_sha256)
  VALUES (v_source_id,'task4c-visibility','task4c','task4c','task4c',repeat('0',64)) RETURNING id INTO v_run_id;
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id)
  VALUES (v_source_id,'task4c-visibility-record','fixture',v_run_id) RETURNING id INTO v_record_id;
  INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
  VALUES (v_source_id,'task4c-visibility-persona',v_run_id) RETURNING id INTO v_persona_id;
  INSERT INTO private.source_scoped_evidence_v3_chain(
    source_id,source_record_id,source_record_key,source_persona_id,canonical_person_id,chain_key
  ) VALUES (v_source_id,v_record_id,'task4c-visibility-record',v_persona_id,v_person_id,repeat('4',64))
  RETURNING id INTO v_chain_id;
  INSERT INTO private.source_scoped_evidence_v3_revision(
    chain_id,revision,fact_id,revision_kind,chain_sha256,manifest_semantic_sha256
  ) VALUES (v_chain_id,1,v_fact_id,'content',repeat('5',64),repeat('6',64)) RETURNING id INTO v_revision_id;
  INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,fact_id)
  VALUES (v_revision_id,'fact','fact:task4c',v_fact_id);
  INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,assertion_id)
  VALUES (v_revision_id,'assertion','assertion:task4c',v_assertion_id);
  INSERT INTO private.source_scoped_evidence_v3_member(revision_id,member_kind,member_key,citation_id)
  VALUES (v_revision_id,'citation','citation:task4c',v_citation_id);

  -- The first event has no predecessor state.  Accepting a fabricated hash
  -- here would create an unrelated audit edge before the chain exists.
  v_event_id:=gen_random_uuid();
  v_error:=NULL;
  BEGIN
    INSERT INTO private.source_scoped_evidence_v3_chain_event(
      id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id
    ) VALUES (v_event_id,v_chain_id,'source_revision_created',repeat('a',64),
      private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,NULL,1,v_event_id),
      v_revision_id);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_TRANSITION_INVALID' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_EVENT_INITIAL_PREDECESSOR_NOT_REJECTED: %',v_error;
  END IF;

  v_event_id:=gen_random_uuid();
  INSERT INTO private.source_scoped_evidence_v3_chain_event(
    id,chain_id,event_type,after_state_sha256,revision_id
  ) VALUES (v_event_id,v_chain_id,'source_revision_created',
    private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,NULL,1,v_event_id),
    v_revision_id);

  BEGIN
    UPDATE private.source_scoped_evidence_v3_chain_state
       SET state_version=2
     WHERE chain_id=v_chain_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_DIRECT_MUTATION' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_GUARD_MISSING: %',v_error;
  END IF;

  -- Trigger depth is ambient session state, not proof that an append-only
  -- chain event created this projection.  A nested but unrelated trigger must
  -- not be able to advance a state hash against an older event.
  CREATE OR REPLACE FUNCTION private.source_scoped_evidence_v3_test_state_guard_bypass()
  RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,private AS $state_guard_bypass$
  DECLARE v_current private.source_scoped_evidence_v3_chain_state%ROWTYPE;
  BEGIN
    SELECT state.* INTO v_current
      FROM private.source_scoped_evidence_v3_chain_state state
      JOIN private.source_scoped_evidence_v3_chain chain ON chain.id=state.chain_id
     WHERE chain.source_id=NEW.id;
    UPDATE private.source_scoped_evidence_v3_chain_state
       SET state_version=v_current.state_version+1,
           state_sha256=private.source_scoped_evidence_v3_chain_state_sha256(
             v_current.chain_id,v_current.head_revision_id,v_current.visible_revision_id,
             v_current.state_version+1,v_current.last_event_id
           )
     WHERE chain_id=v_current.chain_id;
    RETURN NEW;
  END
  $state_guard_bypass$;
  CREATE TRIGGER trg_source_scoped_evidence_v3_test_state_guard_bypass
    BEFORE UPDATE ON public.source
    FOR EACH ROW EXECUTE FUNCTION private.source_scoped_evidence_v3_test_state_guard_bypass();
  v_error:=NULL;
  BEGIN
    UPDATE public.source SET titel='Task 4C state guard bypass attempt'
     WHERE id=v_source_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  DROP TRIGGER trg_source_scoped_evidence_v3_test_state_guard_bypass ON public.source;
  DROP FUNCTION private.source_scoped_evidence_v3_test_state_guard_bypass();
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_DIRECT_MUTATION' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_CHAIN_STATE_TRIGGER_DEPTH_BYPASS: %',v_error;
  END IF;

  -- Precommit must never register a deployment.  A non-existent deployment
  -- therefore reaches the public authorization gate only to prove that it is
  -- rejected before inventory/state publication or any authorization row.
  SELECT * INTO v_state
    FROM private.source_scoped_evidence_v3_chain_state state
   WHERE state.chain_id=v_chain_id;
  PERFORM set_config('request.jwt.claim.sub',v_actor_id::text,true);
  v_error:=NULL;
  BEGIN
    SELECT public.red_authorize_source_scoped_evidence_publication_v3(
      v_chain_id,v_revision_id,'00000000-0000-0000-0000-000000153999',
      v_state.state_sha256,
      jsonb_build_object(
        'schema','source-scoped-evidence-v3-publication-decision-v1',
        'chain_id',v_chain_id::text,'revision_id',v_revision_id::text,
        'deployment_id','00000000-0000-0000-0000-000000153999',
        'deployment_sha256',repeat('f',64),'expected_state_sha256',v_state.state_sha256,
        'decision','publish','rationale','precommit forged deployment fixture'
      ),'00000000-0000-0000-0000-000000153998',clock_timestamp()+interval '5 minutes'
    ) INTO v_authorization_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_DEPLOYMENT_INVALID'
     OR v_authorization_id IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_publication_v3_authorization auth_row
        WHERE auth_row.chain_id=v_chain_id
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_FORGED_DEPLOYMENT_NOT_REJECTED: %',v_error;
  END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);

  -- A consumed authorization must retain the exact receipt returned by the
  -- publication gateway.  Without these fields, a retry is indistinguishable
  -- from a rejected second use and cannot prove exact replay.
  IF NOT EXISTS (
       SELECT 1 FROM pg_attribute attribute
        WHERE attribute.attrelid='private.source_scoped_evidence_publication_v3_authorization'::regclass
          AND attribute.attname='receipt' AND attribute.attnum>0 AND NOT attribute.attisdropped
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_attribute attribute
        WHERE attribute.attrelid='private.source_scoped_evidence_publication_v3_authorization'::regclass
          AND attribute.attname='receipt_sha256' AND attribute.attnum>0 AND NOT attribute.attisdropped
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_PUBLICATION_REPLAY_RECEIPT_COLUMNS_MISSING';
  END IF;
  SELECT inventory.id INTO v_inventory_id
    FROM private.source_scoped_evidence_contract_inventory inventory
   ORDER BY inventory.created_at,inventory.id
   LIMIT 1;
  INSERT INTO private.source_scoped_evidence_v3_deployment(
    inventory_id,repository_tree_id,repository_writer_artifact_sha256,
    schema_contract_version,database_name,system_identifier,registered_by,deployment_sha256
  ) VALUES (
    v_inventory_id,'task4c-replay-fixture',repeat('7',64),'task4c-replay-fixture',
    current_database(),(pg_control_system()).system_identifier::text,v_actor_id,repeat('8',64)
  ) RETURNING id INTO v_deployment_id;
  INSERT INTO private.source_scoped_evidence_publication_v3_authorization(
    chain_id,revision_id,deployment_id,deployment_sha256,expected_state_sha256,
    decision_payload,decision_payload_sha256,actor_id,nonce,expires_at
  ) VALUES (
    v_chain_id,v_revision_id,v_deployment_id,repeat('8',64),v_state.state_sha256,
    jsonb_build_object('schema','source-scoped-evidence-v3-publication-decision-v1',
      'chain_id',v_chain_id::text,'revision_id',v_revision_id::text,
      'deployment_id',v_deployment_id::text,'deployment_sha256',repeat('8',64),
      'expected_state_sha256',v_state.state_sha256,'decision','publish',
      'rationale','Task 4C replay fixture'),
    private.source_scoped_evidence_v3_publication_decision_sha256(
      jsonb_build_object('schema','source-scoped-evidence-v3-publication-decision-v1',
        'chain_id',v_chain_id::text,'revision_id',v_revision_id::text,
        'deployment_id',v_deployment_id::text,'deployment_sha256',repeat('8',64),
        'expected_state_sha256',v_state.state_sha256,'decision','publish',
        'rationale','Task 4C replay fixture')
    ),v_actor_id,'00000000-0000-0000-0000-000000153997',clock_timestamp()+interval '5 minutes'
  ) RETURNING id INTO v_replay_authorization_id;
  v_error:=NULL;
  BEGIN
    UPDATE private.source_scoped_evidence_publication_v3_authorization
       SET consumed_at=clock_timestamp()
     WHERE id=v_replay_authorization_id;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'SOURCE_SCOPED_EVIDENCE_V3_PUBLICATION_AUTHORIZATION_APPEND_ONLY' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_PUBLICATION_REPLAY_RECEIPT_REQUIRED: %',v_error;
  END IF;
  v_receipt:=jsonb_build_object(
    'schema','source-scoped-evidence-v3-publication-receipt-v1',
    'authorization_id',v_replay_authorization_id::text,'terminal_status','published'
  );
  v_receipt_sha256:=encode(extensions.digest(v_receipt::text,'sha256'),'hex');
  UPDATE private.source_scoped_evidence_publication_v3_authorization
     SET consumed_at=clock_timestamp(),receipt=v_receipt,receipt_sha256=v_receipt_sha256
   WHERE id=v_replay_authorization_id;
  IF NOT EXISTS (
       SELECT 1 FROM private.source_scoped_evidence_publication_v3_authorization authorization_row
        WHERE authorization_row.id=v_replay_authorization_id
          AND authorization_row.receipt IS NOT DISTINCT FROM v_receipt
          AND authorization_row.receipt_sha256 IS NOT DISTINCT FROM v_receipt_sha256
     ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_PUBLICATION_REPLAY_RECEIPT_NOT_PERSISTED';
  END IF;

  v_contract_hash_before:=private.source_scoped_evidence_v3_task4c_contract_sha256();
  ALTER TABLE private.source_scoped_evidence_v3_chain_state
    ADD COLUMN source_scoped_evidence_v3_test_receipt_drift boolean;
  v_contract_hash_after:=private.source_scoped_evidence_v3_task4c_contract_sha256();
  IF v_contract_hash_before IS NOT DISTINCT FROM v_contract_hash_after THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_PUBLICATION_RECEIPT_STATE_UNBOUND';
  END IF;

  IF to_regprocedure('private.source_scoped_evidence_v3_visibility_allowed(text,bigint)') IS NOT NULL
     OR to_regprocedure('private.source_scoped_evidence_v3_public_gate_allowed(text,bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PRIVATE_STATE_ORACLE_EXISTS';
  END IF;
END
$source_scoped_evidence_v3_visibility_matrix$;

SET LOCAL ROLE anon;
DO $source_scoped_evidence_v3_visibility_anon_hidden$
BEGIN
  IF EXISTS (SELECT 1 FROM public.fact WHERE id=990153102)
     OR EXISTS (SELECT 1 FROM public.assertion WHERE id=990153103)
     OR EXISTS (SELECT 1 FROM public.citation WHERE id=990153104)
     OR EXISTS (SELECT 1 FROM public.note WHERE id=990153106)
     OR EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids WHERE id=990153102)
     OR EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids WHERE id=990153103)
     OR EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_citation_ids WHERE id=990153104)
     OR EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids WHERE id=990153107)
     OR EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_citation_ids WHERE id=990153108)
     OR NOT EXISTS (SELECT 1 FROM public.fact WHERE id=990153105)
     OR NOT EXISTS (SELECT 1 FROM public.relation WHERE rolle='fixture') THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_HIDDEN_OR_HISTORICAL_VISIBILITY_INVALID';
  END IF;
END
$source_scoped_evidence_v3_visibility_anon_hidden$;
RESET ROLE;

DO $source_scoped_evidence_v3_publish_fixture$
DECLARE v_chain_id uuid; v_revision_id uuid; v_state private.source_scoped_evidence_v3_chain_state%ROWTYPE;
  v_event_id uuid; v_publication_id uuid;
BEGIN
  SELECT chain.id,revision.id INTO v_chain_id,v_revision_id
    FROM private.source_scoped_evidence_v3_chain chain
    JOIN private.source_scoped_evidence_v3_revision revision ON revision.chain_id=chain.id
   WHERE revision.fact_id=990153102;
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=v_chain_id;
  v_event_id:=gen_random_uuid();
  INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id)
  VALUES (v_event_id,v_chain_id,'eligible',v_state.state_sha256,
    private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,NULL,v_state.state_version+1,v_event_id),v_revision_id);
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=v_chain_id;
  INSERT INTO private.source_scoped_evidence_v3_publication(chain_id,revision_id,decision,decision_state_sha256,decision_payload,decided_by)
  VALUES (v_chain_id,v_revision_id,'publish',v_state.state_sha256,'{}'::jsonb,gen_random_uuid()) RETURNING id INTO v_publication_id;
  v_event_id:=gen_random_uuid();
  INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id,publication_id)
  VALUES (v_event_id,v_chain_id,'published',v_state.state_sha256,
    private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,v_revision_id,v_state.state_version+1,v_event_id),v_revision_id,v_publication_id);
END
$source_scoped_evidence_v3_publish_fixture$;
SET LOCAL ROLE authenticated;
DO $source_scoped_evidence_v3_visibility_authenticated_published$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.fact WHERE id=990153102)
     OR NOT EXISTS (SELECT 1 FROM public.assertion WHERE id=990153103)
     OR NOT EXISTS (SELECT 1 FROM public.citation WHERE id=990153104)
     OR NOT EXISTS (SELECT 1 FROM public.note WHERE id=990153106)
     OR NOT EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids WHERE id=990153102)
     OR NOT EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids WHERE id=990153103)
     OR NOT EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_citation_ids WHERE id=990153104) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_PUBLISHED_VISIBILITY_INVALID';
  END IF;
END
$source_scoped_evidence_v3_visibility_authenticated_published$;
RESET ROLE;

SET LOCAL ROLE anon;
DO $source_scoped_evidence_v3_visibility_anon_published$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.fact WHERE id=990153102)
     OR NOT EXISTS (SELECT 1 FROM public.assertion WHERE id=990153103)
     OR NOT EXISTS (SELECT 1 FROM public.citation WHERE id=990153104)
     OR NOT EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids WHERE id=990153102)
     OR NOT EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_assertion_ids WHERE id=990153103)
     OR NOT EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_citation_ids WHERE id=990153104) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_ANON_PUBLISHED_VISIBILITY_INVALID';
  END IF;
END
$source_scoped_evidence_v3_visibility_anon_published$;
RESET ROLE;

DO $source_scoped_evidence_v3_withdraw_fixture$
DECLARE v_chain_id uuid; v_previous_revision_id uuid; v_revision_id uuid; v_state private.source_scoped_evidence_v3_chain_state%ROWTYPE;
  v_event_id uuid; v_publication_id uuid;
BEGIN
  SELECT chain.id,state.head_revision_id INTO v_chain_id,v_previous_revision_id
    FROM private.source_scoped_evidence_v3_chain chain JOIN private.source_scoped_evidence_v3_chain_state state ON state.chain_id=chain.id
   WHERE state.visible_revision_id=(SELECT id FROM private.source_scoped_evidence_v3_revision WHERE fact_id=990153102);
  INSERT INTO private.source_scoped_evidence_v3_revision(chain_id,revision,predecessor_revision_id,revision_kind,chain_sha256,manifest_semantic_sha256)
  VALUES (v_chain_id,2,v_previous_revision_id,'tombstone',repeat('a',64),repeat('b',64)) RETURNING id INTO v_revision_id;
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=v_chain_id;
  v_event_id:=gen_random_uuid();
  INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id)
  VALUES (v_event_id,v_chain_id,'source_revision_created',v_state.state_sha256,
    private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,v_state.visible_revision_id,v_state.state_version+1,v_event_id),v_revision_id);
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=v_chain_id;
  v_event_id:=gen_random_uuid();
  INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id)
  VALUES (v_event_id,v_chain_id,'eligible',v_state.state_sha256,
    private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,v_state.visible_revision_id,v_state.state_version+1,v_event_id),v_revision_id);
  SELECT * INTO v_state FROM private.source_scoped_evidence_v3_chain_state WHERE chain_id=v_chain_id;
  INSERT INTO private.source_scoped_evidence_v3_publication(chain_id,revision_id,decision,decision_state_sha256,decision_payload,decided_by)
  VALUES (v_chain_id,v_revision_id,'withdraw',v_state.state_sha256,'{}'::jsonb,gen_random_uuid()) RETURNING id INTO v_publication_id;
  v_event_id:=gen_random_uuid();
  INSERT INTO private.source_scoped_evidence_v3_chain_event(id,chain_id,event_type,predecessor_state_sha256,after_state_sha256,revision_id,publication_id)
  VALUES (v_event_id,v_chain_id,'withdrawn',v_state.state_sha256,
    private.source_scoped_evidence_v3_chain_state_sha256(v_chain_id,v_revision_id,NULL,v_state.state_version+1,v_event_id),v_revision_id,v_publication_id);
END
$source_scoped_evidence_v3_withdraw_fixture$;
SET LOCAL ROLE authenticated;
DO $source_scoped_evidence_v3_visibility_authenticated_withdrawn$
BEGIN
  IF EXISTS (SELECT 1 FROM public.fact WHERE id=990153102)
     OR EXISTS (SELECT 1 FROM public.assertion WHERE id=990153103)
     OR EXISTS (SELECT 1 FROM public.citation WHERE id=990153104)
     OR EXISTS (SELECT 1 FROM public.note WHERE id=990153106)
     OR EXISTS (SELECT 1 FROM public.source_scoped_evidence_visible_fact_ids WHERE id=990153102) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_WITHDRAWN_VISIBILITY_INVALID';
  END IF;
END
$source_scoped_evidence_v3_visibility_authenticated_withdrawn$;
RESET ROLE;

ROLLBACK;
