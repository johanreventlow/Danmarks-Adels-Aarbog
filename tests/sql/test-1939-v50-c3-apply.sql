-- Task 5 (C3 atomic apply plan): private.reimport_case_authorization / _batch / _event
-- catalog + constraint proof. No RPCs exist yet (Task 6 builds those); this file proves
-- only the table skeleton -- UUID PKs, hash/status/action vocabularies, the two
-- composite drift-guard FKs (event->batch, batch->authorization), the reversal/
-- change-set reference columns, append-only event rows, least-privilege ACLs, and the
-- separate fund-B4 narrative_record_publication exclusivity index.

\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
BEGIN
  IF to_regclass('private.reimport_case_authorization') IS NULL
     OR to_regclass('private.reimport_case_batch') IS NULL
     OR to_regclass('private.reimport_case_event') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_TABLES_MISSING';
  END IF;
  IF to_regclass('private.narrative_record_publication_active_record_uidx') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_RECORD_EXCLUSIVITY_INDEX_MISSING';
  END IF;
  IF to_regprocedure('private.reject_reimport_case_event_mutation()') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_EVENT_APPEND_ONLY_TRIGGER_FUNCTION_MISSING';
  END IF;

  -- UUID primary keys on authorization and batch (event stays bigint identity,
  -- matching the append-only ledger style of the reimport_1939_write_event family).
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='private' AND table_name='reimport_case_authorization'
      AND column_name='id' AND udt_name='uuid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='private' AND table_name='reimport_case_batch'
      AND column_name='id' AND udt_name='uuid'
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_UUID_PRIMARY_KEY_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='private' AND table_name='reimport_case_event'
      AND column_name='id' AND udt_name='int8' AND is_identity='YES'
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_EVENT_IDENTITY_PRIMARY_KEY_MISSING';
  END IF;

  -- RLS enabled + no PUBLIC/anon/authenticated privilege on any of the three tables.
  IF EXISTS (
    SELECT 1 FROM pg_class c
    WHERE c.oid IN (
      'private.reimport_case_authorization'::regclass,
      'private.reimport_case_batch'::regclass,
      'private.reimport_case_event'::regclass
    ) AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_RLS_NOT_ENABLED';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
    WHERE c.oid IN (
      'private.reimport_case_authorization'::regclass,
      'private.reimport_case_batch'::regclass,
      'private.reimport_case_event'::regclass
    ) AND acl.grantee=0
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_PUBLIC_GRANT_PRESENT';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) privilege
    CROSS JOIN unnest(ARRAY[
      'private.reimport_case_authorization','private.reimport_case_batch','private.reimport_case_event'
    ]) tbl
    WHERE has_table_privilege('anon',tbl,privilege)
       OR has_table_privilege('authenticated',tbl,privilege)
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_TABLE_ACL_DRIFT';
  END IF;
  IF has_function_privilege('anon','private.reject_reimport_case_event_mutation()','EXECUTE')
     OR has_function_privilege('authenticated','private.reject_reimport_case_event_mutation()','EXECUTE') THEN
    RAISE EXCEPTION 'C3_APPLY_TRIGGER_FUNCTION_ACL_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    WHERE p.oid='private.reject_reimport_case_event_mutation()'::regprocedure
      AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_TRIGGER_FUNCTION_PUBLIC_GRANT_PRESENT';
  END IF;

  RAISE NOTICE 'OK: C3 apply ledger catalog contract (tables, PK types, index, RLS, ACLs)';
END $catalog$;

DO $test$
DECLARE
  v_source_a bigint; v_source_b bigint;
  v_auth_a uuid; v_auth_b uuid; v_auth_reversal uuid; v_batch_a uuid; v_batch_reversal uuid;
  v_change_set bigint;
  v_person bigint; v_run uuid; v_record1 uuid; v_record2 uuid;
  v_narrative1 bigint; v_narrative2 bigint;
  v_event1 bigint;
  v_hash64 text := repeat('a',64);
  v_hash64_b text := repeat('b',64);
  v_constraint text;
BEGIN
  v_source_a := (SELECT coalesce(max(id),0)+1 FROM public.source);
  INSERT INTO public.source(id,slags,titel,udgave,aar)
    VALUES (v_source_a,'DAA-udgave','C3 apply test A','C3 test A',2026);
  v_source_b := v_source_a + 1;
  INSERT INTO public.source(id,slags,titel,udgave,aar)
    VALUES (v_source_b,'DAA-udgave','C3 apply test B','C3 test B',2026);

  v_change_set := public.begin_change_set('c3-apply-ddl-test','C3 Task 5 DDL proof',NULL,NULL);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  ---------------------------------------------------------------------------
  -- reimport_case_authorization: UUID PK default, phase/operation/status
  -- vocabularies, hash-shape checks, nonce uniqueness, consumed_at coupling.
  ---------------------------------------------------------------------------
  INSERT INTO private.reimport_case_authorization(
    source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
    decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
    expected_counts,authorized_elements,principal_id,nonce,expires_at
  ) VALUES (
    v_source_a,'c3','apply',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
    current_database(),'test-system-identifier',
    '{"identity_different":1}'::jsonb,'{"e1":{}}'::jsonb,
    gen_random_uuid(),gen_random_uuid(),clock_timestamp()+interval '1 hour'
  ) RETURNING id INTO v_auth_a;
  IF v_auth_a IS NULL THEN RAISE EXCEPTION 'C3_APPLY_AUTHORIZATION_UUID_DEFAULT_MISSING'; END IF;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) SELECT source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
             decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
             expected_counts,authorized_elements,principal_id,nonce,expires_at
      FROM private.reimport_case_authorization WHERE id=v_auth_a;
    RAISE EXCEPTION 'EXPECTED_NONCE_UNIQUE_REJECTION';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c3','bogus',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
      current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_OPERATION_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_operation_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c2','apply',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
      current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_PHASE_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_phase_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c3','apply','not-a-hash',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
      current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_HASH_SHAPE_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_manifest_sha256_check' THEN RAISE; END IF;
  END;

  -- Spot-check a SECOND, independent hash column: all six *_sha256 columns share
  -- byte-identical regex text, so a typo confined to one column's CHECK (e.g. a
  -- missing character in approval_sha256's pattern) would not be caught by only
  -- ever exercising manifest_sha256 above.
  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c3','apply',v_hash64,v_hash64,'not-a-hash',v_hash64,v_hash64,v_hash64,
      current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_APPROVAL_HASH_SHAPE_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_approval_sha256_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c3','apply',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
      '   ','x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_DATABASE_NAME_BLANK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_database_name_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c3','apply',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
      current_database(),'x','[1,2]'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_EXPECTED_COUNTS_NOT_OBJECT_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_expected_counts_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_authorization(
      source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
      decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
      expected_counts,authorized_elements,principal_id,nonce,expires_at
    ) VALUES (
      v_source_a,'c3','apply',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
      current_database(),'x','{}'::jsonb,'"scalar"'::jsonb,gen_random_uuid(),gen_random_uuid(),
      clock_timestamp()+interval '1 hour'
    );
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_AUTHORIZED_ELEMENTS_NOT_OBJECT_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_authorized_elements_check' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE private.reimport_case_authorization SET status='consumed' WHERE id=v_auth_a;
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_CONSUMED_WITHOUT_TIMESTAMP_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_consumed_has_timestamp' THEN RAISE; END IF;
  END;
  UPDATE private.reimport_case_authorization
    SET status='consumed', consumed_at=clock_timestamp() WHERE id=v_auth_a;
  IF (SELECT status FROM private.reimport_case_authorization WHERE id=v_auth_a) <> 'consumed' THEN
    RAISE EXCEPTION 'C3_APPLY_AUTHORIZATION_CONSUMED_WRITE_FAILED';
  END IF;

  -- Second authorization (source B) for the batch/index cross-source tests below.
  INSERT INTO private.reimport_case_authorization(
    source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
    decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
    expected_counts,authorized_elements,principal_id,nonce,expires_at
  ) VALUES (
    v_source_b,'c3','apply',v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,v_hash64,
    current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
    clock_timestamp()+interval '1 hour'
  ) RETURNING id INTO v_auth_b;

  -- Authorization status vocabulary: reject anything outside issued|consumed|expired,
  -- and exercise the 'expired' transition explicitly (v_auth_a already proved
  -- 'consumed' above; v_auth_b is still 'issued'/consumed_at IS NULL here, so
  -- moving it straight to 'expired' does not collide with the consumed_has_timestamp
  -- coupling check).
  BEGIN
    UPDATE private.reimport_case_authorization SET status='not-a-status' WHERE id=v_auth_b;
    RAISE EXCEPTION 'EXPECTED_AUTHORIZATION_STATUS_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_authorization_status_check' THEN RAISE; END IF;
  END;
  UPDATE private.reimport_case_authorization SET status='expired' WHERE id=v_auth_b;
  IF (SELECT status FROM private.reimport_case_authorization WHERE id=v_auth_b) <> 'expired' THEN
    RAISE EXCEPTION 'C3_APPLY_AUTHORIZATION_EXPIRED_WRITE_FAILED';
  END IF;

  ---------------------------------------------------------------------------
  -- reimport_case_batch: composite FK to authorization (drift guard), unique
  -- index scoped by (source_id,phase,manifest,preview,principal), status/
  -- operation vocabularies, change_set_id + reversal_batch_id references.
  ---------------------------------------------------------------------------
  BEGIN
    -- authorization_id valid, but source_id deliberately mismatched: the composite
    -- FK (authorization_id,source_id,phase) must reject this, not just a plain
    -- single-column FK on authorization_id.
    INSERT INTO private.reimport_case_batch(
      authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
      principal_id,expected_counts,change_set_id
    ) VALUES (
      v_auth_a,v_source_b,'c3','apply',v_hash64,v_hash64,gen_random_uuid(),'{}'::jsonb,v_change_set
    );
    RAISE EXCEPTION 'EXPECTED_BATCH_AUTHORIZATION_SOURCE_DRIFT_REJECTION';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  INSERT INTO private.reimport_case_batch(
    authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
    principal_id,expected_counts,change_set_id
  ) VALUES (
    v_auth_a,v_source_a,'c3','apply',v_hash64,v_hash64,gen_random_uuid(),'{}'::jsonb,v_change_set
  ) RETURNING id INTO v_batch_a;
  IF v_batch_a IS NULL THEN RAISE EXCEPTION 'C3_APPLY_BATCH_UUID_DEFAULT_MISSING'; END IF;

  BEGIN
    INSERT INTO private.reimport_case_batch(
      authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
      principal_id,expected_counts
    ) VALUES (
      v_auth_a,v_source_a,'c3','apply',v_hash64_b,v_hash64_b,gen_random_uuid(),'{}'::jsonb
    );
    RAISE EXCEPTION 'EXPECTED_BATCH_AUTHORIZATION_ID_UNIQUE_REJECTION';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO private.reimport_case_batch(
      authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
      principal_id,expected_counts
    ) SELECT v_auth_b,source_id,phase,operation,manifest_sha256,preview_sha256,principal_id,expected_counts
      FROM private.reimport_case_batch WHERE id=v_batch_a;
    RAISE EXCEPTION 'EXPECTED_BATCH_MANIFEST_UNIQUE_INDEX_REJECTION';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Same manifest/preview/principal tuple but a DIFFERENT source must NOT collide
  -- (the unique index is scoped by source_id, exactly as the plan requires).
  INSERT INTO private.reimport_case_batch(
    authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
    principal_id,expected_counts
  )
  SELECT v_auth_b, v_source_b, phase, operation, manifest_sha256, preview_sha256, principal_id, expected_counts
  FROM private.reimport_case_batch WHERE id=v_batch_a;

  BEGIN
    INSERT INTO private.reimport_case_batch(
      authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
      principal_id,expected_counts
    ) VALUES (
      v_auth_a,v_source_a,'c2','apply',v_hash64,v_hash64,gen_random_uuid(),'{}'::jsonb
    );
    RAISE EXCEPTION 'EXPECTED_BATCH_PHASE_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_batch_phase_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_batch(
      authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
      principal_id,expected_counts
    ) VALUES (
      v_auth_a,v_source_a,'c3','not-an-operation',v_hash64,v_hash64,gen_random_uuid(),'{}'::jsonb
    );
    RAISE EXCEPTION 'EXPECTED_BATCH_OPERATION_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_batch_operation_check' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE private.reimport_case_batch SET status='not-a-status' WHERE id=v_batch_a;
    RAISE EXCEPTION 'EXPECTED_BATCH_STATUS_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_batch_status_check' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE private.reimport_case_batch SET observed_counts='[1]'::jsonb WHERE id=v_batch_a;
    RAISE EXCEPTION 'EXPECTED_BATCH_OBSERVED_COUNTS_NOT_OBJECT_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_batch_observed_counts_check' THEN RAISE; END IF;
  END;
  UPDATE private.reimport_case_batch
    SET observed_counts='{"identity_different":1}'::jsonb WHERE id=v_batch_a;

  BEGIN
    UPDATE private.reimport_case_batch SET change_set_id=-999999 WHERE id=v_batch_a;
    RAISE EXCEPTION 'EXPECTED_BATCH_CHANGE_SET_FK_REJECTION';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    UPDATE private.reimport_case_batch SET status='reversed' WHERE id=v_batch_a;
    RAISE EXCEPTION 'EXPECTED_BATCH_REVERSED_WITHOUT_REVERSAL_ID_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_batch_reversed_has_reversal' THEN RAISE; END IF;
  END;

  BEGIN
    UPDATE private.reimport_case_batch SET reversal_batch_id=gen_random_uuid() WHERE id=v_batch_a;
    RAISE EXCEPTION 'EXPECTED_BATCH_REVERSAL_ID_WITHOUT_REVERSED_STATUS_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_batch_reversed_has_reversal' THEN RAISE; END IF;
  END;

  -- A distinct reversal batch, referenced from the original -- both directions of
  -- fund B5's coupling proven together. Its own authorization (a batch's
  -- authorization_id is UNIQUE, so v_auth_b -- already spent on the cross-source
  -- batch above -- cannot be reused here).
  INSERT INTO private.reimport_case_authorization(
    source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
    decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,
    expected_counts,authorized_elements,principal_id,nonce,expires_at
  ) VALUES (
    v_source_b,'c3','reversal',v_hash64,v_hash64_b,v_hash64,v_hash64,v_hash64,v_hash64,
    current_database(),'x','{}'::jsonb,'{}'::jsonb,gen_random_uuid(),gen_random_uuid(),
    clock_timestamp()+interval '1 hour'
  ) RETURNING id INTO v_auth_reversal;
  INSERT INTO private.reimport_case_batch(
    authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,
    principal_id,status,expected_counts
  ) VALUES (
    v_auth_reversal,v_source_b,'c3','reversal',v_hash64,v_hash64_b,gen_random_uuid(),'finalized','{}'::jsonb
  ) RETURNING id INTO v_batch_reversal;
  UPDATE private.reimport_case_batch
    SET status='reversed', reversal_batch_id=v_batch_reversal WHERE id=v_batch_a;
  IF (SELECT reversal_batch_id FROM private.reimport_case_batch WHERE id=v_batch_a) <> v_batch_reversal THEN
    RAISE EXCEPTION 'C3_APPLY_BATCH_REVERSAL_LINK_WRITE_FAILED';
  END IF;

  ---------------------------------------------------------------------------
  -- reimport_case_event: composite FK to batch (drift guard), unique
  -- (batch_id,element_id), action/payload_schema_version/payload checks,
  -- append-only trigger.
  ---------------------------------------------------------------------------
  BEGIN
    -- batch_id valid, but source_id mismatched vs. that batch's own source_id.
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_a,'c3','e1','identity_different','c3-apply-v1','{}'::jsonb,v_hash64
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_BATCH_SOURCE_DRIFT_REJECTION';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  INSERT INTO private.reimport_case_event(
    batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
  ) VALUES (
    v_batch_reversal,v_source_b,'c3','e1','identity_different','c3-apply-v1','{}'::jsonb,v_hash64
  ) RETURNING id INTO v_event1;
  IF v_event1 IS NULL THEN RAISE EXCEPTION 'C3_APPLY_EVENT_IDENTITY_DEFAULT_MISSING'; END IF;

  BEGIN
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_b,'c3','e1','record_assign','c3-apply-v1','{}'::jsonb,v_hash64
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_BATCH_ELEMENT_UNIQUE_REJECTION';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Same element_id on a DIFFERENT batch is fine.
  INSERT INTO private.reimport_case_event(
    batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
  ) VALUES (
    v_batch_a,v_source_a,'c3','e1','record_no_publication','c3-apply-v1','{}'::jsonb,v_hash64
  );

  BEGIN
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_b,'c3','e2','not-an-action','c3-apply-v1','{}'::jsonb,v_hash64
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_ACTION_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_event_action_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_b,'c3','e2','identity_different','c2-apply-v0','{}'::jsonb,v_hash64
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_PAYLOAD_SCHEMA_VERSION_CHECK_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_event_payload_schema_version_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_b,'c3','e2','identity_different','c3-apply-v1','[1,2]'::jsonb,v_hash64
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_PAYLOAD_NOT_OBJECT_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_event_payload_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_b,'c3','e2','identity_different','c3-apply-v1','{}'::jsonb,'not-a-hash'
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_AFTER_SHA_SHAPE_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_event_after_sha256_check' THEN RAISE; END IF;
  END;

  BEGIN
    INSERT INTO private.reimport_case_event(
      batch_id,source_id,phase,element_id,action,payload_schema_version,payload,
      before_sha256,after_sha256
    ) VALUES (
      v_batch_reversal,v_source_b,'c3','e2','identity_different','c3-apply-v1','{}'::jsonb,
      'not-a-hash',v_hash64
    );
    RAISE EXCEPTION 'EXPECTED_EVENT_BEFORE_SHA_SHAPE_REJECTION';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
    IF v_constraint <> 'reimport_case_event_before_sha256_check' THEN RAISE; END IF;
  END;

  IF (SELECT created_at FROM private.reimport_case_event WHERE id=v_event1) IS NULL
     OR (SELECT created_at FROM private.reimport_case_authorization WHERE id=v_auth_a) IS NULL
     OR (SELECT created_at FROM private.reimport_case_batch WHERE id=v_batch_a) IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_TIMESTAMP_DEFAULT_MISSING';
  END IF;

  -- Append-only: neither UPDATE nor DELETE may touch an existing event row.
  BEGIN
    UPDATE private.reimport_case_event SET action='record_assign' WHERE id=v_event1;
    RAISE EXCEPTION 'EXPECTED_EVENT_APPEND_ONLY_UPDATE_REJECTION';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'REIMPORT_CASE_EVENT_APPEND_ONLY' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM private.reimport_case_event WHERE id=v_event1;
    RAISE EXCEPTION 'EXPECTED_EVENT_APPEND_ONLY_DELETE_REJECTION';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'REIMPORT_CASE_EVENT_APPEND_ONLY' THEN RAISE; END IF;
  END;
  IF NOT EXISTS (SELECT 1 FROM private.reimport_case_event WHERE id=v_event1 AND action='identity_different') THEN
    RAISE EXCEPTION 'C3_APPLY_EVENT_APPEND_ONLY_ROW_LOST';
  END IF;

  RAISE NOTICE 'OK: C3 apply ledger UUID PKs, hash/status/action vocabularies, drift-guard composite FKs, batch unique index scoping, reversal/change-set references, append-only events';

  ---------------------------------------------------------------------------
  -- Fund B4: narrative_record_publication (source_record_id) is exclusive
  -- across draft/published bindings, but withdrawn bindings do not count.
  ---------------------------------------------------------------------------
  v_person := (SELECT coalesce(max(id),0)+1 FROM public.person);
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
    VALUES (v_person,false,false,false,'C3 apply DDL test person');
  v_run := gen_random_uuid();
  INSERT INTO private.extraction_run(
    id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest
  ) VALUES (v_run,v_source_a,'c3-apply-ddl-test','1','test','test',v_hash64,'{}');
  v_record1 := gen_random_uuid();
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
    VALUES (v_record1,v_source_a,'c3-apply-ddl-record-1','person_entry',v_run);

  v_narrative1 := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat)
    VALUES (v_narrative1,'person',v_person,v_source_a,'C3 narrative 1',false);
  v_narrative2 := v_narrative1 + 1;
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,privat)
    VALUES (v_narrative2,'person',v_person,v_source_a,'C3 narrative 2',false);

  INSERT INTO private.narrative_record_publication(
    narrative_id,source_record_id,record_label,citation_label,status
  ) VALUES (v_narrative1,v_record1,'Linje I, nr. 1','s. 1','draft');

  BEGIN
    INSERT INTO private.narrative_record_publication(
      narrative_id,source_record_id,record_label,citation_label,status
    ) VALUES (v_narrative2,v_record1,'Linje I, nr. 2','s. 2','draft');
    RAISE EXCEPTION 'EXPECTED_RECORD_EXCLUSIVITY_SECOND_DRAFT_REJECTION';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  UPDATE private.narrative_record_publication SET status='withdrawn' WHERE narrative_id=v_narrative1;
  -- Withdrawn no longer counts: a fresh binding to the same record must now succeed.
  INSERT INTO private.narrative_record_publication(
    narrative_id,source_record_id,record_label,citation_label,status
  ) VALUES (v_narrative2,v_record1,'Linje I, nr. 2','s. 2','published');

  RAISE NOTICE 'OK: fund B4 narrative_record_publication_active_record_uidx (draft+published exclusive, withdrawn excluded)';

  RAISE EXCEPTION 'ROLLBACK_TEST_1939_V50_C3_APPLY';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TEST_1939_V50_C3_APPLY' THEN
    RAISE NOTICE 'OK: C3 apply Task 5 testdata rullet tilbage';
  ELSE
    RAISE;
  END IF;
END $test$;

ROLLBACK;
