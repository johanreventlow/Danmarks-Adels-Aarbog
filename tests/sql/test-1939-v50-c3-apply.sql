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

-- ============================================================================
-- Task 6: public.red_preview_reimport_cases / red_authorize_reimport_cases /
-- red_apply_reimport_cases + fund B4 step 4b (red_publicer_narrative_record's
-- source-record lock).
--
-- NOTE on the two-session parts of step 4b: psql runs one session, so the
-- blocking/serialisation proof for red_publicer_narrative_record is run from a
-- two-connection harness and documented in the Task 6 report. What IS proven
-- here is (a) that the lock statement exists and precedes the binding lookup in
-- the deployed function body, and (b) the end state for both commit orders --
-- exactly one active binding per source record, the second attempt rejected.
-- ============================================================================

BEGIN;

DO $t6_catalog$
DECLARE v_def text; v_lock int; v_select int;
BEGIN
  IF to_regprocedure('public.red_preview_reimport_cases(bigint,text,jsonb)') IS NULL
     OR to_regprocedure('public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)') IS NULL
     OR to_regprocedure('public.red_apply_reimport_cases(uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_RPCS_MISSING';
  END IF;
  IF to_regprocedure('private.reimport_case_source_record_state(bigint,text)') IS NULL
     OR to_regprocedure('private.reimport_case_narrative_state(bigint,bigint)') IS NULL
     OR to_regprocedure('private.reimport_case_binding_state(uuid,bigint)') IS NULL
     OR to_regprocedure('private.validate_reimport_case_selection(jsonb)') IS NULL
     OR to_regprocedure('private.validate_reimport_case_elements(jsonb,jsonb)') IS NULL
     OR to_regprocedure('private.validate_reimport_case_counts(jsonb)') IS NULL
     OR to_regprocedure('private.reimport_case_receipt(uuid)') IS NULL
     OR to_regprocedure('private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)') IS NULL THEN
    RAISE EXCEPTION 'C3_APPLY_PRIVATE_HELPERS_MISSING';
  END IF;

  -- Preview must be STABLE (read-only); the two writers must not be.
  IF (SELECT provolatile FROM pg_proc
       WHERE oid='public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_NOT_STABLE';
  END IF;
  IF (SELECT provolatile FROM pg_proc
       WHERE oid='public.red_apply_reimport_cases(uuid,text,text)'::regprocedure) <> 'v' THEN
    RAISE EXCEPTION 'C3_APPLY_APPLY_NOT_VOLATILE';
  END IF;

  -- All three are SECURITY DEFINER with a fixed, minimal search_path.
  IF EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid IN (
      'public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure,
      'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)'::regprocedure,
      'public.red_apply_reimport_cases(uuid,text,text)'::regprocedure)
      AND (NOT p.prosecdef
           OR NOT ('search_path=pg_catalog, public, private' = ANY(coalesce(p.proconfig,'{}'))))
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_RPC_HARDENING_MISSING';
  END IF;

  -- ACL: nothing to PUBLIC/anon anywhere; preview+apply to authenticated only;
  -- authorize to service_role only; every private helper revoked from every role.
  IF has_function_privilege('anon','public.red_preview_reimport_cases(bigint,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('service_role','public.red_preview_reimport_cases(bigint,text,jsonb)','EXECUTE')
     OR has_function_privilege('service_role','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_preview_reimport_cases(bigint,text,jsonb)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_apply_reimport_cases(uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'C3_APPLY_RPC_ACL_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(ARRAY[
      'private.reimport_case_source_record_state(bigint,text)',
      'private.reimport_case_narrative_state(bigint,bigint)',
      'private.reimport_case_binding_state(uuid,bigint)',
      'private.validate_reimport_case_selection(jsonb)',
      'private.validate_reimport_case_elements(jsonb,jsonb)',
      'private.validate_reimport_case_counts(jsonb)',
      'private.reimport_case_receipt(uuid)',
      'private.write_reimport_case_narrative(bigint,bigint,bigint,text,boolean,text)']) fn
    CROSS JOIN unnest(ARRAY['anon','authenticated','service_role']) role_name
    WHERE has_function_privilege(role_name,fn,'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_PRIVATE_HELPER_ACL_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    WHERE p.oid IN (
      'public.red_preview_reimport_cases(bigint,text,jsonb)'::regprocedure,
      'public.red_authorize_reimport_cases(bigint,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,uuid,timestamptz)'::regprocedure,
      'public.red_apply_reimport_cases(uuid,text,text)'::regprocedure,
      'private.reimport_case_receipt(uuid)'::regprocedure)
      AND acl.grantee=0
  ) THEN
    RAISE EXCEPTION 'C3_APPLY_RPC_PUBLIC_GRANT_PRESENT';
  END IF;

  -- Step 4b: red_publicer_narrative_record must lock private.source_record
  -- BEFORE it reads the binding row. Order-checked, not merely presence-checked.
  v_def := pg_get_functiondef('public.red_publicer_narrative_record(bigint,uuid,text,text)'::regprocedure);
  v_lock := strpos(v_def,'FROM private.source_record WHERE id = p_source_record_id FOR UPDATE');
  v_select := strpos(v_def,'FROM private.narrative_record_publication');
  IF v_lock = 0 THEN RAISE EXCEPTION 'C3_APPLY_PUBLICATION_SOURCE_RECORD_LOCK_MISSING'; END IF;
  IF v_select = 0 OR v_lock > v_select THEN
    RAISE EXCEPTION 'C3_APPLY_PUBLICATION_LOCK_ORDER_WRONG';
  END IF;

  RAISE NOTICE 'OK: Task 6 catalog contract (RPC signatures, volatility, hardening, ACLs, step 4b lock order)';
END $t6_catalog$;

ROLLBACK;

-- ============================================================================
-- Task 6 behavioural proof. Builds a self-contained five-case fixture (5
-- identity pairs, 5 assign records, 1 no_publication record = 11 elements) and
-- drives preview -> authorize -> apply through it, then every drift gate.
-- Everything is rolled back at the end; no row survives this file.
-- ============================================================================

BEGIN;

DO $t6$
DECLARE
  v_actor uuid := '00000000-0000-4c33-8000-000000000001';
  v_member uuid := '00000000-0000-4c33-8000-000000000002';
  v_source bigint; v_source_other bigint; v_run uuid; v_run_other uuid; v_rend uuid; v_rend_other uuid;
  v_person bigint[] := '{}'; v_records uuid[] := '{}'; v_narr bigint[] := '{}';
  v_other_record uuid;
  i int; v_pid bigint; v_nid bigint; v_rid uuid; v_occ uuid; v_page int;
  v_sel jsonb; v_cases jsonb := '[]'::jsonb; v_recs jsonb;
  v_elems jsonb := '{}'::jsonb; v_counts jsonb; v_preview jsonb;
  v_auth uuid; v_auth2 uuid; v_receipt jsonb; v_receipt2 jsonb;
  v_case_id text; v_pa bigint; v_pb bigint; v_side text; v_text text;
  v_state jsonb; v_nstate jsonb; v_batch uuid; v_change_set bigint;
  v_nonce uuid; v_n bigint; v_sqlstate text;
  v_rel_before bigint; v_narr_before bigint; v_bind_before bigint;
  v_ce_before bigint; v_ev_before bigint; v_batch_before bigint;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM set_config('request.jwt.claim.sub', v_actor::text, true);

  ---------------------------------------------------------------------------
  -- Fixture
  ---------------------------------------------------------------------------
  INSERT INTO auth.users(id,email) VALUES (v_actor,'c3-task6@test.local')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO auth.users(id,email) VALUES (v_member,'c3-task6-member@test.local')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','c3-task6@test.local')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  INSERT INTO profiles(id,rolle,email) VALUES (v_member,'medlem','c3-task6-member@test.local')
    ON CONFLICT (id) DO UPDATE SET rolle='medlem';
  IF public.current_rolle() <> 'redaktion' OR auth.uid() <> v_actor THEN
    RAISE EXCEPTION 'C3_APPLY_FIXTURE_ACTOR_INVALID';
  END IF;

  v_source := (SELECT coalesce(max(id),0)+1 FROM public.source);
  INSERT INTO public.source(id,slags,titel,udgave,aar)
    VALUES (v_source,'DAA-udgave','DAA 1939 (Task 6 fixture)','1939',1939);
  v_source_other := v_source + 1;
  INSERT INTO public.source(id,slags,titel,udgave,aar)
    VALUES (v_source_other,'DAA-udgave','DAA 2018 (Task 6 fixture)','2018',2018);

  v_run := gen_random_uuid();
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,v_source,'c3-task6','1','t','t',repeat('a',64),'{}');
  v_rend := gen_random_uuid();
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256)
    VALUES (v_rend,v_source,'c3-task6-rend','ocr_text',repeat('b',64));
  v_run_other := gen_random_uuid();
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run_other,v_source_other,'c3-task6-other','1','t','t',repeat('a',64),'{}');
  v_rend_other := gen_random_uuid();
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256)
    VALUES (v_rend_other,v_source_other,'c3-task6-rend-other','ocr_text',repeat('b',64));

  FOR i IN 1..10 LOOP
    v_pid := (SELECT coalesce(max(id),0)+1 FROM public.person);
    INSERT INTO public.person(id,levende,privat,staged,visning_navn)
      VALUES (v_pid,false,false,false,'Task 6 testperson '||i);
    v_person := v_person || v_pid;
  END LOOP;

  FOR i IN 1..6 LOOP
    v_page := 500+i; v_rid := gen_random_uuid();
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES (v_rid,v_source,'t6-record-'||i,'person_entry',v_run);
    v_occ := gen_random_uuid();
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES (v_occ,v_rend,'t6-occ-'||i,v_page,v_page,i*100,i*100+50,
              'RAA OCR '||i,'pf-'||i,'sf-'||i,v_run);
    INSERT INTO private.source_record_anchor_event(
      occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
      VALUES (v_occ,v_rid,'accepted','{"k":"v"}'::jsonb,1,v_actor,'tester');
    v_records := v_records || v_rid;
  END LOOP;

  -- Negative test (fund B3): the SAME record_key in a DIFFERENT source. record_key
  -- is only unique together with source_id, so the source must be a parameter --
  -- this row must never be reachable from a source_id=v_source authorization.
  v_other_record := gen_random_uuid();
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
    VALUES (v_other_record,v_source_other,'t6-record-1','person_entry',v_run_other);
  v_occ := gen_random_uuid();
  INSERT INTO private.source_record_occurrence(
    id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES (v_occ,v_rend_other,'t6-occ-other',900,900,1,50,
            'ANDEN UDGAVE','pf-o','sf-o',v_run_other);
  INSERT INTO private.source_record_anchor_event(
    occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_other_record,'accepted','{"k":"v"}'::jsonb,1,v_actor,'tester');

  FOR i IN 1..5 LOOP
    v_nid := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
    INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
      VALUES (v_nid,'person',v_person[2*i-1],v_source,'GAMMEL TEKST '||i,(500+i)::text,false);
    v_narr := v_narr || v_nid;
  END LOOP;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  ---------------------------------------------------------------------------
  -- Build the selection and the authorized element map (11 stable element IDs)
  ---------------------------------------------------------------------------
  FOR i IN 1..5 LOOP
    v_case_id := 'T6CASE'||i;
    v_pa := v_person[2*i-1]; v_pb := v_person[2*i];
    v_side := (500+i)::text;
    v_text := 'NY NORMALISERET TEKST '||i;
    v_state := private.reimport_case_source_record_state(v_source,'t6-record-'||i);
    v_nstate := private.reimport_case_narrative_state(v_source,v_pa);
    v_recs := jsonb_build_array(jsonb_build_object(
      'rid','T6R0'||i,'record_key','t6-record-'||i,'action','assign',
      'target_person_id',v_pa,'raw_sha256',v_state->>'verbatim_sha256',
      'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex')));
    v_elems := v_elems || jsonb_build_object('case:'||v_case_id, jsonb_build_object(
      'case_id',v_case_id,'action','different',
      'person_ids',jsonb_build_array(v_pa,v_pb),
      'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',false)));
    v_elems := v_elems || jsonb_build_object('case:'||v_case_id||':rid:T6R0'||i, jsonb_build_object(
      'case_id',v_case_id,'rid','T6R0'||i,'record_key','t6-record-'||i,'action','assign',
      'target_person_id',v_pa,'target_narrative_id',v_nstate->'narrative_id',
      'normalized_text',v_text,
      'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex'),
      'record_label','t6-record-'||i,'citation_label','DAA 1939 side '||v_side,
      'side',v_side,'privat',false,
      'before_state',jsonb_build_object(
        'source_record',jsonb_build_object('match_count',1,
          'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
        'target_narrative',jsonb_build_object('person_id',v_pa,
          'narrative_id',v_nstate->'narrative_id','privat',false,
          'old_sha256',v_nstate->'old_sha256'),
        'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));
    IF i = 5 THEN
      v_state := private.reimport_case_source_record_state(v_source,'t6-record-6');
      v_recs := v_recs || jsonb_build_array(jsonb_build_object(
        'rid','T6R06','record_key','t6-record-6','action','no_publication'));
      v_elems := v_elems || jsonb_build_object('case:'||v_case_id||':rid:T6R06', jsonb_build_object(
        'case_id',v_case_id,'rid','T6R06','record_key','t6-record-6','action','no_publication',
        'before_state',jsonb_build_object(
          'source_record',jsonb_build_object('match_count',1,
            'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
          'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));
    END IF;
    v_cases := v_cases || jsonb_build_array(jsonb_build_object(
      'case_id',v_case_id,
      'identity_pair',jsonb_build_object('person_ids',jsonb_build_array(v_pa,v_pb)),
      'records',v_recs));
  END LOOP;
  v_sel := jsonb_build_object('schema_version','1939-v50-c3-apply-selection-v1','cases',v_cases);
  v_counts := jsonb_build_object('cases',5,'identity_events',5,'assign_events',5,
    'no_publication_events',1,'events',11,'approvals_approved',5,'approvals_unresolved',0);
  IF (SELECT count(*) FROM jsonb_object_keys(v_elems)) <> 11 THEN
    RAISE EXCEPTION 'C3_APPLY_FIXTURE_ELEMENT_COUNT_INVALID';
  END IF;

  ---------------------------------------------------------------------------
  -- Preview: the exact contract the shipped R exporter validates byte for byte
  ---------------------------------------------------------------------------
  v_preview := public.red_preview_reimport_cases(v_source,'c3',v_sel);
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_preview) k)
     <> ARRAY['bindings','database_name','identity_components','identity_pairs',
              'source_anchors','source_records','system_identifier','target_narratives'] THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_KEYS_DRIFT';
  END IF;
  IF v_preview->>'database_name' <> current_database()
     OR v_preview->>'system_identifier' <> (pg_control_system()).system_identifier::text
     OR jsonb_array_length(v_preview->'identity_pairs') <> 5
     OR jsonb_array_length(v_preview->'source_records') <> 6
     OR jsonb_array_length(v_preview->'target_narratives') <> 5
     OR jsonb_array_length(v_preview->'bindings') <> 6 THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_SHAPE_DRIFT';
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_preview->'identity_pairs'->0) k)
       <> ARRAY['case_id','component_overlap','existing_rejection','person_ids']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_preview->'source_records'->0) k)
       <> ARRAY['match_count','record_key','rid','side','verbatim_sha256']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_preview->'target_narratives'->0) k)
       <> ARRAY['narrative_id','old_sha256','person_id','privat','rid']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_preview->'bindings'->0) k)
       <> ARRAY['binding_person_id','record_key','status'] THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_ROW_KEYS_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_preview->'bindings') b
              WHERE b->>'status' <> 'absent')
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_preview->'source_records') s
                 WHERE (s->>'match_count')::int <> 1
                    OR s->>'verbatim_sha256' !~ '^[0-9a-f]{64}$'
                    OR btrim(coalesce(s->>'side','')) = '')
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_preview->'identity_pairs') p
                 WHERE (p->>'component_overlap')::boolean OR (p->>'existing_rejection')::boolean) THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_VALUES_DRIFT';
  END IF;
  -- Fund H2 live-guard fields are measured and hash-bound through the preview.
  IF NOT (v_preview->'identity_components'->0->'persons'->0 ? 'staged')
     OR NOT (v_preview->'identity_components'->0->'persons'->0 ? 'levende')
     OR NOT (v_preview->'identity_components'->0->'persons'->0 ? 'privat') THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_LIVE_GUARD_FIELDS_MISSING';
  END IF;
  -- Preview is deterministic: identical input, byte-identical answer (the R
  -- wrapper hashes these exact bytes into the manifest).
  IF v_preview::text <> public.red_preview_reimport_cases(v_source,'c3',v_sel)::text THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_NOT_DETERMINISTIC';
  END IF;
  -- Fund B3 negative: the same record_key exists in another source; a preview
  -- scoped to the other source must not silently answer for this one.
  BEGIN
    PERFORM public.red_preview_reimport_cases(v_source_other,'c3',v_sel);
    RAISE EXCEPTION 'EXPECTED_CROSS_SOURCE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT IN ('REIMPORT_CASE_SOURCE_RECORD_MISSING','REIMPORT_CASE_PERSON_MISSING') THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.red_preview_reimport_cases(v_source,'c2',v_sel);
    RAISE EXCEPTION 'EXPECTED_PHASE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_PHASE_UNSUPPORTED' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: red_preview_reimport_cases contract, determinism, phase/source scoping';

  ---------------------------------------------------------------------------
  -- Fund H5: the role boundary must be executable, not merely declared.
  -- current_user changes with SET LOCAL ROLE; auth.uid()/current_rolle() do not.
  ---------------------------------------------------------------------------
  -- Profile assertion is taken here, as the owner, and re-taken after each role
  -- switch through public.current_rolle() -- which IS the profiles lookup, done
  -- through a SECURITY DEFINER function rather than a raw, RLS-dependent read.
  IF current_user = 'service_role' OR current_user = 'authenticated'
     OR (SELECT rolle FROM profiles WHERE id = v_actor) <> 'redaktion' THEN
    RAISE EXCEPTION 'C3_APPLY_ROLE_CONTEXT_INVALID';
  END IF;
  -- Role gate, proven negatively first: a 'medlem' JWT subject is refused by
  -- every entry point, regardless of which PostgreSQL role calls it.
  PERFORM set_config('request.jwt.claim.sub', v_member::text, true);
  BEGIN
    PERFORM public.red_preview_reimport_cases(v_source,'c3',v_sel);
    RAISE EXCEPTION 'EXPECTED_MEMBER_PREVIEW_DENIED';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_1939_ROLE_FORBIDDEN' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM public.red_preview_reimport_cases(v_source,'c3',v_sel);
    RAISE EXCEPTION 'EXPECTED_ANON_PREVIEW_DENIED';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_1939_ROLE_FORBIDDEN' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub', v_actor::text, true);

  -- public.current_rolle() is granted to authenticated only (db-rls.sql), so
  -- under service_role the profile/role gate is proven by the authorize call
  -- itself: it runs private.require_reimport_1939_editor() as owner and refuses
  -- any JWT subject whose profiles.rolle is not 'redaktion' (proven above).
  EXECUTE 'SET LOCAL ROLE service_role';
  IF current_user <> 'service_role' OR auth.uid() <> v_actor THEN
    RAISE EXCEPTION 'C3_APPLY_ROLE_CONTEXT_INVALID';
  END IF;
  v_nonce := gen_random_uuid();
  v_auth := public.red_authorize_reimport_cases(
    v_source,'c3','apply',repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),
    repeat('5',64),repeat('6',64),current_database(),
    (pg_control_system()).system_identifier::text, v_counts, v_elems,
    v_nonce, clock_timestamp()+interval '1 hour');
  -- service_role may NOT apply.
  BEGIN
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_SERVICE_ROLE_APPLY_DENIED';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';

  EXECUTE 'SET LOCAL ROLE authenticated';
  IF current_user <> 'authenticated' OR auth.uid() <> v_actor
     OR public.current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'C3_APPLY_ROLE_CONTEXT_INVALID';
  END IF;
  -- authenticated may NOT authorize.
  BEGIN
    PERFORM public.red_authorize_reimport_cases(
      v_source,'c3','apply',repeat('7',64),repeat('2',64),repeat('3',64),repeat('4',64),
      repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text, v_counts, v_elems,
      gen_random_uuid(), clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_AUTHENTICATED_AUTHORIZE_DENIED';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE 'OK: fund H5 executable role boundary (service_role authorises, authenticated applies)';

  ---------------------------------------------------------------------------
  -- Authorization drift gates (every gate from Task 3, plus fund B1/B3/B6)
  ---------------------------------------------------------------------------
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN  -- wrong database name (fund B1)
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),'not-this-database',
      (pg_control_system()).system_identifier::text,v_counts,v_elems,gen_random_uuid(),
      clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_DATABASE_NAME_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_DATABASE_IDENTITY_MISMATCH' THEN RAISE; END IF;
  END;
  BEGIN  -- wrong system identifier (fund B1, second field, separately compared)
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      '999999999999999999',v_counts,v_elems,gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_SYSTEM_IDENTIFIER_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_DATABASE_IDENTITY_MISMATCH' THEN RAISE; END IF;
  END;
  BEGIN  -- expired nonce
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,v_counts,v_elems,gen_random_uuid(),
      clock_timestamp()-interval '1 second');
    RAISE EXCEPTION 'EXPECTED_EXPIRY_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  BEGIN  -- malformed hash
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply','not-a-hash',repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,v_counts,v_elems,gen_random_uuid(),
      clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_HASH_SHAPE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  BEGIN  -- an unresolved approval may never be authorised
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,
      jsonb_set(v_counts,'{approvals_unresolved}','1'::jsonb),v_elems,gen_random_uuid(),
      clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_UNRESOLVED_APPROVAL_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_COUNTS_INVALID' THEN RAISE; END IF;
  END;
  BEGIN  -- counts must match the element map
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,
      jsonb_build_object('cases',4,'identity_events',4,'assign_events',5,
        'no_publication_events',1,'events',10,'approvals_approved',5,'approvals_unresolved',0),
      v_elems,gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_COUNTS_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_COUNTS_MISMATCH' THEN RAISE; END IF;
  END;
  BEGIN  -- element id must be exactly "case:<case_id>[:rid:<rid>]"
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,v_counts,
      (v_elems - 'case:T6CASE1') || jsonb_build_object('case-T6CASE1', v_elems->'case:T6CASE1'),
      gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_ELEMENT_ID_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_ELEMENTS_INVALID' THEN RAISE; END IF;
  END;
  BEGIN  -- normalized text and its hash must agree (text integrity, checkable in-DB)
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,v_counts,
      jsonb_set(v_elems,'{case:T6CASE1:rid:T6R01,normalized_text}','"MANIPULERET"'::jsonb),
      gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_TEXT_HASH_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_ELEMENTS_INVALID' THEN RAISE; END IF;
  END;
  BEGIN  -- a record decision without its case's identity decision is a half case
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('1',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,
      jsonb_build_object('cases',4,'identity_events',4,'assign_events',5,
        'no_publication_events',1,'events',10,'approvals_approved',5,'approvals_unresolved',0),
      v_elems - 'case:T6CASE1',gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_HALF_CASE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_ELEMENTS_INVALID' THEN RAISE; END IF;
  END;
  BEGIN  -- same nonce, different payload
    PERFORM public.red_authorize_reimport_cases(v_source,'c3','apply',repeat('9',64),repeat('2',64),
      repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),current_database(),
      (pg_control_system()).system_identifier::text,v_counts,v_elems,v_nonce,
      clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_NONCE_CONFLICT';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_NONCE_CONFLICT' THEN RAISE; END IF;
  END;
  -- same nonce, exactly the same payload -> same authorization id (commit-unknown)
  v_auth2 := public.red_authorize_reimport_cases(
    v_source,'c3','apply',repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),
    repeat('5',64),repeat('6',64),current_database(),
    (pg_control_system()).system_identifier::text,v_counts,v_elems,v_nonce,
    clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';
  IF v_auth2 <> v_auth THEN RAISE EXCEPTION 'C3_APPLY_NONCE_REPLAY_DRIFT'; END IF;
  IF (SELECT count(*) FROM private.reimport_case_authorization WHERE nonce=v_nonce) <> 1 THEN
    RAISE EXCEPTION 'C3_APPLY_NONCE_REPLAY_DUPLICATED';
  END IF;
  RAISE NOTICE 'OK: red_authorize_reimport_cases drift gates (identity, hashes, counts, elements, nonce)';

  ---------------------------------------------------------------------------
  -- Step 2: all-or-nothing. Force a failure in case 3 (its binding is taken by
  -- a competing published binding after the authorization was issued) and prove
  -- that NOTHING partial survives: no identity relation, no narrative change,
  -- no publication row, no change event, no C3 event, no batch row.
  ---------------------------------------------------------------------------
  SELECT count(*) INTO v_rel_before FROM public.relation WHERE rolle='ikke_samme_som';
  SELECT count(*) INTO v_bind_before FROM private.narrative_record_publication;
  SELECT count(*) INTO v_ce_before FROM public.change_event;
  SELECT count(*) INTO v_ev_before FROM private.reimport_case_event;
  SELECT count(*) INTO v_batch_before FROM private.reimport_case_batch;
  SELECT count(*) INTO v_narr_before FROM public.narrative WHERE tekst LIKE 'GAMMEL TEKST %';

  BEGIN
    -- Competing binding on case 3's source record, invisible to the manifest.
    INSERT INTO private.narrative_record_publication(
      narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_narr[4],v_records[3],'kaprer','kaprer','published');
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_CASE3_BINDING_DRIFT';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_BINDING_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM public.relation WHERE rolle='ikke_samme_som') <> v_rel_before
     OR (SELECT count(*) FROM private.narrative_record_publication) <> v_bind_before
     OR (SELECT count(*) FROM public.change_event) <> v_ce_before
     OR (SELECT count(*) FROM private.reimport_case_event) <> v_ev_before
     OR (SELECT count(*) FROM private.reimport_case_batch) <> v_batch_before
     OR (SELECT count(*) FROM public.narrative WHERE tekst LIKE 'GAMMEL TEKST %') <> v_narr_before
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_auth) <> 'issued' THEN
    RAISE EXCEPTION 'C3_APPLY_PARTIAL_STATE_AFTER_FAILURE';
  END IF;
  RAISE NOTICE 'OK: forced failure in case 3 leaves zero partial state (all-or-nothing)';

  ---------------------------------------------------------------------------
  -- Fund H2 live guard: one drift mutation per field, each proved in isolation.
  ---------------------------------------------------------------------------
  FOR i IN 1..4 LOOP
    BEGIN
      IF i=1 THEN UPDATE public.person SET levende=true WHERE id=v_person[1];
      ELSIF i=2 THEN UPDATE public.person SET privat=true WHERE id=v_person[1];
      ELSIF i=3 THEN UPDATE public.person SET staged=true WHERE id=v_person[1];
      ELSE UPDATE public.narrative SET privat=true WHERE id=v_narr[1];
      END IF;
      PERFORM set_config('app.change_set_id','',true);
      EXECUTE 'SET LOCAL ROLE authenticated';
      PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
      RAISE EXCEPTION 'EXPECTED_LIVE_GUARD_REJECTION';
    EXCEPTION WHEN others THEN
      IF i<4 AND SQLERRM <> 'REIMPORT_CASE_PERSON_NOT_PUBLISHABLE' THEN RAISE; END IF;
      IF i=4 AND SQLERRM <> 'REIMPORT_CASE_NARRATIVE_DRIFT' THEN RAISE; END IF;
    END;
    EXECUTE 'RESET ROLE';
    IF (SELECT count(*) FROM private.reimport_case_batch) <> v_batch_before THEN
      RAISE EXCEPTION 'C3_APPLY_PARTIAL_STATE_AFTER_LIVE_GUARD';
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: fund H2 live guard rejects levende/privat/staged/narrative.privat drift';

  ---------------------------------------------------------------------------
  -- Fund H3 (haendelse must be empty) and the no_publication active-binding gate
  ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.haendelse(id,subjekt_type,subjekt_id,narrative_id,noegle,klausul)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM public.haendelse),'person',v_person[1],
              v_narr[1],'t6','klausul');
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_HAENDELSE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_HAENDELSE_PRESENT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  BEGIN
    INSERT INTO private.narrative_record_publication(
      narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_narr[5],v_records[6],'nopub-kaprer','nopub-kaprer','published');
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_NO_PUBLICATION_BINDING_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_BINDING_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  -- Fund M2: a duplicate logical narrative row makes the exact-ID write ambiguous.
  BEGIN
    INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM public.narrative),'person',v_person[1],
              v_source,'DUBLET',(500)::text,false);
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_NARRATIVE_AMBIGUITY_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_NARRATIVE_AMBIGUOUS' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  -- Source-record drift. The evidence tables are append-only, so drift arrives
  -- the way it would in production: a second accepted occurrence is anchored to
  -- the same record, and the measured text is no longer unambiguous.
  BEGIN
    v_occ := gen_random_uuid();
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES (v_occ,v_rend,'t6-occ-drift',502,502,9000,9050,
              'DRIFTET OCR','pf-d','sf-d',v_run);
    INSERT INTO private.source_record_anchor_event(
      occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
      VALUES (v_occ,v_records[2],'accepted','{"k":"v"}'::jsonb,1,v_actor,'tester');
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_SOURCE_RECORD_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_SOURCE_RECORD_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  -- Identity drift: a competing samme_som component overlap.
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
      VALUES ('person',v_person[1],'person',v_person[2],'samme_som');
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_IDENTITY_COMPONENT_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_IDENTITY_COMPONENT_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM private.reimport_case_batch) <> v_batch_before
     OR (SELECT count(*) FROM private.reimport_case_event) <> v_ev_before THEN
    RAISE EXCEPTION 'C3_APPLY_PARTIAL_STATE_AFTER_DRIFT_GATE';
  END IF;
  RAISE NOTICE 'OK: haendelse, no_publication binding, narrative ambiguity, text drift and identity drift gates';

  ---------------------------------------------------------------------------
  -- Happy path: one call, one transaction, one batch, one change set,
  -- 11 events, exact after-state.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt := public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
  EXECUTE 'RESET ROLE';

  IF v_receipt->>'schema_version' <> 'c3-apply-receipt-v1'
     OR v_receipt->>'status' <> 'finalized'
     OR v_receipt->>'phase' <> 'c3' OR v_receipt->>'operation' <> 'apply'
     OR (v_receipt->>'source_id')::bigint <> v_source
     OR jsonb_array_length(v_receipt->'elements') <> 11
     OR (v_receipt->'observed_counts'->>'events')::int <> 11
     OR (v_receipt->'observed_counts'->>'identity_events')::int <> 5
     OR (v_receipt->'observed_counts'->>'assign_events')::int <> 5
     OR (v_receipt->'observed_counts'->>'no_publication_events')::int <> 1 THEN
    RAISE EXCEPTION 'C3_APPLY_RECEIPT_DRIFT';
  END IF;
  -- The receipt carries only IDs, counts, hashes and status -- never prose.
  IF v_receipt::text LIKE '%NY NORMALISERET TEKST%'
     OR v_receipt::text LIKE '%GAMMEL TEKST%'
     OR v_receipt::text LIKE '%RAA OCR%' THEN
    RAISE EXCEPTION 'C3_APPLY_RECEIPT_LEAKS_PROSE';
  END IF;
  v_batch := (v_receipt->>'batch_id')::uuid;
  v_change_set := (v_receipt->>'change_set_id')::bigint;

  IF (SELECT count(*) FROM private.reimport_case_batch WHERE source_id=v_source) <> 1
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_batch) <> 11
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_auth) <> 'consumed'
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_batch AND payload_schema_version <> 'c3-apply-v1') <> 0
     OR (SELECT count(DISTINCT action) FROM private.reimport_case_event WHERE batch_id=v_batch) <> 3 THEN
    RAISE EXCEPTION 'C3_APPLY_LEDGER_DRIFT';
  END IF;
  -- One change set for the whole batch.
  IF (SELECT count(DISTINCT change_set_id) FROM public.change_event
       WHERE change_set_id=v_change_set) <> 1
     OR (SELECT operation FROM public.change_set WHERE id=v_change_set)
        <> 'red_apply_reimport_cases' THEN
    RAISE EXCEPTION 'C3_APPLY_CHANGE_SET_DRIFT';
  END IF;
  -- Fund M2 (c): only the batch's own narratives appear in the change set.
  IF EXISTS (SELECT 1 FROM public.change_event ce
              WHERE ce.change_set_id=v_change_set AND ce.tabel='narrative'
                AND NOT ((ce.row_pk->>'id')::bigint = ANY(v_narr))) THEN
    RAISE EXCEPTION 'C3_APPLY_CHANGE_SCOPE_DRIFT';
  END IF;
  -- Exact after-state: 5 rewritten narratives, 5 published bindings on exactly
  -- the five assign records, 5 identity rejections with evidence, record 6 clean.
  IF (SELECT count(*) FROM public.narrative n
       WHERE n.id = ANY(v_narr) AND n.tekst LIKE 'NY NORMALISERET TEKST %'
         AND coalesce(n.privat,false)=false) <> 5 THEN
    RAISE EXCEPTION 'C3_APPLY_NARRATIVE_AFTER_STATE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM private.narrative_record_publication b
       WHERE b.status='published' AND b.narrative_id = ANY(v_narr)
         AND b.source_record_id = ANY(v_records[1:5])) <> 5
     OR EXISTS (SELECT 1 FROM private.narrative_record_publication b
                 WHERE b.source_record_id = v_records[6]) THEN
    RAISE EXCEPTION 'C3_APPLY_BINDING_AFTER_STATE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.relation r
       JOIN public.conclusion c ON c.target_type='relation' AND c.target_id=r.id
       JOIN public.assertion a ON a.id=c.valgt_assertion_id
       WHERE r.rolle='ikke_samme_som' AND r.subjekt_id = ANY(v_person)) <> 5 THEN
    RAISE EXCEPTION 'C3_APPLY_IDENTITY_AFTER_STATE_DRIFT';
  END IF;
  -- The five identity events are marked 'created' (none reused in this fixture).
  IF (SELECT count(*) FROM private.reimport_case_event
       WHERE batch_id=v_batch AND action='identity_different'
         AND payload->'result'->>'outcome'='created') <> 5 THEN
    RAISE EXCEPTION 'C3_APPLY_IDENTITY_OUTCOME_DRIFT';
  END IF;
  -- The no_publication event records proven absence and mutates nothing.
  IF (SELECT count(*) FROM private.reimport_case_event
       WHERE batch_id=v_batch AND action='record_no_publication'
         AND payload->'result'->>'binding_status'='absent') <> 1 THEN
    RAISE EXCEPTION 'C3_APPLY_NO_PUBLICATION_EVENT_DRIFT';
  END IF;
  -- Public projection actually shows the five records (a receipt that says
  -- "published" while the projection is empty is exactly fund H2's false receipt).
  IF (SELECT count(*) FROM public.public_person_bio_source_versions(v_person)
       WHERE provenance_kind='source_record') < 5 THEN
    RAISE EXCEPTION 'C3_APPLY_PUBLIC_PROJECTION_EMPTY';
  END IF;
  RAISE NOTICE 'OK: red_apply_reimport_cases -- one batch, one change set, 11 events, exact after-state';

  ---------------------------------------------------------------------------
  -- Idempotency and commit-unknown
  ---------------------------------------------------------------------------
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt2 := public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
  EXECUTE 'RESET ROLE';
  IF v_receipt2 <> v_receipt THEN RAISE EXCEPTION 'C3_APPLY_REPLAY_RECEIPT_DRIFT'; END IF;
  IF (SELECT count(*) FROM private.reimport_case_batch WHERE source_id=v_source) <> 1
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_batch) <> 11 THEN
    RAISE EXCEPTION 'C3_APPLY_REPLAY_DUPLICATED';
  END IF;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('9',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_REPLAY_MANIFEST_DRIFT';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('9',64));
    RAISE EXCEPTION 'EXPECTED_REPLAY_APPROVAL_DRIFT';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE 'OK: same nonce/same payload replays the receipt; different payload is rejected';

  ---------------------------------------------------------------------------
  -- Step 4b end state: exactly one active binding per source record, in both
  -- commit orders. The published binding is already there, so the competing
  -- publication of a different narrative must be rejected (Decision 2: the raw
  -- unique_violation on narrative_record_publication_active_record_uidx IS the
  -- accepted failure mode -- no domain-token wrapper).
  ---------------------------------------------------------------------------
  -- A narrative with no binding of its own (so red_publicer_narrative_record
  -- takes its INSERT branch) aimed at a source record that is already actively
  -- bound to a different narrative.
  v_nid := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
    VALUES (v_nid,'person',v_person[2],v_source,'KAPRER-NARRATIV','999',false);
  PERFORM set_config('app.change_set_id','',true);
  BEGIN
    PERFORM public.red_publicer_narrative_record(
      v_nid,v_records[1],'kaprer','kaprer');
    RAISE EXCEPTION 'EXPECTED_RECORD_EXCLUSIVITY_REJECTION';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF (SELECT count(*) FROM private.narrative_record_publication
       WHERE source_record_id=v_records[1] AND status IN ('draft','published')) <> 1 THEN
    RAISE EXCEPTION 'C3_APPLY_RECORD_EXCLUSIVITY_END_STATE_DRIFT';
  END IF;
  RAISE NOTICE 'OK: step 4b end state -- one active binding per source record in both commit orders';

  RAISE EXCEPTION 'ROLLBACK_TEST_1939_V50_C3_APPLY_TASK6';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TEST_1939_V50_C3_APPLY_TASK6' THEN
    RAISE NOTICE 'OK: C3 apply Task 6 testdata rullet tilbage';
  ELSE
    RAISE;
  END IF;
END $t6$;

ROLLBACK;
