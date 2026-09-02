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
  -- Task 7: this test is also run after the current migration of a pre-#153
  -- schema.  C3 remains entitled to these private helper aliases; neither is
  -- a client surface, so both must exist and stay revoked from every client
  -- role after the generic writer transition.
  IF to_regprocedure('private.require_reimport_1939_editor()') IS NULL
     OR to_regprocedure('private.reimport_1939_canonical_json_sha256(jsonb)') IS NULL
     OR has_function_privilege('anon','private.require_reimport_1939_editor()','EXECUTE')
     OR has_function_privilege('authenticated','private.require_reimport_1939_editor()','EXECUTE')
     OR has_function_privilege('service_role','private.require_reimport_1939_editor()','EXECUTE')
     OR has_function_privilege('anon','private.reimport_1939_canonical_json_sha256(jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.reimport_1939_canonical_json_sha256(jsonb)','EXECUTE')
     OR has_function_privilege('service_role','private.reimport_1939_canonical_json_sha256(jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'C3_APPLY_PRIVATE_HELPER_TRANSITION_DRIFT';
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
        v_apply_def text; v_lock_timeout int; v_stmt_timeout int;
        v_writer_lock int; v_guard int; v_begin_cs int;
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

  -- Fund I1: both timeouts must be set BEFORE the step-1 advisory lock.
  -- lock_timeout is re-read at every lock acquisition, so its position decides
  -- whether the longest wait in the call -- step 1 itself -- is bounded at all.
  -- (statement_timeout can never bound this call whatever its position, because
  -- PostgreSQL binds it at statement start and the function body IS the
  -- statement; it is still asserted here so the pair cannot drift apart.)
  v_apply_def := pg_get_functiondef('public.red_apply_reimport_cases(uuid,text,text)'::regprocedure);
  v_lock_timeout := strpos(v_apply_def,'set_config(''lock_timeout''');
  v_stmt_timeout := strpos(v_apply_def,'set_config(''statement_timeout''');
  v_writer_lock  := strpos(v_apply_def,'hashtextextended(''daa-1939-v50-production-writer'',0)');
  IF v_lock_timeout = 0 OR v_stmt_timeout = 0 OR v_writer_lock = 0 THEN
    RAISE EXCEPTION 'C3_APPLY_TIMEOUT_OR_WRITER_LOCK_MISSING';
  END IF;
  IF v_lock_timeout > v_writer_lock OR v_stmt_timeout > v_writer_lock THEN
    RAISE EXCEPTION 'C3_APPLY_TIMEOUTS_SET_TOO_LATE';
  END IF;

  -- Fund C2: the foreign-change-set guard must exist and must run before
  -- begin_change_set, which would otherwise silently return (and enrol these
  -- writes into) an already active change set.
  v_guard    := strpos(v_apply_def,'REIMPORT_CASE_FOREIGN_CHANGE_SET');
  v_begin_cs := strpos(v_apply_def,'public.begin_change_set(');
  IF v_guard = 0 THEN
    RAISE EXCEPTION 'C3_APPLY_FOREIGN_CHANGE_SET_GUARD_MISSING';
  END IF;
  IF v_begin_cs = 0 OR v_guard > v_begin_cs THEN
    RAISE EXCEPTION 'C3_APPLY_FOREIGN_CHANGE_SET_GUARD_TOO_LATE';
  END IF;

  RAISE NOTICE 'OK: Task 6 catalog contract (RPC signatures, volatility, hardening, ACLs, step 4b lock order, timeout/change-set guard order)';
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
  v_foreign_cs bigint;
  v_promo_pa bigint; v_promo_pb bigint; v_promo_rid uuid; v_promo_nid bigint;
  v_promo_bind uuid; v_promo_text text; v_promo_elems jsonb; v_promo_counts jsonb;
  v_promo_auth uuid; v_promo_receipt jsonb; v_promo_batch uuid; v_promo_event jsonb;
  v_promo_sel jsonb;
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
       <> ARRAY['narrative_id','old_sha256','old_text','person_id','privat','rid']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_preview->'bindings'->0) k)
       <> ARRAY['binding_person_id','record_key','status'] THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_ROW_KEYS_DRIFT';
  END IF;
  IF v_preview->'target_narratives'->0->>'old_text' <> 'GAMMEL TEKST 1'
     OR encode(sha256(convert_to(
          v_preview->'target_narratives'->0->>'old_text','UTF8')),'hex')
        <> v_preview->'target_narratives'->0->>'old_sha256' THEN
    RAISE EXCEPTION 'C3_APPLY_PREVIEW_OLD_TEXT_DRIFT';
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
    -- Apply owns its change set (see the foreign-change-set gate below), so
    -- every call site clears app.change_set_id first. This is the caller's
    -- contract, not a workaround.
    PERFORM set_config('app.change_set_id','',true);
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
  -- Foreign change set: apply must own its change set. begin_change_set
  -- RETURNS an already active app.change_set_id rather than opening a new one,
  -- so without this gate a caller that had a change set open would enrol the
  -- whole batch into it -- and Task 7's reversal, which feeds
  -- reimport_case_batch.change_set_id to red_fortryd_change_set, would undo
  -- more than this batch. A REAL foreign change set is opened here, which is
  -- exactly the production hazard.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  v_foreign_cs := public.begin_change_set('t6-fremmed-saet','fremmed change set',NULL,NULL);
  IF coalesce(current_setting('app.change_set_id',true),'') <> v_foreign_cs::text THEN
    RAISE EXCEPTION 'C3_APPLY_FOREIGN_CHANGE_SET_FIXTURE_INVALID';
  END IF;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_FOREIGN_CHANGE_SET_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_FOREIGN_CHANGE_SET' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM private.reimport_case_batch) <> v_batch_before
     OR (SELECT count(*) FROM private.reimport_case_event) <> v_ev_before
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_auth) <> 'issued'
     OR EXISTS (SELECT 1 FROM public.change_event WHERE change_set_id=v_foreign_cs) THEN
    RAISE EXCEPTION 'C3_APPLY_PARTIAL_STATE_AFTER_FOREIGN_CHANGE_SET';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  RAISE NOTICE 'OK: apply refuses to join a foreign change set (REIMPORT_CASE_FOREIGN_CHANGE_SET)';

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
  -- The successful apply above left ITS change set active in this transaction;
  -- the replay is a fresh caller and must clear it, exactly as a gateway would
  -- by calling apply as the only statement in its own transaction.
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt2 := public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
  EXECUTE 'RESET ROLE';
  IF v_receipt2 <> v_receipt THEN RAISE EXCEPTION 'C3_APPLY_REPLAY_RECEIPT_DRIFT'; END IF;
  IF (SELECT count(*) FROM private.reimport_case_batch WHERE source_id=v_source) <> 1
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_batch) <> 11 THEN
    RAISE EXCEPTION 'C3_APPLY_REPLAY_DUPLICATED';
  END IF;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('9',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_REPLAY_MANIFEST_DRIFT';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
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

  ---------------------------------------------------------------------------
  -- The draft_same_record PROMOTE branch. Task 3's shipped finalizer allows
  -- exactly two before-states for an assign record
  -- (_ASSIGN_ALLOWED_BINDING_STATUSES = {absent, draft_same_record}), so a
  -- manifest that passes every offline gate CAN reach the promote branch --
  -- it is production-reachable and must be proven in both directions.
  --
  -- A second, self-contained one-case batch (1 identity + 1 assign = 2
  -- elements) is used rather than a sixth case in the fixture above, so none of
  -- the already-approved five-case assertions move.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  v_promo_pa := (SELECT coalesce(max(id),0)+1 FROM public.person);
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
    VALUES (v_promo_pa,false,false,false,'Task 6 promote-target');
  v_promo_pb := (SELECT coalesce(max(id),0)+1 FROM public.person);
  INSERT INTO public.person(id,levende,privat,staged,visning_navn)
    VALUES (v_promo_pb,false,false,false,'Task 6 promote-partner');

  v_promo_rid := gen_random_uuid();
  INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
    VALUES (v_promo_rid,v_source,'t6-record-promote','person_entry',v_run);
  v_occ := gen_random_uuid();
  INSERT INTO private.source_record_occurrence(
    id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
    verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
    VALUES (v_occ,v_rend,'t6-occ-promote',777,777,7700,7750,
            'RAA OCR PROMOTE','pf-promote','sf-promote',v_run);
  INSERT INTO private.source_record_anchor_event(
    occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
    VALUES (v_occ,v_promo_rid,'accepted','{"k":"v"}'::jsonb,1,v_actor,'tester');

  v_promo_nid := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
    VALUES (v_promo_nid,'person',v_promo_pa,v_source,'GAMMEL PROMOTE TEKST','777',false);

  -- The pre-existing DRAFT binding: same record, same target narrative, and the
  -- exact labels the manifest names.
  INSERT INTO private.narrative_record_publication(
    narrative_id,source_record_id,record_label,citation_label,status)
  VALUES (v_promo_nid,v_promo_rid,'t6-record-promote','DAA 1939 side 777','draft')
  RETURNING id INTO v_promo_bind;
  IF private.reimport_case_binding_state(v_promo_rid,v_promo_nid)->>'status'
       <> 'draft_same_record' THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_FIXTURE_INVALID';
  END IF;

  v_promo_text := 'NY NORMALISERET PROMOTE TEKST';
  v_state := private.reimport_case_source_record_state(v_source,'t6-record-promote');
  v_nstate := private.reimport_case_narrative_state(v_source,v_promo_pa);
  v_promo_elems :=
    jsonb_build_object('case:T6PROMO', jsonb_build_object(
      'case_id','T6PROMO','action','different',
      'person_ids',jsonb_build_array(v_promo_pa,v_promo_pb),
      'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',false)))
    || jsonb_build_object('case:T6PROMO:rid:T6R07', jsonb_build_object(
      'case_id','T6PROMO','rid','T6R07','record_key','t6-record-promote','action','assign',
      'target_person_id',v_promo_pa,'target_narrative_id',v_promo_nid,
      'normalized_text',v_promo_text,
      'normalized_sha256',encode(sha256(convert_to(v_promo_text,'UTF8')),'hex'),
      'record_label','t6-record-promote','citation_label','DAA 1939 side 777',
      'side','777','privat',false,
      'before_state',jsonb_build_object(
        'source_record',jsonb_build_object('match_count',1,
          'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
        'target_narrative',jsonb_build_object('person_id',v_promo_pa,
          'narrative_id',v_promo_nid,'privat',false,'old_sha256',v_nstate->'old_sha256'),
        'binding',jsonb_build_object('status','draft_same_record',
          'binding_person_id',v_promo_pa))));
  v_promo_counts := jsonb_build_object('cases',1,'identity_events',1,'assign_events',1,
    'no_publication_events',0,'events',2,'approvals_approved',1,'approvals_unresolved',0);

  -- Fund H1: preview is the ONLY state oracle, so the before-state this element
  -- map hard-codes must be the one preview would actually publish -- otherwise
  -- the promote branch would be apply-reachable but never reachable through the
  -- real pipeline. Preview re-derives the target narrative from the selection's
  -- target_person_id and passes it to reimport_case_binding_state, so it can and
  -- must distinguish draft_same_record from draft_other_record here.
  v_promo_sel := jsonb_build_object('schema_version','1939-v50-c3-apply-selection-v1',
    'cases', jsonb_build_array(jsonb_build_object(
      'case_id','T6PROMO',
      'identity_pair',jsonb_build_object('person_ids',jsonb_build_array(v_promo_pa,v_promo_pb)),
      'records',jsonb_build_array(jsonb_build_object(
        'rid','T6R07','record_key','t6-record-promote','action','assign',
        'target_person_id',v_promo_pa,
        'raw_sha256',v_state->>'verbatim_sha256',
        'normalized_sha256',encode(sha256(convert_to(v_promo_text,'UTF8')),'hex'))))));
  v_preview := public.red_preview_reimport_cases(v_source,'c3',v_promo_sel);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_preview->'bindings') b
                  WHERE b->>'record_key'='t6-record-promote'
                    AND b->>'status'='draft_same_record'
                    AND (b->>'binding_person_id')::bigint = v_promo_pa) THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_PREVIEW_STATUS_DRIFT';
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v_promo_auth := public.red_authorize_reimport_cases(
    v_source,'c3','apply',repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),
    repeat('e',64),repeat('f',64),current_database(),
    (pg_control_system()).system_identifier::text, v_promo_counts, v_promo_elems,
    gen_random_uuid(), clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';

  -- Negative twin FIRST: the same existing draft, but its label no longer
  -- matches the manifest. Label drift is only detectable in the write loop
  -- (the binding STATUS still measures as draft_same_record), i.e. after the
  -- identity relation and the narrative rewrite have already been written --
  -- so this also re-proves all-or-nothing on the promote path.
  BEGIN
    UPDATE private.narrative_record_publication
       SET record_label='FORKERT ETIKET' WHERE id=v_promo_bind;
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_promo_auth,repeat('a',64),repeat('c',64));
    RAISE EXCEPTION 'EXPECTED_PROMOTE_LABEL_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_BINDING_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT status FROM private.narrative_record_publication WHERE id=v_promo_bind) <> 'draft'
     OR (SELECT record_label FROM private.narrative_record_publication WHERE id=v_promo_bind)
        <> 't6-record-promote'
     OR (SELECT tekst FROM public.narrative WHERE id=v_promo_nid) <> 'GAMMEL PROMOTE TEKST'
     OR EXISTS (SELECT 1 FROM public.relation r
                 WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person'
                   AND r.subjekt_id=v_promo_pa AND r.objekt_id=v_promo_pb)
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_promo_auth) <> 'issued'
     OR (SELECT count(*) FROM private.reimport_case_batch WHERE source_id=v_source) <> 1 THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_LABEL_DRIFT_PARTIAL_STATE';
  END IF;

  -- Positive: the untouched draft is PROMOTED in place.
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_promo_receipt := public.red_apply_reimport_cases(v_promo_auth,repeat('a',64),repeat('c',64));
  EXECUTE 'RESET ROLE';
  v_promo_batch := (v_promo_receipt->>'batch_id')::uuid;
  IF v_promo_receipt->>'status' <> 'finalized'
     OR jsonb_array_length(v_promo_receipt->'elements') <> 2
     OR (v_promo_receipt->'observed_counts'->>'events')::int <> 2
     OR (v_promo_receipt->'observed_counts'->>'identity_events')::int <> 1
     OR (v_promo_receipt->'observed_counts'->>'assign_events')::int <> 1
     OR (v_promo_receipt->'observed_counts'->>'no_publication_events')::int <> 0 THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_RECEIPT_DRIFT';
  END IF;
  -- Promotion, not delete+insert: the SAME binding row id survives, now
  -- published, with its labels intact and still the record's only binding.
  -- NOT EXISTS, not a scalar comparison: a delete+insert would make every
  -- scalar read NULL and let a three-valued IF fall through.
  IF (SELECT count(*) FROM private.narrative_record_publication
       WHERE source_record_id=v_promo_rid) <> 1
     OR NOT EXISTS (SELECT 1 FROM private.narrative_record_publication
                     WHERE id=v_promo_bind AND status='published'
                       AND narrative_id=v_promo_nid
                       AND record_label='t6-record-promote'
                       AND citation_label='DAA 1939 side 777') THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_BINDING_AFTER_STATE_DRIFT';
  END IF;
  IF (SELECT tekst FROM public.narrative WHERE id=v_promo_nid) <> v_promo_text
     OR NOT EXISTS (SELECT 1 FROM public.relation r
                     WHERE r.rolle='ikke_samme_som' AND r.subjekt_type='person'
                       AND r.subjekt_id=v_promo_pa AND r.objekt_id=v_promo_pb) THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_DOMAIN_AFTER_STATE_DRIFT';
  END IF;
  -- The C3 event records WHICH branch ran, so Task 7's reversal can tell a
  -- promoted pre-existing draft from a binding this batch created.
  SELECT e.payload->'result' INTO v_promo_event
    FROM private.reimport_case_event e
   WHERE e.batch_id=v_promo_batch AND e.action='record_assign';
  IF v_promo_event->>'binding_before_kind' <> 'draft_same_record'
     OR v_promo_event->>'binding_status' <> 'published'
     OR v_promo_event->>'binding_id' <> v_promo_bind::text
     OR (v_promo_event->>'narrative_id')::bigint <> v_promo_nid THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_EVENT_DRIFT';
  END IF;
  -- The five-case batch is untouched by this second batch.
  IF (SELECT count(*) FROM private.reimport_case_batch WHERE source_id=v_source) <> 2
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_batch) <> 11 THEN
    RAISE EXCEPTION 'C3_APPLY_PROMOTE_BATCH_SCOPE_DRIFT';
  END IF;
  RAISE NOTICE 'OK: draft_same_record promote branch -- preview reports it, in-place promotion, binding_before_kind recorded, label drift is terminal';

  RAISE EXCEPTION 'ROLLBACK_TEST_1939_V50_C3_APPLY_TASK6';
EXCEPTION WHEN others THEN
  IF SQLERRM = 'ROLLBACK_TEST_1939_V50_C3_APPLY_TASK6' THEN
    RAISE NOTICE 'OK: C3 apply Task 6 testdata rullet tilbage';
  ELSE
    RAISE;
  END IF;
END $t6$;

ROLLBACK;

-- ============================================================================
-- Task 7: public.red_authorize_reimport_case_reversal /
-- public.red_reverse_reimport_cases -- exact-after reversal of an applied batch.
--
-- Catalog contract first: signatures, volatility, hardening, ACL split, the
-- shared lock prefix (same advisory key as apply, timeouts before it), and the
-- structural proof that every CAS runs before the first mutation -- the one
-- claim a single-session behavioural test cannot make, because a failed call's
-- own sub-transaction rollback would erase the evidence either way.
-- ============================================================================

BEGIN;

DO $t7_catalog$
DECLARE v_def text;
        v_lock_timeout int; v_stmt_timeout int; v_writer_lock int; v_guard int;
        v_cas int; v_first_write int; v_fortryd int; v_bindings int;
BEGIN
  IF to_regprocedure('public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)') IS NULL
     OR to_regprocedure('public.red_reverse_reimport_cases(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPCS_MISSING';
  END IF;
  IF to_regprocedure('private.reimport_case_reversal_plan(uuid)') IS NULL THEN
    RAISE EXCEPTION 'C3_REVERSAL_PLAN_HELPER_MISSING';
  END IF;

  -- The plan oracle is read-only; both writers are volatile.
  IF (SELECT provolatile FROM pg_proc
       WHERE oid='private.reimport_case_reversal_plan(uuid)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION 'C3_REVERSAL_PLAN_NOT_STABLE';
  END IF;
  IF (SELECT provolatile FROM pg_proc
       WHERE oid='public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure) <> 'v' THEN
    RAISE EXCEPTION 'C3_REVERSAL_NOT_VOLATILE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid IN (
      'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)'::regprocedure,
      'public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure,
      'private.reimport_case_reversal_plan(uuid)'::regprocedure)
      AND (NOT p.prosecdef
           OR NOT ('search_path=pg_catalog, public, private' = ANY(coalesce(p.proconfig,'{}'))))
  ) THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPC_HARDENING_MISSING';
  END IF;

  -- Same principal split as apply: service_role authorises, authenticated
  -- reverses, anon gets nothing, and the plan oracle is revoked from all three.
  IF has_function_privilege('anon','public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('anon','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)','EXECUTE')
     OR has_function_privilege('service_role','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPC_ACL_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
    WHERE has_function_privilege(role_name,'private.reimport_case_reversal_plan(uuid)','EXECUTE')
  ) THEN
    RAISE EXCEPTION 'C3_REVERSAL_PLAN_ACL_DRIFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    WHERE p.oid IN (
      'public.red_authorize_reimport_case_reversal(uuid,text,uuid,timestamptz)'::regprocedure,
      'public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure,
      'private.reimport_case_reversal_plan(uuid)'::regprocedure)
      AND acl.grantee=0
  ) THEN
    RAISE EXCEPTION 'C3_REVERSAL_RPC_PUBLIC_GRANT_PRESENT';
  END IF;

  v_def := pg_get_functiondef('public.red_reverse_reimport_cases(uuid,uuid)'::regprocedure);

  -- Same lock prefix as apply: timeouts before the writer lock, the SAME
  -- advisory key, and the foreign-change-set guard before any of it.
  v_lock_timeout := strpos(v_def,'set_config(''lock_timeout''');
  v_stmt_timeout := strpos(v_def,'set_config(''statement_timeout''');
  v_writer_lock  := strpos(v_def,'hashtextextended(''daa-1939-v50-production-writer'',0)');
  v_guard        := strpos(v_def,'REIMPORT_CASE_FOREIGN_CHANGE_SET');
  IF v_lock_timeout = 0 OR v_stmt_timeout = 0 OR v_writer_lock = 0 OR v_guard = 0 THEN
    RAISE EXCEPTION 'C3_REVERSAL_LOCK_PREFIX_MISSING';
  END IF;
  IF v_lock_timeout > v_writer_lock OR v_stmt_timeout > v_writer_lock
     OR v_guard > v_writer_lock THEN
    RAISE EXCEPTION 'C3_REVERSAL_LOCK_PREFIX_ORDER_WRONG';
  END IF;
  IF strpos(v_def,'hashtext(''samme_som_mutation'')') = 0
     OR strpos(v_def,'private.lock_identity_people') = 0 THEN
    RAISE EXCEPTION 'C3_REVERSAL_IDENTITY_LOCKS_MISSING';
  END IF;
  IF strpos(v_def,'hashtext(''samme_som_mutation'')') < v_writer_lock
     OR strpos(v_def,'private.lock_identity_people')
        < strpos(v_def,'hashtext(''samme_som_mutation'')') THEN
    RAISE EXCEPTION 'C3_REVERSAL_LOCK_ORDER_WRONG';
  END IF;

  -- Every CAS runs before the first mutation, and the binding restore runs
  -- before the change-set undo (narrative_record_publication.narrative_id is a
  -- plain FK: a batch-created narrative cannot be removed under a live binding).
  v_cas         := strpos(v_def,'reversal CAS: everything is proven BEFORE the first mutation');
  v_first_write := strpos(v_def,'INSERT INTO private.reimport_case_batch(');
  v_bindings    := strpos(v_def,'DELETE FROM private.narrative_record_publication');
  v_fortryd     := strpos(v_def,'public.red_fortryd_change_set(');
  IF v_cas = 0 OR v_first_write = 0 OR v_bindings = 0 OR v_fortryd = 0 THEN
    RAISE EXCEPTION 'C3_REVERSAL_STRUCTURE_MISSING';
  END IF;
  IF v_cas > v_first_write OR v_bindings > v_fortryd THEN
    RAISE EXCEPTION 'C3_REVERSAL_MUTATION_ORDER_WRONG';
  END IF;
  -- The phase offers no force bypass: the undo is always non-force.
  IF strpos(v_def,'red_fortryd_change_set(v_change_set,false)') = 0
     OR strpos(v_def,'red_fortryd_change_set(v_change_set,true)') <> 0 THEN
    RAISE EXCEPTION 'C3_REVERSAL_FORCE_BYPASS_PRESENT';
  END IF;

  -- The lock order is TEN steps, not eight: Task 6's fix round inserted step 0
  -- (timeouts + change-set guard) and step 2.5 (the authorization row). Both
  -- functions must name all ten, in ascending order, in their own bodies -- the
  -- machine-checkable half of the same correction made to the section banners
  -- in schema.sql and db-migrations.sql.
  IF EXISTS (
    SELECT 1
      FROM unnest(ARRAY[
        'public.red_apply_reimport_cases(uuid,text,text)',
        'public.red_reverse_reimport_cases(uuid,uuid)']) fn
      CROSS JOIN LATERAL (SELECT pg_get_functiondef(fn::regprocedure) AS def) d
      CROSS JOIN LATERAL unnest(ARRAY['lock order step 0:','lock order step 1:',
        'lock order step 2:','lock order step 2.5:','lock order step 3:',
        'lock order step 4:','lock order step 5:','lock order step 6:',
        'lock order step 7:','lock order step 8:']) WITH ORDINALITY AS m(marker,ord)
     WHERE strpos(d.def,m.marker) = 0
  ) THEN
    RAISE EXCEPTION 'C3_LOCK_ORDER_STEPS_INCOMPLETE';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM unnest(ARRAY[
        'public.red_apply_reimport_cases(uuid,text,text)',
        'public.red_reverse_reimport_cases(uuid,uuid)']) fn
      CROSS JOIN LATERAL (SELECT pg_get_functiondef(fn::regprocedure) AS def) d
      CROSS JOIN LATERAL unnest(ARRAY['lock order step 0:','lock order step 1:',
        'lock order step 2:','lock order step 2.5:','lock order step 3:',
        'lock order step 4:','lock order step 5:','lock order step 6:',
        'lock order step 7:','lock order step 8:']) WITH ORDINALITY AS m(marker,ord)
      CROSS JOIN LATERAL unnest(ARRAY['lock order step 0:','lock order step 1:',
        'lock order step 2:','lock order step 2.5:','lock order step 3:',
        'lock order step 4:','lock order step 5:','lock order step 6:',
        'lock order step 7:','lock order step 8:']) WITH ORDINALITY AS n(marker2,ord2)
     WHERE n.ord2 = m.ord + 1
       AND strpos(d.def,m.marker) > strpos(d.def,n.marker2)
  ) THEN
    RAISE EXCEPTION 'C3_LOCK_ORDER_STEPS_OUT_OF_ORDER';
  END IF;

  RAISE NOTICE 'OK: Task 7 catalog contract (reversal RPC signatures, hardening, ACLs, shared lock prefix, CAS-before-mutation order)';
END $t7_catalog$;

ROLLBACK;

-- ============================================================================
-- Task 7 roundtrip: apply -> reverse restores the EXACT before-state.
--
-- The fixture deliberately covers all four combinations the reversal has to
-- tell apart in one batch:
--   case 1: identity CREATED   + narrative created from nothing + binding ABSENT
--   case 2: identity REUSED    + existing narrative rewritten   + existing DRAFT binding
--   plus one no_publication record (no domain mutation at all).
-- Only append-only history (change_set/change_event, the reimport_case_* ledger)
-- may survive the roundtrip; every domain row must be byte-identical again.
-- ============================================================================

BEGIN;

DO $t7_roundtrip$
DECLARE
  v_actor uuid := '00000000-0000-4c37-8000-000000000001';
  v_source bigint; v_run uuid; v_rend uuid;
  v_p bigint[]:='{}'; v_rec uuid[]:='{}'; v_nid bigint; v_narr bigint[]:='{}';
  i int; v_pid bigint; v_rid uuid; v_occ uuid; v_page int;
  v_elems jsonb:='{}'::jsonb; v_counts jsonb; v_auth uuid; v_receipt jsonb;
  v_state jsonb; v_nstate jsonb; v_text text; v_side text;
  v_snap_before jsonb; v_snap_after jsonb; v_skip text[];
  v_batch uuid; v_cs bigint; v_reused_rel bigint; v_draft_bind uuid;
  v_rev_auth uuid; v_rev_receipt jsonb; v_rev_receipt2 jsonb; v_rev_batch uuid;
  v_plan jsonb; v_receipt_sha text; v_nonce uuid := gen_random_uuid();
  v_created_rel bigint; v_new_narr bigint;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM set_config('request.jwt.claim.sub', v_actor::text, true);
  INSERT INTO auth.users(id,email) VALUES (v_actor,'c3-task7@test.local') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','c3-task7@test.local')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';

  v_source := (SELECT coalesce(max(id),0)+1 FROM public.source);
  INSERT INTO public.source(id,slags,titel,udgave,aar)
    VALUES (v_source,'DAA-udgave','DAA 1939 (Task 7 fixture)','1939',1939);
  v_run := gen_random_uuid();
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,v_source,'c3-task7','1','t','t',repeat('a',64),'{}');
  v_rend := gen_random_uuid();
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256)
    VALUES (v_rend,v_source,'c3-task7-rend','ocr_text',repeat('b',64));

  FOR i IN 1..4 LOOP
    v_pid := (SELECT coalesce(max(id),0)+1 FROM public.person);
    INSERT INTO public.person(id,levende,privat,staged,visning_navn)
      VALUES (v_pid,false,false,false,'Task 7 testperson '||i);
    v_p := v_p || v_pid;
  END LOOP;
  FOR i IN 1..3 LOOP
    v_page := 700+i; v_rid := gen_random_uuid();
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES (v_rid,v_source,'t7-record-'||i,'person_entry',v_run);
    v_occ := gen_random_uuid();
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES (v_occ,v_rend,'t7-occ-'||i,v_page,v_page,i*100,i*100+50,
              'RAA OCR '||i,'pf-'||i,'sf-'||i,v_run);
    INSERT INTO private.source_record_anchor_event(
      occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
      VALUES (v_occ,v_rid,'accepted','{"k":"v"}'::jsonb,1,v_actor,'tester');
    v_rec := v_rec || v_rid;
  END LOOP;

  -- Case 2 pre-state: an existing narrative, an existing DRAFT binding to its
  -- own record, and an ALREADY REJECTED identity pair (the reused path).
  v_nid := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
    VALUES (v_nid,'person',v_p[3],v_source,'GAMMEL TEKST 2','702',false);
  v_narr := v_narr || v_nid;
  INSERT INTO private.narrative_record_publication(
    narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_nid,v_rec[2],'t7-record-2','DAA 1939 side 702','draft')
    RETURNING id INTO v_draft_bind;
  PERFORM set_config('app.change_set_id','',true);
  v_reused_rel := public.red_ikke_samme_som(v_p[3],v_p[4]);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  IF private.reimport_case_binding_state(v_rec[2],v_nid)->>'status' <> 'draft_same_record' THEN
    RAISE EXCEPTION 'C3_REVERSAL_FIXTURE_DRAFT_BINDING_INVALID';
  END IF;

  ---------------------------------------------------------------------------
  -- Snapshot the exact domain rows the batch may touch.
  -- person.visning_* are excluded through the version registry's OWN skip_cols
  -- (invariant 4: a one-way projection, never restored as data), so the
  -- snapshot can never drift from what the ledger actually versions.
  ---------------------------------------------------------------------------
  SELECT coalesce(skip_cols,'{}') INTO v_skip FROM version_pk_registry WHERE tabel='person';
  IF v_skip = '{}' THEN RAISE EXCEPTION 'C3_REVERSAL_FIXTURE_SKIP_COLS_MISSING'; END IF;
  v_snap_before := jsonb_build_object(
    'person',(SELECT jsonb_agg(to_jsonb(p)-v_skip ORDER BY p.id) FROM public.person p WHERE p.id=ANY(v_p)),
    'narrative',(SELECT jsonb_agg(to_jsonb(n) ORDER BY n.id) FROM public.narrative n WHERE n.subjekt_id=ANY(v_p)),
    'relation',(SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM public.relation r
                 WHERE r.subjekt_id=ANY(v_p) OR r.objekt_id=ANY(v_p)),
    'assertion',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.assertion a WHERE a.target_type='relation'),
    'conclusion',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.conclusion c WHERE c.target_type='relation'),
    'binding',(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM private.narrative_record_publication b
                WHERE b.source_record_id=ANY(v_rec)));

  ---------------------------------------------------------------------------
  -- Element map: case 1 (created identity, new narrative, absent binding),
  -- case 2 (reused identity, existing narrative, draft binding) + no_publication.
  ---------------------------------------------------------------------------
  v_text := 'NY TEKST 1'; v_side := '701';
  v_state := private.reimport_case_source_record_state(v_source,'t7-record-1');
  v_nstate := private.reimport_case_narrative_state(v_source,v_p[1]);
  v_elems := v_elems || jsonb_build_object('case:T7C1', jsonb_build_object(
    'case_id','T7C1','action','different',
    'person_ids',jsonb_build_array(least(v_p[1],v_p[2]),greatest(v_p[1],v_p[2])),
    'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',false)));
  v_elems := v_elems || jsonb_build_object('case:T7C1:rid:T7R1', jsonb_build_object(
    'case_id','T7C1','rid','T7R1','record_key','t7-record-1','action','assign',
    'target_person_id',v_p[1],'target_narrative_id',v_nstate->'narrative_id',
    'normalized_text',v_text,'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'record_label','t7-record-1','citation_label','DAA 1939 side '||v_side,
    'side',v_side,'privat',false,
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'target_narrative',jsonb_build_object('person_id',v_p[1],
        'narrative_id',v_nstate->'narrative_id','privat',false,'old_sha256',v_nstate->'old_sha256'),
      'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));

  v_text := 'NY TEKST 2'; v_side := '702';
  v_state := private.reimport_case_source_record_state(v_source,'t7-record-2');
  v_nstate := private.reimport_case_narrative_state(v_source,v_p[3]);
  v_elems := v_elems || jsonb_build_object('case:T7C2', jsonb_build_object(
    'case_id','T7C2','action','different',
    'person_ids',jsonb_build_array(least(v_p[3],v_p[4]),greatest(v_p[3],v_p[4])),
    'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',true)));
  v_elems := v_elems || jsonb_build_object('case:T7C2:rid:T7R2', jsonb_build_object(
    'case_id','T7C2','rid','T7R2','record_key','t7-record-2','action','assign',
    'target_person_id',v_p[3],'target_narrative_id',v_nstate->'narrative_id',
    'normalized_text',v_text,'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'record_label','t7-record-2','citation_label','DAA 1939 side 702',
    'side',v_side,'privat',false,
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'target_narrative',jsonb_build_object('person_id',v_p[3],
        'narrative_id',v_nstate->'narrative_id','privat',false,'old_sha256',v_nstate->'old_sha256'),
      'binding',jsonb_build_object('status','draft_same_record','binding_person_id',v_p[3]))));

  v_state := private.reimport_case_source_record_state(v_source,'t7-record-3');
  v_elems := v_elems || jsonb_build_object('case:T7C2:rid:T7R3', jsonb_build_object(
    'case_id','T7C2','rid','T7R3','record_key','t7-record-3','action','no_publication',
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));

  v_counts := jsonb_build_object('cases',2,'identity_events',2,'assign_events',2,
    'no_publication_events',1,'events',5,'approvals_approved',2,'approvals_unresolved',0);

  EXECUTE 'SET LOCAL ROLE service_role';
  v_auth := public.red_authorize_reimport_cases(v_source,'c3','apply',
    repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),
    current_database(),(pg_control_system()).system_identifier::text,
    v_counts,v_elems,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';

  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt := public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
  EXECUTE 'RESET ROLE';
  v_batch := (v_receipt->>'batch_id')::uuid;
  v_cs := (v_receipt->>'change_set_id')::bigint;

  -- The fixture really did exercise both identity paths and both binding paths.
  IF (SELECT count(*) FROM private.reimport_case_event
       WHERE batch_id=v_batch AND action='identity_different'
         AND payload->'result'->>'outcome'='created') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_batch AND action='identity_different'
            AND payload->'result'->>'outcome'='reused') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_batch AND action='record_assign'
            AND payload->'result'->>'binding_before_kind'='absent') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_batch AND action='record_assign'
            AND payload->'result'->>'binding_before_kind'='draft_same_record') <> 1 THEN
    RAISE EXCEPTION 'C3_REVERSAL_FIXTURE_MATRIX_INCOMPLETE';
  END IF;
  -- The created relation is in the batch's change set; the reused one is not --
  -- that difference IS the created|reused discriminator the reversal relies on.
  SELECT (payload->'result'->>'relation_id')::bigint INTO v_created_rel
    FROM private.reimport_case_event WHERE batch_id=v_batch
     AND action='identity_different' AND payload->'result'->>'outcome'='created';
  IF NOT EXISTS(SELECT 1 FROM public.change_event
                 WHERE change_set_id=v_cs AND tabel='relation'
                   AND (row_pk->>'id')::bigint=v_created_rel AND op='INSERT')
     OR EXISTS(SELECT 1 FROM public.change_event
                WHERE change_set_id=v_cs AND tabel='relation'
                  AND (row_pk->>'id')::bigint=v_reused_rel) THEN
    RAISE EXCEPTION 'C3_REVERSAL_FIXTURE_CREATED_REUSED_DISCRIMINATOR_INVALID';
  END IF;
  SELECT (payload->'result'->>'narrative_id')::bigint INTO v_new_narr
    FROM private.reimport_case_event WHERE batch_id=v_batch
     AND action='record_assign' AND element_id='case:T7C1:rid:T7R1';
  -- Applied state, before reversal: the draft was promoted in place.
  IF (SELECT status FROM private.narrative_record_publication WHERE id=v_draft_bind) <> 'published'
     OR (SELECT published_at FROM private.narrative_record_publication WHERE id=v_draft_bind) IS NULL THEN
    RAISE EXCEPTION 'C3_REVERSAL_FIXTURE_PROMOTE_INVALID';
  END IF;

  ---------------------------------------------------------------------------
  -- Authorize + reverse
  ---------------------------------------------------------------------------
  v_plan := private.reimport_case_reversal_plan(v_batch);
  v_receipt_sha := private.reimport_1939_canonical_json_sha256(
                     private.reimport_case_receipt(v_batch));
  -- The plan and the receipt are two independent artefacts: the plan must NOT
  -- carry the receipt's hash, or one of the two drift tokens becomes unreachable.
  IF (v_plan ? 'receipt_sha256')
     OR (v_plan->'counts'->>'events')::int <> 5
     OR (v_plan->'counts'->>'identity_created')::int <> 1
     OR (v_plan->'counts'->>'identity_reused')::int <> 1
     OR (v_plan->'counts'->>'bindings_deleted')::int <> 1
     OR (v_plan->'counts'->>'bindings_restored')::int <> 1
     OR (v_plan->'counts'->>'narratives_deleted')::int <> 1
     OR (v_plan->'counts'->>'narratives_restored')::int <> 1 THEN
    RAISE EXCEPTION 'C3_REVERSAL_PLAN_CONTRACT_DRIFT';
  END IF;

  -- A wrong receipt hash is refused at authorization time.
  BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.red_authorize_reimport_case_reversal(
      v_batch,repeat('e',64),gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_RECEIPT_HASH_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_RECEIPT_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';

  EXECUTE 'SET LOCAL ROLE service_role';
  v_rev_auth := public.red_authorize_reimport_case_reversal(
    v_batch,v_receipt_sha,v_nonce,clock_timestamp()+interval '1 hour');
  -- Same nonce, same payload returns the same authorization (commit-unknown).
  IF public.red_authorize_reimport_case_reversal(
       v_batch,v_receipt_sha,v_nonce,clock_timestamp()+interval '1 hour') <> v_rev_auth THEN
    RAISE EXCEPTION 'C3_REVERSAL_AUTHORIZATION_NOT_IDEMPOTENT';
  END IF;
  EXECUTE 'RESET ROLE';
  IF (SELECT operation FROM private.reimport_case_authorization WHERE id=v_rev_auth) <> 'reversal'
     OR (SELECT manifest_sha256 FROM private.reimport_case_authorization WHERE id=v_rev_auth) <> v_receipt_sha
     OR (SELECT count(*) FROM private.reimport_case_authorization WHERE nonce=v_nonce) <> 1 THEN
    RAISE EXCEPTION 'C3_REVERSAL_AUTHORIZATION_DRIFT';
  END IF;
  -- Role boundary: authenticated may not authorise, service_role may not reverse.
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_authorize_reimport_case_reversal(
      v_batch,v_receipt_sha,gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_AUTHORIZE_ROLE_REJECTION';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
  BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.red_reverse_reimport_cases(v_rev_auth,v_batch);
    RAISE EXCEPTION 'EXPECTED_REVERSE_ROLE_REJECTION';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';

  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_rev_receipt := public.red_reverse_reimport_cases(v_rev_auth,v_batch);
  EXECUTE 'RESET ROLE';
  v_rev_batch := (v_rev_receipt->>'batch_id')::uuid;

  ---------------------------------------------------------------------------
  -- The exact before-state is back
  ---------------------------------------------------------------------------
  v_snap_after := jsonb_build_object(
    'person',(SELECT jsonb_agg(to_jsonb(p)-v_skip ORDER BY p.id) FROM public.person p WHERE p.id=ANY(v_p)),
    'narrative',(SELECT jsonb_agg(to_jsonb(n) ORDER BY n.id) FROM public.narrative n WHERE n.subjekt_id=ANY(v_p)),
    'relation',(SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM public.relation r
                 WHERE r.subjekt_id=ANY(v_p) OR r.objekt_id=ANY(v_p)),
    'assertion',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.assertion a WHERE a.target_type='relation'),
    'conclusion',(SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.conclusion c WHERE c.target_type='relation'),
    'binding',(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM private.narrative_record_publication b
                WHERE b.source_record_id=ANY(v_rec)));
  IF v_snap_before IS DISTINCT FROM v_snap_after THEN
    RAISE EXCEPTION 'C3_REVERSAL_SNAPSHOT_DIFFERS: % vs %', v_snap_before, v_snap_after;
  END IF;
  -- Named, not merely implied by the snapshot: the reused edge is the SAME row,
  -- the created one is gone with its evidence, the created narrative is gone,
  -- the promoted draft is a draft again with published_at cleared.
  IF NOT EXISTS(SELECT 1 FROM public.relation WHERE id=v_reused_rel)
     OR EXISTS(SELECT 1 FROM public.relation WHERE id=v_created_rel)
     OR EXISTS(SELECT 1 FROM public.assertion WHERE target_type='relation' AND target_id=v_created_rel)
     OR EXISTS(SELECT 1 FROM public.conclusion WHERE target_type='relation' AND target_id=v_created_rel)
     OR EXISTS(SELECT 1 FROM public.narrative WHERE id=v_new_narr)
     OR (SELECT status FROM private.narrative_record_publication WHERE id=v_draft_bind) <> 'draft'
     OR (SELECT published_at FROM private.narrative_record_publication WHERE id=v_draft_bind) IS NOT NULL
     OR (SELECT tekst FROM public.narrative WHERE id=v_nid) <> 'GAMMEL TEKST 2' THEN
    RAISE EXCEPTION 'C3_REVERSAL_AFTER_STATE_DRIFT';
  END IF;
  -- The public projection is empty again -- the mirror image of apply's own
  -- fund-H2 assertion.
  IF EXISTS(SELECT 1 FROM public.public_person_bio_source_versions(v_p)
             WHERE provenance_kind='source_record') THEN
    RAISE EXCEPTION 'C3_REVERSAL_PUBLIC_PROJECTION_NOT_EMPTY';
  END IF;

  ---------------------------------------------------------------------------
  -- Ledger: a separate, finalized reversal batch, both sides of fund B5's link
  ---------------------------------------------------------------------------
  IF v_rev_receipt->>'operation' <> 'reversal'
     OR v_rev_receipt->>'status' <> 'finalized'
     OR v_rev_batch = v_batch
     OR jsonb_array_length(v_rev_receipt->'elements') <> 5
     OR (v_rev_receipt->'observed_counts'->>'identity_created')::int <> 1
     OR (v_rev_receipt->'observed_counts'->>'identity_reused')::int <> 1
     OR (v_rev_receipt->'observed_counts'->>'bindings_deleted')::int <> 1
     OR (v_rev_receipt->'observed_counts'->>'bindings_restored')::int <> 1
     OR (v_rev_receipt->'observed_counts'->>'narratives_deleted')::int <> 1
     OR (v_rev_receipt->'observed_counts'->>'narratives_restored')::int <> 1
     OR (v_rev_receipt->'observed_counts'->>'reversed_batch_id') <> v_batch::text THEN
    RAISE EXCEPTION 'C3_REVERSAL_RECEIPT_DRIFT';
  END IF;
  IF v_rev_receipt::text LIKE '%NY TEKST%' OR v_rev_receipt::text LIKE '%GAMMEL TEKST%'
     OR v_rev_receipt::text LIKE '%RAA OCR%' THEN
    RAISE EXCEPTION 'C3_REVERSAL_RECEIPT_LEAKS_PROSE';
  END IF;
  IF (SELECT status FROM private.reimport_case_batch WHERE id=v_batch) <> 'reversed'
     OR (SELECT reversal_batch_id FROM private.reimport_case_batch WHERE id=v_batch) <> v_rev_batch
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_rev_batch) <> 'finalized'
     OR (SELECT operation FROM private.reimport_case_batch WHERE id=v_rev_batch) <> 'reversal'
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_rev_batch) <> 5
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_batch) <> 5
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_rev_auth) <> 'consumed' THEN
    RAISE EXCEPTION 'C3_REVERSAL_LEDGER_DRIFT';
  END IF;
  -- Every reversal event names the event it reverses, and the identity events
  -- record which relation was deleted and which was kept.
  IF (SELECT count(*) FROM private.reimport_case_event
       WHERE batch_id=v_rev_batch AND payload->>'reversed_batch_id'=v_batch::text) <> 5
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_rev_batch AND action='identity_different'
            AND payload->'result'->>'outcome'='deleted') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_rev_batch AND action='identity_different'
            AND payload->'result'->>'outcome'='kept') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_rev_batch AND action='record_assign'
            AND payload->'result'->>'outcome'='binding_deleted') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event
          WHERE batch_id=v_rev_batch AND action='record_assign'
            AND payload->'result'->>'outcome'='binding_restored') <> 1 THEN
    RAISE EXCEPTION 'C3_REVERSAL_EVENT_DRIFT';
  END IF;
  -- The reversal batch's change set is red_fortryd_change_set's own reversal
  -- set, chained to the applied one. It legitimately carries no child
  -- change_event rows: fortryd clears app.change_set_id before the inverse DML
  -- exactly so the restore is not double-logged.
  IF (SELECT reverterer_id FROM public.change_set
       WHERE id=(v_rev_receipt->>'change_set_id')::bigint) <> v_cs THEN
    RAISE EXCEPTION 'C3_REVERSAL_CHANGE_SET_CHAIN_DRIFT';
  END IF;

  ---------------------------------------------------------------------------
  -- Commit-unknown replay and the double-reversal guard
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_rev_receipt2 := public.red_reverse_reimport_cases(v_rev_auth,v_batch);
  EXECUTE 'RESET ROLE';
  IF v_rev_receipt2 <> v_rev_receipt THEN RAISE EXCEPTION 'C3_REVERSAL_REPLAY_RECEIPT_DRIFT'; END IF;
  IF (SELECT count(*) FROM private.reimport_case_batch WHERE operation='reversal') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_rev_batch) <> 5 THEN
    RAISE EXCEPTION 'C3_REVERSAL_REPLAY_DUPLICATED';
  END IF;
  BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.red_authorize_reimport_case_reversal(
      v_batch,v_receipt_sha,gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_DOUBLE_REVERSAL_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_BATCH_NOT_REVERSIBLE' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';

  ---------------------------------------------------------------------------
  -- The reversal authorization's nonce is STILL a commit-unknown handle after
  -- the reversal has committed (fix round 1, fund 3)
  --
  -- Both derivations the authorization used to run before its nonce lookup are
  -- unusable by now: the plan oracle refuses a batch that is already
  -- 'reversed', and the applied batch's receipt no longer hashes to what the
  -- human approved, because 'status' flips inside the hashed JSON. A caller
  -- that lost its connection on the ORIGINAL authorize call must nevertheless
  -- be able to repeat it with the same nonce and get the same authorization
  -- back -- so the comparison has to be against the STORED manifest_sha256,
  -- never against a fresh re-derivation. The first assertion pins the premise:
  -- the applied receipt hash really has moved.
  ---------------------------------------------------------------------------
  IF private.reimport_1939_canonical_json_sha256(private.reimport_case_receipt(v_batch))
     = v_receipt_sha THEN
    RAISE EXCEPTION 'C3_REVERSAL_APPLIED_RECEIPT_HASH_UNEXPECTEDLY_STABLE';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  IF public.red_authorize_reimport_case_reversal(
       v_batch,v_receipt_sha,v_nonce,clock_timestamp()+interval '1 hour') <> v_rev_auth THEN
    RAISE EXCEPTION 'C3_REVERSAL_AUTHORIZATION_NONCE_REPLAY_BROKEN';
  END IF;
  -- The negative twin: same nonce, a different payload, is still refused.
  BEGIN
    PERFORM public.red_authorize_reimport_case_reversal(
      v_batch,repeat('e',64),v_nonce,clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_NONCE_PAYLOAD_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_NONCE_CONFLICT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM private.reimport_case_authorization WHERE nonce=v_nonce) <> 1 THEN
    RAISE EXCEPTION 'C3_REVERSAL_AUTHORIZATION_NONCE_DUPLICATED';
  END IF;
  -- The recovered handle closes the loop rather than merely returning a uuid:
  -- reversing with it yields the same receipt, byte for byte, and duplicates
  -- nothing.
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_rev_receipt2 := public.red_reverse_reimport_cases(v_rev_auth,v_batch);
  EXECUTE 'RESET ROLE';
  IF v_rev_receipt2 <> v_rev_receipt
     OR (SELECT count(*) FROM private.reimport_case_batch WHERE operation='reversal') <> 1
     OR (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_rev_batch) <> 5 THEN
    RAISE EXCEPTION 'C3_REVERSAL_NONCE_REPLAY_RECEIPT_DRIFT';
  END IF;

  ---------------------------------------------------------------------------
  -- A stale APPLY retry against a reversed batch says exactly that
  -- (fix round 1, fund 1)
  --
  -- Apply's commit-unknown replay requires the batch to be 'finalized'; this
  -- task flips it to 'reversed'. That must not report as the generic
  -- ...AUTHORIZATION_ALREADY_CONSUMED, which the spec routes to manual audit:
  -- "the batch was deliberately reversed" is a known, benign answer, and a
  -- gateway has to be able to tell it apart from genuinely anomalous state.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
    RAISE EXCEPTION 'EXPECTED_REVERSED_BATCH_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_BATCH_REVERSED' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';

  RAISE NOTICE 'OK: apply -> reverse restores the exact before-state (created+reused identity, absent+draft binding, created+rewritten narrative)';
END $t7_roundtrip$;

DO $t7_rollback$
BEGIN
  RAISE NOTICE 'OK: C3 apply Task 7 roundtrip-testdata rullet tilbage';
END $t7_rollback$;

ROLLBACK;

-- ============================================================================
-- Task 7 drift: every reversal attempt against drifted state fails, and the
-- drifted state survives untouched.
--
-- Drift is applied in the OUTER transaction and the failing call is made inside
-- a sub-block, so the assertions after the handler see the drift as it really
-- is -- Task 6's pattern (mutate inside the sub-block) would have rolled the
-- drift back together with the failure and asserted nothing.
--
-- Batch X carries the restorable drifts and is reversed successfully at the end,
-- which is the real proof that no failed attempt leaked a partial mutation.
-- Batch Y carries the three terminal ones (a deleted reused relation, an
-- injected event, an out-of-band undo of the batch's change set) -- none of
-- which can be undone.
-- ============================================================================

BEGIN;

DO $t7_drift$
DECLARE
  v_actor uuid := '00000000-0000-4c37-8000-000000000002';
  v_source bigint; v_run uuid; v_rend uuid;
  v_p bigint[]:='{}'; v_rec uuid[]:='{}';
  i int; v_pid bigint; v_rid uuid; v_occ uuid; v_page int;
  v_state jsonb; v_nstate jsonb; v_text text; v_side text;
  v_elems jsonb; v_counts jsonb; v_auth uuid; v_receipt jsonb;
  v_bx uuid; v_by uuid; v_bz uuid; v_csx bigint; v_csy bigint; v_csz bigint;
  v_authx uuid; v_authy uuid; v_authz uuid; v_shax text; v_shay text; v_shaz text;
  v_nx bigint; v_ny bigint; v_nz bigint; v_bind_x uuid; v_reused_rel bigint;
  v_noncex uuid := gen_random_uuid();
  v_batches bigint; v_rev_batches bigint;
BEGIN
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);
  PERFORM set_config('request.jwt.claim.sub', v_actor::text, true);
  INSERT INTO auth.users(id,email) VALUES (v_actor,'c3-task7-drift@test.local') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_actor,'redaktion','c3-task7-drift@test.local')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';

  v_source := (SELECT coalesce(max(id),0)+1 FROM public.source);
  INSERT INTO public.source(id,slags,titel,udgave,aar)
    VALUES (v_source,'DAA-udgave','DAA 1939 (Task 7 drift)','1939',1939);
  v_run := gen_random_uuid();
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,v_source,'c3-task7-drift','1','t','t',repeat('a',64),'{}');
  v_rend := gen_random_uuid();
  INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256)
    VALUES (v_rend,v_source,'c3-task7-drift-rend','ocr_text',repeat('b',64));
  FOR i IN 1..6 LOOP
    v_pid := (SELECT coalesce(max(id),0)+1 FROM public.person);
    INSERT INTO public.person(id,levende,privat,staged,visning_navn)
      VALUES (v_pid,false,false,false,'Task 7 drift-person '||i);
    v_p := v_p || v_pid;
  END LOOP;
  FOR i IN 1..4 LOOP
    v_page := 800+i; v_rid := gen_random_uuid();
    INSERT INTO private.source_record(id,source_id,record_key,record_kind,created_run_id)
      VALUES (v_rid,v_source,'t7d-record-'||i,'person_entry',v_run);
    v_occ := gen_random_uuid();
    INSERT INTO private.source_record_occurrence(
      id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
      verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
      VALUES (v_occ,v_rend,'t7d-occ-'||i,v_page,v_page,i*100,i*100+50,
              'RAA OCR D'||i,'pfd-'||i,'sfd-'||i,v_run);
    INSERT INTO private.source_record_anchor_event(
      occurrence_id,source_record_id,decision_status,evidence,version,decided_by,decided_by_name)
      VALUES (v_occ,v_rid,'accepted','{"k":"v"}'::jsonb,1,v_actor,'tester');
    v_rec := v_rec || v_rid;
  END LOOP;
  -- Both batches rewrite an EXISTING narrative, so no batch-created narrative
  -- can block the out-of-band undo through the binding FK.
  v_nx := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
    VALUES (v_nx,'person',v_p[1],v_source,'GAMMEL X','801',false);
  v_ny := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
    VALUES (v_ny,'person',v_p[3],v_source,'GAMMEL Y','803',false);
  v_nz := (SELECT coalesce(max(id),0)+1 FROM public.narrative);
  INSERT INTO public.narrative(id,subjekt_type,subjekt_id,source_id,tekst,side,privat)
    VALUES (v_nz,'person',v_p[5],v_source,'GAMMEL Z','804',false);
  PERFORM set_config('app.change_set_id','',true);
  v_reused_rel := public.red_ikke_samme_som(v_p[3],v_p[4]);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('app.change_seq','',true);

  ---------------------------------------------------------------------------
  -- Batch X: created identity + assign (existing narrative, absent binding)
  --          + no_publication
  ---------------------------------------------------------------------------
  v_text := 'NY X'; v_side := '801';
  v_state := private.reimport_case_source_record_state(v_source,'t7d-record-1');
  v_nstate := private.reimport_case_narrative_state(v_source,v_p[1]);
  v_elems := jsonb_build_object('case:T7X', jsonb_build_object(
    'case_id','T7X','action','different',
    'person_ids',jsonb_build_array(least(v_p[1],v_p[2]),greatest(v_p[1],v_p[2])),
    'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',false)))
    || jsonb_build_object('case:T7X:rid:T7RX', jsonb_build_object(
    'case_id','T7X','rid','T7RX','record_key','t7d-record-1','action','assign',
    'target_person_id',v_p[1],'target_narrative_id',v_nstate->'narrative_id',
    'normalized_text',v_text,'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'record_label','t7d-record-1','citation_label','DAA 1939 side 801',
    'side',v_side,'privat',false,
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'target_narrative',jsonb_build_object('person_id',v_p[1],
        'narrative_id',v_nstate->'narrative_id','privat',false,'old_sha256',v_nstate->'old_sha256'),
      'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));
  v_state := private.reimport_case_source_record_state(v_source,'t7d-record-2');
  v_elems := v_elems || jsonb_build_object('case:T7X:rid:T7RXN', jsonb_build_object(
    'case_id','T7X','rid','T7RXN','record_key','t7d-record-2','action','no_publication',
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));
  v_counts := jsonb_build_object('cases',1,'identity_events',1,'assign_events',1,
    'no_publication_events',1,'events',3,'approvals_approved',1,'approvals_unresolved',0);
  EXECUTE 'SET LOCAL ROLE service_role';
  v_auth := public.red_authorize_reimport_cases(v_source,'c3','apply',
    repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),
    current_database(),(pg_control_system()).system_identifier::text,
    v_counts,v_elems,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt := public.red_apply_reimport_cases(v_auth,repeat('1',64),repeat('3',64));
  EXECUTE 'RESET ROLE';
  v_bx := (v_receipt->>'batch_id')::uuid; v_csx := (v_receipt->>'change_set_id')::bigint;
  SELECT (payload->'result'->>'binding_id')::uuid INTO v_bind_x
    FROM private.reimport_case_event WHERE batch_id=v_bx AND action='record_assign';

  ---------------------------------------------------------------------------
  -- Batch Y: reused identity + assign (existing narrative, absent binding)
  ---------------------------------------------------------------------------
  v_text := 'NY Y'; v_side := '803';
  v_state := private.reimport_case_source_record_state(v_source,'t7d-record-3');
  v_nstate := private.reimport_case_narrative_state(v_source,v_p[3]);
  v_elems := jsonb_build_object('case:T7Y', jsonb_build_object(
    'case_id','T7Y','action','different',
    'person_ids',jsonb_build_array(least(v_p[3],v_p[4]),greatest(v_p[3],v_p[4])),
    'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',true)))
    || jsonb_build_object('case:T7Y:rid:T7RY', jsonb_build_object(
    'case_id','T7Y','rid','T7RY','record_key','t7d-record-3','action','assign',
    'target_person_id',v_p[3],'target_narrative_id',v_nstate->'narrative_id',
    'normalized_text',v_text,'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'record_label','t7d-record-3','citation_label','DAA 1939 side 803',
    'side',v_side,'privat',false,
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'target_narrative',jsonb_build_object('person_id',v_p[3],
        'narrative_id',v_nstate->'narrative_id','privat',false,'old_sha256',v_nstate->'old_sha256'),
      'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));
  v_counts := jsonb_build_object('cases',1,'identity_events',1,'assign_events',1,
    'no_publication_events',0,'events',2,'approvals_approved',1,'approvals_unresolved',0);
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE service_role';
  v_auth := public.red_authorize_reimport_cases(v_source,'c3','apply',
    repeat('7',64),repeat('8',64),repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),
    current_database(),(pg_control_system()).system_identifier::text,
    v_counts,v_elems,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt := public.red_apply_reimport_cases(v_auth,repeat('7',64),repeat('3',64));
  EXECUTE 'RESET ROLE';
  v_by := (v_receipt->>'batch_id')::uuid; v_csy := (v_receipt->>'change_set_id')::bigint;

  ---------------------------------------------------------------------------
  -- Batch Z exists only so the out-of-band-undo guard can be proven on a batch
  -- that carries NO other drift. Sharing Y would have let an earlier terminal
  -- drift mask it: with the guard removed the call would still fail, just with
  -- a different token, and the test could not tell the two apart.
  ---------------------------------------------------------------------------
  v_text := 'NY Z'; v_side := '804';
  v_state := private.reimport_case_source_record_state(v_source,'t7d-record-4');
  v_nstate := private.reimport_case_narrative_state(v_source,v_p[5]);
  v_elems := jsonb_build_object('case:T7Z', jsonb_build_object(
    'case_id','T7Z','action','different',
    'person_ids',jsonb_build_array(least(v_p[5],v_p[6]),greatest(v_p[5],v_p[6])),
    'before_state',jsonb_build_object('component_overlap',false,'existing_rejection',false)))
    || jsonb_build_object('case:T7Z:rid:T7RZ', jsonb_build_object(
    'case_id','T7Z','rid','T7RZ','record_key','t7d-record-4','action','assign',
    'target_person_id',v_p[5],'target_narrative_id',v_nstate->'narrative_id',
    'normalized_text',v_text,'normalized_sha256',encode(sha256(convert_to(v_text,'UTF8')),'hex'),
    'record_label','t7d-record-4','citation_label','DAA 1939 side 804',
    'side',v_side,'privat',false,
    'before_state',jsonb_build_object(
      'source_record',jsonb_build_object('match_count',1,
        'verbatim_sha256',v_state->>'verbatim_sha256','side',v_state->>'side'),
      'target_narrative',jsonb_build_object('person_id',v_p[5],
        'narrative_id',v_nstate->'narrative_id','privat',false,'old_sha256',v_nstate->'old_sha256'),
      'binding',jsonb_build_object('status','absent','binding_person_id',NULL))));
  v_counts := jsonb_build_object('cases',1,'identity_events',1,'assign_events',1,
    'no_publication_events',0,'events',2,'approvals_approved',1,'approvals_unresolved',0);
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE service_role';
  v_auth := public.red_authorize_reimport_cases(v_source,'c3','apply',
    repeat('9',64),repeat('0',64),repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),
    current_database(),(pg_control_system()).system_identifier::text,
    v_counts,v_elems,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt := public.red_apply_reimport_cases(v_auth,repeat('9',64),repeat('3',64));
  EXECUTE 'RESET ROLE';
  v_bz := (v_receipt->>'batch_id')::uuid; v_csz := (v_receipt->>'change_set_id')::bigint;

  -- All three reversal authorizations are issued BEFORE any drift: that is what
  -- binds the human's approval to the state as it was measured.
  v_shax := private.reimport_1939_canonical_json_sha256(private.reimport_case_receipt(v_bx));
  v_shay := private.reimport_1939_canonical_json_sha256(private.reimport_case_receipt(v_by));
  v_shaz := private.reimport_1939_canonical_json_sha256(private.reimport_case_receipt(v_bz));
  EXECUTE 'SET LOCAL ROLE service_role';
  v_authx := public.red_authorize_reimport_case_reversal(
    v_bx,v_shax,v_noncex,clock_timestamp()+interval '1 hour');
  v_authy := public.red_authorize_reimport_case_reversal(
    v_by,v_shay,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  v_authz := public.red_authorize_reimport_case_reversal(
    v_bz,v_shaz,gen_random_uuid(),clock_timestamp()+interval '1 hour');
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_batches FROM private.reimport_case_batch;

  ---------------------------------------------------------------------------
  -- Nonce reuse across batches: the same nonce with a DIFFERENT payload is
  -- terminal, exactly as for apply. Without this the nonce would be a name
  -- rather than a commitment.
  ---------------------------------------------------------------------------
  BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.red_authorize_reimport_case_reversal(
      v_by,v_shay,v_noncex,clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_NONCE_CONFLICT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_NONCE_CONFLICT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  -- An authorization may only be spent on the batch it NAMES. The element
  -- lookup deliberately runs BEFORE the consumed-replay short-circuit, so a
  -- token can never be redirected to fetch another batch's receipt.
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authx,v_by);
    RAISE EXCEPTION 'EXPECTED_WRONG_BATCH_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_AUTHORIZATION_INVALID' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM private.reimport_case_batch) <> v_batches
     OR (SELECT count(*) FROM private.reimport_case_authorization WHERE nonce=v_noncex) <> 1
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_authx) <> 'issued'
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_by) <> 'finalized' THEN
    RAISE EXCEPTION 'C3_REVERSAL_TOKEN_MISBINDING_NOT_REJECTED';
  END IF;

  ---------------------------------------------------------------------------
  -- Drift 1 (X): the narrative text moved on since apply
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  UPDATE public.narrative SET tekst='EN ANDEN HAAND HAR SKREVET HER' WHERE id=v_nx;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authx,v_bx);
    RAISE EXCEPTION 'EXPECTED_NARRATIVE_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_REVERSAL_STATE_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT tekst FROM public.narrative WHERE id=v_nx) <> 'EN ANDEN HAAND HAR SKREVET HER'
     OR (SELECT status FROM private.narrative_record_publication WHERE id=v_bind_x) <> 'published'
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_bx) <> 'finalized'
     OR (SELECT reversal_batch_id FROM private.reimport_case_batch WHERE id=v_bx) IS NOT NULL
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_authx) <> 'issued'
     OR (SELECT count(*) FROM private.reimport_case_batch) <> v_batches THEN
    RAISE EXCEPTION 'C3_REVERSAL_DRIFT_NARRATIVE_NOT_PRESERVED';
  END IF;
  UPDATE public.narrative SET tekst='NY X' WHERE id=v_nx;

  ---------------------------------------------------------------------------
  -- Drift 2 (X): the binding was withdrawn behind the batch's back
  ---------------------------------------------------------------------------
  UPDATE private.narrative_record_publication SET status='withdrawn' WHERE id=v_bind_x;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authx,v_bx);
    RAISE EXCEPTION 'EXPECTED_BINDING_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_REVERSAL_BINDING_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT status FROM private.narrative_record_publication WHERE id=v_bind_x) <> 'withdrawn'
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_bx) <> 'finalized'
     OR (SELECT count(*) FROM private.reimport_case_batch) <> v_batches THEN
    RAISE EXCEPTION 'C3_REVERSAL_DRIFT_BINDING_NOT_PRESERVED';
  END IF;
  UPDATE private.narrative_record_publication SET status='published' WHERE id=v_bind_x;

  ---------------------------------------------------------------------------
  -- Drift 3 (X): the receipt the authorization was bound to no longer holds
  ---------------------------------------------------------------------------
  UPDATE private.reimport_case_batch
     SET observed_counts=observed_counts||jsonb_build_object('events',99) WHERE id=v_bx;
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authx,v_bx);
    RAISE EXCEPTION 'EXPECTED_RECEIPT_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_RECEIPT_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT (observed_counts->>'events')::int FROM private.reimport_case_batch WHERE id=v_bx) <> 99
     OR (SELECT count(*) FROM private.reimport_case_batch) <> v_batches THEN
    RAISE EXCEPTION 'C3_REVERSAL_DRIFT_RECEIPT_NOT_PRESERVED';
  END IF;
  UPDATE private.reimport_case_batch
     SET observed_counts=observed_counts||jsonb_build_object('events',3) WHERE id=v_bx;

  ---------------------------------------------------------------------------
  -- X reverses cleanly now: three failed attempts leaked nothing.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_receipt := public.red_reverse_reimport_cases(v_authx,v_bx);
  EXECUTE 'RESET ROLE';
  IF v_receipt->>'status' <> 'finalized'
     OR (v_receipt->'observed_counts'->>'identity_created')::int <> 1
     OR (v_receipt->'observed_counts'->>'bindings_deleted')::int <> 1
     OR (v_receipt->'observed_counts'->>'narratives_restored')::int <> 1
     OR (SELECT tekst FROM public.narrative WHERE id=v_nx) <> 'GAMMEL X'
     OR EXISTS(SELECT 1 FROM private.narrative_record_publication WHERE id=v_bind_x)
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_bx) <> 'reversed' THEN
    RAISE EXCEPTION 'C3_REVERSAL_POST_DRIFT_REVERSAL_DRIFT';
  END IF;
  SELECT count(*) INTO v_batches FROM private.reimport_case_batch;
  SELECT count(*) INTO v_rev_batches FROM private.reimport_case_batch WHERE operation='reversal';

  ---------------------------------------------------------------------------
  -- Drift 4 (Y): the REUSED identity relation was removed out of band.
  -- Terminal: reversal must not invent a replacement for an edge it never made.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_fjern_ikke_samme_som(v_reused_rel);
  PERFORM set_config('app.change_set_id','',true);
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authy,v_by);
    RAISE EXCEPTION 'EXPECTED_IDENTITY_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_REVERSAL_IDENTITY_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF EXISTS(SELECT 1 FROM public.relation WHERE id=v_reused_rel)
     OR (SELECT tekst FROM public.narrative WHERE id=v_ny) <> 'NY Y'
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_by) <> 'finalized'
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_authy) <> 'issued'
     OR (SELECT count(*) FROM private.reimport_case_batch WHERE operation='reversal') <> v_rev_batches THEN
    RAISE EXCEPTION 'C3_REVERSAL_DRIFT_IDENTITY_NOT_PRESERVED';
  END IF;

  ---------------------------------------------------------------------------
  -- Drift 5 (Y): an event was injected into the applied batch after
  -- authorization -- the pinned plan no longer matches.
  ---------------------------------------------------------------------------
  INSERT INTO private.reimport_case_event(
    batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256)
  VALUES (v_by,v_source,'c3','case:INJECTED','record_no_publication','c3-apply-v1',
    '{"case_id":"INJECTED","result":{"binding_status":"absent"}}'::jsonb,repeat('c',64));
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authy,v_by);
    RAISE EXCEPTION 'EXPECTED_PLAN_DRIFT_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_REVERSAL_PLAN_DRIFT' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM private.reimport_case_event WHERE batch_id=v_by) <> 3
     OR (SELECT status FROM private.reimport_case_batch WHERE id=v_by) <> 'finalized'
     OR (SELECT count(*) FROM private.reimport_case_batch WHERE operation='reversal') <> v_rev_batches THEN
    RAISE EXCEPTION 'C3_REVERSAL_DRIFT_PLAN_NOT_PRESERVED';
  END IF;

  ---------------------------------------------------------------------------
  -- Drift 6 (Z, undrifted): a human undid the batch's change set through the
  -- fortryd panel (prod-live today). Reversal must refuse BEFORE it deletes any
  -- binding row, not discover it inside red_fortryd_change_set afterwards --
  -- which is why the guard sits in the shared plan oracle and not in the undo.
  ---------------------------------------------------------------------------
  PERFORM set_config('app.change_set_id','',true);
  PERFORM public.red_fortryd_change_set(v_csz,false);
  PERFORM set_config('app.change_set_id','',true);
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.red_reverse_reimport_cases(v_authz,v_bz);
    RAISE EXCEPTION 'EXPECTED_ALREADY_REVERSED_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_CHANGE_SET_ALREADY_REVERSED' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';
  IF (SELECT status FROM private.reimport_case_batch WHERE id=v_bz) <> 'finalized'
     OR (SELECT reversal_batch_id FROM private.reimport_case_batch WHERE id=v_bz) IS NOT NULL
     OR (SELECT status FROM private.reimport_case_authorization WHERE id=v_authz) <> 'issued'
     OR (SELECT count(*) FROM private.reimport_case_batch WHERE operation='reversal') <> v_rev_batches
     -- the binding the batch created is still there: nothing was mutated
     OR NOT EXISTS(SELECT 1 FROM private.narrative_record_publication
                    WHERE source_record_id=v_rec[4] AND status='published') THEN
    RAISE EXCEPTION 'C3_REVERSAL_DRIFT_ALREADY_REVERSED_NOT_PRESERVED';
  END IF;
  -- The same guard fails a NEW authorization early, so a gateway never gets a
  -- reversal token for a batch whose change set is already gone.
  BEGIN
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.red_authorize_reimport_case_reversal(
      v_bz,v_shaz,gen_random_uuid(),clock_timestamp()+interval '1 hour');
    RAISE EXCEPTION 'EXPECTED_ALREADY_REVERSED_AUTHORIZE_REJECTION';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'REIMPORT_CASE_CHANGE_SET_ALREADY_REVERSED' THEN RAISE; END IF;
  END;
  EXECUTE 'RESET ROLE';

  RAISE NOTICE 'OK: nonce/batch misbinding plus narrative, binding, receipt, identity, event-set and out-of-band-undo drift each fail closed with the drifted state intact';
END $t7_drift$;

DO $t7_drift_rollback$
BEGIN
  RAISE NOTICE 'OK: C3 apply Task 7 drift-testdata rullet tilbage';
END $t7_drift_rollback$;

ROLLBACK;
