-- #153 Task 4A.  Run after the disposable bootstrap, schema.sql and db-rls.sql.
-- The transaction is rolled back so this contract never leaves fixture rows behind.
BEGIN;

DO $source_scoped_evidence_v3_contract$
DECLARE
  v_signature text;
  v_error text;
  v_state text;
  v_typed_member_rejected boolean := false;
  v_predecessor_rejected boolean := false;
BEGIN
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
  IF NOT EXISTS (
    SELECT 1
      FROM private.source_scoped_evidence_v3_migration_receipt receipt
     WHERE receipt.contract_version='source-scoped-evidence-v3-task4a-v1'
       AND receipt.contract_sha256 ~ '^[0-9a-f]{64}$'
       AND receipt.contract_sha256=private.source_scoped_evidence_v3_task4a_contract_sha256()
  ) THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_MIGRATION_RECEIPT_DRIFT';
  END IF;
  IF encode(extensions.digest(convert_to(
       pg_get_functiondef('private.source_scoped_evidence_v3_task4a_contract_sha256()'::regprocedure),'UTF8'
     ),'sha256'),'hex')<>'6f9ee99a0b5ff924eee42c05dbd7fc6b8f2eeffa045da340a61b008622eb647c' THEN
    RAISE EXCEPTION 'SOURCE_SCOPED_EVIDENCE_V3_TEST_CONTRACT_HASH_FUNCTION_DRIFT';
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

ROLLBACK;
